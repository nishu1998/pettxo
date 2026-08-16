import type {CanonicalBookingState, BookingType, BookingCancellationActor, BookingCancellationType, BookingActor, ProviderResponseType} from "../domain/bookingContracts";
import {isCanonicalBookingState, isBookingActor, isBookingType} from "../domain/bookingContracts";
import type {BookingFinancialSnapshot, BookingServiceSnapshot} from "../domain/bookingSnapshots";
import {isBookingFinancialSnapshot, isBookingServiceSnapshot} from "../domain/bookingSnapshots";
import type {RangeBookingSelection, RangeBookingValidationIssue} from "../domain/rangeBooking";
import {validateRangeBookingSelection} from "../domain/rangeBooking";
import type {SlotBookingSelection, SlotBookingValidationIssue} from "../domain/slotBooking";
import {validateSlotBookingSelection} from "../domain/slotBooking";
import {normalizeTimestampLike} from "./timestampNormalization";

export const CANONICAL_BOOKING_SCHEMA_VERSION = 3;
export const CANONICAL_BOOKING_MODEL_VERSION = "3.2";
export const CANONICAL_BOOKING_DOCUMENT_FORMAT = "canonical_v3";
export const CANONICAL_BOOKING_PRIVATE_DOCUMENT_FORMAT = "canonical_v3_private";
export const BOOKING_PRIVACY_VERSION = 1;

export type PublicParentParticipantSnapshot = {
  parentId: string;
  displayFirstName: string;
  lastInitial: string;
  photoUrl: string;
  completedBookingCount: number;
  rating: number;
};

export type PublicProviderParticipantSnapshot = {
  providerId: string;
  displayName: string;
  username: string;
  photoUrl: string;
  completedBookingCount: number;
  rating: number;
};

export type CanonicalParticipantsV3 = {
  parent: PublicParentParticipantSnapshot;
  provider: PublicProviderParticipantSnapshot;
};

export type CanonicalSlotScheduleV3 = {
  bookingType: "SLOT";
  slots: Array<{
    slotId: string;
    dateKey: string;
    serviceDateKey?: string;
    startAt: Date;
    endAt: Date;
    durationMinutes: number;
    unitPricePaise: number;
    serviceId: string;
    providerId: string;
    timezone: string;
    schedulingMode?: string;
  }>;
  segments?: Array<{
    serviceDateKey: string;
    slotIds: string[];
    startAt: Date;
    endAt: Date;
    durationMinutes: number;
    schedulingMode: string;
  }>;
  slotCount: number;
  scheduledStartAt: Date;
  scheduledEndAt: Date;
  totalDurationMinutes: number;
  firstSegmentEndAt?: Date;
  finalEndAt?: Date;
  serviceDayCount?: number;
  segmentCount?: number;
  timezone: string;
};

export type CanonicalRangeScheduleV3 = {
  bookingType: "RANGE";
  checkInDateTime: Date;
  checkOutDateTime: Date;
  nights: number;
  timezone: string;
  minNightsSnapshot: number | null;
  maxNightsSnapshot: number | null;
  maxConcurrentPetsSnapshot: number | null;
  petQuantity: number | null;
};

export type CanonicalScheduleV3 = (CanonicalSlotScheduleV3 | CanonicalRangeScheduleV3) & {
  serviceAnchorAt: Date;
};

export type CanonicalLifecycleV3 = {
  requestedAt: Date | null;
  timerStartsAt: Date | null;
  wasQueuedOutsideWorkingHours: boolean;
  notifiedAt: Date | null;
  acceptDeadlineAt: Date | null;
  viewedByProviderAt: Date | null;
  respondedAt: Date | null;
  providerResponseType: ProviderResponseType | null;
  responseSeconds: number | null;
  payDeadlineAt: Date | null;
  paymentStartedAt: Date | null;
  paidAt: Date | null;
  paymentSeconds: number | null;
  otpGeneratedAt: Date | null;
  otpEnteredAt: Date | null;
  noShowAt: Date | null;
  serviceEndedAt: Date | null;
  disputeDeadlineAt: Date | null;
  completedAt: Date | null;
  reviewWindowEndsAt: Date | null;
  finalizedAt: Date | null;
  cancelledAt: Date | null;
};

export type CanonicalPaymentMetadataV3 = {
  status: string;
  razorpayOrderId: string;
  razorpayPaymentId: string;
  razorpayRefundId: string;
  paymentAttemptId: string;
  orderCreatedAt: Date | null;
  paymentStartedAt: Date | null;
  capturedAt: Date | null;
  verifiedAt: Date | null;
  verificationSource: string;
  webhookEventIds: string[];
  failureCode: string;
  failureMessage: string;
};

