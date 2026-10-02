const test = require("node:test");
const assert = require("node:assert/strict");

const {
  EXPECTED_PROJECT_ID,
  MIGRATION_SOURCE,
  classifyPreference,
  executeInitialization,
  migrationPatch,
  parseArgs,
  validateSafetyOptions,
} = require("../scripts/initialize_preproduction_marketing_preferences.js");

test("pre-production preference migration defaults to dry-run and requires exact apply confirmation", () => {
  assert.deepEqual(parseArgs(["--project", EXPECTED_PROJECT_ID]), {
    apply: false,
    pageSize: 100,
    projectId: EXPECTED_PROJECT_ID,
    checkpoint: "",
    applyConfirmation: "",
  });
  assert.throws(() => validateSafetyOptions(parseArgs(["--project", "wrong"])), /must be exactly/);
  assert.throws(
    () => validateSafetyOptions(parseArgs(["--project", EXPECTED_PROJECT_ID, "--apply"])),
    /requires --confirm-apply/,
  );
  assert.doesNotThrow(() => validateSafetyOptions(parseArgs([
    "--project", EXPECTED_PROJECT_ID,
    "--apply",
    "--confirm-apply", EXPECTED_PROJECT_ID,
  ])));
});

test("migration distinguishes missing, enabled, disabled, and mismatched private records", () => {
  assert.deepEqual(classifyPreference("u1", false, {}), {kind: "candidate"});
  assert.deepEqual(classifyPreference("u1", true, {uid: "u1"}), {kind: "candidate"});
  assert.deepEqual(classifyPreference("u1", true, {uid: "u1", marketingEmailEnabled: true}), {kind: "alreadyEnabled"});
  assert.deepEqual(classifyPreference("u1", true, {uid: "u1", marketingEmailEnabled: false}), {
    kind: "error",
    reason: "explicit-disabled-preference-requires-review",
  });
  assert.deepEqual(classifyPreference("u1", true, {uid: "other"}), {
    kind: "error",
    reason: "private-profile-uid-mismatch",
  });
});

test("migration patch is narrow and identifies pre-production initialization", () => {
  const timestamp = {server: true};
  assert.deepEqual(migrationPatch("u1", timestamp), {
    uid: "u1",
    marketingEmailEnabled: true,
    marketingEmailPreferenceSource: MIGRATION_SOURCE,
    marketingEmailPreferenceUpdatedAt: timestamp,
    updatedAt: timestamp,
  });
  assert.equal(MIGRATION_SOURCE, "preproduction_test_migration");
});

test("migration dry-run executes no write path", async () => {
  let touched = false;
  const changed = await executeInitialization({
    apply: false,
    uid: "u1",
    timestamp: {},
    privateSnapshot: {
      ref: {
        create: async () => { touched = true; },
        update: async () => { touched = true; },
        get: async () => { touched = true; },
      },
    },
  });
  assert.equal(changed, false);
  assert.equal(touched, false);
});

test("migration APPLY uses an update-time precondition and preserves unrelated fields", async () => {
  const timestamp = {server: true};
  const existing = {uid: "u1", unrelated: "preserved"};
  let updatePatch;
  let updatePrecondition;
  const ref = {
    update: async (patch, precondition) => {
      updatePatch = patch;
      updatePrecondition = precondition;
      Object.assign(existing, patch);
    },
    get: async () => ({exists: true, data: () => existing}),
  };
  const changed = await executeInitialization({
    apply: true,
    uid: "u1",
    timestamp,
    privateSnapshot: {exists: true, updateTime: "version-1", ref},
  });
  assert.equal(changed, true);
  assert.deepEqual(updatePrecondition, {lastUpdateTime: "version-1"});
  assert.equal(updatePatch.unrelated, undefined);
  assert.equal(existing.unrelated, "preserved");
  assert.equal(existing.marketingEmailPreferenceSource, "preproduction_test_migration");
});
