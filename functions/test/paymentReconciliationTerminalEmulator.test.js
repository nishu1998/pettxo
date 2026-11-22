// Phase 3B-4e (R1): payments that will never capture end the attempt.
const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({
  services: ["firestore"],
  projectId: "demo-reconcile-terminal",
});
const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {HttpsError} = require("firebase-functions/https");

const {
  definitiveNonCaptureOutcome,
  reconcilePaymentAttemptsV3,
} = require("../lib/booking/application/paymentOrchestrationV3.js");

const enabled = firebaseEmulator.enabled;

function fetchReturning(record) {
  return async ({paymentId}) => ({
    id: paymentId, orderId: "order_x", amountPaise: 100, currency: "INR", createdAt: null,
    capturedAt: null, receipt: "", notes: {}, ...record,
  });
}

test("definitiveNonCaptureOutcome: only failed, or refunded with captured === false", async () => {
  const outcome = (fetchPayment) => definitiveNonCaptureOutcome({
    fetchPayment, keyId: "k", keySecret: "s", paymentId: "pay_1",
  });
  assert.equal(await outcome(fetchReturning({status: "failed"})), "PAYMENT_FAILED");
  assert.equal(await outcome(fetchReturning({status: "FAILED"})), "PAYMENT_FAILED");
  assert.equal(await outcome(fetchReturning({status: "refunded", captured: false})), "PAYMENT_REFUNDED_UNCAPTURED");
  for (const record of [
    {status: "refunded", captured: true},
    {status: "refunded", captured: null},
    {status: "refunded"},
    {status: "authorized", captured: false},
    {status: "created"},
    {status: "captured", captured: true},
    {status: "something_new"},
    {status: ""},
    {status: "failed", id: "pay_other"},
  ]) {
    assert.equal(await outcome(fetchReturning(record)), null, JSON.stringify(record));
  }
  assert.equal(await outcome(async () => {
    throw new HttpsError("unavailable", "network down");
  }), null);
  assert.equal(await outcome(async () => {
    throw new Error("socket hang up");
  }), null);
});

async function withProject(run) {
  const app = initializeApp({projectId: "demo-reconcile-terminal"}, `reconcile-${randomUUID()}`);
  const db = getFirestore(app);
  db.settings({ignoreUndefinedProperties: true});
  try {
    await run(db);
  } finally {
    await db.terminate();
    await deleteApp(app);
  }
}

async function seedAttempt(db, label) {
  const sfx = `${label}-${randomUUID().slice(0, 6)}`;
  const ref = db.doc(`bookings/bk-${sfx}/paymentAttempts/at-${sfx}`);
  await ref.set({
    bookingId: `bk-${sfx}`,
    paymentAttemptId: `at-${sfx}`,
    razorpayOrderId: `order_${sfx}`,
    razorpayPaymentId: `pay_${sfx}`,
    state: "CAPTURED_REQUIRES_RECONCILIATION",
    captureReportedAt: new Date(),
    nextReconciliationAt: null,
    reconciliationAttemptCount: 0,
    terminalFailureAt: null,
    leaseOwner: "",
    leaseExpiresAt: null,
    paymentMethod: "checkout",
    lastReconciliationCode: "",
  });
  return ref;
}

const notCaptured = async () => {
  throw new HttpsError("failed-precondition", "Razorpay payment is not captured yet.");
};

for (const [label, fetchPayment, expected] of [
  ["failed", fetchReturning({status: "failed", captured: false}), {state: "FAILED", code: "PAYMENT_FAILED", terminal: true}],
  ["refunded-uncaptured", fetchReturning({status: "refunded", captured: false}),
    {state: "FAILED", code: "PAYMENT_REFUNDED_UNCAPTURED", terminal: true}],
  ["refunded-after-capture", fetchReturning({status: "refunded", captured: true}),
    {state: "CAPTURED_REQUIRES_RECONCILIATION", code: "PAYMENT_NOT_CAPTURED_YET", terminal: false}],
  ["authorized", fetchReturning({status: "authorized", captured: false}),
    {state: "CAPTURED_REQUIRES_RECONCILIATION", code: "PAYMENT_NOT_CAPTURED_YET", terminal: false}],
  ["created", fetchReturning({status: "created"}),
    {state: "CAPTURED_REQUIRES_RECONCILIATION", code: "PAYMENT_NOT_CAPTURED_YET", terminal: false}],
  ["network-error", async () => {
    throw new HttpsError("unavailable", "network down");
  }, {state: "CAPTURED_REQUIRES_RECONCILIATION", code: "PAYMENT_NOT_CAPTURED_YET", terminal: false}],
]) {
  test(`reconciler, not-captured payment reported as ${label}`, {skip: !enabled}, async () => {
    await withProject(async (db) => {
      const ref = await seedAttempt(db, label);
      await reconcilePaymentAttemptsV3({
        firestore: db,
        keyId: "k",
        keySecret: "s",
        limit: 200,
        authoritativeNow: new Date(),
        deps: {
          verifyCapturedPayment: notCaptured,
          fetchPayment,
          persistNotifications: async () => undefined,
        },
      });
      const attempt = (await ref.get()).data();
      assert.equal(attempt.state, expected.state);
      assert.equal(attempt.lastReconciliationCode, expected.code);
      assert.equal(attempt.terminalFailureAt != null, expected.terminal);
      if (expected.terminal) {
        assert.equal(attempt.nextReconciliationAt, null);
        assert.equal(attempt.failureCode, expected.code);
      } else {
        assert.ok(attempt.nextReconciliationAt, "stays scheduled for another attempt");
      }
    });
  });
}

test("reconciler, transient gateway error from verification stays retryable", {skip: !enabled}, async () => {
  await withProject(async (db) => {
    const ref = await seedAttempt(db, "gateway");
    let fetched = false;
    await reconcilePaymentAttemptsV3({
      firestore: db, keyId: "k", keySecret: "s", limit: 200, authoritativeNow: new Date(),
      deps: {
        verifyCapturedPayment: async () => {
          throw new HttpsError("unavailable", "gateway timeout");
        },
        fetchPayment: async () => {
          fetched = true;
          return fetchReturning({status: "failed"})({paymentId: "x"});
        },
        persistNotifications: async () => undefined,
      },
    });
    const attempt = (await ref.get()).data();
    assert.equal(attempt.state, "CAPTURED_REQUIRES_RECONCILIATION");
    assert.equal(attempt.lastReconciliationCode, "GATEWAY_RETRY");
    assert.equal(attempt.terminalFailureAt, null);
    assert.equal(fetched, false, "a gateway error never triggers the definitive-status lookup");
  });
});

test("a FAILED attempt is not reconciled again", {skip: !enabled}, async () => {
  await withProject(async (db) => {
    const ref = await seedAttempt(db, "again");
    const deps = {
      verifyCapturedPayment: notCaptured,
      fetchPayment: fetchReturning({status: "failed"}),
      persistNotifications: async () => undefined,
    };
    await reconcilePaymentAttemptsV3({firestore: db, keyId: "k", keySecret: "s", limit: 200, authoritativeNow: new Date(), deps});
    let calls = 0;
    await reconcilePaymentAttemptsV3({
      firestore: db, keyId: "k", keySecret: "s", limit: 200, authoritativeNow: new Date(Date.now() + 3600_000),
      deps: {...deps, verifyCapturedPayment: async (params) => {
        if (params.paymentAttemptId === ref.id) calls += 1;
        return notCaptured();
      }},
    });
    assert.equal(calls, 0);
    assert.equal((await ref.get()).data().reconciliationAttemptCount, 1);
  });
});
