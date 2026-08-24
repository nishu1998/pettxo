const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildConfirmedSlotBookingFixture,
} = require("../lib/booking/schema/bookingFixtures.js");
const {
  completeBookingServiceV3,
  submitBookingReviewV3,
  createBookingDisputeV3,
  finalizeCompletedBookingV3,
  reconcileCanonicalCompletionStateV3,
} = require("../lib/booking/application/serviceCompletionOrchestrationV3.js");

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

function buildInProgressBooking() {
  const booking = buildConfirmedSlotBookingFixture();
  const otpEnteredAt = new Date("2026-07-23T05:50:00.000Z");
  booking.state = "IN_PROGRESS";
  booking.stateQueryValue = "IN_PROGRESS";
  booking.lifecycle.otpEnteredAt = otpEnteredAt;
  booking.lifecycle.serviceEndedAt = null;
  booking.payment.status = "paid";
  return booking;
}

function buildRefundShadowedInProgressBooking() {
  const booking = buildInProgressBooking();
  booking.payment.status = "refunded";
  booking.payment.razorpayRefundId = "rfnd_shadowed";
  return booking;
}

function buildMultiSegmentInProgressBooking() {
  const booking = buildInProgressBooking();
  const firstStart = new Date("2026-07-23T06:00:00.000Z");
  const firstEnd = new Date("2026-07-23T07:00:00.000Z");
  const secondStart = new Date("2026-07-24T08:00:00.000Z");
  const secondEnd = new Date("2026-07-24T09:00:00.000Z");
  booking.schedule.slots = [
    {
      ...booking.schedule.slots[0],
      slotId: "slot-1",
      dateKey: "2026-07-23",
      serviceDateKey: "2026-07-23",
      startAt: firstStart,
      endAt: firstEnd,
      schedulingMode: "fixedDuration",
    },
    {
      ...booking.schedule.slots[0],
      slotId: "slot-2",
      dateKey: "2026-07-24",
      serviceDateKey: "2026-07-24",
      startAt: secondStart,
      endAt: secondEnd,
      schedulingMode: "fixedDuration",
    },
  ];
  booking.schedule.slotCount = 2;
  booking.schedule.scheduledStartAt = firstStart;
  booking.schedule.scheduledEndAt = secondEnd;
  booking.schedule.totalDurationMinutes = 120;
  booking.schedule.segments = [
    {
      serviceDateKey: "2026-07-23",
      startAt: firstStart,
      endAt: firstEnd,
      slotIds: ["slot-1"],
      durationMinutes: 60,
      schedulingMode: "fixedDuration",
    },
    {
      serviceDateKey: "2026-07-24",
      startAt: secondStart,
      endAt: secondEnd,
      slotIds: ["slot-2"],
      durationMinutes: 60,
      schedulingMode: "fixedDuration",
    },
  ];
  booking.schedule.firstSegmentEndAt = firstEnd;
  booking.schedule.finalEndAt = secondEnd;
  booking.schedule.serviceDayCount = 2;
  booking.schedule.segmentCount = 2;
  booking.service.selectedSlotCount = 2;
  booking.service.totalDurationMinutes = 120;
  booking.statistics.selectedSlotCount = 2;
  booking.statistics.totalDurationMinutes = 120;
  return booking;
}

function assertNoLiteralDottedKeys(value, path = "") {
  if (Array.isArray(value)) {
    value.forEach((entry, index) =>
      assertNoLiteralDottedKeys(entry, `${path}[${index}]`),
    );
    return;
  }
  if (value == null || typeof value !== "object") return;

  for (const [key, nested] of Object.entries(value)) {
    assert.equal(
      key.includes("."),
      false,
      `unexpected dotted key at ${path || "<root>"}: ${key}`,
    );
    const nextPath = path ? `${path}.${key}` : key;
    assertNoLiteralDottedKeys(nested, nextPath);
  }
}

