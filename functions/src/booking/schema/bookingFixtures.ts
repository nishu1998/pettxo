import {calculateBookingFinancialSnapshot} from "../domain/bookingPricing";
import {computeAcceptDeadlineAt, computePayDeadlineAt, computeRunwayEndsAt} from "../domain/bookingDeadlines";
import type {CanonicalBookingDocumentV3} from "./bookingDocumentV3";
import type {BookingServiceSnapshot} from "../domain/bookingSnapshots";
import type {BookingActor} from "../domain/bookingContracts";

function buildBaseParticipants() {
  return {
    parent: {
      parentId: "parent-1",
      displayFirstName: "Nisha",
      lastInitial: "G",
      photoUrl: "",
      completedBookingCount: 4,
      rating: 4.8,
    },
    provider: {
      providerId: "provider-1",
      displayName: "Pettxo Care",
      username: "pettxocare",
      photoUrl: "",
      completedBookingCount: 22,
      rating: 4.9,
    },
  };
}

function buildBaseServiceSnapshot(bookingType: "SLOT" | "RANGE"): BookingServiceSnapshot {
  return {
    serviceId: "service-1",
    providerId: "provider-1",
    serviceTitle: bookingType === "SLOT" ? "Dog Walking" : "Pet Boarding",
    animalType: "Dog",
    category: bookingType === "SLOT" ? "Walking" : "Boarding",
    bookingType,
    timezone: "Asia/Kolkata",
    serviceUnitPricePaise: bookingType === "SLOT" ? 25000 : undefined,
    durationMinutes: bookingType === "SLOT" ? 60 : undefined,
    pricePerNightPaise: bookingType === "RANGE" ? 180000 : undefined,
    selectedSlotCount: bookingType === "SLOT" ? 1 : undefined,
    totalDurationMinutes: bookingType === "SLOT" ? 60 : undefined,
    checkInDateTime: undefined,
    checkOutDateTime: undefined,
    capacitySnapshot: bookingType === "SLOT" ? 1 : 2,
    serviceLocationType: "provider_location",
    currency: "INR",
    snapshotVersion: 1,
  };
}

function buildAudit(): {createdBy: BookingActor; lastUpdatedBy: BookingActor; source: string} {
  return {
    createdBy: "system",
    lastUpdatedBy: "system",
    source: "fixture",
  };
}

function buildCommonFields(state: CanonicalBookingDocumentV3["state"], bookingType: CanonicalBookingDocumentV3["bookingType"], serviceAnchorAt: Date) {
  const createdAt = new Date("2026-07-22T10:00:00.000Z");
  return {
    schemaVersion: 3 as 3,
    bookingModelVersion: "3.2" as "3.2",
    documentFormat: "canonical_v3" as "canonical_v3",
    bookingType,
    state,
    participants: buildBaseParticipants(),
    privacy: {
      isPaidContactUnlocked: false,
      contactUnlockedAt: null,
      chatUnlockedAt: null,
      otpVisibleToParent: false,
      exactAddressUnlocked: false,
      privacyVersion: 1,
      privateParticipantsRefPath: "bookingPrivateParticipants/booking-1",
    },
    cancellation: {
      cancelledAt: null,
      cancelledBy: null,
      cancelReasonCode: "",
      cancelReasonText: "",
      hoursBeforeServiceAtCancel: null,
      refundBand: "",
      refundBasisPoints: null,
      refundAmountPaise: 0,
      providerCompensationPaise: 0,
      pettxoRetainedPaise: 0,
      cancellationType: null,
    },
    dispute: {
      disputeId: "",
      status: "none",
      raisedAt: null,
      raisedBy: null,
      reasonCode: "",
      description: "",
      evidenceRefs: [],
      resolvedAt: null,
      resolvedBy: null,
      resolution: "",
      resolutionVersion: 0,
      financialAdjustmentId: "",
      refundInstructionId: "",
      customerRefundPaise: 0,
      providerReleasePaise: 0,
    },
    payout: {
      status: "not_eligible",
      holdReason: "",
      eligibleAt: null,
      readyAt: null,
      processingAt: null,
      releasedAt: null,
      failedAt: null,
      providerPayoutPaise: 0,
      priorPaidPaise: 0,
      remainingPayablePaise: 0,
      payoutReference: "",
      externalTransactionId: "",
      failureCode: "",
      retryCount: 0,
    },
    statistics: {
      selectedSlotCount: bookingType === "SLOT" ? 1 : null,
      totalDurationMinutes: bookingType === "SLOT" ? 60 : null,
      nights: bookingType === "RANGE" ? 2 : null,
    },
    audit: buildAudit(),
    parentId: "parent-1",
    providerId: "provider-1",
    serviceId: "service-1",
    stateQueryValue: state,
    bookingTypeQueryValue: bookingType,
    serviceAnchorAt,
    scheduledStartAt: null,
    checkInDateTime: null,
    acceptDeadlineAt: null,
    payDeadlineAt: null,
    completedAt: null,
    customerId: "parent-1",
    serviceOwnerId: "provider-1",
    createdAt,
    updatedAt: createdAt,
  };
}

