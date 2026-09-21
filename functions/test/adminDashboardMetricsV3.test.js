const test = require("node:test");
const assert = require("node:assert/strict");

const {
  collectCanonicalDisputeMetricState,
  countCanonicalBookingMetrics,
  countCanonicalVisibleReviews,
  loadCanonicalBookingMetricCounts,
} = require("../lib/booking/adminDashboardMetricsV3.js");
const {
  buildAcceptedAwaitingPaymentSlotBookingFixture,
  buildCancelledBookingFixture,
  buildCompletedFinalBookingFixture,
  buildConfirmedRangeBookingFixture,
  buildConfirmedSlotBookingFixture,
  buildRequestedMultiSlotBookingFixture,
  buildRequestedSingleSlotBookingFixture,
} = require("../lib/booking/schema/bookingFixtures.js");

const BEFORE_SERVICE = new Date("2026-07-23T05:00:00.000Z");
const AFTER_SLOT_SERVICE = new Date("2026-07-23T12:00:00.000Z");
const AFTER_RANGE_SERVICE = new Date("2026-07-27T12:00:00.000Z");

function record(id, booking) {
  return {id, data: booking};
}

function withState(booking, state) {
  return {...booking, state, stateQueryValue: state};
}

function bookingCounts(records, now = BEFORE_SERVICE, disputes = new Map()) {
  return countCanonicalBookingMetrics({
    records,
    disputeStatusByBookingId: disputes,
    now,
  });
}

function pagedQuery(records, afterId = null, pageSize = records.length) {
  return {
    orderBy() {
      return pagedQuery(records, afterId, pageSize);
    },
    limit(limit) {
      return pagedQuery(records, afterId, limit);
    },
    startAfter(cursor) {
      return pagedQuery(records, cursor.id, pageSize);
    },
    async get() {
      const cursorIndex = afterId == null ? -1 : records.findIndex((item) => item.id === afterId);
      const start = cursorIndex + 1;
      return {
        docs: records.slice(start, start + pageSize).map((item) => ({
          id: item.id,
          data: () => item.data,
        })),
      };
    },
  };
}

test("active booking metrics count only effective CONFIRMED and IN_PROGRESS", () => {
  const confirmed = buildConfirmedSlotBookingFixture();
  const inProgress = withState(buildConfirmedSlotBookingFixture(), "IN_PROGRESS");
  inProgress.lifecycle.otpEnteredAt = new Date("2026-07-23T04:30:00.000Z");

  const excluded = [
    buildRequestedSingleSlotBookingFixture(),
    withState(buildRequestedSingleSlotBookingFixture(), "PENDING_PROVIDER"),
    buildAcceptedAwaitingPaymentSlotBookingFixture(),
    withState(buildCompletedFinalBookingFixture(), "COMPLETED_PENDING_REVIEW"),
    buildCompletedFinalBookingFixture(),
    withState(buildConfirmedSlotBookingFixture(), "NO_SHOW"),
    withState(buildCancelledBookingFixture(), "CANCELLED"),
    buildCancelledBookingFixture(),
    withState(buildAcceptedAwaitingPaymentSlotBookingFixture(), "PAYMENT_EXPIRED"),
  ];

  const records = [record("confirmed", confirmed), record("in-progress", inProgress)];
  excluded.forEach((booking, index) => records.push(record(`excluded-${index}`, booking)));

  assert.deepEqual(bookingCounts(records), {
    activeBookings: 2,
    completedBookings: 2,
  });
});

test("stale CONFIRMED derives NO_SHOW and is not active", () => {
  const counts = bookingCounts(
    [record("stale-confirmed", buildConfirmedSlotBookingFixture())],
    AFTER_SLOT_SERVICE,
  );
  assert.deepEqual(counts, {activeBookings: 0, completedBookings: 0});
});

test("stale IN_PROGRESS derives completed pending review", () => {
  const booking = withState(buildConfirmedRangeBookingFixture(), "IN_PROGRESS");
  booking.lifecycle.otpEnteredAt = new Date("2026-07-24T06:05:00.000Z");
  const counts = bookingCounts(
    [record("stale-in-progress", booking)],
    AFTER_RANGE_SERVICE,
  );
  assert.deepEqual(counts, {activeBookings: 0, completedBookings: 1});
});

test("completed metrics include review, dispute, resolved dispute, and final states", () => {
  const pendingReview = withState(
    buildCompletedFinalBookingFixture(),
    "COMPLETED_PENDING_REVIEW",
  );
  const underDispute = withState(
    buildCompletedFinalBookingFixture(),
    "COMPLETED_PENDING_REVIEW",
  );
  const disputeResolved = buildCompletedFinalBookingFixture();
  const finalBooking = buildCompletedFinalBookingFixture();
  const records = [
    record("pending-review", pendingReview),
    record("under-dispute", underDispute),
    record("dispute-resolved", disputeResolved),
    record("final", finalBooking),
    record("not-ended", withState(buildConfirmedRangeBookingFixture(), "IN_PROGRESS")),
    record("no-show", withState(buildConfirmedSlotBookingFixture(), "NO_SHOW")),
    record("cancelled", buildCancelledBookingFixture()),
  ];
  const disputes = new Map([
    ["under-dispute", "OPEN"],
    ["dispute-resolved", "RESOLVED"],
  ]);

  assert.deepEqual(bookingCounts(records, BEFORE_SERVICE, disputes), {
    activeBookings: 1,
    completedBookings: 4,
  });
});

