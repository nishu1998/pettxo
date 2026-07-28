const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildAcceptedAwaitingPaymentSlotBookingFixture,
  buildRequestedRangeBookingFixture,
} = require("../lib/booking/schema/bookingFixtures.js");
const {
  resolveCanonicalPricingV3,
  validatePreCheckoutAvailabilityV3,
  previewCanonicalPaymentPricingV3,
  finalizeCapturedBookingPaymentV3,
  finalizeCapturedCanonicalPaymentV3,
  persistFinalizePaymentResultV3,
  reconcilePaymentAttemptsV3,
  submitRefundInstructionV3,
} = require("../lib/booking/application/paymentOrchestrationV3.js");
const {Timestamp} = require("firebase-admin/firestore");
const razorpayGateway = require("../lib/booking/application/razorpayGateway.js");
const sharedFirebase = require("../lib/shared/firebase.js");
const {
  buildCanonicalPaymentRaceFixture,
  assertNoPrivateLeakage,
} = require("./helpers/canonicalPaymentRaceFixture.js");

const BOOKING_CHAT_SAFETY_NOTICE =
  "For your protection, keep payments and booking changes inside Pettxo.";
const LEGACY_BOOKING_CHAT_SAFETY_NOTICE =
  "Bookings made outside Pettxo are not covered by OTP verification, dispute protection, or refunds.";

function parentIdentity() {
  return {
    uid: "parent-1",
    displayName: "Nisha Gautam",
    fullName: "Nisha Gautam",
    email: "nisha@example.com",
    phoneNumber: "+919999999999",
  };
}

function providerPrivateIdentity(phoneNumber = "+918888888888") {
  return {
    uid: "provider-1",
    phoneNumber,
  };
}

function liveService() {
  return {
    status: "active",
    isActive: true,
    isDeleted: false,
    isPaused: false,
    isVisibleToMarketplace: true,
    isPausedByVerification: false,
    location: {
      displayAddress: "Andheri West, Mumbai",
      latitude: 19.136,
      longitude: 72.829,
    },
  };
}

function buildFutureAcceptedAwaitingPaymentBookingFixture() {
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  const startAt = new Date("2026-08-02T06:00:00.000Z");
  const endAt = new Date("2026-08-02T07:00:00.000Z");
  const payDeadlineAt = new Date("2026-08-01T10:30:00.000Z");
  booking.schedule.slots[0].dateKey = "2026-08-02";
  booking.schedule.slots[0].startAt = startAt;
  booking.schedule.slots[0].endAt = endAt;
  booking.schedule.scheduledStartAt = startAt;
  booking.schedule.scheduledEndAt = endAt;
  booking.schedule.serviceAnchorAt = startAt;
  booking.serviceAnchorAt = startAt;
  booking.scheduledStartAt = startAt;
  booking.lifecycle.payDeadlineAt = payDeadlineAt;
  booking.payDeadlineAt = payDeadlineAt;
  return booking;
}

test("previewCanonicalPaymentPricingV3 returns the authoritative pricing summary before order creation", () => {
  const booking = buildFutureAcceptedAwaitingPaymentBookingFixture();

  const preview = previewCanonicalPaymentPricingV3({
    bookingId: "booking-preview-1",
    parentId: booking.parentId,
    service: liveService(),
    booking,
    authoritativeNow: new Date("2026-07-31T10:30:00.000Z"),
  });

  assert.equal(preview.ok, true);
  assert.equal(preview.code, "READY");
  if (!preview.ok) return;

  const resolved = resolveCanonicalPricingV3({booking, claimedOffer: null});
  assert.deepEqual(preview.pricing, resolved);
  assert.equal(
    preview.payDeadlineAt?.toISOString(),
    booking.lifecycle.payDeadlineAt?.toISOString(),
  );
});

test("previewCanonicalPaymentPricingV3 applies valid coupons and supports zero-payable totals", () => {
  const booking = buildFutureAcceptedAwaitingPaymentBookingFixture();
  const claimedOffer = {
    id: "claimed-free",
    claimedOfferId: "claimed-free",
    offerId: "campaign-free",
    couponCode: "FREEWALK",
    discountType: "flat",
    discountValue: 250,
    maxDiscountAmount: null,
    minBookingAmount: 0,
    validUntil: new Date("2026-08-01T00:00:00.000Z"),
    usageLimit: 1,
    usedCount: 0,
    status: "claimed",
    serviceIds: [booking.serviceId],
    providerIds: [booking.providerId],
    categoryRestrictions: [booking.service.category],
    campaignSnapshot: {
      title: "Free walk",
      description: "Makes the booking free.",
      serviceIds: [booking.serviceId],
      providerIds: [booking.providerId],
      categoryRestrictions: [booking.service.category],
    },
  };

  const preview = previewCanonicalPaymentPricingV3({
    bookingId: "booking-preview-2",
    parentId: booking.parentId,
    service: liveService(),
    booking,
    claimedOffer,
    authoritativeNow: new Date("2026-07-31T10:30:00.000Z"),
  });

  assert.equal(preview.ok, true);
  if (!preview.ok) return;

  assert.equal(preview.pricing.serviceSubtotalPaise, 25000);
  assert.equal(preview.pricing.couponDiscountPaise, 25000);
  assert.equal(preview.pricing.customerPaidPaise, 0);
});

function buildAttempt({booking, pricing, paymentAttemptId, razorpayOrderId}) {
  return {
    schemaVersion: 1,
    paymentAttemptId,
    bookingId: booking.parentId === "parent-1" ? `booking-${paymentAttemptId}` : "booking-slot",
    parentId: booking.parentId,
    providerId: booking.providerId,
    requestAttemptId: `request-${paymentAttemptId}`,
    razorpayOrderId,
    razorpayPaymentId: "",
    amountPaise: pricing.financialSnapshot.customerPaidPaise,
    currency: "INR",
    couponId: "",
    couponClaimId: "",
    pricingHash: pricing.pricingHash,
    availabilityHash: `availability-${paymentAttemptId}`,
    state: "ORDER_CREATED",
    orderExpiresAt: booking.lifecycle.payDeadlineAt,
    createdAt: new Date("2026-07-22T10:20:00.000Z"),
    orderCreatedAt: new Date("2026-07-22T10:21:00.000Z"),
    checkoutOpenedAt: new Date("2026-07-22T10:21:30.000Z"),
    captureReportedAt: null,
    captureCreatedAt: null,
    confirmedAt: null,
    failedAt: null,
    refundRequiredAt: null,
    refundedAt: null,
    nextReconciliationAt: null,
    lastReconciledAt: null,
    reconciliationAttemptCount: 0,
    lastReconciliationCode: "",
    terminalFailureAt: null,
    leaseOwner: "",
    leaseExpiresAt: null,
    verificationSource: "",
    failureCode: "",
    failureMessage: "",
    retryCount: 0,
    updatedAt: new Date("2026-07-22T10:21:30.000Z"),
    pricingSnapshot: {financials: pricing.financialSnapshot},
    couponSnapshot: null,
  };
}

function assertConfirmedSideEffectsExactlyOnce(result, {bookingId, paymentAttemptId}) {
  assert.equal(result.ok, true);
  assert.equal(result.booking.state, "CONFIRMED");
  assert.equal(result.paymentAttempt.state, "CONFIRMED");
  assert.equal(result.paymentAttempt.paymentAttemptId, paymentAttemptId);
  assert.equal(result.booking.lifecycle.paidAt instanceof Date, true);
  assert.equal(
    result.booking.payment.paymentAttemptId === "" ||
      result.booking.payment.paymentAttemptId === paymentAttemptId,
    true,
  );
  assert.equal(
    result.booking.payment.razorpayPaymentId === "" ||
      result.booking.payment.razorpayPaymentId.length > 0,
    true,
  );
  assert.equal(result.bookingPrivate.bookingId, bookingId);
  assert.equal(result.bookingPrivate.parentOtpCode.length, 6);
  assert.equal(result.bookingPrivate.contactUnlockedAt instanceof Date, true);
  assert.equal(result.otpCode.length, result.code === "IDEMPOTENT_REPLAY" ? 0 : 6);
  assert.equal(Object.keys(result.occupancyWrites).length > 0 || result.code === "IDEMPOTENT_REPLAY", true);
  assert.equal(result.financialWrites.bookingFinancial.bookingId, bookingId);
  assert.equal(result.financialWrites.payment.bookingId, bookingId);
  assert.equal(result.financialWrites.invoice.invoiceId, bookingId);
  assert.equal(result.financialWrites.providerEarning.bookingId, bookingId);
  assert.equal(result.financialWrites.payoutReadiness.bookingId, bookingId);
  assert.equal(result.financialWrites.bookingChat.bookingId, bookingId);
  assert.equal(result.events.every((event) => event.record.bookingId === bookingId), true);
}

