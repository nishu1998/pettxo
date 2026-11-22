// Phase 3B-4a: operator scripts can never target production.
//
// 1. The guard function, as a table.
// 2. Guarded scripts spawned with a scrubbed environment, a fake `firebase`
//    binary on PATH and a firebase-admin load trap: refusals happen before any
//    Firebase module loads or the CLI runs.
// 3. Emulator-only: the repair script's dry run writes nothing; --apply writes.
// 4. Static checks over functions/scripts.
const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({services: ["firestore"]});
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {spawnSync} = require("node:child_process");

const {
  PRODUCTION_PROJECT_ID,
  ScriptTargetError,
  assertAppTarget,
  assertSafeScriptTarget,
} = require("../scripts/lib/targetGuard");

const FUNCTIONS_DIR = path.resolve(__dirname, "..");
const SCRIPTS_DIR = path.join(FUNCTIONS_DIR, "scripts");
const REPAIR_SCRIPT = path.join(SCRIPTS_DIR, "repair_completed_booking_nested_fields.js");
const GUARDED_SCRIPTS = [
  REPAIR_SCRIPT,
  path.join(SCRIPTS_DIR, "lib", "targetGuard.js"),
];
// Scripts that still build production REST URLs. They are NOT guarded (see
// docs/PETTXO_PHASE3B4_DECISIONS.md and the Phase 3B-4a report). A new entry
// here must be a deliberate decision.
const KNOWN_UNGUARDED_FIRESTORE_REST_SCRIPTS = new Set([
  "slot_capacity_projection_dry_run.py",
]);

const LOOPBACK = "127.0.0.1:8080";
// The production ID is taken from the guard constant (cross-checked against
// .firebaserc below), never written literally: test files must not contain it
// (test/firebaseTestSafety.test.js).
const PROD = PRODUCTION_PROJECT_ID;
const PROD_UPPER = PROD.toUpperCase();
const PROD_MIXED = PROD.charAt(0).toUpperCase() + PROD.slice(1, 4) + PROD.slice(4).toUpperCase();
const STAGING = "staging-x";

function guard(argv, env) {
  return assertSafeScriptTarget({scriptName: "test-script", argv, env});
}

function refuses(argv, env, pattern) {
  assert.throws(() => guard(argv, env), (error) => {
    assert.ok(error instanceof ScriptTargetError, `expected ScriptTargetError, got ${error}`);
    if (pattern) assert.match(error.message, pattern);
    return true;
  });
}

test("the hard-coded deny is the repository's production project", () => {
  const firebaserc = JSON.parse(fs.readFileSync(path.join(FUNCTIONS_DIR, "..", ".firebaserc"), "utf8"));
  assert.equal(PRODUCTION_PROJECT_ID, firebaserc.projects.default);
  assert.match(fs.readFileSync(path.join(SCRIPTS_DIR, "lib", "targetGuard.js"), "utf8"),
    new RegExp(`const PRODUCTION_PROJECT_ID = "${PROD}";`));
});

test("guard table: refusals", () => {
  refuses([], {}, /FIRESTORE_EMULATOR_HOST is not set/);
  refuses(["--project=demo-x"], {}, /FIRESTORE_EMULATOR_HOST is not set/);
  refuses(["--project=demo-x"], {FIRESTORE_EMULATOR_HOST: "10.0.0.5:8080"}, /not a loopback/);
  refuses(["--project=demo-x"], {FIRESTORE_EMULATOR_HOST: "firestore.googleapis.com:443"}, /not a loopback/);
  refuses([`--project=${PROD}`], {FIRESTORE_EMULATOR_HOST: LOOPBACK}, /can never be targeted/);
  refuses(["--project", PROD], {FIRESTORE_EMULATOR_HOST: LOOPBACK}, /can never be targeted/);
  refuses([`--allow-project=${PROD}`], {}, /can never be targeted/);
  refuses([`--allow-project=${PROD_UPPER} `], {}, /can never be targeted/);
  refuses([`--allow-project=  ${PROD_MIXED}`], {}, /can never be targeted/);
  refuses(["--allow-project=staging-x"], {GCLOUD_PROJECT: PROD}, new RegExp(`GCLOUD_PROJECT is ${PROD}`));
  refuses(["--allow-project=staging-x"], {GOOGLE_CLOUD_PROJECT: ` ${PROD_UPPER}`}, /GOOGLE_CLOUD_PROJECT/);
  refuses(["--project=demo-x"], {
    FIRESTORE_EMULATOR_HOST: LOOPBACK,
    GCLOUD_PROJECT: PROD,
  }, new RegExp(`GCLOUD_PROJECT is ${PROD}`));
  refuses(["--project=demo-x"], {
    FIRESTORE_EMULATOR_HOST: LOOPBACK,
    FIREBASE_CONFIG: JSON.stringify({projectId: PROD}),
  }, new RegExp(`FIREBASE_CONFIG is ${PROD}`));
  refuses(["--project=demo-x"], {
    FIRESTORE_EMULATOR_HOST: LOOPBACK,
    FIREBASE_CONFIG: "/path/to/firebase-config.json",
  }, /FIREBASE_CONFIG points to a file/);
  refuses(["--project=demo-x"], {FIRESTORE_EMULATOR_HOST: LOOPBACK, GCLOUD_PROJECT: "demo-y"}, /disagree/);
  refuses(["--allow-project=staging-x"], {GCLOUD_PROJECT: "staging-y"}, /disagree/);
  refuses(["--project=staging-x"], {FIRESTORE_EMULATOR_HOST: LOOPBACK}, /requires a demo-\* project/);
  refuses([], {FIRESTORE_EMULATOR_HOST: LOOPBACK}, /no project given/);
  refuses(["--allow-project=demo-x"], {}, /must use emulator mode/);
  refuses(["--allow-project=a", "--allow-project=b"], {}, /only once/);
  refuses(["--project="], {FIRESTORE_EMULATOR_HOST: LOOPBACK}, /empty project/);
});

