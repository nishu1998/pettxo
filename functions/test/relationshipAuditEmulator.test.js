"use strict";
const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({services: ["firestore"], projectId: "demo-pettxo-audit"});

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {spawnSync} = require("node:child_process");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const firestoreModule = require("firebase-admin/firestore");

const {buildRelationshipAuditRehearsal} = require("./fixtures/relationshipAuditRehearsal.js");
const {enforceReadOnlyFirestore} = require("../lib/audit/readOnlyFirestore.js");
const {chooseReadTime, scanRelationshipAuditSource} = require("../lib/audit/relationshipAuditScanner.js");

const FUNCTIONS_DIR = path.resolve(__dirname, "..");
const AUDIT_SCRIPT = path.join(FUNCTIONS_DIR, "scripts", "read_only_relationship_audit.js");
const PROJECT = `demo-pettxo-audit-${process.pid}`;
const skip = !firebaseEmulator.enabled;

let seedApp;
let seedDb;
let rehearsal;
let seededUpdateTimes;

function childEnv() {
  return {
    PATH: process.env.PATH,
    HOME: fs.mkdtempSync(path.join(os.tmpdir(), "pettxo-audit-home-")),
    GCLOUD_PROJECT: PROJECT,
    FIRESTORE_EMULATOR_HOST: process.env.FIRESTORE_EMULATOR_HOST,
  };
}

function runAudit(extraArgs) {
  const outDir = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "pettxo-audit-out-")), "run");
  const result = spawnSync(process.execPath, [AUDIT_SCRIPT, `--project=${PROJECT}`, ...extraArgs, `--out-dir=${outDir}`], {
    cwd: FUNCTIONS_DIR,
    env: childEnv(),
    encoding: "utf8",
  });
  const read = (name) => fs.existsSync(path.join(outDir, name)) ?
    JSON.parse(fs.readFileSync(path.join(outDir, name), "utf8")) : null;
  return {
    status: result.status,
    stdout: result.stdout,
    stderr: result.stderr,
    outDir,
    summary: read("summary.json"),
    review: read("review_records.json"),
    manifest: read("manifest.json"),
  };
}

async function updateTimes() {
  const times = {};
  for (const {path: docPath} of rehearsal.documents) {
    const snapshot = await seedDb.doc(docPath).get();
    times[docPath] = snapshot.exists ? snapshot.updateTime.toMillis() : null;
  }
  return times;
}

test.before(async () => {
  if (skip) return;
  seedApp = initializeApp({projectId: PROJECT}, `audit-seed-${process.pid}`);
  seedDb = firestoreModule.getFirestore(seedApp);
  seedDb.settings({ignoreUndefinedProperties: true});
  rehearsal = buildRelationshipAuditRehearsal(new Date());
  await Promise.all(rehearsal.documents.map(({path: docPath, data}) => seedDb.doc(docPath).set(data)));
  seededUpdateTimes = await updateTimes();
  // The CLI snapshots at (now - 2s) truncated to the second; let the seed age past it.
  await new Promise((resolve) => setTimeout(resolve, 3500));
});

test.after(async () => {
  if (seedApp) await deleteApp(seedApp);
});

let countRun;
let fullRun;

test("count-only run with the production command shape reports every collection", {skip}, () => {
  countRun = runAudit(["--count-only"]);
  assert.equal(countRun.status, 0, countRun.stderr);
  assert.equal(countRun.summary.status, "COMPLETE");
  assert.equal(countRun.summary.reviewDetermination, "NOT_EVALUATED_IN_COUNT_ONLY_MODE");
  const counts = countRun.summary.countOnlyResult.collectionCounts;
  const expected = rehearsal.expected.sourceCounts;
  assert.deepEqual(counts, {
    userBlocks: expected.userBlocks,
    userRelationshipGuards: expected.userRelationshipGuards,
    bookings: expected.bookings,
    paymentAttempts: expected.paymentAttempts,
    canonicalPaymentOrderMappings: expected.paymentOrderMappings,
    canonicalQrPaymentMappings: expected.qrPaymentMappings,
    refunds: expected.refunds,
    paymentRefunds: expected.paymentRefunds,
    disputes: expected.disputes,
    bookingFinancialReconciliation: expected.bookingFinancialReconciliation,
    manualSettlementObligations: expected.manualSettlementObligations,
    providerPayouts: expected.providerPayouts,
    providerEarnings: expected.providerEarnings,
    payoutReadiness: expected.payoutReadiness,
  });
  assert.equal(countRun.summary.countOnlyResult.bookingsWithNonCanonicalState, 1);
  assert.equal(countRun.summary.countOnlyResult.queryShapesProbed, 14);
  assert.equal(countRun.review, null);
});

