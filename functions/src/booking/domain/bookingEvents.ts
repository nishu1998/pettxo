import {isBookingActor, type BookingActor} from "./bookingContracts";

export const CANONICAL_BOOKING_EVENTS = [
  "requested",
  "timer_started",
  "notified",
  "viewed_by_provider",
  "accepted",
  "declined",
  "expired",
  "payment_started",
  "paid",
  "payment_abandoned",
  "refund_required",
  "refund_pending",
  "otp_entered",
  "no_show",
  "service_completed",
  "review_submitted",
  "dispute_created",
  "booking_finalized",
  "payout_ready",
  "service_ended",
  "cancelled",
  "capacity_released",
  "refunded",
  "refund_failed",
  "payout_released",
  "disputed",
  "completed_final",
] as const;

export type CanonicalBookingEvent = typeof CANONICAL_BOOKING_EVENTS[number];

export type BookingEventRecord = {
  bookingId: string;
  event: CanonicalBookingEvent;
  actor: BookingActor;
  at: Date;
  meta: Record<string, unknown>;
  schemaVersion: 1;
};

export function isCanonicalBookingEvent(value: unknown): value is CanonicalBookingEvent {
  return typeof value === "string" &&
    (CANONICAL_BOOKING_EVENTS as readonly string[]).includes(value);
}

export function isBookingEventRecord(value: unknown): value is BookingEventRecord {
  if (typeof value !== "object" || value == null) return false;
  const event = value as Partial<BookingEventRecord>;
  return typeof event.bookingId === "string" &&
    event.bookingId.trim().length > 0 &&
    isCanonicalBookingEvent(event.event) &&
    isBookingActor(event.actor) &&
    event.at instanceof Date &&
    !Number.isNaN(event.at.getTime()) &&
    typeof event.meta === "object" &&
    event.meta != null &&
    event.schemaVersion === 1;
}
