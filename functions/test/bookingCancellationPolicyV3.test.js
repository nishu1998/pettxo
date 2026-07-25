const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildConfirmedRangeBookingFixture,
  buildConfirmedSlotBookingFixture,
} = require("../lib/booking/schema/bookingFixtures.js");
const {
  calculateCanonicalCancellationDecisionV3,
} = require("../lib/booking/application/cancellationOrchestrationV3.js");

function buildSlotBooking(anchorIso = "2026-07-24T12:00:00.000Z") {
  const booking = buildConfirmedSlotBookingFixture();
  booking.scheduledStartAt = new Date(anchorIso);
  booking.serviceAnchorAt = booking.scheduledStartAt;
  booking.schedule.scheduledStartAt = booking.scheduledStartAt;
  return booking;
}

function buildRangeBooking(anchorIso = "2026-07-24T15:00:00.000Z") {
  const booking = buildConfirmedRangeBookingFixture();
  booking.checkInDateTime = new Date(anchorIso);
  booking.serviceAnchorAt = booking.checkInDateTime;
  booking.schedule.checkInDateTime = booking.checkInDateTime;
  return booking;
}

function decide({
  booking,
  requestedAt,
  actorType = "CUSTOMER",
  existingRefund = null,
}) {
  return calculateCanonicalCancellationDecisionV3({
    booking,
    actorType,
    requestedAt: new Date(requestedAt),
    existingRefund,
  });
}

test("24h + 1ms stays in the 95 percent band", () => {
  const booking = buildSlotBooking();
  const decision = decide({
    booking,
    requestedAt: "2026-07-23T11:59:59.999Z",
  });

  assert.equal(decision.allowed, true);
  assert.equal(decision.timingBand, "MORE_THAN_24_HOURS");
  assert.equal(decision.refundPercentageBasisPoints, 9500);
  assert.equal(decision.providerShareBasisPoints, 0);
  assert.equal(decision.pettxoShareBasisPoints, 500);
  assert.equal(decision.grossCustomerRefundPaise, 23750);
});

test("exactly 24h moves into the 75 percent customer band", () => {
  const booking = buildSlotBooking();
  const decision = decide({
    booking,
    requestedAt: "2026-07-23T12:00:00.000Z",
  });

  assert.equal(decision.allowed, true);
  assert.equal(decision.timingBand, "BETWEEN_24_AND_12_HOURS");
  assert.equal(decision.refundPercentageBasisPoints, 7500);
  assert.equal(decision.providerShareBasisPoints, 1500);
  assert.equal(decision.pettxoShareBasisPoints, 1000);
  assert.equal(decision.grossCustomerRefundPaise, 18750);
  assert.equal(decision.providerCompensationPaise, 3750);
  assert.equal(decision.retainedCustomerAmountPaise, 2500);
});

test("12h + 1ms remains in the 75 percent customer band", () => {
  const booking = buildSlotBooking();
  const decision = decide({
    booking,
    requestedAt: "2026-07-23T23:59:59.999Z",
  });

  assert.equal(decision.timingBand, "BETWEEN_24_AND_12_HOURS");
  assert.equal(decision.grossCustomerRefundPaise, 18750);
});

test("exactly 12h still belongs to the 75 percent customer band", () => {
  const booking = buildSlotBooking();
  const decision = decide({
    booking,
    requestedAt: "2026-07-24T00:00:00.000Z",
  });

  assert.equal(decision.timingBand, "BETWEEN_24_AND_12_HOURS");
  assert.equal(decision.grossCustomerRefundPaise, 18750);
});

test("12h - 1ms moves into the 50 percent customer band", () => {
  const booking = buildSlotBooking();
  const decision = decide({
    booking,
    requestedAt: "2026-07-24T00:00:00.001Z",
  });

  assert.equal(decision.timingBand, "BETWEEN_12_AND_6_HOURS");
  assert.equal(decision.refundPercentageBasisPoints, 5000);
  assert.equal(decision.providerShareBasisPoints, 3500);
  assert.equal(decision.pettxoShareBasisPoints, 1500);
  assert.equal(decision.grossCustomerRefundPaise, 12500);
  assert.equal(decision.providerCompensationPaise, 8750);
  assert.equal(decision.retainedCustomerAmountPaise, 3750);
});

