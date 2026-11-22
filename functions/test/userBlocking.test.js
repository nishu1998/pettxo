require("./helpers/firebaseTestSafety").assertUnitTestIsolation();
const test = require("node:test");
const assert = require("node:assert/strict");

const {
  cancelAcceptedUnpaidBookingForBlockV1,
  classifyRelationshipProtectionV1,
} = require("../lib/blocking/userBlocking.js");
const {
  canonicalUserPair,
} = require("../lib/blocking/relationshipGuard.js");
const {
  buildAcceptedAwaitingPaymentSlotBookingFixture,
  buildCompletedFinalBookingFixture,
  buildConfirmedSlotBookingFixture,
  buildConfirmedRangeBookingFixture,
} = require("../lib/booking/schema/bookingFixtures.js");

test("canonical relationship pair is symmetric and collision resistant", () => {
  const forward = canonicalUserPair("user_a", "user_b_c");
  const reverse = canonicalUserPair("user_b_c", "user_a");
  const different = canonicalUserPair("user_a_user_b", "c");
  assert.deepEqual(forward, reverse);
  assert.notEqual(forward.pairKey, different.pairKey);
});

test("accepted unpaid booking is cancellable while confirmed booking is protected", () => {
  const now = new Date("2026-07-22T10:30:00.000Z");
  assert.deepEqual(classifyRelationshipProtectionV1({
    booking: buildAcceptedAwaitingPaymentSlotBookingFixture(),
    authoritativeNow: now,
  }), {kind: "accepted_unpaid", reason: "ACCEPTED_UNPAID"});
  const confirmed = classifyRelationshipProtectionV1({
    booking: buildConfirmedSlotBookingFixture(),
    authoritativeNow: now,
  });
  assert.equal(confirmed.kind, "protected");
  assert.equal(confirmed.reason, "PROTECTED_STATE_CONFIRMED");
});

test("completed final booking is released only after deadlines and finance settle", () => {
  const booking = buildCompletedFinalBookingFixture();
  booking.lifecycle.reviewWindowEndsAt = new Date("2026-07-24T10:00:00.000Z");
  booking.lifecycle.disputeDeadlineAt = new Date("2026-07-24T10:00:00.000Z");
  booking.dispute.status = "resolved";
  booking.payout.status = "released";
  booking.payment.status = "paid";
  const beforeDeadline = classifyRelationshipProtectionV1({
    booking,
    authoritativeNow: new Date(booking.lifecycle.reviewWindowEndsAt.getTime() - 1),
  });
  assert.equal(beforeDeadline.kind, "protected");
  const afterDeadline = classifyRelationshipProtectionV1({
    booking,
    authoritativeNow: new Date(booking.lifecycle.reviewWindowEndsAt.getTime() + 1),
  });
  assert.equal(afterDeadline.kind, "unprotected");
});

test("D4: a pending provider payout no longer protects; customer refunds still do", () => {
  const afterDeadlines = new Date("2026-07-25T10:00:00.000Z");
  const settledBooking = () => {
    const booking = buildCompletedFinalBookingFixture();
    booking.lifecycle.reviewWindowEndsAt = new Date("2026-07-24T10:00:00.000Z");
    booking.lifecycle.disputeDeadlineAt = new Date("2026-07-24T10:00:00.000Z");
    booking.dispute.status = "resolved";
    booking.payment.status = "paid";
    return booking;
  };
  for (const payoutStatus of ["pending", "eligible", "held", "processing", "failed", "scheduled"]) {
    const booking = settledBooking();
    booking.payout.status = payoutStatus;
    assert.deepEqual(
      classifyRelationshipProtectionV1({booking, authoritativeNow: afterDeadlines}),
      {kind: "unprotected", reason: "NO_PROTECTED_OBLIGATION"},
      `payout.status ${payoutStatus}`,
    );
  }
  for (const paymentStatus of ["refund_required", "refund_pending", "captured"]) {
    const booking = settledBooking();
    booking.payout.status = "released";
    booking.payment.status = paymentStatus;
    assert.deepEqual(
      classifyRelationshipProtectionV1({booking, authoritativeNow: afterDeadlines}),
      {kind: "protected", reason: "FINANCIAL_OBLIGATION_UNRESOLVED"},
      `payment.status ${paymentStatus}`,
    );
  }
});

