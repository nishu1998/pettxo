import {createHash, randomInt} from "node:crypto";

import {FieldValue, Timestamp, type Firestore, type Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/https";

import {auth} from "../../shared/firebase";
import {
  PAY_WINDOW_MS,
  PLATFORM_COMMISSION_BASIS_POINTS,
} from "../domain/bookingConstants";
import {calculateBookingFinancialSnapshot} from "../domain/bookingPricing";
import type {
  CanonicalBookingDocumentV3,
  BookingPrivateParticipantsDocumentV3,
  CanonicalRangeScheduleV3,
  CanonicalSlotScheduleV3,
} from "../schema/bookingDocumentV3";
import type {
  CanonicalBookingPrivateDocumentV3,
  CanonicalPaymentAttemptDocumentV3,
  CanonicalCouponSnapshotV3,
} from "../schema/paymentAttemptDocumentV3";
import {
  CANONICAL_PAYMENT_ATTEMPT_SCHEMA_VERSION,
  parseCanonicalPaymentAttemptDocumentV3,
} from "../schema/paymentAttemptDocumentV3";
import {parseCanonicalBookingDocumentV3} from "../schema/bookingDocumentV3";
import {normalizeTimestampLike} from "../schema/timestampNormalization";
import {buildStoredBookingNotificationDocument} from "../../notifications/notificationChannels";
import {
  type ValidatedOfferCampaignSelection,
} from "../../offers/application/validateOfferCampaignForBooking";
import {consumeOfferUsageInTransaction} from "../../offers/application/consumeOfferUsage";
import type {AuthenticatedParentIdentity, CanonicalServiceSource} from "./createBookingRequestV3";
import {buildBookingEventPlan, type BookingEventWritePlan} from "./bookingEventsWriter";
import {
  buildBookingConfirmedNotification,
  buildPaymentFailedNotification,
  buildPaymentOrderReadyNotification,
  buildPaymentRefundRequiredNotification,
  buildZeroPayableConfirmationNotification,
  type BookingNotificationPlan,
} from "./bookingNotificationsV3";
import type {ParentStatsV3} from "./bookingStats";
import {applyParentStatsMutation, emptyParentStatsV3} from "./bookingStats";
import {
  createRazorpayOrderV3,
  processRazorpayRefundV3,
  resolveCapturedRazorpayPaymentV3,
  type RazorpayPaymentRecord,
} from "./razorpayGateway";

const CAPTURE_DEADLINE_TOLERANCE_MS = 2 * 60 * 1000;
const MAX_RANGE_OCCUPANCY_NIGHTS = 30;
const RECONCILIATION_LEASE_MS = 2 * 60 * 1000;
const RECONCILIATION_BASE_BACKOFF_MS = 30 * 1000;
const RECONCILIATION_MAX_BACKOFF_MS = 15 * 60 * 1000;
const DEFAULT_RECONCILIATION_LIMIT = 25;
export const CANONICAL_RECONCILIATION_ATTEMPT_STATES = [
  "CAPTURE_REPORTED",
  "CONFIRMING",
  "CAPTURED_REQUIRES_RECONCILIATION",
  "REFUND_REQUIRED",
  "REFUND_PENDING",
] as const;

export const CANONICAL_PAYMENT_ORDER_MAPPINGS_COLLECTION =
  "canonicalPaymentOrderMappings";

export type CanonicalPricingResolution = {
  financialSnapshot: NonNullable<CanonicalBookingDocumentV3["financials"]>;
  couponSnapshot: CanonicalCouponSnapshotV3 | null;
  pricingHash: string;
  serviceSubtotalPaise: number;
  couponDiscountPaise: number;
  customerPaidPaise: number;
};

export type PreCheckoutAvailabilityCode =
  | "OK"
  | "PAYMENT_WINDOW_EXPIRED"
  | "BOOKING_NOT_PAYABLE"
  | "SERVICE_UNAVAILABLE"
  | "PROVIDER_UNAVAILABLE"
  | "SLOT_NO_LONGER_AVAILABLE"
  | "SLOT_CONFIGURATION_CHANGED"
  | "RANGE_NO_LONGER_AVAILABLE"
  | "CAPACITY_EXHAUSTED"
  | "COUPON_INVALID"
  | "PRICING_CHANGED"
  | "MALFORMED_BOOKING";

export type PreCheckoutAvailabilityResult =
  | {
      ok: true;
      code: "OK";
      availabilityHash: string;
    }
  | {
      ok: false;
      code: Exclude<PreCheckoutAvailabilityCode, "OK">;
      message: string;
    };

export type PaymentAttemptOrderResult =
  | {
      ok: true;
      code: "ORDER_READY";
      paymentAttempt: CanonicalPaymentAttemptDocumentV3;
      order: {
        bookingId: string;
        paymentAttemptId: string;
        razorpayOrderId: string;
        keyId: string;
        amountPaise: number;
        currency: string;
        paymentExpiresAt: Date;
        serviceSubtotalPaise: number;
        couponDiscountPaise: number;
        customerPaidPaise: number;
      };
      events: BookingEventWritePlan[];
      notifications: BookingNotificationPlan[];
    }
  | {
      ok: true;
      code: "ZERO_PAYABLE_CONFIRMED";
      paymentAttempt: CanonicalPaymentAttemptDocumentV3;
      finalizeResult: FinalizePaymentResult;
    }
  | {
      ok: false;
      code: string;
      message: string;
    };

export type FinalizePaymentSuccess = {
  ok: true;
  code: "CONFIRMED" | "IDEMPOTENT_REPLAY";
  booking: CanonicalBookingDocumentV3;
  paymentAttempt: CanonicalPaymentAttemptDocumentV3;
  bookingPrivate: CanonicalBookingPrivateDocumentV3;
  bookingPrivateParticipants: BookingPrivateParticipantsDocumentV3;
  otpCode: string;
  occupancyWrites: Record<string, Record<string, unknown>>;
  financialWrites: {
    bookingFinancial: Record<string, unknown>;
    payment: Record<string, unknown>;
    invoice: Record<string, unknown>;
    providerEarning: Record<string, unknown>;
    payoutReadiness: Record<string, unknown>;
    bookingChat: Record<string, unknown>;
  };
  couponWrite: {
    offerUsagePath: string;
    offerCampaignId: string;
    bookingId: string;
    paymentAttemptId: string;
    couponCode: string;
    usageLimitPerUser: number | null;
  } | null;
  events: BookingEventWritePlan[];
  notifications: BookingNotificationPlan[];
  parentStats: ParentStatsV3;
  privateWritePlan?: {
    writeBookingPrivate: boolean;
    writeBookingPrivateParticipants: boolean;
  };
};

export type FinalizePaymentFailure = {
  ok: false;
  code: "REFUND_REQUIRED" | "PAYMENT_EXPIRED" | "CAPACITY_EXHAUSTED" | "MALFORMED_BOOKING" | "PRIVATE_REPAIR_REQUIRED";
  booking: CanonicalBookingDocumentV3;
  paymentAttempt: CanonicalPaymentAttemptDocumentV3;
  refundInstruction: Record<string, unknown> | null;
  notifications: BookingNotificationPlan[];
  events: BookingEventWritePlan[];
  message: string;
};

export type FinalizePaymentResult = FinalizePaymentSuccess | FinalizePaymentFailure;

export type CanonicalPaymentFinalizeSource =
  | "callable"
  | "webhook"
  | "reconciliation"
  | "zero_payable";

export type CanonicalCapturedPaymentFacts = {
  bookingId: string;
  paymentAttemptId: string;
  razorpayOrderId: string;
  razorpayPaymentId: string;
  capturedAmountPaise: number;
  currency: string;
  capturedAt: Date;
  verificationSource: Exclude<CanonicalPaymentFinalizeSource, "zero_payable">;
  sourceEventId?: string;
};

export type LiveServiceSnapshot = {
  status?: string;
  isActive?: boolean;
  isDeleted?: boolean;
  isPaused?: boolean;
  isVisibleToMarketplace?: boolean;
  providerVerificationStatus?: string;
  providerVerificationGraceEndsAt?: Date | null;
  isPausedByVerification?: boolean;
  location?: {
    displayAddress?: string;
    latitude?: number | null;
    longitude?: number | null;
  };
};

type AuthenticatedProviderPrivateIdentity = {
  uid: string;
  phoneNumber?: string;
};

type ClaimedOfferDocument = Record<string, unknown> | null;

export function buildLegacyCouponRecordFromCampaignSelection(
  selection: ValidatedOfferCampaignSelection,
): Record<string, unknown> {
  return {
    offerCampaignId: selection.offerCampaignId,
    offerId: selection.offerCampaignId,
    couponCode: selection.couponCode,
    discountType: selection.discountType,
    discountValue: selection.discountValue,
    maxDiscountAmount: selection.maxDiscountAmount,
    minBookingAmount: selection.minBookingAmount,
    campaignType: selection.campaignType,
    usageLimit: selection.usageLimitPerUser,
    usedCount: selection.usedCount,
    status: "claimed",
    validUntil: selection.validUntil,
    serviceIds: selection.serviceIds,
    providerIds: selection.providerIds,
    categoryRestrictions: selection.categoryRestrictions,
    campaignSnapshot: {
      title: selection.title,
      description: selection.description,
      campaignType: selection.campaignType,
    },
  };
}

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

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asInt(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value) ? Math.trunc(value) : fallback;
}

function asFiniteNumber(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function asNullableDate(value: unknown): Date | null {
  return normalizeTimestampLike(value);
}

function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value != null ? value as Record<string, unknown> : {};
}

function logMalformedPaymentSnapshot(params: {
  kind: "booking" | "payment_attempt";
  bookingId: string;
  paymentAttemptId: string;
  issues: ReadonlyArray<{code: string; path: string; message: string}>;
}): void {
  void params;
}

function requireCanonicalBookingForPaymentFinalization(params: {
  rawBooking: unknown;
  bookingId: string;
  paymentAttemptId: string;
}): CanonicalBookingDocumentV3 {
  const parsed = parseCanonicalBookingDocumentV3(params.rawBooking);
  if (parsed.ok) return parsed.booking;
  logMalformedPaymentSnapshot({
    kind: "booking",
    bookingId: params.bookingId,
    paymentAttemptId: params.paymentAttemptId,
    issues: parsed.issues,
  });
  throw new HttpsError(
    "failed-precondition",
    "Canonical booking snapshot is malformed for payment finalization.",
    {
      code: "MALFORMED_BOOKING",
      bookingId: params.bookingId,
      paymentAttemptId: params.paymentAttemptId,
    },
  );
}

function requireCanonicalPaymentAttemptForFinalization(params: {
  rawAttempt: unknown;
  bookingId: string;
  paymentAttemptId: string;
}): CanonicalPaymentAttemptDocumentV3 {
  const parsed = parseCanonicalPaymentAttemptDocumentV3(params.rawAttempt);
  if (parsed.ok) return parsed.value;
  logMalformedPaymentSnapshot({
    kind: "payment_attempt",
    bookingId: params.bookingId,
    paymentAttemptId: params.paymentAttemptId,
    issues: parsed.issues,
  });
  throw new HttpsError(
    "failed-precondition",
    "Canonical payment attempt snapshot is malformed for payment finalization.",
    {
      code: "MALFORMED_PAYMENT_ATTEMPT",
      bookingId: params.bookingId,
      paymentAttemptId: params.paymentAttemptId,
    },
  );
}

