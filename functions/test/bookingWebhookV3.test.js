const test = require("node:test");
const assert = require("node:assert/strict");
const {createHmac} = require("node:crypto");

const {
  verifyRazorpayWebhookSignatureV3,
} = require("../lib/booking/application/razorpayGateway.js");
const {
  buildPaymentWebhookEventKeyV3,
  claimPaymentWebhookEventV3,
  normalizePaymentWebhookProcessingStateV3,
  processRazorpayWebhookEnvelopeV3,
} = require("../lib/booking/application/paymentWebhookEventsV3.js");
const {
  routeCanonicalWebhookEventV3,
} = require("../lib/booking/application/canonicalPaymentWebhookV3.js");
const {
  buildCanonicalPaymentRaceFixture,
  assertNoPrivateLeakage,
} = require("./helpers/canonicalPaymentRaceFixture.js");
const {
  finalizeCapturedBookingPaymentV3,
  persistFinalizePaymentResultV3,
} = require("../lib/booking/application/paymentOrchestrationV3.js");

class FakeDocSnapshot {
  constructor(path, data) {
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
    for (const operation of this.operations) operation();
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
    return new FakeDocSnapshot(this.path, this.firestore.store.get(this.path));
  }

  async set(data, options) {
    this.firestore._set(this.path, data, options);
  }
}

class FakeQuery {
  constructor(firestore, collectionName, docs) {
    this.firestore = firestore;
    this.collectionName = collectionName;
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
        if (filter.op !== "==") return false;
        return doc.data()?.[filter.field] === filter.value;
      });
    }
    if (this.max != null) docs = docs.slice(0, this.max);
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
    return new FakeQuery(this.firestore, this.id, this.firestore._docsForCollection(this.path))
      .where(field, op, value);
  }

  limit(max) {
    return new FakeQuery(this.firestore, this.id, this.firestore._docsForCollection(this.path))
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
    return new FakeQuery(this, name, this._docsForCollectionGroup(name));
  }

  batch() {
    return new FakeBatch(this);
  }

  async runTransaction(handler) {
    return handler(new FakeTransaction(this));
  }

  _docsForCollection(collectionPath) {
    const targetSegments = collectionPath.split("/").length + 1;
    return [...this.store.entries()]
      .filter(([path]) =>
        path.startsWith(`${collectionPath}/`) &&
        path.split("/").length === targetSegments)
      .map(([path, data]) => new FakeDocSnapshot(path, data));
  }

  _docsForCollectionGroup(name) {
    return [...this.store.entries()]
      .filter(([path]) => {
        const segments = path.split("/");
        return segments.length >= 2 && segments[segments.length - 2] === name;
      })
      .map(([path, data]) => new FakeDocSnapshot(path, data));
  }

  _set(path, data, options = {}) {
    const existing = this.store.get(path) ?? {};
    this.store.set(path, options.merge ? {...existing, ...data} : {...data});
  }
}

function buildWebhookPayload(overrides = {}) {
  return {
    event: "payment.captured",
    payload: {
      payment: {
        entity: {
          id: "pay_1",
          order_id: "order_1",
          amount: 25000,
          currency: "INR",
        },
      },
      refund: {entity: {}},
    },
    ...overrides,
  };
}

function signBody(secret, rawBody) {
  return createHmac("sha256", secret).update(rawBody).digest("hex");
}

function seedCanonicalBookingStore() {
  return new FakeFirestore({
    "canonicalPaymentOrderMappings/order_1": {
      bookingId: "booking_1",
      paymentAttemptId: "attempt_1",
      schemaVersion: 1,
    },
    "bookings/booking_1": {
      bookingId: "booking_1",
      bookingModelVersion: "3.2",
      state: "ACCEPTED_AWAITING_PAYMENT",
      bookingType: "SLOT",
      parentId: "parent_1",
      providerId: "provider_1",
    },
    "bookings/booking_1/paymentAttempts/attempt_1": {
      bookingId: "booking_1",
      paymentAttemptId: "attempt_1",
      amountPaise: 25000,
      currency: "INR",
      razorpayOrderId: "order_1",
      razorpayPaymentId: "",
      state: "ORDER_CREATED",
    },
  });
}

test("verifyRazorpayWebhookSignatureV3 uses the raw webhook body", () => {
  const secret = "webhook_secret";
  const rawBody = Buffer.from('{"event":"payment.captured","id":1}');
  const signature = signBody(secret, rawBody);

  assert.equal(
    verifyRazorpayWebhookSignatureV3({webhookSecret: secret, rawBody, signature}),
    true,
  );
  assert.equal(
    verifyRazorpayWebhookSignatureV3({
      webhookSecret: secret,
      rawBody: Buffer.from('{"event":"payment.captured","id":2}'),
      signature,
    }),
    false,
  );
});

