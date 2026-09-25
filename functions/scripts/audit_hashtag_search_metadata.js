#!/usr/bin/env node
"use strict";

/**
 * Read-only audit for derived hashtag search metadata. This script has no
 * apply mode. It derives expected metadata only from explicitly stored public
 * socialPosts.hashtags values and never guesses tags from captions.
 */
const {applicationDefault, initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const EXPECTED_PROJECT_ID = "pettexo-d9409";

function parseArgs(argv) {
  const options = {projectId: "", pageSize: 200};
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--project") options.projectId = argv[++index] || "";
    else if (value === "--page-size") options.pageSize = Number(argv[++index]);
    else if (value === "--help") options.help = true;
    else throw new Error(`Unknown argument: ${value}`);
  }
  if (!Number.isInteger(options.pageSize) || options.pageSize < 1 || options.pageSize > 400) {
    throw new Error("--page-size must be an integer from 1 to 400");
  }
  return options;
}

function normalizeHashtag(value) {
  const trimmed = String(value || "").trim();
  const withoutPrefix = trimmed.startsWith("#") ? trimmed.slice(1) : trimmed;
  const normalized = withoutPrefix.toLowerCase();
  if (!/^[a-z0-9_]{1,30}$/.test(normalized)) return "";
  return normalized;
}

function userIsPubliclyVisible(data) {
  const status = String(data?.accountStatus || "active").trim().toLowerCase();
  return data?.isDeleted !== true &&
    data?.deletionRequested !== true &&
    data?.isActive !== false &&
    String(data?.profileVisibility || "public").trim().toLowerCase() !== "hidden" &&
    !["deleted", "deactivated", "disabled", "pendingdeletion", "deletioninprogress"].includes(status);
}

function postCreatedAtMs(data) {
  if (Number.isFinite(Number(data.createdAtEpoch))) return Number(data.createdAtEpoch);
  if (data.createdAt && typeof data.createdAt.toMillis === "function") {
    return data.createdAt.toMillis();
  }
  return 0;
}

function buildExpectedMetadata(posts, visibleAuthorIds) {
  const byTag = new Map();
  const invalidPostTags = [];
  for (const post of posts) {
    const data = post.data;
    if (data.visibilityStatus !== "visible" || data.moderationStatus !== "approved") continue;
    const authorId = String(data.authorId || "").trim();
    if (!visibleAuthorIds.has(authorId)) continue;
    const normalizedTags = new Set();
    for (const rawTag of Array.isArray(data.hashtags) ? data.hashtags : []) {
      const tag = normalizeHashtag(rawTag);
      if (!tag) {
        invalidPostTags.push({postId: post.id, rawTag: String(rawTag)});
      } else {
        normalizedTags.add(tag);
      }
    }
    for (const tag of normalizedTags) {
      const entries = byTag.get(tag) || [];
      entries.push({postId: post.id, createdAtMs: postCreatedAtMs(data)});
      byTag.set(tag, entries);
    }
  }
  const expected = new Map();
  for (const [tag, entries] of byTag.entries()) {
    entries.sort((a, b) => b.createdAtMs - a.createdAtMs || a.postId.localeCompare(b.postId));
    expected.set(tag, {
      tag,
      postCount: entries.length,
      recentPostIds: entries.slice(0, 30).map((entry) => entry.postId),
    });
  }
  return {expected, invalidPostTags};
}

function compareMetadata(expected, actualDocs) {
  const actual = new Map(actualDocs.map((doc) => [doc.id, doc.data]));
  const repairs = [];
  for (const [tag, next] of expected.entries()) {
    const before = actual.get(tag);
    const beforeIds = Array.isArray(before?.recentPostIds) ? before.recentPostIds : [];
    const idsMatch = beforeIds.length === next.recentPostIds.length &&
      beforeIds.every((id, index) => id === next.recentPostIds[index]);
    if (!before || before.tag !== tag || Number(before.postCount) !== next.postCount || !idsMatch) {
      repairs.push({tag, before: before || null, after: next});
    }
  }
  return repairs;
}

async function listCollection(db, collectionName, pageSize) {
  const documents = [];
  let last = null;
  do {
    let query = db.collection(collectionName).orderBy("__name__").limit(pageSize);
    if (last) query = query.startAfter(last);
    const page = await query.get();
    for (const doc of page.docs) documents.push({id: doc.id, data: doc.data()});
    last = page.docs.length === pageSize ? page.docs.at(-1) : null;
  } while (last);
  return documents;
}

async function runAudit({db, pageSize}) {
  const [posts, hashtagDocs, users] = await Promise.all([
    listCollection(db, "socialPosts", pageSize),
    listCollection(db, "hashtags", pageSize),
    listCollection(db, "users", pageSize),
  ]);
  const visibleAuthorIds = new Set(
    users.filter((user) => userIsPubliclyVisible(user.data)).map((user) => user.id),
  );
  const {expected, invalidPostTags} = buildExpectedMetadata(posts, visibleAuthorIds);
  const repairs = compareMetadata(expected, hashtagDocs);
  return {
    mode: "READ_ONLY_DRY_RUN",
    scanned: {posts: posts.length, hashtags: hashtagDocs.length, users: users.length},
    expectedHashtags: expected.size,
    affectedHashtags: repairs.length,
    missingHashtagDocuments: repairs.filter((repair) => repair.before == null).length,
    invalidExplicitPostTags: invalidPostTags.length,
    invalidPostTagSamples: invalidPostTags.slice(0, 10),
    repairSamples: repairs.slice(0, 20),
  };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.projectId) {
    console.log(`Usage: node scripts/audit_hashtag_search_metadata.js --project ${EXPECTED_PROJECT_ID} [--page-size 200]`);
    console.log("This tool is always read-only and has no apply mode.");
    process.exitCode = options.help ? 0 : 2;
    return;
  }
  if (options.projectId !== EXPECTED_PROJECT_ID) {
    throw new Error(`--project must be exactly ${EXPECTED_PROJECT_ID}`);
  }
  initializeApp({credential: applicationDefault(), projectId: options.projectId});
  const result = await runAudit({db: getFirestore(), pageSize: options.pageSize});
  console.log(JSON.stringify(result, null, 2));
  if (result.invalidExplicitPostTags > 0) process.exitCode = 1;
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message || error);
    process.exitCode = 1;
  });
}

module.exports = {
  buildExpectedMetadata,
  compareMetadata,
  normalizeHashtag,
  parseArgs,
  userIsPubliclyVisible,
};
