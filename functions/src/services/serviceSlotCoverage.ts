import {FieldPath, FieldValue, Timestamp} from "firebase-admin/firestore";
import type {DocumentData, Firestore, Transaction} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {buildServiceSlotCandidates, serviceSlotConfigChanged, serviceDateKey, SlotCandidate} from "./serviceSlotCandidates";

const CHUNK_SIZE = 50;
// Fail closed on unusually large/unknown legacy booking histories. Never infer that
// absence from a truncated query means a slot has no booking references.
const BOOKING_PROTECTION_LIMIT = 500;
const OVERLAP_PROTECTION_LIMIT = 300;
function millis(value: unknown): number {
  if (value instanceof Timestamp || value instanceof Date) return value instanceof Date ? value.getTime() : value.toMillis();
  if (typeof value === "string") return Date.parse(value);
  return NaN;
}
function payload(candidate: SlotCandidate): DocumentData {
  const {id: _id, startAtMs, endAtMs, ...data} = candidate;
  return {...data, startAt: Timestamp.fromMillis(startAtMs), endAt: Timestamp.fromMillis(endAtMs),
    generatedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()};
}
function matches(candidate: SlotCandidate | undefined, slot: DocumentData): boolean {
  return !!candidate && millis(slot.startAt) === candidate.startAtMs && millis(slot.endAt) === candidate.endAtMs &&
    slot.capacity === candidate.capacity && slot.serviceOwnerId === candidate.serviceOwnerId &&
    slot.durationMinutes === candidate.durationMinutes && slot.dateKey === candidate.dateKey;
}
function rangeKeys(start: number, end: number): string[] {
  if (!Number.isFinite(start)) return [];
  return [...new Set([serviceDateKey(start), serviceDateKey(Number.isFinite(end) ? Math.max(start, end - 1) : start)])];
}
async function occupiedRangeDates(db: Firestore, tx: Transaction, serviceId: string, keys: string[]): Promise<Set<string>> {
  const unique = [...new Set(keys)];
  if (!unique.length) return new Set();
  const snapshots = await tx.getAll(...unique.map((key) => db.doc(`services/${serviceId}/occupancy/${key}`)));
  return new Set(snapshots.filter((snapshot) => snapshot.exists).map((snapshot) => snapshot.id));
}
async function bookingProtection(db: Firestore, tx: Transaction, serviceId: string, nowMs: number) {
  const snapshot = await tx.get(db.collection("bookings").where("serviceId", "==", serviceId).limit(BOOKING_PROTECTION_LIMIT + 1));
  if (snapshot.size > BOOKING_PROTECTION_LIMIT) throw new Error("booking_protection_limit_exceeded");
  const ids = new Set<string>();
  const windows: Array<{id: string; start: number; end: number}> = [];
  for (const doc of snapshot.docs) {
    const booking = doc.data();
    const schedule = booking.schedule ?? {};
    if (millis(schedule.scheduledEndAt) < nowMs) continue;
    // Preserve references from every state, including pending requests and cancelled
    // bookings. Their immutable schedules must not be rewritten by a service edit.
    if (!Array.isArray(schedule.slots) || !schedule.slots.length) {
      throw new Error("unrecognized_booking_schedule_requires_review");
    }
    for (const slot of schedule.slots) {
      if (typeof slot.slotId !== "string" || !Number.isFinite(millis(slot.startAt)) || !Number.isFinite(millis(slot.endAt))) {
        throw new Error("unrecognized_booking_slot_requires_review");
      }
      ids.add(slot.slotId);
      windows.push({id: slot.slotId, start: millis(slot.startAt), end: millis(slot.endAt)});
    }
  }
  return {ids, windows};
}

/** Replenishment never updates/deletes existing slots, bookings, or occupancy.
 * reconcileChangedSchedule is exclusively for the service-write trigger: it may
 * delete obsolete future slots only after transactional booking/occupancy checks.
 */