export type CanonicalPrivacyV3 = {
  isPaidContactUnlocked: boolean;
  contactUnlockedAt: Date | null;
  chatUnlockedAt: Date | null;
  otpVisibleToParent: boolean;
  exactAddressUnlocked: boolean;
  privacyVersion: number;
  privateParticipantsRefPath: string;
};

export type CanonicalCancellationV3 = {
  cancelledAt: Date | null;
  cancelledBy: BookingCancellationActor | null;
  cancelReasonCode: string;
  cancelReasonText: string;
  hoursBeforeServiceAtCancel: number | null;
  refundBand: string;
  refundBasisPoints: number | null;
  refundAmountPaise: number;
  providerCompensationPaise: number;
  pettxoRetainedPaise: number;
  cancellationType: BookingCancellationType | null;
};

export type CanonicalDisputeV3 = {
  disputeId: string;
  status: string;
  raisedAt: Date | null;
  raisedBy: BookingActor | null;
  reasonCode: string;
  description: string;
  evidenceRefs: string[];
  resolvedAt: Date | null;
  resolvedBy: BookingActor | null;
  resolution: string;
  resolutionVersion: number;
  financialAdjustmentId: string;
  refundInstructionId: string;
  customerRefundPaise: number;
  providerReleasePaise: number;
};

export type CanonicalPayoutV3 = {
  status: string;
  holdReason: string;
  eligibleAt: Date | null;
  readyAt: Date | null;
  processingAt: Date | null;
  releasedAt: Date | null;
  failedAt: Date | null;
  providerPayoutPaise: number;
  priorPaidPaise: number;
  remainingPayablePaise: number;
  payoutReference: string;
  externalTransactionId: string;
  failureCode: string;
  retryCount: number;
};

export type CanonicalStatisticsV3 = {
  selectedSlotCount: number | null;
  totalDurationMinutes: number | null;
  nights: number | null;
};

export type CanonicalAuditV3 = {
  createdBy: BookingActor;
  lastUpdatedBy: BookingActor;
  source: string;
};

export type CanonicalBookingDocumentV3 = {
  schemaVersion: 3;
  bookingModelVersion: "3.2";
  documentFormat: "canonical_v3";
  bookingType: BookingType;
  state: CanonicalBookingState;
  participants: CanonicalParticipantsV3;
  service: BookingServiceSnapshot;
  schedule: CanonicalScheduleV3;
  lifecycle: CanonicalLifecycleV3;
  payment: CanonicalPaymentMetadataV3;
  financials: BookingFinancialSnapshot | null;
  privacy: CanonicalPrivacyV3;
  cancellation: CanonicalCancellationV3;
  dispute: CanonicalDisputeV3;
  payout: CanonicalPayoutV3;
  statistics: CanonicalStatisticsV3;
  audit: CanonicalAuditV3;
  parentId: string;
  providerId: string;
  serviceId: string;
  bookingIdSearchKey?: string;
  stateQueryValue: CanonicalBookingState;
  bookingTypeQueryValue: BookingType;
  serviceAnchorAt: Date;
  scheduledStartAt: Date | null;
  checkInDateTime: Date | null;
  acceptDeadlineAt: Date | null;
  payDeadlineAt: Date | null;
  completedAt: Date | null;
  customerId: string;
  serviceOwnerId: string;
  createdAt: Date;
  updatedAt: Date;
};

export type BookingPrivateParticipantsDocumentV3 = {
  schemaVersion: 3;
  bookingModelVersion: "3.2";
  documentFormat: "canonical_v3_private";
  bookingId: string;
  parentId: string;
  providerId: string;
  unlockedAfterPaidOnly: true;
  parentPrivate: {
    fullName: string;
    phoneNumber: string;
    email: string;
    exactAddress: string;
    latitude: number | null;
    longitude: number | null;
  };
  providerPrivate?: {
    phoneNumber: string;
  };
  createdAt: Date;
  updatedAt: Date;
};

export type CanonicalBookingValidationIssue = {
  code: string;
  message: string;
  path: string;
};

export type CanonicalBookingValidationResult =
  | {
      ok: true;
      booking: CanonicalBookingDocumentV3;
      issues: [];
    }
  | {
      ok: false;
      booking: null;
      issues: CanonicalBookingValidationIssue[];
    };

function issue(code: string, message: string, path: string): CanonicalBookingValidationIssue {
  return {code, message, path};
}

function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value != null ? value as Record<string, unknown> : {};
}

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asNullableDate(value: unknown): Date | null {
  return normalizeTimestampLike(value);
}

function asInteger(value: unknown): number | null {
  return Number.isInteger(value) ? value as number : null;
}

function asNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function asBoolean(value: unknown): boolean {
  return value === true;
}

function asStringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((entry): entry is string => typeof entry === "string") : [];
}

function parseParentParticipant(
  raw: Record<string, unknown>,
  issues: CanonicalBookingValidationIssue[],
): PublicParentParticipantSnapshot {
  const restrictedFields = ["fullName", "phoneNumber", "email", "exactAddress", "latitude", "longitude", "username", "profileRoute"];
  for (const field of restrictedFields) {
    if (field in raw) {
      issues.push(issue("PREPAYMENT_PRIVATE_FIELD", `Public parent participant snapshot cannot expose ${field}.`, `participants.parent.${field}`));
    }
  }
  const rating = asNumber(raw.rating) ?? 0;
  const completedBookingCount = asInteger(raw.completedBookingCount) ?? 0;
  return {
    parentId: asString(raw.parentId),
    displayFirstName: asString(raw.displayFirstName) || "Customer",
    lastInitial: asString(raw.lastInitial),
    photoUrl: asString(raw.photoUrl),
    completedBookingCount,
    rating,
  };
}

function parseProviderParticipant(raw: Record<string, unknown>): PublicProviderParticipantSnapshot {
  return {
    providerId: asString(raw.providerId),
    displayName: asString(raw.displayName),
    username: asString(raw.username),
    photoUrl: asString(raw.photoUrl),
    completedBookingCount: asInteger(raw.completedBookingCount) ?? 0,
    rating: asNumber(raw.rating) ?? 0,
  };
}

function parseSchedule(
  bookingType: BookingType,
  raw: Record<string, unknown>,
  issues: CanonicalBookingValidationIssue[],
  serviceSnapshot: Record<string, unknown> = {},
): CanonicalScheduleV3 | null {
  if (bookingType === "SLOT") {
    const slots = Array.isArray(raw.slots) ? raw.slots.map((entry) => {
      const slot = asRecord(entry);
      return {
        slotId: asString(slot.slotId),
        dateKey: asString(slot.dateKey),
        serviceDateKey: asString(slot.serviceDateKey) || undefined,
        startAt: asNullableDate(slot.startAt) ?? new Date("invalid"),
        endAt: asNullableDate(slot.endAt) ?? new Date("invalid"),
        durationMinutes: asInteger(slot.durationMinutes) ?? -1,
        unitPricePaise: asInteger(slot.unitPricePaise) ?? -1,
        serviceId: asString(slot.serviceId),
        providerId: asString(slot.providerId),
        timezone: asString(slot.timezone),
        schedulingMode: asString(slot.schedulingMode) || asString(serviceSnapshot.schedulingMode) || undefined,
      };
    }) : [];
    const segments = Array.isArray(raw.segments) ? raw.segments.map((entry) => {
      const segment = asRecord(entry);
      return {
        serviceDateKey: asString(segment.serviceDateKey),
        slotIds: asStringArray(segment.slotIds),
        startAt: asNullableDate(segment.startAt) ?? new Date("invalid"),
        endAt: asNullableDate(segment.endAt) ?? new Date("invalid"),
        durationMinutes: asInteger(segment.durationMinutes) ?? -1,
        schedulingMode: asString(segment.schedulingMode),
      };
    }) : undefined;

    const selection: SlotBookingSelection = {
      bookingType: "SLOT",
      slots,
      slotCount: asInteger(raw.slotCount) ?? slots.length,
      scheduledStartAt: asNullableDate(raw.scheduledStartAt) ?? new Date("invalid"),
      scheduledEndAt: asNullableDate(raw.scheduledEndAt) ?? new Date("invalid"),
      totalDurationMinutes: asInteger(raw.totalDurationMinutes) ?? -1,
      segments,
      firstSegmentEndAt: asNullableDate(raw.firstSegmentEndAt) ?? undefined,
      finalEndAt: asNullableDate(raw.finalEndAt) ?? undefined,
      serviceDayCount: asInteger(raw.serviceDayCount) ?? undefined,
      segmentCount: asInteger(raw.segmentCount) ?? undefined,
    };
    const validation = validateSlotBookingSelection(selection);
    if (!validation.ok) {
      for (const failure of validation.issues as SlotBookingValidationIssue[]) {
        issues.push(issue(failure.code, failure.message, `schedule.${failure.slotId ?? "slots"}`));
      }
      return null;
    }
    const timezone = asString(raw.timezone) || validation.normalizedSelection.slots[0].timezone;
    const serviceAnchorAt = asNullableDate(raw.serviceAnchorAt);
    if (serviceAnchorAt == null ||
      serviceAnchorAt.getTime() !== validation.normalizedSelection.scheduledStartAt.getTime()) {
      issues.push(issue("SERVICE_ANCHOR_MISMATCH", "serviceAnchorAt must equal scheduledStartAt for SLOT bookings.", "schedule.serviceAnchorAt"));
    }
    return {
      bookingType: "SLOT",
      slots: validation.normalizedSelection.slots,
      segments: validation.normalizedSelection.segments,
      slotCount: validation.normalizedSelection.slotCount,
      scheduledStartAt: validation.normalizedSelection.scheduledStartAt,
      scheduledEndAt: validation.normalizedSelection.scheduledEndAt,
      totalDurationMinutes: validation.normalizedSelection.totalDurationMinutes,
      firstSegmentEndAt: validation.normalizedSelection.firstSegmentEndAt,
      finalEndAt: validation.normalizedSelection.finalEndAt,
      serviceDayCount: validation.normalizedSelection.serviceDayCount,
      segmentCount: validation.normalizedSelection.segmentCount,
      timezone,
      serviceAnchorAt: validation.normalizedSelection.scheduledStartAt,
    };
  }

  const rangeSelection: RangeBookingSelection = {
    bookingType: "RANGE",
    checkInDateTime: asNullableDate(raw.checkInDateTime) ?? new Date("invalid"),
    checkOutDateTime: asNullableDate(raw.checkOutDateTime) ?? new Date("invalid"),
    nights: asInteger(raw.nights) ?? -1,
    pricePerNightPaise:
      asInteger(raw.pricePerNightPaise) ??
      asInteger(serviceSnapshot.pricePerNightPaise) ??
      -1,
    timezone: asString(raw.timezone),
    petQuantity: asInteger(raw.petQuantity) ?? undefined,
    maxConcurrentPetsSnapshot: asInteger(raw.maxConcurrentPetsSnapshot) ?? undefined,
    minNights: asInteger(raw.minNightsSnapshot) ?? undefined,
    maxNights: asInteger(raw.maxNightsSnapshot) ?? undefined,
  };
  const validation = validateRangeBookingSelection(rangeSelection);
  if (!validation.ok) {
    for (const failure of validation.issues as RangeBookingValidationIssue[]) {
      issues.push(issue(failure.code, failure.message, "schedule"));
    }
    return null;
  }
  const serviceAnchorAt = asNullableDate(raw.serviceAnchorAt);
  if (serviceAnchorAt == null ||
    serviceAnchorAt.getTime() !== validation.normalizedSelection.checkInDateTime.getTime()) {
    issues.push(issue("SERVICE_ANCHOR_MISMATCH", "serviceAnchorAt must equal checkInDateTime for RANGE bookings.", "schedule.serviceAnchorAt"));
  }
  return {
    bookingType: "RANGE",
    checkInDateTime: validation.normalizedSelection.checkInDateTime,
    checkOutDateTime: validation.normalizedSelection.checkOutDateTime,
    nights: validation.normalizedSelection.nights,
    timezone: validation.normalizedSelection.timezone,
    minNightsSnapshot: validation.normalizedSelection.minNights ?? null,
    maxNightsSnapshot: validation.normalizedSelection.maxNights ?? null,
    maxConcurrentPetsSnapshot: validation.normalizedSelection.maxConcurrentPetsSnapshot ?? null,
    petQuantity: validation.normalizedSelection.petQuantity ?? null,
    serviceAnchorAt: validation.normalizedSelection.checkInDateTime,
  };
}

