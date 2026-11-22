import {createHash} from "node:crypto";

import {
  FieldPath,
  FieldValue,
  type DocumentData,
  type Firestore,
  type QueryDocumentSnapshot,
} from "firebase-admin/firestore";

import {
  CANONICAL_PAYMENT_ORDER_MAPPINGS_COLLECTION,
  CANONICAL_QR_PAYMENT_MAPPINGS_COLLECTION,
} from "../booking/application/paymentOrchestrationV3";
import {assertValidCanonicalBookingDocumentV3} from "../booking/schema/bookingDocumentV3";
import {directReader, liveCustomerObligationReason} from "./historicalProtection";
import {
  parseRelationshipActivationDecision,
  relationshipActivationDecisionId,
  type RelationshipActivationDecisionDocument,
} from "./relationshipActivationDecisions";
import {
  USER_RELATIONSHIP_GUARDS_COLLECTION,
  canonicalUserPair,
} from "./relationshipGuard";
import {classifyRelationshipProtectionV1} from "./userBlocking";

export type HistoricalMigrationMode = "dry-run" | "apply" | "reconcile";
export type HistoricalMigrationPhase = "blocks" | "bookings";

export type HistoricalMigrationPageResult = {
  phase: HistoricalMigrationPhase;
  mode: HistoricalMigrationMode;
  scannedCount: number;
  protectedCount: number;
  anomalyCount: number;
  appliedCount: number;
  alreadyAppliedCount: number;
  mismatchCount: number;
  nextCursor: string | null;
  complete: boolean;
  findings: Array<{sourceId: string; pairKey: string; reasonCode: string}>;
};

export const HISTORICAL_RELATIONSHIP_MIGRATION_VERSION = 1;

export type HistoricalRelationshipEvidence = {
  sourceId: string;
  pairKey: string;
  uidA: string;
  uidB: string;
  protected: boolean;
  blocked: boolean;
  anomaly: boolean;
  reasonCode: string;
  directedBlockId: string;
  sourceUpdateTimeMillis: number;
};

function value(data: DocumentData, primary: string, legacy: string): string {
  const first = typeof data[primary] === "string" ? data[primary].trim() : "";
  const second = typeof data[legacy] === "string" ? data[legacy].trim() : "";
  if (first && second && first !== second) return "";
  return first || second;
}

function status(data: DocumentData | undefined): string {
  const raw = data?.status ?? data?.state ?? data?.payoutStatus;
  return typeof raw === "string" ? raw.trim().toUpperCase() : "";
}

/**
 * Customer-side obligations outside the booking document. Provider payouts
 * (payoutReadiness, PROVIDER_PAYOUT obligations) no longer protect (D4);
 * obligations of unknown type still do (fail closed). The
 * runtime uses the same helper for D2 re-judgement.
 */
async function externalFinancialProtectionReason(
  firestore: Firestore,
  bookingId: string,
): Promise<string> {
  return liveCustomerObligationReason({firestore, reader: directReader, bookingId});
}

async function bookingEvidence(
  firestore: Firestore,
  snapshot: QueryDocumentSnapshot<DocumentData>,
  authoritativeNow: Date,
): Promise<HistoricalRelationshipEvidence> {
  const data = snapshot.data();
  const parentId = value(data, "parentId", "customerId");
  const providerId = value(data, "providerId", "serviceOwnerId");
  if (!parentId || !providerId || parentId === providerId) {
    return {
      sourceId: snapshot.id,
      pairKey: "",
      uidA: "",
      uidB: "",
      protected: true,
      blocked: false,
      anomaly: true,
      reasonCode: "INVALID_BOOKING_PARTICIPANTS",
      directedBlockId: "",
      sourceUpdateTimeMillis: snapshot.updateTime.toMillis(),
    };
  }
  const pair = canonicalUserPair(parentId, providerId);
  const externalReason = await externalFinancialProtectionReason(
    firestore,
    snapshot.id,
  );
  if (externalReason) {
    return {
      sourceId: snapshot.id,
      ...pair,
      protected: true,
      blocked: false,
      anomaly: false,
      reasonCode: externalReason,
      directedBlockId: "",
      sourceUpdateTimeMillis: snapshot.updateTime.toMillis(),
    };
  }
  try {
    const booking = assertValidCanonicalBookingDocumentV3(data);
    const protection = classifyRelationshipProtectionV1({booking, authoritativeNow});
    if (protection.kind === "accepted_unpaid") {
      const [attempts, orders, qrMappings] = await Promise.all([
        snapshot.ref.collection("paymentAttempts").limit(1).get(),
        firestore.collection(CANONICAL_PAYMENT_ORDER_MAPPINGS_COLLECTION)
          .where("bookingId", "==", snapshot.id).limit(1).get(),
        firestore.collection(CANONICAL_QR_PAYMENT_MAPPINGS_COLLECTION)
          .where("bookingId", "==", snapshot.id).limit(1).get(),
      ]);
      const uncertain = !attempts.empty || !orders.empty || !qrMappings.empty;
      return {
        sourceId: snapshot.id,
        ...pair,
        protected: uncertain,
        blocked: false,
        anomaly: uncertain,
        reasonCode: uncertain ? "PAYMENT_RECONCILIATION_REQUIRED" : "ACCEPTED_UNPAID_ACCOUNTED",
        directedBlockId: "",
        sourceUpdateTimeMillis: snapshot.updateTime.toMillis(),
      };
    }
    return {
      sourceId: snapshot.id,
      ...pair,
      protected: protection.kind === "protected",
      blocked: false,
      anomaly: false,
      reasonCode: protection.reason,
      directedBlockId: "",
      sourceUpdateTimeMillis: snapshot.updateTime.toMillis(),
    };
  } catch {
    return {
      sourceId: snapshot.id,
      ...pair,
      protected: true,
      blocked: false,
      anomaly: true,
      reasonCode: "INVALID_OR_LEGACY_BOOKING",
      directedBlockId: "",
      sourceUpdateTimeMillis: snapshot.updateTime.toMillis(),
    };
  }
}