test("normalizePaymentWebhookProcessingStateV3 accepts historic stored values", () => {
  assert.equal(normalizePaymentWebhookProcessingStateV3("retryable_error"), "RETRYABLE_FAILURE");
  assert.equal(normalizePaymentWebhookProcessingStateV3("processed"), "PROCESSED");
  assert.equal(normalizePaymentWebhookProcessingStateV3(""), "RECEIVED");
});

test("processRazorpayWebhookEnvelopeV3 rejects missing and invalid signatures without writes", async () => {
  const firestore = new FakeFirestore();
  let canonicalCalls = 0;
  const payload = buildWebhookPayload();
  const rawBody = Buffer.from(JSON.stringify(payload));

  const missing = await processRazorpayWebhookEnvelopeV3({
    firestore,
    signature: "",
    rawBody,
    payload,
    webhookSecret: "secret",
    keyId: "key",
    keySecret: "secret",
    routeCanonicalWebhook: async () => {
      canonicalCalls += 1;
      throw new Error("should not run");
    },
  });
  assert.equal(missing.statusCode, 400);
  assert.equal(firestore.store.size, 0);

  const invalid = await processRazorpayWebhookEnvelopeV3({
    firestore,
    signature: "invalid",
    rawBody,
    payload,
    webhookSecret: "secret",
    keyId: "key",
    keySecret: "secret",
    routeCanonicalWebhook: async () => {
      canonicalCalls += 1;
      throw new Error("should not run");
    },
  });
  assert.equal(invalid.statusCode, 401);
  assert.equal(canonicalCalls, 0);
  assert.equal(firestore.store.size, 0);
});

test("claimPaymentWebhookEventV3 claims new events and suppresses active duplicates", async () => {
  const firestore = new FakeFirestore();
  const now = new Date("2026-07-22T10:00:00.000Z");
  const eventKey = "payment.captured:pay_1";

  const first = await claimPaymentWebhookEventV3({
    firestore,
    eventKey,
    eventName: "payment.captured",
    paymentId: "pay_1",
    orderId: "order_1",
    refundId: "",
    authoritativeNow: now,
  });
  assert.equal(first.outcome, "CLAIMED");

  const second = await claimPaymentWebhookEventV3({
    firestore,
    eventKey,
    eventName: "payment.captured",
    paymentId: "pay_1",
    orderId: "order_1",
    refundId: "",
    authoritativeNow: new Date("2026-07-22T10:00:30.000Z"),
  });
  assert.equal(second.outcome, "ALREADY_PROCESSING");
});

test("claimPaymentWebhookEventV3 reclaims retryable failures and expired processing leases", async () => {
  const eventKey = buildPaymentWebhookEventKeyV3({
    eventName: "payment.captured",
    paymentEntity: {id: "pay_1", order_id: "order_1"},
    refundEntity: {},
  });
  const firestore = new FakeFirestore({
    [`paymentWebhookEvents/${eventKey}`]: {
      eventId: eventKey,
      processingState: "RETRYABLE_FAILURE",
      processingLeaseOwner: "old",
      processingLeaseExpiresAt: {toDate: () => new Date("2026-07-22T09:50:00.000Z")},
    },
  });

  const reclaimed = await claimPaymentWebhookEventV3({
    firestore,
    eventKey,
    eventName: "payment.captured",
    paymentId: "pay_1",
    orderId: "order_1",
    refundId: "",
    authoritativeNow: new Date("2026-07-22T10:00:00.000Z"),
  });
  assert.equal(reclaimed.outcome, "CLAIMED");
});

