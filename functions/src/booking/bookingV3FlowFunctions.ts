import {FieldPath, FieldValue, Timestamp} from "firebase-admin/firestore";
import {
  HttpsError,
  onCall,
  onRequest,
  type CallableRequest,
} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";

import {
  RAZORPAY_KEY_ID,
  RAZORPAY_KEY_SECRET,
  RAZORPAY_WEBHOOK_SECRET,
} from "../config/secrets";
import {normalizeServiceSchedulingMode} from "../serviceScheduling";
import {auth, db, storage} from "../shared/firebase";
import {ACCEPT_WINDOW_MS} from "./domain/bookingConstants";
import {
  ACTIONABLE_PROVIDER_REQUEST_STATES,
  acceptBookingRequestV3 as acceptBookingRequestApplicationV3,
  buildCustomerPaymentReminderIfDueV3,
  buildProviderRequestReminderIfDueV3,
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
  CANONICAL_QR_PAYMENT_MAPPINGS_COLLECTION,
  canonicalPaymentOrderMappingRef,
  canonicalQrPaymentMappingRef,
  buildLegacyCouponRecordFromCampaignSelection,
  buildPaymentAttemptDocument,
  createDeterministicPaymentAttemptId,
  createRazorpayPaymentOrderV3 as createRazorpayPaymentOrderApplicationV3,
  persistFinalizePaymentResultV3,
  previewCanonicalPaymentPricingV3,
  reconcilePaymentAttemptsV3,
  resolveQrSwitchLockedUntil,
  resolveCanonicalPricingV3,
  validatePreCheckoutAvailabilityV3,
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
  type CanonicalDisputeEvidenceRecord,
  completeBookingServiceV3 as completeBookingServiceApplicationV3,
  createBookingDisputeV3 as createBookingDisputeApplicationV3,
  finalizeCompletedBookingV3 as finalizeCompletedBookingApplicationV3,
  reconcileCanonicalCompletionStateV3,
  submitBookingReviewV3 as submitBookingReviewApplicationV3,
} from "./application/serviceCompletionOrchestrationV3";
import {routeCanonicalWebhookEventV3} from "./application/canonicalPaymentWebhookV3";
import {
  CANONICAL_FINANCIAL_LEDGER_COLLECTION,
  CANONICAL_PROVIDER_PAYOUTS_COLLECTION,
  DisabledProviderPayoutGatewayV3,
  processProviderPayoutV3 as processProviderPayoutApplicationV3,
  previewBookingDisputeResolutionV3 as previewBookingDisputeResolutionApplicationV3,
  processReadyProviderPayoutBatchV3,
  processRetryableProviderPayoutBatchV3,
  reconcileBookingFinancialsV3 as reconcileBookingFinancialsApplicationV3,
  resolveBookingDisputeV3 as resolveBookingDisputeApplicationV3,
} from "./application/financialSettlementV3";
import {processRazorpayWebhookEnvelopeV3} from "./application/paymentWebhookEventsV3";
import {
  closeRazorpayQrCodeV3,
  createRazorpayQrCodeV3,
  verifyRazorpayPaymentSignature,
} from "./application/razorpayGateway";
import {
  assertValidCanonicalBookingDocumentV3,
  type CanonicalBookingDocumentV3,
} from "./schema/bookingDocumentV3";
import type {CanonicalPaymentAttemptDocumentV3} from "./schema/paymentAttemptDocumentV3";
import {buildStoredBookingNotificationDocument} from "../notifications/notificationChannels";
import type {
  RangeBookingSelection,
} from "./domain/rangeBooking";
import type {
  SlotBookingSelection,
  SlotSegment,
} from "./domain/slotBooking";
import {validateSlotBookingSelection} from "./domain/slotBooking";
import {validateOfferCampaignForBooking} from "../offers/application/validateOfferCampaignForBooking";

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

type CanonicalQrPaymentResponse =
  | {
      bookingId: string;
      paymentAttemptId: string;
      mode: "qr";
      qrCodeId: string;
      imageUrl: string;
      amountPaise: number;
      currency: string;
      expiresAt: string | null;
      switchLockUntil: string | null;
      pricingSummary: CanonicalPaymentPricingSummaryResponse;
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

type CanonicalPaymentPricingPreviewResponse = {
  bookingId: string;
  pricingSummary: CanonicalPaymentPricingSummaryResponse;
  payDeadlineAt: string | null;
  offerCampaignId: string;
  idempotentReplay: boolean;
};

const canonicalPrivateCallableOptions = {
  region: "asia-south1" as const,
  invoker: "private" as const,
  // Keep canonical payment callable policy explicit and aligned while
  // Flutter's App Check rollout is still incomplete in production/debug.
  enforceAppCheck: false,
};

const canonicalPrivateRazorpayCallableOptions = {
  ...canonicalPrivateCallableOptions,
  secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET],
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
  customerPaidPaise: number;
  authoritativeAmountPaidPaise: number;
  customerAllocationBasisPoints: number | null;
  providerAllocationBasisPoints: number | null;
  pettxoAllocationBasisPoints: number | null;
  customerFinalPaise: number;
  customerRefundPaise: number;
  providerAllocationPaise: number;
  providerFinalEntitlementPaise: number;
  providerCouponSubsidyPaise: number;
  providerAlreadyPaidPaise: number;
  providerRemainingPayablePaise: number;
  pettxoFinalRetainedPaise: number;
  refundToIssuePaise: number;
  idempotentReplay: boolean;
};

