import {DEFAULT_PROVIDER_TIMEZONE} from "../domain/bookingConstants";
import {
  normalizeServiceSchedulingMode,
  SERVICE_SCHEDULING_MODE_DAY_CARE,
  SERVICE_SCHEDULING_MODE_FIXED_DURATION,
  SERVICE_SCHEDULING_MODE_OVERNIGHT,
  SERVICE_SCHEDULING_MODE_TWENTY_FOUR_HOURS,
} from "../../serviceScheduling";

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

export type WorkingHoursIssueCode =
  | "INVALID_TIMEZONE"
  | "INVALID_WORKING_HOURS";

export type WorkingHoursIssue = {
  code: WorkingHoursIssueCode;
  message: string;
};

export type CanonicalServiceWorkingHoursSource = {
  timezone?: unknown;
  availableDays?: unknown;
  schedulingMode?: unknown;
  sessionDurationMinutes?: unknown;
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
      issues: WorkingHoursIssue[];
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

function issue(
  code: WorkingHoursIssueCode,
  message: string,
): WorkingHoursIssue {
  return {code, message};
}

function isTruthyFlag(value: unknown): boolean {
  if (value === true) return true;
  if (typeof value === "number") return value > 0;
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    return normalized === "true" || normalized === "yes" || normalized === "1";
  }
  return false;
}

function isValidClockStartMinutes(value: number | null): value is number {
  return value != null && value >= 0 && value < 24 * 60;
}

function isValidClockEndMinutes(value: number | null): value is number {
  return value != null && value >= 0 && value <= 24 * 60;
}

function isValidTimeZone(value: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", {timeZone: value}).format(new Date());
    return true;
  } catch (_) {
    return false;
  }
}

function nextWeekday(weekday: WeekdayKey): WeekdayKey {
  return WEEKDAY_KEYS[(weekdayToIndex(weekday) + 1) % 7];
}

type ParsedAvailableDay = {
  weekday: WeekdayKey;
  startMinutes: number | null;
  endMinutes: number | null;
};

function pushParsedAvailableDay(
  target: ParsedAvailableDay[],
  rawDay: unknown,
  options?: {
    startMinutes?: unknown;
    endMinutes?: unknown;
    enabled?: unknown;
  },
): void {
  const weekday = weekdayFromSource(asString(rawDay));
  if (!weekday) return;
  if (options?.enabled === false) return;
  if (options?.enabled != null && !isTruthyFlag(options.enabled) && options.enabled !== true) {
    return;
  }
  target.push({
    weekday,
    startMinutes: asInt(options?.startMinutes),
    endMinutes: asInt(options?.endMinutes),
  });
}

function parseAvailableDays(value: unknown): ParsedAvailableDay[] {
  const parsed: ParsedAvailableDay[] = [];
  if (Array.isArray(value)) {
    for (const entry of value) {
      if (typeof entry === "string") {
        pushParsedAvailableDay(parsed, entry);
        continue;
      }
      if (typeof entry === "object" && entry != null) {
        const record = entry as Record<string, unknown>;
        pushParsedAvailableDay(parsed, record.day ?? record.weekday ?? record.key, {
          startMinutes: record.startMinutes,
          endMinutes: record.endMinutes,
          enabled: record.enabled ?? true,
        });
      }
    }
    return parsed;
  }

  if (typeof value === "string" && value.trim()) {
    for (const token of value.split(",")) {
      pushParsedAvailableDay(parsed, token);
    }
    return parsed;
  }

  if (typeof value === "object" && value != null) {
    for (const [key, rawEntry] of Object.entries(value as Record<string, unknown>)) {
      if (typeof rawEntry === "object" && rawEntry != null) {
        const record = rawEntry as Record<string, unknown>;
        pushParsedAvailableDay(parsed, key, {
          startMinutes: record.startMinutes,
          endMinutes: record.endMinutes,
          enabled: record.enabled ?? true,
        });
        continue;
      }
      pushParsedAvailableDay(parsed, key, {enabled: rawEntry});
    }
  }

  return parsed;
}

function pushInterval(
  days: Record<WeekdayKey, WorkingHoursInterval[]>,
  weekday: WeekdayKey,
  startMinutes: number,
  endMinutes: number,
): void {
  if (startMinutes < 0 || endMinutes > 24 * 60 || endMinutes <= startMinutes) {
    return;
  }
  days[weekday].push({startMinutes, endMinutes});
}

function normalizeIntervals(
  intervals: WorkingHoursInterval[],
): WorkingHoursInterval[] {
  if (intervals.length <= 1) return intervals;
  const sorted = [...intervals].sort((left, right) =>
    left.startMinutes - right.startMinutes,
  );
  const merged: WorkingHoursInterval[] = [];
  for (const interval of sorted) {
    const previous = merged[merged.length - 1];
    if (!previous || interval.startMinutes > previous.endMinutes) {
      merged.push({...interval});
      continue;
    }
    previous.endMinutes = Math.max(previous.endMinutes, interval.endMinutes);
  }
  return merged;
}