test("guard table: allowed targets", () => {
  assert.deepEqual(guard(["--project=demo-x"], {FIRESTORE_EMULATOR_HOST: LOOPBACK}),
    {projectId: "demo-x", mode: "emulator"});
  assert.deepEqual(guard([], {FIRESTORE_EMULATOR_HOST: "localhost:8080", GCLOUD_PROJECT: "demo-y"}),
    {projectId: "demo-y", mode: "emulator"});
  assert.deepEqual(guard(["--project=demo-x"], {
    FIRESTORE_EMULATOR_HOST: "[::1]:8080",
    GCLOUD_PROJECT: "demo-x",
    GOOGLE_CLOUD_PROJECT: "demo-x",
  }), {projectId: "demo-x", mode: "emulator"});
  assert.deepEqual(guard(["--allow-project=staging-x"], {}),
    {projectId: STAGING, mode: "allowed-project"});
  assert.deepEqual(guard(["--allow-project=staging-x"], {GCLOUD_PROJECT: "staging-x"}),
    {projectId: STAGING, mode: "allowed-project"});
});

test("guard: required extra emulator hosts must also be loopback", () => {
  assert.throws(() => assertSafeScriptTarget({
    scriptName: "test-script",
    argv: ["--project=demo-x"],
    env: {FIRESTORE_EMULATOR_HOST: LOOPBACK},
    requiredEmulatorHosts: ["FIREBASE_AUTH_EMULATOR_HOST"],
  }), /FIREBASE_AUTH_EMULATOR_HOST is not set/);
  assert.throws(() => assertSafeScriptTarget({
    scriptName: "test-script",
    argv: ["--project=demo-x"],
    env: {FIRESTORE_EMULATOR_HOST: LOOPBACK, FIREBASE_AUTH_EMULATOR_HOST: "auth.example:9099"},
    requiredEmulatorHosts: ["FIREBASE_AUTH_EMULATOR_HOST"],
  }), /not a loopback/);
});

test("second check: the resolved app project must match and never be production", () => {
  const target = {projectId: "demo-x", mode: "emulator"};
  assert.doesNotThrow(() => assertAppTarget({options: {projectId: "demo-x"}}, target));
  assert.throws(() => assertAppTarget({options: {projectId: "demo-y"}}, target), ScriptTargetError);
  assert.throws(() => assertAppTarget({options: {}}, target), ScriptTargetError);
  assert.throws(() => assertAppTarget({options: {projectId: PROD}},
    {projectId: PROD, mode: "allowed-project"}), ScriptTargetError);
});

// --- spawned scripts --------------------------------------------------------

function makeSandbox() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "script-guard-"));
  const binDir = path.join(dir, "bin");
  fs.mkdirSync(binDir);
  const firebaseLog = path.join(dir, "firebase-cli.log");
  const trapLog = path.join(dir, "trap.log");
  const fakeFirebase = path.join(binDir, "firebase");
  fs.writeFileSync(fakeFirebase, `#!/bin/sh\necho "$@" >> "${firebaseLog}"\nexit 1\n`, {mode: 0o755});
  for (const name of ["gcloud"]) {
    fs.writeFileSync(path.join(binDir, name), `#!/bin/sh\necho "${name} $@" >> "${firebaseLog}"\nexit 1\n`, {mode: 0o755});
  }
  const trap = path.join(dir, "firebase-admin-trap.js");
  fs.writeFileSync(trap, `"use strict";
const Module = require("node:module");
const fs = require("node:fs");
const original = Module._load;
Module._load = function (request, parent, isMain) {
  if (/^(firebase-admin|@google-cloud\\/|google-auth-library|firebase-functions)(\\/|$)/.test(request)) {
    fs.appendFileSync(${JSON.stringify(trapLog)}, request + "\\n");
    throw new Error("TRAP: " + request + " loaded");
  }
  return original.apply(this, arguments);
};
`);
  return {dir, binDir, firebaseLog, trapLog, trap};
}

