const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const { doc, setDoc, serverTimestamp } = require("firebase/firestore");

const projectId = "pettexo-d9409";
const rules = fs.readFileSync(
  path.resolve(__dirname, "../../firestore.rules"),
  "utf8",
);

function buildRuntimePayload(uid, postId) {
  return {
    id: postId,
    authorId: uid,
    authorType: "user",
    authorDisplayName: "Nishant Gautam",
    authorUsername: "@nishant",
    authorPhotoUrl: "https://example.com/avatar.jpg",
    authorCategoryLabel: "Pet Parent",
    authorCity: "Mumbai",
    authorState: "Maharashtra",
    imageUrls: [
      "https://firebasestorage.googleapis.com/v0/b/pettexo/o/socialPosts%2Fuser_123%2Fpost_123%2Fimages%2F0.jpg",
    ],
    thumbnailUrls: [
      "https://firebasestorage.googleapis.com/v0/b/pettexo/o/socialPosts%2Fuser_123%2Fpost_123%2Fthumbs%2F0.jpg",
    ],
    imageAspectRatio: "square",
    caption: "hello",
    hashtags: ["pets"],
    likeCount: 0,
    commentCount: 0,
    shareCount: 0,
    reportCount: 0,
    visibilityStatus: "visible",
    moderationStatus: "approved",
    createdAtEpoch: 1765219200000,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

const omissionSafeDefaults = {
  isAdminPost: false,
  adminPriorityBoost: 0,
  recentEngagementScore: 0,
  saveCount: 0,
  moderationReason: "",
  moderatedBy: "",
  moderatedAt: null,
  lastReportedAt: null,
  discoverScore: 0,
  discoverRankVersion: 0,
  discoverScoreUpdatedAt: null,
  discoverEligible: false,
  nearbyEligible: false,
  feedGeohash3: "",
  feedGeohash4: "",
  feedGeohash5: "",
  feedLocationVersion: 0,
  feedLocationUpdatedAt: null,
  feedCityKey: "",
  feedStateKey: "",
};

test("social post create accepts runtime payload without backend-owned feed defaults", async () => {
  const testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { rules },
  });

  try {
    const uid = "user_123";

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users", uid), {
        uid,
        accountStatus: "active",
      });
    });

    const payload = buildRuntimePayload(uid, "post_runtime_payload");
    await assertSucceeds(
      setDoc(
        doc(
          testEnv.authenticatedContext(uid).firestore(),
          "socialPosts",
          payload.id,
        ),
        payload,
      ),
    );
  } finally {
    await testEnv.cleanup();
  }
});

test("social post create keeps non-backend omission-safe defaults optional", async () => {
  const testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { rules },
  });

  try {
    const uid = "user_123";

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users", uid), {
        uid,
        accountStatus: "active",
      });
    });

    const fields = [
      "isAdminPost",
      "adminPriorityBoost",
      "recentEngagementScore",
      "saveCount",
      "moderationReason",
      "moderatedBy",
      "moderatedAt",
      "lastReportedAt",
    ];

    for (const field of fields) {
      const payload = {
        ...buildRuntimePayload(uid, `post_${field}`),
        ...omissionSafeDefaults,
      };
      delete payload[field];

      await assertSucceeds(
        setDoc(
          doc(
            testEnv.authenticatedContext(uid).firestore(),
            "socialPosts",
            payload.id,
          ),
          payload,
        ),
      );
    }
  } finally {
    await testEnv.cleanup();
  }
});

test("social post create rejects backend-owned feed defaults if client writes non-defaults", async () => {
  const testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { rules },
  });

  try {
    const uid = "user_123";

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users", uid), {
        uid,
        accountStatus: "active",
      });
    });

    const payload = {
      ...buildRuntimePayload(uid, "post_bad_discover_score"),
      discoverScore: 5,
    };

    await assertFails(
      setDoc(
        doc(
          testEnv.authenticatedContext(uid).firestore(),
          "socialPosts",
          payload.id,
        ),
        payload,
      ),
    );
  } finally {
    await testEnv.cleanup();
  }
});

test("social post create still rejects another user's authorId", async () => {
  const testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { rules },
  });

  try {
    const uid = "user_123";
    const otherUid = "user_456";

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users", uid), {
        uid,
        accountStatus: "active",
      });
      await setDoc(doc(context.firestore(), "users", otherUid), {
        uid: otherUid,
        accountStatus: "active",
      });
    });

    const payload = buildRuntimePayload(otherUid, "post_wrong_author");
    payload.authorId = otherUid;

    await assertFails(
      setDoc(
        doc(
          testEnv.authenticatedContext(uid).firestore(),
          "socialPosts",
          payload.id,
        ),
        payload,
      ),
    );
  } finally {
    await testEnv.cleanup();
  }
});

test("social post create regex keeps backend-owned feed defaults omission-safe", () => {
  assert.match(
    rules,
    /function safeSocialPostCreate\(\)\s*\{[\s\S]*!request\.resource\.data\.keys\(\)\.hasAny\(\['discoverScore'\]\)\s*\|\|\s*request\.resource\.data\.discoverScore == 0[\s\S]*!request\.resource\.data\.keys\(\)\.hasAny\(\['discoverRankVersion'\]\)\s*\|\|\s*request\.resource\.data\.discoverRankVersion == 0[\s\S]*!request\.resource\.data\.keys\(\)\.hasAny\(\['discoverScoreUpdatedAt'\]\)\s*\|\|\s*request\.resource\.data\.discoverScoreUpdatedAt == null[\s\S]*!request\.resource\.data\.keys\(\)\.hasAny\(\['discoverEligible'\]\)\s*\|\|\s*request\.resource\.data\.discoverEligible == false[\s\S]*!request\.resource\.data\.keys\(\)\.hasAny\(\['nearbyEligible'\]\)\s*\|\|\s*request\.resource\.data\.nearbyEligible == false[\s\S]*!request\.resource\.data\.keys\(\)\.hasAny\(\['feedGeohash3'\]\)\s*\|\|\s*request\.resource\.data\.feedGeohash3 == ''[\s\S]*!request\.resource\.data\.keys\(\)\.hasAny\(\['feedGeohash4'\]\)\s*\|\|\s*request\.resource\.data\.feedGeohash4 == ''[\s\S]*!request\.resource\.data\.keys\(\)\.hasAny\(\['feedGeohash5'\]\)\s*\|\|\s*request\.resource\.data\.feedGeohash5 == ''[\s\S]*!request\.resource\.data\.keys\(\)\.hasAny\(\['feedLocationVersion'\]\)\s*\|\|\s*request\.resource\.data\.feedLocationVersion == 0[\s\S]*!request\.resource\.data\.keys\(\)\.hasAny\(\['feedLocationUpdatedAt'\]\)\s*\|\|\s*request\.resource\.data\.feedLocationUpdatedAt == null[\s\S]*!request\.resource\.data\.keys\(\)\.hasAny\(\['feedCityKey'\]\)\s*\|\|\s*request\.resource\.data\.feedCityKey == ''[\s\S]*!request\.resource\.data\.keys\(\)\.hasAny\(\['feedStateKey'\]\)\s*\|\|\s*request\.resource\.data\.feedStateKey == ''/s,
  );
});