function assertNoDottedBookingMutationFields(storedBooking) {
  assert.equal(Object.prototype.hasOwnProperty.call(storedBooking, "dispute.status"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(storedBooking, "dispute.reasonCode"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(storedBooking, "payout.status"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(storedBooking, "audit.lastUpdatedBy"), false);
}

test("provider completion moves IN_PROGRESS booking into COMPLETED_PENDING_REVIEW and writes payout hold docs", async () => {
  const bookingId = "booking-complete-1";
  const booking = buildInProgressBooking();
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
  });

  const result = await completeBookingServiceV3({
    firestore,
    bookingId,
    providerUid: booking.providerId,
    authoritativeNow: new Date(booking.schedule.scheduledEndAt.getTime() + 5 * 60 * 1000),
  });

  assert.equal(result.code, "COMPLETED_PENDING_REVIEW");
  const storedBooking = firestore.store.get(`bookings/${bookingId}`);
  assert.equal(storedBooking.state, "COMPLETED_PENDING_REVIEW");
  assert.ok(storedBooking.lifecycle.completedAt);
  assert.ok(storedBooking.lifecycle.serviceEndedAt);
  assert.ok(storedBooking.lifecycle.reviewWindowEndsAt);
  assert.ok(storedBooking.lifecycle.disputeDeadlineAt);
  assert.equal(storedBooking.payout.status, "HELD");
  assert.ok(storedBooking.payout.eligibleAt);
  assert.equal(
    storedBooking.payout.providerPayoutPaise,
    booking.financials.providerPayoutPaise,
  );
  assert.equal(storedBooking.privacy.otpVisibleToParent, false);
  assert.equal(
    storedBooking.completion.policyVersion,
    "v3.2_slice8",
  );
  assert.equal(
    storedBooking.completion.reasonCode,
    "provider_marked_complete",
  );
  assert.equal(storedBooking.audit.lastUpdatedBy, "provider");
  assertNoLiteralDottedKeys(storedBooking);
  assert.equal(firestore.store.get(`payoutReadiness/${bookingId}`).status, "HELD");
  assert.equal(
    firestore.store.get(`bookings/${bookingId}/events/service_completed`).event,
    "service_completed",
  );
});

test("provider completion still succeeds when refund mirroring overwrote display payment status", async () => {
  const bookingId = "booking-complete-refund-shadow";
  const booking = buildRefundShadowedInProgressBooking();
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
  });

  const result = await completeBookingServiceV3({
    firestore,
    bookingId,
    providerUid: booking.providerId,
    authoritativeNow: new Date(booking.schedule.scheduledEndAt.getTime() + 5 * 60 * 1000),
  });

  assert.equal(result.code, "COMPLETED_PENDING_REVIEW");
  assert.equal(
    firestore.store.get(`bookings/${bookingId}`).state,
    "COMPLETED_PENDING_REVIEW",
  );
});

test("provider completion is rejected before the single-slot service end", async () => {
  const bookingId = "booking-complete-too-early";
  const booking = buildInProgressBooking();
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
  });

  const result = await completeBookingServiceV3({
    firestore,
    bookingId,
    providerUid: booking.providerId,
    authoritativeNow: new Date(booking.schedule.scheduledEndAt.getTime() - 1),
  });

  assert.equal(result.code, "BOOKING_SERVICE_NOT_ENDED");
  assert.equal(firestore.store.get(`bookings/${bookingId}`).state, "IN_PROGRESS");
});

test("provider completion is rejected after the first segment but before the final segment ends", async () => {
  const bookingId = "booking-complete-multiday-too-early";
  const booking = buildMultiSegmentInProgressBooking();
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
  });

  const result = await completeBookingServiceV3({
    firestore,
    bookingId,
    providerUid: booking.providerId,
    authoritativeNow: new Date(booking.schedule.firstSegmentEndAt.getTime() + 15 * 60 * 1000),
  });

  assert.equal(result.code, "BOOKING_SERVICE_NOT_ENDED");
  assert.equal(firestore.store.get(`bookings/${bookingId}`).state, "IN_PROGRESS");
});

