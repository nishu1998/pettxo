#!/usr/bin/env node
"use strict";

/**
 * Pettxo user-blocking activation tool (Phase 3B-4d). Local, owner-run.
 *
 *   node scripts/blocking_activation.js template-decisions --out=<file>
 *   node scripts/blocking_activation.js template-attestation --out=<file>
 *   node scripts/blocking_activation.js status     --project=<id>
 *   node scripts/blocking_activation.js verify     --project=<id> [--decisions=<file>] [--flagged-out=<file>]
 *   node scripts/blocking_activation.js activate   --project=<id> --decisions=<file> --attestation=<file> --confirm=<fingerprint12>
 *   node scripts/blocking_activation.js deactivate --project=<id> --operator-uid=<uid> --reason="..." --confirm=DEACTIVATE
 *
 * Targets:
 *   - Production: --project=pettexo-d9409 explicitly, no emulator host, ADC from
 *     `gcloud auth application-default login` (authorized_user only).
 *   - Emulator rehearsal: loopback FIRESTORE_EMULATOR_HOST and a demo-* project
 *     (scripts/lib/targetGuard.js).
 *
 * Decisions: docs/PETTXO_PHASE3B4_DECISIONS.md. Runbook:
 * docs/PETTXO_PHASE3B4_ACTIVATION_RUNBOOK.md.
 */

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const readline = require("node:readline");
const {execFileSync} = require("node:child_process");
const {randomUUID} = require("node:crypto");

const {ScriptTargetError, assertSafeScriptTarget} = require("./lib/targetGuard");
const plan = require("./lib/activationPlan");

/** The only place a production target is allowed. */
const PRODUCTION_PROJECT_ID = "pettexo-d9409";
const SCRIPT_NAME = "blocking_activation";
const FUNCTIONS_DIR = path.resolve(__dirname, "..");
const REPO_DIR = path.resolve(FUNCTIONS_DIR, "..");
const CONFIRMATION_WINDOW_MS = 14 * 60 * 1000;
const REVOKE_REMINDER =
  "REMINDER: when you are finished, run:  gcloud auth application-default revoke";

class ActivationRefusal extends Error {
  constructor(message) {
    super(message);
    this.name = "ActivationRefusal";
  }
}

function parseArgs(argv) {
  const [command = "", ...rest] = argv;
  const flags = {};
  for (const arg of rest) {
    const match = /^--([a-z0-9-]+)(?:=(.*))?$/s.exec(arg);
    if (!match) throw new ActivationRefusal(`unexpected argument: ${arg}`);
    flags[match[1]] = match[2] ?? true;
  }
  return {command, flags};
}

function flagString(flags, name) {
  const value = flags[name];
  return typeof value === "string" ? value.trim() : "";
}

