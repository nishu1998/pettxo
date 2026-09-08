import {AggregateField, Timestamp, type Firestore} from "firebase-admin/firestore";
import {HttpsError, type CallableRequest} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {loadAdminActor} from "../bookingAdminOperationsV3";

export type ProviderEarningsSummaryV3 = {
  providerId: string;
  lifetimeEarnedPaise: number;
  finalizedRecordCount: number;
  provisionalRecordCount: number;
  projectionVersion: 1;
  currency: "INR";
  asOf: string;
};

/** Server aggregation over full history; no list limit, deltas or payout math.
 * All aggregate reads share one read-only transaction snapshot. No documents
 * are downloaded, locked for update, or changed by this operation.
 */
export async function getProviderLifetimeEarningsDataV3(params: {
  firestore: Firestore;
  auth: CallableRequest["auth"];
  providerId?: unknown;
}): Promise<ProviderEarningsSummaryV3> {
  const uid = params.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  const providerId = params.providerId ?? uid;
  if (typeof providerId !== "string" || !providerId.trim() || providerId.includes("/") ||
    Buffer.byteLength(providerId, "utf8") > 1500) {
    throw new HttpsError("invalid-argument", "A valid provider ID is required.");
  }
  if (providerId !== uid) await loadAdminActor(params.firestore, params.auth, "financial");
  const result = await params.firestore.runTransaction(async tx => {
    const all = params.firestore.collection("providerEarnings").where("providerId", "==", providerId);
    const canonical = all.where("earningsSchemaVersion", "==", 1);
    const numeric = canonical.where("providerFinalEntitlementPaise", ">=", 0)
      .where("providerFinalEntitlementPaise", "<=", Number.MAX_SAFE_INTEGER);
    const [total, versioned, finalized, provisional, noEarning, paidBookings] = await Promise.all([
      tx.get(all.count()),
      tx.get(canonical.count()),
      tx.get(numeric.aggregate({records: AggregateField.count(), amount: AggregateField.sum("providerFinalEntitlementPaise")})),
      tx.get(canonical.where("providerFinalEntitlementPaise", "==", null).count()),
      tx.get(canonical.where("earningsOutcome", "==", "NO_EARNING_RECORD_REQUIRED").count()),
      tx.get(params.firestore.collection("bookings").where("providerId", "==", providerId)
        .where("lifecycle.paidAt", ">", Timestamp.fromMillis(0)).count()),
    ]);
    const counts = {
      records: total.data().count,
      canonical: versioned.data().count,
      finalized: finalized.data().records,
      provisional: provisional.data().count,
      noEarning: noEarning.data().count,
      paidBookings: paidBookings.data().count,
    };
    const amount = finalized.data().amount;
    if (!Object.values(counts).every(n => Number.isSafeInteger(n) && n >= 0) ||
      counts.noEarning > counts.provisional || counts.records !== counts.canonical || counts.canonical !== counts.finalized + counts.provisional ||
      counts.paidBookings !== counts.canonical - counts.noEarning ||
      !Number.isSafeInteger(amount) || amount < 0) {
      logger.warn("providerEarnings.lifetime.reconciliationRequired", {providerId, ...counts});
      throw new HttpsError("failed-precondition", "Earnings history requires reconciliation before a lifetime total is available.",
        {code: "EARNINGS_RECONCILIATION_REQUIRED"});
    }
    return {providerId, lifetimeEarnedPaise: amount, finalizedRecordCount: counts.finalized,
      provisionalRecordCount: counts.provisional - counts.noEarning,
      projectionVersion: 1 as const, currency: "INR" as const, asOf: finalized.readTime.toDate().toISOString()};
  }, {readOnly: true});
  logger.info("providerEarnings.lifetime.read", {providerId, lifetimeEarnedPaise: result.lifetimeEarnedPaise,
    finalizedRecordCount: result.finalizedRecordCount, projectionVersion: result.projectionVersion});
  return result;
}
