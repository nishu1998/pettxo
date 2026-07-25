export const BOOKING_TYPES = ["SLOT", "RANGE"] as const;
export type BookingType = typeof BOOKING_TYPES[number];

export const CANONICAL_BOOKING_STATES = [
  "REQUESTED",
  "PENDING_PROVIDER",
  "ACCEPTED_AWAITING_PAYMENT",
  "CONFIRMED",
  "IN_PROGRESS",
  "COMPLETED_PENDING_REVIEW",
  "COMPLETED_FINAL",
  "DECLINED",
  "EXPIRED",
  "PAYMENT_EXPIRED",
  "CANCELLED_BY_PARENT",
  "CANCELLED",
  "DISPUTED",
  "SERVICE_NOT_STARTED",
  "NO_SHOW",
] as const;
export type CanonicalBookingState = typeof CANONICAL_BOOKING_STATES[number];

export const BOOKING_ACTORS = [
  "parent",
  "provider",
  "system",
  "admin",
  "payment_gateway",
] as const;
export type BookingActor = typeof BOOKING_ACTORS[number];

export const PROVIDER_RESPONSE_TYPES = ["accept", "decline", "expired"] as const;
export type ProviderResponseType = typeof PROVIDER_RESPONSE_TYPES[number];

export const BOOKING_CANCELLATION_ACTORS = [
  "parent",
  "provider",
  "system",
  "admin",
] as const;
export type BookingCancellationActor = typeof BOOKING_CANCELLATION_ACTORS[number];

export const BOOKING_CANCELLATION_TYPES = [
  "parent_requested",
  "provider_requested",
  "system_expired",
  "payment_expired",
  "service_not_started",
  "no_show",
  "dispute_resolution",
] as const;
export type BookingCancellationType = typeof BOOKING_CANCELLATION_TYPES[number];

export function isBookingType(value: unknown): value is BookingType {
  return typeof value === "string" &&
    (BOOKING_TYPES as readonly string[]).includes(value);
}

export function isCanonicalBookingState(value: unknown): value is CanonicalBookingState {
  return typeof value === "string" &&
    (CANONICAL_BOOKING_STATES as readonly string[]).includes(value);
}

export function isBookingActor(value: unknown): value is BookingActor {
  return typeof value === "string" &&
    (BOOKING_ACTORS as readonly string[]).includes(value);
}