test("full run detects every seeded category with exact IDs and exits 2", {skip}, () => {
  const maxReads = countRun?.summary.countOnlyResult.suggestedMaxReads ?? 5000;
  fullRun = runAudit([`--max-reads=${maxReads}`]);
  assert.equal(fullRun.status, 2, fullRun.stderr);
  assert.equal(fullRun.summary.status, "COMPLETE");
  assert.equal(fullRun.summary.reviewDetermination, "RECORDS_NEED_REVIEW");
  assert.ok(fullRun.summary.readCount <= maxReads);
  const grouped = {};
  for (const record of fullRun.review.reviewRecords) {
    (grouped[record.category] ??= []).push(`${record.collection}/${record.documentId}`);
  }
  for (const list of Object.values(grouped)) list.sort();
  const expected = Object.fromEntries(Object.entries(rehearsal.expected.review).map(([key, list]) => [key, [...list].sort()]));
  assert.deepEqual(grouped, expected);
  const findings = fullRun.summary.findings;
  assert.deepEqual(findings.payments.strandedMoney.byReason, rehearsal.expected.strandedReasons);
  assert.equal(findings.userBlocks.blockConflictsWithOpenPaymentOrder, 1);
  assert.equal(findings.userBlocks.reciprocalPairs, 1);
  assert.equal(findings.userBlocks.missingUsers, 1);
  assert.equal(findings.multiDayPackages.partiallyElapsed, 1);
  assert.equal(findings.bookings.completedInDisputeWindow, 1);
  assert.equal(findings.bookings.completedPastDisputeWindow, 1);
  assert.equal(findings.pettxoProviderSettlement.heldPayouts, 1);
  assert.equal(findings.relationshipGuards.inconsistent, 2);
});

test("outputs are private, hashed, outside the repository, and hash-verified by the manifest", {skip}, () => {
  assert.ok(fullRun, "full run must have executed");
  assert.ok(!fullRun.outDir.startsWith(path.resolve(FUNCTIONS_DIR, "..")));
  assert.equal(fs.statSync(fullRun.outDir).mode & 0o777, 0o700);
  for (const name of ["summary.json", "summary.md", "review_records.json", "manifest.json"]) {
    assert.equal(fs.statSync(path.join(fullRun.outDir, name)).mode & 0o777, 0o600, name);
  }
  const {createHash} = require("node:crypto");
  for (const [name, digest] of Object.entries(fullRun.manifest.outputFiles)) {
    assert.equal(createHash("sha256").update(fs.readFileSync(path.join(fullRun.outDir, name))).digest("hex"), digest);
  }
  assert.equal(fullRun.manifest.mode, "emulator");
  assert.equal(fullRun.manifest.project, PROJECT);
  assert.equal(fullRun.manifest.status, "COMPLETE");
  assert.equal(fullRun.manifest.exitCode, 2);
  assert.equal(fullRun.manifest.writeLock.processWideMethodsLocked, 20);
  assert.match(fullRun.manifest.gitSha, /^[0-9a-f]{40}$|^unknown$/);
  assert.ok(fullRun.manifest.readTime && fullRun.manifest.readTime < fullRun.manifest.startedAt);
  // summary.json / summary.md carry no raw UIDs or document IDs.
  const summaryText = fs.readFileSync(path.join(fullRun.outDir, "summary.json"), "utf8") +
    fs.readFileSync(path.join(fullRun.outDir, "summary.md"), "utf8");
  for (const raw of ["\"uA\"", "\"uGhost\"", "rh_b0", "uX_uGhost", rehearsal.pairs.pairAB]) {
    assert.ok(!summaryText.includes(raw), `summary leaks ${raw}`);
  }
  assert.ok(fullRun.summary.reviewIndex.every((entry) => entry.hashedUids.every((value) => /^h_[0-9a-f]{16}$/.test(value))));
  assert.match(fullRun.review.salt, /^[0-9a-f]{64}$/);
});

test("the audit wrote nothing and a repeat run is identical", {skip}, async () => {
  const second = runAudit([]);
  assert.equal(second.status, 2, second.stderr);
  const strip = (findings) => ({...findings, evaluatedAt: null});
  assert.deepEqual(strip(second.summary.findings), strip(fullRun.summary.findings));
  assert.deepEqual(await updateTimes(), seededUpdateTimes);
  for (const collection of ["_migrations", "relationshipMigrationEvidence", "userBlockingActivationAudit"]) {
    assert.equal((await seedDb.collection(collection).get()).size, 0, collection);
  }
});

