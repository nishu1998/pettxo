const test = require("node:test");
const assert = require("node:assert/strict");

const {
  assertMarketingAdminRole,
  canTransitionMarketingCampaign,
  classifyMarketingEligibility,
  durableMarketingUnsubscribeUid,
  isMarketingUnsubscribeToken,
  normalizeMarketingAudience,
  normalizeMarketingCampaignInput,
  stableMarketingId,
} = require("../lib/marketingEmail/marketingEmailDomain.js");
const {renderMarketingEmail} = require("../lib/marketingEmail/marketingEmailTemplate.js");

const content = {
  subject: "Pettxo update",
  preheader: "A short preview",
  heading: "Hello pets",
  body: "First line\nSecond line",
  imageUrl: "",
  ctaText: "Open Pettxo",
  ctaDestination: "https://pettxo.com/app",
};

test("marketing authorization permits only an authenticated superAdmin", () => {
  assert.doesNotThrow(() => assertMarketingAdminRole("admin", "superAdmin"));
  assert.throws(() => assertMarketingAdminRole("", "superAdmin"), {code: "unauthenticated"});
  assert.throws(() => assertMarketingAdminRole("finance", "financeAdmin"), {code: "permission-denied"});
  assert.throws(() => assertMarketingAdminRole("support", "customerSupportAdmin"), {code: "permission-denied"});
});

test("draft validation accepts structured content and rejects recipient emails or unsafe CTA", () => {
  const valid = normalizeMarketingCampaignInput({internalName: "October", content, audience: {mode: "all"}});
  assert.equal(valid.content.subject, "Pettxo update");
  assert.throws(() => normalizeMarketingCampaignInput({...valid, recipientEmails: ["outside@example.com"]}));
  assert.throws(() => normalizeMarketingCampaignInput({internalName: "x", content: {...content, ctaDestination: "javascript:alert(1)"}, audience: {mode: "all"}}));
  assert.throws(() => normalizeMarketingCampaignInput({internalName: "x", content: {...content, ctaText: ""}, audience: {mode: "all"}}));
  assert.throws(() => normalizeMarketingCampaignInput({internalName: "x", content: {...content, subject: "Hello\r\nBcc: bad@example.com"}, audience: {mode: "all"}}));
});

test("audience supports roles, locations, combinations, selected UIDs, and deduplication", () => {
  assert.equal(normalizeMarketingAudience({mode: "role", role: "petParent"}).role, "petParent");
  assert.equal(normalizeMarketingAudience({mode: "state", state: "Maharashtra"}).state, "Maharashtra");
  assert.equal(normalizeMarketingAudience({mode: "city", city: "Pune"}).city, "Pune");
  assert.equal(normalizeMarketingAudience({mode: "roleCity", role: "serviceProvider", city: "Pune"}).mode, "roleCity");
  assert.deepEqual(normalizeMarketingAudience({mode: "selected", selectedUids: ["a", "a", "b"]}).selectedUids, ["a", "b"]);
  assert.throws(() => normalizeMarketingAudience({mode: "selected", selectedUids: ["person@example.com"]}));
});

test("audience matching handles all, pet parents, providers, state, city, and combinations", () => {
  const {marketingAudienceMatches} = require("../lib/marketingEmail/marketingEmailDomain.js");
  const profile = {role: "serviceProvider", state: "Maharashtra", city: "Pune"};
  const audience = (mode, extra = {}) => ({mode, role: "", state: "", city: "", selectedUids: [], ...extra});
  assert.equal(marketingAudienceMatches("u1", profile, audience("all")), true);
  assert.equal(marketingAudienceMatches("u1", profile, audience("role", {role: "serviceProvider"})), true);
  assert.equal(marketingAudienceMatches("u1", profile, audience("role", {role: "petParent"})), false);
  assert.equal(marketingAudienceMatches("u1", profile, audience("state", {state: "maharashtra"})), true);
  assert.equal(marketingAudienceMatches("u1", profile, audience("city", {city: "pune"})), true);
  assert.equal(marketingAudienceMatches("u1", profile, audience("roleCity", {role: "serviceProvider", city: "Pune"})), true);
});

