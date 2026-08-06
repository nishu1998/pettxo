import {createHash, timingSafeEqual} from "node:crypto";

import {FieldValue, Timestamp, type Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/https";

import type {CanonicalBookingDocumentV3, CanonicalRangeScheduleV3, CanonicalSlotScheduleV3} from "../schema/bookingDocumentV3";
import type {CanonicalBookingPrivateDocumentV3} from "../schema/paymentAttemptDocumentV3";
import {buildBookingEventPlan} from "./bookingEventsWriter";
import {
  buildBookingNoShowNotifications,
  buildServiceStartedNotification,
  type BookingNotificationPlan,
} from "./bookingNotificationsV3";
import {buildStoredBookingNotificationDocument} from "../../notifications/notificationChannels";

export const BOOKING_SERVICE_STARTS_COLLECTION = "bookingServiceStarts";
export const BOOKING_NO_SHOWS_COLLECTION = "bookingNoShows";
export const SERVICE_START_POLICY_VERSION = "v3.2_slice7";
export const SERVICE_START_MAX_FAILED_ATTEMPTS = 5;
export const SERVICE_START_LOCKOUT_MS = 30 * 60 * 1000;
export const NO_SHOW_DISPUTE_WINDOW_MS = 24 * 60 * 60 * 1000;

const NO_SHOW_PROVIDER_SHARE_BASIS_POINTS = 8500;
const NO_SHOW_PETTXO_SHARE_BASIS_POINTS = 1500;
const NO_SHOW_CUSTOMER_REFUND_BASIS_POINTS = 0;

export type ServiceStartOutcomeCode =
  | "VERIFIED_STARTED"
  | "ALREADY_STARTED"
  | "INVALID_OTP"
  | "ATTEMPTS_EXCEEDED"
  | "TEMPORARILY_LOCKED"
  | "AFTER_SERVICE_END"
  | "BOOKING_CANCELLED"
  | "INVALID_STATE"
  | "PAYMENT_NOT_CONFIRMED"
  | "OTP_NOT_AVAILABLE"
  | "UNAUTHORIZED"
  | "INVALID_BOOKING_DATA"
  | "POLICY_NOT_CONFIGURED";

export type ServiceStartEligibilityCode =
  | "ALLOWED"
  | "AFTER_SERVICE_END"
  | "INVALID_BOOKING_DATA"
  | "POLICY_NOT_CONFIGURED";

export type ServiceEndResolutionCode =
  | "RESOLVED"
  | "INVALID_BOOKING_DATA"
  | "POLICY_NOT_CONFIGURED";

export type NoShowEvaluationCode =
  | "NOT_DUE"
  | "STARTED"
  | "ELIGIBLE_NO_SHOW"
  | "FINALIZED_NO_SHOW"
  | "ALREADY_FINALIZED"
  | "INVALID_BOOKING_DATA"
  | "INELIGIBLE_STATE";

export type BookingServiceStartRecord = {
  bookingId: string;
  providerId: string;
  parentId: string;
  serviceAnchorAt: Date;
  verifiedAt: Date;
  otpGeneratedAt: Date | null;
  otpVerifiedAt: Date;
  verificationAttemptId: string;
  successfulAttemptNumber: number;
  priorFailedAttempts: number;
  stateBefore: CanonicalBookingDocumentV3["state"];
  stateAfter: CanonicalBookingDocumentV3["state"];
  policyVersion: string;
  createdAt: Date;
  updatedAt: Date;
};

export type BookingNoShowRecord = {
  bookingId: string;
  providerId: string;
  parentId: string;
  bookingType: CanonicalBookingDocumentV3["bookingType"];
  serviceAnchorAt: Date;
  expectedServiceEndAt: Date;
  noShowAt: Date;
  noShowReasonCode: "OTP_NOT_ENTERED_BY_SERVICE_END";
  customerRefundBasisPoints: number;
  providerShareBasisPoints: number;
  pettxoShareBasisPoints: number;
  customerRefundPaise: number;
  providerCompensationPaise: number;
  pettxoRetainedPaise: number;
  pettxoCouponCostPaise: number;
  disputeEligible: true;
  disputeDeadlineAt: Date;
  payoutStatus: "held";
  payoutHoldReason: "NO_SHOW_DISPUTE_WINDOW";
  policyVersion: string;
  createdAt: Date;
  updatedAt: Date;
};

export type NoShowFinancialAllocation = {
  customerRefundBasisPoints: 0;
  providerShareBasisPoints: 8500;
  pettxoShareBasisPoints: 1500;
  customerRefundPaise: 0;
  providerCompensationPaise: number;
  pettxoRetainedPaise: number;
  pettxoCouponCostPaise: number;
  serviceSubtotalPaise: number;
  customerPaidPaise: number;
  providerPayoutPaise: number;
  platformCommissionPaise: number;
  policyVersion: string;
  reasonCode: "NO_SHOW_OTP_NOT_ENTERED";
};

export type ServiceStartApplyResult = {
  code: ServiceStartOutcomeCode;
  bookingId: string;
  state: CanonicalBookingDocumentV3["state"];
  otpEnteredAt: Date | null;
  idempotentReplay: boolean;
  retryAfterMs: number | null;
};

export type ServiceEndResolutionResult = {
  code: ServiceEndResolutionCode;
  serviceAnchorAt: Date | null;
  expectedServiceEndAt: Date | null;
};

export type ServiceStartEligibilityResult = {
  code: ServiceStartEligibilityCode;
  serviceAnchorAt: Date | null;
  expectedServiceEndAt: Date | null;
};

export type NoShowEvaluationResult = {
  code: NoShowEvaluationCode;
  serviceAnchorAt: Date | null;
  expectedServiceEndAt: Date | null;
};

function hasConfirmedPaymentV3(booking: CanonicalBookingDocumentV3): boolean {
  const normalizedStatus = booking.payment.status.trim().toLowerCase();
  return booking.lifecycle.paidAt != null &&
    (normalizedStatus === "paid" || normalizedStatus === "confirmed");
}

function asDate(value: unknown): Date | null {
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value;
  if (typeof value === "object" && value != null && "toDate" in value) {
    try {
      const converted = (value as {toDate(): Date}).toDate();
      return Number.isNaN(converted.getTime()) ? null : converted;
    } catch {
      return null;
    }
  }
  return null;
}

function asNonNegativeInteger(value: unknown): number | null {
  return Number.isInteger(value) && (value as number) >= 0
    ? value as number
    : null;
}

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function slotSchedule(booking: CanonicalBookingDocumentV3): CanonicalSlotScheduleV3 {
  return booking.schedule as CanonicalSlotScheduleV3;
}

function rangeSchedule(booking: CanonicalBookingDocumentV3): CanonicalRangeScheduleV3 {
  return booking.schedule as CanonicalRangeScheduleV3;
}

function serviceAnchorAt(booking: CanonicalBookingDocumentV3): Date {
  return booking.bookingType === "SLOT"
    ? slotSchedule(booking).scheduledStartAt
    : rangeSchedule(booking).checkInDateTime;
}

function hashOtp(bookingId: string, otp: string): string {
  return createHash("sha256").update(`${bookingId}:${otp}`).digest("hex");
}

function safeOtpMatches(expectedHash: string, bookingId: string, candidate: string): boolean {
  const normalizedExpected = expectedHash.trim();
  if (!/^[a-f0-9]{64}$/i.test(normalizedExpected)) return false;
  const expected = Buffer.from(normalizedExpected, "hex");
  const actual = Buffer.from(hashOtp(bookingId, candidate), "hex");
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

export function resolveAuthoritativeServiceEndV3(params: {
  booking: CanonicalBookingDocumentV3;
}): ServiceEndResolutionResult {
  const booking = params.booking;
  const anchor = asDate(serviceAnchorAt(booking));
  if (anchor == null) {
    return {
      code: "INVALID_BOOKING_DATA",
      serviceAnchorAt: null,
      expectedServiceEndAt: null,
    };
  }

  if (booking.bookingType === "RANGE") {
    const schedule = rangeSchedule(booking);
    const checkIn = asDate(schedule.checkInDateTime);
    const checkOut = asDate(schedule.checkOutDateTime);
    if (checkIn == null || checkOut == null) {
      return {
        code: "INVALID_BOOKING_DATA",
        serviceAnchorAt: anchor,
        expectedServiceEndAt: null,
      };
    }
    if (checkOut.getTime() <= checkIn.getTime()) {
      return {
        code: "INVALID_BOOKING_DATA",
        serviceAnchorAt: anchor,
        expectedServiceEndAt: null,
      };
    }
    return {
      code: "RESOLVED",
      serviceAnchorAt: anchor,
      expectedServiceEndAt: checkOut,
    };
  }

  const schedule = slotSchedule(booking);
  const scheduledStartAt = asDate(schedule.scheduledStartAt);
  if (scheduledStartAt == null) {
    return {
      code: "INVALID_BOOKING_DATA",
      serviceAnchorAt: anchor,
      expectedServiceEndAt: null,
    };
  }

  const slotEnds = schedule.slots
    .map((slot) => asDate(slot.endAt))
    .filter((value): value is Date => value != null);
  const canonicalSlotEnd = slotEnds.length === schedule.slots.length && slotEnds.length > 0
    ? slotEnds.reduce((latest, current) =>
      current.getTime() > latest.getTime() ? current : latest)
    : null;
  const scheduledEndAt = asDate(schedule.scheduledEndAt);
  const totalDurationMinutes = asNonNegativeInteger(schedule.totalDurationMinutes);
  const derivedEndAt =
    totalDurationMinutes != null && totalDurationMinutes > 0
      ? new Date(scheduledStartAt.getTime() + totalDurationMinutes * 60 * 1000)
      : null;

  const candidates = [canonicalSlotEnd, scheduledEndAt, derivedEndAt]
    .filter((value): value is Date => value != null);
  if (candidates.length === 0) {
    return {
      code: "POLICY_NOT_CONFIGURED",
      serviceAnchorAt: anchor,
      expectedServiceEndAt: null,
    };
  }

  const resolved = canonicalSlotEnd ?? scheduledEndAt ?? derivedEndAt ?? null;
  if (resolved == null) {
    return {
      code: "POLICY_NOT_CONFIGURED",
      serviceAnchorAt: anchor,
      expectedServiceEndAt: null,
    };
  }
  if (resolved.getTime() <= scheduledStartAt.getTime()) {
    return {
      code: "INVALID_BOOKING_DATA",
      serviceAnchorAt: anchor,
      expectedServiceEndAt: null,
    };
  }
  if (canonicalSlotEnd != null &&
      scheduledEndAt != null &&
      canonicalSlotEnd.getTime() !== scheduledEndAt.getTime()) {
    return {
      code: "INVALID_BOOKING_DATA",
      serviceAnchorAt: anchor,
      expectedServiceEndAt: null,
    };
  }
  if (scheduledEndAt != null &&
      derivedEndAt != null &&
      scheduledEndAt.getTime() !== derivedEndAt.getTime()) {
    return {
      code: "INVALID_BOOKING_DATA",
      serviceAnchorAt: anchor,
      expectedServiceEndAt: null,
    };
  }
  if (canonicalSlotEnd != null &&
      derivedEndAt != null &&
      canonicalSlotEnd.getTime() !== derivedEndAt.getTime()) {
    return {
      code: "INVALID_BOOKING_DATA",
      serviceAnchorAt: anchor,
      expectedServiceEndAt: null,
    };
  }

  return {
    code: "RESOLVED",
    serviceAnchorAt: anchor,
    expectedServiceEndAt: resolved,
  };
}

export function evaluateCanonicalServiceStartEligibilityV3(params: {
  booking: CanonicalBookingDocumentV3;
  authoritativeNow: Date;
}): ServiceStartEligibilityResult {
  const resolved = resolveAuthoritativeServiceEndV3({booking: params.booking});
  if (resolved.code !== "RESOLVED") {
    return {
      code: resolved.code,
      serviceAnchorAt: resolved.serviceAnchorAt,
      expectedServiceEndAt: resolved.expectedServiceEndAt,
    };
  }
  if (!(params.authoritativeNow instanceof Date) || Number.isNaN(params.authoritativeNow.getTime())) {
    return {
      code: "INVALID_BOOKING_DATA",
      serviceAnchorAt: resolved.serviceAnchorAt,
      expectedServiceEndAt: resolved.expectedServiceEndAt,
    };
  }
  if (params.authoritativeNow.getTime() > resolved.expectedServiceEndAt!.getTime()) {
    return {
      code: "AFTER_SERVICE_END",
      serviceAnchorAt: resolved.serviceAnchorAt,
      expectedServiceEndAt: resolved.expectedServiceEndAt,
    };
  }
  return {
    code: "ALLOWED",
    serviceAnchorAt: resolved.serviceAnchorAt,
    expectedServiceEndAt: resolved.expectedServiceEndAt,
  };
}

export function evaluateCanonicalNoShowEligibilityV3(params: {
  booking: CanonicalBookingDocumentV3;
  authoritativeNow: Date;
  hasSuccessfulServiceStartArtifact?: boolean;
}): NoShowEvaluationResult {
  const booking = params.booking;
  if (booking.state === "NO_SHOW") {
    return {
      code: "ALREADY_FINALIZED",
      serviceAnchorAt: asDate(serviceAnchorAt(booking)),
      expectedServiceEndAt: resolveAuthoritativeServiceEndV3({booking}).expectedServiceEndAt,
    };
  }
  if (booking.lifecycle.otpEnteredAt != null ||
      booking.state === "IN_PROGRESS" ||
      booking.state === "COMPLETED_PENDING_REVIEW" ||
      booking.state === "COMPLETED_FINAL" ||
      params.hasSuccessfulServiceStartArtifact === true) {
    return {
      code: "STARTED",
      serviceAnchorAt: asDate(serviceAnchorAt(booking)),
      expectedServiceEndAt: resolveAuthoritativeServiceEndV3({booking}).expectedServiceEndAt,
    };
  }
  if (booking.state !== "CONFIRMED" || !hasConfirmedPaymentV3(booking)) {
    return {
      code: "INELIGIBLE_STATE",
      serviceAnchorAt: asDate(serviceAnchorAt(booking)),
      expectedServiceEndAt: resolveAuthoritativeServiceEndV3({booking}).expectedServiceEndAt,
    };
  }
  const resolved = resolveAuthoritativeServiceEndV3({booking});
  if (resolved.code !== "RESOLVED") {
    return {
      code: "INVALID_BOOKING_DATA",
      serviceAnchorAt: resolved.serviceAnchorAt,
      expectedServiceEndAt: resolved.expectedServiceEndAt,
    };
  }
  if (params.authoritativeNow.getTime() <= resolved.expectedServiceEndAt!.getTime()) {
    return {
      code: "NOT_DUE",
      serviceAnchorAt: resolved.serviceAnchorAt,
      expectedServiceEndAt: resolved.expectedServiceEndAt,
    };
  }
  return {
    code: "ELIGIBLE_NO_SHOW",
    serviceAnchorAt: resolved.serviceAnchorAt,
    expectedServiceEndAt: resolved.expectedServiceEndAt,
  };
}

export function calculateCanonicalNoShowAllocationV3(params: {
  booking: CanonicalBookingDocumentV3;
}): NoShowFinancialAllocation {
  const financials = params.booking.financials;
  if (financials == null) {
    throw new HttpsError("failed-precondition", "Missing canonical financial snapshot.");
  }
  return {
    customerRefundBasisPoints: NO_SHOW_CUSTOMER_REFUND_BASIS_POINTS,
    providerShareBasisPoints: NO_SHOW_PROVIDER_SHARE_BASIS_POINTS,
    pettxoShareBasisPoints: NO_SHOW_PETTXO_SHARE_BASIS_POINTS,
    customerRefundPaise: 0,
    providerCompensationPaise: financials.providerPayoutPaise,
    pettxoRetainedPaise: financials.platformCommissionPaise,
    pettxoCouponCostPaise: financials.pettxoCouponFundingPaise,
    serviceSubtotalPaise: financials.serviceSubtotalPaise,
    customerPaidPaise: financials.customerPaidPaise,
    providerPayoutPaise: financials.providerPayoutPaise,
    platformCommissionPaise: financials.platformCommissionPaise,
    policyVersion: SERVICE_START_POLICY_VERSION,
    reasonCode: "NO_SHOW_OTP_NOT_ENTERED",
  };
}

function buildServiceStartRecord(params: {
  booking: CanonicalBookingDocumentV3;
  bookingId: string;
  authoritativeNow: Date;
  requestAttemptId: string;
  priorFailedAttempts: number;
  successfulAttemptNumber: number;
}): BookingServiceStartRecord {
  const normalizedServiceAnchorAt = asDate(serviceAnchorAt(params.booking));
  if (normalizedServiceAnchorAt == null) {
    throw new HttpsError(
      "failed-precondition",
      "Booking is missing a valid service anchor time.",
    );
  }
  return {
    bookingId: params.bookingId,
    providerId: params.booking.providerId,
    parentId: params.booking.parentId,
    serviceAnchorAt: normalizedServiceAnchorAt,
    verifiedAt: new Date(params.authoritativeNow.getTime()),
    otpGeneratedAt: asDate(params.booking.lifecycle.otpGeneratedAt),
    otpVerifiedAt: new Date(params.authoritativeNow.getTime()),
    verificationAttemptId: params.requestAttemptId,
    successfulAttemptNumber: params.successfulAttemptNumber,
    priorFailedAttempts: params.priorFailedAttempts,
    stateBefore: params.booking.state,
    stateAfter: "IN_PROGRESS",
    policyVersion: SERVICE_START_POLICY_VERSION,
    createdAt: new Date(params.authoritativeNow.getTime()),
    updatedAt: new Date(params.authoritativeNow.getTime()),
  };
}

function buildServiceStartNotification(params: {
  booking: CanonicalBookingDocumentV3;
  bookingId: string;
}): BookingNotificationPlan {
  return buildServiceStartedNotification({
    bookingId: params.bookingId,
    parentId: params.booking.parentId,
    bookingType: params.booking.bookingType,
    state: "IN_PROGRESS",
  });
}

function buildNoShowNotifications(params: {
  booking: CanonicalBookingDocumentV3;
  bookingId: string;
}): BookingNotificationPlan[] {
  return buildBookingNoShowNotifications({
    bookingId: params.bookingId,
    parentId: params.booking.parentId,
    providerId: params.booking.providerId,
    bookingType: params.booking.bookingType,
    state: "NO_SHOW",
  });
}

export function buildNoShowRecord(params: {
  booking: CanonicalBookingDocumentV3;
  bookingId: string;
  authoritativeNow: Date;
  expectedServiceEndAt: Date;
}): BookingNoShowRecord {
  const normalizedServiceAnchorAt = asDate(serviceAnchorAt(params.booking));
  if (normalizedServiceAnchorAt == null) {
    throw new Error(
      `Booking ${params.bookingId} is missing a valid authoritative service anchor time.`,
    );
  }
  const noShowAt = new Date(params.expectedServiceEndAt.getTime());
  const disputeDeadlineAt = new Date(
    noShowAt.getTime() + NO_SHOW_DISPUTE_WINDOW_MS,
  );
  const allocation = calculateCanonicalNoShowAllocationV3({booking: params.booking});
  return {
    bookingId: params.bookingId,
    providerId: params.booking.providerId,
    parentId: params.booking.parentId,
    bookingType: params.booking.bookingType,
    serviceAnchorAt: normalizedServiceAnchorAt,
    expectedServiceEndAt: new Date(params.expectedServiceEndAt.getTime()),
    noShowAt,
    noShowReasonCode: "OTP_NOT_ENTERED_BY_SERVICE_END",
    customerRefundBasisPoints: allocation.customerRefundBasisPoints,
    providerShareBasisPoints: allocation.providerShareBasisPoints,
    pettxoShareBasisPoints: allocation.pettxoShareBasisPoints,
    customerRefundPaise: allocation.customerRefundPaise,
    providerCompensationPaise: allocation.providerCompensationPaise,
    pettxoRetainedPaise: allocation.pettxoRetainedPaise,
    pettxoCouponCostPaise: allocation.pettxoCouponCostPaise,
    disputeEligible: true,
    disputeDeadlineAt,
    payoutStatus: "held",
    payoutHoldReason: "NO_SHOW_DISPUTE_WINDOW",
    policyVersion: SERVICE_START_POLICY_VERSION,
    createdAt: new Date(params.authoritativeNow.getTime()),
    updatedAt: new Date(params.authoritativeNow.getTime()),
  };
}

export async function verifyBookingStartOtpV3(params: {
  firestore: Firestore;
  bookingId: string;
  providerId: string;
  otpCandidate: string;
  requestAttemptId: string;
  authoritativeNow?: Date;
}): Promise<ServiceStartApplyResult> {
  const authoritativeNow = params.authoritativeNow ?? new Date();
  const bookingRef = params.firestore.collection("bookings").doc(params.bookingId);
  const bookingPrivateRef = params.firestore.collection("bookingPrivate").doc(params.bookingId);
  const serviceStartRef = params.firestore.collection(BOOKING_SERVICE_STARTS_COLLECTION).doc(params.bookingId);
  const notificationRef = params.firestore
    .collection("notifications")
    .doc(`service_started:${params.bookingId}:${params.providerId}`);

  const otpCandidate = params.otpCandidate.trim();
  if (!/^\d{6}$/.test(otpCandidate)) {
    return {
      code: "INVALID_OTP",
      bookingId: params.bookingId,
      state: "CONFIRMED",
      otpEnteredAt: null,
      idempotentReplay: false,
      retryAfterMs: null,
    };
  }

  let checkpoint = "OTP_VERIFY_REQUEST_RECEIVED";
  let currentState = "";
  console.info("OTP_VERIFY_REQUEST_RECEIVED", {
    bookingId: params.bookingId,
    providerUid: params.providerId,
    bookingPath: bookingRef.path,
    bookingPrivatePath: bookingPrivateRef.path,
    serviceStartPath: serviceStartRef.path,
  });
  try {
    return await params.firestore.runTransaction(async (transaction) => {
      const [bookingSnapshot, bookingPrivateSnapshot, serviceStartSnapshot] = await Promise.all([
        transaction.get(bookingRef),
        transaction.get(bookingPrivateRef),
        transaction.get(serviceStartRef),
      ]);

      checkpoint = "OTP_VERIFY_BOOKING_LOADED";
      console.info("OTP_VERIFY_BOOKING_LOADED", {
        bookingId: params.bookingId,
        providerUid: params.providerId,
      });
      if (!bookingSnapshot.exists) {
        throw new HttpsError("not-found", "Booking not found.");
      }

      const booking = bookingSnapshot.data() as CanonicalBookingDocumentV3;
      currentState = booking.state;
      const bookingOtpEnteredAt = asDate(booking.lifecycle.otpEnteredAt);
      if (booking.providerId !== params.providerId) {
        return {
          code: "UNAUTHORIZED",
          bookingId: params.bookingId,
          state: booking.state,
          otpEnteredAt: bookingOtpEnteredAt,
          idempotentReplay: false,
          retryAfterMs: null,
        };
      }
      if (booking.state === "IN_PROGRESS" || serviceStartSnapshot.exists) {
        return {
          code: "ALREADY_STARTED",
          bookingId: params.bookingId,
          state: "IN_PROGRESS",
          otpEnteredAt:
            bookingOtpEnteredAt ??
            asDate(serviceStartSnapshot.data()?.otpVerifiedAt),
          idempotentReplay: true,
          retryAfterMs: null,
        };
      }
      if (booking.state === "CANCELLED" || booking.state === "NO_SHOW") {
        return {
          code: "BOOKING_CANCELLED",
          bookingId: params.bookingId,
          state: booking.state,
          otpEnteredAt: bookingOtpEnteredAt,
          idempotentReplay: false,
          retryAfterMs: null,
        };
      }
      if (booking.state !== "CONFIRMED") {
        return {
          code: !hasConfirmedPaymentV3(booking)
            ? "PAYMENT_NOT_CONFIRMED"
            : "INVALID_STATE",
          bookingId: params.bookingId,
          state: booking.state,
          otpEnteredAt: bookingOtpEnteredAt,
          idempotentReplay: false,
          retryAfterMs: null,
        };
      }
      if (!hasConfirmedPaymentV3(booking)) {
        return {
          code: "PAYMENT_NOT_CONFIRMED",
          bookingId: params.bookingId,
          state: booking.state,
          otpEnteredAt: null,
          idempotentReplay: false,
          retryAfterMs: null,
        };
      }

      checkpoint = "OTP_VERIFY_PRIVATE_RECORD_LOADED";
      console.info("OTP_VERIFY_PRIVATE_RECORD_LOADED", {
        bookingId: params.bookingId,
        providerUid: params.providerId,
        serviceStartExists: serviceStartSnapshot.exists,
      });
      const bookingPrivate = bookingPrivateSnapshot.exists
        ? bookingPrivateSnapshot.data() as CanonicalBookingPrivateDocumentV3
        : null;
      if (!bookingPrivate || !asTrimmedString(bookingPrivate.providerOtpHash)) {
        return {
          code: "OTP_NOT_AVAILABLE",
          bookingId: params.bookingId,
          state: booking.state,
          otpEnteredAt: null,
          idempotentReplay: false,
          retryAfterMs: null,
        };
      }

      checkpoint = "OTP_VERIFY_AUTHORIZED";
      console.info("OTP_VERIFY_AUTHORIZED", {
        bookingId: params.bookingId,
        providerUid: params.providerId,
        bookingState: booking.state,
      });
      if (bookingPrivate.lastVerificationAttemptId === params.requestAttemptId) {
        const previousOutcome = bookingPrivate.lastVerificationOutcome.trim();
        if (previousOutcome === "VERIFIED_STARTED" || previousOutcome === "ALREADY_STARTED") {
          return {
            code: "ALREADY_STARTED",
            bookingId: params.bookingId,
            state: "IN_PROGRESS",
            otpEnteredAt: asDate(bookingPrivate.verifiedAt) ?? bookingOtpEnteredAt,
            idempotentReplay: true,
            retryAfterMs: null,
          };
        }
        if (previousOutcome === "INVALID_OTP") {
          return {
            code: "INVALID_OTP",
            bookingId: params.bookingId,
            state: booking.state,
            otpEnteredAt: null,
            idempotentReplay: true,
            retryAfterMs: null,
          };
        }
        if (previousOutcome === "TEMPORARILY_LOCKED") {
          const lockedUntil = asDate(bookingPrivate.lockedUntil);
          const retryAfterMs = lockedUntil == null
            ? null
            : Math.max(lockedUntil.getTime() - authoritativeNow.getTime(), 0);
          return {
            code: "TEMPORARILY_LOCKED",
            bookingId: params.bookingId,
            state: booking.state,
            otpEnteredAt: null,
            idempotentReplay: true,
            retryAfterMs,
          };
        }
      }

      if (bookingPrivate.otpState === "USED" || bookingPrivate.verifiedAt != null) {
        return {
          code: "ALREADY_STARTED",
          bookingId: params.bookingId,
          state: "IN_PROGRESS",
          otpEnteredAt: asDate(bookingPrivate.verifiedAt) ?? bookingOtpEnteredAt,
          idempotentReplay: true,
          retryAfterMs: null,
        };
      }

      const lockedUntil = asDate(bookingPrivate.lockedUntil);
      if (lockedUntil != null && lockedUntil.getTime() > authoritativeNow.getTime()) {
        transaction.set(bookingPrivateRef, {
          lastVerificationAttemptId: params.requestAttemptId,
          lastVerificationOutcome: "TEMPORARILY_LOCKED",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        return {
          code: "TEMPORARILY_LOCKED",
          bookingId: params.bookingId,
          state: booking.state,
          otpEnteredAt: null,
          idempotentReplay: false,
          retryAfterMs: lockedUntil.getTime() - authoritativeNow.getTime(),
        };
      }

      const eligibility = evaluateCanonicalServiceStartEligibilityV3({
        booking,
        authoritativeNow,
      });
      if (eligibility.code !== "ALLOWED") {
        const outcome =
          eligibility.code === "AFTER_SERVICE_END"
            ? "AFTER_SERVICE_END"
            : eligibility.code;
        transaction.set(bookingPrivateRef, {
          lastVerificationAttemptId: params.requestAttemptId,
          lastVerificationOutcome: outcome,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        return {
          code: outcome as ServiceStartOutcomeCode,
          bookingId: params.bookingId,
          state: booking.state,
          otpEnteredAt: null,
          idempotentReplay: false,
          retryAfterMs: null,
        };
      }

      checkpoint = "OTP_VERIFY_ELIGIBILITY_PASSED";
      console.info("OTP_VERIFY_ELIGIBILITY_PASSED", {
        bookingId: params.bookingId,
        providerUid: params.providerId,
        bookingState: booking.state,
      });
      if (!safeOtpMatches(bookingPrivate.providerOtpHash, params.bookingId, otpCandidate)) {
        const failedAttemptCount =
          typeof bookingPrivate.failedAttemptCount === "number" &&
              Number.isFinite(bookingPrivate.failedAttemptCount)
            ? bookingPrivate.failedAttemptCount
            : 0;
        const nextFailedAttemptCount = failedAttemptCount + 1;
        const locked =
          nextFailedAttemptCount >= SERVICE_START_MAX_FAILED_ATTEMPTS
            ? new Date(authoritativeNow.getTime() + SERVICE_START_LOCKOUT_MS)
            : null;
        transaction.set(bookingPrivateRef, {
          failedAttemptCount: nextFailedAttemptCount,
          lastFailedAttemptAt: Timestamp.fromDate(authoritativeNow),
          lockedUntil: locked == null ? null : Timestamp.fromDate(locked),
          lastVerificationAttemptId: params.requestAttemptId,
          lastVerificationOutcome:
            nextFailedAttemptCount >= SERVICE_START_MAX_FAILED_ATTEMPTS
              ? "TEMPORARILY_LOCKED"
              : "INVALID_OTP",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        return {
          code:
            nextFailedAttemptCount >= SERVICE_START_MAX_FAILED_ATTEMPTS
              ? "ATTEMPTS_EXCEEDED"
              : "INVALID_OTP",
          bookingId: params.bookingId,
          state: booking.state,
          otpEnteredAt: null,
          idempotentReplay: false,
          retryAfterMs:
            locked == null ? null : locked.getTime() - authoritativeNow.getTime(),
        };
      }

      checkpoint = "OTP_VERIFY_MATCHED";
      console.info("OTP_VERIFY_MATCHED", {
        bookingId: params.bookingId,
        providerUid: params.providerId,
        bookingState: booking.state,
      });
      const priorFailedAttempts =
        typeof bookingPrivate.failedAttemptCount === "number" &&
            Number.isFinite(bookingPrivate.failedAttemptCount)
          ? bookingPrivate.failedAttemptCount
          : 0;
      const successfulAttemptNumber = priorFailedAttempts + 1;
      const serviceStartRecord = buildServiceStartRecord({
        booking,
        bookingId: params.bookingId,
        authoritativeNow,
        requestAttemptId: params.requestAttemptId,
        priorFailedAttempts,
        successfulAttemptNumber,
      });
      const event = buildBookingEventPlan({
        bookingId: params.bookingId,
        event: "otp_entered",
        actor: "provider",
        at: authoritativeNow,
        meta: {
          verificationAttemptId: params.requestAttemptId,
        },
      });
      const notification = buildServiceStartNotification({
        booking,
        bookingId: params.bookingId,
      });

      checkpoint = "OTP_VERIFY_TRANSACTION_WRITES_PREPARED";
      console.info("OTP_VERIFY_TRANSACTION_WRITES_PREPARED", {
        bookingId: params.bookingId,
        providerUid: params.providerId,
        eventId: event.eventId,
      });
      transaction.set(bookingRef, {
        state: "IN_PROGRESS",
        stateQueryValue: "IN_PROGRESS",
        "lifecycle.otpEnteredAt": Timestamp.fromDate(authoritativeNow),
        updatedAt: FieldValue.serverTimestamp(),
        "audit.lastUpdatedBy": "provider",
        "privacy.otpVisibleToParent": false,
      }, {merge: true});
      transaction.set(bookingPrivateRef, {
        parentOtpCode: "",
        providerOtpHash: "",
        otpState: "USED",
        verifiedAt: Timestamp.fromDate(authoritativeNow),
        successfulAttemptNumber,
        lastVerificationAttemptId: params.requestAttemptId,
        lastVerificationOutcome: "VERIFIED_STARTED",
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.set(serviceStartRef, {
        ...serviceStartRecord,
        createdAt: Timestamp.fromDate(serviceStartRecord.createdAt),
        updatedAt: Timestamp.fromDate(serviceStartRecord.updatedAt),
        verifiedAt: Timestamp.fromDate(serviceStartRecord.verifiedAt),
        otpGeneratedAt:
          serviceStartRecord.otpGeneratedAt == null
            ? null
            : Timestamp.fromDate(serviceStartRecord.otpGeneratedAt),
        otpVerifiedAt: Timestamp.fromDate(serviceStartRecord.otpVerifiedAt),
        serviceAnchorAt: Timestamp.fromDate(serviceStartRecord.serviceAnchorAt),
      }, {merge: false});
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
        {merge: false},
      );
      transaction.set(notificationRef, buildStoredBookingNotificationDocument({
        notification: {
          ...notification,
          data: {
            ...notification.data,
            serviceId: notification.data.serviceId ?? booking.serviceId,
          },
        },
        actorId: params.providerId,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        source: "canonical_v3",
      }), {merge: true});
      checkpoint = "OTP_VERIFY_TRANSACTION_COMMITTED";
      console.info("OTP_VERIFY_TRANSACTION_COMMITTED", {
        bookingId: params.bookingId,
        providerUid: params.providerId,
      });
      console.info("OTP_VERIFY_COMPLETED", {
        bookingId: params.bookingId,
        providerUid: params.providerId,
        bookingState: "IN_PROGRESS",
      });
      return {
        code: "VERIFIED_STARTED",
        bookingId: params.bookingId,
        state: "IN_PROGRESS",
        otpEnteredAt: authoritativeNow,
        idempotentReplay: false,
        retryAfterMs: null,
      };
    });
  } catch (error) {
    console.error("bookingV3.verifyBookingStartOtpV3.unexpected", {
      checkpoint,
      bookingId: params.bookingId,
      providerUid: params.providerId,
      bookingState: currentState,
      bookingPath: bookingRef.path,
      bookingPrivatePath: bookingPrivateRef.path,
      serviceStartPath: serviceStartRef.path,
      notificationPath: notificationRef.path,
      errorName: error instanceof Error ? error.name : typeof error,
      errorMessage: error instanceof Error ? error.message : String(error),
      errorStack: error instanceof Error ? error.stack : null,
    });
    throw error;
  }
}

export async function finalizeCanonicalNoShowV3(params: {
  firestore: Firestore;
  bookingId: string;
  authoritativeNow?: Date;
}): Promise<NoShowEvaluationResult> {
  const authoritativeNow = params.authoritativeNow ?? new Date();
  const bookingRef = params.firestore.collection("bookings").doc(params.bookingId);
  const bookingPrivateRef = params.firestore.collection("bookingPrivate").doc(params.bookingId);
  const serviceStartRef = params.firestore.collection(BOOKING_SERVICE_STARTS_COLLECTION).doc(params.bookingId);
  const noShowRef = params.firestore.collection(BOOKING_NO_SHOWS_COLLECTION).doc(params.bookingId);
  const bookingFinancialRef = params.firestore.collection("bookingFinancials").doc(params.bookingId);
  const providerEarningRef = params.firestore.collection("providerEarnings").doc(params.bookingId);
  const payoutReadinessRef = params.firestore.collection("payoutReadiness").doc(params.bookingId);
  const notificationRefs = {
    parent: params.firestore.collection("notifications").doc(`booking_no_show:${params.bookingId}:parent`),
    provider: params.firestore.collection("notifications").doc(`booking_no_show:${params.bookingId}:provider`),
  };

  return params.firestore.runTransaction(async (transaction) => {
    const [bookingSnapshot, serviceStartSnapshot, noShowSnapshot] =
      await Promise.all([
        transaction.get(bookingRef),
        transaction.get(serviceStartRef),
        transaction.get(noShowRef),
      ]);
    if (!bookingSnapshot.exists) {
      return {
        code: "INELIGIBLE_STATE",
        serviceAnchorAt: null,
        expectedServiceEndAt: null,
      };
    }
    const booking = bookingSnapshot.data() as CanonicalBookingDocumentV3;
    if (booking.state === "NO_SHOW" || noShowSnapshot.exists) {
      return {
        code: "ALREADY_FINALIZED",
        serviceAnchorAt: asDate(serviceAnchorAt(booking)),
        expectedServiceEndAt: resolveAuthoritativeServiceEndV3({booking}).expectedServiceEndAt,
      };
    }

    const evaluation = evaluateCanonicalNoShowEligibilityV3({
      booking,
      authoritativeNow,
      hasSuccessfulServiceStartArtifact: serviceStartSnapshot.exists,
    });
    if (evaluation.code !== "ELIGIBLE_NO_SHOW") {
      return evaluation;
    }

    const expectedServiceEndAt = evaluation.expectedServiceEndAt;
    if (expectedServiceEndAt == null) {
      return {
        code: "INVALID_BOOKING_DATA",
        serviceAnchorAt: evaluation.serviceAnchorAt,
        expectedServiceEndAt,
      };
    }

    const noShowRecord = buildNoShowRecord({
      booking,
      bookingId: params.bookingId,
      authoritativeNow,
      expectedServiceEndAt,
    });
    const allocation = calculateCanonicalNoShowAllocationV3({booking});
    const event = buildBookingEventPlan({
      bookingId: params.bookingId,
      event: "no_show",
      actor: "system",
      at: noShowRecord.noShowAt,
      meta: {
        reasonCode: noShowRecord.noShowReasonCode,
      },
    });
    const notifications = buildNoShowNotifications({
      booking,
      bookingId: params.bookingId,
    });

    transaction.set(bookingRef, {
      state: "NO_SHOW",
      stateQueryValue: "NO_SHOW",
      lifecycle: {
        noShowAt: Timestamp.fromDate(noShowRecord.noShowAt),
        disputeDeadlineAt: Timestamp.fromDate(noShowRecord.disputeDeadlineAt),
      },
      updatedAt: FieldValue.serverTimestamp(),
      audit: {
        lastUpdatedBy: "system",
      },
      privacy: {
        otpVisibleToParent: false,
      },
      dispute: {
        status: "none",
        raisedAt: null,
        raisedBy: null,
        reasonCode: "",
        description: "",
        evidenceRefs: [],
        resolvedAt: null,
        resolvedBy: null,
        resolution: "",
        customerRefundPaise: 0,
        providerReleasePaise: 0,
      },
      payout: {
        status: "held",
        eligibleAt: Timestamp.fromDate(noShowRecord.disputeDeadlineAt),
        releasedAt: null,
        providerPayoutPaise: allocation.providerCompensationPaise,
        payoutReference: "",
        failureCode: "",
      },
    }, {merge: true});
    transaction.set(bookingPrivateRef, {
      parentOtpCode: "",
      providerOtpHash: "",
      otpState: "REVOKED",
      lastVerificationOutcome: "AFTER_SERVICE_END",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(noShowRef, {
      ...noShowRecord,
      serviceAnchorAt: Timestamp.fromDate(noShowRecord.serviceAnchorAt),
      expectedServiceEndAt: Timestamp.fromDate(noShowRecord.expectedServiceEndAt),
      noShowAt: Timestamp.fromDate(noShowRecord.noShowAt),
      disputeDeadlineAt: Timestamp.fromDate(noShowRecord.disputeDeadlineAt),
      createdAt: Timestamp.fromDate(noShowRecord.createdAt),
      updatedAt: Timestamp.fromDate(noShowRecord.updatedAt),
    }, {merge: false});
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
      {merge: false},
    );
    for (const notification of notifications) {
      const ref = notification.recipientUserId === booking.parentId
        ? notificationRefs.parent
        : notificationRefs.provider;
      transaction.set(ref, buildStoredBookingNotificationDocument({
        notification: {
          ...notification,
          data: {
            ...notification.data,
            serviceId: notification.data.serviceId ?? booking.serviceId,
          },
        },
        actorId: "system",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        source: "canonical_v3",
      }), {merge: true});
    }
    transaction.set(bookingFinancialRef, {
      bookingId: params.bookingId,
      status: "no_show",
      paymentStatus: "captured",
      disputeStatus: "none",
      payoutStatus: "held",
      customerRefundBasisPoints: allocation.customerRefundBasisPoints,
      providerShareBasisPoints: allocation.providerShareBasisPoints,
      pettxoShareBasisPoints: allocation.pettxoShareBasisPoints,
      customerRefundPaise: allocation.customerRefundPaise,
      providerCompensationPaise: allocation.providerCompensationPaise,
      pettxoRetainedPaise: allocation.pettxoRetainedPaise,
      pettxoCouponCostPaise: allocation.pettxoCouponCostPaise,
      noShowReasonCode: allocation.reasonCode,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(providerEarningRef, {
      bookingId: params.bookingId,
      providerId: booking.providerId,
      status: "hold",
      eligibleForPayout: false,
      compensationAmountPaise: allocation.providerCompensationPaise,
      reversedAmountPaise: 0,
      noShowReasonCode: allocation.reasonCode,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(payoutReadinessRef, {
      bookingId: params.bookingId,
      providerId: booking.providerId,
      customerId: booking.parentId,
      status: "held",
      eligibilityReason: "Payout is held during the no-show dispute window.",
      eligibleAt: Timestamp.fromDate(noShowRecord.disputeDeadlineAt),
      providerPayoutPaise: allocation.providerCompensationPaise,
      payoutId: "",
      payoutHoldReason: "NO_SHOW_DISPUTE_WINDOW",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {
      code: "FINALIZED_NO_SHOW",
      serviceAnchorAt: evaluation.serviceAnchorAt,
      expectedServiceEndAt,
    };
  });
}

export async function reconcileCanonicalServiceStartArtifactsV3(params: {
  firestore: Firestore;
  bookingId: string;
  authoritativeNow?: Date;
}): Promise<"NOOP" | "REPAIRED" | "NO_SHOW_FINALIZED"> {
  const authoritativeNow = params.authoritativeNow ?? new Date();
  const bookingRef = params.firestore.collection("bookings").doc(params.bookingId);
  const bookingPrivateRef = params.firestore.collection("bookingPrivate").doc(params.bookingId);
  const serviceStartRef = params.firestore.collection(BOOKING_SERVICE_STARTS_COLLECTION).doc(params.bookingId);

  const [bookingSnapshot, bookingPrivateSnapshot, serviceStartSnapshot] =
    await Promise.all([
      bookingRef.get(),
      bookingPrivateRef.get(),
      serviceStartRef.get(),
    ]);
  if (!bookingSnapshot.exists) return "NOOP";
  const booking = bookingSnapshot.data() as CanonicalBookingDocumentV3;

  const bookingOtpEnteredAt = asDate(booking.lifecycle.otpEnteredAt);
  if (booking.state === "IN_PROGRESS" && bookingOtpEnteredAt != null) {
    const updates: Record<string, unknown> = {};
    const bookingPrivate = bookingPrivateSnapshot.exists
      ? (bookingPrivateSnapshot.data() as CanonicalBookingPrivateDocumentV3)
      : null;
    const normalizedServiceAnchorAt = asDate(serviceAnchorAt(booking));
    const normalizedOtpGeneratedAt = asDate(booking.lifecycle.otpGeneratedAt);
    if (bookingPrivate &&
        (bookingPrivate.otpState !== "USED" ||
          bookingPrivate.parentOtpCode.trim().length > 0 ||
          bookingPrivate.providerOtpHash.trim().length > 0)) {
      updates.bookingPrivate = {
        parentOtpCode: "",
        providerOtpHash: "",
        otpState: "USED",
        verifiedAt: Timestamp.fromDate(bookingOtpEnteredAt),
        updatedAt: FieldValue.serverTimestamp(),
      };
    }
    if (!serviceStartSnapshot.exists && normalizedServiceAnchorAt != null) {
      updates.serviceStart = {
        bookingId: params.bookingId,
        providerId: booking.providerId,
        parentId: booking.parentId,
        serviceAnchorAt: Timestamp.fromDate(normalizedServiceAnchorAt),
        verifiedAt: Timestamp.fromDate(bookingOtpEnteredAt),
        otpGeneratedAt:
          normalizedOtpGeneratedAt == null
            ? null
            : Timestamp.fromDate(normalizedOtpGeneratedAt),
        otpVerifiedAt: Timestamp.fromDate(bookingOtpEnteredAt),
        verificationAttemptId: "",
        successfulAttemptNumber: 1,
        priorFailedAttempts: 0,
        stateBefore: "CONFIRMED",
        stateAfter: "IN_PROGRESS",
        policyVersion: SERVICE_START_POLICY_VERSION,
        createdAt: Timestamp.fromDate(bookingOtpEnteredAt),
        updatedAt: Timestamp.fromDate(bookingOtpEnteredAt),
      };
    }
    if (Object.keys(updates).length === 0) return "NOOP";
    await params.firestore.runTransaction(async (transaction) => {
      if (updates.bookingPrivate) {
        transaction.set(bookingPrivateRef, updates.bookingPrivate, {merge: true});
      }
      if (updates.serviceStart) {
        transaction.set(serviceStartRef, updates.serviceStart, {merge: true});
      }
    });
    return "REPAIRED";
  }

  const finalized = await finalizeCanonicalNoShowV3({
    firestore: params.firestore,
    bookingId: params.bookingId,
    authoritativeNow,
  });
  return finalized.code === "FINALIZED_NO_SHOW" ? "NO_SHOW_FINALIZED" : "NOOP";
}
