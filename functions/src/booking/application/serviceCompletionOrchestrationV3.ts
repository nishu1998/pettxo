import {Timestamp, type Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/https";

import type {CanonicalBookingDocumentV3} from "../schema/bookingDocumentV3";
import {buildBookingEventPlan} from "./bookingEventsWriter";
import type {BookingNotificationPlan} from "./bookingNotificationsV3";
import {buildStoredBookingNotificationDocument} from "../../notifications/notificationChannels";
import {
  buildBookingFinalizedNotifications,
  buildBookingPayoutReadyNotifications,
  buildBookingReviewReceivedNotification,
  buildServiceCompletedNotification,
} from "./bookingNotificationsV3";
import {resolveCanonicalCompletionAvailableAtV3} from "./serviceStartOrchestrationV3";

export const BOOKING_SERVICE_COMPLETIONS_COLLECTION = "bookingServiceCompletions";
export const BOOKING_COMPLETION_DISPUTES_COLLECTION = "disputes";
export const SERVICE_COMPLETION_POLICY_VERSION = "v3.2_slice8";
export const CANONICAL_REVIEW_WINDOW_MS = 24 * 60 * 60 * 1000;

export type CompletionOutcomeCode =
  | "COMPLETED_PENDING_REVIEW"
  | "ALREADY_COMPLETED"
  | "BOOKING_SERVICE_NOT_ENDED"
  | "INVALID_STATE"
  | "PAYMENT_NOT_CONFIRMED"
  | "UNAUTHORIZED"
  | "NOT_FOUND"
  | "INVALID_BOOKING_DATA";

export type ReviewSubmissionCode =
  | "REVIEW_SUBMITTED"
  | "ALREADY_REVIEWED"
  | "INVALID_STATE"
  | "UNAUTHORIZED"
  | "NOT_FOUND"
  | "INVALID_BOOKING_DATA";

export type DisputeSubmissionCode =
  | "DISPUTE_CREATED"
  | "ALREADY_DISPUTED"
  | "INVALID_STATE"
  | "WINDOW_EXPIRED"
  | "UNAUTHORIZED"
  | "NOT_FOUND"
  | "INVALID_BOOKING_DATA";

export type CompletionFinalizationCode =
  | "FINALIZED"
  | "NOT_DUE"
  | "DISPUTE_OPEN"
  | "ALREADY_FINAL"
  | "INVALID_STATE"
  | "NOT_FOUND"
  | "INVALID_BOOKING_DATA";

export type CompletionResult = {
  code: CompletionOutcomeCode;
  bookingId: string;
  state: CanonicalBookingDocumentV3["state"] | "";
  idempotentReplay: boolean;
  completedAt: Date | null;
  reviewWindowEndsAt: Date | null;
};

export type ReviewSubmissionResult = {
  code: ReviewSubmissionCode;
  bookingId: string;
  state: CanonicalBookingDocumentV3["state"] | "";
  reviewId: string;
  idempotentReplay: boolean;
  submittedAt: Date | null;
};

export type DisputeSubmissionResult = {
  code: DisputeSubmissionCode;
  bookingId: string;
  state: CanonicalBookingDocumentV3["state"] | "";
  disputeId: string;
  idempotentReplay: boolean;
  createdAt: Date | null;
};

export type CompletionFinalizationResult = {
  code: CompletionFinalizationCode;
  bookingId: string;
  state: CanonicalBookingDocumentV3["state"] | "";
  finalizedAt: Date | null;
  payoutEligibleAt: Date | null;
};

export type CompletionFinalizationEvaluation = {
  code: CompletionFinalizationCode;
  reviewWindowEndsAt: Date | null;
};

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asDate(value: unknown): Date | null {
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value;
  if (value instanceof Timestamp) return value.toDate();
  return null;
}

function isPaymentConfirmedV3(booking: CanonicalBookingDocumentV3): boolean {
  const status = booking.payment.status.trim().toLowerCase();
  return booking.lifecycle.paidAt != null &&
    (status === "paid" || status === "confirmed");
}

function hasOpenDisputeV3(booking: CanonicalBookingDocumentV3): boolean {
  return booking.dispute.status.trim().toLowerCase() === "open";
}

function hasReviewAlreadyV3(bookingData: Record<string, unknown>): {reviewId: string; submitted: boolean} {
  const review = typeof bookingData.review === "object" && bookingData.review != null ?
    bookingData.review as Record<string, unknown> :
    {};
  const reviewId = asString(bookingData.reviewId) || asString(review.reviewId);
  const reviewStatus = (asString(bookingData.reviewStatus) || asString(review.status)).toLowerCase();
  return {
    reviewId,
    submitted: reviewId.length > 0 || reviewStatus === "submitted",
  };
}

function isReviewEligibleCompletedStateV3(state: CanonicalBookingDocumentV3["state"]): boolean {
  return state === "COMPLETED_PENDING_REVIEW" || state === "COMPLETED_FINAL";
}

function resolveCompletedAtV3(bookingData: Record<string, unknown>): Date | null {
  const lifecycle =
    typeof bookingData.lifecycle === "object" && bookingData.lifecycle != null ?
      bookingData.lifecycle as Record<string, unknown> :
      {};
  return (
    asDate(lifecycle.completedAt) ??
    asDate(bookingData["lifecycle.completedAt"]) ??
    asDate(bookingData.completedAt)
  );
}

function resolveDisputeDeadlineV3(bookingData: Record<string, unknown>): {
  deadline: Date | null;
  source:
    | "lifecycle.disputeDeadlineAt"
    | "legacy.lifecycle.disputeDeadlineAt"
    | "lifecycle.reviewWindowEndsAt"
    | "legacy.lifecycle.reviewWindowEndsAt"
    | "missing";
} {
  const lifecycle =
    typeof bookingData.lifecycle === "object" && bookingData.lifecycle != null ?
      bookingData.lifecycle as Record<string, unknown> :
      {};
  const nestedDisputeDeadlineAt = asDate(lifecycle.disputeDeadlineAt);
  if (nestedDisputeDeadlineAt != null) {
    return {
      deadline: nestedDisputeDeadlineAt,
      source: "lifecycle.disputeDeadlineAt",
    };
  }
  const legacyDisputeDeadlineAt = asDate(bookingData["lifecycle.disputeDeadlineAt"]);
  if (legacyDisputeDeadlineAt != null) {
    return {
      deadline: legacyDisputeDeadlineAt,
      source: "legacy.lifecycle.disputeDeadlineAt",
    };
  }
  const nestedReviewWindowEndsAt = asDate(lifecycle.reviewWindowEndsAt);
  if (nestedReviewWindowEndsAt != null) {
    return {
      deadline: nestedReviewWindowEndsAt,
      source: "lifecycle.reviewWindowEndsAt",
    };
  }
  const legacyReviewWindowEndsAt = asDate(bookingData["lifecycle.reviewWindowEndsAt"]);
  if (legacyReviewWindowEndsAt != null) {
    return {
      deadline: legacyReviewWindowEndsAt,
      source: "legacy.lifecycle.reviewWindowEndsAt",
    };
  }
  return {deadline: null, source: "missing"};
}

function toReviewerName(booking: CanonicalBookingDocumentV3): string {
  const firstName = booking.participants.parent.displayFirstName.trim();
  const lastInitial = booking.participants.parent.lastInitial.trim();
  return [firstName, lastInitial].filter((value) => value.length > 0).join(" ");
}

function nextRatingAverage(currentAverage: number, currentCount: number, nextRating: number): number {
  if (currentCount <= 0) return nextRating;
  return ((currentAverage * currentCount) + nextRating) / (currentCount + 1);
}

function computeTrustScore(ratingAverage: number, completedBookingCount: number): number {
  const ratingSignal = Math.min(Math.max(ratingAverage / 5, 0), 1);
  const volumeSignal = Math.min(Math.max(completedBookingCount / 25, 0), 1);
  return Number(((ratingSignal * 0.7) + (volumeSignal * 0.3)).toFixed(4));
}

function persistNotificationsInTransaction(params: {
  firestore: Firestore;
  transaction: FirebaseFirestore.Transaction;
  notifications: ReadonlyArray<BookingNotificationPlan>;
  actorId: string;
  createdAt: Date;
}): void {
  for (const notification of params.notifications) {
    const notificationRef = params.firestore
      .collection("notifications")
      .doc(notification.idempotencyKey);
    params.transaction.set(notificationRef, buildStoredBookingNotificationDocument({
      notification,
      actorId: params.actorId,
      createdAt: Timestamp.fromDate(params.createdAt),
      updatedAt: Timestamp.fromDate(params.createdAt),
      source: "canonical_v3",
    }), {merge: true});
  }
}

function buildCompletionPayoutDocuments(params: {
  booking: CanonicalBookingDocumentV3;
  bookingId: string;
  completedAt: Date;
  reviewWindowEndsAt: Date;
}) {
  const financials = params.booking.financials;
  if (financials == null) {
    throw new HttpsError("failed-precondition", "Missing canonical financial snapshot.");
  }
  return {
    bookingFinancial: {
      bookingId: params.bookingId,
      userId: params.booking.parentId,
      providerId: params.booking.providerId,
      serviceId: params.booking.serviceId,
      totalAmountPaise: financials.customerPaidPaise,
      currency: financials.currency,
      status: "HELD",
      customerRefundPaise: 0,
      pettxoAmountPaise: financials.platformCommissionPaise,
      providerAmountPaise: financials.providerPayoutPaise,
      gatewayFeePaise: financials.gatewayFeeSunkPaise,
      couponCostPaise: financials.pettxoCouponFundingPaise,
      disputeStatus: hasOpenDisputeV3(params.booking) ? "OPEN" : "NONE",
      completedAt: Timestamp.fromDate(params.completedAt),
      payoutEligibleAt: Timestamp.fromDate(params.reviewWindowEndsAt),
      updatedAt: Timestamp.fromDate(params.completedAt),
      source: "canonical_v3",
      policyVersion: SERVICE_COMPLETION_POLICY_VERSION,
    },
    providerEarning: {
      bookingId: params.bookingId,
      providerId: params.booking.providerId,
      userId: params.booking.parentId,
      serviceId: params.booking.serviceId,
      amountPaise: financials.providerPayoutPaise,
      pettxoCommissionAmountPaise: financials.platformCommissionPaise,
      totalAmountPaise: financials.customerPaidPaise,
      source: "canonical_v3_completion",
      status: "HELD",
      eligibleAt: Timestamp.fromDate(params.reviewWindowEndsAt),
      paidAt: null,
      createdAt: Timestamp.fromDate(params.completedAt),
      updatedAt: Timestamp.fromDate(params.completedAt),
      policyVersion: SERVICE_COMPLETION_POLICY_VERSION,
    },
    payoutReadiness: {
      bookingId: params.bookingId,
      providerId: params.booking.providerId,
      customerId: params.booking.parentId,
      serviceId: params.booking.serviceId,
      payoutStatus: "HELD",
      status: "HELD",
      providerAmount: financials.providerPayoutPaise,
      providerAmountPaise: financials.providerPayoutPaise,
      pettxoAmount: financials.platformCommissionPaise,
      pettxoAmountPaise: financials.platformCommissionPaise,
      gatewayFee: financials.gatewayFeeSunkPaise,
      gatewayFeePaise: financials.gatewayFeeSunkPaise,
      couponCost: financials.pettxoCouponFundingPaise,
      couponCostPaise: financials.pettxoCouponFundingPaise,
      eligibleAt: Timestamp.fromDate(params.reviewWindowEndsAt),
      eligibilityReason: "Held until the 24-hour review and dispute window closes.",
      updatedAt: Timestamp.fromDate(params.completedAt),
      source: "canonical_v3",
      policyVersion: SERVICE_COMPLETION_POLICY_VERSION,
    },
  };
}

export async function completeBookingServiceV3(params: {
  firestore: Firestore;
  bookingId: string;
  providerUid: string;
  authoritativeNow?: Date;
}): Promise<CompletionResult> {
  const authoritativeNow = params.authoritativeNow ?? new Date();
  const bookingRef = params.firestore.collection("bookings").doc(params.bookingId);
  const completionRef = params.firestore
    .collection(BOOKING_SERVICE_COMPLETIONS_COLLECTION)
    .doc(params.bookingId);
  const bookingFinancialRef = params.firestore.collection("bookingFinancials").doc(params.bookingId);
  const providerEarningRef = params.firestore.collection("providerEarnings").doc(params.bookingId);
  const payoutReadinessRef = params.firestore.collection("payoutReadiness").doc(params.bookingId);

  console.info("SERVICE_COMPLETE_REQUEST_RECEIVED", {
    bookingId: params.bookingId,
    providerUid: params.providerUid,
  });

  return params.firestore.runTransaction(async (transaction) => {
    const [bookingSnapshot, completionSnapshot] = await Promise.all([
      transaction.get(bookingRef),
      transaction.get(completionRef),
    ]);
    if (!bookingSnapshot.exists) {
      return {
        code: "NOT_FOUND",
        bookingId: params.bookingId,
        state: "",
        idempotentReplay: false,
        completedAt: null,
        reviewWindowEndsAt: null,
      };
    }
    const bookingData = (bookingSnapshot.data() ?? {}) as Record<string, unknown>;
    const booking = bookingData as CanonicalBookingDocumentV3;
    console.info("SERVICE_COMPLETE_BOOKING_LOADED", {
      bookingId: params.bookingId,
      providerUid: params.providerUid,
      currentState: booking.state,
      paymentStatus: booking.payment.status,
      hasPaidAt: booking.lifecycle.paidAt != null,
      completionRecordExists: completionSnapshot.exists,
    });
    if (booking.providerId !== params.providerUid) {
      return {
        code: "UNAUTHORIZED",
        bookingId: params.bookingId,
        state: booking.state,
        idempotentReplay: false,
        completedAt: booking.lifecycle.completedAt,
        reviewWindowEndsAt: booking.lifecycle.reviewWindowEndsAt,
      };
    }
    console.info("SERVICE_COMPLETE_AUTHORIZED", {
      bookingId: params.bookingId,
      providerUid: params.providerUid,
      currentState: booking.state,
    });
    if (booking.state === "COMPLETED_PENDING_REVIEW" && completionSnapshot.exists) {
      return {
        code: "ALREADY_COMPLETED",
        bookingId: params.bookingId,
        state: booking.state,
        idempotentReplay: true,
        completedAt: booking.lifecycle.completedAt,
        reviewWindowEndsAt: booking.lifecycle.reviewWindowEndsAt,
      };
    }
    if (booking.state !== "IN_PROGRESS") {
      return {
        code: "INVALID_STATE",
        bookingId: params.bookingId,
        state: booking.state,
        idempotentReplay: false,
        completedAt: booking.lifecycle.completedAt,
        reviewWindowEndsAt: booking.lifecycle.reviewWindowEndsAt,
      };
    }
    if (booking.lifecycle.otpEnteredAt == null) {
      return {
        code: "INVALID_STATE",
        bookingId: params.bookingId,
        state: booking.state,
        idempotentReplay: false,
        completedAt: null,
        reviewWindowEndsAt: null,
      };
    }
    if (!isPaymentConfirmedV3(booking)) {
      return {
        code: "PAYMENT_NOT_CONFIRMED",
        bookingId: params.bookingId,
        state: booking.state,
        idempotentReplay: false,
        completedAt: null,
        reviewWindowEndsAt: null,
      };
    }
    if (booking.financials == null) {
      return {
        code: "INVALID_BOOKING_DATA",
        bookingId: params.bookingId,
        state: booking.state,
        idempotentReplay: false,
        completedAt: null,
        reviewWindowEndsAt: null,
      };
    }
    const completionAvailableAt = resolveCanonicalCompletionAvailableAtV3({
      booking,
    });
    if (completionAvailableAt.code !== "RESOLVED" ||
        completionAvailableAt.expectedServiceEndAt == null) {
      return {
        code: "INVALID_BOOKING_DATA",
        bookingId: params.bookingId,
        state: booking.state,
        idempotentReplay: false,
        completedAt: null,
        reviewWindowEndsAt: null,
      };
    }
    if (authoritativeNow.getTime() < completionAvailableAt.expectedServiceEndAt.getTime()) {
      return {
        code: "BOOKING_SERVICE_NOT_ENDED",
        bookingId: params.bookingId,
        state: booking.state,
        idempotentReplay: false,
        completedAt: null,
        reviewWindowEndsAt: null,
      };
    }

    const completedAt = new Date(authoritativeNow.getTime());
    const reviewWindowEndsAt = new Date(completedAt.getTime() + CANONICAL_REVIEW_WINDOW_MS);
    console.info("SERVICE_COMPLETE_STATE_VALIDATED", {
      bookingId: params.bookingId,
      providerUid: params.providerUid,
      currentState: booking.state,
      completedAt: completedAt.toISOString(),
      reviewWindowEndsAt: reviewWindowEndsAt.toISOString(),
    });
    const payoutDocs = buildCompletionPayoutDocuments({
      booking,
      bookingId: params.bookingId,
      completedAt,
      reviewWindowEndsAt,
    });
    const event = buildBookingEventPlan({
      bookingId: params.bookingId,
      event: "service_completed",
      actor: "provider",
      at: completedAt,
      meta: {policyVersion: SERVICE_COMPLETION_POLICY_VERSION},
    });
    const notifications = buildServiceCompletedNotification({
      bookingId: params.bookingId,
      parentId: booking.parentId,
      bookingType: booking.bookingType,
      state: "COMPLETED_PENDING_REVIEW",
    });
    console.info("SERVICE_COMPLETE_WRITES_PREPARED", {
      bookingId: params.bookingId,
      providerUid: params.providerUid,
      targetState: "COMPLETED_PENDING_REVIEW",
      notificationCount: notifications.length,
    });

    const nextLifecycle = {
      ...booking.lifecycle,
      serviceEndedAt: Timestamp.fromDate(completedAt),
      completedAt: Timestamp.fromDate(completedAt),
      reviewWindowEndsAt: Timestamp.fromDate(reviewWindowEndsAt),
      disputeDeadlineAt: Timestamp.fromDate(reviewWindowEndsAt),
    };
    const nextPayout = {
      ...booking.payout,
      status: "HELD",
      eligibleAt: Timestamp.fromDate(reviewWindowEndsAt),
      providerPayoutPaise: booking.financials.providerPayoutPaise,
    };
    const nextPrivacy = {
      ...booking.privacy,
      otpVisibleToParent: false,
    };
    const existingCompletion =
      typeof bookingData.completion === "object" && bookingData.completion != null ?
        bookingData.completion as Record<string, unknown> :
        {};
    const nextCompletion = {
      ...existingCompletion,
      reasonCode: "provider_marked_complete",
      policyVersion: SERVICE_COMPLETION_POLICY_VERSION,
    };
    const nextDispute = {
      ...booking.dispute,
      status: "none",
    };
    const nextAudit = {
      ...booking.audit,
      lastUpdatedBy: "provider",
    };

    transaction.set(bookingRef, {
      state: "COMPLETED_PENDING_REVIEW",
      stateQueryValue: "COMPLETED_PENDING_REVIEW",
      completedAt: Timestamp.fromDate(completedAt),
      updatedAt: Timestamp.fromDate(completedAt),
      lifecycle: nextLifecycle,
      payout: nextPayout,
      privacy: nextPrivacy,
      completion: nextCompletion,
      dispute: nextDispute,
      audit: nextAudit,
    }, {merge: true});
    transaction.set(completionRef, {
      bookingId: params.bookingId,
      providerId: params.providerUid,
      parentId: booking.parentId,
      completedAt: Timestamp.fromDate(completedAt),
      reviewWindowEndsAt: Timestamp.fromDate(reviewWindowEndsAt),
      completionReason: "provider_marked_complete",
      policyVersion: SERVICE_COMPLETION_POLICY_VERSION,
      createdAt: Timestamp.fromDate(completedAt),
      updatedAt: Timestamp.fromDate(completedAt),
    }, {merge: true});
    transaction.set(
      bookingRef.collection("events").doc(event.eventId),
      {
        ...event.record,
        at: Timestamp.fromDate(event.record.at),
      },
      {merge: true},
    );
    transaction.set(bookingFinancialRef, payoutDocs.bookingFinancial, {merge: true});
    transaction.set(providerEarningRef, payoutDocs.providerEarning, {merge: true});
    transaction.set(payoutReadinessRef, payoutDocs.payoutReadiness, {merge: true});
    persistNotificationsInTransaction({
      firestore: params.firestore,
      transaction,
      notifications,
      actorId: params.providerUid,
      createdAt: completedAt,
    });
    console.info("SERVICE_COMPLETE_TRANSACTION_COMMITTED", {
      bookingId: params.bookingId,
      providerUid: params.providerUid,
      targetState: "COMPLETED_PENDING_REVIEW",
    });

    const result: CompletionResult = {
      code: "COMPLETED_PENDING_REVIEW",
      bookingId: params.bookingId,
      state: "COMPLETED_PENDING_REVIEW",
      idempotentReplay: false,
      completedAt,
      reviewWindowEndsAt,
    };
    console.info("SERVICE_COMPLETE_COMPLETED", {
      bookingId: params.bookingId,
      providerUid: params.providerUid,
      resultCode: result.code,
      targetState: result.state,
    });
    return result;
  });
}

export async function submitBookingReviewV3(params: {
  firestore: Firestore;
  bookingId: string;
  parentUid: string;
  rating: number;
  comment: string;
  tags: string[];
  authoritativeNow?: Date;
}): Promise<ReviewSubmissionResult> {
  const authoritativeNow = params.authoritativeNow ?? new Date();
  const bookingRef = params.firestore.collection("bookings").doc(params.bookingId);
  return params.firestore.runTransaction(async (transaction) => {
    const bookingSnapshot = await transaction.get(bookingRef);
    if (!bookingSnapshot.exists) {
      return {
        code: "NOT_FOUND",
        bookingId: params.bookingId,
        state: "",
        reviewId: "",
        idempotentReplay: false,
        submittedAt: null,
      };
    }
    const bookingData = bookingSnapshot.data() ?? {};
    const booking = bookingData as CanonicalBookingDocumentV3;
    const reviewStatusBefore =
      asString(bookingData.reviewStatus) ||
      asString((bookingData.review as Record<string, unknown> | undefined)?.status);
    const existingReview = hasReviewAlreadyV3(bookingData);
    if (booking.parentId !== params.parentUid) {
      return {
        code: "UNAUTHORIZED",
        bookingId: params.bookingId,
        state: booking.state,
        reviewId: "",
        idempotentReplay: false,
        submittedAt: null,
      };
    }
    if (!isReviewEligibleCompletedStateV3(booking.state)) {
      console.info("bookingV3.submitBookingReviewV3.validation", {
        bookingId: params.bookingId,
        reviewExists: existingReview.submitted,
        reviewStatusBefore,
        duplicateRejectionReason: "invalid_state",
        aggregateUpdatePerformed: false,
      });
      return {
        code: "INVALID_STATE",
        bookingId: params.bookingId,
        state: booking.state,
        reviewId: "",
        idempotentReplay: false,
        submittedAt: null,
      };
    }
    if (resolveCompletedAtV3(bookingData) == null) {
      console.info("bookingV3.submitBookingReviewV3.validation", {
        bookingId: params.bookingId,
        reviewExists: existingReview.submitted,
        reviewStatusBefore,
        duplicateRejectionReason: "missing_completed_at",
        aggregateUpdatePerformed: false,
      });
      return {
        code: "INVALID_BOOKING_DATA",
        bookingId: params.bookingId,
        state: booking.state,
        reviewId: "",
        idempotentReplay: false,
        submittedAt: null,
      };
    }
    if (existingReview.submitted) {
      console.info("bookingV3.submitBookingReviewV3.validation", {
        bookingId: params.bookingId,
        reviewExists: true,
        reviewStatusBefore,
        duplicateRejectionReason: "booking_review_already_marked_submitted",
        aggregateUpdatePerformed: false,
      });
      return {
        code: "ALREADY_REVIEWED",
        bookingId: params.bookingId,
        state: booking.state,
        reviewId: existingReview.reviewId || params.bookingId,
        idempotentReplay: true,
        submittedAt: asDate((bookingData.review as Record<string, unknown> | undefined)?.submittedAt) ?? authoritativeNow,
      };
    }

    const reviewRef = params.firestore
      .collection("services")
      .doc(booking.serviceId)
      .collection("reviews")
      .doc(params.bookingId);
    const serviceRef = params.firestore.collection("services").doc(booking.serviceId);
    const providerRef = params.firestore.collection("users").doc(booking.providerId);
    const [reviewSnapshot, serviceSnapshot, providerSnapshot] = await Promise.all([
      transaction.get(reviewRef),
      transaction.get(serviceRef),
      transaction.get(providerRef),
    ]);
    if (reviewSnapshot.exists) {
      console.info("bookingV3.submitBookingReviewV3.validation", {
        bookingId: params.bookingId,
        reviewExists: true,
        reviewStatusBefore,
        duplicateRejectionReason: "review_document_exists",
        aggregateUpdatePerformed: false,
      });
      return {
        code: "ALREADY_REVIEWED",
        bookingId: params.bookingId,
        state: booking.state,
        reviewId: reviewRef.id,
        idempotentReplay: true,
        submittedAt: authoritativeNow,
      };
    }
    if (!serviceSnapshot.exists || !providerSnapshot.exists) {
      return {
        code: "INVALID_BOOKING_DATA",
        bookingId: params.bookingId,
        state: booking.state,
        reviewId: "",
        idempotentReplay: false,
        submittedAt: null,
      };
    }

    const serviceData = serviceSnapshot.data() ?? {};
    const serviceStats = typeof serviceData.stats === "object" && serviceData.stats != null ?
      serviceData.stats as Record<string, unknown> :
      {};
    const currentServiceRatingCount = Number(serviceStats.ratingCount ?? serviceData.ratingCount ?? 0) || 0;
    const currentServiceRatingAverage = Number(serviceStats.ratingAverage ?? serviceData.ratingAverage ?? 0) || 0;
    const currentServiceCompletedCount = Number(serviceStats.completedBookingsCount ?? serviceData.completedBookingCount ?? 0) || 0;
    const currentServiceReviewedCount = Number(serviceStats.reviewedBookingCount ?? serviceData.reviewedBookingCount ?? 0) || 0;
    const nextServiceRatingCount = currentServiceRatingCount + 1;
    const nextServiceRatingAverage = nextRatingAverage(
      currentServiceRatingAverage,
      currentServiceRatingCount,
      params.rating,
    );
    const nextServiceTrustScore = computeTrustScore(
      nextServiceRatingAverage,
      currentServiceCompletedCount,
    );

    const providerData = providerSnapshot.data() ?? {};
    const currentProviderRatingCount = Number(providerData.ratingCount ?? 0) || 0;
    const currentProviderRatingAverage = Number(providerData.ratingAverage ?? 0) || 0;
    const currentProviderCompletedCount =
      Number(providerData.completedBookingCount ?? providerData.completedBookingsCount ?? 0) || 0;
    const currentProviderReviewedCount = Number(providerData.reviewedBookingCount ?? 0) || 0;
    const nextProviderRatingCount = currentProviderRatingCount + 1;
    const nextProviderRatingAverage = nextRatingAverage(
      currentProviderRatingAverage,
      currentProviderRatingCount,
      params.rating,
    );
    const nextProviderTrustScore = computeTrustScore(
      nextProviderRatingAverage,
      currentProviderCompletedCount,
    );

    const reviewEvent = buildBookingEventPlan({
      bookingId: params.bookingId,
      event: "review_submitted",
      actor: "parent",
      at: authoritativeNow,
      meta: {rating: params.rating},
    });
    const notifications = buildBookingReviewReceivedNotification({
      bookingId: params.bookingId,
      providerId: booking.providerId,
      bookingType: booking.bookingType,
      state: booking.state,
    });
    const bookingAudit = typeof booking.audit === "object" && booking.audit != null ?
      booking.audit as Record<string, unknown> :
      {};

    transaction.set(reviewRef, {
      bookingId: params.bookingId,
      serviceId: booking.serviceId,
      providerUserId: booking.providerId,
      reviewerUserId: params.parentUid,
      reviewerId: params.parentUid,
      reviewerName: toReviewerName(booking),
      reviewerPhotoUrl: booking.participants.parent.photoUrl,
      rating: params.rating,
      comment: params.comment.trim(),
      tags: params.tags,
      isEdited: false,
      moderationStatus: "approved",
      createdAt: Timestamp.fromDate(authoritativeNow),
      updatedAt: Timestamp.fromDate(authoritativeNow),
      source: "canonical_v3",
    }, {merge: true});
    transaction.set(bookingRef, {
      reviewStatus: "submitted",
      reviewId: reviewRef.id,
      review: {
        status: "submitted",
        reviewId: reviewRef.id,
        submittedAt: Timestamp.fromDate(authoritativeNow),
      },
      updatedAt: Timestamp.fromDate(authoritativeNow),
      audit: {
        ...bookingAudit,
        lastUpdatedBy: "parent",
      },
    }, {merge: true});
    transaction.set(serviceRef, {
      ratingAverage: nextServiceRatingAverage,
      ratingCount: nextServiceRatingCount,
      reviewedBookingCount: currentServiceReviewedCount + 1,
      trustScore: nextServiceTrustScore,
      stats: {
        ...serviceStats,
        ratingAverage: nextServiceRatingAverage,
        ratingCount: nextServiceRatingCount,
        reviewedBookingCount: currentServiceReviewedCount + 1,
        trustScore: nextServiceTrustScore,
      },
      updatedAt: Timestamp.fromDate(authoritativeNow),
    }, {merge: true});
    transaction.set(providerRef, {
      ratingAverage: nextProviderRatingAverage,
      ratingCount: nextProviderRatingCount,
      reviewedBookingCount: currentProviderReviewedCount + 1,
      trustScore: nextProviderTrustScore,
      updatedAt: Timestamp.fromDate(authoritativeNow),
    }, {merge: true});
    transaction.set(
      bookingRef.collection("events").doc(reviewEvent.eventId),
      {
        ...reviewEvent.record,
        at: Timestamp.fromDate(reviewEvent.record.at),
      },
      {merge: true},
    );
    persistNotificationsInTransaction({
      firestore: params.firestore,
      transaction,
      notifications,
      actorId: params.parentUid,
      createdAt: authoritativeNow,
    });
    console.info("bookingV3.submitBookingReviewV3.validation", {
      bookingId: params.bookingId,
      reviewExists: false,
      reviewStatusBefore,
      duplicateRejectionReason: "",
      aggregateUpdatePerformed: true,
    });

    return {
      code: "REVIEW_SUBMITTED",
      bookingId: params.bookingId,
      state: booking.state,
      reviewId: reviewRef.id,
      idempotentReplay: false,
      submittedAt: authoritativeNow,
    };
  });
}

export async function createBookingDisputeV3(params: {
  firestore: Firestore;
  bookingId: string;
  parentUid: string;
  reason: string;
  description: string;
  attachments: string[];
  authoritativeNow?: Date;
}): Promise<DisputeSubmissionResult> {
  const authoritativeNow = params.authoritativeNow ?? new Date();
  const bookingRef = params.firestore.collection("bookings").doc(params.bookingId);
  const disputeRef = params.firestore
    .collection(BOOKING_COMPLETION_DISPUTES_COLLECTION)
    .doc(params.bookingId);
  const bookingFinancialRef = params.firestore.collection("bookingFinancials").doc(params.bookingId);
  const providerEarningRef = params.firestore.collection("providerEarnings").doc(params.bookingId);
  const payoutReadinessRef = params.firestore.collection("payoutReadiness").doc(params.bookingId);

  return params.firestore.runTransaction(async (transaction) => {
    const [bookingSnapshot, disputeSnapshot] = await Promise.all([
      transaction.get(bookingRef),
      transaction.get(disputeRef),
    ]);
    if (!bookingSnapshot.exists) {
      return {
        code: "NOT_FOUND",
        bookingId: params.bookingId,
        state: "",
        disputeId: "",
        idempotentReplay: false,
        createdAt: null,
      };
    }
    const booking = bookingSnapshot.data() as CanonicalBookingDocumentV3;
    if (booking.parentId !== params.parentUid) {
      return {
        code: "UNAUTHORIZED",
        bookingId: params.bookingId,
        state: booking.state,
        disputeId: "",
        idempotentReplay: false,
        createdAt: null,
      };
    }
    if (booking.state !== "COMPLETED_PENDING_REVIEW") {
      return {
        code: "INVALID_STATE",
        bookingId: params.bookingId,
        state: booking.state,
        disputeId: "",
        idempotentReplay: false,
        createdAt: null,
      };
    }
    const bookingData = bookingSnapshot.data() ?? {};
    const disputeDeadlineResolution = resolveDisputeDeadlineV3(
      bookingData as Record<string, unknown>,
    );
    const disputeDeadlineAt = disputeDeadlineResolution.deadline;
    console.info("bookingV3.createBookingDisputeV3.validation", {
      bookingId: params.bookingId,
      callerOwnsBooking: booking.parentId === params.parentUid,
      bookingState: booking.state,
      deadlineSource: disputeDeadlineResolution.source,
      deadlineActive:
        disputeDeadlineAt != null &&
        authoritativeNow.getTime() <= disputeDeadlineAt.getTime(),
      existingDisputeStatus: booking.dispute.status,
    });
    if (disputeDeadlineAt == null) {
      return {
        code: "INVALID_BOOKING_DATA",
        bookingId: params.bookingId,
        state: booking.state,
        disputeId: "",
        idempotentReplay: false,
        createdAt: null,
      };
    }
    if (authoritativeNow.getTime() > disputeDeadlineAt.getTime()) {
      return {
        code: "WINDOW_EXPIRED",
        bookingId: params.bookingId,
        state: booking.state,
        disputeId: "",
        idempotentReplay: false,
        createdAt: null,
      };
    }
    if (disputeSnapshot.exists || hasOpenDisputeV3(booking)) {
      return {
        code: "ALREADY_DISPUTED",
        bookingId: params.bookingId,
        state: booking.state,
        disputeId: params.bookingId,
        idempotentReplay: true,
        createdAt: authoritativeNow,
      };
    }

    const event = buildBookingEventPlan({
      bookingId: params.bookingId,
      event: "dispute_created",
      actor: "parent",
      at: authoritativeNow,
      meta: {reason: params.reason},
    });
    transaction.set(disputeRef, {
      bookingId: params.bookingId,
      providerId: booking.providerId,
      parentId: booking.parentId,
      reason: params.reason,
      description: params.description,
      attachments: params.attachments,
      createdAt: Timestamp.fromDate(authoritativeNow),
      status: "OPEN",
      source: "canonical_v3",
      updatedAt: Timestamp.fromDate(authoritativeNow),
    }, {merge: true});
    const bookingDispute = typeof booking.dispute === "object" && booking.dispute != null ?
      booking.dispute as Record<string, unknown> :
      {};
    const bookingPayout = typeof booking.payout === "object" && booking.payout != null ?
      booking.payout as Record<string, unknown> :
      {};
    const bookingAudit = typeof booking.audit === "object" && booking.audit != null ?
      booking.audit as Record<string, unknown> :
      {};
    transaction.set(bookingRef, {
      updatedAt: Timestamp.fromDate(authoritativeNow),
      dispute: {
        ...bookingDispute,
        status: "OPEN",
        raisedAt: Timestamp.fromDate(authoritativeNow),
        raisedBy: "parent",
        reasonCode: params.reason,
        description: params.description,
        evidenceRefs: params.attachments,
      },
      payout: {
        ...bookingPayout,
        status: "HELD",
      },
      audit: {
        ...bookingAudit,
        lastUpdatedBy: "parent",
      },
    }, {merge: true});
    transaction.set(bookingFinancialRef, {
      status: "HELD",
      disputeStatus: "OPEN",
      updatedAt: Timestamp.fromDate(authoritativeNow),
    }, {merge: true});
    transaction.set(providerEarningRef, {
      status: "HELD",
      updatedAt: Timestamp.fromDate(authoritativeNow),
    }, {merge: true});
    transaction.set(payoutReadinessRef, {
      status: "HELD",
      payoutStatus: "HELD",
      eligibilityReason: "Held because the customer opened a dispute during the review window.",
      updatedAt: Timestamp.fromDate(authoritativeNow),
    }, {merge: true});
    transaction.set(
      bookingRef.collection("events").doc(event.eventId),
      {
        ...event.record,
        at: Timestamp.fromDate(event.record.at),
      },
      {merge: true},
    );

    return {
      code: "DISPUTE_CREATED",
      bookingId: params.bookingId,
      state: booking.state,
      disputeId: disputeRef.id,
      idempotentReplay: false,
      createdAt: authoritativeNow,
    };
  });
}

export function evaluateCompletionFinalizationV3(params: {
  booking: CanonicalBookingDocumentV3;
  authoritativeNow: Date;
}): CompletionFinalizationEvaluation {
  if (params.booking.state === "COMPLETED_FINAL") {
    return {code: "ALREADY_FINAL", reviewWindowEndsAt: params.booking.lifecycle.reviewWindowEndsAt};
  }
  if (params.booking.state !== "COMPLETED_PENDING_REVIEW") {
    return {code: "INVALID_STATE", reviewWindowEndsAt: params.booking.lifecycle.reviewWindowEndsAt};
  }
  if (hasOpenDisputeV3(params.booking)) {
    return {code: "DISPUTE_OPEN", reviewWindowEndsAt: params.booking.lifecycle.reviewWindowEndsAt};
  }
  const reviewWindowEndsAt = params.booking.lifecycle.reviewWindowEndsAt;
  if (reviewWindowEndsAt == null) {
    return {code: "INVALID_BOOKING_DATA", reviewWindowEndsAt: null};
  }
  if (params.authoritativeNow.getTime() < reviewWindowEndsAt.getTime()) {
    return {code: "NOT_DUE", reviewWindowEndsAt};
  }
  return {code: "FINALIZED", reviewWindowEndsAt};
}

export async function finalizeCompletedBookingV3(params: {
  firestore: Firestore;
  bookingId: string;
  authoritativeNow?: Date;
}): Promise<CompletionFinalizationResult> {
  const authoritativeNow = params.authoritativeNow ?? new Date();
  const bookingRef = params.firestore.collection("bookings").doc(params.bookingId);
  const bookingFinancialRef = params.firestore.collection("bookingFinancials").doc(params.bookingId);
  const providerEarningRef = params.firestore.collection("providerEarnings").doc(params.bookingId);
  const payoutReadinessRef = params.firestore.collection("payoutReadiness").doc(params.bookingId);

  return params.firestore.runTransaction(async (transaction) => {
    const bookingSnapshot = await transaction.get(bookingRef);
    if (!bookingSnapshot.exists) {
      return {
        code: "NOT_FOUND",
        bookingId: params.bookingId,
        state: "",
        finalizedAt: null,
        payoutEligibleAt: null,
      };
    }
    const booking = bookingSnapshot.data() as CanonicalBookingDocumentV3;
    const evaluation = evaluateCompletionFinalizationV3({
      booking,
      authoritativeNow,
    });
    if (evaluation.code !== "FINALIZED") {
      return {
        code: evaluation.code,
        bookingId: params.bookingId,
        state: booking.state,
        finalizedAt: booking.lifecycle.finalizedAt,
        payoutEligibleAt: booking.payout.eligibleAt,
      };
    }
    if (booking.financials == null) {
      return {
        code: "INVALID_BOOKING_DATA",
        bookingId: params.bookingId,
        state: booking.state,
        finalizedAt: null,
        payoutEligibleAt: null,
      };
    }
    const finalizedAt = new Date(authoritativeNow.getTime());
    const finalEvent = buildBookingEventPlan({
      bookingId: params.bookingId,
      event: "booking_finalized",
      actor: "system",
      at: finalizedAt,
      meta: {policyVersion: SERVICE_COMPLETION_POLICY_VERSION},
    });
    const payoutEvent = buildBookingEventPlan({
      bookingId: params.bookingId,
      event: "payout_ready",
      actor: "system",
      at: finalizedAt,
      meta: {policyVersion: SERVICE_COMPLETION_POLICY_VERSION},
    });
    const notifications = [
      ...buildBookingFinalizedNotifications({
        bookingId: params.bookingId,
        providerId: booking.providerId,
        bookingType: booking.bookingType,
        state: "COMPLETED_FINAL",
      }),
      ...buildBookingPayoutReadyNotifications({
        bookingId: params.bookingId,
        providerId: booking.providerId,
        bookingType: booking.bookingType,
        state: "COMPLETED_FINAL",
      }),
    ];
    transaction.set(bookingRef, {
      state: "COMPLETED_FINAL",
      stateQueryValue: "COMPLETED_FINAL",
      updatedAt: Timestamp.fromDate(finalizedAt),
      "lifecycle.finalizedAt": Timestamp.fromDate(finalizedAt),
      "payout.status": "READY",
      "payout.eligibleAt": Timestamp.fromDate(finalizedAt),
      "payout.providerPayoutPaise": booking.financials.providerPayoutPaise,
      "audit.lastUpdatedBy": "system",
    }, {merge: true});
    transaction.set(bookingFinancialRef, {
      status: "READY",
      payoutEligibleAt: Timestamp.fromDate(finalizedAt),
      disputeStatus: "NONE",
      updatedAt: Timestamp.fromDate(finalizedAt),
      policyVersion: SERVICE_COMPLETION_POLICY_VERSION,
    }, {merge: true});
    transaction.set(providerEarningRef, {
      status: "READY",
      eligibleAt: Timestamp.fromDate(finalizedAt),
      updatedAt: Timestamp.fromDate(finalizedAt),
      policyVersion: SERVICE_COMPLETION_POLICY_VERSION,
    }, {merge: true});
    transaction.set(payoutReadinessRef, {
      status: "READY",
      payoutStatus: "READY",
      eligibleAt: Timestamp.fromDate(finalizedAt),
      providerAmount: booking.financials.providerPayoutPaise,
      providerAmountPaise: booking.financials.providerPayoutPaise,
      pettxoAmount: booking.financials.platformCommissionPaise,
      pettxoAmountPaise: booking.financials.platformCommissionPaise,
      gatewayFee: booking.financials.gatewayFeeSunkPaise,
      gatewayFeePaise: booking.financials.gatewayFeeSunkPaise,
      couponCost: booking.financials.pettxoCouponFundingPaise,
      couponCostPaise: booking.financials.pettxoCouponFundingPaise,
      policyVersion: SERVICE_COMPLETION_POLICY_VERSION,
      updatedAt: Timestamp.fromDate(finalizedAt),
      eligibilityReason: "Ready because the review and dispute window closed without an open dispute.",
    }, {merge: true});
    transaction.set(
      bookingRef.collection("events").doc(finalEvent.eventId),
      {
        ...finalEvent.record,
        at: Timestamp.fromDate(finalEvent.record.at),
      },
      {merge: true},
    );
    transaction.set(
      bookingRef.collection("events").doc(payoutEvent.eventId),
      {
        ...payoutEvent.record,
        at: Timestamp.fromDate(payoutEvent.record.at),
      },
      {merge: true},
    );
    persistNotificationsInTransaction({
      firestore: params.firestore,
      transaction,
      notifications,
      actorId: "system",
      createdAt: finalizedAt,
    });

    return {
      code: "FINALIZED",
      bookingId: params.bookingId,
      state: "COMPLETED_FINAL",
      finalizedAt,
      payoutEligibleAt: finalizedAt,
    };
  });
}
