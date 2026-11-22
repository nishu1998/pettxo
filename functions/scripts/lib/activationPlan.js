"use strict";

/**
 * Pure helpers for scripts/blocking_activation.js (Phase 3B-4d).
 * No Firebase, network or filesystem access here, so everything is unit-tested.
 *
 * Decision documents use the single shape defined in
 * src/blocking/relationshipActivationDecisions.ts; callers pass that compiled
 * module in so this file never defines a second shape.
 */

const {createHash} = require("node:crypto");

const DECISIONS_FILE_SCHEMA_VERSION = 1;
const ATTESTATION_FILE_SCHEMA_VERSION = 1;
const DECISION_VALUES = ["NO_OBLIGATION", "PROTECT_PAIR", "BLOCK_ACTIVATION"];
const PHASES = ["bookings", "blocks"];
const ATTESTATION_SCOPE_KEYS = [
  "noRealUserBookings",
  "noRealUserPayments",
  "noRealUserDisputes",
  "noRealUserRefunds",
];
const ATTESTATION_STATEMENT =
  "I attest that no real-user bookings, payments, disputes or refunds exist in Pettxo production. " +
  "This attestation replaces the production historical audit for user-blocking activation.";

class ActivationInputError extends Error {
  constructor(problems) {
    super(`invalid input:\n  - ${problems.join("\n  - ")}`);
    this.name = "ActivationInputError";
    this.problems = problems;
  }
}

/** JSON with object keys sorted at every level: stable input for hashing. */
function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function sha256Hex(text) {
  return createHash("sha256").update(text).digest("hex");
}

function text(value) {
  return typeof value === "string" ? value.trim() : "";
}

function isPlainObject(value) {
  return value != null && typeof value === "object" && !Array.isArray(value);
}

/**
 * Validates a decisions file. Returns normalized entries sorted by record key.
 * @param {unknown} raw parsed JSON
 * @param {{relationshipActivationDecisionId: (phase: string, sourceId: string) => string}} shape
 */
function parseDecisionsFile(raw, shape) {
  const problems = [];
  if (!isPlainObject(raw)) throw new ActivationInputError(["decisions file must be a JSON object"]);
  if (raw.schemaVersion !== DECISIONS_FILE_SCHEMA_VERSION) {
    problems.push(`schemaVersion must be ${DECISIONS_FILE_SCHEMA_VERSION}`);
  }
  const decidedByUid = text(raw.decidedByUid);
  if (!decidedByUid || decidedByUid.includes("/") || decidedByUid.startsWith("<")) {
    problems.push("decidedByUid must be the owner's Firebase UID");
  }
  if (!Array.isArray(raw.decisions)) {
    problems.push("decisions must be an array (use [] when verify flagged nothing)");
  }
  const allowedEntryKeys = new Set([
    "phase", "sourceId", "expectedReasonCode", "expectedSourceUpdateTimeMillis",
    "decision", "note", "pairKey", "anomaly",
  ]);
  const entries = [];
  const seen = new Set();
  for (const [index, entry] of (Array.isArray(raw.decisions) ? raw.decisions : []).entries()) {
    const where = `decisions[${index}]`;
    if (!isPlainObject(entry)) {
      problems.push(`${where} must be an object`);
      continue;
    }
    for (const key of Object.keys(entry)) {
      if (!allowedEntryKeys.has(key)) problems.push(`${where} has unknown field "${key}"`);
    }
    const phase = text(entry.phase);
    const sourceId = text(entry.sourceId);
    const expectedReasonCode = text(entry.expectedReasonCode);
    const decision = text(entry.decision);
    const millis = entry.expectedSourceUpdateTimeMillis;
    if (!PHASES.includes(phase)) problems.push(`${where}.phase must be one of ${PHASES.join(", ")}`);
    if (!sourceId || sourceId.includes("/")) problems.push(`${where}.sourceId is required`);
    if (!expectedReasonCode) problems.push(`${where}.expectedReasonCode is required`);
    if (!Number.isSafeInteger(millis) || millis <= 0) {
      problems.push(`${where}.expectedSourceUpdateTimeMillis must be the integer printed by verify`);
    }
    if (!DECISION_VALUES.includes(decision)) {
      problems.push(`${where}.decision must be one of ${DECISION_VALUES.join(" | ")}`);
    }
    if (!PHASES.includes(phase) || !sourceId || sourceId.includes("/")) continue;
    const recordKey = shape.relationshipActivationDecisionId(phase, sourceId);
    if (seen.has(recordKey)) problems.push(`${where} duplicates ${recordKey}`);
    seen.add(recordKey);
    entries.push({
      phase,
      sourceId,
      recordKey,
      expectedReasonCode,
      expectedSourceUpdateTimeMillis: millis,
      decision,
      note: text(entry.note),
    });
  }
  if (problems.length > 0) throw new ActivationInputError(problems);
  entries.sort((left, right) => left.recordKey.localeCompare(right.recordKey));
  return {schemaVersion: DECISIONS_FILE_SCHEMA_VERSION, decidedByUid, entries};
}

