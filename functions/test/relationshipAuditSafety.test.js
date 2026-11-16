"use strict";
require("./helpers/firebaseTestSafety").assertUnitTestIsolation();

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const cli = require("../lib/audit/relationshipAuditCli.js");

const FUNCTIONS_DIR = path.resolve(__dirname, "..");
const REPO_DIR = path.resolve(FUNCTIONS_DIR, "..");
const PROD = cli.PRODUCTION_PROJECT_ID;
const SA = cli.DEFAULT_AUDIT_SERVICE_ACCOUNT;
const READ_ONLY_GRANTS = ["datastore.entities.get", "datastore.entities.list"];

function tempDir(prefix = "pettxo-audit-test-") {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

function fakeDeps(overrides = {}) {
  const calls = {createFirestore: [], testIamPermissions: [], log: [], error: []};
  const deps = {
    env: {HOME: tempDir()},
    now: () => new Date("2026-11-17T00:00:00.000Z"),
    log: (line) => calls.log.push(line),
    error: (line) => calls.error.push(line),
    createFirestore: async (...args) => {
      calls.createFirestore.push(args);
      throw new Error("createFirestore reached");
    },
    resolveCredential: () => ({type: "impersonated_service_account", principal: SA,
      source: "well-known ADC file", keyFileOnDisk: false}),
    testIamPermissions: async (...args) => {
      calls.testIamPermissions.push(args);
      return READ_ONLY_GRANTS;
    },
    gitState: () => ({sha: "test", dirtyAuditSources: false}),
    lockedWriteMethods: ["DocumentReference.set"],
    ...overrides,
  };
  return {deps, calls};
}

async function expectRefusal(argv, overrides, pattern) {
  const {deps, calls} = fakeDeps(overrides);
  const code = await cli.runAuditCli(argv, deps);
  assert.equal(code, 1);
  assert.equal(calls.createFirestore.length, 0, "no Firestore client may be created on refusal");
  assert.match(calls.error.join("\n"), pattern);
  return calls;
}

test("refuses with missing or contradictory flags before any client is created", async () => {
  await expectRefusal([], {}, /--project is required/);
  await expectRefusal([`--project=${PROD}`], {}, /requires --confirm-production-read/);
  await expectRefusal(["--confirm-production-read"], {}, /--project is required/);
  await expectRefusal(["--project=demo-x", "--confirm-production-read"], {}, /cannot be used with a demo/);
  await expectRefusal([`--project=${PROD}`, "--confirm-read-only"], {}, /retired/);
  await expectRefusal(["--project=demo-x", "--max-reads"], {}, /requires a value/);
  await expectRefusal(["--project=demo-x", "--max-reads=-5"], {}, /positive integer/);
  await expectRefusal(["--project=demo-x", "--unexpected"], {}, /unknown argument/);
});

test("refuses any project other than demo-* or the production project", async () => {
  for (const project of ["pettexo-staging", `${PROD}x`, PROD.toUpperCase(), "demo_x", ""]) {
    await expectRefusal([`--project=${project}`, "--confirm-production-read"], {}, /not allowed|is required|cannot be used/);
  }
});

test("emulator mode requires a loopback emulator; production refuses emulator variables", async () => {
  await expectRefusal(["--project=demo-x"], {}, /FIRESTORE_EMULATOR_HOST/);
  await expectRefusal(["--project=demo-x"], {env: {FIRESTORE_EMULATOR_HOST: "firestore.googleapis.com:443"}},
    /loopback/);
  await expectRefusal([`--project=${PROD}`, "--confirm-production-read"],
    {env: {FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080"}}, /refuses while FIRESTORE_EMULATOR_HOST/);
});

function writeAdc(home, content) {
  const dir = path.join(home, ".config", "gcloud");
  fs.mkdirSync(dir, {recursive: true});
  const file = path.join(dir, "application_default_credentials.json");
  fs.writeFileSync(file, JSON.stringify(content));
  return file;
}

test("credential resolution refuses user credentials and reads only type and identity", () => {
  const home = tempDir();
  // Synthetic placeholders only; no real secrets.
  writeAdc(home, {type: "authorized_user", client_id: "placeholder", refresh_token: "placeholder"});
  assert.throws(() => cli.resolveCredentialIdentity({HOME: home}), /user account \(authorized_user\)/);
  writeAdc(home, {type: "external_account"});
  assert.throws(() => cli.resolveCredentialIdentity({HOME: home}), /not accepted/);
  assert.throws(() => cli.resolveCredentialIdentity({HOME: tempDir()}), /no application default credential/);
  writeAdc(home, {
    type: "impersonated_service_account",
    service_account_impersonation_url:
      `https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${SA}:generateAccessToken`,
    source_credentials: {type: "authorized_user", refresh_token: "placeholder"},
  });
  assert.deepEqual(cli.resolveCredentialIdentity({HOME: home}),
    {type: "impersonated_service_account", principal: SA, source: "well-known ADC file", keyFileOnDisk: false});
  const keyFile = path.join(home, "key.json");
  fs.writeFileSync(keyFile, JSON.stringify({type: "service_account", client_email: "other@x.iam.gserviceaccount.com"}));
  assert.deepEqual(cli.resolveCredentialIdentity({HOME: home, GOOGLE_APPLICATION_CREDENTIALS: keyFile}),
    {type: "service_account", principal: "other@x.iam.gserviceaccount.com",
      source: "GOOGLE_APPLICATION_CREDENTIALS", keyFileOnDisk: true});
});

test("production refuses a user credential through the real resolver", async () => {
  const home = tempDir();
  writeAdc(home, {type: "authorized_user", refresh_token: "placeholder"});
  const calls = await expectRefusal([`--project=${PROD}`, "--confirm-production-read"],
    {env: {HOME: home}, resolveCredential: (env) => cli.resolveCredentialIdentity(env)}, /authorized_user/);
  assert.equal(calls.testIamPermissions.length, 0);
});

test("production refuses an unexpected service-account principal", async () => {
  await expectRefusal([`--project=${PROD}`, "--confirm-production-read"], {
    resolveCredential: () => ({type: "impersonated_service_account", principal: "editor@x.iam.gserviceaccount.com",
      source: "well-known ADC file", keyFileOnDisk: false}),
  }, /not the expected/);
});

test("production refuses when mocked testIamPermissions reports any write permission", async () => {
  for (const permission of cli.FORBIDDEN_WRITE_PERMISSIONS) {
    await expectRefusal([`--project=${PROD}`, "--confirm-production-read"], {
      testIamPermissions: async () => [...READ_ONLY_GRANTS, permission],
    }, new RegExp(`write-capable permissions: ${permission.replace(/\./g, "\\.")}`));
  }
  await expectRefusal([`--project=${PROD}`, "--confirm-production-read"], {
    testIamPermissions: async () => ["datastore.entities.get"],
  }, /lacks required read permissions: datastore\.entities\.list/);
  await expectRefusal([`--project=${PROD}`, "--confirm-production-read"], {
    testIamPermissions: async () => {
      throw new Error("permission check unavailable");
    },
  }, /permission check unavailable/);
});

test("production checks the exact permission list, then reaches Firestore only after every gate passes", async () => {
  const {deps, calls} = fakeDeps();
  const outDir = path.join(tempDir(), "out");
  const code = await cli.runAuditCli([`--project=${PROD}`, "--confirm-production-read", `--out-dir=${outDir}`], deps);
  assert.equal(code, 1); // the fake createFirestore throws after being reached
  assert.deepEqual(calls.testIamPermissions[0][1], [...cli.FORBIDDEN_WRITE_PERMISSIONS, ...cli.REQUIRED_READ_PERMISSIONS]);
  assert.equal(calls.testIamPermissions[0][2], SA);
  assert.deepEqual(calls.createFirestore, [[PROD, "production"]]);
  const summary = JSON.parse(fs.readFileSync(path.join(outDir, "summary.json"), "utf8"));
  assert.equal(summary.status, "INCOMPLETE");
  assert.equal(fs.existsSync(path.join(outDir, "review_records.json")), false);
});

test("refuses when the initialised app resolves a different project", async () => {
  const outDir = path.join(tempDir(), "out");
  const {deps, calls} = fakeDeps({
    env: {HOME: tempDir(), FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080"},
    createFirestore: async () => ({
      db: {projectId: "demo-other", formattedName: "projects/demo-other/databases/(default)"},
      appProjectId: "demo-x",
      close: async () => undefined,
    }),
  });
  assert.equal(await cli.runAuditCli(["--project=demo-x", `--out-dir=${outDir}`], deps), 1);
  assert.match(calls.error.join("\n"), /PROJECT_MISMATCH/);
});

test("refuses to run without the process-wide write lock and refuses output inside the repository", async () => {
  await expectRefusal(["--project=demo-x"], {env: {HOME: tempDir(), FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080"},
    lockedWriteMethods: []}, /write lock is not installed/);
  await expectRefusal(["--project=demo-x", `--out-dir=${path.join(FUNCTIONS_DIR, "audit-out")}`],
    {env: {HOME: tempDir(), FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080"}}, /outside the repository/);
  assert.equal(fs.existsSync(path.join(FUNCTIONS_DIR, "audit-out")), false);
});

test("default output directory is outside the repository under PettxoReleaseBackups/audits", () => {
  const dir = cli.defaultOutputDirectory(new Date("2026-11-17T01:02:03.000Z"), "/Users/example");
  assert.equal(dir, "/Users/example/PettxoReleaseBackups/audits/2026-11-17T01-02-03-000Z");
  assert.doesNotThrow(() => cli.assertOutputDirectoryAllowed(path.join(tempDir(), "x"), REPO_DIR));
});

/* ---- static import graph: the audit cannot reach write-capable project code ---- */

const REQUIRE = /require\((["'`])([^"'`]+)\1\)/g;

function closure(entry, seen = new Set()) {
  if (seen.has(entry)) return seen;
  seen.add(entry);
  for (const match of fs.readFileSync(entry, "utf8").matchAll(REQUIRE)) {
    if (!match[2].startsWith(".")) continue;
    const base = path.resolve(path.dirname(entry), match[2]);
    const resolved = [base, `${base}.js`, path.join(base, "index.js")].find((candidate) =>
      fs.existsSync(candidate) && fs.statSync(candidate).isFile());
    if (resolved) closure(resolved, seen);
  }
  return seen;
}

const AUDIT_ENTRY = path.join(FUNCTIONS_DIR, "scripts", "read_only_relationship_audit.js");
const ALLOWED_PROJECT_MODULES = new Set([
  "scripts/read_only_relationship_audit.js",
  "lib/audit/readOnlyFirestore.js",
  "lib/audit/relationshipAuditCli.js",
  "lib/audit/relationshipAuditEvaluation.js",
  "lib/audit/relationshipAuditScanner.js",
  "lib/booking/schema/bookingDocumentV3.js",
  "lib/booking/schema/timestampNormalization.js",
  "lib/booking/domain/bookingContracts.js",
  "lib/booking/domain/bookingSnapshots.js",
  "lib/booking/domain/rangeBooking.js",
  "lib/booking/domain/slotBooking.js",
  "lib/booking/domain/continuousSlotScheduleV3.js",
]);
const FIRESTORE_WRITE_CALL = new RegExp([
  String.raw`\.(doc|ref)\([^)]*\)\s*\.(set|update|create|delete)\(`,
  String.raw`\b(tx|transaction)\.(set|update|create|delete)\(`,
  String.raw`\.batch\(\)`,
  String.raw`\.bulkWriter\(`,
  String.raw`\.recursiveDelete\(`,
  String.raw`\.add\(\{`,
  String.raw`FieldValue\.`,
  String.raw`shared\/firebase`,
].join("|"));

function stripComments(source) {
  return source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:"'`\\])\/\/.*$/gm, "$1");
}

test("the audit import graph contains only read-only project modules", () => {
  const modules = [...closure(AUDIT_ENTRY)].map((file) => path.relative(FUNCTIONS_DIR, file)).sort();
  assert.deepEqual(modules.filter((module) => !ALLOWED_PROJECT_MODULES.has(module)), []);
  for (const module of modules) {
    const source = stripComments(fs.readFileSync(path.join(FUNCTIONS_DIR, module), "utf8"));
    assert.doesNotMatch(source, FIRESTORE_WRITE_CALL, `${module} contains a Firestore write call`);
    if (module === "lib/audit/readOnlyFirestore.js") continue; // the enforcing wrapper itself
    for (const match of source.matchAll(/\.runTransaction\(/g)) {
      const call = source.slice(match.index, match.index + 600);
      assert.match(call, /readOnly:\s*true/, `${module} runs a non read-only transaction`);
    }
  }
  assert.ok(!modules.includes("lib/blocking/historicalRelationshipMigration.js"));
  assert.ok(!modules.includes("lib/blocking/userBlocking.js"));
});

test("audit modules are not exported as deployable Cloud Functions", () => {
  const index = fs.readFileSync(path.join(FUNCTIONS_DIR, "src", "index.ts"), "utf8");
  assert.doesNotMatch(index, /audit\//);
  const indexClosure = [...closure(path.join(FUNCTIONS_DIR, "lib", "index.js"))]
    .map((file) => path.relative(FUNCTIONS_DIR, file));
  assert.deepEqual(indexClosure.filter((file) => file.startsWith("lib/audit/")), []);
  for (const file of fs.readdirSync(path.join(FUNCTIONS_DIR, "src", "audit"))) {
    const source = fs.readFileSync(path.join(FUNCTIONS_DIR, "src", "audit", file), "utf8");
    assert.doesNotMatch(source, /firebase-functions/, `${file} must not define Cloud Functions`);
  }
});
