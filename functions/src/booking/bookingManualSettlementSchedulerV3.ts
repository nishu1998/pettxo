import {FieldPath, type Firestore} from "firebase-admin/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {db} from "../shared/firebase";
import {synchronizeManualSettlementBookingV3} from "./application/manualSettlementSyncV3";

/** Only existing obligations: this is lifecycle synchronization, not backfill. */
export async function synchronizeExistingManualPayoutsV3(firestore: Firestore, now = new Date()) {
  let cursor: string | null = null;
  do {
    let query = firestore.collection("manualSettlementObligations").orderBy(FieldPath.documentId()).limit(100);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) return;
    for (const doc of page.docs) {
      const obligation = doc.data();
      if (obligation.settlementSyncVersion !== 1 || obligation.obligationType !== "PROVIDER_PAYOUT" || !["READY", "HELD"].includes(obligation.status)) continue;
      try {
        await synchronizeManualSettlementBookingV3({firestore, bookingId: obligation.bookingId, now});
      } catch (error) {
        // Ambiguous financial evidence is never converted into executable money.
        logger.error("manualSettlement.sync.failed", {obligationId: doc.id, error: String(error)});
      }
    }
    cursor = page.docs[page.docs.length - 1].id;
    if (page.size < 100) return;
  } while (cursor);
}
export const synchronizeManualSettlementPayoutsV3 = onSchedule(
  {schedule: "every 15 minutes", timeZone: "Asia/Kolkata"},
  async () => { await synchronizeExistingManualPayoutsV3(db); },
);