test("provider completion succeeds once the final segment ends for a multi-day booking", async () => {
  const bookingId = "booking-complete-multiday-success";
  const booking = buildMultiSegmentInProgressBooking();
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
  });

  const result = await completeBookingServiceV3({
    firestore,
    bookingId,
    providerUid: booking.providerId,
    authoritativeNow: new Date(booking.schedule.finalEndAt.getTime() + 1),
  });

  assert.equal(result.code, "COMPLETED_PENDING_REVIEW");
  assert.equal(firestore.store.get(`bookings/${bookingId}`).state, "COMPLETED_PENDING_REVIEW");
});

test("completion reconciliation repairs stale started bookings after the authoritative service end", async () => {
  const bookingId = "booking-complete-reconcile-1";
  const booking = buildInProgressBooking();
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
  });

  const result = await reconcileCanonicalCompletionStateV3({
    firestore,
    bookingId,
    authoritativeNow: new Date(booking.schedule.scheduledEndAt.getTime() + 5 * 60 * 1000),
  });

  assert.equal(result, "AUTO_COMPLETED_PENDING_REVIEW");
  assert.equal(
    firestore.store.get(`bookings/${bookingId}`).state,
    "COMPLETED_PENDING_REVIEW",
  );
  assert.equal(
    firestore.store.get(`bookings/${bookingId}`).completion.reasonCode,
    "system_auto_completed_after_service_end",
  );
  assert.equal(
    firestore.store.get(`bookings/${bookingId}`).audit.lastUpdatedBy,
    "system",
  );
});

test("completion reconciliation leaves in-progress booking unchanged before service end", async () => {
  const bookingId = "booking-complete-reconcile-early-1";
  const booking = buildInProgressBooking();
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
  });

  const result = await reconcileCanonicalCompletionStateV3({
    firestore,
    bookingId,
    authoritativeNow: new Date(booking.schedule.scheduledEndAt.getTime() - 1),
  });

  assert.equal(result, "NOOP");
  assert.equal(firestore.store.get(`bookings/${bookingId}`).state, "IN_PROGRESS");
});

test("completion reconciliation leaves multi-day in-progress booking active until the final segment ends", async () => {
  const bookingId = "booking-complete-reconcile-multiday-1";
  const booking = buildMultiSegmentInProgressBooking();
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
  });

  const result = await reconcileCanonicalCompletionStateV3({
    firestore,
    bookingId,
    authoritativeNow: new Date(booking.schedule.firstSegmentEndAt.getTime() + 15 * 60 * 1000),
  });

  assert.equal(result, "NOOP");
  assert.equal(firestore.store.get(`bookings/${bookingId}`).state, "IN_PROGRESS");
});

