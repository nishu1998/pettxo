// Phase 3B-4d: emulator rehearsal of scripts/blocking_activation.js.
// Every test uses its own demo-* project, because the gate documents are
// global per project.
const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({
  services: ["firestore"],
  projectId: "demo-activation-rehearsal",
});
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {randomUUID} = require("node:crypto");
const {Writable} = require("node:stream");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const enabled = firebaseEmulator.enabled;
const OWNER = "owner-uid";
const NOT_ADMIN = "staff-uid";

let tool;
let fixtures;
let userBlocking;
let relationshipGuard;
let plan;

function capture() {
  let text = "";
  const stream = new Writable({
    write(chunk, _encoding, callback) {
      text += chunk.toString();
      callback();
    },
  });
  return {stream, text: () => text};
}

function assignPair(booking, parentId, providerId) {
  booking.parentId = parentId;
  booking.customerId = parentId;
  booking.providerId = providerId;
  booking.serviceOwnerId = providerId;
  booking.participantIds = [parentId, providerId];
  booking.participants.parent.parentId = parentId;
  booking.participants.provider.providerId = providerId;
  booking.service.providerId = providerId;
  for (const slot of booking.schedule?.slots ?? []) slot.providerId = providerId;
  return booking;
}

async function project(name) {
  const projectId = `demo-act-${name}-${randomUUID().slice(0, 6)}`;
  const app = initializeApp({projectId}, `seed-${projectId}`);
  const db = getFirestore(app);
  db.settings({ignoreUndefinedProperties: true});
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "activation-"));
  return {
    projectId,
    db,
    dir,
    async close() {
      await db.terminate();
      await deleteApp(app);
      fs.rmSync(dir, {recursive: true, force: true});
    },
  };
}

/** Production-like test data: one legacy booking, one confirmed booking, one settled booking, one block. */
async function seed(ctx) {
  const confirmed = assignPair(fixtures.buildConfirmedSlotBookingFixture(), "cust-a", "prov-b");
  const settled = assignPair(fixtures.buildCompletedFinalBookingFixture(), "cust-c", "prov-d");
  settled.lifecycle.reviewWindowEndsAt = new Date("2026-07-25T00:00:00.000Z");
  settled.lifecycle.disputeDeadlineAt = new Date("2026-07-25T00:00:00.000Z");
  settled.dispute.status = "resolved";
  settled.payout.status = "held";
  settled.payment.status = "paid";
  await Promise.all([
    ctx.db.doc(`users/${OWNER}`).set({uid: OWNER, role: "admin", adminRole: "superAdmin"}),
    ctx.db.doc(`users/${NOT_ADMIN}`).set({uid: NOT_ADMIN, role: "admin", adminRole: "customerSupportAdmin"}),
    ...["cust-a", "prov-b", "cust-c", "prov-d", "blk-e", "blk-f"].map((uid) =>
      ctx.db.doc(`users/${uid}`).set({uid, accountStatus: "active"})),
    ctx.db.doc("bookings/legacy-1").set({customerId: "legacy-c", serviceOwnerId: "legacy-p", status: "confirmed"}),
    ctx.db.doc("bookings/confirmed-1").set(confirmed),
    ctx.db.doc("bookings/settled-1").set(settled),
    ctx.db.doc("userBlocks/blk-e_blk-f").set({ownerUserId: "blk-e", blockedUserId: "blk-f", createdAt: new Date()}),
  ]);
}

function attestationFile(ctx, overrides = {}) {
  const file = path.join(ctx.dir, `attestation-${randomUUID().slice(0, 6)}.json`);
  fs.writeFileSync(file, JSON.stringify({
    ...plan.attestationTemplate(),
    attestedByUid: OWNER,
    attestedByEmail: "owner@example.com",
    attestedAt: "2026-11-23T10:00:00+05:30",
    ...overrides,
  }), {mode: 0o600});
  return file;
}

function decisionsFile(ctx, decisions, decidedByUid = OWNER) {
  const file = path.join(ctx.dir, `decisions-${randomUUID().slice(0, 6)}.json`);
  fs.writeFileSync(file, JSON.stringify({schemaVersion: 1, decidedByUid, decisions}), {mode: 0o600});
  return file;
}

