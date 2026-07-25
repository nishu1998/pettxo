import {isBookingType, type BookingType} from "./bookingContracts";

export type SlotBookingValidationCode =
  | "EMPTY_SELECTION"
  | "INVALID_BOOKING_TYPE"
  | "DUPLICATE_SLOT"
  | "INVALID_SLOT_RANGE"
  | "NON_CONTIGUOUS"
  | "OVERLAPPING"
  | "MIXED_SERVICE"
  | "MIXED_PROVIDER"
  | "MIXED_TIMEZONE"
  | "MIXED_DATE_KEY"
  | "INVALID_SLOT_COUNT"
  | "INVALID_TOTAL_DURATION"
  | "INVALID_SCHEDULE_BOUNDS"
  | "INVALID_UNIT_PRICE";

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
  startAt: Date;
  endAt: Date;
  durationMinutes: number;
  unitPricePaise: number;
};

export type SlotBookingSelection = {
  bookingType: BookingType;
  slots: SlotSegment[];
  slotCount: number;
  scheduledStartAt: Date;
  scheduledEndAt: Date;
  totalDurationMinutes: number;
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

  const seenSlotIds = new Set<string>();
  let totalDurationMinutes = 0;
  let previousSlot: SlotSegment | null = null;
  let firstServiceId = "";
  let firstProviderId = "";
  let firstTimezone = "";
  let firstDateKey = "";

  for (const slot of sortedSlots) {
    if (!slot.slotId.trim()) {
      issues.push(issue("DUPLICATE_SLOT", "Slot ID is required.", slot.slotId));
    }
    if (seenSlotIds.has(slot.slotId)) {
      issues.push(issue("DUPLICATE_SLOT", "Duplicate slot IDs are invalid.", slot.slotId));
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
    if (!firstDateKey) firstDateKey = slot.dateKey;

    if (slot.serviceId !== firstServiceId) {
      issues.push(issue("MIXED_SERVICE", "All selected slots must belong to the same service.", slot.slotId));
    }
    if (slot.providerId !== firstProviderId) {
      issues.push(issue("MIXED_PROVIDER", "All selected slots must belong to the same provider.", slot.slotId));
    }
    if (slot.timezone !== firstTimezone) {
      issues.push(issue("MIXED_TIMEZONE", "All selected slots must use the same timezone.", slot.slotId));
    }
    if (slot.dateKey !== firstDateKey) {
      issues.push(issue("MIXED_DATE_KEY", "Slots cannot cross different service-date schedules.", slot.slotId));
    }

    if (previousSlot != null) {
      const previousEndMs = previousSlot.endAt.getTime();
      const currentStartMs = slot.startAt.getTime();
      if (currentStartMs < previousEndMs) {
        issues.push(issue("OVERLAPPING", "Selected slots cannot overlap.", slot.slotId));
      } else if (currentStartMs !== previousEndMs) {
        issues.push(issue("NON_CONTIGUOUS", "Selected slots must be exactly continuous.", slot.slotId));
      }
    }

    previousSlot = slot;
  }

  if (selection.slotCount !== selection.slots.length) {
    issues.push(issue("INVALID_SLOT_COUNT", "slotCount must equal slots.length."));
  }

  if (sortedSlots.length > 0) {
    const derivedStart = sortedSlots[0].startAt;
    const derivedEnd = sortedSlots[sortedSlots.length - 1].endAt;
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
      slots: sortedSlots.map((slot) => ({
        ...slot,
        startAt: asDate(slot.startAt),
        endAt: asDate(slot.endAt),
      })),
      slotCount: sortedSlots.length,
      scheduledStartAt: asDate(sortedSlots[0].startAt),
      scheduledEndAt: asDate(sortedSlots[sortedSlots.length - 1].endAt),
      totalDurationMinutes,
    },
    issues: [],
  };
}