test("processRazorpayWebhookEnvelopeV3 routes canonical events exactly once and ignores duplicates", async () => {
  const firestore = new FakeFirestore();
  const payload = buildWebhookPayload();
  const rawBody = Buffer.from(JSON.stringify(payload));
  const signature = signBody("secret", rawBody);
  let canonicalCalls = 0;

  const first = await processRazorpayWebhookEnvelopeV3({
    firestore,
    signature,
    rawBody,
    payload,
    webhookSecret: "secret",
    keyId: "key",
    keySecret: "secret",
    routeCanonicalWebhook: async () => {
      canonicalCalls += 1;
      return {
        outcome: "CONFIRMED",
        bookingId: "booking_1",
        paymentAttemptId: "attempt_1",
        retryable: false,
        failureCode: "",
        notifications: [],
      };
    },
  });
  assert.equal(first.routeType, "canonical");
  assert.equal(canonicalCalls, 1);

  const second = await processRazorpayWebhookEnvelopeV3({
    firestore,
    signature,
    rawBody,
    payload,
    webhookSecret: "secret",
    keyId: "key",
    keySecret: "secret",
    routeCanonicalWebhook: async () => {
      canonicalCalls += 1;
      return {
        outcome: "CONFIRMED",
        bookingId: "booking_1",
        paymentAttemptId: "attempt_1",
        retryable: false,
        failureCode: "",
        notifications: [],
      };
    },
  });
  assert.equal(second.routeType, "ignored");
  assert.equal(canonicalCalls, 1);
  assertNoPrivateLeakage(
    firestore.store.get("paymentWebhookEvents/payment.captured:pay_1"),
  );
});

test("processRazorpayWebhookEnvelopeV3 records unmapped canonical payment events without legacy fallback", async () => {
  const firestore = new FakeFirestore();
  const payload = buildWebhookPayload();
  const rawBody = Buffer.from(JSON.stringify(payload));
  const signature = signBody("secret", rawBody);

  const result = await processRazorpayWebhookEnvelopeV3({
    firestore,
    signature,
    rawBody,
    payload,
    webhookSecret: "secret",
    keyId: "key",
    keySecret: "secret",
    routeCanonicalWebhook: async () => ({
      outcome: "IGNORED_UNMAPPED",
      bookingId: "",
      paymentAttemptId: "",
      retryable: false,
      failureCode: "",
      notifications: [],
    }),
  });

  assert.equal(result.routeType, "canonical");
  assert.equal(
    firestore.store.get("paymentWebhookEvents/payment.captured:pay_1").outcome,
    "IGNORED_UNMAPPED",
  );
});

test("processRazorpayWebhookEnvelopeV3 preserves canonical handling on invalid mappings", async () => {
  const firestore = new FakeFirestore();
  const payload = buildWebhookPayload();
  const rawBody = Buffer.from(JSON.stringify(payload));
  const signature = signBody("secret", rawBody);

  const result = await processRazorpayWebhookEnvelopeV3({
    firestore,
    signature,
    rawBody,
    payload,
    webhookSecret: "secret",
    keyId: "key",
    keySecret: "secret",
    routeCanonicalWebhook: async () => ({
      outcome: "INVALID_CANONICAL_MAPPING",
      bookingId: "booking_1",
      paymentAttemptId: "attempt_1",
      retryable: false,
      failureCode: "PAYMENT_MISMATCH",
      notifications: [],
    }),
  });

  assert.equal(result.routeType, "canonical");
});

test("routeCanonicalWebhookEventV3 invokes the shared finalizer with trusted normalized facts", async () => {
  const firestore = seedCanonicalBookingStore();
  let receivedFacts = null;
  const result = await routeCanonicalWebhookEventV3({
    firestore,
    eventId: "payment.captured:pay_1",
    eventName: "payment.captured",
    paymentEntity: {
      id: "pay_1",
      order_id: "order_1",
      amount: 25000,
      currency: "INR",
    },
    refundEntity: {},
    keyId: "key",
    keySecret: "secret",
    authoritativeNow: new Date("2026-07-22T10:30:00.000Z"),
    deps: {
      fetchRazorpayPayment: async () => ({
        id: "pay_1",
        orderId: "order_1",
        status: "captured",
        amountPaise: 25000,
        currency: "INR",
        createdAt: new Date("2026-07-22T10:25:00.000Z"),
        capturedAt: new Date("2026-07-22T10:25:01.000Z"),
      }),
      finalizeCapturedPayment: async ({facts}) => {
        receivedFacts = facts;
        return {
          ok: true,
          code: "CONFIRMED",
          booking: {
            parentId: "parent_1",
            providerId: "provider_1",
            bookingType: "SLOT",
            state: "CONFIRMED",
          },
          paymentAttempt: {paymentAttemptId: "attempt_1"},
          bookingPrivate: {bookingId: "booking_1"},
          otpCode: "123456",
          occupancyWrites: {},
          financialWrites: {
            bookingFinancial: {},
            payment: {},
            invoice: {},
            providerEarning: {},
            payoutReadiness: {},
            bookingChat: {},
          },
          couponWrite: null,
          events: [],
          notifications: [],
          parentStats: {},
        };
      },
      persistNotifications: async () => {},
    },
  });

  assert.equal(result.outcome, "CONFIRMED");
  assert.deepEqual(receivedFacts, {
    bookingId: "booking_1",
    paymentAttemptId: "attempt_1",
    razorpayOrderId: "order_1",
    razorpayPaymentId: "pay_1",
    capturedAmountPaise: 25000,
    currency: "INR",
    capturedAt: new Date("2026-07-22T10:25:01.000Z"),
    verificationSource: "webhook",
    sourceEventId: "payment.captured:pay_1",
  });
});