async function run(ctx, args, deps = {}) {
  const out = capture();
  const err = capture();
  const outcome = await tool.runActivationCli({
    argv: [args[0], `--project=${ctx.projectId}`, ...args.slice(1)],
    env: {FIRESTORE_EMULATOR_HOST: process.env.FIRESTORE_EMULATOR_HOST},
    stdout: out.stream,
    stderr: err.stream,
    deps: {
      gitState: () => ({sha: "test-sha", dirty: false, libBuiltFromHead: true}),
      readLine: async () => "",
      ...deps,
    },
  });
  return {...outcome, stdout: out.text(), stderr: err.text()};
}

async function verifyFingerprint(ctx, decisions) {
  const args = ["verify"];
  if (decisions) args.push(`--decisions=${decisions}`);
  const result = await run(ctx, args);
  assert.equal(result.exitCode, 0, result.stderr);
  return result.result;
}

/** Decisions for the seeded flagged records, from verify output. */
function standardDecisions(readiness, overrides = {}) {
  return plan.decisionsTemplate(readiness.flagged).decisions.map((entry) => ({
    ...entry,
    decision: entry.sourceId === "confirmed-1" ? "PROTECT_PAIR" : "NO_OBLIGATION",
    note: `rehearsal ${entry.sourceId}`,
    ...(overrides[entry.sourceId] ?? {}),
  }));
}

async function noActivationWrites(ctx) {
  for (const collection of ["_rollouts", "_migrations", "userBlockingActivationAudit",
    "relationshipActivationDecisions", "blockingActivationAttestations", "relationshipMigrationEvidence"]) {
    assert.equal((await ctx.db.collection(collection).get()).size, 0, `${collection} must be empty`);
  }
}

test.before(() => {
  if (!enabled) return;
  tool = require("../scripts/blocking_activation.js");
  plan = require("../scripts/lib/activationPlan.js");
  fixtures = require("../lib/booking/schema/bookingFixtures.js");
  userBlocking = require("../lib/blocking/userBlocking.js");
  relationshipGuard = require("../lib/blocking/relationshipGuard.js");
});