test("eligibility uses Auth email and conservatively requires explicit marketing opt-in", () => {
  const base = {uid: "u1", profileExists: true, profile: {role: "petParent", state: "Maharashtra", city: "Pune"}, privateProfile: {marketingEmailEnabled: true}, authUser: {email: "Person@Example.com", disabled: false}, audience: {mode: "all", role: "", state: "", city: "", selectedUids: []}};
  assert.deepEqual(classifyMarketingEligibility(base), {category: "eligible", email: "person@example.com"});
  assert.equal(classifyMarketingEligibility({...base, privateProfile: {}}).category, "marketingOptedOut");
  assert.equal(classifyMarketingEligibility({...base, authUser: {disabled: false}}).category, "noCanonicalEmail");
  assert.equal(classifyMarketingEligibility({...base, authUser: {...base.authUser, disabled: true}}).category, "otherExclusion");
  assert.equal(classifyMarketingEligibility({...base, privateProfile: {...base.privateProfile, scheduledDeletionAt: {}}}).category, "otherExclusion");
  assert.equal(classifyMarketingEligibility({...base, privateProfile: {...base.privateProfile, accountStatus: "pendingDeletion"}}).category, "otherExclusion");
  assert.equal(classifyMarketingEligibility({...base, profile: {...base.profile, accountStatus: "deleted"}}).category, "otherExclusion");
  assert.equal(classifyMarketingEligibility({...base, privateProfile: {marketingEmailEnabled: false}}).category, "marketingOptedOut");
  assert.equal(classifyMarketingEligibility({...base, uid: "missing", profileExists: false, profile: {}, audience: {mode: "selected", role: "", state: "", city: "", selectedUids: ["missing"]}}).category, "otherExclusion");
});

test("campaign state machine blocks editing/resending after execution begins", () => {
  assert.equal(canTransitionMarketingCampaign("DRAFT", "SCHEDULED"), true);
  assert.equal(canTransitionMarketingCampaign("DRAFT", "QUEUED"), true);
  assert.equal(canTransitionMarketingCampaign("SCHEDULED", "CANCELLED"), true);
  assert.equal(canTransitionMarketingCampaign("QUEUED", "SENDING"), true);
  assert.equal(canTransitionMarketingCampaign("SENDING", "COMPLETED"), true);
  assert.equal(canTransitionMarketingCampaign("COMPLETED", "QUEUED"), false);
});

test("marketing HTML escapes content and includes CTA and unsubscribe", () => {
  const html = renderMarketingEmail({content: {...content, heading: '<img onerror="bad">', body: "Hi <script>bad()</script>"}, unsubscribeUrl: "https://example.com/unsubscribe?token=abc"});
  assert.match(html, /&lt;img onerror=&quot;bad&quot;&gt;/);
  assert.equal(html.includes("<script>bad()</script>"), false);
  assert.match(html, /Open Pettxo/);
  assert.match(html, /Unsubscribe from marketing emails/);
  assert.match(html, /token=abc/);
});

test("logical execution and delivery identifiers are deterministic and non-sensitive", () => {
  const one = stableMarketingId("delivery", "campaign", "uid");
  assert.equal(one, stableMarketingId("delivery", "campaign", "uid"));
  assert.equal(one.includes("uid"), false);
  assert.notEqual(one, stableMarketingId("delivery", "campaign", "uid-2"));
});

test("unsubscribe tokens are durable, opaque, and exact 32-byte base64url values", () => {
  const validToken = "A".repeat(43);
  assert.equal(isMarketingUnsubscribeToken(validToken), true);
  assert.equal(isMarketingUnsubscribeToken("A".repeat(42)), false);
  assert.equal(isMarketingUnsubscribeToken(`${"A".repeat(42)}+`), false);

  assert.equal(durableMarketingUnsubscribeUid(true, {uid: "user-1"}), "user-1");
  assert.equal(
    durableMarketingUnsubscribeUid(true, {
      uid: "user-1",
      // A legacy expiry value must no longer invalidate a legitimate link.
      expiresAt: new Date(0),
    }),
    "user-1",
  );
  assert.equal(durableMarketingUnsubscribeUid(false, {uid: "user-1"}), "");
  assert.equal(durableMarketingUnsubscribeUid(true, {}), "");
});
