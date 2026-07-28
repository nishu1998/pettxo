const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildAcceptedAwaitingPaymentSlotBookingFixture,
  buildConfirmedSlotBookingFixture,
  buildRequestedSingleSlotBookingFixture,
} = require("../lib/booking/schema/bookingFixtures.js");
const {
  buildCustomerPaymentReminderIfDueV3,
  buildProviderRequestReminderIfDueV3,
  cancelBookingRequestByParentV3,
  declineBookingRequestV3,
  acceptBookingRequestV3,
  expireAwaitingPaymentBookingV3,
  expirePendingProviderBookingV3,
} = require("../lib/booking/application/createBookingRequestV3.js");
const {
  finalizeCanonicalNoShowV3,
  reconcileCanonicalServiceStartArtifactsV3,
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

function buildPendingProviderBooking() {
  const booking = buildRequestedSingleSlotBookingFixture();
  booking.state = "PENDING_PROVIDER";
  booking.stateQueryValue = "PENDING_PROVIDER";
  return booking;
}

function buildAwaitingPaymentBooking() {
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  booking.state = "ACCEPTED_AWAITING_PAYMENT";
  booking.stateQueryValue = "ACCEPTED_AWAITING_PAYMENT";
  return booking;
}

test("halfway reminder sends exactly one provider reminder for actionable requests", () => {
  const booking = buildPendingProviderBooking();
  const result = buildProviderRequestReminderIfDueV3({
    bookingId: "booking-provider-halfway-1",
    booking,
    authoritativeNow: new Date(
      booking.lifecycle.timerStartsAt.getTime() + (30 * 60 * 1000),
    ),
  });

  assert.ok(result);
  assert.equal(result.type, "provider_request_halfway");
  assert.equal(result.recipientUserId, booking.providerId);
  assert.equal(result.data.bookingId, "booking-provider-halfway-1");
});

test("delayed scheduler sends only the ten-minute reminder once the halfway window is obsolete", () => {
  const booking = buildPendingProviderBooking();
  const result = buildProviderRequestReminderIfDueV3({
    bookingId: "booking-provider-ten-minute-1",
    booking,
    authoritativeNow: new Date(booking.acceptDeadlineAt.getTime() - (9 * 60 * 1000)),
  });

  assert.ok(result);
  assert.equal(result.type, "provider_request_ten_minute");
  assert.match(result.body, /9 minutes remain/i);
});

test("provider reminders stop after accept, decline, cancellation, or expiry", () => {
  const booking = buildPendingProviderBooking();
  const reminderAt = new Date(
    booking.lifecycle.timerStartsAt.getTime() + (30 * 60 * 1000),
  );

  const accepted = acceptBookingRequestV3({
    bookingId: "booking-reminder-accept",
    booking,
    providerUid: booking.providerId,
    authoritativeNow: new Date(booking.lifecycle.timerStartsAt.getTime() + (5 * 60 * 1000)),
  });
  assert.equal(
    buildProviderRequestReminderIfDueV3({
      bookingId: "booking-reminder-accept",
      booking: accepted.booking,
      authoritativeNow: reminderAt,
    }),
    null,
  );

  const declined = declineBookingRequestV3({
    bookingId: "booking-reminder-decline",
    booking,
    providerUid: booking.providerId,
    authoritativeNow: new Date(booking.lifecycle.timerStartsAt.getTime() + (5 * 60 * 1000)),
  });
  assert.equal(
    buildProviderRequestReminderIfDueV3({
      bookingId: "booking-reminder-decline",
      booking: declined.booking,
      authoritativeNow: reminderAt,
    }),
    null,
  );

  const cancelled = cancelBookingRequestByParentV3({
    bookingId: "booking-reminder-cancel",
    booking,
    parentUid: booking.parentId,
    authoritativeNow: new Date(booking.lifecycle.timerStartsAt.getTime() + (5 * 60 * 1000)),
  });
  assert.equal(
    buildProviderRequestReminderIfDueV3({
      bookingId: "booking-reminder-cancel",
      booking: cancelled.booking,
      authoritativeNow: reminderAt,
    }),
    null,
  );

  const expired = expirePendingProviderBookingV3({
    bookingId: "booking-reminder-expired",
    booking,
    authoritativeNow: new Date(booking.acceptDeadlineAt.getTime() + 1),
  });
  assert.equal(
    buildProviderRequestReminderIfDueV3({
      bookingId: "booking-reminder-expired",
      booking: expired.booking,
      authoritativeNow: new Date(booking.acceptDeadlineAt.getTime() + 2),
    }),
    null,
  );
});

test("halfway payment reminder sends exactly one customer reminder for actionable unpaid bookings", () => {
  const booking = buildAwaitingPaymentBooking();
  const result = buildCustomerPaymentReminderIfDueV3({
    bookingId: "booking-payment-halfway-1",
    booking,
    authoritativeNow: new Date(
      booking.lifecycle.respondedAt.getTime() + (30 * 60 * 1000),
    ),
  });

  assert.ok(result);
  assert.equal(result.type, "customer_payment_halfway");
  assert.equal(result.recipientUserId, booking.parentId);
  assert.equal(result.data.bookingId, "booking-payment-halfway-1");
});

test("delayed payment reminder catch-up sends only the ten-minute reminder", () => {
  const booking = buildAwaitingPaymentBooking();
  const result = buildCustomerPaymentReminderIfDueV3({
    bookingId: "booking-payment-ten-minute-1",
    booking,
    authoritativeNow: new Date(booking.payDeadlineAt.getTime() - (9 * 60 * 1000)),
  });

  assert.ok(result);
  assert.equal(result.type, "customer_payment_ten_minute");
  assert.match(result.body, /9 minutes remain/i);
});

test("customer payment reminders stop after payment expiry, cancellation, or state changes away from awaiting payment", () => {
  const booking = buildAwaitingPaymentBooking();
  const reminderAt = new Date(
    booking.lifecycle.respondedAt.getTime() + (30 * 60 * 1000),
  );

  const expired = expireAwaitingPaymentBookingV3({
    bookingId: "booking-payment-reminder-expired",
    booking,
    authoritativeNow: new Date(booking.payDeadlineAt.getTime() + 1),
  });
  assert.equal(
    buildCustomerPaymentReminderIfDueV3({
      bookingId: "booking-payment-reminder-expired",
      booking: expired.booking,
      authoritativeNow: new Date(booking.payDeadlineAt.getTime() + 2),
    }),
    null,
  );

  const cancelledByParent = structuredClone(booking);
  cancelledByParent.state = "CANCELLED_BY_PARENT";
  cancelledByParent.stateQueryValue = "CANCELLED_BY_PARENT";
  assert.equal(
    buildCustomerPaymentReminderIfDueV3({
      bookingId: "booking-payment-reminder-cancelled",
      booking: cancelledByParent,
      authoritativeNow: reminderAt,
    }),
    null,
  );

  const confirmed = structuredClone(booking);
  confirmed.state = "CONFIRMED";
  confirmed.stateQueryValue = "CONFIRMED";
  confirmed.lifecycle.paidAt = new Date(
    booking.lifecycle.respondedAt.getTime() + (15 * 60 * 1000),
  );
  assert.equal(
    buildCustomerPaymentReminderIfDueV3({
      bookingId: "booking-payment-reminder-confirmed",
      booking: confirmed,
      authoritativeNow: reminderAt,
    }),
    null,
  );
});

test("customer payment reminders are idempotent across repeated scheduler executions", () => {
  const booking = buildAwaitingPaymentBooking();
  const authoritativeNow = new Date(
    booking.lifecycle.respondedAt.getTime() + (30 * 60 * 1000),
  );

  const first = buildCustomerPaymentReminderIfDueV3({
    bookingId: "booking-payment-idempotent-1",
    booking,
    authoritativeNow,
  });
  const second = buildCustomerPaymentReminderIfDueV3({
    bookingId: "booking-payment-idempotent-1",
    booking,
    authoritativeNow,
  });

  assert.ok(first);
  assert.ok(second);
  assert.equal(first.idempotencyKey, second.idempotencyKey);
  assert.equal(first.type, "customer_payment_halfway");
});

test("provider-response expiry updates an eligible pending provider booking exactly once", () => {
  const booking = buildPendingProviderBooking();
  const authoritativeNow = new Date(booking.acceptDeadlineAt.getTime() + 1);

  const first = expirePendingProviderBookingV3({
    bookingId: "booking-provider-expire-1",
    booking,
    authoritativeNow,
  });

  assert.equal(first.ok, true);
  assert.equal(first.code, "UPDATED");
  assert.equal(first.booking.state, "EXPIRED");
  assert.equal(first.events[0].record.event, "expired");
  assert.equal(first.notifications[0].type, "request_expired");

  const replay = expirePendingProviderBookingV3({
    bookingId: "booking-provider-expire-1",
    booking: first.booking,
    authoritativeNow: new Date(authoritativeNow.getTime() + 60 * 1000),
  });

  assert.equal(replay.ok, true);
  assert.equal(replay.code, "IDEMPOTENT_REPLAY");
  assert.equal(replay.events.length, 0);
  assert.equal(replay.notifications.length, 0);
});

test("provider-response expiry ignores bookings before the authoritative deadline", () => {
  const booking = buildPendingProviderBooking();
  const result = expirePendingProviderBookingV3({
    bookingId: "booking-provider-expire-early",
    booking,
    authoritativeNow: new Date(booking.acceptDeadlineAt.getTime() - 1),
  });

  assert.equal(result.ok, false);
  assert.match(result.message, /before the acceptance deadline/i);
});

test("payment expiry updates an eligible unpaid accepted booking exactly once", () => {
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  const authoritativeNow = new Date(booking.payDeadlineAt.getTime() + 1);

  const first = expireAwaitingPaymentBookingV3({
    bookingId: "booking-payment-expire-1",
    booking,
    authoritativeNow,
  });

  assert.equal(first.ok, true);
  assert.equal(first.code, "UPDATED");
  assert.equal(first.booking.state, "PAYMENT_EXPIRED");
  assert.equal(first.events[0].record.event, "payment_abandoned");
  assert.equal(first.notifications.length > 0, true);

  const replay = expireAwaitingPaymentBookingV3({
    bookingId: "booking-payment-expire-1",
    booking: first.booking,
    authoritativeNow: new Date(authoritativeNow.getTime() + 60 * 1000),
  });

  assert.equal(replay.ok, true);
  assert.equal(replay.code, "IDEMPOTENT_REPLAY");
});

test("payment expiry ignores bookings before the pay deadline and never expires paid bookings", () => {
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  const beforeDeadline = expireAwaitingPaymentBookingV3({
    bookingId: "booking-payment-expire-early",
    booking,
    authoritativeNow: new Date(booking.payDeadlineAt.getTime() - 1),
  });
  assert.equal(beforeDeadline.ok, false);
  assert.match(beforeDeadline.message, /before the payment deadline/i);

  const paidBooking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  paidBooking.lifecycle.paidAt = new Date("2026-07-22T10:40:00.000Z");
  const paid = expireAwaitingPaymentBookingV3({
    bookingId: "booking-payment-paid",
    booking: paidBooking,
    authoritativeNow: new Date(paidBooking.payDeadlineAt.getTime() + 1),
  });
  assert.equal(paid.ok, false);
  assert.match(paid.message, /paid bookings cannot expire/i);
});

test("no-show reconciliation finalizes overdue confirmed bookings and remains harmless on replay", async () => {
  const bookingId = "booking-no-show-scheduler-1";
  const booking = buildConfirmedSlotBookingFixture();
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`bookingPrivate/${bookingId}`]: {
      bookingId,
      parentOtpCode: "123456",
      providerOtpHash: "hash",
      otpState: "ACTIVE",
    },
  });
  const authoritativeNow = new Date(booking.schedule.scheduledEndAt.getTime() + 1);

  const first = await reconcileCanonicalServiceStartArtifactsV3({
    firestore,
    bookingId,
    authoritativeNow,
  });
  const replay = await reconcileCanonicalServiceStartArtifactsV3({
    firestore,
    bookingId,
    authoritativeNow: new Date(authoritativeNow.getTime() + 30 * 60 * 1000),
  });

  assert.equal(first, "NO_SHOW_FINALIZED");
  assert.equal(replay, "NOOP");
  assert.equal(firestore.store.get(`bookings/${bookingId}`).state, "NO_SHOW");
  assert.equal(firestore.store.has(`bookingNoShows/${bookingId}`), true);
});

