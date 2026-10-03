import {computeRunwayEndsAt} from "../domain/bookingDeadlines";
import {isCanonicalServiceRequestable} from "./bookingRunway";
import {buildServiceSlotCandidates} from "../../services/serviceSlotCandidates";

export type CustomerSlotSourceV3 = {
  id: string;
  serviceId?: unknown;
  serviceOwnerId?: unknown;
  startAt?: unknown;
  endAt?: unknown;
  dateKey?: unknown;
  serviceDateKey?: unknown;
  capacity?: unknown;
  acceptedCount?: unknown;
  isBookable?: unknown;
  status?: unknown;
};

export type SlotOccupancySourceV3 = {
  confirmedUnits?: unknown;
  bookingClaims?: unknown;
} | null;

export type CustomerBookableSlotV3 = {
  id: string;
  serviceId: string;
  serviceOwnerId: string;
  startAt: string;
  endAt: string;
  dateKey: string;
  capacity: number;
  confirmedUnits: number;
  isBookable: true;
  status: "open";
};

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asDate(value: unknown): Date | null {
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value;
  if (typeof value === "object" && value != null && "toDate" in value) {
    try {
      const date = (value as {toDate(): Date}).toDate();
      return Number.isNaN(date.getTime()) ? null : date;
    } catch (_) {
      return null;
    }
  }
  return null;
}

/**
 * Produces the customer-safe slot view from canonical occupancy. The slot
 * document's acceptedCount is deliberately ignored because it is only a
 * repairable projection of slotOccupancy.confirmedUnits.
 */
export function buildCustomerBookableSlotsV3(params: {
  serviceId: string;
  service: Record<string, unknown>;
  dateKey: string;
  slots: CustomerSlotSourceV3[];
  occupancyBySlotId: ReadonlyMap<string, SlotOccupancySourceV3>;
  authoritativeNow: Date;
}): CustomerBookableSlotV3[] {
  if (!isCanonicalServiceRequestable(params.service, params.authoritativeNow).ok) {
    return [];
  }

  const runwayEndsAt = computeRunwayEndsAt(params.authoritativeNow).getTime();
  const serviceOwnerId = asString(params.service.ownerUserId);
  if (!serviceOwnerId) return [];
  const expectedByWindow = new Map(
    buildServiceSlotCandidates(
      params.serviceId,
      params.service,
      params.authoritativeNow.getTime(),
    ).candidates
      .filter((candidate) => candidate.dateKey === params.dateKey)
      .map((candidate) => [`${candidate.startAtMs}/${candidate.endAtMs}`, candidate]),
  );

  return params.slots.flatMap((slot): CustomerBookableSlotV3[] => {
    const startAt = asDate(slot.startAt);
    const endAt = asDate(slot.endAt);
    const dateKey = asString(slot.serviceDateKey) || asString(slot.dateKey);
    const capacity = slot.capacity;
    const occupancy = params.occupancyBySlotId.get(slot.id);
    const confirmedUnits = occupancy == null ? 0 : occupancy.confirmedUnits;
    const expected = expectedByWindow.get(`${startAt?.getTime()}/${endAt?.getTime()}`);

    const structurallyValid =
      expected != null &&
      asString(slot.serviceId) === params.serviceId &&
      asString(slot.serviceOwnerId) === serviceOwnerId &&
      dateKey === params.dateKey &&
      startAt != null &&
      endAt != null &&
      endAt.getTime() > startAt.getTime() &&
      Number.isInteger(capacity) &&
      (capacity as number) > 0 &&
      Number.isInteger(confirmedUnits) &&
      (confirmedUnits as number) >= 0 &&
      expected.startAtMs === startAt?.getTime() &&
      expected.endAtMs === endAt?.getTime() &&
      expected.capacity === capacity;
    if (!structurallyValid || startAt!.getTime() < runwayEndsAt) return [];
    if (slot.isBookable !== true || asString(slot.status) !== "open") return [];
    if ((confirmedUnits as number) >= (capacity as number)) return [];

    return [{
      id: slot.id,
      serviceId: params.serviceId,
      serviceOwnerId,
      startAt: startAt!.toISOString(),
      endAt: endAt!.toISOString(),
      dateKey,
      capacity: capacity as number,
      confirmedUnits: confirmedUnits as number,
      isBookable: true,
      status: "open",
    }];
  }).sort((left, right) => left.startAt.localeCompare(right.startAt));
}
