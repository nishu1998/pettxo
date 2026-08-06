import {FieldValue, Timestamp, type Firestore, type Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/https";

import {calculateBasisPointsAmount, calculateRefundAmountFromCustomerPaid} from "../domain/bookingPricing";
import type {CanonicalBookingDocumentV3} from "../schema/bookingDocumentV3";
import type {CanonicalPaymentAttemptDocumentV3} from "../schema/paymentAttemptDocumentV3";
import {buildBookingEventPlan, type BookingEventWritePlan} from "./bookingEventsWriter";
import type {BookingNotificationPlan} from "./bookingNotificationsV3";
import {buildStoredBookingNotificationDocument} from "../../notifications/notificationChannels";

const TWENTY_FOUR_HOURS_MS = 24 * 60 * 60 * 1000;
const TWELVE_HOURS_MS = 12 * 60 * 60 * 1000;
const SIX_HOURS_MS = 6 * 60 * 60 * 1000;
const TWO_HOURS_MS = 2 * 60 * 60 * 1000;
const CANCELLATION_POLICY_VERSION = "v3.2_slice6";

export const BOOKING_CANCELLATION_COLLECTION = "bookingCancellations";
export const BOOKING_FINANCIAL_ADJUSTMENTS_COLLECTION =
  "bookingFinancialAdjustments";
export const CAPACITY_RELEASES_COLLECTION = "capacityReleases";

export const CANCELLATION_ACTOR_TYPES = [
  "CUSTOMER",
  "PROVIDER",
  "ADMIN",
] as const;
export type CancellationActorType =
  typeof CANCELLATION_ACTOR_TYPES[number];

export const CANCELLATION_TIMING_BANDS = [
  "MORE_THAN_24_HOURS",
  "BETWEEN_24_AND_12_HOURS",
  "BETWEEN_12_AND_6_HOURS",
  "BETWEEN_6_AND_2_HOURS",
  "UNDER_2_HOURS",
  "AFTER_OTP_ENTRY",
  "PROVIDER_CANCELLATION",
  "AFTER_START",
] as const;
export type CancellationTimingBand =
  typeof CANCELLATION_TIMING_BANDS[number];

export const CANCELLATION_OUTCOMES = [
  "FULL_REFUND",
  "PARTIAL_REFUND",
  "NO_REFUND",
  "MANUAL_REVIEW",
  "NOT_ALLOWED",
] as const;
export type CancellationOutcome = typeof CANCELLATION_OUTCOMES[number];

export const CAPACITY_RELEASE_STATES = [
  "NOT_REQUIRED",
  "PENDING",
  "PROCESSING",
  "RELEASED",
  "RETRYABLE_FAILURE",
  "TERMINAL_FAILURE",
] as const;
export type CapacityReleaseState = typeof CAPACITY_RELEASE_STATES[number];

export type CanonicalCancellationDecision = {
  allowed: boolean;
  outcome: CancellationOutcome;
  timingBand: CancellationTimingBand;
  refundPercentageBasisPoints: number;
  providerShareBasisPoints: number;
  pettxoShareBasisPoints: number;
  grossCustomerRefundPaise: number;
  alreadyRefundedPaise: number;
  remainingRefundablePaise: number;
  refundableCustomerPaidPaise: number;
  nonRefundableCustomerPaidPaise: number;
  providerCompensationPaise: number;
  providerEarningReversalPaise: number;
  PettxoCouponCostPaise: number;
  commissionReversalPaise: number;
  gatewayFeeSunkPaise: number;
  providerFaultCostPaise: number;
  customerPaidPaise: number;
  serviceSubtotalPaise: number;
  couponDiscountPaise: number;
  retainedCustomerAmountPaise: number;
  capacityReleaseRequired: boolean;
  financialReversalRequired: boolean;
  finalBookingState: CanonicalBookingDocumentV3["state"];
  reasonCode: string;
  actorType: CancellationActorType;
  policyVersion: string;
};

export type CanonicalBookingCancellationRecord = {
  cancellationId: string;
  bookingId: string;
  actorType: CancellationActorType;
  actorId: string;
  reasonCode: string;
  reasonText: string;
  requestedAt: Date;
  effectiveAt: Date;
  policyVersion: string;
  timingBand: CancellationTimingBand;
  refundPercentageBasisPoints: number;
  providerShareBasisPoints: number;
  pettxoShareBasisPoints: number;
  refundableCustomerPaidPaise: number;
  nonRefundableCustomerPaidPaise: number;
  providerCompensationPaise: number;
  pettxoRetainedPaise: number;
  gatewayFeeSunkPaise: number;
  providerFaultCostPaise: number;
  customerPaidPaise: number;
  capacityReleaseRequired: boolean;
  financialReversalRequired: boolean;
  refundInstructionId: string;
  status: string;
  createdAt: Date;
  updatedAt: Date;
  refundAmountPaise: number;
  refundStatus: string;
  capacityReleaseState: CapacityReleaseState;
  outcome: CancellationOutcome;
};

type SlotOccupancyDocument = {
  slotId: string;
  confirmedUnits: number;
  capacitySnapshot: number;
  bookingClaims: Record<string, number>;
};

type RangeOccupancyDocument = {
  dateKey: string;
  confirmedPetUnits: number;
  capacitySnapshot: number;
  bookingClaims: Record<string, number>;
};

export type CapacityReleaseResult = {
  state: CapacityReleaseState;
  writes: Record<string, Record<string, unknown>>;
  marker: Record<string, unknown>;
};

export type CancellationPreviewResult = {
  bookingId: string;
  actorType: CancellationActorType;
  allowed: boolean;
  decision: CanonicalCancellationDecision;
};

export type ApplyConfirmedBookingCancellationResult = {
  booking: CanonicalBookingDocumentV3;
  paymentAttempt: CanonicalPaymentAttemptDocumentV3;
  cancellationRecord: CanonicalBookingCancellationRecord;
  financialAdjustment: Record<string, unknown>;
  capacityRelease: CapacityReleaseResult;
  refundInstruction: Record<string, unknown> | null;
  notifications: BookingNotificationPlan[];
  events: BookingEventWritePlan[];
  bookingPrivateWrite: Record<string, unknown> | null;
  bookingChatWrite: Record<string, unknown> | null;
  paymentWrite: Record<string, unknown>;
  invoiceWrite: Record<string, unknown>;
  bookingFinancialWrite: Record<string, unknown>;
  providerEarningWrite: Record<string, unknown>;
  payoutReadinessWrite: Record<string, unknown>;
  idempotentReplay: boolean;
};

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asInt(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.trunc(value)
    : fallback;
}

function assertNonNegativeInteger(value: number, field: string): void {
  if (!Number.isInteger(value) || value < 0) {
    throw new Error(`${field} must be a non-negative integer paise value.`);
  }
}

function cloneBooking(
  booking: CanonicalBookingDocumentV3,
): CanonicalBookingDocumentV3 {
  return structuredClone(booking);
}

function cloneAttempt(
  attempt: CanonicalPaymentAttemptDocumentV3,
): CanonicalPaymentAttemptDocumentV3 {
  return structuredClone(attempt);
}

function cancellationIdForBooking(bookingId: string): string {
  return bookingId;
}

function refundInstructionIdForBooking(bookingId: string): string {
  return `refund-${bookingId}`;
}

function slotOccupancyPath(serviceId: string, slotId: string): string {
  return `services/${serviceId}/slotOccupancy/${slotId}`;
}

function rangeOccupancyPath(serviceId: string, dateKey: string): string {
  return `services/${serviceId}/occupancy/${dateKey}`;
}

function pathToDoc(firestore: Firestore, path: string) {
  return firestore.doc(path);
}

function currentScheduleAnchor(booking: CanonicalBookingDocumentV3): Date | null {
  if (booking.scheduledStartAt) return booking.scheduledStartAt;
  if (booking.checkInDateTime) return booking.checkInDateTime;
  return booking.serviceAnchorAt ?? null;
}

function bookingRangeDateKeys(booking: CanonicalBookingDocumentV3): string[] {
  if (booking.bookingType !== "RANGE") return [];
  const schedule = booking.schedule as CanonicalBookingDocumentV3["schedule"] & {
    checkInDateTime: Date;
    nights: number;
  };
  const keys: string[] = [];
  const cursor = new Date(schedule.checkInDateTime.getTime());
  for (let day = 0; day < schedule.nights; day += 1) {
    keys.push(cursor.toISOString().slice(0, 10));
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  return keys;
}

function buildCancellationNotificationPlan(params: {
  bookingId: string;
  recipientUserId: string;
  type: BookingNotificationPlan["type"];
  title: string;
  body: string;
  state: string;
  bookingType: string;
  refundStatus: string;
}): BookingNotificationPlan {
  return {
    idempotencyKey: `${params.type}:${params.bookingId}:${params.recipientUserId}`,
    recipientUserId: params.recipientUserId,
    type: params.type,
    channels: ["push", "in_app"],
    title: params.title,
    body: params.body,
    data: {
      bookingId: params.bookingId,
      bookingType: params.bookingType,
      state: params.state,
      refundStatus: params.refundStatus,
    },
  };
}

function calculateCustomerCancellationAllocation(params: {
  basePaise: number;
  customerRefundBasisPoints: number;
  providerShareBasisPoints: number;
}) {
  const grossCustomerRefundPaise = Math.min(
    calculateRefundAmountFromCustomerPaid({
      customerPaidPaise: params.basePaise,
      refundBasisPoints: params.customerRefundBasisPoints,
    }),
    params.basePaise,
  );
  const providerCompensationPaise = Math.min(
    calculateBasisPointsAmount(
      params.basePaise,
      params.providerShareBasisPoints,
    ),
    Math.max(params.basePaise - grossCustomerRefundPaise, 0),
  );
  const pettxoRetainedPaise = Math.max(
    params.basePaise - grossCustomerRefundPaise - providerCompensationPaise,
    0,
  );
  return {
    grossCustomerRefundPaise,
    providerCompensationPaise,
    pettxoRetainedPaise,
  };
}

export function calculateCanonicalCancellationDecisionV3(params: {
  booking: CanonicalBookingDocumentV3;
  actorType: CancellationActorType;
  requestedAt: Date;
  existingRefund?: Record<string, unknown> | null;
}): CanonicalCancellationDecision {
  const financials = params.booking.financials;
  const customerPaidPaise = asInt(financials?.customerPaidPaise, 0);
  const serviceSubtotalPaise = asInt(financials?.serviceSubtotalPaise, 0);
  const couponDiscountPaise = asInt(financials?.couponDiscountPaise, 0);
  const providerPayoutPaise = asInt(financials?.providerPayoutPaise, 0);
  const commissionPaise = asInt(financials?.platformCommissionPaise, 0);
  const gatewayFeeSunkPaise = asInt(financials?.gatewayFeeSunkPaise, 0);
  const alreadyRefundedPaise = asInt(params.existingRefund?.refundAmountPaise, 0);
  assertNonNegativeInteger(customerPaidPaise, "customerPaidPaise");
  assertNonNegativeInteger(serviceSubtotalPaise, "serviceSubtotalPaise");
  assertNonNegativeInteger(couponDiscountPaise, "couponDiscountPaise");
  assertNonNegativeInteger(providerPayoutPaise, "providerPayoutPaise");
  assertNonNegativeInteger(commissionPaise, "platformCommissionPaise");
  assertNonNegativeInteger(gatewayFeeSunkPaise, "gatewayFeeSunkPaise");
  assertNonNegativeInteger(alreadyRefundedPaise, "alreadyRefundedPaise");
  const remainingRefundablePaise = Math.max(
    0,
    customerPaidPaise - alreadyRefundedPaise,
  );
  const anchor = currentScheduleAnchor(params.booking);
  const otpEnteredAt = params.booking.lifecycle.otpEnteredAt;
  const remainingMs =
    anchor == null ? Number.NaN : anchor.getTime() - params.requestedAt.getTime();

  if (params.booking.state !== "CONFIRMED") {
    return {
      allowed: false,
      outcome: "NOT_ALLOWED",
      timingBand: "AFTER_START",
      refundPercentageBasisPoints: 0,
      providerShareBasisPoints: 0,
      pettxoShareBasisPoints: 0,
      grossCustomerRefundPaise: 0,
      alreadyRefundedPaise,
      remainingRefundablePaise,
      refundableCustomerPaidPaise: 0,
      nonRefundableCustomerPaidPaise: customerPaidPaise,
      providerCompensationPaise: 0,
      providerEarningReversalPaise: 0,
      PettxoCouponCostPaise: couponDiscountPaise,
      commissionReversalPaise: 0,
      gatewayFeeSunkPaise,
      providerFaultCostPaise: 0,
      customerPaidPaise,
      serviceSubtotalPaise,
      couponDiscountPaise,
      retainedCustomerAmountPaise: customerPaidPaise,
      capacityReleaseRequired: false,
      financialReversalRequired: false,
      finalBookingState: params.booking.state,
      reasonCode: "INVALID_BOOKING_STATE",
      actorType: params.actorType,
      policyVersion: CANCELLATION_POLICY_VERSION,
    };
  }

  if (!(anchor instanceof Date) || Number.isNaN(anchor.getTime())) {
    return {
      allowed: false,
      outcome: "NOT_ALLOWED",
      timingBand: "AFTER_START",
      refundPercentageBasisPoints: 0,
      providerShareBasisPoints: 0,
      pettxoShareBasisPoints: 0,
      grossCustomerRefundPaise: 0,
      alreadyRefundedPaise,
      remainingRefundablePaise,
      refundableCustomerPaidPaise: 0,
      nonRefundableCustomerPaidPaise: customerPaidPaise,
      providerCompensationPaise: 0,
      providerEarningReversalPaise: 0,
      PettxoCouponCostPaise: couponDiscountPaise,
      commissionReversalPaise: 0,
      gatewayFeeSunkPaise,
      providerFaultCostPaise: 0,
      customerPaidPaise,
      serviceSubtotalPaise,
      couponDiscountPaise,
      retainedCustomerAmountPaise: customerPaidPaise,
      capacityReleaseRequired: false,
      financialReversalRequired: false,
      finalBookingState: params.booking.state,
      reasonCode: "MISSING_SERVICE_ANCHOR",
      actorType: params.actorType,
      policyVersion: CANCELLATION_POLICY_VERSION,
    };
  }

  if (params.actorType === "PROVIDER") {
    const grossCustomerRefundPaise = remainingRefundablePaise;
    return {
      allowed: true,
      outcome: remainingRefundablePaise > 0 ? "FULL_REFUND" : "NO_REFUND",
      timingBand: "PROVIDER_CANCELLATION",
      refundPercentageBasisPoints: 10000,
      providerShareBasisPoints: 0,
      pettxoShareBasisPoints: 0,
      grossCustomerRefundPaise,
      alreadyRefundedPaise,
      remainingRefundablePaise,
      refundableCustomerPaidPaise: grossCustomerRefundPaise,
      nonRefundableCustomerPaidPaise:
        Math.max(customerPaidPaise - grossCustomerRefundPaise, 0),
      providerCompensationPaise: 0,
      providerEarningReversalPaise: providerPayoutPaise,
      PettxoCouponCostPaise: couponDiscountPaise,
      commissionReversalPaise: commissionPaise,
      gatewayFeeSunkPaise,
      providerFaultCostPaise: gatewayFeeSunkPaise,
      customerPaidPaise,
      serviceSubtotalPaise,
      couponDiscountPaise,
      retainedCustomerAmountPaise: 0,
      capacityReleaseRequired: true,
      financialReversalRequired: true,
      finalBookingState: "CANCELLED",
      reasonCode: "PROVIDER_CANCELLATION",
      actorType: params.actorType,
      policyVersion: CANCELLATION_POLICY_VERSION,
    };
  }

  if (otpEnteredAt != null) {
    const allocation = calculateCustomerCancellationAllocation({
      basePaise: remainingRefundablePaise,
      customerRefundBasisPoints: 0,
      providerShareBasisPoints: 8500,
    });
    return {
      allowed: false,
      outcome: "NOT_ALLOWED",
      timingBand: "AFTER_OTP_ENTRY",
      refundPercentageBasisPoints: 0,
      providerShareBasisPoints: 8500,
      pettxoShareBasisPoints: 1500,
      grossCustomerRefundPaise: allocation.grossCustomerRefundPaise,
      alreadyRefundedPaise,
      remainingRefundablePaise,
      refundableCustomerPaidPaise: remainingRefundablePaise,
      nonRefundableCustomerPaidPaise:
        Math.max(remainingRefundablePaise - allocation.grossCustomerRefundPaise, 0),
      providerCompensationPaise: allocation.providerCompensationPaise,
      providerEarningReversalPaise:
        Math.max(providerPayoutPaise - allocation.providerCompensationPaise, 0),
      PettxoCouponCostPaise: couponDiscountPaise,
      commissionReversalPaise:
        Math.max(commissionPaise - allocation.pettxoRetainedPaise, 0),
      gatewayFeeSunkPaise,
      providerFaultCostPaise: 0,
      customerPaidPaise,
      serviceSubtotalPaise,
      couponDiscountPaise,
      retainedCustomerAmountPaise: allocation.pettxoRetainedPaise,
      capacityReleaseRequired: false,
      financialReversalRequired: false,
      finalBookingState: params.booking.state,
      reasonCode: "OTP_ALREADY_ENTERED",
      actorType: params.actorType,
      policyVersion: CANCELLATION_POLICY_VERSION,
    };
  }

  let timingBand: CancellationTimingBand;
  let customerRefundBasisPoints: number;
  let providerShareBasisPoints: number;
  let pettxoShareBasisPoints: number;
  let allowed = true;
  let reasonCode = "CUSTOMER_CANCELLATION";

  if (remainingMs > TWENTY_FOUR_HOURS_MS) {
    timingBand = "MORE_THAN_24_HOURS";
    customerRefundBasisPoints = 9500;
    providerShareBasisPoints = 0;
    pettxoShareBasisPoints = 500;
  } else if (remainingMs >= TWELVE_HOURS_MS) {
    timingBand = "BETWEEN_24_AND_12_HOURS";
    customerRefundBasisPoints = 7500;
    providerShareBasisPoints = 1500;
    pettxoShareBasisPoints = 1000;
  } else if (remainingMs >= SIX_HOURS_MS) {
    timingBand = "BETWEEN_12_AND_6_HOURS";
    customerRefundBasisPoints = 5000;
    providerShareBasisPoints = 3500;
    pettxoShareBasisPoints = 1500;
  } else if (remainingMs >= TWO_HOURS_MS) {
    timingBand = "BETWEEN_6_AND_2_HOURS";
    customerRefundBasisPoints = 2500;
    providerShareBasisPoints = 6000;
    pettxoShareBasisPoints = 1500;
  } else if (remainingMs >= 0) {
    timingBand = "UNDER_2_HOURS";
    customerRefundBasisPoints = 0;
    providerShareBasisPoints = 8500;
    pettxoShareBasisPoints = 1500;
  } else {
    timingBand = "AFTER_START";
    customerRefundBasisPoints = 0;
    providerShareBasisPoints = 8500;
    pettxoShareBasisPoints = 1500;
    allowed = false;
    reasonCode = "SERVICE_ALREADY_STARTED";
  }

  if (remainingMs === 0) {
    allowed = false;
    reasonCode = "SERVICE_START_REACHED";
    timingBand = "UNDER_2_HOURS";
  }

  const allocation = calculateCustomerCancellationAllocation({
    basePaise: remainingRefundablePaise,
    customerRefundBasisPoints,
    providerShareBasisPoints,
  });
  const outcome =
    allocation.grossCustomerRefundPaise >= remainingRefundablePaise &&
        remainingRefundablePaise > 0
      ? "FULL_REFUND"
      : allocation.grossCustomerRefundPaise > 0
      ? "PARTIAL_REFUND"
      : "NO_REFUND";

  return {
    allowed,
    outcome: allowed ? outcome : "NOT_ALLOWED",
    timingBand,
    refundPercentageBasisPoints: customerRefundBasisPoints,
    providerShareBasisPoints,
    pettxoShareBasisPoints,
    grossCustomerRefundPaise: allocation.grossCustomerRefundPaise,
    alreadyRefundedPaise,
    remainingRefundablePaise,
    refundableCustomerPaidPaise: remainingRefundablePaise,
    nonRefundableCustomerPaidPaise:
      Math.max(remainingRefundablePaise - allocation.grossCustomerRefundPaise, 0),
    providerCompensationPaise: allocation.providerCompensationPaise,
    providerEarningReversalPaise:
      Math.max(providerPayoutPaise - allocation.providerCompensationPaise, 0),
    PettxoCouponCostPaise: couponDiscountPaise,
    commissionReversalPaise:
      Math.max(commissionPaise - allocation.pettxoRetainedPaise, 0),
    gatewayFeeSunkPaise,
    providerFaultCostPaise: 0,
    customerPaidPaise,
    serviceSubtotalPaise,
    couponDiscountPaise,
    retainedCustomerAmountPaise: allocation.pettxoRetainedPaise,
    capacityReleaseRequired: allowed,
    financialReversalRequired: allowed,
    finalBookingState: allowed ? "CANCELLED" : params.booking.state,
    reasonCode,
    actorType: params.actorType,
    policyVersion: CANCELLATION_POLICY_VERSION,
  };
}

export function buildCanonicalCancellationPreviewV3(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  actorType: CancellationActorType;
  requestedAt: Date;
  existingRefund?: Record<string, unknown> | null;
}): CancellationPreviewResult {
  const decision = calculateCanonicalCancellationDecisionV3({
    booking: params.booking,
    actorType: params.actorType,
    requestedAt: params.requestedAt,
    existingRefund: params.existingRefund ?? null,
  });
  return {
    bookingId: params.bookingId,
    actorType: params.actorType,
    allowed: decision.allowed,
    decision,
  };
}

function buildCancellationRecord(params: {
  bookingId: string;
  actorType: CancellationActorType;
  actorId: string;
  reasonCode: string;
  reasonText: string;
  now: Date;
  decision: CanonicalCancellationDecision;
  refundStatus: string;
  capacityReleaseState: CapacityReleaseState;
  existing?: Record<string, unknown> | null;
}): CanonicalBookingCancellationRecord {
  const createdAt =
    params.existing && params.existing.createdAt instanceof Date
      ? (params.existing.createdAt as Date)
      : params.now;
  return {
    cancellationId: cancellationIdForBooking(params.bookingId),
    bookingId: params.bookingId,
    actorType: params.actorType,
    actorId: params.actorId,
    reasonCode: params.reasonCode,
    reasonText: params.reasonText,
    requestedAt: params.now,
    effectiveAt: params.now,
    policyVersion: params.decision.policyVersion,
    timingBand: params.decision.timingBand,
    refundPercentageBasisPoints:
      params.decision.refundPercentageBasisPoints,
    providerShareBasisPoints: params.decision.providerShareBasisPoints,
    pettxoShareBasisPoints: params.decision.pettxoShareBasisPoints,
    refundableCustomerPaidPaise:
      params.decision.refundableCustomerPaidPaise,
    nonRefundableCustomerPaidPaise:
      params.decision.nonRefundableCustomerPaidPaise,
    providerCompensationPaise:
      params.decision.providerCompensationPaise,
    pettxoRetainedPaise:
      params.decision.retainedCustomerAmountPaise,
    gatewayFeeSunkPaise: params.decision.gatewayFeeSunkPaise,
    providerFaultCostPaise: params.decision.providerFaultCostPaise,
    customerPaidPaise: params.decision.customerPaidPaise,
    capacityReleaseRequired: params.decision.capacityReleaseRequired,
    financialReversalRequired: params.decision.financialReversalRequired,
    refundInstructionId:
      params.decision.grossCustomerRefundPaise > 0
        ? refundInstructionIdForBooking(params.bookingId)
        : "",
    status:
      params.decision.remainingRefundablePaise > 0 ? params.refundStatus : "CANCELLED",
    createdAt,
    updatedAt: params.now,
    refundAmountPaise: params.decision.grossCustomerRefundPaise,
    refundStatus: params.refundStatus,
    capacityReleaseState: params.capacityReleaseState,
    outcome: params.decision.outcome,
  };
}

function releaseSlotOccupancy(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  existing: Record<string, SlotOccupancyDocument>;
}): Record<string, Record<string, unknown>> {
  const writes: Record<string, Record<string, unknown>> = {};
  if (params.booking.bookingType !== "SLOT") return writes;
  const schedule = params.booking.schedule as CanonicalBookingDocumentV3["schedule"] & {
    slots: Array<{slotId: string}>;
  };
  for (const slot of schedule.slots) {
    const existing = params.existing[slot.slotId];
    if (!existing) continue;
    const claim = asInt(existing.bookingClaims[params.bookingId], 0);
    if (claim <= 0) continue;
    const nextClaims = {...existing.bookingClaims};
    delete nextClaims[params.bookingId];
    writes[slotOccupancyPath(params.booking.serviceId, slot.slotId)] = {
      slotId: existing.slotId,
      confirmedUnits: Math.max(existing.confirmedUnits - claim, 0),
      capacitySnapshot: existing.capacitySnapshot,
      bookingClaims: nextClaims,
      updatedAt: FieldValue.serverTimestamp(),
      version: 1,
    };
  }
  return writes;
}

