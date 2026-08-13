const test = require("node:test");
const assert = require("node:assert/strict");

const sharedFirebase = require("../lib/shared/firebase.js");
const {cleanupAccountFirestoreData} = require("../lib/legacyFunctions.js");

function createStats() {
  return {
    firestoreDeleted: {},
    firestoreUpdated: {},
    storageDeleted: {},
  };
}

class FakeDocSnapshot {
  constructor(ref) {
    this.ref = ref;
    this.id = ref.id;
  }
}

class FakeQuery {
  limit() {
    return this;
  }

  where() {
    return this;
  }

  async get() {
    return {empty: true, docs: []};
  }
}

class FakeCollectionRef extends FakeQuery {
  constructor(firestore, path) {
    super();
    this.firestore = firestore;
    this.path = path;
    this.id = path.split("/").pop();
  }

  doc(id) {
    return new FakeDocRef(this.firestore, `${this.path}/${id}`);
  }

  async get() {
    const docs = [...this.firestore.store.keys()]
      .filter((path) => {
        if (!path.startsWith(`${this.path}/`)) return false;
        const remainder = path.slice(this.path.length + 1);
        return remainder.length > 0 && !remainder.includes("/");
      })
      .sort()
      .map((path) => new FakeDocSnapshot(new FakeDocRef(this.firestore, path)));
    return {
      empty: docs.length === 0,
      docs,
    };
  }
}

class FakeDocRef {
  constructor(firestore, path) {
    this.firestore = firestore;
    this.path = path;
    this.id = path.split("/").pop();
  }

  get parent() {
    return new FakeCollectionRef(
      this.firestore,
      this.path.split("/").slice(0, -1).join("/"),
    );
  }

  collection(name) {
    return new FakeCollectionRef(this.firestore, `${this.path}/${name}`);
  }

  async listCollections() {
    const seen = new Set();
    for (const path of this.firestore.store.keys()) {
      if (!path.startsWith(`${this.path}/`)) continue;
      const remainder = path.slice(this.path.length + 1);
      const [collectionId] = remainder.split("/");
      if (collectionId) {
        seen.add(`${this.path}/${collectionId}`);
      }
    }
    return [...seen].sort().map((path) => new FakeCollectionRef(this.firestore, path));
  }

  async delete() {
    this.firestore.store.delete(this.path);
  }
}

class FakeCleanupFirestore {
  constructor(seed = {}) {
    this.store = new Map(Object.entries(seed));
  }

  collection(path) {
    return new FakeCollectionRef(this, path);
  }

  collectionGroup() {
    return new FakeQuery();
  }
}

test("cleanupAccountFirestoreData removes offerUsage with the existing user cleanup flow", async () => {
  const originalCollection = sharedFirebase.db.collection;
  const originalCollectionGroup = sharedFirebase.db.collectionGroup;
  const firestore = new FakeCleanupFirestore({
    "users/user_1/notificationTokens/token_1": {token: "abc"},
    "users/user_1/claimedOffers/legacy_1": {status: "claimed"},
    "users/user_1/offerUsage/campaign_1": {usedCount: 1},
    "users/user_1/offerUsage/campaign_2": {usedCount: 2},
    "users/user_1/providerVerification/check_1": {status: "approved"},
  });

  sharedFirebase.db.collection = firestore.collection.bind(firestore);
  sharedFirebase.db.collectionGroup = firestore.collectionGroup.bind(firestore);

  try {
    const stats = createStats();
    await cleanupAccountFirestoreData("user_1", stats);

    assert.equal(
      [...firestore.store.keys()].some((path) => path.startsWith("users/user_1/offerUsage/")),
      false,
    );
    assert.equal(
      [...firestore.store.keys()].some((path) => path.startsWith("users/user_1/claimedOffers/")),
      false,
    );
    assert.equal(stats.firestoreDeleted.offerUsage, 2);
  } finally {
    sharedFirebase.db.collection = originalCollection;
    sharedFirebase.db.collectionGroup = originalCollectionGroup;
  }
});