test("no-show reconciliation repairs missing start artifacts for in-progress bookings", async () => {
  const bookingId = "booking-no-show-repair-1";
  const booking = buildConfirmedSlotBookingFixture();
  booking.state = "IN_PROGRESS";
  booking.stateQueryValue = "IN_PROGRESS";
  booking.lifecycle.otpEnteredAt = new Date("2026-07-23T05:55:00.000Z");
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
    [`bookingPrivate/${bookingId}`]: {
      bookingId,
      parentOtpCode: "123456",
      providerOtpHash: "hash",
      otpState: "ACTIVE",
    },
  });

  const result = await reconcileCanonicalServiceStartArtifactsV3({
    firestore,
    bookingId,
    authoritativeNow: new Date("2026-07-23T06:10:00.000Z"),
  });

  assert.equal(result, "REPAIRED");
  assert.equal(
    firestore.store.get(`bookingPrivate/${bookingId}`).otpState,
    "USED",
  );
  assert.equal(
    firestore.store.has(`bookingServiceStarts/${bookingId}`),
    true,
  );
});

test("direct no-show finalization does not run before service window end or after booking completion", async () => {
  const bookingId = "booking-no-show-guard-1";
  const booking = buildConfirmedSlotBookingFixture();
  const firestore = new FakeFirestore({
    [`bookings/${bookingId}`]: booking,
  });

  const beforeEnd = await finalizeCanonicalNoShowV3({
    firestore,
    bookingId,
    authoritativeNow: new Date(booking.schedule.scheduledEndAt.getTime() - 1),
  });
  assert.equal(beforeEnd.code, "NOT_DUE");

  booking.state = "COMPLETED_PENDING_REVIEW";
  booking.stateQueryValue = "COMPLETED_PENDING_REVIEW";
  firestore.store.set(`bookings/${bookingId}`, booking);
  const completed = await finalizeCanonicalNoShowV3({
    firestore,
    bookingId,
    authoritativeNow: new Date(booking.schedule.scheduledEndAt.getTime() + 1),
  });
  assert.equal(completed.code, "STARTED");
});