function releaseRangeOccupancy(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  existing: Record<string, RangeOccupancyDocument>;
}): Record<string, Record<string, unknown>> {
  const writes: Record<string, Record<string, unknown>> = {};
  if (params.booking.bookingType !== "RANGE") return writes;
  for (const dateKey of bookingRangeDateKeys(params.booking)) {
    const existing = params.existing[dateKey];
    if (!existing) continue;
    const claim = asInt(existing.bookingClaims[params.bookingId], 0);
    if (claim <= 0) continue;
    const nextClaims = {...existing.bookingClaims};
    delete nextClaims[params.bookingId];
    writes[rangeOccupancyPath(params.booking.serviceId, dateKey)] = {
      dateKey: existing.dateKey,
      confirmedPetUnits: Math.max(existing.confirmedPetUnits - claim, 0),
      capacitySnapshot: existing.capacitySnapshot,
      bookingClaims: nextClaims,
      updatedAt: FieldValue.serverTimestamp(),
      version: 1,
    };
  }
  return writes;
}

export function buildCapacityReleaseForCancelledBookingV3(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  existingSlotOccupancy?: Record<string, SlotOccupancyDocument>;
  existingRangeOccupancy?: Record<string, RangeOccupancyDocument>;
  existingReleaseRecord?: Record<string, unknown> | null;
  now: Date;
}): CapacityReleaseResult {
  if (
    asString(params.existingReleaseRecord?.state).toUpperCase() === "RELEASED"
  ) {
    return {
      state: "RELEASED",
      writes: {},
      marker: {
        ...params.existingReleaseRecord,
        updatedAt: Timestamp.fromDate(params.now),
      },
    };
  }

  const writes =
    params.booking.bookingType === "SLOT"
      ? releaseSlotOccupancy({
          bookingId: params.bookingId,
          booking: params.booking,
          existing: params.existingSlotOccupancy ?? {},
        })
      : releaseRangeOccupancy({
          bookingId: params.bookingId,
          booking: params.booking,
          existing: params.existingRangeOccupancy ?? {},
        });

  return {
    state: "RELEASED",
    writes,
    marker: {
      bookingId: params.bookingId,
      bookingType: params.booking.bookingType,
      state: "RELEASED",
      releasedPaths: Object.keys(writes),
      createdAt:
        params.existingReleaseRecord?.createdAt ?? Timestamp.fromDate(params.now),
      updatedAt: Timestamp.fromDate(params.now),
      schemaVersion: 1,
    },
  };
}