function normalize(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

// --- target and credentials ---------------------------------------------------

function adcFilePath(env) {
  if (env.GOOGLE_APPLICATION_CREDENTIALS) return env.GOOGLE_APPLICATION_CREDENTIALS;
  const home = env.HOME || os.homedir();
  return path.join(home, ".config", "gcloud", "application_default_credentials.json");
}

/**
 * Decides the target from flags and environment before any Firebase module is
 * loaded. Throws ActivationRefusal / ScriptTargetError.
 */
function resolveTarget(argv, env) {
  const projectFlags = argv.filter((arg) => arg.startsWith("--project="));
  if (projectFlags.length !== 1) {
    throw new ActivationRefusal("pass the project explicitly, exactly once: --project=<id>");
  }
  const projectId = normalize(projectFlags[0].slice("--project=".length));
  if (projectId === PRODUCTION_PROJECT_ID) {
    for (const name of [
      "FIRESTORE_EMULATOR_HOST",
      "FIREBASE_AUTH_EMULATOR_HOST",
      "FIREBASE_STORAGE_EMULATOR_HOST",
    ]) {
      if (env[name]) {
        throw new ActivationRefusal(`${name} is set; production mode never talks to an emulator. Unset it.`);
      }
    }
    for (const name of ["GCLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT"]) {
      if (env[name] && normalize(env[name]) !== PRODUCTION_PROJECT_ID) {
        throw new ActivationRefusal(`${name}=${env[name]} disagrees with --project; unset it or set it to the same project.`);
      }
    }
    if (env.FIREBASE_CONFIG) {
      throw new ActivationRefusal("FIREBASE_CONFIG is set; unset it for production mode.");
    }
    const adcPath = adcFilePath(env);
    let adc;
    try {
      adc = JSON.parse(fs.readFileSync(adcPath, "utf8"));
    } catch {
      throw new ActivationRefusal(
        `no Application Default Credentials at ${adcPath}. Run: gcloud auth application-default login`,
      );
    }
    if (adc?.type !== "authorized_user") {
      throw new ActivationRefusal(
        `ADC type is "${adc?.type ?? "unknown"}"; only your own owner login (authorized_user) is allowed. ` +
        "No service accounts.",
      );
    }
    return {projectId, mode: "production", adcPath};
  }
  if (argv.some((arg) => arg.startsWith("--allow-project"))) {
    throw new ActivationRefusal("--allow-project is not supported: use an emulator with a demo-* project, or production");
  }
  const guarded = assertSafeScriptTarget({scriptName: SCRIPT_NAME, argv, env});
  if (guarded.mode !== "emulator") {
    throw new ActivationRefusal("only emulator rehearsal or production are supported");
  }
  return {projectId: guarded.projectId, mode: "emulator", adcPath: ""};
}

async function resolvePrincipalEmail() {
  // Same google-auth-library instance @google-cloud/firestore uses, so the
  // principal printed is the one Firestore authenticates as.
  const {createRequire} = require("node:module");
  const firestoreRequire = createRequire(require.resolve("@google-cloud/firestore"));
  const {GoogleAuth} = firestoreRequire("google-auth-library");
  const auth = new GoogleAuth({scopes: ["https://www.googleapis.com/auth/cloud-platform"]});
  const client = await auth.getClient();
  const {token} = await client.getAccessToken();
  const info = await client.getTokenInfo(token);
  return typeof info.email === "string" ? info.email : "";
}

function gitState() {
  const run = (args) => execFileSync("git", args, {cwd: REPO_DIR, encoding: "utf8"}).trim();
  try {
    const sha = run(["rev-parse", "HEAD"]);
    const dirty = run(["status", "--porcelain", "--", "functions/src", "functions/scripts"]);
    const libBuiltFromHead = dirty === "" && libIsCurrent();
    return {sha, dirty: dirty !== "", libBuiltFromHead};
  } catch (error) {
    return {sha: "unknown", dirty: true, libBuiltFromHead: false, error: String(error)};
  }
}

/** Every src/**\/*.ts has a compiled lib/**\/*.js at least as new. */
function libIsCurrent() {
  const srcDir = path.join(FUNCTIONS_DIR, "src");
  let current = true;
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else if (entry.name.endsWith(".ts") && !entry.name.endsWith(".d.ts")) {
        const compiled = path.join(FUNCTIONS_DIR, "lib", path.relative(srcDir, full)).replace(/\.ts$/, ".js");
        if (!fs.existsSync(compiled) || fs.statSync(compiled).mtimeMs < fs.statSync(full).mtimeMs) current = false;
      }
    }
  };
  walk(srcDir);
  return current;
}

// --- Firebase -----------------------------------------------------------------

function loadLibrary() {
  return {
    gate: require("../lib/blocking/blockingActivationGate.js"),
    migration: require("../lib/blocking/historicalRelationshipMigration.js"),
    decisionShape: require("../lib/blocking/relationshipActivationDecisions.js"),
    readOnly: require("../lib/audit/readOnlyFirestore.js"),
    userBlocking: require("../lib/blocking/userBlocking.js"),
  };
}

function openFirestore(target, {readOnly}, lib) {
  const {applicationDefault, initializeApp} = require("firebase-admin/app");
  const {getFirestore} = require("firebase-admin/firestore");
  const options = target.mode === "production" ?
    {projectId: target.projectId, credential: applicationDefault()} :
    {projectId: target.projectId};
  const app = initializeApp(options, `${SCRIPT_NAME}-${readOnly ? "ro" : "rw"}-${randomUUID()}`);
  if (normalize(app.options.projectId) !== target.projectId) {
    throw new ActivationRefusal(`initialized app project ${app.options.projectId} does not match ${target.projectId}`);
  }
  const db = getFirestore(app);
  db.settings({ignoreUndefinedProperties: true});
  return {app, db: readOnly ? lib.readOnly.enforceReadOnlyFirestore(db) : db};
}

