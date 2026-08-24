const test = require("node:test");
const assert = require("node:assert/strict");

const {HttpsError} = require("firebase-functions/https");
const {Timestamp} = require("firebase-admin/firestore");
const {
  CANONICAL_RECONCILIATION_ATTEMPT_STATES,
  nextReconciliationAtForAttempt,
  reconciliationDue,
  tryAcquireReconciliationLease,
  reconcilePaymentAttemptsV3,
} = require("../lib/booking/application/paymentOrchestrationV3.js");

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
        if (filter.op === ">") {
          return data[filter.field] > filter.value;
        }
        return false;
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
    const docs = [...this.store.entries()]
      .filter(([path]) => {
        const segments = path.split("/");
        return segments.length >= 2 && segments[segments.length - 2] === name;
      })
      .map(([path, data]) => new FakeDocSnapshot(this, path, data));
    return new FakeQuery(this, docs);
  }

  async runTransaction(handler) {
    return handler(new FakeTransaction(this));
  }

  _set(path, data, options = {}) {
    const existing = this.store.get(path) ?? {};
    this.store.set(path, options.merge ? {...existing, ...data} : {...data});
  }
}

function buildAttempt(state, overrides = {}) {
  return {
    bookingId: "booking_1",
    paymentAttemptId: "attempt_1",
    state,
    razorpayOrderId: "order_1",
    razorpayPaymentId: "pay_1",
    reconciliationAttemptCount: 0,
    nextReconciliationAt: null,
    lastReconciledAt: null,
    lastReconciliationCode: "",
    terminalFailureAt: null,
    leaseOwner: "",
    leaseExpiresAt: null,
    ...overrides,
  };
}

test("reconciliation state allowlist stays locked to canonical retry states", () => {
  assert.deepEqual([...CANONICAL_RECONCILIATION_ATTEMPT_STATES], [
    "CAPTURE_REPORTED",
    "CONFIRMING",
    "CAPTURED_REQUIRES_RECONCILIATION",
    "REFUND_REQUIRED",
    "REFUND_PENDING",
  ]);
});

test("reconciliationDue respects future nextReconciliationAt and terminal attempts", () => {
  const now = new Date("2026-07-22T10:00:00.000Z");
  assert.equal(reconciliationDue(buildAttempt("CONFIRMING"), now), true);
  assert.equal(
    reconciliationDue(
      buildAttempt("CONFIRMING", {
        nextReconciliationAt: new Date("2026-07-22T10:05:00.000Z"),
      }),
      now,
    ),
    false,
  );
  assert.equal(
    reconciliationDue(
      buildAttempt("CONFIRMING", {
        terminalFailureAt: new Date("2026-07-22T09:59:00.000Z"),
      }),
      now,
    ),
    false,
  );
  assert.equal(
    reconciliationDue(
      buildAttempt("CONFIRMING", {
        nextReconciliationAt: Timestamp.fromDate(new Date("2026-07-22T09:55:00.000Z")),
      }),
      now,
    ),
    true,
  );
});

test("tryAcquireReconciliationLease acquires once, blocks active duplicates, and reclaims expired leases", async () => {
  const firestore = new FakeFirestore({
    "bookings/booking_1/paymentAttempts/attempt_1": buildAttempt("CONFIRMING"),
  });
  const attemptRef = firestore.doc("bookings/booking_1/paymentAttempts/attempt_1");

  const claimed = await tryAcquireReconciliationLease({
    firestore,
    attemptRef,
    authoritativeNow: new Date("2026-07-22T10:00:00.000Z"),
  });
  assert.equal(claimed, true);

  const duplicate = await tryAcquireReconciliationLease({
    firestore,
    attemptRef,
    authoritativeNow: new Date("2026-07-22T10:00:30.000Z"),
  });
  assert.equal(duplicate, false);

  await attemptRef.set({
    leaseOwner: "stale-owner",
    leaseExpiresAt: Timestamp.fromDate(new Date("2026-07-22T09:55:00.000Z")),
  }, {merge: true});
  const reclaimed = await tryAcquireReconciliationLease({
    firestore,
    attemptRef,
    authoritativeNow: new Date("2026-07-22T10:01:00.000Z"),
  });
  assert.equal(reclaimed, true);
});

