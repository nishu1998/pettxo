const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({services: ["firestore"], projectId: "demo-user-blocking"});
const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const {
  blockUserDataV1,
  getUserRelationshipStateDataV1,
  unblockUserDataV1,
} = require("../lib/blocking/userBlocking.js");
const {
  relationshipActivationDecisionId,
} = require("../lib/blocking/relationshipActivationDecisions.js");
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

// --- D2: historical marks are re-judged from live state ----------------------

const HISTORICAL_CODE = "HISTORICAL_RELATIONSHIP_RECONCILIATION_REQUIRED";

async function seedHistoricalMark(firestore, ids, {reasons, markers = []}) {
  const pair = canonicalUserPair(ids.a, ids.b);
  await firestore.collection("userRelationshipGuards").doc(pair.pairKey).set({
    pairKey: pair.pairKey,
    uidA: pair.uidA,
    uidB: pair.uidB,
    historicalProtectionBlocked: true,
    historicalProtectionReasons: reasons,
  });
  for (const marker of markers) {
    await firestore.collection("relationshipMigrationEvidence")
      .doc(`v1_${marker.phase}_${marker.sourceId}`).set({
        schemaVersion: 1,
        migrationVersion: 1,
        runId: "historical-run",
        pairKey: pair.pairKey,
        protected: true,
        blocked: false,
        anomaly: marker.reasonCode === "INVALID_OR_LEGACY_BOOKING",
        sourceUpdateTimeMillis: 1700000000000,
        ...marker,
      });
  }
  return pair;
}

async function seedDecision(firestore, {phase, sourceId, reasonCode, decision, updateTimeMillis}) {
  const recordKey = relationshipActivationDecisionId(phase, sourceId);
  await firestore.collection("relationshipActivationDecisions").doc(recordKey).set({
    schemaVersion: 1,
    phase,
    sourceId,
    recordKey,
    pairKey: "",
    expectedReasonCode: reasonCode,
    expectedSourceUpdateTimeMillis: updateTimeMillis,
    decision,
    decidedByUid: "owner-uid",
    decidedByEmail: "",
    note: "test",
    decisionSetHash: "",
    decidedAt: new Date(),
  });
}

/** blockUserDataV1 and getUserRelationshipStateDataV1 must agree. */
async function expectBlockOutcome(firestore, actorUid, targetUid, pair, expected) {
  const state = await getUserRelationshipStateDataV1({firestore, actorUid, targetUid});
  if (expected.allowed) {
    assert.equal(state.canBlock, true, `state reason ${state.reasonCode}`);
    assert.equal(state.reasonCode, "");
    const result = await blockUserDataV1({firestore, actorUid, targetUid});
    assert.equal(result.relationshipBlocked, true);
    const guard = (await firestore.collection("userRelationshipGuards").doc(pair.pairKey).get()).data();
    assert.equal(guard.historicalProtectionBlocked, false);
    assert.equal(guard.historicalProtectionClearedReason, "LIVE_OBLIGATION_ENDED");
    assert.ok(guard.historicalProtectionClearedAt);
    assert.deepEqual(guard.historicalProtectionReasons, expected.reasons, "reasons kept as history");
    return;
  }
  assert.equal(state.canBlock, false);
  assert.equal(state.reasonCode, HISTORICAL_CODE);
  await assert.rejects(blockUserDataV1({firestore, actorUid, targetUid}), (error) => {
    assert.equal(error.details?.code, HISTORICAL_CODE);
    if (expected.reason) assert.equal(error.details?.reason, expected.reason);
    return true;
  });
  assert.equal((await firestore.collection("userBlocks").doc(`${actorUid}_${targetUid}`).get()).exists, false);
  const guard = (await firestore.collection("userRelationshipGuards").doc(pair.pairKey).get()).data();
  assert.equal(guard.historicalProtectionBlocked, true, "refusal writes nothing");
}

function bothDirections(ids) {
  return [[ids.a, ids.b], [ids.b, ids.a]];
}

const DIRECTIONS = ["a->b", "b->a"];

