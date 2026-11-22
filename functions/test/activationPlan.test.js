// Phase 3B-4d: decisions/attestation file validation and hash stability for
// scripts/lib/activationPlan.js. Pure; no Firebase.
require("./helpers/firebaseTestSafety").assertUnitTestIsolation();
const test = require("node:test");
const assert = require("node:assert/strict");

const plan = require("../scripts/lib/activationPlan.js");
const shape = require("../lib/blocking/relationshipActivationDecisions.js");

function entry(overrides = {}) {
  return {
    phase: "bookings",
    sourceId: "legacy-1",
    expectedReasonCode: "INVALID_OR_LEGACY_BOOKING",
    expectedSourceUpdateTimeMillis: 1763800000000,
    decision: "NO_OBLIGATION",
    note: "owner test booking",
    ...overrides,
  };
}

function file(decisions, extra = {}) {
  return {schemaVersion: 1, decidedByUid: "owner-uid", decisions, ...extra};
}

function validAttestation(overrides = {}) {
  return {
    ...plan.attestationTemplate(),
    attestedByUid: "owner-uid",
    attestedByEmail: "owner@example.com",
    attestedAt: "2026-11-23T10:00:00+05:30",
    ...overrides,
  };
}

function problemsOf(fn) {
  try {
    fn();
  } catch (error) {
    assert.ok(error instanceof plan.ActivationInputError, String(error));
    return error.problems;
  }
  assert.fail("expected ActivationInputError");
}

test("decisions file: valid input is normalized and sorted by record key", () => {
  const parsed = plan.parseDecisionsFile(file([
    entry({sourceId: "z-1"}),
    entry({phase: "blocks", sourceId: "a_b", expectedReasonCode: "INVALID_DIRECTED_BLOCK"}),
    entry({sourceId: "a-1", decision: "PROTECT_PAIR", note: "  keep  "}),
  ]), shape);
  assert.equal(parsed.decidedByUid, "owner-uid");
  assert.deepEqual(parsed.entries.map((item) => item.recordKey),
    ["blocks__a_b", "bookings__a-1", "bookings__z-1"]);
  assert.equal(parsed.entries[1].note, "keep");
  assert.deepEqual(plan.parseDecisionsFile(file([]), shape).entries, []);
});

test("decisions file: every invalid field is reported", () => {
  const problems = problemsOf(() => plan.parseDecisionsFile({
    schemaVersion: 2,
    decidedByUid: "<owner Firebase UID>",
    decisions: [
      entry({phase: "posts"}),
      entry({sourceId: ""}),
      entry({sourceId: "a/b"}),
      entry({expectedReasonCode: ""}),
      entry({expectedSourceUpdateTimeMillis: "1763800000000"}),
      entry({expectedSourceUpdateTimeMillis: 1.5}),
      entry({decision: "MAYBE"}),
      entry({sourceId: "dup"}),
      entry({sourceId: "dup"}),
      {...entry({sourceId: "extra"}), surprise: true},
      "not-an-object",
    ],
  }, shape));
  const joined = problems.join("\n");
  for (const pattern of [
    /schemaVersion must be 1/,
    /decidedByUid must be the owner's Firebase UID/,
    /decisions\[0\]\.phase/,
    /decisions\[1\]\.sourceId is required/,
    /decisions\[2\]\.sourceId is required/,
    /decisions\[3\]\.expectedReasonCode is required/,
    /decisions\[4\]\.expectedSourceUpdateTimeMillis/,
    /decisions\[5\]\.expectedSourceUpdateTimeMillis/,
    /decisions\[6\]\.decision must be one of NO_OBLIGATION \| PROTECT_PAIR \| BLOCK_ACTIVATION/,
    /decisions\[8\] duplicates bookings__dup/,
    /decisions\[9\] has unknown field "surprise"/,
    /decisions\[10\] must be an object/,
  ]) {
    assert.match(joined, pattern);
  }
  assert.match(problemsOf(() => plan.parseDecisionsFile([], shape)).join(), /JSON object/);
  assert.match(problemsOf(() => plan.parseDecisionsFile({schemaVersion: 1, decidedByUid: "u"}, shape)).join(),
    /decisions must be an array/);
});

test("the unfilled decisions template is rejected", () => {
  const template = plan.decisionsTemplate([{
    phase: "bookings", sourceId: "legacy-1", reasonCode: "INVALID_OR_LEGACY_BOOKING",
    sourceUpdateTimeMillis: 1763800000000, pairKey: "pair_x", anomaly: true,
  }]);
  const problems = problemsOf(() => plan.parseDecisionsFile(template, shape)).join("\n");
  assert.match(problems, /decidedByUid/);
  assert.match(problems, /decision must be one of/);
});

