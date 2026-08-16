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

export const CANONICAL_PAYMENT_METHODS = [
  "checkout",
  "qr",
] as const;

export type CanonicalPaymentMethod = typeof CANONICAL_PAYMENT_METHODS[number];

export const CANONICAL_QR_STATES = [
  "ACTIVE",
  "PAYMENT_CAPTURED",
  "CONFIRMED",
  "CLOSED",
  "EXPIRED",
  "SUPERSEDED",
  "REFUND_REQUIRED",
] as const;

export type CanonicalQrState = typeof CANONICAL_QR_STATES[number];

export function isCanonicalPaymentState(value: unknown): value is CanonicalPaymentState {
  return typeof value === "string" &&
    (CANONICAL_PAYMENT_STATES as readonly string[]).includes(value);
}

export function isPaymentVerificationSource(value: unknown): value is PaymentVerificationSource {
  return typeof value === "string" &&
    (PAYMENT_VERIFICATION_SOURCES as readonly string[]).includes(value);
}

export function isCanonicalPaymentMethod(value: unknown): value is CanonicalPaymentMethod {
  return typeof value === "string" &&
    (CANONICAL_PAYMENT_METHODS as readonly string[]).includes(value);
}

export function isCanonicalQrState(value: unknown): value is CanonicalQrState {
  return typeof value === "string" &&
    (CANONICAL_QR_STATES as readonly string[]).includes(value);
}