/** Hash over the decision-relevant fields only (not notes), stable for any order. */
function decisionSetHash(decidedByUid, entries) {
  const canonical = [...entries]
    .sort((left, right) => left.recordKey.localeCompare(right.recordKey))
    .map((entry) => ({
      phase: entry.phase,
      sourceId: entry.sourceId,
      expectedReasonCode: entry.expectedReasonCode,
      expectedSourceUpdateTimeMillis: entry.expectedSourceUpdateTimeMillis,
      decision: entry.decision,
    }));
  return sha256Hex(canonicalJson({decidedByUid, decisions: canonical}));
}

/**
 * Builds relationshipActivationDecisions documents in the shared shape and
 * checks each with the shared strict parser.
 */
function buildDecisionDocuments({parsed, pairKeyByRecordKey, decidedByEmail, setHash, shape}) {
  return parsed.entries.map((entry) => {
    const document = {
      schemaVersion: 1,
      phase: entry.phase,
      sourceId: entry.sourceId,
      recordKey: entry.recordKey,
      pairKey: pairKeyByRecordKey.get(entry.recordKey) ?? "",
      expectedReasonCode: entry.expectedReasonCode,
      expectedSourceUpdateTimeMillis: entry.expectedSourceUpdateTimeMillis,
      decision: entry.decision,
      decidedByUid: parsed.decidedByUid,
      decidedByEmail: text(decidedByEmail),
      note: entry.note,
      decisionSetHash: setHash,
    };
    if (!shape.parseRelationshipActivationDecision(document)) {
      throw new ActivationInputError([`decision ${entry.recordKey} does not match the shared decision shape`]);
    }
    return document;
  });
}

function parseAttestationFile(raw) {
  const problems = [];
  if (!isPlainObject(raw)) throw new ActivationInputError(["attestation file must be a JSON object"]);
  if (raw.schemaVersion !== ATTESTATION_FILE_SCHEMA_VERSION) {
    problems.push(`schemaVersion must be ${ATTESTATION_FILE_SCHEMA_VERSION}`);
  }
  const attestedByUid = text(raw.attestedByUid);
  const attestedByEmail = text(raw.attestedByEmail);
  const statement = text(raw.statement);
  const attestedAt = text(raw.attestedAt);
  if (!attestedByUid || attestedByUid.startsWith("<")) problems.push("attestedByUid is required");
  if (!attestedByEmail || !attestedByEmail.includes("@")) problems.push("attestedByEmail must be an email address");
  if (statement !== ATTESTATION_STATEMENT) {
    problems.push("statement must be exactly the text written by the template command");
  }
  if (!attestedAt || Number.isNaN(Date.parse(attestedAt))) problems.push("attestedAt must be an ISO date-time");
  const scope = isPlainObject(raw.scope) ? raw.scope : {};
  for (const key of ATTESTATION_SCOPE_KEYS) {
    if (scope[key] !== true) problems.push(`scope.${key} must be true`);
  }
  for (const key of Object.keys(scope)) {
    if (!ATTESTATION_SCOPE_KEYS.includes(key)) problems.push(`scope has unknown field "${key}"`);
  }
  for (const key of Object.keys(raw)) {
    if (!["schemaVersion", "attestedByUid", "attestedByEmail", "statement", "scope", "attestedAt"].includes(key)) {
      problems.push(`unknown field "${key}"`);
    }
  }
  if (problems.length > 0) throw new ActivationInputError(problems);
  const attestation = {
    schemaVersion: ATTESTATION_FILE_SCHEMA_VERSION,
    attestedByUid,
    attestedByEmail,
    statement,
    scope: Object.fromEntries(ATTESTATION_SCOPE_KEYS.map((key) => [key, true])),
    attestedAt: new Date(attestedAt).toISOString(),
  };
  const attestationHash = sha256Hex(canonicalJson(attestation));
  return {attestation, attestationHash, attestationId: `att_${attestationHash.slice(0, 16)}`};
}