function buildCancellationRefundInstruction(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  paymentAttempt: CanonicalPaymentAttemptDocumentV3;
  refundAmountPaise: number;
  reasonCode: string;
  now: Date;
}): Record<string, unknown> {
  return {
    bookingId: params.bookingId,
    paymentAttemptId: params.paymentAttempt.paymentAttemptId,
    userId: params.booking.parentId,
    providerId: params.booking.providerId,
    razorpayPaymentId: params.paymentAttempt.razorpayPaymentId,
    refundAmountPaise: params.refundAmountPaise,
    reasonCode: params.reasonCode,
    refundInstructionId: refundInstructionIdForBooking(params.bookingId),
    state: "required",
    createdAt: Timestamp.fromDate(params.now),
    submittedAt: null,
    confirmedAt: null,
    razorpayRefundId: "",
    attemptCount: 0,
    lastErrorCode: "",
    schemaVersion: 3,
    bookingModelVersion: params.booking.bookingModelVersion,
    updatedAt: Timestamp.fromDate(params.now),
  };
}

function buildFinancialAdjustment(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  actorType: CancellationActorType;
  decision: CanonicalCancellationDecision;
  now: Date;
}): Record<string, unknown> {
  const financials = params.booking.financials;
  return {
    bookingId: params.bookingId,
    providerId: params.booking.providerId,
    userId: params.booking.parentId,
    actorType: params.actorType,
    timingBand: params.decision.timingBand,
    policyVersion: params.decision.policyVersion,
    customerRefundBasisPoints: params.decision.refundPercentageBasisPoints,
    providerShareBasisPoints: params.decision.providerShareBasisPoints,
    pettxoShareBasisPoints: params.decision.pettxoShareBasisPoints,
    originalCustomerPaidPaise: financials?.customerPaidPaise ?? 0,
    refundPaise: params.decision.grossCustomerRefundPaise,
    providerCompensationPaise: params.decision.providerCompensationPaise,
    pettxoRetainedPaise: params.decision.retainedCustomerAmountPaise,
    retainedCustomerAmountPaise: params.decision.retainedCustomerAmountPaise,
    originalProviderEarningPaise: financials?.providerPayoutPaise ?? 0,
    reversedProviderEarningPaise:
      params.decision.providerEarningReversalPaise,
    originalCommissionPaise: financials?.platformCommissionPaise ?? 0,
    reversedCommissionPaise: params.decision.commissionReversalPaise,
    PettxoCouponCostPaise: params.decision.PettxoCouponCostPaise,
    gatewayFeeSunkPaise: params.decision.gatewayFeeSunkPaise,
    providerFaultCostPaise: params.decision.providerFaultCostPaise,
    createdAt: Timestamp.fromDate(params.now),
    updatedAt: Timestamp.fromDate(params.now),
    schemaVersion: 1,
  };
}

