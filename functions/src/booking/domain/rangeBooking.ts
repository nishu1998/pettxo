import {type BookingType, isBookingType} from "./bookingContracts";

export type RangeBookingSelection = {
  bookingType: BookingType;
  checkInDateTime: Date;
  checkOutDateTime: Date;
  nights: number;
  pricePerNightPaise: number;
  timezone: string;
  petQuantity?: number;
  maxConcurrentPetsSnapshot?: number;
  minNights?: number;
  maxNights?: number;
};

export type RangeBookingValidationCode =
  | "INVALID_BOOKING_TYPE"
  | "INVALID_RANGE"
  | "INVALID_NIGHTS"
  | "INVALID_UNIT_PRICE"
  | "BELOW_MIN_NIGHTS"
  | "ABOVE_MAX_NIGHTS";

export type RangeBookingValidationIssue = {
  code: RangeBookingValidationCode;
  message: string;
};

export type RangeBookingValidationResult =
  | {
      ok: true;
      normalizedSelection: RangeBookingSelection;
      issues: [];
    }
  | {
      ok: false;
      normalizedSelection: null;
      issues: RangeBookingValidationIssue[];
    };

function issue(
  code: RangeBookingValidationCode,
  message: string,
): RangeBookingValidationIssue {
  return {code, message};
}

function datePartsInTimeZone(value: Date, timeZone: string): {
  year: number;
  month: number;
  day: number;
} {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const parts = formatter.formatToParts(value);
  const readPart = (type: "year" | "month" | "day") =>
    Number(parts.find((part) => part.type === type)?.value ?? "0");

  return {
    year: readPart("year"),
    month: readPart("month"),
    day: readPart("day"),
  };
}

export function calculateRangeBookingNights(params: {
  checkInDateTime: Date;
  checkOutDateTime: Date;
  timezone: string;
}): number {
  const checkIn = datePartsInTimeZone(params.checkInDateTime, params.timezone);
  const checkOut = datePartsInTimeZone(params.checkOutDateTime, params.timezone);
  const startUtc = Date.UTC(checkIn.year, checkIn.month - 1, checkIn.day);
  const endUtc = Date.UTC(checkOut.year, checkOut.month - 1, checkOut.day);
  return Math.round((endUtc - startUtc) / (24 * 60 * 60 * 1000));
}

export function validateRangeBookingSelection(
  selection: RangeBookingSelection,
): RangeBookingValidationResult {
  const issues: RangeBookingValidationIssue[] = [];

  if (!isBookingType(selection.bookingType) || selection.bookingType !== "RANGE") {
    issues.push(issue("INVALID_BOOKING_TYPE", "Range bookings must use bookingType RANGE."));
  }

  if (!(selection.checkInDateTime instanceof Date) ||
    Number.isNaN(selection.checkInDateTime.getTime()) ||
    !(selection.checkOutDateTime instanceof Date) ||
    Number.isNaN(selection.checkOutDateTime.getTime()) ||
    selection.checkInDateTime.getTime() >= selection.checkOutDateTime.getTime()) {
    issues.push(issue("INVALID_RANGE", "checkInDateTime must be before checkOutDateTime."));
  }

  if (!Number.isInteger(selection.pricePerNightPaise) || selection.pricePerNightPaise < 0) {
    issues.push(issue("INVALID_UNIT_PRICE", "pricePerNightPaise must be a non-negative integer."));
  }

  const derivedNights = calculateRangeBookingNights({
    checkInDateTime: selection.checkInDateTime,
    checkOutDateTime: selection.checkOutDateTime,
    timezone: selection.timezone,
  });

  if (derivedNights < 1 || selection.nights !== derivedNights) {
    issues.push(issue("INVALID_NIGHTS", "nights must match the authoritative calendar-date calculation."));
  }
  if (selection.minNights != null && derivedNights < selection.minNights) {
    issues.push(issue("BELOW_MIN_NIGHTS", "Selected stay is below the minimum nights."));
  }
  if (selection.maxNights != null && derivedNights > selection.maxNights) {
    issues.push(issue("ABOVE_MAX_NIGHTS", "Selected stay exceeds the maximum nights."));
  }

  if (issues.length > 0) {
    return {ok: false, normalizedSelection: null, issues};
  }

  return {
    ok: true,
    normalizedSelection: {
      ...selection,
      bookingType: "RANGE",
      checkInDateTime: new Date(selection.checkInDateTime.getTime()),
      checkOutDateTime: new Date(selection.checkOutDateTime.getTime()),
      nights: derivedNights,
    },
    issues: [],
  };
}