type CanonicalDisputeResolutionPreviewResponse = {
  bookingId: string;
  disputeId: string;
  resolutionType: string;
  currency: string;
  customerPaidPaise: number;
  authoritativeAmountPaidPaise: number;
  alreadyRefundedPaise: number;
  providerBaseEntitlementPaise: number;
  providerAlreadyPaidPaise: number;
  providerRemainingPayablePaise: number;
  customerAllocationBasisPoints: number | null;
  providerAllocationBasisPoints: number | null;
  pettxoAllocationBasisPoints: number | null;
  customerRefundBasisPoints: number | null;
  customerFinalPaise: number;
  customerRefundPaise: number;
  providerAllocationPaise: number;
  providerFinalEntitlementPaise: number;
  providerCouponSubsidyPaise: number;
  pettxoFinalRetainedPaise: number;
  refundToIssuePaise: number;
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
  selectedDays?: Array<{
    serviceDateKey: string;
    slotIds: string[];
  }>;
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

type RequestedDisputeEvidence = {
  evidenceId: string;
  storagePath: string;
};

function fileExtensionFromPath(path: string): string {
  const fileName = path.split("/").pop() ?? "";
  const lastDot = fileName.lastIndexOf(".");
  return lastDot >= 0 ? fileName.slice(lastDot + 1).toLowerCase() : "";
}

function normalizeRequestedDisputeEvidence(
  rawEvidence: unknown,
  rawAttachments: unknown[],
): RequestedDisputeEvidence[] {
  const requested = Array.isArray(rawEvidence) ? rawEvidence : [];
  const normalizedFromEvidence = requested
    .map((value) => asRecord(value))
    .map((value) => ({
      evidenceId: asString(value.evidenceId),
      storagePath: asString(value.storagePath),
    }))
    .filter((value) => value.storagePath.length > 0);
  if (normalizedFromEvidence.length > 0) {
    return normalizedFromEvidence;
  }
  return rawAttachments
    .map((value) => asString(value))
    .filter((value) => value.length > 0)
    .map((storagePath) => ({
      evidenceId: asString(storagePath.split("/").pop()?.split(".").shift()),
      storagePath,
    }));
}

async function validateBookingDisputeEvidenceUploads(params: {
  bookingId: string;
  uid: string;
  requestedEvidence: RequestedDisputeEvidence[];
}): Promise<CanonicalDisputeEvidenceRecord[]> {
  if (params.requestedEvidence.length === 0) return [];
  if (params.requestedEvidence.length > 5) {
    throw new HttpsError("invalid-argument", "You can attach up to 5 screenshots or photos.", {
      code: "TOO_MANY_EVIDENCE_FILES",
    });
  }
  const bucket = storage.bucket();
  const seenStoragePaths = new Set<string>();
  const seenEvidenceIds = new Set<string>();
  const validated: CanonicalDisputeEvidenceRecord[] = [];
  const allowedContentTypes = new Set(["image/jpeg", "image/jpg", "image/png", "image/webp"]);
  for (const item of params.requestedEvidence) {
    const storagePath = item.storagePath.trim();
    const evidenceId = item.evidenceId.trim();
    const expectedPrefix = `disputes/${params.bookingId}/evidence/${params.uid}/`;
    if (!storagePath.startsWith(expectedPrefix) || storagePath.includes("..")) {
      throw new HttpsError("invalid-argument", "Evidence path is invalid.", {
        code: "INVALID_EVIDENCE_PATH",
      });
    }
    if (seenStoragePaths.has(storagePath)) {
      throw new HttpsError("invalid-argument", "Duplicate evidence references are not allowed.", {
        code: "DUPLICATE_EVIDENCE_REFERENCE",
      });
    }
    const normalizedEvidenceId = evidenceId ||
      asString(storagePath.split("/").pop()?.split(".").shift());
    if (!normalizedEvidenceId) {
      throw new HttpsError("invalid-argument", "Evidence id is missing.", {
        code: "INVALID_EVIDENCE_ID",
      });
    }
    if (seenEvidenceIds.has(normalizedEvidenceId)) {
      throw new HttpsError("invalid-argument", "Duplicate evidence ids are not allowed.", {
        code: "DUPLICATE_EVIDENCE_ID",
      });
    }
    seenStoragePaths.add(storagePath);
    seenEvidenceIds.add(normalizedEvidenceId);

    const [metadata] = await bucket.file(storagePath).getMetadata();
    const contentType = asString(metadata.contentType).toLowerCase();
    if (!allowedContentTypes.has(contentType)) {
      throw new HttpsError("invalid-argument", "Only JPG, JPEG, PNG, or WEBP images are supported.", {
        code: "UNSUPPORTED_EVIDENCE_TYPE",
      });
    }
    const sizeBytes = Number.parseInt(`${metadata.size ?? "0"}`, 10);
    if (!Number.isFinite(sizeBytes) || sizeBytes <= 0) {
      throw new HttpsError("failed-precondition", "Evidence file metadata is incomplete.", {
        code: "INVALID_EVIDENCE_METADATA",
      });
    }
    if (sizeBytes > 5 * 1024 * 1024) {
      throw new HttpsError("invalid-argument", "Each evidence image must be 5 MB or smaller.", {
        code: "EVIDENCE_FILE_TOO_LARGE",
      });
    }
    const customMetadata = asRecord(metadata.metadata);
    if (asString(customMetadata.bookingId) !== params.bookingId ||
      asString(customMetadata.uploadedByUid) !== params.uid ||
      asString(customMetadata.uploadedByRole) !== "parent") {
      throw new HttpsError("permission-denied", "Evidence does not belong to this dispute request.", {
        code: "EVIDENCE_OWNERSHIP_MISMATCH",
      });
    }
    validated.push({
      evidenceId: normalizedEvidenceId,
      storagePath,
      mimeType: contentType === "image/jpg" ? "image/jpeg" : contentType,
      sizeBytes,
      uploadedByUid: params.uid,
      uploadedByRole: "parent",
      createdAt: new Date(),
      width: asInt(customMetadata.width, 0) > 0 ? asInt(customMetadata.width, 0) : null,
      height: asInt(customMetadata.height, 0) > 0 ? asInt(customMetadata.height, 0) : null,
    });
  }
  return validated.sort((left, right) => {
    const leftKey = `${left.createdAt.getTime()}:${left.evidenceId}:${fileExtensionFromPath(left.storagePath)}`;
    const rightKey = `${right.createdAt.getTime()}:${right.evidenceId}:${fileExtensionFromPath(right.storagePath)}`;
    return leftKey.localeCompare(rightKey);
  });
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

function serviceDateKeyFromDate(date: Date, timezone: string): string {
  try {
    const formatter = new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone || "UTC",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
    const parts = formatter.formatToParts(date);
    const year = parts.find((part) => part.type === "year")?.value ?? "1970";
    const month = parts.find((part) => part.type === "month")?.value ?? "01";
    const day = parts.find((part) => part.type === "day")?.value ?? "01";
    return `${year}-${month}-${day}`;
  } catch (_) {
    return date.toISOString().slice(0, 10);
  }
}

function sameSlotIdMultiset(left: string[], right: string[]): boolean {
  if (left.length !== right.length) return false;
  const counts = new Map<string, number>();
  for (const slotId of left) {
    counts.set(slotId, (counts.get(slotId) ?? 0) + 1);
  }
  for (const slotId of right) {
    const current = counts.get(slotId) ?? 0;
    if (current <= 0) return false;
    if (current === 1) {
      counts.delete(slotId);
    } else {
      counts.set(slotId, current - 1);
    }
  }
  return counts.size === 0;
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
    const selectedDaysRaw = Array.isArray(data.selectedDays) ? data.selectedDays : [];
    const selectedDays = selectedDaysRaw.map((entry) => {
      const day = asRecord(entry);
      return {
        serviceDateKey: asString(day.serviceDateKey),
        slotIds: Array.isArray(day.slotIds) ?
          day.slotIds.map((slotId) => asString(slotId)).filter(Boolean) :
          [],
      };
    });
    const groupedSlotIds = selectedDays.flatMap((day) => day.slotIds);

    if (slotIds.length === 0 && groupedSlotIds.length === 0) {
      throw new HttpsError("invalid-argument", "slotIds or selectedDays are required for SLOT requests.");
    }
    if (selectedDaysRaw.length > 0 && selectedDays.some((day) => day.slotIds.length === 0)) {
      throw new HttpsError("invalid-argument", "Each selectedDays entry must include at least one slotId.", {
        code: "INVALID_SLOT_SELECTION",
      });
    }
    if (slotIds.length > 0 && groupedSlotIds.length > 0 && !sameSlotIdMultiset(slotIds, groupedSlotIds)) {
      throw new HttpsError("invalid-argument", "slotIds and selectedDays must describe the same slot selection.", {
        code: "INVALID_SLOT_SELECTION",
      });
    }
    return {
      requestAttemptId,
      serviceId,
      bookingType,
      slotRequest: {
        slotIds: slotIds.length > 0 ? slotIds : groupedSlotIds,
        selectedDays: selectedDaysRaw.length > 0 ? selectedDays : undefined,
      },
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
  const normalizedSchedulingMode = normalizeServiceSchedulingMode({
    schedulingMode: service.schedulingMode,
    sessionDurationMinutes: asInt(service.sessionDurationMinutes, 0),
    startMinutes: service.startMinutes,
    endMinutes: service.endMinutes,
  });
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
    schedulingMode: normalizedSchedulingMode || undefined,
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
  serviceTimezone: string;
  schedulingMode: string;
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
      dateKey:
        asString(data.serviceDateKey) ||
        asString(data.dateKey) ||
        serviceDateKeyFromDate(startAt, asString(data.timezone) || params.serviceTimezone),
      serviceDateKey:
        asString(data.serviceDateKey) ||
        asString(data.dateKey) ||
        serviceDateKeyFromDate(startAt, asString(data.timezone) || params.serviceTimezone),
      startAt,
      endAt,
      durationMinutes: Math.round((endAt.getTime() - startAt.getTime()) / 60000),
      unitPricePaise: params.unitPricePaise,
      schedulingMode: params.schedulingMode,
    };
  }).sort((left, right) => left.startAt.getTime() - right.startAt.getTime());

  const rawSelection: SlotBookingSelection = {
    bookingType: "SLOT",
    slots,
    slotCount: slots.length,
    scheduledStartAt: slots[0].startAt,
    scheduledEndAt: slots[slots.length - 1].endAt,
    totalDurationMinutes: slots.reduce(
      (sum, slot) => sum + slot.durationMinutes,
      0,
    ),
  };
  const normalized = validateSlotBookingSelection(rawSelection);
  if (!normalized.ok || !normalized.normalizedSelection) {
    throw new HttpsError("failed-precondition", "Selected slots failed validation.", {
      code: normalized.issues[0]?.code ?? "INVALID_SLOT_SELECTION",
      issues: normalized.issues.map((entry) => `${entry.code}:${entry.message}`),
    });
  }
  return normalized.normalizedSelection;
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

function buildQrPaymentResponse(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  paymentAttemptId: string;
  paymentAttempt: Record<string, unknown> | null;
  mode: "qr" | "zero_payable";
  qrCodeId?: string;
  imageUrl?: string;
  amountPaise?: number;
  currency?: string;
  expiresAt?: Date | null;
  idempotentReplay: boolean;
}): CanonicalQrPaymentResponse {
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
    mode: "qr",
    qrCodeId: params.qrCodeId ?? asString(params.paymentAttempt?.razorpayQrCodeId),
    imageUrl: params.imageUrl ?? asString(params.paymentAttempt?.razorpayQrImageUrl),
    amountPaise: params.amountPaise ?? pricingSummary.customerPaidPaise,
    currency: params.currency || pricingSummary.currency,
    expiresAt: (params.expiresAt ?? asNullableDate(params.paymentAttempt?.qrExpiresAt))?.toISOString() ?? null,
    switchLockUntil: resolveQrSwitchLockedUntil({
      booking: params.booking,
      paymentAttempt: params.paymentAttempt,
    })?.toISOString() ?? null,
    pricingSummary,
    idempotentReplay: params.idempotentReplay,
  };
}

function isReusableQrAttempt(paymentAttempt: Record<string, unknown> | null, now: Date): boolean {
  if (paymentAttempt == null) return false;
  if (asString(paymentAttempt.paymentMethod) !== "qr") return false;
  const qrCodeId = asString(paymentAttempt.razorpayQrCodeId);
  const qrImageUrl = asString(paymentAttempt.razorpayQrImageUrl);
  const qrState = asString(paymentAttempt.qrState).toUpperCase();
  const qrExpiresAt = asNullableDate(paymentAttempt.qrExpiresAt);
  if (!qrCodeId || !qrImageUrl) return false;
  if (qrState !== "ACTIVE") return false;
  if (qrExpiresAt && qrExpiresAt.getTime() <= now.getTime()) return false;
  return true;
}

function isActiveQrState(value: string): boolean {
  return ["CREATED", "ACTIVE", "PAYMENT_CAPTURED"].includes(value.toUpperCase());
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

function buildPaymentPricingPreviewResponse(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  pricingSummary: CanonicalPaymentPricingSummaryResponse;
  offerCampaignId?: string;
  idempotentReplay: boolean;
}): CanonicalPaymentPricingPreviewResponse {
  return {
    bookingId: params.bookingId,
    pricingSummary: params.pricingSummary,
    payDeadlineAt: params.booking.lifecycle.payDeadlineAt?.toISOString() ?? null,
    offerCampaignId: params.offerCampaignId?.trim() ?? "",
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
  customerPaidPaise: number;
  authoritativeAmountPaidPaise: number;
  customerAllocationBasisPoints: number | null;
  providerAllocationBasisPoints: number | null;
  pettxoAllocationBasisPoints: number | null;
  customerFinalPaise: number;
  customerRefundPaise: number;
  providerAllocationPaise: number;
  providerFinalEntitlementPaise: number;
  providerCouponSubsidyPaise: number;
  providerAlreadyPaidPaise: number;
  providerRemainingPayablePaise: number;
  pettxoFinalRetainedPaise: number;
  refundToIssuePaise: number;
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
    customerPaidPaise: params.customerPaidPaise,
    authoritativeAmountPaidPaise: params.authoritativeAmountPaidPaise,
    customerAllocationBasisPoints: params.customerAllocationBasisPoints,
    providerAllocationBasisPoints: params.providerAllocationBasisPoints,
    pettxoAllocationBasisPoints: params.pettxoAllocationBasisPoints,
    customerFinalPaise: params.customerFinalPaise,
    customerRefundPaise: params.customerRefundPaise,
    providerAllocationPaise: params.providerAllocationPaise,
    providerFinalEntitlementPaise:
      params.providerFinalEntitlementPaise,
    providerCouponSubsidyPaise: params.providerCouponSubsidyPaise,
    providerAlreadyPaidPaise: params.providerAlreadyPaidPaise,
    providerRemainingPayablePaise: params.providerRemainingPayablePaise,
    pettxoFinalRetainedPaise: params.pettxoFinalRetainedPaise,
    refundToIssuePaise: params.refundToIssuePaise,
    idempotentReplay: params.idempotentReplay,
  };
}

