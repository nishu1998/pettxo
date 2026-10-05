const test = require("node:test");
const assert = require("node:assert/strict");

const sharedFirebase = require("../lib/shared/firebase.js");
const {
  acknowledgeOfferWallImpression,
  evaluateOfferWallForLaunch,
} = require("../lib/offerWall/application/evaluateOfferWallForLaunch.js");
const {
  matchesOfferWallAudience,
  offerWallAudienceValues,
  offerWallUserRoleValues,
} = require("../lib/offerWall/domain/offerWallAudience.js");

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

  collection(name) {
    return new FakeCollectionRef(this.firestore, `${this.path}/${name}`);
  }

  async get() {
    return new FakeDocSnapshot(this, this.firestore.store.get(this.path));
  }
}

class FakeQuerySnapshot {
  constructor(docs) {
    this.docs = docs;
  }
}

class FakeQuery {
  constructor(firestore, path, filters) {
    this.firestore = firestore;
    this.path = path;
    this.filters = filters;
  }

  where(field, operator, value) {
    assert.equal(operator, "==");
    return new FakeQuery(
      this.firestore,
      this.path,
      [...this.filters, {field, value}],
    );
  }

  async get() {
    const prefix = `${this.path}/`;
    const docs = [];
    for (const [path, data] of this.firestore.store.entries()) {
      if (!path.startsWith(prefix)) continue;
      const remaining = path.slice(prefix.length);
      if (remaining.includes("/")) continue;
      if (!this.filters.every(({field, value}) => data?.[field] === value)) {
        continue;
      }
      docs.push(new FakeDocSnapshot(new FakeDocRef(this.firestore, path), data));
    }
    return new FakeQuerySnapshot(docs);
  }
}

class FakeCollectionRef extends FakeQuery {
  constructor(firestore, path) {
    super(firestore, path, []);
    this.id = path.split("/").pop();
  }

  doc(id) {
    return new FakeDocRef(this.firestore, `${this.path}/${id}`);
  }
}

class StrictTransaction {
  constructor(firestore) {
    this.firestore = firestore;
    this.hasWrites = false;
    this.writes = [];
  }

  _assertReadable() {
    if (this.hasWrites) {
      throw new Error("Firestore transaction read attempted after a write.");
    }
  }

  async get(ref) {
    this._assertReadable();
    return new FakeDocSnapshot(ref, this.firestore._clone(
      this.firestore.store.get(ref.path),
    ));
  }

  async getAll(...refs) {
    this._assertReadable();
    this.firestore.getAllCalls += 1;
    return refs.map((ref) => new FakeDocSnapshot(
      ref,
      this.firestore._clone(this.firestore.store.get(ref.path)),
    ));
  }

  set(ref, data, options = {}) {
    this.hasWrites = true;
    this.writes.push({ref, data, options});
  }

  commit() {
    for (const {ref, data, options} of this.writes) {
      this.firestore._set(ref.path, data, options);
      this.firestore.writePaths.push(ref.path);
    }
  }
}

class StrictFirestore {
  constructor(seed) {
    this.store = new Map(Object.entries(seed));
    this.getAllCalls = 0;
    this.writePaths = [];
    this.transactionQueue = Promise.resolve();
  }

  collection(path) {
    return new FakeCollectionRef(this, path);
  }

  runTransaction(handler) {
    const run = async () => {
      const transaction = new StrictTransaction(this);
      const result = await handler(transaction);
      transaction.commit();
      return result;
    };
    const result = this.transactionQueue.then(run, run);
    this.transactionQueue = result.then(() => undefined, () => undefined);
    return result;
  }

  _clone(value) {
    if (value == null) return value;
    if (value instanceof Date) return new Date(value.getTime());
    if (Array.isArray(value)) return value.map((entry) => this._clone(entry));
    if (typeof value === "object") {
      const prototype = Object.getPrototypeOf(value);
      if (prototype !== Object.prototype && prototype !== null) return value;
      return Object.fromEntries(
        Object.entries(value).map(([key, entry]) => [key, this._clone(entry)]),
      );
    }
    return value;
  }

  _resolveValue(value) {
    if (value?.constructor?.name === "ServerTimestampTransform") {
      return new Date("2026-10-05T00:00:00.000Z");
    }
    return this._clone(value);
  }

  _set(path, data, options) {
    const existing = this.store.get(path);
    const next = options.merge ? this._clone(existing) ?? {} : {};
    for (const [key, value] of Object.entries(data)) {
      next[key] = this._resolveValue(value);
    }
    this.store.set(path, next);
  }
}

const uid = "offer_wall_user";

