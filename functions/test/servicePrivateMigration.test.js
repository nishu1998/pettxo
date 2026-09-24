const test = require("node:test");
const assert = require("node:assert/strict");

const {
  EXPECTED_PROJECT_ID,
  buildMigration,
  encodeGeohash,
  executeMigration,
  parseArgs,
  privateCopyIsComplete,
  terminalServiceSkipReason,
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

test("malformed active service remains invalid without inferred city or state", () => {
  const result = buildMigration("active-malformed", {
    ownerUserId: "provider-1",
    ownerSnapshot: {city: "Pune", state: "Maharashtra"},
    status: "active",
    isActive: true,
    isDeleted: false,
    isVisibleToMarketplace: true,
    location: {
      displayAddress: "Baihar, Madhya Pradesh",
      latitude: 22.0987394,
      longitude: 80.5541251,
      city: "pune",
      state: "",
      country: "IN",
    },
  });
  assert.deepEqual(result, {error: "missing-city-or-state"});
});

test("malformed removed or deleted service is safely skipped only when terminal", () => {
  const malformedLocation = {
    displayAddress: "Balaghat",
    latitude: 21.8249324,
    longitude: 80.1744063,
    city: "pune",
    state: "",
    country: "IN",
  };
  assert.deepEqual(buildMigration("removed-service", {
    ownerUserId: "provider-1",
    status: "removed",
    isActive: false,
    isDeleted: false,
    isVisibleToMarketplace: false,
    location: malformedLocation,
  }), {skip: "removed-service"});
  assert.deepEqual(buildMigration("deleted-service", {
    ownerUserId: "provider-1",
    status: "active",
    isActive: true,
    isDeleted: true,
    isVisibleToMarketplace: true,
    location: malformedLocation,
  }), {skip: "deleted-service"});
  assert.equal(terminalServiceSkipReason({
    status: "removed",
    isActive: true,
    isDeleted: false,
    isVisibleToMarketplace: true,
  }), null);
});

test("valid active legacy service remains a migration candidate", () => {
  const result = buildMigration("active-valid", {
    ownerUserId: "provider-1",
    status: "active",
    isActive: true,
    isDeleted: false,
    isVisibleToMarketplace: true,
    privateNotes: "Ring bell",
    location: {
      displayAddress: "Baihar, Madhya Pradesh",
      latitude: 22.0987394,
      longitude: 80.5541251,
      city: "Baihar",
      state: "Madhya Pradesh",
      country: "IN",
    },
  });
  assert.equal(result.error, undefined);
  assert.equal(result.skip, undefined);
  assert.equal(result.publicLocation.city, "Baihar");
  assert.equal(result.publicLocation.state, "Madhya Pradesh");
});

test("dry-run candidate execution performs no mutation-path Firestore calls", async () => {
  let firestoreTouched = false;
  const result = await executeMigration({
    apply: false,
    db: {collection: () => { firestoreTouched = true; }},
    document: {
      id: "dry-run-service",
      ref: {
        get: async () => { firestoreTouched = true; },
        update: async () => { firestoreTouched = true; },
      },
    },
    migration: {
      privateData: {},
      publicLocation: {},
    },
  });
  assert.equal(result, false);
  assert.equal(firestoreTouched, false);
});

test("apply verifies private copy and uses the source update-time precondition", async () => {
  const migration = buildMigration("apply-service", {
    ownerUserId: "provider-1",
    status: "active",
    isActive: true,
    isDeleted: false,
    isVisibleToMarketplace: true,
    privateNotes: "Gate code",
    location: {
      displayAddress: "Exact address",
      latitude: 19.076,
      longitude: 72.8777,
      city: "Mumbai",
      state: "Maharashtra",
      country: "IN",
    },
  });
  const updateTime = {seconds: 123, nanoseconds: 456};
  let privateGetCount = 0;
  let privateSetOptions;
  let publicUpdatePrecondition;
  const privateRef = {
    get: async () => {
      privateGetCount += 1;
      return privateGetCount === 1 ?
        {exists: false} :
        {exists: true, data: () => migration.privateData};
    },
    set: async (_data, options) => { privateSetOptions = options; },
  };
  const document = {
    id: "apply-service",
    updateTime,
    ref: {
      update: async (_patch, precondition) => { publicUpdatePrecondition = precondition; },
      get: async () => ({data: () => ({location: migration.publicLocation})}),
    },
  };
  const applied = await executeMigration({
    apply: true,
    db: {
      collection: (name) => {
        assert.equal(name, "servicePrivate");
        return {doc: (id) => {
          assert.equal(id, "apply-service");
          return privateRef;
        }};
      },
    },
    document,
    migration,
  });
  assert.equal(applied, true);
  assert.deepEqual(privateSetOptions, {merge: true});
  assert.deepEqual(publicUpdatePrecondition, {lastUpdateTime: updateTime});
});
