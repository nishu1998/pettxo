const test = require("node:test");
const assert = require("node:assert/strict");

const constants = require("../lib/booking/domain/bookingConstants.js");
const contracts = require("../lib/booking/domain/bookingContracts.js");
const slotBooking = require("../lib/booking/domain/slotBooking.js");
const rangeBooking = require("../lib/booking/domain/rangeBooking.js");
const deadlines = require("../lib/booking/domain/bookingDeadlines.js");
const pricing = require("../lib/booking/domain/bookingPricing.js");
const snapshots = require("../lib/booking/domain/bookingSnapshots.js");
const events = require("../lib/booking/domain/bookingEvents.js");

function slot({
  slotId,
  startHour,
  endHour,
  serviceId = "service-1",
  providerId = "provider-1",
  timezone = "Asia/Kolkata",
  dateKey = "2026-07-22",
  unitPricePaise = 10000,
}) {
  const startAt = new Date(Date.UTC(2026, 6, 22, startHour));
  const endAt = new Date(Date.UTC(2026, 6, 22, endHour));
  return {
    slotId,
    serviceId,
    providerId,
    timezone,
    dateKey,
    startAt,
    endAt,
    durationMinutes: (endAt.getTime() - startAt.getTime()) / 60000,
    unitPricePaise,
  };
}

test("canonical constants expose the approved v3.2 defaults", () => {
  assert.equal(constants.ACCEPT_WINDOW_MINUTES, 60);
  assert.equal(constants.PAY_WINDOW_MINUTES, 60);
  assert.equal(constants.BUFFER_MINUTES, 30);
  assert.equal(constants.RUNWAY_MINUTES, 150);
  assert.equal(constants.DEFAULT_PROVIDER_TIMEZONE, "Asia/Kolkata");
  assert.equal(constants.PLATFORM_COMMISSION_BASIS_POINTS, 1500);
});

test("runway equals accept plus pay plus buffer", () => {
  assert.equal(
    constants.RUNWAY_MINUTES,
    constants.ACCEPT_WINDOW_MINUTES +
      constants.PAY_WINDOW_MINUTES +
      constants.BUFFER_MINUTES,
  );
});

test("deadline utilities are deterministic and inclusive on the boundary", () => {
  const timerStartsAt = new Date("2026-07-22T10:00:00.000Z");
  const respondedAt = new Date("2026-07-22T11:15:00.000Z");
  const anchorAt = new Date("2026-07-22T12:30:00.000Z");

  assert.equal(
    deadlines.computeAcceptDeadlineAt(timerStartsAt).toISOString(),
    "2026-07-22T11:00:00.000Z",
  );
  assert.equal(
    deadlines.computePayDeadlineAt(respondedAt).toISOString(),
    "2026-07-22T12:15:00.000Z",
  );
  assert.equal(
    deadlines.computeRunwayEndsAt(timerStartsAt).toISOString(),
    "2026-07-22T12:30:00.000Z",
  );
  assert.equal(deadlines.isAnchorBookable(anchorAt, timerStartsAt), true);
});

test("slot validator accepts one slot and multiple continuous slots", () => {
  const first = slot({slotId: "slot-1", startHour: 10, endHour: 11});
  const second = slot({slotId: "slot-2", startHour: 11, endHour: 12});

  const single = slotBooking.validateSlotBookingSelection({
    bookingType: "SLOT",
    slots: [first],
    slotCount: 1,
    scheduledStartAt: first.startAt,
    scheduledEndAt: first.endAt,
    totalDurationMinutes: 60,
  });
  assert.equal(single.ok, true);

  const multi = slotBooking.validateSlotBookingSelection({
    bookingType: "SLOT",
    slots: [second, first],
    slotCount: 2,
    scheduledStartAt: first.startAt,
    scheduledEndAt: second.endAt,
    totalDurationMinutes: 120,
  });
  assert.equal(multi.ok, true);
  assert.equal(multi.normalizedSelection.slots[0].slotId, "slot-1");
});

test("slot validator rejects gap, overlap, duplicate slot, mixed provider, mixed service, and mixed timezone", () => {
  const first = slot({slotId: "slot-1", startHour: 10, endHour: 11});
  const gap = slot({slotId: "slot-2", startHour: 12, endHour: 13});
  const overlap = slot({slotId: "slot-1", startHour: 10, endHour: 12, serviceId: "service-2", providerId: "provider-2", timezone: "UTC"});

  const gapResult = slotBooking.validateSlotBookingSelection({
    bookingType: "SLOT",
    slots: [first, gap],
    slotCount: 2,
    scheduledStartAt: first.startAt,
    scheduledEndAt: gap.endAt,
    totalDurationMinutes: 120,
  });
  assert.equal(gapResult.ok, false);
  assert.ok(gapResult.issues.some((issue) => issue.code === "NON_CONTIGUOUS"));

  const overlapResult = slotBooking.validateSlotBookingSelection({
    bookingType: "SLOT",
    slots: [first, overlap],
    slotCount: 2,
    scheduledStartAt: first.startAt,
    scheduledEndAt: overlap.endAt,
    totalDurationMinutes: 180,
  });
  assert.equal(overlapResult.ok, false);
  assert.ok(overlapResult.issues.some((issue) => issue.code === "DUPLICATE_SLOT"));
  assert.ok(overlapResult.issues.some((issue) => issue.code === "OVERLAPPING"));
  assert.ok(overlapResult.issues.some((issue) => issue.code === "MIXED_PROVIDER"));
  assert.ok(overlapResult.issues.some((issue) => issue.code === "MIXED_SERVICE"));
  assert.ok(overlapResult.issues.some((issue) => issue.code === "MIXED_TIMEZONE"));
});

