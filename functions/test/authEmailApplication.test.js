const test = require("node:test");
const assert = require("node:assert/strict");

const {
  handleRequestEmailChangeV2,
  handleRequestPasswordResetV2,
  handleSendVerificationEmailV2,
} = require("../lib/email/authEmailApplication.js");
const {
  authEmailRateLimitKey,
} = require("../lib/email/authEmailRateLimit.js");

function user(overrides = {}) {
  return {
    uid: "canonical-uid",
    email: "person@example.com",
    emailVerified: false,
    disabled: false,
    displayName: "Auth Name",
    providerIds: ["password"],
    ...overrides,
  };
}

function dependencies(overrides = {}) {
  const sent = [];
  const calls = {
    uid: [],
    email: [],
    verificationLinks: [],
    emailChangeLinks: [],
    resetLinks: [],
    resetFailures: [],
  };
  return {
    sent,
    calls,
    value: {
      async getUserByUid(uid) {
        calls.uid.push(uid);
        return user();
      },
      async getUserByEmail(email) {
        calls.email.push(email);
        return user();
      },
      async getProfiles() {
        return {
          publicProfile: {displayName: "Profile Name", accountStatus: "active"},
          privateProfile: {accountStatus: "active"},
        };
      },
      async reserveVerificationCooldown() {
        return true;
      },
      async reservePasswordResetCooldown() {
        return true;
      },
      async reserveEmailChangeCooldown() {
        return true;
      },
      async generateVerificationLink(email) {
        calls.verificationLinks.push(email);
        return "https://example.test/action?mode=verifyEmail&oobCode=secret";
      },
      async generatePasswordResetLink(email) {
        calls.resetLinks.push(email);
        return "https://example.test/action?mode=resetPassword&oobCode=secret";
      },
      async generateVerifyAndChangeEmailLink(currentEmail, newEmail) {
        calls.emailChangeLinks.push({currentEmail, newEmail});
        return "https://example.test/action?mode=verifyAndChangeEmail&oobCode=secret";
      },
      async sendEmail(message) {
        sent.push(message);
      },
      reportPasswordResetFailure(stage, email, error) {
        calls.resetFailures.push({stage, email, error});
      },
      ...overrides,
    },
  };
}

function recentCaller(overrides = {}) {
  return {
    uid: "canonical-uid",
    email: "person@example.com",
    authTimeSeconds: 1_000,
    ...overrides,
  };
}

test("email change requires an authenticated recently signed-in caller", async () => {
  const deps = dependencies();
  await assert.rejects(
    handleRequestEmailChangeV2(
      {newEmail: "new@example.com"},
      undefined,
      deps.value,
      1_010,
    ),
    (error) => error.code === "unauthenticated",
  );
  await assert.rejects(
    handleRequestEmailChangeV2(
      {newEmail: "new@example.com"},
      recentCaller({authTimeSeconds: 600}),
      deps.value,
      1_010,
    ),
    (error) =>
      error.code === "failed-precondition" &&
      error.details?.appCode === "requires-recent-login",
  );
  assert.equal(deps.sent.length, 0);
});

test("email change sends the branded VERIFY_AND_CHANGE_EMAIL action to the new address", async () => {
  const deps = dependencies();
  const result = await handleRequestEmailChangeV2(
    {newEmail: "  New@Example.COM "},
    recentCaller(),
    deps.value,
    1_010,
  );

  assert.deepEqual(result, {success: true});
  assert.deepEqual(deps.calls.uid, ["canonical-uid"]);
  assert.deepEqual(deps.calls.emailChangeLinks, [{
    currentEmail: "person@example.com",
    newEmail: "new@example.com",
  }]);
  assert.equal(deps.sent.length, 1);
  assert.equal(deps.sent[0].to, "new@example.com");
  assert.equal(deps.sent[0].subject, "Verify your new email for Pettxo");
  assert.match(deps.sent[0].html, /PETTXO/);
  assert.match(deps.sent[0].html, />Verify new email<\/a>/);
  assert.match(deps.sent[0].html, /mode=verifyAndChangeEmail&amp;oobCode=secret/);
  assert.equal(JSON.stringify(result).includes("oobCode"), false);
});