test("routeCanonicalWebhookEventV3 safely rejects payment mismatches and missing canonical mappings", async () => {
  const missingMapping = await routeCanonicalWebhookEventV3({
    firestore: new FakeFirestore(),
    eventId: "payment.captured:pay_1",
    eventName: "payment.captured",
    paymentEntity: {id: "pay_1", order_id: "order_1"},
    refundEntity: {},
    keyId: "key",
    keySecret: "secret",
    deps: {
      fetchRazorpayPayment: async () => {
        throw new Error("should not fetch");
      },
      finalizeCapturedPayment: async () => {
        throw new Error("should not finalize");
      },
      persistNotifications: async () => {},
    },
  });
  assert.equal(missingMapping.outcome, "IGNORED_UNMAPPED");

  const mismatchStore = seedCanonicalBookingStore();
  const mismatch = await routeCanonicalWebhookEventV3({
    firestore: mismatchStore,
    eventId: "payment.captured:pay_1",
    eventName: "payment.captured",
    paymentEntity: {id: "pay_1", order_id: "order_1"},
    refundEntity: {},
    keyId: "key",
    keySecret: "secret",
    deps: {
      fetchRazorpayPayment: async () => ({
        id: "pay_1",
        orderId: "order_1",
        status: "captured",
        amountPaise: 35000,
        currency: "INR",
        createdAt: new Date("2026-07-22T10:25:00.000Z"),
        capturedAt: new Date("2026-07-22T10:25:00.000Z"),
      }),
      finalizeCapturedPayment: async () => {
        throw new Error("should not finalize");
      },
      persistNotifications: async () => {},
    },
  });
  assert.equal(mismatch.outcome, "INVALID_CANONICAL_MAPPING");
  assert.equal(mismatch.failureCode, "PAYMENT_MISMATCH");
});

test("processRazorpayWebhookEnvelopeV3 marks retryable failure, then a reclaimed replay succeeds once", async () => {
  const firestore = new FakeFirestore();
  const payload = buildWebhookPayload();
  const rawBody = Buffer.from(JSON.stringify(payload));
  const signature = signBody("secret", rawBody);
  let canonicalCalls = 0;

  await assert.rejects(
    () => processRazorpayWebhookEnvelopeV3({
      firestore,
      signature,
      rawBody,
      payload,
      webhookSecret: "secret",
      keyId: "key",
      keySecret: "secret",
      routeCanonicalWebhook: async () => {
        canonicalCalls += 1;
        throw new Error("temporary webhook failure");
      },
    }),
    /temporary webhook failure/,
  );

  const eventRef = firestore.store.get("paymentWebhookEvents/payment.captured:pay_1");
  assert.equal(eventRef.processingState, "RETRYABLE_FAILURE");
  assert.equal(canonicalCalls, 1);

  const retried = await processRazorpayWebhookEnvelopeV3({
    firestore,
    signature,
    rawBody,
    payload,
    webhookSecret: "secret",
    keyId: "key",
    keySecret: "secret",
    authoritativeNow: new Date("2026-07-22T10:05:00.000Z"),
    routeCanonicalWebhook: async () => {
      canonicalCalls += 1;
      return {
        outcome: "CONFIRMED",
        bookingId: "booking_1",
        paymentAttemptId: "attempt_1",
        retryable: false,
        failureCode: "",
        notifications: [],
      };
    },
  });

  assert.equal(retried.routeType, "canonical");
  assert.equal(canonicalCalls, 2);
  assert.equal(
    firestore.store.get("paymentWebhookEvents/payment.captured:pay_1").processingState,
    "PROCESSED",
  );
});