test("in-progress, dispute-window, active-dispute, and multi-day bookings stay protected", () => {
  const now = new Date("2026-07-23T10:00:00.000Z");
  const inProgress = buildConfirmedSlotBookingFixture();
  inProgress.state = "IN_PROGRESS";
  inProgress.stateQueryValue = "IN_PROGRESS";
  assert.equal(classifyRelationshipProtectionV1({booking: inProgress, authoritativeNow: now}).kind, "protected");

  const disputed = buildCompletedFinalBookingFixture();
  disputed.dispute.status = "open";
  assert.equal(classifyRelationshipProtectionV1({booking: disputed, authoritativeNow: now}).reason, "ACTIVE_DISPUTE");

  const multiDay = buildConfirmedRangeBookingFixture();
  assert.equal(classifyRelationshipProtectionV1({booking: multiDay, authoritativeNow: now}).kind, "protected");
});

test("accepted unpaid block cancellation preserves history and creates no refund", () => {
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  const result = cancelAcceptedUnpaidBookingForBlockV1({
    bookingId: "booking-1",
    booking,
    blockerUid: booking.parentId,
    targetUid: booking.providerId,
    authoritativeNow: new Date("2026-07-22T10:30:00.000Z"),
  });
  assert.equal(result.booking.state, "CANCELLED");
  assert.equal(result.booking.cancellation.cancellationType, "user_blocked");
  assert.equal(result.booking.cancellation.cancelReasonCode, "USER_BLOCKED_BEFORE_PAYMENT");
  assert.equal(result.booking.cancellation.refundAmountPaise, 0);
  assert.equal(result.booking.financials, null);
  assert.equal(result.event.record.event, "cancelled");
});

test("blocking callables are Gen 2 functions in asia-south1", () => {
  const functions = require("../lib/blocking/userBlockingFunctions.js");
  for (const name of ["blockUserV1", "unblockUserV1", "getUserRelationshipStateV1"]) {
    const callable = functions[name];
    assert.equal(callable.__endpoint.platform, "gcfv2");
    assert.deepEqual(callable.__endpoint.region, ["asia-south1"]);
    assert.equal(callable.__endpoint.callableTrigger != null, true);
  }
});

test("block callable rejects unauthenticated and self-block requests before data access", async () => {
  const {blockUserV1} = require("../lib/blocking/userBlockingFunctions.js");
  await assert.rejects(blockUserV1.run({data: {targetUid: "target"}}), {
    code: "unauthenticated",
  });
  await assert.rejects(blockUserV1.run({
    auth: {uid: "same-user"},
    data: {targetUid: "same-user"},
  }), (error) => error.details?.code === "SELF_BLOCK_NOT_ALLOWED");
});

test("activation documents must agree on migration run, audit, and rollout version", async () => {
  const {readBlockingActivationState} = require("../lib/blocking/blockingActivationGate.js");
  const documents = new Map();
  const firestore = {
    doc(path) {
      return {get: async () => ({exists: documents.has(path), data: () => documents.get(path)})};
    },
    collection(path) {
      return {doc: (id) => ({get: async () => ({
        exists: documents.has(`${path}/${id}`),
        data: () => documents.get(`${path}/${id}`),
      })})};
    },
  };
  assert.equal((await readBlockingActivationState(firestore)).enabled, false);
  documents.set("_rollouts/userBlockingV1", {
    enabled: true,
    status: "active",
    migrationRunId: "run-1",
    activationAuditId: "audit-1",
    rolloutVersion: 2,
    sourceFingerprint: "fingerprint-1",
    verificationValidUntil: new Date(Date.now() + 60 * 60 * 1000),
  });
  documents.set("_migrations/userRelationshipGuardV1", {
    migrationVersion: 1,
    status: "verified",
    runId: "run-1",
    reconciliationPassed: true,
    anomalyCount: 0,
    mismatchCount: 0,
    sourceFingerprint: "fingerprint-1",
  });
  documents.set("userBlockingActivationAudit/audit-1", {
    event: "ACTIVATE",
    enabled: true,
    migrationRunId: "run-1",
    rolloutVersion: 1,
    sourceFingerprint: "fingerprint-1",
  });
  assert.equal((await readBlockingActivationState(firestore)).reasonCode,
    "BLOCKING_ACTIVATION_NOT_AUDITED");
  documents.get("userBlockingActivationAudit/audit-1").rolloutVersion = 2;
  assert.equal((await readBlockingActivationState(firestore)).enabled, true);
});

