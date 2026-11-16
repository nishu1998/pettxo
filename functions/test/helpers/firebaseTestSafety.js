"use strict";

/**
 * Shared production-isolation guard for every backend test that initialises
 * firebase-admin, @firebase/rules-unit-testing, or a Firebase client SDK, or
 * that loads lib/shared/firebase.js directly or transitively.
 *
 * Two entry points:
 *   - emulatorGate({projectId, services}) for tests that need emulators.
 *     Returns {enabled, skip}. When none of the required emulator variables
 *     are set the test skips; when some are set but unsafe it throws, failing
 *     the file before any Firebase client is created.
 *   - assertUnitTestIsolation() for unit tests whose imports create the
 *     default Admin app. It pins a demo-* project and refuses ambient
 *     credentials, so an unstubbed call can never authenticate to production.
 *
 * Safety basis: a demo-* project ID is never a real Google Cloud project, the
 * emulators refuse real credentials for it, and every emulator host must be a
 * loopback address.
 */

const fs = require("node:fs");
const path = require("node:path");

const DEMO_PROJECT_PATTERN = /^demo-[a-z0-9-]+$/;
const LOOPBACK_HOST_PATTERN = /^(127\.0\.0\.1|localhost|\[::1\]):\d+$/;
const DEFAULT_UNIT_PROJECT_ID = "demo-pettxo-unit";
const EMULATOR_HOST_VARIABLES = Object.freeze({
  firestore: "FIRESTORE_EMULATOR_HOST",
  auth: "FIREBASE_AUTH_EMULATOR_HOST",
  storage: "FIREBASE_STORAGE_EMULATOR_HOST",
});
const PROJECT_VARIABLES = ["GCLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT"];

class FirebaseTestSafetyError extends Error {
  constructor(message) {
    super(`[firebase-test-safety] ${message}`);
    this.name = "FirebaseTestSafetyError";
  }
}

function wellKnownAdcPath(env) {
  const home = env.HOME || "";
  return home ? path.join(home, ".config", "gcloud", "application_default_credentials.json") : "";
}

/** Lists reasons ambient Google credentials could be discovered. Never reads file contents. */
function credentialProblems(env = process.env) {
  const problems = [];
  for (const name of ["GOOGLE_APPLICATION_CREDENTIALS", "google_application_credentials"]) {
    if (env[name]) problems.push(`${name} is set`);
  }
  const adc = wellKnownAdcPath(env);
  if (adc && fs.existsSync(adc)) {
    problems.push(`application default credentials exist under HOME (${adc})`);
  }
  if (env.CLOUDSDK_CONFIG) {
    const sdkAdc = path.join(env.CLOUDSDK_CONFIG, "application_default_credentials.json");
    if (fs.existsSync(sdkAdc)) problems.push(`application default credentials exist under CLOUDSDK_CONFIG (${sdkAdc})`);
  }
  return problems;
}

function assertNoProductionCredentials(env = process.env) {
  const problems = credentialProblems(env);
  if (problems.length > 0) {
    throw new FirebaseTestSafetyError(
      `refusing to run with reachable Google credentials: ${problems.join("; ")}. ` +
      "Run tests through `npm test` or `npm run test:emulator`, which scrub the environment.",
    );
  }
}

function assertLoopbackEmulatorHosts(env = process.env) {
  for (const variable of Object.values(EMULATOR_HOST_VARIABLES)) {
    const value = env[variable];
    if (value !== undefined && value !== "" && !LOOPBACK_HOST_PATTERN.test(value)) {
      throw new FirebaseTestSafetyError(`${variable}=${value} is not a loopback emulator address`);
    }
  }
}

function assertDemoProjectEnvironment(env = process.env) {
  for (const variable of PROJECT_VARIABLES) {
    const value = env[variable];
    if (value !== undefined && value !== "" && !DEMO_PROJECT_PATTERN.test(value)) {
      throw new FirebaseTestSafetyError(`${variable}=${value} is not a demo-* project ID`);
    }
  }
}

/**
 * Unit-test guard for files whose imports create the default Admin app.
 * Must be called before the first require of ../lib/**.
 */
function assertUnitTestIsolation(env = process.env) {
  assertNoProductionCredentials(env);
  assertLoopbackEmulatorHosts(env);
  assertDemoProjectEnvironment(env);
  for (const variable of PROJECT_VARIABLES) {
    if (!env[variable]) env[variable] = DEFAULT_UNIT_PROJECT_ID;
  }
  return {projectId: env.GCLOUD_PROJECT};
}

/**
 * Emulator-test guard. `projectId` is the explicit project the test passes to
 * initializeApp/initializeTestEnvironment; omit it only when the test relies on
 * the default app, whose project comes from GCLOUD_PROJECT.
 */
function emulatorGate(options = {}, env = process.env) {
  const services = options.services ?? ["firestore"];
  const unknown = services.filter((service) => !EMULATOR_HOST_VARIABLES[service]);
  if (unknown.length > 0) throw new FirebaseTestSafetyError(`unknown emulator services: ${unknown.join(", ")}`);
  const variables = services.map((service) => EMULATOR_HOST_VARIABLES[service]);
  const present = variables.filter((variable) => env[variable]);
  if (present.length === 0) {
    // Emulator files often also contain unit tests; isolate those the same way.
    assertUnitTestIsolation(env);
    return {
      enabled: false,
      skip: `requires the Firebase emulators (${variables.join(", ")}); run \`npm run test:emulator\``,
      projectId: options.projectId ?? null,
    };
  }
  const missing = variables.filter((variable) => !env[variable]);
  if (missing.length > 0) {
    throw new FirebaseTestSafetyError(
      `partial emulator environment: ${missing.join(", ")} missing. A client without an emulator host would target Google production endpoints.`,
    );
  }
  assertLoopbackEmulatorHosts(env);
  assertNoProductionCredentials(env);
  assertDemoProjectEnvironment(env);
  const projectId = options.projectId ?? env.GCLOUD_PROJECT ?? env.GOOGLE_CLOUD_PROJECT ?? "";
  if (!DEMO_PROJECT_PATTERN.test(projectId)) {
    throw new FirebaseTestSafetyError(`emulator tests require a demo-* project ID (got ${projectId || "none"})`);
  }
  return {enabled: true, skip: false, projectId};
}

/** Preflight for every process started by scripts/run_tests.js (NODE_OPTIONS --require). */
function assertTestProcessPreflight(env = process.env) {
  assertNoProductionCredentials(env);
  assertLoopbackEmulatorHosts(env);
  assertDemoProjectEnvironment(env);
  for (const variable of PROJECT_VARIABLES) {
    if (!env[variable]) {
      throw new FirebaseTestSafetyError(`${variable} must be set to a demo-* project by the test runner`);
    }
  }
}

module.exports = {
  DEFAULT_UNIT_PROJECT_ID,
  DEMO_PROJECT_PATTERN,
  EMULATOR_HOST_VARIABLES,
  FirebaseTestSafetyError,
  LOOPBACK_HOST_PATTERN,
  assertDemoProjectEnvironment,
  assertLoopbackEmulatorHosts,
  assertNoProductionCredentials,
  assertTestProcessPreflight,
  assertUnitTestIsolation,
  credentialProblems,
  emulatorGate,
  wellKnownAdcPath,
};
