const test = require("node:test");
const assert = require("node:assert/strict");

const {
  requestPasswordResetV2,
  sendVerificationEmailV2,
  sendWelcomeEmailOnUserCreated,
} = require("../lib/index.js");

const {
  processMarketingEmailCampaignsV3,
  sendMarketingEmailCampaignTestV3,
} = require("../lib/index.js");

for (const [name, callable] of Object.entries({
  requestPasswordResetV2,
  sendVerificationEmailV2,
})) {
  test(`${name} is Gen 2 in asia-south1 with RESEND_API_KEY bound`, () => {
    const endpoint = callable.__endpoint;
    assert.equal(endpoint.platform, "gcfv2");
    assert.deepEqual(endpoint.region, ["asia-south1"]);
    assert.deepEqual(endpoint.secretEnvironmentVariables, [
      {key: "RESEND_API_KEY"},
    ]);
    assert.deepEqual(endpoint.callableTrigger, {});
  });
}

test("welcome email is a retrying canonical-user create trigger with secret bound", () => {
  const endpoint = sendWelcomeEmailOnUserCreated.__endpoint;
  assert.equal(endpoint.platform, "gcfv2");
  assert.deepEqual(endpoint.region, ["asia-south1"]);
  assert.deepEqual(endpoint.secretEnvironmentVariables, [
    {key: "RESEND_API_KEY"},
  ]);
  assert.equal(
    endpoint.eventTrigger.eventType,
    "google.cloud.firestore.document.v1.created",
  );
  assert.equal(
    endpoint.eventTrigger.eventFilterPathPatterns.document,
    "users/{uid}",
  );
  assert.equal(endpoint.eventTrigger.retry, true);
});

test("marketing send surfaces bind only the marketing Resend secret", () => {
  assert.deepEqual(
    sendMarketingEmailCampaignTestV3.__endpoint.secretEnvironmentVariables,
    [{key: "RESEND_MARKETING_API_KEY"}],
  );
  assert.deepEqual(
    processMarketingEmailCampaignsV3.__endpoint.secretEnvironmentVariables,
    [{key: "RESEND_MARKETING_API_KEY"}],
  );
});