function buildDisputeResolutionPreviewResponse(params: {
  bookingId: string;
  disputeId: string;
  resolutionType: string;
  currency: string;
  customerPaidPaise: number;
  authoritativeAmountPaidPaise: number;
  alreadyRefundedPaise: number;
  providerBaseEntitlementPaise: number;
  providerAlreadyPaidPaise: number;
  providerRemainingPayablePaise: number;
  customerAllocationBasisPoints: number | null;
  providerAllocationBasisPoints: number | null;
  pettxoAllocationBasisPoints: number | null;
  customerRefundBasisPoints: number | null;
  customerFinalPaise: number;
  customerRefundPaise: number;
  providerAllocationPaise: number;
  providerFinalEntitlementPaise: number;
  providerCouponSubsidyPaise: number;
  pettxoFinalRetainedPaise: number;
  refundToIssuePaise: number;
}): CanonicalDisputeResolutionPreviewResponse {
  return {
    bookingId: params.bookingId,
    disputeId: params.disputeId,
    resolutionType: params.resolutionType,
    currency: params.currency,
    customerPaidPaise: params.customerPaidPaise,
    authoritativeAmountPaidPaise: params.authoritativeAmountPaidPaise,
    alreadyRefundedPaise: params.alreadyRefundedPaise,
    providerBaseEntitlementPaise: params.providerBaseEntitlementPaise,
    providerAlreadyPaidPaise: params.providerAlreadyPaidPaise,
    providerRemainingPayablePaise: params.providerRemainingPayablePaise,
    customerAllocationBasisPoints: params.customerAllocationBasisPoints,
    providerAllocationBasisPoints: params.providerAllocationBasisPoints,
    pettxoAllocationBasisPoints: params.pettxoAllocationBasisPoints,
    customerRefundBasisPoints: params.customerRefundBasisPoints,
    customerFinalPaise: params.customerFinalPaise,
    customerRefundPaise: params.customerRefundPaise,
    providerAllocationPaise: params.providerAllocationPaise,
    providerFinalEntitlementPaise: params.providerFinalEntitlementPaise,
    providerCouponSubsidyPaise: params.providerCouponSubsidyPaise,
    pettxoFinalRetainedPaise: params.pettxoFinalRetainedPaise,
    refundToIssuePaise: params.refundToIssuePaise,
  };
}

function logRequestEvent(
  event: string,
  payload: Record<string, unknown>,
): void {
  console.info(`bookingV3.${event}`, payload);
}

function providerActionLogContext(params: {
  bookingId: string;
  action: "accept" | "decline";
  booking: CanonicalBookingDocumentV3;
  authoritativeNow: Date;
  providerUid: string;
  rejectionCode?: string;
  rejectionMessage?: string;
}): Record<string, unknown> {
  const acceptDeadlineAt = params.booking.acceptDeadlineAt ?? params.booking.lifecycle.acceptDeadlineAt;
  return {
    bookingId: params.bookingId,
    action: params.action,
    rawState: params.booking.state,
    effectiveState: params.booking.state,
    now: params.authoritativeNow.toISOString(),
    createdAt: params.booking.createdAt.toISOString(),
    responseWindowStartsAt: params.booking.lifecycle.timerStartsAt?.toISOString() ?? null,
    responseDeadlineAt: acceptDeadlineAt?.toISOString() ?? null,
    receivedOutsideWorkingHours: params.booking.lifecycle.wasQueuedOutsideWorkingHours,
    providerUidMatches: params.booking.providerId === params.providerUid,
    rejectionCode: params.rejectionCode ?? "",
    rejectionMessage: params.rejectionMessage ?? "",
  };
}

function normalizeError(error: unknown): Error {
  if (error instanceof Error) {
    return error;
  }

  if (typeof error === "string") {
    return new Error(error);
  }

  try {
    return new Error(JSON.stringify(error));
  } catch {
    return new Error(String(error));
  }
}

async function loadSelectedCouponForCheckout(params: {
  uid: string;
  offerCampaignId: string;
  booking: CanonicalBookingDocumentV3;
}): Promise<Record<string, unknown> | null> {
  const offerCampaignId = params.offerCampaignId.trim();
  if (!offerCampaignId) {
    return null;
  }
  const serviceSubtotalPaise =
    params.booking.bookingType === "SLOT" ?
      (params.booking.schedule as {slots: Array<{unitPricePaise: number}>}).slots.reduce(
        (sum, slot) => sum + slot.unitPricePaise,
        0,
      ) :
      (params.booking.service.pricePerNightPaise ?? 0) *
        ((params.booking.schedule as {nights: number}).nights ?? 0);
  const validation = await validateOfferCampaignForBooking({
    uid: params.uid,
    offerCampaignId,
    booking: params.booking,
    serviceSubtotalAmount: serviceSubtotalPaise / 100,
  });
  if (!validation.ok) {
    throw new HttpsError("failed-precondition", validation.message, {
      code: validation.code,
    });
  }
  return buildLegacyCouponRecordFromCampaignSelection(validation.selection);
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
    channels: ReadonlyArray<string>;
    title: string;
    body: string;
    data: Record<string, string>;
  }>,
  actorId: string,
): void {
  for (const notification of notifications) {
    const notificationRef = db.collection("notifications").doc(notification.idempotencyKey);
    transaction.set(notificationRef, buildStoredBookingNotificationDocument({
      notification,
      actorId,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      source: "canonical_v3",
    }), {merge: true});
  }
}

