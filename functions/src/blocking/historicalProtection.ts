import type {
  DocumentData,
  DocumentReference,
  DocumentSnapshot,
  Firestore,
  Query,
  QuerySnapshot,
  Transaction,
} from "firebase-admin/firestore";

import {
  RELATIONSHIP_ACTIVATION_DECISIONS_COLLECTION,
  UNPARSABLE_HISTORICAL_REASON_CODES,
  decisionReleasesRecord,
  parseRelationshipActivationDecision,
  relationshipActivationDecisionId,
  type RelationshipActivationDecisionPhase,
} from "./relationshipActivationDecisions";

/**
 * Phase 3B-4 D2 and D4.
 *
 * D4: Pettxo->provider settlement (payouts, payoutReadiness, PROVIDER_PAYOUT
 * manual obligations) never protects a pair. Customer-side refunds, disputes
 * and payment reconciliation still do.
 *
 * D2: a historicalProtectionBlocked mark on a relationship guard is re-judged
 * from live state each time. It stops protecting once nothing live still
 * protects the pair; records that live state cannot re-judge (unparsable)
 * keep protecting unless a matching D3 NO_OBLIGATION decision exists.
 */

export const RELATIONSHIP_MIGRATION_EVIDENCE_COLLECTION = "relationshipMigrationEvidence";
const MAX_PAIR_EVIDENCE_MARKERS = 250;
const MAX_OBLIGATIONS_PER_BOOKING = 10;

export const DISPUTE_TERMINAL_STATUSES: ReadonlySet<string> = new Set([
  "RESOLVED", "CLOSED", "REJECTED",
]);
export const REFUND_TERMINAL_STATUSES: ReadonlySet<string> = new Set([
  "PAID", "PROCESSED", "REFUNDED", "COMPLETED", "CANCELLED",
]);
export const RECONCILIATION_TERMINAL_STATUSES: ReadonlySet<string> = new Set([
  "RESOLVED", "CLEAN", "COMPLETED",
]);
export const OBLIGATION_TERMINAL_STATUSES: ReadonlySet<string> = new Set([
  "COMPLETED", "PAID", "CANCELLED", "RESOLVED",
]);

/** Historical reasons that live state can re-judge (D2). */
const REJUDGEABLE_REASON_CODES: ReadonlySet<string> = new Set([
  "ACTIVE_DISPUTE",
  "DISPUTE_WINDOW_ACTIVE",
  "FINANCIAL_OBLIGATION_UNRESOLVED",
  "PAYMENT_RECONCILIATION_REQUIRED",
  "EXTERNAL_DISPUTE_UNRESOLVED",
  "EXTERNAL_REFUND_UNRESOLVED",
  "EXTERNAL_PAYOUT_UNRESOLVED",
  "MANUAL_SETTLEMENT_OBLIGATION_UNRESOLVED",
]);

export function isRejudgeableHistoricalReason(reasonCode: string): boolean {
  return REJUDGEABLE_REASON_CODES.has(reasonCode) ||
    reasonCode.startsWith("PROTECTED_STATE_") ||
    reasonCode.startsWith("PAID_STATE_");
}

/** Same status resolution the migration has always used. */
export function externalRecordStatus(data: DocumentData | undefined): string {
  const raw = data?.status ?? data?.state ?? data?.payoutStatus;
  return typeof raw === "string" ? raw.trim().toUpperCase() : "";
}

/**
 * D4 releases only provider payouts. Customer refunds protect, and so does any
 * obligation whose type is missing or unknown (fail closed).
 */
export function obligationProtectsPair(data: DocumentData | undefined): boolean {
  const raw = data?.obligationType ?? data?.type;
  const type = typeof raw === "string" ? raw.trim().toUpperCase() : "";
  return type !== "PROVIDER_PAYOUT";
}

export type FirestoreReader = {
  getDoc(ref: DocumentReference<DocumentData>): Promise<DocumentSnapshot<DocumentData>>;
  getQuery(query: Query<DocumentData>): Promise<QuerySnapshot<DocumentData>>;
};

export function transactionReader(transaction: Transaction): FirestoreReader {
  return {
    getDoc: (ref) => transaction.get(ref),
    getQuery: (query) => transaction.get(query),
  };
}

export const directReader: FirestoreReader = {
  getDoc: (ref) => ref.get(),
  getQuery: (query) => query.get(),
};

/**
 * Customer-side obligations recorded outside the booking document. Returns ""
 * when none is open. Provider payouts (payoutReadiness, PROVIDER_PAYOUT
 * obligations) are deliberately not considered (D4).
 */