function assertConfirmedSideEffectsAbsent(result) {
  assert.equal("bookingPrivate" in result, false);
  assert.equal("otpCode" in result, false);
  assert.equal("occupancyWrites" in result, false);
  assert.equal("financialWrites" in result, false);
  assert.equal("couponWrite" in result, false);
}

function assertRefundInstructionExactlyOnce(result, {
  bookingId,
  expectedCode,
  expectedReasonCode,
  expectedRefundAmountPaise,
  expectedEvent,
  expectedNotificationType,
}) {
  assert.equal(result.ok, false);
  assert.equal(result.code, expectedCode);
  assert.equal(result.booking.state, "PAYMENT_EXPIRED");
  assert.equal(result.paymentAttempt.state, "REFUND_REQUIRED");
  assert.equal(result.refundInstruction.bookingId, bookingId);
  assert.equal(result.refundInstruction.reasonCode, expectedReasonCode);
  assert.equal(result.refundInstruction.refundAmountPaise, expectedRefundAmountPaise);
  assert.equal(result.booking.lifecycle.paidAt, null);
  assert.equal(result.booking.privacy.isPaidContactUnlocked, false);
  assert.equal(
    result.booking.payment.razorpayPaymentId === "" ||
      result.booking.payment.razorpayPaymentId.length > 0,
    true,
  );
  assert.equal(result.events.every((event) => event.record.event === expectedEvent), true);
  assert.equal(
    result.notifications.every((notification) => notification.type === expectedNotificationType),
    true,
  );
  assertConfirmedSideEffectsAbsent(result);
}

function assertNoPaidUnlocks(firestore, bookingId) {
  for (const path of [
    `bookingPrivate/${bookingId}`,
    `bookingChats/${bookingId}`,
    `chats/${bookingId}`,
    `bookingFinancials/${bookingId}`,
    `payments/${bookingId}`,
    `invoices/${bookingId}`,
    `providerEarnings/${bookingId}`,
    `payoutReadiness/${bookingId}`,
  ]) {
    assert.equal(firestore.store.has(path), false, path);
  }
}

function assertChatCompatibilityExactlyOnce(firestore, bookingId, {
  expectedParticipants,
  expectedProviderId,
}) {
  const bookingChat = firestore.store.get(`bookingChats/${bookingId}`);
  const inboxChat = firestore.store.get(`chats/${bookingId}`);
  assert.ok(bookingChat);
  assert.ok(inboxChat);
  assert.equal(bookingChat.bookingId, bookingId);
  assert.equal(inboxChat.bookingId, bookingId);
  assert.deepEqual(bookingChat.participantIds, expectedParticipants);
  assert.deepEqual(inboxChat.participantIds, expectedParticipants);
  assert.equal(bookingChat.providerId, expectedProviderId);
  assert.equal(inboxChat.providerId, expectedProviderId);
  assert.equal(bookingChat.status, "unlocked");
  assert.equal(inboxChat.status, "unlocked");
  assert.equal(bookingChat.unreadCountCustomer, 0);
  assert.equal(bookingChat.unreadCountProvider, 0);
  assert.equal(inboxChat.unreadCountCustomer, 0);
  assert.equal(inboxChat.unreadCountProvider, 0);
  assert.equal(bookingChat.safetyNotice, BOOKING_CHAT_SAFETY_NOTICE);
  assert.equal(inboxChat.safetyNotice, BOOKING_CHAT_SAFETY_NOTICE);
  assert.notEqual(bookingChat.safetyNotice, LEGACY_BOOKING_CHAT_SAFETY_NOTICE);
  assert.notEqual(inboxChat.safetyNotice, LEGACY_BOOKING_CHAT_SAFETY_NOTICE);
}

class FakeDocSnapshot {
  constructor(firestore, path, data) {
    this.ref = new FakeDocRef(firestore, path);
    this.path = path;
    this.id = path.split("/").pop();
    this._data = data;
  }

  get exists() {
    return this._data !== undefined;
  }

  data() {
    return this._data;
  }
}

class FakeDocRef {
  constructor(firestore, path) {
    this.firestore = firestore;
    this.path = path;
    this.id = path.split("/").pop();
  }

  collection(name) {
    return new FakeCollectionRef(this.firestore, `${this.path}/${name}`);
  }

  get parent() {
    const collectionPath = this.path.split("/").slice(0, -1).join("/");
    return new FakeCollectionRef(this.firestore, collectionPath);
  }

  async get() {
    return new FakeDocSnapshot(this.firestore, this.path, this.firestore.store.get(this.path));
  }

  async set(data, options) {
    this.firestore._set(this.path, data, options);
  }
}

class FakeCollectionRef {
  constructor(firestore, path) {
    this.firestore = firestore;
    this.path = path;
    this.id = path.split("/").pop();
  }

  get parent() {
    const segments = this.path.split("/");
    if (segments.length < 2) return null;
    return new FakeDocRef(this.firestore, segments.slice(0, -1).join("/"));
  }

  doc(id) {
    return new FakeDocRef(this.firestore, `${this.path}/${id}`);
  }
}

class FakeQuery {
  constructor(docs) {
    this.docs = docs;
  }

  where(field, operator, value) {
    const filtered = this.docs.filter((doc) => {
      const fieldValue = doc.data()?.[field];
      if (operator === "in") {
        return Array.isArray(value) && value.includes(fieldValue);
      }
      if (operator === "==") {
        return fieldValue === value;
      }
      return false;
    });
    return new FakeQuery(filtered);
  }

  limit(count) {
    return new FakeQuery(this.docs.slice(0, count));
  }

  async get() {
    return {docs: this.docs};
  }
}

class FakeTransaction {
  constructor(firestore) {
    this.firestore = firestore;
  }

  async get(ref) {
    return ref.get();
  }

  set(ref, data, options) {
    this.firestore._set(ref.path, data, options);
  }
}

class FakeFirestore {
  constructor(seed = {}) {
    this.store = new Map(Object.entries(seed));
  }

  collection(path) {
    return new FakeCollectionRef(this, path);
  }

  doc(path) {
    return new FakeDocRef(this, path);
  }

  collectionGroup(path) {
    const suffix = `/${path}/`;
    const docs = [...this.store.entries()]
      .filter(([docPath]) => docPath.includes(suffix))
      .map(([docPath, data]) => new FakeDocSnapshot(this, docPath, data));
    return new FakeQuery(docs);
  }

  async runTransaction(handler) {
    return handler(new FakeTransaction(this));
  }

  _set(path, data, options = {}) {
    const existing = this.store.get(path) ?? {};
    this.store.set(path, options.merge ? {...existing, ...data} : {...data});
  }
}

function toSerializedTimestamp(date) {
  return {
    seconds: Math.floor(date.getTime() / 1000),
    nanoseconds: (date.getTime() % 1000) * 1000000,
  };
}

function setPath(target, path, value) {
  const segments = path.split(".");
  let cursor = target;
  for (let index = 0; index < segments.length - 1; index += 1) {
    cursor = cursor[segments[index]];
  }
  cursor[segments[segments.length - 1]] = value;
}