test("full rehearsal: verify, decide, activate, replay, block, deactivate", {skip: !enabled}, async () => {
  const ctx = await project("full");
  try {
    await seed(ctx);

    const status = await run(ctx, ["status"]);
    assert.equal(status.exitCode, 0, status.stderr);
    assert.equal(status.result.state.enabled, false);
    assert.match(status.stdout, /REMINDER: .*gcloud auth application-default revoke/);

    // 1. Verify without decisions: two flagged records, not ready.
    const flaggedOut = path.join(ctx.dir, "flagged.json");
    const first = await run(ctx, ["verify", `--flagged-out=${flaggedOut}`]);
    assert.equal(first.exitCode, 0, first.stderr);
    const readiness = first.result.readiness;
    assert.equal(readiness.ready, false);
    assert.deepEqual(readiness.flagged.map((record) => [record.sourceId, record.reasonCode]).sort(), [
      ["confirmed-1", "PROTECTED_STATE_CONFIRMED"],
      ["legacy-1", "INVALID_OR_LEGACY_BOOKING"],
    ]);
    assert.match(first.stdout, /NOT READY/);
    assert.match(first.stdout, /"expectedSourceUpdateTimeMillis": \d+/);
    assert.equal(fs.statSync(flaggedOut).mode & 0o777, 0o600);
    const template = JSON.parse(fs.readFileSync(flaggedOut, "utf8"));
    assert.equal(template.decisions.length, 2);
    await noActivationWrites(ctx);

    // 2. Decide and re-verify: ready.
    const decisions = decisionsFile(ctx, standardDecisions(readiness));
    const attestation = attestationFile(ctx);
    const second = await verifyFingerprint(ctx, decisions);
    assert.equal(second.readiness.ready, true, JSON.stringify(second.summary));
    const fp12 = second.summary.fingerprint12;
    await noActivationWrites(ctx);

    // 3. Activate with the typed confirmation.
    const prompts = [];
    const activated = await run(ctx, [
      "activate", `--decisions=${decisions}`, `--attestation=${attestation}`, `--confirm=${fp12}`,
    ], {readLine: async (prompt) => {
      prompts.push(prompt);
      return `ACTIVATE ${fp12}`;
    }});
    assert.equal(activated.exitCode, 0, activated.stderr + activated.stdout);
    assert.equal(prompts.length, 1);
    assert.match(activated.stdout, /documents to be written:/);
    assert.match(activated.stdout, /relationshipActivationDecisions\/bookings__legacy-1/);
    assert.match(activated.stdout, /_rollouts\/userBlockingV1/);
    assert.match(activated.stdout, /attestation hash: {2}[0-9a-f]{64}/);
    assert.match(activated.stdout, /decision set hash: [0-9a-f]{64}/);
    assert.equal(activated.result.gate.enabled, true);

    const migration = (await ctx.db.doc("_migrations/userRelationshipGuardV1").get()).data();
    assert.equal(migration.status, "verified");
    assert.equal(migration.anomalyCount, 0);
    assert.equal(migration.mismatchCount, 0);
    assert.equal(migration.flaggedRecordCount, 2);
    assert.equal(migration.decidedRecordCount, 2);
    assert.match(migration.decisionSetHash, /^[0-9a-f]{64}$/);
    assert.match(migration.attestationId, /^att_[0-9a-f]{16}$/);
    const rollout = (await ctx.db.doc("_rollouts/userBlockingV1").get()).data();
    const audit = (await ctx.db.collection("userBlockingActivationAudit").doc(rollout.activationAuditId).get()).data();
    assert.equal(audit.event, "ACTIVATE");
    assert.equal(audit.operatorUid, OWNER);
    assert.equal(audit.decisionSetHash, migration.decisionSetHash);
    assert.equal(audit.toolGitSha, "test-sha");
    assert.equal(audit.attestation.attestedByUid, OWNER);
    assert.match(audit.attestationHash, /^[0-9a-f]{64}$/);
    const attestationDoc = (await ctx.db.collection("blockingActivationAttestations")
      .doc(migration.attestationId).get()).data();
    assert.equal(attestationDoc.attestationHash, audit.attestationHash);
    const legacyDecision = (await ctx.db.doc("relationshipActivationDecisions/bookings__legacy-1").get()).data();
    assert.equal(legacyDecision.decision, "NO_OBLIGATION");
    assert.equal(legacyDecision.decisionSetHash, migration.decisionSetHash);
    // PROTECT_PAIR wrote evidence and a guard mark for the confirmed pair.
    const protectedPair = relationshipGuard.canonicalUserPair("cust-a", "prov-b");
    assert.equal((await ctx.db.doc(`userRelationshipGuards/${protectedPair.pairKey}`).get())
      .data().historicalProtectionBlocked, true);
    assert.ok((await ctx.db.doc("relationshipMigrationEvidence/v1_bookings_confirmed-1").get()).exists);
    assert.ok((await ctx.db.doc("relationshipMigrationEvidence/v1_blocks_blk-e_blk-f").get()).exists);

    // 4. Idempotent replay with the same inputs.
    const replay = await run(ctx, [
      "activate", `--decisions=${decisions}`, `--attestation=${attestation}`, `--confirm=${fp12}`,
    ], {readLine: async () => `ACTIVATE ${fp12}`});
    assert.equal(replay.exitCode, 0, replay.stderr);
    assert.equal(replay.result.transition.idempotentReplay, true);
    assert.equal(replay.result.gate.enabled, true);
    assert.equal((await ctx.db.collection("userBlockingActivationAudit").get()).size, 1);

    // 5. Blocking works through the real code path.
    const blocked = await userBlocking.blockUserDataV1({firestore: ctx.db, actorUid: "cust-c", targetUid: "prov-d"});
    assert.equal(blocked.relationshipBlocked, true);
    await assert.rejects(
      userBlocking.blockUserDataV1({firestore: ctx.db, actorUid: "cust-a", targetUid: "prov-b"}),
      (error) => error.details?.code === "PROTECTED_BOOKING_EXISTS",
    );

    // 6. Deactivate: new blocks refused, existing blocks enforced, unblock works.
    const off = await run(ctx, ["deactivate", `--operator-uid=${OWNER}`,
      "--reason=rehearsal off switch", "--confirm=DEACTIVATE"]);
    assert.equal(off.exitCode, 0, off.stderr);
    assert.equal(off.result.gate.enabled, false);
    assert.equal(off.result.gate.reasonCode, "USER_BLOCKING_DISABLED");
    await assert.rejects(
      userBlocking.blockUserDataV1({firestore: ctx.db, actorUid: "blk-f", targetUid: "blk-e"}),
      (error) => error.details?.code === "USER_BLOCKING_DISABLED",
    );
    const stillBlocked = await relationshipGuard.getEffectiveRelationshipState({
      firestore: ctx.db, firstUid: "cust-c", secondUid: "prov-d",
    });
    assert.equal(stillBlocked.blocked, true);
    const unblocked = await userBlocking.unblockUserDataV1({firestore: ctx.db, actorUid: "cust-c", targetUid: "prov-d"});
    assert.equal(unblocked.relationshipBlocked, false);
    const audits = (await ctx.db.collection("userBlockingActivationAudit").get()).docs.map((doc) => doc.data().event);
    assert.deepEqual(audits.sort(), ["ACTIVATE", "DEACTIVATE"]);
  } finally {
    await ctx.close();
  }
});

