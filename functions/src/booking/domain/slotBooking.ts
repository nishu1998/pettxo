import {isBookingType, type BookingType} from "./bookingContracts";

export type SlotBookingValidationCode =
  | "INVALID_SLOT_SELECTION"
  | "EMPTY_SELECTION"
  | "INVALID_BOOKING_TYPE"
  | "DUPLICATE_SLOT_SELECTION"
  | "INVALID_SLOT_RANGE"
  | "NON_CONTIGUOUS_DAILY_SLOTS"
  | "OVERLAPPING_BOOKING_SEGMENTS"
  | "MIXED_SERVICE_SLOT_SELECTION"
  | "MIXED_PROVIDER_SLOT_SELECTION"
  | "MIXED_TIMEZONE"
  | "NON_CONSECUTIVE_SERVICE_DATES"
  | "TOO_MANY_SERVICE_DAYS"
  | "INVALID_SLOT_COUNT"
  | "INVALID_TOTAL_DURATION"
  | "INVALID_SCHEDULE_BOUNDS"
  | "INVALID_UNIT_PRICE"
  | "MIXED_SCHEDULING_MODE";

export type SlotBookingValidationIssue = {
  code: SlotBookingValidationCode;
  message: string;
  slotId?: string;
};

export type SlotSegment = {
  slotId: string;
  serviceId: string;
  providerId: string;
  timezone: string;
  dateKey: string;
  serviceDateKey?: string;
  startAt: Date;
  endAt: Date;
  durationMinutes: number;
  unitPricePaise: number;
  schedulingMode?: string;
};

export type SlotBookingScheduleSegment = {
  serviceDateKey: string;
  slotIds: string[];
  startAt: Date;
  endAt: Date;
  durationMinutes: number;
  schedulingMode: string;
};

export type SlotBookingSelection = {
  bookingType: BookingType;
  slots: SlotSegment[];
  slotCount: number;
  scheduledStartAt: Date;
  scheduledEndAt: Date;
  totalDurationMinutes: number;
  segments?: SlotBookingScheduleSegment[];
  firstSegmentEndAt?: Date;
  finalEndAt?: Date;
  serviceDayCount?: number;
  segmentCount?: number;
};

export type SlotBookingValidationResult =
  | {
      ok: true;
      normalizedSelection: SlotBookingSelection;
      issues: [];
    }
  | {
      ok: false;
      normalizedSelection: null;
      issues: SlotBookingValidationIssue[];
    };

function issue(
  code: SlotBookingValidationCode,
  message: string,
  slotId?: string,
): SlotBookingValidationIssue {
  return {code, message, slotId};
}

function asDate(value: Date): Date {
  return new Date(value.getTime());
}

function normalizeSchedulingMode(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function formatDateKeyInTimezone(date: Date, timezone: string): string {
  try {
    const formatter = new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone || "UTC",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
    const parts = formatter.formatToParts(date);
    const year = parts.find((part) => part.type === "year")?.value ?? "1970";
    const month = parts.find((part) => part.type === "month")?.value ?? "01";
    const day = parts.find((part) => part.type === "day")?.value ?? "01";
    return `${year}-${month}-${day}`;
  } catch (_) {
    return date.toISOString().slice(0, 10);
  }
}

function parseDateKeyParts(value: string): {year: number; month: number; day: number} | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.trim());
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (!Number.isInteger(year) || !Number.isInteger(month) || !Number.isInteger(day)) {
    return null;
  }
  return {year, month, day};
}

function dateKeyOrdinal(value: string): number | null {
  const parts = parseDateKeyParts(value);
  if (!parts) return null;
  return Math.trunc(Date.UTC(parts.year, parts.month - 1, parts.day) / 86400000);
}

function resolveAuthoritativeServiceDateKey(slot: SlotSegment): string {
  const explicitServiceDateKey = typeof slot.serviceDateKey === "string" ? slot.serviceDateKey.trim() : "";
  if (explicitServiceDateKey) return explicitServiceDateKey;
  const compatibilityDateKey = slot.dateKey.trim();
  if (compatibilityDateKey) return compatibilityDateKey;
  return formatDateKeyInTimezone(slot.startAt, slot.timezone);
}

