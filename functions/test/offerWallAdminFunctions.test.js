const test = require("node:test");
const assert = require("node:assert/strict");

const sharedFirebase = require("../lib/shared/firebase.js");
const {
  createOfferWallCampaignDocument,
  listOfferWallCampaignDocuments,
  setOfferWallCampaignStatusDocument,
  updateOfferWallCampaignDocument,
} = require("../lib/offerWall/application/offerWallAdminApplication.js");
const {
  sanitizeOfferWallMutationInput,
} = require("../lib/offerWall/application/offerWallAdminContract.js");
const {HttpsError} = require("firebase-functions/v2/https");

class FakeDocSnapshot {
  constructor(ref, data) {
    this.ref = ref;
    this.id = ref.id;
    this._data = data;
  }

  get exists() {
    return this._data !== undefined;
  }

  data() {
    return this._data;
  }
}

class FakeDocRef {
  constructor(firestore, path) {
    this.firestore = firestore;
    this.path = path;
    this.id = path.split("/").pop();
  }

  async get() {
    return new FakeDocSnapshot(this, this.firestore.store.get(this.path));
  }

  async set(data, options) {
    this.firestore._set(this.path, data, options);
  }
}

class FakeQuerySnapshot {
  constructor(docs) {
    this.docs = docs;
  }
}

class FakeCollectionRef {
  constructor(firestore, path) {
    this.firestore = firestore;
    this.path = path;
    this.id = path.split("/").pop();
  }

  doc(id) {
    const resolvedId = id ?? `${this.id}_${++this.firestore.autoId}`;
    return new FakeDocRef(this.firestore, `${this.path}/${resolvedId}`);
  }

  async get() {
    const prefix = `${this.path}/`;
    const docs = [];
    for (const [path, data] of this.firestore.store.entries()) {
      if (!path.startsWith(prefix)) continue;
      const remaining = path.slice(prefix.length);
      if (remaining.includes("/")) continue;
      docs.push(new FakeDocSnapshot(new FakeDocRef(this.firestore, path), data));
    }
    return new FakeQuerySnapshot(docs);
  }
}

class FakeFirestore {
  constructor(seed = {}) {
    this.store = new Map(Object.entries(seed));
    this.autoId = 0;
  }

  collection(path) {
    return new FakeCollectionRef(this, path);
  }

  _clone(value) {
    if (value == null) return value;
    if (value instanceof Date) return new Date(value.getTime());
    if (Array.isArray(value)) return value.map((entry) => this._clone(entry));
    if (typeof value === "object") {
      const prototype = Object.getPrototypeOf(value);
      if (prototype !== Object.prototype && prototype !== null) {
        return value;
      }
      const copy = {};
      for (const [key, entry] of Object.entries(value)) {
        copy[key] = this._clone(entry);
      }
      return copy;
    }
    return value;
  }

  _resolveValue(existingValue, incomingValue) {
    if (Array.isArray(incomingValue)) {
      return incomingValue.map((entry) => this._clone(entry));
    }
    if (incomingValue instanceof Date || incomingValue == null) {
      return incomingValue;
    }
    const ctorName = incomingValue?.constructor?.name;
    if (ctorName === "ServerTimestampTransform") {
      return new Date("2026-08-13T00:00:00.000Z");
    }
    if (typeof incomingValue === "object") {
      const prototype = Object.getPrototypeOf(incomingValue);
      if (prototype !== Object.prototype && prototype !== null) {
        return incomingValue;
      }
      const base = typeof existingValue === "object" && existingValue != null ?
        existingValue :
        {};
      const nested = {};
      for (const [key, value] of Object.entries(incomingValue)) {
        nested[key] = this._resolveValue(base[key], value);
      }
      return nested;
    }
    return incomingValue;
  }

  _set(path, data, options = {}) {
    const existing = this.store.get(path);
    const base = options.merge ? this._clone(existing) ?? {} : {};
    const next = {...base};
    for (const [key, value] of Object.entries(data)) {
      next[key] = this._resolveValue(existing?.[key], value);
    }
    this.store.set(path, next);
  }
}

async function withFakeFirestore(seed, fn) {
  const firestore = new FakeFirestore(seed);
  const originalCollection = sharedFirebase.db.collection;

  sharedFirebase.db.collection = firestore.collection.bind(firestore);

  try {
    await fn(firestore);
  } finally {
    sharedFirebase.db.collection = originalCollection;
  }
}

function baseOfferWallCampaign(overrides = {}) {
  return {
    id: "campaign_1",
    name: "Welcome",
    creativeStoragePath: "",
    creativeDownloadUrl: "",
    audiences: ["allUsers"],
    openInterval: 2,
    repetitionLimit: 4,
    status: "draft",
    createdAt: new Date("2026-08-13T00:00:00.000Z"),
    updatedAt: new Date("2026-08-13T00:00:00.000Z"),
    createdBy: "admin_1",
    createdByRole: "financeAdmin",
    updatedBy: "admin_1",
    updatedByRole: "financeAdmin",
    ...overrides,
  };
}

