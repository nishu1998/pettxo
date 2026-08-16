import {FieldValue, Timestamp, type Firestore} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

import {
  buildPaymentCapturedProcessingNotification,
  buildPaymentRefundRequiredNotification,
  type BookingNotificationPlan,
} from "./bookingNotificationsV3";
import {buildStoredBookingNotificationDocument} from "../../notifications/notificationChannels";
import {BOOKING_CANCELLATION_COLLECTION} from "./cancellationOrchestrationV3";
import {
  canonicalPaymentOrderMappingRef,
  canonicalQrPaymentMappingRef,
  finalizeCapturedCanonicalPaymentV3,
} from "./paymentOrchestrationV3";
import {fetchRazorpayPaymentV3} from "./razorpayGateway";
import type {CanonicalPaymentAttemptDocumentV3} from "../schema/paymentAttemptDocumentV3";
import type {CanonicalBookingDocumentV3} from "../schema/bookingDocumentV3";

export type CanonicalWebhookOutcome =
  | "CONFIRMED"
  | "ALREADY_CONFIRMED"
  | "RECONCILIATION_REQUIRED"
  | "REFUND_REQUIRED"
  | "PRIVATE_REPAIR_REQUIRED"
  | "REFUND_UPDATED"
  | "IGNORED_UNMAPPED"
  | "INVALID_CANONICAL_MAPPING"
  | "NON_CAPTURE_EVENT";

export type CanonicalWebhookResult = {
  outcome: CanonicalWebhookOutcome;
  bookingId: string;
  paymentAttemptId: string;
  retryable: boolean;
  failureCode: string;
  notifications: BookingNotificationPlan[];
};

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

function buildCancellationRefundNotification(params: {
  bookingId: string;
  parentId: string;
  providerId: string;
  bookingType: string;
  state: string;
  eventName: "refund.processed" | "refund.failed";
}): BookingNotificationPlan[] {
  const parentType =
    params.eventName === "refund.processed" ?
      "booking_refund_processed" :
      "booking_refund_failed";
  const providerType =
    params.eventName === "refund.processed" ?
      "booking_cancellation_acknowledged" :
      "booking_refund_failed";
  return [
    {
      idempotencyKey: `${parentType}:${params.bookingId}:${params.parentId}`,
      recipientUserId: params.parentId,
      type: parentType,
      channels: ["push", "in_app"],
      title: params.eventName === "refund.processed" ? "Refund processed" : "Refund retry needed",
      body:
        params.eventName === "refund.processed" ?
          "Your cancellation refund has been processed." :
          "Your cancellation refund is taking longer than expected. Pettxo will keep retrying safely.",
      data: {
        bookingId: params.bookingId,
        bookingType: params.bookingType,
        state: params.state,
      },
    },
    {
      idempotencyKey: `${providerType}:${params.bookingId}:${params.providerId}`,
      recipientUserId: params.providerId,
      type: providerType,
      channels: ["in_app"],
      title:
        params.eventName === "refund.processed" ?
          "Refund completed" :
          "Refund pending retry",
      body:
        params.eventName === "refund.processed" ?
          "The cancellation refund has completed for this booking." :
          "The cancellation refund has not completed yet. Payout remains blocked.",
      data: {
        bookingId: params.bookingId,
        bookingType: params.bookingType,
        state: params.state,
      },
    },
  ];
}