function runScript(script, args, extraEnv, sandbox) {
  const env = {
    PATH: `${sandbox.binDir}:/usr/bin:/bin`,
    HOME: sandbox.dir,
    CLOUDSDK_CONFIG: path.join(sandbox.dir, "gcloud"),
    NODE_OPTIONS: `--require ${sandbox.trap}`,
    ...extraEnv,
  };
  return spawnSync(process.execPath, [script, ...args], {
    cwd: FUNCTIONS_DIR,
    env,
    encoding: "utf8",
    timeout: 30_000,
  });
}

function readIfExists(file) {
  return fs.existsSync(file) ? fs.readFileSync(file, "utf8") : "";
}

const REFUSAL_CASES = [
  {name: "no emulator and no project", args: ["booking-1"], env: {}},
  {name: "non-loopback emulator host", args: ["booking-1", "--project=demo-x"],
    env: {FIRESTORE_EMULATOR_HOST: "10.1.2.3:8080"}},
  {name: "production via --project", args: ["booking-1", `--project=${PROD}`],
    env: {FIRESTORE_EMULATOR_HOST: LOOPBACK}},
  {name: "production via --allow-project", args: ["booking-1", `--allow-project=${PROD}`], env: {}},
  {name: "production via --allow-project, mixed case", args: ["booking-1", `--allow-project=${PROD_UPPER}`], env: {}},
  {name: "production via GCLOUD_PROJECT", args: ["booking-1", "--project=demo-x"],
    env: {FIRESTORE_EMULATOR_HOST: LOOPBACK, GCLOUD_PROJECT: PROD}},
  {name: "production via GOOGLE_CLOUD_PROJECT", args: ["booking-1", "--allow-project=staging-x"],
    env: {GOOGLE_CLOUD_PROJECT: PROD}},
  {name: "production via FIREBASE_CONFIG", args: ["booking-1", "--project=demo-x"],
    env: {FIRESTORE_EMULATOR_HOST: LOOPBACK, FIREBASE_CONFIG: JSON.stringify({projectId: PROD})}},
];

for (const scenario of REFUSAL_CASES) {
  test(`repair script refuses before loading Firebase: ${scenario.name}`, () => {
    const sandbox = makeSandbox();
    try {
      const result = runScript(REPAIR_SCRIPT, scenario.args, scenario.env, sandbox);
      assert.notEqual(result.status, 0, `exit status: ${result.status}`);
      assert.match(result.stderr, /refusing to run/);
      assert.doesNotMatch(result.stderr, /TRAP:/);
      assert.equal(readIfExists(sandbox.trapLog), "", "firebase-admin must not be loaded");
      assert.equal(readIfExists(sandbox.firebaseLog), "", "no CLI must be invoked");
    } finally {
      fs.rmSync(sandbox.dir, {recursive: true, force: true});
    }
  });
}

test("repair script loads firebase-admin only after the guard passes", () => {
  const sandbox = makeSandbox();
  try {
    const result = runScript(REPAIR_SCRIPT, ["booking-1", "--project=demo-guard-check"], {
      FIRESTORE_EMULATOR_HOST: LOOPBACK,
    }, sandbox);
    assert.notEqual(result.status, 0);
    assert.doesNotMatch(result.stderr, /refusing to run/);
    assert.match(result.stderr, /TRAP: firebase-admin/);
    assert.match(readIfExists(sandbox.trapLog), /^firebase-admin/);
    assert.equal(readIfExists(sandbox.firebaseLog), "");
  } finally {
    fs.rmSync(sandbox.dir, {recursive: true, force: true});
  }
});

test("repair script rejects unknown options and conflicting modes", () => {
  const sandbox = makeSandbox();
  try {
    for (const args of [
      ["booking-1", "--project=demo-x", "--force"],
      ["booking-1", "--project=demo-x", "--apply", "--dry-run"],
    ]) {
      const result = runScript(REPAIR_SCRIPT, args, {FIRESTORE_EMULATOR_HOST: LOOPBACK}, sandbox);
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /Unknown option|cannot be combined/);
      assert.equal(readIfExists(sandbox.trapLog), "");
    }
  } finally {
    fs.rmSync(sandbox.dir, {recursive: true, force: true});
  }
});

