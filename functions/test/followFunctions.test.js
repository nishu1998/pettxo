const test = require("node:test");
const assert = require("node:assert/strict");

const {
  accountCanUseFollow,
  deriveFollowTransition,
} = require("../lib/social/followFunctions");

test("follow increments both counters exactly once and duplicate follow is a no-op", () => {
  const first = deriveFollowTransition({
    relationshipExists: false,
    desiredFollowing: true,
    followerFollowingCount: 4,
    followeeFollowerCount: 9,
  });
  assert.deepEqual(first, {
    changed: true,
    following: true,
    delta: 1,
    followerFollowingCount: 5,
    followeeFollowerCount: 10,
  });
  const duplicate = deriveFollowTransition({
    relationshipExists: true,
    desiredFollowing: true,
    followerFollowingCount: first.followerFollowingCount,
    followeeFollowerCount: first.followeeFollowerCount,
  });
  assert.equal(duplicate.changed, false);
  assert.equal(duplicate.delta, 0);
  assert.equal(duplicate.followerFollowingCount, 5);
  assert.equal(duplicate.followeeFollowerCount, 10);
});

test("unfollow decrements both counters exactly once and never below zero", () => {
  const first = deriveFollowTransition({
    relationshipExists: true,
    desiredFollowing: false,
    followerFollowingCount: 1,
    followeeFollowerCount: 1,
  });
  assert.equal(first.followerFollowingCount, 0);
  assert.equal(first.followeeFollowerCount, 0);
  const duplicate = deriveFollowTransition({
    relationshipExists: false,
    desiredFollowing: false,
    followerFollowingCount: 0,
    followeeFollowerCount: 0,
  });
  assert.equal(duplicate.changed, false);
  assert.equal(duplicate.followerFollowingCount, 0);
  assert.equal(duplicate.followeeFollowerCount, 0);
});

test("rapid follow, unfollow, follow converges without counter drift", () => {
  let relationshipExists = false;
  let followingCount = 0;
  let followerCount = 0;
  for (const desiredFollowing of [true, false, true, true]) {
    const result = deriveFollowTransition({
      relationshipExists,
      desiredFollowing,
      followerFollowingCount: followingCount,
      followeeFollowerCount: followerCount,
    });
    relationshipExists = result.following;
    followingCount = result.followerFollowingCount;
    followerCount = result.followeeFollowerCount;
  }
  assert.equal(relationshipExists, true);
  assert.equal(followingCount, 1);
  assert.equal(followerCount, 1);
});

test("restricted, banned, deleted, and pending-deletion actors are unauthorized", () => {
  assert.equal(accountCanUseFollow({accountStatus: "active"}), true);
  assert.equal(accountCanUseFollow({accountStatus: "restricted"}), false);
  assert.equal(accountCanUseFollow({accountStatus: "pendingDeletion"}), false);
  assert.equal(accountCanUseFollow({accountStatus: "active", isDeleted: true}), false);
  assert.equal(accountCanUseFollow({
    accountStatus: "active",
    restrictions: {social: {isBanned: true}},
  }), false);
  assert.equal(accountCanUseFollow({
    accountStatus: "active",
    restrictions: {hard: {isBanned: true}},
  }), false);
});
