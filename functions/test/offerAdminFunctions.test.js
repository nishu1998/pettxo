const test = require("node:test");
const assert = require("node:assert/strict");

const sharedFirebase = require("../lib/shared/firebase.js");
const legacyFunctions = require("../lib/legacyFunctions.js");
const {
  sanitizeOfferCampaignMutationInput,
} = require("../lib/offers/application/offerAdminContract.js");

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
}

class FakeBatch {
  constructor(firestore) {
    this.firestore = firestore;
    this.writes = [];
  }

  set(ref, data, options) {
    this.writes.push({path: ref.path, data, options});
  }

  async commit() {
    for (const write of this.writes) {
      this.firestore._set(write.path, write.data, write.options);
    }
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

  batch() {
    return new FakeBatch(this);
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

function baseCampaign(overrides = {}) {
  return {
    title: "Independence Day Offer",
    description: "Save on your next booking",
    couponCode: "SAVE100",
    displayType: "popup",
    campaignType: "general",
    discountType: "flat",
    discountValue: 100,
    maxDiscountAmount: null,
    minBookingAmount: null,
    isActive: true,
    isDeleted: false,
    startAt: new Date("2026-08-01T00:00:00.000Z"),
    endAt: new Date("2026-08-31T23:59:59.000Z"),
    usageLimitPerUser: 1,
    targeting: {
      firstBookingOnly: false,
      rebookingOnly: false,
    },
    audience: {type: "all"},
    priority: 0,
    ...overrides,
  };
}

async function withFakeFirestore(seed, fn) {
  const firestore = new FakeFirestore(seed);
  const originalCollection = sharedFirebase.db.collection;
  const originalBatch = sharedFirebase.db.batch;

  sharedFirebase.db.collection = firestore.collection.bind(firestore);
  sharedFirebase.db.batch = firestore.batch.bind(firestore);

  try {
    await fn(firestore);
  } finally {
    sharedFirebase.db.collection = originalCollection;
    sharedFirebase.db.batch = originalBatch;
  }
}

test("sanitizeOfferCampaignMutationInput accepts the canonical update payload", () => {
  const result = sanitizeOfferCampaignMutationInput({
    rawData: {
      campaignId: "campaign_1",
      title: "Updated",
      couponCode: "SAVE200",
      campaignType: "general",
      discountType: "flat",
      discountValue: 200,
      startAt: "2026-08-01T00:00:00.000Z",
      endAt: "2026-08-31T23:59:59.000Z",
      audience: {type: "all"},
      usageLimitPerUser: 1,
      targeting: {firstBookingOnly: false, rebookingOnly: false},
      priority: 5,
    },
    requireCampaignId: true,
  });

  assert.equal(result.campaignId, "campaign_1");
  assert.deepEqual(result.ignoredLegacyFields, []);
  assert.equal(result.usedLegacyIdentityAlias, false);
});

test("sanitizeOfferCampaignMutationInput strips known claim-era compatibility fields for the active admin caller", () => {
  const result = sanitizeOfferCampaignMutationInput({
    rawData: {
      offerCampaignId: "campaign_legacy",
      title: "Updated",
      claimValidityType: "fixed",
      claimValidUntil: "2026-09-01T00:00:00.000Z",
      validDaysAfterClaim: 5,
      displayType: "popup",
    },
    requireCampaignId: true,
  });

  assert.equal(result.campaignId, "campaign_legacy");
  assert.deepEqual(
    result.ignoredLegacyFields.sort(),
    ["claimValidUntil", "claimValidityType", "displayType", "validDaysAfterClaim"],
  );
  assert.deepEqual(result.payload, {title: "Updated"});
  assert.equal(result.usedLegacyIdentityAlias, true);
});

test("sanitizeOfferCampaignMutationInput rejects unsupported non-contract fields clearly", () => {
  assert.throws(
    () => sanitizeOfferCampaignMutationInput({
      rawData: {
        campaignId: "campaign_1",
        title: "Updated",
        unsupportedLegacyBlob: true,
      },
      requireCampaignId: true,
    }),
    /Unsupported fields: unsupportedLegacyBlob/,
  );
});

test("sanitizeOfferCampaignMutationInput rejects coupon imageUrl in new requests", () => {
  assert.throws(
    () => sanitizeOfferCampaignMutationInput({
      rawData: {
        campaignId: "campaign_1",
        title: "Updated",
        imageUrl: "https://example.com/coupon.png",
      },
      requireCampaignId: true,
    }),
    /Unsupported fields: imageUrl/,
  );
});

test("campaignId remains the canonical mutation identity and conflicting aliases fail", () => {
  assert.throws(
    () => sanitizeOfferCampaignMutationInput({
      rawData: {
        campaignId: "campaign_a",
        offerCampaignId: "campaign_b",
        title: "Updated",
      },
      requireCampaignId: true,
    }),
    /Provide exactly one campaign identity/,
  );
});

test("updateOfferCampaign edits an old legacy document with the canonical payload and does not require claim fields", async () => {
  await withFakeFirestore({
    "users/admin_1": {
      adminRole: "financeAdmin",
    },
    "offerCampaigns/campaign_1": {
      ...baseCampaign(),
      claimValidityType: "fixed",
      claimValidUntil: new Date("2026-08-31T23:59:59.000Z"),
      validDaysAfterClaim: 7,
    },
  }, async (firestore) => {
    const result = await legacyFunctions.updateOfferCampaign.run({
      auth: {uid: "admin_1"},
      data: {
        campaignId: "campaign_1",
        title: "Updated title",
        description: "Updated description",
        couponCode: "SAVE200",
        campaignType: "general",
        discountType: "flat",
        discountValue: 200,
        maxDiscountAmount: null,
        minBookingAmount: 500,
        startAt: "2026-08-05T00:00:00.000Z",
        endAt: "2026-08-31T23:59:59.000Z",
        audience: {type: "all"},
        usageLimitPerUser: 3,
        targeting: {firstBookingOnly: false, rebookingOnly: false},
        priority: 9,
      },
    });

    assert.deepEqual(result, {ok: true, campaignId: "campaign_1"});
    const updated = firestore.store.get("offerCampaigns/campaign_1");
    assert.equal(updated.title, "Updated title");
    assert.equal(updated.discountValue, 200);
    assert.equal(updated.displayType, "popup");
    assert.equal(updated.claimValidityType, "fixed");
  });
});

test("authorized deleteOfferCampaign soft-deletes the campaign without touching historical financial documents", async () => {
  await withFakeFirestore({
    "users/admin_1": {
      adminRole: "superAdmin",
    },
    "offerCampaigns/campaign_delete_1": baseCampaign({
      isActive: true,
      isDeleted: false,
    }),
    "payments/booking_1": {bookingId: "booking_1", offerCampaignId: "campaign_delete_1"},
    "bookingFinancials/booking_1": {bookingId: "booking_1", offerCampaignId: "campaign_delete_1"},
    "providerEarnings/booking_1": {bookingId: "booking_1", offerCampaignId: "campaign_delete_1"},
    "invoices/booking_1": {invoiceId: "booking_1", offerCampaignId: "campaign_delete_1"},
  }, async (firestore) => {
    const historicalBefore = {
      payment: firestore.store.get("payments/booking_1"),
      bookingFinancial: firestore.store.get("bookingFinancials/booking_1"),
      providerEarning: firestore.store.get("providerEarnings/booking_1"),
      invoice: firestore.store.get("invoices/booking_1"),
    };

    const result = await legacyFunctions.deleteOfferCampaign.run({
      auth: {uid: "admin_1"},
      data: {campaignId: "campaign_delete_1"},
    });

    assert.deepEqual(result, {
      ok: true,
      campaignId: "campaign_delete_1",
      isDeleted: true,
    });
    const deleted = firestore.store.get("offerCampaigns/campaign_delete_1");
    assert.equal(deleted.isActive, false);
    assert.equal(deleted.isDeleted, true);
    assert.equal(deleted.deletedBy, "admin_1");
    assert.equal(deleted.updatedBy, "admin_1");
    assert.equal(deleted.deletedAt instanceof Date, true);
    assert.equal(deleted.updatedAt instanceof Date, true);
    assert.deepEqual(firestore.store.get("payments/booking_1"), historicalBefore.payment);
    assert.deepEqual(
      firestore.store.get("bookingFinancials/booking_1"),
      historicalBefore.bookingFinancial,
    );
    assert.deepEqual(
      firestore.store.get("providerEarnings/booking_1"),
      historicalBefore.providerEarning,
    );
    assert.deepEqual(firestore.store.get("invoices/booking_1"), historicalBefore.invoice);
  });
});

test("unauthorized admins cannot delete offer campaigns", async () => {
  await withFakeFirestore({
    "users/admin_1": {
      adminRole: "customerSupportAdmin",
    },
    "offerCampaigns/campaign_delete_2": baseCampaign(),
  }, async () => {
    await assert.rejects(
      () => legacyFunctions.deleteOfferCampaign.run({
        auth: {uid: "admin_1"},
        data: {campaignId: "campaign_delete_2"},
      }),
      /do not have access to manage offer campaigns/i,
    );
  });
});
