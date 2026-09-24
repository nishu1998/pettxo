const test = require("node:test");
const assert = require("node:assert/strict");

const {
  EXPECTED_PROJECT_ID,
  buildMigration,
  encodeGeohash,
  parseArgs,
  privateCopyIsComplete,
  validateSafetyOptions,
} = require("../scripts/migrate_service_private_data.js");

test("service private migration defaults to dry-run and validates paging", () => {
  assert.deepEqual(parseArgs(["--project", EXPECTED_PROJECT_ID]), {
    apply: false,
    pageSize: 100,
    projectId: EXPECTED_PROJECT_ID,
    checkpoint: "",
    applyConfirmation: "",
  });
  assert.throws(() => parseArgs(["--page-size", "0"]));
});

test("service private migration is pinned to production and apply requires explicit confirmation", () => {
  assert.throws(
    () => validateSafetyOptions(parseArgs(["--project", "wrong-project"])),
    /must be exactly pettexo-d9409/,
  );
  assert.throws(
    () => validateSafetyOptions(parseArgs(["--project", EXPECTED_PROJECT_ID, "--apply"])),
    /requires --confirm-apply pettexo-d9409/,
  );
  assert.doesNotThrow(() => validateSafetyOptions(parseArgs([
    "--project", EXPECTED_PROJECT_ID,
    "--apply",
    "--confirm-apply", EXPECTED_PROJECT_ID,
  ])));
});

test("service private migration separates exact and public location", () => {
  const result = buildMigration("service-1", {
    ownerUserId: "provider-1",
    privateNotes: "Gate code 1234",
    location: {
      displayAddress: "Exact address",
      latitude: 19.076,
      longitude: 72.8777,
      city: "Mumbai",
      state: "Maharashtra",
    },
  });
  assert.equal(result.privateData.privateNotes, "Gate code 1234");
  assert.equal(result.privateData.location.displayAddress, "Exact address");
  assert.deepEqual(result.publicLocation, {
    approximateLatitude: 19.08,
    approximateLongitude: 72.88,
    geohash: encodeGeohash(19.08, 72.88),
    city: "Mumbai",
    state: "Maharashtra",
    country: "IN",
  });
  assert.equal(Object.hasOwn(result.publicLocation, "displayAddress"), false);
  assert.equal(Object.hasOwn(result.publicLocation, "latitude"), false);
});

test("service private migration is idempotent for sanitized documents", () => {
  assert.equal(buildMigration("service-2", {
    location: {
      approximateLatitude: 19.08,
      approximateLongitude: 72.88,
      geohash: "te7ud",
      city: "Mumbai",
      state: "Maharashtra",
      country: "IN",
    },
  }), null);
});

test("service private migration rejects null or non-numeric exact coordinates", () => {
  for (const [latitude, longitude] of [[null, 72.8777], [19.076, null], ["19.076", 72.8777]]) {
    assert.deepEqual(buildMigration("invalid-service", {
      ownerUserId: "provider-1",
      location: {latitude, longitude, city: "Mumbai", state: "Maharashtra"},
    }), {error: "missing-or-invalid-exact-coordinates"});
  }
});

test("service private migration validates a complete private copy for sanitized services", () => {
  const publicData = {ownerUserId: "provider-1"};
  const privateData = {
    serviceId: "service-1",
    ownerUserId: "provider-1",
    privateNotes: "Gate code",
    location: {displayAddress: "Exact address", latitude: 19.076, longitude: 72.8777},
  };
  assert.equal(privateCopyIsComplete("service-1", publicData, privateData), true);
  assert.equal(privateCopyIsComplete("service-1", publicData, {...privateData, location: null}), false);
  assert.equal(privateCopyIsComplete("service-1", publicData, {...privateData, serviceId: "other"}), false);
});
