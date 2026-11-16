const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({services: ["firestore"], projectId: "demo-relationship-migration"});
const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const {
  runReadOnlyHistoricalRelationshipAudit,
  runHistoricalRelationshipMigrationPage,
  verifyAndRecordRelationshipMigration,
} = require("../lib/blocking/historicalRelationshipMigration.js");
const {canonicalUserPair} = require("../lib/blocking/relationshipGuard.js");
const {
  buildAcceptedAwaitingPaymentSlotBookingFixture,
  buildCompletedFinalBookingFixture,
  buildConfirmedRangeBookingFixture,
  buildConfirmedSlotBookingFixture,
} = require("../lib/booking/schema/bookingFixtures.js");

const enabled = firebaseEmulator.enabled;

function assignPair(booking, parentId, providerId) {
  booking.parentId = parentId;
  booking.customerId = parentId;
  booking.providerId = providerId;
  booking.serviceOwnerId = providerId;
  booking.participantIds = [parentId, providerId];
  booking.participants.parent.parentId = parentId;
  booking.participants.provider.providerId = providerId;
  booking.service.providerId = providerId;
  for (const slot of booking.schedule?.slots ?? []) slot.providerId = providerId;
  return booking;
}

async function allPages(firestore, phase, mode, runId) {
  const totals = {scannedCount: 0, protectedCount: 0, anomalyCount: 0,
    appliedCount: 0, alreadyAppliedCount: 0, mismatchCount: 0};
  let cursor = null;
  do {
    const page = await runHistoricalRelationshipMigrationPage({
      firestore,
      phase,
      mode,
      runId,
      cursor,
      pageSize: 2,
      authoritativeNow: new Date("2026-07-30T00:00:00.000Z"),
    });
    for (const key of Object.keys(totals)) totals[key] += page[key];
    cursor = page.nextCursor;
  } while (cursor);
  return totals;
}

