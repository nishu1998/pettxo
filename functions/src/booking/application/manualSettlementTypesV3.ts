import {HttpsError} from "firebase-functions/https";

export const MANUAL_SETTLEMENT_SOURCES_V3 = [
  "NORMAL_COMPLETION", "DISPUTE_RESOLUTION", "CUSTOMER_CANCELLATION",
  "PROVIDER_CANCELLATION", "NO_SHOW",
] as const;
export type ManualSettlementSourceV3 = typeof MANUAL_SETTLEMENT_SOURCES_V3[number];
export function parseManualSettlementSourceV3(value: unknown): ManualSettlementSourceV3 {
  const source = String(value ?? "").trim().toUpperCase();
  if (!(MANUAL_SETTLEMENT_SOURCES_V3 as readonly string[]).includes(source)) {
    throw new HttpsError("failed-precondition", "Unsupported manual settlement source.");
  }
  return source as ManualSettlementSourceV3;
}
export function isCancellationSourceV3(source: unknown): boolean {
  return source === "CUSTOMER_CANCELLATION" || source === "PROVIDER_CANCELLATION";
}
export function cancellationRefundObligationIdV3(bookingId: string): string {
  return `customer_refund_cancellation_${bookingId}`;
}
export function moneyV3(value: unknown): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new HttpsError("failed-precondition", "Invalid canonical settlement amount.");
  }
  return value;
}
/** An instruction is a liability, not evidence of completed money. */
export function completedRefundPaiseV3(refund: Record<string, any> | null | undefined): number {
  if (!refund) return 0;
  if (refund.refundedAmountPaise != null) return moneyV3(refund.refundedAmountPaise);
  return ["processed", "refunded"].includes(String(refund.state).toLowerCase()) ?
    moneyV3(refund.refundAmountPaise ?? 0) : 0;
}
