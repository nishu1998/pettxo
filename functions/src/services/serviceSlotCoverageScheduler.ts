import {randomUUID} from "crypto";
import {FieldPath, Timestamp} from "firebase-admin/firestore";
import type {Firestore} from "firebase-admin/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {logger} from "firebase-functions";
import {db} from "../shared/firebase";
import {serviceSlotEligibilityReason} from "./serviceSlotCandidates";
import {ensureServiceSlotCoverage} from "./serviceSlotCoverage";

// Resume across invocations instead of repeatedly starting at the first service.
// Hourly bounded passes allow retries/catch-up; coverage itself advances daily.
export async function runServiceSlotCoveragePass(firestore: Firestore) {
  const state = firestore.collection("_maintenance").doc("serviceSlotCoverage");
  const token = randomUUID();
  const started = Date.now();
  const lease = await firestore.runTransaction(async (tx) => {
    const snapshot = await tx.get(state);
    const data = snapshot.data() ?? {};
    if (data.leaseUntil instanceof Timestamp && data.leaseUntil.toMillis() > started) return null;
    tx.set(state, {token, leaseUntil: Timestamp.fromMillis(started + 600000)}, {merge: true});
    return {cursor: typeof data.cursor === "string" ? data.cursor : null};
  });
  if (!lease) { logger.info("service-slot-coverage-pass-already-running"); return; }
  const summary = {servicesScanned: 0, eligibleServices: 0, servicesReplenished: 0, slotsCreated: 0, failures: 0, cycleComplete: false};
  let cursor = lease.cursor;
  const checkpoint = async (release: boolean) => firestore.runTransaction(async (tx) => {
    const current = await tx.get(state);
    if (current.data()?.token !== token) throw new Error("coverage_lease_lost");
    tx.set(state, {cursor, lastProgressAt: Timestamp.now(),
      ...(release ? {leaseUntil: Timestamp.fromMillis(0), lastSummary: summary} : {})}, {merge: true});
  });
  try {
    while (summary.servicesScanned < 100 && Date.now() - started < 420000) {
      let query = firestore.collection("services").where("isActive", "==", true)
        .orderBy(FieldPath.documentId()).limit(10);
      if (cursor) query = query.startAfter(cursor);
      const page = await query.get();
      if (page.empty) { cursor = null; summary.cycleComplete = true; break; }
      for (const service of page.docs) {
        if (Date.now() - started >= 420000) break;
        summary.servicesScanned++;
        const reason = serviceSlotEligibilityReason(service.data());
        if (reason) {
          logger.info("service-slot-coverage-service-skipped", {serviceId: service.id, eligibilitySkipReason: reason});
        } else {
          summary.eligibleServices++;
          try {
            const result = await ensureServiceSlotCoverage(firestore, service.id, {deadlineMs: started + 450000});
            summary.slotsCreated += result.createdCount;
            if (result.createdCount) summary.servicesReplenished++;
          } catch {
            // The helper logs a privacy-safe reason. Continue so one malformed
            // service cannot starve every later service; retry on the next cycle.
            summary.failures++;
          }
        }
        cursor = service.id;
        await checkpoint(false);
      }
    }
  } finally {
    await checkpoint(true);
    logger.info("service-slot-coverage-pass", {...summary, cursor, elapsedMs: Date.now() - started});
  }
}

export const replenishServiceSlots = onSchedule({
  schedule: "every 60 minutes", timeZone: "Asia/Kolkata", region: "asia-south1",
  timeoutSeconds: 540, memory: "512MiB", maxInstances: 1, retryCount: 3,
}, async () => { await runServiceSlotCoveragePass(db); });