test("exactly 6h stays in the 50 percent customer band", () => {
  const booking = buildSlotBooking();
  const decision = decide({
    booking,
    requestedAt: "2026-07-24T06:00:00.000Z",
  });

  assert.equal(decision.timingBand, "BETWEEN_12_AND_6_HOURS");
  assert.equal(decision.grossCustomerRefundPaise, 12500);
});

test("6h - 1ms moves into the 25 percent customer band", () => {
  const booking = buildSlotBooking();
  const decision = decide({
    booking,
    requestedAt: "2026-07-24T06:00:00.001Z",
  });

  assert.equal(decision.timingBand, "BETWEEN_6_AND_2_HOURS");
  assert.equal(decision.refundPercentageBasisPoints, 2500);
  assert.equal(decision.providerShareBasisPoints, 6000);
  assert.equal(decision.pettxoShareBasisPoints, 1500);
  assert.equal(decision.grossCustomerRefundPaise, 6250);
  assert.equal(decision.providerCompensationPaise, 15000);
  assert.equal(decision.retainedCustomerAmountPaise, 3750);
});

test("exactly 2h stays in the 25 percent customer band", () => {
  const booking = buildSlotBooking();
  const decision = decide({
    booking,
    requestedAt: "2026-07-24T10:00:00.000Z",
  });

  assert.equal(decision.timingBand, "BETWEEN_6_AND_2_HOURS");
  assert.equal(decision.grossCustomerRefundPaise, 6250);
});

test("2h - 1ms moves into the zero-refund under-2-hours band", () => {
  const booking = buildSlotBooking();
  const decision = decide({
    booking,
    requestedAt: "2026-07-24T10:00:00.001Z",
  });

  assert.equal(decision.allowed, true);
  assert.equal(decision.timingBand, "UNDER_2_HOURS");
  assert.equal(decision.refundPercentageBasisPoints, 0);
  assert.equal(decision.providerShareBasisPoints, 8500);
  assert.equal(decision.pettxoShareBasisPoints, 1500);
  assert.equal(decision.grossCustomerRefundPaise, 0);
  assert.equal(decision.providerCompensationPaise, 21250);
  assert.equal(decision.retainedCustomerAmountPaise, 3750);
});

test("exactly service start keeps the zero-refund policy result but blocks normal cancellation", () => {
  const booking = buildSlotBooking();
  const decision = decide({
    booking,
    requestedAt: "2026-07-24T12:00:00.000Z",
  });

  assert.equal(decision.allowed, false);
  assert.equal(decision.timingBand, "UNDER_2_HOURS");
  assert.equal(decision.refundPercentageBasisPoints, 0);
  assert.equal(decision.reasonCode, "SERVICE_START_REACHED");
});

test("after service start blocks normal cancellation", () => {
  const booking = buildSlotBooking();
  const decision = decide({
    booking,
    requestedAt: "2026-07-24T12:00:00.001Z",
  });

  assert.equal(decision.allowed, false);
  assert.equal(decision.timingBand, "AFTER_START");
  assert.equal(decision.reasonCode, "SERVICE_ALREADY_STARTED");
});

test("otpEnteredAt blocks normal cancellation and uses the locked 0/85/15 policy values", () => {
  const booking = buildSlotBooking();
  booking.lifecycle.otpEnteredAt = new Date("2026-07-24T08:30:00.000Z");
  const decision = decide({
    booking,
    requestedAt: "2026-07-24T09:00:00.000Z",
  });

  assert.equal(decision.allowed, false);
  assert.equal(decision.timingBand, "AFTER_OTP_ENTRY");
  assert.equal(decision.refundPercentageBasisPoints, 0);
  assert.equal(decision.providerShareBasisPoints, 8500);
  assert.equal(decision.pettxoShareBasisPoints, 1500);
  assert.equal(decision.reasonCode, "OTP_ALREADY_ENTERED");
});

