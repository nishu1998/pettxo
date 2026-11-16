"use strict";

/**
 * Synthetic emulator fixtures for the Phase 3B-3b relationship audit rehearsal.
 * All IDs are synthetic (prefix rh_ / u*). No personal data.
 *
 * buildRelationshipAuditRehearsal(now) returns {documents, expected}. `expected`
 * lists, per audit category, the exact record IDs the audit must report.
 */

const fixtures = require("../../lib/booking/schema/bookingFixtures.js");
const {auditPairKey} = require("../../lib/audit/relationshipAuditEvaluation.js");

const DAY = 24 * 60 * 60 * 1000;

function shiftDates(value, deltaMs) {
  if (value instanceof Date) return new Date(value.getTime() + deltaMs);
  if (Array.isArray(value)) return value.map((item) => shiftDates(item, deltaMs));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, shiftDates(item, deltaMs)]));
  }
  return value;
}

function forPair(booking, parentId, providerId) {
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

function attempt(bookingId, attemptId, state, extra = {}) {
  return {
    path: `bookings/${bookingId}/paymentAttempts/${attemptId}`,
    data: {schemaVersion: 1, paymentAttemptId: attemptId, bookingId, state, amountPaise: 25000, ...extra},
  };
}

function buildRelationshipAuditRehearsal(now) {
  const documents = [];
  const add = (path, data) => documents.push({path, data});
  const booking = (id, data) => add(`bookings/${id}`, data);

  // B1 confirmed booking on a pair that is blocked in BOTH directions (reciprocal).
  booking("rh_b01_confirmed_blocked", forPair(fixtures.buildConfirmedSlotBookingFixture(), "uA", "uB"));
  // B2 accepted-unpaid booking with an open Razorpay order on a blocked pair.
  booking("rh_b02_accepted_open_order", forPair(fixtures.buildAcceptedAwaitingPaymentSlotBookingFixture(), "uC", "uD"));
  documents.push(attempt("rh_b02_accepted_open_order", "rh_att_b02", "ORDER_CREATED", {razorpayOrderId: "order_rh_b02"}));
  add("canonicalPaymentOrderMappings/order_rh_b02",
    {bookingId: "rh_b02_accepted_open_order", paymentAttemptId: "rh_att_b02", status: "active"});
  // B3 cancelled booking with captured money and NO refund record (stranded).
  booking("rh_b03_cancelled_captured_no_refund", forPair(fixtures.buildCancelledBookingFixture(), "uE", "uF"));
  add("manualSettlementObligations/rh_obl_b03",
    {bookingId: "rh_b03_cancelled_captured_no_refund", obligationType: "CUSTOMER_REFUND", status: "READY"});
  add("bookingFinancialReconciliation/rh_b03_cancelled_captured_no_refund",
    {bookingId: "rh_b03_cancelled_captured_no_refund", status: "AMOUNT_MISMATCH"});
  // B4 cancelled booking with captured money and an OPEN refund (stranded).
  booking("rh_b04_cancelled_refund_open", forPair(fixtures.buildCancelledBookingFixture(), "uG", "uH"));
  documents.push(attempt("rh_b04_cancelled_refund_open", "rh_att_b04", "REFUND_PENDING",
    {razorpayPaymentId: "pay_rh_b04", capturedAmountPaise: 25000, refundedAmountPaise: 0}));
  add("refunds/rh_b04_cancelled_refund_open", {bookingId: "rh_b04_cancelled_refund_open", state: "pending"});
  add("paymentRefunds/rh_evt_b04", {bookingId: "rh_b04_cancelled_refund_open", state: "submitted", amountPaise: 18750});
  // B5 cancelled booking fully refunded (NOT stranded) whose refund record has an unknown status.
  booking("rh_b05_cancelled_refunded", forPair(fixtures.buildCancelledBookingFixture(), "uI", "uJ"));
  documents.push(attempt("rh_b05_cancelled_refunded", "rh_att_b05", "REFUNDED",
    {razorpayPaymentId: "pay_rh_b05", capturedAmountPaise: 25000, refundedAmountPaise: 25000}));
  add("refunds/rh_b05_cancelled_refunded", {bookingId: "rh_b05_cancelled_refunded", state: "weird_new_state"});
  // B6 completed, still INSIDE the dispute window (shifted so the deadline is tomorrow).
  const completed = fixtures.buildCompletedFinalBookingFixture();
  const inWindowDelta = now.getTime() + DAY - completed.lifecycle.disputeDeadlineAt.getTime();
  booking("rh_b06_completed_in_window", forPair(shiftDates(completed, inWindowDelta), "uK", "uL"));
  add("disputes/rh_dispute_b06", {bookingId: "rh_b06_completed_in_window", status: "OPEN"});
  add("providerEarnings/rh_b06_completed_in_window",
    {bookingId: "rh_b06_completed_in_window", earningsStatus: "PROVISIONAL"});
  // B7 completed, PAST the dispute window; Pettxo still holds the provider payout; pair blocked.
  booking("rh_b07_completed_past_window", forPair(fixtures.buildCompletedFinalBookingFixture(), "uM", "uN"));
  add("providerPayouts/rh_b07_completed_past_window", {bookingId: "rh_b07_completed_past_window", status: "HELD"});
  add("payoutReadiness/rh_b07_completed_past_window",
    {bookingId: "rh_b07_completed_past_window", status: "held", payoutHoldReason: "MANUAL_REVIEW"});
  // B8 legacy/old-schema booking with a non-canonical status.
  booking("rh_b08_legacy_schema", {customerId: "uO", serviceOwnerId: "uS", status: "confirmed"});
  // B9 canonical-shaped booking whose participants are the same user.
  booking("rh_b09_invalid_participants", forPair(fixtures.buildRequestedSingleSlotBookingFixture(), "uT", "uT"));
  // B10 multi-day package in progress (checked in yesterday, checks out tomorrow).
  const range = fixtures.buildConfirmedRangeBookingFixture();
  const rangeDelta = now.getTime() - DAY - range.schedule.checkInDateTime.getTime();
  booking("rh_b10_multiday_in_progress", forPair(shiftDates(range, rangeDelta), "uU", "uV"));
  // B11 plain requested booking, no payment evidence (baseline).
  booking("rh_b11_requested_plain", forPair(fixtures.buildRequestedSingleSlotBookingFixture(), "uW", "uY"));

  // Orphan QR mapping pointing to a booking that does not exist.
  add("canonicalQrPaymentMappings/qr_rh_orphan",
    {bookingId: "rh_missing_booking", paymentAttemptId: "rh_att_missing", status: "active"});

  // Users (only existence matters). uGhost intentionally missing.
  for (const uid of ["uA", "uB", "uC", "uD", "uM", "uN", "uX", "uP", "uQ", "uR"]) add(`users/${uid}`, {uid});

  const pairAB = auditPairKey("uA", "uB").pairKey;
  const pairCD = auditPairKey("uC", "uD").pairKey;
  const pairEF = auditPairKey("uE", "uF").pairKey;
  const pairMN = auditPairKey("uM", "uN").pairKey;
  // Directed blocks: every schema/source variant.
  add("userBlocks/uB_uA", {ownerUserId: "uB", blockedUserId: "uA", createdAt: new Date(now.getTime() - DAY)});
  add("userBlocks/uA_uB", {schemaVersion: 1, ownerUserId: "uA", blockerUid: "uA", blockedUserId: "uB",
    pairKey: pairAB, status: "active", source: "server_block_user_v1"});
  add("userBlocks/uC_uD", {schemaVersion: 1, ownerUserId: "uC", blockerUid: "uC", blockedUserId: "uD",
    pairKey: pairCD, status: "active", source: "server_block_user_v1"});
  add("userBlocks/uM_uN", {ownerUserId: "uM", blockedUserId: "uN"});
  add("userBlocks/uX_uGhost", {ownerUserId: "uX", blockedUserId: "uGhost"});
  add("userBlocks/uQ_uR", {blockerUid: "uQ", blockedUserId: "uR"});
  add("userBlocks/rh_bad_self_block", {ownerUserId: "uP", blockedUserId: "uP"});

  // Relationship guards: one consistent, two inconsistent.
  add(`userRelationshipGuards/${pairAB}`, {schemaVersion: 1, pairKey: pairAB, uidA: "uA", uidB: "uB",
    blocked: true, status: "blocked", activeDirectedBlockIds: ["uA_uB", "uB_uA"]});
  add(`userRelationshipGuards/${pairCD}`, {schemaVersion: 1, pairKey: pairCD, uidA: "uC", uidB: "uD",
    blocked: false, status: "open", activeDirectedBlockIds: []});
  add(`userRelationshipGuards/${pairEF}`, {schemaVersion: 1, pairKey: pairEF, uidA: "uE", uidB: "uF",
    blocked: false, status: "open", activeDirectedBlockIds: [], historicalProtectionBlocked: true});

  const expected = {
    sourceCounts: {
      userBlocks: 7, userRelationshipGuards: 3, bookings: 11, paymentAttempts: 3, paymentOrderMappings: 1,
      qrPaymentMappings: 1, refunds: 2, paymentRefunds: 1, disputes: 1, bookingFinancialReconciliation: 1,
      manualSettlementObligations: 1, providerPayouts: 1, providerEarnings: 1, payoutReadiness: 1,
    },
    review: {
      MALFORMED_BOOKING: ["bookings/rh_b08_legacy_schema", "bookings/rh_b09_invalid_participants"],
      STRANDED_MONEY: [
        "bookings/rh_b02_accepted_open_order",
        "bookings/rh_b03_cancelled_captured_no_refund",
        "bookings/rh_b04_cancelled_refund_open",
      ],
      BLOCK_BOOKING_CONFLICT: ["userBlocks/uA_uB,uB_uA", "userBlocks/uC_uD"],
      USER_BLOCK_MISSING_USER: ["userBlocks/uX_uGhost"],
      INVALID_USER_BLOCK: ["userBlocks/rh_bad_self_block"],
      RELATIONSHIP_GUARD_INCONSISTENT: [`userRelationshipGuards/${pairCD}`, `userRelationshipGuards/${pairEF}`],
      UNKNOWN_FINANCIAL_STATUS: ["refunds/rh_b05_cancelled_refunded"],
      PAYMENT_EVIDENCE_INCONSISTENT: ["canonicalQrPaymentMappings/qr_rh_orphan"],
    },
    strandedReasons: {
      PENDING_PAYMENT_ON_UNCONFIRMED_BOOKING: 1,
      CAPTURED_NO_REFUND_RECORD: 1,
      CAPTURED_REFUND_OPEN: 1,
    },
    blockConflictWithOpenOrder: "userBlocks/uC_uD",
    settlementOnlyPair: pairMN,
    reciprocalPairs: 1,
    schemaVariants: {owner_field: 4, server_v1: 2, legacy_blocker_field: 1},
    multiDay: {total: 3, partiallyElapsed: 1, partiallyElapsedId: "rh_b10_multiday_in_progress"},
    completedInDisputeWindow: 1,
    completedPastDisputeWindow: 1,
    openDisputes: 1,
    openRefunds: 2, // the unknown-status refund on B5 is counted open (fail-closed)
    openPaymentRefundEvents: 1,
    unresolvedReconciliations: 1,
    openCustomerRefundObligations: 1,
    heldPayouts: 1,
    payoutReadinessHolds: 1,
    openProviderEarnings: 1,
    guardHistoricalProtection: 1,
  };
  return {documents, expected, pairs: {pairAB, pairCD, pairEF, pairMN}};
}

module.exports = {buildRelationshipAuditRehearsal, shiftDates};