function parseLifecycle(raw: Record<string, unknown>): CanonicalLifecycleV3 {
  const providerResponseTypeValue = asString(raw.providerResponseType);
  const providerResponseType: ProviderResponseType | null =
    providerResponseTypeValue === "accept" || providerResponseTypeValue === "decline" || providerResponseTypeValue === "expired" ?
      providerResponseTypeValue :
      null;

  return {
    requestedAt: asNullableDate(raw.requestedAt),
    timerStartsAt: asNullableDate(raw.timerStartsAt),
    wasQueuedOutsideWorkingHours: asBoolean(raw.wasQueuedOutsideWorkingHours),
    notifiedAt: asNullableDate(raw.notifiedAt),
    acceptDeadlineAt: asNullableDate(raw.acceptDeadlineAt),
    viewedByProviderAt: asNullableDate(raw.viewedByProviderAt),
    respondedAt: asNullableDate(raw.respondedAt),
    providerResponseType,
    responseSeconds: asInteger(raw.responseSeconds),
    payDeadlineAt: asNullableDate(raw.payDeadlineAt),
    paymentStartedAt: asNullableDate(raw.paymentStartedAt),
    paidAt: asNullableDate(raw.paidAt),
    paymentSeconds: asInteger(raw.paymentSeconds),
    otpGeneratedAt: asNullableDate(raw.otpGeneratedAt),
    otpEnteredAt: asNullableDate(raw.otpEnteredAt),
    noShowAt: asNullableDate(raw.noShowAt),
    serviceEndedAt: asNullableDate(raw.serviceEndedAt),
    disputeDeadlineAt: asNullableDate(raw.disputeDeadlineAt),
    completedAt: asNullableDate(raw.completedAt),
    reviewWindowEndsAt: asNullableDate(raw.reviewWindowEndsAt),
    finalizedAt: asNullableDate(raw.finalizedAt),
    cancelledAt: asNullableDate(raw.cancelledAt),
  };
}