function deriveActivationIds({fingerprint, attestationHash, setHash}) {
  const suffix = `${fingerprint.slice(0, 12)}_${sha256Hex(`${attestationHash}:${setHash}`).slice(0, 8)}`;
  return {runId: `act_${suffix}`, auditId: `activate_${suffix}`};
}

function decisionsTemplate(flagged = []) {
  return {
    schemaVersion: DECISIONS_FILE_SCHEMA_VERSION,
    decidedByUid: "<owner Firebase UID>",
    decisions: flagged.map((record) => ({
      phase: record.phase,
      sourceId: record.sourceId,
      expectedReasonCode: record.reasonCode,
      expectedSourceUpdateTimeMillis: record.sourceUpdateTimeMillis,
      pairKey: record.pairKey,
      anomaly: record.anomaly,
      decision: "<NO_OBLIGATION | PROTECT_PAIR | BLOCK_ACTIVATION>",
      note: "",
    })),
  };
}

function attestationTemplate() {
  return {
    schemaVersion: ATTESTATION_FILE_SCHEMA_VERSION,
    attestedByUid: "<owner Firebase UID>",
    attestedByEmail: "<owner email>",
    statement: ATTESTATION_STATEMENT,
    scope: Object.fromEntries(ATTESTATION_SCOPE_KEYS.map((key) => [key, true])),
    attestedAt: "<ISO date-time, e.g. 2026-11-23T10:00:00+05:30>",
  };
}

/** Exact document paths an activation would write, in order. */
function plannedActivationWrites({readiness, decisionDocuments, attestationId, runId, auditId}) {
  const paths = [];
  for (const document of decisionDocuments) {
    paths.push(`relationshipActivationDecisions/${document.recordKey}`);
  }
  paths.push(`blockingActivationAttestations/${attestationId}`);
  for (const item of readiness.requiredEvidence) {
    paths.push(`relationshipMigrationEvidence/v1_${item.phase}_${item.sourceId}`);
    paths.push(`userRelationshipGuards/${item.pairKey}`);
  }
  paths.push("_migrations/userRelationshipGuardV1");
  paths.push(`userBlockingActivationAudit/${auditId}`);
  paths.push("_rollouts/userBlockingV1");
  return {paths, runId};
}

function readinessSummary(readiness) {
  const byReason = {};
  for (const record of readiness.flagged) byReason[record.reasonCode] = (byReason[record.reasonCode] ?? 0) + 1;
  return {
    sourceFingerprint: readiness.sourceFingerprint,
    fingerprint12: readiness.sourceFingerprint.slice(0, 12),
    bookingsScanned: readiness.bookingCount,
    directedBlocks: readiness.directedBlockCount,
    flaggedRecords: readiness.flagged.length,
    flaggedByReason: byReason,
    decidedRecords: readiness.decided.length,
    undecidedRecords: readiness.undecided.map((entry) => ({
      recordKey: entry.record.recordKey,
      reason: entry.reason,
    })),
    extraDecisions: readiness.extraDecisionKeys,
    invalidDecisions: readiness.invalidDecisionCount,
    evidenceMarkersToWrite: readiness.requiredEvidence.length,
    protectionMarksToWrite: readiness.requiredEvidence.filter((item) => item.protected).length,
    ready: readiness.ready,
  };
}

module.exports = {
  ATTESTATION_STATEMENT,
  ActivationInputError,
  canonicalJson,
  sha256Hex,
  parseDecisionsFile,
  decisionSetHash,
  buildDecisionDocuments,
  parseAttestationFile,
  deriveActivationIds,
  decisionsTemplate,
  attestationTemplate,
  plannedActivationWrites,
  readinessSummary,
};
