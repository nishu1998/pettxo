const test = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");

const schema = require("../lib/booking/schema/bookingDocumentV3.js");
const readModel = require("../lib/booking/schema/bookingReadModel.js");
const fixtures = require("../lib/booking/schema/bookingFixtures.js");

test("parses valid canonical SLOT booking", () => {
  const booking = fixtures.buildRequestedSingleSlotBookingFixture();
  const parsed = schema.parseCanonicalBookingDocumentV3(booking);
  assert.equal(parsed.ok, true);
  assert.equal(parsed.booking.bookingType, "SLOT");
});

test("parses valid canonical multi-slot booking", () => {
  const booking = fixtures.buildRequestedMultiSlotBookingFixture();
  const parsed = schema.parseCanonicalBookingDocumentV3(booking);
  assert.equal(parsed.ok, true);
  assert.equal(parsed.booking.schedule.slotCount, 3);
});

test("parses valid canonical RANGE booking", () => {
  const booking = fixtures.buildRequestedRangeBookingFixture();
  const parsed = schema.parseCanonicalBookingDocumentV3(booking);
  assert.equal(parsed.ok, true);
  assert.equal(parsed.booking.bookingType, "RANGE");
  assert.equal(parsed.booking.schedule.nights, 2);
});

test("rejects invalid schema version", () => {
  const booking = {
    ...fixtures.buildRequestedSingleSlotBookingFixture(),
    schemaVersion: 2,
  };
  const parsed = schema.parseCanonicalBookingDocumentV3(booking);
  assert.equal(parsed.ok, false);
  assert.ok(parsed.issues.some((entry) => entry.code === "INVALID_SCHEMA_VERSION"));
});

test("classifies non-canonical booking documents as invalid", () => {
  const read = readModel.parseBookingReadModel({
    customerId: "parent-1",
    serviceOwnerId: "provider-1",
    serviceId: "service-1",
    status: "paymentPending",
  }, "historic-booking-1");
  assert.equal(read.source, "invalid");
  assert.ok(
    read.errors.some((entry) => entry.code === "NON_CANONICAL_BOOKING_DOCUMENT"),
  );
});

test("returns invalid for malformed canonical documents", () => {
  const malformed = {
    ...fixtures.buildRequestedSingleSlotBookingFixture(),
    bookingType: "SLOT",
    schedule: {
      ...fixtures.buildRequestedSingleSlotBookingFixture().schedule,
      slotCount: 2,
    },
  };
  const parsed = readModel.parseBookingReadModel(malformed, "booking-1");
  assert.equal(parsed.source, "invalid");
  assert.ok(parsed.errors.some((entry) => entry.code === "INVALID_SLOT_COUNT"));
});

test("rejects serviceAnchorAt mismatch", () => {
  const booking = {
    ...fixtures.buildRequestedSingleSlotBookingFixture(),
    serviceAnchorAt: new Date("2026-07-23T07:00:00.000Z"),
  };
  const parsed = schema.parseCanonicalBookingDocumentV3(booking);
  assert.equal(parsed.ok, false);
  assert.ok(parsed.issues.some((entry) => entry.code === "QUERY_FIELD_MISMATCH"));
});

test("rejects scheduledStartAt mismatch", () => {
  const booking = {
    ...fixtures.buildRequestedSingleSlotBookingFixture(),
    scheduledStartAt: new Date("2026-07-23T08:00:00.000Z"),
  };
  const parsed = schema.parseCanonicalBookingDocumentV3(booking);
  assert.equal(parsed.ok, false);
  assert.ok(parsed.issues.some((entry) => entry.path === "scheduledStartAt"));
});

test("rejects checkInDateTime mismatch", () => {
  const booking = {
    ...fixtures.buildRequestedRangeBookingFixture(),
    checkInDateTime: new Date("2026-07-25T06:00:00.000Z"),
  };
  const parsed = schema.parseCanonicalBookingDocumentV3(booking);
  assert.equal(parsed.ok, false);
  assert.ok(parsed.issues.some((entry) => entry.path === "checkInDateTime"));
});

test("rejects paid state without immutable financial snapshot", () => {
  const booking = fixtures.buildConfirmedSlotBookingFixture();
  booking.financials = null;
  const parsed = schema.parseCanonicalBookingDocumentV3(booking);
  assert.equal(parsed.ok, false);
  assert.ok(parsed.issues.some((entry) => entry.code === "PAID_WITHOUT_FINANCIAL_SNAPSHOT"));
});

test("rejects OTP timestamps before payment", () => {
  const booking = fixtures.buildRequestedSingleSlotBookingFixture();
  booking.lifecycle.otpGeneratedAt = new Date("2026-07-22T10:10:00.000Z");
  const parsed = schema.parseCanonicalBookingDocumentV3(booking);
  assert.equal(parsed.ok, false);
  assert.ok(parsed.issues.some((entry) => entry.code === "OTP_BEFORE_PAYMENT"));
});

test("rejects pay deadline without provider response", () => {
  const booking = fixtures.buildRequestedSingleSlotBookingFixture();
  booking.lifecycle.payDeadlineAt = new Date("2026-07-22T11:00:00.000Z");
  booking.payDeadlineAt = booking.lifecycle.payDeadlineAt;
  const parsed = schema.parseCanonicalBookingDocumentV3(booking);
  assert.equal(parsed.ok, false);
  assert.ok(parsed.issues.some((entry) => entry.code === "PAY_DEADLINE_WITHOUT_RESPONSE"));
});