async function closeAll(handles) {
  const {deleteApp} = require("firebase-admin/app");
  for (const handle of handles) {
    try {
      await handle.db.terminate();
    } catch {
      // ignore
    }
    try {
      await deleteApp(handle.app);
    } catch {
      // ignore
    }
  }
}

async function readGateDocs(db, lib) {
  const rollout = await db.doc(lib.gate.USER_BLOCKING_ROLLOUT_PATH).get();
  const migration = await db.doc(lib.gate.RELATIONSHIP_MIGRATION_PATH).get();
  const auditId = typeof rollout.data()?.activationAuditId === "string" ?
    rollout.data().activationAuditId.trim() : "";
  const audit = auditId ?
    await db.collection(lib.gate.USER_BLOCKING_ACTIVATION_AUDIT_COLLECTION).doc(auditId).get() :
    null;
  const state = await lib.gate.readBlockingActivationState(db);
  return {
    state,
    rollout: rollout.exists ? rollout.data() : null,
    migration: migration.exists ? migration.data() : null,
    audit: audit?.exists ? audit.data() : null,
  };
}

function jsonSafe(value) {
  return JSON.parse(JSON.stringify(value, (key, entry) => {
    if (entry && typeof entry === "object" && typeof entry.toDate === "function") {
      return entry.toDate().toISOString();
    }
    return entry;
  }));
}

async function assertSuperAdmin(db, uid) {
  const snapshot = await db.collection("users").doc(uid).get();
  const data = snapshot.data() ?? {};
  if (!snapshot.exists || data.adminRole !== "superAdmin") {
    throw new ActivationRefusal(`users/${uid} is not a superAdmin (adminRole must be "superAdmin")`);
  }
}

function readJsonFile(file, label) {
  if (!file) throw new ActivationRefusal(`--${label}=<file> is required`);
  try {
    return JSON.parse(fs.readFileSync(path.resolve(file), "utf8"));
  } catch (error) {
    throw new ActivationRefusal(`cannot read ${label} file ${file}: ${error.message}`);
  }
}

function writeNewPrivateFile(file, value) {
  if (!file) throw new ActivationRefusal("--out=<file> is required");
  const resolved = path.resolve(file);
  try {
    fs.writeFileSync(resolved, `${JSON.stringify(value, null, 2)}\n`, {flag: "wx", mode: 0o600});
  } catch (error) {
    if (error.code === "EEXIST") throw new ActivationRefusal(`${resolved} already exists; choose a new path`);
    throw error;
  }
  fs.chmodSync(resolved, 0o600);
  return resolved;
}

// --- commands -------------------------------------------------------------------

async function printHeader(io, target, deps) {
  const git = deps.gitState();
  let principal = "emulator (no credentials)";
  let credentialType = "none (emulator)";
  if (target.mode === "production") {
    credentialType = "authorized_user (gcloud application-default login)";
    principal = await deps.resolvePrincipalEmail();
    if (!principal) throw new ActivationRefusal("could not resolve the ADC principal email");
  }
  io.out("== Target ==");
  io.out(`project:          ${target.projectId} (${target.mode})`);
  io.out(`principal:        ${principal}`);
  io.out(`credential type:  ${credentialType}`);
  io.out(`git SHA:          ${git.sha}${git.dirty ? " (functions/src or scripts has local changes)" : ""}`);
  io.out(`functions/lib built from this SHA: ${git.libBuiltFromHead ? "yes" : "NO"}`);
  return {git, principal};
}

async function commandStatus(target, io, deps) {
  const lib = deps.loadLibrary();
  const handles = [openFirestore(target, {readOnly: true}, lib)];
  try {
    await printHeader(io, target, deps);
    const gate = await readGateDocs(handles[0].db, lib);
    io.out("== Gate ==");
    io.out(JSON.stringify(jsonSafe(gate), null, 2));
    return gate;
  } finally {
    await closeAll(handles);
  }
}

