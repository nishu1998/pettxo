const test = require("node:test");
const assert = require("node:assert/strict");

const {
  handleCanonicalUserCreated,
} = require("../lib/email/welcomeEmailApplication.js");

function harness(overrides = {}) {
  const state = {status: "", attempts: 0};
  const sent = [];
  const calls = {authUids: [], noEmail: 0, missingAuth: 0, failures: 0};
  const dependencies = {
    async getAuthUser(uid) {
      calls.authUids.push(uid);
      return {
        uid,
        email: "canonical@example.com",
        displayName: "Auth Name",
      };
    },
    async reserveDelivery() {
      if (state.status === "sent") return {decision: "sent"};
      if (state.status === "skippedNoEmail") return {decision: "skippedNoEmail"};
      if (state.status === "sending") return {decision: "busy"};
      state.status = "sending";
      state.attempts += 1;
      return {
        decision: "send",
        leaseId: `lease-${state.attempts}`,
        idempotencyKey: "welcome-stable-uid-hash",
      };
    },
    async recordNoEmail() {
      calls.noEmail += 1;
      state.status = "skippedNoEmail";
    },
    async recordMissingAuthUser() {
      calls.missingAuth += 1;
      state.status = "skippedMissingAuthUser";
    },
    async markSent() {
      state.status = "sent";
    },
    async markRetryableFailure() {
      calls.failures += 1;
      state.status = "retryableFailure";
    },
    async sendEmail(message, idempotencyKey) {
      sent.push({message, idempotencyKey});
    },
    ...overrides,
  };
  return {state, sent, calls, dependencies};
}

test("new canonical email account receives one approved welcome email", async () => {
  const h = harness();
  const result = await handleCanonicalUserCreated(
    "new-uid",
    {displayName: "Profile Name"},
    h.dependencies,
  );

  assert.equal(result, "sent");
  assert.deepEqual(h.calls.authUids, ["new-uid"]);
  assert.equal(h.sent.length, 1);
  assert.equal(h.sent[0].message.to, "canonical@example.com");
  assert.equal(h.sent[0].message.subject, "Welcome to Pettxo, Profile Name");
  assert.match(h.sent[0].message.html, /Welcome to Pettxo, Profile Name/);
  assert.match(h.sent[0].message.html, />Open Pettxo<\/a>/);
  assert.equal(h.sent[0].idempotencyKey, "welcome-stable-uid-hash");
  assert.equal(h.state.status, "sent");
});

test("profile-controlled recipient fields cannot override Firebase Auth email", async () => {
  const h = harness();
  await handleCanonicalUserCreated(
    "new-uid",
    {displayName: "Person", email: "attacker@example.com"},
    h.dependencies,
  );
  assert.equal(h.sent[0].message.to, "canonical@example.com");
  assert.equal(JSON.stringify(h.sent[0]).includes("attacker@example.com"), false);
});

test("missing name uses the approved safe fallback", async () => {
  const h = harness({
    getAuthUser: async (uid) => ({uid, email: "person@example.com"}),
  });
  await handleCanonicalUserCreated("new-uid", {}, h.dependencies);
  assert.equal(h.sent[0].message.subject, "Welcome to Pettxo, there");
  assert.match(h.sent[0].message.html, /Welcome to Pettxo, there/);
});

test("phone-only canonical account is recorded without sending", async () => {
  const h = harness({
    getAuthUser: async (uid) => ({uid}),
  });
  const result = await handleCanonicalUserCreated(
    "phone-uid",
    {displayName: "Phone User"},
    h.dependencies,
  );
  assert.equal(result, "skippedNoEmail");
  assert.equal(h.calls.noEmail, 1);
  assert.equal(h.sent.length, 0);
  assert.equal(h.state.status, "skippedNoEmail");
});

test("duplicate lifecycle delivery does not send a second email", async () => {
  const h = harness();
  assert.equal(
    await handleCanonicalUserCreated("new-uid", {displayName: "Person"}, h.dependencies),
    "sent",
  );
  assert.equal(
    await handleCanonicalUserCreated("new-uid", {displayName: "Person"}, h.dependencies),
    "alreadySent",
  );
  assert.equal(h.sent.length, 1);
});

test("concurrent lifecycle attempts allow at most one delivery", async () => {
  let releaseSend;
  let notifyStarted;
  const started = new Promise((resolve) => {
    notifyStarted = resolve;
  });
  const gate = new Promise((resolve) => {
    releaseSend = resolve;
  });
  const h = harness({
    async sendEmail(message, idempotencyKey) {
      h.sent.push({message, idempotencyKey});
      notifyStarted();
      await gate;
    },
  });

  const first = handleCanonicalUserCreated(
    "new-uid",
    {displayName: "Person"},
    h.dependencies,
  );
  await started;
  await assert.rejects(
    handleCanonicalUserCreated(
      "new-uid",
      {displayName: "Person"},
      h.dependencies,
    ),
    /delivery_in_progress/,
  );
  releaseSend();
  assert.equal(await first, "sent");
  assert.equal(h.sent.length, 1);
});

test("temporary provider failure becomes retryable and later succeeds once", async () => {
  let providerAttempts = 0;
  const h = harness({
    async sendEmail(message, idempotencyKey) {
      providerAttempts += 1;
      if (providerAttempts === 1) throw new Error("temporary failure");
      h.sent.push({message, idempotencyKey});
    },
  });

  await assert.rejects(
    handleCanonicalUserCreated(
      "new-uid",
      {displayName: "Person"},
      h.dependencies,
    ),
    /temporary failure/,
  );
  assert.equal(h.state.status, "retryableFailure");
  assert.equal(h.calls.failures, 1);

  assert.equal(
    await handleCanonicalUserCreated(
      "new-uid",
      {displayName: "Person"},
      h.dependencies,
    ),
    "sent",
  );
  assert.equal(h.sent.length, 1);
  assert.equal(h.sent[0].idempotencyKey, "welcome-stable-uid-hash");
});

test("missing Auth account is terminally skipped without recipient guessing", async () => {
  const h = harness({getAuthUser: async () => null});
  const result = await handleCanonicalUserCreated(
    "missing-uid",
    {displayName: "Person"},
    h.dependencies,
  );
  assert.equal(result, "skippedMissingAuthUser");
  assert.equal(h.calls.missingAuth, 1);
  assert.equal(h.sent.length, 0);
});