function buildPersistedFinalizationSeed({
  bookingId,
  paymentAttemptId,
  timestampFactory,
}) {
  const booking = buildFutureAcceptedAwaitingPaymentBookingFixture();
  const pricing = resolveCanonicalPricingV3({booking, claimedOffer: null});
  booking.financials = pricing.financialSnapshot;
  booking.createdAt = new Date("2026-07-28T09:00:00.000Z");
  booking.updatedAt = new Date("2026-07-28T09:05:00.000Z");
  booking.lifecycle.respondedAt = new Date("2026-07-28T09:10:00.000Z");
  booking.lifecycle.payDeadlineAt = new Date("2026-07-28T10:30:00.000Z");
  booking.payDeadlineAt = booking.lifecycle.payDeadlineAt;
  booking.schedule.slots[0].startAt = new Date("2026-07-29T06:00:00.000Z");
  booking.schedule.slots[0].endAt = new Date("2026-07-29T07:00:00.000Z");
  booking.schedule.scheduledStartAt = new Date("2026-07-29T06:00:00.000Z");
  booking.schedule.scheduledEndAt = new Date("2026-07-29T07:00:00.000Z");
  booking.schedule.serviceAnchorAt = new Date("2026-07-29T06:00:00.000Z");
  booking.serviceAnchorAt = booking.schedule.serviceAnchorAt;
  booking.scheduledStartAt = booking.schedule.scheduledStartAt;

  const attempt = buildAttempt({
    booking,
    pricing,
    paymentAttemptId,
    razorpayOrderId: `order_${paymentAttemptId}`,
  });
  attempt.bookingId = bookingId;
  attempt.createdAt = new Date("2026-07-28T09:11:00.000Z");
  attempt.orderCreatedAt = new Date("2026-07-28T09:12:00.000Z");
  attempt.checkoutOpenedAt = new Date("2026-07-28T09:13:00.000Z");
  attempt.updatedAt = new Date("2026-07-28T09:13:00.000Z");
  attempt.orderExpiresAt = booking.lifecycle.payDeadlineAt;

  const persistedBooking = structuredClone(booking);
  const persistedAttempt = structuredClone(attempt);
  for (const path of [
    "createdAt",
    "updatedAt",
    "serviceAnchorAt",
    "scheduledStartAt",
    "payDeadlineAt",
    "lifecycle.respondedAt",
    "lifecycle.payDeadlineAt",
    "schedule.serviceAnchorAt",
    "schedule.scheduledStartAt",
    "schedule.scheduledEndAt",
    "schedule.slots.0.startAt",
    "schedule.slots.0.endAt",
  ]) {
    setPath(persistedBooking, path, timestampFactory(path, path.split(".").reduce((value, segment) => value[segment], booking)));
  }
  for (const path of [
    "orderExpiresAt",
    "createdAt",
    "orderCreatedAt",
    "checkoutOpenedAt",
    "updatedAt",
  ]) {
    setPath(persistedAttempt, path, timestampFactory(path, path.split(".").reduce((value, segment) => value[segment], attempt)));
  }

  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: persistedBooking,
    [`bookings/${bookingId}/paymentAttempts/${paymentAttemptId}`]: persistedAttempt,
    [`users/${booking.parentId}`]: {
      displayName: "Nisha Gautam",
      photoUrl: "https://example.com/nisha.jpg",
      ratingAverage: 4.9,
      completedBookingCount: 5,
    },
    [`services/${booking.serviceId}`]: {
      serviceId: booking.serviceId,
      ownerUserId: booking.providerId,
      isActive: true,
      isDeleted: false,
      isPaused: false,
      isVisibleToMarketplace: true,
      isPausedByVerification: false,
      status: "active",
      currency: "INR",
      timezone: "Asia/Kolkata",
      location: {
        displayAddress: "Andheri West, Mumbai",
        latitude: 19.136,
        longitude: 72.829,
      },
    },
  });

  return {firestore, booking, attempt};
}

test("resolveCanonicalPricingV3 keeps provider payout unaffected by Pettxo coupon", () => {
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  booking.service.serviceUnitPricePaise = 100000;
  booking.schedule.slots[0].unitPricePaise = 100000;

  const pricing = resolveCanonicalPricingV3({
    booking,
    claimedOffer: {
      status: "claimed",
      offerId: "offer-1",
      claimedOfferId: "claim-1",
      discountType: "flat",
      discountValue: 300,
      usageLimit: 1,
      usedCount: 0,
      couponCode: "PET300",
    },
  });

  assert.equal(pricing.financialSnapshot.serviceSubtotalPaise, 100000);
  assert.equal(pricing.financialSnapshot.customerPaidPaise, 70000);
  assert.equal(pricing.financialSnapshot.providerPayoutPaise, 85000);
  assert.equal(pricing.financialSnapshot.pettxoCouponFundingPaise, 30000);
});

test("resolveCanonicalPricingV3 supports a 100 percent Pettxo-funded coupon", () => {
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  const pricing = resolveCanonicalPricingV3({
    booking,
    claimedOffer: {
      status: "claimed",
      offerId: "offer-100",
      claimedOfferId: "claim-100",
      discountType: "flat",
      discountValue: 250,
      usageLimit: 1,
      usedCount: 0,
      couponCode: "FREE250",
    },
  });

  assert.equal(pricing.financialSnapshot.serviceSubtotalPaise, 25000);
  assert.equal(pricing.financialSnapshot.customerPaidPaise, 0);
  assert.equal(pricing.financialSnapshot.providerPayoutPaise, 21250);
});

test("validatePreCheckoutAvailabilityV3 rejects an expired payment window", () => {
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  const result = validatePreCheckoutAvailabilityV3({
    booking,
    service: liveService(),
    authoritativeNow: new Date("2026-07-22T12:00:01.000Z"),
  });

  assert.equal(result.ok, false);
  assert.equal(result.code, "PAYMENT_WINDOW_EXPIRED");
});

test("finalizeCapturedBookingPaymentV3 confirms a paid SLOT booking once", () => {
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  const pricing = resolveCanonicalPricingV3({booking, claimedOffer: null});
  booking.financials = pricing.financialSnapshot;

  const result = finalizeCapturedBookingPaymentV3({
    bookingId: "booking-slot-1",
    booking,
    paymentAttempt: {
      schemaVersion: 1,
      paymentAttemptId: "attempt-slot-1",
      bookingId: "booking-slot-1",
      parentId: booking.parentId,
      providerId: booking.providerId,
      requestAttemptId: "request-1",
      razorpayOrderId: "order_slot_1",
      razorpayPaymentId: "",
      amountPaise: pricing.financialSnapshot.customerPaidPaise,
      currency: "INR",
      couponId: "",
      couponClaimId: "",
      pricingHash: pricing.pricingHash,
      availabilityHash: "availability-1",
      state: "ORDER_CREATED",
      orderExpiresAt: booking.lifecycle.payDeadlineAt,
      createdAt: new Date("2026-07-22T10:20:00.000Z"),
      orderCreatedAt: new Date("2026-07-22T10:21:00.000Z"),
      checkoutOpenedAt: new Date("2026-07-22T10:21:30.000Z"),
      captureReportedAt: null,
      captureCreatedAt: null,
      confirmedAt: null,
      failedAt: null,
      refundRequiredAt: null,
      refundedAt: null,
      lastReconciledAt: null,
      verificationSource: "",
      failureCode: "",
      failureMessage: "",
      retryCount: 0,
      updatedAt: new Date("2026-07-22T10:21:30.000Z"),
      pricingSnapshot: {financials: pricing.financialSnapshot},
      couponSnapshot: null,
    },
    parent: parentIdentity(),
    service: liveService(),
    slotOccupancy: {},
    rangeOccupancy: {},
    razorpayPayment: {
      id: "pay_slot_1",
      orderId: "order_slot_1",
      status: "captured",
      amountPaise: pricing.financialSnapshot.customerPaidPaise,
      currency: "INR",
      createdAt: new Date("2026-07-22T10:25:00.000Z"),
      capturedAt: new Date("2026-07-22T10:25:05.000Z"),
    },
    authoritativeNow: new Date("2026-07-22T10:25:10.000Z"),
    verificationSource: "callable",
  });

  assertConfirmedSideEffectsExactlyOnce(result, {
    bookingId: "booking-slot-1",
    paymentAttemptId: "attempt-slot-1",
  });
  assert.equal(result.booking.financials.customerPaidPaise, 25000);
  assert.equal(result.booking.payment.razorpayPaymentId, "pay_slot_1");
  assert.equal(result.notifications.length, 2);
  assert.equal(
    result.notifications.some((notification) =>
      notification.type === "booking_confirmed" &&
      notification.recipientUserId === booking.providerId &&
      notification.data.bookingId === "booking-slot-1"),
    true,
  );
});