function buildCancellationAwareBooking(params: {
  booking: CanonicalBookingDocumentV3;
  actorType: CancellationActorType;
  now: Date;
  decision: CanonicalCancellationDecision;
  reasonCode: string;
  reasonText: string;
  refundId?: string;
}): CanonicalBookingDocumentV3 {
  const next = cloneBooking(params.booking);
  next.state = "CANCELLED";
  next.stateQueryValue = "CANCELLED";
  next.lifecycle.cancelledAt = new Date(params.now.getTime());
  next.updatedAt = new Date(params.now.getTime());
  next.completedAt = null;
  next.audit.lastUpdatedBy =
    params.actorType === "CUSTOMER"
      ? "parent"
      : params.actorType === "PROVIDER"
      ? "provider"
      : "admin";
  next.cancellation = {
    ...next.cancellation,
    cancelledAt: new Date(params.now.getTime()),
    cancelledBy:
      params.actorType === "CUSTOMER"
        ? "parent"
        : params.actorType === "PROVIDER"
        ? "provider"
        : "admin",
    cancelReasonCode: params.reasonCode,
    cancelReasonText: params.reasonText,
    hoursBeforeServiceAtCancel: (() => {
      const anchor = currentScheduleAnchor(params.booking);
      if (!anchor) return null;
      return Math.max(
        Math.floor(
          (anchor.getTime() - params.now.getTime()) / (60 * 60 * 1000),
        ),
        0,
      );
    })(),
    refundBand: params.decision.timingBand.toLowerCase(),
    refundBasisPoints: params.decision.refundPercentageBasisPoints,
    refundAmountPaise: params.decision.grossCustomerRefundPaise,
    providerCompensationPaise: params.decision.providerCompensationPaise,
    pettxoRetainedPaise: params.decision.retainedCustomerAmountPaise,
    cancellationType:
      params.actorType === "CUSTOMER"
        ? "parent_requested"
        : "provider_requested",
  };
  next.payment = {
    ...next.payment,
    status:
      params.decision.grossCustomerRefundPaise > 0 ? "refund_pending" : "cancelled",
    razorpayRefundId: params.refundId ?? next.payment.razorpayRefundId,
  };
  next.privacy = {
    ...next.privacy,
    isPaidContactUnlocked: false,
    contactUnlockedAt: null,
    chatUnlockedAt: null,
    otpVisibleToParent: false,
    exactAddressUnlocked: false,
  };
  if (next.financials) {
    next.financials = {
      ...next.financials,
      refundAmountPaise: params.decision.grossCustomerRefundPaise,
    };
  }
  next.payout = {
    ...next.payout,
    status: "cancelled",
    eligibleAt: null,
    releasedAt: null,
    failureCode: "BOOKING_CANCELLED",
  };
  return next;
}