test("routeCanonicalWebhookEventV3 replay for the same captured payment does not leak private fields", async () => {
  const firestore = seedCanonicalBookingStore();

  const result = await routeCanonicalWebhookEventV3({
    firestore,
    eventId: "payment.captured:pay_1:replay",
    eventName: "payment.captured",
    paymentEntity: {
      id: "pay_1",
      order_id: "order_1",
      amount: 25000,
      currency: "INR",
    },
    refundEntity: {},
    keyId: "key",
    keySecret: "secret",
    authoritativeNow: new Date("2026-07-22T10:30:00.000Z"),
    deps: {
      fetchRazorpayPayment: async () => ({
        id: "pay_1",
        orderId: "order_1",
        status: "captured",
        amountPaise: 25000,
        currency: "INR",
        createdAt: new Date("2026-07-22T10:25:00.000Z"),
        capturedAt: new Date("2026-07-22T10:25:01.000Z"),
      }),
      finalizeCapturedPayment: async () => ({
        ok: true,
        code: "IDEMPOTENT_REPLAY",
        booking: {
          parentId: "parent_1",
          providerId: "provider_1",
          bookingType: "SLOT",
          state: "CONFIRMED",
        },
        paymentAttempt: {paymentAttemptId: "attempt_1"},
        bookingPrivate: {bookingId: "booking_1", parentOtpCode: "123456"},
        otpCode: "123456",
        occupancyWrites: {},
        financialWrites: {
          bookingFinancial: {},
          payment: {},
          invoice: {},
          providerEarning: {},
          payoutReadiness: {},
          bookingChat: {},
        },
        couponWrite: null,
        events: [],
        notifications: [],
        parentStats: {},
      }),
      persistNotifications: async () => {},
    },
  });

  assert.equal(result.outcome, "ALREADY_CONFIRMED");
  assertNoPrivateLeakage(
    firestore.store.get("canonicalPaymentOrderMappings/order_1"),
  );
});

test("refund.processed synchronizes cancellation refund status and persists safe canonical notifications", async () => {
  const fixture = buildCanonicalPaymentRaceFixture({
    ids: {
      bookingId: "booking_refund_notif_1",
      paymentAttemptId: "attempt_refund_notif_1",
      razorpayOrderId: "order_refund_notif_1",
      razorpayPaymentId: "pay_refund_notif_1",
    },
  });
  const confirmResult = finalizeCapturedBookingPaymentV3({
    bookingId: fixture.ids.bookingId,
    booking: fixture.booking,
    paymentAttempt: fixture.paymentAttempt,
    parent: fixture.parent,
    service: fixture.service,
    slotOccupancy: fixture.slotOccupancy,
    rangeOccupancy: fixture.rangeOccupancy,
    razorpayPayment: fixture.razorpayPayment,
    authoritativeNow: fixture.authoritativeNow,
    verificationSource: "callable",
  });
  const firestore = new FakeFirestore({
    [`canonicalPaymentOrderMappings/${fixture.ids.razorpayOrderId}`]: {
      bookingId: fixture.ids.bookingId,
      paymentAttemptId: fixture.ids.paymentAttemptId,
      schemaVersion: 1,
    },
  });
  await persistFinalizePaymentResultV3({
    firestore,
    result: confirmResult,
    bookingId: fixture.ids.bookingId,
  });

  const result = await routeCanonicalWebhookEventV3({
    firestore,
    eventId: "refund.processed:rfnd_1",
    eventName: "refund.processed",
    paymentEntity: {},
    refundEntity: {
      id: "rfnd_1",
      payment_id: fixture.ids.razorpayPaymentId,
      amount: fixture.pricing.financialSnapshot.customerPaidPaise,
      status: "processed",
    },
    keyId: "key",
    keySecret: "secret",
    authoritativeNow: new Date("2026-07-22T10:40:00.000Z"),
  });

  assert.equal(result.outcome, "REFUND_UPDATED");
  const cancellationDoc = firestore.store.get(
    `bookingCancellations/${fixture.ids.bookingId}`,
  );
  assert.ok(cancellationDoc);
  assert.equal(cancellationDoc.bookingId, fixture.ids.bookingId);
  assert.equal(cancellationDoc.refundAmountPaise, fixture.pricing.financialSnapshot.customerPaidPaise);
  assert.equal(cancellationDoc.refundStatus, "REFUNDED");
  assert.equal(cancellationDoc.status, "REFUNDED");
  assert.equal(cancellationDoc.refundInstructionId, `refund-${fixture.ids.bookingId}`);
  const notificationDoc = [...firestore.store.entries()]
    .find(([path]) =>
      path.startsWith("notifications/booking_refund_processed:") &&
      path.includes(`:${fixture.booking.parentId}`),
    )?.[1];
  assert.ok(notificationDoc);
  assert.equal(notificationDoc.bookingId, fixture.ids.bookingId);
  assert.equal(notificationDoc.type, "booking_refund_processed");
  assertNoPrivateLeakage(notificationDoc.data);
  assertNoPrivateLeakage(notificationDoc);
});
