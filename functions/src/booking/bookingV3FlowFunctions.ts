import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {
  HttpsError,
  onCall,
  onRequest,
  type CallableRequest,
} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {
  RAZORPAY_KEY_ID,
  RAZORPAY_KEY_SECRET,
  RAZORPAY_WEBHOOK_SECRET,
} from "../config/secrets";
import {auth, db} from "../shared/firebase";
import {
  acceptBookingRequestV3 as acceptBookingRequestApplicationV3,
  cancelBookingRequestByParentV3 as cancelBookingRequestByParentApplicationV3,
  createBookingRequestV3 as createBookingRequestApplicationV3,
  declineBookingRequestV3 as declineBookingRequestApplicationV3,
  expireAwaitingPaymentBookingV3 as expireAwaitingPaymentBookingApplicationV3,
  expirePendingProviderBookingV3 as expirePendingProviderBookingApplicationV3,
  type AuthenticatedParentIdentity,
  type BookingRequestAttemptRecord,
  type CanonicalServiceSource,
  markBookingViewedByProviderV3 as markBookingViewedByProviderApplicationV3,
} from "./application/createBookingRequestV3";
import {emptyParentStatsV3, emptyProviderStatsV3} from "./application/bookingStats";
import {
  canonicalPaymentOrderMappingRef,
  createRazorpayPaymentOrderV3 as createRazorpayPaymentOrderApplicationV3,
  persistFinalizePaymentResultV3,
  reconcilePaymentAttemptsV3,
  verifyCapturedBookingPaymentV3,
} from "./application/paymentOrchestrationV3";
import {
  applyConfirmedBookingCancellationV3,
  buildCanonicalCancellationPreviewV3,
  BOOKING_CANCELLATION_COLLECTION,
  loadCapacityStateForCancellationV3,
  writeConfirmedBookingCancellationTransactionV3,
  type CancellationActorType,
} from "./application/cancellationOrchestrationV3";
import {
  verifyBookingStartOtpV3 as verifyBookingStartOtpApplicationV3,
  reconcileCanonicalServiceStartArtifactsV3,
  type ServiceStartApplyResult,
} from "./application/serviceStartOrchestrationV3";
import {
  completeBookingServiceV3 as completeBookingServiceApplicationV3,
  createBookingDisputeV3 as createBookingDisputeApplicationV3,
  finalizeCompletedBookingV3 as finalizeCompletedBookingApplicationV3,
  submitBookingReviewV3 as submitBookingReviewApplicationV3,
} from "./application/serviceCompletionOrchestrationV3";
import {routeCanonicalWebhookEventV3} from "./application/canonicalPaymentWebhookV3";
import {
  CANONICAL_FINANCIAL_LEDGER_COLLECTION,
  CANONICAL_PROVIDER_PAYOUTS_COLLECTION,
  DisabledProviderPayoutGatewayV3,
  processProviderPayoutV3 as processProviderPayoutApplicationV3,
  processReadyProviderPayoutBatchV3,
  processRetryableProviderPayoutBatchV3,
  reconcileBookingFinancialsV3 as reconcileBookingFinancialsApplicationV3,
  resolveBookingDisputeV3 as resolveBookingDisputeApplicationV3,
} from "./application/financialSettlementV3";
import {processRazorpayWebhookEnvelopeV3} from "./application/paymentWebhookEventsV3";
import {verifyRazorpayPaymentSignature} from "./application/razorpayGateway";
import {
  assertValidCanonicalBookingDocumentV3,
  type CanonicalBookingDocumentV3,
} from "./schema/bookingDocumentV3";
import type {CanonicalPaymentAttemptDocumentV3} from "./schema/paymentAttemptDocumentV3";
import type {
  RangeBookingSelection,
} from "./domain/rangeBooking";
import type {
  SlotBookingSelection,
  SlotSegment,
} from "./domain/slotBooking";

type CanonicalBookingRequestResponse = {
  bookingId: string;
  source: "canonical_v3";
  schemaVersion: 3;
  bookingModelVersion: "3.2";
  state: CanonicalBookingDocumentV3["state"];
  bookingType: CanonicalBookingDocumentV3["bookingType"];
  requestedAt: string | null;
  timerStartsAt: string | null;
  acceptDeadlineAt: string | null;
  wasQueuedOutsideWorkingHours: boolean;
  idempotentReplay: boolean;
};

type CanonicalBookingCommandResponse = {
  bookingId: string;
  state: CanonicalBookingDocumentV3["state"];
  respondedAt?: string | null;
  payDeadlineAt?: string | null;
  cancelledAt?: string | null;
  viewedByProviderAt?: string | null;
  idempotentReplay: boolean;
};

type CanonicalPaymentPricingSummaryResponse = {
  serviceSubtotalPaise: number;
  couponDiscountPaise: number;
  customerPaidPaise: number;
  providerPayoutPaise: number;
  currency: string;
};

type CanonicalPaymentOrderResponse =
  | {
      bookingId: string;
      paymentAttemptId: string;
      mode: "razorpay";
      keyId: string;
      razorpayOrderId: string;
      amountPaise: number;
      currency: string;
      pricingSummary: CanonicalPaymentPricingSummaryResponse;
      expiresAt: string | null;
      idempotentReplay: boolean;
    }
  | {
      bookingId: string;
      paymentAttemptId: string;
      mode: "zero_payable";
      state: CanonicalBookingDocumentV3["state"];
      confirmedAt: string | null;
      pricingSummary: CanonicalPaymentPricingSummaryResponse;
      idempotentReplay: boolean;
    };

type CanonicalPaymentVerificationResponse = {
  bookingId: string;
  paymentAttemptId: string;
  status:
    | "CONFIRMED"
    | "PROCESSING"
    | "RECONCILIATION_REQUIRED"
    | "REFUND_REQUIRED"
    | "PAYMENT_EXPIRED"
    | "FAILED";
  state: CanonicalBookingDocumentV3["state"] | null;
  confirmedAt: string | null;
  payDeadlineAt: string | null;
  idempotentReplay: boolean;
};

type CanonicalBookingCancellationPreviewResponse = {
  bookingId: string;
  actorType: string;
  allowed: boolean;
  outcome: string;
  timingBand: string;
  refundPercentageBasisPoints: number;
  providerShareBasisPoints: number;
  pettxoShareBasisPoints: number;
  customerPaidPaise: number;
  refundableCustomerPaidPaise: number;
  nonRefundableCustomerPaidPaise: number;
  grossCustomerRefundPaise: number;
  remainingRefundablePaise: number;
  providerCompensationPaise: number;
  pettxoRetainedPaise: number;
  message: string;
  policyVersion: string;
};

type CanonicalBookingCancellationResponse = {
  bookingId: string;
  state: CanonicalBookingDocumentV3["state"];
  cancellationStatus: string;
  refundStatus: string;
  refundAmountPaise: number;
  timingBand: string;
  outcome: string;
  cancelledAt: string | null;
  idempotentReplay: boolean;
};

type CanonicalBookingStartOtpResponse = {
  bookingId: string;
  code: ServiceStartApplyResult["code"];
  state: CanonicalBookingDocumentV3["state"];
  otpEnteredAt: string | null;
  idempotentReplay: boolean;
  retryAfterMs: number | null;
};

type CanonicalBookingCompletionResponse = {
  bookingId: string;
  code: string;
  state: CanonicalBookingDocumentV3["state"] | "";
  idempotentReplay: boolean;
  completedAt: string | null;
  reviewWindowEndsAt: string | null;
};

type CanonicalBookingReviewResponse = {
  bookingId: string;
  code: string;
  state: CanonicalBookingDocumentV3["state"] | "";
  reviewId: string;
  idempotentReplay: boolean;
  submittedAt: string | null;
};

type CanonicalBookingDisputeResponse = {
  bookingId: string;
  code: string;
  state: CanonicalBookingDocumentV3["state"] | "";
  disputeId: string;
  idempotentReplay: boolean;
  createdAt: string | null;
};

type CanonicalDisputeResolutionResponse = {
  bookingId: string;
  disputeId: string;
  resolutionId: string;
  adjustmentId: string;
  refundInstructionId: string;
  payoutId: string;
  resolutionType: string;
  disputeStatus: string;
  payoutStatus: string;
  customerRefundPaise: number;
  providerFinalEntitlementPaise: number;
  pettxoFinalRetainedPaise: number;
  idempotentReplay: boolean;
};

type CanonicalProviderPayoutResponse = {
  ok: boolean;
  code: string;
  bookingId: string;
  payoutId: string;
  status: string;
  failureCode: string;
  externalPayoutId?: string;
  externalTransactionId?: string;
};

type CanonicalFinancialReconciliationResponse = {
  bookingId: string;
  status: string;
  action: string;
  issues: string[];
  repairWriteCount: number;
};

type CanonicalAuthorizationResult = {
  allowed: true;
  code: "CANONICAL_BOOKING_ENABLED";
  metadata: {
    matchedRule: "ALWAYS_ON_CANONICAL_V3";
    rolloutBucket: null;
    configVersion: "always-on-canonical-v3";
  };
};

type SlotRequestPayload = {
  slotIds: string[];
};

type RangeRequestPayload = {
  checkInDateTime: Date;
  checkOutDateTime: Date;
  petQuantity: number | null;
};

type ParsedCanonicalRequestInput = {
  requestAttemptId: string;
  serviceId: string;
  bookingType: "SLOT" | "RANGE";
  slotRequest: SlotRequestPayload | null;
  rangeRequest: RangeRequestPayload | null;
};

type AuthorizedCanonicalCommandContext = {
  bookingRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
  booking: CanonicalBookingDocumentV3;
  service: Record<string, unknown> | null;
  authorization: CanonicalAuthorizationResult;
};

type AuthorizedCanonicalPaymentCommandContext = AuthorizedCanonicalCommandContext & {
  paymentAttemptRef:
    | FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>
    | null;
  paymentAttempt:
    | Record<string, unknown>
    | null;
  paymentAttemptState: string;
};

function requireUid(authContext: {uid?: string} | null | undefined): string {
  const uid = authContext?.uid?.trim() ?? "";
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return uid;
}

async function requireFinanceAdmin(uid: string): Promise<void> {
  const snapshot = await db.collection("users").doc(uid).get();
  const adminRole = asString(snapshot.data()?.adminRole);
  if (adminRole !== "superAdmin" && adminRole !== "financeAdmin") {
    throw new HttpsError("permission-denied", "Finance admin access required.");
  }
}

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asInt(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value) ? Math.trunc(value) : fallback;
}

function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value != null ?
    value as Record<string, unknown> :
    {};
}

