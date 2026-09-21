import {confirmManualCancellationRefundTransactionV3} from "./manualCancellationRefundV3";
import {isCancellationSourceV3} from "./manualSettlementTypesV3";
import {canonicalRefundEarningsHoldV3} from "./providerEarningsV3";
import {createHash} from "node:crypto";
import {Timestamp, type Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/https";

type Data = FirebaseFirestore.DocumentData;
export function authoritativePaymentIdV3(booking: Data): string {
  // The booking payment ID is the funding identity; an order or booking ID
  // alone cannot establish that a refund affects the winning capture.
  return typeof booking.payment?.razorpayPaymentId === "string" ?
    booking.payment.razorpayPaymentId.trim() : "";
}

export function excessRefundIdV3(paymentId: string): string {
  return `excess_${createHash("sha256").update(paymentId).digest("hex")}`;
}

export function refundInstructionIdV3(bookingId: string, booking: Data, paymentId: string): string {
  const winner = authoritativePaymentIdV3(booking);
  return winner && winner === paymentId ? bookingId : excessRefundIdV3(paymentId);
}

export function hasRefundEvidenceV3(attempt: Data): boolean {
  return attempt.state === "REFUNDED" || attempt.state === "REFUND_PENDING" || Number(attempt.refundedAmountPaise ?? 0) > 0 ||
    Object.keys(attempt.refundEvents ?? {}).length > 0;
}

/** Apply one processor refund fact atomically, using refund ID for idempotency.
 * paymentRefunds stores each refund, while refunds stores its instruction/summary.
 * Excess ledger entries have a distinct type so canonical booking reconciliation
 * never subtracts them from the service's customer-paid amount.
 */
export async function applyPaymentRefundEventV3(params: {
  firestore: Firestore; bookingId: string; paymentAttemptId: string;
  paymentId: string; refundId: string; amountPaise: number;
  eventName: "refund.created" | "refund.processed" | "refund.failed";
  now: Date;
}): Promise<{authoritative: boolean; changed: boolean; manual: boolean}> {
  if (!params.refundId || !Number.isSafeInteger(params.amountPaise) || params.amountPaise <= 0) {
    throw new HttpsError("invalid-argument", "Refund ID and positive integer amount are required.");
  }
  const bookingRef = params.firestore.collection("bookings").doc(params.bookingId);
  const attemptRef = bookingRef.collection("paymentAttempts").doc(params.paymentAttemptId);
  const eventKey = createHash("sha256").update(`${params.paymentId}:${params.refundId}`).digest("hex");
  const eventRef = params.firestore.collection("paymentRefunds").doc(eventKey);
  return params.firestore.runTransaction(async (tx) => {
    const [bookingSnap, attemptSnap, eventSnap, canonicalRefundSnap, earningSnap] = await Promise.all([
      tx.get(bookingRef), tx.get(attemptRef), tx.get(eventRef),
      tx.get(params.firestore.collection("refunds").doc(params.bookingId)),
      tx.get(params.firestore.collection("providerEarnings").doc(params.bookingId)),
    ]);
    const booking = bookingSnap.data() as Data | undefined;
    const attempt = attemptSnap.data() as Data | undefined;
    if (!booking || !attempt || attempt.razorpayPaymentId !== params.paymentId) {
      throw new HttpsError("failed-precondition", "Refund payment identity does not match its attempt.");
    }
    const authoritative = authoritativePaymentIdV3(booking) === params.paymentId;
    const canonicalRefund = canonicalRefundSnap.data() ?? {};
    if (authoritative && isCancellationSourceV3(canonicalRefund.origin) && canonicalRefund.executionMode === "MANUAL") {
      const changed = await confirmManualCancellationRefundTransactionV3({...params,
        transaction: tx, booking, attempt, refund: canonicalRefund});
      return {authoritative, changed, manual: false};
    }
    if (authoritative && (
      String(canonicalRefund.executionMode).toUpperCase() === "MANUAL" ||
      String(canonicalRefund.origin).toUpperCase() === "DISPUTE_RESOLUTION"
    )) return {authoritative, changed: false, manual: true};

    const instructionRef = params.firestore.collection("refunds").doc(
      refundInstructionIdV3(params.bookingId, booking, params.paymentId),
    );
    const instruction = authoritative ? canonicalRefund : (await tx.get(instructionRef)).data() ?? {};
    const captured = Number(attempt.capturedAmountPaise ?? attempt.amountPaise);
    const previous = eventSnap.data();
    if (!Number.isSafeInteger(captured) || captured <= 0 || params.amountPaise > captured ||
      (previous && previous.amountPaise !== params.amountPaise)) {
      throw new HttpsError("failed-precondition", "Refund amount conflicts with captured payment/refund history.");
    }
    const state = params.eventName === "refund.processed" ? "processed" :
      params.eventName === "refund.failed" ? "failed" : "submitted";
    // Processed is final. A delayed created event cannot revive a failed refund.
    if (previous && (previous.state === "processed" || previous.state === state ||
      (previous.state === "failed" && state === "submitted"))) {
      return {authoritative, changed: false, manual: false};
    }
    const events: Record<string, {amountPaise: number; state: string}> = {
      ...(attempt.refundEvents ?? {}), [eventKey]: {amountPaise: params.amountPaise, state},
    };
    const refunded = Object.values(events).filter((e) => e.state === "processed")
      .reduce((sum, e) => sum + e.amountPaise, 0);
    if (refunded > captured) throw new HttpsError("failed-precondition", "Refund total exceeds captured amount.");
    const pending = Object.values(events).some((e) => e.state === "submitted");
    const failed = Object.values(events).some((e) => e.state === "failed");
    const refundStatus = refunded === captured ? "REFUNDED" : pending ? "REFUND_PENDING" :
      failed ? "REFUND_FAILED" : refunded > 0 ? "PARTIALLY_REFUNDED" : "NONE";
    const now = Timestamp.fromDate(params.now);
    const summary = {
      bookingId: params.bookingId, paymentAttemptId: params.paymentAttemptId,
      razorpayPaymentId: params.paymentId, razorpayRefundId: params.refundId,
      refundAmountPaise: Math.max(Number(instruction.refundAmountPaise ?? 0), refunded, params.amountPaise), refundedAmountPaise: refunded,
      capturedAmountPaise: captured, netCapturedAmountPaise: captured - refunded,
      refundStatus, state: refunded === captured ? "processed" : pending ? "submitted" : failed ? "failed" : state, scope: authoritative ? "AUTHORITATIVE" : "EXCESS",
      updatedAt: now,
    };
    tx.set(eventRef, {...summary, state, amountPaise: params.amountPaise, createdAt: previous?.createdAt ?? now}, {merge: true});
    tx.set(instructionRef, summary, {merge: true});
    tx.set(attemptRef, {
      refundEvents: events, refundStatus, refundedAmountPaise: refunded,
      capturedAmountPaise: captured, netCapturedAmountPaise: captured - refunded,
      state: refunded === captured ? "REFUNDED" : pending ? "REFUND_PENDING" :
        authoritative && !failed ? "CONFIRMED" : "REFUND_REQUIRED",
      refundedAt: refunded === captured ? now : null,
      nextReconciliationAt: null, updatedAt: now,
    }, {merge: true});
    if (state === "processed") {
      tx.set(params.firestore.collection("bookingFinancialLedger").doc(`refund_${eventKey}`), {
        entryId: `refund_${eventKey}`, bookingId: params.bookingId,
        paymentAttemptId: params.paymentAttemptId, razorpayPaymentId: params.paymentId,
        refundId: params.refundId, type: authoritative ? "CUSTOMER_REFUND" : "EXCESS_PAYMENT_REFUND",
        account: authoritative ? "customer_refund" : "excess_payment_refund",
        direction: "debit", amountPaise: params.amountPaise, currency: attempt.currency ?? "INR",
        providerId: booking.providerId ?? "", sourceType: "razorpay_refund", sourceId: params.refundId,
        occurredAt: now, createdAt: now,
      }, {merge: true});
    }
    if (!authoritative) return {authoritative, changed: true, manual: false};

    // Preserve the funding identity and lifecycle; partial refunds carry their
    // own status instead of pretending that the whole capture was returned.
    const paymentStatus = refunded === captured ? "refunded" : pending ? "refund_pending" :
      failed ? "refund_failed" : "CONFIRMED";
    tx.set(bookingRef, {
      payment: {...booking.payment, status: paymentStatus, refundStatus,
        razorpayRefundId: params.refundId, refundedAmountPaise: refunded,
        netCapturedAmountPaise: captured - refunded},
      financials: {...booking.financials, refundAmountPaise: refunded}, updatedAt: now,
    }, {merge: true});
    tx.set(params.firestore.collection("bookingCancellations").doc(params.bookingId), {
      bookingId: params.bookingId, refundAmountPaise: refunded, refundStatus,
      status: refunded === captured ? "REFUNDED" : "CANCELLED",
      refundInstructionId: `refund-${params.bookingId}`, updatedAt: now,
    }, {merge: true});
    // A capture refunded before confirmation never earned provider entitlement.
    if (booking.lifecycle?.paidAt == null) return {authoritative, changed: true, manual: false};
    for (const collection of ["payments", "invoices", "bookingFinancials"]) {
      tx.set(params.firestore.collection(collection).doc(params.bookingId), {
        refundStatus: refundStatus.toLowerCase(), refundAmountPaise: refunded,
        ...(collection === "bookingFinancials" ? {paymentStatus} : {}), updatedAt: now,
      }, {merge: true});
    }
    if (earningSnap.exists) tx.set(params.firestore.collection("providerEarnings").doc(params.bookingId), {
      ...canonicalRefundEarningsHoldV3(earningSnap.data() ?? {}),
      refundStatus: refundStatus.toLowerCase(), eligibleForPayout: false, updatedAt: now,
    }, {merge: true});
    tx.set(params.firestore.collection("payoutReadiness").doc(params.bookingId), {
      status: refunded === captured ? "cancelled" : "held",
      ...(refunded === captured ? {providerPayoutPaise: 0} : {}), updatedAt: now,
    }, {merge: true});
    return {authoritative, changed: true, manual: false};
  });
}