async function evaluate(target, db, lib, decisionDocuments, deps) {
  return lib.migration.evaluateRelationshipActivationReadiness({
    firestore: db,
    strategy: "zero-protected-baseline",
    decisions: decisionDocuments,
    authoritativeNow: deps.now(),
    onBetweenScans: deps.onBetweenScans,
  });
}

async function commandVerify(target, flags, io, deps) {
  const lib = deps.loadLibrary();
  const handles = [openFirestore(target, {readOnly: true}, lib)];
  try {
    await printHeader(io, target, deps);
    const db = handles[0].db;
    const gate = await readGateDocs(db, lib);
    io.out("== Gate ==");
    io.out(`enabled: ${gate.state.enabled}  reasonCode: ${gate.state.reasonCode || "-"}`);

    let decisionDocuments = [];
    let parsedDecisions = null;
    const decisionsFile = flagString(flags, "decisions");
    if (decisionsFile) {
      parsedDecisions = plan.parseDecisionsFile(readJsonFile(decisionsFile, "decisions"), lib.decisionShape);
      const setHash = plan.decisionSetHash(parsedDecisions.decidedByUid, parsedDecisions.entries);
      decisionDocuments = plan.buildDecisionDocuments({
        parsed: parsedDecisions,
        pairKeyByRecordKey: new Map(),
        decidedByEmail: "",
        setHash,
        shape: lib.decisionShape,
      });
    }
    io.out("== Scanning (two full passes; read-only) ==");
    const readiness = await evaluate(target, db, lib, decisionDocuments, deps);
    const summary = plan.readinessSummary(readiness);
    io.out(JSON.stringify(summary, null, 2));
    io.out("== Flagged records (copy each into the decisions file and choose a decision) ==");
    io.out(JSON.stringify(plan.decisionsTemplate(readiness.flagged).decisions, null, 2));
    const flaggedOut = flagString(flags, "flagged-out");
    if (flaggedOut) {
      const written = writeNewPrivateFile(flaggedOut, plan.decisionsTemplate(readiness.flagged));
      io.out(`decisions template with every flagged record written to ${written} (mode 0600)`);
    }
    io.out("== Planned writes on activate ==");
    io.out("relationshipActivationDecisions/<one per decision>");
    io.out("blockingActivationAttestations/<attestation id>");
    for (const item of readiness.requiredEvidence) {
      io.out(`relationshipMigrationEvidence/v1_${item.phase}_${item.sourceId}`);
      io.out(`userRelationshipGuards/${item.pairKey || "<missing pair: refused>"}`);
    }
    io.out("_migrations/userRelationshipGuardV1");
    io.out("userBlockingActivationAudit/<activation audit id>");
    io.out("_rollouts/userBlockingV1");
    io.out(`== Result: ${readiness.ready ? "READY" : "NOT READY"} ==`);
    io.out(`fingerprint12: ${summary.fingerprint12}`);
    if (readiness.ready) {
      io.out(`next: activate --project=${target.projectId} --decisions=<file> --attestation=<file> --confirm=${summary.fingerprint12}`);
    }
    return {readiness, summary};
  } finally {
    await closeAll(handles);
  }
}

async function writeIfAbsentOrIdentical(db, docPath, data, compareKeys) {
  const ref = db.doc(docPath);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (snapshot.exists) {
      const existing = snapshot.data() ?? {};
      const same = compareKeys.every((key) =>
        plan.canonicalJson(existing[key] ?? null) === plan.canonicalJson(data[key] ?? null));
      if (!same) throw new ActivationRefusal(`${docPath} already exists with different content`);
      return;
    }
    transaction.create(ref, data);
  });
}

