const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildConfirmedSlotBookingFixture,
} = require("../lib/booking/schema/bookingFixtures.js");
const {
  applyConfirmedBookingCancellationV3,
  persistConfirmedBookingCancellationV3,
} = require("../lib/booking/application/cancellationOrchestrationV3.js");
const {
  FakeFirestore,
} = require("./helpers/canonicalPaymentRaceHarness.js");

function buildConfirmedAttempt({bookingId, booking}) {
  return {
    schemaVersion: 1,
    paymentAttemptId: booking.payment.paymentAttemptId || "attempt-confirmed-1",
    bookingId,
    parentId: booking.parentId,
    providerId: booking.providerId,
    requestAttemptId: `request-${bookingId}`,
    razorpayOrderId: booking.payment.razorpayOrderId || "order-confirmed-1",
    razorpayPaymentId: booking.payment.razorpayPaymentId || "pay-confirmed-1",
    amountPaise: booking.financials.customerPaidPaise,
    currency: booking.financials.currency,
    couponId: "",
    couponClaimId: "",
    pricingHash: "pricing-confirmed-1",
    availabilityHash: "availability-confirmed-1",
    state: "CONFIRMED",
    orderExpiresAt: booking.payDeadlineAt,
    createdAt: new Date("2026-07-22T10:20:00.000Z"),
    orderCreatedAt: new Date("2026-07-22T10:21:00.000Z"),
    checkoutOpenedAt: new Date("2026-07-22T10:21:30.000Z"),
    captureReportedAt: booking.lifecycle.paidAt,
    captureCreatedAt: booking.lifecycle.paidAt,
    confirmedAt: booking.lifecycle.paidAt,
    failedAt: null,
    refundRequiredAt: null,
    refundedAt: null,
    nextReconciliationAt: null,
    lastReconciledAt: null,
    reconciliationAttemptCount: 0,
    lastReconciliationCode: "",
    terminalFailureAt: null,
    leaseOwner: "",
    leaseExpiresAt: null,
    verificationSource: "callable",
    failureCode: "",
    failureMessage: "",
    retryCount: 0,
    updatedAt: booking.updatedAt,
    pricingSnapshot: {financials: booking.financials},
    couponSnapshot: null,
  };
}

function buildConfirmedBooking(anchorIso = "2026-07-24T12:00:00.000Z") {
  const booking = buildConfirmedSlotBookingFixture();
  booking.scheduledStartAt = new Date(anchorIso);
  booking.serviceAnchorAt = booking.scheduledStartAt;
  booking.schedule.scheduledStartAt = booking.scheduledStartAt;
  return booking;
}

test("customer cancellation at exactly 24h creates one deterministic refund instruction and capacity release", async () => {
  const bookingId = "booking-cancel-1";
  const booking = buildConfirmedBooking();
  const attempt = buildConfirmedAttempt({bookingId, booking});
  const slotId = booking.schedule.slots[0].slotId;

  const result = applyConfirmedBookingCancellationV3({
    bookingId,
    booking,
    paymentAttempt: attempt,
    actorType: "CUSTOMER",
    actorId: booking.parentId,
    reasonCode: "customer_requested",
    authoritativeNow: new Date("2026-07-23T12:00:00.000Z"),
    existingSlotOccupancy: {
      [slotId]: {
        slotId,
        confirmedUnits: 1,
        capacitySnapshot: 1,
        bookingClaims: {[bookingId]: 1},
      },
    },
    existingBookingPrivate: {
      bookingId,
      parentOtpCode: "123456",
      providerOtpHash: "hash",
      contactUnlockedAt: new Date("2026-07-22T10:25:05.000Z"),
    },
    existingBookingChat: {
      bookingId,
      participantIds: [booking.parentId, booking.providerId],
      status: "unlocked",
    },
  });

  assert.equal(result.idempotentReplay, false);
  assert.equal(result.booking.state, "CANCELLED");
  assert.equal(result.paymentAttempt.state, "REFUND_REQUIRED");
  assert.equal(result.cancellationRecord.timingBand, "BETWEEN_24_AND_12_HOURS");
  assert.equal(result.cancellationRecord.refundAmountPaise, 18750);
  assert.equal(result.cancellationRecord.providerCompensationPaise, 3750);
  assert.equal(result.cancellationRecord.pettxoRetainedPaise, 2500);
  assert.equal(result.refundInstruction.refundInstructionId, `refund-${bookingId}`);
  assert.equal(result.capacityRelease.state, "RELEASED");
  assert.deepEqual(
    Object.keys(result.capacityRelease.writes),
    [`services/${booking.serviceId}/slotOccupancy/${slotId}`],
  );
  assert.equal(result.booking.privacy.isPaidContactUnlocked, false);
  assert.equal(result.bookingPrivateWrite.parentOtpCode, "");

  const firestore = new FakeFirestore();
  await persistConfirmedBookingCancellationV3({
    firestore,
    bookingId,
    result,
  });
  assert.equal(firestore.store.has(`bookingCancellations/${bookingId}`), true);
  assert.equal(firestore.store.has(`refunds/${bookingId}`), true);
  assert.equal(firestore.store.has(`capacityReleases/${bookingId}`), true);
});