function asNullableDate(value: unknown): Date | null {
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value;
  if (value instanceof Timestamp) return value.toDate();
  if (typeof value === "string" && value.trim()) {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  if (typeof value === "object" && value != null && "toDate" in value) {
    try {
      return (value as {toDate(): Date}).toDate();
    } catch (_) {
      return null;
    }
  }
  return null;
}

function inferBookingType(service: Record<string, unknown>): "SLOT" | "RANGE" {
  const explicit = asString(service.bookingType).toUpperCase();
  if (explicit === "RANGE") return "RANGE";
  if (explicit === "SLOT") return "SLOT";
  const hasRangePricing = asInt(service.pricePerNightPaise, 0) > 0;
  return hasRangePricing ? "RANGE" : "SLOT";
}

const CANONICAL_BOOKING_AUTHORIZATION: CanonicalAuthorizationResult = {
  allowed: true,
  code: "CANONICAL_BOOKING_ENABLED",
  metadata: {
    matchedRule: "ALWAYS_ON_CANONICAL_V3",
    rolloutBucket: null,
    configVersion: "always-on-canonical-v3",
  },
};

async function loadServiceSnapshot(serviceId: string): Promise<Record<string, unknown> | null> {
  const snapshot = await db.collection("services").doc(serviceId).get();
  if (!snapshot.exists) return null;
  return snapshot.data() as Record<string, unknown>;
}

function requireCanonicalGate(params: {
  uid: string;
  serviceId: string;
  bookingType: "SLOT" | "RANGE";
  service: Record<string, unknown> | null;
  now: Date;
}): CanonicalAuthorizationResult {
  return CANONICAL_BOOKING_AUTHORIZATION;
}

function parseCanonicalRequestInput(raw: unknown): ParsedCanonicalRequestInput {
  const data =
    typeof raw === "object" && raw != null ? raw as Record<string, unknown> : {};
  const requestAttemptId = asString(data.requestAttemptId);
  const serviceId = asString(data.serviceId);
  const bookingType = asString(data.bookingType).toUpperCase();

  if (!requestAttemptId) {
    throw new HttpsError("invalid-argument", "requestAttemptId is required.");
  }
  if (!serviceId) {
    throw new HttpsError("invalid-argument", "serviceId is required.");
  }
  if (bookingType !== "SLOT" && bookingType !== "RANGE") {
    throw new HttpsError("invalid-argument", "bookingType must be SLOT or RANGE.");
  }

  if (bookingType === "SLOT") {
    const slotIdsRaw = Array.isArray(data.slotIds) ? data.slotIds : [];
    const slotIds = slotIdsRaw
      .map((entry) => asString(entry))
      .filter(Boolean);
    if (slotIds.length === 0) {
      throw new HttpsError("invalid-argument", "slotIds are required for SLOT requests.");
    }
    return {
      requestAttemptId,
      serviceId,
      bookingType,
      slotRequest: {slotIds: [...new Set(slotIds)]},
      rangeRequest: null,
    };
  }

  const checkInDateTime = asNullableDate(data.checkInDateTime);
  const checkOutDateTime = asNullableDate(data.checkOutDateTime);
  const petQuantity = data.petQuantity == null ? null : asInt(data.petQuantity, 0);
  if (!checkInDateTime || !checkOutDateTime) {
    throw new HttpsError(
      "invalid-argument",
      "checkInDateTime and checkOutDateTime are required for RANGE requests.",
    );
  }
  return {
    requestAttemptId,
    serviceId,
    bookingType,
    slotRequest: null,
    rangeRequest: {
      checkInDateTime,
      checkOutDateTime,
      petQuantity: petQuantity != null && petQuantity > 0 ? petQuantity : null,
    },
  };
}

function buildCanonicalServiceSource(
  service: Record<string, unknown>,
): CanonicalServiceSource & {
  isPaused?: boolean;
  isPausedByVerification?: boolean;
  status?: string;
  isActive?: boolean;
  isDeleted?: boolean;
  isVisibleToMarketplace?: boolean;
  providerVerificationStatus?: string;
  providerVerificationGraceEndsAt?: Date | null;
} {
  const rawGraceEndsAt = service.providerVerificationGraceEndsAt;
  const finalGraceEndsAt =
    typeof rawGraceEndsAt === "object" &&
        rawGraceEndsAt != null &&
        "toDate" in (rawGraceEndsAt as Record<string, unknown>) ?
      (rawGraceEndsAt as {toDate(): Date}).toDate() :
      rawGraceEndsAt instanceof Date ?
        rawGraceEndsAt :
        null;
  return {
    id: asString(service.id) || asString(service.serviceId),
    ownerUserId: asString(service.ownerUserId),
    ownerName:
      asString(service.ownerName) ||
      asString((service.ownerSnapshot as Record<string, unknown> | undefined)?.name),
    ownerUsername:
      asString(service.ownerUsername) ||
      asString((service.ownerSnapshot as Record<string, unknown> | undefined)?.username),
    ownerPhotoUrl:
      asString(service.ownerPhotoUrl) ||
      asString((service.ownerSnapshot as Record<string, unknown> | undefined)?.photoUrl),
    title: asString(service.title),
    animalType: asString(service.animalType),
    category: asString(service.category),
    serviceType: asString(service.serviceType),
    currency: asString(service.currency) || "INR",
    sessionDurationMinutes: asInt(service.sessionDurationMinutes, 0),
    capacity: asInt(service.capacity, 1),
    stats:
      typeof service.stats === "object" && service.stats != null ?
        service.stats as Record<string, unknown> :
        {},
    location:
      typeof service.location === "object" && service.location != null ?
        service.location as Record<string, unknown> :
        {},
    timezone: asString(service.timezone) || "Asia/Kolkata",
    availableDays: service.availableDays,
    startMinutes: service.startMinutes,
    endMinutes: service.endMinutes,
    sameForAllDays: service.sameForAllDays,
    isPaused: typeof service.isPaused === "boolean" ? service.isPaused : undefined,
    isPausedByVerification:
      typeof service.isPausedByVerification === "boolean" ?
        service.isPausedByVerification :
        undefined,
    status: asString(service.status) || undefined,
    isActive: typeof service.isActive === "boolean" ? service.isActive : undefined,
    isDeleted: typeof service.isDeleted === "boolean" ? service.isDeleted : undefined,
    isVisibleToMarketplace:
      typeof service.isVisibleToMarketplace === "boolean" ?
        service.isVisibleToMarketplace :
        undefined,
    providerVerificationStatus:
      asString(service.providerVerificationStatus) || undefined,
    providerVerificationGraceEndsAt: finalGraceEndsAt,
  };
}

async function buildParentIdentity(uid: string): Promise<AuthenticatedParentIdentity> {
  const [authRecord, userSnapshot] = await Promise.all([
    auth.getUser(uid),
    db.collection("users").doc(uid).get(),
  ]);
  const user = userSnapshot.data() ?? {};
  return {
    uid,
    displayName:
      asString(user.displayName) ||
      asString(user.name) ||
      asString(authRecord.displayName),
    fullName:
      asString(user.displayName) ||
      asString(user.name) ||
      asString(authRecord.displayName),
    photoUrl:
      asString(user.photoUrl) ||
      asString(user.profileImage) ||
      asString(authRecord.photoURL),
    email: asString(authRecord.email),
    phoneNumber: asString(authRecord.phoneNumber),
    rating:
      typeof user.ratingAverage === "number" && Number.isFinite(user.ratingAverage) ?
        user.ratingAverage as number :
        0,
    completedBookingCount: asInt(
      user.completedBookingCount,
      asInt(user.completedBookingsCount, 0),
    ),
  };
}

async function buildAuthoritativeSlotSelection(params: {
  serviceId: string;
  providerId: string;
  slotIds: string[];
  unitPricePaise: number;
}): Promise<SlotBookingSelection> {
  const snapshots = await Promise.all(
    params.slotIds.map((slotId) =>
      db.collection("services").doc(params.serviceId).collection("slots").doc(slotId).get(),
    ),
  );
  if (snapshots.some((snapshot) => !snapshot.exists)) {
    throw new HttpsError("invalid-argument", "One or more selected slots no longer exist.");
  }
  const slots: SlotSegment[] = snapshots.map((snapshot) => {
    const data = snapshot.data() ?? {};
    const startAt = asNullableDate(data.startAt);
    const endAt = asNullableDate(data.endAt);
    if (!startAt || !endAt) {
      throw new HttpsError("invalid-argument", "Selected slot timing is invalid.");
    }
    if (data.isBookable !== true || asString(data.status) !== "open") {
      throw new HttpsError("failed-precondition", "Selected slot is no longer requestable.");
    }
    return {
      slotId: snapshot.id,
      serviceId: params.serviceId,
      providerId: params.providerId,
      timezone: asString(data.timezone) || "Asia/Kolkata",
      dateKey: asString(data.dateKey),
      startAt,
      endAt,
      durationMinutes: Math.round((endAt.getTime() - startAt.getTime()) / 60000),
      unitPricePaise: params.unitPricePaise,
    };
  }).sort((left, right) => left.startAt.getTime() - right.startAt.getTime());
  const scheduledStartAt = slots[0].startAt;
  const scheduledEndAt = slots[slots.length - 1].endAt;
  const totalDurationMinutes = slots.reduce(
    (sum, slot) => sum + slot.durationMinutes,
    0,
  );
  return {
    bookingType: "SLOT",
    slots,
    slotCount: slots.length,
    scheduledStartAt,
    scheduledEndAt,
    totalDurationMinutes,
  };
}

function buildAuthoritativeRangeSelection(params: {
  service: Record<string, unknown>;
  rangeRequest: RangeRequestPayload;
}): RangeBookingSelection {
  return {
    bookingType: "RANGE",
    checkInDateTime: new Date(params.rangeRequest.checkInDateTime.getTime()),
    checkOutDateTime: new Date(params.rangeRequest.checkOutDateTime.getTime()),
    nights: 0,
    pricePerNightPaise: Math.max(asInt(params.service.pricePerNightPaise, 0), 0),
    timezone: asString(params.service.timezone) || "Asia/Kolkata",
    petQuantity: params.rangeRequest.petQuantity ?? undefined,
    maxConcurrentPetsSnapshot: (() => {
      const value = asInt(
        params.service.maxConcurrentPetsSnapshot,
        asInt(params.service.maxConcurrentPets, 0),
      );
      return value > 0 ? value : undefined;
    })(),
    minNights: Math.max(asInt(params.service.minNights, 1), 1),
    maxNights: Math.min(Math.max(asInt(params.service.maxNights, 30), 1), 30),
  };
}

function parseExistingAttempt(
  raw: FirebaseFirestore.DocumentData | undefined,
): BookingRequestAttemptRecord | null {
  if (!raw) return null;
  try {
    return {
      parentId: asString(raw.parentId),
      requestAttemptId: asString(raw.requestAttemptId),
      bookingId: asString(raw.bookingId),
      requestHash: asString(raw.requestHash),
      bookingSnapshot: assertValidCanonicalBookingDocumentV3(raw.bookingSnapshot),
    };
  } catch (_) {
    return null;
  }
}

function serializeAttemptRecord(record: BookingRequestAttemptRecord): Record<string, unknown> {
  return {
    parentId: record.parentId,
    requestAttemptId: record.requestAttemptId,
    bookingId: record.bookingId,
    requestHash: record.requestHash,
    bookingSnapshot: record.bookingSnapshot,
    schemaVersion: 1,
    source: "booking_v3_internal",
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function buildRequestResponse(
  bookingId: string,
  booking: CanonicalBookingDocumentV3,
  idempotentReplay: boolean,
): CanonicalBookingRequestResponse {
  return {
    bookingId,
    source: "canonical_v3",
    schemaVersion: 3,
    bookingModelVersion: "3.2",
    state: booking.state,
    bookingType: booking.bookingType,
    requestedAt: booking.lifecycle.requestedAt?.toISOString() ?? null,
    timerStartsAt: booking.lifecycle.timerStartsAt?.toISOString() ?? null,
    acceptDeadlineAt: booking.lifecycle.acceptDeadlineAt?.toISOString() ?? null,
    wasQueuedOutsideWorkingHours: booking.lifecycle.wasQueuedOutsideWorkingHours,
    idempotentReplay,
  };
}

function buildCommandResponse(
  bookingId: string,
  booking: CanonicalBookingDocumentV3,
  idempotentReplay: boolean,
): CanonicalBookingCommandResponse {
  return {
    bookingId,
    state: booking.state,
    respondedAt: booking.lifecycle.respondedAt?.toISOString() ?? null,
    payDeadlineAt: booking.lifecycle.payDeadlineAt?.toISOString() ?? null,
    cancelledAt: booking.lifecycle.cancelledAt?.toISOString() ?? null,
    viewedByProviderAt: booking.lifecycle.viewedByProviderAt?.toISOString() ?? null,
    idempotentReplay,
  };
}

function buildPricingSummaryResponse(
  booking: CanonicalBookingDocumentV3,
  paymentAttempt?: Record<string, unknown> | null,
): CanonicalPaymentPricingSummaryResponse {
  const bookingFinancials = booking.financials;
  const attemptPricing =
    typeof paymentAttempt?.pricingSnapshot === "object" &&
        paymentAttempt?.pricingSnapshot != null ?
      paymentAttempt.pricingSnapshot as Record<string, unknown> :
      {};
  const attemptFinancials =
    typeof attemptPricing.financials === "object" && attemptPricing.financials != null ?
      attemptPricing.financials as Record<string, unknown> :
      {};
  return {
    serviceSubtotalPaise:
      bookingFinancials?.serviceSubtotalPaise ??
      asInt(attemptPricing.serviceSubtotalPaise, 0),
    couponDiscountPaise:
      bookingFinancials?.couponDiscountPaise ??
      asInt(attemptPricing.couponDiscountPaise, 0),
    customerPaidPaise:
      bookingFinancials?.customerPaidPaise ??
      asInt(paymentAttempt?.amountPaise, 0),
    providerPayoutPaise:
      bookingFinancials?.providerPayoutPaise ??
      asInt(attemptFinancials.providerPayoutPaise, 0),
    currency: bookingFinancials?.currency ??
      (asString(paymentAttempt?.currency) || "INR"),
  };
}

function buildPaymentOrderResponse(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  paymentAttemptId: string;
  paymentAttempt: Record<string, unknown> | null;
  mode: "razorpay" | "zero_payable";
  keyId?: string;
  razorpayOrderId?: string;
  amountPaise?: number;
  currency?: string;
  expiresAt?: Date | null;
  idempotentReplay: boolean;
}): CanonicalPaymentOrderResponse {
  const pricingSummary = buildPricingSummaryResponse(
    params.booking,
    params.paymentAttempt,
  );
  if (params.mode === "zero_payable") {
    return {
      bookingId: params.bookingId,
      paymentAttemptId: params.paymentAttemptId,
      mode: "zero_payable",
      state: params.booking.state,
      confirmedAt: params.booking.lifecycle.paidAt?.toISOString() ?? null,
      pricingSummary,
      idempotentReplay: params.idempotentReplay,
    };
  }
  return {
    bookingId: params.bookingId,
    paymentAttemptId: params.paymentAttemptId,
    mode: "razorpay",
    keyId: params.keyId ?? "",
    razorpayOrderId: params.razorpayOrderId ?? "",
    amountPaise: params.amountPaise ?? pricingSummary.customerPaidPaise,
    currency: params.currency || pricingSummary.currency,
    pricingSummary,
    expiresAt: params.expiresAt?.toISOString() ?? null,
    idempotentReplay: params.idempotentReplay,
  };
}

function buildPaymentVerificationResponse(params: {
  bookingId: string;
  paymentAttemptId: string;
  status:
    | "CONFIRMED"
    | "PROCESSING"
    | "RECONCILIATION_REQUIRED"
    | "REFUND_REQUIRED"
    | "PAYMENT_EXPIRED"
    | "FAILED";
  booking: CanonicalBookingDocumentV3 | null;
  idempotentReplay: boolean;
}): CanonicalPaymentVerificationResponse {
  return {
    bookingId: params.bookingId,
    paymentAttemptId: params.paymentAttemptId,
    status: params.status,
    state: params.booking?.state ?? null,
    confirmedAt: params.booking?.lifecycle.paidAt?.toISOString() ?? null,
    payDeadlineAt: params.booking?.lifecycle.payDeadlineAt?.toISOString() ?? null,
    idempotentReplay: params.idempotentReplay,
  };
}

function buildCancellationPreviewResponse(params: {
  bookingId: string;
  preview: ReturnType<typeof buildCanonicalCancellationPreviewV3>;
}): CanonicalBookingCancellationPreviewResponse {
  const decision = params.preview.decision;
  return {
    bookingId: params.bookingId,
    actorType: params.preview.actorType,
    allowed: decision.allowed,
    outcome: decision.outcome,
    timingBand: decision.timingBand,
    refundPercentageBasisPoints: decision.refundPercentageBasisPoints,
    providerShareBasisPoints: decision.providerShareBasisPoints,
    pettxoShareBasisPoints: decision.pettxoShareBasisPoints,
    customerPaidPaise: decision.customerPaidPaise,
    refundableCustomerPaidPaise: decision.refundableCustomerPaidPaise,
    nonRefundableCustomerPaidPaise: decision.nonRefundableCustomerPaidPaise,
    grossCustomerRefundPaise: decision.grossCustomerRefundPaise,
    remainingRefundablePaise: decision.remainingRefundablePaise,
    providerCompensationPaise: decision.providerCompensationPaise,
    pettxoRetainedPaise: decision.retainedCustomerAmountPaise,
    message:
      decision.allowed
        ? "Cancellation preview calculated successfully."
        : decision.reasonCode === "OTP_ALREADY_ENTERED"
        ? "Cancellation is no longer available after OTP verification."
        : decision.reasonCode === "SERVICE_START_REACHED" ||
            decision.reasonCode === "SERVICE_ALREADY_STARTED"
        ? "Cancellation is no longer available after the service start time."
        : "This booking cannot be cancelled in the current state.",
    policyVersion: decision.policyVersion,
  };
}

function buildCancellationResponse(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  cancellation: Record<string, unknown>;
  idempotentReplay: boolean;
}): CanonicalBookingCancellationResponse {
  return {
    bookingId: params.bookingId,
    state: params.booking.state,
    cancellationStatus: asString(params.cancellation.status) || "CANCELLED",
    refundStatus: asString(params.cancellation.refundStatus) || "UNKNOWN",
    refundAmountPaise: asInt(params.cancellation.refundAmountPaise, 0),
    timingBand: asString(params.cancellation.timingBand),
    outcome: asString(params.cancellation.outcome),
    cancelledAt: params.booking.lifecycle.cancelledAt?.toISOString() ?? null,
    idempotentReplay: params.idempotentReplay,
  };
}

function buildBookingStartOtpResponse(
  result: ServiceStartApplyResult,
): CanonicalBookingStartOtpResponse {
  return {
    bookingId: result.bookingId,
    code: result.code,
    state: result.state,
    otpEnteredAt: result.otpEnteredAt?.toISOString() ?? null,
    idempotentReplay: result.idempotentReplay,
    retryAfterMs: result.retryAfterMs,
  };
}

function buildBookingCompletionResponse(params: {
  bookingId: string;
  code: string;
  state: CanonicalBookingDocumentV3["state"] | "";
  idempotentReplay: boolean;
  completedAt: Date | null;
  reviewWindowEndsAt: Date | null;
}): CanonicalBookingCompletionResponse {
  return {
    bookingId: params.bookingId,
    code: params.code,
    state: params.state,
    idempotentReplay: params.idempotentReplay,
    completedAt: params.completedAt?.toISOString() ?? null,
    reviewWindowEndsAt: params.reviewWindowEndsAt?.toISOString() ?? null,
  };
}

function buildBookingReviewResponse(params: {
  bookingId: string;
  code: string;
  state: CanonicalBookingDocumentV3["state"] | "";
  reviewId: string;
  idempotentReplay: boolean;
  submittedAt: Date | null;
}): CanonicalBookingReviewResponse {
  return {
    bookingId: params.bookingId,
    code: params.code,
    state: params.state,
    reviewId: params.reviewId,
    idempotentReplay: params.idempotentReplay,
    submittedAt: params.submittedAt?.toISOString() ?? null,
  };
}

function buildBookingDisputeResponse(params: {
  bookingId: string;
  code: string;
  state: CanonicalBookingDocumentV3["state"] | "";
  disputeId: string;
  idempotentReplay: boolean;
  createdAt: Date | null;
}): CanonicalBookingDisputeResponse {
  return {
    bookingId: params.bookingId,
    code: params.code,
    state: params.state,
    disputeId: params.disputeId,
    idempotentReplay: params.idempotentReplay,
    createdAt: params.createdAt?.toISOString() ?? null,
  };
}

function buildDisputeResolutionResponse(params: {
  bookingId: string;
  disputeId: string;
  resolutionId: string;
  adjustmentId: string;
  refundInstructionId: string;
  payoutId: string;
  resolutionType: string;
  disputeStatus: string;
  payoutStatus: string;
  customerRefundPaise: number;
  providerFinalEntitlementPaise: number;
  pettxoFinalRetainedPaise: number;
  idempotentReplay: boolean;
}): CanonicalDisputeResolutionResponse {
  return {
    bookingId: params.bookingId,
    disputeId: params.disputeId,
    resolutionId: params.resolutionId,
    adjustmentId: params.adjustmentId,
    refundInstructionId: params.refundInstructionId,
    payoutId: params.payoutId,
    resolutionType: params.resolutionType,
    disputeStatus: params.disputeStatus,
    payoutStatus: params.payoutStatus,
    customerRefundPaise: params.customerRefundPaise,
    providerFinalEntitlementPaise:
      params.providerFinalEntitlementPaise,
    pettxoFinalRetainedPaise: params.pettxoFinalRetainedPaise,
    idempotentReplay: params.idempotentReplay,
  };
}

function logRequestEvent(
  event: string,
  payload: Record<string, unknown>,
): void {
  console.info(`bookingV3.${event}`, payload);
}

async function loadClaimedOffer(
  uid: string,
  claimedOfferId: string,
): Promise<Record<string, unknown> | null> {
  const safeId = claimedOfferId.trim();
  if (!safeId) return null;
  const snapshot = await db
    .collection("users")
    .doc(uid)
    .collection("claimedOffers")
    .doc(safeId)
    .get();
  if (!snapshot.exists) {
    throw new HttpsError("failed-precondition", "Coupon is no longer available.", {
      code: "COUPON_INVALID",
    });
  }
  return snapshot.data() as Record<string, unknown>;
}

function ensureCanonicalBooking(data: Record<string, unknown> | undefined): CanonicalBookingDocumentV3 {
  if (!data) {
    throw new HttpsError("not-found", "Booking not found.", {
      code: "BOOKING_NOT_FOUND",
    });
  }
  try {
    return assertValidCanonicalBookingDocumentV3(data);
  } catch (_) {
    throw new HttpsError("failed-precondition", "Booking is not a valid canonical booking.", {
      code: "INVALID_CANONICAL_BOOKING",
    });
  }
}

function writeNotifications(
  transaction: FirebaseFirestore.Transaction,
  notifications: ReadonlyArray<{
    idempotencyKey: string;
    recipientUserId: string;
    type: string;
    title: string;
    body: string;
    data: Record<string, string>;
  }>,
  actorId: string,
): void {
  for (const notification of notifications) {
    const notificationRef = db.collection("notifications").doc(notification.idempotencyKey);
    transaction.set(notificationRef, {
      userId: notification.recipientUserId,
      category: "booking",
      type: notification.type,
      title: notification.title,
      body: notification.body,
      read: false,
      isRead: false,
      actorId,
      bookingId: notification.data.bookingId ?? "",
      serviceId: notification.data.serviceId ?? "",
      data: notification.data,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      source: "canonical_v3",
    }, {merge: true});
  }
}

async function persistNotifications(params: {
  notifications: ReadonlyArray<{
    idempotencyKey: string;
    recipientUserId: string;
    type: string;
    title: string;
    body: string;
    data: Record<string, string>;
  }>;
  actorId: string;
}): Promise<void> {
  if (params.notifications.length === 0) return;
  const batch = db.batch();
  for (const notification of params.notifications) {
    const notificationRef = db.collection("notifications").doc(notification.idempotencyKey);
    batch.set(notificationRef, {
      userId: notification.recipientUserId,
      category: "booking",
      type: notification.type,
      title: notification.title,
      body: notification.body,
      read: false,
      isRead: false,
      actorId: params.actorId,
      bookingId: notification.data.bookingId ?? "",
      serviceId: notification.data.serviceId ?? "",
      data: notification.data,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      source: "canonical_v3",
    }, {merge: true});
  }
  await batch.commit();
}

async function applySchedulerLifecycleMutation(params: {
  bookingRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
  lifecycleResult: {
    code: "UPDATED" | "IDEMPOTENT_REPLAY";
    booking: CanonicalBookingDocumentV3;
    events: ReadonlyArray<{
      eventId: string;
      record: {
        bookingId: string;
        event: string;
        actor: string;
        at: Date;
        meta?: Record<string, unknown>;
        schemaVersion: number;
      };
    }>;
    notifications: ReadonlyArray<{
      idempotencyKey: string;
      recipientUserId: string;
      type: string;
      title: string;
      body: string;
      data: Record<string, string>;
    }>;
  };
}): Promise<boolean> {
  if (params.lifecycleResult.code !== "UPDATED") {
    return false;
  }
  await db.runTransaction(async (transaction) => {
    transaction.set(params.bookingRef, params.lifecycleResult.booking, {merge: false});
    for (const event of params.lifecycleResult.events) {
      transaction.set(
        params.bookingRef.collection("events").doc(event.eventId),
        event.record,
        {merge: false},
      );
    }
    writeNotifications(transaction, params.lifecycleResult.notifications, "system");
  });
  return true;
}

function isPaymentAttemptUncertainOrCaptured(state: string): boolean {
  return [
    "CAPTURE_REPORTED",
    "CONFIRMING",
    "CAPTURED_REQUIRES_RECONCILIATION",
    "REFUND_REQUIRED",
    "REFUND_PENDING",
    "REFUNDED",
    "CONFIRMED",
  ].includes(state);
}

function buildBookingForOrderReady(params: {
  booking: CanonicalBookingDocumentV3;
  paymentAttempt: Record<string, unknown>;
  financials: Record<string, unknown>;
  authoritativeNow: Date;
}): CanonicalBookingDocumentV3 {
  const next = structuredClone(params.booking);
  next.financials = {
    currency: asString(params.financials.currency) || "INR",
    serviceSubtotalPaise: asInt(params.financials.serviceSubtotalPaise, 0),
    couponDiscountPaise: asInt(params.financials.couponDiscountPaise, 0),
    customerPaidPaise: asInt(params.financials.customerPaidPaise, 0),
    platformCommissionRateBasisPoints: asInt(
      params.financials.platformCommissionRateBasisPoints,
      0,
    ),
    platformCommissionPaise: asInt(params.financials.platformCommissionPaise, 0),
    providerPayoutPaise: asInt(params.financials.providerPayoutPaise, 0),
    pettxoCouponFundingPaise: asInt(params.financials.pettxoCouponFundingPaise, 0),
    gatewayFeeSunkPaise: asInt(params.financials.gatewayFeeSunkPaise, 0),
    providerFaultCostPaise: asInt(params.financials.providerFaultCostPaise, 0),
    refundAmountPaise: asInt(params.financials.refundAmountPaise, 0),
    pettxoNetBeforeGatewayPaise: asInt(
      params.financials.pettxoNetBeforeGatewayPaise,
      0,
    ),
    pricingVersion: 1 as const,
  };
  next.updatedAt = new Date(params.authoritativeNow.getTime());
  next.audit.lastUpdatedBy = "parent";
  next.lifecycle.paymentStartedAt =
    next.lifecycle.paymentStartedAt ?? new Date(params.authoritativeNow.getTime());
  next.payment.status = asString(params.paymentAttempt.state) || "ORDER_CREATED";
  next.payment.paymentAttemptId = asString(params.paymentAttempt.paymentAttemptId);
  next.payment.razorpayOrderId = asString(params.paymentAttempt.razorpayOrderId);
  next.payment.orderCreatedAt =
    asNullableDate(params.paymentAttempt.orderCreatedAt) ??
    new Date(params.authoritativeNow.getTime());
  next.payment.paymentStartedAt =
    asNullableDate(params.paymentAttempt.checkoutOpenedAt) ??
    next.lifecycle.paymentStartedAt;
  next.payment.failureCode = "";
  next.payment.failureMessage = "";
  return next;
}

async function authorizeCanonicalBookingCommand(params: {
  bookingId: string;
  authenticatedUserId: string;
  expectedActor: "parent" | "provider" | "system";
  allowedStates: CanonicalBookingDocumentV3["state"][];
  operation: "continuation" | "provider_actions" | "schedulers";
  now: Date;
}): Promise<AuthorizedCanonicalCommandContext> {
  const bookingRef = db.collection("bookings").doc(params.bookingId);
  const bookingSnapshot = await bookingRef.get();
  if (!bookingSnapshot.exists) {
    throw new HttpsError("not-found", "Booking not found.", {
      code: "BOOKING_NOT_FOUND",
    });
  }
  const booking = ensureCanonicalBooking(bookingSnapshot.data());
  if (!params.allowedStates.includes(booking.state)) {
    throw new HttpsError("failed-precondition", "Booking is not in a valid state for this action.", {
      code: "INVALID_BOOKING_STATE",
      state: booking.state,
    });
  }
  if (params.expectedActor === "parent" && booking.parentId !== params.authenticatedUserId) {
    throw new HttpsError("permission-denied", "Only the booking parent can perform this action.", {
      code: "ACTOR_NOT_AUTHORIZED",
    });
  }
  if (params.expectedActor === "provider" && booking.providerId !== params.authenticatedUserId) {
    throw new HttpsError("permission-denied", "Only the assigned provider can perform this action.", {
      code: "ACTOR_NOT_AUTHORIZED",
    });
  }

  const liveService = await loadServiceSnapshot(booking.serviceId);
  const authorization = CANONICAL_BOOKING_AUTHORIZATION;
  return {
    bookingRef,
    booking,
    service: liveService,
    authorization,
  };
}

async function authorizeCanonicalPaymentCommand(params: {
  bookingId: string;
  paymentAttemptId?: string;
  authenticatedUserId: string;
  command: "create_order" | "verify";
  now: Date;
}): Promise<AuthorizedCanonicalPaymentCommandContext> {
  const bookingRef = db.collection("bookings").doc(params.bookingId);
  const bookingSnapshot = await bookingRef.get();
  if (!bookingSnapshot.exists) {
    throw new HttpsError("not-found", "Booking not found.", {
      code: "BOOKING_NOT_FOUND",
    });
  }
  const booking = ensureCanonicalBooking(bookingSnapshot.data());
  if (booking.parentId !== params.authenticatedUserId) {
    throw new HttpsError(
      "permission-denied",
      "Only the booking parent can perform this action.",
      {code: "ACTOR_NOT_AUTHORIZED"},
    );
  }

  const paymentAttemptId = params.paymentAttemptId?.trim() ?? "";
  const paymentAttemptRef = paymentAttemptId
    ? bookingRef.collection("paymentAttempts").doc(paymentAttemptId)
    : null;
  const paymentAttemptSnapshot = paymentAttemptRef
    ? await paymentAttemptRef.get()
    : null;
  const paymentAttempt = paymentAttemptSnapshot?.exists
    ? (paymentAttemptSnapshot.data() as Record<string, unknown>)
    : null;
  const paymentAttemptState = asString(paymentAttempt?.state).toUpperCase();

  const liveService = await loadServiceSnapshot(booking.serviceId);
  if (!liveService) {
    throw new HttpsError("failed-precondition", "Service is no longer available.", {
      code: "SERVICE_UNAVAILABLE",
    });
  }

  const requiresContinuationOnly =
    booking.state === "CONFIRMED" ||
    [
      "CAPTURE_REPORTED",
      "CAPTURED_REQUIRES_RECONCILIATION",
      "REFUND_REQUIRED",
      "REFUND_PENDING",
      "REFUNDED",
      "CONFIRMED",
    ].includes(paymentAttemptState);
  const operation =
    params.command === "create_order" || !requiresContinuationOnly
      ? "payment"
      : "continuation";
  void operation;
  const authorization = CANONICAL_BOOKING_AUTHORIZATION;

  if (params.command === "create_order") {
    if (booking.state !== "ACCEPTED_AWAITING_PAYMENT") {
      throw new HttpsError("failed-precondition", "Booking is not awaiting payment.", {
        code: "BOOKING_NOT_PAYABLE",
      });
    }
    const payDeadlineAt = booking.lifecycle.payDeadlineAt;
    if (!payDeadlineAt || payDeadlineAt.getTime() < params.now.getTime()) {
      throw new HttpsError("failed-precondition", "The payment window has expired.", {
        code: "PAYMENT_WINDOW_EXPIRED",
      });
    }
  }

  if (params.command === "verify") {
    if (!paymentAttemptId) {
      throw new HttpsError("invalid-argument", "paymentAttemptId is required.", {
        code: "PAYMENT_ATTEMPT_CONFLICT",
      });
    }
    if (paymentAttempt && asString(paymentAttempt.parentId) !== booking.parentId) {
      throw new HttpsError("permission-denied", "Payment attempt does not belong to this parent.", {
        code: "ACTOR_NOT_AUTHORIZED",
      });
    }
  }

  return {
    bookingRef,
    booking,
    service: liveService,
    authorization,
    paymentAttemptRef,
    paymentAttempt,
    paymentAttemptState,
  };
}

export const createBookingRequestV3 = onCall({invoker: "private"}, async (request) => {
  const authoritativeNow = new Date();
  const uid = requireUid(request.auth);
  const parsed = parseCanonicalRequestInput(request.data);
  logRequestEvent("request_callable_invoked", {
    userId: uid,
    serviceId: parsed.serviceId,
    requestAttemptId: parsed.requestAttemptId,
    bookingType: parsed.bookingType,
  });

  const [service, parent] = await Promise.all([
    loadServiceSnapshot(parsed.serviceId),
    buildParentIdentity(uid),
  ]);
  if (!service) {
    throw new HttpsError("not-found", "Service not found.", {
      code: "SERVICE_NOT_FOUND",
    });
  }

  const authoritativeBookingType = inferBookingType(service);
  if (authoritativeBookingType !== parsed.bookingType) {
    throw new HttpsError("invalid-argument", "bookingType does not match the authoritative service.", {
      code: "INVALID_BOOKING_TYPE",
    });
  }

  const authorization = requireCanonicalGate({
    uid,
    serviceId: parsed.serviceId,
    bookingType: parsed.bookingType,
    service,
    now: authoritativeNow,
  });

  const canonicalService = buildCanonicalServiceSource({
    ...service,
    id: parsed.serviceId,
  });
  const schedule =
    parsed.bookingType === "SLOT" ?
      await buildAuthoritativeSlotSelection({
        serviceId: parsed.serviceId,
        providerId: canonicalService.ownerUserId,
        slotIds: parsed.slotRequest?.slotIds ?? [],
        unitPricePaise: Math.max(asInt(service.pricePerSession, 0) * 100, 0),
      }) :
      buildAuthoritativeRangeSelection({
        service,
        rangeRequest: parsed.rangeRequest!,
      });

  const bookingRef = db.collection("bookings").doc();
  const attemptRef = db
    .collection("userPrivate")
    .doc(uid)
    .collection("bookingRequestAttempts")
    .doc(parsed.requestAttemptId);

  const result = await db.runTransaction(async (transaction) => {
    const existingAttemptSnapshot = await transaction.get(attemptRef);
    const existingAttempt = parseExistingAttempt(existingAttemptSnapshot.data());
    const createResult = createBookingRequestApplicationV3({
      parent,
      service: canonicalService,
      input: {
        requestAttemptId: parsed.requestAttemptId,
        serviceId: parsed.serviceId,
        bookingType: parsed.bookingType,
        schedule,
      },
      authoritativeNow,
      generatedBookingId: existingAttempt?.bookingId || bookingRef.id,
      existingAttempt,
    });

    if (!createResult.ok) {
      logRequestEvent("request_validation_failed", {
        userId: uid,
        serviceId: parsed.serviceId,
        requestAttemptId: parsed.requestAttemptId,
        bookingType: parsed.bookingType,
        code: createResult.code,
      });
      throw new HttpsError(
        createResult.code === "SERVICE_NOT_FOUND" ? "not-found" : "failed-precondition",
        createResult.message,
        {code: createResult.code, issues: createResult.issues ?? []},
      );
    }

    if (createResult.code === "CREATED") {
      const canonicalBookingRef = db.collection("bookings").doc(createResult.bookingId);
      transaction.set(canonicalBookingRef, createResult.booking, {merge: false});
      transaction.set(attemptRef, serializeAttemptRecord(createResult.attemptRecord), {merge: true});
      for (const event of createResult.events) {
        transaction.set(
          canonicalBookingRef.collection("events").doc(event.eventId),
          {
            bookingId: event.record.bookingId,
            event: event.record.event,
            actor: event.record.actor,
            at: event.record.at,
            meta: event.record.meta,
            schemaVersion: event.record.schemaVersion,
          },
          {merge: false},
        );
      }
    }

    return createResult;
  });

  if (result.code === "IDEMPOTENT_REPLAY") {
    logRequestEvent("idempotent_request_replay", {
      userId: uid,
      serviceId: parsed.serviceId,
      requestAttemptId: parsed.requestAttemptId,
      bookingId: result.bookingId,
      matchedRule: authorization.metadata.matchedRule,
    });
  } else {
    logRequestEvent("request_created", {
      userId: uid,
      serviceId: parsed.serviceId,
      requestAttemptId: parsed.requestAttemptId,
      bookingId: result.bookingId,
      state: result.booking.state,
      wasQueuedOutsideWorkingHours:
        result.booking.lifecycle.wasQueuedOutsideWorkingHours,
      matchedRule: authorization.metadata.matchedRule,
    });
  }

  return buildRequestResponse(
    result.bookingId,
    result.booking,
    result.code === "IDEMPOTENT_REPLAY",
  );
});

export const markBookingViewedByProviderV3 = onCall({invoker: "private"}, async (request) => {
  const authoritativeNow = new Date();
  const uid = requireUid(request.auth);
  const bookingId = asString(request.data?.bookingId);
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }
  const authorized = await authorizeCanonicalBookingCommand({
    bookingId,
    authenticatedUserId: uid,
    expectedActor: "provider",
    allowedStates: ["REQUESTED", "PENDING_PROVIDER", "ACCEPTED_AWAITING_PAYMENT"],
    operation: "provider_actions",
    now: authoritativeNow,
  });

  const result = await db.runTransaction(async (transaction) => {
    const currentSnapshot = await transaction.get(authorized.bookingRef);
    const booking = ensureCanonicalBooking(currentSnapshot.data());
    const lifecycleResult = markBookingViewedByProviderApplicationV3({
      bookingId,
      booking,
      providerUid: uid,
      authoritativeNow,
    });
    if (!lifecycleResult.ok) {
      throw new HttpsError("failed-precondition", lifecycleResult.message, {
        code: lifecycleResult.code,
      });
    }
    if (lifecycleResult.code === "UPDATED") {
      transaction.set(authorized.bookingRef, lifecycleResult.booking, {merge: false});
      for (const event of lifecycleResult.events) {
        transaction.set(
          authorized.bookingRef.collection("events").doc(event.eventId),
          event.record,
          {merge: false},
        );
      }
    }
    return lifecycleResult;
  });

  return buildCommandResponse(
    bookingId,
    result.booking,
    result.code === "IDEMPOTENT_REPLAY",
  );
});

