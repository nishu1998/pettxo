const test = require("node:test");
const assert = require("node:assert/strict");

const {
  shouldDisplayOfferWallAfterCount,
  sortOfferWallCampaignsForEvaluation,
} = require("../lib/offerWall/domain/offerWallEligibility.js");

test("offer wall interval 5 repetition 2 unlocks on opens 5 and 10 only", () => {
  const campaign = {openInterval: 5, repetitionLimit: 2};
  let state = {eligibleOpenCount: 0, impressionsShown: 0};
  const displays = [];

  for (let open = 1; open <= 11; open += 1) {
    state = {...state, eligibleOpenCount: open};
    if (shouldDisplayOfferWallAfterCount({campaign, state})) {
      displays.push(open);
      state = {...state, impressionsShown: state.impressionsShown + 1};
    }
  }

  assert.deepEqual(displays, [5, 10]);
  assert.equal(
    shouldDisplayOfferWallAfterCount({
      campaign,
      state: {eligibleOpenCount: 11, impressionsShown: 2},
    }),
    false,
  );
});

test("offer wall campaign sort uses oldest createdAt then id", () => {
  const campaigns = [
    {id: "c", createdAt: new Date("2026-08-12T00:00:00.000Z")},
    {id: "a", createdAt: new Date("2026-08-10T00:00:00.000Z")},
    {id: "b", createdAt: new Date("2026-08-10T00:00:00.000Z")},
  ];

  assert.deepEqual(
    sortOfferWallCampaignsForEvaluation(campaigns).map((campaign) => campaign.id),
    ["a", "b", "c"],
  );
});