function buildCancellationAwareAttempt(params: {
  attempt: CanonicalPaymentAttemptDocumentV3;
  decision: CanonicalCancellationDecision;
  now: Date;
  actorType: CancellationActorType;
}): CanonicalPaymentAttemptDocumentV3 {
  const next = cloneAttempt(params.attempt);
  next.updatedAt = new Date(params.now.getTime());
  next.verificationSource =
    params.actorType === "CUSTOMER" ? "callable" : "callable";
  if (params.decision.grossCustomerRefundPaise > 0) {
    next.state = "REFUND_REQUIRED";
    next.refundRequiredAt = new Date(params.now.getTime());
    next.lastReconciliationCode = "CANCELLATION_REFUND_REQUIRED";
  }
  return next;
}

export async function loadCapacityStateForCancellationV3(params: {
  firestore: Firestore;
  transaction: Transaction;
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
}): Promise<{
  slotOccupancy: Record<string, SlotOccupancyDocument>;
  rangeOccupancy: Record<string, RangeOccupancyDocument>;
  existingReleaseRecord: Record<string, unknown> | null;
}> {
  const slotOccupancy: Record<string, SlotOccupancyDocument> = {};
  const rangeOccupancy: Record<string, RangeOccupancyDocument> = {};
  if (params.booking.bookingType === "SLOT") {
    const schedule = params.booking.schedule as CanonicalBookingDocumentV3["schedule"] & {
      slots: Array<{slotId: string}>;
    };
    for (const slot of schedule.slots) {
      const snapshot = await params.transaction.get(
        params.firestore.doc(
          slotOccupancyPath(params.booking.serviceId, slot.slotId),
        ),
      );
      if (!snapshot.exists) continue;
      const data = snapshot.data() ?? {};
      slotOccupancy[slot.slotId] = {
        slotId: asString(data.slotId) || slot.slotId,
        confirmedUnits: asInt(data.confirmedUnits, 0),
        capacitySnapshot: asInt(
          data.capacitySnapshot,
          params.booking.service.capacitySnapshot,
        ),
        bookingClaims: data.bookingClaims as Record<string, number>,
      };
    }
  } else {
    for (const dateKey of bookingRangeDateKeys(params.booking)) {
      const snapshot = await params.transaction.get(
        params.firestore.doc(rangeOccupancyPath(params.booking.serviceId, dateKey)),
      );
      if (!snapshot.exists) continue;
      const data = snapshot.data() ?? {};
      rangeOccupancy[dateKey] = {
        dateKey,
        confirmedPetUnits: asInt(data.confirmedPetUnits, 0),
        capacitySnapshot: asInt(
          data.capacitySnapshot,
          params.booking.service.capacitySnapshot,
        ),
        bookingClaims: data.bookingClaims as Record<string, number>,
      };
    }
  }
  const releaseSnapshot = await params.transaction.get(
    params.firestore
      .collection(CAPACITY_RELEASES_COLLECTION)
      .doc(params.bookingId),
  );
  return {
    slotOccupancy,
    rangeOccupancy,
    existingReleaseRecord: releaseSnapshot.exists
      ? (releaseSnapshot.data() as Record<string, unknown>)
      : null,
  };
}