async function readyContext(name) {
  const ctx = await project(name);
  await seed(ctx);
  const first = await verifyFingerprint(ctx);
  return {ctx, readiness: first.readiness};
}

async function expectRefusedActivate(ctx, {decisions, attestation, confirm, deps = {}, pattern}) {
  const args = ["activate"];
  if (decisions) args.push(`--decisions=${decisions}`);
  if (attestation) args.push(`--attestation=${attestation}`);
  if (confirm) args.push(`--confirm=${confirm}`);
  const result = await run(ctx, args, {readLine: async () => `ACTIVATE ${confirm}`, ...deps});
  assert.equal(result.exitCode, 1, result.stdout);
  assert.match(result.stderr, /REFUSED:/);
  if (pattern) assert.match(result.stderr, pattern);
  assert.match(result.stdout, /gcloud auth application-default revoke/);
  const state = (await ctx.db.doc("_rollouts/userBlockingV1").get());
  assert.ok(!state.exists || state.data().enabled !== true, "blocking must not be enabled");
  return result;
}

test("refused: a flagged record without a decision", {skip: !enabled}, async () => {
  const {ctx, readiness} = await readyContext("nodecision");
  try {
    const decisions = decisionsFile(ctx, standardDecisions(readiness)
      .filter((entry) => entry.sourceId !== "legacy-1"));
    const fp12 = (await verifyFingerprint(ctx, decisions)).summary.fingerprint12;
    await expectRefusedActivate(ctx, {decisions, attestation: attestationFile(ctx), confirm: fp12, pattern: /not ready/});
    await noActivationWrites(ctx);
  } finally {
    await ctx.close();
  }
});

test("refused: a stale decision (record changed since the scan)", {skip: !enabled}, async () => {
  const {ctx, readiness} = await readyContext("stale");
  try {
    const decisions = decisionsFile(ctx, standardDecisions(readiness, {
      "legacy-1": {expectedSourceUpdateTimeMillis: 1700000000000},
    }));
    const verify = await verifyFingerprint(ctx, decisions);
    assert.deepEqual(verify.summary.undecidedRecords, [{recordKey: "bookings__legacy-1", reason: "STALE_DECISION"}]);
    await expectRefusedActivate(ctx, {
      decisions, attestation: attestationFile(ctx), confirm: verify.summary.fingerprint12, pattern: /not ready/,
    });
  } finally {
    await ctx.close();
  }
});

test("refused: an extra decision for a record that is not flagged", {skip: !enabled}, async () => {
  const {ctx, readiness} = await readyContext("extra");
  try {
    const decisions = decisionsFile(ctx, [...standardDecisions(readiness), {
      phase: "bookings", sourceId: "settled-1", expectedReasonCode: "NO_PROTECTED_OBLIGATION",
      expectedSourceUpdateTimeMillis: 1700000000000, decision: "NO_OBLIGATION", note: "",
    }]);
    const verify = await verifyFingerprint(ctx, decisions);
    assert.deepEqual(verify.summary.extraDecisions, ["bookings__settled-1"]);
    await expectRefusedActivate(ctx, {
      decisions, attestation: attestationFile(ctx), confirm: verify.summary.fingerprint12, pattern: /not ready/,
    });
  } finally {
    await ctx.close();
  }
});