test("range validator calculates nights by calendar date in provider timezone", () => {
  const india = rangeBooking.validateRangeBookingSelection({
    bookingType: "RANGE",
    checkInDateTime: new Date("2026-07-22T10:00:00.000Z"),
    checkOutDateTime: new Date("2026-07-24T10:00:00.000Z"),
    nights: 2,
    pricePerNightPaise: 250000,
    timezone: "Asia/Kolkata",
  });
  assert.equal(india.ok, true);

  const dstNights = rangeBooking.calculateRangeBookingNights({
    checkInDateTime: new Date("2026-03-07T17:00:00.000Z"),
    checkOutDateTime: new Date("2026-03-09T16:00:00.000Z"),
    timezone: "America/New_York",
  });
  assert.equal(dstNights, 2);
});

test("range validator rejects invalid range and enforces min/max nights", () => {
  const invalid = rangeBooking.validateRangeBookingSelection({
    bookingType: "RANGE",
    checkInDateTime: new Date("2026-07-24T10:00:00.000Z"),
    checkOutDateTime: new Date("2026-07-22T10:00:00.000Z"),
    nights: 0,
    pricePerNightPaise: 250000,
    timezone: "Asia/Kolkata",
  });
  assert.equal(invalid.ok, false);
  assert.ok(invalid.issues.some((issue) => issue.code === "INVALID_RANGE"));
  assert.ok(invalid.issues.some((issue) => issue.code === "INVALID_NIGHTS"));

  const minMax = rangeBooking.validateRangeBookingSelection({
    bookingType: "RANGE",
    checkInDateTime: new Date("2026-07-22T10:00:00.000Z"),
    checkOutDateTime: new Date("2026-07-23T10:00:00.000Z"),
    nights: 1,
    pricePerNightPaise: 250000,
    timezone: "Asia/Kolkata",
    minNights: 2,
    maxNights: 5,
  });
  assert.equal(minMax.ok, false);
  assert.ok(minMax.issues.some((issue) => issue.code === "BELOW_MIN_NIGHTS"));
});

test("pricing calculator uses integer paise and keeps provider payout independent from Pettxo-funded coupons", () => {
  const standard = pricing.calculateBookingFinancialSnapshot({
    currency: "INR",
    serviceSubtotalPaise: 100000,
    couponDiscountPaise: 0,
  });
  assert.equal(standard.platformCommissionPaise, 15000);
  assert.equal(standard.providerPayoutPaise, 85000);
  assert.equal(standard.customerPaidPaise, 100000);

  const coupon = pricing.calculateBookingFinancialSnapshot({
    currency: "INR",
    serviceSubtotalPaise: 100000,
    couponDiscountPaise: 30000,
  });
  assert.equal(coupon.customerPaidPaise, 70000);
  assert.equal(coupon.providerPayoutPaise, 85000);
  assert.equal(coupon.pettxoCouponFundingPaise, 30000);
  assert.equal(coupon.pettxoNetBeforeGatewayPaise, -15000);
});

test("pricing calculator supports a 100 percent coupon and deterministic floor rounding", () => {
  const free = pricing.calculateBookingFinancialSnapshot({
    currency: "INR",
    serviceSubtotalPaise: 999,
    couponDiscountPaise: 999,
  });
  assert.equal(free.customerPaidPaise, 0);
  assert.equal(free.platformCommissionPaise, 149);
  assert.equal(free.providerPayoutPaise, 850);
});

test("refunds are calculated from actual customer payment", () => {
  const refundAmount = pricing.calculateRefundAmountFromCustomerPaid({
    customerPaidPaise: 70000,
    refundBasisPoints: 7500,
  });
  assert.equal(refundAmount, 52500);
});

test("snapshot and event guards accept canonical typed payloads", () => {
  const serviceSnapshot = {
    serviceId: "service-1",
    providerId: "provider-1",
    serviceTitle: "Pet Boarding",
    animalType: "Dog",
    category: "Boarding",
    bookingType: "RANGE",
    timezone: "Asia/Kolkata",
    pricePerNightPaise: 250000,
    capacitySnapshot: 2,
    serviceLocationType: "provider_location",
    currency: "INR",
    snapshotVersion: 1,
  };
  assert.equal(snapshots.isBookingServiceSnapshot(serviceSnapshot), true);

  const financialSnapshot = pricing.calculateBookingFinancialSnapshot({
    currency: "INR",
    serviceSubtotalPaise: 100000,
    couponDiscountPaise: 30000,
  });
  assert.equal(snapshots.isBookingFinancialSnapshot(financialSnapshot), true);

  const eventRecord = {
    bookingId: "booking-1",
    event: "requested",
    actor: "parent",
    at: new Date("2026-07-22T10:00:00.000Z"),
    meta: {channel: "in_app"},
    schemaVersion: 1,
  };
  assert.equal(events.isBookingEventRecord(eventRecord), true);
  assert.equal(contracts.isCanonicalBookingState("CONFIRMED"), true);
});