export function applyConfirmedBookingCancellationV3(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  paymentAttempt: CanonicalPaymentAttemptDocumentV3;
  actorType: CancellationActorType;
  actorId: string;
  reasonCode: string;
  reasonText?: string;
  authoritativeNow: Date;
  existingRefund?: Record<string, unknown> | null;
  existingCancellation?: Record<string, unknown> | null;
  existingReleaseRecord?: Record<string, unknown> | null;
  existingSlotOccupancy?: Record<string, SlotOccupancyDocument>;
  existingRangeOccupancy?: Record<string, RangeOccupancyDocument>;
  existingBookingPrivate?: Record<string, unknown> | null;
  existingBookingChat?: Record<string, unknown> | null;
}): ApplyConfirmedBookingCancellationResult {
  if (
    params.booking.state === "CANCELLED" &&
    params.existingCancellation
  ) {
    const existingRecord =
      params.existingCancellation as unknown as CanonicalBookingCancellationRecord;
    return {
      booking: cloneBooking(params.booking),
      paymentAttempt: cloneAttempt(params.paymentAttempt),
      cancellationRecord: existingRecord,
      financialAdjustment: {},
      capacityRelease: buildCapacityReleaseForCancelledBookingV3({
        bookingId: params.bookingId,
        booking: params.booking,
        existingSlotOccupancy: params.existingSlotOccupancy,
        existingRangeOccupancy: params.existingRangeOccupancy,
        existingReleaseRecord: params.existingReleaseRecord,
        now: params.authoritativeNow,
      }),
      refundInstruction: null,
      notifications: [],
      events: [],
      bookingPrivateWrite: null,
      bookingChatWrite: null,
      paymentWrite: {},
      invoiceWrite: {},
      bookingFinancialWrite: {},
      providerEarningWrite: {},
      payoutReadinessWrite: {},
      idempotentReplay: true,
    };
  }

  const decision = calculateCanonicalCancellationDecisionV3({
    booking: params.booking,
    actorType: params.actorType,
    requestedAt: params.authoritativeNow,
    existingRefund: params.existingRefund ?? null,
  });
  if (!decision.allowed) {
    throw new HttpsError(
      "failed-precondition",
      decision.reasonCode === "OTP_ALREADY_ENTERED"
        ? "This booking can no longer be cancelled after OTP verification."
        : decision.reasonCode === "SERVICE_START_REACHED" ||
            decision.reasonCode === "SERVICE_ALREADY_STARTED"
        ? "This booking can no longer be cancelled after the service start time."
        : "This booking cannot be cancelled in the current state.",
      {code: decision.reasonCode},
    );
  }

  const nextBooking = buildCancellationAwareBooking({
    booking: params.booking,
    actorType: params.actorType,
    now: params.authoritativeNow,
    decision,
    reasonCode: params.reasonCode || decision.reasonCode,
    reasonText: asString(params.reasonText),
  });
  const nextAttempt = buildCancellationAwareAttempt({
    attempt: params.paymentAttempt,
    decision,
    now: params.authoritativeNow,
    actorType: params.actorType,
  });
  const capacityRelease = buildCapacityReleaseForCancelledBookingV3({
    bookingId: params.bookingId,
    booking: params.booking,
    existingSlotOccupancy: params.existingSlotOccupancy,
    existingRangeOccupancy: params.existingRangeOccupancy,
    existingReleaseRecord: params.existingReleaseRecord,
    now: params.authoritativeNow,
  });
  const refundInstruction =
    decision.grossCustomerRefundPaise > 0
      ? buildCancellationRefundInstruction({
          bookingId: params.bookingId,
          booking: nextBooking,
          paymentAttempt: nextAttempt,
          refundAmountPaise: decision.grossCustomerRefundPaise,
          reasonCode: decision.reasonCode,
          now: params.authoritativeNow,
        })
      : null;
  const cancellationRecord = buildCancellationRecord({
    bookingId: params.bookingId,
    actorType: params.actorType,
    actorId: params.actorId,
    reasonCode: params.reasonCode || decision.reasonCode,
    reasonText: asString(params.reasonText),
    now: params.authoritativeNow,
    decision,
    refundStatus:
      decision.grossCustomerRefundPaise > 0 ? "REFUND_REQUIRED" : "NO_REFUND",
    capacityReleaseState: capacityRelease.state,
    existing: params.existingCancellation ?? null,
  });

  const financialAdjustment = buildFinancialAdjustment({
    bookingId: params.bookingId,
    booking: params.booking,
    actorType: params.actorType,
    decision,
    now: params.authoritativeNow,
  });

  const actorLabel =
    params.actorType === "CUSTOMER" ? "customer" : "provider";
  const safeState = nextBooking.state;
  const notifications: BookingNotificationPlan[] = [
    buildCancellationNotificationPlan({
      bookingId: params.bookingId,
      recipientUserId: params.booking.parentId,
      type:
        params.actorType === "PROVIDER"
          ? "booking_cancelled_by_provider"
          : "booking_cancelled_by_customer",
      title:
        params.actorType === "PROVIDER"
          ? "Provider cancelled your booking"
          : "Booking cancelled",
      body:
        params.actorType === "PROVIDER"
          ? "Your booking was cancelled by the provider. Refund processing is underway."
          : decision.grossCustomerRefundPaise > 0
          ? "Your booking cancellation has been recorded. Refund processing is underway."
          : "Your booking cancellation has been recorded. No gateway refund applies for this time band.",
      state: safeState,
      bookingType: params.booking.bookingType,
      refundStatus: cancellationRecord.refundStatus,
    }),
    buildCancellationNotificationPlan({
      bookingId: params.bookingId,
      recipientUserId: params.booking.providerId,
      type:
        params.actorType === "PROVIDER"
          ? "booking_cancellation_acknowledged"
          : "booking_cancelled_by_customer",
      title:
        params.actorType === "PROVIDER"
          ? "Booking cancellation recorded"
          : "Customer cancelled the booking",
      body:
        params.actorType === "PROVIDER"
          ? "This booking is cancelled and payout eligibility has been removed."
          : "The customer cancelled this paid booking. Capacity and payout eligibility were reversed.",
      state: safeState,
      bookingType: params.booking.bookingType,
      refundStatus: cancellationRecord.refundStatus,
    }),
  ];

  const events: BookingEventWritePlan[] = [
    buildBookingEventPlan({
      bookingId: params.bookingId,
      event: "cancelled",
      actor:
        params.actorType === "CUSTOMER"
          ? "parent"
          : params.actorType === "PROVIDER"
          ? "provider"
          : "admin",
      at: params.authoritativeNow,
        meta: {
          reasonCode: decision.reasonCode,
          timingBand: decision.timingBand,
          outcome: decision.outcome,
          refundAmountPaise: decision.grossCustomerRefundPaise,
          providerCompensationPaise: decision.providerCompensationPaise,
          pettxoRetainedPaise: decision.retainedCustomerAmountPaise,
          cancelledBy: actorLabel,
        },
      }),
  ];
  if (capacityRelease.state === "RELEASED") {
    events.push(
      buildBookingEventPlan({
        bookingId: params.bookingId,
        event: "capacity_released",
        actor:
          params.actorType === "CUSTOMER"
            ? "parent"
            : params.actorType === "PROVIDER"
            ? "provider"
            : "admin",
        at: params.authoritativeNow,
        meta: {
          releasedPaths: capacityRelease.marker.releasedPaths ?? [],
        },
      }),
    );
  }
  if (decision.grossCustomerRefundPaise > 0) {
    events.push(
      buildBookingEventPlan({
        bookingId: params.bookingId,
        event: "refund_required",
        actor:
          params.actorType === "CUSTOMER"
            ? "parent"
            : params.actorType === "PROVIDER"
            ? "provider"
            : "admin",
        at: params.authoritativeNow,
        meta: {
          refundAmountPaise: decision.grossCustomerRefundPaise,
          reasonCode: decision.reasonCode,
        },
      }),
    );
  }

  const bookingPrivateWrite =
    params.existingBookingPrivate != null
      ? {
          ...params.existingBookingPrivate,
          parentOtpCode: "",
          providerOtpHash: "",
          contactUnlockedAt: params.existingBookingPrivate.contactUnlockedAt ?? null,
          accessRevokedAt: Timestamp.fromDate(params.authoritativeNow),
          accessRevokedReason: decision.reasonCode,
          updatedAt: Timestamp.fromDate(params.authoritativeNow),
        }
      : null;
  const bookingChatWrite =
    params.existingBookingChat != null
      ? {
          ...params.existingBookingChat,
          accessStatus: "cancelled_read_only",
          accessRevokedAt: Timestamp.fromDate(params.authoritativeNow),
          updatedAt: Timestamp.fromDate(params.authoritativeNow),
        }
      : null;

  return {
    booking: nextBooking,
    paymentAttempt: nextAttempt,
    cancellationRecord,
    financialAdjustment,
    capacityRelease,
    refundInstruction,
    notifications,
    events,
    bookingPrivateWrite,
    bookingChatWrite,
    paymentWrite: {
      bookingId: params.bookingId,
      cancellationStatus: "cancelled",
      refundStatus: cancellationRecord.refundStatus,
      refundAmountPaise: decision.grossCustomerRefundPaise,
      providerCompensationPaise: decision.providerCompensationPaise,
      pettxoRetainedPaise: decision.retainedCustomerAmountPaise,
      cancellationActorType: params.actorType,
      updatedAt: FieldValue.serverTimestamp(),
    },
    invoiceWrite: {
      bookingId: params.bookingId,
      cancellationStatus: "cancelled",
      refundStatus: cancellationRecord.refundStatus,
      refundAmountPaise: decision.grossCustomerRefundPaise,
      providerCompensationPaise: decision.providerCompensationPaise,
      pettxoRetainedPaise: decision.retainedCustomerAmountPaise,
      updatedAt: FieldValue.serverTimestamp(),
    },
    bookingFinancialWrite: {
      bookingId: params.bookingId,
      status: "cancelled",
      paymentStatus:
        decision.grossCustomerRefundPaise > 0 ? "refund_pending" : "cancelled",
      refundAmountPaise: decision.grossCustomerRefundPaise,
      providerCompensationPaise: decision.providerCompensationPaise,
      pettxoRetainedPaise: decision.retainedCustomerAmountPaise,
      cancellationActorType: params.actorType,
      updatedAt: FieldValue.serverTimestamp(),
    },
    providerEarningWrite: {
      bookingId: params.bookingId,
      providerId: params.booking.providerId,
      status: "cancelled",
      eligibleForPayout: false,
      compensationAmountPaise: decision.providerCompensationPaise,
      reversedAmountPaise: decision.providerEarningReversalPaise,
      updatedAt: FieldValue.serverTimestamp(),
    },
    payoutReadinessWrite: {
      bookingId: params.bookingId,
      providerId: params.booking.providerId,
      customerId: params.booking.parentId,
      status: "cancelled",
      eligibleAt: null,
      providerPayoutPaise: decision.providerCompensationPaise,
      updatedAt: FieldValue.serverTimestamp(),
    },
    idempotentReplay: false,
  };
}

