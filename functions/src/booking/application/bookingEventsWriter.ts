import type {BookingActor} from "../domain/bookingContracts";
import type {BookingEventRecord, CanonicalBookingEvent} from "../domain/bookingEvents";

export type BookingEventWritePlan = {
  eventId: string;
  record: BookingEventRecord;
};

export function buildBookingEventPlan(params: {
  bookingId: string;
  event: CanonicalBookingEvent;
  actor: BookingActor;
  at: Date;
  meta?: Record<string, unknown>;
}): BookingEventWritePlan {
  return {
    eventId: params.event,
    record: {
      bookingId: params.bookingId,
      event: params.event,
      actor: params.actor,
      at: new Date(params.at.getTime()),
      meta: {...(params.meta ?? {})},
      schemaVersion: 1,
    },
  };
}
