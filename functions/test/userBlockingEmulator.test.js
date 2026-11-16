const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({services: ["firestore"], projectId: "demo-user-blocking"});
const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const {
  blockUserDataV1,
  unblockUserDataV1,
} = require("../lib/blocking/userBlocking.js");
const {
  canonicalUserPair,
  openRelationshipGuardMutation,
  readOpenRelationshipGuardInTransaction,
} = require("../lib/blocking/relationshipGuard.js");
const {
  buildAcceptedAwaitingPaymentSlotBookingFixture,
  buildConfirmedSlotBookingFixture,
} = require("../lib/booking/schema/bookingFixtures.js");
const {
  persistFinalizePaymentResultV3,
} = require("../lib/booking/application/paymentOrchestrationV3.js");
const {
  readBlockingActivationState,
  recordBlockingRolloutTransition,
} = require("../lib/blocking/blockingActivationGate.js");

const enabled = firebaseEmulator.enabled;

async function enableBlocking(firestore, runId = "test-migration-run") {
  await Promise.all([
    firestore.doc("_migrations/userRelationshipGuardV1").set({
      migrationVersion: 1,
      runId,
      status: "verified",
      sourceFingerprint: "test-source-fingerprint",
      verificationValidUntil: new Date(Date.now() + 60 * 60 * 1000),
      reconciliationPassed: true,
      anomalyCount: 0,
      mismatchCount: 0,
    }),
    firestore.collection("userBlockingActivationAudit").doc("test-activation").set({
      event: "ACTIVATE",
      enabled: true,
      migrationRunId: runId,
      sourceFingerprint: "test-source-fingerprint",
      rolloutVersion: 1,
    }),
    firestore.doc("_rollouts/userBlockingV1").set({
      enabled: true,
      status: "active",
      migrationRunId: runId,
      sourceFingerprint: "test-source-fingerprint",
      activationAuditId: "test-activation",
      rolloutVersion: 1,
    }),
  ]);
}

function errorCode(code) {
  return (error) => {
    assert.equal(error.details?.code, code);
    return true;
  };
}

async function fixture(run, {activationEnabled = true} = {}) {
  const suffix = randomUUID();
  const app = initializeApp({projectId: "demo-user-blocking"}, `blocking-${suffix}`);
  const firestore = getFirestore(app);
  firestore.settings({ignoreUndefinedProperties: true});
  const ids = {a: `a-${suffix}`, b: `b-${suffix}`};
  try {
    await Promise.all([
      firestore.collection("users").doc(ids.a).set({uid: ids.a, accountStatus: "active"}),
      firestore.collection("users").doc(ids.b).set({uid: ids.b, accountStatus: "active"}),
    ]);
    if (activationEnabled) await enableBlocking(firestore);
    await run({firestore, ids});
  } finally {
    await firestore.terminate();
    await deleteApp(app);
  }
}

test("block creation is disabled by default and a failed migration cannot enable it", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await assert.rejects(
      blockUserDataV1({firestore, actorUid: ids.a, targetUid: ids.b}),
      errorCode("USER_BLOCKING_DISABLED"),
    );
    await Promise.all([
      firestore.doc("_migrations/userRelationshipGuardV1").set({
        migrationVersion: 1,
        runId: "failed-run",
        status: "failed",
        sourceFingerprint: "failed-source-fingerprint",
        verificationValidUntil: new Date(Date.now() + 60 * 60 * 1000),
        reconciliationPassed: false,
        anomalyCount: 1,
        mismatchCount: 0,
      }),
      firestore.collection("userBlockingActivationAudit").doc("failed-activation").set({
        event: "ACTIVATE",
        enabled: true,
        migrationRunId: "failed-run",
        sourceFingerprint: "failed-source-fingerprint",
        rolloutVersion: 1,
      }),
      firestore.doc("_rollouts/userBlockingV1").set({
        enabled: true,
        status: "active",
        migrationRunId: "failed-run",
        sourceFingerprint: "failed-source-fingerprint",
        activationAuditId: "failed-activation",
        rolloutVersion: 1,
      }),
    ]);
    await assert.rejects(
      blockUserDataV1({firestore, actorUid: ids.a, targetUid: ids.b}),
      errorCode("RELATIONSHIP_MIGRATION_NOT_VERIFIED"),
    );
  }, {activationEnabled: false});
});