test("reconcilePaymentAttemptsV3 persists shared confirmation notifications exactly once", async () => {
  const bookingId = "booking-reconcile-notification-1";
  const paymentAttemptId = "attempt-reconcile-notification-1";
  const {firestore, booking, attempt} = buildPersistedFinalizationSeed({
    bookingId,
    paymentAttemptId,
    timestampFactory: (_path, value) => value,
  });
  attempt.state = "CAPTURE_REPORTED";
  attempt.razorpayPaymentId = "pay_reconcile_notification_1";
  attempt.razorpayOrderId = `order_${paymentAttemptId}`;
  firestore.store.set(
    `bookings/${bookingId}/paymentAttempts/${paymentAttemptId}`,
    {...firestore.store.get(`bookings/${bookingId}/paymentAttempts/${paymentAttemptId}`), ...attempt},
  );
  const originalGetUser = sharedFirebase.auth.getUser;
  sharedFirebase.auth.getUser = async () => ({
    displayName: "Nisha Gautam",
    email: "nisha@example.com",
    phoneNumber: "+919999999999",
    photoURL: "https://example.com/nisha.jpg",
  });

  const recordedNotifications = [];

  try {
    const processed = await reconcilePaymentAttemptsV3({
      firestore,
      keyId: "rzp_test_key",
      keySecret: "rzp_test_secret",
      authoritativeNow: new Date("2026-07-28T09:30:00.000Z"),
      deps: {
        verifyCapturedPayment: async () => ({
          ok: true,
          code: "CONFIRMED",
          paymentAttempt: {
            ...attempt,
            state: "CONFIRMED",
          },
          notifications: [
            {
              idempotencyKey: `booking_confirmed:${bookingId}:${booking.parentId}`,
              recipientUserId: booking.parentId,
              type: "booking_confirmed",
              channels: ["push", "in_app"],
              title: "Booking confirmed",
              body: "Customer notification",
              data: {
                bookingId,
                recipientRole: "customer",
              },
            },
            {
              idempotencyKey: `booking_confirmed:${bookingId}:${booking.providerId}`,
              recipientUserId: booking.providerId,
              type: "booking_confirmed",
              channels: ["push", "in_app"],
              title: "Booking confirmed",
              body: "Provider notification",
              data: {
                bookingId,
                recipientRole: "provider",
              },
            },
          ],
        }),
        persistNotifications: async ({notifications}) => {
          recordedNotifications.push(...notifications);
        },
      },
    });

    assert.equal(processed, 1);
    assert.equal(recordedNotifications.length, 2);
    assert.equal(
      recordedNotifications.some((notification) =>
        notification.type === "booking_confirmed" &&
        notification.recipientUserId === booking.providerId &&
        notification.data.bookingId === bookingId),
      true,
    );
  } finally {
    sharedFirebase.auth.getUser = originalGetUser;
  }
});

test("finalizeCapturedCanonicalPaymentV3 normalizes Firestore Timestamp deadlines at the persistence boundary", async () => {
  const bookingId = "booking-boundary-timestamp-1";
  const paymentAttemptId = "attempt-boundary-timestamp-1";
  const {firestore, booking, attempt} = buildPersistedFinalizationSeed({
    bookingId,
    paymentAttemptId,
    timestampFactory: (_path, value) => Timestamp.fromDate(value),
  });
  const originalGetUser = sharedFirebase.auth.getUser;
  sharedFirebase.auth.getUser = async () => ({
    displayName: "Nisha Gautam",
    email: "nisha@example.com",
    phoneNumber: "+919999999999",
    photoURL: "https://example.com/nisha.jpg",
  });

  try {
    const result = await finalizeCapturedCanonicalPaymentV3({
      firestore,
      facts: {
        bookingId,
        paymentAttemptId,
        razorpayOrderId: attempt.razorpayOrderId,
        razorpayPaymentId: "pay_boundary_timestamp_1",
        capturedAmountPaise: attempt.amountPaise,
        currency: attempt.currency,
        capturedAt: new Date("2026-07-28T09:20:00.000Z"),
        verificationSource: "webhook",
      },
      authoritativeNow: new Date("2026-07-28T09:20:05.000Z"),
    });

    assert.equal(result.ok, true);
    assert.equal(result.booking.state, "CONFIRMED");
    assert.equal(result.paymentAttempt.state, "CONFIRMED");
    assert.equal(
      result.bookingPrivateParticipants.providerPrivate.phoneNumber,
      "+919999999999",
    );
    assert.equal(
      result.booking.lifecycle.payDeadlineAt?.toISOString(),
      booking.lifecycle.payDeadlineAt?.toISOString(),
    );
    assert.equal(
      result.paymentAttempt.orderExpiresAt?.toISOString(),
      booking.lifecycle.payDeadlineAt?.toISOString(),
    );
  } finally {
    sharedFirebase.auth.getUser = originalGetUser;
  }
});

test("finalizeCapturedCanonicalPaymentV3 normalizes serialized timestamp-like deadlines and stays idempotent on replay", async () => {
  const bookingId = "booking-boundary-serialized-1";
  const paymentAttemptId = "attempt-boundary-serialized-1";
  const {firestore, booking, attempt} = buildPersistedFinalizationSeed({
    bookingId,
    paymentAttemptId,
    timestampFactory: (_path, value) => toSerializedTimestamp(value),
  });
  const originalGetUser = sharedFirebase.auth.getUser;
  sharedFirebase.auth.getUser = async () => ({
    displayName: "Nisha Gautam",
    email: "nisha@example.com",
    phoneNumber: "+919999999999",
    photoURL: "https://example.com/nisha.jpg",
  });

  try {
    const first = await finalizeCapturedCanonicalPaymentV3({
      firestore,
      facts: {
        bookingId,
        paymentAttemptId,
        razorpayOrderId: attempt.razorpayOrderId,
        razorpayPaymentId: "pay_boundary_serialized_1",
        capturedAmountPaise: attempt.amountPaise,
        currency: attempt.currency,
        capturedAt: new Date("2026-07-28T09:21:00.000Z"),
        verificationSource: "reconciliation",
      },
      authoritativeNow: new Date("2026-07-28T09:21:05.000Z"),
    });
    assert.equal(first.ok, true);
    await persistFinalizePaymentResultV3({firestore, result: first, bookingId});

    const replay = await finalizeCapturedCanonicalPaymentV3({
      firestore,
      facts: {
        bookingId,
        paymentAttemptId,
        razorpayOrderId: attempt.razorpayOrderId,
        razorpayPaymentId: "pay_boundary_serialized_1",
        capturedAmountPaise: attempt.amountPaise,
        currency: attempt.currency,
        capturedAt: new Date("2026-07-28T09:21:00.000Z"),
        verificationSource: "reconciliation",
      },
      authoritativeNow: new Date("2026-07-28T09:22:05.000Z"),
    });

    assert.equal(replay.ok, true);
    assert.equal(replay.code, "IDEMPOTENT_REPLAY");
    assert.equal(
      replay.booking.lifecycle.payDeadlineAt?.toISOString(),
      booking.lifecycle.payDeadlineAt?.toISOString(),
    );
  } finally {
    sharedFirebase.auth.getUser = originalGetUser;
  }
});