const adminActor = {uid: "admin_1", role: "financeAdmin"};

test("update input accepts creativeStoragePath as the canonical creative field", () => {
  const result = sanitizeOfferWallMutationInput({
    rawData: {
      campaignId: "campaign_1",
      name: "Welcome",
      audiences: ["allUsers"],
      openInterval: 2,
      repetitionLimit: 4,
      creativeStoragePath: "offerWalls/campaign_1/image.png",
    },
    requireCampaignId: true,
  });

  assert.equal(result.campaignId, "campaign_1");
  assert.equal(
    result.payload.creativeStoragePath,
    "offerWalls/campaign_1/image.png",
  );
});

test("updating a campaign persists creativeStoragePath", async () => {
  await withFakeFirestore({
    "offerWallCampaigns/campaign_1": baseOfferWallCampaign(),
  }, async (firestore) => {
    await updateOfferWallCampaignDocument({
      campaignId: "campaign_1",
      payload: {
        name: "Welcome",
        audiences: ["allUsers"],
        openInterval: 2,
        repetitionLimit: 4,
        creativeStoragePath: "offerWalls/campaign_1/image.png",
      },
      actor: adminActor,
    });

    const stored = firestore.store.get("offerWallCampaigns/campaign_1");
    assert.equal(
      stored.creativeStoragePath,
      "offerWalls/campaign_1/image.png",
    );
  });
});

test("editing unrelated fields preserves an existing creativeStoragePath", async () => {
  await withFakeFirestore({
    "offerWallCampaigns/campaign_1": baseOfferWallCampaign({
      creativeStoragePath: "offerWalls/campaign_1/image.png",
    }),
  }, async (firestore) => {
    await updateOfferWallCampaignDocument({
      campaignId: "campaign_1",
      payload: {
        name: "Welcome Back",
        openInterval: 5,
      },
      actor: adminActor,
    });

    const stored = firestore.store.get("offerWallCampaigns/campaign_1");
    assert.equal(stored.name, "Welcome Back");
    assert.equal(stored.openInterval, 5);
    assert.equal(
      stored.creativeStoragePath,
      "offerWalls/campaign_1/image.png",
    );
  });
});

test("campaign with creativeStoragePath activates successfully", async () => {
  await withFakeFirestore({
    "offerWallCampaigns/campaign_1": baseOfferWallCampaign({
      creativeStoragePath: "offerWalls/campaign_1/image.png",
    }),
  }, async (firestore) => {
    await setOfferWallCampaignStatusDocument({
      campaignId: "campaign_1",
      status: "active",
      actor: adminActor,
    });

    const stored = firestore.store.get("offerWallCampaigns/campaign_1");
    assert.equal(stored.status, "active");
    assert.equal(
      stored.creativeStoragePath,
      "offerWalls/campaign_1/image.png",
    );
  });
});

test("campaign without a creative fails activation with failed-precondition", async () => {
  await withFakeFirestore({
    "offerWallCampaigns/campaign_1": baseOfferWallCampaign(),
  }, async () => {
    await assert.rejects(
      () => setOfferWallCampaignStatusDocument({
        campaignId: "campaign_1",
        status: "active",
        actor: adminActor,
      }),
      (error) => {
        assert.ok(error instanceof HttpsError);
        assert.equal(error.code, "failed-precondition");
        assert.equal(
          error.message,
          "Offer Wall creative is required before activation.",
        );
        return true;
      },
    );
  });
});

test("list responses include the persisted creativeStoragePath", async () => {
  await withFakeFirestore({
    "offerWallCampaigns/campaign_1": baseOfferWallCampaign({
      creativeStoragePath: "offerWalls/campaign_1/image.png",
    }),
  }, async () => {
    const campaigns = await listOfferWallCampaignDocuments();
    assert.equal(campaigns.length, 1);
    assert.equal(
      campaigns[0].creativeStoragePath,
      "offerWalls/campaign_1/image.png",
    );
  });
});

test("creating a draft campaign persists creativeStoragePath when supplied", async () => {
  await withFakeFirestore({}, async (firestore) => {
    const result = await createOfferWallCampaignDocument({
      payload: {
        name: "Welcome",
        audiences: ["allUsers"],
        openInterval: 2,
        repetitionLimit: 4,
        status: "draft",
        creativeStoragePath: "offerWalls/generated/image.png",
      },
      actor: adminActor,
    });

    const stored = firestore.store.get(`offerWallCampaigns/${result.campaignId}`);
    assert.equal(
      stored.creativeStoragePath,
      "offerWalls/generated/image.png",
    );
  });
});