test("--max-reads abort produces an INCOMPLETE result with exit 1 and no review file", {skip}, () => {
  const run = runAudit(["--max-reads=5"]);
  assert.equal(run.status, 1);
  assert.equal(run.summary.status, "INCOMPLETE");
  assert.equal(run.summary.incompleteReason, "MAX_READS_EXCEEDED");
  assert.equal(run.summary.reviewDetermination, "UNKNOWN_INCOMPLETE");
  assert.equal(run.summary.findings, null);
  assert.ok(run.summary.readCount <= 5);
  assert.ok(run.summary.partialProgress);
  assert.equal(run.review, null);
  assert.equal(run.manifest.status, "INCOMPLETE");
  assert.match(fs.readFileSync(path.join(run.outDir, "summary.md"), "utf8"), /INCOMPLETE - partial progress/);
});

test("all reads describe one readTime: later writes are invisible to the snapshot", {skip}, async () => {
  const app = initializeApp({projectId: PROJECT}, `audit-snapshot-${process.pid}`);
  try {
    const db = enforceReadOnlyFirestore(firestoreModule.getFirestore(app));
    const readTime = chooseReadTime(Date.now());
    await new Promise((resolve) => setTimeout(resolve, 1100));
    await seedDb.doc("bookings/rh_zz_written_after_snapshot").set({status: "late"});
    const progress = {readCount: 0, maxReads: null, collectionsCompleted: {}, inProgress: null};
    const source = await scanRelationshipAuditSource({db, readTime, maxReads: null, progress});
    assert.equal(source.bookings.length, rehearsal.expected.sourceCounts.bookings);
    assert.ok(!source.bookings.some((doc) => doc.id === "rh_zz_written_after_snapshot"));
  } finally {
    await seedDb.doc("bookings/rh_zz_written_after_snapshot").delete();
    await deleteApp(app);
  }
});

test("every write path on a read-only Firestore instance throws and nothing is written", {skip}, async () => {
  const app = initializeApp({projectId: PROJECT}, `audit-write-${process.pid}`);
  try {
    const db = enforceReadOnlyFirestore(firestoreModule.getFirestore(app));
    const target = db.doc("bookings/rh_write_attempt");
    const violation = (error) => error.code === "AUDIT_READ_ONLY_VIOLATION";
    assert.throws(() => db.batch(), violation);
    assert.throws(() => db.bulkWriter(), violation);
    assert.throws(() => db.recursiveDelete(db.collection("bookings")), violation);
    assert.throws(() => db.runTransaction(async () => undefined), violation);
    await assert.rejects(target.set({x: 1}), violation);
    await assert.rejects(target.create({x: 1}), violation);
    await assert.rejects(db.doc("bookings/rh_b11_requested_plain").update({x: 1}), violation);
    await assert.rejects(db.doc("bookings/rh_b11_requested_plain").delete(), violation);
    await assert.rejects(db.collection("bookings").add({x: 1}), violation);
    await assert.rejects(db.runTransaction(async (transaction) => {
      transaction.set(target, {x: 1});
    }, {readOnly: true}), violation);
    assert.equal((await seedDb.doc("bookings/rh_write_attempt").get()).exists, false);
    assert.equal((await seedDb.collection("bookings").get()).size, rehearsal.expected.sourceCounts.bookings);
  } finally {
    await deleteApp(app);
  }
});

test("process-wide write lock makes every Firestore write method throw synchronously", {skip}, () => {
  const script = `
    const fsMod = require("firebase-admin/firestore");
    const {lockFirestoreWritePrototypes} = require("./lib/audit/readOnlyFirestore.js");
    const locked = lockFirestoreWritePrototypes(fsMod);
    const {initializeApp} = require("firebase-admin/app");
    const db = fsMod.getFirestore(initializeApp({projectId: process.env.GCLOUD_PROJECT}));
    const attempts = {
      set: () => db.doc("a/b").set({x: 1}),
      update: () => db.doc("a/b").update({x: 1}),
      create: () => db.doc("a/b").create({x: 1}),
      delete: () => db.doc("a/b").delete(),
      add: () => db.collection("a").add({x: 1}),
      batchSet: () => db.batch().set(db.doc("a/b"), {x: 1}),
      batchCommit: () => db.batch().commit(),
      bulkSet: () => db.bulkWriter().set(db.doc("a/b"), {x: 1}),
    };
    const results = {};
    for (const [name, run] of Object.entries(attempts)) {
      try { run(); results[name] = "NOT_THROWN"; } catch (error) { results[name] = error.code; }
    }
    process.stdout.write(JSON.stringify({locked: locked.length, results}));
  `;
  const result = spawnSync(process.execPath, ["-e", script], {cwd: FUNCTIONS_DIR, env: childEnv(), encoding: "utf8"});
  assert.equal(result.status, 0, result.stderr);
  const output = JSON.parse(result.stdout);
  assert.equal(output.locked, 20);
  for (const [name, code] of Object.entries(output.results)) assert.equal(code, "AUDIT_READ_ONLY_VIOLATION", name);
});