export function buildRequestedSingleSlotBookingFixture(): CanonicalBookingDocumentV3 {
  const slotStart = new Date("2026-07-23T06:00:00.000Z");
  const slotEnd = new Date("2026-07-23T07:00:00.000Z");
  const timerStartsAt = new Date("2026-07-22T10:30:00.000Z");
  const service = {
    ...buildBaseServiceSnapshot("SLOT"),
    selectedSlotCount: 1,
    totalDurationMinutes: 60,
  };
  return {
    ...buildCommonFields("REQUESTED", "SLOT", slotStart),
    service,
    schedule: {
      bookingType: "SLOT",
      slots: [{
        slotId: "slot-1",
        dateKey: "2026-07-23",
        startAt: slotStart,
        endAt: slotEnd,
        durationMinutes: 60,
        unitPricePaise: 25000,
        serviceId: "service-1",
        providerId: "provider-1",
        timezone: "Asia/Kolkata",
      }],
      slotCount: 1,
      scheduledStartAt: slotStart,
      scheduledEndAt: slotEnd,
      totalDurationMinutes: 60,
      timezone: "Asia/Kolkata",
      serviceAnchorAt: slotStart,
    },
    lifecycle: {
      requestedAt: new Date("2026-07-22T10:00:00.000Z"),
      timerStartsAt,
      wasQueuedOutsideWorkingHours: false,
      notifiedAt: new Date("2026-07-22T10:01:00.000Z"),
      acceptDeadlineAt: computeAcceptDeadlineAt(timerStartsAt),
      viewedByProviderAt: null,
      respondedAt: null,
      providerResponseType: null,
      responseSeconds: null,
      payDeadlineAt: null,
      paymentStartedAt: null,
      paidAt: null,
      paymentSeconds: null,
      otpGeneratedAt: null,
      otpEnteredAt: null,
      noShowAt: null,
      serviceEndedAt: null,
      disputeDeadlineAt: null,
      completedAt: null,
      reviewWindowEndsAt: null,
      finalizedAt: null,
      cancelledAt: null,
    },
    payment: {
      status: "not_started",
      razorpayOrderId: "",
      razorpayPaymentId: "",
      razorpayRefundId: "",
      paymentAttemptId: "",
      orderCreatedAt: null,
      paymentStartedAt: null,
      capturedAt: null,
      verifiedAt: null,
      verificationSource: "",
      webhookEventIds: [],
      failureCode: "",
      failureMessage: "",
    },
    financials: null,
    scheduledStartAt: slotStart,
    acceptDeadlineAt: computeAcceptDeadlineAt(timerStartsAt),
  };
}

export function buildRequestedMultiSlotBookingFixture(): CanonicalBookingDocumentV3 {
  const start = new Date("2026-07-23T06:00:00.000Z");
  const middle = new Date("2026-07-23T07:00:00.000Z");
  const end = new Date("2026-07-23T09:00:00.000Z");
  const timerStartsAt = new Date("2026-07-22T10:30:00.000Z");
  return {
    ...buildRequestedSingleSlotBookingFixture(),
    service: {
      ...buildBaseServiceSnapshot("SLOT"),
      selectedSlotCount: 3,
      totalDurationMinutes: 180,
    },
    schedule: {
      bookingType: "SLOT",
      slots: [
        {
          slotId: "slot-1",
          dateKey: "2026-07-23",
          startAt: start,
          endAt: middle,
          durationMinutes: 60,
          unitPricePaise: 25000,
          serviceId: "service-1",
          providerId: "provider-1",
          timezone: "Asia/Kolkata",
        },
        {
          slotId: "slot-2",
          dateKey: "2026-07-23",
          startAt: middle,
          endAt: new Date("2026-07-23T08:00:00.000Z"),
          durationMinutes: 60,
          unitPricePaise: 25000,
          serviceId: "service-1",
          providerId: "provider-1",
          timezone: "Asia/Kolkata",
        },
        {
          slotId: "slot-3",
          dateKey: "2026-07-23",
          startAt: new Date("2026-07-23T08:00:00.000Z"),
          endAt: end,
          durationMinutes: 60,
          unitPricePaise: 25000,
          serviceId: "service-1",
          providerId: "provider-1",
          timezone: "Asia/Kolkata",
        },
      ],
      slotCount: 3,
      scheduledStartAt: start,
      scheduledEndAt: end,
      totalDurationMinutes: 180,
      timezone: "Asia/Kolkata",
      serviceAnchorAt: start,
    },
    statistics: {
      selectedSlotCount: 3,
      totalDurationMinutes: 180,
      nights: null,
    },
    lifecycle: {
      ...buildRequestedSingleSlotBookingFixture().lifecycle,
      timerStartsAt,
      acceptDeadlineAt: computeAcceptDeadlineAt(timerStartsAt),
    },
    serviceAnchorAt: start,
    scheduledStartAt: start,
    acceptDeadlineAt: computeAcceptDeadlineAt(timerStartsAt),
  };
}

