const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const rulesPath = path.resolve(__dirname, "../../firestore.rules");
const rules = fs.readFileSync(rulesPath, "utf8");

test("social post private documents are fully denied to clients", () => {
  assert.match(
    rules,
    /match \/socialPostPrivate\/\{postId\}\s*\{\s*allow read, write: if false;\s*\}/s,
  );
});

test("nearby feed session documents are fully denied to clients", () => {
  assert.match(
    rules,
    /match \/nearbyFeedSessions\/\{sessionId\}\s*\{\s*allow read, write: if false;\s*\}/s,
  );
});

test("public social post create rules no longer expose raw location buckets", () => {
  assert.doesNotMatch(rules, /feedLatitudeBucket/);
  assert.doesNotMatch(rules, /feedLongitudeBucket/);
});

test("social post create rules allow omitted backend-owned authoring defaults", () => {
  assert.match(
    rules,
    /function safeSocialPostCreate\(\)\s*\{[\s\S]*!request\.resource\.data\.keys\(\)\.hasAny\(\['isAdminPost'\]\)\s*\|\|\s*request\.resource\.data\.isAdminPost == false[\s\S]*!request\.resource\.data\.keys\(\)\.hasAny\(\['adminPriorityBoost'\]\)\s*\|\|\s*request\.resource\.data\.adminPriorityBoost == 0[\s\S]*!request\.resource\.data\.keys\(\)\.hasAny\(\['recentEngagementScore'\]\)\s*\|\|\s*request\.resource\.data\.recentEngagementScore == 0/s,
  );
});