function parsePayment(raw: Record<string, unknown>): CanonicalPaymentMetadataV3 {
  return {
    status: asString(raw.status),
    razorpayOrderId: asString(raw.razorpayOrderId),
    razorpayPaymentId: asString(raw.razorpayPaymentId),
    razorpayRefundId: asString(raw.razorpayRefundId),
    paymentAttemptId: asString(raw.paymentAttemptId),
    orderCreatedAt: asNullableDate(raw.orderCreatedAt),
    paymentStartedAt: asNullableDate(raw.paymentStartedAt),
    capturedAt: asNullableDate(raw.capturedAt),
    verifiedAt: asNullableDate(raw.verifiedAt),
    verificationSource: asString(raw.verificationSource),
    webhookEventIds: asStringArray(raw.webhookEventIds),
    failureCode: asString(raw.failureCode),
    failureMessage: asString(raw.failureMessage),
  };
}

function parsePrivacy(raw: Record<string, unknown>): CanonicalPrivacyV3 {
  return {
    isPaidContactUnlocked: asBoolean(raw.isPaidContactUnlocked),
    contactUnlockedAt: asNullableDate(raw.contactUnlockedAt),
    chatUnlockedAt: asNullableDate(raw.chatUnlockedAt),
    otpVisibleToParent: asBoolean(raw.otpVisibleToParent),
    exactAddressUnlocked: asBoolean(raw.exactAddressUnlocked),
    privacyVersion: asInteger(raw.privacyVersion) ?? 0,
    privateParticipantsRefPath: asString(raw.privateParticipantsRefPath),
  };
}

function parseCancellation(raw: Record<string, unknown>): CanonicalCancellationV3 {
  const cancelledByValue = asString(raw.cancelledBy);
  const cancelledBy: BookingCancellationActor | null =
    cancelledByValue === "parent" || cancelledByValue === "provider" || cancelledByValue === "system" || cancelledByValue === "admin" ?
      cancelledByValue :
      null;
  const cancellationTypeValue = asString(raw.cancellationType);
  const cancellationType: BookingCancellationType | null = [
    "parent_requested",
    "provider_requested",
    "system_expired",
    "payment_expired",
    "service_not_started",
    "no_show",
    "dispute_resolution",
  ].includes(cancellationTypeValue) ? cancellationTypeValue as BookingCancellationType : null;

  return {
    cancelledAt: asNullableDate(raw.cancelledAt),
    cancelledBy,
    cancelReasonCode: asString(raw.cancelReasonCode),
    cancelReasonText: asString(raw.cancelReasonText),
    hoursBeforeServiceAtCancel: asInteger(raw.hoursBeforeServiceAtCancel),
    refundBand: asString(raw.refundBand),
    refundBasisPoints: asInteger(raw.refundBasisPoints),
    refundAmountPaise: asInteger(raw.refundAmountPaise) ?? 0,
    providerCompensationPaise: asInteger(raw.providerCompensationPaise) ?? 0,
    pettxoRetainedPaise: asInteger(raw.pettxoRetainedPaise) ?? 0,
    cancellationType,
  };
}

function parseDispute(raw: Record<string, unknown>): CanonicalDisputeV3 {
  const raisedByValue = asString(raw.raisedBy);
  const resolvedByValue = asString(raw.resolvedBy);
  return {
    disputeId: asString(raw.disputeId),
    status: asString(raw.status),
    raisedAt: asNullableDate(raw.raisedAt),
    raisedBy: isBookingActor(raisedByValue) ? raisedByValue : null,
    reasonCode: asString(raw.reasonCode),
    description: asString(raw.description),
    evidenceRefs: asStringArray(raw.evidenceRefs),
    resolvedAt: asNullableDate(raw.resolvedAt),
    resolvedBy: isBookingActor(resolvedByValue) ? resolvedByValue : null,
    resolution: asString(raw.resolution),
    resolutionVersion: asInteger(raw.resolutionVersion) ?? 0,
    financialAdjustmentId: asString(raw.financialAdjustmentId),
    refundInstructionId: asString(raw.refundInstructionId),
    customerRefundPaise: asInteger(raw.customerRefundPaise) ?? 0,
    providerReleasePaise: asInteger(raw.providerReleasePaise) ?? 0,
  };
}

