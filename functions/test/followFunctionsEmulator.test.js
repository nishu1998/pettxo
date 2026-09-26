const test = require("node:test");
const assert = require("node:assert/strict");

const {applyFollowState} = require("../lib/social/followFunctions");
const {db} = require("../lib/shared/firebase");

async function seedUsers() {
  await Promise.all([
    db.collection("users").doc("follower").set({
      uid: "follower",
      accountStatus: "active",
      followingCount: 0,
      followerCount: 0,
    }),
    db.collection("users").doc("followee").set({
      uid: "followee",
      accountStatus: "active",
      profileVisibility: "public",
      isActive: true,
      followingCount: 0,
      followerCount: 0,
    }),
  ]);
}

async function cleanup() {
  const batch = db.batch();
  batch.delete(db.collection("follows").doc("follower_followee"));
  batch.delete(db.collection("users").doc("follower"));
  batch.delete(db.collection("users").doc("followee"));
  await batch.commit();
}

test.beforeEach(seedUsers);
test.afterEach(cleanup);

test("server transaction atomically follows once and duplicate follow is idempotent", async () => {
  const first = await applyFollowState({
    followerId: "follower",
    followeeId: "followee",
    desiredFollowing: true,
  });
  const duplicate = await applyFollowState({
    followerId: "follower",
    followeeId: "followee",
    desiredFollowing: true,
  });
  const [relationship, follower, followee] = await Promise.all([
    db.collection("follows").doc("follower_followee").get(),
    db.collection("users").doc("follower").get(),
    db.collection("users").doc("followee").get(),
  ]);
  assert.equal(first.changed, true);
  assert.equal(duplicate.changed, false);
  assert.equal(relationship.exists, true);
  assert.equal(follower.data().followingCount, 1);
  assert.equal(followee.data().followerCount, 1);
});

test("server transaction atomically unfollows once and duplicate unfollow is idempotent", async () => {
  await applyFollowState({
    followerId: "follower",
    followeeId: "followee",
    desiredFollowing: true,
  });
  const first = await applyFollowState({
    followerId: "follower",
    followeeId: "followee",
    desiredFollowing: false,
  });
  const duplicate = await applyFollowState({
    followerId: "follower",
    followeeId: "followee",
    desiredFollowing: false,
  });
  const [relationship, follower, followee] = await Promise.all([
    db.collection("follows").doc("follower_followee").get(),
    db.collection("users").doc("follower").get(),
    db.collection("users").doc("followee").get(),
  ]);
  assert.equal(first.changed, true);
  assert.equal(duplicate.changed, false);
  assert.equal(relationship.exists, false);
  assert.equal(follower.data().followingCount, 0);
  assert.equal(followee.data().followerCount, 0);
});

test("concurrent duplicate follows converge to one relationship and one count", async () => {
  await Promise.all([
    applyFollowState({followerId: "follower", followeeId: "followee", desiredFollowing: true}),
    applyFollowState({followerId: "follower", followeeId: "followee", desiredFollowing: true}),
  ]);
  const [follower, followee] = await Promise.all([
    db.collection("users").doc("follower").get(),
    db.collection("users").doc("followee").get(),
  ]);
  assert.equal(follower.data().followingCount, 1);
  assert.equal(followee.data().followerCount, 1);
});

test("unauthorized restricted actor cannot mutate a relationship", async () => {
  await db.collection("users").doc("follower").update({accountStatus: "restricted"});
  await assert.rejects(
    applyFollowState({
      followerId: "follower",
      followeeId: "followee",
      desiredFollowing: true,
    }),
    /cannot update follows/i,
  );
  assert.equal(
    (await db.collection("follows").doc("follower_followee").get()).exists,
    false,
  );
});
