"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  buildExpectedMetadata,
  compareMetadata,
  normalizeHashtag,
  parseArgs,
  userIsPubliclyVisible,
} = require("../scripts/audit_hashtag_search_metadata.js");

test("hashtag audit normalizes only explicit canonical post tags", () => {
  assert.equal(normalizeHashtag(" #Adoption "), "adoption");
  assert.equal(normalizeHashtag("rabbit"), "rabbit");
  assert.equal(normalizeHashtag("two words"), "");
});

test("hashtag audit derives visible approved metadata without caption guessing", () => {
  const posts = [
    {id: "new", data: {authorId: "a", visibilityStatus: "visible", moderationStatus: "approved", hashtags: ["#Adoption", "rabbit"], caption: "#ignored", createdAtEpoch: 20}},
    {id: "old", data: {authorId: "a", visibilityStatus: "visible", moderationStatus: "approved", hashtags: ["adoption"], createdAtEpoch: 10}},
    {id: "hidden", data: {authorId: "a", visibilityStatus: "hidden", moderationStatus: "approved", hashtags: ["adoption"], createdAtEpoch: 30}},
    {id: "inactive-author", data: {authorId: "b", visibilityStatus: "visible", moderationStatus: "approved", hashtags: ["adoption"], createdAtEpoch: 40}},
  ];
  const {expected, invalidPostTags} = buildExpectedMetadata(posts, new Set(["a"]));

  assert.deepEqual(expected.get("adoption"), {
    tag: "adoption",
    postCount: 2,
    recentPostIds: ["new", "old"],
  });
  assert.deepEqual(expected.get("rabbit"), {
    tag: "rabbit",
    postCount: 1,
    recentPostIds: ["new"],
  });
  assert.deepEqual(invalidPostTags, []);
  assert.equal(expected.has("ignored"), false);
});

test("hashtag audit identifies missing and stale derived documents", () => {
  const expected = new Map([
    ["adoption", {tag: "adoption", postCount: 2, recentPostIds: ["new", "old"]}],
    ["rabbit", {tag: "rabbit", postCount: 2, recentPostIds: ["new", "rabbit-old"]}],
  ]);
  const repairs = compareMetadata(expected, [
    {id: "rabbit", data: {tag: "rabbit", postCount: 1, recentPostIds: ["rabbit-old"]}},
  ]);

  assert.deepEqual(repairs.map((repair) => repair.tag), ["adoption", "rabbit"]);
  assert.equal(repairs[0].before, null);
  assert.equal(repairs[1].after.postCount, 2);
});

test("hashtag audit has an exact project argument and no apply option", () => {
  assert.deepEqual(parseArgs(["--project", "pettexo-d9409"]), {
    projectId: "pettexo-d9409",
    pageSize: 200,
  });
  assert.throws(() => parseArgs(["--apply"]), /Unknown argument/);
});

test("hashtag audit excludes deleted and hidden accounts", () => {
  assert.equal(userIsPubliclyVisible({accountStatus: "active"}), true);
  assert.equal(userIsPubliclyVisible({isDeleted: true}), false);
  assert.equal(userIsPubliclyVisible({profileVisibility: "hidden"}), false);
  assert.equal(userIsPubliclyVisible({accountStatus: "deactivated"}), false);
});