test("historical relationship migration is resumable, idempotent, and fail-closed", {
  skip: !enabled,
}, async () => {
  const app = initializeApp({projectId: "demo-relationship-migration"},
    `migration-${randomUUID()}`);
  const firestore = getFirestore(app);
  firestore.settings({ignoreUndefinedProperties: true});
  try {
    const confirmed = assignPair(buildConfirmedSlotBookingFixture(), "customer-a", "provider-a");
    const range = assignPair(buildConfirmedRangeBookingFixture(), "customer-b", "provider-b");
    const accepted = assignPair(buildAcceptedAwaitingPaymentSlotBookingFixture(), "customer-c", "provider-c");
    const settled = assignPair(buildCompletedFinalBookingFixture(), "customer-d", "provider-d");
    settled.lifecycle.reviewWindowEndsAt = new Date("2026-07-25T00:00:00.000Z");
    settled.lifecycle.disputeDeadlineAt = new Date("2026-07-25T00:00:00.000Z");
    settled.dispute.status = "resolved";
    settled.payout.status = "released";
    settled.payment.status = "paid";
    const uncertain = assignPair(buildAcceptedAwaitingPaymentSlotBookingFixture(),
      "customer-e", "provider-e");
    await Promise.all([
      firestore.doc("userBlocks/customer-z_provider-z").set({
        ownerUserId: "customer-z",
        blockedUserId: "provider-z",
      }),
      firestore.doc("bookings/01-confirmed").set(confirmed),
      firestore.doc("bookings/02-range").set(range),
      firestore.doc("bookings/03-accepted").set(accepted),
      firestore.doc("bookings/04-settled").set(settled),
      firestore.doc("bookings/05-uncertain").set(uncertain),
      firestore.doc("bookings/05-uncertain/paymentAttempts/attempt-1").set({
        state: "ORDER_CREATED",
      }),
      firestore.doc("manualSettlementObligations/obligation-1").set({
        bookingId: "04-settled",
        status: "PROCESSING",
      }),
      firestore.doc("bookings/06-legacy").set({
        customerId: "customer-f",
        serviceOwnerId: "provider-f",
        status: "confirmed",
      }),
    ]);

    const dryBlocks = await allPages(firestore, "blocks", "dry-run", "run-1");
    const dryBookings = await allPages(firestore, "bookings", "dry-run", "run-1");
    assert.equal(dryBlocks.scannedCount, 1);
    assert.equal(dryBookings.scannedCount, 6);
    assert.equal((await firestore.collection("relationshipMigrationEvidence").get()).empty, true);
    assert.equal(dryBookings.protectedCount, 5);
    assert.equal(dryBookings.anomalyCount, 2);

    assert.equal((await allPages(firestore, "blocks", "apply", "run-1")).appliedCount, 1);
    assert.equal((await allPages(firestore, "bookings", "apply", "run-1")).appliedCount, 6);
    assert.equal((await allPages(firestore, "bookings", "apply", "run-1")).alreadyAppliedCount, 6);
    assert.equal((await allPages(firestore, "blocks", "reconcile", "run-1")).mismatchCount, 0);
    assert.equal((await allPages(firestore, "bookings", "reconcile", "run-1")).mismatchCount, 0);

    const blockedPair = canonicalUserPair("customer-z", "provider-z");
    const blockedGuard = (await firestore.collection("userRelationshipGuards")
      .doc(blockedPair.pairKey).get()).data();
    assert.equal(blockedGuard.blocked, true);
    assert.deepEqual(blockedGuard.activeDirectedBlockIds, ["customer-z_provider-z"]);
    const legacyPair = canonicalUserPair("customer-f", "provider-f");
    assert.equal((await firestore.collection("userRelationshipGuards")
      .doc(legacyPair.pairKey).get()).data().historicalProtectionBlocked, true);

    await assert.rejects(verifyAndRecordRelationshipMigration({
      firestore,
      runId: "run-1",
      operatorUid: "local-test",
      strategy: "exception-backfill",
      authoritativeNow: new Date("2026-07-30T00:00:00.000Z"),
    }), /not_verifiable/);
  } finally {
    await firestore.terminate();
    await deleteApp(app);
  }
});

test("clean migration can record verified readiness only after reconciliation", {
  skip: !enabled,
}, async () => {
  const app = initializeApp({projectId: "demo-clean-relationship-migration"},
    `clean-migration-${randomUUID()}`);
  const firestore = getFirestore(app);
  firestore.settings({ignoreUndefinedProperties: true});
  try {
    await firestore.doc("bookings/settled").set(assignPair(
      buildAcceptedAwaitingPaymentSlotBookingFixture(), "clean-a", "clean-b"));
    await allPages(firestore, "bookings", "dry-run", "clean-run");
    await allPages(firestore, "bookings", "apply", "clean-run");
    const reconciliation = await allPages(firestore, "bookings", "reconcile", "clean-run");
    assert.equal(reconciliation.mismatchCount, 0);
    const verification = await verifyAndRecordRelationshipMigration({
      firestore,
      runId: "clean-run",
      operatorUid: "local-test",
      strategy: "exception-backfill",
      authoritativeNow: new Date("2026-07-30T00:00:00.000Z"),
    });
    assert.equal(verification.bookingCount, 1);
    assert.equal(verification.requiredEvidenceCount, 1);
    assert.match(verification.sourceFingerprint, /^[a-f0-9]{64}$/);
    assert.equal((await firestore.doc("_migrations/userRelationshipGuardV1").get()).data().status,
      "verified");
  } finally {
    await firestore.terminate();
    await deleteApp(app);
  }
});