test("activation and emergency deactivation are append-only and auditable", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore}) => {
    await assert.rejects(recordBlockingRolloutTransition({
      firestore,
      enabled: true,
      operatorUid: "release-operator",
      reason: "must not activate",
      auditId: "rejected-activation",
      migrationRunId: "unverified-run",
    }), /not_verified/);
    await firestore.doc("_migrations/userRelationshipGuardV1").set({
      migrationVersion: 1,
      runId: "audited-run",
      status: "verified",
      sourceFingerprint: "audited-source-fingerprint",
      verificationValidUntil: new Date(Date.now() - 1000),
      reconciliationPassed: true,
      anomalyCount: 0,
      mismatchCount: 0,
    });
    await assert.rejects(recordBlockingRolloutTransition({
      firestore,
      enabled: true,
      operatorUid: "release-operator",
      reason: "stale verification must fail",
      auditId: "stale-activation",
      migrationRunId: "audited-run",
    }), /not_verified/);
    await firestore.doc("_migrations/userRelationshipGuardV1").set({
      migrationVersion: 1,
      runId: "audited-run",
      status: "verified",
      sourceFingerprint: "audited-source-fingerprint",
      verificationValidUntil: new Date(Date.now() + 60 * 60 * 1000),
      reconciliationPassed: true,
      anomalyCount: 0,
      mismatchCount: 0,
    });
    const activated = await recordBlockingRolloutTransition({
      firestore,
      enabled: true,
      operatorUid: "release-operator",
      reason: "local emulator activation",
      auditId: "activate-1",
      migrationRunId: "audited-run",
    });
    assert.ok(activated.rolloutVersion >= 1);
    assert.equal((await readBlockingActivationState(firestore)).enabled, true);
    const replay = await recordBlockingRolloutTransition({
      firestore,
      enabled: true,
      operatorUid: "release-operator",
      reason: "local emulator activation",
      auditId: "activate-1",
      migrationRunId: "audited-run",
    });
    assert.equal(replay.idempotentReplay, true);
    const deactivated = await recordBlockingRolloutTransition({
      firestore,
      enabled: false,
      operatorUid: "release-operator",
      reason: "local emergency stop",
      auditId: "deactivate-1",
      migrationRunId: "audited-run",
    });
    assert.equal(deactivated.rolloutVersion, activated.rolloutVersion + 1);
    assert.equal((await readBlockingActivationState(firestore)).enabled, false);
    assert.equal((await firestore.collection("userBlockingActivationAudit")
      .doc("activate-1").get()).exists, true);
    assert.equal((await firestore.collection("userBlockingActivationAudit")
      .doc("deactivate-1").get()).exists, true);
  }, {activationEnabled: false});
});

function acceptedBooking(ids) {
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  booking.parentId = ids.a;
  booking.customerId = ids.a;
  booking.providerId = ids.b;
  booking.serviceOwnerId = ids.b;
  booking.participantIds = [ids.a, ids.b];
  booking.participants.parent.parentId = ids.a;
  booking.participants.provider.providerId = ids.b;
  booking.service.providerId = ids.b;
  for (const slot of booking.schedule.slots) slot.providerId = ids.b;
  return booking;
}

function confirmedBooking(ids) {
  const booking = buildConfirmedSlotBookingFixture();
  booking.parentId = ids.a;
  booking.customerId = ids.a;
  booking.providerId = ids.b;
  booking.serviceOwnerId = ids.b;
  booking.participantIds = [ids.a, ids.b];
  booking.participants.parent.parentId = ids.a;
  booking.participants.provider.providerId = ids.b;
  booking.service.providerId = ids.b;
  for (const slot of booking.schedule.slots) slot.providerId = ids.b;
  return booking;
}

test("directed blocks are idempotent and both owners must unblock", {skip: !enabled}, async () => {
  await fixture(async ({firestore, ids}) => {
    const first = await blockUserDataV1({firestore, actorUid: ids.a, targetUid: ids.b});
    assert.equal(first.idempotentReplay, false);
    const replay = await blockUserDataV1({firestore, actorUid: ids.a, targetUid: ids.b});
    assert.equal(replay.idempotentReplay, true);
    await blockUserDataV1({firestore, actorUid: ids.b, targetUid: ids.a});

    const oneRemoved = await unblockUserDataV1({firestore, actorUid: ids.a, targetUid: ids.b});
    assert.equal(oneRemoved.relationshipBlocked, true);
    const bothRemoved = await unblockUserDataV1({firestore, actorUid: ids.b, targetUid: ids.a});
    assert.equal(bothRemoved.relationshipBlocked, false);
  });
});

test("self-block and missing target fail without creating relationship state", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await assert.rejects(
      blockUserDataV1({firestore, actorUid: ids.a, targetUid: ids.a}),
      errorCode("SELF_BLOCK_NOT_ALLOWED"),
    );
    await assert.rejects(
      blockUserDataV1({firestore, actorUid: ids.a, targetUid: "missing-user"}),
      errorCode("TARGET_USER_NOT_FOUND"),
    );
  });
});

test("accepted unpaid bookings in both directions cancel atomically without refunds", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    const first = acceptedBooking(ids);
    const second = acceptedBooking({a: ids.b, b: ids.a});
    await Promise.all([
      firestore.collection("bookings").doc("accepted-a-b").set(first),
      firestore.collection("bookings").doc("accepted-b-a").set(second),
    ]);
    const result = await blockUserDataV1({firestore, actorUid: ids.a, targetUid: ids.b});
    assert.deepEqual(result.cancelledBookingIds.sort(), ["accepted-a-b", "accepted-b-a"]);
    for (const bookingId of result.cancelledBookingIds) {
      const booking = (await firestore.collection("bookings").doc(bookingId).get()).data();
      assert.equal(booking.state, "CANCELLED");
      assert.equal(booking.cancellation.cancellationType, "user_blocked");
      assert.equal(booking.cancellation.refundAmountPaise, 0);
      assert.equal((await firestore.collection("bookings").doc(bookingId)
        .collection("events").doc("cancelled").get()).exists, true);
    }
  });
});

