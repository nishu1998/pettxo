import {computeRunwayEndsAt} from "../domain/bookingDeadlines";
import type {BookingType} from "../domain/bookingContracts";
import type {RangeBookingSelection} from "../domain/rangeBooking";
import {validateRangeBookingSelection} from "../domain/rangeBooking";
import type {SlotBookingSelection} from "../domain/slotBooking";
import {validateSlotBookingSelection} from "../domain/slotBooking";
import type {CanonicalServiceWorkingHoursSource, NormalizedWeeklyWorkingHours} from "./workingHours";
import {isServiceVerificationPaused} from "./workingHours";

export type RunwayValidationCode =
  | "INVALID_BOOKING_TYPE"
  | "INVALID_SCHEDULE"
  | "RUNWAY_NOT_SATISFIED"
  | "SERVICE_INACTIVE"
  | "SERVICE_PAUSED"
  | "PROVIDER_PAUSED"
  | "INVALID_WORKING_HOURS"
  | "INVALID_TIMEZONE"
  | "ANCHOR_MISMATCH";

export type RunwayValidationIssue = {
  code: RunwayValidationCode;
  message: string;
};

export type RunwayValidationResult =
  | {
      ok: true;
      bookingType: BookingType;
      serviceAnchorAt: Date;
      timerStartsAt: Date;
      runwayEndsAt: Date;
      issues: [];
    }
  | {
      ok: false;
      bookingType: BookingType;
      serviceAnchorAt: Date | null;
      timerStartsAt: Date;
      runwayEndsAt: Date;
      issues: RunwayValidationIssue[];
    };

function issue(code: RunwayValidationCode, message: string): RunwayValidationIssue {
  return {code, message};
}

export function isCanonicalServiceRequestable(
  service: CanonicalServiceWorkingHoursSource,
  now: Date,
): {ok: boolean; issues: RunwayValidationIssue[]} {
  const issues: RunwayValidationIssue[] = [];
  if (
    service.status !== "active" ||
    service.isActive !== true ||
    service.isDeleted === true ||
    service.isVisibleToMarketplace !== true
  ) {
    issues.push(issue("SERVICE_INACTIVE", "Service is not active and marketplace-visible."));
  }
  if (service.isPaused === true) {
    issues.push(issue("SERVICE_PAUSED", "Service is paused."));
  }
  if (isServiceVerificationPaused(service, now.getTime())) {
    issues.push(issue("PROVIDER_PAUSED", "Provider verification pause is active."));
  }
  return {ok: issues.length === 0, issues};
}

export function validateCanonicalBookingRunway(params: {
  bookingType: BookingType;
  schedule: SlotBookingSelection | RangeBookingSelection;
  timerStartsAt: Date;
  service: CanonicalServiceWorkingHoursSource;
  workingHours: NormalizedWeeklyWorkingHours | null;
}): RunwayValidationResult {
  const issues: RunwayValidationIssue[] = [];
  const runwayEndsAt = computeRunwayEndsAt(params.timerStartsAt);
  const serviceStatus = isCanonicalServiceRequestable(params.service, params.timerStartsAt);
  if (!serviceStatus.ok) issues.push(...serviceStatus.issues);
  if (!params.workingHours) {
    issues.push(issue("INVALID_WORKING_HOURS", "Working hours could not be normalized."));
  }
  if (!params.workingHours?.timezone?.trim()) {
    issues.push(issue("INVALID_TIMEZONE", "Provider timezone is missing."));
  }

  if (params.bookingType === "SLOT") {
    const schedule = params.schedule as SlotBookingSelection;
    const validation = validateSlotBookingSelection(schedule);
    if (!validation.ok) {
      issues.push(issue("INVALID_SCHEDULE", validation.issues.map((entry) => entry.code).join(",")));
      return {
        ok: false,
        bookingType: params.bookingType,
        serviceAnchorAt: null,
        timerStartsAt: params.timerStartsAt,
        runwayEndsAt,
        issues,
      };
    }
    const anchor = validation.normalizedSelection.scheduledStartAt;
    if (anchor.getTime() !== schedule.scheduledStartAt.getTime()) {
      issues.push(issue("ANCHOR_MISMATCH", "SLOT serviceAnchorAt must equal scheduledStartAt."));
    }
    if (anchor.getTime() < runwayEndsAt.getTime()) {
      issues.push(issue("RUNWAY_NOT_SATISFIED", "Service start is too early for the required runway."));
    }
    return issues.length > 0 ? {
      ok: false,
      bookingType: params.bookingType,
      serviceAnchorAt: anchor,
      timerStartsAt: params.timerStartsAt,
      runwayEndsAt,
      issues,
    } : {
      ok: true,
      bookingType: params.bookingType,
      serviceAnchorAt: anchor,
      timerStartsAt: params.timerStartsAt,
      runwayEndsAt,
      issues: [],
    };
  }

  const schedule = params.schedule as RangeBookingSelection;
  const validation = validateRangeBookingSelection(schedule);
  if (!validation.ok) {
    issues.push(issue("INVALID_SCHEDULE", validation.issues.map((entry) => entry.code).join(",")));
    return {
      ok: false,
      bookingType: params.bookingType,
      serviceAnchorAt: null,
      timerStartsAt: params.timerStartsAt,
      runwayEndsAt,
      issues,
    };
  }
  const anchor = validation.normalizedSelection.checkInDateTime;
  if (anchor.getTime() !== schedule.checkInDateTime.getTime()) {
    issues.push(issue("ANCHOR_MISMATCH", "RANGE serviceAnchorAt must equal checkInDateTime."));
  }
  if (anchor.getTime() < runwayEndsAt.getTime()) {
    issues.push(issue("RUNWAY_NOT_SATISFIED", "Check-in is too early for the required runway."));
  }
  return issues.length > 0 ? {
    ok: false,
    bookingType: params.bookingType,
    serviceAnchorAt: anchor,
    timerStartsAt: params.timerStartsAt,
    runwayEndsAt,
    issues,
  } : {
    ok: true,
    bookingType: params.bookingType,
    serviceAnchorAt: anchor,
    timerStartsAt: params.timerStartsAt,
    runwayEndsAt,
    issues: [],
  };
}