test("review submission is idempotent and updates the service review document once", async () => {
  const bookingId = "booking-review-1";
  const booking = buildInProgressBooking();
  booking.state = "COMPLETED_PENDING_REVIEW";
  booking.stateQueryValue = "COMPLETED_PENDING_REVIEW";
  booking.lifecycle.completedAt = new Date("2026-07-23T06:10:00.000Z");
  booking.lifecycle.reviewWindowEndsAt = new Date("2026-07-24T06:10:00.000Z");
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`services/${booking.serviceId}`]: {stats: {}, ratingAverage: 0, ratingCount: 0},
    [`users/${booking.providerId}`]: {ratingAverage: 0, ratingCount: 0},
  });

  const first = await submitBookingReviewV3({
    firestore,
    bookingId,
    parentUid: booking.parentId,
    rating: 5,
    comment: "Excellent service",
    tags: [],
    authoritativeNow: new Date("2026-07-23T07:00:00.000Z"),
  });
  const second = await submitBookingReviewV3({
    firestore,
    bookingId,
    parentUid: booking.parentId,
    rating: 5,
    comment: "Excellent service",
    tags: [],
    authoritativeNow: new Date("2026-07-23T07:05:00.000Z"),
  });

  assert.equal(first.code, "REVIEW_SUBMITTED");
  assert.equal(second.code, "ALREADY_REVIEWED");
  const storedReview = firestore.store.get(`services/${booking.serviceId}/reviews/${bookingId}`);
  const storedBooking = firestore.store.get(`bookings/${bookingId}`);
  const storedService = firestore.store.get(`services/${booking.serviceId}`);
  const storedProvider = firestore.store.get(`users/${booking.providerId}`);
  assert.equal(storedReview.rating, 5);
  assert.equal(storedBooking.reviewStatus, "submitted");
  assert.equal(storedBooking.review.reviewId, bookingId);
  assert.equal(storedBooking.review.status, "submitted");
  assert.equal(storedBooking.audit.lastUpdatedBy, "parent");
  assert.equal(Object.prototype.hasOwnProperty.call(storedBooking, "audit.lastUpdatedBy"), false);
  assert.equal(storedService.ratingCount, 1);
  assert.equal(storedProvider.ratingCount, 1);
  assert.equal(storedService.reviewedBookingCount, 1);
  assert.equal(storedProvider.reviewedBookingCount, 1);
});

test("review submission still succeeds after the dispute deadline expires", async () => {
  const bookingId = "booking-review-late-1";
  const booking = buildInProgressBooking();
  booking.state = "COMPLETED_PENDING_REVIEW";
  booking.stateQueryValue = "COMPLETED_PENDING_REVIEW";
  booking.completedAt = new Date("2026-07-23T06:10:00.000Z");
  booking.lifecycle.completedAt = new Date("2026-07-23T06:10:00.000Z");
  booking.lifecycle.reviewWindowEndsAt = new Date("2026-07-24T06:10:00.000Z");
  booking.lifecycle.disputeDeadlineAt = new Date("2026-07-24T06:10:00.000Z");
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`services/${booking.serviceId}`]: {stats: {}, ratingAverage: 0, ratingCount: 0},
    [`users/${booking.providerId}`]: {ratingAverage: 0, ratingCount: 0},
  });

  const result = await submitBookingReviewV3({
    firestore,
    bookingId,
    parentUid: booking.parentId,
    rating: 4,
    comment: "Still reviewing after the dispute window.",
    tags: [],
    authoritativeNow: new Date("2026-07-25T07:00:00.000Z"),
  });

  assert.equal(result.code, "REVIEW_SUBMITTED");
  assert.equal(
    firestore.store.get(`services/${booking.serviceId}/reviews/${bookingId}`).rating,
    4,
  );
});

test("review submission accepts historical completed booking when nested lifecycle.completedAt is stale", async () => {
  const bookingId = "booking-review-legacy-1";
  const booking = buildInProgressBooking();
  booking.state = "COMPLETED_FINAL";
  booking.stateQueryValue = "COMPLETED_FINAL";
  booking.completedAt = new Date("2026-07-23T06:10:00.000Z");
  booking.lifecycle.completedAt = null;
  booking.lifecycle.reviewWindowEndsAt = new Date("2026-07-24T06:10:00.000Z");
  booking.lifecycle.disputeDeadlineAt = new Date("2026-07-24T06:10:00.000Z");
  booking["lifecycle.completedAt"] = new Date("2026-07-23T06:10:00.000Z");
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`services/${booking.serviceId}`]: {stats: {}, ratingAverage: 0, ratingCount: 0},
    [`users/${booking.providerId}`]: {ratingAverage: 0, ratingCount: 0},
  });

  const result = await submitBookingReviewV3({
    firestore,
    bookingId,
    parentUid: booking.parentId,
    rating: 5,
    comment: "Legacy completed booking review",
    tags: [],
    authoritativeNow: new Date("2026-07-26T07:00:00.000Z"),
  });

  assert.equal(result.code, "REVIEW_SUBMITTED");
});

