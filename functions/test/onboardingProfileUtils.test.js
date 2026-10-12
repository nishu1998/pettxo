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

const officialUid = "Yo5HtRbusBNl9NkPhelXp5naNF93";
const officialProfile = {
  uid: officialUid,
  role: "petLover",
  displayName: "Pettxo",
  username: "pettxo",
  usernameLowercase: "pettxo",
  state: "Maharashtra",
  city: "Mumbai",
};

function officialOwnership(overrides = {}) {
  return {
    username: "pettxo",
    reservationExists: true,
    reservationUid: officialUid,
    authorizedByTrustedIdentity: true,
    ...overrides,
  };
}

test("official account is complete only with trusted matching canonical ownership", () => {
  const params = {
    uid: officialUid,
    publicUser: officialProfile,
    reservedUsernameOwnership: officialOwnership(),
  };

  assert.equal(isPersistedCompletedAccount(params), true);
  assert.equal(isPersistedCompletedAccount(params), true);
});

test("official account rejects missing or mismatched canonical ownership", () => {
  assert.equal(
    isPersistedCompletedAccount({
      uid: officialUid,
      publicUser: officialProfile,
    }),
    false,
  );
  assert.equal(
    isPersistedCompletedAccount({
      uid: officialUid,
      publicUser: officialProfile,
      reservedUsernameOwnership: officialOwnership({reservationExists: false}),
    }),
    false,
  );
  assert.equal(
    isPersistedCompletedAccount({
      uid: officialUid,
      publicUser: officialProfile,
      reservedUsernameOwnership: officialOwnership({reservationUid: "another_uid"}),
    }),
    false,
  );
});

test("official account rejects an identity not authorized by the backend", () => {
  assert.equal(
    isPersistedCompletedAccount({
      uid: officialUid,
      publicUser: officialProfile,
      reservedUsernameOwnership: officialOwnership({
        authorizedByTrustedIdentity: false,
      }),
    }),
    false,
  );
});

test("other reserved usernames remain protected even with a matching reservation", () => {
  assert.equal(
    isPersistedCompletedAccount({
      uid: "uid_123",
      publicUser: {...officialProfile, uid: "uid_123", username: "admin", usernameLowercase: "admin"},
      reservedUsernameOwnership: {
        username: "admin",
        reservationExists: true,
        reservationUid: "uid_123",
        authorizedByTrustedIdentity: true,
      },
    }),
    false,
  );
});