test("finalizeCapturedCanonicalPaymentV3 turns invalid persisted payDeadlineAt into a controlled malformed-booking result", async () => {
  const bookingId = "booking-boundary-invalid-1";
  const paymentAttemptId = "attempt-boundary-invalid-1";
  const {firestore, attempt} = buildPersistedFinalizationSeed({
    bookingId,
    paymentAttemptId,
    timestampFactory: (path, value) =>
      path.includes("payDeadlineAt") ? {seconds: "not-a-number"} : value,
  });
  const originalGetUser = sharedFirebase.auth.getUser;
  sharedFirebase.auth.getUser = async () => ({
    displayName: "Nisha Gautam",
    email: "nisha@example.com",
    phoneNumber: "+919999999999",
    photoURL: "https://example.com/nisha.jpg",
  });

  try {
    const result = await finalizeCapturedCanonicalPaymentV3({
      firestore,
      facts: {
        bookingId,
        paymentAttemptId,
        razorpayOrderId: attempt.razorpayOrderId,
        razorpayPaymentId: "pay_boundary_invalid_1",
        capturedAmountPaise: attempt.amountPaise,
        currency: attempt.currency,
        capturedAt: new Date("2026-07-28T09:23:00.000Z"),
        verificationSource: "webhook",
      },
      authoritativeNow: new Date("2026-07-28T09:23:05.000Z"),
    });

    assert.equal(result.ok, false);
    assert.equal(result.code, "MALFORMED_BOOKING");
    assert.equal(result.message, "Canonical payment deadline is missing.");
  } finally {
    sharedFirebase.auth.getUser = originalGetUser;
  }
});

test("finalizeCapturedBookingPaymentV3 creates refund-required outcome when capacity is lost", () => {
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  const pricing = resolveCanonicalPricingV3({booking, claimedOffer: null});
  booking.financials = pricing.financialSnapshot;

  const result = finalizeCapturedBookingPaymentV3({
    bookingId: "booking-slot-2",
    booking,
    paymentAttempt: {
      schemaVersion: 1,
      paymentAttemptId: "attempt-slot-2",
      bookingId: "booking-slot-2",
      parentId: booking.parentId,
      providerId: booking.providerId,
      requestAttemptId: "request-2",
      razorpayOrderId: "order_slot_2",
      razorpayPaymentId: "",
      amountPaise: pricing.financialSnapshot.customerPaidPaise,
      currency: "INR",
      couponId: "",
      couponClaimId: "",
      pricingHash: pricing.pricingHash,
      availabilityHash: "availability-2",
      state: "ORDER_CREATED",
      orderExpiresAt: booking.lifecycle.payDeadlineAt,
      createdAt: new Date("2026-07-22T10:20:00.000Z"),
      orderCreatedAt: new Date("2026-07-22T10:21:00.000Z"),
      checkoutOpenedAt: new Date("2026-07-22T10:21:30.000Z"),
      captureReportedAt: null,
      captureCreatedAt: null,
      confirmedAt: null,
      failedAt: null,
      refundRequiredAt: null,
      refundedAt: null,
      lastReconciledAt: null,
      verificationSource: "",
      failureCode: "",
      failureMessage: "",
      retryCount: 0,
      updatedAt: new Date("2026-07-22T10:21:30.000Z"),
      pricingSnapshot: {financials: pricing.financialSnapshot},
      couponSnapshot: null,
    },
    parent: parentIdentity(),
    service: liveService(),
    slotOccupancy: {
      "slot-1": {
        slotId: "slot-1",
        confirmedUnits: 1,
        capacitySnapshot: 1,
        bookingClaims: {},
      },
    },
    rangeOccupancy: {},
    razorpayPayment: {
      id: "pay_slot_2",
      orderId: "order_slot_2",
      status: "captured",
      amountPaise: pricing.financialSnapshot.customerPaidPaise,
      currency: "INR",
      createdAt: new Date("2026-07-22T10:25:00.000Z"),
      capturedAt: new Date("2026-07-22T10:25:05.000Z"),
    },
    authoritativeNow: new Date("2026-07-22T10:25:10.000Z"),
    verificationSource: "webhook",
  });

  assertRefundInstructionExactlyOnce(result, {
    bookingId: "booking-slot-2",
    expectedCode: "CAPACITY_EXHAUSTED",
    expectedReasonCode: "CAPACITY_UNAVAILABLE_AFTER_CAPTURE",
    expectedRefundAmountPaise: 25000,
    expectedEvent: "refunded",
    expectedNotificationType: "payment_refund_required",
  });
});

test("range pricing calculates nights authoritatively", () => {
  const booking = buildRequestedRangeBookingFixture();
  booking.state = "ACCEPTED_AWAITING_PAYMENT";
  booking.stateQueryValue = "ACCEPTED_AWAITING_PAYMENT";
  booking.lifecycle.respondedAt = new Date("2026-07-22T10:20:00.000Z");
  booking.lifecycle.payDeadlineAt = new Date("2026-07-22T11:20:00.000Z");
  const pricing = resolveCanonicalPricingV3({booking, claimedOffer: null});

  assert.equal(pricing.financialSnapshot.serviceSubtotalPaise, 360000);
  assert.equal(pricing.financialSnapshot.providerPayoutPaise, 306000);
});

test("finalizer keeps existing private data on idempotent replay", () => {
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  const pricing = resolveCanonicalPricingV3({booking, claimedOffer: null});
  booking.financials = pricing.financialSnapshot;
  booking.state = "CONFIRMED";
  booking.stateQueryValue = "CONFIRMED";
  booking.lifecycle.paidAt = new Date("2026-07-22T10:25:10.000Z");

  const existingPrivate = {
    schemaVersion: 1,
    bookingId: "booking-confirmed-1",
    parentId: booking.parentId,
    providerId: booking.providerId,
    parentOtpCode: "482913",
    providerOtpHash: "a".repeat(64),
    otpState: "ACTIVE",
    failedAttemptCount: 0,
    lastFailedAttemptAt: null,
    lockedUntil: null,
    verifiedAt: null,
    successfulAttemptNumber: null,
    lastVerificationAttemptId: "",
    lastVerificationOutcome: "",
    contactUnlockedAt: new Date("2026-07-22T10:25:10.000Z"),
    createdAt: new Date("2026-07-22T10:25:10.000Z"),
    updatedAt: new Date("2026-07-22T10:25:10.000Z"),
  };

  const result = finalizeCapturedBookingPaymentV3({
    bookingId: "booking-confirmed-1",
    booking,
    paymentAttempt: {
      ...buildAttempt({
        booking,
        pricing,
        paymentAttemptId: "attempt-confirmed-1",
        razorpayOrderId: "order_confirmed_1",
      }),
      state: "CONFIRMED",
      razorpayPaymentId: "pay_confirmed_1",
      confirmedAt: new Date("2026-07-22T10:25:10.000Z"),
    },
    parent: parentIdentity(),
    providerPrivate: providerPrivateIdentity(),
    service: liveService(),
    existingBookingPrivate: existingPrivate,
    slotOccupancy: {},
    rangeOccupancy: {},
    razorpayPayment: {
      id: "pay_confirmed_1",
      orderId: "order_confirmed_1",
      status: "captured",
      amountPaise: pricing.financialSnapshot.customerPaidPaise,
      currency: "INR",
      createdAt: new Date("2026-07-22T10:25:00.000Z"),
      capturedAt: new Date("2026-07-22T10:25:05.000Z"),
    },
    authoritativeNow: new Date("2026-07-22T10:26:00.000Z"),
    verificationSource: "webhook",
  });

  assert.equal(result.ok, true);
  assert.equal(result.code, "IDEMPOTENT_REPLAY");
  assertConfirmedSideEffectsExactlyOnce(result, {
    bookingId: "booking-confirmed-1",
    paymentAttemptId: "attempt-confirmed-1",
  });
  assert.equal(result.bookingPrivate.parentOtpCode, "482913");
  assert.equal(result.privateWritePlan.writeBookingPrivate, false);
  assert.equal(result.otpCode, "");
  assert.deepEqual(result.occupancyWrites, {});
});