async function persistNotifications(params: {
  firestore: Firestore;
  notifications: ReadonlyArray<BookingNotificationPlan>;
  actorId: string;
}): Promise<void> {
  if (params.notifications.length === 0) return;
  const batch = params.firestore.batch();
  for (const notification of params.notifications) {
    const notificationRef = params.firestore
      .collection("notifications")
      .doc(notification.idempotencyKey);
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

async function loadCanonicalMapping(params: {
  firestore: Firestore;
  razorpayOrderId: string;
}): Promise<{bookingId: string; paymentAttemptId: string} | null> {
  const snapshot = await canonicalPaymentOrderMappingRef(
    params.firestore,
    params.razorpayOrderId,
  ).get();
  if (!snapshot.exists) return null;
  const data = snapshot.data() ?? {};
  const bookingId = asString(data.bookingId);
  const paymentAttemptId = asString(data.paymentAttemptId);
  if (!bookingId || !paymentAttemptId) return null;
  return {bookingId, paymentAttemptId};
}

async function loadCanonicalAttemptByPaymentId(params: {
  firestore: Firestore;
  razorpayPaymentId: string;
}): Promise<{bookingId: string; paymentAttemptId: string} | null> {
  try {
    const query = await params.firestore.collectionGroup("paymentAttempts")
      .where("razorpayPaymentId", "==", params.razorpayPaymentId)
      .limit(1)
      .get();
    if (query.empty) return null;
    const attempt = query.docs[0].data() as CanonicalPaymentAttemptDocumentV3;
    if (!attempt.bookingId || !attempt.paymentAttemptId) return null;
    return {
      bookingId: attempt.bookingId,
      paymentAttemptId: attempt.paymentAttemptId,
    };
  } catch (error) {
    logger.warn("captured-payment-lookup-skipped", {
      field: "razorpayPaymentId",
      paymentId: params.razorpayPaymentId,
      reason: error instanceof Error ? error.message : String(error),
    });
    return null;
  }
}

async function loadCanonicalAttemptByOrderId(params: {
  firestore: Firestore;
  razorpayOrderId: string;
}): Promise<{bookingId: string; paymentAttemptId: string} | null> {
  try {
    const query = await params.firestore.collectionGroup("paymentAttempts")
      .where("razorpayOrderId", "==", params.razorpayOrderId)
      .limit(1)
      .get();
    if (query.empty) return null;
    const attempt = query.docs[0].data() as CanonicalPaymentAttemptDocumentV3;
    if (!attempt.bookingId || !attempt.paymentAttemptId) return null;
    return {
      bookingId: attempt.bookingId,
      paymentAttemptId: attempt.paymentAttemptId,
    };
  } catch (error) {
    logger.warn("captured-order-lookup-skipped", {
      field: "razorpayOrderId",
      orderId: params.razorpayOrderId,
      reason: error instanceof Error ? error.message : String(error),
    });
    return null;
  }
}

async function loadCanonicalQrMapping(params: {
  firestore: Firestore;
  razorpayQrCodeId: string;
}): Promise<{bookingId: string; paymentAttemptId: string} | null> {
  const snapshot = await canonicalQrPaymentMappingRef(
    params.firestore,
    params.razorpayQrCodeId,
  ).get();
  if (!snapshot.exists) return null;
  const data = snapshot.data() ?? {};
  const bookingId = asString(data.bookingId);
  const paymentAttemptId = asString(data.paymentAttemptId);
  if (!bookingId || !paymentAttemptId) return null;
  return {bookingId, paymentAttemptId};
}

async function loadBookingAndAttempt(params: {
  firestore: Firestore;
  bookingId: string;
  paymentAttemptId: string;
}): Promise<{
  booking: CanonicalBookingDocumentV3 | null;
  attempt: CanonicalPaymentAttemptDocumentV3 | null;
}> {
  const bookingRef = params.firestore.collection("bookings").doc(params.bookingId);
  const attemptRef = bookingRef.collection("paymentAttempts").doc(params.paymentAttemptId);
  const [bookingSnapshot, attemptSnapshot] = await Promise.all([
    bookingRef.get(),
    attemptRef.get(),
  ]);
  return {
    booking: bookingSnapshot.exists ?
      bookingSnapshot.data() as CanonicalBookingDocumentV3 :
      null,
    attempt: attemptSnapshot.exists ?
      attemptSnapshot.data() as CanonicalPaymentAttemptDocumentV3 :
      null,
  };
}

async function findAlreadyConfirmedReplay(params: {
  firestore: Firestore;
  razorpayPaymentId: string;
}): Promise<{bookingId: string; paymentAttemptId: string} | null> {
  const existingAttemptByPaymentId = await loadCanonicalAttemptByPaymentId({
    firestore: params.firestore,
    razorpayPaymentId: params.razorpayPaymentId,
  });
  if (!existingAttemptByPaymentId) return null;
  const loaded = await loadBookingAndAttempt({
    firestore: params.firestore,
    bookingId: existingAttemptByPaymentId.bookingId,
    paymentAttemptId: existingAttemptByPaymentId.paymentAttemptId,
  });
  if (
    loaded.booking &&
    asString(loaded.booking.payment?.razorpayPaymentId) === params.razorpayPaymentId
  ) {
    return existingAttemptByPaymentId;
  }
  return null;
}

function buildAlreadyConfirmedResult(mapping: {
  bookingId: string;
  paymentAttemptId: string;
}): CanonicalWebhookResult {
  return {
    outcome: "ALREADY_CONFIRMED",
    bookingId: mapping.bookingId,
    paymentAttemptId: mapping.paymentAttemptId,
    retryable: false,
    failureCode: "",
    notifications: [],
  };
}

async function persistUnmappedCaptureReconciliation(params: {
  firestore: Firestore;
  eventId: string;
  paymentId: string;
  orderId: string;
  amountPaise: number;
  currency: string;
  now: Date;
}): Promise<void> {
  await params.firestore.collection("paymentWebhookEvents").doc(params.eventId).set({
    razorpayPaymentId: params.paymentId,
    razorpayOrderId: params.orderId,
    amountPaise: params.amountPaise,
    currency: params.currency,
    status: "RECONCILIATION_REQUIRED",
    reconciliationStatus: "RECONCILIATION_REQUIRED",
    reconciliationReason: "UNMAPPED_CAPTURE",
    reconciliationRequiredAt: Timestamp.fromDate(params.now),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}

export async function routeCanonicalWebhookEventV3(params: {
  firestore: Firestore;
  eventId: string;
  eventName: string;
  paymentEntity: Record<string, unknown>;
  refundEntity: Record<string, unknown>;
  qrCodeEntity?: Record<string, unknown>;
  keyId: string;
  keySecret: string;
  authoritativeNow?: Date;
  deps?: {
    fetchRazorpayPayment?: typeof fetchRazorpayPaymentV3;
    finalizeCapturedPayment?: typeof finalizeCapturedCanonicalPaymentV3;
    persistNotifications?: typeof persistNotifications;
  };
}): Promise<CanonicalWebhookResult> {
  const authoritativeNow = params.authoritativeNow ?? new Date();
  const fetchRazorpayPayment = params.deps?.fetchRazorpayPayment ?? fetchRazorpayPaymentV3;
  const finalizeCapturedPayment =
    params.deps?.finalizeCapturedPayment ?? finalizeCapturedCanonicalPaymentV3;
  const persistNotificationsFn =
    params.deps?.persistNotifications ?? persistNotifications;
  const orderId = asString(params.paymentEntity.order_id);
  const paymentId = asString(params.paymentEntity.id) ||
    asString(params.refundEntity.payment_id);
  const refundId = asString(params.refundEntity.id);
  const qrCodeId = asString(params.qrCodeEntity?.id);

  if (params.eventName === "payment.captured") {
    if (!paymentId) {
      return {
        outcome: "INVALID_CANONICAL_MAPPING",
        bookingId: "",
        paymentAttemptId: "",
        retryable: false,
        failureCode: "MISSING_PAYMENT_ID",
        notifications: [],
      };
    }
    let resolvedOrderId = orderId;
    let mapping = resolvedOrderId ?
      await loadCanonicalMapping({
        firestore: params.firestore,
        razorpayOrderId: resolvedOrderId,
      }) :
      null;
    let mappingRecoverySource = "";
    let paymentRecord = null;

    if (!mapping && paymentId) {
      logger.info("captured-payment-mapping-recovery-start", {
        eventId: params.eventId,
        paymentId,
        orderId: resolvedOrderId,
      });

      const replay = await findAlreadyConfirmedReplay({
        firestore: params.firestore,
        razorpayPaymentId: paymentId,
      });
      if (replay) {
        logger.info("captured-payment-replay", {
          eventId: params.eventId,
          paymentId,
          bookingId: replay.bookingId,
          paymentAttemptId: replay.paymentAttemptId,
        });
        return buildAlreadyConfirmedResult(replay);
      }

      if (resolvedOrderId) {
        mapping = await loadCanonicalAttemptByOrderId({
          firestore: params.firestore,
          razorpayOrderId: resolvedOrderId,
        });
        if (mapping) mappingRecoverySource = "payment_attempt";
      }

      if (!mapping) {
        try {
          paymentRecord = await fetchRazorpayPayment({
            keyId: params.keyId,
            keySecret: params.keySecret,
            paymentId,
          });
        } catch (_) {
          logger.warn("captured-payment-mapping-recovery-failed", {
            eventId: params.eventId,
            paymentId,
            orderId: resolvedOrderId,
            reason: "PAYMENT_FETCH_FAILED",
          });
          await persistUnmappedCaptureReconciliation({
            firestore: params.firestore,
            eventId: params.eventId,
            paymentId,
            orderId: resolvedOrderId,
            amountPaise: asInt(params.paymentEntity.amount, 0),
            currency: asString(params.paymentEntity.currency) || "INR",
            now: authoritativeNow,
          });
          return {
            outcome: "RECONCILIATION_REQUIRED",
            bookingId: "",
            paymentAttemptId: "",
            retryable: true,
            failureCode: "PAYMENT_FETCH_FAILED",
            notifications: [],
          };
        }

        resolvedOrderId = resolvedOrderId || paymentRecord.orderId;
        if (resolvedOrderId) {
          mapping = await loadCanonicalMapping({
            firestore: params.firestore,
            razorpayOrderId: resolvedOrderId,
          });
          if (mapping) mappingRecoverySource = "payment_fetch";
        }
        if (!mapping && paymentRecord.orderId) {
          mapping = await loadCanonicalAttemptByOrderId({
            firestore: params.firestore,
            razorpayOrderId: paymentRecord.orderId,
          });
          if (mapping) mappingRecoverySource = "payment_attempt";
        }
        if (!mapping) {
          const notes = asRecord(paymentRecord.notes);
          const notesBookingId = asString(notes.bookingId);
          const notesPaymentAttemptId = asString(notes.paymentAttemptId);
          if (notesBookingId && notesPaymentAttemptId) {
            const loadedFromNotes = await loadBookingAndAttempt({
              firestore: params.firestore,
              bookingId: notesBookingId,
              paymentAttemptId: notesPaymentAttemptId,
            });
            if (
              loadedFromNotes.booking &&
              loadedFromNotes.attempt &&
              asString(loadedFromNotes.attempt.bookingId) === notesBookingId &&
              asString(loadedFromNotes.attempt.paymentAttemptId) === notesPaymentAttemptId &&
              (
                !resolvedOrderId ||
                !asString(loadedFromNotes.attempt.razorpayOrderId) ||
                asString(loadedFromNotes.attempt.razorpayOrderId) === resolvedOrderId
              )
            ) {
              mapping = {
                bookingId: notesBookingId,
                paymentAttemptId: notesPaymentAttemptId,
              };
              mappingRecoverySource = "payment_notes";
            }
          }
        }
      }
    }

    if (!mapping) {
      logger.warn("captured-payment-reconciliation-required", {
        eventId: params.eventId,
        paymentId,
        orderId: resolvedOrderId,
      });
      await persistUnmappedCaptureReconciliation({
        firestore: params.firestore,
        eventId: params.eventId,
        paymentId,
        orderId: resolvedOrderId,
        amountPaise: paymentRecord?.amountPaise ?? asInt(params.paymentEntity.amount, 0),
        currency: paymentRecord?.currency ?? (asString(params.paymentEntity.currency) || "INR"),
        now: authoritativeNow,
      });
      return {
        outcome: paymentId ? "RECONCILIATION_REQUIRED" : "INVALID_CANONICAL_MAPPING",
        bookingId: "",
        paymentAttemptId: "",
        retryable: Boolean(paymentId),
        failureCode: paymentId ? "UNMAPPED_CAPTURE" : "MISSING_ORDER_ID",
        notifications: [],
      };
    }

    if (mappingRecoverySource) {
      logger.info("captured-payment-mapping-recovery-success", {
        eventId: params.eventId,
        paymentId,
        orderId: resolvedOrderId,
        bookingId: mapping.bookingId,
        paymentAttemptId: mapping.paymentAttemptId,
        source: mappingRecoverySource,
      });
    }

    if (resolvedOrderId) {
      await canonicalPaymentOrderMappingRef(params.firestore, resolvedOrderId).set({
        bookingId: mapping.bookingId,
        paymentAttemptId: mapping.paymentAttemptId,
        schemaVersion: 1,
        updatedAt: FieldValue.serverTimestamp(),
        recoveredAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    const loaded = await loadBookingAndAttempt({
      firestore: params.firestore,
      bookingId: mapping.bookingId,
      paymentAttemptId: mapping.paymentAttemptId,
    });
    if (!loaded.booking || !loaded.attempt) {
      return {
        outcome: "INVALID_CANONICAL_MAPPING",
        bookingId: mapping.bookingId,
        paymentAttemptId: mapping.paymentAttemptId,
        retryable: false,
        failureCode: "MISSING_BOOKING_OR_ATTEMPT",
        notifications: [],
      };
    }

    await params.firestore
      .collection("bookings")
      .doc(mapping.bookingId)
      .collection("paymentAttempts")
      .doc(mapping.paymentAttemptId)
      .set({
        razorpayOrderId: resolvedOrderId,
        razorpayPaymentId: paymentId,
        captureReportedAt: Timestamp.fromDate(authoritativeNow),
        verificationSource: "webhook",
        lastReconciledAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});

    if (!paymentRecord) {
      try {
        paymentRecord = await fetchRazorpayPayment({
          keyId: params.keyId,
          keySecret: params.keySecret,
          paymentId,
        });
      } catch (_) {
        await params.firestore
          .collection("bookings")
          .doc(mapping.bookingId)
          .collection("paymentAttempts")
          .doc(mapping.paymentAttemptId)
          .set({
            state: "CAPTURED_REQUIRES_RECONCILIATION",
            nextReconciliationAt: Timestamp.fromDate(authoritativeNow),
            reconciliationAttemptCount: FieldValue.increment(1),
            lastReconciliationCode: "WEBHOOK_FETCH_FAILED",
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
        return {
          outcome: "RECONCILIATION_REQUIRED",
          bookingId: mapping.bookingId,
          paymentAttemptId: mapping.paymentAttemptId,
          retryable: true,
          failureCode: "PAYMENT_FETCH_FAILED",
          notifications: buildPaymentCapturedProcessingNotification({
            bookingId: mapping.bookingId,
            parentId: loaded.booking.parentId,
            bookingType: loaded.booking.bookingType,
            state: loaded.booking.state,
          }),
        };
      }
    }

    if (paymentRecord.orderId !== resolvedOrderId ||
      paymentRecord.amountPaise !== loaded.attempt.amountPaise ||
      paymentRecord.currency !== loaded.attempt.currency) {
      return {
        outcome: "INVALID_CANONICAL_MAPPING",
        bookingId: mapping.bookingId,
        paymentAttemptId: mapping.paymentAttemptId,
        retryable: false,
        failureCode: "PAYMENT_MISMATCH",
        notifications: [],
      };
    }

    if (paymentRecord.status !== "captured") {
      await params.firestore
        .collection("bookings")
        .doc(mapping.bookingId)
        .collection("paymentAttempts")
        .doc(mapping.paymentAttemptId)
        .set({
          state: "CAPTURED_REQUIRES_RECONCILIATION",
          nextReconciliationAt: Timestamp.fromDate(authoritativeNow),
          reconciliationAttemptCount: FieldValue.increment(1),
          lastReconciliationCode: `WEBHOOK_${paymentRecord.status.toUpperCase()}`,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      return {
        outcome: "RECONCILIATION_REQUIRED",
        bookingId: mapping.bookingId,
        paymentAttemptId: mapping.paymentAttemptId,
        retryable: true,
        failureCode: "PAYMENT_NOT_CAPTURED",
        notifications: buildPaymentCapturedProcessingNotification({
          bookingId: mapping.bookingId,
          parentId: loaded.booking.parentId,
          bookingType: loaded.booking.bookingType,
          state: loaded.booking.state,
        }),
      };
    }

    const result = await finalizeCapturedPayment({
      firestore: params.firestore,
      facts: {
        bookingId: mapping.bookingId,
        paymentAttemptId: mapping.paymentAttemptId,
        razorpayOrderId: paymentRecord.orderId,
        razorpayPaymentId: paymentRecord.id,
        capturedAmountPaise: paymentRecord.amountPaise,
        currency: paymentRecord.currency,
        capturedAt:
          paymentRecord.capturedAt ?? paymentRecord.createdAt ?? authoritativeNow,
        verificationSource: "webhook",
        sourceEventId: params.eventId,
      },
      keyId: params.keyId,
      keySecret: params.keySecret,
      authoritativeNow,
    });
    if (!result.ok && result.code !== "PRIVATE_REPAIR_REQUIRED") {
      logger.warn("captured-payment-duplicate-refund-required", {
        eventId: params.eventId,
        paymentId: paymentRecord.id,
        bookingId: mapping.bookingId,
        paymentAttemptId: mapping.paymentAttemptId,
        code: result.code,
      });
    }
    await persistNotificationsFn({
      firestore: params.firestore,
      notifications: result.ok ?
        result.notifications :
        result.code === "PRIVATE_REPAIR_REQUIRED" ?
          [] :
          buildPaymentRefundRequiredNotification({
            bookingId: mapping.bookingId,
            parentId: loaded.booking.parentId,
            providerId: loaded.booking.providerId,
            bookingType: loaded.booking.bookingType,
            state: result.booking.state,
          }),
      actorId: "payment_gateway",
    });
    return {
      outcome: result.ok ?
        (result.code === "IDEMPOTENT_REPLAY" ? "ALREADY_CONFIRMED" : "CONFIRMED") :
        (result.code === "PRIVATE_REPAIR_REQUIRED" ? "PRIVATE_REPAIR_REQUIRED" : "REFUND_REQUIRED"),
      bookingId: mapping.bookingId,
      paymentAttemptId: mapping.paymentAttemptId,
      retryable: false,
      failureCode: result.ok ? "" : result.code,
      notifications: result.notifications,
    };
  }

  if (params.eventName === "qr_code.credited") {
    if (!qrCodeId) {
      return {
        outcome: "INVALID_CANONICAL_MAPPING",
        bookingId: "",
        paymentAttemptId: "",
        retryable: false,
        failureCode: "MISSING_QR_CODE_ID",
        notifications: [],
      };
    }
    const mapping = await loadCanonicalQrMapping({
      firestore: params.firestore,
      razorpayQrCodeId: qrCodeId,
    });
    if (!mapping) {
      return {
        outcome: "IGNORED_UNMAPPED",
        bookingId: "",
        paymentAttemptId: "",
        retryable: false,
        failureCode: "",
        notifications: [],
      };
    }
    const loaded = await loadBookingAndAttempt({
      firestore: params.firestore,
      bookingId: mapping.bookingId,
      paymentAttemptId: mapping.paymentAttemptId,
    });
    if (!loaded.booking || !loaded.attempt) {
      return {
        outcome: "INVALID_CANONICAL_MAPPING",
        bookingId: mapping.bookingId,
        paymentAttemptId: mapping.paymentAttemptId,
        retryable: false,
        failureCode: "MISSING_BOOKING_OR_ATTEMPT",
        notifications: [],
      };
    }
    if (loaded.attempt.paymentMethod !== "qr" ||
      loaded.attempt.razorpayQrCodeId !== qrCodeId) {
      return {
        outcome: "INVALID_CANONICAL_MAPPING",
        bookingId: mapping.bookingId,
        paymentAttemptId: mapping.paymentAttemptId,
        retryable: false,
        failureCode: "QR_MAPPING_MISMATCH",
        notifications: [],
      };
    }

    await params.firestore
      .collection("bookings")
      .doc(mapping.bookingId)
      .collection("paymentAttempts")
      .doc(mapping.paymentAttemptId)
      .set({
        razorpayPaymentId: paymentId,
        captureReportedAt: Timestamp.fromDate(authoritativeNow),
        verificationSource: "webhook",
        qrState: "PAYMENT_CAPTURED",
        lastReconciledAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    await canonicalQrPaymentMappingRef(params.firestore, qrCodeId).set({
      bookingId: mapping.bookingId,
      paymentAttemptId: mapping.paymentAttemptId,
      status: "PAYMENT_CAPTURED",
      updatedAt: FieldValue.serverTimestamp(),
      razorpayPaymentId: paymentId,
    }, {merge: true});

    if (asInt(params.paymentEntity.amount, 0) !== loaded.attempt.amountPaise) {
      return {
        outcome: "INVALID_CANONICAL_MAPPING",
        bookingId: mapping.bookingId,
        paymentAttemptId: mapping.paymentAttemptId,
        retryable: false,
        failureCode: "PAYMENT_MISMATCH",
        notifications: [],
      };
    }
    if ((asString(params.paymentEntity.currency) || "INR") !== loaded.attempt.currency) {
      return {
        outcome: "INVALID_CANONICAL_MAPPING",
        bookingId: mapping.bookingId,
        paymentAttemptId: mapping.paymentAttemptId,
        retryable: false,
        failureCode: "PAYMENT_CURRENCY_MISMATCH",
        notifications: [],
      };
    }
    if (asString(params.paymentEntity.status).toLowerCase() !== "captured") {
      return {
        outcome: "RECONCILIATION_REQUIRED",
        bookingId: mapping.bookingId,
        paymentAttemptId: mapping.paymentAttemptId,
        retryable: true,
        failureCode: "PAYMENT_NOT_CAPTURED",
        notifications: buildPaymentCapturedProcessingNotification({
          bookingId: mapping.bookingId,
          parentId: loaded.booking.parentId,
          bookingType: loaded.booking.bookingType,
          state: loaded.booking.state,
        }),
      };
    }

    const result = await finalizeCapturedPayment({
      firestore: params.firestore,
      facts: {
        bookingId: mapping.bookingId,
        paymentAttemptId: mapping.paymentAttemptId,
        razorpayOrderId: "",
        razorpayPaymentId: paymentId,
        capturedAmountPaise: asInt(params.paymentEntity.amount, 0),
        currency: asString(params.paymentEntity.currency) || "INR",
        capturedAt: authoritativeNow,
        verificationSource: "webhook",
        sourceEventId: params.eventId,
      },
      keyId: params.keyId,
      keySecret: params.keySecret,
      authoritativeNow,
    });
    await canonicalQrPaymentMappingRef(params.firestore, qrCodeId).set({
      status: result.ok ? "CONFIRMED" : "REFUND_REQUIRED",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    await persistNotificationsFn({
      firestore: params.firestore,
      notifications: result.ok ?
        result.notifications :
        result.code === "PRIVATE_REPAIR_REQUIRED" ?
          [] :
          buildPaymentRefundRequiredNotification({
            bookingId: mapping.bookingId,
            parentId: loaded.booking.parentId,
            providerId: loaded.booking.providerId,
            bookingType: loaded.booking.bookingType,
            state: result.booking.state,
          }),
      actorId: "payment_gateway",
    });
    return {
      outcome: result.ok ?
        (result.code === "IDEMPOTENT_REPLAY" ? "ALREADY_CONFIRMED" : "CONFIRMED") :
        (result.code === "PRIVATE_REPAIR_REQUIRED" ? "PRIVATE_REPAIR_REQUIRED" : "REFUND_REQUIRED"),
      bookingId: mapping.bookingId,
      paymentAttemptId: mapping.paymentAttemptId,
      retryable: false,
      failureCode: result.ok ? "" : result.code,
      notifications: result.notifications,
    };
  }

  if (params.eventName === "qr_code.closed") {
    if (!qrCodeId) {
      return {
        outcome: "NON_CAPTURE_EVENT",
        bookingId: "",
        paymentAttemptId: "",
        retryable: false,
        failureCode: "MISSING_QR_CODE_ID",
        notifications: [],
      };
    }
    const mapping = await loadCanonicalQrMapping({
      firestore: params.firestore,
      razorpayQrCodeId: qrCodeId,
    });
    if (!mapping) {
      return {
        outcome: "IGNORED_UNMAPPED",
        bookingId: "",
        paymentAttemptId: "",
        retryable: false,
        failureCode: "",
        notifications: [],
      };
    }
    await params.firestore
      .collection("bookings")
      .doc(mapping.bookingId)
      .collection("paymentAttempts")
      .doc(mapping.paymentAttemptId)
      .set({
        qrState: "CLOSED",
        qrClosedAt: Timestamp.fromDate(authoritativeNow),
        qrCloseReason: asString(params.qrCodeEntity?.close_reason) || "closed",
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    await canonicalQrPaymentMappingRef(params.firestore, qrCodeId).set({
      status: "CLOSED",
      updatedAt: FieldValue.serverTimestamp(),
      closedAt: FieldValue.serverTimestamp(),
      closeReason: asString(params.qrCodeEntity?.close_reason) || "closed",
    }, {merge: true});
    return {
      outcome: "NON_CAPTURE_EVENT",
      bookingId: mapping.bookingId,
      paymentAttemptId: mapping.paymentAttemptId,
      retryable: false,
      failureCode: "",
      notifications: [],
    };
  }

  if (
    params.eventName === "refund.created" ||
    params.eventName === "refund.processed" ||
    params.eventName === "refund.failed"
  ) {
    if (!paymentId) {
      return {
        outcome: "NON_CAPTURE_EVENT",
        bookingId: "",
        paymentAttemptId: "",
        retryable: false,
        failureCode: "MISSING_PAYMENT_ID",
        notifications: [],
      };
    }
    const mapping = await loadCanonicalAttemptByPaymentId({
      firestore: params.firestore,
      razorpayPaymentId: paymentId,
    });
    if (!mapping) {
  return {
    outcome: "IGNORED_UNMAPPED",
    bookingId: "",
    paymentAttemptId: "",
    retryable: false,
        failureCode: "",
        notifications: [],
      };
    }
    const loaded = await loadBookingAndAttempt({
      firestore: params.firestore,
      bookingId: mapping.bookingId,
      paymentAttemptId: mapping.paymentAttemptId,
    });
    if (!loaded.booking || !loaded.attempt) {
      return {
        outcome: "INVALID_CANONICAL_MAPPING",
        bookingId: mapping.bookingId,
        paymentAttemptId: mapping.paymentAttemptId,
        retryable: false,
        failureCode: "MISSING_BOOKING_OR_ATTEMPT",
        notifications: [],
      };
    }

    const refundRef = params.firestore.collection("refunds").doc(mapping.bookingId);
    const cancellationRef = params.firestore
      .collection(BOOKING_CANCELLATION_COLLECTION)
      .doc(mapping.bookingId);
    const bookingRef = params.firestore.collection("bookings").doc(mapping.bookingId);
    const attemptRef = params.firestore.collection("bookings")
      .doc(mapping.bookingId)
      .collection("paymentAttempts")
      .doc(mapping.paymentAttemptId);
    const refundAmountPaise = asInt(params.refundEntity.amount, loaded.attempt.amountPaise);
    const state = params.eventName === "refund.processed" ?
      "processed" :
      (params.eventName === "refund.created" ? "submitted" : "failed");
    await Promise.all([
      refundRef.set({
        bookingId: mapping.bookingId,
        paymentAttemptId: mapping.paymentAttemptId,
        razorpayPaymentId: paymentId,
        razorpayRefundId: refundId,
        refundAmountPaise,
        state,
        submittedAt: params.eventName === "refund.created" ?
          FieldValue.serverTimestamp() :
          null,
        confirmedAt: params.eventName === "refund.processed" ?
          FieldValue.serverTimestamp() :
          null,
        lastErrorCode: params.eventName === "refund.failed" ?
          asString(params.refundEntity.status) || "refund_failed" :
          "",
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true}),
      cancellationRef.set({
        bookingId: mapping.bookingId,
        refundAmountPaise,
        refundStatus:
          params.eventName === "refund.processed" ?
            "REFUNDED" :
            (params.eventName === "refund.created" ? "REFUND_PENDING" : "REFUND_FAILED"),
        status:
          params.eventName === "refund.processed" ? "REFUNDED" : "CANCELLED",
        refundInstructionId: `refund-${mapping.bookingId}`,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true}),
      bookingRef.set({
        payment: {
          status:
            params.eventName === "refund.processed" ?
              "refunded" :
              (params.eventName === "refund.created" ? "refund_pending" : "refund_failed"),
          razorpayRefundId: refundId || "",
        },
        financials: {
          refundAmountPaise,
        },
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true}),
      params.firestore.collection("payments").doc(mapping.bookingId).set({
        refundStatus:
          params.eventName === "refund.processed" ?
            "refunded" :
            (params.eventName === "refund.created" ? "refund_pending" : "refund_failed"),
        refundAmountPaise,
        razorpayRefundId: refundId || "",
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true}),
      params.firestore.collection("invoices").doc(mapping.bookingId).set({
        refundStatus:
          params.eventName === "refund.processed" ?
            "refunded" :
            (params.eventName === "refund.created" ? "refund_pending" : "refund_failed"),
        refundAmountPaise,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true}),
      params.firestore.collection("bookingFinancials").doc(mapping.bookingId).set({
        paymentStatus:
          params.eventName === "refund.processed" ?
            "refunded" :
            (params.eventName === "refund.created" ? "refund_pending" : "refund_failed"),
        refundAmountPaise,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true}),
      params.firestore.collection("providerEarnings").doc(mapping.bookingId).set({
        refundStatus:
          params.eventName === "refund.processed" ?
            "refunded" :
            (params.eventName === "refund.created" ? "refund_pending" : "refund_failed"),
        eligibleForPayout: false,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true}),
      params.firestore.collection("payoutReadiness").doc(mapping.bookingId).set({
        status: "cancelled",
        providerPayoutPaise: 0,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true}),
      attemptRef.set({
        state: params.eventName === "refund.processed" ? "REFUNDED" : "REFUND_PENDING",
        refundedAt: params.eventName === "refund.processed" ?
          FieldValue.serverTimestamp() :
          null,
        lastReconciledAt: FieldValue.serverTimestamp(),
        lastReconciliationCode: params.eventName.toUpperCase().replaceAll(".", "_"),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true}),
    ]);

    const notifications =
      params.eventName === "refund.processed" || params.eventName === "refund.failed" ?
        buildCancellationRefundNotification({
          bookingId: mapping.bookingId,
          parentId: loaded.booking.parentId,
          providerId: loaded.booking.providerId,
          bookingType: loaded.booking.bookingType,
          state: loaded.booking.state,
          eventName: params.eventName,
        }) :
        [];
    await persistNotificationsFn({
      firestore: params.firestore,
      notifications,
      actorId: "payment_gateway",
    });
    return {
      outcome: "REFUND_UPDATED",
      bookingId: mapping.bookingId,
      paymentAttemptId: mapping.paymentAttemptId,
      retryable: false,
      failureCode: "",
      notifications,
    };
  }

  return {
    outcome: "NON_CAPTURE_EVENT",
    bookingId: "",
    paymentAttemptId: "",
    retryable: false,
    failureCode: "",
    notifications: [],
  };
}