async function commandActivate(target, flags, io, deps) {
  const lib = deps.loadLibrary();
  const decisionsRaw = readJsonFile(flagString(flags, "decisions"), "decisions");
  const attestationRaw = readJsonFile(flagString(flags, "attestation"), "attestation");
  const confirm = flagString(flags, "confirm").toLowerCase();
  if (!/^[0-9a-f]{12}$/.test(confirm)) {
    throw new ActivationRefusal("--confirm must be the 12-character fingerprint printed by verify");
  }
  const parsedDecisions = plan.parseDecisionsFile(decisionsRaw, lib.decisionShape);
  const attestation = plan.parseAttestationFile(attestationRaw);
  if (attestation.attestation.attestedByUid !== parsedDecisions.decidedByUid) {
    throw new ActivationRefusal("attestedByUid must equal decidedByUid (the same owner)");
  }
  const operatorUid = parsedDecisions.decidedByUid;
  const setHash = plan.decisionSetHash(operatorUid, parsedDecisions.entries);

  const handles = [];
  try {
    handles.push(openFirestore(target, {readOnly: true}, lib));
    const roDb = handles[0].db;
    const {git, principal} = await printHeader(io, target, deps);
    if (target.mode === "production" && !git.libBuiltFromHead) {
      throw new ActivationRefusal("functions/lib is not built from a clean HEAD; run npm run build on a clean tree first");
    }
    await assertSuperAdmin(roDb, operatorUid);

    const gateBefore = await readGateDocs(roDb, lib);
    const evaluatedAt = deps.now();
    const readiness = await evaluate(target, roDb, lib, plan.buildDecisionDocuments({
      parsed: parsedDecisions, pairKeyByRecordKey: new Map(), decidedByEmail: principal,
      setHash, shape: lib.decisionShape,
    }), deps);
    const summary = plan.readinessSummary(readiness);
    if (summary.fingerprint12 !== confirm) {
      throw new ActivationRefusal(
        `the data changed since verify: fingerprint is now ${summary.fingerprint12}, --confirm was ${confirm}. ` +
        "Run verify again and use the new fingerprint.",
      );
    }
    if (!readiness.ready) {
      io.out(JSON.stringify(summary, null, 2));
      throw new ActivationRefusal("not ready: every flagged record needs a matching decision, with no extra decisions");
    }
    const pairKeyByRecordKey = new Map(readiness.flagged.map((record) => [record.recordKey, record.pairKey]));
    const decisionDocuments = plan.buildDecisionDocuments({
      parsed: parsedDecisions, pairKeyByRecordKey, decidedByEmail: principal,
      setHash, shape: lib.decisionShape,
    });
    const ids = plan.deriveActivationIds({
      fingerprint: readiness.sourceFingerprint,
      attestationHash: attestation.attestationHash,
      setHash,
    });
    const activeAuditId = typeof gateBefore.rollout?.activationAuditId === "string" ?
      gateBefore.rollout.activationAuditId : "";
    const replay = gateBefore.state.enabled && activeAuditId === ids.auditId;
    if (gateBefore.state.enabled && !replay) {
      throw new ActivationRefusal(
        `blocking is already active under audit ${activeAuditId}. Deactivate first if you really need to re-activate.`,
      );
    }
    const writes = plan.plannedActivationWrites({
      readiness, decisionDocuments, attestationId: attestation.attestationId,
      runId: ids.runId, auditId: ids.auditId,
    });
    io.out("== Activation plan ==");
    io.out(`gate now:          enabled=${gateBefore.state.enabled} reasonCode=${gateBefore.state.reasonCode || "-"}`);
    io.out(`counts:            ${JSON.stringify({
      bookings: summary.bookingsScanned, directedBlocks: summary.directedBlocks,
      flagged: summary.flaggedRecords, decided: summary.decidedRecords,
      evidenceMarkers: summary.evidenceMarkersToWrite, protectionMarks: summary.protectionMarksToWrite,
    })}`);
    io.out(`fingerprint:       ${readiness.sourceFingerprint}`);
    io.out(`attestation id:    ${attestation.attestationId}`);
    io.out(`attestation hash:  ${attestation.attestationHash}`);
    io.out(`decision set hash: ${setHash}`);
    io.out(`operator uid:      ${operatorUid}`);
    io.out(`migration run id:  ${ids.runId}`);
    io.out(`audit id:          ${ids.auditId}${replay ? " (already active: idempotent replay)" : ""}`);
    io.out("documents to be written:");
    for (const docPath of writes.paths) io.out(`  ${docPath}`);
    const expected = `ACTIVATE ${summary.fingerprint12}`;
    const typed = (await deps.readLine(`Type "${expected}" to write, anything else aborts: `)).trim();
    if (typed !== expected) {
      throw new ActivationRefusal("confirmation text did not match; nothing was written");
    }
    if (deps.now().getTime() - evaluatedAt.getTime() > CONFIRMATION_WINDOW_MS) {
      throw new ActivationRefusal("more than 14 minutes passed since the scan; nothing was written. Re-run activate.");
    }

    handles.push(openFirestore(target, {readOnly: false}, lib));
    const db = handles[1].db;
    const {FieldValue} = require("firebase-admin/firestore");
    for (const document of decisionDocuments) {
      await writeIfAbsentOrIdentical(db, `relationshipActivationDecisions/${document.recordKey}`,
        {...document, decidedAt: FieldValue.serverTimestamp()},
        ["phase", "sourceId", "expectedReasonCode", "expectedSourceUpdateTimeMillis", "decision", "decidedByUid"]);
    }
    await writeIfAbsentOrIdentical(db, `blockingActivationAttestations/${attestation.attestationId}`, {
      ...attestation.attestation,
      attestationHash: attestation.attestationHash,
      decisionSetHash: setHash,
      operatorEmail: principal,
      recordedAt: FieldValue.serverTimestamp(),
    }, ["attestationHash"]);
    // Evidence markers and guard state: every directed block, plus bookings
    // decided PROTECT_PAIR.
    let cursor = null;
    do {
      const page = await lib.migration.runHistoricalRelationshipMigrationPage({
        firestore: db, runId: ids.runId, phase: "blocks", mode: "apply", cursor,
        authoritativeNow: deps.now(),
      });
      cursor = page.nextCursor;
    } while (cursor);
    const protectPairBookings = readiness.decided
      .filter((entry) => entry.decision.decision === "PROTECT_PAIR" && entry.record.phase === "bookings")
      .map((entry) => entry.record.sourceId);
    if (protectPairBookings.length > 0) {
      await lib.migration.applyHistoricalEvidenceForSources({
        firestore: db, runId: ids.runId, phase: "bookings", sourceIds: protectPairBookings,
        authoritativeNow: deps.now(),
      });
    }
    const recorded = await lib.migration.verifyAndRecordRelationshipMigration({
      firestore: db,
      runId: ids.runId,
      operatorUid,
      strategy: "zero-protected-baseline",
      decisions: decisionDocuments,
      decisionSetHash: setHash,
      attestationId: attestation.attestationId,
      authoritativeNow: deps.now(),
      onBetweenScans: deps.onBetweenScans,
    });
    if (recorded.sourceFingerprint !== readiness.sourceFingerprint) {
      throw new ActivationRefusal("the data changed during activation; blocking was NOT enabled. Re-run verify.");
    }
    if (deps.afterMigrationRecorded) await deps.afterMigrationRecorded(db);
    const transition = await lib.gate.recordBlockingRolloutTransition({
      firestore: db,
      enabled: true,
      operatorUid,
      reason: `Phase 3B-4d activation; attestation ${attestation.attestationId}`,
      auditId: ids.auditId,
      migrationRunId: ids.runId,
      auditExtras: {
        attestation: attestation.attestation,
        attestationHash: attestation.attestationHash,
        decisionSetHash: setHash,
        operatorEmail: principal,
        toolGitSha: git.sha,
      },
    });
    const after = await lib.gate.readBlockingActivationState(db);
    io.out("== Done ==");
    io.out(JSON.stringify({transition, gate: after}, null, 2));
    if (!after.enabled) throw new ActivationRefusal(`gate is not enabled after activation: ${after.reasonCode}`);
    return {readiness, ids, transition, gate: after};
  } finally {
    await closeAll(handles);
  }
}