test("review submission rejects active bookings before completion", async () => {
  const bookingId = "booking-review-active-1";
  const booking = buildInProgressBooking();
  booking.state = "IN_PROGRESS";
  booking.stateQueryValue = "IN_PROGRESS";
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`services/${booking.serviceId}`]: {stats: {}, ratingAverage: 0, ratingCount: 0},
    [`users/${booking.providerId}`]: {ratingAverage: 0, ratingCount: 0},
  });

  const result = await submitBookingReviewV3({
    firestore,
    bookingId,
    parentUid: booking.parentId,
    rating: 5,
    comment: "Should fail before completion",
    tags: [],
    authoritativeNow: new Date("2026-07-23T07:00:00.000Z"),
  });

  assert.equal(result.code, "INVALID_STATE");
});

test("review submission rejects the wrong user safely", async () => {
  const bookingId = "booking-review-wrong-user-1";
  const booking = buildInProgressBooking();
  booking.state = "COMPLETED_PENDING_REVIEW";
  booking.stateQueryValue = "COMPLETED_PENDING_REVIEW";
  booking.completedAt = new Date("2026-07-23T06:10:00.000Z");
  booking.lifecycle.completedAt = new Date("2026-07-23T06:10:00.000Z");
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`services/${booking.serviceId}`]: {stats: {}, ratingAverage: 0, ratingCount: 0},
    [`users/${booking.providerId}`]: {ratingAverage: 0, ratingCount: 0},
  });

  const result = await submitBookingReviewV3({
    firestore,
    bookingId,
    parentUid: "someone-else",
    rating: 5,
    comment: "Wrong user",
    tags: [],
    authoritativeNow: new Date("2026-07-23T07:00:00.000Z"),
  });

  assert.equal(result.code, "UNAUTHORIZED");
});

test("open dispute blocks canonical finalization", async () => {
  const bookingId = "booking-dispute-1";
  const booking = buildInProgressBooking();
  booking.state = "COMPLETED_PENDING_REVIEW";
  booking.stateQueryValue = "COMPLETED_PENDING_REVIEW";
  booking.lifecycle.completedAt = new Date("2026-07-23T06:10:00.000Z");
  booking.lifecycle.reviewWindowEndsAt = new Date("2026-07-24T06:10:00.000Z");
  booking.dispute.status = "OPEN";
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
  });

  const result = await finalizeCompletedBookingV3({
    firestore,
    bookingId,
    authoritativeNow: new Date("2026-07-24T06:11:00.000Z"),
  });

  assert.equal(result.code, "DISPUTE_OPEN");
  assert.equal(firestore.store.get(`bookings/${bookingId}`).state, "COMPLETED_PENDING_REVIEW");
});

test("completed pending review booking finalizes exactly once when the review window expires without dispute", async () => {
  const bookingId = "booking-finalize-1";
  const booking = buildInProgressBooking();
  booking.state = "COMPLETED_PENDING_REVIEW";
  booking.stateQueryValue = "COMPLETED_PENDING_REVIEW";
  booking.lifecycle.completedAt = new Date("2026-07-23T06:10:00.000Z");
  booking.lifecycle.reviewWindowEndsAt = new Date("2026-07-24T06:10:00.000Z");
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`bookingFinancials/${bookingId}`]: {},
    [`providerEarnings/${bookingId}`]: {},
    [`payoutReadiness/${bookingId}`]: {},
  });

  const result = await finalizeCompletedBookingV3({
    firestore,
    bookingId,
    authoritativeNow: new Date("2026-07-24T06:11:00.000Z"),
  });

  assert.equal(result.code, "FINALIZED");
  assert.equal(firestore.store.get(`bookings/${bookingId}`).state, "COMPLETED_FINAL");
  assert.equal(firestore.store.get(`payoutReadiness/${bookingId}`).status, "READY");
  assert.equal(
    firestore.store.get(`bookings/${bookingId}/events/booking_finalized`).event,
    "booking_finalized",
  );
  assert.equal(
    firestore.store.get(`bookings/${bookingId}/events/payout_ready`).event,
    "payout_ready",
  );
});