test("any persisted payment attempt makes accepted booking fail closed", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    const bookingRef = firestore.collection("bookings").doc("accepted-with-order");
    await bookingRef.set(acceptedBooking(ids));
    await bookingRef.collection("paymentAttempts").doc("attempt-1").set({
      state: "ORDER_CREATED",
      razorpayOrderId: "order-1",
    });
    await assert.rejects(
      blockUserDataV1({firestore, actorUid: ids.a, targetUid: ids.b}),
      errorCode("PAYMENT_RECONCILIATION_REQUIRED"),
    );
    assert.equal((await bookingRef.get()).data().state, "ACCEPTED_AWAITING_PAYMENT");
  });
});

test("paid protected booking prevents either participant from blocking", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await firestore.collection("bookings").doc("confirmed").set(confirmedBooking(ids));
    await assert.rejects(
      blockUserDataV1({firestore, actorUid: ids.a, targetUid: ids.b}),
      errorCode("PROTECTED_BOOKING_EXISTS"),
    );
    await assert.rejects(
      blockUserDataV1({firestore, actorUid: ids.b, targetUid: ids.a}),
      errorCode("PROTECTED_BOOKING_EXISTS"),
    );
  });
});

test("historical migration protection blocks both booking directions until reconciled", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    const pair = canonicalUserPair(ids.a, ids.b);
    await firestore.collection("userRelationshipGuards").doc(pair.pairKey).set({
      pairKey: pair.pairKey,
      uidA: pair.uidA,
      uidB: pair.uidB,
      historicalProtectionBlocked: true,
      historicalProtectionReasons: ["MANUAL_SETTLEMENT_OBLIGATION_UNRESOLVED"],
    });
    for (const [actorUid, targetUid] of [[ids.a, ids.b], [ids.b, ids.a]]) {
      await assert.rejects(
        blockUserDataV1({firestore, actorUid, targetUid}),
        errorCode("HISTORICAL_RELATIONSHIP_RECONCILIATION_REQUIRED"),
      );
    }
  });
});

test("payment mutation and block activation cannot both commit", {skip: !enabled}, async () => {
  await fixture(async ({firestore, ids}) => {
    const bookingId = "accepted-race";
    const bookingRef = firestore.collection("bookings").doc(bookingId);
    await bookingRef.set(acceptedBooking(ids));
    const paymentMutation = firestore.runTransaction(async (transaction) => {
      const guard = await readOpenRelationshipGuardInTransaction({
        firestore,
        transaction,
        firstUid: ids.a,
        secondUid: ids.b,
      });
      const latest = await transaction.get(bookingRef);
      if (latest.data().state !== "ACCEPTED_AWAITING_PAYMENT") {
        throw new Error("booking-cancelled");
      }
      transaction.create(bookingRef.collection("paymentAttempts").doc("race-attempt"), {
        state: "ORDER_CREATED",
      });
      transaction.set(guard.ref, openRelationshipGuardMutation({
        pair: guard.pair,
        bookingId,
        operation: "test_payment_order_created",
      }), {merge: true});
      return "payment";
    });
    const blockMutation = blockUserDataV1({
      firestore,
      actorUid: ids.a,
      targetUid: ids.b,
    });
    const results = await Promise.allSettled([paymentMutation, blockMutation]);
    assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
    const pair = canonicalUserPair(ids.a, ids.b);
    const guard = (await firestore.collection("userRelationshipGuards").doc(pair.pairKey).get()).data();
    const attemptExists = (await bookingRef.collection("paymentAttempts").doc("race-attempt").get()).exists;
    assert.notEqual(guard.blocked, attemptExists);
  });
});

test("canonical captured-payment persistence refuses a blocked relationship", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await blockUserDataV1({firestore, actorUid: ids.a, targetUid: ids.b});
    const bookingId = "forged-late-capture";
    const booking = confirmedBooking(ids);
    const attempt = {
      paymentAttemptId: "late-attempt",
      razorpayPaymentId: "late-payment",
    };
    await Promise.all([
      firestore.collection("bookings").doc(bookingId).set(booking),
      firestore.collection("bookings").doc(bookingId)
        .collection("paymentAttempts").doc(attempt.paymentAttemptId).set(attempt),
    ]);
    await assert.rejects(persistFinalizePaymentResultV3({
      firestore,
      bookingId,
      result: {
        ok: true,
        booking,
        paymentAttempt: attempt,
        couponWrite: null,
        notifications: [],
        events: [],
        occupancyWrites: {},
      },
    }), errorCode("USER_RELATIONSHIP_BLOCKED"));
    assert.equal((await firestore.collection("bookings").doc(bookingId).get()).data().state, "CONFIRMED");
  });
});