test("provider cancellation always returns 100 percent of the actual customer-paid amount", () => {
  const booking = buildSlotBooking();
  const decision = decide({
    booking,
    requestedAt: "2026-07-24T09:00:00.000Z",
    actorType: "PROVIDER",
  });

  assert.equal(decision.allowed, true);
  assert.equal(decision.timingBand, "PROVIDER_CANCELLATION");
  assert.equal(decision.grossCustomerRefundPaise, booking.financials.customerPaidPaise);
  assert.equal(decision.providerCompensationPaise, 0);
  assert.equal(decision.providerFaultCostPaise, booking.financials.gatewayFeeSunkPaise);
});

test("range bookings use checkInDateTime as the service anchor", () => {
  const booking = buildRangeBooking("2026-07-26T15:00:00.000Z");
  const decision = decide({
    booking,
    requestedAt: "2026-07-25T15:00:00.000Z",
  });

  assert.equal(decision.timingBand, "BETWEEN_24_AND_12_HOURS");
});

test("partial Pettxo coupon keeps the refund based on actual customer-paid amount", () => {
  const booking = buildSlotBooking("2026-07-24T12:00:00.000Z");
  booking.financials.serviceSubtotalPaise = 100000;
  booking.financials.couponDiscountPaise = 50000;
  booking.financials.customerPaidPaise = 50000;
  booking.financials.pettxoCouponFundingPaise = 50000;
  booking.financials.providerPayoutPaise = 85000;
  booking.financials.platformCommissionPaise = 15000;
  booking.financials.pettxoNetBeforeGatewayPaise = -35000;
  const decision = decide({
    booking,
    requestedAt: "2026-07-23T11:59:59.999Z",
  });

  assert.equal(decision.grossCustomerRefundPaise, 47500);
  assert.equal(decision.providerCompensationPaise, 0);
  assert.equal(decision.retainedCustomerAmountPaise, 2500);
  assert.equal(decision.PettxoCouponCostPaise, 50000);
});

test("100 percent Pettxo coupon creates no customer refund but still preserves provider and Pettxo accounting fields", () => {
  const booking = buildSlotBooking("2026-07-24T12:00:00.000Z");
  booking.financials.serviceSubtotalPaise = 100000;
  booking.financials.couponDiscountPaise = 100000;
  booking.financials.customerPaidPaise = 0;
  booking.financials.pettxoCouponFundingPaise = 100000;
  booking.financials.providerPayoutPaise = 85000;
  booking.financials.platformCommissionPaise = 15000;
  booking.financials.pettxoNetBeforeGatewayPaise = -85000;
  const decision = decide({
    booking,
    requestedAt: "2026-07-23T11:59:59.999Z",
  });

  assert.equal(decision.grossCustomerRefundPaise, 0);
  assert.equal(decision.providerCompensationPaise, 0);
  assert.equal(decision.retainedCustomerAmountPaise, 0);
  assert.equal(decision.PettxoCouponCostPaise, 100000);
});

test("prior refunds reduce the remaining refundable basis deterministically", () => {
  const booking = buildSlotBooking("2026-07-24T12:00:00.000Z");
  const decision = decide({
    booking,
    requestedAt: "2026-07-23T11:59:59.999Z",
    existingRefund: {refundAmountPaise: 20000},
  });

  assert.equal(decision.alreadyRefundedPaise, 20000);
  assert.equal(decision.remainingRefundablePaise, 5000);
  assert.equal(decision.grossCustomerRefundPaise, 4750);
});

test("negative persisted financial values are rejected", () => {
  const booking = buildSlotBooking();
  booking.financials.customerPaidPaise = -1;

  assert.throws(
    () =>
      decide({
        booking,
        requestedAt: "2026-07-23T11:59:59.999Z",
      }),
    /customerPaidPaise/,
  );
});

test("repeated calculation is deterministic for the same inputs", () => {
  const booking = buildSlotBooking();
  const first = decide({
    booking,
    requestedAt: "2026-07-23T12:00:00.000Z",
  });
  const second = decide({
    booking,
    requestedAt: "2026-07-23T12:00:00.000Z",
  });

  assert.deepEqual(second, first);
});