test("customer dispute creation marks payout hold and stays in COMPLETED_PENDING_REVIEW", async () => {
  const bookingId = "booking-dispute-create-1";
  const booking = buildInProgressBooking();
  booking.state = "COMPLETED_PENDING_REVIEW";
  booking.stateQueryValue = "COMPLETED_PENDING_REVIEW";
  booking.lifecycle.completedAt = new Date("2026-07-23T06:10:00.000Z");
  booking.lifecycle.reviewWindowEndsAt = new Date("2026-07-24T06:10:00.000Z");
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`bookingFinancials/${bookingId}`]: {},
    [`providerEarnings/${bookingId}`]: {},
    [`payoutReadiness/${bookingId}`]: {},
  });

  const result = await createBookingDisputeV3({
    firestore,
    bookingId,
    parentUid: booking.parentId,
    reason: "provider_unavailable",
    description: "The provider did not show up.",
    attachments: [],
    authoritativeNow: new Date("2026-07-23T07:00:00.000Z"),
  });

  assert.equal(result.code, "DISPUTE_CREATED");
  const storedBooking = firestore.store.get(`bookings/${bookingId}`);
  assert.equal(storedBooking.state, "COMPLETED_PENDING_REVIEW");
  assert.equal(storedBooking.dispute.status, "OPEN");
  assert.equal(storedBooking.dispute.reasonCode, "provider_unavailable");
  assert.equal(storedBooking.payout.status, "HELD");
  assert.equal(storedBooking.audit.lastUpdatedBy, "parent");
  assertNoLiteralDottedKeys(storedBooking);
  assert.equal(firestore.store.get(`payoutReadiness/${bookingId}`).status, "HELD");
});

test("customer dispute creation is rejected after the dispute deadline expires", async () => {
  const bookingId = "booking-dispute-expired-1";
  const booking = buildInProgressBooking();
  booking.state = "COMPLETED_PENDING_REVIEW";
  booking.stateQueryValue = "COMPLETED_PENDING_REVIEW";
  booking.lifecycle.completedAt = new Date("2026-07-23T06:10:00.000Z");
  booking.lifecycle.reviewWindowEndsAt = new Date("2026-07-24T06:10:00.000Z");
  booking.lifecycle.disputeDeadlineAt = new Date("2026-07-24T06:10:00.000Z");
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`bookingFinancials/${bookingId}`]: {},
    [`providerEarnings/${bookingId}`]: {},
    [`payoutReadiness/${bookingId}`]: {},
  });

  const result = await createBookingDisputeV3({
    firestore,
    bookingId,
    parentUid: booking.parentId,
    reason: "late-dispute",
    description: "The dispute window already expired.",
    attachments: [],
    authoritativeNow: new Date("2026-07-25T07:00:00.000Z"),
  });

  assert.equal(result.code, "WINDOW_EXPIRED");
});