function cloneBooking(booking: CanonicalBookingDocumentV3): CanonicalBookingDocumentV3 {
  return structuredClone(booking);
}

function cloneAttempt(
  paymentAttempt: CanonicalPaymentAttemptDocumentV3,
): CanonicalPaymentAttemptDocumentV3 {
  return structuredClone(paymentAttempt);
}

function slotSchedule(booking: CanonicalBookingDocumentV3): CanonicalSlotScheduleV3 {
  return booking.schedule as CanonicalSlotScheduleV3;
}

function rangeSchedule(booking: CanonicalBookingDocumentV3): CanonicalRangeScheduleV3 {
  return booking.schedule as CanonicalRangeScheduleV3;
}

function hashValue(payload: unknown): string {
  return createHash("sha256").update(JSON.stringify(payload)).digest("hex");
}

function calculateServiceSubtotalPaise(booking: CanonicalBookingDocumentV3): number {
  if (booking.bookingType === "SLOT") {
    return slotSchedule(booking).slots.reduce(
      (sum: number, slot) => sum + slot.unitPricePaise,
      0,
    );
  }
  const pricePerNightPaise = booking.service.pricePerNightPaise ?? 0;
  return pricePerNightPaise * rangeSchedule(booking).nights;
}

function bookingAnchorAt(booking: CanonicalBookingDocumentV3): Date {
  return booking.bookingType === "SLOT" ?
    slotSchedule(booking).scheduledStartAt :
    rangeSchedule(booking).checkInDateTime;
}

function bookingCapacityUnits(booking: CanonicalBookingDocumentV3): number {
  if (booking.bookingType === "RANGE" && rangeSchedule(booking).petQuantity != null) {
    return Math.max(rangeSchedule(booking).petQuantity ?? 1, 1);
  }
  return 1;
}

function validateCouponAgainstBooking(params: {
  booking: CanonicalBookingDocumentV3;
  claimedOffer: ClaimedOfferDocument;
  serviceSubtotalPaise: number;
  authoritativeNow: Date;
}): {
  ok: true;
  couponDiscountPaise: number;
  couponSnapshot: CanonicalCouponSnapshotV3 | null;
} | {
  ok: false;
  message: string;
} {
  const claimedOffer = params.claimedOffer;
  if (claimedOffer == null) {
    return {ok: true, couponDiscountPaise: 0, couponSnapshot: null};
  }
  const status = asString(claimedOffer.status);
  const validUntil = asNullableDate(claimedOffer.validUntil);
  const usageLimit = Math.max(asInt(claimedOffer.usageLimit, 0), 0);
  const usedCount = Math.max(asInt(claimedOffer.usedCount, 0), 0);
  const minBookingAmountPaise = Math.max(
    Math.round(asFiniteNumber(claimedOffer.minBookingAmount, 0) * 100),
    0,
  );
  const maxDiscountAmountPaise = Math.max(
    Math.round(asFiniteNumber(claimedOffer.maxDiscountAmount, 0) * 100),
    0,
  );
  const discountType = asString(claimedOffer.discountType);
  const discountValue = asFiniteNumber(claimedOffer.discountValue, 0);
  const couponClaimId = asString(claimedOffer.claimedOfferId) || asString(claimedOffer.id);
  const couponId =
    asString(claimedOffer.offerCampaignId) ||
    asString(claimedOffer.offerId) ||
    couponClaimId;
  const campaignSnapshot = asRecord(claimedOffer.campaignSnapshot);
  const serviceRestrictions = Array.isArray(claimedOffer.serviceIds) ?
    claimedOffer.serviceIds.map((entry) => asString(entry)).filter(Boolean) :
    [];
  const providerRestrictions = Array.isArray(claimedOffer.providerIds) ?
    claimedOffer.providerIds.map((entry) => asString(entry)).filter(Boolean) :
    [];
  const categoryRestrictions = Array.isArray(claimedOffer.categoryRestrictions) ?
    claimedOffer.categoryRestrictions.map((entry) => asString(entry)).filter(Boolean) :
    [];

  if (status && status !== "claimed") {
    return {ok: false, message: "Coupon is no longer active."};
  }
  if (validUntil && validUntil.getTime() < params.authoritativeNow.getTime()) {
    return {ok: false, message: "Coupon has expired."};
  }
  if (usageLimit > 0 && usedCount >= usageLimit) {
    return {ok: false, message: "Coupon has already been fully used."};
  }
  if (minBookingAmountPaise > 0 && params.serviceSubtotalPaise < minBookingAmountPaise) {
    return {ok: false, message: "Coupon minimum booking amount is not met."};
  }
  if (serviceRestrictions.length > 0 && !serviceRestrictions.includes(params.booking.serviceId)) {
    return {ok: false, message: "Coupon does not apply to this service."};
  }
  if (providerRestrictions.length > 0 && !providerRestrictions.includes(params.booking.providerId)) {
    return {ok: false, message: "Coupon does not apply to this provider."};
  }
  if (categoryRestrictions.length > 0 &&
    !categoryRestrictions.includes(params.booking.service.category)) {
    return {ok: false, message: "Coupon does not apply to this category."};
  }

  let couponDiscountPaise = 0;
  if (discountType === "flat") {
    couponDiscountPaise = Math.round(discountValue * 100);
  } else if (discountType === "percent") {
    couponDiscountPaise = Math.floor((params.serviceSubtotalPaise * discountValue) / 100);
  } else if (discountType) {
    return {ok: false, message: "Coupon configuration is invalid."};
  }
  if (maxDiscountAmountPaise > 0) {
    couponDiscountPaise = Math.min(couponDiscountPaise, maxDiscountAmountPaise);
  }
  couponDiscountPaise = Math.max(0, Math.min(couponDiscountPaise, params.serviceSubtotalPaise));

  return {
    ok: true,
    couponDiscountPaise,
    couponSnapshot: {
      offerCampaignId: couponId,
      couponId,
      couponClaimId,
      couponCode: asString(claimedOffer.couponCode),
      usageLimitPerUser: usageLimit || null,
      discountType,
      discountValue,
      maxDiscountAmountPaise: maxDiscountAmountPaise || null,
      minBookingValuePaise: minBookingAmountPaise || null,
      campaignType: asString(claimedOffer.campaignType) || asString(campaignSnapshot.campaignType),
      validUntil,
    },
  };
}

export function resolveCanonicalPricingV3(params: {
  booking: CanonicalBookingDocumentV3;
  claimedOffer: ClaimedOfferDocument;
  authoritativeNow?: Date;
}): CanonicalPricingResolution {
  const serviceSubtotalPaise = calculateServiceSubtotalPaise(params.booking);
  const couponResult = validateCouponAgainstBooking({
    booking: params.booking,
    claimedOffer: params.claimedOffer,
    serviceSubtotalPaise,
    authoritativeNow: params.authoritativeNow ?? new Date(),
  });
  if (!couponResult.ok) {
    throw new HttpsError("failed-precondition", couponResult.message);
  }
  const financialSnapshot = calculateBookingFinancialSnapshot({
    currency: params.booking.service.currency || "INR",
    serviceSubtotalPaise,
    couponDiscountPaise: couponResult.couponDiscountPaise,
    platformCommissionRateBasisPoints: PLATFORM_COMMISSION_BASIS_POINTS,
  });
  const pricingHash = hashValue({
    bookingId: params.booking.serviceId,
    serviceSubtotalPaise,
    couponDiscountPaise: couponResult.couponDiscountPaise,
    customerPaidPaise: financialSnapshot.customerPaidPaise,
    providerPayoutPaise: financialSnapshot.providerPayoutPaise,
    bookingType: params.booking.bookingType,
    schedule: params.booking.schedule,
  });
  return {
    financialSnapshot,
    couponSnapshot: couponResult.couponSnapshot,
    pricingHash,
    serviceSubtotalPaise,
    couponDiscountPaise: couponResult.couponDiscountPaise,
    customerPaidPaise: financialSnapshot.customerPaidPaise,
  };
}

function isLiveServiceUnavailable(service: LiveServiceSnapshot | null): boolean {
  if (!service) return true;
  return service.status === "paused" ||
    service.isActive === false ||
    service.isDeleted === true ||
    service.isPaused === true ||
    service.isVisibleToMarketplace === false ||
    service.isPausedByVerification === true;
}

function buildAvailabilityHash(booking: CanonicalBookingDocumentV3, service: LiveServiceSnapshot | null): string {
  return hashValue({
    bookingId: booking.serviceId,
    bookingType: booking.bookingType,
    schedule: booking.schedule,
    serviceStatus: service ?? {},
  });
}

export function validatePreCheckoutAvailabilityV3(params: {
  booking: CanonicalBookingDocumentV3;
  service: LiveServiceSnapshot | null;
  authoritativeNow: Date;
}): PreCheckoutAvailabilityResult {
  if (params.booking.state !== "ACCEPTED_AWAITING_PAYMENT") {
    return {ok: false, code: "BOOKING_NOT_PAYABLE", message: "Booking is not awaiting payment."};
  }
  const payDeadlineAt = params.booking.lifecycle.payDeadlineAt;
  if (!payDeadlineAt || payDeadlineAt.getTime() < params.authoritativeNow.getTime()) {
    return {ok: false, code: "PAYMENT_WINDOW_EXPIRED", message: "The payment window has expired."};
  }
  if (isLiveServiceUnavailable(params.service)) {
    return {ok: false, code: "SERVICE_UNAVAILABLE", message: "The service is no longer available."};
  }
  const anchorAt = bookingAnchorAt(params.booking);
  if (anchorAt.getTime() <= params.authoritativeNow.getTime()) {
    return {ok: false, code: "BOOKING_NOT_PAYABLE", message: "The service start time has already passed."};
  }
  if (params.booking.bookingType === "RANGE" &&
    rangeSchedule(params.booking).nights > MAX_RANGE_OCCUPANCY_NIGHTS) {
    return {
      ok: false,
      code: "MALFORMED_BOOKING",
      message: `Range bookings are currently limited to ${MAX_RANGE_OCCUPANCY_NIGHTS} nights.`,
    };
  }
  return {
    ok: true,
    code: "OK",
    availabilityHash: buildAvailabilityHash(params.booking, params.service),
  };
}

function createDeterministicPaymentAttemptId(params: {
  bookingId: string;
  parentId: string;
  pricingHash: string;
}): string {
  return `attempt_${createHash("sha256")
    .update(`${params.bookingId}:${params.parentId}:${params.pricingHash}`)
    .digest("hex")
    .slice(0, 20)}`;
}

