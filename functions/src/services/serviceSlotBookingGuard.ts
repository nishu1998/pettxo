import type {Firestore, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import type {SlotBookingSelection} from "../booking/domain/slotBooking";
import type {CanonicalBookingDocumentV3} from "../booking/schema/bookingDocumentV3";
import {buildServiceSlotCandidates, serviceSlotConfigChanged, ServiceSlotSource} from "./serviceSlotCandidates";

// Slot reads used to happen only before the booking transaction. Keep the service
// and selected slots in its read set so a concurrent schedule edit must serialize
// with request creation. Existing idempotent requests do not need this new gate.
export async function lockServiceSlotSelection(db: Firestore, tx: Transaction, serviceId: string,
  service: ServiceSlotSource, selection: SlotBookingSelection): Promise<void> {
  const ref = db.collection("services").doc(serviceId);
  const live = await tx.get(ref);
  const slots = await tx.getAll(...selection.slots.map((slot) => ref.collection("slots").doc(slot.slotId)));
  const occupancy = await tx.getAll(...selection.slots.map((slot) =>
    ref.collection("slotOccupancy").doc(slot.slotId)));
  // A booked slot retained after an edit remains immutable, but must not accept
  // NEW requests if its old window/capacity no longer matches the live service.
  const expected = new Map(buildServiceSlotCandidates(serviceId, service,
    selection.scheduledStartAt.getTime()).candidates.map((candidate) =>
    [`${candidate.startAtMs}/${candidate.endAtMs}`, candidate]));
  const changed = !live.exists || serviceSlotConfigChanged(service, live.data()!);
  if (changed || slots.some((snapshot, index) => {
    const data = snapshot.data();
    const candidate = expected.get(`${data?.startAt?.toMillis?.()}/${data?.endAt?.toMillis?.()}`);
    return !candidate || !data || data.capacity !== candidate.capacity ||
      data.startAt?.toMillis?.() !== candidate.startAtMs || data.endAt?.toMillis?.() !== candidate.endAtMs ||
      data.isBookable !== true || data.status !== "open" ||
      data.startAt?.toMillis?.() !== selection.slots[index].startAt.getTime() ||
      data.endAt?.toMillis?.() !== selection.slots[index].endAt.getTime();
  })) {
    throw new HttpsError("failed-precondition", "Service availability changed. Please select your slots again.",
      {code: "SERVICE_SCHEDULE_CHANGED"});
  }
  // Payment confirmation owns slotOccupancy. Pending and accepted requests do
  // not claim it, so they retain the existing unreserved-request semantics.
  // Reading these documents in the request transaction makes a later request
  // serialize with confirmation and prevents an already paid slot from reaching
  // provider notification or checkout.
  if (slots.some((snapshot, index) => {
    const slot = snapshot.data()!;
    const occupied = occupancy[index].data();
    const claimed = occupied == null ? 0 : occupied.confirmedUnits;
    const projected = slot.acceptedCount ?? 0;
    return !Number.isInteger(claimed) || claimed < 0 ||
      !Number.isInteger(projected) || projected < 0 ||
      Math.max(claimed, projected) + 1 > slot.capacity;
  })) {
    throw new HttpsError("failed-precondition", "This time slot was just booked. Please choose another available time.",
      {code: "SLOT_CAPACITY_UNAVAILABLE"});
  }
}

/** Reject an accepted request whose capacity was claimed before a payment order
 * is created or an existing order is returned. Final capture still performs its
 * own transactional capacity check for the genuine race after this read. */
export async function assertPreCheckoutSlotCapacity(db: Firestore, booking: CanonicalBookingDocumentV3,
  bookingId: string): Promise<void> {
  if (booking.bookingType !== "SLOT" || booking.state === "CONFIRMED") return;
  const slots = (booking.schedule as {slots: Array<{slotId: string}>}).slots;
  const service = db.collection("services").doc(booking.serviceId);
  const occupancy = await db.getAll(...slots.map((slot) => service.collection("slotOccupancy").doc(slot.slotId)));
  const projections = await db.getAll(...slots.map((slot) => service.collection("slots").doc(slot.slotId)));
  if (slots.some((_, index) => {
    const claim = occupancy[index].data();
    const own = claim?.bookingClaims?.[bookingId] ?? 0;
    const occupied = claim?.confirmedUnits ?? 0;
    const projected = projections[index].data()?.acceptedCount ?? 0;
    const capacity = projections[index].data()?.capacity ?? booking.service.capacitySnapshot;
    return ![own, occupied, projected, capacity].every(Number.isInteger) ||
      Math.max(occupied - own, projected - own) + 1 > capacity;
  })) {
    throw new HttpsError("failed-precondition", "This time slot was just booked. Please choose another available time.",
      {code: "CAPACITY_UNAVAILABLE"});
  }
}
