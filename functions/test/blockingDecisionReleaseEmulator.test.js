// Phase 3B-4e (T1): live blocking checks honour D3 NO_OBLIGATION decisions.
const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({
  services: ["firestore"],
  projectId: "demo-decision-release",
});
const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const enabled = firebaseEmulator.enabled;
let ub;
let fx;
let decisions;
let race;

async function withProject(run) {
  const app = initializeApp({projectId: "demo-decision-release"}, `release-${randomUUID()}`);
  const db = getFirestore(app);
  db.settings({ignoreUndefinedProperties: true});
  const sfx = randomUUID().slice(0, 8);
  const ids = {a: `rel-a-${sfx}`, b: `rel-b-${sfx}`, sfx};
  try {
    await Promise.all([
      db.doc(`users/${ids.a}`).set({uid: ids.a, accountStatus: "active"}),
      db.doc(`users/${ids.b}`).set({uid: ids.b, accountStatus: "active"}),
      db.doc("_migrations/userRelationshipGuardV1").set({migrationVersion: 1, runId: "rel", status: "verified",
        sourceFingerprint: "fp", reconciliationPassed: true, anomalyCount: 0, mismatchCount: 0}),
      db.doc("userBlockingActivationAudit/rel").set({event: "ACTIVATE", enabled: true, migrationRunId: "rel",
        sourceFingerprint: "fp", rolloutVersion: 1}),
      db.doc("_rollouts/userBlockingV1").set({enabled: true, status: "active", migrationRunId: "rel",
        sourceFingerprint: "fp", activationAuditId: "rel", rolloutVersion: 1}),
    ]);
    await run(db, ids);
  } finally {
    await db.terminate();
    await deleteApp(app);
  }
}

function pairify(booking, parent, provider) {
  booking.parentId = parent;
  booking.customerId = parent;
  booking.providerId = provider;
  booking.serviceOwnerId = provider;
  booking.participantIds = [parent, provider];
  booking.participants.parent.parentId = parent;
  booking.participants.provider.providerId = provider;
  booking.service.providerId = provider;
  for (const slot of booking.schedule?.slots ?? []) slot.providerId = provider;
  return booking;
}

/** Legacy / invalid booking that still carries parentId + providerId. */
async function seedLegacy(db, ids) {
  const id = `legacy-${ids.sfx}`;
  await db.doc(`bookings/${id}`).set({parentId: ids.a, providerId: ids.b, customerId: ids.a, status: "confirmed"});
  return id;
}

/** Stuck ACCEPTED_AWAITING_PAYMENT with payment evidence (financials, attempt, mapping). */
async function seedStuckAccepted(db, ids) {
  const id = `stuck-${ids.sfx}`;
  // Race fixture: accepted booking carrying the real pricing snapshot as financials.
  const booking = pairify(race.buildCanonicalPaymentRaceFixture().booking, ids.a, ids.b);
  booking.payment.paymentAttemptId = `att-${ids.sfx}`;
  booking.payment.razorpayOrderId = `order_${ids.sfx}`;
  await Promise.all([
    db.doc(`bookings/${id}`).set(booking),
    db.doc(`bookings/${id}/paymentAttempts/att-${ids.sfx}`).set({state: "CAPTURED_REQUIRES_RECONCILIATION",
      razorpayPaymentId: `pay_${ids.sfx}`, bookingId: id}),
    db.doc(`canonicalPaymentOrderMappings/order_${ids.sfx}`).set({bookingId: id, paymentAttemptId: `att-${ids.sfx}`}),
  ]);
  return id;
}

async function decide(db, bookingId, decision, {timeOffset = 0} = {}) {
  const snapshot = await db.doc(`bookings/${bookingId}`).get();
  const recordKey = decisions.relationshipActivationDecisionId("bookings", bookingId);
  await db.doc(`relationshipActivationDecisions/${recordKey}`).set({
    schemaVersion: 1,
    phase: "bookings",
    sourceId: bookingId,
    recordKey,
    pairKey: "",
    expectedReasonCode: "INVALID_OR_LEGACY_BOOKING",
    expectedSourceUpdateTimeMillis: snapshot.updateTime.toMillis() + timeOffset,
    decision,
    decidedByUid: "owner-uid",
    decidedByEmail: "",
    note: "",
    decisionSetHash: "",
    decidedAt: new Date(),
  });
}

/** State and block must agree; returns {canBlock, reasonCode, blockCode}. */
async function verdict(db, actor, target) {
  const state = await ub.getUserRelationshipStateDataV1({firestore: db, actorUid: actor, targetUid: target});
  let blockCode = "";
  let cancelled = [];
  try {
    const result = await ub.blockUserDataV1({firestore: db, actorUid: actor, targetUid: target});
    cancelled = result.cancelledBookingIds;
    await ub.unblockUserDataV1({firestore: db, actorUid: actor, targetUid: target});
  } catch (error) {
    blockCode = error.details?.code ?? error.message;
  }
  assert.equal(state.canBlock, blockCode === "", `state ${JSON.stringify(state)} vs block ${blockCode}`);
  return {canBlock: state.canBlock, reasonCode: state.reasonCode, blockCode, cancelled};
}

