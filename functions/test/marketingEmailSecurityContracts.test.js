const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const firestoreRules = fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8");
const storageRules = fs.readFileSync(path.resolve(__dirname, "../../storage.rules"), "utf8");
const functionsSource = fs.readFileSync(path.resolve(__dirname, "../src/marketingEmail/marketingEmailFunctions.ts"), "utf8");
const domainSource = fs.readFileSync(path.resolve(__dirname, "../src/marketingEmail/marketingEmailDomain.ts"), "utf8");
const authTransport = fs.readFileSync(path.resolve(__dirname, "../src/email/authEmailTransport.ts"), "utf8");

test("marketing Firestore records are denied to all clients", () => {
  for (const collection of ["marketingCampaigns", "marketingCampaignExecutions", "marketingUnsubscribeTokens", "marketingEmailTestRateLimits"]) {
    assert.match(firestoreRules, new RegExp(`match /${collection}`));
  }
  assert.match(firestoreRules, /match \/marketingCampaigns\/\{campaignId\}[\s\S]*allow read, write: if false;[\s\S]*match \/deliveries\/\{deliveryId\}[\s\S]*allow read, write: if false;/s);
});

test("preference is callable-owned and can only alter the authenticated private profile", () => {
  assert.match(functionsSource, /const uid = requireUid\(request\.auth\?\.uid\);[\s\S]*collection\("userPrivate"\)\.doc\(uid\)\.set/s);
  assert.doesNotMatch(functionsSource, /request\.data\?\.uid/);
  assert.match(functionsSource, /marketingEmailPreferencePatch\(request\.data\.enabled, "settings", FieldValue\.serverTimestamp\(\)\)/);
  assert.match(domainSource, /marketingEmailEnabled: enabled/);
  assert.doesNotMatch(firestoreRules.match(/function safeUserPrivateOwnerUpdate[\s\S]*?\n    \}/s)?.[0] ?? "", /marketingEmailEnabled/);
});

test("marketing image path is public-get, non-listable, and superAdmin-only image write", () => {
  assert.match(storageRules, /function canManageMarketingCampaigns\(\)[\s\S]*adminRole == "superAdmin"/s);
  assert.match(storageRules, /match \/marketingCampaigns\/\{campaignId\}\/\{fileName\}[\s\S]*allow get: if true;[\s\S]*allow list: if false;[\s\S]*allow create, update: if canManageMarketingCampaigns\(\)[\s\S]*isSupportedImage\(\)[\s\S]*isMaxFiveMb\(\)/s);
});

test("marketing and transactional Resend credentials and senders remain separate", () => {
  assert.match(functionsSource, /RESEND_MARKETING_API_KEY/);
  assert.doesNotMatch(functionsSource, /\bRESEND_API_KEY\b/);
  assert.match(authTransport, /Pettxo <no-reply@pettxo\.com>/);
  assert.doesNotMatch(authTransport, /RESEND_MARKETING_API_KEY/);
});

test("delivery is bounded, retry-safe, and uses stable provider idempotency", () => {
  assert.match(functionsSource, /const batchSize = 25;/);
  assert.match(functionsSource, /stableMarketingId\("marketing-delivery", campaign\.campaignId, profileSnapshot\.id\)/);
  assert.match(functionsSource, /attemptCount:[\s\S]*attempts \+ 1/);
  assert.match(functionsSource, /terminal = reservation\.attempts >= 3/);
});

test("unsubscribe is opaque, hashed at rest, idempotent, and marketing-only", () => {
  assert.match(functionsSource, /randomBytes\(32\)\.toString\("base64url"\)/);
  assert.match(functionsSource, /unsubscribeTokens\.doc\(sha256\(token\)\)/);
  assert.match(functionsSource, /marketingEmailPreferencePatch\(false, "unsubscribe", FieldValue\.serverTimestamp\(\)\)/);
  assert.doesNotMatch(functionsSource, /emailVerified: false|disabled: true/);
  assert.match(functionsSource, /transaction\.set\(ref, \{usedAt:/);
  assert.doesNotMatch(functionsSource, /tokenLifetimeMs|expiresAt\.toMillis\(\)/);
  assert.match(functionsSource, /durableMarketingUnsubscribeUid\(snapshot\.exists, data\)/);
});

test("admin test-send remains bound to the authenticated admin canonical email", () => {
  assert.match(functionsSource, /const authUser = await loadAuthUser\(actor\.uid\)/);
  assert.match(functionsSource, /to: email/);
  assert.doesNotMatch(
    functionsSource.match(/export const sendMarketingEmailCampaignTestV3[\s\S]*?async function queueCampaign/)?.[0] ?? "",
    /recipientEmail|classifyMarketingEligibility/,
  );
});

test("permanent account deletion removes durable unsubscribe lookup records", () => {
  const legacySource = fs.readFileSync(path.resolve(__dirname, "../src/legacyFunctions.ts"), "utf8");
  assert.match(
    legacySource,
    /collection\("marketingUnsubscribeTokens"\)\.where\("uid", "==", uid\)/,
  );
});