async function persistNotifications(params: {
  notifications: ReadonlyArray<{
    idempotencyKey: string;
    recipientUserId: string;
    type: string;
    channels: ReadonlyArray<string>;
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
    batch.set(notificationRef, buildStoredBookingNotificationDocument({
      notification,
      actorId: params.actorId,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      source: "canonical_v3",
    }), {merge: true});
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
      channels: ReadonlyArray<string>;
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

async function createProviderRequestReminderIfDue(params: {
  bookingRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
  authoritativeNow: Date;
}): Promise<"created" | "duplicate" | "not_due"> {
  return db.runTransaction(async (transaction) => {
    const bookingSnapshot = await transaction.get(params.bookingRef);
    if (!bookingSnapshot.exists) {
      return "not_due";
    }
    const booking = ensureCanonicalBooking(bookingSnapshot.data());
    const notification = buildProviderRequestReminderIfDueV3({
      bookingId: params.bookingRef.id,
      booking,
      authoritativeNow: params.authoritativeNow,
    });
    if (!notification) {
      return "not_due";
    }
    const notificationRef = db.collection("notifications").doc(notification.idempotencyKey);
    const existingNotification = await transaction.get(notificationRef);
    if (existingNotification.exists) {
      return "duplicate";
    }
    writeNotifications(transaction, [notification], "system");
    return "created";
  });
}

async function createCustomerPaymentReminderIfDue(params: {
  bookingRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
  authoritativeNow: Date;
}): Promise<"created" | "duplicate" | "not_due"> {
  return db.runTransaction(async (transaction) => {
    const bookingSnapshot = await transaction.get(params.bookingRef);
    if (!bookingSnapshot.exists) {
      return "not_due";
    }
    const booking = ensureCanonicalBooking(bookingSnapshot.data());
    const notification = buildCustomerPaymentReminderIfDueV3({
      bookingId: params.bookingRef.id,
      booking,
      authoritativeNow: params.authoritativeNow,
    });
    if (!notification) {
      return "not_due";
    }
    const notificationRef = db.collection("notifications").doc(notification.idempotencyKey);
    const existingNotification = await transaction.get(notificationRef);
    if (existingNotification.exists) {
      return "duplicate";
    }
    writeNotifications(transaction, [notification], "system");
    return "created";
  });
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

export async function closeQrAttemptIfActive(params: {
  bookingId: string;
  paymentAttemptRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
  paymentAttempt: Record<string, unknown>;
  keyId: string;
  keySecret: string;
  authoritativeNow: Date;
  reason: "SUPERSEDED" | "CLOSED" | "EXPIRED";
  localCloseReason?: string;
  closeQr?: typeof closeRazorpayQrCodeV3;
}): Promise<void> {
  const qrCodeId = asString(params.paymentAttempt.razorpayQrCodeId);
  const existingQrState = asString(params.paymentAttempt.qrState);
  const firestore = params.paymentAttemptRef.firestore;
  if (!qrCodeId || !isActiveQrState(existingQrState)) {
    return;
  }
  logger.info("booking-qr-close-start", {
    bookingId: params.bookingId,
    paymentAttemptId: asString(params.paymentAttempt.paymentAttemptId),
    qrCodeId,
    reason: params.reason,
  });
  try {
    const closeQr = params.closeQr ?? closeRazorpayQrCodeV3;
    const closedQr = await closeQr({
      keyId: params.keyId,
      keySecret: params.keySecret,
      qrCodeId,
    });
    await params.paymentAttemptRef.set({
      qrState: params.reason,
      qrClosedAt: closedQr.closedAt ?? Timestamp.fromDate(params.authoritativeNow),
      qrCloseReason: params.localCloseReason || closedQr.closeReason || params.reason,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    await canonicalQrPaymentMappingRef(firestore, qrCodeId).set({
      bookingId: params.bookingId,
      paymentAttemptId: asString(params.paymentAttempt.paymentAttemptId),
      status: params.reason,
      updatedAt: FieldValue.serverTimestamp(),
      closedAt: closedQr.closedAt != null ? Timestamp.fromDate(closedQr.closedAt) : FieldValue.serverTimestamp(),
      closeReason: params.localCloseReason || closedQr.closeReason || params.reason,
    }, {merge: true});
    logger.info("booking-qr-close-success", {
      bookingId: params.bookingId,
      paymentAttemptId: asString(params.paymentAttempt.paymentAttemptId),
      qrCodeId,
      reason: params.reason,
    });
  } catch (error) {
    await params.paymentAttemptRef.set({
      qrState: params.reason,
      qrClosedAt: Timestamp.fromDate(params.authoritativeNow),
      qrCloseReason: params.localCloseReason || params.reason,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    await canonicalQrPaymentMappingRef(firestore, qrCodeId).set({
      bookingId: params.bookingId,
      paymentAttemptId: asString(params.paymentAttempt.paymentAttemptId),
      status: params.reason,
      updatedAt: FieldValue.serverTimestamp(),
      closedAt: FieldValue.serverTimestamp(),
      closeReason: params.localCloseReason || params.reason,
    }, {merge: true});
    logger.warn("booking-qr-close-failed", {
      bookingId: params.bookingId,
      paymentAttemptId: asString(params.paymentAttempt.paymentAttemptId),
      qrCodeId,
      reason: params.reason,
      message: normalizeError(error).message,
    });
  }
}

export async function closeBookingQrAttemptsBestEffort(params: {
  bookingId: string;
  bookingRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
  keyId: string;
  keySecret: string;
  authoritativeNow: Date;
  reason: "SUPERSEDED" | "CLOSED" | "EXPIRED";
  localCloseReason?: string;
  closeQr?: typeof closeRazorpayQrCodeV3;
}): Promise<void> {
  const qrAttemptsSnapshot = await params.bookingRef
    .collection("paymentAttempts")
    .where("paymentMethod", "==", "qr")
    .limit(20)
    .get();
  for (const attemptDoc of qrAttemptsSnapshot.docs) {
    const attempt = attemptDoc.data() as Record<string, unknown>;
    if (!isActiveQrState(asString(attempt.qrState))) continue;
    await closeQrAttemptIfActive({
      bookingId: params.bookingId,
      paymentAttemptRef: attemptDoc.ref,
      paymentAttempt: attempt,
      keyId: params.keyId,
      keySecret: params.keySecret,
      authoritativeNow: params.authoritativeNow,
      reason: params.reason,
      localCloseReason: params.localCloseReason,
      closeQr: params.closeQr,
    });
  }
}

async function retireBookingQrAttemptsForPaymentSwitch(params: {
  booking: CanonicalBookingDocumentV3;
  bookingId: string;
  bookingRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
  keyId: string;
  keySecret: string;
  authoritativeNow: Date;
  reason: "SUPERSEDED";
  localCloseReason: string;
}): Promise<void> {
  const qrAttemptsSnapshot = await params.bookingRef
    .collection("paymentAttempts")
    .where("paymentMethod", "==", "qr")
    .limit(20)
    .get();
  for (const attemptDoc of qrAttemptsSnapshot.docs) {
    const attempt = attemptDoc.data() as Record<string, unknown>;
    const qrState = asString(attempt.qrState).toUpperCase();
    if (qrState !== "ACTIVE") continue;
    if (hasQrCaptureEvidence(attempt)) {
      throw new HttpsError(
        "failed-precondition",
        "An earlier QR payment is still being reconciled. Please wait for Pettxo to finish processing it.",
        {
          code: "PAYMENT_RECONCILIATION_REQUIRED",
          paymentAttemptId: asString(attempt.paymentAttemptId) || attemptDoc.id,
          paymentRail: "qr",
          qrCodeId: asString(attempt.razorpayQrCodeId),
        },
      );
    }
    const lockUntil = resolveQrSwitchLockedUntil({
      booking: params.booking,
      paymentAttempt: attempt,
    });
    if (lockUntil != null && lockUntil.getTime() > params.authoritativeNow.getTime()) {
      throw new HttpsError(
        "failed-precondition",
        "This QR payment is still active for a short safety window.",
        {
          code: "PAYMENT_QR_SWITCH_LOCKED",
          paymentAttemptId: asString(attempt.paymentAttemptId) || attemptDoc.id,
          activeAttemptId: asString(attempt.paymentAttemptId) || attemptDoc.id,
          paymentRail: "qr",
          qrCodeId: asString(attempt.razorpayQrCodeId),
          lockUntil: lockUntil.toISOString(),
        },
      );
    }
    const qrCodeId = asString(attempt.razorpayQrCodeId);
    if (!qrCodeId) continue;
    let closedQr;
    try {
      closedQr = await closeRazorpayQrCodeV3({
        keyId: params.keyId,
        keySecret: params.keySecret,
        qrCodeId,
      });
    } catch (error) {
      throw new HttpsError(
        "failed-precondition",
        "We are checking your previous QR payment before switching payment methods.",
        {
          code: "PAYMENT_RECONCILIATION_REQUIRED",
          paymentAttemptId: asString(attempt.paymentAttemptId) || attemptDoc.id,
          paymentRail: "qr",
          qrCodeId,
          reason: error instanceof Error ? error.message : String(error),
        },
      );
    }
    await attemptDoc.ref.set({
      qrState: params.reason,
      qrClosedAt: closedQr.closedAt ?? Timestamp.fromDate(params.authoritativeNow),
      qrCloseReason: params.localCloseReason || closedQr.closeReason || params.reason,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    await canonicalQrPaymentMappingRef(db, qrCodeId).set({
      bookingId: params.bookingId,
      paymentAttemptId: asString(attempt.paymentAttemptId) || attemptDoc.id,
      status: params.reason,
      updatedAt: FieldValue.serverTimestamp(),
      closedAt: closedQr.closedAt != null ?
        Timestamp.fromDate(closedQr.closedAt) :
        FieldValue.serverTimestamp(),
      closeReason: params.localCloseReason || closedQr.closeReason || params.reason,
    }, {merge: true});
  }
}

function hasBlockingAttemptPaymentEvidence(attempt: Record<string, unknown>): boolean {
  const paymentState = asString(attempt.state).toUpperCase();
  if (isPaymentAttemptUncertainOrCaptured(paymentState)) {
    return true;
  }
  if (asString(attempt.razorpayPaymentId).length > 0) {
    return true;
  }
  if (asNullableDate(attempt.captureReportedAt) != null || asNullableDate(attempt.captureCreatedAt) != null) {
    return true;
  }
  return [
    "PAYMENT_CAPTURED",
    "REFUND_REQUIRED",
    "CONFIRMED",
  ].includes(asString(attempt.qrState).toUpperCase());
}

function hasQrCaptureEvidence(attempt: Record<string, unknown>): boolean {
  return asString(attempt.razorpayPaymentId).length > 0 ||
    asNullableDate(attempt.captureReportedAt) != null ||
    asNullableDate(attempt.captureCreatedAt) != null ||
    [
      "PAYMENT_CAPTURED",
      "CONFIRMED",
      "REFUND_REQUIRED",
      "REFUND_PENDING",
    ].includes(asString(attempt.state).toUpperCase()) ||
    [
      "PAYMENT_CAPTURED",
      "CONFIRMED",
      "REFUND_REQUIRED",
    ].includes(asString(attempt.qrState).toUpperCase());
}

function isQrSwitchLockActive(params: {
  booking: CanonicalBookingDocumentV3;
  attempt: Record<string, unknown>;
  now: Date;
}): boolean {
  const qrState = asString(params.attempt.qrState).toUpperCase();
  if (qrState !== "ACTIVE") return false;
  if (hasQrCaptureEvidence(params.attempt)) return false;
  const lockUntil = resolveQrSwitchLockedUntil({
    booking: params.booking,
    paymentAttempt: params.attempt,
  });
  return lockUntil != null && lockUntil.getTime() > params.now.getTime();
}

async function loadActiveQrSwitchLock(params: {
  booking: CanonicalBookingDocumentV3;
  bookingRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
  now: Date;
}): Promise<{
  paymentAttemptId: string;
  lockUntil: Date;
  qrCodeId: string;
} | null> {
  const attemptsSnapshot = await params.bookingRef
    .collection("paymentAttempts")
    .where("paymentMethod", "==", "qr")
    .limit(20)
    .get();
  for (const attemptDoc of attemptsSnapshot.docs) {
    const attempt = attemptDoc.data() as Record<string, unknown>;
    if (!isQrSwitchLockActive({
      booking: params.booking,
      attempt,
      now: params.now,
    })) {
      continue;
    }
    const lockUntil = resolveQrSwitchLockedUntil({
      booking: params.booking,
      paymentAttempt: attempt,
    });
    if (lockUntil == null) continue;
    return {
      paymentAttemptId: asString(attempt.paymentAttemptId) || attemptDoc.id,
      lockUntil,
      qrCodeId: asString(attempt.razorpayQrCodeId),
    };
  }
  return null;
}

export async function findBlockingBookingPaymentEvidence(params: {
  firestore: FirebaseFirestore.Firestore;
  bookingId: string;
  bookingRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
}): Promise<{
  source: "attempt" | "qr_mapping";
  paymentAttemptId: string;
  razorpayPaymentId: string;
  state: string;
  qrCodeId: string;
} | null> {
  const attemptsSnapshot = await params.bookingRef.collection("paymentAttempts").limit(20).get();
  for (const attemptDoc of attemptsSnapshot.docs) {
    const attempt = attemptDoc.data() as Record<string, unknown>;
    if (!hasBlockingAttemptPaymentEvidence(attempt)) continue;
    return {
      source: "attempt",
      paymentAttemptId: asString(attempt.paymentAttemptId) || attemptDoc.id,
      razorpayPaymentId: asString(attempt.razorpayPaymentId),
      state: asString(attempt.state).toUpperCase(),
      qrCodeId: asString(attempt.razorpayQrCodeId),
    };
  }

  const qrMappingsSnapshot = await params.firestore
    .collection(CANONICAL_QR_PAYMENT_MAPPINGS_COLLECTION)
    .where("bookingId", "==", params.bookingId)
    .limit(20)
    .get();
  for (const mappingDoc of qrMappingsSnapshot.docs) {
    const mapping = mappingDoc.data() as Record<string, unknown>;
    const paymentId = asString(mapping.razorpayPaymentId);
    if (!paymentId) continue;
    return {
      source: "qr_mapping",
      paymentAttemptId: asString(mapping.paymentAttemptId),
      razorpayPaymentId: paymentId,
      state: asString(mapping.status).toUpperCase(),
      qrCodeId: mappingDoc.id,
    };
  }

  return null;
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
    if (params.operation === "provider_actions") {
      logger.warn("booking-provider-action-authorization-rejected", {
        bookingId: params.bookingId,
        rawState: booking.state,
        effectiveState: booking.state,
        now: params.now.toISOString(),
        createdAt: booking.createdAt.toISOString(),
        responseWindowStartsAt: booking.lifecycle.timerStartsAt?.toISOString() ?? null,
        responseDeadlineAt: (booking.acceptDeadlineAt ?? booking.lifecycle.acceptDeadlineAt)?.toISOString() ?? null,
        receivedOutsideWorkingHours: booking.lifecycle.wasQueuedOutsideWorkingHours,
        providerUidMatches: booking.providerId === params.authenticatedUserId,
        rejectionCode: "INVALID_BOOKING_STATE",
        allowedStates: params.allowedStates,
      });
    }
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
  paymentRail?: "checkout" | "qr";
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
    if (requiresContinuationOnly) {
      throw new HttpsError(
        "failed-precondition",
        "This payment is already being finalized or refunded. Please wait for Pettxo to finish processing it.",
        {code: "PAYMENT_RECONCILIATION_REQUIRED"},
      );
    }
    const blockingEvidence = await findBlockingBookingPaymentEvidence({
      firestore: db,
      bookingId: params.bookingId,
      bookingRef,
    });
    if (blockingEvidence) {
      throw new HttpsError(
        "failed-precondition",
        "An earlier payment for this booking is still being reconciled. Please wait for Pettxo to finish processing it.",
        {
          code: "PAYMENT_RECONCILIATION_REQUIRED",
          source: blockingEvidence.source,
          paymentAttemptId: blockingEvidence.paymentAttemptId,
          razorpayPaymentId: blockingEvidence.razorpayPaymentId,
          qrCodeId: blockingEvidence.qrCodeId,
          state: blockingEvidence.state,
        },
      );
    }
    if (params.paymentRail === "checkout") {
      const switchLock = await loadActiveQrSwitchLock({
        booking,
        bookingRef,
        now: params.now,
      });
      if (switchLock) {
        throw new HttpsError(
          "failed-precondition",
          "This QR payment is still active for a short safety window.",
          {
            code: "PAYMENT_QR_SWITCH_LOCKED",
            paymentAttemptId: switchLock.paymentAttemptId,
            activeAttemptId: switchLock.paymentAttemptId,
            paymentRail: "qr",
            qrCodeId: switchLock.qrCodeId,
            lockUntil: switchLock.lockUntil.toISOString(),
          },
        );
      }
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
  let phase = "request_received";
  let providerId = "";
  let schedulingMode = "";
  logRequestEvent("request_callable_invoked", {
    userId: uid,
    serviceId: parsed.serviceId,
    requestAttemptId: parsed.requestAttemptId,
    bookingType: parsed.bookingType,
  });

  try {
    phase = "load_service_and_parent";
    const [service, parent] = await Promise.all([
      loadServiceSnapshot(parsed.serviceId),
      buildParentIdentity(uid),
    ]);
    if (!service) {
      throw new HttpsError("not-found", "Service not found.", {
        code: "SERVICE_NOT_FOUND",
      });
    }

    phase = "infer_booking_type";
    const authoritativeBookingType = inferBookingType(service);
    if (authoritativeBookingType !== parsed.bookingType) {
      throw new HttpsError("invalid-argument", "bookingType does not match the authoritative service.", {
        code: "INVALID_BOOKING_TYPE",
      });
    }

    phase = "authorization_gate";
    const authorization = requireCanonicalGate({
      uid,
      serviceId: parsed.serviceId,
      bookingType: parsed.bookingType,
      service,
      now: authoritativeNow,
    });

    phase = "service_schedule_parse";
    const canonicalService = buildCanonicalServiceSource({
      ...service,
      id: parsed.serviceId,
    });
    providerId = canonicalService.ownerUserId;
    schedulingMode = canonicalService.schedulingMode ?? "";

    phase =
      parsed.bookingType === "SLOT" ?
        "authoritative_slot_selection" :
        "authoritative_range_selection";
    const schedule =
      parsed.bookingType === "SLOT" ?
        await buildAuthoritativeSlotSelection({
          serviceId: parsed.serviceId,
          providerId: canonicalService.ownerUserId,
          slotIds: parsed.slotRequest?.slotIds ?? [],
          unitPricePaise: Math.max(asInt(service.pricePerSession, 0) * 100, 0),
          serviceTimezone: asString(canonicalService.timezone) || "Asia/Kolkata",
          schedulingMode: canonicalService.schedulingMode ?? "",
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

    phase = "create_request_transaction";
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
          providerId,
          serviceId: parsed.serviceId,
          requestAttemptId: parsed.requestAttemptId,
          bookingType: parsed.bookingType,
          code: createResult.code,
          phase,
          scheduleSchemaVersion: schedulingMode || "unspecified",
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
        providerId,
        serviceId: parsed.serviceId,
        requestAttemptId: parsed.requestAttemptId,
        bookingId: result.bookingId,
        matchedRule: authorization.metadata.matchedRule,
      });
    } else {
      logRequestEvent("request_created", {
        userId: uid,
        providerId,
        serviceId: parsed.serviceId,
        requestAttemptId: parsed.requestAttemptId,
        bookingId: result.bookingId,
        state: result.booking.state,
        wasQueuedOutsideWorkingHours:
          result.booking.lifecycle.wasQueuedOutsideWorkingHours,
        matchedRule: authorization.metadata.matchedRule,
      });
    }

    phase = "persist_notifications";
    await persistNotifications({
      notifications: result.notifications,
      actorId: uid,
    });

    return buildRequestResponse(
      result.bookingId,
      result.booking,
      result.code === "IDEMPOTENT_REPLAY",
    );
  } catch (error) {
    const normalizedError = normalizeError(error);
    const detailCode =
      error instanceof HttpsError &&
          typeof error.details === "object" &&
          error.details != null &&
          "code" in (error.details as Record<string, unknown>) ?
        asString((error.details as Record<string, unknown>).code) :
        "";
    const logPayload = {
      customerId: uid,
      providerId,
      serviceId: parsed.serviceId,
      requestAttemptId: parsed.requestAttemptId,
      bookingType: parsed.bookingType,
      phase,
      errorType: normalizedError.name || "Error",
      errorCode: error instanceof HttpsError ? error.code : "internal",
      safeCode: detailCode || (error instanceof HttpsError ? error.code : "internal"),
      scheduleSchemaVersion: schedulingMode || "unspecified",
      errorMessage: normalizedError.message,
      errorStack: normalizedError.stack || "",
    };
    if (error instanceof HttpsError) {
      logger.warn("booking-create-v3-failed", logPayload);
      throw error;
    }
    logger.error("booking-create-v3-failed", logPayload);
    throw new HttpsError("internal", "We could not create the booking request right now.");
  }
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
    allowedStates: [...ACTIONABLE_PROVIDER_REQUEST_STATES],
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
      logger.warn("booking-provider-action-rejected", providerActionLogContext({
        bookingId,
        action: "accept",
        booking,
        authoritativeNow,
        providerUid: uid,
        rejectionCode: lifecycleResult.code,
        rejectionMessage: lifecycleResult.message,
      }));
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
    allowedStates: [...ACTIONABLE_PROVIDER_REQUEST_STATES],
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
      logger.warn("booking-provider-action-rejected", providerActionLogContext({
        bookingId,
        action: "decline",
        booking,
        authoritativeNow,
        providerUid: uid,
        rejectionCode: lifecycleResult.code,
        rejectionMessage: lifecycleResult.message,
      }));
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
    allowedStates: [...ACTIONABLE_PROVIDER_REQUEST_STATES],
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

export const createRazorpayPaymentOrderV3 = onCall(
  canonicalPrivateRazorpayCallableOptions,
  async (request) => {
  const authoritativeNow = new Date();
  const uid = requireUid(request.auth);
  const bookingId = asString(request.data?.bookingId);
  const paymentAttemptId = asString(request.data?.paymentAttemptId);
  const offerCampaignId = asString(request.data?.offerCampaignId);
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }

  const authorized = await authorizeCanonicalPaymentCommand({
    bookingId,
    paymentAttemptId,
    authenticatedUserId: uid,
    command: "create_order",
    paymentRail: "checkout",
    now: authoritativeNow,
  });
  const canonicalService = buildCanonicalServiceSource({
    ...(authorized.service ?? {}),
    id: bookingId ? authorized.booking.serviceId : "",
  });
  const parent = await buildParentIdentity(uid);
  const claimedOffer = await loadSelectedCouponForCheckout({
    uid,
    offerCampaignId,
    booking: authorized.booking,
  });
  const paymentMethod = asString(authorized.paymentAttempt?.paymentMethod) || "checkout";

  if (authorized.paymentAttempt &&
    paymentMethod !== "qr" &&
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
  if (authorized.paymentAttemptRef && authorized.paymentAttempt && paymentMethod === "qr") {
    await retireBookingQrAttemptsForPaymentSwitch({
      booking: authorized.booking,
      bookingId,
      bookingRef: authorized.bookingRef,
      keyId,
      keySecret,
      authoritativeNow,
      reason: "SUPERSEDED",
      localCloseReason: "CHECKOUT_SUPERSEDED_QR",
    });
  } else {
    await retireBookingQrAttemptsForPaymentSwitch({
      booking: authorized.booking,
      bookingId,
      bookingRef: authorized.bookingRef,
      keyId,
      keySecret,
      authoritativeNow,
      reason: "SUPERSEDED",
      localCloseReason: "CHECKOUT_SUPERSEDED_QR",
    });
  }
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
    paymentAttemptId: paymentMethod === "qr" ? undefined : (paymentAttemptId || undefined),
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

export const createBookingQrPaymentV3 = onCall(
  canonicalPrivateRazorpayCallableOptions,
  async (request) => {
  const authoritativeNow = new Date();
  const uid = requireUid(request.auth);
  const bookingId = asString(request.data?.bookingId);
  const offerCampaignId = asString(request.data?.offerCampaignId);
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }

  logger.info("booking-qr-handler-enter", {
    bookingId,
    authPresent: Boolean(request.auth),
    appCheckPresent: Boolean(request.app),
    userId: uid,
  });
  logger.info("booking-qr-create-start", {bookingId, userId: uid});
  const authorized = await authorizeCanonicalPaymentCommand({
    bookingId,
    authenticatedUserId: uid,
    command: "create_order",
    paymentRail: "qr",
    now: authoritativeNow,
  });
  const claimedOffer = await loadSelectedCouponForCheckout({
    uid,
    offerCampaignId,
    booking: authorized.booking,
  });
  const canonicalService = buildCanonicalServiceSource({
    ...(authorized.service ?? {}),
    id: bookingId ? authorized.booking.serviceId : "",
  });
  const availability = validatePreCheckoutAvailabilityV3({
    booking: authorized.booking,
    service: authorized.service,
    authoritativeNow,
  });
  if (!availability.ok) {
    logger.warn("booking-qr-create-failed", {bookingId, code: availability.code});
    throw new HttpsError("failed-precondition", availability.message, {code: availability.code});
  }
  const pricing = resolveCanonicalPricingV3({
    booking: authorized.booking,
    claimedOffer: claimedOffer ?? null,
    authoritativeNow,
  });
  const reusableQrAttemptId = createDeterministicPaymentAttemptId({
    bookingId,
    parentId: authorized.booking.parentId,
    pricingHash: pricing.pricingHash,
    paymentMethod: "qr",
  });
  const reusableQrAttemptRef =
    authorized.bookingRef.collection("paymentAttempts").doc(reusableQrAttemptId);
  const qrAttemptSnapshot = await reusableQrAttemptRef.get();
  const existingQrAttempt = qrAttemptSnapshot.exists ?
    qrAttemptSnapshot.data() as Record<string, unknown> :
    null;
  const qrAttemptId =
    existingQrAttempt != null && !isReusableQrAttempt(existingQrAttempt, authoritativeNow) ?
      authorized.bookingRef.collection("paymentAttempts").doc().id :
      reusableQrAttemptId;
  const qrAttemptRef = authorized.bookingRef.collection("paymentAttempts").doc(qrAttemptId);

  if (pricing.financialSnapshot.customerPaidPaise === 0) {
    const parent = await buildParentIdentity(uid);
    const keyId = asString(RAZORPAY_KEY_ID.value());
    const keySecret = asString(RAZORPAY_KEY_SECRET.value());
    const zeroPayableResult = await createRazorpayPaymentOrderApplicationV3({
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
      paymentAttemptId: qrAttemptId,
    });
    if (!zeroPayableResult.ok) {
      throw new HttpsError("failed-precondition", zeroPayableResult.message, {
        code: zeroPayableResult.code,
      });
    }
    if (zeroPayableResult.code !== "ZERO_PAYABLE_CONFIRMED") {
      throw new HttpsError("failed-precondition", "Zero-payable QR payment did not finalize canonically.", {
        code: zeroPayableResult.code,
      });
    }
    await persistFinalizePaymentResultV3({
      firestore: db,
      result: zeroPayableResult.finalizeResult,
      bookingId,
    });
    await persistNotifications({
      notifications: zeroPayableResult.finalizeResult.notifications,
      actorId: uid,
    });
    return buildQrPaymentResponse({
      bookingId,
      booking: zeroPayableResult.finalizeResult.booking,
      paymentAttemptId: zeroPayableResult.paymentAttempt.paymentAttemptId,
      paymentAttempt: zeroPayableResult.paymentAttempt as unknown as Record<string, unknown>,
      mode: "zero_payable",
      idempotentReplay: zeroPayableResult.finalizeResult.code === "IDEMPOTENT_REPLAY",
    });
  }

  if (isReusableQrAttempt(existingQrAttempt, authoritativeNow)) {
    logger.info("booking-qr-create-reuse", {
      bookingId,
      paymentAttemptId: reusableQrAttemptId,
      qrCodeId: asString(existingQrAttempt?.razorpayQrCodeId),
    });
    return buildQrPaymentResponse({
      bookingId,
      booking: authorized.booking,
      paymentAttemptId: reusableQrAttemptId,
      paymentAttempt: existingQrAttempt,
      mode: "qr",
      idempotentReplay: true,
    });
  }

  const keyId = asString(RAZORPAY_KEY_ID.value());
  const keySecret = asString(RAZORPAY_KEY_SECRET.value());
  await retireBookingQrAttemptsForPaymentSwitch({
    booking: authorized.booking,
    bookingId,
    bookingRef: authorized.bookingRef,
    keyId,
    keySecret,
    authoritativeNow,
    reason: "SUPERSEDED",
    localCloseReason: "QR_SUPERSEDED_BY_NEW_QR",
  });
  const qrExpiryLimit = authorized.booking.lifecycle.payDeadlineAt;
  if (!qrExpiryLimit) {
    throw new HttpsError("failed-precondition", "The payment window has expired.", {
      code: "PAYMENT_WINDOW_EXPIRED",
    });
  }
  const maxRazorpayCloseBy = new Date(authoritativeNow.getTime() + (2 * 60 * 60 * 1000));
  // Razorpay QR Codes require close_by to be sufficiently ahead of current time.
  const minimumRazorpayCloseBy = new Date(authoritativeNow.getTime() + (15 * 60 * 1000));
  const effectiveQrExpiry = new Date(
    Math.min(qrExpiryLimit.getTime(), maxRazorpayCloseBy.getTime()),
  );
  if (effectiveQrExpiry.getTime() <= minimumRazorpayCloseBy.getTime()) {
    throw new HttpsError("failed-precondition", "The payment window is too close to create a QR payment.", {
      code: "PAYMENT_WINDOW_EXPIRED",
    });
  }

  const paymentAttempt = buildPaymentAttemptDocument({
    bookingId,
    booking: authorized.booking,
    pricing,
    paymentAttemptId: qrAttemptId,
    availabilityHash: availability.availabilityHash,
    authoritativeNow,
    paymentMethod: "qr",
  });
  logger.info("booking-qr-create-phase", {
    bookingId,
    paymentAttemptId: paymentAttempt.paymentAttemptId,
    amountPaise: paymentAttempt.amountPaise,
    currency: paymentAttempt.currency,
    closeByEpochSeconds: Math.floor(effectiveQrExpiry.getTime() / 1000),
    paymentWindowEndsAt: qrExpiryLimit.toISOString(),
  });
  const qrCode = await createRazorpayQrCodeV3({
    keyId,
    keySecret,
    bookingId,
    paymentAttemptId: paymentAttempt.paymentAttemptId,
    amountPaise: paymentAttempt.amountPaise,
    currency: paymentAttempt.currency,
    closeBy: effectiveQrExpiry,
    notes: {
      bookingId,
      paymentAttemptId: paymentAttempt.paymentAttemptId,
      purpose: "booking",
    },
  });

  const qrAttempt = {
    ...paymentAttempt,
    state: "ORDER_CREATED" as const,
    orderCreatedAt: authoritativeNow,
    checkoutOpenedAt: authoritativeNow,
    updatedAt: authoritativeNow,
    razorpayQrCodeId: qrCode.id,
    razorpayQrImageUrl: qrCode.imageUrl,
    qrState: "ACTIVE" as const,
    qrCreatedAt: authoritativeNow,
    qrSwitchLockedUntil: resolveQrSwitchLockedUntil({
      booking: authorized.booking,
      paymentAttempt: {
        ...paymentAttempt,
        qrCreatedAt: authoritativeNow,
        qrExpiresAt: qrCode.closeBy ?? effectiveQrExpiry,
      },
    }),
    qrExpiresAt: qrCode.closeBy ?? effectiveQrExpiry,
    qrClosedAt: qrCode.closedAt,
    qrCloseReason: qrCode.closeReason,
  };
  const updatedBooking = buildBookingForOrderReady({
    booking: authorized.booking,
    paymentAttempt: qrAttempt as unknown as Record<string, unknown>,
    financials: qrAttempt.pricingSnapshot.financials as Record<string, unknown>,
    authoritativeNow,
  });
  await db.runTransaction(async (transaction) => {
    transaction.set(authorized.bookingRef, updatedBooking, {merge: false});
    transaction.set(qrAttemptRef, qrAttempt, {merge: false});
    transaction.set(canonicalQrPaymentMappingRef(db, qrCode.id), {
      schemaVersion: 1,
      bookingId,
      paymentAttemptId: qrAttempt.paymentAttemptId,
      customerUid: uid,
      razorpayQrCodeId: qrCode.id,
      status: "ACTIVE",
      createdAt: Timestamp.fromDate(authoritativeNow),
      updatedAt: Timestamp.fromDate(authoritativeNow),
    }, {merge: false});
  });
  logger.info("booking-qr-create-success", {
    bookingId,
    paymentAttemptId: qrAttempt.paymentAttemptId,
    qrCodeId: qrCode.id,
    amountPaise: qrAttempt.amountPaise,
  });
  return buildQrPaymentResponse({
    bookingId,
    booking: updatedBooking,
    paymentAttemptId: qrAttempt.paymentAttemptId,
    paymentAttempt: qrAttempt as unknown as Record<string, unknown>,
    mode: "qr",
    qrCodeId: qrCode.id,
    imageUrl: qrCode.imageUrl,
    amountPaise: qrAttempt.amountPaise,
    currency: qrAttempt.currency,
    expiresAt: qrCode.closeBy ?? effectiveQrExpiry,
    idempotentReplay: false,
  });
});

export const previewBookingPaymentPricingV3 = onCall(
  canonicalPrivateCallableOptions,
  async (request) => {
  const authoritativeNow = new Date();
  const uid = requireUid(request.auth);
  const bookingId = asString(request.data?.bookingId);
  const offerCampaignId = asString(request.data?.offerCampaignId);
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }

  const authorized = await authorizeCanonicalPaymentCommand({
    bookingId,
    authenticatedUserId: uid,
    command: "create_order",
    now: authoritativeNow,
  });
  const claimedOffer = await loadSelectedCouponForCheckout({
    uid,
    offerCampaignId,
    booking: authorized.booking,
  });
  const preview = previewCanonicalPaymentPricingV3({
    bookingId,
    parentId: uid,
    service: authorized.service,
    booking: authorized.booking,
    claimedOffer: claimedOffer ?? undefined,
    authoritativeNow,
  });
  if (!preview.ok) {
    throw new HttpsError("failed-precondition", preview.message, {
      code: preview.code,
    });
  }

  return buildPaymentPricingPreviewResponse({
    bookingId,
    booking: authorized.booking,
    pricingSummary: {
      serviceSubtotalPaise: preview.pricing.serviceSubtotalPaise,
      couponDiscountPaise: preview.pricing.couponDiscountPaise,
      customerPaidPaise: preview.pricing.customerPaidPaise,
      providerPayoutPaise: preview.pricing.financialSnapshot.providerPayoutPaise,
      currency: preview.pricing.financialSnapshot.currency,
    },
    offerCampaignId,
    idempotentReplay: false,
  });
});

export const verifyBookingPaymentV3 = onCall(
  canonicalPrivateRazorpayCallableOptions,
  async (request) => {
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
  const canonicalConfirmedPaymentId =
    asString(authorized.booking.payment.razorpayPaymentId) ||
    asString(authorized.paymentAttempt?.razorpayPaymentId);

  if (
    (authorized.booking.state === "CONFIRMED" || authorized.paymentAttemptState === "CONFIRMED") &&
    canonicalConfirmedPaymentId &&
    canonicalConfirmedPaymentId === razorpayPaymentId
  ) {
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
    if (result.code === "PRIVATE_REPAIR_REQUIRED") {
      throw new HttpsError(
        "failed-precondition",
        "Canonical private booking data requires server-side repair.",
        {
          code: result.code,
        },
      );
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
  await closeBookingQrAttemptsBestEffort({
    bookingId,
    bookingRef: authorized.bookingRef,
    keyId: asString(RAZORPAY_KEY_ID.value()),
    keySecret: asString(RAZORPAY_KEY_SECRET.value()),
    authoritativeNow,
    reason: "CLOSED",
    localCloseReason: "BOOKING_CANCELLED",
  });
  return buildCancellationResponse({
    bookingId,
    booking: result.booking,
    cancellation: result.cancellationRecord,
    idempotentReplay: result.idempotentReplay,
  });
}

export const cancelConfirmedBookingByCustomerV3 = onCall(
  {
    invoker: "private",
    secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET],
  },
  async (request) => cancelConfirmedBookingInternal({request, expectedActor: "parent"}),
);

export const cancelConfirmedBookingByProviderV3 = onCall(
  {
    invoker: "private",
    secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET],
  },
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

    console.info("bookingV3.verifyBookingStartOtpV3.request", {
      bookingId,
      providerUid: uid,
      requestAttemptId,
    });

    const authorized = await authorizeCanonicalBookingCommand({
      bookingId,
      authenticatedUserId: uid,
      expectedActor: "provider",
      allowedStates: ["CONFIRMED", "IN_PROGRESS", "CANCELLED"],
      operation: "continuation",
      now: authoritativeNow,
    });
    console.info("bookingV3.verifyBookingStartOtpV3.authorized", {
      bookingId,
      providerUid: uid,
      state: authorized.booking.state,
      paymentStatus: authorized.booking.payment.status,
      paidAt: authorized.booking.lifecycle.paidAt?.toISOString() ?? null,
    });

    const result = await verifyBookingStartOtpApplicationV3({
      firestore: db,
      bookingId,
      providerId: uid,
      otpCandidate,
      requestAttemptId,
      authoritativeNow,
    });
    console.info("bookingV3.verifyBookingStartOtpV3.result", {
      bookingId,
      providerUid: uid,
      code: result.code,
      state: result.state,
      otpEnteredAt: result.otpEnteredAt?.toISOString() ?? null,
      idempotentReplay: result.idempotentReplay,
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

    console.info("bookingV3.completeBookingServiceV3.request", {
      bookingId,
      providerUid: uid,
    });
    try {
      const bookingSnapshot = await db.collection("bookings").doc(bookingId).get();
      if (!bookingSnapshot.exists) {
        throw new HttpsError("not-found", "Booking not found.", {code: "BOOKING_NOT_FOUND"});
      }
      const booking = ensureCanonicalBooking(bookingSnapshot.data());
      console.info("bookingV3.completeBookingServiceV3.bookingLoaded", {
        bookingId,
        providerUid: uid,
        currentState: booking.state,
        paymentStatus: booking.payment.status,
        hasPaidAt: booking.lifecycle.paidAt != null,
      });
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
      console.info("bookingV3.completeBookingServiceV3.authorized", {
        bookingId,
        providerUid: uid,
        authorizedState: authorized.booking.state,
      });
      const result = await completeBookingServiceApplicationV3({
        firestore: db,
        bookingId,
        providerUid: uid,
      });
      console.info("bookingV3.completeBookingServiceV3.result", {
        bookingId,
        providerUid: uid,
        resultCode: result.code,
        state: result.state,
        idempotentReplay: result.idempotentReplay,
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
        result.code === "BOOKING_SERVICE_NOT_ENDED" ||
        result.code === "INVALID_STATE" ||
        result.code === "INVALID_BOOKING_DATA") {
        throw new HttpsError(
          "failed-precondition",
          result.code === "BOOKING_SERVICE_NOT_ENDED" ?
            "The service has not ended yet. You can complete this booking after the final service end time." :
            "This booking cannot be completed right now.",
          {
            code: result.code,
            state: result.state,
          });
      }
      return buildBookingCompletionResponse({
        ...result,
        state: result.code === "COMPLETED_PENDING_REVIEW" ? "COMPLETED_PENDING_REVIEW" : authorized.booking.state,
      });
    } catch (error) {
      const errorDetails =
        error instanceof HttpsError &&
            typeof error.details === "object" &&
            error.details != null
          ? error.details as Record<string, unknown>
          : null;
      console.error("bookingV3.completeBookingServiceV3.error", {
        bookingId,
        providerUid: uid,
        errorName: error instanceof Error ? error.name : typeof error,
        message: error instanceof Error ? error.message : String(error),
        code:
          error instanceof HttpsError
            ? (typeof errorDetails?.code === "string" ? errorDetails.code : error.code)
            : undefined,
      });
      throw error;
    }
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

    try {
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
      if (result.code === "ALREADY_REVIEWED") {
        throw new HttpsError("already-exists", "A review has already been submitted for this booking.", {
          code: "REVIEW_ALREADY_SUBMITTED",
          state: result.state,
          reviewId: result.reviewId,
        });
      }
      if (result.code === "INVALID_STATE" || result.code === "INVALID_BOOKING_DATA") {
        throw new HttpsError("failed-precondition", "This booking is not ready for review.", {
          code: result.code,
          state: result.state,
        });
      }
      return buildBookingReviewResponse(result);
    } catch (error) {
      const errorDetails =
        error instanceof HttpsError &&
            typeof error.details === "object" &&
            error.details != null
          ? error.details as Record<string, unknown>
          : null;
      console.error("bookingV3.submitBookingReviewV3.error", {
        bookingId,
        parentUid: uid,
        bookingState: booking.state,
        completedAtPresent: booking.completedAt != null || booking.lifecycle.completedAt != null,
        reviewAlreadyExistsKnown:
          Boolean((bookingSnapshot.data() ?? {}).reviewId) ||
          String((bookingSnapshot.data() ?? {}).reviewStatus ?? "").trim().toLowerCase() === "submitted",
        errorName: error instanceof Error ? error.name : typeof error,
        message: error instanceof Error ? error.message : String(error),
        code:
          error instanceof HttpsError
            ? (typeof errorDetails?.code === "string" ? errorDetails.code : error.code)
            : undefined,
      });
      throw error;
    }
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
    const requestedEvidence = normalizeRequestedDisputeEvidence(
      request.data?.evidence,
      rawAttachments,
    );
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
    try {
      const validatedEvidence = await validateBookingDisputeEvidenceUploads({
        bookingId,
        uid,
        requestedEvidence,
      });
      const result = await createBookingDisputeApplicationV3({
        firestore: db,
        bookingId,
        parentUid: uid,
        reason,
        description,
        attachments: validatedEvidence.map((item) => item.storagePath),
        evidenceRecords: validatedEvidence,
      });
      if (result.code === "NOT_FOUND") {
        throw new HttpsError("not-found", "Booking not found.", {code: result.code});
      }
      if (result.code === "UNAUTHORIZED") {
        throw new HttpsError("permission-denied", "Only the customer can raise a dispute.", {
          code: result.code,
        });
      }
      if (result.code === "ALREADY_DISPUTED") {
        throw new HttpsError("already-exists", "A dispute already exists for this booking.", {
          code: result.code,
          state: result.state,
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
    } catch (error) {
      const errorDetails =
        error instanceof HttpsError &&
        typeof error.details === "object" &&
        error.details != null ?
          error.details as Record<string, unknown> :
          undefined;
      console.error("bookingV3.createBookingDisputeV3.error", {
        bookingId,
        callerUid: uid,
        callerOwnsBooking: booking.parentId === uid,
        bookingState: booking.state,
        nestedDisputeDeadlinePresent: booking.lifecycle.disputeDeadlineAt != null,
        reviewWindowFallbackPresent: booking.lifecycle.reviewWindowEndsAt != null,
        existingDisputeStatus: booking.dispute.status,
        reasonPresent: reason.length > 0,
        descriptionLength: description.length,
        evidenceCount: requestedEvidence.length,
        code:
          error instanceof HttpsError ?
            (typeof errorDetails?.code === "string" ? errorDetails.code : error.code) :
            undefined,
        message: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
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
            | "CUSTOM_ALLOCATION"
            | "PARTIAL_REFUND"
            | "CUSTOM_ADJUSTMENT",
        policyReason: asString(data.policyReason),
        notes: asString(data.notes),
        resolutionAttemptId: asString(data.resolutionAttemptId),
        customerAllocationBasisPoints:
          data.customerAllocationBasisPoints == null ?
            null :
            asInt(data.customerAllocationBasisPoints, 0),
        providerAllocationBasisPoints:
          data.providerAllocationBasisPoints == null ?
            null :
            asInt(data.providerAllocationBasisPoints, 0),
        pettxoAllocationBasisPoints:
          data.pettxoAllocationBasisPoints == null ?
            null :
            asInt(data.pettxoAllocationBasisPoints, 0),
        customerRefundBasisPoints:
          data.customerRefundBasisPoints == null ?
            null :
            asInt(data.customerRefundBasisPoints, 0),
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

export const previewBookingDisputeResolutionV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const uid = requireUid(request.auth);
    await requireFinanceAdmin(uid);
    const data =
      typeof request.data === "object" && request.data != null ?
        request.data as Record<string, unknown> :
        {};
    const result = await previewBookingDisputeResolutionApplicationV3({
      firestore: db,
      auth: request.auth,
      input: {
        disputeId: asString(data.disputeId),
        bookingId: asString(data.bookingId),
        resolutionType:
          asString(data.resolutionType) as
            | "CUSTOMER_WINS"
            | "PROVIDER_WINS"
            | "CUSTOM_ALLOCATION"
            | "PARTIAL_REFUND"
            | "CUSTOM_ADJUSTMENT",
        policyReason: asString(data.policyReason),
        notes: asString(data.notes),
        resolutionAttemptId: asString(data.resolutionAttemptId) || "preview",
        customerAllocationBasisPoints:
          data.customerAllocationBasisPoints == null ?
            null :
            asInt(data.customerAllocationBasisPoints, 0),
        providerAllocationBasisPoints:
          data.providerAllocationBasisPoints == null ?
            null :
            asInt(data.providerAllocationBasisPoints, 0),
        pettxoAllocationBasisPoints:
          data.pettxoAllocationBasisPoints == null ?
            null :
            asInt(data.pettxoAllocationBasisPoints, 0),
        customerRefundBasisPoints:
          data.customerRefundBasisPoints == null ?
            null :
            asInt(data.customerRefundBasisPoints, 0),
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
    return buildDisputeResolutionPreviewResponse(result);
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
    let processed = 0;
    let scanned = 0;
    for (const state of ACTIONABLE_PROVIDER_REQUEST_STATES) {
      const dueSnapshot = await db
        .collection("bookings")
        .where("stateQueryValue", "==", state)
        .where("acceptDeadlineAt", "<=", Timestamp.fromDate(authoritativeNow))
        .limit(100)
        .get();
      scanned += dueSnapshot.size;
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
    }

    console.info("bookingV3.scheduler.providerExpiry", {
      processed,
      scanned,
      authoritativeAt: authoritativeNow.toISOString(),
    });
  },
);

export const sendProviderRequestRemindersV3 = onSchedule(
  {schedule: "every 5 minutes", timeZone: "Asia/Kolkata"},
  async () => {
    const authoritativeNow = new Date();
    const providerReminderDeadline = new Date(authoritativeNow.getTime() + (ACCEPT_WINDOW_MS / 2));
    const customerReminderDeadline = new Date(authoritativeNow.getTime() + (ACCEPT_WINDOW_MS / 2));
    let scanned = 0;
    let created = 0;
    let duplicates = 0;

    for (const state of ACTIONABLE_PROVIDER_REQUEST_STATES) {
      const snapshot = await db
        .collection("bookings")
        .where("stateQueryValue", "==", state)
        .where("acceptDeadlineAt", ">", Timestamp.fromDate(authoritativeNow))
        .where("acceptDeadlineAt", "<=", Timestamp.fromDate(providerReminderDeadline))
        .limit(100)
        .get();
      scanned += snapshot.size;
      for (const doc of snapshot.docs) {
        const result = await createProviderRequestReminderIfDue({
          bookingRef: doc.ref,
          authoritativeNow,
        });
        if (result === "created") {
          created += 1;
        } else if (result === "duplicate") {
          duplicates += 1;
        }
      }
    }

    const paymentSnapshot = await db
      .collection("bookings")
      .where("stateQueryValue", "==", "ACCEPTED_AWAITING_PAYMENT")
      .where("payDeadlineAt", ">", Timestamp.fromDate(authoritativeNow))
      .where("payDeadlineAt", "<=", Timestamp.fromDate(customerReminderDeadline))
      .limit(100)
      .get();
    scanned += paymentSnapshot.size;
    for (const doc of paymentSnapshot.docs) {
      const result = await createCustomerPaymentReminderIfDue({
        bookingRef: doc.ref,
        authoritativeNow,
      });
      if (result === "created") {
        created += 1;
      } else if (result === "duplicate") {
        duplicates += 1;
      }
    }

    console.info("bookingV3.scheduler.providerRequestReminders", {
      scanned,
      created,
      duplicates,
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
          const expiredAttemptWrite: Record<string, unknown> = {
            state: "EXPIRED",
            nextReconciliationAt: null,
            terminalFailureAt: FieldValue.serverTimestamp(),
            lastReconciledAt: FieldValue.serverTimestamp(),
            lastReconciliationCode: "PAYMENT_WINDOW_EXPIRED",
            updatedAt: FieldValue.serverTimestamp(),
          };
          if (asString(attempt.data.paymentMethod) === "qr") {
            expiredAttemptWrite.qrState = "EXPIRED";
            expiredAttemptWrite.qrClosedAt = FieldValue.serverTimestamp();
            expiredAttemptWrite.qrCloseReason = "PAYMENT_WINDOW_EXPIRED";
          }
          batch.set(attempt.ref, expiredAttemptWrite, {merge: true});
          expiredAttempts += 1;
        }
        await batch.commit();
      }
      await closeBookingQrAttemptsBestEffort({
        bookingId: doc.id,
        bookingRef: doc.ref,
        keyId,
        keySecret,
        authoritativeNow,
        reason: "EXPIRED",
        localCloseReason: "PAYMENT_WINDOW_EXPIRED",
      });
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

type NoShowBucketState = "CONFIRMED" | "IN_PROGRESS";

type SchedulerLogger = Pick<typeof logger, "info" | "error">;

type NoShowScanStats = {
  scanned: number;
  noShowFinalized: number;
  repairedStarts: number;
};

export const finalizeCanonicalNoShowsV3 = onSchedule(
  {schedule: "every 30 minutes", timeZone: "Asia/Kolkata"},
  async () => {
    await runFinalizeCanonicalNoShowsSchedulerV3();
  },
);

export async function runFinalizeCanonicalNoShowsSchedulerV3(params?: {
  authoritativeNow?: Date;
  schedulerLogger?: SchedulerLogger;
  scanStateBucket?: (args: {
    stateQueryValue: NoShowBucketState;
    authoritativeNow: Date;
    schedulerLogger: SchedulerLogger;
  }) => Promise<NoShowScanStats>;
}): Promise<void> {
  const authoritativeNow = params?.authoritativeNow ?? new Date();
  const schedulerLogger = params?.schedulerLogger ?? logger;
  const scanStateBucket =
    params?.scanStateBucket ??
    ((args: {
      stateQueryValue: NoShowBucketState;
      authoritativeNow: Date;
      schedulerLogger: SchedulerLogger;
    }) => scanCanonicalNoShowCandidatesByStateV3(args));

  schedulerLogger.info("bookingV3.scheduler.noShowFinalization.started", {
    schedule: "every 30 minutes",
    timeZone: "Asia/Kolkata",
    authoritativeAt: authoritativeNow.toISOString(),
  });

  try {
    const confirmedStats = await scanStateBucket({
      stateQueryValue: "CONFIRMED",
      authoritativeNow,
      schedulerLogger,
    });
    const inProgressStats = await scanStateBucket({
      stateQueryValue: "IN_PROGRESS",
      authoritativeNow,
      schedulerLogger,
    });

    schedulerLogger.info("bookingV3.scheduler.noShowFinalization.completed", {
      confirmedScanned: confirmedStats.scanned,
      inProgressScanned: inProgressStats.scanned,
      noShowFinalized:
        confirmedStats.noShowFinalized + inProgressStats.noShowFinalized,
      repairedStarts:
        confirmedStats.repairedStarts + inProgressStats.repairedStarts,
      authoritativeAt: authoritativeNow.toISOString(),
    });
  } catch (error) {
    const normalized = normalizeError(error);
    schedulerLogger.error("bookingV3.scheduler.noShowFinalization.failed", {
      message: normalized.message,
      stack: normalized.stack,
      authoritativeAt: authoritativeNow.toISOString(),
    });
    throw normalized;
  }
}

const NO_SHOW_SCAN_BATCH_SIZE = 100;

export async function scanCanonicalNoShowCandidatesByStateV3(params: {
  stateQueryValue: NoShowBucketState;
  authoritativeNow: Date;
  schedulerLogger?: SchedulerLogger;
  firestore?: typeof db;
  reconcileBooking?: typeof reconcileCanonicalServiceStartArtifactsV3;
}): Promise<NoShowScanStats> {
  const schedulerLogger = params.schedulerLogger ?? logger;
  const firestore = params.firestore ?? db;
  const reconcileBooking =
    params.reconcileBooking ?? reconcileCanonicalServiceStartArtifactsV3;
  let scanned = 0;
  let noShowFinalized = 0;
  let repairedStarts = 0;
  let lastDocumentId: string | null = null;
  let pageNumber = 0;

  schedulerLogger.info("bookingV3.scheduler.noShowFinalization.stateBucket.started", {
    stateQueryValue: params.stateQueryValue,
    authoritativeAt: params.authoritativeNow.toISOString(),
  });

  while (true) {
    let query = firestore
      .collection("bookings")
      .where("stateQueryValue", "==", params.stateQueryValue)
      .orderBy(FieldPath.documentId())
      .limit(NO_SHOW_SCAN_BATCH_SIZE);
    if (lastDocumentId != null) {
      query = query.startAfter(lastDocumentId);
    }

    const snapshot = await query.get();
    if (snapshot.empty) break;

    pageNumber += 1;
    schedulerLogger.info("bookingV3.scheduler.noShowFinalization.pageLoaded", {
      stateQueryValue: params.stateQueryValue,
      pageNumber,
      pageSize: snapshot.size,
      lastDocumentId,
    });

    scanned += snapshot.size;
    for (const doc of snapshot.docs) {
      try {
        const result = await reconcileBooking({
          firestore,
          bookingId: doc.id,
          authoritativeNow: params.authoritativeNow,
        });
        if (result === "NO_SHOW_FINALIZED") {
          noShowFinalized += 1;
        } else if (result === "REPAIRED") {
          repairedStarts += 1;
        }
        schedulerLogger.info("bookingV3.scheduler.noShowFinalization.bookingProcessed", {
          bookingId: doc.id,
          stateQueryValue: params.stateQueryValue,
          outcome: result,
        });
      } catch (error) {
        const normalized = normalizeError(error);
        schedulerLogger.error("bookingV3.scheduler.noShowFinalization.bookingFailed", {
          bookingId: doc.id,
          stateQueryValue: params.stateQueryValue,
          message: normalized.message,
          stack: normalized.stack,
        });
        throw normalized;
      }
    }

    lastDocumentId = snapshot.docs[snapshot.docs.length - 1]?.id ?? null;
    if (snapshot.size < NO_SHOW_SCAN_BATCH_SIZE) break;
  }

  schedulerLogger.info("bookingV3.scheduler.noShowFinalization.stateBucket.completed", {
    stateQueryValue: params.stateQueryValue,
    scanned,
    noShowFinalized,
    repairedStarts,
    pages: pageNumber,
    authoritativeAt: params.authoritativeNow.toISOString(),
  });

  return {
    scanned,
    noShowFinalized,
    repairedStarts,
  };
}

export const finalizeCompletedBookingsV3 = onSchedule(
  {schedule: "every 15 minutes", timeZone: "Asia/Kolkata"},
  async () => {
    await runFinalizeCompletedBookingsSchedulerV3();
  },
);

const COMPLETION_SCAN_BATCH_SIZE = 100;

export async function runFinalizeCompletedBookingsSchedulerV3(params?: {
  authoritativeNow?: Date;
  firestore?: typeof db;
  schedulerLogger?: Pick<typeof logger, "info" | "error">;
}): Promise<void> {
  const authoritativeNow = params?.authoritativeNow ?? new Date();
  const firestore = params?.firestore ?? db;
  const schedulerLogger = params?.schedulerLogger ?? logger;

  schedulerLogger.info("bookingV3.scheduler.completedFinalization.started", {
    schedule: "every 15 minutes",
    timeZone: "Asia/Kolkata",
    authoritativeAt: authoritativeNow.toISOString(),
  });

  let scannedInProgress = 0;
  let autoCompletedPendingReview = 0;
  let scannedCompletedPendingReview = 0;
  let finalized = 0;
  let lastInProgressId: string | null = null;
  let lastCompletedId: string | null = null;

  while (true) {
    let query = firestore
      .collection("bookings")
      .where("stateQueryValue", "==", "IN_PROGRESS")
      .orderBy(FieldPath.documentId())
      .limit(COMPLETION_SCAN_BATCH_SIZE);
    if (lastInProgressId != null) {
      query = query.startAfter(lastInProgressId);
    }
    const snapshot = await query.get();
    if (snapshot.empty) break;
    scannedInProgress += snapshot.size;
    for (const doc of snapshot.docs) {
      try {
        const result = await reconcileCanonicalCompletionStateV3({
          firestore,
          bookingId: doc.id,
          authoritativeNow,
        });
        if (result === "AUTO_COMPLETED_PENDING_REVIEW") {
          autoCompletedPendingReview += 1;
        }
      } catch (error) {
        const normalized = normalizeError(error);
        schedulerLogger.error("bookingV3.scheduler.completedFinalization.inProgressBookingFailed", {
          bookingId: doc.id,
          message: normalized.message,
          stack: normalized.stack,
        });
      }
    }
    lastInProgressId = snapshot.docs[snapshot.docs.length - 1]?.id ?? null;
    if (snapshot.size < COMPLETION_SCAN_BATCH_SIZE) break;
  }

  while (true) {
    let query = firestore
      .collection("bookings")
      .where("stateQueryValue", "==", "COMPLETED_PENDING_REVIEW")
      .orderBy(FieldPath.documentId())
      .limit(COMPLETION_SCAN_BATCH_SIZE);
    if (lastCompletedId != null) {
      query = query.startAfter(lastCompletedId);
    }
    const snapshot = await query.get();
    if (snapshot.empty) break;
    scannedCompletedPendingReview += snapshot.size;
    for (const doc of snapshot.docs) {
      try {
        const result = await finalizeCompletedBookingApplicationV3({
          firestore,
          bookingId: doc.id,
          authoritativeNow,
        });
        if (result.code === "FINALIZED") {
          finalized += 1;
        }
      } catch (error) {
        const normalized = normalizeError(error);
        schedulerLogger.error("bookingV3.scheduler.completedFinalization.completedBookingFailed", {
          bookingId: doc.id,
          message: normalized.message,
          stack: normalized.stack,
        });
      }
    }
    lastCompletedId = snapshot.docs[snapshot.docs.length - 1]?.id ?? null;
    if (snapshot.size < COMPLETION_SCAN_BATCH_SIZE) break;
  }

  schedulerLogger.info("bookingV3.scheduler.completedFinalization.completed", {
    scannedInProgress,
    autoCompletedPendingReview,
    scannedCompletedPendingReview,
    finalized,
    authoritativeAt: authoritativeNow.toISOString(),
  });
}