function parsePayout(raw: Record<string, unknown>): CanonicalPayoutV3 {
  return {
    status: asString(raw.status),
    holdReason: asString(raw.holdReason),
    eligibleAt: asNullableDate(raw.eligibleAt),
    readyAt: asNullableDate(raw.readyAt),
    processingAt: asNullableDate(raw.processingAt),
    releasedAt: asNullableDate(raw.releasedAt),
    failedAt: asNullableDate(raw.failedAt),
    providerPayoutPaise: asInteger(raw.providerPayoutPaise) ?? 0,
    priorPaidPaise: asInteger(raw.priorPaidPaise) ?? 0,
    remainingPayablePaise: asInteger(raw.remainingPayablePaise) ?? 0,
    payoutReference: asString(raw.payoutReference),
    externalTransactionId: asString(raw.externalTransactionId),
    failureCode: asString(raw.failureCode),
    retryCount: asInteger(raw.retryCount) ?? 0,
  };
}

function parseStatistics(raw: Record<string, unknown>): CanonicalStatisticsV3 {
  return {
    selectedSlotCount: asInteger(raw.selectedSlotCount),
    totalDurationMinutes: asInteger(raw.totalDurationMinutes),
    nights: asInteger(raw.nights),
  };
}

function parseAudit(raw: Record<string, unknown>, issues: CanonicalBookingValidationIssue[]): CanonicalAuditV3 {
  const createdByValue = asString(raw.createdBy);
  const lastUpdatedByValue = asString(raw.lastUpdatedBy);
  if (!isBookingActor(createdByValue)) {
    issues.push(issue("INVALID_AUDIT_ACTOR", "audit.createdBy must be a canonical booking actor.", "audit.createdBy"));
  }
  if (!isBookingActor(lastUpdatedByValue)) {
    issues.push(issue("INVALID_AUDIT_ACTOR", "audit.lastUpdatedBy must be a canonical booking actor.", "audit.lastUpdatedBy"));
  }
  return {
    createdBy: isBookingActor(createdByValue) ? createdByValue : "system",
    lastUpdatedBy: isBookingActor(lastUpdatedByValue) ? lastUpdatedByValue : "system",
    source: asString(raw.source),
  };
}

function validateLifecycle(
  booking: Omit<CanonicalBookingDocumentV3, "schemaVersion" | "bookingModelVersion" | "documentFormat">,
  issues: CanonicalBookingValidationIssue[],
): void {
  const {lifecycle, financials, payment} = booking;
  if (lifecycle.paidAt != null && lifecycle.respondedAt == null) {
    issues.push(issue("PAID_WITHOUT_RESPONSE", "paidAt cannot exist before respondedAt.", "lifecycle.paidAt"));
  }
  if (lifecycle.otpGeneratedAt != null && lifecycle.paidAt == null) {
    issues.push(issue("OTP_BEFORE_PAYMENT", "otpGeneratedAt cannot exist before paidAt.", "lifecycle.otpGeneratedAt"));
  }
  if (lifecycle.completedAt != null && lifecycle.serviceEndedAt == null) {
    issues.push(issue("COMPLETED_WITHOUT_SERVICE_END", "completedAt requires serviceEndedAt.", "lifecycle.completedAt"));
  }
  if (lifecycle.payDeadlineAt != null && lifecycle.respondedAt == null) {
    issues.push(issue("PAY_DEADLINE_WITHOUT_RESPONSE", "payDeadlineAt cannot exist before provider response.", "lifecycle.payDeadlineAt"));
  }
  if (lifecycle.paidAt != null && financials == null) {
    issues.push(issue("PAID_WITHOUT_FINANCIAL_SNAPSHOT", "Paid bookings must include immutable financials.", "financials"));
  }
  if (payment.status.toLowerCase() === "paid" && financials == null) {
    issues.push(issue("PAID_STATUS_WITHOUT_FINANCIAL_SNAPSHOT", "Payment status paid requires immutable financials.", "payment.status"));
  }
}