export const acceptBookingRequestV3 = onCall({invoker: "private"}, async (request) => {
  const authoritativeNow = new Date();
  const uid = requireUid(request.auth);
  const bookingId = asString(request.data?.bookingId);
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }
  const authorized = await authorizeCanonicalBookingCommand({
    bookingId,
    authenticatedUserId: uid,
    expectedActor: "provider",
    allowedStates: ["PENDING_PROVIDER"],
    operation: "provider_actions",
    now: authoritativeNow,
  });
  if (!authorized.service) {
    throw new HttpsError("failed-precondition", "Service is no longer available.", {
      code: "SERVICE_UNAVAILABLE",
    });
  }

  const result = await db.runTransaction(async (transaction) => {
    const currentSnapshot = await transaction.get(authorized.bookingRef);
    const booking = ensureCanonicalBooking(currentSnapshot.data());
    const lifecycleResult = acceptBookingRequestApplicationV3({
      bookingId,
      booking,
      providerUid: uid,
      authoritativeNow,
      existingProviderStats: emptyProviderStatsV3(),
    });
    if (!lifecycleResult.ok) {
      throw new HttpsError("failed-precondition", lifecycleResult.message, {
        code: lifecycleResult.code,
      });
    }
    if (lifecycleResult.code === "UPDATED") {
      transaction.set(authorized.bookingRef, lifecycleResult.booking, {merge: false});
      for (const event of lifecycleResult.events) {
        transaction.set(
          authorized.bookingRef.collection("events").doc(event.eventId),
          event.record,
          {merge: false},
        );
      }
      writeNotifications(transaction, lifecycleResult.notifications, uid);
    }
    return lifecycleResult;
  });

  return buildCommandResponse(
    bookingId,
    result.booking,
    result.code === "IDEMPOTENT_REPLAY",
  );
});