async function commandDeactivate(target, flags, io, deps) {
  const lib = deps.loadLibrary();
  const reason = flagString(flags, "reason");
  const operatorUid = flagString(flags, "operator-uid");
  if (flagString(flags, "confirm") !== "DEACTIVATE") throw new ActivationRefusal("--confirm=DEACTIVATE is required");
  if (!reason) throw new ActivationRefusal("--reason=\"...\" is required");
  if (!operatorUid) throw new ActivationRefusal("--operator-uid=<owner Firebase UID> is required");
  const handles = [];
  try {
    handles.push(openFirestore(target, {readOnly: false}, lib));
    const db = handles[0].db;
    const {git, principal} = await printHeader(io, target, deps);
    await assertSuperAdmin(db, operatorUid);
    const auditId = flagString(flags, "audit-id") ||
      `deactivate_${deps.now().toISOString().replace(/[^0-9]/g, "").slice(0, 14)}`;
    io.out("== Deactivation ==");
    io.out(`documents to be written:\n  userBlockingActivationAudit/${auditId}\n  _rollouts/userBlockingV1`);
    const transition = await lib.gate.recordBlockingRolloutTransition({
      firestore: db,
      enabled: false,
      operatorUid,
      reason,
      auditId,
      migrationRunId: "",
      auditExtras: {operatorEmail: principal, toolGitSha: git.sha},
    });
    const after = await lib.gate.readBlockingActivationState(db);
    io.out(JSON.stringify({transition, gate: after}, null, 2));
    io.out("New blocks are now refused. Existing blocks stay enforced and unblock keeps working.");
    return {transition, gate: after};
  } finally {
    await closeAll(handles);
  }
}

