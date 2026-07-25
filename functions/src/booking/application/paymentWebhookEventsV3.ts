import {FieldValue, Timestamp, type Firestore} from "firebase-admin/firestore";

import {verifyRazorpayWebhookSignatureV3} from "./razorpayGateway";
import type {CanonicalWebhookResult} from "./canonicalPaymentWebhookV3";

const WEBHOOK_PROCESSING_LEASE_MS = 2 * 60 * 1000;

export type PaymentWebhookProcessingState =
  | "RECEIVED"
  | "PROCESSING"
  | "PROCESSED"
  | "RETRYABLE_FAILURE"
  | "TERMINAL_FAILURE";

export type PaymentWebhookClaimResult =
  | {
      outcome: "CLAIMED";
      eventKey: string;
      leaseOwner: string;
    }
  | {
      outcome: "ALREADY_PROCESSED" | "ALREADY_PROCESSING" | "TERMINAL_FAILURE";
      eventKey: string;
    };

export type ProcessRazorpayWebhookEnvelopeResult = {
  statusCode: number;
  responseBody: string;
  eventKey: string | null;
  routeType: "canonical" | "ignored";
};

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value != null ?
    value as Record<string, unknown> :
    {};
}

export function normalizePaymentWebhookProcessingStateV3(
  value: unknown,
): PaymentWebhookProcessingState {
  const normalized = asString(value).toUpperCase();
  switch (normalized) {
  case "RECEIVED":
    return "RECEIVED";
  case "PROCESSING":
    return "PROCESSING";
  case "PROCESSED":
  case "PROCESSED_SUCCESS":
    return "PROCESSED";
  case "TERMINAL_FAILURE":
    return "TERMINAL_FAILURE";
  case "RETRYABLE_FAILURE":
  case "RETRYABLE_ERROR":
    return "RETRYABLE_FAILURE";
  default:
    return "RECEIVED";
  }
}

export function buildPaymentWebhookEventKeyV3(params: {
  eventName: string;
  paymentEntity: Record<string, unknown>;
  refundEntity: Record<string, unknown>;
}): string {
  const refundId = asString(params.refundEntity.id);
  const paymentId = asString(params.paymentEntity.id);
  const orderId = asString(params.paymentEntity.order_id);
  const stableId = refundId || paymentId || orderId || "missing_entity";
  return `${params.eventName.trim() || "unknown"}:${stableId}`;
}

function webhookLeaseExpiresAt(now: Date): Date {
  return new Date(now.getTime() + WEBHOOK_PROCESSING_LEASE_MS);
}

export async function claimPaymentWebhookEventV3(params: {
  firestore: Firestore;
  eventKey: string;
  eventName: string;
  paymentId: string;
  orderId: string;
  refundId: string;
  authoritativeNow: Date;
}): Promise<PaymentWebhookClaimResult> {
  const eventRef = params.firestore.collection("paymentWebhookEvents").doc(params.eventKey);
  const leaseOwner = `${params.eventKey}:${params.authoritativeNow.getTime()}`;
  return params.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(eventRef);
    if (snapshot.exists) {
      const existing = snapshot.data() ?? {};
      const state = normalizePaymentWebhookProcessingStateV3(existing.processingState);
      const leaseExpiresAt = existing.processingLeaseExpiresAt instanceof Timestamp ?
        existing.processingLeaseExpiresAt.toDate() :
        null;
      if (state === "PROCESSED") {
        return {outcome: "ALREADY_PROCESSED", eventKey: params.eventKey};
      }
      if (state === "TERMINAL_FAILURE") {
        return {outcome: "TERMINAL_FAILURE", eventKey: params.eventKey};
      }
      if (
        state === "PROCESSING" &&
        leaseExpiresAt != null &&
        leaseExpiresAt.getTime() > params.authoritativeNow.getTime()
      ) {
        return {outcome: "ALREADY_PROCESSING", eventKey: params.eventKey};
      }
    }

    transaction.set(eventRef, {
      eventId: params.eventKey,
      eventType: params.eventName,
      paymentId: params.paymentId,
      orderId: params.orderId,
      refundId: params.refundId,
      receivedAt: snapshot.exists ?
        (snapshot.data()?.receivedAt ?? FieldValue.serverTimestamp()) :
        FieldValue.serverTimestamp(),
      processingState: "PROCESSING",
      processingLeaseOwner: leaseOwner,
      processingLeaseExpiresAt: Timestamp.fromDate(
        webhookLeaseExpiresAt(params.authoritativeNow),
      ),
      retryCount: FieldValue.increment(snapshot.exists ? 1 : 0),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {outcome: "CLAIMED", eventKey: params.eventKey, leaseOwner};
  });
}

