const test = require("node:test");
const assert = require("node:assert/strict");

const {
  analyzeFollowConsistency,
  parseArgs,
} = require("../scripts/audit_follow_consistency");

test("follow audit reports exact counts for valid deterministic relationships", () => {
  const result = analyzeFollowConsistency(
    [
      {id: "a", data: {followerCount: 0, followingCount: 1}},
      {id: "b", data: {followerCount: 1, followingCount: 0}},
    ],
    [{id: "a_b", data: {followerId: "a", followeeId: "b"}}],
  );
  assert.equal(result.incorrectFollowerCounts, 0);
  assert.equal(result.incorrectFollowingCounts, 0);
  assert.equal(result.invalidRelationships, 0);
});

test("follow audit finds drift, orphans, invalid ids, and self follows", () => {
  const result = analyzeFollowConsistency(
    [
      {id: "a", data: {followerCount: 3, followingCount: 0}},
      {id: "b", data: {followerCount: 0, followingCount: 7}},
    ],
    [
      {id: "a_b", data: {followerId: "a", followeeId: "b"}},
      {id: "a_missing", data: {followerId: "a", followeeId: "missing"}},
      {id: "wrong", data: {followerId: "b", followeeId: "a"}},
      {id: "a_a", data: {followerId: "a", followeeId: "a"}},
    ],
  );
  assert.equal(result.incorrectFollowerCounts, 2);
  assert.equal(result.incorrectFollowingCounts, 2);
  assert.equal(result.orphanRelationships, 1);
  assert.equal(result.invalidRelationships, 1);
  assert.equal(result.selfFollowRecords, 1);
});

test("follow audit has an exact project guard and no apply option", () => {
  assert.deepEqual(parseArgs(["--project", "pettexo-d9409"]), {
    projectId: "pettexo-d9409",
    pageSize: 300,
  });
  assert.throws(() => parseArgs(["--apply"]), /Unknown argument/);
});
