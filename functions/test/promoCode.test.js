const test = require("node:test");
const assert = require("node:assert/strict");

const {
  normalizePromoCode,
  normalizePromoCodeForDefinition,
  promoCodeHash,
} = require("../lib/offers/domain/promoCode.js");
const sharedFirebase = require("../lib/shared/firebase.js");
const {
  assertPromoCodeAttemptAllowed,
  PROMO_ATTEMPT_LIMIT,
  resolveOfferCampaignByPromoCode,
} = require("../lib/offers/data/offerRepository.js");

test("promo code normalization canonicalizes case, width, and surrounding whitespace", () => {
  assert.equal(normalizePromoCode("pettxo50"), "PETTXO50");
  assert.equal(normalizePromoCode("  Pettxo50  "), "PETTXO50");
  assert.equal(normalizePromoCode("ＰＥＴＴＸＯ５０"), "PETTXO50");
  assert.equal(promoCodeHash(normalizePromoCode(" pettxo50 ")), promoCodeHash("PETTXO50"));
});

test("promo code normalization rejects unsafe and ambiguous input", () => {
  for (const value of [
    "@pettxo50",
    "PET TXO50",
    "PET\u200bTXO50",
    "PET\nTXO50",
    "AB",
    "A".repeat(33),
    "SAVE.50",
    "",
  ]) {
    assert.throws(() => normalizePromoCode(value), /invalid/i, value);
  }
});

test("new coupon definitions accept 20 characters and reject oversized pasted input", () => {
  assert.equal(normalizePromoCodeForDefinition("a".repeat(20)), "A".repeat(20));
  assert.equal(
    normalizePromoCodeForDefinition(`  ${"b".repeat(20)}  `),
    "B".repeat(20),
  );
  assert.throws(
    () => normalizePromoCodeForDefinition("c".repeat(21)),
    /invalid/i,
  );
  assert.throws(
    () => normalizePromoCodeForDefinition(`  ${"d".repeat(21)}  `),
    /invalid/i,
  );
});

test("legacy redemption normalization still accepts existing 21-32 character codes", () => {
  assert.equal(normalizePromoCode("a".repeat(32)), "A".repeat(32));
});

test("promo attempt limiter allows human retries and blocks the next attempt in the window", async () => {
  const store = new Map();
  const originalCollection = sharedFirebase.db.collection;
  const originalRunTransaction = sharedFirebase.db.runTransaction;
  const refFor = (path) => ({
    path,
    get: async () => ({
      exists: store.has(path),
      data: () => store.get(path),
    }),
  });
  sharedFirebase.db.collection = (collectionPath) => ({
    doc: (id) => refFor(`${collectionPath}/${id}`),
  });
  sharedFirebase.db.runTransaction = async (callback) => callback({
    get: (ref) => ref.get(),
    set: (ref, data, options = {}) => {
      store.set(ref.path, options.merge ? {...store.get(ref.path), ...data} : data);
    },
  });

  try {
    const now = new Date("2026-10-02T10:00:00.000Z");
    for (let attempt = 0; attempt < PROMO_ATTEMPT_LIMIT; attempt += 1) {
      await assertPromoCodeAttemptAllowed({uid: "user-1", now});
    }
    await assert.rejects(
      assertPromoCodeAttemptAllowed({uid: "user-1", now}),
      /PROMO_CODE_RATE_LIMITED/,
    );
    await assertPromoCodeAttemptAllowed({
      uid: "user-1",
      now: new Date("2026-10-02T10:10:00.000Z"),
    });
  } finally {
    sharedFirebase.db.collection = originalCollection;
    sharedFirebase.db.runTransaction = originalRunTransaction;
  }
});

test("exact promo resolution uses only the hashed index and does not return retired codes", async () => {
  const originalCollection = sharedFirebase.db.collection;
  const documents = new Map([
    [`offerCodeIndex/${promoCodeHash("SECRET50")}`, {
      campaignId: "campaign-secret",
      state: "active",
    }],
    [`offerCodeIndex/${promoCodeHash("OLD50")}`, {
      campaignId: "campaign-old",
      state: "retired",
    }],
  ]);
  sharedFirebase.db.collection = (collectionPath) => ({
    doc: (id) => ({
      get: async () => ({
        exists: documents.has(`${collectionPath}/${id}`),
        data: () => documents.get(`${collectionPath}/${id}`),
      }),
    }),
  });

  try {
    assert.deepEqual(await resolveOfferCampaignByPromoCode(" secret50 "), {
      normalizedCode: "SECRET50",
      campaignId: "campaign-secret",
    });
    assert.equal(await resolveOfferCampaignByPromoCode("OLD50"), null);
  } finally {
    sharedFirebase.db.collection = originalCollection;
  }
});
