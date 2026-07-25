const {
  buildAcceptedAwaitingPaymentSlotBookingFixture,
} = require("../../lib/booking/schema/bookingFixtures.js");
const {
  resolveCanonicalPricingV3,
} = require("../../lib/booking/application/paymentOrchestrationV3.js");

const DEFAULT_IDS = Object.freeze({
  bookingId: "booking-race-1",
  paymentAttemptId: "attempt-race-1",
  razorpayOrderId: "order_race_1",
  razorpayPaymentId: "pay_race_1",
  webhookEventId: "payment.captured:pay_race_1",
  refundInstructionId: "booking-race-1",
});

function parentIdentity() {
  return {
    uid: "parent-1",
    displayName: "Nisha Gautam",
    fullName: "Nisha Gautam",
    email: "nisha@example.com",
    phoneNumber: "+919999999999",
  };
}

function liveService() {
  return {
    status: "active",
    isActive: true,
    isDeleted: false,
    isPaused: false,
    isVisibleToMarketplace: true,
    isPausedByVerification: false,
    location: {
      displayAddress: "Andheri West, Mumbai",
      latitude: 19.136,
      longitude: 72.829,
    },
  };
}

function buildPaymentAttempt({booking, pricing, ids = DEFAULT_IDS, overrides = {}}) {
  return {
    schemaVersion: 1,
    paymentAttemptId: ids.paymentAttemptId,
    bookingId: ids.bookingId,
    parentId: booking.parentId,
    providerId: booking.providerId,
    requestAttemptId: `request-${ids.paymentAttemptId}`,
    razorpayOrderId: ids.razorpayOrderId,
    razorpayPaymentId: "",
    amountPaise: pricing.financialSnapshot.customerPaidPaise,
    currency: "INR",
    couponId: "",
    couponClaimId: "",
    pricingHash: pricing.pricingHash,
    availabilityHash: `availability-${ids.paymentAttemptId}`,
    state: "ORDER_CREATED",
    orderExpiresAt: booking.lifecycle.payDeadlineAt,
    createdAt: new Date("2026-07-22T10:20:00.000Z"),
    orderCreatedAt: new Date("2026-07-22T10:21:00.000Z"),
    checkoutOpenedAt: new Date("2026-07-22T10:21:30.000Z"),
    captureReportedAt: null,
    captureCreatedAt: null,
    confirmedAt: null,
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
    verificationSource: "",
    failureCode: "",
    failureMessage: "",
    retryCount: 0,
    updatedAt: new Date("2026-07-22T10:21:30.000Z"),
    pricingSnapshot: {financials: pricing.financialSnapshot},
    couponSnapshot: null,
    ...overrides,
  };
}

function buildCapturedPayment({pricing, ids = DEFAULT_IDS, overrides = {}}) {
  return {
    id: ids.razorpayPaymentId,
    orderId: ids.razorpayOrderId,
    status: "captured",
    amountPaise: pricing.financialSnapshot.customerPaidPaise,
    currency: "INR",
    createdAt: new Date("2026-07-22T10:25:00.000Z"),
    capturedAt: new Date("2026-07-22T10:25:05.000Z"),
    ...overrides,
  };
}

function buildCanonicalPaymentRaceFixture(options = {}) {
  const ids = {...DEFAULT_IDS, ...(options.ids ?? {})};
  const booking = buildAcceptedAwaitingPaymentSlotBookingFixture();
  const pricing = resolveCanonicalPricingV3({booking, claimedOffer: null});
  booking.financials = pricing.financialSnapshot;

  return {
    ids,
    booking,
    pricing,
    parent: parentIdentity(),
    service: liveService(),
    paymentAttempt: buildPaymentAttempt({booking, pricing, ids, overrides: options.attemptOverrides}),
    razorpayPayment: buildCapturedPayment({pricing, ids, overrides: options.paymentOverrides}),
    authoritativeNow: options.authoritativeNow ?? new Date("2026-07-22T10:25:10.000Z"),
    slotOccupancy: options.slotOccupancy ?? {},
    rangeOccupancy: options.rangeOccupancy ?? {},
  };
}

function assertNoPrivateLeakage(value) {
  const serialized = JSON.stringify(value);
  for (const forbidden of [
    "123456",
    "482913",
    "+919999999999",
    "Andheri West, Mumbai",
    "parentOtpCode",
    "providerOtpHash",
    "phoneNumber",
    "serviceAddress",
    "latitude",
    "longitude",
  ]) {
    if (serialized.includes(forbidden)) {
      throw new Error(`Found private leakage token: ${forbidden}`);
    }
  }
}

module.exports = {
  DEFAULT_IDS,
  buildCanonicalPaymentRaceFixture,
  buildPaymentAttempt,
  buildCapturedPayment,
  parentIdentity,
  liveService,
  assertNoPrivateLeakage,
};
