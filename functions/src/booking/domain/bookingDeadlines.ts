import {
  ACCEPT_WINDOW_MS,
  PAY_WINDOW_MS,
  RUNWAY_MS,
} from "./bookingConstants";

export type BookingAnchor = "scheduledStartAt" | "checkInDateTime";

export type FutureWorkingHoursCalculatorInput = {
  requestedAt: Date;
  providerTimezone: string;
};

export type FutureWorkingHoursCalculator = (
  input: FutureWorkingHoursCalculatorInput,
) => Date;

function addMs(anchor: Date, durationMs: number): Date {
  return new Date(anchor.getTime() + durationMs);
}

export function computeAcceptDeadlineAt(timerStartsAt: Date): Date {
  return addMs(timerStartsAt, ACCEPT_WINDOW_MS);
}

export function computePayDeadlineAt(respondedAt: Date): Date {
  return addMs(respondedAt, PAY_WINDOW_MS);
}

export function computeRunwayEndsAt(timerStartsAt: Date): Date {
  return addMs(timerStartsAt, RUNWAY_MS);
}

export function isAnchorBookable(anchorAt: Date, timerStartsAt: Date): boolean {
  return anchorAt.getTime() >= computeRunwayEndsAt(timerStartsAt).getTime();
}