export const declineBookingRequestV3 = onCall({invoker: "private"}, async (request) => {
  const authoritativeNow = new Date();
  const uid = requireUid(request.auth);
  const bookingId = asString(request.data?.bookingId);
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }
  const authorized = await authorizeCanonicalBookingCommand({
    bookingId,
    authenticatedUserId: uid,
    expectedActor: "provider",
    allowedStates: ["PENDING_PROVIDER"],
    operation: "provider_actions",
    now: authoritativeNow,
  });

  const result = await db.runTransaction(async (transaction) => {
    const currentSnapshot = await transaction.get(authorized.bookingRef);
    const booking = ensureCanonicalBooking(currentSnapshot.data());
    const lifecycleResult = declineBookingRequestApplicationV3({
      bookingId,
      booking,
      providerUid: uid,
      authoritativeNow,
      existingProviderStats: emptyProviderStatsV3(),
    });
    if (!lifecycleResult.ok) {
      throw new HttpsError("failed-precondition", lifecycleResult.message, {
        code: lifecycleResult.code,
      });
    }
    if (lifecycleResult.code === "UPDATED") {
      transaction.set(authorized.bookingRef, lifecycleResult.booking, {merge: false});
      for (const event of lifecycleResult.events) {
        transaction.set(
          authorized.bookingRef.collection("events").doc(event.eventId),
          event.record,
          {merge: false},
        );
      }
      writeNotifications(transaction, lifecycleResult.notifications, uid);
    }
    return lifecycleResult;
  });

  return buildCommandResponse(
    bookingId,
    result.booking,
    result.code === "IDEMPOTENT_REPLAY",
  );
});