export function buildAcceptedAwaitingPaymentSlotBookingFixture(): CanonicalBookingDocumentV3 {
  const requested = buildRequestedSingleSlotBookingFixture();
  const respondedAt = new Date("2026-07-22T10:20:00.000Z");
  return {
    ...requested,
    state: "ACCEPTED_AWAITING_PAYMENT",
    stateQueryValue: "ACCEPTED_AWAITING_PAYMENT",
    lifecycle: {
      ...requested.lifecycle,
      respondedAt,
      providerResponseType: "accept",
      responseSeconds: 1200,
      payDeadlineAt: computePayDeadlineAt(respondedAt),
    },
    payment: {
      ...requested.payment,
      status: "awaiting_customer_payment",
    },
    payDeadlineAt: computePayDeadlineAt(respondedAt),
  };
}

export function buildConfirmedSlotBookingFixture(): CanonicalBookingDocumentV3 {
  const accepted = buildAcceptedAwaitingPaymentSlotBookingFixture();
  const financials = calculateBookingFinancialSnapshot({
    currency: "INR",
    serviceSubtotalPaise: 25000,
    couponDiscountPaise: 0,
  });
  const paidAt = new Date("2026-07-22T10:40:00.000Z");
  return {
    ...accepted,
    state: "CONFIRMED",
    stateQueryValue: "CONFIRMED",
    lifecycle: {
      ...accepted.lifecycle,
      paidAt,
      paymentStartedAt: new Date("2026-07-22T10:30:00.000Z"),
      paymentSeconds: 600,
    },
    payment: {
      ...accepted.payment,
      status: "paid",
      razorpayOrderId: "order_123",
      razorpayPaymentId: "pay_123",
      paymentAttemptId: "attempt_123",
      orderCreatedAt: new Date("2026-07-22T10:30:00.000Z"),
      paymentStartedAt: new Date("2026-07-22T10:30:00.000Z"),
      capturedAt: paidAt,
      verifiedAt: paidAt,
      verificationSource: "callable",
      webhookEventIds: ["event_1"],
    },
    financials,
    privacy: {
      ...accepted.privacy,
      isPaidContactUnlocked: true,
      contactUnlockedAt: paidAt,
      chatUnlockedAt: paidAt,
      exactAddressUnlocked: true,
    },
  };
}

export function buildRequestedRangeBookingFixture(): CanonicalBookingDocumentV3 {
  const checkIn = new Date("2026-07-24T06:00:00.000Z");
  const checkOut = new Date("2026-07-26T06:00:00.000Z");
  const timerStartsAt = new Date("2026-07-22T11:00:00.000Z");
  return {
    ...buildCommonFields("REQUESTED", "RANGE", checkIn),
    service: {
      ...buildBaseServiceSnapshot("RANGE"),
      pricePerNightPaise: 180000,
      checkInDateTime: checkIn,
      checkOutDateTime: checkOut,
    },
    schedule: {
      bookingType: "RANGE",
      checkInDateTime: checkIn,
      checkOutDateTime: checkOut,
      nights: 2,
      timezone: "Asia/Kolkata",
      minNightsSnapshot: 1,
      maxNightsSnapshot: 14,
      maxConcurrentPetsSnapshot: 2,
      petQuantity: 1,
      serviceAnchorAt: checkIn,
    },
    lifecycle: {
      requestedAt: new Date("2026-07-22T10:55:00.000Z"),
      timerStartsAt,
      wasQueuedOutsideWorkingHours: false,
      notifiedAt: new Date("2026-07-22T10:56:00.000Z"),
      acceptDeadlineAt: computeAcceptDeadlineAt(timerStartsAt),
      viewedByProviderAt: null,
      respondedAt: null,
      providerResponseType: null,
      responseSeconds: null,
      payDeadlineAt: null,
      paymentStartedAt: null,
      paidAt: null,
      paymentSeconds: null,
      otpGeneratedAt: null,
      otpEnteredAt: null,
      noShowAt: null,
      serviceEndedAt: null,
      disputeDeadlineAt: null,
      completedAt: null,
      reviewWindowEndsAt: null,
      finalizedAt: null,
      cancelledAt: null,
    },
    payment: {
      status: "not_started",
      razorpayOrderId: "",
      razorpayPaymentId: "",
      razorpayRefundId: "",
      paymentAttemptId: "",
      orderCreatedAt: null,
      paymentStartedAt: null,
      capturedAt: null,
      verifiedAt: null,
      verificationSource: "",
      webhookEventIds: [],
      failureCode: "",
      failureMessage: "",
    },
    financials: null,
    checkInDateTime: checkIn,
    acceptDeadlineAt: computeAcceptDeadlineAt(timerStartsAt),
  };
}