function user(role = "petParent") {
  return {
    uid,
    role,
    displayName: "Offer Wall User",
    username: "offer_wall_user",
    state: "Delhi",
    city: "New Delhi",
  };
}

function campaign(id, audiences, overrides = {}) {
  return {
    id,
    name: `Campaign ${id}`,
    creativeStoragePath: `offerWalls/${id}/creative.webp`,
    creativeDownloadUrl: "",
    audiences,
    openInterval: 1,
    repetitionLimit: 3,
    status: "active",
    createdAt: new Date(`2026-09-${id === "a" ? "01" : "02"}T00:00:00.000Z`),
    updatedAt: new Date("2026-09-03T00:00:00.000Z"),
    createdBy: "admin",
    createdByRole: "financeAdmin",
    updatedBy: "admin",
    updatedByRole: "financeAdmin",
    ...overrides,
  };
}

function state(id, overrides = {}) {
  return {
    campaignId: id,
    uid,
    eligibleOpenCount: 0,
    impressionsShown: 0,
    lastCountedSessionId: "",
    pendingDisplayToken: "",
    pendingSessionId: "",
    ...overrides,
  };
}

async function withFirestore(seed, callback) {
  const firestore = new StrictFirestore({
    [`users/${uid}`]: user(),
    [`userPrivate/${uid}`]: {},
    ...seed,
  });
  const originalCollection = sharedFirebase.db.collection;
  const originalRunTransaction = sharedFirebase.db.runTransaction;
  sharedFirebase.db.collection = firestore.collection.bind(firestore);
  sharedFirebase.db.runTransaction = firestore.runTransaction.bind(firestore);
  try {
    await callback(firestore);
  } finally {
    sharedFirebase.db.collection = originalCollection;
    sharedFirebase.db.runTransaction = originalRunTransaction;
  }
}

function evaluate(sessionId, randomValue = 0) {
  return evaluateOfferWallForLaunch({
    uid,
    sessionId,
    randomSource: () => randomValue,
  });
}

test("allUsers campaign launches for a pet parent", async () => {
  await withFirestore({"offerWallCampaigns/a": campaign("a", ["allUsers"])}, async () => {
    assert.equal((await evaluate("session_all_only")).campaignId, "a");
  });
});

test("matching canonical role campaign launches", async () => {
  await withFirestore({"offerWallCampaigns/a": campaign("a", ["petParent"])}, async () => {
    assert.equal((await evaluate("session_role_only")).campaignId, "a");
  });
});

test("wrong role returns no campaign", async () => {
  await withFirestore({
    "offerWallCampaigns/a": campaign("a", ["serviceProvider"]),
  }, async () => {
    assert.equal(await evaluate("session_wrong_role"), null);
  });
});

test("allUsers plus matching role bulk-reads state and returns one candidate", async () => {
  await withFirestore({
    "offerWallCampaigns/a": campaign("a", ["allUsers"]),
    "offerWallCampaigns/b": campaign("b", ["petParent"]),
  }, async (firestore) => {
    const selected = await evaluate("session_two_match", 0.75);
    assert.equal(selected.campaignId, "b");
    assert.equal(firestore.getAllCalls, 1);
  });
});

test("nonmatching campaign is excluded before random selection", async () => {
  await withFirestore({
    "offerWallCampaigns/a": campaign("a", ["allUsers"]),
    "offerWallCampaigns/b": campaign("b", ["serviceProvider"]),
  }, async () => {
    assert.equal((await evaluate("session_nonmatch", 0.999)).campaignId, "a");
  });
});

test("three matching campaigns return one launch-eligible campaign", async () => {
  await withFirestore({
    "offerWallCampaigns/a": campaign("a", ["allUsers"]),
    "offerWallCampaigns/b": campaign("b", ["petParent"]),
    "offerWallCampaigns/c": campaign("c", ["petLover", "petParent"]),
  }, async () => {
    assert.equal((await evaluate("session_three_match", 0.9)).campaignId, "c");
  });
});

test("repetition-exhausted campaign is excluded before selection", async () => {
  await withFirestore({
    "offerWallCampaigns/a": campaign("a", ["allUsers"], {repetitionLimit: 1}),
    "offerWallCampaigns/b": campaign("b", ["petParent"]),
    [`userPrivate/${uid}/offerWallState/a`]: state("a", {impressionsShown: 1}),
  }, async () => {
    assert.equal((await evaluate("session_repetition", 0)).campaignId, "b");
  });
});

test("open-interval-ineligible campaign is excluded before selection", async () => {
  await withFirestore({
    "offerWallCampaigns/a": campaign("a", ["allUsers"], {openInterval: 2}),
    "offerWallCampaigns/b": campaign("b", ["petParent"]),
  }, async () => {
    assert.equal((await evaluate("session_interval", 0)).campaignId, "b");
  });
});

