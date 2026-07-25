import {DEFAULT_PROVIDER_TIMEZONE} from "../domain/bookingConstants";

export const WEEKDAY_KEYS = [
  "sunday",
  "monday",
  "tuesday",
  "wednesday",
  "thursday",
  "friday",
  "saturday",
] as const;

export type WeekdayKey = typeof WEEKDAY_KEYS[number];

export type WorkingHoursInterval = {
  startMinutes: number;
  endMinutes: number;
};

export type NormalizedWeeklyWorkingHours = {
  timezone: string;
  days: Record<WeekdayKey, WorkingHoursInterval[]>;
  isAlwaysOpen: boolean;
  sourceSupportsSingleIntervalPerDay: boolean;
};

export type TimerStartResult = {
  timerStartsAt: Date;
  wasQueuedOutsideWorkingHours: boolean;
  nextOpeningDay: WeekdayKey | null;
  nextOpeningMinutes: number | null;
};

export type CanonicalServiceWorkingHoursSource = {
  timezone?: unknown;
  availableDays?: unknown;
  startMinutes?: unknown;
  endMinutes?: unknown;
  sameForAllDays?: unknown;
  isPaused?: unknown;
  isPausedByVerification?: unknown;
  status?: unknown;
  isActive?: unknown;
  isDeleted?: unknown;
  isVisibleToMarketplace?: unknown;
  providerVerificationStatus?: unknown;
  providerVerificationGraceEndsAt?: {toMillis(): number} | Date | null;
};

export type NormalizedWorkingHoursResult =
  | {
      ok: true;
      workingHours: NormalizedWeeklyWorkingHours;
      issues: [];
    }
  | {
      ok: false;
      workingHours: null;
      issues: string[];
    };

const LOCAL_PARTS_FORMATTER_CACHE = new Map<string, Intl.DateTimeFormat>();

