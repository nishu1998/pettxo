const test = require("node:test");
const assert = require("node:assert/strict");

const {
  normalizeOfferAudienceInput,
  matchesOfferAudience,
} = require("../lib/offers/domain/offerAudience.js");
const {
  parseOfferCampaignRecord,
} = require("../lib/offers/domain/offerCampaign.js");
const {
  evaluateOfferAvailability,
} = require("../lib/offers/domain/offerEligibility.js");
const {
  buildAvailableOffersResult,
} = require("../lib/offers/application/getAvailableOffersApplication.js");
const {
  validateOfferCampaignForBooking,
} = require("../lib/offers/application/validateOfferCampaignForBooking.js");
const offerRepository = require("../lib/offers/data/offerRepository.js");
const {
  assertAuthenticatedOfferUid,
} = require("../lib/offers/callables/getAvailableOffers.js");
const {
  isOfferUsageAvailable,
} = require("../lib/offers/domain/offerUsagePolicy.js");

function buildCampaign(overrides = {}) {
  return {
    title: "Independence Day offer",
    description: "Seasonal savings",
    couponCode: "SAVE100",
    displayType: "offerWall",
    campaignType: "general",
    discountType: "flat",
    discountValue: 100,
    maxDiscountAmount: null,
    minBookingAmount: null,
    isActive: true,
    startAt: new Date("2026-08-01T00:00:00.000Z"),
    endAt: new Date("2026-08-31T23:59:59.000Z"),
    usageLimitPerUser: 1,
    targeting: {
      firstBookingOnly: false,
      rebookingOnly: false,
    },
    priority: 10,
    ...overrides,
  };
}

function buildUser(overrides = {}) {
  return {
    uid: "user_1",
    role: "petParent",
    completedBookingCount: 0,
    ...overrides,
  };
}

test("legacy campaigns without audience default to all users", () => {
  const audience = normalizeOfferAudienceInput(undefined, {
    allowLegacyMissing: true,
  });
  assert.deepEqual(audience, {type: "all"});

  const parsed = parseOfferCampaignRecord("campaign_1", buildCampaign());
  assert.deepEqual(parsed.audience, {type: "all"});
});

test("audience parsing supports all users, single roles, and multiple roles", () => {
  assert.deepEqual(normalizeOfferAudienceInput({type: "all"}), {type: "all"});
  assert.deepEqual(
    normalizeOfferAudienceInput({type: "roles", roles: ["serviceProvider"]}),
    {type: "roles", roles: ["serviceProvider"]},
  );
  assert.deepEqual(
    normalizeOfferAudienceInput({
      type: "roles",
      roles: ["petLover", "petParent", "petParent"],
    }),
    {type: "roles", roles: ["petLover", "petParent"]},
  );
});

test("malformed audience configuration fails safely", () => {
  assert.throws(
    () => normalizeOfferAudienceInput({type: "roles", roles: ["provider"]}),
    /invalid role/i,
  );
  assert.throws(
    () => normalizeOfferAudienceInput({type: "group", roles: ["petParent"]}),
    /audience\.type is invalid/i,
  );
  assert.equal(matchesOfferAudience({type: "all"}, ""), true);
  assert.equal(
    matchesOfferAudience({type: "roles", roles: ["serviceProvider"]}, "petParent"),
    false,
  );
});

test("automatic availability enforces audience and active date rules", () => {
  const now = new Date("2026-08-13T10:00:00.000Z");
  const eligible = parseOfferCampaignRecord("eligible", buildCampaign({
    audience: {type: "roles", roles: ["petParent"]},
  }));
  const inactive = parseOfferCampaignRecord("inactive", buildCampaign({
    isActive: false,
  }));
  const future = parseOfferCampaignRecord("future", buildCampaign({
    startAt: new Date("2026-09-01T00:00:00.000Z"),
  }));
  const expired = parseOfferCampaignRecord("expired", buildCampaign({
    endAt: new Date("2026-08-10T00:00:00.000Z"),
  }));

  assert.equal(
    evaluateOfferAvailability({
      campaign: eligible,
      user: buildUser(),
      now,
    }).ok,
    true,
  );
  assert.equal(
    evaluateOfferAvailability({
      campaign: eligible,
      user: buildUser({role: "serviceProvider"}),
      now,
    }).ok,
    false,
  );
  assert.equal(
    evaluateOfferAvailability({campaign: inactive, user: buildUser(), now}).ok,
    false,
  );
  assert.equal(
    evaluateOfferAvailability({campaign: future, user: buildUser(), now}).ok,
    false,
  );
  assert.equal(
    evaluateOfferAvailability({campaign: expired, user: buildUser(), now}).ok,
    false,
  );
});

