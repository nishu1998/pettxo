"use strict";
require("./helpers/firebaseTestSafety").assertUnitTestIsolation();

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const safety = require("./helpers/firebaseTestSafety");

const FUNCTIONS_DIR = path.resolve(__dirname, "..");
const TEST_DIR = __dirname;
const SHARED_FIREBASE = path.join(FUNCTIONS_DIR, "lib", "shared", "firebase.js");
const GUARD_FILES = new Set([
  path.join(TEST_DIR, "helpers", "firebaseTestSafety.js"),
  path.join(TEST_DIR, "helpers", "testProcessPreflight.js"),
  __filename, // the scanner's own fixtures contain the patterns it rejects
]);
const DIRECT_INIT = /\binitializeApp\s*\(|\binitializeTestEnvironment\s*\(|\bgetFirestore\s*\(|\bgetAuth\s*\(|\bgetStorage\s*\(|lib\/shared\/firebase/;
const EXPLICIT_APP_INIT = /\binitializeApp\s*\(|\binitializeTestEnvironment\s*\(/;
const REQUIRE = /require\((["'`])([^"'`]+)\1\)/g;

function resolveLocal(from, specifier) {
  if (!specifier.startsWith(".")) return null;
  const base = path.resolve(path.dirname(from), specifier);
  for (const candidate of [base, `${base}.js`, path.join(base, "index.js")]) {
    if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) return candidate;
  }
  return null;
}

function localRequireClosure(entry, seen = new Set()) {
  if (seen.has(entry)) return seen;
  seen.add(entry);
  const source = fs.readFileSync(entry, "utf8");
  for (const match of source.matchAll(REQUIRE)) {
    const resolved = resolveLocal(entry, match[2]);
    if (resolved) localRequireClosure(resolved, seen);
  }
  return seen;
}

function firstIndex(source, pattern) {
  const match = pattern.exec(source);
  return match ? match.index : Infinity;
}

/**
 * Returns the safety violations for one test source. Exported shape is used by
 * the self-test below so the scanner itself is proven to catch an unguarded file.
 */
function scanTestSource(source, {initialisesTransitively = false} = {}) {
  const violations = [];
  const direct = DIRECT_INIT.test(source);
  if (!direct && !initialisesTransitively) return violations;
  const emulatorGuard = firstIndex(source, /\bemulatorGate\s*\(/);
  const unitGuard = firstIndex(source, /\bassertUnitTestIsolation\s*\(/);
  const guard = Math.min(emulatorGuard, unitGuard);
  if (guard === Infinity) {
    violations.push("initialises Firebase (directly or through lib/shared/firebase) without the firebaseTestSafety guard");
    return violations;
  }
  const firstLibRequire = firstIndex(source, /require\((["'`])(?:\.\.\/)+lib\//);
  const firstInit = firstIndex(source, EXPLICIT_APP_INIT);
  if (guard > firstLibRequire || guard > firstInit) {
    violations.push("the firebaseTestSafety guard must run before the first ../lib require and before any app initialisation");
  }
  if (EXPLICIT_APP_INIT.test(source) && emulatorGuard === Infinity) {
    violations.push("explicit initializeApp/initializeTestEnvironment requires emulatorGate, not only unit isolation");
  }
  if (/pettexo-d9409/.test(source)) {
    violations.push("references the production project ID");
  }
  for (const match of source.matchAll(/projectId\s*:\s*(["'`])([^"'`]*)\1?/g)) {
    if (!match[2].startsWith("demo-")) violations.push(`literal projectId "${match[2]}" is not demo-*`);
  }
  return violations;
}

function testSources() {
  const files = fs.readdirSync(TEST_DIR)
    .filter((name) => name.endsWith(".js"))
    .map((name) => path.join(TEST_DIR, name));
  const helpers = fs.readdirSync(path.join(TEST_DIR, "helpers"))
    .filter((name) => name.endsWith(".js"))
    .map((name) => path.join(TEST_DIR, "helpers", name));
  return [...files, ...helpers].filter((file) => !GUARD_FILES.has(file));
}

test("compiled lib exists so the transitive Firebase scan is meaningful", () => {
  assert.ok(fs.existsSync(SHARED_FIREBASE), "run `npm run build` before the test suite");
});

test("every test file that initialises Firebase runs the production-isolation guard first", () => {
  const failures = [];
  let guarded = 0;
  for (const file of testSources()) {
    const source = fs.readFileSync(file, "utf8");
    const initialisesTransitively = localRequireClosure(file).has(SHARED_FIREBASE);
    const violations = scanTestSource(source, {initialisesTransitively});
    if (DIRECT_INIT.test(source) || initialisesTransitively) guarded += 1;
    for (const violation of violations) failures.push(`${path.relative(FUNCTIONS_DIR, file)}: ${violation}`);
  }
  assert.deepEqual(failures, []);
  assert.ok(guarded >= 53, `expected at least 53 Firebase-initialising test files, found ${guarded}`);
});

test("the scanner rejects an unguarded or production-targeted test file", () => {
  assert.match(scanTestSource('const {db} = require("../lib/shared/firebase");')[0], /without the firebaseTestSafety guard/);
  assert.ok(scanTestSource("require('x');", {initialisesTransitively: true}).length > 0);
  assert.ok(scanTestSource([
    'const {initializeApp} = require("firebase-admin/app");',
    'require("./helpers/firebaseTestSafety").assertUnitTestIsolation();',
    'initializeApp({projectId: "pettexo-d9409"});',
  ].join("\n")).some((violation) => /production project ID/.test(violation)));
  assert.deepEqual(scanTestSource([
    'const gate = require("./helpers/firebaseTestSafety").emulatorGate({projectId: "demo-x"});',
    'const {initializeApp} = require("firebase-admin/app");',
    'initializeApp({projectId: "demo-x"});',
  ].join("\n")), []);
});

function scratchEnv(extra = {}) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "pettxo-safety-"));
  return {HOME: home, ...extra};
}

test("emulatorGate skips when no emulator is configured and pins a demo project", () => {
  const env = scratchEnv();
  const gate = safety.emulatorGate({services: ["firestore"]}, env);
  assert.equal(gate.enabled, false);
  assert.match(gate.skip, /test:emulator/);
  assert.equal(env.GCLOUD_PROJECT, safety.DEFAULT_UNIT_PROJECT_ID);
});

test("emulatorGate refuses non-loopback hosts, partial environments, and non-demo projects", () => {
  assert.throws(() => safety.emulatorGate({projectId: "demo-x"},
    scratchEnv({FIRESTORE_EMULATOR_HOST: "firestore.googleapis.com:443"})), /not a loopback/);
  assert.throws(() => safety.emulatorGate({projectId: "demo-x", services: ["firestore", "storage"]},
    scratchEnv({FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080"})), /partial emulator environment/);
  assert.throws(() => safety.emulatorGate({projectId: "pettexo-d9409"},
    scratchEnv({FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080"})), /demo-\* project/);
  assert.throws(() => safety.emulatorGate({},
    scratchEnv({FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080", GCLOUD_PROJECT: "pettexo-d9409"})), /demo-\* project/);
  const ok = safety.emulatorGate({projectId: "demo-x"}, scratchEnv({FIRESTORE_EMULATOR_HOST: "localhost:8080"}));
  assert.deepEqual([ok.enabled, ok.projectId], [true, "demo-x"]);
});

test("guards refuse reachable Google credentials without reading them", () => {
  assert.throws(() => safety.assertUnitTestIsolation(scratchEnv({GOOGLE_APPLICATION_CREDENTIALS: "/nonexistent.json"})),
    /GOOGLE_APPLICATION_CREDENTIALS is set/);
  const env = scratchEnv();
  const adcDir = path.join(env.HOME, ".config", "gcloud");
  fs.mkdirSync(adcDir, {recursive: true});
  fs.writeFileSync(path.join(adcDir, "application_default_credentials.json"), "{}");
  assert.throws(() => safety.assertUnitTestIsolation(env), /application default credentials exist under HOME/);
  assert.throws(() => safety.emulatorGate({projectId: "demo-x"}, {...env, FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080"}),
    /application default credentials/);
});

test("the test-process preflight requires a pinned demo project", () => {
  assert.throws(() => safety.assertTestProcessPreflight(scratchEnv()), /must be set/);
  assert.throws(() => safety.assertTestProcessPreflight(scratchEnv({GCLOUD_PROJECT: "pettexo-d9409",
    GOOGLE_CLOUD_PROJECT: "pettexo-d9409"})), /not a demo-\* project/);
  safety.assertTestProcessPreflight(scratchEnv({GCLOUD_PROJECT: "demo-a", GOOGLE_CLOUD_PROJECT: "demo-a"}));
});

test("npm test scripts route through the isolated runner with a demo emulator project", () => {
  const pkg = JSON.parse(fs.readFileSync(path.join(FUNCTIONS_DIR, "package.json"), "utf8"));
  assert.match(pkg.scripts.test, /scripts\/run_tests\.js unit/);
  assert.match(pkg.scripts["test:emulator"], /scripts\/run_tests\.js emulator/);
  for (const script of Object.values(pkg.scripts)) {
    assert.doesNotMatch(script, /node --test(?! *$)/, "no script may invoke node --test directly");
  }
  const runner = fs.readFileSync(path.join(FUNCTIONS_DIR, "scripts", "run_tests.js"), "utf8");
  assert.match(runner, /EMULATOR_PROJECT_ID = "demo-[a-z0-9-]+"/);
  assert.match(runner, /"--project", EMULATOR_PROJECT_ID/);
  assert.match(runner, /NODE_OPTIONS: `--require \$\{PREFLIGHT\}`/);
});
