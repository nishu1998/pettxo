/**
 * D3 (Phase 3B-4): per-record Super Admin decisions for malformed or
 * old-format records found while preparing blocking activation.
 *
 * Decisions are stored separately from the records they describe; the
 * original records are never changed. This module is the single definition of
 * the decision document shape. The runtime (blockUserV1 /
 * getUserRelationshipStateV1) reads it, and the 3B-4d activation tool writes
 * it. Clients cannot read or write the collection (no rules match, so
 * Firestore denies by default).
 */

export const RELATIONSHIP_ACTIVATION_DECISIONS_COLLECTION =
  "relationshipActivationDecisions";
export const RELATIONSHIP_ACTIVATION_DECISION_SCHEMA_VERSION = 1;

export const RELATIONSHIP_ACTIVATION_DECISION_VALUES = [
  "NO_OBLIGATION",
  "PROTECT_PAIR",
  "BLOCK_ACTIVATION",
] as const;
export type RelationshipActivationDecisionValue =
  typeof RELATIONSHIP_ACTIVATION_DECISION_VALUES[number];

export const RELATIONSHIP_ACTIVATION_DECISION_PHASES = ["bookings", "blocks"] as const;
export type RelationshipActivationDecisionPhase =
  typeof RELATIONSHIP_ACTIVATION_DECISION_PHASES[number];

/** Reasons that live booking state cannot re-judge (the record is unparsable). */
export const UNPARSABLE_HISTORICAL_REASON_CODES: ReadonlySet<string> = new Set([
  "INVALID_OR_LEGACY_BOOKING",
  "INVALID_BOOKING_PARTICIPANTS",
  "INVALID_DIRECTED_BLOCK",
]);

/**
 * Stored at relationshipActivationDecisions/{phase}__{sourceId}.
 * The decision is bound to the record's reason code and update time as seen
 * by the migration scan; a later change to the record makes it stale.
 */
export type RelationshipActivationDecisionDocument = {
  schemaVersion: 1;
  phase: RelationshipActivationDecisionPhase;
  sourceId: string;
  recordKey: string;
  pairKey: string;
  expectedReasonCode: string;
  expectedSourceUpdateTimeMillis: number;
  decision: RelationshipActivationDecisionValue;
  decidedByUid: string;
  decidedByEmail: string;
  note: string;
  decisionSetHash: string;
  decidedAt: unknown;
};

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function relationshipActivationDecisionId(
  phase: RelationshipActivationDecisionPhase,
  sourceId: string,
): string {
  const id = sourceId.trim();
  if (!RELATIONSHIP_ACTIVATION_DECISION_PHASES.includes(phase) || !id || id.includes("/")) {
    throw new Error("invalid_relationship_activation_decision_key");
  }
  return `${phase}__${id}`;
}

/** Strict parse; returns null for anything that is not a well-formed decision. */
export function parseRelationshipActivationDecision(
  data: Record<string, unknown> | undefined | null,
): RelationshipActivationDecisionDocument | null {
  if (!data || data.schemaVersion !== RELATIONSHIP_ACTIVATION_DECISION_SCHEMA_VERSION) return null;
  const phase = text(data.phase) as RelationshipActivationDecisionPhase;
  const decision = text(data.decision) as RelationshipActivationDecisionValue;
  const sourceId = text(data.sourceId);
  const expectedReasonCode = text(data.expectedReasonCode);
  const expectedSourceUpdateTimeMillis = Number(data.expectedSourceUpdateTimeMillis);
  if (!RELATIONSHIP_ACTIVATION_DECISION_PHASES.includes(phase) ||
    !RELATIONSHIP_ACTIVATION_DECISION_VALUES.includes(decision) ||
    !sourceId || !expectedReasonCode ||
    !Number.isFinite(expectedSourceUpdateTimeMillis) ||
    text(data.recordKey) !== relationshipActivationDecisionId(phase, sourceId) ||
    !text(data.decidedByUid)) {
    return null;
  }
  return {
    schemaVersion: 1,
    phase,
    sourceId,
    recordKey: text(data.recordKey),
    pairKey: text(data.pairKey),
    expectedReasonCode,
    expectedSourceUpdateTimeMillis,
    decision,
    decidedByUid: text(data.decidedByUid),
    decidedByEmail: text(data.decidedByEmail),
    note: text(data.note),
    decisionSetHash: text(data.decisionSetHash),
    decidedAt: data.decidedAt ?? null,
  };
}

/**
 * True only for a well-formed NO_OBLIGATION decision that matches the record
 * exactly (phase, source, reason code and the update time the migration saw).
 */
export function decisionReleasesRecord(
  decision: RelationshipActivationDecisionDocument | null,
  record: {
    phase: RelationshipActivationDecisionPhase;
    sourceId: string;
    reasonCode: string;
    sourceUpdateTimeMillis: number;
  },
): boolean {
  return decision != null &&
    decision.decision === "NO_OBLIGATION" &&
    decision.phase === record.phase &&
    decision.sourceId === record.sourceId &&
    decision.expectedReasonCode === record.reasonCode &&
    decision.expectedSourceUpdateTimeMillis === record.sourceUpdateTimeMillis;
}