test("email change rejects token-email mismatch and UID tampering", async () => {
  const mismatch = dependencies();
  await assert.rejects(
    handleRequestEmailChangeV2(
      {newEmail: "new@example.com"},
      recentCaller({email: "attacker@example.com"}),
      mismatch.value,
      1_010,
    ),
    (error) => error.details?.appCode === "requires-recent-login",
  );

  const wrongUid = dependencies({getUserByUid: async () => user()});
  await assert.rejects(
    handleRequestEmailChangeV2(
      {newEmail: "new@example.com"},
      recentCaller({uid: "caller-uid", email: "person@example.com"}),
      wrongUid.value,
      1_010,
    ),
    (error) => error.code === "failed-precondition",
  );
  assert.equal(wrongUid.sent.length, 0);
});

test("email change cooldown prevents repeated branded sends", async () => {
  const deps = dependencies({reserveEmailChangeCooldown: async () => false});
  await assert.rejects(
    handleRequestEmailChangeV2(
      {newEmail: "new@example.com"},
      recentCaller(),
      deps.value,
      1_010,
    ),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal(deps.sent.length, 0);
  assert.equal(deps.calls.emailChangeLinks.length, 0);
});

test("email change refuses a generic VERIFY_EMAIL action", async () => {
  const deps = dependencies({
    generateVerifyAndChangeEmailLink: async () =>
      "https://example.test/action?mode=verifyEmail&oobCode=secret",
  });
  await assert.rejects(
    handleRequestEmailChangeV2(
      {newEmail: "new@example.com"},
      recentCaller(),
      deps.value,
      1_010,
    ),
    (error) => error.code === "unavailable",
  );
  assert.equal(deps.sent.length, 0);
});

test("verification rejects unauthenticated requests", async () => {
  const deps = dependencies();
  await assert.rejects(
    handleSendVerificationEmailV2(undefined, deps.value),
    (error) => error.code === "unauthenticated",
  );
  assert.equal(deps.sent.length, 0);
});

test("verification derives user and recipient server-side", async () => {
  const deps = dependencies();
  const result = await handleSendVerificationEmailV2(
    "canonical-uid",
    deps.value,
  );

  assert.deepEqual(result, {success: true});
  assert.deepEqual(deps.calls.uid, ["canonical-uid"]);
  assert.deepEqual(deps.calls.verificationLinks, ["person@example.com"]);
  assert.equal(deps.sent.length, 1);
  assert.equal(deps.sent[0].to, "person@example.com");
  assert.equal(deps.sent[0].subject, "Verify your email for Pettxo");
  assert.match(deps.sent[0].html, /Hi Profile Name,/);
  assert.equal(JSON.stringify(result).includes("oobCode"), false);
});

test("verification safely handles missing email and verified users", async () => {
  const missing = dependencies({getUserByUid: async () => user({email: undefined})});
  await assert.rejects(
    handleSendVerificationEmailV2("canonical-uid", missing.value),
    (error) => error.code === "failed-precondition",
  );

  const verified = dependencies({
    getUserByUid: async () => user({emailVerified: true}),
  });
  assert.deepEqual(
    await handleSendVerificationEmailV2("canonical-uid", verified.value),
    {success: true},
  );
  assert.equal(verified.sent.length, 0);
});

test("verification cooldown prevents a send", async () => {
  const deps = dependencies({
    reserveVerificationCooldown: async () => false,
  });
  await assert.rejects(
    handleSendVerificationEmailV2("canonical-uid", deps.value),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal(deps.sent.length, 0);
});

test("eligible reset generates one server link and sends one email", async () => {
  const deps = dependencies();
  const result = await handleRequestPasswordResetV2(
    {email: "  Person@Example.COM "},
    deps.value,
  );

  assert.deepEqual(result, {success: true});
  assert.deepEqual(deps.calls.email, ["person@example.com"]);
  assert.deepEqual(deps.calls.resetLinks, ["person@example.com"]);
  assert.equal(deps.sent.length, 1);
  assert.equal(deps.sent[0].to, "person@example.com");
  assert.equal(deps.sent[0].subject, "Reset your Pettxo password");
  assert.equal(JSON.stringify(result).includes("oobCode"), false);
});

test("unknown and ineligible reset accounts return the same generic result", async () => {
  const unknown = dependencies({getUserByEmail: async () => null});
  const phoneOnly = dependencies({
    getUserByEmail: async () => user({providerIds: ["phone"]}),
  });
  const disabled = dependencies({
    getUserByEmail: async () => user({disabled: true}),
  });
  const pendingDeletion = dependencies({
    getProfiles: async () => ({
      publicProfile: {displayName: "Person", accountStatus: "active"},
      privateProfile: {accountStatus: "pendingDeletion"},
    }),
  });

  const results = await Promise.all([
    handleRequestPasswordResetV2({email: "unknown@example.com"}, unknown.value),
    handleRequestPasswordResetV2({email: "phone@example.com"}, phoneOnly.value),
    handleRequestPasswordResetV2({email: "disabled@example.com"}, disabled.value),
    handleRequestPasswordResetV2(
      {email: "pending@example.com"},
      pendingDeletion.value,
    ),
  ]);
  for (const result of results) assert.deepEqual(result, {success: true});
  assert.equal(unknown.sent.length, 0);
  assert.equal(phoneOnly.sent.length, 0);
  assert.equal(disabled.sent.length, 0);
  assert.equal(pendingDeletion.sent.length, 0);
});

test("reset cooldown and provider failures do not expose account existence", async () => {
  const cooldown = dependencies({
    reservePasswordResetCooldown: async () => false,
  });
  const providerFailure = dependencies({
    sendEmail: async () => {
      throw new Error("provider unavailable");
    },
  });

  const cooldownResult = await handleRequestPasswordResetV2(
    {email: "person@example.com"},
    cooldown.value,
  );
  const failureResult = await handleRequestPasswordResetV2(
    {email: "person@example.com"},
    providerFailure.value,
  );
  assert.deepEqual(cooldownResult, {success: true});
  assert.deepEqual(failureResult, {success: true});
  assert.equal(cooldown.sent.length, 0);
  assert.equal(providerFailure.calls.resetFailures.length, 1);
});

test("malformed reset input is rejected before lookup", async () => {
  const deps = dependencies();
  await assert.rejects(
    handleRequestPasswordResetV2({email: "not-an-email"}, deps.value),
    (error) => error.code === "invalid-argument",
  );
  assert.equal(deps.calls.email.length, 0);
  assert.equal(deps.sent.length, 0);
});

test("concurrent reset requests reserve only one send", async () => {
  let reservations = 0;
  const deps = dependencies({
    reservePasswordResetCooldown: async () => {
      reservations += 1;
      return reservations === 1;
    },
  });
  const results = await Promise.all([
    handleRequestPasswordResetV2({email: "person@example.com"}, deps.value),
    handleRequestPasswordResetV2({email: "person@example.com"}, deps.value),
  ]);
  assert.deepEqual(results, [{success: true}, {success: true}]);
  assert.equal(deps.sent.length, 1);
});

test("rate-limit keys are deterministic SHA-256 values without raw email", () => {
  const email = "person@example.com";
  const first = authEmailRateLimitKey(email);
  assert.equal(first, authEmailRateLimitKey(email));
  assert.match(first, /^[a-f0-9]{64}$/);
  assert.equal(first.includes(email), false);
});
