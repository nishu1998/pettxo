const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const rulesPath = path.resolve(__dirname, "../../storage.rules");
const rules = fs.readFileSync(rulesPath, "utf8");

test("social post storage paths allow owner create and update for images and thumbs", () => {
  assert.match(
    rules,
    /match \/socialPosts\/\{userId\}\/\{postId\}\/\{folder\}\/\{fileName\}\s*\{[\s\S]*allow create, update: if isOwner\(userId\) &&[\s\S]*folder in \['images', 'thumbs'\] &&[\s\S]*isSupportedImage\(\) &&[\s\S]*isMaxFiveMb\(\);/s,
  );
});

test("social post storage paths allow only the owner to delete failed uploads", () => {
  assert.match(
    rules,
    /match \/socialPosts\/\{userId\}\/\{postId\}\/\{folder\}\/\{fileName\}\s*\{[\s\S]*allow delete: if isOwner\(userId\) &&[\s\S]*folder in \['images', 'thumbs'\];/s,
  );
});