test("zero-protected baseline verifies blocks without creating guards for harmless history", {
  skip: !enabled,
}, async () => {
  const app = initializeApp({projectId: "demo-zero-baseline-migration"},
    `zero-migration-${randomUUID()}`);
  const firestore = getFirestore(app);
  firestore.settings({ignoreUndefinedProperties: true});
  try {
    const settled = assignPair(buildCompletedFinalBookingFixture(), "zero-a", "zero-b");
    settled.lifecycle.reviewWindowEndsAt = new Date("2026-07-25T00:00:00.000Z");
    settled.lifecycle.disputeDeadlineAt = new Date("2026-07-25T00:00:00.000Z");
    settled.dispute.status = "resolved";
    settled.payout.status = "released";
    settled.payment.status = "paid";
    await Promise.all([
      firestore.doc("bookings/settled-history").set(settled),
      firestore.doc("userBlocks/zero-c_zero-d").set({
        ownerUserId: "zero-c",
        blockedUserId: "zero-d",
      }),
    ]);
    const beforeMigration = await runReadOnlyHistoricalRelationshipAudit({
      firestore,
      authoritativeNow: new Date("2026-07-30T00:00:00.000Z"),
      pageSize: 1,
    });
    assert.equal(beforeMigration.fullTraversal, true);
    assert.equal(beforeMigration.totalHistoricalBookingCount, 1);
    assert.equal(beforeMigration.currentlyProtectedPaidBookingCount, 0);
    assert.equal(beforeMigration.acceptedUnpaidBookingCount, 0);
    assert.equal(beforeMigration.uncertainPaymentStateCount, 0);
    assert.equal(beforeMigration.existingDirectedBlockCount, 1);
    assert.equal(beforeMigration.existingRelationshipGuardCount, 0);
    assert.equal(beforeMigration.inconsistentHistoricalBlockBookingPairCount, 1);
    assert.equal(beforeMigration.manualReviewCount, 1);
    await allPages(firestore, "blocks", "apply", "zero-run");
    const afterMigration = await runReadOnlyHistoricalRelationshipAudit({
      firestore,
      authoritativeNow: new Date("2026-07-30T00:00:00.000Z"),
      pageSize: 1,
    });
    assert.equal(afterMigration.existingRelationshipGuardCount, 1);
    assert.equal(afterMigration.inconsistentHistoricalBlockBookingPairCount, 0);
    assert.equal(afterMigration.manualReviewCount, 0);
    const verification = await verifyAndRecordRelationshipMigration({
      firestore,
      runId: "zero-run",
      operatorUid: "local-test",
      strategy: "zero-protected-baseline",
      authoritativeNow: new Date("2026-07-30T00:00:00.000Z"),
      pageSize: 1,
    });
    assert.equal(verification.bookingCount, 1);
    assert.equal(verification.directedBlockCount, 1);
    assert.equal(verification.requiredEvidenceCount, 1);
    assert.equal((await firestore.collection("userRelationshipGuards")
      .doc(canonicalUserPair("zero-a", "zero-b").pairKey).get()).exists, false);

    await firestore.doc("bookings/new-unpaid").set(assignPair(
      buildAcceptedAwaitingPaymentSlotBookingFixture(), "zero-e", "zero-f"));
    const concurrentAccepted = await verifyAndRecordRelationshipMigration({
      firestore,
      runId: "zero-run",
      operatorUid: "local-test",
      strategy: "zero-protected-baseline",
      authoritativeNow: new Date("2026-07-30T00:00:00.000Z"),
      pageSize: 1,
    });
    assert.equal(concurrentAccepted.bookingCount, 2);
    await firestore.doc("bookings/new-unpaid/paymentAttempts/attempt-1").set({
      state: "ORDER_CREATED",
    });
    await assert.rejects(verifyAndRecordRelationshipMigration({
      firestore,
      runId: "zero-run",
      operatorUid: "local-test",
      strategy: "zero-protected-baseline",
      authoritativeNow: new Date("2026-07-30T00:00:00.000Z"),
      pageSize: 1,
    }), /not_verifiable/);
  } finally {
    await firestore.terminate();
    await deleteApp(app);
  }
});
