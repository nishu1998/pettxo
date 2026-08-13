const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const rulesPath = path.resolve(__dirname, "../../storage.rules");
const rules = fs.readFileSync(rulesPath, "utf8");

test("offer wall storage path restricts writes to superAdmin and financeAdmin only", () => {
  assert.match(
    rules,
    /function canManageOfferWalls\(\)\s*\{[\s\S]*adminRole in \["superAdmin", "financeAdmin"\];[\s\S]*\}/s,
  );
  assert.match(
    rules,
    /match \/offerWalls\/\{campaignId\}\/\{fileName\}\s*\{[\s\S]*allow create, update: if canManageOfferWalls\(\) &&[\s\S]*isSupportedOfferWallImage\(fileName\) &&[\s\S]*isMaxFiveMb\(\);/s,
  );
  assert.match(
    rules,
    /match \/offerWalls\/\{campaignId\}\/\{fileName\}\s*\{[\s\S]*allow delete: if canManageOfferWalls\(\);/s,
  );
});

test("offer wall storage path allows authenticated reads only", () => {
  assert.match(
    rules,
    /match \/offerWalls\/\{campaignId\}\/\{fileName\}\s*\{[\s\S]*allow read: if signedIn\(\);/s,
  );
});

test("offer wall storage path accepts supported image MIME types or supported file extensions", () => {
  assert.match(
    rules,
    /function isSupportedOfferWallImage\(fileName\)\s*\{[\s\S]*return isSupportedImage\(\) \|\| hasSupportedImageExtension\(fileName\);[\s\S]*\}/s,
  );
  assert.match(
    rules,
    /function hasSupportedImageExtension\(fileName\)\s*\{[\s\S]*fileName\.matches\('\(\?i\)\.\+\\\\\.\(jpg\|jpeg\|png\|webp\)\$'\);[\s\S]*\}/s,
  );
});