export const cancelBookingRequestByParentV3 = onCall({invoker: "private"}, async (request) => {
  const authoritativeNow = new Date();
  const uid = requireUid(request.auth);
  const bookingId = asString(request.data?.bookingId);
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }
  const authorized = await authorizeCanonicalBookingCommand({
    bookingId,
    authenticatedUserId: uid,
    expectedActor: "parent",
    allowedStates: ["REQUESTED", "PENDING_PROVIDER"],
    operation: "continuation",
    now: authoritativeNow,
  });

  const result = await db.runTransaction(async (transaction) => {
    const currentSnapshot = await transaction.get(authorized.bookingRef);
    const booking = ensureCanonicalBooking(currentSnapshot.data());
    const lifecycleResult = cancelBookingRequestByParentApplicationV3({
      bookingId,
      booking,
      parentUid: uid,
      authoritativeNow,
    });
    if (!lifecycleResult.ok) {
      throw new HttpsError("failed-precondition", lifecycleResult.message, {
        code: lifecycleResult.code,
      });
    }
    if (lifecycleResult.code === "UPDATED") {
      transaction.set(authorized.bookingRef, lifecycleResult.booking, {merge: false});
      for (const event of lifecycleResult.events) {
        transaction.set(
          authorized.bookingRef.collection("events").doc(event.eventId),
          event.record,
          {merge: false},
        );
      }
      writeNotifications(transaction, lifecycleResult.notifications, uid);
    }
    return lifecycleResult;
  });

  return buildCommandResponse(
    bookingId,
    result.booking,
    result.code === "IDEMPOTENT_REPLAY",
  );
});

export const razorpayWebhook = onRequest({
  invoker: "public",
  secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET, RAZORPAY_WEBHOOK_SECRET],
}, async (request, response) => {
  if (request.method !== "POST") {
    response.status(405).send("Method not allowed");
    return;
  }

  try {
    const result = await processRazorpayWebhookEnvelopeV3({
      firestore: db,
      signature: asString(request.header("x-razorpay-signature")),
      rawBody: request.rawBody as Buffer | undefined,
      payload:
        typeof request.body === "object" && request.body != null ?
          request.body as Record<string, unknown> :
          {},
      webhookSecret: asString(RAZORPAY_WEBHOOK_SECRET.value()),
      keyId: asString(RAZORPAY_KEY_ID.value()),
      keySecret: asString(RAZORPAY_KEY_SECRET.value()),
      routeCanonicalWebhook: routeCanonicalWebhookEventV3,
    });
    response.status(result.statusCode).send(result.responseBody);
  } catch (error) {
    console.error("razorpayWebhookV3.error", error);
    response.status(500).send("error");
  }
});

export const createRazorpayPaymentOrderV3 = onCall({
  invoker: "private",
  secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET],
}, async (request) => {
  const authoritativeNow = new Date();
  const uid = requireUid(request.auth);
  const bookingId = asString(request.data?.bookingId);
  const paymentAttemptId = asString(request.data?.paymentAttemptId);
  const claimedOfferId = asString(request.data?.claimedOfferId);
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }

  const authorized = await authorizeCanonicalPaymentCommand({
    bookingId,
    paymentAttemptId,
    authenticatedUserId: uid,
    command: "create_order",
    now: authoritativeNow,
  });
  const canonicalService = buildCanonicalServiceSource({
    ...(authorized.service ?? {}),
    id: bookingId ? authorized.booking.serviceId : "",
  });
  const parent = await buildParentIdentity(uid);
  const claimedOffer = await loadClaimedOffer(uid, claimedOfferId);

  if (authorized.paymentAttempt &&
    ["ORDER_CREATED", "CHECKOUT_OPENED", "CONFIRMED"].includes(
      authorized.paymentAttemptState,
    )) {
    if (authorized.paymentAttemptState === "CONFIRMED" ||
      authorized.booking.state === "CONFIRMED") {
      return buildPaymentOrderResponse({
        bookingId,
        booking: authorized.booking,
        paymentAttemptId:
          paymentAttemptId || asString(authorized.paymentAttempt.paymentAttemptId),
        paymentAttempt: authorized.paymentAttempt,
        mode: asInt(authorized.paymentAttempt.amountPaise, 0) > 0 ?
          "razorpay" :
          "zero_payable",
        idempotentReplay: true,
      });
    }
    return buildPaymentOrderResponse({
      bookingId,
      booking: authorized.booking,
      paymentAttemptId:
        paymentAttemptId || asString(authorized.paymentAttempt.paymentAttemptId),
      paymentAttempt: authorized.paymentAttempt,
      mode: "razorpay",
      keyId: "",
      razorpayOrderId: asString(authorized.paymentAttempt.razorpayOrderId),
      amountPaise: asInt(authorized.paymentAttempt.amountPaise, 0),
      currency: asString(authorized.paymentAttempt.currency) || "INR",
      expiresAt: asNullableDate(authorized.paymentAttempt.orderExpiresAt),
      idempotentReplay: true,
    });
  }

  const keyId = asString(RAZORPAY_KEY_ID.value());
  const keySecret = asString(RAZORPAY_KEY_SECRET.value());
  const createResult = await createRazorpayPaymentOrderApplicationV3({
    firestore: db,
    bookingId,
    parentId: uid,
    parent,
    service: canonicalService,
    booking: authorized.booking,
    claimedOffer: claimedOffer ?? undefined,
    authoritativeNow,
    keyId,
    keySecret,
    paymentAttemptId: paymentAttemptId || undefined,
  });

  if (!createResult.ok) {
    throw new HttpsError("failed-precondition", createResult.message, {
      code: createResult.code,
    });
  }

  if (createResult.code === "ZERO_PAYABLE_CONFIRMED") {
    const finalizeResult = createResult.finalizeResult;
    await persistFinalizePaymentResultV3({
      firestore: db,
      result: finalizeResult,
      bookingId,
    });
    await persistNotifications({
      notifications: finalizeResult.notifications,
      actorId: uid,
    });
    if (!finalizeResult.ok) {
      throw new HttpsError("failed-precondition", finalizeResult.message, {
        code: finalizeResult.code,
      });
    }
    logRequestEvent("payment_zero_payable_confirmed", {
      bookingId,
      paymentAttemptId: finalizeResult.paymentAttempt.paymentAttemptId,
      state: finalizeResult.booking.state,
      matchedRule: authorized.authorization.metadata.matchedRule,
    });
    return buildPaymentOrderResponse({
      bookingId,
      booking: finalizeResult.booking,
      paymentAttemptId: finalizeResult.paymentAttempt.paymentAttemptId,
      paymentAttempt: finalizeResult.paymentAttempt,
      mode: "zero_payable",
      idempotentReplay: finalizeResult.code === "IDEMPOTENT_REPLAY",
    });
  }

  const updatedBooking = buildBookingForOrderReady({
    booking: authorized.booking,
    paymentAttempt: createResult.paymentAttempt as unknown as Record<string, unknown>,
    financials: createResult.paymentAttempt.pricingSnapshot
      .financials as Record<string, unknown>,
    authoritativeNow,
  });
  await db.runTransaction(async (transaction) => {
    transaction.set(authorized.bookingRef, updatedBooking, {merge: false});
    transaction.set(
      authorized.bookingRef
        .collection("paymentAttempts")
        .doc(createResult.paymentAttempt.paymentAttemptId),
      createResult.paymentAttempt,
      {merge: false},
    );
    transaction.create(
      canonicalPaymentOrderMappingRef(db, createResult.order.razorpayOrderId),
      {
        bookingId,
        paymentAttemptId: createResult.paymentAttempt.paymentAttemptId,
        schemaVersion: 1,
        bookingModelVersion: updatedBooking.bookingModelVersion,
        createdAt: Timestamp.fromDate(authoritativeNow),
      },
    );
    for (const event of createResult.events) {
      transaction.set(
        authorized.bookingRef.collection("events").doc(event.eventId),
        event.record,
        {merge: false},
      );
    }
  });
  await persistNotifications({
    notifications: createResult.notifications,
    actorId: uid,
  });
  logRequestEvent("payment_order_requested", {
    bookingId,
    paymentAttemptId: createResult.paymentAttempt.paymentAttemptId,
    razorpayOrderId: createResult.order.razorpayOrderId,
    amountPaise: createResult.order.amountPaise,
    matchedRule: authorized.authorization.metadata.matchedRule,
  });
  return buildPaymentOrderResponse({
    bookingId,
    booking: updatedBooking,
    paymentAttemptId: createResult.paymentAttempt.paymentAttemptId,
    paymentAttempt: createResult.paymentAttempt as unknown as Record<string, unknown>,
    mode: "razorpay",
    keyId: createResult.order.keyId,
    razorpayOrderId: createResult.order.razorpayOrderId,
    amountPaise: createResult.order.amountPaise,
    currency: createResult.order.currency,
    expiresAt: createResult.order.paymentExpiresAt,
    idempotentReplay: false,
  });
});

