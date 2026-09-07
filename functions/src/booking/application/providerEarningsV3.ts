import {HttpsError} from "firebase-functions/https";
import type {CanonicalBookingDocumentV3} from "../schema/bookingDocumentV3";

export type ProviderEarningsPhaseV3 = "PROVISIONAL" | "HELD" | "FINALIZED" | "ADJUSTED";
export type ProviderEarningsOutcomeV3 = "PAYMENT_CONFIRMED" | "COMPLETION_REVIEW" |
  "NORMAL_COMPLETION" | "CUSTOMER_CANCELLATION" | "PROVIDER_CANCELLATION" |
  "NO_SHOW" | "OPEN_DISPUTE" | "DISPUTE_RESOLUTION" | "CANONICAL_REFUND_REVIEW";

/** Outcome entitlement, independent of payout readiness or money transferred.
 * amountPaise is the compatible public projection of the final entitlement.
 * A null final entitlement means there is no finalized earning yet, not that
 * the provisional entitlement is zero. All updates assign, never increment.
 */
export function buildProviderEarningsProjectionV3(params: {
  entitlementPaise: number;
  phase: ProviderEarningsPhaseV3;
  outcome: ProviderEarningsOutcomeV3;
  priorFinalEntitlementPaise?: number | null;
}) {
  for (const amount of [params.entitlementPaise, params.priorFinalEntitlementPaise]) {
    if (amount != null && (!Number.isSafeInteger(amount) || amount < 0)) {
      throw new HttpsError("failed-precondition", "Provider entitlement must be a non-negative integer in paise.");
    }
  }
  const final = params.phase === "FINALIZED" || params.phase === "ADJUSTED" ?
    params.entitlementPaise : params.priorFinalEntitlementPaise ?? null;
  return {
    earningsSchemaVersion: 1,
    earningsStatus: params.phase,
    earningsOutcome: params.outcome,
    providerProvisionalEntitlementPaise: params.entitlementPaise,
    providerFinalEntitlementPaise: final,
    amountPaise: final ?? 0,
  };
}

/** A processor refund is not an allocation decision. Preserve a known final
 * outcome; an unexplained canonical refund requires review, not invented loss.
 */
export function canonicalRefundEarningsHoldV3(earning: FirebaseFirestore.DocumentData) {
  if (["CUSTOMER_CANCELLATION", "PROVIDER_CANCELLATION", "NO_SHOW", "DISPUTE_RESOLUTION"]
    .includes(earning.earningsOutcome)) return {};
  return buildProviderEarningsProjectionV3({
    entitlementPaise: earning.providerProvisionalEntitlementPaise ?? earning.amountPaise ?? 0,
    priorFinalEntitlementPaise: earning.providerFinalEntitlementPaise ?? null,
    phase: "HELD", outcome: "CANONICAL_REFUND_REVIEW",
  });
}

export function buildCompletionEarningsProjectionV3(
  booking: Pick<CanonicalBookingDocumentV3, "payment" | "financials">,
  finalized: boolean,
) {
  if (!booking.financials) throw new HttpsError("failed-precondition", "Missing canonical financial snapshot.");
  // A partial refund may leave payment.status CONFIRMED. Its refund identity
  // still requires an allocation decision before provisional earnings finalize.
  const refundNeedsReview = Boolean(booking.payment.razorpayRefundId) ||
    booking.payment.status.toLowerCase().includes("refund");
  return buildProviderEarningsProjectionV3({
    entitlementPaise: booking.financials.providerPayoutPaise,
    phase: refundNeedsReview ? "HELD" : finalized ? "FINALIZED" : "PROVISIONAL",
    outcome: refundNeedsReview ? "CANONICAL_REFUND_REVIEW" : finalized ? "NORMAL_COMPLETION" : "COMPLETION_REVIEW",
  });
}
