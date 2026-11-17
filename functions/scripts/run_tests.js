#!/usr/bin/env node
"use strict";

/**
 * Production-isolated backend test runner.
 *
 *   node scripts/run_tests.js unit [test files...]
 *       Runs the suite with no emulators. Emulator tests skip themselves.
 *   node scripts/run_tests.js emulator [test files...]
 *       Starts the Firestore and Storage emulators with an explicit demo-*
 *       project through `firebase emulators:exec` and runs the full suite.
 *
 * Every child process gets a scrubbed environment:
 *   - an empty temporary HOME (google-auth-library looks for
 *     application_default_credentials.json under $HOME/.config/gcloud, and
 *     firebase-tools keeps its login tokens under $HOME/.config),
 *   - an empty temporary CLOUDSDK_CONFIG (gcloud config, and the
 *     `gcloud config config-helper` project fallback),
 *   - no GOOGLE_APPLICATION_CREDENTIALS,
 *   - GCLOUD_PROJECT / GOOGLE_CLOUD_PROJECT pinned to a demo-* project,
 *   - NODE_OPTIONS=--require test/helpers/testProcessPreflight.js, which
 *     re-verifies all of the above inside every test process.
 * Only PATH, locale and timezone variables are inherited.
 */

const {spawnSync} = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const {
  assertTestProcessPreflight,
  credentialProblems,
  LOOPBACK_HOST_PATTERN,
} = require("../test/helpers/firebaseTestSafety");

const FUNCTIONS_DIR = path.resolve(__dirname, "..");
const REPO_DIR = path.resolve(FUNCTIONS_DIR, "..");
const PREFLIGHT = path.join(FUNCTIONS_DIR, "test", "helpers", "testProcessPreflight.js");
const UNIT_PROJECT_ID = "demo-pettxo-unit";
const EMULATOR_PROJECT_ID = "demo-pettxo-test";
const INHERITED = ["PATH", "LANG", "LC_ALL", "LC_CTYPE", "TZ", "TERM", "NO_COLOR", "CI", "JAVA_HOME"];

function fail(message) {
  process.stderr.write(`[run_tests] ${message}\n`);
  process.exit(1);
}

function defaultTestFiles() {
  return fs.readdirSync(path.join(FUNCTIONS_DIR, "test"))
    .filter((name) => name.endsWith(".test.js"))
    .sort()
    .map((name) => path.join("test", name));
}

function scrubbedEnvironment(projectId, scratch) {
  const env = {};
  for (const name of INHERITED) if (process.env[name]) env[name] = process.env[name];
  const home = path.join(scratch, "home");
  const cloudsdk = path.join(scratch, "cloudsdk");
  fs.mkdirSync(home, {recursive: true, mode: 0o700});
  fs.mkdirSync(cloudsdk, {recursive: true, mode: 0o700});
  env.HOME = home;
  env.CLOUDSDK_CONFIG = cloudsdk;
  env.GCLOUD_PROJECT = projectId;
  env.GOOGLE_CLOUD_PROJECT = projectId;
  // Reuse already-downloaded emulator binaries without exposing the real HOME.
  const emulatorCache = path.join(os.homedir(), ".cache", "firebase", "emulators");
  if (fs.existsSync(emulatorCache)) env.FIREBASE_EMULATORS_PATH = emulatorCache;
  const problems = credentialProblems(env);
  if (problems.length > 0) fail(`scrubbed environment still exposes credentials: ${problems.join("; ")}`);
  return env;
}

function loadsStorageRules(file) {
  const source = fs.readFileSync(path.resolve(FUNCTIONS_DIR, file), "utf8");
  return source.includes("initializeTestEnvironment") && source.includes("storage.rules");
}