test("first-booking and rebooking targeting preserve existing behavior", () => {
  const now = new Date("2026-08-13T10:00:00.000Z");
  const firstBookingOnly = parseOfferCampaignRecord("first", buildCampaign({
    targeting: {firstBookingOnly: true, rebookingOnly: false},
  }));
  const rebookingOnly = parseOfferCampaignRecord("rebook", buildCampaign({
    targeting: {firstBookingOnly: false, rebookingOnly: true},
  }));

  assert.equal(
    evaluateOfferAvailability({
      campaign: firstBookingOnly,
      user: buildUser({completedBookingCount: 0}),
      now,
    }).ok,
    true,
  );
  assert.equal(
    evaluateOfferAvailability({
      campaign: firstBookingOnly,
      user: buildUser({completedBookingCount: 2}),
      now,
    }).ok,
    false,
  );
  assert.equal(
    evaluateOfferAvailability({
      campaign: rebookingOnly,
      user: buildUser({completedBookingCount: 0}),
      now,
    }).ok,
    false,
  );
  assert.equal(
    evaluateOfferAvailability({
      campaign: rebookingOnly,
      user: buildUser({completedBookingCount: 3}),
      now,
    }).ok,
    true,
  );
});

test("automatic availability does not depend on claimed-offer documents", () => {
  const now = new Date("2026-08-13T10:00:00.000Z");
  const result = buildAvailableOffersResult({
    user: buildUser({role: "petParent"}),
    campaigns: [
      {
        id: "campaign_parent",
        data: buildCampaign({
          audience: {type: "roles", roles: ["petParent"]},
          displayType: "offerWall",
          priority: 50,
        }),
        createdAt: new Date("2026-08-12T00:00:00.000Z"),
      },
      {
        id: "campaign_provider",
        data: buildCampaign({
          audience: {type: "roles", roles: ["serviceProvider"]},
          displayType: "popup",
          priority: 60,
        }),
        createdAt: new Date("2026-08-11T00:00:00.000Z"),
      },
    ],
    now,
  });

  assert.equal(result.ok, true);
  assert.equal(result.offers.length, 1);
  assert.equal(result.offers[0].id, "campaign_parent");
  assert.equal("imageUrl" in result.offers[0], false);
  assert.equal(result.offerWall.id, "campaign_parent");
  assert.equal(result.popup, null);
});

test("automatic availability excludes malformed explicit audience docs instead of treating them as all users", () => {
  const result = buildAvailableOffersResult({
    user: buildUser(),
    campaigns: [
      {
        id: "bad_audience",
        data: buildCampaign({
          audience: {type: "roles", roles: ["provider"]},
        }),
        createdAt: new Date("2026-08-12T00:00:00.000Z"),
      },
    ],
    now: new Date("2026-08-13T10:00:00.000Z"),
  });

  assert.equal(result.offers.length, 0);
});

test("deleted campaigns are excluded from available offers while legacy docs without isDeleted remain valid", () => {
  const now = new Date("2026-08-13T10:00:00.000Z");
  const result = buildAvailableOffersResult({
    user: buildUser(),
    campaigns: [
      {
        id: "legacy_no_is_deleted",
        data: buildCampaign({
          couponCode: "LEGACYOK",
        }),
        createdAt: new Date("2026-08-12T00:00:00.000Z"),
      },
      {
        id: "deleted_campaign",
        data: buildCampaign({
          couponCode: "DELETED",
          isDeleted: true,
        }),
        createdAt: new Date("2026-08-11T00:00:00.000Z"),
      },
    ],
    now,
  });

  assert.deepEqual(
    result.offers.map((offer) => offer.id),
    ["legacy_no_is_deleted"],
  );
});

test("offer usage policy preserves bounded and legacy-unlimited semantics", () => {
  assert.equal(isOfferUsageAvailable({usageLimitPerUser: 1, usedCount: 0}), true);
  assert.equal(isOfferUsageAvailable({usageLimitPerUser: 1, usedCount: 1}), false);
  assert.equal(isOfferUsageAvailable({usageLimitPerUser: 3, usedCount: 2}), true);
  assert.equal(isOfferUsageAvailable({usageLimitPerUser: 3, usedCount: 3}), false);
  assert.equal(isOfferUsageAvailable({usageLimitPerUser: 0, usedCount: 99}), true);
});

