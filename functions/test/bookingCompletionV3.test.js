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
    authoritativeNow: new Date("2026-07-23T06:10:00.000Z"),
  });

  assert.equal(result.code, "COMPLETED_PENDING_REVIEW");
  assert.equal(firestore.store.get(`bookings/${bookingId}`).state, "COMPLETED_PENDING_REVIEW");
  assert.equal(firestore.store.get(`payoutReadiness/${bookingId}`).status, "HELD");
  assert.equal(
    firestore.store.get(`bookings/${bookingId}/events/service_completed`).event,
    "service_completed",
  );
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
  assert.equal(
    firestore.store.get(`services/${booking.serviceId}/reviews/${bookingId}`).rating,
    5,
  );
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
  assert.equal(firestore.store.get(`bookings/${bookingId}`).state, "COMPLETED_PENDING_REVIEW");
  assert.equal(firestore.store.get(`bookings/${bookingId}`)["dispute.status"], "OPEN");
  assert.equal(firestore.store.get(`payoutReadiness/${bookingId}`).status, "HELD");
});
