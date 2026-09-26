#!/usr/bin/env node
"use strict";

/** Read-only audit of follows/{followerId}_{followeeId} and user counters. */
const {applicationDefault, initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const EXPECTED_PROJECT_ID = "pettexo-d9409";

function parseArgs(argv) {
  const options = {projectId: "", pageSize: 300};
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--project") options.projectId = argv[++index] || "";
    else if (value === "--page-size") options.pageSize = Number(argv[++index]);
    else if (value === "--help") options.help = true;
    else throw new Error(`Unknown argument: ${value}`);
  }
  if (!Number.isInteger(options.pageSize) || options.pageSize < 1 || options.pageSize > 500) {
    throw new Error("--page-size must be an integer from 1 to 500");
  }
  return options;
}

function nonNegativeCount(value) {
  return typeof value === "number" && Number.isFinite(value) ? Math.max(0, value) : 0;
}

function analyzeFollowConsistency(users, follows) {
  const userById = new Map(users.map((user) => [user.id, user.data]));
  const expectedFollowers = new Map(users.map((user) => [user.id, 0]));
  const expectedFollowing = new Map(users.map((user) => [user.id, 0]));
  const pairDocuments = new Map();
  const invalidRelationships = [];
  const orphanRelationships = [];
  const selfFollowRecords = [];

  for (const follow of follows) {
    const followerId = String(follow.data.followerId || "").trim();
    const followeeId = String(follow.data.followeeId || "").trim();
    const pair = `${followerId}_${followeeId}`;
    if (!followerId || !followeeId || follow.id !== pair) {
      invalidRelationships.push({id: follow.id, followerId, followeeId});
      continue;
    }
    if (followerId === followeeId) {
      selfFollowRecords.push({id: follow.id, userId: followerId});
      continue;
    }
    const documents = pairDocuments.get(pair) || [];
    documents.push(follow.id);
    pairDocuments.set(pair, documents);
    const missingUsers = [followerId, followeeId].filter((id) => !userById.has(id));
    if (missingUsers.length > 0) {
      orphanRelationships.push({id: follow.id, followerId, followeeId, missingUsers});
    }
    if (expectedFollowing.has(followerId)) {
      expectedFollowing.set(followerId, expectedFollowing.get(followerId) + 1);
    }
    if (expectedFollowers.has(followeeId)) {
      expectedFollowers.set(followeeId, expectedFollowers.get(followeeId) + 1);
    }
  }

  const duplicateRelationships = Array.from(pairDocuments.entries())
    .filter(([, documents]) => documents.length > 1)
    .map(([pair, documents]) => ({pair, documents}));
  const followerCountMismatches = [];
  const followingCountMismatches = [];
  for (const user of users) {
    const storedFollowerCount = nonNegativeCount(user.data.followerCount);
    const storedFollowingCount = nonNegativeCount(user.data.followingCount);
    const expectedFollowerCount = expectedFollowers.get(user.id) || 0;
    const expectedFollowingCount = expectedFollowing.get(user.id) || 0;
    if (storedFollowerCount !== expectedFollowerCount) {
      followerCountMismatches.push({
        userId: user.id,
        stored: storedFollowerCount,
        expected: expectedFollowerCount,
      });
    }
    if (storedFollowingCount !== expectedFollowingCount) {
      followingCountMismatches.push({
        userId: user.id,
        stored: storedFollowingCount,
        expected: expectedFollowingCount,
      });
    }
  }

  return {
    mode: "READ_ONLY",
    usersScanned: users.length,
    relationshipsScanned: follows.length,
    incorrectFollowerCounts: followerCountMismatches.length,
    incorrectFollowingCounts: followingCountMismatches.length,
    orphanRelationships: orphanRelationships.length,
    duplicateRelationships: duplicateRelationships.length,
    invalidRelationships: invalidRelationships.length,
    selfFollowRecords: selfFollowRecords.length,
    samples: {
      followerCountMismatches: followerCountMismatches.slice(0, 20),
      followingCountMismatches: followingCountMismatches.slice(0, 20),
      orphanRelationships: orphanRelationships.slice(0, 20),
      duplicateRelationships: duplicateRelationships.slice(0, 20),
      invalidRelationships: invalidRelationships.slice(0, 20),
      selfFollowRecords: selfFollowRecords.slice(0, 20),
    },
  };
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

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.projectId) {
    console.log(`Usage: node scripts/audit_follow_consistency.js --project ${EXPECTED_PROJECT_ID}`);
    console.log("This tool is always read-only and has no apply mode.");
    process.exitCode = options.help ? 0 : 2;
    return;
  }
  if (options.projectId !== EXPECTED_PROJECT_ID) {
    throw new Error(`--project must be exactly ${EXPECTED_PROJECT_ID}`);
  }
  initializeApp({credential: applicationDefault(), projectId: options.projectId});
  const db = getFirestore();
  const [users, follows] = await Promise.all([
    listCollection(db, "users", options.pageSize),
    listCollection(db, "follows", options.pageSize),
  ]);
  console.log(JSON.stringify(analyzeFollowConsistency(users, follows), null, 2));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message || error);
    process.exitCode = 1;
  });
}

module.exports = {analyzeFollowConsistency, nonNegativeCount, parseArgs};
