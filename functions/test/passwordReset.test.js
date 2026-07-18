const test = require("node:test");
const assert = require("node:assert/strict");

const {
  normalizePasswordResetEmail,
  validatePasswordResetEmail,
  evaluatePasswordResetEligibility,
} = require("../lib/passwordReset.js");

test("normalizePasswordResetEmail trims and lowercases", () => {
  assert.equal(
    normalizePasswordResetEmail("  Person@Example.COM "),
    "person@example.com",
  );
});

test("validatePasswordResetEmail rejects malformed email", () => {
  assert.equal(validatePasswordResetEmail(""), "Email is required.");
  assert.equal(
    validatePasswordResetEmail("not-an-email"),
    "Enter a valid email address.",
  );
  assert.equal(validatePasswordResetEmail("person@example.com"), null);
});

test("evaluatePasswordResetEligibility approves password accounts", () => {
  assert.equal(
    evaluatePasswordResetEligibility({
      providerIds: ["password"],
      disabled: false,
      accountStatus: "active",
    }),
    "approved",
  );
  assert.equal(
    evaluatePasswordResetEligibility({
      providerIds: ["password", "phone"],
      disabled: false,
      accountStatus: "active",
    }),
    "approved",
  );
});

test("evaluatePasswordResetEligibility rejects phone-only, disabled, and pending deletion accounts", () => {
  assert.equal(
    evaluatePasswordResetEligibility({
      providerIds: ["phone"],
      disabled: false,
      accountStatus: "active",
    }),
    "phoneOnlyAccount",
  );
  assert.equal(
    evaluatePasswordResetEligibility({
      providerIds: ["password"],
      disabled: true,
      accountStatus: "active",
    }),
    "accountDisabled",
  );
  assert.equal(
    evaluatePasswordResetEligibility({
      providerIds: ["password"],
      disabled: false,
      accountStatus: "pendingDeletion",
    }),
    "accountPendingDeletion",
  );
  assert.equal(
    evaluatePasswordResetEligibility({
      providerIds: ["password"],
      disabled: false,
      accountStatus: "deletionInProgress",
    }),
    "accountPendingDeletion",
  );
});