function buildPaymentAttemptDocument(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  pricing: CanonicalPricingResolution;
  paymentAttemptId?: string;
  availabilityHash: string;
  authoritativeNow: Date;
}): CanonicalPaymentAttemptDocumentV3 {
  const payDeadlineAt = params.booking.lifecycle.payDeadlineAt;
  if (!payDeadlineAt) {
    throw new HttpsError("failed-precondition", "Accepted booking is missing payDeadlineAt.");
  }
  const paymentAttemptId = params.paymentAttemptId?.trim() ||
    createDeterministicPaymentAttemptId({
      bookingId: params.bookingId,
      parentId: params.booking.parentId,
      pricingHash: params.pricing.pricingHash,
    });
  return {
    schemaVersion: CANONICAL_PAYMENT_ATTEMPT_SCHEMA_VERSION,
    paymentAttemptId,
    bookingId: params.bookingId,
    parentId: params.booking.parentId,
    providerId: params.booking.providerId,
    requestAttemptId: "",
    razorpayOrderId: "",
    razorpayPaymentId: "",
    amountPaise: params.pricing.customerPaidPaise,
    currency: params.pricing.financialSnapshot.currency,
    offerCampaignId:
      params.pricing.couponSnapshot?.offerCampaignId ??
      params.pricing.couponSnapshot?.couponId ??
      "",
    couponId: params.pricing.couponSnapshot?.couponId ?? "",
    couponClaimId: params.pricing.couponSnapshot?.couponClaimId ?? "",
    pricingHash: params.pricing.pricingHash,
    availabilityHash: params.availabilityHash,
    state: "NOT_STARTED",
    orderExpiresAt: new Date(payDeadlineAt.getTime()),
    createdAt: new Date(params.authoritativeNow.getTime()),
    orderCreatedAt: null,
    checkoutOpenedAt: null,
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
    updatedAt: new Date(params.authoritativeNow.getTime()),
    pricingSnapshot: {
      financials: params.pricing.financialSnapshot,
      serviceSubtotalPaise: params.pricing.serviceSubtotalPaise,
      couponDiscountPaise: params.pricing.couponDiscountPaise,
    },
    couponSnapshot: params.pricing.couponSnapshot,
  };
}

export function canonicalPaymentOrderMappingRef(
  firestore: Firestore,
  razorpayOrderId: string,
): FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData> {
  return firestore
    .collection(CANONICAL_PAYMENT_ORDER_MAPPINGS_COLLECTION)
    .doc(razorpayOrderId);
}

export function nextReconciliationAtForAttempt(params: {
  now: Date;
  attemptCount: number;
}): Date {
  const multiplier = Math.max(params.attemptCount, 0);
  const backoff = Math.min(
    RECONCILIATION_BASE_BACKOFF_MS * Math.max(multiplier, 1),
    RECONCILIATION_MAX_BACKOFF_MS,
  );
  return new Date(params.now.getTime() + backoff);
}

function reconciliationLeaseExpiresAt(now: Date): Date {
  return new Date(now.getTime() + RECONCILIATION_LEASE_MS);
}

function buildCanonicalRefundInstruction(params: {
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

function otpHash(bookingId: string, otpCode: string): string {
  return createHash("sha256").update(`${bookingId}:${otpCode}`).digest("hex");
}

function buildOtpCode(): string {
  return randomInt(100000, 999999).toString();
}

function calculatePaymentSeconds(booking: CanonicalBookingDocumentV3, paidAt: Date): number {
  const startedAt = booking.lifecycle.paymentStartedAt ?? booking.lifecycle.respondedAt;
  if (!startedAt) return 0;
  return Math.max(Math.floor((paidAt.getTime() - startedAt.getTime()) / 1000), 0);
}

function slotOccupancyPath(serviceId: string, slotId: string): string {
  return `services/${serviceId}/slotOccupancy/${slotId}`;
}

function rangeOccupancyPath(serviceId: string, dateKey: string): string {
  return `services/${serviceId}/occupancy/${dateKey}`;
}

function claimSlotOccupancy(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  existing: Record<string, SlotOccupancyDocument>;
}): Record<string, Record<string, unknown>> {
  const writes: Record<string, Record<string, unknown>> = {};
  const requestedUnits = bookingCapacityUnits(params.booking);
  for (const slot of slotSchedule(params.booking).slots) {
    const existing = params.existing[slot.slotId] ?? {
      slotId: slot.slotId,
      confirmedUnits: 0,
      capacitySnapshot: params.booking.service.capacitySnapshot,
      bookingClaims: {},
    };
    const existingClaim = existing.bookingClaims[params.bookingId] ?? 0;
    const nextConfirmedUnits = existing.confirmedUnits - existingClaim + requestedUnits;
    if (nextConfirmedUnits > existing.capacitySnapshot) {
      throw new HttpsError(
        "failed-precondition",
        "One or more selected slots are no longer available. Please review your booking.",
      );
    }
    writes[slotOccupancyPath(params.booking.serviceId, slot.slotId)] = {
      slotId: slot.slotId,
      confirmedUnits: nextConfirmedUnits,
      capacitySnapshot: existing.capacitySnapshot,
      bookingClaims: {
        ...existing.bookingClaims,
        [params.bookingId]: requestedUnits,
      },
      updatedAt: FieldValue.serverTimestamp(),
      version: 1,
    };
  }
  return writes;
}

function rangeDateKeys(booking: CanonicalBookingDocumentV3): string[] {
  if (booking.bookingType !== "RANGE") return [];
  const keys: string[] = [];
  const schedule = rangeSchedule(booking);
  const current = new Date(schedule.checkInDateTime.getTime());
  for (let day = 0; day < schedule.nights; day += 1) {
    const dateKey = current.toISOString().slice(0, 10);
    keys.push(dateKey);
    current.setUTCDate(current.getUTCDate() + 1);
  }
  return keys;
}

function claimRangeOccupancy(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  existing: Record<string, RangeOccupancyDocument>;
}): Record<string, Record<string, unknown>> {
  const writes: Record<string, Record<string, unknown>> = {};
  const requestedUnits = bookingCapacityUnits(params.booking);
  for (const dateKey of rangeDateKeys(params.booking)) {
    const existing = params.existing[dateKey] ?? {
      dateKey,
      confirmedPetUnits: 0,
      capacitySnapshot: params.booking.service.capacitySnapshot,
      bookingClaims: {},
    };
    const existingClaim = existing.bookingClaims[params.bookingId] ?? 0;
    const nextConfirmedUnits = existing.confirmedPetUnits - existingClaim + requestedUnits;
    if (nextConfirmedUnits > existing.capacitySnapshot) {
      throw new HttpsError("failed-precondition", "Selected range capacity is exhausted.");
    }
    writes[rangeOccupancyPath(params.booking.serviceId, dateKey)] = {
      dateKey,
      confirmedPetUnits: nextConfirmedUnits,
      capacitySnapshot: existing.capacitySnapshot,
      bookingClaims: {
        ...existing.bookingClaims,
        [params.bookingId]: requestedUnits,
      },
      updatedAt: FieldValue.serverTimestamp(),
      version: 1,
    };
  }
  return writes;
}

function buildBookingFinancialWrite(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  paymentAttempt: CanonicalPaymentAttemptDocumentV3;
  paidAt: Date;
  verificationSource: string;
}): FinalizePaymentSuccess["financialWrites"] {
  const financials = params.booking.financials!;
  const customerName = [
    params.booking.participants.parent.displayFirstName,
    params.booking.participants.parent.lastInitial,
  ].filter((value) => value.trim().length > 0).join(" ").trim();
  return {
    bookingFinancial: {
      bookingId: params.bookingId,
      userId: params.booking.parentId,
      providerId: params.booking.providerId,
      serviceId: params.booking.serviceId,
      totalAmountPaise: financials.customerPaidPaise,
      serviceAmountPaise: financials.serviceSubtotalPaise,
      currency: financials.currency,
      status: "confirmed",
      paymentStatus: "paid",
      couponFundingPaise: financials.pettxoCouponFundingPaise,
      providerPayoutPaise: financials.providerPayoutPaise,
      pettxoNetBeforeGatewayPaise: financials.pettxoNetBeforeGatewayPaise,
      razorpayPaymentId: params.paymentAttempt.razorpayPaymentId,
      razorpayOrderId: params.paymentAttempt.razorpayOrderId,
      paymentAttemptId: params.paymentAttempt.paymentAttemptId,
      verifiedAt: Timestamp.fromDate(params.paidAt),
      verificationSource: params.verificationSource,
      schemaVersion: 3,
      updatedAt: FieldValue.serverTimestamp(),
    },
    payment: {
      bookingId: params.bookingId,
      userId: params.booking.parentId,
      providerId: params.booking.providerId,
      serviceId: params.booking.serviceId,
      amountPaise: financials.customerPaidPaise,
      serviceAmountPaise: financials.serviceSubtotalPaise,
      currency: financials.currency,
      status: "confirmed",
      paymentStatus: "paid",
      paymentAttemptId: params.paymentAttempt.paymentAttemptId,
      razorpayOrderId: params.paymentAttempt.razorpayOrderId,
      razorpayPaymentId: params.paymentAttempt.razorpayPaymentId,
      captureVerificationSource: params.verificationSource,
      updatedAt: FieldValue.serverTimestamp(),
    },
    invoice: {
      invoiceId: params.bookingId,
      bookingId: params.bookingId,
      userId: params.booking.parentId,
      providerId: params.booking.providerId,
      serviceId: params.booking.serviceId,
      status: "issued",
      currency: financials.currency,
      serviceAmountPaise: financials.serviceSubtotalPaise,
      discountAmountPaise: financials.couponDiscountPaise,
      totalPayablePaise: financials.customerPaidPaise,
      taxLabel: "GST",
      taxAmountPaise: 0,
      taxStatus: "Not applicable",
      issuedAt: Timestamp.fromDate(params.paidAt),
      createdAt: Timestamp.fromDate(params.paidAt),
      updatedAt: Timestamp.fromDate(params.paidAt),
    },
    providerEarning: {
      bookingId: params.bookingId,
      providerId: params.booking.providerId,
      userId: params.booking.parentId,
      serviceId: params.booking.serviceId,
      amountPaise: financials.providerPayoutPaise,
      pettxoCommissionAmountPaise: financials.platformCommissionPaise,
      totalAmountPaise: financials.customerPaidPaise,
      source: "paidBookingCanonical",
      status: "notEligible",
      eligibleAt: null,
      paidAt: null,
      schemaVersion: 3,
      createdAt: Timestamp.fromDate(params.paidAt),
      updatedAt: Timestamp.fromDate(params.paidAt),
    },
    payoutReadiness: {
      bookingId: params.bookingId,
      providerId: params.booking.providerId,
      customerId: params.booking.parentId,
      status: "not_eligible",
      eligibilityReason: "Service must complete before payout eligibility.",
      eligibleAt: null,
      payoutId: "",
      updatedAt: FieldValue.serverTimestamp(),
    },
    bookingChat: {
      bookingId: params.bookingId,
      chatType: "booking",
      customerId: params.booking.parentId,
      providerId: params.booking.providerId,
      participantIds: [params.booking.parentId, params.booking.providerId],
      customerName,
      customerPhotoUrl: params.booking.participants.parent.photoUrl,
      providerName: params.booking.participants.provider.displayName,
      providerPhotoUrl: params.booking.participants.provider.photoUrl,
      sourceServiceIds: [params.booking.serviceId],
      lastServiceId: params.booking.serviceId,
      lastServiceTitle: params.booking.service.serviceTitle,
      lastServiceImageUrl: "",
      lastMessage: "",
      lastMessageAt: Timestamp.fromDate(params.paidAt),
      lastSenderId: "",
      unreadCountCustomer: 0,
      unreadCountProvider: 0,
      customerLastReadAt: null,
      providerLastReadAt: null,
      status: "unlocked",
      unlockedAt: Timestamp.fromDate(params.paidAt),
      linkedBookingId: params.bookingId,
      safetyNotice: "For your protection, keep payments and booking changes inside Pettxo.",
      createdBy: "system",
      createdAt: Timestamp.fromDate(params.paidAt),
      updatedAt: FieldValue.serverTimestamp(),
    },
  };
}