function cloneScheduleSegment(segment: SlotBookingScheduleSegment): SlotBookingScheduleSegment {
  return {
    serviceDateKey: segment.serviceDateKey,
    slotIds: [...segment.slotIds],
    startAt: asDate(segment.startAt),
    endAt: asDate(segment.endAt),
    durationMinutes: segment.durationMinutes,
    schedulingMode: segment.schedulingMode,
  };
}

export function validateSlotBookingSelection(
  selection: SlotBookingSelection,
): SlotBookingValidationResult {
  const issues: SlotBookingValidationIssue[] = [];

  if (!isBookingType(selection.bookingType) || selection.bookingType !== "SLOT") {
    issues.push(issue("INVALID_BOOKING_TYPE", "Slot bookings must use bookingType SLOT."));
  }

  if (!Array.isArray(selection.slots) || selection.slots.length === 0) {
    issues.push(issue("EMPTY_SELECTION", "At least one slot is required."));
  }

  const sortedSlots = [...selection.slots].sort(
    (left, right) => left.startAt.getTime() - right.startAt.getTime(),
  );
  const normalizedSlots: SlotSegment[] = [];
  const slotsByServiceDateKey = new Map<string, SlotSegment[]>();

  const seenSlotIds = new Set<string>();
  let totalDurationMinutes = 0;
  let firstServiceId = "";
  let firstProviderId = "";
  let firstTimezone = "";
  let firstSchedulingMode = "";

  for (const slot of sortedSlots) {
    if (!slot.slotId.trim()) {
      issues.push(issue("INVALID_SLOT_SELECTION", "Slot ID is required.", slot.slotId));
    }
    if (seenSlotIds.has(slot.slotId)) {
      issues.push(issue("DUPLICATE_SLOT_SELECTION", "Duplicate slot IDs are invalid.", slot.slotId));
    }
    seenSlotIds.add(slot.slotId);

    if (!(slot.startAt instanceof Date) || Number.isNaN(slot.startAt.getTime()) ||
      !(slot.endAt instanceof Date) || Number.isNaN(slot.endAt.getTime()) ||
      slot.startAt.getTime() >= slot.endAt.getTime()) {
      issues.push(issue("INVALID_SLOT_RANGE", "Each slot must have startAt < endAt.", slot.slotId));
      continue;
    }

    if (!Number.isInteger(slot.unitPricePaise) || slot.unitPricePaise < 0) {
      issues.push(issue("INVALID_UNIT_PRICE", "Slot unitPricePaise must be a non-negative integer.", slot.slotId));
    }

    const derivedDurationMinutes = Math.round(
      (slot.endAt.getTime() - slot.startAt.getTime()) / 60000,
    );
    if (derivedDurationMinutes !== slot.durationMinutes) {
      issues.push(issue("INVALID_TOTAL_DURATION", "Slot durationMinutes must match its timestamps.", slot.slotId));
    }
    totalDurationMinutes += derivedDurationMinutes;

    if (!firstServiceId) firstServiceId = slot.serviceId;
    if (!firstProviderId) firstProviderId = slot.providerId;
    if (!firstTimezone) firstTimezone = slot.timezone;
    const schedulingMode = normalizeSchedulingMode(slot.schedulingMode);
    if (!firstSchedulingMode && schedulingMode) firstSchedulingMode = schedulingMode;

    if (slot.serviceId !== firstServiceId) {
      issues.push(issue("MIXED_SERVICE_SLOT_SELECTION", "All selected slots must belong to the same service.", slot.slotId));
    }
    if (slot.providerId !== firstProviderId) {
      issues.push(issue("MIXED_PROVIDER_SLOT_SELECTION", "All selected slots must belong to the same provider.", slot.slotId));
    }
    if (slot.timezone !== firstTimezone) {
      issues.push(issue("MIXED_TIMEZONE", "All selected slots must use the same timezone.", slot.slotId));
    }
    if (firstSchedulingMode && schedulingMode && schedulingMode !== firstSchedulingMode) {
      issues.push(issue("MIXED_SCHEDULING_MODE", "All selected slots must use the same scheduling mode.", slot.slotId));
    }

    const serviceDateKey = resolveAuthoritativeServiceDateKey(slot);
    const normalizedSlot: SlotSegment = {
      ...slot,
      dateKey: serviceDateKey,
      serviceDateKey,
      schedulingMode,
      startAt: asDate(slot.startAt),
      endAt: asDate(slot.endAt),
      durationMinutes: derivedDurationMinutes,
    };
    normalizedSlots.push(normalizedSlot);
    const grouped = slotsByServiceDateKey.get(serviceDateKey) ?? [];
    grouped.push(normalizedSlot);
    slotsByServiceDateKey.set(serviceDateKey, grouped);
  }

  if (selection.slotCount !== selection.slots.length) {
    issues.push(issue("INVALID_SLOT_COUNT", "slotCount must equal slots.length."));
  }

  const sortedDateKeys = [...slotsByServiceDateKey.keys()].sort();
  if (sortedDateKeys.length > 10) {
    issues.push(issue("TOO_MANY_SERVICE_DAYS", "A booking can include at most 10 consecutive service start dates."));
  }

  for (let index = 1; index < sortedDateKeys.length; index += 1) {
    const previousOrdinal = dateKeyOrdinal(sortedDateKeys[index - 1]);
    const currentOrdinal = dateKeyOrdinal(sortedDateKeys[index]);
    if (previousOrdinal == null || currentOrdinal == null || currentOrdinal - previousOrdinal !== 1) {
      issues.push(issue("NON_CONSECUTIVE_SERVICE_DATES", "Selected service dates must be consecutive calendar dates."));
      break;
    }
  }

  const derivedSegments: SlotBookingScheduleSegment[] = [];
  for (const serviceDateKey of sortedDateKeys) {
    const daySlots = [...(slotsByServiceDateKey.get(serviceDateKey) ?? [])].sort(
      (left, right) => left.startAt.getTime() - right.startAt.getTime(),
    );
    let previousDaySlot: SlotSegment | null = null;
    let dayDurationMinutes = 0;
    for (const slot of daySlots) {
      dayDurationMinutes += slot.durationMinutes;
      if (previousDaySlot != null) {
        const previousEndMs = previousDaySlot.endAt.getTime();
        const currentStartMs = slot.startAt.getTime();
        if (currentStartMs < previousEndMs) {
          issues.push(issue(
            "OVERLAPPING_BOOKING_SEGMENTS",
            "Selected slots within a service day cannot overlap.",
            slot.slotId,
          ));
        } else if (currentStartMs !== previousEndMs) {
          issues.push(issue(
            "NON_CONTIGUOUS_DAILY_SLOTS",
            "Selected slots within one service day must remain contiguous.",
            slot.slotId,
          ));
        }
      }
      previousDaySlot = slot;
    }
    if (daySlots.length > 0) {
      derivedSegments.push({
        serviceDateKey,
        slotIds: daySlots.map((slot) => slot.slotId),
        startAt: asDate(daySlots[0].startAt),
        endAt: asDate(daySlots[daySlots.length - 1].endAt),
        durationMinutes: dayDurationMinutes,
        schedulingMode: daySlots[0].schedulingMode ?? firstSchedulingMode,
      });
    }
  }

  for (let index = 1; index < derivedSegments.length; index += 1) {
    const previousSegment = derivedSegments[index - 1];
    const nextSegment = derivedSegments[index];
    if (nextSegment.startAt.getTime() < previousSegment.endAt.getTime()) {
      issues.push(issue(
        "OVERLAPPING_BOOKING_SEGMENTS",
        "Daily booking segments cannot overlap across service dates.",
      ));
    }
  }

  if (normalizedSlots.length > 0) {
    const derivedStart = normalizedSlots[0].startAt;
    const derivedEnd = normalizedSlots[normalizedSlots.length - 1].endAt;
    if (selection.scheduledStartAt.getTime() !== derivedStart.getTime() ||
      selection.scheduledEndAt.getTime() !== derivedEnd.getTime()) {
      issues.push(issue(
        "INVALID_SCHEDULE_BOUNDS",
        "scheduledStartAt and scheduledEndAt must match the slot boundaries.",
      ));
    }
  }

  if (selection.totalDurationMinutes !== totalDurationMinutes) {
    issues.push(issue("INVALID_TOTAL_DURATION", "totalDurationMinutes must equal the sum of slot durations."));
  }

  if (selection.serviceDayCount != null && selection.serviceDayCount !== derivedSegments.length) {
    issues.push(issue(
      "INVALID_SCHEDULE_BOUNDS",
      "serviceDayCount must equal the number of distinct selected service dates.",
    ));
  }

  if (selection.segmentCount != null && selection.segmentCount !== derivedSegments.length) {
    issues.push(issue(
      "INVALID_SCHEDULE_BOUNDS",
      "segmentCount must equal the number of normalized schedule segments.",
    ));
  }

  if (derivedSegments.length > 0) {
    if (selection.firstSegmentEndAt != null &&
      selection.firstSegmentEndAt.getTime() !== derivedSegments[0].endAt.getTime()) {
      issues.push(issue(
        "INVALID_SCHEDULE_BOUNDS",
        "firstSegmentEndAt must equal the first normalized segment endAt.",
      ));
    }
    if (selection.finalEndAt != null &&
      selection.finalEndAt.getTime() !== derivedSegments[derivedSegments.length - 1].endAt.getTime()) {
      issues.push(issue(
        "INVALID_SCHEDULE_BOUNDS",
        "finalEndAt must equal the final normalized segment endAt.",
      ));
    }
  }

  if (selection.segments != null) {
    if (selection.segments.length !== derivedSegments.length) {
      issues.push(issue(
        "INVALID_SCHEDULE_BOUNDS",
        "schedule.segments must match the normalized daily selection segments.",
      ));
    } else {
      for (let index = 0; index < selection.segments.length; index += 1) {
        const provided = selection.segments[index];
        const derived = derivedSegments[index];
        const sameSlotIds =
          provided.slotIds.length === derived.slotIds.length &&
          provided.slotIds.every((slotId, slotIndex) => slotId === derived.slotIds[slotIndex]);
        if (
          provided.serviceDateKey !== derived.serviceDateKey ||
          !sameSlotIds ||
          provided.startAt.getTime() !== derived.startAt.getTime() ||
          provided.endAt.getTime() !== derived.endAt.getTime() ||
          provided.durationMinutes !== derived.durationMinutes ||
          normalizeSchedulingMode(provided.schedulingMode) !== normalizeSchedulingMode(derived.schedulingMode)
        ) {
          issues.push(issue(
            "INVALID_SCHEDULE_BOUNDS",
            "schedule.segments must match the authoritative normalized daily segments.",
          ));
          break;
        }
      }
    }
  }

  if (issues.length > 0) {
    return {
      ok: false,
      normalizedSelection: null,
      issues,
    };
  }

  return {
    ok: true,
    normalizedSelection: {
      ...selection,
      bookingType: "SLOT",
      slots: normalizedSlots.map((slot) => ({
        ...slot,
        startAt: asDate(slot.startAt),
        endAt: asDate(slot.endAt),
      })),
      slotCount: normalizedSlots.length,
      scheduledStartAt: asDate(normalizedSlots[0].startAt),
      scheduledEndAt: asDate(normalizedSlots[normalizedSlots.length - 1].endAt),
      totalDurationMinutes,
      segments: derivedSegments.map(cloneScheduleSegment),
      firstSegmentEndAt: asDate(derivedSegments[0].endAt),
      finalEndAt: asDate(derivedSegments[derivedSegments.length - 1].endAt),
      serviceDayCount: derivedSegments.length,
      segmentCount: derivedSegments.length,
    },
    issues: [],
  };
}