test("customer dispute creation accepts historical dotted dispute deadline data", async () => {
  const bookingId = "booking-dispute-legacy-deadline-1";
  const booking = buildInProgressBooking();
  booking.state = "COMPLETED_PENDING_REVIEW";
  booking.stateQueryValue = "COMPLETED_PENDING_REVIEW";
  booking.completedAt = new Date("2026-07-23T06:10:00.000Z");
  booking.lifecycle.completedAt = new Date("2026-07-23T06:10:00.000Z");
  booking.lifecycle.disputeDeadlineAt = null;
  booking.lifecycle.reviewWindowEndsAt = null;
  booking["lifecycle.disputeDeadlineAt"] = new Date("2026-07-24T06:10:00.000Z");
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`bookingFinancials/${bookingId}`]: {},
    [`providerEarnings/${bookingId}`]: {},
    [`payoutReadiness/${bookingId}`]: {},
  });

  const result = await createBookingDisputeV3({
    firestore,
    bookingId,
    parentUid: booking.parentId,
    reason: "legacy-window",
    description: "Historical dotted deadline should still allow disputes.",
    attachments: [],
    authoritativeNow: new Date("2026-07-23T07:00:00.000Z"),
  });

  assert.equal(result.code, "DISPUTE_CREATED");
  const storedBooking = firestore.store.get(`bookings/${bookingId}`);
  assert.equal(storedBooking.dispute.status, "OPEN");
  assert.equal(storedBooking.payout.status, "HELD");
  assertNoDottedBookingMutationFields(storedBooking);
});

test("customer dispute creation falls back to review window when dispute deadline is missing", async () => {
  const bookingId = "booking-dispute-review-window-fallback-1";
  const booking = buildInProgressBooking();
  booking.state = "COMPLETED_PENDING_REVIEW";
  booking.stateQueryValue = "COMPLETED_PENDING_REVIEW";
  booking.completedAt = new Date("2026-07-23T06:10:00.000Z");
  booking.lifecycle.completedAt = new Date("2026-07-23T06:10:00.000Z");
  booking.lifecycle.disputeDeadlineAt = null;
  booking.lifecycle.reviewWindowEndsAt = null;
  booking["lifecycle.reviewWindowEndsAt"] = new Date("2026-07-24T06:10:00.000Z");
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`bookingFinancials/${bookingId}`]: {},
    [`providerEarnings/${bookingId}`]: {},
    [`payoutReadiness/${bookingId}`]: {},
  });

  const result = await createBookingDisputeV3({
    firestore,
    bookingId,
    parentUid: booking.parentId,
    reason: "fallback-window",
    description: "Review window fallback should preserve historical eligibility.",
    attachments: [],
    authoritativeNow: new Date("2026-07-23T07:00:00.000Z"),
  });

  assert.equal(result.code, "DISPUTE_CREATED");
  const storedBooking = firestore.store.get(`bookings/${bookingId}`);
  assert.equal(storedBooking.dispute.status, "OPEN");
  assertNoDottedBookingMutationFields(storedBooking);
});

test("customer dispute creation returns ALREADY_DISPUTED when an active dispute already exists", async () => {
  const bookingId = "booking-dispute-duplicate-1";
  const booking = buildInProgressBooking();
  booking.state = "COMPLETED_PENDING_REVIEW";
  booking.stateQueryValue = "COMPLETED_PENDING_REVIEW";
  booking.lifecycle.completedAt = new Date("2026-07-23T06:10:00.000Z");
  booking.lifecycle.reviewWindowEndsAt = new Date("2026-07-24T06:10:00.000Z");
  booking.lifecycle.disputeDeadlineAt = new Date("2026-07-24T06:10:00.000Z");
  booking.dispute = {
    ...booking.dispute,
    status: "OPEN",
  };
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`bookingFinancials/${bookingId}`]: {},
    [`providerEarnings/${bookingId}`]: {},
    [`payoutReadiness/${bookingId}`]: {},
    [`bookingCompletionDisputes/${bookingId}`]: {
      bookingId,
      status: "OPEN",
    },
  });

  const result = await createBookingDisputeV3({
    firestore,
    bookingId,
    parentUid: booking.parentId,
    reason: "provider_unavailable",
    description: "Duplicate dispute should be rejected safely.",
    attachments: [],
    authoritativeNow: new Date("2026-07-23T07:00:00.000Z"),
  });

  assert.equal(result.code, "ALREADY_DISPUTED");
});