export const verifyBookingPaymentV3 = onCall({
  invoker: "private",
  secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET],
}, async (request) => {
  const authoritativeNow = new Date();
  const uid = requireUid(request.auth);
  const bookingId = asString(request.data?.bookingId);
  const paymentAttemptId = asString(request.data?.paymentAttemptId);
  const razorpayOrderId = asString(request.data?.razorpay_order_id);
  const razorpayPaymentId = asString(request.data?.razorpay_payment_id);
  const razorpaySignature = asString(request.data?.razorpay_signature);
  if (!bookingId || !paymentAttemptId || !razorpayOrderId || !razorpayPaymentId || !razorpaySignature) {
    throw new HttpsError("invalid-argument", "Booking and Razorpay payment fields are required.");
  }

  const authorized = await authorizeCanonicalPaymentCommand({
    bookingId,
    paymentAttemptId,
    authenticatedUserId: uid,
    command: "verify",
    now: authoritativeNow,
  });

  if (authorized.booking.state === "CONFIRMED" || authorized.paymentAttemptState === "CONFIRMED") {
    return buildPaymentVerificationResponse({
      bookingId,
      paymentAttemptId,
      status: "CONFIRMED",
      booking: authorized.booking,
      idempotentReplay: true,
    });
  }

  const keySecret = asString(RAZORPAY_KEY_SECRET.value());
  if (!verifyRazorpayPaymentSignature({
    keySecret,
    orderId: razorpayOrderId,
    paymentId: razorpayPaymentId,
    signature: razorpaySignature,
  })) {
    throw new HttpsError("permission-denied", "Payment signature verification failed.", {
      code: "PAYMENT_ATTEMPT_CONFLICT",
    });
  }

  try {
    const result = await verifyCapturedBookingPaymentV3({
      firestore: db,
      bookingId,
      paymentAttemptId,
      verificationSource: "callable",
      keyId: asString(RAZORPAY_KEY_ID.value()),
      keySecret,
      razorpayOrderId,
      razorpayPaymentId,
      authoritativeNow,
    });
    await persistNotifications({
      notifications: result.notifications,
      actorId: uid,
    });
    if (result.ok) {
      return buildPaymentVerificationResponse({
        bookingId,
        paymentAttemptId,
        status: "CONFIRMED",
        booking: result.booking,
        idempotentReplay: result.code === "IDEMPOTENT_REPLAY",
      });
    }
    return buildPaymentVerificationResponse({
      bookingId,
      paymentAttemptId,
      status: result.paymentAttempt.state === "REFUND_REQUIRED" ? "REFUND_REQUIRED" : "PAYMENT_EXPIRED",
      booking: result.booking,
      idempotentReplay: false,
    });
  } catch (error) {
    const message = error instanceof HttpsError ? error.message : String(error);
    if (authorized.paymentAttemptRef &&
      message.toLowerCase().includes("not captured yet")) {
      await authorized.paymentAttemptRef.set({
        razorpayOrderId,
        razorpayPaymentId,
        state: "CAPTURED_REQUIRES_RECONCILIATION",
        captureReportedAt: FieldValue.serverTimestamp(),
        verificationSource: "callable",
        retryCount: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      return buildPaymentVerificationResponse({
        bookingId,
        paymentAttemptId,
        status: "RECONCILIATION_REQUIRED",
        booking: authorized.booking,
        idempotentReplay: false,
      });
    }
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", "We could not verify the booking payment right now.", {
      code: "UNKNOWN",
    });
  }
});

async function loadCanonicalCancellationContext(params: {
  bookingId: string;
  paymentAttemptId: string;
}): Promise<{
  paymentAttemptRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
  paymentAttempt: CanonicalPaymentAttemptDocumentV3;
  cancellationRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
  cancellation: Record<string, unknown> | null;
  refund: Record<string, unknown> | null;
  bookingPrivate: Record<string, unknown> | null;
  bookingChat: Record<string, unknown> | null;
}> {
  const paymentAttemptRef = db
    .collection("bookings")
    .doc(params.bookingId)
    .collection("paymentAttempts")
    .doc(params.paymentAttemptId);
  const cancellationRef = db
    .collection(BOOKING_CANCELLATION_COLLECTION)
    .doc(params.bookingId);
  const [attemptSnapshot, cancellationSnapshot, refundSnapshot, privateSnapshot, chatSnapshot] =
    await Promise.all([
      paymentAttemptRef.get(),
      cancellationRef.get(),
      db.collection("refunds").doc(params.bookingId).get(),
      db.collection("bookingPrivate").doc(params.bookingId).get(),
      db.collection("bookingChats").doc(params.bookingId).get(),
    ]);
  if (!attemptSnapshot.exists) {
    throw new HttpsError("failed-precondition", "Canonical payment attempt is missing.", {
      code: "PAYMENT_ATTEMPT_NOT_FOUND",
    });
  }
  return {
    paymentAttemptRef,
    paymentAttempt: attemptSnapshot.data() as CanonicalPaymentAttemptDocumentV3,
    cancellationRef,
    cancellation: cancellationSnapshot.exists
      ? (cancellationSnapshot.data() as Record<string, unknown>)
      : null,
    refund: refundSnapshot.exists
      ? (refundSnapshot.data() as Record<string, unknown>)
      : null,
    bookingPrivate: privateSnapshot.exists
      ? (privateSnapshot.data() as Record<string, unknown>)
      : null,
    bookingChat: chatSnapshot.exists
      ? (chatSnapshot.data() as Record<string, unknown>)
      : null,
  };
}

function cancellationActorTypeForExpectedActor(
  actor: "parent" | "provider" | "system",
): CancellationActorType {
  if (actor === "parent") return "CUSTOMER";
  if (actor === "provider") return "PROVIDER";
  return "ADMIN";
}

export const previewBookingCancellationV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const authoritativeNow = new Date();
    const uid = requireUid(request.auth);
    const bookingId = asString(request.data?.bookingId);
    const actorHint = asString(request.data?.actorType).toUpperCase();
    if (!bookingId) {
      throw new HttpsError("invalid-argument", "bookingId is required.");
    }

    const bookingRef = db.collection("bookings").doc(bookingId);
    const bookingSnapshot = await bookingRef.get();
    if (!bookingSnapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.", {
        code: "BOOKING_NOT_FOUND",
      });
    }
    const booking = ensureCanonicalBooking(bookingSnapshot.data());
    const expectedActor =
      booking.parentId === uid ? "parent" : booking.providerId === uid ? "provider" : null;
    if (!expectedActor) {
      throw new HttpsError("permission-denied", "Only booking participants can preview cancellation.", {
        code: "ACTOR_NOT_AUTHORIZED",
      });
    }
    if (actorHint && actorHint !== cancellationActorTypeForExpectedActor(expectedActor)) {
      throw new HttpsError("permission-denied", "Cancellation actor mismatch.", {
        code: "ACTOR_NOT_AUTHORIZED",
      });
    }
    const authorized = await authorizeCanonicalBookingCommand({
      bookingId,
      authenticatedUserId: uid,
      expectedActor,
      allowedStates: ["CONFIRMED", "CANCELLED"],
      operation: "continuation",
      now: authoritativeNow,
    });
    const paymentAttemptId = asString(authorized.booking.payment.paymentAttemptId);
    if (!paymentAttemptId) {
      throw new HttpsError("failed-precondition", "Canonical payment attempt is missing.", {
        code: "PAYMENT_ATTEMPT_NOT_FOUND",
      });
    }
    const loaded = await loadCanonicalCancellationContext({
      bookingId,
      paymentAttemptId,
    });
    const preview = buildCanonicalCancellationPreviewV3({
      bookingId,
      booking: authorized.booking,
      actorType: cancellationActorTypeForExpectedActor(expectedActor),
      requestedAt: authoritativeNow,
      existingRefund: loaded.refund,
    });
    return buildCancellationPreviewResponse({bookingId, preview});
  },
);

async function cancelConfirmedBookingInternal(params: {
  request: CallableRequest<unknown>;
  expectedActor: "parent" | "provider";
}) {
  const authoritativeNow = new Date();
  const uid = requireUid(params.request.auth);
  const data =
    typeof params.request.data === "object" && params.request.data != null
      ? (params.request.data as Record<string, unknown>)
      : {};
  const bookingId = asString(data.bookingId);
  const reasonCode = asString(data.reasonCode);
  const reasonText = asString(data.reasonText);
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }
  const authorized = await authorizeCanonicalBookingCommand({
    bookingId,
    authenticatedUserId: uid,
    expectedActor: params.expectedActor,
    allowedStates: ["CONFIRMED", "CANCELLED"],
    operation: "continuation",
    now: authoritativeNow,
  });
  const paymentAttemptId = asString(authorized.booking.payment.paymentAttemptId);
  if (!paymentAttemptId) {
    throw new HttpsError("failed-precondition", "Canonical payment attempt is missing.", {
      code: "PAYMENT_ATTEMPT_NOT_FOUND",
    });
  }
  const result = await db.runTransaction(async (transaction) => {
    const currentBookingSnapshot = await transaction.get(authorized.bookingRef);
    const currentBooking = ensureCanonicalBooking(currentBookingSnapshot.data());
    const cancellationRef = db.collection(BOOKING_CANCELLATION_COLLECTION).doc(bookingId);
    const [
      attemptSnapshot,
      cancellationSnapshot,
      refundSnapshot,
      bookingPrivateSnapshot,
      bookingChatSnapshot,
    ] = await Promise.all([
      transaction.get(
        authorized.bookingRef.collection("paymentAttempts").doc(paymentAttemptId),
      ),
      transaction.get(cancellationRef),
      transaction.get(db.collection("refunds").doc(bookingId)),
      transaction.get(db.collection("bookingPrivate").doc(bookingId)),
      transaction.get(db.collection("bookingChats").doc(bookingId)),
    ]);
    if (!attemptSnapshot.exists) {
      throw new HttpsError("failed-precondition", "Canonical payment attempt is missing.", {
        code: "PAYMENT_ATTEMPT_NOT_FOUND",
      });
    }
    const loadedCapacity = await loadCapacityStateForCancellationV3({
      firestore: db,
      transaction,
      bookingId,
      booking: currentBooking,
    });
    const cancellationResult = applyConfirmedBookingCancellationV3({
      bookingId,
      booking: currentBooking,
      paymentAttempt: attemptSnapshot.data() as CanonicalPaymentAttemptDocumentV3,
      actorType: cancellationActorTypeForExpectedActor(params.expectedActor),
      actorId: uid,
      reasonCode,
      reasonText,
      authoritativeNow,
      existingRefund: refundSnapshot.exists
        ? (refundSnapshot.data() as Record<string, unknown>)
        : null,
      existingCancellation: cancellationSnapshot.exists
        ? (cancellationSnapshot.data() as Record<string, unknown>)
        : null,
      existingReleaseRecord: loadedCapacity.existingReleaseRecord,
      existingSlotOccupancy: loadedCapacity.slotOccupancy,
      existingRangeOccupancy: loadedCapacity.rangeOccupancy,
      existingBookingPrivate: bookingPrivateSnapshot.exists
        ? (bookingPrivateSnapshot.data() as Record<string, unknown>)
        : null,
      existingBookingChat: bookingChatSnapshot.exists
        ? (bookingChatSnapshot.data() as Record<string, unknown>)
        : null,
    });
    writeConfirmedBookingCancellationTransactionV3({
      firestore: db,
      transaction,
      bookingId,
      result: cancellationResult,
    });
    return cancellationResult;
  });

  logRequestEvent("booking_cancelled", {
    bookingId,
    actor: params.expectedActor,
    refundStatus: result.cancellationRecord.refundStatus,
    refundAmountPaise: result.cancellationRecord.refundAmountPaise,
    idempotentReplay: result.idempotentReplay,
  });
  return buildCancellationResponse({
    bookingId,
    booking: result.booking,
    cancellation: result.cancellationRecord,
    idempotentReplay: result.idempotentReplay,
  });
}