test.before(() => {
  if (!enabled) return;
  ub = require("../lib/blocking/userBlocking.js");
  fx = require("../lib/booking/schema/bookingFixtures.js");
  decisions = require("../lib/blocking/relationshipActivationDecisions.js");
  race = require("./helpers/canonicalPaymentRaceFixture.js");
});

for (const direction of ["a->b", "b->a"]) {
  const actorTarget = (ids) => direction === "a->b" ? [ids.a, ids.b] : [ids.b, ids.a];

  test(`${direction}: a legacy/invalid booking is released by a matching NO_OBLIGATION decision`, {skip: !enabled}, async () => {
    await withProject(async (db, ids) => {
      const legacy = await seedLegacy(db, ids);
      const before = await verdict(db, ...actorTarget(ids));
      assert.equal(before.reasonCode, "INVALID_CANONICAL_BOOKING");
      assert.equal(before.blockCode, "INVALID_CANONICAL_BOOKING");
      await decide(db, legacy, "NO_OBLIGATION");
      const after = await verdict(db, ...actorTarget(ids));
      assert.equal(after.canBlock, true);
      assert.equal(after.blockCode, "");
    });
  });

  test(`${direction}: a stuck accepted booking with payment evidence is released and left untouched`, {skip: !enabled}, async () => {
    await withProject(async (db, ids) => {
      const stuck = await seedStuckAccepted(db, ids);
      const before = await verdict(db, ...actorTarget(ids));
      assert.equal(before.reasonCode, "PAYMENT_RECONCILIATION_REQUIRED");
      assert.equal(before.blockCode, "PAYMENT_RECONCILIATION_REQUIRED");
      await decide(db, stuck, "NO_OBLIGATION");
      const after = await verdict(db, ...actorTarget(ids));
      assert.equal(after.canBlock, true);
      assert.deepEqual(after.cancelled, [], "a released booking is not cancelled by the block");
      assert.equal((await db.doc(`bookings/${stuck}`).get()).data().state, "ACCEPTED_AWAITING_PAYMENT");
    });
  });

  test(`${direction}: stale, PROTECT_PAIR and BLOCK_ACTIVATION decisions do not release`, {skip: !enabled}, async () => {
    await withProject(async (db, ids) => {
      const legacy = await seedLegacy(db, ids);
      await decide(db, legacy, "NO_OBLIGATION", {timeOffset: 1});
      assert.equal((await verdict(db, ...actorTarget(ids))).reasonCode, "INVALID_CANONICAL_BOOKING");
      for (const decision of ["PROTECT_PAIR", "BLOCK_ACTIVATION"]) {
        await decide(db, legacy, decision);
        assert.equal((await verdict(db, ...actorTarget(ids))).reasonCode, "INVALID_CANONICAL_BOOKING", decision);
      }
      // A matching decision releases; a later change to the booking makes it stale again.
      await decide(db, legacy, "NO_OBLIGATION");
      assert.equal((await verdict(db, ...actorTarget(ids))).canBlock, true);
      await db.doc(`bookings/${legacy}`).update({touchedAt: new Date()});
      assert.equal((await verdict(db, ...actorTarget(ids))).reasonCode, "INVALID_CANONICAL_BOOKING");
    });
  });

  test(`${direction}: a malformed decision document does not release`, {skip: !enabled}, async () => {
    await withProject(async (db, ids) => {
      const legacy = await seedLegacy(db, ids);
      const snapshot = await db.doc(`bookings/${legacy}`).get();
      await db.doc(`relationshipActivationDecisions/bookings__${legacy}`).set({
        decision: "NO_OBLIGATION", expectedSourceUpdateTimeMillis: snapshot.updateTime.toMillis(),
      });
      assert.equal((await verdict(db, ...actorTarget(ids))).reasonCode, "INVALID_CANONICAL_BOOKING");
    });
  });

  test(`${direction}: only the released booking is skipped; other bookings still count`, {skip: !enabled}, async () => {
    await withProject(async (db, ids) => {
      const legacy = await seedLegacy(db, ids);
      await decide(db, legacy, "NO_OBLIGATION");
      const confirmed = pairify(fx.buildConfirmedSlotBookingFixture(), ids.a, ids.b);
      await db.doc(`bookings/confirmed-${ids.sfx}`).set(confirmed);
      const result = await verdict(db, ...actorTarget(ids));
      assert.equal(result.reasonCode, "PROTECTED_STATE_CONFIRMED");
      assert.equal(result.blockCode, "PROTECTED_BOOKING_EXISTS");
    });
  });
}