export async function liveCustomerObligationReason(params: {
  firestore: Firestore;
  reader: FirestoreReader;
  bookingId: string;
}): Promise<string> {
  const {firestore, reader, bookingId} = params;
  const [dispute, refund, reconciliation, obligations] = await Promise.all([
    reader.getDoc(firestore.collection("disputes").doc(bookingId)),
    reader.getDoc(firestore.collection("refunds").doc(bookingId)),
    reader.getDoc(firestore.collection("bookingFinancialReconciliation").doc(bookingId)),
    reader.getQuery(firestore.collection("manualSettlementObligations")
      .where("bookingId", "==", bookingId).limit(MAX_OBLIGATIONS_PER_BOOKING)),
  ]);
  if (dispute.exists && !DISPUTE_TERMINAL_STATUSES.has(externalRecordStatus(dispute.data()))) {
    return "EXTERNAL_DISPUTE_UNRESOLVED";
  }
  if (refund.exists && !REFUND_TERMINAL_STATUSES.has(externalRecordStatus(refund.data()))) {
    return "EXTERNAL_REFUND_UNRESOLVED";
  }
  if (reconciliation.exists &&
    !RECONCILIATION_TERMINAL_STATUSES.has(externalRecordStatus(reconciliation.data()))) {
    return "PAYMENT_RECONCILIATION_REQUIRED";
  }
  if (obligations.docs.some((doc) => obligationProtectsPair(doc.data()) &&
    !OBLIGATION_TERMINAL_STATUSES.has(externalRecordStatus(doc.data())))) {
    return "MANUAL_SETTLEMENT_OBLIGATION_UNRESOLVED";
  }
  return "";
}

export type HistoricalProtectionJudgement =
  | {marked: false}
  | {marked: true; stillProtected: true; reason: string}
  | {marked: true; stillProtected: false};

function stringList(value: unknown): string[] {
  return Array.isArray(value) ?
    value.filter((entry): entry is string => typeof entry === "string")
      .map((entry) => entry.trim()).filter(Boolean) :
    [];
}

/**
 * Re-judges a historicalProtectionBlocked mark from live state (D2).
 * The caller has already classified the pair's live bookings and refused on any
 * live protection; this adds what the mark covered beyond the booking
 * documents. Fails closed on anything it cannot judge.
 */
export async function judgeHistoricalProtection(params: {
  firestore: Firestore;
  reader: FirestoreReader;
  pairKey: string;
  guardData: DocumentData | undefined;
  liveBookingIds: string[];
}): Promise<HistoricalProtectionJudgement> {
  if (params.guardData?.historicalProtectionBlocked !== true) return {marked: false};
  const reasons = stringList(params.guardData.historicalProtectionReasons);
  if (reasons.length === 0) {
    return {marked: true, stillProtected: true, reason: "HISTORICAL_REASON_UNKNOWN"};
  }
  for (const reason of reasons) {
    if (!UNPARSABLE_HISTORICAL_REASON_CODES.has(reason) && !isRejudgeableHistoricalReason(reason)) {
      return {marked: true, stillProtected: true, reason};
    }
  }

  const markerSnapshot = await params.reader.getQuery(
    params.firestore.collection(RELATIONSHIP_MIGRATION_EVIDENCE_COLLECTION)
      .where("pairKey", "==", params.pairKey)
      .limit(MAX_PAIR_EVIDENCE_MARKERS + 1),
  );
  if (markerSnapshot.size > MAX_PAIR_EVIDENCE_MARKERS) {
    return {marked: true, stillProtected: true, reason: "HISTORICAL_EVIDENCE_LIMIT_EXCEEDED"};
  }
  const protectedMarkers = markerSnapshot.docs
    .map((doc) => doc.data())
    .filter((data) => data.protected === true);

  // Unparsable records: only a matching D3 NO_OBLIGATION decision releases them.
  for (const reason of reasons.filter((code) => UNPARSABLE_HISTORICAL_REASON_CODES.has(code))) {
    const markers = protectedMarkers.filter((data) => data.reasonCode === reason);
    if (markers.length === 0) return {marked: true, stillProtected: true, reason};
    for (const marker of markers) {
      const phase = marker.phase as RelationshipActivationDecisionPhase;
      const sourceId = typeof marker.sourceId === "string" ? marker.sourceId : "";
      let decisionId: string;
      try {
        decisionId = relationshipActivationDecisionId(phase, sourceId);
      } catch {
        return {marked: true, stillProtected: true, reason};
      }
      const decisionSnapshot = await params.reader.getDoc(
        params.firestore.collection(RELATIONSHIP_ACTIVATION_DECISIONS_COLLECTION).doc(decisionId),
      );
      const released = decisionReleasesRecord(
        parseRelationshipActivationDecision(decisionSnapshot.data()),
        {
          phase,
          sourceId,
          reasonCode: reason,
          sourceUpdateTimeMillis: Number(marker.sourceUpdateTimeMillis),
        },
      );
      if (!released) return {marked: true, stillProtected: true, reason};
    }
  }

  // Re-judgeable records: live customer-side obligations for every booking of
  // the pair, plus bookings the migration recorded for this pair.
  const bookingIds = new Set(params.liveBookingIds);
  for (const marker of protectedMarkers) {
    if (marker.phase === "bookings" && typeof marker.sourceId === "string" &&
      isRejudgeableHistoricalReason(String(marker.reasonCode ?? ""))) {
      bookingIds.add(marker.sourceId);
    }
  }
  for (const bookingId of bookingIds) {
    const reason = await liveCustomerObligationReason({
      firestore: params.firestore,
      reader: params.reader,
      bookingId,
    });
    if (reason) return {marked: true, stillProtected: true, reason};
  }
  return {marked: true, stillProtected: false};
}
