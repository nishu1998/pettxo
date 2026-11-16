"use strict";
require("./helpers/firebaseTestSafety").assertUnitTestIsolation();

const test = require("node:test");
const assert = require("node:assert/strict");

const fixtures = require("../lib/booking/schema/bookingFixtures.js");
const {classifyRelationshipProtectionV1} = require("../lib/blocking/userBlocking.js");
const {canonicalUserPair} = require("../lib/blocking/relationshipGuard.js");
const {
  AUDIT_COLLECTIONS,
  auditPairKey,
  classifyRelationshipProtectionForAudit,
  evaluateRelationshipAudit,
} = require("../lib/audit/relationshipAuditEvaluation.js");
const {buildRelationshipAuditRehearsal, shiftDates} = require("./fixtures/relationshipAuditRehearsal.js");

const DAY = 24 * 60 * 60 * 1000;

function variants() {
  const bases = [
    fixtures.buildRequestedSingleSlotBookingFixture(),
    fixtures.buildRequestedMultiSlotBookingFixture(),
    fixtures.buildAcceptedAwaitingPaymentSlotBookingFixture(),
    fixtures.buildConfirmedSlotBookingFixture(),
    fixtures.buildRequestedRangeBookingFixture(),
    fixtures.buildConfirmedRangeBookingFixture(),
    fixtures.buildCancelledBookingFixture(),
    fixtures.buildCompletedFinalBookingFixture(),
  ];
  const states = [
    "REQUESTED", "PENDING_PROVIDER", "ACCEPTED_AWAITING_PAYMENT", "CONFIRMED", "IN_PROGRESS",
    "COMPLETED_PENDING_REVIEW", "COMPLETED_FINAL", "DECLINED", "EXPIRED", "PAYMENT_EXPIRED",
    "CANCELLED_BY_PARENT", "CANCELLED", "DISPUTED", "SERVICE_NOT_STARTED", "NO_SHOW",
  ];
  const out = [];
  for (const base of bases) {
    for (const state of states) {
      for (const paymentStatus of ["", "paid", "refunded", "refund_pending", "created"]) {
        for (const disputeStatus of ["none", "open", "resolved"]) {
          for (const payoutStatus of ["not_eligible", "held", "released"]) {
            for (const deadlineOffset of [null, -DAY, DAY]) {
              const booking = structuredClone(base);
              booking.state = state;
              booking.payment.status = paymentStatus;
              booking.dispute.status = disputeStatus;
              booking.payout.status = payoutStatus;
              booking.lifecycle.disputeDeadlineAt = deadlineOffset == null ? null : new Date(Date.UTC(2026, 6, 25) + deadlineOffset);
              out.push(booking);
            }
          }
        }
      }
    }
  }
  return out;
}

test("audit classifier is output-identical to the runtime classifyRelationshipProtectionV1", () => {
  const now = new Date(Date.UTC(2026, 6, 25));
  let compared = 0;
  for (const booking of variants()) {
    assert.deepEqual(
      classifyRelationshipProtectionForAudit({booking, authoritativeNow: now}),
      classifyRelationshipProtectionV1({booking, authoritativeNow: now}),
    );
    compared += 1;
  }
  assert.ok(compared >= 8 * 15 * 5 * 3 * 3 * 3);
});

test("audit pair key derivation is identical to canonicalUserPair", () => {
  for (const [a, b] of [["uA", "uB"], ["zz", "aa"], ["user_1", "user_10"], ["Ä", "a"]]) {
    assert.deepEqual(auditPairKey(a, b), canonicalUserPair(a, b));
  }
  assert.equal(auditPairKey("x", "x"), null);
  assert.equal(auditPairKey("a/b", "c"), null);
});

function sourceFromDocuments(documents) {
  const source = {};
  for (const key of Object.keys(AUDIT_COLLECTIONS)) source[key] = [];
  const users = new Set();
  for (const {path, data} of documents) {
    const segments = path.split("/");
    const id = segments.at(-1);
    if (segments[0] === "users") {
      users.add(id);
      continue;
    }
    const key = segments.length === 4 ? "paymentAttempts" :
      Object.keys(AUDIT_COLLECTIONS).find((name) => AUDIT_COLLECTIONS[name].collection === segments[0]);
    source[key].push({id, path, data: structuredClone(data)});
  }
  const uids = new Set();
  for (const block of source.userBlocks) {
    for (const field of ["ownerUserId", "blockerUid", "blockedUserId"]) if (block.data[field]) uids.add(block.data[field]);
  }
  source.checkedUserIds = uids;
  source.existingUserIds = new Set([...uids].filter((uid) => users.has(uid)));
  return source;
}

function recordsByCategory(records) {
  const grouped = {};
  for (const record of records) (grouped[record.category] ??= []).push(`${record.collection}/${record.documentId}`);
  for (const list of Object.values(grouped)) list.sort();
  return grouped;
}

