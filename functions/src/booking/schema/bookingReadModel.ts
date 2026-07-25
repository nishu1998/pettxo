import {CANONICAL_BOOKING_DOCUMENT_FORMAT, CANONICAL_BOOKING_MODEL_VERSION, CANONICAL_BOOKING_SCHEMA_VERSION, parseCanonicalBookingDocumentV3, type CanonicalBookingDocumentV3} from "./bookingDocumentV3";

export type InvalidBookingReadModel = {
  source: "invalid";
  rawStatus: unknown;
  errors: Array<{code: string; message: string; path: string}>;
};

export type BookingReadModel =
  | {
      source: "canonical_v3";
      booking: CanonicalBookingDocumentV3;
    }
  | InvalidBookingReadModel;

function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value != null ? value as Record<string, unknown> : {};
}

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function isCanonicalBookingDocumentCandidate(rawValue: unknown): boolean {
  const raw = asRecord(rawValue);
  return raw.schemaVersion === CANONICAL_BOOKING_SCHEMA_VERSION &&
    asString(raw.bookingModelVersion) === CANONICAL_BOOKING_MODEL_VERSION &&
    asString(raw.documentFormat) === CANONICAL_BOOKING_DOCUMENT_FORMAT;
}

export function parseBookingReadModel(rawValue: unknown, bookingId = ""): BookingReadModel {
  if (isCanonicalBookingDocumentCandidate(rawValue)) {
    const parsed = parseCanonicalBookingDocumentV3(rawValue);
    if (!parsed.ok) {
      return {
        source: "invalid",
        rawStatus: asRecord(rawValue).state,
        errors: parsed.issues,
      };
    }
    return {
      source: "canonical_v3",
      booking: parsed.booking,
    };
  }

  return {
    source: "invalid",
    rawStatus: asRecord(rawValue).status,
    errors: [{
      code: "NON_CANONICAL_BOOKING_DOCUMENT",
      message: bookingId ?
        `Booking ${bookingId} does not match the canonical Booking Model v3.2 schema.` :
        "Booking document does not match the canonical Booking Model v3.2 schema.",
      path: "",
    }],
  };
}