export function buildConfirmedRangeBookingFixture(): CanonicalBookingDocumentV3 {
  const requested = buildRequestedRangeBookingFixture();
  const respondedAt = new Date("2026-07-22T11:20:00.000Z");
  const paidAt = new Date("2026-07-22T11:45:00.000Z");
  const financials = calculateBookingFinancialSnapshot({
    currency: "INR",
    serviceSubtotalPaise: 360000,
    couponDiscountPaise: 20000,
  });
  return {
    ...requested,
    state: "CONFIRMED",
    stateQueryValue: "CONFIRMED",
    lifecycle: {
      ...requested.lifecycle,
      respondedAt,
      providerResponseType: "accept",
      responseSeconds: 1500,
      payDeadlineAt: computePayDeadlineAt(respondedAt),
      paymentStartedAt: new Date("2026-07-22T11:25:00.000Z"),
      paidAt,
      paymentSeconds: 1200,
    },
    payment: {
      ...requested.payment,
      status: "paid",
      razorpayOrderId: "order_range_1",
      razorpayPaymentId: "pay_range_1",
      paymentAttemptId: "attempt_range_1",
      orderCreatedAt: new Date("2026-07-22T11:25:00.000Z"),
      paymentStartedAt: new Date("2026-07-22T11:25:00.000Z"),
      capturedAt: paidAt,
      verifiedAt: paidAt,
      verificationSource: "webhook",
      webhookEventIds: ["event_range_1"],
    },
    financials,
    privacy: {
      ...requested.privacy,
      isPaidContactUnlocked: true,
      contactUnlockedAt: paidAt,
      chatUnlockedAt: paidAt,
      exactAddressUnlocked: true,
    },
    payDeadlineAt: computePayDeadlineAt(respondedAt),
  };
}

export function buildCancelledBookingFixture(): CanonicalBookingDocumentV3 {
  const confirmed = buildConfirmedSlotBookingFixture();
  const cancelledAt = new Date("2026-07-22T11:00:00.000Z");
  return {
    ...confirmed,
    state: "CANCELLED_BY_PARENT",
    stateQueryValue: "CANCELLED_BY_PARENT",
    lifecycle: {
      ...confirmed.lifecycle,
      cancelledAt,
    },
    cancellation: {
      cancelledAt,
      cancelledBy: "parent",
      cancelReasonCode: "changed_plan",
      cancelReasonText: "Plan changed",
      hoursBeforeServiceAtCancel: 19,
      refundBand: "between_24_and_12_hours",
      refundBasisPoints: 7500,
      refundAmountPaise: 18750,
      providerCompensationPaise: 0,
      pettxoRetainedPaise: 6250,
      cancellationType: "parent_requested",
    },
    financials: {
      ...confirmed.financials!,
      refundAmountPaise: 18750,
    },
  };
}

export function buildCompletedFinalBookingFixture(): CanonicalBookingDocumentV3 {
  const confirmed = buildConfirmedRangeBookingFixture();
  const serviceEndedAt = new Date("2026-07-26T06:00:00.000Z");
  const completedAt = new Date("2026-07-26T06:30:00.000Z");
  return {
    ...confirmed,
    state: "COMPLETED_FINAL",
    stateQueryValue: "COMPLETED_FINAL",
    lifecycle: {
      ...confirmed.lifecycle,
      serviceEndedAt,
      disputeDeadlineAt: new Date("2026-07-27T06:30:00.000Z"),
      completedAt,
    },
    payout: {
      status: "released",
      holdReason: "",
      eligibleAt: computeRunwayEndsAt(new Date("2026-07-22T11:00:00.000Z")),
      readyAt: new Date("2026-07-27T06:30:00.000Z"),
      processingAt: new Date("2026-07-27T06:35:00.000Z"),
      releasedAt: new Date("2026-07-27T06:45:00.000Z"),
      failedAt: null,
      providerPayoutPaise: confirmed.financials?.providerPayoutPaise ?? 0,
      priorPaidPaise: confirmed.financials?.providerPayoutPaise ?? 0,
      remainingPayablePaise: 0,
      payoutReference: "payout_1",
      externalTransactionId: "txn_1",
      failureCode: "",
      retryCount: 0,
    },
    completedAt,
  };
}
