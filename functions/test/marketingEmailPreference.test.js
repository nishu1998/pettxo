const test = require("node:test");
const assert = require("node:assert/strict");

const {
  marketingEmailPreferencePatch,
  resolveSignupTermsCommunicationsContract,
  signupMarketingEmailPreferencePatch,
  signupTermsCommunicationsPolicyVersion,
} = require("../lib/marketingEmail/marketingEmailDomain.js");

test("onboarding compatibility distinguishes absent, current, and invalid policy versions", () => {
  assert.equal(resolveSignupTermsCommunicationsContract({}), "legacy");
  assert.equal(
    resolveSignupTermsCommunicationsContract({
      termsCommunicationsPolicyVersion: signupTermsCommunicationsPolicyVersion,
    }),
    "current",
  );
  assert.throws(
    () => resolveSignupTermsCommunicationsContract({termsCommunicationsPolicyVersion: ""}),
    {code: "failed-precondition"},
  );
  assert.throws(
    () => resolveSignupTermsCommunicationsContract({termsCommunicationsPolicyVersion: "future_version"}),
    {code: "failed-precondition"},
  );
});

test("current disclosed signup initializes marketing with authoritative metadata", () => {
  const timestamp = {server: true};
  assert.deepEqual(
    signupMarketingEmailPreferencePatch({}, signupTermsCommunicationsPolicyVersion, timestamp),
    {
      marketingEmailEnabled: true,
      marketingEmailPreferenceSource: "signup",
      marketingEmailPreferenceUpdatedAt: timestamp,
      marketingEmailSignupPolicyVersion: signupTermsCommunicationsPolicyVersion,
    },
  );
});

test("signup initialization rejects stale consent and preserves every explicit preference", () => {
  assert.throws(
    () => signupMarketingEmailPreferencePatch({}, "older_terms", {}),
    {code: "failed-precondition"},
  );
  assert.deepEqual(
    signupMarketingEmailPreferencePatch(
      {marketingEmailEnabled: false, marketingEmailPreferenceSource: "unsubscribe"},
      signupTermsCommunicationsPolicyVersion,
      {},
    ),
    {},
  );
  assert.deepEqual(
    signupMarketingEmailPreferencePatch(
      {marketingEmailEnabled: true, marketingEmailPreferenceSource: "settings"},
      signupTermsCommunicationsPolicyVersion,
      {},
    ),
    {},
  );
});

test("settings and unsubscribe patches have server-selected sources and timestamps", () => {
  const timestamp = {server: true};
  assert.deepEqual(marketingEmailPreferencePatch(false, "settings", timestamp), {
    marketingEmailEnabled: false,
    marketingEmailPreferenceSource: "settings",
    marketingEmailPreferenceUpdatedAt: timestamp,
  });
  assert.deepEqual(marketingEmailPreferencePatch(false, "unsubscribe", timestamp), {
    marketingEmailEnabled: false,
    marketingEmailPreferenceSource: "unsubscribe",
    marketingEmailPreferenceUpdatedAt: timestamp,
  });
});