export async function ensureServiceSlotCoverage(db: Firestore, serviceId: string,
  options: {nowMs?: number; reconcileChangedSchedule?: boolean; deadlineMs?: number} = {}) {
  const nowMs = options.nowMs ?? Date.now();
  const ref = db.collection("services").doc(serviceId);
  const snapshot = await ref.get();
  const service = snapshot.data();
  const plan = buildServiceSlotCandidates(serviceId, service ?? {}, nowMs);
  const summary = {serviceId, coverageStartDate: plan.coverageStartDate, coverageEndDate: plan.coverageEndDate,
    candidateCount: plan.candidates.length, existingCount: 0, createdCount: 0, skippedExistingCount: 0,
    protectedCount: 0, deletedUnbookedCount: 0,
    invalidScheduleReason: plan.invalidScheduleReason,
    eligibilitySkipReason: service ? plan.eligibilitySkipReason : "service_missing"};
  if (!service) { logger.info("service-slot-coverage", summary); return summary; }
  const assertCurrentService = async (tx: Transaction) => {
    const live = await tx.get(ref);
    if (!live.exists || serviceSlotConfigChanged(service, live.data()!)) throw new Error("service_changed_retry_required");
  };
  const checkDeadline = () => {
    if (options.deadlineMs && Date.now() >= options.deadlineMs) throw new Error("coverage_time_budget_exhausted");
  };
  try {
    // Invalid input must not destroy the last known valid schedule.
    if (options.reconcileChangedSchedule && !plan.invalidScheduleReason) {
      const desired = new Map(plan.candidates.map((candidate) => [candidate.id, candidate]));
      let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
      while (true) {
        checkDeadline();
        let query = ref.collection("slots").where("startAt", ">=", Timestamp.fromMillis(nowMs))
          .orderBy("startAt").orderBy(FieldPath.documentId()).limit(CHUNK_SIZE);
        if (cursor) query = query.startAfter(cursor);
        const page = await query.get();
        if (page.empty) break;
        const counts = await db.runTransaction(async (tx) => {
          await assertCurrentService(tx);
          const protection = await bookingProtection(db, tx, serviceId, nowMs);
          const slots = await tx.getAll(...page.docs.map((doc) => doc.ref));
          const occupancy = await tx.getAll(...page.docs.map((doc) => ref.collection("slotOccupancy").doc(doc.id)));
          const rangeDates = await occupiedRangeDates(db, tx, serviceId, slots.flatMap((slot) =>
            rangeKeys(millis(slot.data()?.startAt), millis(slot.data()?.endAt))));
          let deleted = 0;
          let protectedCount = 0;
          for (let i = 0; i < slots.length; i++) {
            const slot = slots[i];
            const data = slot.data();
            if (!data || millis(data.startAt) < nowMs || !Number.isFinite(millis(data.startAt))) continue;
            // Slots outside the managed horizon are untouched while active.
            if (!plan.eligibilitySkipReason && String(data.dateKey) > plan.coverageEndDate) continue;
            if (matches(desired.get(slot.id), data)) continue;
            if (Number(data.acceptedCount ?? 0) !== 0 || occupancy[i].exists || protection.ids.has(slot.id) ||
              !["open", "closed"].includes(data.status) ||
              rangeKeys(millis(data.startAt), millis(data.endAt)).some((key) => rangeDates.has(key))) {
              protectedCount++; continue;
            }
            tx.delete(slot.ref);
            deleted++;
          }
          return {deleted, protectedCount};
        });
        summary.deletedUnbookedCount += counts.deleted;
        summary.protectedCount += counts.protectedCount;
        cursor = page.docs[page.docs.length - 1];
      }
    }
    for (let offset = 0; offset < plan.candidates.length; offset += CHUNK_SIZE) {
      checkDeadline();
      const chunk = plan.candidates.slice(offset, offset + CHUNK_SIZE);
      const counts = await db.runTransaction(async (tx) => {
        await assertCurrentService(tx);
        const slots = await tx.getAll(...chunk.map((candidate) => ref.collection("slots").doc(candidate.id)));
        const missing = chunk.filter((_, i) => !slots[i].exists);
        if (!missing.length) return {existing: slots.length, created: 0, protectedCount: 0};
        const protection = await bookingProtection(db, tx, serviceId, nowMs);
        const occupancy = await tx.getAll(...missing.map((candidate) => ref.collection("slotOccupancy").doc(candidate.id)));
        // Also protect legacy/orphan occupancy under a DIFFERENT deterministic ID
        // when an edited schedule shifts or resizes a candidate window.
        const min = Math.min(...missing.map((candidate) => candidate.startAtMs));
        const max = Math.max(...missing.map((candidate) => candidate.endAtMs));
        const neighbors = await tx.get(ref.collection("slots")
          .where("startAt", ">=", Timestamp.fromMillis(min - 86400000))
          .where("startAt", "<", Timestamp.fromMillis(max)).limit(OVERLAP_PROTECTION_LIMIT + 1));
        if (neighbors.size > OVERLAP_PROTECTION_LIMIT) throw new Error("overlap_protection_limit_exceeded");
        const neighborOccupancy = neighbors.empty ? [] : await tx.getAll(...neighbors.docs.map((doc) => ref.collection("slotOccupancy").doc(doc.id)));
        const rangeDates = await occupiedRangeDates(db, tx, serviceId,
          missing.flatMap((candidate) => rangeKeys(candidate.startAtMs, candidate.endAtMs)));
        const protectedWindows = [...protection.windows];
        neighbors.docs.forEach((doc, i) => {
          if (Number(doc.data().acceptedCount ?? 0) !== 0 || neighborOccupancy[i].exists ||
            !["open", "closed"].includes(doc.data().status)) {
            protectedWindows.push({id: doc.id, start: millis(doc.data().startAt), end: millis(doc.data().endAt)});
          }
        });
        let created = 0;
        let protectedCount = 0;
        for (let i = 0; i < missing.length; i++) {
          const candidate = missing[i];
          if (occupancy[i].exists || protection.ids.has(candidate.id) ||
            rangeKeys(candidate.startAtMs, candidate.endAtMs).some((key) => rangeDates.has(key)) || protectedWindows.some((window) =>
            window.id !== candidate.id && window.start < candidate.endAtMs && window.end > candidate.startAtMs)) {
            protectedCount++; continue;
          }
          // Firestore create carries exists=false. A competing create/read conflict
          // retries the transaction, which then observes and skips the existing slot.
          tx.create(ref.collection("slots").doc(candidate.id), payload(candidate));
          created++;
        }
        return {existing: slots.length - missing.length, created, protectedCount};
      });
      summary.existingCount += counts.existing;
      summary.skippedExistingCount += counts.existing;
      summary.createdCount += counts.created;
      summary.protectedCount += counts.protectedCount;
    }
    logger.info("service-slot-coverage", summary);
    return summary;
  } catch (error) {
    logger.error("service-slot-coverage-failed", {...summary,
      errorCode: error instanceof Error && /^[a-z_]+$/.test(error.message) ? error.message : "coverage_transaction_failed"});
    throw error;
  }
}
