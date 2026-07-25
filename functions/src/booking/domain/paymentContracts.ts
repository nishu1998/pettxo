export const CANONICAL_PAYMENT_STATES = [
  "NOT_STARTED",
  "ORDER_CREATING",
  "ORDER_CREATED",
  "CHECKOUT_OPENED",
  "CAPTURE_REPORTED",
  "CONFIRMING",
  "CONFIRMED",
  "CAPTURED_REQUIRES_RECONCILIATION",
  "FAILED",
  "EXPIRED",
  "REFUND_REQUIRED",
  "REFUND_PENDING",
  "REFUNDED",
] as const;

export type CanonicalPaymentState = typeof CANONICAL_PAYMENT_STATES[number];

export const PAYMENT_VERIFICATION_SOURCES = [
  "callable",
  "webhook",
  "reconciliation",
  "zero_payable",
] as const;

export type PaymentVerificationSource = typeof PAYMENT_VERIFICATION_SOURCES[number];

export function isCanonicalPaymentState(value: unknown): value is CanonicalPaymentState {
  return typeof value === "string" &&
    (CANONICAL_PAYMENT_STATES as readonly string[]).includes(value);
}

export function isPaymentVerificationSource(value: unknown): value is PaymentVerificationSource {
  return typeof value === "string" &&
    (PAYMENT_VERIFICATION_SOURCES as readonly string[]).includes(value);
}