test("D4/D2: only PROVIDER_PAYOUT obligations stop protecting; unknown types fail closed", async () => {
  const {liveCustomerObligationReason} = require("../lib/blocking/historicalProtection.js");
  const fakeFirestore = {
    collection: (name) => ({
      doc: (id) => ({path: `${name}/${id}`}),
      where: () => ({limit: () => ({collection: name})}),
    }),
  };
  async function reasonFor(obligation) {
    return liveCustomerObligationReason({
      firestore: fakeFirestore,
      bookingId: "booking-1",
      reader: {
        getDoc: async () => ({exists: false, data: () => undefined}),
        getQuery: async () => ({docs: obligation ? [{data: () => obligation}] : []}),
      },
    });
  }
  assert.equal(await reasonFor(null), "");
  assert.equal(await reasonFor({obligationType: "PROVIDER_PAYOUT", status: "HELD"}), "");
  assert.equal(await reasonFor({obligationType: "provider_payout", status: "READY"}), "");
  for (const obligation of [
    {obligationType: "CUSTOMER_REFUND", status: "HELD"},
    {status: "PROCESSING"},
    {obligationType: "SOMETHING_NEW", status: "READY"},
    {type: "CUSTOMER_REFUND", status: "NEEDS_ATTENTION"},
  ]) {
    assert.equal(await reasonFor(obligation), "MANUAL_SETTLEMENT_OBLIGATION_UNRESOLVED", JSON.stringify(obligation));
  }
  assert.equal(await reasonFor({obligationType: "CUSTOMER_REFUND", status: "COMPLETED"}), "");
});

test("R2: paid bookings in PAYMENT_EXPIRED / EXPIRED / DECLINED stop protecting once money is settled", () => {
  const now = new Date("2026-11-22T10:00:00.000Z");
  for (const state of ["PAYMENT_EXPIRED", "EXPIRED", "DECLINED"]) {
    const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
    booking.state = state;
    booking.stateQueryValue = state;
    booking.payment.razorpayPaymentId = "pay_late";
    for (const status of ["refunded", "paid", "cancelled"]) {
      booking.payment.status = status;
      assert.deepEqual(classifyRelationshipProtectionV1({booking, authoritativeNow: now}),
        {kind: "unprotected", reason: "NO_PROTECTED_OBLIGATION"}, `${state}/${status}`);
    }
    for (const status of ["refund_required", "refund_pending", "captured"]) {
      booking.payment.status = status;
      assert.deepEqual(classifyRelationshipProtectionV1({booking, authoritativeNow: now}),
        {kind: "protected", reason: "FINANCIAL_OBLIGATION_UNRESOLVED"}, `${state}/${status}`);
    }
  }
  // Other paid, non-terminal states still protect.
  const accepted = buildAcceptedAwaitingPaymentSlotBookingFixture();
  accepted.payment.razorpayPaymentId = "pay_x";
  accepted.payment.status = "refunded";
  assert.deepEqual(classifyRelationshipProtectionV1({booking: accepted, authoritativeNow: now}),
    {kind: "protected", reason: "PAID_STATE_ACCEPTED_AWAITING_PAYMENT"});
});
