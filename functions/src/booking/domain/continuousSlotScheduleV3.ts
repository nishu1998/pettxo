import type {SlotBookingSelection} from "./slotBooking";
import {normalizeTimestampLike as asDate} from "../schema/timestampNormalization";

/** Shared creation/lifecycle contract; dates may be Firestore timestamps at runtime. */
export function continuousSlotDeadlineV3(schedule: SlotBookingSelection): Date | null {
  const scheduledStartAt = asDate(schedule.scheduledStartAt);
  if (!scheduledStartAt) return null;
  // One continuous package has one lifecycle deadline. Individual slot ends
  // are partition boundaries, not independent no-show deadlines.
  const intervals = (values: Array<{startAt: unknown; endAt: unknown}>) =>
    values.map(value => ({start: asDate(value?.startAt), end: asDate(value?.endAt)}))
      .sort((a, b) => (a.start?.getTime() ?? 0) - (b.start?.getTime() ?? 0));
  const slots = intervals(Array.isArray(schedule.slots) ? schedule.slots : []);
  const continuous = (parts: ReturnType<typeof intervals>) => parts.length > 0 &&
    parts.every((part, i) => part.start != null && part.end != null &&
      part.end.getTime() > part.start.getTime() &&
      (i === 0 || parts[i - 1].end?.getTime() === part.start.getTime()));
  if (!continuous(slots)) return null;
  const slotIds = schedule.slots.map(slot => slot.slotId);
  if (slotIds.some(id => typeof id !== "string" || !id.trim()) || new Set(slotIds).size !== slotIds.length ||
    (schedule.slotCount != null && schedule.slotCount !== slots.length)) return null;
  const resolved = slots[slots.length - 1].end!;
  if (slots[0].start!.getTime() !== scheduledStartAt.getTime()) return null;
  if (schedule.slots.some(slot => slot.durationMinutes != null &&
    (!Number.isSafeInteger(slot.durationMinutes) || slot.durationMinutes <= 0 ||
      slot.durationMinutes * 60000 !== asDate(slot.endAt)!.getTime() - asDate(slot.startAt)!.getTime()))) return null;
  const totalDurationMinutes = (Number.isSafeInteger(schedule.totalDurationMinutes) && schedule.totalDurationMinutes >= 0 ? schedule.totalDurationMinutes : null);
  if (totalDurationMinutes == null || totalDurationMinutes * 60000 !==
    resolved.getTime() - scheduledStartAt.getTime()) return null;
  for (const value of [schedule.scheduledEndAt, schedule.finalEndAt]) {
    if (value != null && asDate(value)?.getTime() !== resolved.getTime()) return null;
  }
  if (schedule.segments != null) {
    if (!Array.isArray(schedule.segments)) return null;
    const segments = intervals(schedule.segments);
    if (!continuous(segments) || segments[0].start!.getTime() !== scheduledStartAt.getTime() ||
      segments[segments.length - 1].end!.getTime() !== resolved.getTime()) return null;
    if (schedule.segmentCount != null && schedule.segmentCount !== segments.length) return null;
    for (const segment of schedule.segments) {
      const start = asDate(segment.startAt)!;
      const end = asDate(segment.endAt)!;
      if (!Number.isSafeInteger(segment.durationMinutes) || segment.durationMinutes * 60000 !== end.getTime() - start.getTime()) return null;
      const members = schedule.slots.filter(slot => asDate(slot.startAt)!.getTime() >= start.getTime() &&
        asDate(slot.endAt)!.getTime() <= end.getTime()).map(slot => slot.slotId).sort();
      if (!Array.isArray(segment.slotIds) || segment.slotIds.length !== members.length ||
        [...segment.slotIds].sort().some((id, i) => id !== members[i])) return null;
    }
    // Segments must partition whole slots, never cut through one.
    if (segments.some(segment => !slots.some(slot => slot.start!.getTime() === segment.start!.getTime()) ||
      !slots.some(slot => slot.end!.getTime() === segment.end!.getTime()))) return null;
    if (schedule.firstSegmentEndAt != null && asDate(schedule.firstSegmentEndAt)?.getTime() !==
      segments[0].end!.getTime()) return null;
  } else if (schedule.firstSegmentEndAt != null &&
    asDate(schedule.firstSegmentEndAt)?.getTime() !== resolved.getTime()) {
    return null;
  }

  return resolved;
}