test("tryAcquireReconciliationLease rejects malformed and terminal attempts", async () => {
  const firestore = new FakeFirestore({
    "bookings/booking_1/paymentAttempts/attempt_bad": buildAttempt("CONFIRMING", {
      bookingId: "",
    }),
    "bookings/booking_1/paymentAttempts/attempt_terminal": buildAttempt("CONFIRMING", {
      terminalFailureAt: new Date("2026-07-22T09:00:00.000Z"),
    }),
    "bookings/booking_1/paymentAttempts/attempt_precanonical": buildAttempt("ORDER_CREATED"),
  });

  assert.equal(
    await tryAcquireReconciliationLease({
      firestore,
      attemptRef: firestore.doc("bookings/booking_1/paymentAttempts/attempt_bad"),
      authoritativeNow: new Date("2026-07-22T10:00:00.000Z"),
    }),
    false,
  );
  assert.equal(
    await tryAcquireReconciliationLease({
      firestore,
      attemptRef: firestore.doc("bookings/booking_1/paymentAttempts/attempt_terminal"),
      authoritativeNow: new Date("2026-07-22T10:00:00.000Z"),
    }),
    false,
  );
  assert.equal(
    await tryAcquireReconciliationLease({
      firestore,
      attemptRef: firestore.doc("bookings/booking_1/paymentAttempts/attempt_precanonical"),
      authoritativeNow: new Date("2026-07-22T10:00:00.000Z"),
    }),
    false,
  );
});

test("nextReconciliationAtForAttempt is deterministic and bounded", () => {
  const now = new Date("2026-07-22T10:00:00.000Z");
  const first = nextReconciliationAtForAttempt({now, attemptCount: 1});
  const later = nextReconciliationAtForAttempt({now, attemptCount: 100});
  assert.equal(first.toISOString(), "2026-07-22T10:00:30.000Z");
  assert.equal(later.toISOString(), "2026-07-22T10:15:00.000Z");
});

test("reconcilePaymentAttemptsV3 schedules retryable gateway failures deterministically", async () => {
  const firestore = new FakeFirestore({
    "bookings/booking_1/paymentAttempts/attempt_1": buildAttempt("CONFIRMING"),
  });
  const now = new Date("2026-07-22T10:00:00.000Z");

  const processed = await reconcilePaymentAttemptsV3({
    firestore,
    keyId: "key",
    keySecret: "secret",
    authoritativeNow: now,
    deps: {
      verifyCapturedPayment: async () => {
        throw new HttpsError("unavailable", "temporary gateway issue");
      },
      submitRefundInstruction: async () => "SKIPPED",
    },
  });

  assert.equal(processed, 1);
  const attempt = firestore.store.get("bookings/booking_1/paymentAttempts/attempt_1");
  assert.equal(attempt.state, "CAPTURED_REQUIRES_RECONCILIATION");
  assert.equal(attempt.lastReconciliationCode, "GATEWAY_RETRY");
  assert.ok(attempt.nextReconciliationAt instanceof Timestamp);
});

test("reconcilePaymentAttemptsV3 rescues stale qr captures that only have a payment id", async () => {
  const firestore = new FakeFirestore({
    "bookings/booking_qr/paymentAttempts/attempt_qr": buildAttempt("ORDER_CREATED", {
      bookingId: "booking_qr",
      paymentAttemptId: "attempt_qr",
      paymentMethod: "qr",
      razorpayOrderId: "",
      razorpayPaymentId: "pay_qr_stale_1",
      captureReportedAt: Timestamp.fromDate(new Date("2026-07-22T09:55:00.000Z")),
      qrState: "PAYMENT_CAPTURED",
    }),
  });
  const processed = await reconcilePaymentAttemptsV3({
    firestore,
    keyId: "key",
    keySecret: "secret",
    authoritativeNow: new Date("2026-07-22T10:00:00.000Z"),
    deps: {
      fetchPayment: async ({paymentId}) => ({
        id: paymentId,
        orderId: "",
        status: "captured",
        amountPaise: 200,
        currency: "INR",
        createdAt: new Date("2026-07-22T09:54:00.000Z"),
        capturedAt: new Date("2026-07-22T09:55:00.000Z"),
        receipt: "",
        notes: {},
      }),
      finalizeCapturedPayment: async ({facts}) => ({
        ok: true,
        code: "CONFIRMED",
        booking: {},
        paymentAttempt: {state: "CONFIRMED", paymentAttemptId: facts.paymentAttemptId},
        notifications: [],
      }),
      verifyCapturedPayment: async () => {
        throw new Error("checkout verifier should not run for stale qr capture");
      },
      submitRefundInstruction: async () => "SKIPPED",
    },
  });

  assert.equal(processed, 1);
  assert.equal(
    firestore.store.get("bookings/booking_qr/paymentAttempts/attempt_qr").lastReconciliationCode,
    "CONFIRMED",
  );
});