function blockEvidence(snapshot: QueryDocumentSnapshot<DocumentData>): HistoricalRelationshipEvidence {
  const data = snapshot.data();
  const owner = value(data, "ownerUserId", "blockerUid");
  const blocked = typeof data.blockedUserId === "string" ? data.blockedUserId.trim() : "";
  if (!owner || !blocked || owner === blocked) {
    return {
      sourceId: snapshot.id,
      pairKey: "",
      uidA: "",
      uidB: "",
      protected: true,
      blocked: true,
      anomaly: true,
      reasonCode: "INVALID_DIRECTED_BLOCK",
      directedBlockId: snapshot.id,
      sourceUpdateTimeMillis: snapshot.updateTime.toMillis(),
    };
  }
  return {
    sourceId: snapshot.id,
    ...canonicalUserPair(owner, blocked),
    protected: false,
    blocked: true,
    anomaly: false,
    reasonCode: "DIRECTED_BLOCK_ACCOUNTED",
    directedBlockId: snapshot.id,
    sourceUpdateTimeMillis: snapshot.updateTime.toMillis(),
  };
}

async function applyOrReconcileEvidence(params: {
  firestore: Firestore;
  phase: HistoricalMigrationPhase;
  mode: HistoricalMigrationMode;
  runId: string;
  evidence: HistoricalRelationshipEvidence;
}): Promise<"applied" | "already-applied" | "matched" | "mismatch"> {
  if (!params.evidence.pairKey) return params.mode === "reconcile" ? "mismatch" : "already-applied";
  const markerId = `v1_${params.phase}_${params.evidence.sourceId}`;
  const markerRef = params.firestore.collection("relationshipMigrationEvidence").doc(markerId);
  const guardRef = params.firestore.collection(USER_RELATIONSHIP_GUARDS_COLLECTION)
    .doc(params.evidence.pairKey);
  return params.firestore.runTransaction(async (transaction) => {
    const [marker, guard] = await Promise.all([
      transaction.get(markerRef),
      transaction.get(guardRef),
    ]);
    if (params.mode === "reconcile") {
      const guardData = guard.data() ?? {};
      const ids = Array.isArray(guardData.activeDirectedBlockIds) ?
        guardData.activeDirectedBlockIds : [];
      const matched = marker.exists && guard.exists &&
        (!params.evidence.blocked || (guardData.blocked === true && ids.includes(params.evidence.directedBlockId))) &&
        (!params.evidence.protected || guardData.historicalProtectionBlocked === true);
      return matched ? "matched" : "mismatch";
    }
    if (marker.exists) {
      const prior = marker.data() ?? {};
      if (prior.pairKey !== params.evidence.pairKey ||
        prior.protected !== params.evidence.protected ||
        prior.blocked !== params.evidence.blocked ||
        prior.reasonCode !== params.evidence.reasonCode) {
        throw new Error("migration_evidence_changed_requires_reconciliation");
      }
      transaction.set(markerRef, {
        runId: params.runId,
        migrationVersion: HISTORICAL_RELATIONSHIP_MIGRATION_VERSION,
        sourceUpdateTimeMillis: params.evidence.sourceUpdateTimeMillis,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      return "already-applied";
    }
    const mutation: Record<string, unknown> = {
      schemaVersion: 1,
      migrationVersion: HISTORICAL_RELATIONSHIP_MIGRATION_VERSION,
      pairKey: params.evidence.pairKey,
      uidA: params.evidence.uidA,
      uidB: params.evidence.uidB,
      historicalEvidenceCount: FieldValue.increment(1),
      historicalMigrationRunId: params.runId,
      historicalMigrationUpdatedAt: FieldValue.serverTimestamp(),
    };
    if (params.evidence.blocked) {
      mutation.blocked = true;
      mutation.status = "blocked";
      mutation.activeDirectedBlockIds = FieldValue.arrayUnion(params.evidence.directedBlockId);
    }
    if (params.evidence.protected) {
      mutation.historicalProtectionBlocked = true;
      mutation.historicalProtectionReasons = FieldValue.arrayUnion(params.evidence.reasonCode);
    }
    transaction.set(guardRef, mutation, {merge: true});
    transaction.create(markerRef, {
      schemaVersion: 1,
      migrationVersion: HISTORICAL_RELATIONSHIP_MIGRATION_VERSION,
      runId: params.runId,
      phase: params.phase,
      sourceId: params.evidence.sourceId,
      pairKey: params.evidence.pairKey,
      protected: params.evidence.protected,
      blocked: params.evidence.blocked,
      anomaly: params.evidence.anomaly,
      reasonCode: params.evidence.reasonCode,
      sourceUpdateTimeMillis: params.evidence.sourceUpdateTimeMillis,
      createdAt: FieldValue.serverTimestamp(),
    });
    return "applied";
  });
}

export async function runHistoricalRelationshipMigrationPage(params: {
  firestore: Firestore;
  runId: string;
  phase: HistoricalMigrationPhase;
  mode: HistoricalMigrationMode;
  cursor?: string | null;
  pageSize?: number;
  authoritativeNow?: Date;
}): Promise<HistoricalMigrationPageResult> {
  if (!params.runId.trim()) throw new Error("migration_run_id_required");
  const pageSize = Math.min(Math.max(params.pageSize ?? 100, 1), 250);
  const collectionName = params.phase === "blocks" ? "userBlocks" : "bookings";
  let query = params.firestore.collection(collectionName)
    .orderBy(FieldPath.documentId()).limit(pageSize);
  if (params.cursor) query = query.startAfter(params.cursor);
  const page = await query.get();
  const evidence = await Promise.all(page.docs.map((snapshot) => params.phase === "blocks" ?
    blockEvidence(snapshot) :
    bookingEvidence(params.firestore, snapshot, params.authoritativeNow ?? new Date())));
  let appliedCount = 0;
  let alreadyAppliedCount = 0;
  let mismatchCount = 0;
  if (params.mode !== "dry-run") {
    for (const item of evidence) {
      const outcome = await applyOrReconcileEvidence({...params, evidence: item});
      if (outcome === "applied") appliedCount += 1;
      if (outcome === "already-applied") alreadyAppliedCount += 1;
      if (outcome === "mismatch") mismatchCount += 1;
    }
  }
  const complete = page.size < pageSize;
  return {
    phase: params.phase,
    mode: params.mode,
    scannedCount: page.size,
    protectedCount: evidence.filter((item) => item.protected).length,
    anomalyCount: evidence.filter((item) => item.anomaly).length,
    appliedCount,
    alreadyAppliedCount,
    mismatchCount,
    nextCursor: complete || page.empty ? null : page.docs.at(-1)?.id ?? null,
    complete,
    findings: evidence.filter((item) => item.anomaly || item.protected).map((item) => ({
      sourceId: item.sourceId,
      pairKey: item.pairKey,
      reasonCode: item.reasonCode,
    })),
  };
}

type MigrationSourceScan = {
  evidence: Array<HistoricalRelationshipEvidence & {phase: HistoricalMigrationPhase}>;
  sourceFingerprint: string;
  bookingCount: number;
  directedBlockCount: number;
};

type FullyScannedDocument = QueryDocumentSnapshot<DocumentData>;

async function scanCollectionFully(params: {
  firestore: Firestore;
  collectionName: string;
  pageSize: number;
}): Promise<FullyScannedDocument[]> {
  const documents: FullyScannedDocument[] = [];
  let cursor: FullyScannedDocument | null = null;
  while (true) {
    let query = params.firestore.collection(params.collectionName)
      .orderBy(FieldPath.documentId()).limit(params.pageSize);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    documents.push(...page.docs);
    if (page.size < params.pageSize) return documents;
    cursor = page.docs.at(-1) ?? null;
  }
}

async function scanMigrationSources(params: {
  firestore: Firestore;
  authoritativeNow: Date;
  pageSize: number;
}): Promise<MigrationSourceScan> {
  const evidence: Array<HistoricalRelationshipEvidence & {phase: HistoricalMigrationPhase}> = [];
  for (const phase of ["blocks", "bookings"] as const) {
    const collectionName = phase === "blocks" ? "userBlocks" : "bookings";
    let cursor: QueryDocumentSnapshot<DocumentData> | null = null;
    while (true) {
      let query = params.firestore.collection(collectionName)
        .orderBy(FieldPath.documentId()).limit(params.pageSize);
      if (cursor) query = query.startAfter(cursor);
      const page = await query.get();
      for (const snapshot of page.docs) {
        const item = phase === "blocks" ? blockEvidence(snapshot) :
          await bookingEvidence(params.firestore, snapshot, params.authoritativeNow);
        evidence.push({...item, phase});
      }
      if (page.size < params.pageSize) break;
      cursor = page.docs.at(-1) ?? null;
    }
  }
  const canonical = evidence.map((item) => ({
    phase: item.phase,
    sourceId: item.sourceId,
    sourceUpdateTimeMillis: item.sourceUpdateTimeMillis,
    pairKey: item.pairKey,
    protected: item.protected,
    blocked: item.blocked,
    anomaly: item.anomaly,
    reasonCode: item.reasonCode,
  }));
  return {
    evidence,
    sourceFingerprint: createHash("sha256").update(JSON.stringify(canonical)).digest("hex"),
    bookingCount: evidence.filter((item) => item.phase === "bookings").length,
    directedBlockCount: evidence.filter((item) => item.phase === "blocks").length,
  };
}

export type IndependentMigrationVerification = {
  migrationVersion: number;
  strategy: "zero-protected-baseline" | "exception-backfill";
  sourceFingerprint: string;
  bookingCount: number;
  directedBlockCount: number;
  requiredEvidenceCount: number;
  anomalyCount: number;
  mismatchCount: number;
};

export type HistoricalRelationshipAudit = {
  auditVersion: number;
  authoritativeAt: string;
  fullTraversal: true;
  sourceFingerprint: string;
  totalHistoricalBookingCount: number;
  currentlyProtectedPaidBookingCount: number;
  acceptedUnpaidBookingCount: number;
  uncertainPaymentStateCount: number;
  openDisputeCount: number;
  pendingRefundCount: number;
  otherProtectedFinancialObligationCount: number;
  existingDirectedBlockCount: number;
  existingRelationshipGuardCount: number;
  inconsistentHistoricalBlockBookingPairCount: number;
  manualReviewCount: number;
};

function sourceBookingId(snapshot: FullyScannedDocument): string {
  const data = snapshot.data();
  const bookingId = typeof data.bookingId === "string" ? data.bookingId.trim() : "";
  return bookingId || snapshot.id;
}

function isOpenStatus(snapshot: FullyScannedDocument, terminal: ReadonlySet<string>): boolean {
  return !terminal.has(status(snapshot.data()));
}

/**
 * Performs a complete, read-only traversal of the authoritative booking,
 * financial, block, and guard sources used to decide migration scope. This
 * function deliberately exposes no Firestore write and is suitable for an
 * operator-side audit after explicit production-read approval.
 */
export async function runReadOnlyHistoricalRelationshipAudit(params: {
  firestore: Firestore;
  authoritativeNow?: Date;
  pageSize?: number;
}): Promise<HistoricalRelationshipAudit> {
  const authoritativeNow = params.authoritativeNow ?? new Date();
  const pageSize = Math.min(Math.max(params.pageSize ?? 100, 1), 250);
  const sourceScan = await scanMigrationSources({
    firestore: params.firestore,
    authoritativeNow,
    pageSize,
  });
  const [disputes, refunds, payouts, reconciliations, obligations, guards] =
    await Promise.all([
      scanCollectionFully({firestore: params.firestore, collectionName: "disputes", pageSize}),
      scanCollectionFully({firestore: params.firestore, collectionName: "refunds", pageSize}),
      scanCollectionFully({
        firestore: params.firestore,
        collectionName: "payoutReadiness",
        pageSize,
      }),
      scanCollectionFully({
        firestore: params.firestore,
        collectionName: "bookingFinancialReconciliation",
        pageSize,
      }),
      scanCollectionFully({
        firestore: params.firestore,
        collectionName: "manualSettlementObligations",
        pageSize,
      }),
      scanCollectionFully({
        firestore: params.firestore,
        collectionName: USER_RELATIONSHIP_GUARDS_COLLECTION,
        pageSize,
      }),
    ]);
  const openDisputes = disputes.filter((item) => isOpenStatus(
    item, new Set(["RESOLVED", "CLOSED", "REJECTED"]),
  ));
  const pendingRefunds = refunds.filter((item) => isOpenStatus(
    item, new Set(["PAID", "PROCESSED", "REFUNDED", "COMPLETED", "CANCELLED"]),
  ));
  const unresolvedPayouts = payouts.filter((item) => isOpenStatus(
    item, new Set(["PAID", "RELEASED", "COMPLETED", "CANCELLED", "NOT_ELIGIBLE"]),
  ));
  const unresolvedReconciliations = reconciliations.filter((item) => isOpenStatus(
    item, new Set(["RESOLVED", "CLEAN", "COMPLETED"]),
  ));
  const unresolvedObligations = obligations.filter((item) => isOpenStatus(
    item, new Set(["COMPLETED", "PAID", "CANCELLED", "RESOLVED"]),
  ));
  const otherFinancialBookingIds = new Set([
    ...unresolvedPayouts.map(sourceBookingId),
    ...unresolvedReconciliations.map(sourceBookingId),
    ...unresolvedObligations.map(sourceBookingId),
  ].filter(Boolean));
  const guardByPair = new Map(guards.map((item) => [item.id, item.data()]));
  const inconsistentSources = new Set<string>();
  for (const item of sourceScan.evidence) {
    if (!item.pairKey) {
      inconsistentSources.add(`${item.phase}:${item.sourceId}`);
      continue;
    }
    if (!item.blocked && !item.protected) continue;
    const guard = guardByPair.get(item.pairKey);
    const directedIds = Array.isArray(guard?.activeDirectedBlockIds) ?
      guard.activeDirectedBlockIds : [];
    if (!guard || (item.blocked && (guard.blocked !== true ||
      !directedIds.includes(item.directedBlockId))) ||
      (item.protected && guard.historicalProtectionBlocked !== true)) {
      inconsistentSources.add(`${item.phase}:${item.sourceId}`);
    }
  }
  const bookingEvidenceItems = sourceScan.evidence.filter((item) => item.phase === "bookings");
  const uncertainBookings = bookingEvidenceItems.filter((item) =>
    item.reasonCode === "PAYMENT_RECONCILIATION_REQUIRED");
  const acceptedUnpaidBookings = bookingEvidenceItems.filter((item) =>
    item.reasonCode === "ACCEPTED_UNPAID_ACCOUNTED");
  const protectedPaidBookings = bookingEvidenceItems.filter((item) => item.protected &&
    !item.anomaly && item.reasonCode !== "PAYMENT_RECONCILIATION_REQUIRED");
  const manualReviewRecords = new Set<string>();
  for (const item of bookingEvidenceItems.filter((entry) => entry.anomaly)) {
    manualReviewRecords.add(`bookings:${item.sourceId}`);
  }
  for (const key of inconsistentSources) manualReviewRecords.add(key);
  for (const item of openDisputes) manualReviewRecords.add(`disputes:${item.id}`);
  for (const item of pendingRefunds) manualReviewRecords.add(`refunds:${item.id}`);
  for (const item of unresolvedPayouts) manualReviewRecords.add(`payoutReadiness:${item.id}`);
  for (const item of unresolvedReconciliations) {
    manualReviewRecords.add(`bookingFinancialReconciliation:${item.id}`);
  }
  for (const item of unresolvedObligations) {
    manualReviewRecords.add(`manualSettlementObligations:${item.id}`);
  }
  return {
    auditVersion: HISTORICAL_RELATIONSHIP_MIGRATION_VERSION,
    authoritativeAt: authoritativeNow.toISOString(),
    fullTraversal: true,
    sourceFingerprint: sourceScan.sourceFingerprint,
    totalHistoricalBookingCount: sourceScan.bookingCount,
    currentlyProtectedPaidBookingCount: protectedPaidBookings.length,
    acceptedUnpaidBookingCount: acceptedUnpaidBookings.length,
    uncertainPaymentStateCount: uncertainBookings.length,
    openDisputeCount: openDisputes.length,
    pendingRefundCount: pendingRefunds.length,
    otherProtectedFinancialObligationCount: otherFinancialBookingIds.size,
    existingDirectedBlockCount: sourceScan.directedBlockCount,
    existingRelationshipGuardCount: guards.length,
    inconsistentHistoricalBlockBookingPairCount: inconsistentSources.size,
    manualReviewCount: manualReviewRecords.size,
  };
}

// ---------------------------------------------------------------------------
// Phase 3B-4d: activation readiness with D3 decisions.
// ---------------------------------------------------------------------------

const ZERO_BASELINE_SAFE_REASONS: ReadonlySet<string> = new Set([
  "NO_PROTECTED_OBLIGATION",
  "ACCEPTED_UNPAID_ACCOUNTED",
]);

export type RelationshipActivationFlaggedRecord = {
  phase: HistoricalMigrationPhase;
  sourceId: string;
  recordKey: string;
  pairKey: string;
  reasonCode: string;
  sourceUpdateTimeMillis: number;
  anomaly: boolean;
  protected: boolean;
  zeroBaselineException: boolean;
};

export type RelationshipActivationUndecidedReason =
  | "NO_DECISION"
  | "STALE_DECISION"
  | "BLOCK_ACTIVATION"
  | "PROTECT_PAIR_WITHOUT_PAIR";

export type RelationshipActivationReadiness = {
  migrationVersion: number;
  strategy: "zero-protected-baseline" | "exception-backfill";
  authoritativeAt: string;
  sourceFingerprint: string;
  bookingCount: number;
  directedBlockCount: number;
  flagged: RelationshipActivationFlaggedRecord[];
  decided: Array<{record: RelationshipActivationFlaggedRecord; decision: RelationshipActivationDecisionDocument}>;
  undecided: Array<{record: RelationshipActivationFlaggedRecord; reason: RelationshipActivationUndecidedReason}>;
  /** Decisions that match no flagged record, or that are not well-formed. */
  extraDecisionKeys: string[];
  invalidDecisionCount: number;
  /** Records that need an evidence marker and guard state before activation. */
  requiredEvidence: Array<{
    phase: HistoricalMigrationPhase;
    sourceId: string;
    pairKey: string;
    protected: boolean;
    blocked: boolean;
    reasonCode: string;
  }>;
  undecidedAnomalyCount: number;
  undecidedExceptionCount: number;
  ready: boolean;
};

type ScannedEvidence = HistoricalRelationshipEvidence & {phase: HistoricalMigrationPhase};

function flaggedKey(phase: HistoricalMigrationPhase, sourceId: string): string {
  return relationshipActivationDecisionId(phase, sourceId);
}

function classifyActivationReadiness(params: {
  scan: MigrationSourceScan;
  strategy: "zero-protected-baseline" | "exception-backfill";
  decisions: ReadonlyArray<unknown>;
  authoritativeNow: Date;
}): RelationshipActivationReadiness {
  const zeroBaseline = params.strategy === "zero-protected-baseline";
  const decisionsByKey = new Map<string, RelationshipActivationDecisionDocument>();
  let invalidDecisionCount = 0;
  for (const raw of params.decisions) {
    const parsed = parseRelationshipActivationDecision(
      (raw ?? null) as Record<string, unknown> | null,
    );
    if (!parsed || decisionsByKey.has(parsed.recordKey)) {
      invalidDecisionCount += 1;
      continue;
    }
    decisionsByKey.set(parsed.recordKey, parsed);
  }

  const flagged: RelationshipActivationFlaggedRecord[] = [];
  const evidenceByKey = new Map<string, ScannedEvidence>();
  for (const item of params.scan.evidence) {
    const exception = zeroBaseline && item.phase === "bookings" &&
      !ZERO_BASELINE_SAFE_REASONS.has(item.reasonCode);
    if (!item.anomaly && !exception) continue;
    const recordKey = flaggedKey(item.phase, item.sourceId);
    evidenceByKey.set(recordKey, item);
    flagged.push({
      phase: item.phase,
      sourceId: item.sourceId,
      recordKey,
      pairKey: item.pairKey,
      reasonCode: item.reasonCode,
      sourceUpdateTimeMillis: item.sourceUpdateTimeMillis,
      anomaly: item.anomaly,
      protected: item.protected,
      zeroBaselineException: exception,
    });
  }

  const decided: RelationshipActivationReadiness["decided"] = [];
  const undecided: RelationshipActivationReadiness["undecided"] = [];
  for (const record of flagged) {
    const decision = decisionsByKey.get(record.recordKey);
    if (!decision) {
      undecided.push({record, reason: "NO_DECISION"});
    } else if (decision.phase !== record.phase || decision.sourceId !== record.sourceId ||
      decision.expectedReasonCode !== record.reasonCode ||
      decision.expectedSourceUpdateTimeMillis !== record.sourceUpdateTimeMillis) {
      undecided.push({record, reason: "STALE_DECISION"});
    } else if (decision.decision === "BLOCK_ACTIVATION") {
      undecided.push({record, reason: "BLOCK_ACTIVATION"});
    } else if (decision.decision === "PROTECT_PAIR" && !record.pairKey) {
      undecided.push({record, reason: "PROTECT_PAIR_WITHOUT_PAIR"});
    } else {
      decided.push({record, decision});
    }
  }
  const extraDecisionKeys = [...decisionsByKey.keys()]
    .filter((key) => !evidenceByKey.has(key)).sort();

  const decidedKeys = new Map(decided.map((entry) => [entry.record.recordKey, entry.decision]));
  const required = params.scan.evidence.filter((item) => {
    const decision = decidedKeys.get(flaggedKey(item.phase, item.sourceId));
    if (item.phase === "blocks") return decision?.decision !== "NO_OBLIGATION";
    if (!zeroBaseline) return true;
    return decision?.decision === "PROTECT_PAIR";
  });
  const undecidedKeys = new Set(undecided.map((entry) => entry.record.recordKey));
  const undecidedAnomalyCount = flagged
    .filter((record) => record.anomaly && undecidedKeys.has(record.recordKey)).length;
  const undecidedExceptionCount = flagged
    .filter((record) => record.zeroBaselineException && undecidedKeys.has(record.recordKey)).length;
  return {
    migrationVersion: HISTORICAL_RELATIONSHIP_MIGRATION_VERSION,
    strategy: params.strategy,
    authoritativeAt: params.authoritativeNow.toISOString(),
    sourceFingerprint: params.scan.sourceFingerprint,
    bookingCount: params.scan.bookingCount,
    directedBlockCount: params.scan.directedBlockCount,
    flagged,
    decided,
    undecided,
    extraDecisionKeys,
    invalidDecisionCount,
    requiredEvidence: required.map((item) => ({
      phase: item.phase,
      sourceId: item.sourceId,
      pairKey: item.pairKey,
      protected: item.protected,
      blocked: item.blocked,
      reasonCode: item.reasonCode,
    })),
    undecidedAnomalyCount,
    undecidedExceptionCount,
    ready: undecided.length === 0 && extraDecisionKeys.length === 0 &&
      invalidDecisionCount === 0 && required.every((item) => item.pairKey !== ""),
  };
}

/**
 * Read-only readiness evaluation for the activation tool's verify step.
 * Scans every directed block and booking twice; refuses if the sources change
 * between the scans. Performs no write, so it can run on a read-only client.
 */
export async function evaluateRelationshipActivationReadiness(params: {
  firestore: Firestore;
  strategy?: "zero-protected-baseline";
  decisions?: ReadonlyArray<unknown>;
  authoritativeNow?: Date;
  pageSize?: number;
  onBetweenScans?: () => Promise<void>;
}): Promise<RelationshipActivationReadiness> {
  const pageSize = Math.min(Math.max(params.pageSize ?? 100, 1), 250);
  const authoritativeNow = params.authoritativeNow ?? new Date();
  const first = await scanMigrationSources({firestore: params.firestore, authoritativeNow, pageSize});
  if (params.onBetweenScans) await params.onBetweenScans();
  const second = await scanMigrationSources({firestore: params.firestore, authoritativeNow, pageSize});
  if (first.sourceFingerprint !== second.sourceFingerprint ||
    first.bookingCount !== second.bookingCount ||
    first.directedBlockCount !== second.directedBlockCount) {
    throw new Error("relationship_migration_concurrent_source_change");
  }
  return classifyActivationReadiness({
    scan: first,
    strategy: params.strategy ?? "zero-protected-baseline",
    decisions: params.decisions ?? [],
    authoritativeNow,
  });
}

/**
 * Applies evidence markers and guard state for specific source records (used
 * by the activation tool for bookings decided PROTECT_PAIR). Same writes as
 * runHistoricalRelationshipMigrationPage in apply mode, for named records.
 */
export async function applyHistoricalEvidenceForSources(params: {
  firestore: Firestore;
  runId: string;
  phase: HistoricalMigrationPhase;
  sourceIds: string[];
  authoritativeNow?: Date;
}): Promise<{applied: number; alreadyApplied: number}> {
  if (!params.runId.trim()) throw new Error("migration_run_id_required");
  const collectionName = params.phase === "blocks" ? "userBlocks" : "bookings";
  let applied = 0;
  let alreadyApplied = 0;
  for (const sourceId of params.sourceIds) {
    const snapshot = await params.firestore.collection(collectionName).doc(sourceId).get();
    if (!snapshot.exists) throw new Error(`migration_source_missing:${params.phase}:${sourceId}`);
    const document = snapshot as QueryDocumentSnapshot<DocumentData>;
    const evidence = params.phase === "blocks" ?
      blockEvidence(document) :
      await bookingEvidence(params.firestore, document, params.authoritativeNow ?? new Date());
    const outcome = await applyOrReconcileEvidence({
      firestore: params.firestore,
      phase: params.phase,
      mode: "apply",
      runId: params.runId,
      evidence,
    });
    if (outcome === "applied") applied += 1;
    if (outcome === "already-applied") alreadyApplied += 1;
  }
  return {applied, alreadyApplied};
}

export type RelationshipMigrationVerificationRecord = IndependentMigrationVerification & {
  flaggedRecordCount: number;
  decidedRecordCount: number;
  decisionSetHash: string;
  attestationId: string;
};

export async function verifyAndRecordRelationshipMigration(params: {
  firestore: Firestore;
  runId: string;
  operatorUid: string;
  strategy: "zero-protected-baseline" | "exception-backfill";
  authoritativeNow?: Date;
  pageSize?: number;
  /** D3 decision documents (relationshipActivationDecisions shape). */
  decisions?: ReadonlyArray<unknown>;
  decisionSetHash?: string;
  attestationId?: string;
  /** Test hook: runs between the two source scans. */
  onBetweenScans?: () => Promise<void>;
}): Promise<RelationshipMigrationVerificationRecord> {
  const runId = params.runId.trim();
  const operatorUid = params.operatorUid.trim();
  if (!runId || !operatorUid) {
    throw new Error("relationship_migration_not_verifiable");
  }
  const pageSize = Math.min(Math.max(params.pageSize ?? 100, 1), 250);
  const authoritativeNow = params.authoritativeNow ?? new Date();
  const first = await scanMigrationSources({
    firestore: params.firestore,
    authoritativeNow,
    pageSize,
  });
  // D3: flagged records with a matching NO_OBLIGATION / PROTECT_PAIR decision
  // are not counted. anomalyCount and mismatchCount below are UNDECIDED counts.
  const readiness = classifyActivationReadiness({
    scan: first,
    strategy: params.strategy,
    decisions: params.decisions ?? [],
    authoritativeNow,
  });
  const requiredKeys = new Set(readiness.requiredEvidence
    .map((item) => flaggedKey(item.phase, item.sourceId)));
  const required = first.evidence.filter((item) =>
    requiredKeys.has(flaggedKey(item.phase, item.sourceId)));
  let mismatchCount = 0;
  const anomalyCount = readiness.undecidedAnomalyCount;
  if (params.strategy === "zero-protected-baseline") {
    mismatchCount += readiness.undecidedExceptionCount;
  }
  mismatchCount += readiness.extraDecisionKeys.length + readiness.invalidDecisionCount;
  for (const item of required) {
    if (!item.pairKey) {
      mismatchCount += 1;
      continue;
    }
    const markerId = `v1_${item.phase}_${item.sourceId}`;
    const [marker, guard] = await Promise.all([
      params.firestore.collection("relationshipMigrationEvidence").doc(markerId).get(),
      params.firestore.collection(USER_RELATIONSHIP_GUARDS_COLLECTION).doc(item.pairKey).get(),
    ]);
    const markerData = marker.data() ?? {};
    const guardData = guard.data() ?? {};
    const directedIds = Array.isArray(guardData.activeDirectedBlockIds) ?
      guardData.activeDirectedBlockIds : [];
    if (!marker.exists || markerData.runId !== runId ||
      Number(markerData.migrationVersion ?? -1) !== HISTORICAL_RELATIONSHIP_MIGRATION_VERSION ||
      markerData.pairKey !== item.pairKey || markerData.protected !== item.protected ||
      markerData.blocked !== item.blocked || markerData.reasonCode !== item.reasonCode ||
      Number(markerData.sourceUpdateTimeMillis ?? -1) !== item.sourceUpdateTimeMillis ||
      !guard.exists ||
      (item.blocked && (guardData.blocked !== true || !directedIds.includes(item.directedBlockId))) ||
      (item.protected && guardData.historicalProtectionBlocked !== true)) {
      mismatchCount += 1;
    }
  }
  const evidenceSnapshot = await params.firestore.collection("relationshipMigrationEvidence")
    .where("runId", "==", runId).get();
  if (evidenceSnapshot.size !== required.length) mismatchCount += 1;
  if (params.onBetweenScans) await params.onBetweenScans();
  const second = await scanMigrationSources({
    firestore: params.firestore,
    authoritativeNow,
    pageSize,
  });
  if (first.sourceFingerprint !== second.sourceFingerprint ||
    first.bookingCount !== second.bookingCount ||
    first.directedBlockCount !== second.directedBlockCount) {
    throw new Error("relationship_migration_concurrent_source_change");
  }
  if (anomalyCount !== 0 || mismatchCount !== 0) {
    throw new Error("relationship_migration_not_verifiable");
  }
  const verification: RelationshipMigrationVerificationRecord = {
    migrationVersion: HISTORICAL_RELATIONSHIP_MIGRATION_VERSION,
    strategy: params.strategy,
    sourceFingerprint: first.sourceFingerprint,
    bookingCount: first.bookingCount,
    directedBlockCount: first.directedBlockCount,
    requiredEvidenceCount: required.length,
    anomalyCount,
    mismatchCount,
    flaggedRecordCount: readiness.flagged.length,
    decidedRecordCount: readiness.decided.length,
    decisionSetHash: (params.decisionSetHash ?? "").trim(),
    attestationId: (params.attestationId ?? "").trim(),
  };
  await params.firestore.doc("_migrations/userRelationshipGuardV1").set({
    schemaVersion: 1,
    runId,
    status: "verified",
    reconciliationPassed: true,
    ...verification,
    verifiedBy: operatorUid,
    verifiedAt: FieldValue.serverTimestamp(),
    verificationValidUntil: new Date(Date.now() + 15 * 60 * 1000),
  }, {merge: false});
  return verification;
}