function runNodeTests(env, files, nodeTestArgs = []) {
  const childEnv = {...env, NODE_OPTIONS: `--require ${PREFLIGHT}`};
  try {
    assertTestProcessPreflight(childEnv);
  } catch (error) {
    fail(error.message);
  }
  process.stdout.write(
    `[run_tests] node --test (${files.length} files) project=${childEnv.GCLOUD_PROJECT} ` +
    `firestore=${childEnv.FIRESTORE_EMULATOR_HOST ?? "none"} storage=${childEnv.FIREBASE_STORAGE_EMULATOR_HOST ?? "none"} ` +
    `HOME=<scrubbed> CLOUDSDK_CONFIG=<scrubbed> GOOGLE_APPLICATION_CREDENTIALS=<unset>\n`,
  );
  const extra = process.env.PETTXO_TEST_REPORTER ? [`--test-reporter=${process.env.PETTXO_TEST_REPORTER}`] : [];
  const result = spawnSync(process.execPath, ["--test", ...nodeTestArgs, ...extra, ...files], {
    cwd: FUNCTIONS_DIR,
    env: childEnv,
    stdio: "inherit",
  });
  return result.status ?? 1;
}

function main() {
  const [mode, ...rest] = process.argv.slice(2);
  const files = rest.length > 0 ? rest : defaultTestFiles();

  if (mode === "--inside-emulator") {
    // Invoked by `firebase emulators:exec`; the environment was scrubbed by the
    // outer runner and extended with emulator hosts by the Firebase CLI.
    for (const variable of ["FIRESTORE_EMULATOR_HOST", "FIREBASE_STORAGE_EMULATOR_HOST"]) {
      if (!LOOPBACK_HOST_PATTERN.test(process.env[variable] ?? "")) {
        fail(`${variable} is not a loopback emulator address inside emulators:exec`);
      }
    }
    if (process.env.GCLOUD_PROJECT !== EMULATOR_PROJECT_ID) {
      fail(`unexpected GCLOUD_PROJECT inside emulators:exec: ${process.env.GCLOUD_PROJECT}`);
    }
    const env = {...process.env, GOOGLE_CLOUD_PROJECT: EMULATOR_PROJECT_ID};
    delete env.NODE_OPTIONS;
    // Files that load storage.rules into the shared Storage emulator
    // (initializeTestEnvironment) reset its ruleset; while a reload is in
    // progress the emulator denies every request ("no Storage ruleset is
    // currently loaded") and cross-service Firestore lookups can stall. Run
    // those files one at a time after the parallel batch so no Storage Rules
    // reload overlaps another file's Storage requests.
    const storageRulesFiles = files.filter(loadsStorageRules);
    const parallelFiles = files.filter((file) => !storageRulesFiles.includes(file));
    let status = 0;
    if (parallelFiles.length > 0) status = runNodeTests(env, parallelFiles) || status;
    if (storageRulesFiles.length > 0) {
      status = runNodeTests(env, storageRulesFiles, ["--test-concurrency=1"]) || status;
    }
    process.exit(status);
  }

  if (mode !== "unit" && mode !== "emulator") {
    fail("usage: node scripts/run_tests.js <unit|emulator> [test files...]");
  }
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "pettxo-tests-"));
  try {
    if (mode === "unit") {
      process.exitCode = runNodeTests(scrubbedEnvironment(UNIT_PROJECT_ID, scratch), files);
      return;
    }
    const env = scrubbedEnvironment(EMULATOR_PROJECT_ID, scratch);
    const firebaseBinary = spawnSync("sh", ["-c", "command -v firebase"], {env, encoding: "utf8"});
    if (firebaseBinary.status !== 0) fail("firebase CLI not found on PATH");
    const quoted = [process.execPath, __filename, "--inside-emulator", ...files]
      .map((part) => `'${String(part).replace(/'/g, "'\\''")}'`).join(" ");
    const cwd = path.join(scratch, "emulator-cwd");
    fs.mkdirSync(cwd);
    process.stdout.write(`[run_tests] firebase emulators:exec --project ${EMULATOR_PROJECT_ID} --only firestore,storage (logs in ${cwd})\n`);
    const result = spawnSync("firebase", [
      "emulators:exec",
      "--project", EMULATOR_PROJECT_ID,
      "--only", "firestore,storage",
      "--config", path.join(REPO_DIR, "firebase.json"),
      quoted,
    ], {cwd, env, stdio: "inherit"});
    process.exitCode = result.status ?? 1;
  } finally {
    if (!process.env.PETTXO_KEEP_TEST_SCRATCH) fs.rmSync(scratch, {recursive: true, force: true});
  }
}

main();
