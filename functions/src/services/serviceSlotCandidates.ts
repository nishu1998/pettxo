import {
  generateSlotWindows, normalizeServiceSchedulingMode, resolveSessionDurationMinutes,
  SERVICE_SCHEDULING_MODE_DAY_CARE, SERVICE_SCHEDULING_MODE_TWENTY_FOUR_HOURS,
} from "../serviceScheduling";

// Customer range: today through today + 30 inclusive. Dart parity is tested.
export const SERVICE_BOOKING_HORIZON_DAYS = 30;
// Cover the next midnight before the rolling worker has finished its next pass.
export const SERVICE_SLOT_COVERAGE_RESERVE_DAYS = 1;
const DAY_MS = 86400000;
const IST_MS = 330 * 60000;
const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const configKeys = ["ownerUserId", "schedulingMode", "sessionDurationMinutes", "capacity",
  "availableDays", "startMinutes", "endMinutes", "status", "isActive", "isDeleted",
  "isPaused", "isVisibleToMarketplace"];
export type ServiceSlotSource = Record<string, unknown>;
export type SlotCandidate = {
  id: string; serviceId: string; serviceOwnerId: unknown; startAtMs: number; endAtMs: number;
  dateKey: string; serviceDateKey: string; startMinutes: number; endMinutes: number;
  durationMinutes: number; capacity: number; acceptedCount: number;
  isBookable: boolean; status: string; timezone: string;
};
export function serviceSlotConfigChanged(before: ServiceSlotSource | undefined, after: ServiceSlotSource): boolean {
  return !before || configKeys.some((key) => JSON.stringify(before[key]) !== JSON.stringify(after[key]));
}
export function serviceSlotEligibilityReason(service: ServiceSlotSource): string | null {
  if (service.status !== "active") return "status_not_active";
  if (service.isActive !== true) return "inactive";
  if (service.isDeleted === true) return "deleted";
  if (service.isPaused === true) return "paused";
  if (service.isVisibleToMarketplace !== true) return "not_visible";
  return null;
}
function toInt(value: unknown, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : fallback;
}
export function serviceDateKey(timeMs: number): string {
  return new Date(timeMs + IST_MS).toISOString().slice(0, 10);
}
export function buildServiceSlotCandidates(serviceId: string, service: ServiceSlotSource, nowMs: number) {
  const local = new Date(nowMs + IST_MS);
  const midnight = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate()) - IST_MS;
  const coverageDays = SERVICE_BOOKING_HORIZON_DAYS + SERVICE_SLOT_COVERAGE_RESERVE_DAYS;
  const result = {
    coverageStartDate: serviceDateKey(midnight), coverageEndDate: serviceDateKey(midnight + coverageDays * DAY_MS),
    eligibilitySkipReason: serviceSlotEligibilityReason(service), invalidScheduleReason: null as string | null,
    candidates: [] as SlotCandidate[],
  };
  if (result.eligibilitySkipReason) return result;
  const mode = normalizeServiceSchedulingMode(service);
  const duration = resolveSessionDurationMinutes(service);
  const days = new Set(Array.isArray(service.availableDays) ? service.availableDays.map(String) : []);
  const start = Math.max(toInt(service.startMinutes, 0), 0);
  const end = Math.min(toInt(service.endMinutes, 1440), 1440);
  if (!days.size || !weekdays.some((day) => days.has(day))) result.invalidScheduleReason = "missing_or_invalid_weekdays";
  else if (duration <= 0) result.invalidScheduleReason = "invalid_duration_or_window";
  else if (start >= 1440 || end < 0) result.invalidScheduleReason = "invalid_clock_minutes";
  if (result.invalidScheduleReason) return result;
  const windows = generateSlotWindows({schedulingMode: mode, sessionDurationMinutes: duration, startMinutes: start, endMinutes: end});
  if (!windows.length) { result.invalidScheduleReason = "no_valid_slot_windows"; return result; }
  for (let offset = 0; offset <= coverageDays; offset++) {
    const dayMs = midnight + offset * DAY_MS;
    if (!days.has(weekdays[new Date(dayMs + IST_MS).getUTCDay()])) continue;
    const key = serviceDateKey(dayMs);
    for (const window of windows) {
      const startAtMs = dayMs + window.startMinutes * 60000;
      const endAtMs = mode === SERVICE_SCHEDULING_MODE_TWENTY_FOUR_HOURS ? startAtMs + window.durationMinutes * 60000 :
        window.endMinutes > window.startMinutes ? dayMs + window.endMinutes * 60000 : startAtMs + window.durationMinutes * 60000;
      const prefix = `${key}_${String(window.startMinutes).padStart(4, "0")}`;
      const id = mode === SERVICE_SCHEDULING_MODE_DAY_CARE || window.endMinutes < window.startMinutes ?
        `${prefix}_${String(window.endMinutes).padStart(4, "0")}` : mode === SERVICE_SCHEDULING_MODE_TWENTY_FOUR_HOURS ?
          `${prefix}_${String(window.durationMinutes).padStart(4, "0")}` : prefix;
      const isBookable = startAtMs - nowMs >= 3600000;
      result.candidates.push({id, serviceId, serviceOwnerId: service.ownerUserId ?? "", startAtMs, endAtMs,
        dateKey: key, serviceDateKey: key, startMinutes: window.startMinutes, endMinutes: window.endMinutes,
        durationMinutes: window.durationMinutes, capacity: Math.max(toInt(service.capacity, 1), 1),
        acceptedCount: 0, isBookable, status: isBookable ? "open" : "closed", timezone: "Asia/Kolkata"});
    }
  }
  return result;
}