test("finalizer reports repair-required when a confirmed booking is missing its OTP private document", () => {
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  const pricing = resolveCanonicalPricingV3({booking, claimedOffer: null});
  booking.financials = pricing.financialSnapshot;
  booking.state = "CONFIRMED";
  booking.stateQueryValue = "CONFIRMED";
  booking.lifecycle.paidAt = new Date("2026-07-22T10:25:10.000Z");

  const result = finalizeCapturedBookingPaymentV3({
    bookingId: "booking-confirmed-missing-private-1",
    booking,
    paymentAttempt: {
      ...buildAttempt({
        booking,
        pricing,
        paymentAttemptId: "attempt-confirmed-missing-private-1",
        razorpayOrderId: "order_confirmed_missing_private_1",
      }),
      state: "CONFIRMED",
      razorpayPaymentId: "pay_confirmed_missing_private_1",
      confirmedAt: new Date("2026-07-22T10:25:10.000Z"),
    },
    parent: parentIdentity(),
    providerPrivate: providerPrivateIdentity(),
    service: liveService(),
    existingBookingPrivate: null,
    slotOccupancy: {},
    rangeOccupancy: {},
    razorpayPayment: {
      id: "pay_confirmed_missing_private_1",
      orderId: "order_confirmed_missing_private_1",
      status: "captured",
      amountPaise: pricing.financialSnapshot.customerPaidPaise,
      currency: "INR",
      createdAt: new Date("2026-07-22T10:25:00.000Z"),
      capturedAt: new Date("2026-07-22T10:25:05.000Z"),
    },
    authoritativeNow: new Date("2026-07-22T10:26:00.000Z"),
    verificationSource: "webhook",
  });

  assert.equal(result.ok, false);
  assert.equal(result.code, "PRIVATE_REPAIR_REQUIRED");
  assert.equal(result.refundInstruction, null);
});

test("finalizer allows captures received after deadline when trusted capture happened in-window", () => {
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  const pricing = resolveCanonicalPricingV3({booking, claimedOffer: null});
  booking.financials = pricing.financialSnapshot;

  const result = finalizeCapturedBookingPaymentV3({
    bookingId: "booking-slot-deadline-1",
    booking,
    paymentAttempt: buildAttempt({
      booking,
      pricing,
      paymentAttemptId: "attempt-deadline-1",
      razorpayOrderId: "order_deadline_1",
    }),
    parent: parentIdentity(),
    service: liveService(),
    slotOccupancy: {},
    rangeOccupancy: {},
    razorpayPayment: {
      id: "pay_deadline_1",
      orderId: "order_deadline_1",
      status: "captured",
      amountPaise: pricing.financialSnapshot.customerPaidPaise,
      currency: "INR",
      createdAt: new Date("2026-07-22T10:59:59.999Z"),
      capturedAt: new Date("2026-07-22T10:59:59.999Z"),
    },
    authoritativeNow: new Date("2026-07-22T11:05:00.000Z"),
    verificationSource: "webhook",
  });

  assert.equal(result.ok, true);
  assert.equal(result.booking.state, "CONFIRMED");
});

test("finalizer accepts capture exactly at payDeadlineAt", () => {
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  const pricing = resolveCanonicalPricingV3({booking, claimedOffer: null});
  booking.financials = pricing.financialSnapshot;

  const result = finalizeCapturedBookingPaymentV3({
    bookingId: "booking-slot-deadline-2",
    booking,
    paymentAttempt: buildAttempt({
      booking,
      pricing,
      paymentAttemptId: "attempt-deadline-2",
      razorpayOrderId: "order_deadline_2",
    }),
    parent: parentIdentity(),
    service: liveService(),
    slotOccupancy: {},
    rangeOccupancy: {},
    razorpayPayment: {
      id: "pay_deadline_2",
      orderId: "order_deadline_2",
      status: "captured",
      amountPaise: pricing.financialSnapshot.customerPaidPaise,
      currency: "INR",
      createdAt: new Date("2026-07-22T11:00:00.000Z"),
      capturedAt: new Date("2026-07-22T11:00:00.000Z"),
    },
    authoritativeNow: new Date("2026-07-22T11:00:30.000Z"),
    verificationSource: "callable",
  });

  assert.equal(result.ok, true);
  assert.equal(result.booking.state, "CONFIRMED");
});

test("finalizer marks refund required when trusted capture is beyond deadline tolerance", () => {
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  const pricing = resolveCanonicalPricingV3({booking, claimedOffer: null});
  booking.financials = pricing.financialSnapshot;
  const beyondToleranceCaptureAt = new Date(
    booking.lifecycle.payDeadlineAt.getTime() + (2 * 60 * 1000) + 1,
  );

  const result = finalizeCapturedBookingPaymentV3({
    bookingId: "booking-slot-deadline-3",
    booking,
    paymentAttempt: buildAttempt({
      booking,
      pricing,
      paymentAttemptId: "attempt-deadline-3",
      razorpayOrderId: "order_deadline_3",
    }),
    parent: parentIdentity(),
    service: liveService(),
    slotOccupancy: {},
    rangeOccupancy: {},
    razorpayPayment: {
      id: "pay_deadline_3",
      orderId: "order_deadline_3",
      status: "captured",
      amountPaise: pricing.financialSnapshot.customerPaidPaise,
      currency: "INR",
      createdAt: beyondToleranceCaptureAt,
      capturedAt: beyondToleranceCaptureAt,
    },
    authoritativeNow: new Date(beyondToleranceCaptureAt.getTime() + 5 * 1000),
    verificationSource: "reconciliation",
  });

  assertRefundInstructionExactlyOnce(result, {
    bookingId: "booking-slot-deadline-3",
    expectedCode: "PAYMENT_EXPIRED",
    expectedReasonCode: "CAPTURE_AFTER_DEADLINE",
    expectedRefundAmountPaise: 25000,
    expectedEvent: "payment_abandoned",
    expectedNotificationType: "payment_failed",
  });
});

test("late capture for an already expired booking stays in refund-required flow", () => {
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  const pricing = resolveCanonicalPricingV3({booking, claimedOffer: null});
  booking.financials = pricing.financialSnapshot;
  booking.state = "PAYMENT_EXPIRED";
  booking.stateQueryValue = "PAYMENT_EXPIRED";
  booking.payment.status = "expired";
  booking.lifecycle.cancelledAt = new Date("2026-07-22T11:05:00.000Z");

  const result = finalizeCapturedBookingPaymentV3({
    bookingId: "booking-slot-expired-late-capture-1",
    booking,
    paymentAttempt: buildAttempt({
      booking,
      pricing,
      paymentAttemptId: "attempt-expired-late-capture-1",
      razorpayOrderId: "order_expired_late_capture_1",
    }),
    parent: parentIdentity(),
    service: liveService(),
    slotOccupancy: {},
    rangeOccupancy: {},
    razorpayPayment: {
      id: "pay_expired_late_capture_1",
      orderId: "order_expired_late_capture_1",
      status: "captured",
      amountPaise: pricing.financialSnapshot.customerPaidPaise,
      currency: "INR",
      createdAt: new Date("2026-07-22T11:06:00.000Z"),
      capturedAt: new Date("2026-07-22T11:06:00.000Z"),
    },
    authoritativeNow: new Date("2026-07-22T11:06:30.000Z"),
    verificationSource: "webhook",
  });

  assertRefundInstructionExactlyOnce(result, {
    bookingId: "booking-slot-expired-late-capture-1",
    expectedCode: "PAYMENT_EXPIRED",
    expectedReasonCode: "CAPTURE_AFTER_PAYMENT_EXPIRED",
    expectedRefundAmountPaise: 25000,
    expectedEvent: "payment_abandoned",
    expectedNotificationType: "payment_failed",
  });
});