test("every rehearsal category is detected in memory with the exact record IDs", () => {
  const now = new Date();
  const {documents, expected, pairs} = buildRelationshipAuditRehearsal(now);
  const {findings, reviewRecords, informationalRecords} = evaluateRelationshipAudit(sourceFromDocuments(documents), now);
  const sortedExpected = Object.fromEntries(Object.entries(expected.review).map(([key, list]) => [key, [...list].sort()]));
  assert.deepEqual(recordsByCategory(reviewRecords), sortedExpected);
  assert.deepEqual(findings.sourceCounts, expected.sourceCounts);
  assert.deepEqual(findings.payments.strandedMoney.byReason, expected.strandedReasons);
  assert.equal(reviewRecords.find((record) => record.reasonCode === "BLOCK_WITH_OPEN_PAYMENT_ORDER")?.documentId, "uC_uD");
  assert.equal(findings.userBlocks.reciprocalPairs, expected.reciprocalPairs);
  assert.deepEqual(findings.userBlocks.schemaVariants, expected.schemaVariants);
  assert.equal(findings.userBlocks.blockConflictsWithSettlementOnly, 1);
  assert.ok(informationalRecords.some((record) =>
    record.category === "BLOCK_WITH_PETTXO_PROVIDER_SETTLEMENT_ONLY" && record.pairKey === pairs.pairMN));
  assert.equal(findings.multiDayPackages.total, expected.multiDay.total);
  assert.equal(findings.multiDayPackages.partiallyElapsed, expected.multiDay.partiallyElapsed);
  assert.ok(informationalRecords.some((record) => record.category === "MULTI_DAY_PACKAGE" &&
    record.documentId === expected.multiDay.partiallyElapsedId && record.detail.partiallyElapsed === true &&
    record.detail.packageProtected === true));
  assert.equal(findings.bookings.completedInDisputeWindow, expected.completedInDisputeWindow);
  assert.equal(findings.bookings.completedPastDisputeWindow, expected.completedPastDisputeWindow);
  const protections = findings.customerProviderProtections;
  assert.equal(protections.openDisputes, expected.openDisputes);
  assert.equal(protections.openRefunds, expected.openRefunds);
  assert.equal(protections.openPaymentRefundEvents, expected.openPaymentRefundEvents);
  assert.equal(protections.unresolvedReconciliations, expected.unresolvedReconciliations);
  assert.equal(protections.openCustomerRefundObligations, expected.openCustomerRefundObligations);
  const settlement = findings.pettxoProviderSettlement;
  assert.equal(settlement.heldPayouts, expected.heldPayouts);
  assert.equal(settlement.payoutReadinessHolds, expected.payoutReadinessHolds);
  assert.equal(settlement.openProviderEarnings, expected.openProviderEarnings);
  assert.equal(findings.relationshipGuards.historicalProtectionBlockedTrue, expected.guardHistoricalProtection);
  assert.equal(findings.reviewRecordCount, reviewRecords.length);
});

test("a clean database produces no review records", () => {
  const now = new Date();
  const documents = [
    {path: "bookings/clean_1", data: fixtures.buildRequestedSingleSlotBookingFixture()},
    {path: "bookings/clean_2", data: fixtures.buildCompletedFinalBookingFixture()},
    {path: "users/u1", data: {uid: "u1"}},
    {path: "users/u2", data: {uid: "u2"}},
    {path: "userBlocks/u1_u2", data: {ownerUserId: "u1", blockedUserId: "u2"}},
  ];
  const {reviewRecords, findings} = evaluateRelationshipAudit(sourceFromDocuments(documents), now);
  assert.deepEqual(reviewRecords, []);
  assert.equal(findings.userBlocks.total, 1);
});

test("multi-day packages are evaluated at package level and early completion is flagged", () => {
  const now = new Date();
  const range = fixtures.buildCompletedFinalBookingFixture();
  const shifted = shiftDates(range, now.getTime() - range.schedule.checkInDateTime.getTime() - DAY);
  const {findings, reviewRecords} = evaluateRelationshipAudit(
    sourceFromDocuments([{path: "bookings/early", data: shifted}]), now);
  assert.equal(findings.multiDayPackages.terminalBeforePackageEnd, 1);
  assert.deepEqual(reviewRecords.map((record) => record.category), ["MULTI_DAY_PACKAGE_INCONSISTENT"]);
});

const ALLOWED_RECORD_KEYS = new Set(["category", "reasonCode", "collection", "documentId", "bookingId", "pairKey", "uids", "detail"]);
const FORBIDDEN_TEXT = /@|\+91|displayName|fullName|phone|email|address|latitude|longitude|ifsc|account|bank|upi/i;

test("records carry IDs and codes only, never personal or bank data", () => {
  const now = new Date();
  const {documents} = buildRelationshipAuditRehearsal(now);
  const booking = documents.find((doc) => doc.path === "bookings/rh_b01_confirmed_blocked").data;
  booking.participants.parent.displayName = "Private Person";
  booking.participants.parent.email = "private@example.com";
  const {reviewRecords, informationalRecords, findings} = evaluateRelationshipAudit(sourceFromDocuments(documents), now);
  for (const record of [...reviewRecords, ...informationalRecords]) {
    for (const key of Object.keys(record)) assert.ok(ALLOWED_RECORD_KEYS.has(key), key);
    for (const value of Object.values(record.detail ?? {})) {
      assert.ok(value === null || ["string", "number", "boolean"].includes(typeof value));
    }
  }
  const serialized = JSON.stringify({reviewRecords, informationalRecords, findings});
  assert.doesNotMatch(serialized, FORBIDDEN_TEXT);
});