function validateTopLevelQueryFields(
  booking: Omit<CanonicalBookingDocumentV3, "schemaVersion" | "bookingModelVersion" | "documentFormat">,
  issues: CanonicalBookingValidationIssue[],
): void {
  if (booking.parentId !== booking.participants.parent.parentId) {
    issues.push(issue("QUERY_FIELD_MISMATCH", "parentId must match participants.parent.parentId.", "parentId"));
  }
  if (booking.customerId !== booking.parentId) {
    issues.push(issue("QUERY_FIELD_MISMATCH", "customerId compatibility field must match parentId.", "customerId"));
  }
  if (booking.providerId !== booking.participants.provider.providerId ||
    booking.providerId !== booking.service.providerId) {
    issues.push(issue("QUERY_FIELD_MISMATCH", "providerId must match provider and service snapshots.", "providerId"));
  }
  if (booking.serviceOwnerId !== booking.providerId) {
    issues.push(issue("QUERY_FIELD_MISMATCH", "serviceOwnerId compatibility field must match providerId.", "serviceOwnerId"));
  }
  if (booking.serviceId !== booking.service.serviceId) {
    issues.push(issue("QUERY_FIELD_MISMATCH", "serviceId must match service snapshot.", "serviceId"));
  }
  if (booking.stateQueryValue !== booking.state) {
    issues.push(issue("QUERY_FIELD_MISMATCH", "stateQueryValue must match state.", "stateQueryValue"));
  }
  if (booking.bookingTypeQueryValue !== booking.bookingType) {
    issues.push(issue("QUERY_FIELD_MISMATCH", "bookingTypeQueryValue must match bookingType.", "bookingTypeQueryValue"));
  }
  if (booking.serviceAnchorAt.getTime() !== booking.schedule.serviceAnchorAt.getTime()) {
    issues.push(issue("QUERY_FIELD_MISMATCH", "Top-level serviceAnchorAt must match schedule.serviceAnchorAt.", "serviceAnchorAt"));
  }
  if (booking.bookingType === "SLOT") {
    const schedule = booking.schedule as CanonicalSlotScheduleV3 & {serviceAnchorAt: Date};
    if (booking.scheduledStartAt == null ||
      booking.scheduledStartAt.getTime() !== schedule.scheduledStartAt.getTime()) {
      issues.push(issue("QUERY_FIELD_MISMATCH", "scheduledStartAt must match the SLOT schedule.", "scheduledStartAt"));
    }
  }
  if (booking.bookingType === "RANGE") {
    const schedule = booking.schedule as CanonicalRangeScheduleV3 & {serviceAnchorAt: Date};
    if (booking.checkInDateTime == null ||
      booking.checkInDateTime.getTime() !== schedule.checkInDateTime.getTime()) {
      issues.push(issue("QUERY_FIELD_MISMATCH", "checkInDateTime must match the RANGE schedule.", "checkInDateTime"));
    }
  }
  if ((booking.acceptDeadlineAt?.getTime() ?? null) !== (booking.lifecycle.acceptDeadlineAt?.getTime() ?? null)) {
    issues.push(issue("QUERY_FIELD_MISMATCH", "acceptDeadlineAt must match lifecycle.acceptDeadlineAt.", "acceptDeadlineAt"));
  }
  if ((booking.payDeadlineAt?.getTime() ?? null) !== (booking.lifecycle.payDeadlineAt?.getTime() ?? null)) {
    issues.push(issue("QUERY_FIELD_MISMATCH", "payDeadlineAt must match lifecycle.payDeadlineAt.", "payDeadlineAt"));
  }
  if ((booking.completedAt?.getTime() ?? null) !== (booking.lifecycle.completedAt?.getTime() ?? null)) {
    issues.push(issue("QUERY_FIELD_MISMATCH", "completedAt must match lifecycle.completedAt.", "completedAt"));
  }
}