test("multi-segment package counts once as one root booking", () => {
  const multi = buildRequestedMultiSlotBookingFixture();
  const confirmed = buildConfirmedSlotBookingFixture();
  multi.state = confirmed.state;
  multi.stateQueryValue = confirmed.stateQueryValue;
  multi.lifecycle = confirmed.lifecycle;
  multi.payment = confirmed.payment;
  multi.financials = confirmed.financials;
  multi.payout = confirmed.payout;
  multi.payDeadlineAt = confirmed.payDeadlineAt;
  assert.equal(multi.schedule.slots.length, 3);

  assert.deepEqual(bookingCounts([record("package-1", multi)]), {
    activeBookings: 1,
    completedBookings: 0,
  });
});

test("legacy, noncanonical, and partially migrated records do not abort counts", () => {
  const anomalies = [];
  const confirmed = buildConfirmedSlotBookingFixture();
  const counts = countCanonicalBookingMetrics({
    records: [
      record("valid", confirmed),
      {id: "legacy", data: {status: "confirmed"}},
      {id: "noncanonical", data: {documentFormat: "legacy", status: "completed"}},
      {
        id: "partial",
        data: {
          schemaVersion: 3,
          bookingModelVersion: "3.2",
          state: "CONFIRMED",
        },
      },
    ],
    disputeStatusByBookingId: new Map(),
    now: BEFORE_SERVICE,
    onAnomaly: (anomaly) => anomalies.push(anomaly),
  });

  assert.deepEqual(counts, {activeBookings: 1, completedBookings: 0});
  assert.equal(anomalies.length, 1);
  assert.equal(anomalies[0].bookingId, "partial");
  assert.equal(anomalies[0].failureStage, "eligibility");
});

test("malformed canonical booking is logged and valid records still count", () => {
  const malformed = buildCompletedFinalBookingFixture();
  malformed.lifecycle.completedAt = null;
  const anomalies = [];

  const counts = countCanonicalBookingMetrics({
    records: [
      record("malformed-completed", malformed),
      record("valid-active", buildConfirmedSlotBookingFixture()),
      record("valid-completed", buildCompletedFinalBookingFixture()),
    ],
    disputeStatusByBookingId: new Map(),
    now: BEFORE_SERVICE,
    onAnomaly: (anomaly) => anomalies.push(anomaly),
  });

  assert.deepEqual(counts, {activeBookings: 1, completedBookings: 1});
  assert.equal(anomalies.length, 1);
  assert.equal(anomalies[0].bookingId, "malformed-completed");
  assert.equal(anomalies[0].failureStage, "parse");
  assert.deepEqual(anomalies[0].issues, [
    {code: "QUERY_FIELD_MISMATCH", path: "completedAt"},
  ]);
});

test("missing optional timestamps remain parser-normalized", () => {
  const confirmed = buildConfirmedSlotBookingFixture();
  delete confirmed.lifecycle.otpGeneratedAt;
  delete confirmed.lifecycle.noShowAt;

  assert.deepEqual(bookingCounts([record("confirmed", confirmed)]), {
    activeBookings: 1,
    completedBookings: 0,
  });
});

test("missing dispute document is treated as no external dispute", () => {
  const pendingReview = withState(
    buildCompletedFinalBookingFixture(),
    "COMPLETED_PENDING_REVIEW",
  );

  assert.deepEqual(
    bookingCounts([record("pending-review", pendingReview)], BEFORE_SERVICE),
    {activeBookings: 0, completedBookings: 1},
  );
});

test("booking pagination counts every root document exactly once", async () => {
  const records = Array.from({length: 251}, (_, index) =>
    record(String(index).padStart(3, "0"), buildConfirmedSlotBookingFixture()));
  const firestore = {
    collection(name) {
      assert.equal(name, "bookings");
      return pagedQuery(records);
    },
  };

  const counts = await loadCanonicalBookingMetricCounts({
    firestore,
    disputeStatusByBookingId: new Map(),
    now: BEFORE_SERVICE,
  });

  assert.deepEqual(counts, {activeBookings: 251, completedBookings: 0});
});

test("open disputes count only well-formed canonical OPEN root documents", () => {
  const result = collectCanonicalDisputeMetricState([
    {id: "booking-1", data: {bookingId: "booking-1", source: "canonical_v3", status: "OPEN"}},
    {id: "booking-2", data: {bookingId: "booking-2", source: "canonical_v3", status: "OPEN"}},
    {id: "booking-3", data: {bookingId: "booking-3", source: "canonical_v3", status: "RESOLVED"}},
    {id: "legacy", data: {bookingId: "legacy", source: "legacy", status: "OPEN"}},
    {id: "malformed", data: {source: "canonical_v3", status: "OPEN"}},
    {id: "wrong-id", data: {bookingId: "another-id", source: "canonical_v3", status: "OPEN"}},
  ]);

  assert.equal(result.openDisputes, 2);
  assert.deepEqual([...result.statusByBookingId.entries()], [
    ["booking-1", "OPEN"],
    ["booking-2", "OPEN"],
    ["booking-3", "RESOLVED"],
  ]);
});

test("visible reviews count only approved canonical reviews", () => {
  const count = countCanonicalVisibleReviews([
    {id: "approved", data: {source: "canonical_v3", moderationStatus: "approved"}},
    {id: "hidden", data: {source: "canonical_v3", moderationStatus: "hidden"}},
    {id: "pending", data: {source: "canonical_v3", moderationStatus: "pending"}},
    {id: "blank", data: {source: "canonical_v3", moderationStatus: ""}},
    {id: "legacy", data: {source: "legacy", moderationStatus: "approved"}},
  ]);
  assert.equal(count, 1);
});