for (const [index, label] of DIRECTIONS.entries()) {
  test(`D2/D4 ${label}: a mark whose obligation is only a provider payout expires`, {skip: !enabled}, async () => {
    await fixture(async ({firestore, ids}) => {
      const reasons = ["MANUAL_SETTLEMENT_OBLIGATION_UNRESOLVED", "EXTERNAL_PAYOUT_UNRESOLVED"];
      const bookingId = `hist-payout-${ids.a}`;
      const pair = await seedHistoricalMark(firestore, ids, {
        reasons,
        markers: [{phase: "bookings", sourceId: bookingId, reasonCode: "MANUAL_SETTLEMENT_OBLIGATION_UNRESOLVED"}],
      });
      await Promise.all([
        firestore.collection("manualSettlementObligations").doc(`provider_payout_${bookingId}`).set({
          bookingId, obligationType: "PROVIDER_PAYOUT", status: "HELD",
        }),
        firestore.collection("payoutReadiness").doc(bookingId).set({bookingId, status: "HELD"}),
      ]);
      const [actor, target] = bothDirections(ids)[index];
      await expectBlockOutcome(firestore, actor, target, pair, {allowed: true, reasons});
    });
  });

  test(`D2 ${label}: a live customer-refund obligation keeps the mark`, {skip: !enabled}, async () => {
    await fixture(async ({firestore, ids}) => {
      const bookingId = `hist-refund-ob-${ids.a}`;
      const pair = await seedHistoricalMark(firestore, ids, {
        reasons: ["MANUAL_SETTLEMENT_OBLIGATION_UNRESOLVED"],
        markers: [{phase: "bookings", sourceId: bookingId, reasonCode: "MANUAL_SETTLEMENT_OBLIGATION_UNRESOLVED"}],
      });
      await firestore.collection("manualSettlementObligations").doc(`customer_refund_${bookingId}`).set({
        bookingId, obligationType: "CUSTOMER_REFUND", status: "HELD",
      });
      const [actor, target] = bothDirections(ids)[index];
      await expectBlockOutcome(firestore, actor, target, pair, {
        allowed: false, reason: "MANUAL_SETTLEMENT_OBLIGATION_UNRESOLVED",
      });
    });
  });

  test(`D2 ${label}: a pending refunds/{id} keeps the mark, and its completion releases it`, {skip: !enabled}, async () => {
    await fixture(async ({firestore, ids}) => {
      const bookingId = `hist-refund-${ids.a}`;
      const reasons = ["EXTERNAL_REFUND_UNRESOLVED"];
      const pair = await seedHistoricalMark(firestore, ids, {
        reasons,
        markers: [{phase: "bookings", sourceId: bookingId, reasonCode: "EXTERNAL_REFUND_UNRESOLVED"}],
      });
      await firestore.collection("refunds").doc(bookingId).set({bookingId, status: "PENDING"});
      const [actor, target] = bothDirections(ids)[index];
      await expectBlockOutcome(firestore, actor, target, pair, {
        allowed: false, reason: "EXTERNAL_REFUND_UNRESOLVED",
      });
      await firestore.collection("refunds").doc(bookingId).set({bookingId, status: "PROCESSED"});
      await expectBlockOutcome(firestore, actor, target, pair, {allowed: true, reasons});
    });
  });

  test(`D2 ${label}: a live dispute record on a pair booking keeps the mark`, {skip: !enabled}, async () => {
    await fixture(async ({firestore, ids}) => {
      const bookingId = `hist-dispute-${ids.a}`;
      const pair = await seedHistoricalMark(firestore, ids, {
        reasons: ["EXTERNAL_DISPUTE_UNRESOLVED"],
        markers: [{phase: "bookings", sourceId: bookingId, reasonCode: "EXTERNAL_DISPUTE_UNRESOLVED"}],
      });
      await firestore.collection("disputes").doc(bookingId).set({bookingId, status: "OPEN"});
      const [actor, target] = bothDirections(ids)[index];
      await expectBlockOutcome(firestore, actor, target, pair, {
        allowed: false, reason: "EXTERNAL_DISPUTE_UNRESOLVED",
      });
    });
  });

  test(`D2/D3 ${label}: an unparsable record needs a matching NO_OBLIGATION decision`, {skip: !enabled}, async () => {
    await fixture(async ({firestore, ids}) => {
      const sourceId = `legacy-${ids.a}`;
      const reasons = ["INVALID_OR_LEGACY_BOOKING"];
      const pair = await seedHistoricalMark(firestore, ids, {
        reasons,
        markers: [{phase: "bookings", sourceId, reasonCode: "INVALID_OR_LEGACY_BOOKING"}],
      });
      const [actor, target] = bothDirections(ids)[index];
      // No decision.
      await expectBlockOutcome(firestore, actor, target, pair, {allowed: false, reason: "INVALID_OR_LEGACY_BOOKING"});
      // Stale decision (record changed since the scan).
      await seedDecision(firestore, {
        phase: "bookings", sourceId, reasonCode: "INVALID_OR_LEGACY_BOOKING",
        decision: "NO_OBLIGATION", updateTimeMillis: 1700000000001,
      });
      await expectBlockOutcome(firestore, actor, target, pair, {allowed: false, reason: "INVALID_OR_LEGACY_BOOKING"});
      // PROTECT_PAIR keeps refusing.
      await seedDecision(firestore, {
        phase: "bookings", sourceId, reasonCode: "INVALID_OR_LEGACY_BOOKING",
        decision: "PROTECT_PAIR", updateTimeMillis: 1700000000000,
      });
      await expectBlockOutcome(firestore, actor, target, pair, {allowed: false, reason: "INVALID_OR_LEGACY_BOOKING"});
      // Matching NO_OBLIGATION releases.
      await seedDecision(firestore, {
        phase: "bookings", sourceId, reasonCode: "INVALID_OR_LEGACY_BOOKING",
        decision: "NO_OBLIGATION", updateTimeMillis: 1700000000000,
      });
      await expectBlockOutcome(firestore, actor, target, pair, {allowed: true, reasons});
    });
  });

  test(`D2 ${label}: fail closed without evidence or with an unknown reason`, {skip: !enabled}, async () => {
    await fixture(async ({firestore, ids}) => {
      const [actor, target] = bothDirections(ids)[index];
      const missingEvidence = await seedHistoricalMark(firestore, ids, {reasons: ["INVALID_OR_LEGACY_BOOKING"]});
      await expectBlockOutcome(firestore, actor, target, missingEvidence, {
        allowed: false, reason: "INVALID_OR_LEGACY_BOOKING",
      });
      const unknown = await seedHistoricalMark(firestore, ids, {reasons: ["SOMETHING_NEW"]});
      await expectBlockOutcome(firestore, actor, target, unknown, {allowed: false, reason: "SOMETHING_NEW"});
      const empty = await seedHistoricalMark(firestore, ids, {reasons: []});
      await expectBlockOutcome(firestore, actor, target, empty, {
        allowed: false, reason: "HISTORICAL_REASON_UNKNOWN",
      });
    });
  });

  test(`D2 ${label}: a live protected booking still refuses through the live classifier`, {skip: !enabled}, async () => {
    await fixture(async ({firestore, ids}) => {
      const pair = await seedHistoricalMark(firestore, ids, {reasons: ["PROTECTED_STATE_CONFIRMED"]});
      await firestore.collection("bookings").doc(`hist-live-${ids.a}`).set(confirmedBooking(ids));
      const [actor, target] = bothDirections(ids)[index];
      const state = await getUserRelationshipStateDataV1({firestore, actorUid: actor, targetUid: target});
      assert.equal(state.canBlock, false);
      assert.equal(state.reasonCode, "PROTECTED_STATE_CONFIRMED");
      await assert.rejects(blockUserDataV1({firestore, actorUid: actor, targetUid: target}), (error) => {
        assert.equal(error.details?.code, "PROTECTED_BOOKING_EXISTS");
        assert.equal(error.details?.reason, "PROTECTED_STATE_CONFIRMED");
        return true;
      });
      assert.equal((await firestore.collection("userRelationshipGuards").doc(pair.pairKey).get())
        .data().historicalProtectionBlocked, true);
    });
  });
}

test("an unmarked pair does not read external obligation records", {skip: !enabled}, async () => {
  await fixture(async ({firestore, ids}) => {
    // A pending refund for a pair booking without a historical mark does not
    // change today's behaviour: only the live booking classifier applies.
    await firestore.collection("refunds").doc(`unmarked-${ids.a}`).set({status: "PENDING"});
    const state = await getUserRelationshipStateDataV1({firestore, actorUid: ids.a, targetUid: ids.b});
    assert.equal(state.canBlock, true);
    await blockUserDataV1({firestore, actorUid: ids.a, targetUid: ids.b});
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