// --- emulator: dry run vs apply ----------------------------------------------

test("repair script: dry run writes nothing, --apply moves literal dotted keys", {
  skip: firebaseEmulator.skip,
}, async () => {
  const {db} = require("../lib/shared/firebase.js");
  const projectId = firebaseEmulator.projectId;
  const bookingId = `repair-guard-${Date.now()}`;
  const ref = db.collection("bookings").doc(bookingId);
  const completedAt = new Date("2026-11-01T10:00:00Z");
  // set() stores dotted keys literally.
  await ref.set({"state": "COMPLETED_FINAL", "lifecycle.completedAt": completedAt, "payout.status": "pending"});
  const sandbox = makeSandbox();
  const env = {FIRESTORE_EMULATOR_HOST: process.env.FIRESTORE_EMULATOR_HOST, NODE_OPTIONS: ""};
  try {
    const dry = runScript(REPAIR_SCRIPT, [bookingId, `--project=${projectId}`], env, sandbox);
    assert.equal(dry.status, 0, dry.stderr);
    assert.match(dry.stdout, /"mode": "dry-run"/);
    assert.match(dry.stdout, /"from": "lifecycle\.completedAt"/);
    assert.match(dry.stdout, /"from": "payout\.status"/);
    const untouched = (await ref.get()).data();
    assert.ok(untouched["lifecycle.completedAt"], "dry run must not change the document");
    assert.equal(untouched.lifecycle, undefined);

    const applied = runScript(REPAIR_SCRIPT, [bookingId, `--project=${projectId}`, "--apply"], env, sandbox);
    assert.equal(applied.status, 0, applied.stderr);
    const repaired = (await ref.get()).data();
    assert.equal(repaired["lifecycle.completedAt"], undefined);
    assert.equal(repaired["payout.status"], undefined);
    assert.equal(repaired.lifecycle.completedAt.toDate().toISOString(), completedAt.toISOString());
    assert.equal(repaired.payout.status, "pending");
    assert.equal(readIfExists(sandbox.firebaseLog), "");
  } finally {
    fs.rmSync(sandbox.dir, {recursive: true, force: true});
    await ref.delete();
  }
});

// --- static checks -------------------------------------------------------------

function scriptFiles(dir) {
  const files = [];
  for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) files.push(...scriptFiles(full));
    else files.push(full);
  }
  return files;
}

test("static: reset_test_data is retired", () => {
  assert.equal(fs.existsSync(path.join(SCRIPTS_DIR, "reset_test_data.js")), false);
  const pkg = JSON.parse(fs.readFileSync(path.join(FUNCTIONS_DIR, "package.json"), "utf8"));
  assert.equal(pkg.scripts["reset-test-data"], undefined);
  assert.equal(Object.values(pkg.scripts).some((command) => /reset_test_data/.test(command)), false);
});

test("static: guarded scripts never build production REST URLs", () => {
  for (const file of GUARDED_SCRIPTS) {
    const source = fs.readFileSync(file, "utf8");
    assert.doesNotMatch(source, /googleapis\.com/, path.relative(FUNCTIONS_DIR, file));
  }
});

test("static: no new script builds firestore.googleapis.com URLs", () => {
  const offenders = scriptFiles(SCRIPTS_DIR)
    .filter((file) => /firestore\.googleapis\.com/.test(fs.readFileSync(file, "utf8")))
    .map((file) => path.relative(SCRIPTS_DIR, file))
    .filter((name) => !KNOWN_UNGUARDED_FIRESTORE_REST_SCRIPTS.has(name));
  assert.deepEqual(offenders, []);
});

test("static: the repair script runs the guard before requiring firebase-admin", () => {
  const source = fs.readFileSync(REPAIR_SCRIPT, "utf8");
  const guardRequire = source.indexOf("require(\"./lib/targetGuard\")");
  const guardCall = source.indexOf("assertSafeScriptTarget({");
  const adminRequire = source.search(/require\("firebase-admin/);
  assert.ok(guardRequire >= 0 && guardCall >= 0 && adminRequire >= 0);
  assert.ok(guardCall < adminRequire, "guard call must come before firebase-admin is required");
  assert.doesNotMatch(source, /initializeApp\(\s*\)/, "no ambient initializeApp()");
  assert.match(source, /assertAppTarget\(app, target\)/);
});

test("static: the guard module loads no Firebase or network module", () => {
  const source = fs.readFileSync(path.join(SCRIPTS_DIR, "lib", "targetGuard.js"), "utf8");
  const requires = [...source.matchAll(/require\(["']([^"']+)["']\)/g)].map((match) => match[1]);
  assert.deepEqual(requires, []);
});
