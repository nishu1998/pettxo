const test = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");

const {
  buildConfirmedSlotBookingFixture,
} = require("../lib/booking/schema/bookingFixtures.js");
const {
  calculateCanonicalNoShowAllocationV3,
  finalizeCanonicalNoShowV3,
  verifyBookingStartOtpV3,
} = require("../lib/booking/application/serviceStartOrchestrationV3.js");

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

class FakeDocRef {
  constructor(firestore, path) {
    this.firestore = firestore;
    this.path = path;
    this.id = path.split("/").pop();
  }

  collection(name) {
    return new FakeCollectionRef(this.firestore, `${this.path}/${name}`);
  }

  async get() {
    return new FakeDocSnapshot(
      this.firestore,
      this.path,
      this.firestore.store.get(this.path),
    );
  }
}

class FakeCollectionRef {
  constructor(firestore, path) {
    this.firestore = firestore;
    this.path = path;
  }

  doc(id) {
    return new FakeDocRef(this.firestore, `${this.path}/${id}`);
  }
}

class FakeFirestore {
  constructor(seed = {}) {
    this.store = new Map(Object.entries(seed));
  }

  collection(path) {
    return new FakeCollectionRef(this, path);
  }

  async runTransaction(handler) {
    return handler(new FakeTransaction(this));
  }

  _set(path, data, options = {}) {
    const existing = this.store.get(path) ?? {};
    this.store.set(path, options.merge ? {...existing, ...data} : {...data});
  }
}

function providerOtpHash(bookingId, otp) {
  return createHash("sha256").update(`${bookingId}:${otp}`).digest("hex");
}

function buildPrivateDoc({bookingId, booking, otp = "482913"}) {
  return {
    schemaVersion: 1,
    bookingId,
    parentId: booking.parentId,
    providerId: booking.providerId,
    parentOtpCode: otp,
    providerOtpHash: providerOtpHash(bookingId, otp),
    otpState: "ACTIVE",
    failedAttemptCount: 0,
    lastFailedAttemptAt: null,
    lockedUntil: null,
    verifiedAt: null,
    successfulAttemptNumber: null,
    lastVerificationAttemptId: "",
    lastVerificationOutcome: "",
    contactUnlockedAt: booking.lifecycle.paidAt,
    createdAt: booking.lifecycle.paidAt,
    updatedAt: booking.lifecycle.paidAt,
  };
}

function buildConfirmedBookingSeed() {
  const bookingId = "booking-start-1";
  const booking = buildConfirmedSlotBookingFixture();
  return {
    bookingId,
    booking,
    privateDoc: buildPrivateDoc({bookingId, booking}),
  };
}

test("correct OTP succeeds before the scheduled start once payment is confirmed", async () => {
  const {bookingId, booking, privateDoc} = buildConfirmedBookingSeed();
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`bookingPrivate/${bookingId}`]: privateDoc,
  });
  const beforeScheduledStart = new Date(
    booking.schedule.scheduledStartAt.getTime() - 60 * 1000,
  );

  const result = await verifyBookingStartOtpV3({
    firestore,
    bookingId,
    providerId: booking.providerId,
    otpCandidate: "482913",
    requestAttemptId: "attempt-1",
    authoritativeNow: beforeScheduledStart,
  });

  assert.equal(result.code, "VERIFIED_STARTED");
  assert.equal(firestore.store.get(`bookings/${bookingId}`).state, "IN_PROGRESS");
});

test("correct OTP is still allowed at the exact authoritative service end", async () => {
  const {bookingId, booking, privateDoc} = buildConfirmedBookingSeed();
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`bookingPrivate/${bookingId}`]: privateDoc,
  });

  const result = await verifyBookingStartOtpV3({
    firestore,
    bookingId,
    providerId: booking.providerId,
    otpCandidate: "482913",
    requestAttemptId: "attempt-2",
    authoritativeNow: booking.schedule.scheduledEndAt,
  });

  assert.equal(result.code, "VERIFIED_STARTED");
});

test("OTP is rejected after authoritative service end by one millisecond", async () => {
  const {bookingId, booking, privateDoc} = buildConfirmedBookingSeed();
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`bookingPrivate/${bookingId}`]: privateDoc,
  });

  const result = await verifyBookingStartOtpV3({
    firestore,
    bookingId,
    providerId: booking.providerId,
    otpCandidate: "482913",
    requestAttemptId: "attempt-3",
    authoritativeNow: new Date(booking.schedule.scheduledEndAt.getTime() + 1),
  });

  assert.equal(result.code, "AFTER_SERVICE_END");
  assert.equal(firestore.store.get(`bookings/${bookingId}`).state, "CONFIRMED");
});

test("overdue confirmed booking finalizes to NO_SHOW exactly once", async () => {
  const {bookingId, booking, privateDoc} = buildConfirmedBookingSeed();
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`bookingPrivate/${bookingId}`]: privateDoc,
  });
  const authoritativeNow = new Date(booking.schedule.scheduledEndAt.getTime() + 1);

  const result = await finalizeCanonicalNoShowV3({
    firestore,
    bookingId,
    authoritativeNow,
  });

  assert.equal(result.code, "FINALIZED_NO_SHOW");
  assert.equal(firestore.store.get(`bookings/${bookingId}`).state, "NO_SHOW");
  assert.equal(firestore.store.has(`bookingNoShows/${bookingId}`), true);
  assert.equal(
    firestore.store.get(`bookingFinancials/${bookingId}`).customerRefundPaise,
    0,
  );
  assert.equal(
    firestore.store.get(`payoutReadiness/${bookingId}`).status,
    "held",
  );
});

test("no-show allocation keeps provider entitlement intact across coupon scenarios", () => {
  const booking = buildConfirmedSlotBookingFixture();

  booking.financials.serviceSubtotalPaise = 100000;
  booking.financials.couponDiscountPaise = 50000;
  booking.financials.customerPaidPaise = 50000;
  booking.financials.pettxoCouponFundingPaise = 50000;
  booking.financials.providerPayoutPaise = 85000;
  booking.financials.platformCommissionPaise = 15000;

  const partialCoupon = calculateCanonicalNoShowAllocationV3({booking});
  assert.equal(partialCoupon.customerRefundPaise, 0);
  assert.equal(partialCoupon.providerCompensationPaise, 85000);
  assert.equal(partialCoupon.pettxoRetainedPaise, 15000);
  assert.equal(partialCoupon.pettxoCouponCostPaise, 50000);

  booking.financials.couponDiscountPaise = 100000;
  booking.financials.customerPaidPaise = 0;
  booking.financials.pettxoCouponFundingPaise = 100000;

  const fullCoupon = calculateCanonicalNoShowAllocationV3({booking});
  assert.equal(fullCoupon.customerRefundPaise, 0);
  assert.equal(fullCoupon.providerCompensationPaise, 85000);
  assert.equal(fullCoupon.pettxoRetainedPaise, 15000);
  assert.equal(fullCoupon.pettxoCouponCostPaise, 100000);
});
