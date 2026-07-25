const assert = require("node:assert/strict");

const {
  buildCanonicalPaymentRaceFixture,
  assertNoPrivateLeakage,
} = require("./canonicalPaymentRaceFixture.js");
const {
  finalizeCapturedBookingPaymentV3,
  persistFinalizePaymentResultV3,
  reconcilePaymentAttemptsV3,
  submitRefundInstructionV3,
} = require("../../lib/booking/application/paymentOrchestrationV3.js");
const {
  routeCanonicalWebhookEventV3,
} = require("../../lib/booking/application/canonicalPaymentWebhookV3.js");
const {
  processRazorpayWebhookEnvelopeV3,
} = require("../../lib/booking/application/paymentWebhookEventsV3.js");
const {
  expireAwaitingPaymentBookingV3,
} = require("../../lib/booking/application/createBookingRequestV3.js");
const razorpayGateway = require("../../lib/booking/application/razorpayGateway.js");

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

class FakeQuerySnapshot {
  constructor(docs) {
    this.docs = docs;
    this.empty = docs.length === 0;
  }
}

class FakeBatch {
  constructor(firestore) {
    this.firestore = firestore;
    this.operations = [];
  }

  set(ref, data, options) {
    this.operations.push(() => this.firestore._set(ref.path, data, options));
  }

  async commit() {
    for (const operation of this.operations) {
      operation();
    }
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

  get parent() {
    const collectionPath = this.path.split("/").slice(0, -1).join("/");
    return new FakeCollectionRef(this.firestore, collectionPath);
  }

  async get() {
    return new FakeDocSnapshot(
      this.firestore,
      this.path,
      this.firestore.store.get(this.path),
    );
  }

  async set(data, options) {
    this.firestore._set(this.path, data, options);
  }
}

class FakeQuery {
  constructor(firestore, docs) {
    this.firestore = firestore;
    this.docs = docs;
    this.filters = [];
    this.max = null;
  }

  where(field, op, value) {
    this.filters.push({field, op, value});
    return this;
  }

  limit(max) {
    this.max = max;
    return this;
  }

  async get() {
    let docs = this.docs;
    for (const filter of this.filters) {
      docs = docs.filter((doc) => {
        const data = doc.data() ?? {};
        if (filter.op === "in") {
          return filter.value.includes(data[filter.field]);
        }
        if (filter.op === "==") {
          return data[filter.field] === filter.value;
        }
        return false;
      });
    }
    if (this.max != null) {
      docs = docs.slice(0, this.max);
    }
    return new FakeQuerySnapshot(docs);
  }
}

class FakeCollectionRef {
  constructor(firestore, path) {
    this.firestore = firestore;
    this.path = path;
    this.id = path.split("/").pop();
  }

  doc(id) {
    return new FakeDocRef(this.firestore, `${this.path}/${id}`);
  }

  where(field, op, value) {
    return new FakeQuery(this.firestore, this.firestore._docsForCollection(this.path))
      .where(field, op, value);
  }

  limit(max) {
    return new FakeQuery(this.firestore, this.firestore._docsForCollection(this.path))
      .limit(max);
  }

  async get() {
    return new FakeQuerySnapshot(this.firestore._docsForCollection(this.path));
  }
}

class FakeFirestore {
  constructor(seed = {}) {
    this.store = new Map(Object.entries(seed));
  }

  doc(path) {
    return new FakeDocRef(this, path);
  }

  collection(path) {
    return new FakeCollectionRef(this, path);
  }

  collectionGroup(name) {
    return new FakeQuery(this, this._docsForCollectionGroup(name));
  }

  batch() {
    return new FakeBatch(this);
  }

  async runTransaction(handler) {
    return handler(new FakeTransaction(this));
  }

  _docsForCollection(path) {
    const targetSegments = path.split("/").length + 1;
    return [...this.store.entries()]
      .filter(([entryPath]) =>
        entryPath.startsWith(`${path}/`) &&
        entryPath.split("/").length === targetSegments)
      .map(([entryPath, data]) => new FakeDocSnapshot(this, entryPath, data));
  }