test("refused: BLOCK_ACTIVATION keeps activation off", {skip: !enabled}, async () => {
  const {ctx, readiness} = await readyContext("blockact");
  try {
    const decisions = decisionsFile(ctx, standardDecisions(readiness, {"legacy-1": {decision: "BLOCK_ACTIVATION"}}));
    const verify = await verifyFingerprint(ctx, decisions);
    await expectRefusedActivate(ctx, {
      decisions, attestation: attestationFile(ctx), confirm: verify.summary.fingerprint12, pattern: /not ready/,
    });
  } finally {
    await ctx.close();
  }
});

test("refused: wrong --confirm fingerprint", {skip: !enabled}, async () => {
  const {ctx, readiness} = await readyContext("wrongfp");
  try {
    const decisions = decisionsFile(ctx, standardDecisions(readiness));
    await expectRefusedActivate(ctx, {
      decisions, attestation: attestationFile(ctx), confirm: "000000000000", pattern: /data changed since verify/,
    });
    await noActivationWrites(ctx);
  } finally {
    await ctx.close();
  }
});

test("refused: typed confirmation does not match, nothing written", {skip: !enabled}, async () => {
  const {ctx, readiness} = await readyContext("typed");
  try {
    const decisions = decisionsFile(ctx, standardDecisions(readiness));
    const fp12 = (await verifyFingerprint(ctx, decisions)).summary.fingerprint12;
    for (const typed of ["", "yes", `ACTIVATE ${fp12.slice(0, 11)}`, `activate ${fp12}`]) {
      await expectRefusedActivate(ctx, {
        decisions, attestation: attestationFile(ctx), confirm: fp12,
        deps: {readLine: async () => typed}, pattern: /confirmation text did not match/,
      });
    }
    await noActivationWrites(ctx);
  } finally {
    await ctx.close();
  }
});

test("refused: more than 14 minutes between scan and confirmation", {skip: !enabled}, async () => {
  const {ctx, readiness} = await readyContext("slow");
  try {
    const decisions = decisionsFile(ctx, standardDecisions(readiness));
    const fp12 = (await verifyFingerprint(ctx, decisions)).summary.fingerprint12;
    let calls = 0;
    const base = Date.now();
    await expectRefusedActivate(ctx, {
      decisions, attestation: attestationFile(ctx), confirm: fp12,
      deps: {now: () => new Date(base + (calls++ === 0 ? 0 : 15 * 60 * 1000))},
      pattern: /more than 14 minutes/,
    });
    await noActivationWrites(ctx);
  } finally {
    await ctx.close();
  }
});

test("refused: the 15-minute verificationValidUntil expired before the rollout write", {skip: !enabled}, async () => {
  const {ctx, readiness} = await readyContext("expired");
  try {
    const decisions = decisionsFile(ctx, standardDecisions(readiness));
    const fp12 = (await verifyFingerprint(ctx, decisions)).summary.fingerprint12;
    await expectRefusedActivate(ctx, {
      decisions, attestation: attestationFile(ctx), confirm: fp12,
      deps: {afterMigrationRecorded: async (db) => {
        await db.doc("_migrations/userRelationshipGuardV1").update({
          verificationValidUntil: new Date(Date.now() - 1000),
        });
      }},
      pattern: /relationship_migration_not_verified/,
    });
    assert.equal((await ctx.db.doc("_rollouts/userBlockingV1").get()).exists, false);
  } finally {
    await ctx.close();
  }
});

test("refused: a booking changes between the two scans (just re-run)", {skip: !enabled}, async () => {
  const {ctx, readiness} = await readyContext("concurrent");
  try {
    const decisions = decisionsFile(ctx, standardDecisions(readiness));
    const fp12 = (await verifyFingerprint(ctx, decisions)).summary.fingerprint12;
    await expectRefusedActivate(ctx, {
      decisions, attestation: attestationFile(ctx), confirm: fp12,
      deps: {onBetweenScans: async () => {
        await ctx.db.doc("bookings/settled-1").update({touchedAt: new Date()});
      }},
      pattern: /relationship_migration_concurrent_source_change/,
    });
    await noActivationWrites(ctx);
  } finally {
    await ctx.close();
  }
});