function buildBookingPrivateDocument(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  otpCode: string;
  paidAt: Date;
}): CanonicalBookingPrivateDocumentV3 {
  return {
    schemaVersion: 1,
    bookingId: params.bookingId,
    parentId: params.booking.parentId,
    providerId: params.booking.providerId,
    parentOtpCode: params.otpCode,
    providerOtpHash: otpHash(params.bookingId, params.otpCode),
    otpState: params.otpCode.trim().length === 0 ? "REVOKED" : "ACTIVE",
    failedAttemptCount: 0,
    lastFailedAttemptAt: null,
    lockedUntil: null,
    verifiedAt: null,
    successfulAttemptNumber: null,
    lastVerificationAttemptId: "",
    lastVerificationOutcome: "",
    contactUnlockedAt: new Date(params.paidAt.getTime()),
    createdAt: new Date(params.paidAt.getTime()),
    updatedAt: new Date(params.paidAt.getTime()),
  };
}

function buildBookingPrivateParticipantsDocument(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  parent: AuthenticatedParentIdentity;
  providerPrivate: AuthenticatedProviderPrivateIdentity | null;
  service: LiveServiceSnapshot | null;
  paidAt: Date;
}): BookingPrivateParticipantsDocumentV3 {
  const providerPhoneNumber = asString(params.providerPrivate?.phoneNumber);
  return {
    schemaVersion: 3,
    bookingModelVersion: "3.2",
    documentFormat: "canonical_v3_private",
    bookingId: params.bookingId,
    parentId: params.booking.parentId,
    providerId: params.booking.providerId,
    unlockedAfterPaidOnly: true,
    parentPrivate: {
      fullName:
        asString(params.parent.fullName) || asString(params.parent.displayName),
      phoneNumber: asString(params.parent.phoneNumber),
      email: asString(params.parent.email),
      exactAddress: asString(params.service?.location?.displayAddress),
      latitude: params.service?.location?.latitude ?? null,
      longitude: params.service?.location?.longitude ?? null,
    },
    providerPrivate: providerPhoneNumber ?
      {
        phoneNumber: providerPhoneNumber,
      } :
      undefined,
    createdAt: new Date(params.paidAt.getTime()),
    updatedAt: new Date(params.paidAt.getTime()),
  };
}

function buildConfirmedBooking(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  paymentAttempt: CanonicalPaymentAttemptDocumentV3;
  paidAt: Date;
  otpGeneratedAt: Date;
  verificationSource: "callable" | "webhook" | "reconciliation" | "zero_payable";
}): CanonicalBookingDocumentV3 {
  const next = cloneBooking(params.booking);
  next.state = "CONFIRMED";
  next.stateQueryValue = "CONFIRMED";
  next.updatedAt = new Date(params.paidAt.getTime());
  next.payDeadlineAt = next.lifecycle.payDeadlineAt;
  next.lifecycle.paymentStartedAt = next.lifecycle.paymentStartedAt ?? next.lifecycle.respondedAt;
  next.lifecycle.paidAt = new Date(params.paidAt.getTime());
  next.lifecycle.paymentSeconds = calculatePaymentSeconds(next, params.paidAt);
  next.lifecycle.otpGeneratedAt = new Date(params.otpGeneratedAt.getTime());
  next.payment.status = "CONFIRMED";
  next.payment.razorpayOrderId = params.paymentAttempt.razorpayOrderId;
  next.payment.razorpayPaymentId = params.paymentAttempt.razorpayPaymentId;
  next.payment.paymentAttemptId = params.paymentAttempt.paymentAttemptId;
  next.payment.orderCreatedAt = params.paymentAttempt.orderCreatedAt;
  next.payment.paymentStartedAt = params.paymentAttempt.checkoutOpenedAt ?? next.lifecycle.paymentStartedAt;
  next.payment.capturedAt = new Date(params.paidAt.getTime());
  next.payment.verifiedAt = new Date(params.paidAt.getTime());
  next.payment.verificationSource = params.verificationSource;
  next.privacy.isPaidContactUnlocked = true;
  next.privacy.contactUnlockedAt = new Date(params.paidAt.getTime());
  next.privacy.chatUnlockedAt = new Date(params.paidAt.getTime());
  next.privacy.otpVisibleToParent = true;
  next.privacy.exactAddressUnlocked = true;
  next.payout.providerPayoutPaise = next.financials?.providerPayoutPaise ?? 0;
  next.audit.lastUpdatedBy = "payment_gateway";
  return next;
}

function hasReusableBookingPrivateForConfirmedReplay(
  bookingPrivate: CanonicalBookingPrivateDocumentV3 | null | undefined,
): bookingPrivate is CanonicalBookingPrivateDocumentV3 {
  if (!bookingPrivate) return false;
  return /^\d{6}$/.test(asString(bookingPrivate.parentOtpCode)) &&
    /^[a-f0-9]{64}$/i.test(asString(bookingPrivate.providerOtpHash)) &&
    asString(bookingPrivate.otpState).toUpperCase() === "ACTIVE";
}

function hasExistingProviderPrivatePhone(
  bookingPrivateParticipants: BookingPrivateParticipantsDocumentV3 | null | undefined,
): boolean {
  return asString(bookingPrivateParticipants?.providerPrivate?.phoneNumber).length > 0;
}

function hasReusableBookingPrivateParticipants(
  bookingPrivateParticipants: BookingPrivateParticipantsDocumentV3 | null | undefined,
  providerPrivate: AuthenticatedProviderPrivateIdentity | null,
): bookingPrivateParticipants is BookingPrivateParticipantsDocumentV3 {
  if (!bookingPrivateParticipants) return false;
  if (asString(bookingPrivateParticipants.bookingId).length === 0) return false;
  if (asString(bookingPrivateParticipants.parentId).length === 0) return false;
  if (asString(bookingPrivateParticipants.providerId).length === 0) return false;
  if (providerPrivate?.phoneNumber?.trim().length) {
    return hasExistingProviderPrivatePhone(bookingPrivateParticipants);
  }
  return true;
}

function buildRefundRequiredBooking(params: {
  booking: CanonicalBookingDocumentV3;
  paymentAttempt: CanonicalPaymentAttemptDocumentV3;
  failureCode: string;
  message: string;
  now: Date;
}): CanonicalBookingDocumentV3 {
  const next = cloneBooking(params.booking);
  next.state = "PAYMENT_EXPIRED";
  next.stateQueryValue = "PAYMENT_EXPIRED";
  next.updatedAt = new Date(params.now.getTime());
  next.lifecycle.cancelledAt = new Date(params.now.getTime());
  next.payment.status = "REFUND_REQUIRED";
  next.payment.razorpayOrderId = params.paymentAttempt.razorpayOrderId;
  next.payment.razorpayPaymentId = params.paymentAttempt.razorpayPaymentId;
  next.payment.paymentAttemptId = params.paymentAttempt.paymentAttemptId;
  next.payment.failureCode = params.failureCode;
  next.payment.failureMessage = params.message;
  next.audit.lastUpdatedBy = "payment_gateway";
  return next;
}