function dayIsFullyCovered(intervals: WorkingHoursInterval[]): boolean {
  const normalized = normalizeIntervals(intervals);
  if (normalized.length === 0 || normalized[0].startMinutes > 0) {
    return false;
  }
  let coveredUntil = normalized[0].endMinutes;
  if (coveredUntil >= 24 * 60) return true;
  for (let index = 1; index < normalized.length; index += 1) {
    const interval = normalized[index];
    if (interval.startMinutes > coveredUntil) return false;
    coveredUntil = Math.max(coveredUntil, interval.endMinutes);
    if (coveredUntil >= 24 * 60) return true;
  }
  return coveredUntil >= 24 * 60;
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
  const issues: WorkingHoursIssue[] = [];
  const schedulingMode = normalizeServiceSchedulingMode({
    schedulingMode: service.schedulingMode,
    sessionDurationMinutes: asInt(service.sessionDurationMinutes) ?? 0,
  });
  const availableDays = parseAvailableDays(service.availableDays);
  const globalStartMinutes = asInt(service.startMinutes);
  const globalEndMinutes = asInt(service.endMinutes);

  if (!timezone.trim() || !isValidTimeZone(timezone)) {
    issues.push(
      issue(
        "INVALID_TIMEZONE",
        `Unsupported timezone: ${timezone || "<empty>"}.`,
      ),
    );
  }
  if (availableDays.length === 0) {
    issues.push(issue("INVALID_WORKING_HOURS", "availableDays is empty."));
  }

  for (const entry of availableDays) {
    const startMinutes = entry.startMinutes ?? globalStartMinutes;
    const endMinutes = entry.endMinutes ?? globalEndMinutes;
    switch (schedulingMode) {
      case SERVICE_SCHEDULING_MODE_TWENTY_FOUR_HOURS: {
        if (!isValidClockStartMinutes(startMinutes)) {
          issues.push(
            issue(
              "INVALID_WORKING_HOURS",
              `startMinutes is invalid for ${entry.weekday}.`,
            ),
          );
          break;
        }
        pushInterval(days, entry.weekday, startMinutes, 24 * 60);
        pushInterval(days, nextWeekday(entry.weekday), 0, startMinutes);
        break;
      }
      case SERVICE_SCHEDULING_MODE_OVERNIGHT: {
        if (!isValidClockStartMinutes(startMinutes)) {
          issues.push(
            issue(
              "INVALID_WORKING_HOURS",
              `startMinutes is invalid for ${entry.weekday}.`,
            ),
          );
          break;
        }
        if (!isValidClockEndMinutes(endMinutes)) {
          issues.push(
            issue(
              "INVALID_WORKING_HOURS",
              `endMinutes is invalid for ${entry.weekday}.`,
            ),
          );
          break;
        }
        if (endMinutes >= startMinutes) {
          issues.push(
            issue(
              "INVALID_WORKING_HOURS",
              `Overnight hours for ${entry.weekday} must end on the next day.`,
            ),
          );
          break;
        }
        pushInterval(days, entry.weekday, startMinutes, 24 * 60);
        pushInterval(days, nextWeekday(entry.weekday), 0, endMinutes);
        break;
      }
      case SERVICE_SCHEDULING_MODE_DAY_CARE:
      case SERVICE_SCHEDULING_MODE_FIXED_DURATION:
      default: {
        if (!isValidClockStartMinutes(startMinutes)) {
          issues.push(
            issue(
              "INVALID_WORKING_HOURS",
              `startMinutes is invalid for ${entry.weekday}.`,
            ),
          );
          break;
        }
        if (!isValidClockEndMinutes(endMinutes)) {
          issues.push(
            issue(
              "INVALID_WORKING_HOURS",
              `endMinutes is invalid for ${entry.weekday}.`,
            ),
          );
          break;
        }
        if (endMinutes <= startMinutes) {
          issues.push(
            issue(
              "INVALID_WORKING_HOURS",
              `endMinutes must be greater than startMinutes for ${entry.weekday}.`,
            ),
          );
          break;
        }
        pushInterval(days, entry.weekday, startMinutes, endMinutes);
        break;
      }
    }
  }

  for (const weekday of WEEKDAY_KEYS) {
    days[weekday] = normalizeIntervals(days[weekday]);
  }

  const isAlwaysOpen = WEEKDAY_KEYS.every((weekday) => dayIsFullyCovered(days[weekday]));

  if (issues.length > 0) {
    return {ok: false, workingHours: null, issues};
  }

  return {
    ok: true,
    workingHours: {
      timezone,
      days,
      isAlwaysOpen,
      sourceSupportsSingleIntervalPerDay: WEEKDAY_KEYS.every(
        (weekday) => days[weekday].length <= 1,
      ),
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
