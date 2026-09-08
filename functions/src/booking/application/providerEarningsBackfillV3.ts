import {createHash} from "node:crypto";
import {FieldPath, Timestamp, type Firestore} from "firebase-admin/firestore";
import {HttpsError, type CallableRequest} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {loadAdminActor} from "../bookingAdminOperationsV3";
import {buildProviderEarningsProjectionV3} from "./providerEarningsV3";

type Data = FirebaseFirestore.DocumentData;
const VERSION = 1;
const MAX_BATCH = 20;
const safeId = (id: unknown): id is string => typeof id === "string" && id.length > 0 &&
  Buffer.byteLength(id, "utf8") <= 1500 && !id.includes("/") && id !== "." && id !== "..";
const upper = (value: unknown) => typeof value === "string" ? value.trim().toUpperCase() : "";
function date(value: unknown): Timestamp | null {
  if (value instanceof Timestamp) return value;
  if (value instanceof Date && Number.isFinite(value.getTime())) return Timestamp.fromDate(value);
  return null;
}
function money(value: unknown): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new Error("INVALID_CANONICAL_ENTITLEMENT");
  }
  return value;
}
function status(value: unknown): string {
  const raw = upper(value);
  if (["READY", "PAID", "PROCESSING", "FAILED", "CANCELLED"].includes(raw)) return raw;
  return raw === "PAYOUTELIGIBLE" ? "READY" : "HELD";
}
function stable(value: unknown): string {
  if (value instanceof Timestamp) return JSON.stringify([value.seconds, value.nanoseconds]);
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.entries(value).sort(([a], [b]) => a.localeCompare(b))
    .map(([k, v]) => `${JSON.stringify(k)}:${stable(v)}`).join(",")}}`;
  return JSON.stringify(value) ?? "null";
}
const publicFields = ["bookingId", "providerId", "amountPaise", "amount", "earningsSchemaVersion", "earningsStatus",
  "earningsOutcome", "providerFinalEntitlementPaise", "providerProvisionalEntitlementPaise", "status", "paidAt", "createdAt"];
const safeProjection = (data: Data | undefined) => data ? Object.fromEntries(
  publicFields.filter(k => data[k] !== undefined).map(k => [k,
    data[k] instanceof Timestamp ? data[k] :
      ["string", "number", "boolean"].includes(typeof data[k]) || data[k] == null ? data[k] : null]),
) : null;

/** No projection amounts or payout balances participate in reconstruction. */
export function reconstructProviderEarningsV3(params: {
  bookingId: string; booking: Data; cancellation?: Data; adjustment?: Data;
  noShow?: Data; dispute?: Data; resolutions?: Data[]; refund?: Data;
}) {
  const {booking: b, bookingId} = params;
  if (!safeId(b.providerId)) throw new Error("MISSING_CANONICAL_PROVIDER");
  if (b.bookingId && b.bookingId !== bookingId) throw new Error("BOOKING_ID_CONFLICT");
  for (const record of [params.cancellation, params.adjustment, params.noShow, params.dispute, ...(params.resolutions ?? [])]) {
    if (record && ((record.bookingId && record.bookingId !== bookingId) ||
      (record.providerId && record.providerId !== b.providerId))) throw new Error("CANONICAL_IDENTITY_CONFLICT");
  }
  const state = upper(b.state);
  const unpaid = ["REQUESTED", "PENDING_PROVIDER", "CANCELLED_BY_PARENT", "PENDING", "DECLINED", "REQUEST_EXPIRED", "EXPIRED", "PAYMENT_EXPIRED", "ACCEPTED_AWAITING_PAYMENT"];
  const paid = date(b.lifecycle?.paidAt) != null;
  if (unpaid.includes(state) || (state === "CANCELLED" && !paid)) {
    if (paid) throw new Error("STATE_PAYMENT_CONFLICT");
    return {classification: "NO_EARNING_RECORD_REQUIRED", projection: null, timestamp: date(b.createdAt)};
  }
  if (!paid) throw new Error("MISSING_CANONICAL_PAYMENT_EVIDENCE");
  const base = money(b.financials?.providerPayoutPaise);
  const disputeStatus = upper(b.dispute?.status);
  const separateDisputeStatus = upper(params.dispute?.status);
  const open = [disputeStatus, separateDisputeStatus].some(s => ["OPEN", "UNDER_REVIEW"].includes(s));
  const resolved = [disputeStatus, separateDisputeStatus].some(s => ["RESOLVED", "CLOSED"].includes(s));
  if (open && resolved) throw new Error("DISPUTE_STATE_CONFLICT");
  if (!resolved && ((state !== "CANCELLED" && params.cancellation?.actorType) ||
    (state !== "NO_SHOW" && params.noShow))) throw new Error("CONFLICTING_TERMINAL_OUTCOME");
  let projection;
  let timestamp = date(b.lifecycle?.paidAt);
  if (resolved) {
    const allocations = [...(params.resolutions ?? []).map(r => r.providerFinalEntitlementPaise),
      params.dispute?.resolution?.providerFinalEntitlementPaise].filter(v => v != null).map(money);
    if (!allocations.length || new Set(allocations).size !== 1) throw new Error("MISSING_OR_CONFLICTING_DISPUTE_ALLOCATION");
    projection = buildProviderEarningsProjectionV3({entitlementPaise: allocations[0], phase: "ADJUSTED", outcome: "DISPUTE_RESOLUTION"});
    timestamp = date(b.dispute?.resolvedAt) ?? date(params.resolutions?.[0]?.resolvedAt);
  } else if ((params.resolutions ?? []).length) {
    throw new Error("DISPUTE_STATE_CONFLICT");
  } else if (open) {
    if (state !== "COMPLETED_PENDING_REVIEW") throw new Error("AMBIGUOUS_PRIOR_FINAL_ENTITLEMENT");
    projection = buildProviderEarningsProjectionV3({entitlementPaise: base, phase: "HELD", outcome: "OPEN_DISPUTE"});
  } else if (state === "CANCELLED") {
    const records = [params.cancellation, params.adjustment].filter((r): r is Data => Boolean(r));
    const values = records.map(r => r.providerCompensationPaise).filter(v => v != null).map(money);
    const actors = records.map(r => upper(r.actorType)).filter(Boolean);
    if (!values.length || new Set(values).size !== 1 || new Set(actors).size !== 1 ||
      !["CUSTOMER", "PROVIDER"].includes(actors[0])) throw new Error("MISSING_OR_CONFLICTING_CANCELLATION");
    if (values[0] > base || (actors[0] === "PROVIDER" && values[0] !== 0)) throw new Error("INVALID_CANCELLATION_ALLOCATION");
    projection = buildProviderEarningsProjectionV3({entitlementPaise: values[0], phase: "FINALIZED",
      outcome: actors[0] === "CUSTOMER" ? "CUSTOMER_CANCELLATION" : "PROVIDER_CANCELLATION"});
    timestamp = date(b.lifecycle?.cancelledAt) ?? date(params.cancellation?.createdAt);
  } else if (state === "NO_SHOW") {
    const compensation = money(params.noShow?.providerCompensationPaise);
    if (compensation > base) throw new Error("INVALID_NO_SHOW_ALLOCATION");
    projection = buildProviderEarningsProjectionV3({entitlementPaise: compensation, phase: "FINALIZED", outcome: "NO_SHOW"});
    timestamp = date(params.noShow?.noShowAt);
  } else if (["CONFIRMED", "IN_PROGRESS", "COMPLETED_PENDING_REVIEW", "COMPLETED_FINAL"].includes(state)) {
    const refund = params.refund;
    const mappedRefund = refund && refund.razorpayPaymentId === b.payment?.razorpayPaymentId;
    if (refund && !refund.razorpayPaymentId && ["processed", "submitted", "required"].includes(refund.state)) {
      throw new Error("UNIDENTIFIED_REFUND_PAYMENT");
    }
    const hasRefund = Boolean(b.payment?.razorpayRefundId) || upper(b.payment?.status).includes("REFUND") || mappedRefund;
    // Without event chronology a historical refunded final booking might have
    // finalized before OR after its refund. Neither the old projection nor a
    // payout balance can resolve that financial ambiguity safely.
    if (hasRefund && state === "COMPLETED_FINAL") throw new Error("UNALLOCATED_FINAL_REFUND_REQUIRES_REVIEW");
    const final = state === "COMPLETED_FINAL";
    if (final && !date(b.lifecycle?.finalizedAt)) throw new Error("MISSING_FINALIZATION_EVIDENCE");
    projection = buildProviderEarningsProjectionV3({entitlementPaise: base,
      phase: hasRefund ? "HELD" : final ? "FINALIZED" : "PROVISIONAL",
      outcome: hasRefund ? "CANONICAL_REFUND_REVIEW" : final ? "NORMAL_COMPLETION" :
        state === "COMPLETED_PENDING_REVIEW" ? "COMPLETION_REVIEW" : "PAYMENT_CONFIRMED"});
    timestamp = final ? date(b.lifecycle?.finalizedAt) : date(b.lifecycle?.paidAt);
  } else throw new Error("UNSUPPORTED_BOOKING_STATE");
  return {classification: projection.earningsStatus === "HELD" ? "HELD_FINAL_OR_PROVISIONAL_EARNING" :
    projection.providerFinalEntitlementPaise == null ? "PROVISIONAL_EARNING" : "FINAL_EARNING", projection, timestamp};
}

export async function reconcileProviderEarningsBatchDataV3(params: {
  firestore: Firestore; auth: CallableRequest["auth"];
  input: {dryRun?: boolean; scan?: "bookings" | "providerEarnings"; limit?: number; cursor?: string; ids?: string[]};
}) {
  const actor = await loadAdminActor(params.firestore, params.auth, "financial");
  if (actor.role !== "superAdmin") throw new HttpsError("permission-denied", "Super Admin access required.");
  const {input, firestore} = params;
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new HttpsError("invalid-argument", "Batch options must be an object.");
  }
  const scan = input.scan ?? "bookings";
  const limit = input.limit ?? 10;
  const dryRun = input.dryRun !== false;
  if (!["bookings", "providerEarnings"].includes(scan) || !Number.isInteger(limit) || limit < 1 || limit > MAX_BATCH ||
    (input.dryRun != null && typeof input.dryRun !== "boolean") ||
    (input.cursor != null && !safeId(input.cursor)) ||
    (input.ids != null && (!Array.isArray(input.ids) || !input.ids.length || input.ids.length > MAX_BATCH ||
      !input.ids.every(safeId) || input.cursor != null))) throw new HttpsError("invalid-argument", "Invalid bounded batch options.");
  let query = firestore.collection(scan).orderBy(FieldPath.documentId()).limit(limit + 1);
  if (input.cursor) query = query.startAfter(input.cursor);
  const page = input.ids ? null : await query.get();
  const ids = input.ids ? [...new Set(input.ids)] : page!.docs.slice(0, limit).map(d => d.id);
  const counts = {scanned: 0, unchanged: 0, created: 0, updated: 0, zeroed: 0, skipped: 0, failed: 0};
  const items: Data[] = [];
  for (const id of ids) {
    let item: Data;
    try {
      item = await firestore.runTransaction(async tx => {
        const earningRef = firestore.collection("providerEarnings").doc(id);
        const collections = ["bookings", "bookingCancellations", "bookingFinancialAdjustments", "bookingNoShows", "disputes", "refunds", "providerPayouts"];
        const snapshots = await Promise.all(collections.map(c => tx.get(firestore.collection(c).doc(id))));
        const existingSnap = await tx.get(earningRef);
        const old = existingSnap.data();
        const current = safeProjection(old);
        const b = snapshots[0].data();
        const skip = (category: string) => ({id, bookingId: id, action: "skipped", errorCategory: category, severity: "HIGH", current});
        if (scan === "providerEarnings" && !existingSnap.exists) return skip("PROJECTION_DISAPPEARED");
        if (!b) return skip("ORPHAN_PROJECTION_OR_MISSING_BOOKING");
        if (old?.bookingId && old.bookingId !== id) return skip("PROJECTION_BOOKING_ID_CONFLICT");
        const duplicates = await tx.get(firestore.collection("providerEarnings").where("bookingId", "==", id).limit(2));
        if (duplicates.docs.some(d => d.id !== id)) return skip("DUPLICATE_PROJECTION");
        const resolutions = await tx.get(firestore.collection("bookingDisputeResolutions").where("bookingId", "==", id).limit(2));
        if (resolutions.size > 1) return skip("MULTIPLE_DISPUTE_RESOLUTIONS");
        let reconstructed;
        try {
          reconstructed = reconstructProviderEarningsV3({bookingId: id, booking: b,
            cancellation: snapshots[1].data(), adjustment: snapshots[2].data(), noShow: snapshots[3].data(),
            dispute: snapshots[4].data(), refund: snapshots[5].data(), resolutions: resolutions.docs.map(d => d.data())});
        } catch (error) { return skip(error instanceof Error ? error.message : "INVALID_CANONICAL_DATA"); }
        const {projection, classification, timestamp} = reconstructed;
        if (!projection && !old) return {...skip("NO_EARNING_RECORD_REQUIRED"), classification};
        const payout = snapshots[6].data();
        if (payout && ((payout.providerId && payout.providerId !== b.providerId) ||
          (payout.bookingId && payout.bookingId !== id))) return skip("PAYOUT_IDENTITY_CONFLICT");
        const wrongProvider = old?.providerId && old.providerId !== b.providerId;
        const expected: Data = {
          ...(projection ?? buildProviderEarningsProjectionV3({entitlementPaise: 0,
            phase: "PROVISIONAL", outcome: "NO_EARNING_RECORD_REQUIRED"})),
          bookingId: id, providerId: b.providerId, userId: b.parentId ?? "", serviceId: b.serviceId ?? "",
          currency: b.financials?.currency ?? "INR",
          status: status(payout?.status ?? b.payout?.status ?? (wrongProvider ? "HELD" : old?.status)),
          createdAt: date(b.lifecycle?.paidAt) ?? date(b.createdAt), earningsOutcomeAt: timestamp,
        };
        const paidAt = date(payout?.paidAt) ?? date(b.payout?.releasedAt);
        if (paidAt) expected.paidAt = paidAt;
        // Preserve the deployed rupee field, but label it legacy. It is never
        // read for calculations. Legacy payout references are also retained.
        if (old?.amount !== undefined) expected.legacyAmountDeprecated = true;
        if (typeof old?.status === "string" && old.status !== expected.status) {
          expected.legacyPayoutStatus = old.legacyPayoutStatus ?? old.status;
        }
        const changed = !old || Object.entries(expected).some(([k, v]) => stable(old[k]) !== stable(v));
        const action = !changed ? "unchanged" : !old ? "created" : expected.amountPaise === 0 && old.amountPaise !== 0 ? "zeroed" : "updated";
        const anomalies = [...(wrongProvider ? ["WRONG_PROVIDER_ID"] : []), ...(!timestamp ? ["MISSING_OUTCOME_TIMESTAMP"] : [])];
        const result = {id, bookingId: id, providerId: b.providerId, action, classification, anomalies,
          severity: wrongProvider ? "HIGH" : anomalies.length ? "WARNING" : "INFO", current, expected};
        if (changed && !dryRun) {
          const now = Timestamp.now();
          const fingerprint = createHash("sha256").update(stable({bookingId: id, current, expected})).digest("hex");
          tx.set(earningRef, {...expected, reconciledAt: now, earningsReconciliationVersion: VERSION,
            updatedAt: now}, {merge: true});
          tx.set(firestore.collection("providerEarningsReconciliationAudit").doc(fingerprint), {
            bookingId: id, providerId: b.providerId, actorUid: actor.uid, action, classification, anomalies,
            previous: current, expected, version: VERSION, at: now,
          });
        }
        return result;
      });
    } catch {
      item = {id, bookingId: id, action: "failed", errorCategory: "TRANSACTION_FAILED", severity: "HIGH"};
    }
    counts.scanned++;
    counts[item.action as keyof Omit<typeof counts, "scanned">]++;
    items.push(item);
    logger.info("providerEarnings.reconciliation", {bookingId: item.bookingId, providerId: item.providerId ?? null,
      action: item.action, previousAmountPaise: typeof item.current?.amountPaise === "number" ? item.current.amountPaise : null,
      newAmountPaise: item.expected?.amountPaise ?? null, outcome: item.expected?.earningsOutcome ?? null,
      dryRun, errorCategory: item.errorCategory ?? null, anomalies: item.anomalies ?? [], severityLevel: item.severity});
  }
  return {dryRun, scan, counts, items, nextCursor: !input.ids && page!.docs.length > limit ? ids[ids.length - 1] : null,
    retryIds: items.filter(i => i.action === "failed").map(i => i.id)};
}