test("decision set hash: stable across order and notes, sensitive to decisions", () => {
  const a = plan.parseDecisionsFile(file([entry({sourceId: "x"}), entry({sourceId: "y"})]), shape);
  const b = plan.parseDecisionsFile(file([entry({sourceId: "y", note: "other"}), entry({sourceId: "x"})]), shape);
  const hash = plan.decisionSetHash(a.decidedByUid, a.entries);
  assert.match(hash, /^[0-9a-f]{64}$/);
  assert.equal(plan.decisionSetHash(b.decidedByUid, b.entries), hash);
  const changed = plan.parseDecisionsFile(file([entry({sourceId: "x", decision: "PROTECT_PAIR"}), entry({sourceId: "y"})]), shape);
  assert.notEqual(plan.decisionSetHash(changed.decidedByUid, changed.entries), hash);
  assert.notEqual(plan.decisionSetHash("someone-else", a.entries), hash);
  const time = plan.parseDecisionsFile(file([entry({sourceId: "x", expectedSourceUpdateTimeMillis: 1763800000001}), entry({sourceId: "y"})]), shape);
  assert.notEqual(plan.decisionSetHash(time.decidedByUid, time.entries), hash);
  // Pinned value: a change here means previously recorded hashes no longer match.
  const pinned = plan.parseDecisionsFile(file([entry()]), shape);
  assert.equal(plan.decisionSetHash(pinned.decidedByUid, pinned.entries),
    plan.sha256Hex('{"decidedByUid":"owner-uid","decisions":[{"decision":"NO_OBLIGATION",' +
      '"expectedReasonCode":"INVALID_OR_LEGACY_BOOKING","expectedSourceUpdateTimeMillis":1763800000000,' +
      '"phase":"bookings","sourceId":"legacy-1"}]}'));
});

test("decision documents use the shared shape and pass its strict parser", () => {
  const parsed = plan.parseDecisionsFile(file([entry(), entry({sourceId: "p", decision: "PROTECT_PAIR"})]), shape);
  const setHash = plan.decisionSetHash(parsed.decidedByUid, parsed.entries);
  const documents = plan.buildDecisionDocuments({
    parsed,
    pairKeyByRecordKey: new Map([["bookings__p", "pair_abc"]]),
    decidedByEmail: "owner@example.com",
    setHash,
    shape,
  });
  for (const document of documents) {
    const reparsed = shape.parseRelationshipActivationDecision(document);
    assert.ok(reparsed);
    assert.equal(reparsed.recordKey, shape.relationshipActivationDecisionId(document.phase, document.sourceId));
    assert.equal(reparsed.decisionSetHash, setHash);
  }
  assert.equal(documents.find((document) => document.sourceId === "p").pairKey, "pair_abc");
});

test("attestation file: valid input, stable hash and id", () => {
  const first = plan.parseAttestationFile(validAttestation());
  assert.match(first.attestationHash, /^[0-9a-f]{64}$/);
  assert.equal(first.attestationId, `att_${first.attestationHash.slice(0, 16)}`);
  // Key order and time-zone spelling do not change the hash.
  const reordered = Object.fromEntries(Object.entries(validAttestation({
    attestedAt: "2026-11-23T04:30:00.000Z",
  })).reverse());
  assert.equal(plan.parseAttestationFile(reordered).attestationHash, first.attestationHash);
  assert.notEqual(plan.parseAttestationFile(validAttestation({attestedByEmail: "other@example.com"})).attestationHash,
    first.attestationHash);
});

test("attestation file: every invalid field is reported; the template is rejected", () => {
  const problems = problemsOf(() => plan.parseAttestationFile({
    schemaVersion: 0,
    attestedByUid: "",
    attestedByEmail: "not-an-email",
    statement: "I attest.",
    scope: {noRealUserBookings: true, noRealUserPayments: false, extraScope: true},
    attestedAt: "yesterday",
    signature: "x",
  })).join("\n");
  for (const pattern of [
    /schemaVersion must be 1/, /attestedByUid is required/, /attestedByEmail must be an email/,
    /statement must be exactly/, /attestedAt must be an ISO date-time/,
    /scope\.noRealUserPayments must be true/, /scope\.noRealUserDisputes must be true/,
    /scope has unknown field "extraScope"/, /unknown field "signature"/,
  ]) {
    assert.match(problems, pattern);
  }
  assert.ok(problemsOf(() => plan.parseAttestationFile(plan.attestationTemplate())).length >= 2);
});

test("activation ids are deterministic and change with any input", () => {
  const input = {fingerprint: "a".repeat(64), attestationHash: "b".repeat(64), setHash: "c".repeat(64)};
  const ids = plan.deriveActivationIds(input);
  assert.deepEqual(plan.deriveActivationIds(input), ids);
  assert.match(ids.runId, /^act_aaaaaaaaaaaa_[0-9a-f]{8}$/);
  assert.match(ids.auditId, /^activate_aaaaaaaaaaaa_[0-9a-f]{8}$/);
  assert.notEqual(plan.deriveActivationIds({...input, setHash: "d".repeat(64)}).auditId, ids.auditId);
  assert.notEqual(plan.deriveActivationIds({...input, attestationHash: "e".repeat(64)}).auditId, ids.auditId);
});

test("planned writes list every document path in order", () => {
  const writes = plan.plannedActivationWrites({
    readiness: {requiredEvidence: [{phase: "blocks", sourceId: "a_b", pairKey: "pair_1", protected: false}]},
    decisionDocuments: [{recordKey: "bookings__legacy-1"}],
    attestationId: "att_1",
    runId: "act_x",
    auditId: "activate_x",
  });
  assert.deepEqual(writes.paths, [
    "relationshipActivationDecisions/bookings__legacy-1",
    "blockingActivationAttestations/att_1",
    "relationshipMigrationEvidence/v1_blocks_a_b",
    "userRelationshipGuards/pair_1",
    "_migrations/userRelationshipGuardV1",
    "userBlockingActivationAudit/activate_x",
    "_rollouts/userBlockingV1",
  ]);
});
