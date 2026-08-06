const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const rulesPath = path.resolve(__dirname, "../../firestore.rules");
const exploreRepositoryPath = path.resolve(
  __dirname,
  "../../lib/features/explore/data/explore_viewer_context_repository.dart",
);

const rules = fs.readFileSync(rulesPath, "utf8");
const exploreRepository = fs.readFileSync(exploreRepositoryPath, "utf8");

test("userBlocks rules keep reads owner-only and preserve create/delete restrictions", () => {
  assert.match(
    rules,
    /match \/userBlocks\/\{blockId\}\s*\{[\s\S]*allow get: if signedIn\(\) && resource\.data\.ownerUserId == request\.auth\.uid;[\s\S]*allow list: if signedIn\(\) && resource\.data\.ownerUserId == request\.auth\.uid;[\s\S]*allow create: if requesterAccountIsActive\(\) &&[\s\S]*request\.resource\.data\.ownerUserId == request\.auth\.uid[\s\S]*request\.resource\.data\.blockedUserId is string[\s\S]*request\.resource\.data\.blockedUserId != request\.auth\.uid[\s\S]*request\.resource\.id == \(request\.resource\.data\.ownerUserId \+ '_' \+ request\.resource\.data\.blockedUserId\)[\s\S]*allow delete: if requesterAccountIsActive\(\) &&[\s\S]*resource\.data\.ownerUserId == request\.auth\.uid;[\s\S]*allow update: if false;/,
  );
});

test("userMutes rules keep reads owner-only and preserve create/delete restrictions", () => {
  assert.match(
    rules,
    /match \/userMutes\/\{muteId\}\s*\{[\s\S]*allow get: if signedIn\(\) && resource\.data\.ownerUserId == request\.auth\.uid;[\s\S]*allow list: if signedIn\(\) && resource\.data\.ownerUserId == request\.auth\.uid;[\s\S]*allow create: if requesterAccountIsActive\(\) &&[\s\S]*request\.resource\.data\.ownerUserId == request\.auth\.uid[\s\S]*request\.resource\.data\.mutedUserId is string[\s\S]*request\.resource\.data\.mutedUserId != request\.auth\.uid[\s\S]*request\.resource\.id == \(request\.resource\.data\.ownerUserId \+ '_' \+ request\.resource\.data\.mutedUserId\)[\s\S]*allow delete: if requesterAccountIsActive\(\) &&[\s\S]*resource\.data\.ownerUserId == request\.auth\.uid;[\s\S]*allow update: if false;/,
  );
});

test("Explore viewer context queries blocks and mutes by ownerUserId only", () => {
  assert.match(
    exploreRepository,
    /collection: 'userBlocks'[\s\S]*ownerField: 'ownerUserId'[\s\S]*targetField: 'blockedUserId'[\s\S]*ownerUserId: currentUserId/,
  );
  assert.match(
    exploreRepository,
    /collection: 'userMutes'[\s\S]*ownerField: 'ownerUserId'[\s\S]*targetField: 'mutedUserId'[\s\S]*ownerUserId: currentUserId/,
  );
  assert.match(
    exploreRepository,
    /\.collection\(collection\)\s*\.where\(ownerField, isEqualTo: ownerUserId\)\s*\.get\(\)/,
  );
});