export function finalizeCapturedBookingPaymentV3(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  paymentAttempt: CanonicalPaymentAttemptDocumentV3;
  parent: AuthenticatedParentIdentity;
  providerPrivate?: AuthenticatedProviderPrivateIdentity | null;
  service: LiveServiceSnapshot | null;
  existingBookingPrivate?: CanonicalBookingPrivateDocumentV3 | null;
  existingBookingPrivateParticipants?: BookingPrivateParticipantsDocumentV3 | null;
  slotOccupancy: Record<string, SlotOccupancyDocument>;
  rangeOccupancy: Record<string, RangeOccupancyDocument>;
  razorpayPayment: RazorpayPaymentRecord | null;
  authoritativeNow: Date;
  verificationSource: CanonicalPaymentFinalizeSource;
}): FinalizePaymentResult {
  const providerPrivate = params.providerPrivate ?? null;
  if (params.booking.state === "CONFIRMED" && params.paymentAttempt.state === "CONFIRMED") {
    const paidAt = params.booking.lifecycle.paidAt ?? params.authoritativeNow;
    if (!hasReusableBookingPrivateForConfirmedReplay(params.existingBookingPrivate)) {
      return {
        ok: false,
        code: "PRIVATE_REPAIR_REQUIRED",
        booking: cloneBooking(params.booking),
        paymentAttempt: cloneAttempt(params.paymentAttempt),
        refundInstruction: null,
        notifications: [],
        events: [],
        message: "Confirmed booking is missing its canonical private OTP document and requires server-side repair.",
      };
    }
    const bookingPrivate = structuredClone(params.existingBookingPrivate);
    const bookingPrivateParticipants = hasReusableBookingPrivateParticipants(
      params.existingBookingPrivateParticipants,
      providerPrivate,
    ) ?
      structuredClone(params.existingBookingPrivateParticipants) :
      buildBookingPrivateParticipantsDocument({
        bookingId: params.bookingId,
        booking: params.booking,
        parent: params.parent,
        providerPrivate,
        service: params.service,
        paidAt,
      });
    return {
      ok: true,
      code: "IDEMPOTENT_REPLAY",
      booking: cloneBooking(params.booking),
      paymentAttempt: cloneAttempt(params.paymentAttempt),
      bookingPrivate,
      bookingPrivateParticipants,
      otpCode: "",
      occupancyWrites: {},
      financialWrites: buildBookingFinancialWrite({
        bookingId: params.bookingId,
        booking: params.booking,
        paymentAttempt: params.paymentAttempt,
        paidAt,
        verificationSource: params.verificationSource,
      }),
      couponWrite: null,
      events: [],
      notifications: [],
      parentStats: emptyParentStatsV3(),
      privateWritePlan: {
        writeBookingPrivate: false,
        writeBookingPrivateParticipants: !hasReusableBookingPrivateParticipants(
          params.existingBookingPrivateParticipants,
          providerPrivate,
        ),
      },
    };
  }

  if (params.booking.state === "PAYMENT_EXPIRED") {
    const attempt = cloneAttempt(params.paymentAttempt);
    if (attempt.state !== "REFUND_PENDING" && attempt.state !== "REFUNDED") {
      attempt.state = "REFUND_REQUIRED";
      attempt.failureCode = attempt.failureCode || "CAPTURE_AFTER_PAYMENT_EXPIRED";
      attempt.failureMessage =
        attempt.failureMessage || "Captured payment arrived after the booking payment window expired.";
      attempt.refundRequiredAt = attempt.refundRequiredAt ?? new Date(params.authoritativeNow.getTime());
      attempt.updatedAt = new Date(params.authoritativeNow.getTime());
    }
    const booking = buildRefundRequiredBooking({
      booking: params.booking,
      paymentAttempt: attempt,
      failureCode: attempt.failureCode || "CAPTURE_AFTER_PAYMENT_EXPIRED",
      message:
        attempt.failureMessage ||
        "Captured payment arrived after the booking payment window expired.",
      now: params.authoritativeNow,
    });
    return {
      ok: false,
      code: "PAYMENT_EXPIRED",
      booking,
      paymentAttempt: attempt,
      refundInstruction: attempt.state === "REFUNDED" ? null : buildCanonicalRefundInstruction({
        bookingId: params.bookingId,
        booking,
        paymentAttempt: attempt,
        refundAmountPaise: params.booking.financials?.customerPaidPaise ?? attempt.amountPaise,
        reasonCode: "CAPTURE_AFTER_PAYMENT_EXPIRED",
        now: params.authoritativeNow,
      }),
      notifications: buildPaymentFailedNotification({
        bookingId: params.bookingId,
        parentId: booking.parentId,
        providerId: booking.providerId,
        bookingType: booking.bookingType,
        state: booking.state,
      }),
      events: [
        buildBookingEventPlan({
          bookingId: params.bookingId,
          event: "payment_abandoned",
          actor: "payment_gateway",
          at: params.authoritativeNow,
          meta: {code: "CAPTURE_AFTER_PAYMENT_EXPIRED"},
        }),
      ],
      message:
        attempt.failureMessage ||
        "Captured payment arrived after the booking payment window expired.",
    };
  }

  if (params.booking.state !== "ACCEPTED_AWAITING_PAYMENT") {
    return {
      ok: false,
      code: "MALFORMED_BOOKING",
      booking: cloneBooking(params.booking),
      paymentAttempt: cloneAttempt(params.paymentAttempt),
      refundInstruction: null,
      notifications: [],
      events: [],
      message: "Booking is not awaiting canonical payment confirmation.",
    };
  }
  if (!params.booking.financials) {
    return {
      ok: false,
      code: "MALFORMED_BOOKING",
      booking: cloneBooking(params.booking),
      paymentAttempt: cloneAttempt(params.paymentAttempt),
      refundInstruction: null,
      notifications: [],
      events: [],
      message: "Canonical financial snapshot is missing.",
    };
  }
  const payDeadlineAt = params.booking.lifecycle.payDeadlineAt;
  if (!payDeadlineAt) {
    return {
      ok: false,
      code: "MALFORMED_BOOKING",
      booking: cloneBooking(params.booking),
      paymentAttempt: cloneAttempt(params.paymentAttempt),
      refundInstruction: null,
      notifications: [],
      events: [],
      message: "Canonical payment deadline is missing.",
    };
  }

  const captureAt = params.verificationSource === "zero_payable" ?
    params.authoritativeNow :
    (params.razorpayPayment?.capturedAt ?? params.razorpayPayment?.createdAt ?? params.authoritativeNow);
  if (captureAt.getTime() > payDeadlineAt.getTime() + CAPTURE_DEADLINE_TOLERANCE_MS) {
    const attempt = cloneAttempt(params.paymentAttempt);
    attempt.state = "REFUND_REQUIRED";
    attempt.failureCode = "CAPTURE_AFTER_DEADLINE";
    attempt.failureMessage = "Captured payment arrived after the payment deadline.";
    attempt.refundRequiredAt = new Date(params.authoritativeNow.getTime());
    attempt.updatedAt = new Date(params.authoritativeNow.getTime());
    const booking = buildRefundRequiredBooking({
      booking: params.booking,
      paymentAttempt: attempt,
      failureCode: attempt.failureCode,
      message: attempt.failureMessage,
      now: params.authoritativeNow,
    });
    return {
      ok: false,
      code: "PAYMENT_EXPIRED",
      booking,
      paymentAttempt: attempt,
      refundInstruction: buildCanonicalRefundInstruction({
        bookingId: params.bookingId,
        booking,
        paymentAttempt: attempt,
        refundAmountPaise: params.booking.financials.customerPaidPaise,
        reasonCode: "CAPTURE_AFTER_DEADLINE",
        now: params.authoritativeNow,
      }),
      notifications: buildPaymentFailedNotification({
        bookingId: params.bookingId,
        parentId: booking.parentId,
        providerId: booking.providerId,
        bookingType: booking.bookingType,
        state: booking.state,
      }),
      events: [
        buildBookingEventPlan({
          bookingId: params.bookingId,
          event: "payment_abandoned",
          actor: "payment_gateway",
          at: params.authoritativeNow,
          meta: {code: "CAPTURE_AFTER_DEADLINE"},
        }),
      ],
      message: attempt.failureMessage,
    };
  }

  const attempt = cloneAttempt(params.paymentAttempt);
  attempt.state = "CONFIRMING";
  attempt.updatedAt = new Date(params.authoritativeNow.getTime());
  attempt.captureReportedAt = new Date(params.authoritativeNow.getTime());
  attempt.captureCreatedAt = captureAt;
  attempt.verificationSource = params.verificationSource;
  if (params.razorpayPayment) {
    if (params.razorpayPayment.orderId !== attempt.razorpayOrderId) {
      throw new HttpsError("failed-precondition", "Razorpay order does not match the payment attempt.");
    }
    if (params.razorpayPayment.amountPaise !== attempt.amountPaise) {
      throw new HttpsError("failed-precondition", "Razorpay amount does not match the payment attempt.");
    }
    if ((params.razorpayPayment.currency || "INR") !== attempt.currency) {
      throw new HttpsError("failed-precondition", "Razorpay currency does not match the payment attempt.");
    }
    attempt.razorpayPaymentId = params.razorpayPayment.id;
  }

  try {
    const occupancyWrites = params.booking.bookingType === "SLOT" ?
      claimSlotOccupancy({
        bookingId: params.bookingId,
        booking: params.booking,
        existing: params.slotOccupancy,
      }) :
      claimRangeOccupancy({
        bookingId: params.bookingId,
        booking: params.booking,
        existing: params.rangeOccupancy,
      });
    const paidAt = new Date(params.authoritativeNow.getTime());
    const otpGeneratedAt = new Date(params.authoritativeNow.getTime());
    const otpCode = buildOtpCode();
    attempt.state = "CONFIRMED";
    attempt.confirmedAt = new Date(paidAt.getTime());
    attempt.updatedAt = new Date(paidAt.getTime());
    const confirmedBooking = buildConfirmedBooking({
      bookingId: params.bookingId,
      booking: params.booking,
      paymentAttempt: attempt,
      paidAt,
      otpGeneratedAt,
      verificationSource: params.verificationSource,
    });
    const bookingPrivate = buildBookingPrivateDocument({
      bookingId: params.bookingId,
      booking: confirmedBooking,
      otpCode,
      paidAt,
    });
    const bookingPrivateParticipants = buildBookingPrivateParticipantsDocument({
      bookingId: params.bookingId,
      booking: confirmedBooking,
      parent: params.parent,
      providerPrivate,
      service: params.service,
      paidAt,
    });
    const financialWrites = buildBookingFinancialWrite({
      bookingId: params.bookingId,
      booking: confirmedBooking,
      paymentAttempt: attempt,
      paidAt,
      verificationSource: params.verificationSource,
    });
    const offerCampaignId = asString(attempt.offerCampaignId) || asString(attempt.couponId);
    const couponWrite = offerCampaignId ?
      {
        offerUsagePath: `users/${confirmedBooking.parentId}/offerUsage/${offerCampaignId}`,
        offerCampaignId,
        bookingId: params.bookingId,
        paymentAttemptId: attempt.paymentAttemptId,
        couponCode: attempt.couponSnapshot?.couponCode ?? "",
        usageLimitPerUser: attempt.couponSnapshot?.usageLimitPerUser ?? null,
      } :
      null;
    const events = [
      buildBookingEventPlan({
        bookingId: params.bookingId,
        event: "paid",
        actor: "payment_gateway",
        at: paidAt,
        meta: {
          paymentAttemptId: attempt.paymentAttemptId,
          verificationSource: params.verificationSource,
        },
      }),
    ];
    const notifications = params.razorpayPayment == null ?
      buildZeroPayableConfirmationNotification({
        bookingId: params.bookingId,
        parentId: confirmedBooking.parentId,
        providerId: confirmedBooking.providerId,
        bookingType: confirmedBooking.bookingType,
        state: confirmedBooking.state,
        serviceName: confirmedBooking.service.serviceTitle,
      }) :
      buildBookingConfirmedNotification({
        bookingId: params.bookingId,
        parentId: confirmedBooking.parentId,
        providerId: confirmedBooking.providerId,
        bookingType: confirmedBooking.bookingType,
        state: confirmedBooking.state,
        serviceName: confirmedBooking.service.serviceTitle,
      });
    const parentStats = applyParentStatsMutation(emptyParentStatsV3(), {
      type: "payment_completed",
      mutationKey: `payment_completed:${params.bookingId}`,
      occurredAt: paidAt,
    });
    return {
      ok: true,
      code: "CONFIRMED",
      booking: confirmedBooking,
      paymentAttempt: attempt,
      bookingPrivate,
      bookingPrivateParticipants,
      otpCode,
      occupancyWrites,
      financialWrites,
      couponWrite,
      events,
      notifications,
      parentStats,
      privateWritePlan: {
        writeBookingPrivate: true,
        writeBookingPrivateParticipants: true,
      },
    };
  } catch (error) {
    const failureMessage = error instanceof HttpsError ?
      error.message :
      "Capacity could not be claimed after capture.";
    attempt.state = "REFUND_REQUIRED";
    attempt.failureCode = "CAPACITY_EXHAUSTED";
    attempt.failureMessage = failureMessage;
    attempt.refundRequiredAt = new Date(params.authoritativeNow.getTime());
    attempt.updatedAt = new Date(params.authoritativeNow.getTime());
    const booking = buildRefundRequiredBooking({
      booking: params.booking,
      paymentAttempt: attempt,
      failureCode: attempt.failureCode,
      message: failureMessage,
      now: params.authoritativeNow,
    });
    return {
      ok: false,
      code: "CAPACITY_EXHAUSTED",
      booking,
      paymentAttempt: attempt,
      refundInstruction: buildCanonicalRefundInstruction({
        bookingId: params.bookingId,
        booking,
        paymentAttempt: attempt,
        refundAmountPaise: params.booking.financials.customerPaidPaise,
        reasonCode: "CAPACITY_UNAVAILABLE_AFTER_CAPTURE",
        now: params.authoritativeNow,
      }),
      notifications: buildPaymentRefundRequiredNotification({
        bookingId: params.bookingId,
        parentId: booking.parentId,
        providerId: booking.providerId,
        bookingType: booking.bookingType,
        state: booking.state,
      }),
      events: [
        buildBookingEventPlan({
          bookingId: params.bookingId,
          event: "refunded",
          actor: "payment_gateway",
          at: params.authoritativeNow,
          meta: {reason: "capacity_lost_after_capture"},
        }),
      ],
      message: failureMessage,
    };
  }
}

