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

test("userBlocks are readable by either participant but backend-only for mutations", () => {
  const block = rules.match(/match \/userBlocks\/\{blockId\}\s*\{([\s\S]*?)\n {4}\}\n/);
  assert.ok(block, "userBlocks match block not found");
  const body = block[1];

  // List: only queries constrained to the caller as owner or blocked user.
  assert.match(
    body,
    /allow list: if signedIn\(\) &&\s*\(\s*resource\.data\.ownerUserId == request\.auth\.uid \|\|\s*resource\.data\.blockedUserId == request\.auth\.uid\s*\);/,
  );
  // Get: a missing well-formed {a}_{b} pair doc for either party (Phase 3C-8),
  // or an existing doc where the caller is owner or blocked user.
  assert.match(
    body,
    /allow get: if signedIn\(\) &&\s*\(\s*\(\s*resource == null &&\s*blockId\.matches\('\^\[\^_\]\+_\[\^_\]\+\$'\) &&\s*request\.auth\.uid in blockId\.split\('_'\)\s*\) \|\|\s*\(\s*resource\.data\.ownerUserId == request\.auth\.uid \|\|\s*resource\.data\.blockedUserId == request\.auth\.uid\s*\)\s*\);/,
  );
  // Mutations stay backend-only, and no other allow statement exists.
  assert.match(body, /allow create, update, delete: if false;/);
  assert.deepEqual(
    body.match(/^\s*allow [^:]+:/gm).map((line) => line.trim()),
    ["allow list:", "allow get:", "allow create, update, delete:"],
  );
});

test("userMutes rules keep reads owner-only and preserve create/delete restrictions", () => {
  assert.match(
    rules,
    /match \/userMutes\/\{muteId\}\s*\{[\s\S]*allow get: if signedIn\(\) && resource\.data\.ownerUserId == request\.auth\.uid;[\s\S]*allow list: if signedIn\(\) && resource\.data\.ownerUserId == request\.auth\.uid;[\s\S]*allow create: if requesterAccountIsActive\(\) &&[\s\S]*request\.resource\.data\.ownerUserId == request\.auth\.uid[\s\S]*request\.resource\.data\.mutedUserId is string[\s\S]*request\.resource\.data\.mutedUserId != request\.auth\.uid[\s\S]*request\.resource\.id == \(request\.resource\.data\.ownerUserId \+ '_' \+ request\.resource\.data\.mutedUserId\)[\s\S]*allow delete: if requesterAccountIsActive\(\) &&[\s\S]*resource\.data\.ownerUserId == request\.auth\.uid;[\s\S]*allow update: if false;/,
  );
});

test("Explore viewer context loads effective bilateral blocks and owner-scoped mutes", () => {
  assert.match(
    exploreRepository,
    /BlockedRelationshipRepository\(firestore: _firestore, auth: _auth\)/,
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
