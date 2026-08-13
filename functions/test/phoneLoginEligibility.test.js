const test = require("node:test");
const assert = require("node:assert/strict");

const {
  normalizePhoneLoginNumber,
  validatePhoneLoginNumber,
  evaluatePhoneLoginEligibility,
} = require("../lib/phoneLoginEligibility.js");

test("normalizePhoneLoginNumber trims input", () => {
  assert.equal(normalizePhoneLoginNumber("  +919876543210 "), "+919876543210");
});

test("validatePhoneLoginNumber rejects missing and malformed values", () => {
  assert.equal(validatePhoneLoginNumber(""), "Phone number is required.");
  assert.equal(
    validatePhoneLoginNumber("9876543210"),
    "Enter a valid phone number.",
  );
  assert.equal(validatePhoneLoginNumber("+919876543210"), null);
});

test("evaluatePhoneLoginEligibility approves complete active accounts", () => {
  assert.equal(
    evaluatePhoneLoginEligibility({
      disabled: false,
      accountStatus: "active",
      hasPublicProfile: true,
      hasPrivateProfile: true,
      hasCompletedPublicProfile: true,
    }),
    "active",
  );
});

test("evaluatePhoneLoginEligibility returns blocked, recovery, and incomplete states", () => {
  assert.equal(
    evaluatePhoneLoginEligibility({
      disabled: true,
      accountStatus: "active",
      hasPublicProfile: true,
      hasPrivateProfile: true,
      hasCompletedPublicProfile: true,
    }),
    "blocked",
  );
  assert.equal(
    evaluatePhoneLoginEligibility({
      disabled: false,
      accountStatus: "restricted",
      hasPublicProfile: true,
      hasPrivateProfile: true,
      hasCompletedPublicProfile: true,
    }),
    "blocked",
  );
  assert.equal(
    evaluatePhoneLoginEligibility({
      disabled: false,
      accountStatus: "pendingDeletion",
      hasPublicProfile: true,
      hasPrivateProfile: true,
      hasCompletedPublicProfile: true,
    }),
    "accountRecoveryRequired",
  );
  assert.equal(
    evaluatePhoneLoginEligibility({
      disabled: false,
      accountStatus: "active",
      hasPublicProfile: false,
      hasPrivateProfile: true,
      hasCompletedPublicProfile: false,
    }),
    "incompleteSignup",
  );
  assert.equal(
    evaluatePhoneLoginEligibility({
      disabled: false,
      accountStatus: "active",
      hasPublicProfile: true,
      hasPrivateProfile: false,
      hasCompletedPublicProfile: false,
    }),
    "incompleteSignup",
  );
});

test("evaluatePhoneLoginEligibility allows completed public profiles while private repair catches up", () => {
  assert.equal(
    evaluatePhoneLoginEligibility({
      disabled: false,
      accountStatus: "active",
      hasPublicProfile: true,
      hasPrivateProfile: false,
      hasCompletedPublicProfile: true,
    }),
    "active",
  );
});
