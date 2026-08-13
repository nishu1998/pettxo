const test = require("node:test");
const assert = require("node:assert/strict");

const {
  isPersistedCompletedAccount,
} = require("../lib/identity/onboardingProfileUtils.js");

test("isPersistedCompletedAccount accepts a canonical completed account", () => {
  assert.equal(
    isPersistedCompletedAccount({
      uid: "uid_123",
      publicUser: {
        uid: "uid_123",
        role: "petParent",
        displayName: "Nishant",
        username: "nishant.pet",
        usernameLowercase: "nishant.pet",
        state: "Maharashtra",
        city: "Mumbai",
      },
    }),
    true,
  );
});

test("isPersistedCompletedAccount accepts legacy location fallback", () => {
  assert.equal(
    isPersistedCompletedAccount({
      uid: "uid_123",
      publicUser: {
        uid: "uid_123",
        role: "petParent",
        name: "Nishant",
        username: "nishant.pet",
        location: "Mumbai, Maharashtra",
      },
    }),
    true,
  );
});

test("isPersistedCompletedAccount rejects incomplete or mismatched profiles", () => {
  assert.equal(
    isPersistedCompletedAccount({
      uid: "uid_123",
      publicUser: {
        uid: "uid_other",
        role: "petParent",
        displayName: "Nishant",
        username: "nishant.pet",
        state: "Maharashtra",
        city: "Mumbai",
      },
    }),
    false,
  );

  assert.equal(
    isPersistedCompletedAccount({
      uid: "uid_123",
      publicUser: {
        uid: "uid_123",
        role: "",
        displayName: "Nishant",
        username: "nishant.pet",
        state: "Maharashtra",
        city: "Mumbai",
      },
    }),
    false,
  );
});
