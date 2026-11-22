"use strict";

/**
 * Target guard for operator scripts (Phase 3B-4a).
 *
 * Call assertSafeScriptTarget() BEFORE requiring firebase-admin, spawning the
 * Firebase CLI, or making any network call. It decides which Firebase project
 * a script may touch, from flags and environment only, and refuses anything
 * that could reach production.
 *
 * Allowed targets:
 *   1. Emulator: FIRESTORE_EMULATOR_HOST (and any other required emulator
 *      host variables) point at a loopback address, and the project matches
 *      ^demo-[a-z0-9-]+$. The project comes from --project=<id>,
 *      GCLOUD_PROJECT, GOOGLE_CLOUD_PROJECT or FIREBASE_CONFIG, and every
 *      source that is set must agree.
 *   2. Override: --allow-project=<id> for a non-production, non-emulator
 *      project (for example a staging project).
 *
 * pettexo-d9409 is a hard-coded, non-configurable deny. It is compared
 * case-insensitively after trimming against the flags, GCLOUD_PROJECT,
 * GOOGLE_CLOUD_PROJECT, FIREBASE_CONFIG and, through assertAppTarget(), the
 * resolved app projectId.
 *
 * This module must not require firebase-admin or any network module.
 */

const PRODUCTION_PROJECT_ID = "pettexo-d9409";
const DEMO_PROJECT_PATTERN = /^demo-[a-z0-9-]+$/;
const LOOPBACK_HOST_PATTERN = /^(127\.0\.0\.1|localhost|\[::1\]):\d{1,5}$/;

class ScriptTargetError extends Error {
  constructor(message) {
    super(message);
    this.name = "ScriptTargetError";
  }
}

function normalizeProjectId(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function isProductionProject(value) {
  return normalizeProjectId(value) === PRODUCTION_PROJECT_ID;
}

function flagValues(argv, name) {
  const prefix = `--${name}=`;
  const values = [];
  for (let index = 0; index < argv.length; index += 1) {
    const arg = String(argv[index]);
    if (arg.startsWith(prefix)) {
      values.push(arg.slice(prefix.length));
    } else if (arg === `--${name}`) {
      values.push(index + 1 < argv.length ? String(argv[index + 1]) : "");
    }
  }
  return values;
}

function firebaseConfigProjectId(env) {
  const raw = env.FIREBASE_CONFIG;
  if (typeof raw !== "string" || !raw.trim()) return "";
  const text = raw.trim();
  if (!text.startsWith("{")) {
    // FIREBASE_CONFIG may be a file path; the guard does not read files, so
    // refuse rather than let firebase-admin resolve an unknown project.
    throw new ScriptTargetError(
      "FIREBASE_CONFIG points to a file; unset it so the guard can verify the project.",
    );
  }
  try {
    const parsed = JSON.parse(text);
    return typeof parsed.projectId === "string" ? parsed.projectId : "";
  } catch {
    throw new ScriptTargetError("FIREBASE_CONFIG is not valid JSON.");
  }
}

/**
 * @param {object} params
 * @param {string} params.scriptName
 * @param {string[]} [params.argv] arguments after the script path
 * @param {Record<string, string | undefined>} [params.env]
 * @param {string[]} [params.requiredEmulatorHosts] env var names that must be
 *   loopback in emulator mode (FIRESTORE_EMULATOR_HOST is always required)
 * @returns {{projectId: string, mode: "emulator" | "allowed-project"}}
 */
function assertSafeScriptTarget(params) {
  const scriptName = params.scriptName || "script";
  const argv = params.argv || process.argv.slice(2);
  const env = params.env || process.env;
  const refuse = (reason) => {
    throw new ScriptTargetError(`${scriptName}: refusing to run: ${reason}`);
  };

  const projectFlags = flagValues(argv, "project");
  const allowFlags = flagValues(argv, "allow-project");
  const envProjects = {
    GCLOUD_PROJECT: env.GCLOUD_PROJECT,
    GOOGLE_CLOUD_PROJECT: env.GOOGLE_CLOUD_PROJECT,
    FIREBASE_CONFIG: firebaseConfigProjectId(env),
  };

  // Hard deny first: production may not appear anywhere.
  for (const value of [...projectFlags, ...allowFlags]) {
    if (isProductionProject(value)) {
      refuse(`${PRODUCTION_PROJECT_ID} can never be targeted by this script.`);
    }
  }
  for (const [name, value] of Object.entries(envProjects)) {
    if (isProductionProject(value)) {
      refuse(`${name} is ${PRODUCTION_PROJECT_ID}; this script can never target production.`);
    }
  }

  if (allowFlags.length > 1) refuse("--allow-project may be given only once.");
  if (projectFlags.length > 1) refuse("--project may be given only once.");

  const candidates = [
    ...projectFlags.map((value) => ["--project", value]),
    ...allowFlags.map((value) => ["--allow-project", value]),
    ...Object.entries(envProjects).filter(([, value]) => normalizeProjectId(value)),
  ];
  const distinct = new Set(candidates.map(([, value]) => normalizeProjectId(value)));
  if (candidates.some(([, value]) => !normalizeProjectId(value))) {
    refuse("an empty project value was given.");
  }
  if (distinct.size > 1) {
    refuse(`project sources disagree (${candidates.map(([name, value]) => `${name}=${String(value).trim()}`).join(", ")}).`);
  }
  const projectId = distinct.size === 1 ? [...distinct][0] : "";

  if (allowFlags.length === 1) {
    if (!projectId) refuse("--allow-project needs a project ID.");
    if (DEMO_PROJECT_PATTERN.test(projectId)) {
      refuse("demo-* projects must use emulator mode, not --allow-project.");
    }
    return {projectId, mode: "allowed-project"};
  }

  const requiredHosts = new Set([
    "FIRESTORE_EMULATOR_HOST",
    ...(params.requiredEmulatorHosts || []),
  ]);
  for (const name of requiredHosts) {
    const host = typeof env[name] === "string" ? env[name].trim() : "";
    if (!host) {
      refuse(`${name} is not set. Run against a local emulator with a demo-* project, or pass --allow-project=<non-production project>.`);
    }
    if (!LOOPBACK_HOST_PATTERN.test(host)) {
      refuse(`${name}=${host} is not a loopback emulator address.`);
    }
  }
  if (!projectId) {
    refuse("no project given. Pass --project=demo-<name> (emulator mode).");
  }
  if (!DEMO_PROJECT_PATTERN.test(projectId)) {
    refuse(`emulator mode requires a demo-* project, got ${projectId}.`);
  }
  return {projectId, mode: "emulator"};
}

/**
 * Second check, after initializeApp(): the resolved app project must be the
 * guarded target and never production.
 * @param {{options?: {projectId?: string}}} app
 * @param {{projectId: string}} target
 */
function assertAppTarget(app, target) {
  const resolved = normalizeProjectId(app && app.options && app.options.projectId);
  if (!resolved || isProductionProject(resolved) || resolved !== normalizeProjectId(target.projectId)) {
    throw new ScriptTargetError(
      `refusing to continue: initialized app project (${resolved || "unknown"}) does not match the guarded target (${target.projectId}).`,
    );
  }
}

module.exports = {
  PRODUCTION_PROJECT_ID,
  ScriptTargetError,
  assertAppTarget,
  assertSafeScriptTarget,
};
