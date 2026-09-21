import {Timestamp, type Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/https";
import {parseCanonicalBookingDocumentV3, type CanonicalBookingDocumentV3} from "../schema/bookingDocumentV3";
import {normalizeTimestampLike} from "../schema/timestampNormalization";
import {buildCanonicalProviderPayoutDocumentV3, evaluateCanonicalProviderPayoutEligibilityV3} from "./financialSettlementV3";
import {cancellationRefundObligationIdV3, completedRefundPaiseV3, isCancellationSourceV3, moneyV3, parseManualSettlementSourceV3, type ManualSettlementSourceV3} from "./manualSettlementTypesV3";

type Data = Record<string, any>;
const protectedStatuses = ["COMPLETED", "PROCESSING", "NEEDS_ATTENTION"];
export type SettlementContextV3 = {
  booking: CanonicalBookingDocumentV3; cancellation: Data; resolution: Data; earning: Data;
  refund: Data; payout: Data; provider: Data; customer: Data; profile: Data | null; attempt: Data;
};
export async function loadSettlementContextV3(params: {
  firestore: Firestore; transaction: FirebaseFirestore.Transaction; bookingId: string;
  booking?: CanonicalBookingDocumentV3; cancellation?: Data; refund?: Data; earning?: Data;
}): Promise<SettlementContextV3> {
  const {firestore: db, transaction: tx, bookingId: id} = params;
  const snapshot = await tx.get(db.collection("bookings").doc(id));
  let booking = params.booking;
  if (!booking) {
    const parsed = parseCanonicalBookingDocumentV3(snapshot.data() ?? {});
    if (!parsed.ok) throw new HttpsError("failed-precondition", "Canonical booking is incomplete.");
    booking = parsed.booking;
  }
  const paths = [
    ["bookingCancellations", id], ["bookingDisputeResolutions", `resolution_${id}`],
    ["providerEarnings", id], ["refunds", id], ["providerPayouts", id],
    ["manualSettlementObligations", `provider_payout_${id}`],
  ];
  const docs = await Promise.all(paths.map(([collection, doc]) => tx.get(db.collection(collection).doc(doc))));
  const [cancellation, resolution, earning, refund, payout, provider] = docs.map((doc) => doc.data() ?? {});
  const customerId = Object.keys(resolution).length ? `customer_refund_resolution_${id}` : cancellationRefundObligationIdV3(id);
  const [customer, profile, attempt] = await Promise.all([
    tx.get(db.collection("manualSettlementObligations").doc(customerId)),
    tx.get(db.collection("users").doc(booking.providerId).collection("providerBankDetails").doc("main")),
    tx.get(db.collection("bookings").doc(id).collection("paymentAttempts").doc(booking.payment.paymentAttemptId)),
  ]);
  return {booking, cancellation: params.cancellation ?? cancellation, resolution,
    earning: params.earning ?? earning, refund: params.refund ?? refund, payout, provider,
    customer: customer.data() ?? {}, profile: profile.data() ?? null, attempt: attempt.data() ?? {}};
}
export function settlementOutcomeV3(ctx: SettlementContextV3): {source: ManualSettlementSourceV3; entitlement: number} {
  if (ctx.resolution.resolutionId) return {source: "DISPUTE_RESOLUTION",
    entitlement: moneyV3(ctx.resolution.providerFinalEntitlementPaise)};
  if (ctx.booking.state === "CANCELLED") {
    if (!["CUSTOMER", "PROVIDER"].includes(ctx.cancellation.actorType)) {
      throw new HttpsError("failed-precondition", "Final cancellation outcome is missing.");
    }
    const entitlement = moneyV3(ctx.cancellation.providerCompensationPaise);
    if (ctx.earning.providerFinalEntitlementPaise != null &&
      moneyV3(ctx.earning.providerFinalEntitlementPaise) !== entitlement) {
      throw new HttpsError("failed-precondition", "Cancellation entitlement conflicts with finalized earnings.");
    }
    return {source: ctx.cancellation.actorType === "CUSTOMER" ? "CUSTOMER_CANCELLATION" : "PROVIDER_CANCELLATION", entitlement};
  }
  if (!["NO_SHOW", "COMPLETED_FINAL"].includes(ctx.booking.state)) {
    throw new HttpsError("failed-precondition", "Booking has no finalized settlement outcome.");
  }
  return {source: ctx.booking.state === "NO_SHOW" ? "NO_SHOW" : "NORMAL_COMPLETION",
    entitlement: moneyV3(ctx.booking.financials?.providerPayoutPaise)};
}
export function outstandingProviderV3(ctx: SettlementContextV3, entitlement: number): number {
  const paid = Math.max(moneyV3(ctx.payout.priorPaidPaise ?? 0),
    String(ctx.payout.status).toUpperCase() === "PAID" ? moneyV3(ctx.payout.providerEntitlementPaise ?? entitlement) : 0,
    ctx.provider.status === "COMPLETED" ? moneyV3(ctx.provider.amountPaise) : 0);
  if (paid > entitlement) throw new HttpsError("failed-precondition", "Paid provider amount exceeds final entitlement; review required.");
  if (ctx.provider.status === "COMPLETED" && paid < entitlement) {
    throw new HttpsError("failed-precondition", "Completed payout conflicts with increased entitlement; review required.");
  }
  return entitlement - paid;
}
export function payoutEligibilityForOutcomeV3(ctx: SettlementContextV3, now: Date) {
  const outcome = settlementOutcomeV3(ctx);
  const remaining = outstandingProviderV3(ctx, outcome.entitlement);
  const cancellation = isCancellationSourceV3(outcome.source);
  // Cancellation has a final compensation allocation despite the booking's
  // operational cancelled/payment-refund status. Never use its original price.
  const booking = cancellation ? {...ctx.booking, state: "COMPLETED_FINAL" as const,
    payment: {...ctx.booking.payment, status: ctx.booking.lifecycle.paidAt ? "paid" : ctx.booking.payment.status},
    payout: {...ctx.booking.payout, eligibleAt: normalizeTimestampLike(ctx.cancellation.requestedAt) ?? now}} : ctx.booking;
  const eligible = evaluateCanonicalProviderPayoutEligibilityV3({booking,
    existingPayout: {...ctx.payout, providerEntitlementPaise: outcome.entitlement,
      priorPaidPaise: outcome.entitlement - remaining,
      eligibleAt: cancellation ? booking.payout.eligibleAt : ctx.booking.payout.eligibleAt},
    existingRefund: ctx.refund, providerBankDetails: ctx.profile, authoritativeNow: now});
  if (outcome.source !== "DISPUTE_RESOLUTION" && ctx.earning.earningsStatus === "HELD" &&
    !["OPEN", "UNDER_REVIEW"].includes(ctx.booking.dispute.status.toUpperCase())) {
    return {...eligible, status: "HELD" as const, holdReason: "Final provider earnings require canonical review.", readyAt: null};
  }
  // The legacy evaluator does not recognize every in-flight manual state.
  const pending = ["required", "submitting", "submission_unknown", "submitted", "pending", "manual_recorded", "failed"].includes(String(ctx.refund.state).toLowerCase());
  if (pending && outcome.source !== "DISPUTE_RESOLUTION" && !["OPEN", "UNDER_REVIEW"].includes(ctx.booking.dispute.status.toUpperCase())) {
    return {...eligible, status: "HELD" as const, holdReason: "Payout remains held while a refund is pending.", readyAt: null};
  }
  if (["PROCESSING", "FAILED"].includes(String(ctx.payout.status).toUpperCase())) {
    return {...eligible, status: "HELD" as const, holdReason: "Existing payout execution requires reconciliation.", readyAt: null};
  }
  return eligible;
}
export function cancellationRefundOutstandingV3(ctx: SettlementContextV3): number {
  const total = moneyV3(ctx.refund.refundEntitlementPaise ?? ctx.cancellation.refundAmountPaise);
  const baseline = moneyV3(ctx.refund.refundedBeforeCancellationPaise ?? 0);
  if (total !== moneyV3(ctx.cancellation.refundAmountPaise)) {
    throw new HttpsError("failed-precondition", "Refund instruction conflicts with the cancellation entitlement.");
  }
  const refunded = Math.max(completedRefundPaiseV3(ctx.refund), moneyV3(ctx.attempt.refundedAmountPaise ?? 0));
  const completedForOutcome = Math.max(refunded - baseline, 0);
  const outstanding = Math.max(total - completedForOutcome, 0);
  const captured = moneyV3(ctx.attempt.capturedAmountPaise ?? ctx.attempt.amountPaise ?? ctx.booking.financials?.customerPaidPaise);
  if (outstanding > Math.max(Math.min(captured, moneyV3(ctx.booking.financials?.customerPaidPaise)) - refunded, 0)) {
    throw new HttpsError("failed-precondition", "Refund exceeds outstanding customer-paid funds.");
  }
  return outstanding;
}
/** Read everything first. Call write only after the caller's other reads. */
export async function prepareManualSettlementSyncV3(params: Parameters<typeof loadSettlementContextV3>[0] & {now: Date}) {
  const ctx = await loadSettlementContextV3(params);
  for (const record of [ctx.provider, ctx.customer]) {
    if (record.obligationId) parseManualSettlementSourceV3(record.source);
  }
  const {source, entitlement} = settlementOutcomeV3(ctx);
  const remaining = outstandingProviderV3(ctx, entitlement);
  const eligibility = payoutEligibilityForOutcomeV3(ctx, params.now);
  const stamp = Timestamp.fromDate(params.now);
  const id = params.bookingId;
  const base = (type: string, recipient: string, amount: number): Data => ({
    bookingId: id, obligationType: type, recipientType: type === "PROVIDER_PAYOUT" ? "PROVIDER" : "CUSTOMER",
    recipientUserId: recipient, amountPaise: amount, currency: ctx.booking.financials?.currency ?? "INR",
    source, executionMode: "MANUAL", settlementSyncVersion: 1,
    disputeId: ctx.resolution.disputeId ?? "", disputeResolutionId: ctx.resolution.resolutionId ?? "",
    policyVersion: "v3_manual_outcomes_1", relatedPayoutId: "", relatedRefundId: "", cancelledAt: null,
    financialSettlementStatus: "PENDING", paymentAttemptId: ctx.booking.payment.paymentAttemptId,
    razorpayOrderId: ctx.booking.payment.razorpayOrderId, razorpayPaymentId: ctx.booking.payment.razorpayPaymentId,
    createdAt: stamp, updatedAt: stamp, completedAt: null, completedByAdminUid: "", readyAt: null,
    reasonCode: `${source}_${ctx.cancellation.timingBand ?? "PAYOUT"}`, holdReason: "",
    metadata: {timingBand: ctx.cancellation.timingBand ?? null},
  });
  const payoutInFlight = ["PROCESSING", "FAILED"].includes(String(ctx.payout.status).toUpperCase());
  const provider = protectedStatuses.includes(ctx.provider.status) ? ctx.provider :
    remaining > 0 || ctx.provider.obligationId ? {...base("PROVIDER_PAYOUT", ctx.booking.providerId, remaining),
      obligationId: `provider_payout_${id}`, relatedPayoutId: id,
      createdAt: ctx.provider.createdAt ?? stamp,
      status: payoutInFlight ? "NEEDS_ATTENTION" : remaining === 0 ? "CANCELLED" : eligibility.status,
      holdReason: eligibility.holdReason, readyAt: eligibility.readyAt ? Timestamp.fromDate(eligibility.readyAt) : null} : null;
  let customer: Data | null = null;
  if (isCancellationSourceV3(source) && moneyV3(ctx.cancellation.refundAmountPaise) > 0) {
    const manual = ctx.refund.executionMode === "MANUAL" && ctx.refund.origin === source;
    const amount = cancellationRefundOutstandingV3(ctx);
    const unsafe = !manual || ctx.refund.state !== "required" || Boolean(ctx.refund.razorpayRefundId);
    customer = protectedStatuses.includes(ctx.customer.status) ? ctx.customer : amount > 0 || ctx.customer.obligationId ? {
      ...base("CUSTOMER_REFUND", ctx.booking.parentId, amount), obligationId: cancellationRefundObligationIdV3(id),
      relatedRefundId: id, createdAt: ctx.customer.createdAt ?? stamp,
      status: amount === 0 ? "COMPLETED" : unsafe ? "NEEDS_ATTENTION" : "READY",
      holdReason: unsafe ? "Refund execution evidence requires reconciliation." : "",
      readyAt: amount > 0 && !unsafe ? stamp : null,
    } : null;
  } else if (source === "DISPUTE_RESOLUTION") {
    // Resolution writer owns its financial allocation. Reconstruct only a
    // verified manual instruction; never fabricate a second refund liability.
    const amount = Math.max(moneyV3(ctx.resolution.customerRefundPaise ?? 0) - completedRefundPaiseV3(ctx.refund), 0);
    if (ctx.customer.obligationId) customer = ctx.customer;
    else if (amount > 0 && ctx.refund.origin === source && ctx.refund.executionMode === "MANUAL") {
      customer = {...base("CUSTOMER_REFUND", ctx.booking.parentId, amount),
        obligationId: `customer_refund_resolution_${id}`, relatedRefundId: id,
        status: ["required", "pending"].includes(ctx.refund.state) && !ctx.refund.razorpayRefundId ? "READY" : "NEEDS_ATTENTION"};
    }
  }
  return {ctx, provider, customer, write: () => {
    const {transaction: tx, firestore: db} = params;
    if (provider && !protectedStatuses.includes(ctx.provider.status)) {
      tx.set(db.collection("manualSettlementObligations").doc(provider.obligationId), provider, {merge: true});
      if (!payoutInFlight) tx.set(db.collection("providerPayouts").doc(id), {
        ...buildCanonicalProviderPayoutDocumentV3({bookingId: id,
          booking: {...ctx.booking, financials: {...ctx.booking.financials!, providerPayoutPaise: entitlement}},
          now: params.now}),
        ...ctx.payout, payoutId: id, bookingId: id, providerId: ctx.booking.providerId,
        providerEntitlementPaise: entitlement, remainingPayablePaise: remaining,
        priorPaidPaise: entitlement - remaining, status: provider.status,
        holdReason: provider.holdReason, eligibleAt: ctx.booking.payout.eligibleAt ?? stamp,
        readyAt: provider.readyAt, updatedAt: stamp, createdAt: ctx.payout.createdAt ?? stamp,
        currency: provider.currency, source, executionMode: "MANUAL",
      }, {merge: true});
      if (!payoutInFlight) {
        tx.set(db.collection("bookings").doc(id), {payout: {status: provider.status.toLowerCase(),
          eligibleAt: ctx.booking.payout.eligibleAt ?? stamp, providerPayoutPaise: entitlement}}, {merge: true});
        if (Object.keys(ctx.earning).length > 0) tx.set(db.collection("providerEarnings").doc(id), {status: provider.status,
          eligibleForPayout: provider.status === "READY", updatedAt: stamp}, {merge: true});
      }
      tx.set(db.collection("payoutReadiness").doc(id), {status: provider.status.toLowerCase(), payoutStatus: provider.status,
        manualSettlementStatus: provider.status, providerPayoutPaise: remaining,
        payoutHoldReason: provider.holdReason, updatedAt: stamp}, {merge: true});
    }
    if (customer && !protectedStatuses.includes(ctx.customer.status)) {
      tx.set(db.collection("manualSettlementObligations").doc(customer.obligationId), customer, {merge: true});
    }
  }};
}
export async function synchronizeManualSettlementBookingV3(params: {firestore: Firestore; bookingId: string; now?: Date}) {
  return params.firestore.runTransaction(async (transaction) => {
    const plan = await prepareManualSettlementSyncV3({...params, transaction, now: params.now ?? new Date()});
    plan.write();
    return {ok: true, code: plan.ctx.provider.obligationId ? "SYNCHRONIZED" : "MATERIALIZED",
      bookingId: params.bookingId, obligationId: plan.provider?.obligationId ?? plan.customer?.obligationId ?? null,
      obligationIds: [plan.provider?.obligationId, plan.customer?.obligationId].filter(Boolean)};
  });
}