export const cancelConfirmedBookingByCustomerV3 = onCall(
  {invoker: "private"},
  async (request) => cancelConfirmedBookingInternal({request, expectedActor: "parent"}),
);

export const cancelConfirmedBookingByProviderV3 = onCall(
  {invoker: "private"},
  async (request) => cancelConfirmedBookingInternal({request, expectedActor: "provider"}),
);

export const verifyBookingStartOtpV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const authoritativeNow = new Date();
    const uid = requireUid(request.auth);
    const data =
      typeof request.data === "object" && request.data != null
        ? (request.data as Record<string, unknown>)
        : {};
    const bookingId = asString(data.bookingId);
    const otpCandidate = asString(data.otp);
    const requestAttemptId = asString(data.requestAttemptId);
    if (!bookingId) {
      throw new HttpsError("invalid-argument", "bookingId is required.");
    }
    if (!otpCandidate) {
      throw new HttpsError("invalid-argument", "otp is required.");
    }
    if (!requestAttemptId) {
      throw new HttpsError("invalid-argument", "requestAttemptId is required.");
    }

    await authorizeCanonicalBookingCommand({
      bookingId,
      authenticatedUserId: uid,
      expectedActor: "provider",
      allowedStates: ["CONFIRMED", "IN_PROGRESS", "CANCELLED"],
      operation: "continuation",
      now: authoritativeNow,
    });

    const result = await verifyBookingStartOtpApplicationV3({
      firestore: db,
      bookingId,
      providerId: uid,
      otpCandidate,
      requestAttemptId,
      authoritativeNow,
    });

    if (result.code === "UNAUTHORIZED") {
      throw new HttpsError("permission-denied", "Only the assigned provider can verify this OTP.", {
        code: result.code,
      });
    }
    if (result.code === "BOOKING_CANCELLED") {
      throw new HttpsError("failed-precondition", "This booking has already been cancelled.", {
        code: result.code,
      });
    }
    if (result.code === "INVALID_STATE" || result.code === "PAYMENT_NOT_CONFIRMED") {
      throw new HttpsError("failed-precondition", "This booking is not eligible for service start.", {
        code: result.code,
        state: result.state,
      });
    }
    if (result.code === "OTP_NOT_AVAILABLE") {
      throw new HttpsError("failed-precondition", "OTP verification is not available for this booking.", {
        code: result.code,
      });
    }
    if (result.code === "AFTER_SERVICE_END") {
      throw new HttpsError("failed-precondition", "The service-start window has already passed.", {
        code: result.code,
      });
    }
    if (result.code === "INVALID_BOOKING_DATA") {
      throw new HttpsError("failed-precondition", "This booking is missing valid service timing data.", {
        code: result.code,
      });
    }
    if (result.code === "POLICY_NOT_CONFIGURED") {
      throw new HttpsError("failed-precondition", "The service-start timing policy is not configured for this booking.", {
        code: result.code,
      });
    }
    if (result.code === "TEMPORARILY_LOCKED" || result.code === "ATTEMPTS_EXCEEDED") {
      throw new HttpsError("resource-exhausted", "OTP verification is temporarily locked. Please try again later.", {
        code: result.code,
        retryAfterMs: result.retryAfterMs,
      });
    }
    if (result.code === "INVALID_OTP") {
      throw new HttpsError("permission-denied", "The OTP is invalid.", {
        code: result.code,
      });
    }

    return buildBookingStartOtpResponse(result);
  },
);

export const completeBookingServiceV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const uid = requireUid(request.auth);
    const bookingId = asString(request.data?.bookingId);
    if (!bookingId) {
      throw new HttpsError("invalid-argument", "bookingId is required.");
    }

    const bookingSnapshot = await db.collection("bookings").doc(bookingId).get();
    if (!bookingSnapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.", {code: "BOOKING_NOT_FOUND"});
    }
    const booking = ensureCanonicalBooking(bookingSnapshot.data());
    if (booking.providerId !== uid) {
      throw new HttpsError("permission-denied", "Only the provider can complete this booking.", {
        code: "ACTOR_NOT_AUTHORIZED",
      });
    }
    const authorized = await authorizeCanonicalBookingCommand({
      bookingId,
      authenticatedUserId: uid,
      expectedActor: "provider",
      allowedStates: ["IN_PROGRESS", "COMPLETED_PENDING_REVIEW"],
      operation: "continuation",
      now: new Date(),
    });
    const result = await completeBookingServiceApplicationV3({
      firestore: db,
      bookingId,
      providerUid: uid,
    });
    if (result.code === "NOT_FOUND") {
      throw new HttpsError("not-found", "Booking not found.", {code: result.code});
    }
    if (result.code === "UNAUTHORIZED") {
      throw new HttpsError("permission-denied", "Only the provider can complete this booking.", {
        code: result.code,
      });
    }
    if (result.code === "PAYMENT_NOT_CONFIRMED" ||
      result.code === "INVALID_STATE" ||
      result.code === "INVALID_BOOKING_DATA") {
      throw new HttpsError("failed-precondition", "This booking cannot be completed right now.", {
        code: result.code,
        state: result.state,
      });
    }
    return buildBookingCompletionResponse({
      ...result,
      state: result.code === "COMPLETED_PENDING_REVIEW" ? "COMPLETED_PENDING_REVIEW" : authorized.booking.state,
    });
  },
);

export const submitBookingReviewV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const uid = requireUid(request.auth);
    const bookingId = asString(request.data?.bookingId);
    const rating = asInt(request.data?.rating, 0);
    const comment = asString(request.data?.comment);
    const rawTags = Array.isArray(request.data?.tags) ? request.data?.tags : [];
    const tags = rawTags
      .map((value: unknown) => asString(value))
      .filter((value: string) => value.length > 0);
    if (!bookingId) {
      throw new HttpsError("invalid-argument", "bookingId is required.");
    }
    if (rating < 1 || rating > 5) {
      throw new HttpsError("invalid-argument", "rating must be between 1 and 5.");
    }

    const bookingSnapshot = await db.collection("bookings").doc(bookingId).get();
    if (!bookingSnapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.", {code: "BOOKING_NOT_FOUND"});
    }
    const booking = ensureCanonicalBooking(bookingSnapshot.data());
    if (booking.parentId !== uid) {
      throw new HttpsError("permission-denied", "Only the customer can submit a review.", {
        code: "ACTOR_NOT_AUTHORIZED",
      });
    }

    const result = await submitBookingReviewApplicationV3({
      firestore: db,
      bookingId,
      parentUid: uid,
      rating,
      comment,
      tags,
    });
    if (result.code === "NOT_FOUND") {
      throw new HttpsError("not-found", "Booking not found.", {code: result.code});
    }
    if (result.code === "UNAUTHORIZED") {
      throw new HttpsError("permission-denied", "Only the customer can submit a review.", {
        code: result.code,
      });
    }
    if (result.code === "INVALID_STATE" ||
      result.code === "WINDOW_EXPIRED" ||
      result.code === "INVALID_BOOKING_DATA") {
      throw new HttpsError("failed-precondition", "This booking is not ready for review.", {
        code: result.code,
        state: result.state,
      });
    }
    return buildBookingReviewResponse(result);
  },
);

export const createBookingDisputeV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const uid = requireUid(request.auth);
    const bookingId = asString(request.data?.bookingId);
    const reason = asString(request.data?.reason);
    const description = asString(request.data?.description);
    const rawAttachments = Array.isArray(request.data?.attachments) ? request.data?.attachments : [];
    const attachments = rawAttachments
      .map((value: unknown) => asString(value))
      .filter((value: string) => value.length > 0);
    if (!bookingId || !reason || !description) {
      throw new HttpsError("invalid-argument", "bookingId, reason, and description are required.");
    }

    const bookingSnapshot = await db.collection("bookings").doc(bookingId).get();
    if (!bookingSnapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.", {code: "BOOKING_NOT_FOUND"});
    }
    const booking = ensureCanonicalBooking(bookingSnapshot.data());
    if (booking.parentId !== uid) {
      throw new HttpsError("permission-denied", "Only the customer can raise a dispute.", {
        code: "ACTOR_NOT_AUTHORIZED",
      });
    }

    const result = await createBookingDisputeApplicationV3({
      firestore: db,
      bookingId,
      parentUid: uid,
      reason,
      description,
      attachments,
    });
    if (result.code === "NOT_FOUND") {
      throw new HttpsError("not-found", "Booking not found.", {code: result.code});
    }
    if (result.code === "UNAUTHORIZED") {
      throw new HttpsError("permission-denied", "Only the customer can raise a dispute.", {
        code: result.code,
      });
    }
    if (result.code === "INVALID_STATE" ||
      result.code === "WINDOW_EXPIRED" ||
      result.code === "INVALID_BOOKING_DATA") {
      throw new HttpsError("failed-precondition", "This booking is not eligible for dispute submission.", {
        code: result.code,
        state: result.state,
      });
    }
    return buildBookingDisputeResponse(result);
  },
);

export const resolveBookingDisputeV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const uid = requireUid(request.auth);
    await requireFinanceAdmin(uid);
    const data =
      typeof request.data === "object" && request.data != null ?
        request.data as Record<string, unknown> :
        {};
    const result = await resolveBookingDisputeApplicationV3({
      firestore: db,
      auth: request.auth,
      input: {
        disputeId: asString(data.disputeId),
        bookingId: asString(data.bookingId),
        resolutionType:
          asString(data.resolutionType) as
            | "CUSTOMER_WINS"
            | "PROVIDER_WINS"
            | "PARTIAL_REFUND"
            | "CUSTOM_ADJUSTMENT",
        policyReason: asString(data.policyReason),
        notes: asString(data.notes),
        resolutionAttemptId: asString(data.resolutionAttemptId),
        customerRefundPaise:
          data.customerRefundPaise == null ?
            null :
            asInt(data.customerRefundPaise, 0),
        providerFinalEntitlementPaise:
          data.providerFinalEntitlementPaise == null ?
            null :
            asInt(data.providerFinalEntitlementPaise, 0),
      },
    });
    return buildDisputeResolutionResponse(result);
  },
);

export const listCanonicalDisputesV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const uid = requireUid(request.auth);
    await requireFinanceAdmin(uid);
    const statusFilter = asString(request.data?.status).toUpperCase();
    const limit = Math.min(Math.max(asInt(request.data?.limit, 25), 1), 100);
    const snapshot = await db.collection("disputes").limit(limit).get();
    const items = snapshot.docs
      .map((doc): Record<string, unknown> => ({
        disputeId: doc.id,
        ...asRecord(doc.data()),
      }))
      .filter((entry) =>
        asString(entry.source) === "canonical_v3" &&
        (!statusFilter || asString(entry.status).toUpperCase() === statusFilter),
      )
      .map((entry) => ({
        disputeId: asString(entry.disputeId),
        bookingId: asString(entry.bookingId),
        providerId: asString(entry.providerId),
        customerId: asString(entry.customerId || entry.parentId),
        status: asString(entry.status),
        reasonCode:
          asString(entry.reasonCode) || asString(entry.reason),
        resolutionType: asString(asRecord(entry.resolution).type),
        createdAt: asNullableDate(entry.createdAt)?.toISOString() ?? null,
        updatedAt: asNullableDate(entry.updatedAt)?.toISOString() ?? null,
      }));
    return {items};
  },
);

export const getCanonicalDisputeV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const uid = requireUid(request.auth);
    await requireFinanceAdmin(uid);
    const disputeId = asString(request.data?.disputeId);
    if (!disputeId) {
      throw new HttpsError("invalid-argument", "disputeId is required.");
    }
    const snapshot = await db.collection("disputes").doc(disputeId).get();
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Dispute not found.");
    }
    const data = snapshot.data() ?? {};
    return {
      disputeId,
      bookingId: asString(data.bookingId),
      providerId: asString(data.providerId),
      customerId: asString(data.customerId || data.parentId),
      status: asString(data.status),
      reasonCode: asString(data.reasonCode) || asString(data.reason),
      description: asString(data.description),
      attachmentPaths: Array.isArray(data.attachmentPaths) ?
        data.attachmentPaths :
        (Array.isArray(data.attachments) ? data.attachments : []),
      resolution: asRecord(data.resolution),
      resolvedAt: asNullableDate(data.resolvedAt)?.toISOString() ?? null,
      updatedAt: asNullableDate(data.updatedAt)?.toISOString() ?? null,
    };
  },
);