function defaultReadLine(stdin, stdout) {
  return (prompt) => new Promise((resolve) => {
    const rl = readline.createInterface({input: stdin, output: stdout, terminal: false});
    stdout.write(prompt);
    let answered = false;
    rl.once("line", (line) => {
      answered = true;
      rl.close();
      resolve(line);
    });
    rl.once("close", () => {
      if (!answered) resolve("");
    });
  });
}

/**
 * Entry point used by the CLI and by tests.
 * @returns {Promise<{exitCode: number, result?: unknown, error?: Error}>}
 */
async function runActivationCli({argv, env = process.env, stdin = process.stdin, stdout = process.stdout,
  stderr = process.stderr, deps = {}}) {
  const io = {
    out: (line) => stdout.write(`${line}\n`),
    err: (line) => stderr.write(`${line}\n`),
  };
  const fullDeps = {
    loadLibrary,
    gitState,
    resolvePrincipalEmail,
    now: () => new Date(),
    readLine: defaultReadLine(stdin, stdout),
    onBetweenScans: undefined,
    afterMigrationRecorded: undefined,
    ...deps,
  };
  try {
    const {command, flags} = parseArgs(argv);
    if (command === "template-decisions") {
      const written = writeNewPrivateFile(flagString(flags, "out"), plan.decisionsTemplate());
      io.out(`decisions template written to ${written} (mode 0600). Run verify to list the records to decide.`);
      return {exitCode: 0};
    }
    if (command === "template-attestation") {
      const written = writeNewPrivateFile(flagString(flags, "out"), plan.attestationTemplate());
      io.out(`attestation template written to ${written} (mode 0600). Fill in your UID, email and the time.`);
      return {exitCode: 0};
    }
    if (!["status", "verify", "activate", "deactivate"].includes(command)) {
      throw new ActivationRefusal(
        "command must be one of: status, verify, activate, deactivate, template-decisions, template-attestation",
      );
    }
    const target = resolveTarget(argv.slice(1), env);
    let result;
    if (command === "status") result = await commandStatus(target, io, fullDeps);
    if (command === "verify") result = await commandVerify(target, flags, io, fullDeps);
    if (command === "activate") result = await commandActivate(target, flags, io, fullDeps);
    if (command === "deactivate") result = await commandDeactivate(target, flags, io, fullDeps);
    return {exitCode: 0, result};
  } catch (error) {
    const known = error instanceof ActivationRefusal || error instanceof ScriptTargetError ||
      error instanceof plan.ActivationInputError;
    io.err(`REFUSED: ${error instanceof Error ? error.message : String(error)}`);
    if (!known && error instanceof Error && error.stack) io.err(error.stack);
    return {exitCode: 1, error};
  } finally {
    io.out(REVOKE_REMINDER);
  }
}

module.exports = {
  PRODUCTION_PROJECT_ID,
  ActivationRefusal,
  REVOKE_REMINDER,
  gitState,
  resolveTarget,
  runActivationCli,
};

if (require.main === module) {
  runActivationCli({argv: process.argv.slice(2)}).then(({exitCode}) => {
    process.exitCode = exitCode;
  });
}