export function parseCanonicalBookingDocumentV3(rawValue: unknown): CanonicalBookingValidationResult {
  const raw = asRecord(rawValue);
  const issues: CanonicalBookingValidationIssue[] = [];

  const schemaVersion = asInteger(raw.schemaVersion);
  const bookingModelVersion = asString(raw.bookingModelVersion);
  const documentFormat = asString(raw.documentFormat);
  const bookingTypeValue = asString(raw.bookingType);
  const stateValue = asString(raw.state);

  if (schemaVersion !== CANONICAL_BOOKING_SCHEMA_VERSION) {
    issues.push(issue("INVALID_SCHEMA_VERSION", "schemaVersion must equal 3.", "schemaVersion"));
  }
  if (bookingModelVersion !== CANONICAL_BOOKING_MODEL_VERSION) {
    issues.push(issue("INVALID_MODEL_VERSION", 'bookingModelVersion must equal "3.2".', "bookingModelVersion"));
  }
  if (documentFormat !== CANONICAL_BOOKING_DOCUMENT_FORMAT) {
    issues.push(issue("INVALID_DOCUMENT_FORMAT", 'documentFormat must equal "canonical_v3".', "documentFormat"));
  }
  if (!isBookingType(bookingTypeValue)) {
    issues.push(issue("INVALID_BOOKING_TYPE", "bookingType must be SLOT or RANGE.", "bookingType"));
  }
  if (!isCanonicalBookingState(stateValue)) {
    issues.push(issue("INVALID_STATE", "state must be a canonical booking state.", "state"));
  }

  const participants = {
    parent: parseParentParticipant(asRecord(raw.participants).parent ? asRecord(asRecord(raw.participants).parent) : {}, issues),
    provider: parseProviderParticipant(asRecord(raw.participants).provider ? asRecord(asRecord(raw.participants).provider) : {}),
  };

  const service = asRecord(raw.service);
  if (!isBookingServiceSnapshot(service)) {
    issues.push(issue("INVALID_SERVICE_SNAPSHOT", "service must match the immutable booking service snapshot contract.", "service"));
  }

  const schedule = isBookingType(bookingTypeValue) ?
    parseSchedule(bookingTypeValue, asRecord(raw.schedule), issues, service) :
    null;
  const lifecycle = parseLifecycle(asRecord(raw.lifecycle));
  const payment = parsePayment(asRecord(raw.payment));
  const privacy = parsePrivacy(asRecord(raw.privacy));
  const cancellation = parseCancellation(asRecord(raw.cancellation));
  const dispute = parseDispute(asRecord(raw.dispute));
  const payout = parsePayout(asRecord(raw.payout));
  const statistics = parseStatistics(asRecord(raw.statistics));
  const audit = parseAudit(asRecord(raw.audit), issues);
  const financialsRaw = raw.financials == null ? null : asRecord(raw.financials);
  const financials = financialsRaw == null ? null :
    (isBookingFinancialSnapshot(financialsRaw) ? financialsRaw : null);
  if (financialsRaw != null && financials == null) {
    issues.push(issue("INVALID_FINANCIAL_SNAPSHOT", "financials must match the canonical paise-only financial snapshot.", "financials"));
  }

  const createdAt = asNullableDate(raw.createdAt);
  const updatedAt = asNullableDate(raw.updatedAt);
  if (createdAt == null) {
    issues.push(issue("MISSING_CREATED_AT", "createdAt is required.", "createdAt"));
  }
  if (updatedAt == null) {
    issues.push(issue("MISSING_UPDATED_AT", "updatedAt is required.", "updatedAt"));
  }

  if (issues.length > 0 || schedule == null || !isBookingType(bookingTypeValue) || !isCanonicalBookingState(stateValue) || !isBookingServiceSnapshot(service) || createdAt == null || updatedAt == null) {
    return {ok: false, booking: null, issues};
  }

  const booking: Omit<CanonicalBookingDocumentV3, "schemaVersion" | "bookingModelVersion" | "documentFormat"> = {
    bookingType: bookingTypeValue,
    state: stateValue,
    participants,
    service,
    schedule,
    lifecycle,
    payment,
    financials,
    privacy,
    cancellation,
    dispute,
    payout,
    statistics,
    audit,
    parentId: asString(raw.parentId),
    providerId: asString(raw.providerId),
    serviceId: asString(raw.serviceId),
    bookingIdSearchKey: asString(raw.bookingIdSearchKey),
    stateQueryValue: isCanonicalBookingState(asString(raw.stateQueryValue)) ? asString(raw.stateQueryValue) as CanonicalBookingState : stateValue,
    bookingTypeQueryValue: isBookingType(asString(raw.bookingTypeQueryValue)) ? asString(raw.bookingTypeQueryValue) as BookingType : bookingTypeValue,
    serviceAnchorAt: asNullableDate(raw.serviceAnchorAt) ?? schedule.serviceAnchorAt,
    scheduledStartAt: asNullableDate(raw.scheduledStartAt),
    checkInDateTime: asNullableDate(raw.checkInDateTime),
    acceptDeadlineAt: asNullableDate(raw.acceptDeadlineAt),
    payDeadlineAt: asNullableDate(raw.payDeadlineAt),
    completedAt: asNullableDate(raw.completedAt),
    customerId: asString(raw.customerId),
    serviceOwnerId: asString(raw.serviceOwnerId),
    createdAt,
    updatedAt,
  };

  validateLifecycle(booking, issues);
  validateTopLevelQueryFields(booking, issues);

  if (issues.length > 0) {
    return {ok: false, booking: null, issues};
  }

  return {
    ok: true,
    booking: {
      schemaVersion: CANONICAL_BOOKING_SCHEMA_VERSION,
      bookingModelVersion: CANONICAL_BOOKING_MODEL_VERSION,
      documentFormat: CANONICAL_BOOKING_DOCUMENT_FORMAT,
      ...booking,
    },
    issues: [],
  };
}

export function assertValidCanonicalBookingDocumentV3(rawValue: unknown): CanonicalBookingDocumentV3 {
  const parsed = parseCanonicalBookingDocumentV3(rawValue);
  if (!parsed.ok) {
    throw new Error(parsed.issues.map((entry) => `${entry.code}:${entry.path}`).join(", "));
  }
  return parsed.booking;
}