test("under-2-hours customer cancellation persists without a Razorpay refund instruction", () => {
  const bookingId = "booking-cancel-2";
  const booking = buildConfirmedBooking();
  const attempt = buildConfirmedAttempt({bookingId, booking});

  const result = applyConfirmedBookingCancellationV3({
    bookingId,
    booking,
    paymentAttempt: attempt,
    actorType: "CUSTOMER",
    actorId: booking.parentId,
    reasonCode: "customer_requested",
    authoritativeNow: new Date("2026-07-24T10:30:00.000Z"),
  });

  assert.equal(result.booking.state, "CANCELLED");
  assert.equal(result.cancellationRecord.timingBand, "UNDER_2_HOURS");
  assert.equal(result.cancellationRecord.refundAmountPaise, 0);
  assert.equal(result.cancellationRecord.providerCompensationPaise, 21250);
  assert.equal(result.paymentAttempt.state, "CONFIRMED");
  assert.equal(result.refundInstruction, null);
});

test("provider cancellation refunds the full customer-paid amount and records provider-fault cost", () => {
  const bookingId = "booking-cancel-3";
  const booking = buildConfirmedBooking();
  const attempt = buildConfirmedAttempt({bookingId, booking});

  const result = applyConfirmedBookingCancellationV3({
    bookingId,
    booking,
    paymentAttempt: attempt,
    actorType: "PROVIDER",
    actorId: booking.providerId,
    reasonCode: "provider_requested",
    authoritativeNow: new Date("2026-07-23T18:00:00.000Z"),
  });

  assert.equal(result.booking.state, "CANCELLED");
  assert.equal(result.cancellationRecord.actorType, "PROVIDER");
  assert.equal(
    result.cancellationRecord.refundAmountPaise,
    booking.financials.customerPaidPaise,
  );
  assert.equal(
    result.cancellationRecord.providerFaultCostPaise,
    booking.financials.gatewayFeeSunkPaise,
  );
  assert.equal(result.payoutReadinessWrite.status, "cancelled");
  assert.equal(result.providerEarningWrite.status, "cancelled");
});

test("otp-entered bookings are blocked from normal cancellation", () => {
  const bookingId = "booking-cancel-4";
  const booking = buildConfirmedBooking();
  booking.lifecycle.otpEnteredAt = new Date("2026-07-24T08:30:00.000Z");
  const attempt = buildConfirmedAttempt({bookingId, booking});

  assert.throws(
    () =>
      applyConfirmedBookingCancellationV3({
        bookingId,
        booking,
        paymentAttempt: attempt,
        actorType: "CUSTOMER",
        actorId: booking.parentId,
        reasonCode: "customer_requested",
        authoritativeNow: new Date("2026-07-24T09:00:00.000Z"),
      }),
    /otp verification/i,
  );
});

test("existing canonical cancellation replays without a second refund instruction", () => {
  const bookingId = "booking-cancel-5";
  const booking = buildConfirmedBooking();
  booking.state = "CANCELLED";
  booking.stateQueryValue = "CANCELLED";
  booking.lifecycle.cancelledAt = new Date("2026-07-23T12:00:00.000Z");
  const attempt = buildConfirmedAttempt({bookingId, booking});

  const result = applyConfirmedBookingCancellationV3({
    bookingId,
    booking,
    paymentAttempt: attempt,
    actorType: "CUSTOMER",
    actorId: booking.parentId,
    reasonCode: "customer_requested",
    authoritativeNow: new Date("2026-07-23T12:01:00.000Z"),
    existingCancellation: {
      bookingId,
      actorId: booking.parentId,
      actorType: "CUSTOMER",
      status: "REFUND_PENDING",
      refundStatus: "REFUND_PENDING",
      refundAmountPaise: 18750,
      timingBand: "BETWEEN_24_AND_12_HOURS",
      outcome: "PARTIAL_REFUND",
    },
  });

  assert.equal(result.idempotentReplay, true);
  assert.equal(result.refundInstruction, null);
  assert.equal(result.notifications.length, 0);
});
