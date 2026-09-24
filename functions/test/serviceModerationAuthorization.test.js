const test = require("node:test");
const assert = require("node:assert/strict");

const {
  canModerateService,
  isServiceModerationAction,
} = require("../lib/moderation/serviceModerationAuthorization.js");

test("service moderation permits support and super admin roles", () => {
  assert.equal(canModerateService("customerSupportAdmin"), true);
  assert.equal(canModerateService("superAdmin"), true);
});

test("service moderation denies finance and untrusted roles", () => {
  assert.equal(canModerateService("financeAdmin"), false);
  assert.equal(canModerateService("serviceProvider"), false);
  assert.equal(canModerateService(""), false);
});

test("service moderation accepts only explicit approve and remove actions", () => {
  assert.equal(isServiceModerationAction("approve"), true);
  assert.equal(isServiceModerationAction("remove"), true);
  assert.equal(isServiceModerationAction("reject"), false);
  assert.equal(isServiceModerationAction(""), false);
});