test("reconcilePaymentAttemptsV3 confirms eligible captures and records already-confirmed replays safely", async () => {
  const firestore = new FakeFirestore({
    "bookings/booking_1/paymentAttempts/attempt_1": buildAttempt("CONFIRMING"),
    "bookings/booking_2/paymentAttempts/attempt_2": buildAttempt("CAPTURED_REQUIRES_RECONCILIATION", {
      bookingId: "booking_2",
      paymentAttemptId: "attempt_2",
      razorpayOrderId: "order_2",
      razorpayPaymentId: "pay_2",
      nextReconciliationAt: new Date("2026-07-22T09:00:00.000Z"),
    }),
  });

  const seen = [];
  const processed = await reconcilePaymentAttemptsV3({
    firestore,
    keyId: "key",
    keySecret: "secret",
    authoritativeNow: new Date("2026-07-22T10:00:00.000Z"),
    deps: {
      verifyCapturedPayment: async ({bookingId}) => {
        seen.push(bookingId);
        return {
          ok: true,
          code: bookingId === "booking_1" ? "CONFIRMED" : "IDEMPOTENT_REPLAY",
          booking: {},
          paymentAttempt: {state: "CONFIRMED"},
        };
      },
      submitRefundInstruction: async () => "SKIPPED",
    },
  });

  assert.equal(processed, 2);
  assert.deepEqual(seen.sort(), ["booking_1", "booking_2"]);
  assert.equal(
    firestore.store.get("bookings/booking_1/paymentAttempts/attempt_1").lastReconciliationCode,
    "CONFIRMED",
  );
  assert.equal(
    firestore.store.get("bookings/booking_2/paymentAttempts/attempt_2").lastReconciliationCode,
    "ALREADY_CONFIRMED",
  );
});

test("reconcilePaymentAttemptsV3 excludes future, malformed, and noncanonical attempts while processing refund states through the refund wrapper", async () => {
  const firestore = new FakeFirestore({
    "bookings/booking_1/paymentAttempts/attempt_refund": buildAttempt("REFUND_REQUIRED"),
    "bookings/booking_2/paymentAttempts/attempt_future": buildAttempt("CONFIRMING", {
      bookingId: "booking_2",
      paymentAttemptId: "attempt_future",
      nextReconciliationAt: new Date("2026-07-22T11:00:00.000Z"),
    }),
    "bookings/booking_3/paymentAttempts/attempt_missing": buildAttempt("CONFIRMING", {
      bookingId: "booking_3",
      paymentAttemptId: "",
    }),
    "bookings/booking_4/paymentAttempts/attempt_precanonical": buildAttempt("ORDER_CREATED", {
      bookingId: "booking_4",
      paymentAttemptId: "attempt_precanonical",
    }),
  });
  const refundCalls = [];
  const verifyCalls = [];

  const processed = await reconcilePaymentAttemptsV3({
    firestore,
    keyId: "key",
    keySecret: "secret",
    authoritativeNow: new Date("2026-07-22T10:00:00.000Z"),
    deps: {
      verifyCapturedPayment: async ({bookingId}) => {
        verifyCalls.push(bookingId);
        return {
          ok: true,
          code: "CONFIRMED",
          booking: {},
          paymentAttempt: {state: "CONFIRMED"},
        };
      },
      submitRefundInstruction: async ({bookingId}) => {
        refundCalls.push(bookingId);
        return "REFUND_PENDING";
      },
    },
  });

  assert.equal(processed, 1);
  assert.deepEqual(refundCalls, ["booking_1"]);
  assert.deepEqual(verifyCalls, []);
});

test("reconcilePaymentAttemptsV3 skips attempts with an active lease owned by another worker", async () => {
  const firestore = new FakeFirestore({
    "bookings/booking_1/paymentAttempts/attempt_1": buildAttempt("CONFIRMING", {
      leaseOwner: "other-worker",
      leaseExpiresAt: Timestamp.fromDate(new Date("2026-07-22T10:05:00.000Z")),
    }),
  });
  let verifyCalls = 0;

  const processed = await reconcilePaymentAttemptsV3({
    firestore,
    keyId: "key",
    keySecret: "secret",
    authoritativeNow: new Date("2026-07-22T10:00:00.000Z"),
    deps: {
      verifyCapturedPayment: async () => {
        verifyCalls += 1;
        return {ok: true, code: "CONFIRMED", booking: {}, paymentAttempt: {state: "CONFIRMED"}};
      },
      submitRefundInstruction: async () => "SKIPPED",
    },
  });

  assert.equal(processed, 0);
  assert.equal(verifyCalls, 0);
});

test("reconcilePaymentAttemptsV3 excludes already-confirmed attempts from future processing", async () => {
  const firestore = new FakeFirestore({
    "bookings/booking_1/paymentAttempts/attempt_1": buildAttempt("CONFIRMED", {
      nextReconciliationAt: new Date("2026-07-22T09:00:00.000Z"),
    }),
  });
  let verifyCalls = 0;

  const processed = await reconcilePaymentAttemptsV3({
    firestore,
    keyId: "key",
    keySecret: "secret",
    authoritativeNow: new Date("2026-07-22T10:00:00.000Z"),
    deps: {
      verifyCapturedPayment: async () => {
        verifyCalls += 1;
        return {ok: true, code: "CONFIRMED", booking: {}, paymentAttempt: {state: "CONFIRMED"}};
      },
      submitRefundInstruction: async () => "SKIPPED",
    },
  });

  assert.equal(processed, 0);
  assert.equal(verifyCalls, 0);
  assert.equal(
    firestore.store.get("bookings/booking_1/paymentAttempts/attempt_1").nextReconciliationAt.toISOString(),
    "2026-07-22T09:00:00.000Z",
  );
});