export async function markPaymentWebhookEventProcessedV3(params: {
  firestore: Firestore;
  eventKey: string;
  routeType: "canonical";
  outcome: string;
  bookingId?: string;
  paymentAttemptId?: string;
  failureCode?: string;
  retryable?: boolean;
}): Promise<void> {
  await params.firestore.collection("paymentWebhookEvents").doc(params.eventKey).set({
    processingState: "PROCESSED",
    processedAt: FieldValue.serverTimestamp(),
    canonicalOrLegacy: params.routeType,
    bookingId: params.bookingId ?? "",
    paymentAttemptId: params.paymentAttemptId ?? "",
    failureCode: params.failureCode ?? "",
    retryable: params.retryable ?? false,
    outcome: params.outcome,
    processingLeaseOwner: "",
    processingLeaseExpiresAt: null,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}

export async function markPaymentWebhookEventRetryableFailureV3(params: {
  firestore: Firestore;
  eventKey: string;
  failureCode: string;
}): Promise<void> {
  await params.firestore.collection("paymentWebhookEvents").doc(params.eventKey).set({
    processingState: "RETRYABLE_FAILURE",
    retryable: true,
    failureCode: params.failureCode,
    processingLeaseOwner: "",
    processingLeaseExpiresAt: null,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}

export async function processRazorpayWebhookEnvelopeV3(params: {
  firestore: Firestore;
  signature: string;
  rawBody?: Buffer;
  payload: Record<string, unknown>;
  webhookSecret: string;
  keyId: string;
  keySecret: string;
  authoritativeNow?: Date;
  verifySignature?: typeof verifyRazorpayWebhookSignatureV3;
  routeCanonicalWebhook: (args: {
    firestore: Firestore;
    eventId: string;
    eventName: string;
    paymentEntity: Record<string, unknown>;
    refundEntity: Record<string, unknown>;
    keyId: string;
    keySecret: string;
    authoritativeNow: Date;
  }) => Promise<CanonicalWebhookResult>;
}): Promise<ProcessRazorpayWebhookEnvelopeResult> {
  if (!params.signature.trim()) {
    return {
      statusCode: 400,
      responseBody: "Missing signature",
      eventKey: null,
      routeType: "ignored",
    };
  }

  const verifySignature = params.verifySignature ?? verifyRazorpayWebhookSignatureV3;
  if (
    !params.rawBody ||
    !verifySignature({
      webhookSecret: params.webhookSecret,
      rawBody: params.rawBody,
      signature: params.signature,
    })
  ) {
    return {
      statusCode: 401,
      responseBody: "Invalid signature",
      eventKey: null,
      routeType: "ignored",
    };
  }

  const authoritativeNow = params.authoritativeNow ?? new Date();
  const eventName = asString(params.payload.event);
  const paymentEntity = asRecord(asRecord(asRecord(params.payload.payload).payment).entity);
  const refundEntity = asRecord(asRecord(asRecord(params.payload.payload).refund).entity);
  const paymentId = asString(paymentEntity.id);
  const orderId = asString(paymentEntity.order_id);
  const refundId = asString(refundEntity.id);
  const eventKey = buildPaymentWebhookEventKeyV3({
    eventName,
    paymentEntity,
    refundEntity,
  });

  const claim = await claimPaymentWebhookEventV3({
    firestore: params.firestore,
    eventKey,
    eventName,
    paymentId,
    orderId,
    refundId,
    authoritativeNow,
  });
  if (claim.outcome !== "CLAIMED") {
    return {
      statusCode: 200,
      responseBody: "ok",
      eventKey,
      routeType: "ignored",
    };
  }

  try {
    if (
      eventName === "payment.captured" ||
      eventName === "refund.created" ||
      eventName === "refund.processed" ||
      eventName === "refund.failed"
    ) {
      const canonicalResult = await params.routeCanonicalWebhook({
        firestore: params.firestore,
        eventId: eventKey,
        eventName,
        paymentEntity,
        refundEntity,
        keyId: params.keyId,
        keySecret: params.keySecret,
        authoritativeNow,
      });
      if (canonicalResult.outcome !== "NON_CAPTURE_EVENT") {
        await markPaymentWebhookEventProcessedV3({
          firestore: params.firestore,
          eventKey,
          routeType: "canonical",
          outcome: canonicalResult.outcome,
          bookingId: canonicalResult.bookingId,
          paymentAttemptId: canonicalResult.paymentAttemptId,
          failureCode: canonicalResult.failureCode,
          retryable: canonicalResult.retryable,
        });
        return {
          statusCode: 200,
          responseBody: "ok",
          eventKey,
          routeType: "canonical",
        };
      }
    }

    await markPaymentWebhookEventProcessedV3({
      firestore: params.firestore,
      eventKey,
      routeType: "canonical",
      outcome: "IGNORED_UNHANDLED_EVENT",
    });
    return {
      statusCode: 200,
      responseBody: "ok",
      eventKey,
      routeType: "canonical",
    };
  } catch (error) {
    const failureCode = error instanceof Error ? error.message : String(error);
    await markPaymentWebhookEventRetryableFailureV3({
      firestore: params.firestore,
      eventKey,
      failureCode: failureCode.slice(0, 120),
    });
    throw error;
  }
}