export async function createRazorpayPaymentOrderV3(params: {
  firestore: Firestore;
  bookingId: string;
  parentId: string;
  parent: AuthenticatedParentIdentity;
  service: CanonicalServiceSource & LiveServiceSnapshot;
  booking: CanonicalBookingDocumentV3;
  claimedOffer?: ClaimedOfferDocument;
  authoritativeNow?: Date;
  keyId: string;
  keySecret: string;
  paymentAttemptId?: string;
}): Promise<PaymentAttemptOrderResult> {
  const authoritativeNow = params.authoritativeNow ?? new Date();
  if (params.parentId !== params.booking.parentId) {
    return {ok: false, code: "PERMISSION_DENIED", message: "Only the booking parent can start payment."};
  }
  const availability = validatePreCheckoutAvailabilityV3({
    booking: params.booking,
    service: params.service,
    authoritativeNow,
  });
  if (!availability.ok) {
    return {ok: false, code: availability.code, message: availability.message};
  }
  const pricing = resolveCanonicalPricingV3({
    booking: params.booking,
    claimedOffer: params.claimedOffer ?? null,
    authoritativeNow,
  });
  const attempt = buildPaymentAttemptDocument({
    bookingId: params.bookingId,
    booking: params.booking,
    pricing,
    paymentAttemptId: params.paymentAttemptId,
    availabilityHash: availability.availabilityHash,
    authoritativeNow,
  });
  if (attempt.amountPaise === 0) {
    const finalized = finalizeCapturedBookingPaymentV3({
      bookingId: params.bookingId,
      booking: {
        ...params.booking,
        financials: pricing.financialSnapshot,
      },
      paymentAttempt: {
        ...attempt,
        state: "CHECKOUT_OPENED",
        checkoutOpenedAt: new Date(authoritativeNow.getTime()),
        verificationSource: "zero_payable",
      },
      parent: params.parent,
      service: params.service,
      slotOccupancy: {},
      rangeOccupancy: {},
      razorpayPayment: null,
      authoritativeNow,
      verificationSource: "zero_payable",
    });
    return {ok: true, code: "ZERO_PAYABLE_CONFIRMED", paymentAttempt: attempt, finalizeResult: finalized};
  }
  const order = await createRazorpayOrderV3({
    keyId: params.keyId,
    keySecret: params.keySecret,
    bookingId: params.bookingId,
    paymentAttemptId: attempt.paymentAttemptId,
    amountPaise: attempt.amountPaise,
    currency: attempt.currency,
    notes: {
      bookingId: params.bookingId,
      paymentAttemptId: attempt.paymentAttemptId,
      bookingModelVersion: params.booking.bookingModelVersion,
      parentId: params.booking.parentId,
    },
  });
  const nextAttempt: CanonicalPaymentAttemptDocumentV3 = {
    ...attempt,
    bookingId: params.bookingId,
    razorpayOrderId: order.orderId,
    state: "ORDER_CREATED",
    orderCreatedAt: new Date(authoritativeNow.getTime()),
    checkoutOpenedAt: new Date(authoritativeNow.getTime()),
    updatedAt: new Date(authoritativeNow.getTime()),
  };
  return {
    ok: true,
    code: "ORDER_READY",
    paymentAttempt: nextAttempt,
    order: {
      bookingId: params.bookingId,
      paymentAttemptId: nextAttempt.paymentAttemptId,
      razorpayOrderId: order.orderId,
      keyId: order.keyId,
      amountPaise: order.amountPaise,
      currency: order.currency,
      paymentExpiresAt: params.booking.lifecycle.payDeadlineAt ?? new Date(authoritativeNow.getTime() + PAY_WINDOW_MS),
      serviceSubtotalPaise: pricing.serviceSubtotalPaise,
      couponDiscountPaise: pricing.couponDiscountPaise,
      customerPaidPaise: pricing.customerPaidPaise,
    },
    events: [
      buildBookingEventPlan({
        bookingId: params.bookingId,
        event: "payment_started",
        actor: "parent",
        at: authoritativeNow,
        meta: {paymentAttemptId: nextAttempt.paymentAttemptId},
      }),
    ],
    notifications: buildPaymentOrderReadyNotification({
      bookingId: params.bookingId,
      parentId: params.booking.parentId,
      bookingType: params.booking.bookingType,
      state: params.booking.state,
      paymentAttemptId: nextAttempt.paymentAttemptId,
    }),
  };
}

export function previewCanonicalPaymentPricingV3(params: {
  bookingId: string;
  parentId: string;
  service: LiveServiceSnapshot | null;
  booking: CanonicalBookingDocumentV3;
  claimedOffer?: ClaimedOfferDocument | null;
  authoritativeNow?: Date;
}):
  | {
    ok: true;
    code: "READY";
    pricing: CanonicalPricingResolution;
    payDeadlineAt: Date | null;
  }
  | {
    ok: false;
    code: string;
    message: string;
  } {
  const authoritativeNow = params.authoritativeNow ?? new Date();
  if (params.parentId !== params.booking.parentId) {
    return {
      ok: false,
      code: "ACTOR_NOT_AUTHORIZED",
      message: "Only the booking parent can preview payment pricing.",
    };
  }
  const availability = validatePreCheckoutAvailabilityV3({
    booking: params.booking,
    service: params.service,
    authoritativeNow,
  });
  if (!availability.ok) {
    return {ok: false, code: availability.code, message: availability.message};
  }
  const pricing = resolveCanonicalPricingV3({
    booking: params.booking,
    claimedOffer: params.claimedOffer ?? null,
    authoritativeNow,
  });
  return {
    ok: true,
    code: "READY",
    pricing,
    payDeadlineAt: params.booking.lifecycle.payDeadlineAt ?? null,
  };
}