export const listProviderPayoutsV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const uid = requireUid(request.auth);
    await requireFinanceAdmin(uid);
    const statusFilter = asString(request.data?.status).toUpperCase();
    const limit = Math.min(Math.max(asInt(request.data?.limit, 25), 1), 100);
    const snapshot = await db
      .collection(CANONICAL_PROVIDER_PAYOUTS_COLLECTION)
      .limit(limit)
      .get();
    const items = snapshot.docs
      .map((doc): Record<string, unknown> => ({
        payoutId: doc.id,
        ...asRecord(doc.data()),
      }))
      .filter((entry) =>
        !statusFilter || asString(entry.status).toUpperCase() === statusFilter,
      )
      .map((entry) => ({
        payoutId: asString(entry.payoutId),
        bookingId: asString(entry.bookingId),
        providerId: asString(entry.providerId),
        status: asString(entry.status),
        holdReason: asString(entry.holdReason),
        remainingPayablePaise: asInt(entry.remainingPayablePaise, 0),
        retryCount: asInt(entry.retryCount, 0),
        updatedAt: asNullableDate(entry.updatedAt)?.toISOString() ?? null,
      }));
    return {items, livePayoutEnabled: false};
  },
);

export const getProviderPayoutV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const uid = requireUid(request.auth);
    await requireFinanceAdmin(uid);
    const bookingId = asString(request.data?.bookingId);
    if (!bookingId) {
      throw new HttpsError("invalid-argument", "bookingId is required.");
    }
    const snapshot = await db
      .collection(CANONICAL_PROVIDER_PAYOUTS_COLLECTION)
      .doc(bookingId)
      .get();
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Payout not found.");
    }
    const data = snapshot.data() ?? {};
    return {
      payoutId: snapshot.id,
      bookingId: asString(data.bookingId),
      providerId: asString(data.providerId),
      status: asString(data.status),
      holdReason: asString(data.holdReason),
      providerEntitlementPaise: asInt(data.providerEntitlementPaise, 0),
      remainingPayablePaise: asInt(data.remainingPayablePaise, 0),
      priorPaidPaise: asInt(data.priorPaidPaise, 0),
      failureCode: asString(data.failureCode),
      retryCount: asInt(data.retryCount, 0),
      updatedAt: asNullableDate(data.updatedAt)?.toISOString() ?? null,
      externalPayoutId: asString(data.externalPayoutId),
      externalTransactionId: asString(data.externalTransactionId),
    };
  },
);

export const retryProviderPayoutV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const uid = requireUid(request.auth);
    await requireFinanceAdmin(uid);
    const bookingId = asString(request.data?.bookingId);
    if (!bookingId) {
      throw new HttpsError("invalid-argument", "bookingId is required.");
    }
    const result = await processProviderPayoutApplicationV3({
      firestore: db,
      bookingId,
      gateway: new DisabledProviderPayoutGatewayV3(),
      processorLeaseOwner: `manual_retry:${uid}`,
    });
    const response: CanonicalProviderPayoutResponse = {
      ok: result.ok,
      code: result.code,
      bookingId: result.bookingId,
      payoutId: result.payoutId,
      status: result.status,
      failureCode: result.ok ? "" : result.failureCode,
      externalPayoutId:
        result.ok ? result.externalPayoutId : undefined,
      externalTransactionId:
        result.ok ? result.externalTransactionId : undefined,
    };
    return response;
  },
);

export const getBookingFinancialLedgerV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const uid = requireUid(request.auth);
    await requireFinanceAdmin(uid);
    const bookingId = asString(request.data?.bookingId);
    if (!bookingId) {
      throw new HttpsError("invalid-argument", "bookingId is required.");
    }
    const snapshot = await db
      .collection(CANONICAL_FINANCIAL_LEDGER_COLLECTION)
      .where("bookingId", "==", bookingId)
      .get();
    const items = snapshot.docs.map((doc) => ({
      entryId: doc.id,
      ...doc.data(),
      occurredAt:
        asNullableDate(doc.data().occurredAt)?.toISOString() ?? null,
      createdAt:
        asNullableDate(doc.data().createdAt)?.toISOString() ?? null,
    }));
    return {items};
  },
);

export const runBookingFinancialReconciliationV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const uid = requireUid(request.auth);
    await requireFinanceAdmin(uid);
    const bookingId = asString(request.data?.bookingId);
    if (!bookingId) {
      throw new HttpsError("invalid-argument", "bookingId is required.");
    }
    const result = await reconcileBookingFinancialsApplicationV3({
      firestore: db,
      bookingId,
    });
    const response: CanonicalFinancialReconciliationResponse = {
      bookingId: result.bookingId,
      status: result.status,
      action: result.action,
      issues: result.issues,
      repairWriteCount: result.repairWrites.length,
    };
    return response;
  },
);

export const runProviderPayoutProcessingBatchV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const uid = requireUid(request.auth);
    await requireFinanceAdmin(uid);
    const mode = asString(request.data?.mode).toLowerCase();
    const processorLeaseOwner = `admin_batch:${uid}`;
    const results = mode === "retry" ?
      await processRetryableProviderPayoutBatchV3({
        firestore: db,
        gateway: new DisabledProviderPayoutGatewayV3(),
        processorLeaseOwner,
      }) :
      await processReadyProviderPayoutBatchV3({
        firestore: db,
        gateway: new DisabledProviderPayoutGatewayV3(),
        processorLeaseOwner,
      });
    return {
      livePayoutEnabled: false,
      results: results.map((result) => ({
        ok: result.ok,
        code: result.code,
        bookingId: result.bookingId,
        payoutId: result.payoutId,
        status: result.status,
        failureCode: result.ok ? "" : result.failureCode,
      })),
    };
  },
);

export const expirePendingProviderBookingsV3 = onSchedule(
  {schedule: "every 5 minutes", timeZone: "Asia/Kolkata"},
  async () => {
    const authoritativeNow = new Date();
    const dueSnapshot = await db
      .collection("bookings")
      .where("stateQueryValue", "==", "PENDING_PROVIDER")
      .where("acceptDeadlineAt", "<=", Timestamp.fromDate(authoritativeNow))
      .limit(100)
      .get();

    let processed = 0;
    for (const doc of dueSnapshot.docs) {
      const parsed = ensureCanonicalBooking(doc.data());
      const lifecycleResult = expirePendingProviderBookingApplicationV3({
        bookingId: doc.id,
        booking: parsed,
        authoritativeNow,
        existingProviderStats: emptyProviderStatsV3(),
      });
      if (!lifecycleResult.ok) continue;
      const changed = await applySchedulerLifecycleMutation({
        bookingRef: doc.ref,
        lifecycleResult,
      });
      if (changed) processed += 1;
    }

    console.info("bookingV3.scheduler.providerExpiry", {
      processed,
      scanned: dueSnapshot.size,
      authoritativeAt: authoritativeNow.toISOString(),
    });
  },
);

export const expireAwaitingPaymentsV3 = onSchedule(
  {
    schedule: "every 5 minutes",
    timeZone: "Asia/Kolkata",
    secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET],
  },
  async () => {
    const authoritativeNow = new Date();
    const keyId = asString(RAZORPAY_KEY_ID.value());
    const keySecret = asString(RAZORPAY_KEY_SECRET.value());
    const reconciledAttempts = await reconcilePaymentAttemptsV3({
      firestore: db,
      keyId,
      keySecret,
      authoritativeNow,
      limit: 100,
    });

    const dueSnapshot = await db
      .collection("bookings")
      .where("stateQueryValue", "==", "ACCEPTED_AWAITING_PAYMENT")
      .where("payDeadlineAt", "<=", Timestamp.fromDate(authoritativeNow))
      .limit(100)
      .get();

    let processed = 0;
    let skippedForReconciliation = 0;
    let expiredAttempts = 0;
    for (const doc of dueSnapshot.docs) {
      const booking = ensureCanonicalBooking(doc.data());
      const attemptsSnapshot = await doc.ref.collection("paymentAttempts").limit(20).get();
      const activeAttempts = attemptsSnapshot.docs
        .map((snapshot) => ({ref: snapshot.ref, data: asRecord(snapshot.data())}))
        .filter(({data}) => {
          const state = asString(data.state).toUpperCase();
          return state.length > 0 &&
            state !== "REFUNDED" &&
            state !== "FAILED" &&
            state !== "EXPIRED";
        });

      if (activeAttempts.some(({data}) => isPaymentAttemptUncertainOrCaptured(asString(data.state).toUpperCase()) || asString(data.razorpayPaymentId).length > 0)) {
        skippedForReconciliation += 1;
        continue;
      }

      const lifecycleResult = expireAwaitingPaymentBookingApplicationV3({
        bookingId: doc.id,
        booking,
        authoritativeNow,
        existingProviderStats: emptyProviderStatsV3(),
        existingParentStats: emptyParentStatsV3(),
      });
      if (!lifecycleResult.ok) continue;

      const changed = await applySchedulerLifecycleMutation({
        bookingRef: doc.ref,
        lifecycleResult,
      });
      if (!changed) continue;

      if (activeAttempts.length > 0) {
        const batch = db.batch();
        for (const attempt of activeAttempts) {
          batch.set(attempt.ref, {
            state: "EXPIRED",
            nextReconciliationAt: null,
            terminalFailureAt: FieldValue.serverTimestamp(),
            lastReconciledAt: FieldValue.serverTimestamp(),
            lastReconciliationCode: "PAYMENT_WINDOW_EXPIRED",
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
          expiredAttempts += 1;
        }
        await batch.commit();
      }
      processed += 1;
    }

    console.info("bookingV3.scheduler.paymentExpiry", {
      processed,
      scanned: dueSnapshot.size,
      reconciledAttempts,
      skippedForReconciliation,
      expiredAttempts,
      authoritativeAt: authoritativeNow.toISOString(),
    });
  },
);

export const reconcileBookingPaymentsV3 = onSchedule(
  {
    schedule: "every 10 minutes",
    timeZone: "Asia/Kolkata",
    secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET],
  },
  async () => {
    const authoritativeNow = new Date();
    const processed = await reconcilePaymentAttemptsV3({
      firestore: db,
      keyId: asString(RAZORPAY_KEY_ID.value()),
      keySecret: asString(RAZORPAY_KEY_SECRET.value()),
      authoritativeNow,
      limit: 100,
    });
    console.info("bookingV3.scheduler.paymentReconciliation", {
      processed,
      authoritativeAt: authoritativeNow.toISOString(),
    });
  },
);

export const finalizeCanonicalNoShowsV3 = onSchedule(
  {schedule: "every 30 minutes", timeZone: "Asia/Kolkata"},
  async () => {
    const authoritativeNow = new Date();
    const confirmedSnapshot = await db
      .collection("bookings")
      .where("stateQueryValue", "==", "CONFIRMED")
      .limit(100)
      .get();
    const inProgressSnapshot = await db
      .collection("bookings")
      .where("stateQueryValue", "==", "IN_PROGRESS")
      .limit(100)
      .get();

    let noShowFinalized = 0;
    let repairedStarts = 0;
    for (const doc of [...confirmedSnapshot.docs, ...inProgressSnapshot.docs]) {
      const result = await reconcileCanonicalServiceStartArtifactsV3({
        firestore: db,
        bookingId: doc.id,
        authoritativeNow,
      });
      if (result === "NO_SHOW_FINALIZED") {
        noShowFinalized += 1;
      } else if (result === "REPAIRED") {
        repairedStarts += 1;
      }
    }

    console.info("bookingV3.scheduler.noShowFinalization", {
      confirmedScanned: confirmedSnapshot.size,
      inProgressScanned: inProgressSnapshot.size,
      noShowFinalized,
      repairedStarts,
      authoritativeAt: authoritativeNow.toISOString(),
    });
  },
);

export const finalizeCompletedBookingsV3 = onSchedule(
  {schedule: "every 15 minutes", timeZone: "Asia/Kolkata"},
  async () => {
    const snapshot = await db
      .collection("bookings")
      .where("state", "==", "COMPLETED_PENDING_REVIEW")
      .limit(100)
      .get();
    for (const doc of snapshot.docs) {
      await finalizeCompletedBookingApplicationV3({
        firestore: db,
        bookingId: doc.id,
      });
    }
  },
);