test("all frequency-ineligible candidates return null without ordering errors", async () => {
  await withFirestore({
    "offerWallCampaigns/a": campaign("a", ["allUsers"], {openInterval: 2}),
    "offerWallCampaigns/b": campaign("b", ["petParent"], {openInterval: 3}),
  }, async (firestore) => {
    assert.equal(await evaluate("session_none_due"), null);
    assert.equal(firestore.getAllCalls, 1);
  });
});

test("missing state documents preserve first-launch behavior", async () => {
  await withFirestore({
    "offerWallCampaigns/a": campaign("a", ["allUsers"]),
    "offerWallCampaigns/b": campaign("b", ["petParent"]),
  }, async (firestore) => {
    assert.equal((await evaluate("session_no_state", 0)).campaignId, "a");
    assert.equal(
      firestore.store.get(`userPrivate/${uid}/offerWallState/a`).eligibleOpenCount,
      1,
    );
    assert.equal(
      firestore.store.get(`userPrivate/${uid}/offerWallState/b`).eligibleOpenCount,
      1,
    );
  });
});

test("only the selected campaign receives pending display state and impression", async () => {
  await withFirestore({
    "offerWallCampaigns/a": campaign("a", ["allUsers"]),
    "offerWallCampaigns/b": campaign("b", ["petParent"]),
  }, async (firestore) => {
    const selected = await evaluate("session_state_mutation", 0.75);
    assert.equal(selected.campaignId, "b");
    const aState = firestore.store.get(`userPrivate/${uid}/offerWallState/a`);
    const bState = firestore.store.get(`userPrivate/${uid}/offerWallState/b`);
    assert.equal(aState.eligibleOpenCount, 1);
    assert.equal(aState.pendingDisplayToken, undefined);
    assert.equal(aState.impressionsShown, undefined);
    assert.equal(bState.pendingDisplayToken, selected.displayToken);
    assert.equal(bState.impressionsShown, 0);

    const acknowledged = await acknowledgeOfferWallImpression({
      uid,
      campaignId: selected.campaignId,
      sessionId: selected.sessionId,
      displayToken: selected.displayToken,
    });
    assert.deepEqual(acknowledged, {counted: true});
    assert.equal(
      firestore.store.get(`userPrivate/${uid}/offerWallState/b`).impressionsShown,
      1,
    );
    assert.equal(
      firestore.store.get(`userPrivate/${uid}/offerWallState/a`).impressionsShown,
      undefined,
    );
  });
});

test("deterministic random values can select either eligible campaign", async () => {
  const seed = {
    "offerWallCampaigns/a": campaign("a", ["allUsers"]),
    "offerWallCampaigns/b": campaign("b", ["petParent"]),
  };
  await withFirestore(seed, async () => {
    assert.equal((await evaluate("session_index_zero", 0)).campaignId, "a");
  });
  await withFirestore(seed, async () => {
    assert.equal((await evaluate("session_index_one", 0.999)).campaignId, "b");
  });
});

test("role contract uses exact canonical audience values", () => {
  assert.deepEqual(
    [...offerWallAudienceValues],
    ["allUsers", "petParent", "petLover", "serviceProvider"],
  );
  assert.deepEqual(
    [...offerWallUserRoleValues],
    ["petParent", "petLover", "serviceProvider"],
  );
  for (const role of ["petParent", "petLover", "serviceProvider"]) {
    assert.equal(matchesOfferWallAudience({audiences: [role], role}), true);
    assert.equal(matchesOfferWallAudience({audiences: ["allUsers"], role}), true);
  }
  for (const role of ["provider", "PET_PARENT", "pet_parent", "service_provider"]) {
    assert.equal(matchesOfferWallAudience({audiences: ["petParent"], role}), false);
    assert.equal(matchesOfferWallAudience({audiences: ["allUsers"], role}), false);
  }
});

test("concurrent duplicate evaluation of one session is idempotent", async () => {
  await withFirestore({
    "offerWallCampaigns/a": campaign("a", ["allUsers"]),
    "offerWallCampaigns/b": campaign("b", ["petParent"]),
  }, async (firestore) => {
    const [first, second] = await Promise.all([
      evaluate("session_concurrent", 0.75),
      evaluate("session_concurrent", 0),
    ]);
    assert.equal(first.campaignId, "b");
    assert.deepEqual(second, first);
    assert.equal(
      firestore.store.get(`userPrivate/${uid}/offerWallState/a`).eligibleOpenCount,
      1,
    );
    assert.equal(
      firestore.store.get(`userPrivate/${uid}/offerWallState/b`).eligibleOpenCount,
      1,
    );
  });
});