  _docsForCollectionGroup(name) {
    return [...this.store.entries()]
      .filter(([entryPath]) => {
        const segments = entryPath.split("/");
        return segments.length >= 2 && segments[segments.length - 2] === name;
      })
      .map(([entryPath, data]) => new FakeDocSnapshot(this, entryPath, data));
  }

  _set(path, data, options = {}) {
    const existing = this.store.get(path) ?? {};
    this.store.set(path, options.merge ? {...existing, ...data} : {...data});
  }
}

function persistNotifications(firestore, notifications, actorId) {
  for (const notification of notifications) {
    firestore._set(`notifications/${notification.idempotencyKey}`, {
      userId: notification.recipientUserId,
      category: "booking",
      type: notification.type,
      title: notification.title,
      body: notification.body,
      read: false,
      isRead: false,
      actorId,
      bookingId: notification.data.bookingId ?? "",
      serviceId: notification.data.serviceId ?? "",
      data: notification.data,
      source: "canonical_v3",
    }, {merge: true});
  }
}

function createRaceFixture(options = {}) {
  let refundGatewayOutcome = options.refundGatewayOutcome;
  const base = buildCanonicalPaymentRaceFixture({
    ids: {
      bookingId: "booking-race-v3",
      paymentAttemptId: "payment-attempt-race-v3",
      razorpayOrderId: "order-race-v3",
      razorpayPaymentId: "payment-race-v3",
      webhookEventId: "webhook-race-a",
      refundInstructionId: "refund-booking-race-v3",
    },
  });

  if (options.zeroPayable) {
    base.paymentAttempt.amountPaise = 0;
    base.razorpayPayment.amountPaise = 0;
    base.booking.financials.customerPaidPaise = 0;
    base.booking.financials.couponDiscountPaise =
      base.booking.financials.serviceSubtotalPaise;
  }
  if (options.capacityAvailable === false) {
    base.slotOccupancy = {
      "slot-1": {
        slotId: "slot-1",
        confirmedUnits: 1,
        capacitySnapshot: 1,
        bookingClaims: {},
      },
    };
  }
  if (options.captureTimestamp) {
    base.razorpayPayment.createdAt = options.captureTimestamp;
    base.razorpayPayment.capturedAt = options.captureTimestamp;
    base.authoritativeNow = new Date(options.captureTimestamp.getTime() + 5000);
  }
  if (options.payDeadlineAt) {
    base.booking.lifecycle.payDeadlineAt = options.payDeadlineAt;
    base.booking.payDeadlineAt = options.payDeadlineAt;
    base.paymentAttempt.orderExpiresAt = options.payDeadlineAt;
  }

  const firestore = new FakeFirestore({
    [`bookings/${base.ids.bookingId}`]: {
      ...base.booking,
      bookingId: base.ids.bookingId,
      serviceId: base.booking.serviceId,
    },
    [`bookings/${base.ids.bookingId}/paymentAttempts/${base.ids.paymentAttemptId}`]:
      {
        ...base.paymentAttempt,
        bookingId: base.ids.bookingId,
      },
    [`canonicalPaymentOrderMappings/${base.ids.razorpayOrderId}`]: {
      bookingId: base.ids.bookingId,
      paymentAttemptId: base.ids.paymentAttemptId,
      schemaVersion: 1,
    },
  });

  async function runCallable({source = "callable", simulateTimeoutAfterCommit = false} = {}) {
    const booking =
      firestore.store.get(`bookings/${base.ids.bookingId}`) ?? base.booking;
    const paymentAttempt =
      firestore.store.get(
        `bookings/${base.ids.bookingId}/paymentAttempts/${base.ids.paymentAttemptId}`,
      ) ?? base.paymentAttempt;

    const result = finalizeCapturedBookingPaymentV3({
      bookingId: base.ids.bookingId,
      booking,
      paymentAttempt,
      parent: base.parent,
      service: base.service,
      existingBookingPrivate:
        firestore.store.get(`bookingPrivate/${base.ids.bookingId}`) ?? null,
      slotOccupancy: base.slotOccupancy,
      rangeOccupancy: base.rangeOccupancy,
      razorpayPayment: options.zeroPayable ? null : {
        ...base.razorpayPayment,
      },
      authoritativeNow: base.authoritativeNow,
      verificationSource: source,
    });
    await persistFinalizePaymentResultV3({
      firestore,
      result,
      bookingId: base.ids.bookingId,
    });
    persistNotifications(firestore, result.notifications, source);
    if (simulateTimeoutAfterCommit) {
      const error = new Error("simulated timeout after commit");
      error.code = "TIMEOUT_AFTER_COMMIT";
      throw error;
    }
    return result;
  }

  async function runWebhook({
    eventId = "webhook-race-a",
    mode = "direct",
    failBeforeFinalize = false,
  } = {}) {
    const finalizeCapturedPayment = async () => {
      if (failBeforeFinalize) {
        throw new Error("temporary webhook failure");
      }
      return runCallable({source: "webhook"});
    };

    if (mode === "envelope") {
      return processRazorpayWebhookEnvelopeV3({
        firestore,
        rawBody: Buffer.from("{}"),
        signature: "valid",
        webhookSecret: "secret",
        payload: {
          event: "payment.captured",
          payload: {
            payment: {
              entity: {
                id: base.ids.razorpayPaymentId,
                order_id: base.ids.razorpayOrderId,
                amount: base.razorpayPayment.amountPaise,
                currency: base.razorpayPayment.currency,
              },
            },
            refund: {entity: {}},
          },
        },
        verifySignature: () => true,
        routeCanonicalWebhook: (params) =>
          routeCanonicalWebhookEventV3({
            ...params,
            deps: {
              fetchRazorpayPayment: async () => ({
                ...base.razorpayPayment,
              }),
              finalizeCapturedPayment,
            },
          }),
        keyId: "key",
        keySecret: "secret",
        authoritativeNow: base.authoritativeNow,
      });
    }

    return routeCanonicalWebhookEventV3({
      firestore,
      eventId,
      eventName: "payment.captured",
      paymentEntity: {
        id: base.ids.razorpayPaymentId,
        order_id: base.ids.razorpayOrderId,
        amount: base.razorpayPayment.amountPaise,
        currency: base.razorpayPayment.currency,
      },
      refundEntity: {},
      keyId: "key",
      keySecret: "secret",
      authoritativeNow: base.authoritativeNow,
      deps: {
        fetchRazorpayPayment: async () => ({
          ...base.razorpayPayment,
        }),
        finalizeCapturedPayment,
      },
    });
  }

  async function runReconciliation({leaseState} = {}) {
    const attemptPath =
      `bookings/${base.ids.bookingId}/paymentAttempts/${base.ids.paymentAttemptId}`;
    if (leaseState === "active") {
      firestore._set(attemptPath, {
        leaseOwner: "other-worker",
        leaseExpiresAt: new Date(base.authoritativeNow.getTime() + 60_000),
      }, {merge: true});
    } else if (leaseState === "stale") {
      firestore._set(attemptPath, {
        leaseOwner: "stale-worker",
        leaseExpiresAt: new Date(base.authoritativeNow.getTime() - 60_000),
      }, {merge: true});
    }

    return reconcilePaymentAttemptsV3({
      firestore,
      keyId: "key",
      keySecret: "secret",
      authoritativeNow: base.authoritativeNow,
      deps: {
        verifyCapturedPayment: async () => runCallable({source: "reconciliation"}),
        submitRefundInstruction: async (params) =>
          runRefundSubmission({
            bookingId: params.bookingId,
            paymentAttemptId: params.paymentAttemptId,
          }),
      },
    });
  }

  async function runPaymentExpiry() {
    const booking = firestore.store.get(`bookings/${base.ids.bookingId}`);
    const result = expireAwaitingPaymentBookingV3({
      bookingId: base.ids.bookingId,
      booking,
      authoritativeNow: new Date(
        (booking.payDeadlineAt ?? booking.lifecycle.payDeadlineAt).getTime() + 1000,
      ),
    });
    if (result.ok) {
      firestore._set(`bookings/${base.ids.bookingId}`, result.booking, {merge: false});
      for (const event of result.events) {
        firestore._set(
          `bookings/${base.ids.bookingId}/events/${event.eventId}`,
          event.record,
          {merge: false},
        );
      }
      persistNotifications(firestore, result.notifications, "system");
    }
    return result;
  }

  async function runRefundSubmission({bookingId, paymentAttemptId} = {}) {
    const original = razorpayGateway.processRazorpayRefundV3;
    let callCount = 0;
    razorpayGateway.processRazorpayRefundV3 = async () => {
      callCount += 1;
      if (refundGatewayOutcome === "timeout") {
        throw new Error("gateway timeout");
      }
      if (refundGatewayOutcome === "processed") {
        return {razorpayRefundId: "rfnd-race-v3", status: "processed"};
      }
      return {razorpayRefundId: "rfnd-race-v3", status: "submitted"};
    };
    try {
      const outcome = await submitRefundInstructionV3({
        firestore,
        bookingId: bookingId ?? base.ids.bookingId,
        paymentAttemptId: paymentAttemptId ?? base.ids.paymentAttemptId,
        keyId: "key",
        keySecret: "secret",
        authoritativeNow: base.authoritativeNow,
      });
      return {outcome, callCount};
    } finally {
      razorpayGateway.processRazorpayRefundV3 = original;
    }
  }

  async function runRefundWebhook({eventName = "refund.processed"} = {}) {
    return routeCanonicalWebhookEventV3({
      firestore,
      eventId: `${eventName}:rfnd-race-v3`,
      eventName,
      paymentEntity: {},
      refundEntity: {
        id: "rfnd-race-v3",
        payment_id: base.ids.razorpayPaymentId,
        amount: base.razorpayPayment.amountPaise,
        status: eventName === "refund.failed" ? "failed" : "processed",
      },
      keyId: "key",
      keySecret: "secret",
      authoritativeNow: base.authoritativeNow,
    });
  }

  function readState() {
    return {
      firestore,
      booking: firestore.store.get(`bookings/${base.ids.bookingId}`),
      paymentAttempt: firestore.store.get(
        `bookings/${base.ids.bookingId}/paymentAttempts/${base.ids.paymentAttemptId}`,
      ),
      refund: firestore.store.get(`refunds/${base.ids.bookingId}`),
      bookingPrivate: firestore.store.get(`bookingPrivate/${base.ids.bookingId}`),
      bookingChat: firestore.store.get(`bookingChats/${base.ids.bookingId}`),
      chat: firestore.store.get(`chats/${base.ids.bookingId}`),
    };
  }

  function countByPrefix(prefix) {
    return [...firestore.store.keys()].filter((path) => path.startsWith(prefix)).length;
  }

  function readPersistedEffects() {
    return {
      bookingFinancials: countByPrefix(`bookingFinancials/${base.ids.bookingId}`),
      payments: countByPrefix(`payments/${base.ids.bookingId}`),
      invoices: countByPrefix(`invoices/${base.ids.bookingId}`),
      providerEarnings: countByPrefix(`providerEarnings/${base.ids.bookingId}`),
      payoutReadiness: countByPrefix(`payoutReadiness/${base.ids.bookingId}`),
      bookingPrivate: countByPrefix(`bookingPrivate/${base.ids.bookingId}`),
      bookingChats: countByPrefix(`bookingChats/${base.ids.bookingId}`),
      chats: countByPrefix(`chats/${base.ids.bookingId}`),
      refunds: countByPrefix(`refunds/${base.ids.bookingId}`),
      events: countByPrefix(`bookings/${base.ids.bookingId}/events/`),
      notifications: [...firestore.store.keys()].filter((path) =>
        path.startsWith("notifications/") &&
        firestore.store.get(path)?.bookingId === base.ids.bookingId,
      ).length,
    };
  }

  return {
    ids: base.ids,
    base,
    firestore,
    runCallable,
    runWebhook,
    runReconciliation,
    runPaymentExpiry,
    runRefundSubmission,
    runRefundWebhook,
    setRefundGatewayOutcome(value) {
      refundGatewayOutcome = value;
    },
    readState,
    readPersistedEffects,
  };
}

function assertConfirmedExactlyOnce(fixture) {
  const {booking, paymentAttempt, bookingPrivate, bookingChat, chat} =
    fixture.readState();
  const effects = fixture.readPersistedEffects();
  assert.equal(booking.state, "CONFIRMED");
  assert.ok(booking.lifecycle.paidAt);
  assert.equal(paymentAttempt.state, "CONFIRMED");
  assert.equal(effects.bookingFinancials, 1);
  assert.equal(effects.payments, 1);
  assert.equal(effects.invoices, 1);
  assert.equal(effects.providerEarnings, 1);
  assert.equal(effects.payoutReadiness, 1);
  assert.equal(effects.bookingPrivate, 1);
  assert.equal(effects.bookingChats, 1);
  assert.equal(effects.chats, 1);
  assert.equal(effects.refunds, 0);
  assert.ok(bookingPrivate.parentOtpCode);
  assert.equal(bookingChat.bookingId, fixture.ids.bookingId);
  assert.equal(chat.bookingId, fixture.ids.bookingId);
  assert.deepEqual(bookingChat.participantIds, ["parent-1", "provider-1"]);
  assert.deepEqual(chat.participantIds, ["parent-1", "provider-1"]);
  assert.equal(bookingChat.unreadCountCustomer, 0);
  assert.equal(chat.unreadCountProvider, 0);
  assertNoPrivateLeakage(booking);
  assertNoPrivateLeakage(paymentAttempt);
}

function assertRefundRequiredExactlyOnce(fixture) {
  const {booking, paymentAttempt, refund, bookingPrivate, bookingChat, chat} =
    fixture.readState();
  const effects = fixture.readPersistedEffects();
  assert.notEqual(booking.state, "CONFIRMED");
  assert.equal(booking.lifecycle.paidAt ?? null, null);
  assert.ok(["REFUND_REQUIRED", "REFUND_PENDING", "REFUNDED"].includes(paymentAttempt.state));
  assert.equal(effects.refunds, 1);
  assert.ok(refund);
  assert.equal(effects.bookingFinancials, 0);
  assert.equal(effects.payments, 0);
  assert.equal(effects.invoices, 0);
  assert.equal(effects.providerEarnings, 0);
  assert.equal(effects.payoutReadiness, 0);
  assert.equal(bookingPrivate, undefined);
  assert.equal(bookingChat, undefined);
  assert.equal(chat, undefined);
}

function assertNoCrossBookingEffects(fixture, otherBookingId) {
  assert.equal(fixture.firestore.store.has(`bookingPrivate/${otherBookingId}`), false);
  assert.equal(fixture.firestore.store.has(`bookingChats/${otherBookingId}`), false);
  assert.equal(fixture.firestore.store.has(`chats/${otherBookingId}`), false);
  assert.equal(fixture.firestore.store.has(`bookingFinancials/${otherBookingId}`), false);
  assert.equal(fixture.firestore.store.has(`payments/${otherBookingId}`), false);
}

module.exports = {
  FakeFirestore,
  createRaceFixture,
  assertConfirmedExactlyOnce,
  assertRefundRequiredExactlyOnce,
  assertNoCrossBookingEffects,
};