function formatterFor(timeZone: string): Intl.DateTimeFormat {
  const key = timeZone.trim() || DEFAULT_PROVIDER_TIMEZONE;
  const cached = LOCAL_PARTS_FORMATTER_CACHE.get(key);
  if (cached) return cached;
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: key,
    weekday: "long",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  });
  LOCAL_PARTS_FORMATTER_CACHE.set(key, formatter);
  return formatter;
}

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asInt(value: unknown): number | null {
  if (typeof value === "number" && Number.isInteger(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number.parseInt(value.trim(), 10);
    return Number.isInteger(parsed) ? parsed : null;
  }
  return null;
}

function weekdayFromSource(raw: string): WeekdayKey | null {
  const normalized = raw.trim().toLowerCase();
  switch (normalized) {
    case "sun":
    case "sunday":
      return "sunday";
    case "mon":
    case "monday":
      return "monday";
    case "tue":
    case "tues":
    case "tuesday":
      return "tuesday";
    case "wed":
    case "wednesday":
      return "wednesday";
    case "thu":
    case "thurs":
    case "thursday":
      return "thursday";
    case "fri":
    case "friday":
      return "friday";
    case "sat":
    case "saturday":
      return "saturday";
    default:
      return null;
  }
}

function weekdayToIndex(weekday: WeekdayKey): number {
  return WEEKDAY_KEYS.indexOf(weekday);
}

function emptyWeeklyDays(): Record<WeekdayKey, WorkingHoursInterval[]> {
  return {
    sunday: [],
    monday: [],
    tuesday: [],
    wednesday: [],
    thursday: [],
    friday: [],
    saturday: [],
  };
}

export function isServiceVerificationPaused(
  service: CanonicalServiceWorkingHoursSource,
  nowMs = Date.now(),
): boolean {
  if (service.isPausedByVerification === true) return true;
  const status = asString(service.providerVerificationStatus);
  if (status === "approved") return false;
  const grace = service.providerVerificationGraceEndsAt;
  if (grace == null) return false;
  const graceMs = typeof (grace as {toMillis?: unknown}).toMillis === "function" ?
    (grace as {toMillis(): number}).toMillis() :
    (grace instanceof Date ? grace.getTime() : NaN);
  return Number.isFinite(graceMs) && graceMs <= nowMs;
}

export function normalizeServiceWorkingHours(
  service: CanonicalServiceWorkingHoursSource,
): NormalizedWorkingHoursResult {
  const timezone = asString(service.timezone) || DEFAULT_PROVIDER_TIMEZONE;
  const days = emptyWeeklyDays();
  const issues: string[] = [];
  const startMinutes = Math.max(asInt(service.startMinutes) ?? 0, 0);
  const endMinutes = Math.min(asInt(service.endMinutes) ?? 0, 24 * 60);
  const availableDaysRaw = Array.isArray(service.availableDays) ?
    service.availableDays.map((entry) => asString(entry)).filter(Boolean) :
    [];

  if (availableDaysRaw.length === 0) {
    issues.push("availableDays is empty.");
  }
  if (endMinutes <= startMinutes) {
    issues.push("endMinutes must be greater than startMinutes.");
  }

  const normalizedDays = new Set<WeekdayKey>();
  for (const rawDay of availableDaysRaw) {
    const weekday = weekdayFromSource(rawDay);
    if (!weekday) {
      issues.push(`Unsupported weekday value: ${rawDay}`);
      continue;
    }
    normalizedDays.add(weekday);
  }

  for (const weekday of normalizedDays) {
    if (endMinutes > startMinutes) {
      days[weekday] = [{startMinutes, endMinutes}];
    }
  }

  const isAlwaysOpen = normalizedDays.size === 7 && startMinutes === 0 && endMinutes === 24 * 60;

  if (issues.length > 0) {
    return {ok: false, workingHours: null, issues};
  }

  return {
    ok: true,
    workingHours: {
      timezone,
      days,
      isAlwaysOpen,
      sourceSupportsSingleIntervalPerDay: true,
    },
    issues: [],
  };
}

type LocalDateTimeParts = {
  weekday: WeekdayKey;
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
};

function localParts(date: Date, timeZone: string): LocalDateTimeParts {
  const parts = formatterFor(timeZone).formatToParts(date);
  const read = (type: Intl.DateTimeFormatPartTypes): string =>
    parts.find((entry) => entry.type === type)?.value ?? "";

  const weekday = weekdayFromSource(read("weekday"));
  if (!weekday) {
    throw new Error(`Unable to read weekday for timezone ${timeZone}.`);
  }

  return {
    weekday,
    year: Number.parseInt(read("year"), 10),
    month: Number.parseInt(read("month"), 10),
    day: Number.parseInt(read("day"), 10),
    hour: Number.parseInt(read("hour"), 10),
    minute: Number.parseInt(read("minute"), 10),
    second: Number.parseInt(read("second"), 10),
  };
}

function compareLocalDateTime(
  target: Omit<LocalDateTimeParts, "weekday" | "second">,
  actual: LocalDateTimeParts,
): number {
  const targetUtc = Date.UTC(
    target.year,
    target.month - 1,
    target.day,
    target.hour,
    target.minute,
  );
  const actualUtc = Date.UTC(
    actual.year,
    actual.month - 1,
    actual.day,
    actual.hour,
    actual.minute,
  );
  return Math.round((targetUtc - actualUtc) / (60 * 1000));
}

function resolveUtcForLocalTime(params: {
  timeZone: string;
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
}): Date {
  let guessMs = Date.UTC(
    params.year,
    params.month - 1,
    params.day,
    params.hour,
    params.minute,
  );
  for (let index = 0; index < 8; index += 1) {
    const actual = localParts(new Date(guessMs), params.timeZone);
    const diffMinutes = compareLocalDateTime(
      {
        year: params.year,
        month: params.month,
        day: params.day,
        hour: params.hour,
        minute: params.minute,
      },
      actual,
    );
    if (diffMinutes === 0) {
      return new Date(guessMs);
    }
    guessMs += diffMinutes * 60 * 1000;
  }
  return new Date(guessMs);
}

function plusLocalDays(
  local: Pick<LocalDateTimeParts, "year" | "month" | "day">,
  dayOffset: number,
): {year: number; month: number; day: number} {
  const utc = new Date(Date.UTC(local.year, local.month - 1, local.day + dayOffset));
  return {
    year: utc.getUTCFullYear(),
    month: utc.getUTCMonth() + 1,
    day: utc.getUTCDate(),
  };
}

export function computeTimerStartsAt(params: {
  requestedAt: Date;
  timezone: string;
  workingHours: NormalizedWeeklyWorkingHours;
}): TimerStartResult {
  const requestedAt = new Date(params.requestedAt.getTime());
  const timezone = params.timezone.trim() || DEFAULT_PROVIDER_TIMEZONE;
  const schedule = params.workingHours;

  if (schedule.isAlwaysOpen) {
    return {
      timerStartsAt: requestedAt,
      wasQueuedOutsideWorkingHours: false,
      nextOpeningDay: localParts(requestedAt, timezone).weekday,
      nextOpeningMinutes: null,
    };
  }

  const localRequested = localParts(requestedAt, timezone);
  const localMinutes = localRequested.hour * 60 + localRequested.minute;
  const todayIntervals = schedule.days[localRequested.weekday] ?? [];

  for (const interval of todayIntervals) {
    if (localMinutes >= interval.startMinutes && localMinutes < interval.endMinutes) {
      return {
        timerStartsAt: requestedAt,
        wasQueuedOutsideWorkingHours: false,
        nextOpeningDay: localRequested.weekday,
        nextOpeningMinutes: interval.startMinutes,
      };
    }
    if (localMinutes < interval.startMinutes) {
      const timerStartsAt = resolveUtcForLocalTime({
        timeZone: timezone,
        year: localRequested.year,
        month: localRequested.month,
        day: localRequested.day,
        hour: Math.floor(interval.startMinutes / 60),
        minute: interval.startMinutes % 60,
      });
      return {
        timerStartsAt,
        wasQueuedOutsideWorkingHours: true,
        nextOpeningDay: localRequested.weekday,
        nextOpeningMinutes: interval.startMinutes,
      };
    }
  }

  for (let offset = 1; offset <= 8; offset += 1) {
    const localDate = plusLocalDays(localRequested, offset);
    const weekday = WEEKDAY_KEYS[(weekdayToIndex(localRequested.weekday) + offset) % 7];
    const intervals = schedule.days[weekday] ?? [];
    if (intervals.length === 0) continue;
    const firstInterval = intervals[0];
    const timerStartsAt = resolveUtcForLocalTime({
      timeZone: timezone,
      year: localDate.year,
      month: localDate.month,
      day: localDate.day,
      hour: Math.floor(firstInterval.startMinutes / 60),
      minute: firstInterval.startMinutes % 60,
    });
    return {
      timerStartsAt,
      wasQueuedOutsideWorkingHours: true,
      nextOpeningDay: weekday,
      nextOpeningMinutes: firstInterval.startMinutes,
    };
  }

  return {
    timerStartsAt: requestedAt,
    wasQueuedOutsideWorkingHours: false,
    nextOpeningDay: null,
    nextOpeningMinutes: null,
  };
}