export function writeConfirmedBookingCancellationTransactionV3(params: {
  firestore: Firestore;
  transaction: Transaction;
  bookingId: string;
  result: ApplyConfirmedBookingCancellationResult;
}): void {
  const bookingRef = params.firestore.collection("bookings").doc(params.bookingId);
  params.transaction.set(bookingRef, structuredClone(params.result.booking), {merge: false});
  params.transaction.set(
    bookingRef
      .collection("paymentAttempts")
      .doc(params.result.paymentAttempt.paymentAttemptId),
    structuredClone(params.result.paymentAttempt),
    {merge: true},
  );
  params.transaction.set(
    params.firestore
      .collection(BOOKING_CANCELLATION_COLLECTION)
      .doc(params.bookingId),
    structuredClone(params.result.cancellationRecord),
    {merge: true},
  );
  params.transaction.set(
    params.firestore
      .collection(BOOKING_FINANCIAL_ADJUSTMENTS_COLLECTION)
      .doc(params.bookingId),
    params.result.financialAdjustment,
    {merge: true},
  );
  params.transaction.set(
    params.firestore.collection(CAPACITY_RELEASES_COLLECTION).doc(params.bookingId),
    params.result.capacityRelease.marker,
    {merge: true},
  );
  for (const [path, data] of Object.entries(params.result.capacityRelease.writes)) {
    params.transaction.set(pathToDoc(params.firestore, path), data, {merge: true});
  }
  if (params.result.refundInstruction) {
    params.transaction.set(
      params.firestore.collection("refunds").doc(params.bookingId),
      params.result.refundInstruction,
      {merge: true},
    );
  }
  if (params.result.bookingPrivateWrite) {
    params.transaction.set(
      params.firestore.collection("bookingPrivate").doc(params.bookingId),
      params.result.bookingPrivateWrite,
      {merge: true},
    );
  }
  if (params.result.bookingChatWrite) {
    params.transaction.set(
      params.firestore.collection("bookingChats").doc(params.bookingId),
      params.result.bookingChatWrite,
      {merge: true},
    );
    params.transaction.set(
      params.firestore.collection("chats").doc(params.bookingId),
      params.result.bookingChatWrite,
      {merge: true},
    );
  }
  params.transaction.set(
    params.firestore.collection("payments").doc(params.bookingId),
    params.result.paymentWrite,
    {merge: true},
  );
  params.transaction.set(
    params.firestore.collection("invoices").doc(params.bookingId),
    params.result.invoiceWrite,
    {merge: true},
  );
  params.transaction.set(
    params.firestore.collection("bookingFinancials").doc(params.bookingId),
    params.result.bookingFinancialWrite,
    {merge: true},
  );
  params.transaction.set(
    params.firestore.collection("providerEarnings").doc(params.bookingId),
    params.result.providerEarningWrite,
    {merge: true},
  );
  params.transaction.set(
    params.firestore.collection("payoutReadiness").doc(params.bookingId),
    params.result.payoutReadinessWrite,
    {merge: true},
  );
  for (const event of params.result.events) {
    params.transaction.set(
      bookingRef.collection("events").doc(event.eventId),
      {
        bookingId: event.record.bookingId,
        event: event.record.event,
        actor: event.record.actor,
        at: Timestamp.fromDate(event.record.at),
        meta: event.record.meta,
        schemaVersion: event.record.schemaVersion,
      },
      {merge: true},
    );
  }
  for (const notification of params.result.notifications) {
    params.transaction.set(
      params.firestore.collection("notifications").doc(notification.idempotencyKey),
      buildStoredBookingNotificationDocument({
        notification,
        actorId: params.result.cancellationRecord.actorId,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        source: "canonical_v3",
      }),
      {merge: true},
    );
  }
}

export async function persistConfirmedBookingCancellationV3(params: {
  firestore: Firestore;
  bookingId: string;
  result: ApplyConfirmedBookingCancellationResult;
}): Promise<void> {
  await params.firestore.runTransaction(async (transaction) => {
    writeConfirmedBookingCancellationTransactionV3({
      firestore: params.firestore,
      transaction,
      bookingId: params.bookingId,
      result: params.result,
    });
  });
}