test("persistFinalizePaymentResultV3 writes private, financial, and chat unlock docs exactly once for confirmed payments", async () => {
  const bookingId = "booking-slot-persist-1";
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  const pricing = resolveCanonicalPricingV3({booking, claimedOffer: null});
  booking.financials = pricing.financialSnapshot;

  const result = finalizeCapturedBookingPaymentV3({
    bookingId,
    booking,
    paymentAttempt: {
      ...buildAttempt({
        booking,
        pricing,
        paymentAttemptId: "attempt-persist-1",
        razorpayOrderId: "order_persist_1",
      }),
      bookingId,
    },
    parent: parentIdentity(),
    providerPrivate: providerPrivateIdentity(),
    service: liveService(),
    slotOccupancy: {},
    rangeOccupancy: {},
    razorpayPayment: {
      id: "pay_persist_1",
      orderId: "order_persist_1",
      status: "captured",
      amountPaise: pricing.financialSnapshot.customerPaidPaise,
      currency: "INR",
      createdAt: new Date("2026-07-22T10:25:00.000Z"),
      capturedAt: new Date("2026-07-22T10:25:05.000Z"),
    },
    authoritativeNow: new Date("2026-07-22T10:25:10.000Z"),
    verificationSource: "callable",
  });

  assert.equal(result.ok, true);
  assert.equal(
    result.financialWrites.bookingChat.safetyNotice,
    BOOKING_CHAT_SAFETY_NOTICE,
  );
  assert.notEqual(
    result.financialWrites.bookingChat.safetyNotice,
    LEGACY_BOOKING_CHAT_SAFETY_NOTICE,
  );
  const firestore = new FakeFirestore();

  await persistFinalizePaymentResultV3({firestore, result, bookingId});
  await persistFinalizePaymentResultV3({firestore, result, bookingId});

  assert.equal(firestore.store.has(`bookingPrivate/${bookingId}`), true);
  assert.equal(firestore.store.has(`bookingPrivateParticipants/${bookingId}`), true);
  assert.equal(firestore.store.has(`bookingChats/${bookingId}`), true);
  assert.equal(firestore.store.has(`chats/${bookingId}`), true);
  assert.equal(firestore.store.has(`bookingFinancials/${bookingId}`), true);
  assert.equal(firestore.store.has(`payments/${bookingId}`), true);
  assert.equal(firestore.store.has(`invoices/${bookingId}`), true);
  assert.equal(firestore.store.has(`providerEarnings/${bookingId}`), true);
  assert.equal(firestore.store.has(`payoutReadiness/${bookingId}`), true);
  assertChatCompatibilityExactlyOnce(firestore, bookingId, {
    expectedParticipants: ["parent-1", "provider-1"],
    expectedProviderId: "provider-1",
  });
  assert.equal(
    [...firestore.store.keys()].filter((path) => path.startsWith(`messages/${bookingId}`)).length,
    0,
  );

  const eventPaths = [...firestore.store.keys()].filter((path) =>
    path.startsWith(`bookings/${bookingId}/events/`),
  );
  assert.equal(eventPaths.length, 1);
  assert.equal(
    firestore.store.get(`bookingPrivateParticipants/${bookingId}`).providerPrivate.phoneNumber,
    "+918888888888",
  );
  assert.equal(
    firestore.store.get(`bookingPrivateParticipants/${bookingId}`).parentOtpCode,
    undefined,
  );
});

test("persistFinalizePaymentResultV3 keeps paid-only unlock docs absent for refund-required outcomes", async () => {
  const bookingId = "booking-slot-persist-2";
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  const pricing = resolveCanonicalPricingV3({booking, claimedOffer: null});
  booking.financials = pricing.financialSnapshot;

  const result = finalizeCapturedBookingPaymentV3({
    bookingId,
    booking,
    paymentAttempt: {
      ...buildAttempt({
        booking,
        pricing,
        paymentAttemptId: "attempt-persist-2",
        razorpayOrderId: "order_persist_2",
      }),
      bookingId,
    },
    parent: parentIdentity(),
    service: liveService(),
    slotOccupancy: {
      "slot-1": {
        slotId: "slot-1",
        confirmedUnits: 1,
        capacitySnapshot: 1,
        bookingClaims: {},
      },
    },
    rangeOccupancy: {},
    razorpayPayment: {
      id: "pay_persist_2",
      orderId: "order_persist_2",
      status: "captured",
      amountPaise: pricing.financialSnapshot.customerPaidPaise,
      currency: "INR",
      createdAt: new Date("2026-07-22T10:25:00.000Z"),
      capturedAt: new Date("2026-07-22T10:25:05.000Z"),
    },
    authoritativeNow: new Date("2026-07-22T10:25:10.000Z"),
    verificationSource: "webhook",
  });

  assert.equal(result.ok, false);
  const firestore = new FakeFirestore();
  await persistFinalizePaymentResultV3({firestore, result, bookingId});

  for (const path of [
    `refunds/${bookingId}`,
  ]) {
    assert.equal(firestore.store.has(path), true);
  }
  assertNoPaidUnlocks(firestore, bookingId);
});

test("finalizer keeps bookingPrivate and OTP absent across pre-confirmation and refund states", () => {
  const preConfirmationStates = [
    "REQUESTED",
    "PENDING_PROVIDER",
    "ORDER_CREATING",
    "ORDER_CREATED",
    "CHECKOUT_OPENED",
    "CAPTURE_REPORTED",
    "CONFIRMING",
    "CAPTURED_REQUIRES_RECONCILIATION",
    "FAILED",
    "EXPIRED",
    "PAYMENT_EXPIRED",
    "REFUND_REQUIRED",
    "REFUND_PENDING",
    "REFUNDED",
  ];

  for (const state of preConfirmationStates) {
    const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
    const pricing = resolveCanonicalPricingV3({booking, claimedOffer: null});
    booking.financials = pricing.financialSnapshot;
    booking.state = state;
    booking.stateQueryValue = state;

    const result = finalizeCapturedBookingPaymentV3({
      bookingId: `booking-${state.toLowerCase()}`,
      booking,
      paymentAttempt: {
        ...buildAttempt({
          booking,
          pricing,
          paymentAttemptId: `attempt-${state.toLowerCase()}`,
          razorpayOrderId: `order_${state.toLowerCase()}`,
        }),
        state,
      },
      parent: parentIdentity(),
      service: liveService(),
      slotOccupancy: {},
      rangeOccupancy: {},
      razorpayPayment: {
        id: `pay_${state.toLowerCase()}`,
        orderId: `order_${state.toLowerCase()}`,
        status: "captured",
        amountPaise: pricing.financialSnapshot.customerPaidPaise,
        currency: "INR",
        createdAt: new Date("2026-07-22T10:25:00.000Z"),
        capturedAt: new Date("2026-07-22T10:25:05.000Z"),
      },
      authoritativeNow: new Date("2026-07-22T10:25:10.000Z"),
      verificationSource: "reconciliation",
    });

    assert.equal(result.ok, false, state);
    assertConfirmedSideEffectsAbsent(result);
  }
});

test("confirmed persistence keeps OTP and participant contact data in separate private documents", async () => {
  const fixture = buildCanonicalPaymentRaceFixture({
    ids: {
      bookingId: "booking-slot-persist-privacy-1",
      paymentAttemptId: "attempt-privacy-1",
      razorpayOrderId: "order_privacy_1",
      razorpayPaymentId: "pay_privacy_1",
    },
  });

  const result = finalizeCapturedBookingPaymentV3({
    bookingId: fixture.ids.bookingId,
    booking: fixture.booking,
    paymentAttempt: fixture.paymentAttempt,
    parent: fixture.parent,
    providerPrivate: providerPrivateIdentity(""),
    service: fixture.service,
    slotOccupancy: fixture.slotOccupancy,
    rangeOccupancy: fixture.rangeOccupancy,
    razorpayPayment: fixture.razorpayPayment,
    authoritativeNow: fixture.authoritativeNow,
    verificationSource: "callable",
  });

  const firestore = new FakeFirestore();
  await persistFinalizePaymentResultV3({
    firestore,
    result,
    bookingId: fixture.ids.bookingId,
  });

  assert.equal(
    firestore.store.get(`bookingPrivate/${fixture.ids.bookingId}`).phoneNumber,
    undefined,
  );
  assert.equal(
    firestore.store.get(`bookingPrivate/${fixture.ids.bookingId}`).serviceAddress,
    undefined,
  );
  assert.equal(
    firestore.store.get(`bookingPrivateParticipants/${fixture.ids.bookingId}`).parentPrivate.phoneNumber,
    "+919999999999",
  );
  assert.equal(
    firestore.store.get(`bookingPrivateParticipants/${fixture.ids.bookingId}`).parentPrivate.exactAddress,
    "Andheri West, Mumbai",
  );
  assert.equal(
    firestore.store.get(`bookingPrivateParticipants/${fixture.ids.bookingId}`).providerPrivate,
    undefined,
  );
  assertNoPrivateLeakage(
    firestore.store.get(`bookings/${fixture.ids.bookingId}`),
  );
  assertNoPrivateLeakage(
    firestore.store.get(
      `bookings/${fixture.ids.bookingId}/paymentAttempts/${result.paymentAttempt.paymentAttemptId}`,
    ),
  );
  assertNoPrivateLeakage(
    firestore.store.get(`bookingChats/${fixture.ids.bookingId}`),
  );
  assertNoPrivateLeakage(
    firestore.store.get(`chats/${fixture.ids.bookingId}`),
  );
  assertNoPrivateLeakage(
    [...firestore.store.entries()]
      .filter(([path]) =>
        path.startsWith(`bookings/${fixture.ids.bookingId}/events/`),
      )
      .map(([, value]) => value),
  );
});