test("getAvailableOffers excludes exhausted campaigns from bulk offerUsage state", () => {
  const now = new Date("2026-08-13T10:00:00.000Z");
  const result = buildAvailableOffersResult({
    user: buildUser({role: "petParent"}),
    campaigns: [
      {
        id: "limit_1_used_0",
        data: buildCampaign({usageLimitPerUser: 1, couponCode: "A"}),
        createdAt: new Date("2026-08-12T00:00:00.000Z"),
      },
      {
        id: "limit_1_used_1",
        data: buildCampaign({usageLimitPerUser: 1, couponCode: "B"}),
        createdAt: new Date("2026-08-11T00:00:00.000Z"),
      },
      {
        id: "limit_3_used_2",
        data: buildCampaign({usageLimitPerUser: 3, couponCode: "C"}),
        createdAt: new Date("2026-08-10T00:00:00.000Z"),
      },
      {
        id: "limit_3_used_3",
        data: buildCampaign({usageLimitPerUser: 3, couponCode: "D"}),
        createdAt: new Date("2026-08-09T00:00:00.000Z"),
      },
      {
        id: "legacy_unlimited",
        data: buildCampaign({usageLimitPerUser: 0, couponCode: "E"}),
        createdAt: new Date("2026-08-08T00:00:00.000Z"),
      },
    ],
    usageByCampaignId: new Map([
      ["limit_1_used_0", {usedCount: 0}],
      ["limit_1_used_1", {usedCount: 1}],
      ["limit_3_used_2", {usedCount: 2}],
      ["limit_3_used_3", {usedCount: 3}],
      ["legacy_unlimited", {usedCount: 100}],
    ]),
    now,
  });

  assert.deepEqual(
    result.offers.map((offer) => offer.id),
    ["limit_1_used_0", "limit_3_used_2", "legacy_unlimited"],
  );
});

test("getAvailableOffers and booking validation agree on exhausted usage", async () => {
  const now = new Date("2026-08-13T10:00:00.000Z");
  const originalLoadOfferUserProfile = offerRepository.loadOfferUserProfile;
  const originalLoadOfferCampaignDoc = offerRepository.loadOfferCampaignDoc;
  const originalLoadOfferUsageRecord = offerRepository.loadOfferUsageRecord;

  offerRepository.loadOfferUserProfile = async () => buildUser();
  offerRepository.loadOfferCampaignDoc = async () => ({
    id: "campaign_validate",
    data: () => buildCampaign({
      usageLimitPerUser: 1,
      couponCode: "VALIDATE1",
    }),
  });
  offerRepository.loadOfferUsageRecord = async () => ({
    offerCampaignId: "campaign_validate",
    usedCount: 1,
    consumedBookingIds: [],
    lastUsedAt: null,
  });

  try {
    const availability = buildAvailableOffersResult({
      user: buildUser(),
      campaigns: [
        {
          id: "campaign_validate",
          data: buildCampaign({usageLimitPerUser: 1, couponCode: "VALIDATE1"}),
          createdAt: now,
        },
      ],
      usageByCampaignId: new Map([["campaign_validate", {usedCount: 1}]]),
      now,
      bookingContext: {
        bookingAmount: 1000,
        serviceId: "service_1",
        providerId: "provider_1",
        serviceCategory: "grooming",
      },
    });
    assert.equal(availability.offers.length, 0);

    const validation = await validateOfferCampaignForBooking({
      uid: "user_1",
      offerCampaignId: "campaign_validate",
      booking: {
        serviceId: "service_1",
        providerId: "provider_1",
        service: {category: "grooming"},
      },
      serviceSubtotalAmount: 1000,
      now,
    });
    assert.equal(validation.ok, false);
    assert.equal(validation.code, "COUPON_INVALID");
  } finally {
    offerRepository.loadOfferUserProfile = originalLoadOfferUserProfile;
    offerRepository.loadOfferCampaignDoc = originalLoadOfferCampaignDoc;
    offerRepository.loadOfferUsageRecord = originalLoadOfferUsageRecord;
  }
});

test("booking validation rejects deleted campaigns from the live campaign document", async () => {
  const now = new Date("2026-08-13T10:00:00.000Z");
  const originalLoadOfferUserProfile = offerRepository.loadOfferUserProfile;
  const originalLoadOfferCampaignDoc = offerRepository.loadOfferCampaignDoc;
  const originalLoadOfferUsageRecord = offerRepository.loadOfferUsageRecord;

  offerRepository.loadOfferUserProfile = async () => buildUser();
  offerRepository.loadOfferCampaignDoc = async () => ({
    id: "campaign_deleted",
    data: () => buildCampaign({
      isDeleted: true,
      couponCode: "DELETED",
    }),
  });
  offerRepository.loadOfferUsageRecord = async () => ({
    offerCampaignId: "campaign_deleted",
    usedCount: 0,
    consumedBookingIds: [],
    lastUsedAt: null,
  });

  try {
    const validation = await validateOfferCampaignForBooking({
      uid: "user_1",
      offerCampaignId: "campaign_deleted",
      booking: {
        serviceId: "service_1",
        providerId: "provider_1",
        service: {category: "grooming"},
      },
      serviceSubtotalAmount: 1000,
      now,
    });

    assert.equal(validation.ok, false);
    assert.equal(validation.code, "COUPON_INVALID");
  } finally {
    offerRepository.loadOfferUserProfile = originalLoadOfferUserProfile;
    offerRepository.loadOfferCampaignDoc = originalLoadOfferCampaignDoc;
    offerRepository.loadOfferUsageRecord = originalLoadOfferUsageRecord;
  }
});

test("getAvailableOffers rejects unauthenticated callers", () => {
  assert.throws(() => assertAuthenticatedOfferUid(""), /Sign in to continue/);
  assert.doesNotThrow(() => assertAuthenticatedOfferUid("user_1"));
});
