require("./helpers/firebaseTestSafety").assertUnitTestIsolation();
const test = require("node:test");
const assert = require("node:assert/strict");

const {
  adminAccountIsInactive,
  requireActiveAdmin,
  requireActiveSuperAdmin,
} = require("../lib/admin/adminActor.js");

function fakeFirestore(users) {
  return {
    collection(name) {
      assert.equal(name, "users");
      return {
        doc(id) {
          return {
            async get() {
              const data = users[id];
              return {exists: data !== undefined, data: () => data};
            },
          };
        },
      };
    },
  };
}

const VALID_AFTER = "Sat, 01 Nov 2026 00:00:00 GMT";
const SIGNED_IN_AFTER = Date.parse(VALID_AFTER) / 1000 + 3600;

function fakeAuth(records) {
  return {
    async getUser(uid) {
      if (!records[uid]) {
        const error = new Error("no user");
        error.code = "auth/user-not-found";
        throw error;
      }
      return {uid, tokensValidAfterTime: VALID_AFTER, disabled: false, ...records[uid]};
    },
  };
}

function request(uid, authTime = SIGNED_IN_AFTER) {
  return uid ? {auth: {uid, token: {auth_time: authTime}}} : {auth: null};
}

async function expectRefusal(promise, code, appCode) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, code);
    assert.equal(error.details?.appCode, appCode);
    return true;
  });
}

const users = {
  sa: {adminRole: "superAdmin", displayName: "Asha Admin", accountStatus: "active"},
  saNoStatus: {adminRole: "superAdmin", name: "Named Only"},
  cs: {adminRole: "customerSupportAdmin", accountStatus: "active"},
  fa: {adminRole: "financeAdmin", accountStatus: "active"},
  member: {role: "petParent", accountStatus: "active"},
  restricted: {adminRole: "superAdmin", accountStatus: "restricted"},
  disabled: {adminRole: "superAdmin", disabled: true},
  isDisabled: {adminRole: "superAdmin", isDisabled: true},
  adminDisabled: {adminRole: "superAdmin", adminDisabled: true},
  isActiveFalse: {adminRole: "superAdmin", isActive: false},
  authDisabled: {adminRole: "superAdmin", accountStatus: "active"},
};
const authRecords = Object.fromEntries(Object.keys(users).map((uid) => [uid, {}]));
authRecords.authDisabled = {disabled: true};
authRecords.noUsersDoc = {};
const deps = {firestore: fakeFirestore(users), authClient: fakeAuth(authRecords)};

test("requireActiveSuperAdmin returns the actor for an active Super Admin", async () => {
  assert.deepEqual(await requireActiveSuperAdmin(request("sa"), deps), {
    uid: "sa",
    role: "superAdmin",
    displayName: "Asha Admin",
  });
  const unnamed = await requireActiveSuperAdmin(request("saNoStatus"), deps);
  assert.equal(unnamed.displayName, "Named Only");
});

test("missing auth is unauthenticated", async () => {
  await expectRefusal(requireActiveSuperAdmin(request(null), deps), "unauthenticated", "UNAUTHENTICATED");
  await expectRefusal(requireActiveSuperAdmin({}, deps), "unauthenticated", "UNAUTHENTICATED");
});

test("CS, Finance, non-admins and missing users docs are ROLE_NOT_ALLOWED for Super Admin only", async () => {
  for (const uid of ["cs", "fa", "member", "noUsersDoc"]) {
    await expectRefusal(requireActiveSuperAdmin(request(uid), deps), "permission-denied", "ROLE_NOT_ALLOWED");
  }
});

test("a wider role set admits CS and Finance (later roles reuse the guard)", async () => {
  const all = ["superAdmin", "customerSupportAdmin", "financeAdmin"];
  assert.equal((await requireActiveAdmin(request("cs"), all, deps)).role, "customerSupportAdmin");
  assert.equal((await requireActiveAdmin(request("fa"), all, deps)).role, "financeAdmin");
  await expectRefusal(requireActiveAdmin(request("member"), all, deps), "permission-denied", "ROLE_NOT_ALLOWED");
});

test("every inactive or disabled flag is ADMIN_NOT_ACTIVE", async () => {
  for (const uid of ["restricted", "disabled", "isDisabled", "adminDisabled", "isActiveFalse", "authDisabled"]) {
    await expectRefusal(requireActiveSuperAdmin(request(uid), deps), "permission-denied", "ADMIN_NOT_ACTIVE");
  }
});

test("a missing Auth record is ADMIN_NOT_ACTIVE", async () => {
  const noAuth = {firestore: fakeFirestore(users), authClient: fakeAuth({})};
  await expectRefusal(requireActiveSuperAdmin(request("sa"), noAuth), "permission-denied", "ADMIN_NOT_ACTIVE");
});

test("a session signed in before tokensValidAfterTime is SESSION_REVOKED", async () => {
  const before = Date.parse(VALID_AFTER) / 1000 - 1;
  await expectRefusal(requireActiveSuperAdmin(request("sa", before), deps), "unauthenticated", "SESSION_REVOKED");
  // Revocation is checked before the role, so a revoked CS session also gets SESSION_REVOKED.
  await expectRefusal(requireActiveSuperAdmin(request("cs", before), deps), "unauthenticated", "SESSION_REVOKED");
});

test("adminAccountIsInactive covers the union of the existing checks", () => {
  assert.equal(adminAccountIsInactive({}), false);
  assert.equal(adminAccountIsInactive({accountStatus: "active"}), false);
  assert.equal(adminAccountIsInactive({accountStatus: " "}), false);
  assert.equal(adminAccountIsInactive({accountStatus: "pendingDeletion"}), true);
  assert.equal(adminAccountIsInactive({disabled: true}), true);
  assert.equal(adminAccountIsInactive({isDisabled: true}), true);
  assert.equal(adminAccountIsInactive({adminDisabled: true}), true);
  assert.equal(adminAccountIsInactive({isActive: false}), true);
  assert.equal(adminAccountIsInactive({isActive: true, disabled: false}), false);
});