test("participant-private writer omits providerPrivate.phoneNumber safely when unavailable", () => {
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  const pricing = resolveCanonicalPricingV3({booking, claimedOffer: null});
  booking.financials = pricing.financialSnapshot;

  const result = finalizeCapturedBookingPaymentV3({
    bookingId: "booking-no-provider-phone-1",
    booking,
    paymentAttempt: {
      ...buildAttempt({
        booking,
        pricing,
        paymentAttemptId: "attempt-no-provider-phone-1",
        razorpayOrderId: "order_no_provider_phone_1",
      }),
      bookingId: "booking-no-provider-phone-1",
    },
    parent: parentIdentity(),
    providerPrivate: providerPrivateIdentity(""),
    service: liveService(),
    slotOccupancy: {},
    rangeOccupancy: {},
    razorpayPayment: {
      id: "pay_no_provider_phone_1",
      orderId: "order_no_provider_phone_1",
      status: "captured",
      amountPaise: pricing.financialSnapshot.customerPaidPaise,
      currency: "INR",
      createdAt: new Date("2026-07-22T10:25:00.000Z"),
      capturedAt: new Date("2026-07-22T10:25:05.000Z"),
    },
    authoritativeNow: new Date("2026-07-22T10:25:10.000Z"),
    verificationSource: "callable",
  });

  assert.equal(result.ok, true);
  assert.equal(result.bookingPrivateParticipants.providerPrivate, undefined);
  assert.equal(result.bookingPrivateParticipants.parentPrivate.phoneNumber, "+919999999999");
});

test("submitRefundInstructionV3 updates the existing refund document without creating duplicates", async () => {
  const bookingId = "booking-refund-1";
  const originalRefundProcessor = razorpayGateway.processRazorpayRefundV3;
  razorpayGateway.processRazorpayRefundV3 = async () => ({
    razorpayRefundId: "rfnd_1",
    status: "submitted",
  });

  try {
    const firestore = new FakeFirestore({
      [`bookings/${bookingId}/paymentAttempts/attempt-1`]: {
        bookingId,
        paymentAttemptId: "attempt-1",
        state: "REFUND_REQUIRED",
        amountPaise: 25000,
        razorpayPaymentId: "pay_refund_1",
        reconciliationAttemptCount: 0,
      },
      [`refunds/${bookingId}`]: {
        bookingId,
        paymentAttemptId: "attempt-1",
        refundAmountPaise: 25000,
        reasonCode: "CAPACITY_UNAVAILABLE_AFTER_CAPTURE",
        state: "required",
      },
    });

    const outcome = await submitRefundInstructionV3({
      firestore,
      bookingId,
      paymentAttemptId: "attempt-1",
      keyId: "key",
      keySecret: "secret",
      authoritativeNow: new Date("2026-07-22T10:40:00.000Z"),
    });

    assert.equal(outcome, "REFUND_PENDING");
    assert.equal(firestore.store.has(`refunds/${bookingId}`), true);
    assert.equal(
      [...firestore.store.keys()].filter((path) => path === `refunds/${bookingId}`).length,
      1,
    );
    assert.equal(
      firestore.store.get(`bookings/${bookingId}/paymentAttempts/attempt-1`).state,
      "REFUND_PENDING",
    );
    assert.equal(firestore.store.get(`refunds/${bookingId}`).razorpayRefundId, "rfnd_1");
  } finally {
    razorpayGateway.processRazorpayRefundV3 = originalRefundProcessor;
  }
});

test("zero-payable capacity loss stays unconfirmed without creating a Razorpay refund instruction", () => {
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  const pricing = resolveCanonicalPricingV3({
    booking,
    claimedOffer: {
      status: "claimed",
      offerId: "offer-100",
      claimedOfferId: "claim-100",
      discountType: "flat",
      discountValue: 250,
      usageLimit: 1,
      usedCount: 0,
      couponCode: "PETFREE",
    },
  });
  booking.financials = pricing.financialSnapshot;

  const result = finalizeCapturedBookingPaymentV3({
    bookingId: "booking-zero-payable-capacity-1",
    booking,
    paymentAttempt: {
      ...buildAttempt({
        booking,
        pricing,
        paymentAttemptId: "attempt-zero-payable-capacity-1",
        razorpayOrderId: "order_zero_payable_capacity_1",
      }),
      bookingId: "booking-zero-payable-capacity-1",
      amountPaise: 0,
      state: "CHECKOUT_OPENED",
      verificationSource: "zero_payable",
    },
    parent: parentIdentity(),
    service: liveService(),
    slotOccupancy: {
      "slot-1": {
        slotId: "slot-1",
        confirmedUnits: 1,
        capacitySnapshot: 1,
        bookingClaims: {},
      },
    },
    rangeOccupancy: {},
    razorpayPayment: null,
    authoritativeNow: new Date("2026-07-22T10:25:10.000Z"),
    verificationSource: "zero_payable",
  });

  assert.equal(result.ok, false);
  assert.equal(result.booking.state, "PAYMENT_EXPIRED");
  assert.equal(result.paymentAttempt.state, "REFUND_REQUIRED");
  assert.equal(result.refundInstruction?.refundAmountPaise, 0);
  assert.equal(result.refundInstruction?.razorpayPaymentId, "");
  assert.equal(result.booking.lifecycle.paidAt, null);
  assertNoPrivateLeakage(result.booking);
  assertConfirmedSideEffectsAbsent(result);
});

test("submitRefundInstructionV3 keeps one deterministic refund document across retryable gateway failures", async () => {
  const bookingId = "booking-refund-retry-1";
  const originalRefundProcessor = razorpayGateway.processRazorpayRefundV3;
  let callCount = 0;
  razorpayGateway.processRazorpayRefundV3 = async () => {
    callCount += 1;
    if (callCount === 1) {
      throw new Error("gateway timeout");
    }
    return {
      razorpayRefundId: "rfnd_retry_1",
      status: "processed",
    };
  };

  try {
    const firestore = new FakeFirestore({
      [`bookings/${bookingId}/paymentAttempts/attempt-1`]: {
        bookingId,
        paymentAttemptId: "attempt-1",
        state: "REFUND_REQUIRED",
        amountPaise: 25000,
        razorpayPaymentId: "pay_refund_retry_1",
        reconciliationAttemptCount: 0,
      },
      [`refunds/${bookingId}`]: {
        bookingId,
        paymentAttemptId: "attempt-1",
        refundAmountPaise: 25000,
        reasonCode: "CAPACITY_UNAVAILABLE_AFTER_CAPTURE",
        state: "required",
        attemptCount: 0,
      },
    });

    const first = await submitRefundInstructionV3({
      firestore,
      bookingId,
      paymentAttemptId: "attempt-1",
      keyId: "key",
      keySecret: "secret",
      authoritativeNow: new Date("2026-07-22T10:40:00.000Z"),
    });
    const second = await submitRefundInstructionV3({
      firestore,
      bookingId,
      paymentAttemptId: "attempt-1",
      keyId: "key",
      keySecret: "secret",
      authoritativeNow: new Date("2026-07-22T10:45:00.000Z"),
    });

    expectSingleRefundDoc();
    assert.equal(first, "RETRY_LATER");
    assert.equal(second, "REFUNDED");
    assert.equal(callCount, 2);
    assert.equal(
      firestore.store.get(`bookings/${bookingId}/paymentAttempts/attempt-1`).state,
      "REFUND_PENDING",
    );
    assert.equal(
      firestore.store.get(`refunds/${bookingId}`).razorpayRefundId,
      "rfnd_retry_1",
    );

    function expectSingleRefundDoc() {
      assert.equal(
        [...firestore.store.keys()].filter((path) => path === `refunds/${bookingId}`).length,
        1,
      );
    }
  } finally {
    razorpayGateway.processRazorpayRefundV3 = originalRefundProcessor;
  }
});
