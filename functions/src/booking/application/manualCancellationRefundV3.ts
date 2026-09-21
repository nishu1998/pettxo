import {Timestamp, type Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/https";
import {createHash} from "node:crypto";
import {loadSettlementContextV3, cancellationRefundOutstandingV3, settlementOutcomeV3} from "./manualSettlementSyncV3";
import {cancellationRefundObligationIdV3, completedRefundPaiseV3, isCancellationSourceV3, moneyV3} from "./manualSettlementTypesV3";

type Data = Record<string, any>;
export async function recordManualCancellationRefundV3(params: {
  firestore: Firestore; transaction: FirebaseFirestore.Transaction; obligation: Data;
  input: Data; adminUid: string; now: Date;
}) {
  const {firestore: db, transaction: tx, obligation: o} = params;
  const ctx = await loadSettlementContextV3({firestore: db, transaction: tx, bookingId: o.bookingId});
  const source = settlementOutcomeV3(ctx).source;
  const refund = ctx.refund;
  const refundId = String(params.input.razorpayRefundId ?? "").trim();
  if (!isCancellationSourceV3(source) || source !== o.source || o.obligationType !== "CUSTOMER_REFUND" ||
    o.obligationId !== cancellationRefundObligationIdV3(o.bookingId) ||
    o.recipientUserId !== ctx.booking.parentId || o.currency !== ctx.booking.financials?.currency || refund.executionMode !== "MANUAL" || refund.origin !== source || refund.reasonCode !== source ||
    refund.razorpayPaymentId !== ctx.booking.payment.razorpayPaymentId ||
    refund.paymentAttemptId !== ctx.booking.payment.paymentAttemptId) {
    throw new HttpsError("failed-precondition", "Manual refund does not match the canonical cancellation.");
  }
  if (!refundId) throw new HttpsError("invalid-argument", "razorpayRefundId is required for processor confirmation.");
  const evidence = String(refund.razorpayRefundId ?? "");
  if (["COMPLETED", "PROCESSING"].includes(o.status)) {
    if (evidence !== refundId) throw new HttpsError("failed-precondition", "Refund already has different execution evidence.");
    return {ok: true, code: o.status === "COMPLETED" ? "ALREADY_COMPLETED" : "ALREADY_PROCESSING",
      obligationId: o.obligationId, bookingId: o.bookingId, idempotentReplay: true};
  }
  // Failed/ambiguous evidence needs reconciliation before another execution.
  if (o.status !== "READY" || evidence || !["required"].includes(refund.state)) {
    throw new HttpsError("failed-precondition", "Refund is not ready for a new manual recording.");
  }
  const amount = cancellationRefundOutstandingV3(ctx);
  if (amount <= 0 || amount !== moneyV3(o.amountPaise)) {
    throw new HttpsError("failed-precondition", "Stale refund amount; synchronize before recording.");
  }
  const stamp = Timestamp.fromDate(params.now);
  tx.set(db.collection("manualSettlementObligations").doc(o.obligationId), {
    status: "PROCESSING", updatedAt: stamp, metadata: {...o.metadata, razorpayRefundId: refundId,
      manualReference: String(params.input.reference ?? ""), manualAdminNote: String(params.input.adminNote ?? ""),
      recordedByAdminUid: params.adminUid, proofStoragePath: String(params.input.proofStoragePath ?? "")},
  }, {merge: true});
  tx.set(db.collection("refunds").doc(o.bookingId), {
    state: "manual_recorded", manualRefundStatus: "INITIATED", razorpayRefundId: refundId,
    manualRecordedByAdminUid: params.adminUid, manualRecordedAt: stamp,
    manualReference: String(params.input.reference ?? ""), manualNote: String(params.input.adminNote ?? ""),
    updatedAt: stamp,
  }, {merge: true});
  tx.set(db.collection("bookingFinancialLedger").doc(`manual_settlement_record_${o.obligationId}`), {
    bookingId: o.bookingId, type: "MANUAL_SETTLEMENT_OBLIGATION", direction: "memo",
    amountPaise: amount, sourceId: o.obligationId, sourceType: source,
    razorpayRefundId: refundId, occurredAt: stamp, createdAt: stamp,
  }, {merge: false});
  return {ok: true, code: "RECORDED", obligationId: o.obligationId, bookingId: o.bookingId,
    refundId: o.bookingId, idempotentReplay: false};
}

/** Called only with authenticated processor facts. No external money is sent. */
export async function confirmManualCancellationRefundTransactionV3(params: {
  firestore: Firestore; transaction: FirebaseFirestore.Transaction;
  bookingId: string; booking: Data; attempt: Data; refund: Data;
  paymentAttemptId: string; paymentId: string; refundId: string; amountPaise: number;
  eventName: "refund.created" | "refund.processed" | "refund.failed"; now: Date;
}): Promise<boolean> {
  const {firestore: db, transaction: tx, refund, booking, attempt} = params;
  const oid = cancellationRefundObligationIdV3(params.bookingId);
  const ref = db.collection("manualSettlementObligations").doc(oid);
  const eventKey = createHash("sha256").update(`${params.paymentId}:${params.refundId}`).digest("hex");
  const eventRef = db.collection("paymentRefunds").doc(eventKey);
  const [snapshot, previous, cancellationSnapshot] = await Promise.all([
    tx.get(ref), tx.get(eventRef), tx.get(db.collection("bookingCancellations").doc(params.bookingId)),
  ]);
  const cancellation = cancellationSnapshot.data() ?? {};
  const o = snapshot.data();
  if (!o || o.obligationType !== "CUSTOMER_REFUND" || o.obligationId !== oid ||
    o.recipientUserId !== booking.parentId || o.currency !== booking.financials.currency ||
    !isCancellationSourceV3(o.source) || refund.origin !== o.source || refund.executionMode !== "MANUAL" ||
    refund.razorpayPaymentId !== params.paymentId || refund.paymentAttemptId !== params.paymentAttemptId ||
    booking.payment.razorpayPaymentId !== params.paymentId ||
    (refund.razorpayRefundId && refund.razorpayRefundId !== params.refundId)) {
    throw new HttpsError("failed-precondition", "Manual refund processor evidence does not match its obligation.");
  }
  if (params.amountPaise !== moneyV3(o.amountPaise)) {
    throw new HttpsError("failed-precondition", "Processor refund amount does not match the manual obligation.");
  }
  if (o.status === "COMPLETED" || previous.data()?.state === "processed") return false;
  if (previous.data()?.state === "failed" && params.eventName === "refund.created") return false;
  const prior = Math.max(completedRefundPaiseV3(refund), moneyV3(attempt.refundedAmountPaise ?? 0));
  const entitlement = moneyV3(cancellation.refundAmountPaise);
  const baseline = moneyV3(refund.refundedBeforeCancellationPaise ?? 0);
  if (moneyV3(refund.refundEntitlementPaise ?? entitlement) !== entitlement ||
    params.amountPaise !== Math.max(entitlement - Math.max(prior - baseline, 0), 0)) {
    throw new HttpsError("failed-precondition", "Processor refund conflicts with outstanding cancellation entitlement.");
  }
  const processed = params.eventName === "refund.processed";
  const total = prior + (processed ? params.amountPaise : 0);
  if (total > moneyV3(booking.financials.customerPaidPaise) ||
    total > moneyV3(attempt.capturedAmountPaise ?? attempt.amountPaise)) {
    throw new HttpsError("failed-precondition", "Processor refund exceeds outstanding captured money.");
  }
  const status = processed ? "COMPLETED" : params.eventName === "refund.failed" ? "NEEDS_ATTENTION" : "PROCESSING";
  const state = processed ? "processed" : params.eventName === "refund.failed" ? "failed" : "submitted";
  const stamp = Timestamp.fromDate(params.now);
  tx.set(ref, {status, financialSettlementStatus: processed ? "COMPLETED" : "PENDING",
    completedAt: processed ? stamp : null, completedByAdminUid: refund.manualRecordedByAdminUid ?? "",
    updatedAt: stamp, metadata: {...o.metadata, razorpayRefundId: params.refundId, lastWebhookEvent: params.eventName}}, {merge: true});
  tx.set(db.collection("refunds").doc(params.bookingId), {state, refundedAmountPaise: total,
    manualRefundStatus: processed ? "PROCESSED" : params.eventName === "refund.failed" ? "FAILED" : "CREATED",
    razorpayRefundId: params.refundId, confirmedAt: processed ? stamp : null, updatedAt: stamp}, {merge: true});
  tx.set(eventRef, {bookingId: params.bookingId, paymentAttemptId: params.paymentAttemptId,
    razorpayPaymentId: params.paymentId, razorpayRefundId: params.refundId,
    amountPaise: params.amountPaise, state, scope: "AUTHORITATIVE", updatedAt: stamp}, {merge: true});
  if (processed) {
    tx.set(db.collection("bookings").doc(params.bookingId), {
      payment: {...booking.payment, refundedAmountPaise: total, razorpayRefundId: params.refundId,
        refundStatus: total === booking.financials.customerPaidPaise ? "REFUNDED" : "PARTIALLY_REFUNDED"},
      financials: {...booking.financials, refundAmountPaise: total}, updatedAt: stamp,
    }, {merge: true});
    tx.set(db.collection("bookings").doc(params.bookingId).collection("paymentAttempts").doc(params.paymentAttemptId), {
      refundedAmountPaise: total, netCapturedAmountPaise: (attempt.capturedAmountPaise ?? attempt.amountPaise) - total,
      refundEvents: {...attempt.refundEvents, [params.refundId]: {amountPaise: params.amountPaise, state: "processed"}},
      updatedAt: stamp,
    }, {merge: true});
    tx.set(db.collection("bookingCancellations").doc(params.bookingId), {refundStatus: "REFUNDED", updatedAt: stamp}, {merge: true});
    tx.set(db.collection("bookingFinancials").doc(params.bookingId), {refundedAmountPaise: total, refundStatus: "processed", updatedAt: stamp}, {merge: true});
    tx.set(db.collection("bookingFinancialLedger").doc(`refund_${eventKey}`), {
      entryId: `refund_${eventKey}`, bookingId: params.bookingId, type: "CUSTOMER_REFUND", direction: "debit",
      amountPaise: params.amountPaise, currency: o.currency, refundId: params.refundId,
      account: "customer_refund", sourceType: "razorpay_refund", sourceId: params.refundId,
      occurredAt: stamp, createdAt: stamp,
    }, {merge: true});
  }
  return true;
}
