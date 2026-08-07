export const SERVICE_SCHEDULING_MODE_FIXED_DURATION = "fixedDuration";
export const SERVICE_SCHEDULING_MODE_DAY_CARE = "dayCare";
export const SERVICE_SCHEDULING_MODE_OVERNIGHT = "overnight";
export const SERVICE_SCHEDULING_MODE_TWENTY_FOUR_HOURS = "twentyFourHours";

type ServiceSchedulingInput = {
  schedulingMode?: unknown;
  sessionDurationMinutes?: unknown;
  startMinutes?: unknown;
  endMinutes?: unknown;
};

export type GeneratedSlotWindow = {
  startMinutes: number;
  endMinutes: number;
  durationMinutes: number;
};

function asInt(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isInteger(value) ? value : fallback;
}

export function normalizeServiceSchedulingMode(input: ServiceSchedulingInput): string {
  const rawMode = typeof input.schedulingMode === "string" ? input.schedulingMode.trim() : "";
  if (rawMode === SERVICE_SCHEDULING_MODE_DAY_CARE || rawMode.toLowerCase() === "wholeday") {
    return SERVICE_SCHEDULING_MODE_DAY_CARE;
  }
  if (rawMode === SERVICE_SCHEDULING_MODE_OVERNIGHT) {
    return SERVICE_SCHEDULING_MODE_OVERNIGHT;
  }
  if (rawMode === SERVICE_SCHEDULING_MODE_TWENTY_FOUR_HOURS) {
    return SERVICE_SCHEDULING_MODE_TWENTY_FOUR_HOURS;
  }
  if (rawMode === SERVICE_SCHEDULING_MODE_FIXED_DURATION) {
    return SERVICE_SCHEDULING_MODE_FIXED_DURATION;
  }
  const durationMinutes = asInt(input.sessionDurationMinutes, 0);
  if (durationMinutes <= 0 || durationMinutes >= 24 * 60) {
    return SERVICE_SCHEDULING_MODE_DAY_CARE;
  }
  return SERVICE_SCHEDULING_MODE_FIXED_DURATION;
}

export function resolveSessionDurationMinutes(input: ServiceSchedulingInput): number {
  const startMinutes = asInt(input.startMinutes, 0);
  const endMinutes = asInt(input.endMinutes, 0);
  const configuredDuration = asInt(input.sessionDurationMinutes, 0);
  const schedulingMode = normalizeServiceSchedulingMode(input);
  if (schedulingMode === SERVICE_SCHEDULING_MODE_TWENTY_FOUR_HOURS) {
    return 24 * 60;
  }
  if (schedulingMode === SERVICE_SCHEDULING_MODE_OVERNIGHT) {
    if (endMinutes >= startMinutes) return 0;
    const overnightDuration = (24 * 60 - startMinutes) + endMinutes;
    return overnightDuration > 0 && overnightDuration < 24 * 60 ? overnightDuration : 0;
  }
  if (schedulingMode === SERVICE_SCHEDULING_MODE_DAY_CARE) {
    return endMinutes > startMinutes ? endMinutes - startMinutes : 0;
  }
  return configuredDuration > 0 ? configuredDuration : 0;
}

export function generateSlotWindows(input: ServiceSchedulingInput): GeneratedSlotWindow[] {
  const startMinutes = Math.max(asInt(input.startMinutes, 0), 0);
  const schedulingMode = normalizeServiceSchedulingMode(input);
  const rawEndMinutes = asInt(input.endMinutes, 0);
  const endMinutes = schedulingMode === SERVICE_SCHEDULING_MODE_OVERNIGHT ?
    Math.max(Math.min(rawEndMinutes, 24 * 60), 0) :
    Math.min(rawEndMinutes, 24 * 60);
  const durationMinutes = resolveSessionDurationMinutes(input);
  if (durationMinutes <= 0) return [];

  if (schedulingMode === SERVICE_SCHEDULING_MODE_TWENTY_FOUR_HOURS) {
    return [{
      startMinutes,
      endMinutes: startMinutes,
      durationMinutes,
    }];
  }

  if (schedulingMode === SERVICE_SCHEDULING_MODE_OVERNIGHT) {
    if (endMinutes >= startMinutes) return [];
    return [{
      startMinutes,
      endMinutes,
      durationMinutes,
    }];
  }

  if (endMinutes <= startMinutes) return [];

  if (schedulingMode === SERVICE_SCHEDULING_MODE_DAY_CARE) {
    return [{
      startMinutes,
      endMinutes,
      durationMinutes,
    }];
  }

  const slots: GeneratedSlotWindow[] = [];
  for (let cursor = startMinutes; cursor + durationMinutes <= endMinutes; cursor += durationMinutes) {
    slots.push({
      startMinutes: cursor,
      endMinutes: cursor + durationMinutes,
      durationMinutes,
    });
  }
  return slots;
}