test("refused: missing or invalid attestation", {skip: !enabled}, async () => {
  const {ctx, readiness} = await readyContext("attest");
  try {
    const decisions = decisionsFile(ctx, standardDecisions(readiness));
    const fp12 = (await verifyFingerprint(ctx, decisions)).summary.fingerprint12;
    await expectRefusedActivate(ctx, {decisions, confirm: fp12, pattern: /--attestation=<file> is required/});
    await expectRefusedActivate(ctx, {
      decisions, attestation: attestationFile(ctx, {scope: {noRealUserBookings: true}}), confirm: fp12,
      pattern: /scope\.noRealUserPayments must be true/,
    });
    await expectRefusedActivate(ctx, {
      decisions, attestation: attestationFile(ctx, {attestedByUid: NOT_ADMIN}), confirm: fp12,
      pattern: /attestedByUid must equal decidedByUid/,
    });
    await noActivationWrites(ctx);
  } finally {
    await ctx.close();
  }
});

test("refused: decidedByUid is not a superAdmin", {skip: !enabled}, async () => {
  const {ctx, readiness} = await readyContext("notadmin");
  try {
    const decisions = decisionsFile(ctx, standardDecisions(readiness), NOT_ADMIN);
    const fp12 = (await verifyFingerprint(ctx, decisions)).summary.fingerprint12;
    await expectRefusedActivate(ctx, {
      decisions, attestation: attestationFile(ctx, {attestedByUid: NOT_ADMIN}), confirm: fp12,
      pattern: /is not a superAdmin/,
    });
    await noActivationWrites(ctx);
  } finally {
    await ctx.close();
  }
});

test("refused: already active under a different activation", {skip: !enabled}, async () => {
  const {ctx, readiness} = await readyContext("active");
  try {
    const decisions = decisionsFile(ctx, standardDecisions(readiness));
    const fp12 = (await verifyFingerprint(ctx, decisions)).summary.fingerprint12;
    const first = await run(ctx, ["activate", `--decisions=${decisions}`,
      `--attestation=${attestationFile(ctx)}`, `--confirm=${fp12}`], {readLine: async () => `ACTIVATE ${fp12}`});
    assert.equal(first.exitCode, 0, first.stderr);
    const otherAttestation = attestationFile(ctx, {attestedAt: "2026-11-24T10:00:00+05:30"});
    const second = await run(ctx, ["activate", `--decisions=${decisions}`,
      `--attestation=${otherAttestation}`, `--confirm=${fp12}`], {readLine: async () => `ACTIVATE ${fp12}`});
    assert.equal(second.exitCode, 1);
    assert.match(second.stderr, /already active/);
    assert.equal((await ctx.db.collection("userBlockingActivationAudit").get()).size, 1);
  } finally {
    await ctx.close();
  }
});

test("deactivate requires --confirm, a reason and a superAdmin operator", {skip: !enabled}, async () => {
  const ctx = await project("deact");
  try {
    await seed(ctx);
    for (const [args, pattern] of [
      [["deactivate", `--operator-uid=${OWNER}`, "--reason=x"], /--confirm=DEACTIVATE is required/],
      [["deactivate", `--operator-uid=${OWNER}`, "--confirm=DEACTIVATE"], /--reason/],
      [["deactivate", "--reason=x", "--confirm=DEACTIVATE"], /--operator-uid/],
      [["deactivate", `--operator-uid=${NOT_ADMIN}`, "--reason=x", "--confirm=DEACTIVATE"], /not a superAdmin/],
    ]) {
      const result = await run(ctx, args);
      assert.equal(result.exitCode, 1);
      assert.match(result.stderr, pattern);
    }
    await noActivationWrites(ctx);
  } finally {
    await ctx.close();
  }
});

test("template commands write 0600 files and never overwrite", {skip: !enabled}, async () => {
  const ctx = await project("templates");
  try {
    for (const command of ["template-decisions", "template-attestation"]) {
      const file = path.join(ctx.dir, `${command}.json`);
      const out = capture();
      const err = capture();
      const first = await tool.runActivationCli({argv: [command, `--out=${file}`], env: {}, stdout: out.stream, stderr: err.stream});
      assert.equal(first.exitCode, 0, err.text());
      assert.equal(fs.statSync(file).mode & 0o777, 0o600);
      JSON.parse(fs.readFileSync(file, "utf8"));
      const second = await tool.runActivationCli({argv: [command, `--out=${file}`], env: {}, stdout: out.stream, stderr: err.stream});
      assert.equal(second.exitCode, 1);
      assert.match(err.text(), /already exists/);
    }
  } finally {
    await ctx.close();
  }
});