export async function persistFinalizePaymentResultV3(params: {
  firestore: Firestore;
  result: FinalizePaymentResult;
  bookingId: string;
}): Promise<void> {
  await params.firestore.runTransaction(async (transaction) => {
    if (params.result.ok) {
      const bookingRef = params.firestore.collection("bookings").doc(params.bookingId);
      const privateWritePlan = params.result.privateWritePlan ?? {
        writeBookingPrivate: true,
        writeBookingPrivateParticipants: true,
      };
      transaction.set(bookingRef, serializeBookingForFirestore(params.result.booking), {merge: true});
      transaction.set(
        bookingRef.collection("paymentAttempts").doc(params.result.paymentAttempt.paymentAttemptId),
        serializePaymentAttemptForFirestore(params.result.paymentAttempt),
        {merge: true},
      );
      if (privateWritePlan.writeBookingPrivate) {
        transaction.set(
          params.firestore.collection("bookingPrivate").doc(params.bookingId),
          serializeBookingPrivateForFirestore(params.result.bookingPrivate),
          {merge: true},
        );
      }
      if (privateWritePlan.writeBookingPrivateParticipants) {
        transaction.set(
          params.firestore.collection("bookingPrivateParticipants").doc(params.bookingId),
          serializeBookingPrivateParticipantsForFirestore(
            params.result.bookingPrivateParticipants,
          ),
          {merge: true},
        );
      }
      for (const [path, data] of Object.entries(params.result.occupancyWrites)) {
        transaction.set(pathToDoc(params.firestore, path), data, {merge: true});
      }
      transaction.set(params.firestore.collection("bookingFinancials").doc(params.bookingId), params.result.financialWrites.bookingFinancial, {merge: true});
      transaction.set(params.firestore.collection("payments").doc(params.bookingId), params.result.financialWrites.payment, {merge: true});
      transaction.set(params.firestore.collection("invoices").doc(params.bookingId), params.result.financialWrites.invoice, {merge: true});
      transaction.set(params.firestore.collection("providerEarnings").doc(params.bookingId), params.result.financialWrites.providerEarning, {merge: true});
      transaction.set(params.firestore.collection("payoutReadiness").doc(params.bookingId), params.result.financialWrites.payoutReadiness, {merge: true});
      transaction.set(params.firestore.collection("bookingChats").doc(params.bookingId), params.result.financialWrites.bookingChat, {merge: true});
      transaction.set(params.firestore.collection("chats").doc(params.bookingId), params.result.financialWrites.bookingChat, {merge: true});
      if (params.result.couponWrite) {
        await consumeOfferUsageInTransaction({
          firestore: params.firestore,
          transaction,
          uid: params.result.booking.parentId,
          offerCampaignId: params.result.couponWrite.offerCampaignId,
          bookingId: params.result.couponWrite.bookingId,
          paymentAttemptId: params.result.couponWrite.paymentAttemptId,
          couponCode: params.result.couponWrite.couponCode,
          usageLimitPerUser: params.result.couponWrite.usageLimitPerUser,
        });
      }
      for (const event of params.result.events) {
        transaction.set(
          params.firestore.collection("bookings").doc(params.bookingId).collection("events").doc(event.eventId),
          {
            bookingId: event.record.bookingId,
            event: event.record.event,
            actor: event.record.actor,
            at: Timestamp.fromDate(event.record.at),
            meta: event.record.meta,
            schemaVersion: event.record.schemaVersion,
          },
          {merge: false},
        );
      }
    } else {
      const bookingRef = params.firestore.collection("bookings").doc(params.bookingId);
      transaction.set(bookingRef, serializeBookingForFirestore(params.result.booking), {merge: true});
      transaction.set(
        bookingRef.collection("paymentAttempts").doc(params.result.paymentAttempt.paymentAttemptId),
        serializePaymentAttemptForFirestore(params.result.paymentAttempt),
        {merge: true},
      );
      if (params.result.refundInstruction) {
        transaction.set(
          params.firestore.collection("refunds").doc(params.bookingId),
          params.result.refundInstruction,
          {merge: true},
        );
      }
      for (const event of params.result.events) {
        transaction.set(
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
    }
  });
}

async function persistCanonicalNotificationsV3(params: {
  firestore: Firestore;
  notifications?: ReadonlyArray<BookingNotificationPlan> | null;
  actorId: string;
}): Promise<void> {
  const notifications = params.notifications ?? [];
  if (notifications.length === 0) return;
  const batch = params.firestore.batch();
  for (const notification of notifications) {
    batch.set(
      params.firestore.collection("notifications").doc(notification.idempotencyKey),
      buildStoredBookingNotificationDocument({
        notification,
        actorId: params.actorId,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        source: "canonical_v3",
      }),
      {merge: true},
    );
  }
  await batch.commit();
}

function pathToDoc(firestore: Firestore, path: string) {
  const segments = path.split("/").filter(Boolean);
  if (segments.length % 2 !== 0) {
    throw new Error(`Invalid document path: ${path}`);
  }
  return firestore.doc(path);
}

function serializeBookingForFirestore(booking: CanonicalBookingDocumentV3): Record<string, unknown> {
  return structuredClone(booking);
}

function serializePaymentAttemptForFirestore(
  paymentAttempt: CanonicalPaymentAttemptDocumentV3,
): Record<string, unknown> {
  return structuredClone(paymentAttempt);
}

function serializeBookingPrivateForFirestore(
  bookingPrivate: CanonicalBookingPrivateDocumentV3,
): Record<string, unknown> {
  return structuredClone(bookingPrivate);
}

function serializeBookingPrivateParticipantsForFirestore(
  bookingPrivateParticipants: BookingPrivateParticipantsDocumentV3,
): Record<string, unknown> {
  return structuredClone(bookingPrivateParticipants);
}

async function loadParentIdentityForPaymentV3(params: {
  firestore: Firestore;
  parentId: string;
}): Promise<AuthenticatedParentIdentity> {
  const [authRecord, userSnapshot] = await Promise.all([
    auth.getUser(params.parentId),
    params.firestore.collection("users").doc(params.parentId).get(),
  ]);
  const user = userSnapshot.data() ?? {};
  return {
    uid: params.parentId,
    displayName: asString(user.displayName) || asString(user.name) || asString(authRecord.displayName),
    fullName: asString(user.displayName) || asString(user.name) || asString(authRecord.displayName),
    photoUrl: asString(user.photoUrl) || asString(user.profileImage) || asString(authRecord.photoURL),
    email: asString(authRecord.email),
    phoneNumber: asString(authRecord.phoneNumber),
    rating: typeof user.ratingAverage === "number" && Number.isFinite(user.ratingAverage) ?
      user.ratingAverage as number :
      0,
    completedBookingCount: asInt(user.completedBookingCount, asInt(user.completedBookingsCount, 0)),
  };
}

async function loadProviderPrivateIdentityForPaymentV3(params: {
  providerId: string;
}): Promise<AuthenticatedProviderPrivateIdentity | null> {
  try {
    const authRecord = await auth.getUser(params.providerId);
    return {
      uid: params.providerId,
      phoneNumber: asString(authRecord.phoneNumber) || undefined,
    };
  } catch {
    return {
      uid: params.providerId,
      phoneNumber: undefined,
    };
  }
}

async function loadLiveServiceSnapshotForPaymentV3(params: {
  firestore: Firestore;
  serviceId: string;
}): Promise<(CanonicalServiceSource & LiveServiceSnapshot) | null> {
  const snapshot = await params.firestore.collection("services").doc(params.serviceId).get();
  if (!snapshot.exists) return null;
  const data = snapshot.data() ?? {};
  const location =
    typeof data.location === "object" && data.location != null ?
      data.location as Record<string, unknown> :
      {};
  return {
    id: asString(data.serviceId) || snapshot.id,
    ownerUserId: asString(data.ownerUserId),
    ownerName: asString(data.ownerName) || undefined,
    ownerUsername: asString(data.ownerUsername) || undefined,
    ownerPhotoUrl: asString(data.ownerPhotoUrl) || undefined,
    title: asString(data.title) || undefined,
    animalType: asString(data.animalType) || undefined,
    category: asString(data.category) || undefined,
    serviceType: asString(data.serviceType) || undefined,
    currency: asString(data.currency) || "INR",
    schedulingMode: asString(data.schedulingMode) || undefined,
    sessionDurationMinutes: asInt(data.sessionDurationMinutes, 0),
    capacity: asInt(data.capacity, 1),
    stats:
      typeof data.stats === "object" && data.stats != null ?
        data.stats as Record<string, unknown> :
        {},
    location: {
      displayAddress: asString(location.displayAddress) || undefined,
      latitude: typeof location.latitude === "number" ? location.latitude : null,
      longitude: typeof location.longitude === "number" ? location.longitude : null,
    },
    timezone: asString(data.timezone) || "Asia/Kolkata",
    availableDays: data.availableDays,
    startMinutes: data.startMinutes,
    endMinutes: data.endMinutes,
    sameForAllDays: data.sameForAllDays,
    isPaused: data.isPaused === true,
    isPausedByVerification: data.isPausedByVerification === true,
    status: asString(data.status) || undefined,
    isActive: data.isActive === true,
    isDeleted: data.isDeleted === true,
    isVisibleToMarketplace: data.isVisibleToMarketplace === true,
    providerVerificationStatus: asString(data.providerVerificationStatus) || undefined,
    providerVerificationGraceEndsAt: asNullableDate(data.providerVerificationGraceEndsAt),
  };
}

async function loadSlotOccupancyMap(params: {
  transaction: Transaction;
  firestore: Firestore;
  booking: CanonicalBookingDocumentV3;
}): Promise<Record<string, SlotOccupancyDocument>> {
  const entries: Record<string, SlotOccupancyDocument> = {};
  if (params.booking.bookingType !== "SLOT") return entries;
  for (const slot of slotSchedule(params.booking).slots) {
    const snapshot = await params.transaction.get(
      params.firestore.doc(slotOccupancyPath(params.booking.serviceId, slot.slotId)),
    );
    if (!snapshot.exists) continue;
    const data = snapshot.data() ?? {};
    entries[slot.slotId] = {
      slotId: asString(data.slotId) || slot.slotId,
      confirmedUnits: asInt(data.confirmedUnits, 0),
      capacitySnapshot: asInt(data.capacitySnapshot, params.booking.service.capacitySnapshot),
      bookingClaims: asRecord(data.bookingClaims) as Record<string, number>,
    };
  }
  return entries;
}

async function loadRangeOccupancyMap(params: {
  transaction: Transaction;
  firestore: Firestore;
  booking: CanonicalBookingDocumentV3;
}): Promise<Record<string, RangeOccupancyDocument>> {
  const entries: Record<string, RangeOccupancyDocument> = {};
  if (params.booking.bookingType !== "RANGE") return entries;
  for (const dateKey of rangeDateKeys(params.booking)) {
    const snapshot = await params.transaction.get(
      params.firestore.doc(rangeOccupancyPath(params.booking.serviceId, dateKey)),
    );
    if (!snapshot.exists) continue;
    const data = snapshot.data() ?? {};
    entries[dateKey] = {
      dateKey,
      confirmedPetUnits: asInt(data.confirmedPetUnits, 0),
      capacitySnapshot: asInt(data.capacitySnapshot, params.booking.service.capacitySnapshot),
      bookingClaims: asRecord(data.bookingClaims) as Record<string, number>,
    };
  }
  return entries;
}

export async function submitRefundInstructionV3(params: {
  firestore: Firestore;
  bookingId: string;
  paymentAttemptId: string;
  keyId: string;
  keySecret: string;
  authoritativeNow?: Date;
}): Promise<"REFUND_PENDING" | "REFUNDED" | "RETRY_LATER" | "SKIPPED"> {
  const authoritativeNow = params.authoritativeNow ?? new Date();
  const bookingRef = params.firestore.collection("bookings").doc(params.bookingId);
  const attemptRef = bookingRef.collection("paymentAttempts").doc(params.paymentAttemptId);
  const refundRef = params.firestore.collection("refunds").doc(params.bookingId);
  const loaded = await params.firestore.runTransaction(async (transaction) => {
    const [attemptSnapshot, refundSnapshot] = await Promise.all([
      transaction.get(attemptRef),
      transaction.get(refundRef),
    ]);
    if (!attemptSnapshot.exists || !refundSnapshot.exists) {
      return null;
    }
    return {
      attempt: attemptSnapshot.data() as CanonicalPaymentAttemptDocumentV3,
      refund: refundSnapshot.data() as Record<string, unknown>,
    };
  });
  if (!loaded) return "SKIPPED";
  if (loaded.attempt.state !== "REFUND_REQUIRED" && loaded.attempt.state !== "REFUND_PENDING") {
    return "SKIPPED";
  }
  if (!loaded.attempt.razorpayPaymentId) return "SKIPPED";

  try {
    const refund = await processRazorpayRefundV3({
      keyId: params.keyId,
      keySecret: params.keySecret,
      razorpayPaymentId: loaded.attempt.razorpayPaymentId,
      refundAmountPaise: asInt(loaded.refund.refundAmountPaise, loaded.attempt.amountPaise),
      reason: asString(loaded.refund.reasonCode) || loaded.attempt.failureCode || "canonical_refund_required",
    });
    await Promise.all([
      attemptRef.set({
        state: "REFUND_PENDING",
        nextReconciliationAt: null,
        lastReconciledAt: FieldValue.serverTimestamp(),
        reconciliationAttemptCount: FieldValue.increment(1),
        lastReconciliationCode: "REFUND_SUBMITTED",
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true}),
      refundRef.set({
        state: refund.status === "processed" ? "processed" : "submitted",
        submittedAt: FieldValue.serverTimestamp(),
        razorpayRefundId: refund.razorpayRefundId,
        attemptCount: FieldValue.increment(1),
        lastErrorCode: "",
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true}),
    ]);
    return refund.status === "processed" ? "REFUNDED" : "REFUND_PENDING";
  } catch (error) {
    const code = error instanceof HttpsError ? error.code : "unknown";
    await Promise.all([
      attemptRef.set({
        nextReconciliationAt: Timestamp.fromDate(nextReconciliationAtForAttempt({
          now: authoritativeNow,
          attemptCount: loaded.attempt.reconciliationAttemptCount + 1,
        })),
        lastReconciledAt: FieldValue.serverTimestamp(),
        reconciliationAttemptCount: FieldValue.increment(1),
        lastReconciliationCode: `REFUND_${code.toUpperCase()}`,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true}),
      refundRef.set({
        state: "required",
        attemptCount: FieldValue.increment(1),
        lastErrorCode: code,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true}),
    ]);
    return "RETRY_LATER";
  }
}

export async function finalizeCapturedCanonicalPaymentV3(params: {
  firestore: Firestore;
  facts: CanonicalCapturedPaymentFacts;
  keyId?: string;
  keySecret?: string;
  authoritativeNow?: Date;
}): Promise<FinalizePaymentResult> {
  const authoritativeNow = params.authoritativeNow ?? new Date();
  const bookingRef = params.firestore.collection("bookings").doc(params.facts.bookingId);
  const paymentAttemptRef = bookingRef.collection("paymentAttempts").doc(params.facts.paymentAttemptId);
  const bookingPrivateRef = params.firestore.collection("bookingPrivate").doc(params.facts.bookingId);
  const bookingPrivateParticipantsRef =
    params.firestore.collection("bookingPrivateParticipants").doc(params.facts.bookingId);
  const loaded = await params.firestore.runTransaction(async (transaction) => {
    const bookingSnapshot = await transaction.get(bookingRef);
    if (!bookingSnapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }
    const attemptSnapshot = await transaction.get(paymentAttemptRef);
    if (!attemptSnapshot.exists) {
      throw new HttpsError("not-found", "Payment attempt not found.");
    }
    const booking = requireCanonicalBookingForPaymentFinalization({
      rawBooking: bookingSnapshot.data(),
      bookingId: params.facts.bookingId,
      paymentAttemptId: params.facts.paymentAttemptId,
    });
    const paymentAttempt = requireCanonicalPaymentAttemptForFinalization({
      rawAttempt: attemptSnapshot.data(),
      bookingId: params.facts.bookingId,
      paymentAttemptId: params.facts.paymentAttemptId,
    });
    const [bookingPrivateSnapshot, bookingPrivateParticipantsSnapshot] = await Promise.all([
      transaction.get(bookingPrivateRef),
      transaction.get(bookingPrivateParticipantsRef),
    ]);
    const slotOccupancy = await loadSlotOccupancyMap({
      transaction,
      firestore: params.firestore,
      booking,
    });
    const rangeOccupancy = await loadRangeOccupancyMap({
      transaction,
      firestore: params.firestore,
      booking,
    });
    return {
      booking,
      paymentAttempt,
      bookingPrivate: bookingPrivateSnapshot.exists ?
        bookingPrivateSnapshot.data() as CanonicalBookingPrivateDocumentV3 :
        null,
      bookingPrivateParticipants: bookingPrivateParticipantsSnapshot.exists ?
        bookingPrivateParticipantsSnapshot.data() as BookingPrivateParticipantsDocumentV3 :
        null,
      slotOccupancy,
      rangeOccupancy,
    };
  });

  const parent = await loadParentIdentityForPaymentV3({
    firestore: params.firestore,
    parentId: loaded.booking.parentId,
  });
  const service = await loadLiveServiceSnapshotForPaymentV3({
    firestore: params.firestore,
    serviceId: loaded.booking.serviceId,
  });
  const providerPrivate = await loadProviderPrivateIdentityForPaymentV3({
    providerId: loaded.booking.providerId,
  });

  const result = finalizeCapturedBookingPaymentV3({
    bookingId: params.facts.bookingId,
    booking: loaded.booking,
    paymentAttempt: loaded.paymentAttempt,
    parent,
    providerPrivate,
    service,
    existingBookingPrivate: loaded.bookingPrivate,
    existingBookingPrivateParticipants: loaded.bookingPrivateParticipants,
    slotOccupancy: loaded.slotOccupancy,
    rangeOccupancy: loaded.rangeOccupancy,
    razorpayPayment: {
      id: params.facts.razorpayPaymentId,
      orderId: params.facts.razorpayOrderId,
      status: "captured",
      amountPaise: params.facts.capturedAmountPaise,
      currency: params.facts.currency,
      createdAt: params.facts.capturedAt,
      capturedAt: params.facts.capturedAt,
    },
    authoritativeNow,
    verificationSource: params.facts.verificationSource,
  });

  await persistFinalizePaymentResultV3({
    firestore: params.firestore,
    result,
    bookingId: params.facts.bookingId,
  });
  if (!result.ok &&
    result.refundInstruction &&
    params.facts.razorpayPaymentId &&
    params.keyId?.trim() &&
    params.keySecret?.trim()) {
    await submitRefundInstructionV3({
      firestore: params.firestore,
      bookingId: params.facts.bookingId,
      paymentAttemptId: params.facts.paymentAttemptId,
      keyId: params.keyId,
      keySecret: params.keySecret,
      authoritativeNow,
    }).catch(() => undefined);
  }
  return result;
}

export async function verifyCapturedBookingPaymentV3(params: {
  firestore: Firestore;
  bookingId: string;
  paymentAttemptId: string;
  verificationSource: "callable" | "webhook" | "reconciliation";
  keyId: string;
  keySecret: string;
  razorpayOrderId: string;
  razorpayPaymentId: string;
  authoritativeNow?: Date;
}): Promise<FinalizePaymentResult> {
  const authoritativeNow = params.authoritativeNow ?? new Date();
  const capture = await resolveCapturedRazorpayPaymentV3({
    keyId: params.keyId,
    keySecret: params.keySecret,
    paymentId: params.razorpayPaymentId,
    orderId: params.razorpayOrderId,
  });
  return finalizeCapturedCanonicalPaymentV3({
    firestore: params.firestore,
    facts: {
      bookingId: params.bookingId,
      paymentAttemptId: params.paymentAttemptId,
      razorpayOrderId: capture.orderId,
      razorpayPaymentId: capture.id,
      capturedAmountPaise: capture.amountPaise,
      currency: capture.currency,
      capturedAt: capture.capturedAt ?? capture.createdAt ?? authoritativeNow,
      verificationSource: params.verificationSource,
    },
    keyId: params.keyId,
    keySecret: params.keySecret,
    authoritativeNow,
  });
}

export async function tryAcquireReconciliationLease(params: {
  firestore: Firestore;
  attemptRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
  authoritativeNow: Date;
}): Promise<boolean> {
  const leaseOwner =
    `${params.attemptRef.parent.parent?.id ?? "booking"}:${params.attemptRef.id}:${params.authoritativeNow.getTime()}`;
  return params.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(params.attemptRef);
    if (!snapshot.exists) return false;
    const attempt = snapshot.data() as CanonicalPaymentAttemptDocumentV3;
    if (
      !attempt.bookingId ||
      !attempt.paymentAttemptId ||
      attempt.terminalFailureAt != null ||
      !CANONICAL_RECONCILIATION_ATTEMPT_STATES.includes(
        attempt.state as typeof CANONICAL_RECONCILIATION_ATTEMPT_STATES[number],
      )
    ) {
      return false;
    }
    const leaseExpiresAt = asNullableDate(attempt.leaseExpiresAt);
    if (
      attempt.leaseOwner.trim().length > 0 &&
      leaseExpiresAt != null &&
      leaseExpiresAt.getTime() > params.authoritativeNow.getTime()
    ) {
      return false;
    }
    transaction.set(params.attemptRef, {
      leaseOwner,
      leaseExpiresAt: Timestamp.fromDate(
        reconciliationLeaseExpiresAt(params.authoritativeNow),
      ),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return true;
  });
}

export async function releaseReconciliationLease(params: {
  attemptRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
}): Promise<void> {
  await params.attemptRef.set({
    leaseOwner: "",
    leaseExpiresAt: null,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}

export function reconciliationDue(
  attempt: CanonicalPaymentAttemptDocumentV3,
  now: Date,
): boolean {
  if (attempt.terminalFailureAt != null) return false;
  if (attempt.nextReconciliationAt == null) return true;
  return attempt.nextReconciliationAt.getTime() <= now.getTime();
}

function isNotCapturedError(error: unknown): boolean {
  return error instanceof HttpsError &&
    (error.code === "failed-precondition" || error.code === "not-found") &&
    error.message.toLowerCase().includes("not captured");
}

function isTransientGatewayError(error: unknown): boolean {
  if (!(error instanceof HttpsError)) return false;
  return error.code === "unavailable" ||
    error.code === "deadline-exceeded" ||
    error.code === "internal" ||
    error.code === "resource-exhausted";
}

export async function reconcilePaymentAttemptsV3(params: {
  firestore: Firestore;
  keyId: string;
  keySecret: string;
  limit?: number;
  authoritativeNow?: Date;
  deps?: {
    verifyCapturedPayment?: typeof verifyCapturedBookingPaymentV3;
    submitRefundInstruction?: typeof submitRefundInstructionV3;
    persistNotifications?: typeof persistCanonicalNotificationsV3;
  };
}): Promise<number> {
  const authoritativeNow = params.authoritativeNow ?? new Date();
  const verifyCapturedPayment =
    params.deps?.verifyCapturedPayment ?? verifyCapturedBookingPaymentV3;
  const submitRefundInstruction =
    params.deps?.submitRefundInstruction ?? submitRefundInstructionV3;
  const persistNotifications =
    params.deps?.persistNotifications ?? persistCanonicalNotificationsV3;
  const query = await params.firestore.collectionGroup("paymentAttempts")
    .where("state", "in", [...CANONICAL_RECONCILIATION_ATTEMPT_STATES])
    .limit(Math.max(params.limit ?? DEFAULT_RECONCILIATION_LIMIT, 1))
    .get();
  let processed = 0;

  for (const doc of query.docs) {
    const attempt = doc.data() as CanonicalPaymentAttemptDocumentV3;
    if (!attempt.bookingId || !attempt.paymentAttemptId) continue;
    if (!reconciliationDue(attempt, authoritativeNow)) continue;

    const acquired = await tryAcquireReconciliationLease({
      firestore: params.firestore,
      attemptRef: doc.ref,
      authoritativeNow,
    });
    if (!acquired) continue;

    try {
      if (attempt.state === "REFUND_REQUIRED" || attempt.state === "REFUND_PENDING") {
        const refundResult = await submitRefundInstruction({
          firestore: params.firestore,
          bookingId: attempt.bookingId,
          paymentAttemptId: attempt.paymentAttemptId,
          keyId: params.keyId,
          keySecret: params.keySecret,
          authoritativeNow,
        });
        if (refundResult !== "SKIPPED") {
          processed += 1;
        }
        continue;
      }

      if (!attempt.razorpayPaymentId || !attempt.razorpayOrderId) {
        await doc.ref.set({
          terminalFailureAt: FieldValue.serverTimestamp(),
          lastReconciledAt: FieldValue.serverTimestamp(),
          lastReconciliationCode: "MISSING_PAYMENT_LINKAGE",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        continue;
      }

      try {
        const result = await verifyCapturedPayment({
          firestore: params.firestore,
          bookingId: attempt.bookingId,
          paymentAttemptId: attempt.paymentAttemptId,
          verificationSource: "reconciliation",
          keyId: params.keyId,
          keySecret: params.keySecret,
          razorpayOrderId: attempt.razorpayOrderId,
          razorpayPaymentId: attempt.razorpayPaymentId,
          authoritativeNow,
        });
        await persistNotifications({
          firestore: params.firestore,
          notifications: result.notifications,
          actorId: "system",
        });
        await doc.ref.set({
          nextReconciliationAt: null,
          lastReconciledAt: FieldValue.serverTimestamp(),
          reconciliationAttemptCount: FieldValue.increment(1),
          lastReconciliationCode: result.ok ?
            (result.code === "IDEMPOTENT_REPLAY" ? "ALREADY_CONFIRMED" : "CONFIRMED") :
            result.paymentAttempt.state,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        processed += 1;
      } catch (error) {
        if (isNotCapturedError(error) || isTransientGatewayError(error)) {
          await doc.ref.set({
            state: "CAPTURED_REQUIRES_RECONCILIATION",
            nextReconciliationAt: Timestamp.fromDate(nextReconciliationAtForAttempt({
              now: authoritativeNow,
              attemptCount: attempt.reconciliationAttemptCount + 1,
            })),
            lastReconciledAt: FieldValue.serverTimestamp(),
            reconciliationAttemptCount: FieldValue.increment(1),
            lastReconciliationCode: isNotCapturedError(error) ?
              "PAYMENT_NOT_CAPTURED_YET" :
              "GATEWAY_RETRY",
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
          processed += 1;
          continue;
        }
        throw error;
      }
    } finally {
      await releaseReconciliationLease({attemptRef: doc.ref});
    }
  }

  return processed;
}