test("rejects completedAt without serviceEndedAt", () => {
  const booking = fixtures.buildConfirmedRangeBookingFixture();
  booking.lifecycle.completedAt = new Date("2026-07-26T06:30:00.000Z");
  booking.completedAt = booking.lifecycle.completedAt;
  const parsed = schema.parseCanonicalBookingDocumentV3(booking);
  assert.equal(parsed.ok, false);
  assert.ok(parsed.issues.some((entry) => entry.code === "COMPLETED_WITHOUT_SERVICE_END"));
});

test("rejects pre-payment private fields in the public parent snapshot", () => {
  const booking = fixtures.buildRequestedSingleSlotBookingFixture();
  booking.participants.parent.fullName = "Nisha Gautam";
  const parsed = schema.parseCanonicalBookingDocumentV3(booking);
  assert.equal(parsed.ok, false);
  assert.ok(parsed.issues.some((entry) => entry.code === "PREPAYMENT_PRIVATE_FIELD"));
});

test("validates canonical query field consistency", () => {
  const booking = fixtures.buildRequestedSingleSlotBookingFixture();
  booking.parentId = "parent-2";
  const parsed = schema.parseCanonicalBookingDocumentV3(booking);
  assert.equal(parsed.ok, false);
  assert.ok(parsed.issues.some((entry) => entry.code === "QUERY_FIELD_MISMATCH"));
});

test("accepts cancellation, dispute, and payout structures in canonical documents", () => {
  const cancelled = schema.parseCanonicalBookingDocumentV3(
    fixtures.buildCancelledBookingFixture(),
  );
  assert.equal(cancelled.ok, true);

  const completed = schema.parseCanonicalBookingDocumentV3(
    fixtures.buildCompletedFinalBookingFixture(),
  );
  assert.equal(completed.ok, true);
});

test("parses Firestore Timestamp values in canonical date fields", () => {
  const booking = fixtures.buildRequestedSingleSlotBookingFixture();
  booking.createdAt = Timestamp.fromDate(booking.createdAt);
  booking.updatedAt = Timestamp.fromDate(booking.updatedAt);
  booking.serviceAnchorAt = Timestamp.fromDate(booking.serviceAnchorAt);
  booking.scheduledStartAt = Timestamp.fromDate(booking.scheduledStartAt);
  booking.schedule.serviceAnchorAt = Timestamp.fromDate(
    booking.schedule.serviceAnchorAt,
  );
  booking.schedule.scheduledStartAt = Timestamp.fromDate(
    booking.schedule.scheduledStartAt,
  );
  booking.schedule.scheduledEndAt = Timestamp.fromDate(
    booking.schedule.scheduledEndAt,
  );
  booking.schedule.slots = booking.schedule.slots.map((slot) => ({
    ...slot,
    startAt: Timestamp.fromDate(slot.startAt),
    endAt: Timestamp.fromDate(slot.endAt),
  }));

  const parsed = schema.parseCanonicalBookingDocumentV3(booking);
  assert.equal(parsed.ok, true);
  assert.ok(parsed.booking.createdAt instanceof Date);
  assert.ok(parsed.booking.schedule.scheduledStartAt instanceof Date);
});

test("parses serialized Firestore timestamp shapes in canonical payout dates", () => {
  const booking = fixtures.buildCompletedFinalBookingFixture();
  booking.createdAt = {
    seconds: Math.floor(booking.createdAt.getTime() / 1000),
    nanoseconds: 0,
  };
  booking.updatedAt = {
    seconds: Math.floor(booking.updatedAt.getTime() / 1000),
    nanoseconds: 0,
  };
  booking.completedAt = {
    seconds: Math.floor(booking.completedAt.getTime() / 1000),
    nanoseconds: 0,
  };
  booking.lifecycle.completedAt = {
    seconds: Math.floor(booking.lifecycle.completedAt.getTime() / 1000),
    nanoseconds: 0,
  };
  booking.lifecycle.serviceEndedAt = {
    seconds: Math.floor(booking.lifecycle.serviceEndedAt.getTime() / 1000),
    nanoseconds: 0,
  };
  booking.payout.eligibleAt = {
    seconds: Math.floor(booking.payout.eligibleAt.getTime() / 1000),
    nanoseconds: 0,
  };

  const parsed = schema.parseCanonicalBookingDocumentV3(booking);
  assert.equal(parsed.ok, true);
  assert.ok(parsed.booking.payout.eligibleAt instanceof Date);
});

test("event immutability contract remains append-only by shape", () => {
  const eventRecord = {
    bookingId: "booking-1",
    event: "requested",
    actor: "system",
    at: new Date("2026-07-22T10:00:00.000Z"),
    meta: {schema: "3.2"},
    schemaVersion: 1,
  };
  const bookingEvents = require("../lib/booking/domain/bookingEvents.js");
  assert.equal(bookingEvents.isBookingEventRecord(eventRecord), true);
});

test("safe unknown historic status stays invalid and does not crash parsing", () => {
  const read = readModel.parseBookingReadModel({
    customerId: "parent-1",
    serviceOwnerId: "provider-1",
    serviceId: "service-1",
    status: "mystery_status",
  }, "historic-booking-2");
  assert.equal(read.source, "invalid");
  assert.ok(
    read.errors.some((entry) => entry.code === "NON_CANONICAL_BOOKING_DOCUMENT"),
  );
});
