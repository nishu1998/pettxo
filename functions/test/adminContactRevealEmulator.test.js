// Item 27: admin contact callables against the Firestore emulator. Firebase
// Auth is a fake passed through deps (the test emulators run Firestore and
// Storage only).
const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({services: ["firestore"]});
const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");

const enabled = firebaseEmulator.enabled;
const skip = !enabled;

let db;
let mod;

const RUN = randomUUID().slice(0, 8);
const id = (name) => `${name}-${RUN}`;
const VALID_AFTER = "Sat, 01 Nov 2026 00:00:00 GMT";
const AUTH_TIME = Date.parse(VALID_AFTER) / 1000 + 3600;

// Phone numbers and emails are unique per run: other emulator files share the database.
const DIGITS = String(Math.floor(Math.random() * 1e6)).padStart(6, "0");
const phone = (n) => `+9196${DIGITS}${String(n).padStart(2, "0")}`;
const national = (value) => value.slice(3);
const masked = (value) => `+91 96•••• •${value.slice(-3)}`;
const P1 = phone(1);
const P2 = phone(2);
const P3 = phone(3);
const P4 = phone(4);
const P5 = phone(5);
const P6 = phone(6);
const PT = phone(7);
const E_PARENT = `asha.k.${RUN}@example.com`;
const E_AUTH = `auth.only.${RUN}@example.com`;
const E_PROVIDER = `ravi.${RUN}@example.com`;
const E_TEAM = `teamlead.${RUN}@pettxo.com`;

// Every full value used in this file. No adminAuditLogs row may contain any.
const RAW_VALUES = [
  ...[P1, P2, P3, P4, P5, P6, PT].flatMap((value) => [value, national(value)]),
  E_PARENT, E_AUTH, E_PROVIDER, E_TEAM,
];

const authUsers = new Map();
const authClient = {
  async getUser(uid) {
    const user = authUsers.get(uid);
    if (!user) {
      const error = new Error("There is no user record.");
      error.code = "auth/user-not-found";
      throw error;
    }
    return {uid, disabled: false, tokensValidAfterTime: VALID_AFTER, providerData: [], ...user};
  },
  async getUsers(identifiers) {
    const users = [];
    for (const {uid} of identifiers) {
      if (authUsers.has(uid)) users.push(await this.getUser(uid));
    }
    return {users, notFound: []};
  },
};

// The clock moves 200 s per call unless a test pins it, so the main Super
// Admin never reaches 20 reveals in one hour by accident.
let clockMs = Date.parse("2026-11-23T10:00:00.000Z");
let autoAdvance = true;
const now = () => {
  if (autoAdvance) clockMs += 200_000;
  return new Date(clockMs);
};
const deps = () => ({firestore: db, authClient, now});

const SA = id("sa");
const SA2 = id("sa2");
const SA_RATE = id("sa-rate");
const SA_DAY = id("sa-day");
const SA_SEARCH = id("sa-search");
const SA_FAIL = id("sa-fail");
const CS = id("cs");
const FA = id("fa");
const SA_DISABLED = id("sa-disabled");
const SA_AUTH_DISABLED = id("sa-authdisabled");
const PARENT = id("parent");
const PROVIDER = id("provider");
const LEGACY_PHONE = id("legacy-phone");
const MOBILE_ONLY = id("mobile-only");
const AUTH_ONLY = id("auth-only");
const NOTHING = id("nothing");
const STRANGER = id("stranger");
const BOOKING = id("booking");
const TICKET = id("ticket");
const TICKET_EMPTY = id("ticket-empty");
const HOLD = id("hold");
const ACTOR_UIDS = [SA, SA2, SA_RATE, SA_DAY, SA_SEARCH, SA_FAIL, CS, FA, SA_DISABLED, SA_AUTH_DISABLED];

function call(uid, data) {
  return {auth: uid ? {uid, token: {auth_time: AUTH_TIME}} : null, data};
}

let requestCounter = 0;
function revealData(overrides = {}) {
  requestCounter += 1;
  return {
    userId: PARENT,
    field: "phone",
    purpose: "show",
    reasonCode: "BOOKING_PROBLEM",
    context: {type: "booking", id: BOOKING},
    requestId: `req_${RUN}_${requestCounter}`,
    ...overrides,
  };
}

async function expectCode(promise, code, appCode) {
  let caught;
  await assert.rejects(promise, (error) => {
    caught = error;
    assert.equal(error.code, code, error.message);
    if (appCode) assert.equal(error.details?.appCode, appCode);
    return true;
  });
  return caught;
}

async function rowsBy(uid) {
  const snapshot = await db.collection("adminAuditLogs").where("byUid", "==", uid).get();
  return snapshot.docs.map((doc) => ({id: doc.id, ...doc.data()}));
}

async function enableReveal(enabledValue = true) {
  await db.doc("_rollouts/adminContactReveal").set({enabled: enabledValue});
}

test.before(async () => {
  if (skip) return;
  ({db} = require("../lib/shared/firebase.js"));
  mod = require("../lib/admin/contactReveal.js");

  const admin = (role, extra = {}) => ({adminRole: role, displayName: `Admin ${role}`, accountStatus: "active", ...extra});
  await Promise.all([
    db.doc(`users/${SA}`).set(admin("superAdmin", {displayName: "Asha Admin"})),
    db.doc(`users/${SA2}`).set(admin("superAdmin")),
    db.doc(`users/${SA_RATE}`).set(admin("superAdmin")),
    db.doc(`users/${SA_DAY}`).set(admin("superAdmin")),
    db.doc(`users/${SA_SEARCH}`).set(admin("superAdmin")),
    db.doc(`users/${SA_FAIL}`).set(admin("superAdmin")),
    db.doc(`users/${CS}`).set(admin("customerSupportAdmin")),
    db.doc(`users/${FA}`).set(admin("financeAdmin")),
    db.doc(`users/${SA_DISABLED}`).set(admin("superAdmin", {adminDisabled: true})),
    db.doc(`users/${SA_AUTH_DISABLED}`).set(admin("superAdmin")),
    db.doc(`userPrivate/${SA2}`).set({email: E_TEAM, providers: ["password"]}),

    db.doc(`users/${PARENT}`).set({uid: PARENT, role: "petParent", accountStatus: "active"}),
    db.doc(`userPrivate/${PARENT}`).set({
      phoneNumber: P1, phone: P1, mobileNumber: P1,
      email: E_PARENT,
    }),
    db.doc(`users/${PROVIDER}`).set({uid: PROVIDER, role: "serviceProvider"}),
    db.doc(`userPrivate/${PROVIDER}`).set({phoneNumber: P2, email: E_PROVIDER}),
    db.doc(`users/${LEGACY_PHONE}`).set({uid: LEGACY_PHONE}),
    db.doc(`userPrivate/${LEGACY_PHONE}`).set({phoneNumber: "", phone: P3}),
    db.doc(`userPrivate/${MOBILE_ONLY}`).set({mobileNumber: P4}),
    db.doc(`users/${AUTH_ONLY}`).set({uid: AUTH_ONLY}),
    db.doc(`users/${NOTHING}`).set({uid: NOTHING}),

    db.doc(`bookings/${BOOKING}`).set({parentId: PARENT, customerId: PARENT, providerId: PROVIDER, serviceOwnerId: PROVIDER}),
    db.doc(`supportTickets/${TICKET}`).set({userId: PARENT, contactNumber: PT}),
    db.doc(`supportTickets/${TICKET_EMPTY}`).set({userId: PARENT, contactNumber: ""}),
    db.doc(`blockedRelationshipPaymentHolds/${HOLD}`).set({parentId: PARENT, providerId: PROVIDER, status: "OPEN"}),
  ]);
  for (const uid of ACTOR_UIDS) authUsers.set(uid, {});
  authUsers.set(SA_AUTH_DISABLED, {disabled: true});
  authUsers.set(SA2, {email: E_TEAM, providerData: [{providerId: "google.com"}]});
  authUsers.set(AUTH_ONLY, {phoneNumber: P5, email: E_AUTH});
  authUsers.set(PARENT, {phoneNumber: P6});
  await enableReveal(true);
});

test.after(async () => {
  if (skip) return;
  await enableReveal(true);
});

// --- revealContactForAdmin ---------------------------------------------------

test("reveal: an active Super Admin gets the full phone once and the row holds only the mask", {skip}, async () => {
  const data = revealData({purpose: "call", reasonCode: "CALLBACK_REQUESTED"});
  const result = await mod.revealContactForAdminData(call(SA, data), deps());
  assert.equal(result.value, P1);
  assert.equal(result.valueMasked, masked(P1));
  assert.equal(result.field, "phone");
  assert.equal(result.purpose, "call");
  assert.equal(result.outcome, "REVEALED");
  assert.equal(result.repeat, false);
  assert.equal(result.expiresInSeconds, 30);
  assert.equal(result.logId, mod.revealLogDocId(SA, data.requestId));

  const row = (await db.collection("adminAuditLogs").doc(result.logId).get()).data();
  assert.equal(row.schemaVersion, 2);
  assert.equal(row.type, "contact");
  assert.equal(row.action, "contact.reveal");
  assert.equal(row.byUid, SA);
  assert.equal(row.byName, "Asha Admin");
  assert.equal(row.byRole, "superAdmin");
  assert.equal(row.targetType, "user");
  assert.equal(row.targetId, PARENT);
  assert.equal(row.before, null);
  assert.deepEqual(row.context, {type: "booking", id: BOOKING, purpose: "call"});
  assert.equal(row.reasonCode, "CALLBACK_REQUESTED");
  assert.equal(row.reason, "Customer asked for a call back");
  assert.equal(row.requestId, data.requestId);
  assert.equal(row.source, "revealContactForAdmin");
  assert.equal(row.after.valueMasked, masked(P1));
  assert.equal(row.after.valueSource, "userPrivate.phoneNumber");
  assert.equal(row.after.outcome, "REVEALED");
  assert.ok(row.at && row.createdAt && row.at.isEqual(row.createdAt));
  assert.ok(!("value" in row.after) && !("valueHash" in row.after));

  const limit = (await db.doc(`adminRateLimits/${SA}_contactReveal`).get()).data();
  assert.ok(limit.events.length >= 1);
});

test("reveal: email is revealed and logged masked", {skip}, async () => {
  const result = await mod.revealContactForAdminData(
    call(SA, revealData({field: "email", purpose: "email", context: {type: "user", id: PARENT}})),
    deps(),
  );
  assert.equal(result.value, E_PARENT);
  assert.equal(result.valueMasked, "as***@example.com");
  const row = (await db.collection("adminAuditLogs").doc(result.logId).get()).data();
  assert.equal(row.after.field, "email");
  assert.equal(row.after.valueMasked, "as***@example.com");
});

test("reveal: every purpose is accepted for its field, including copy", {skip}, async () => {
  for (const purpose of ["show", "call", "whatsapp", "copy"]) {
    const result = await mod.revealContactForAdminData(call(SA, revealData({purpose})), deps());
    const row = (await db.collection("adminAuditLogs").doc(result.logId).get()).data();
    assert.equal(row.context.purpose, purpose);
  }
  for (const purpose of ["show", "email", "copy"]) {
    const result = await mod.revealContactForAdminData(
      call(SA, revealData({field: "email", purpose, context: {type: "user", id: PARENT}})),
      deps(),
    );
    assert.equal(result.purpose, purpose);
  }
});

test("reveal: phone falls back phoneNumber -> phone -> mobileNumber -> Auth", {skip}, async () => {
  const cases = [
    [LEGACY_PHONE, P3, "userPrivate.phone"],
    [MOBILE_ONLY, P4, "userPrivate.mobileNumber"],
    [AUTH_ONLY, P5, "auth.phoneNumber"],
  ];
  for (const [userId, value, source] of cases) {
    const result = await mod.revealContactForAdminData(
      call(SA, revealData({userId, context: {type: "user", id: userId}})),
      deps(),
    );
    assert.equal(result.value, value, userId);
    const row = (await db.collection("adminAuditLogs").doc(result.logId).get()).data();
    assert.equal(row.after.valueSource, source, userId);
  }
  // userPrivate wins over Auth when it has a phone.
  const parent = await mod.revealContactForAdminData(call(SA, revealData()), deps());
  assert.equal(parent.value, P1);
  const email = await mod.revealContactForAdminData(
    call(SA, revealData({userId: AUTH_ONLY, field: "email", context: {type: "user", id: AUTH_ONLY}})),
    deps(),
  );
  assert.equal(email.value, E_AUTH);
});

test("reveal: no value anywhere is NO_CONTACT_ON_FILE and still logged as contact.reveal_empty", {skip}, async () => {
  const error = await expectCode(
    mod.revealContactForAdminData(call(SA, revealData({userId: NOTHING, context: {type: "user", id: NOTHING}})), deps()),
    "failed-precondition",
    "NO_CONTACT_ON_FILE",
  );
  const row = (await db.collection("adminAuditLogs").doc(error.details.logId).get()).data();
  assert.equal(row.action, "contact.reveal_empty");
  assert.equal(row.after.outcome, "NOT_AVAILABLE");
  assert.equal(row.after.valueMasked, null);
});

test("reveal: support ticket contactNumber needs the support context for that ticket", {skip}, async () => {
  const result = await mod.revealContactForAdminData(call(SA, {
    supportTicketId: TICKET,
    field: "phone",
    purpose: "whatsapp",
    reasonCode: "CALLBACK_REQUESTED",
    context: {type: "support", id: TICKET},
    requestId: `req_${RUN}_ticket`,
  }), deps());
  assert.equal(result.value, PT);
  assert.equal(result.valueMasked, masked(PT));
  const row = (await db.collection("adminAuditLogs").doc(result.logId).get()).data();
  assert.equal(row.targetType, "supportTicket");
  assert.equal(row.targetId, TICKET);
  assert.equal(row.after.valueSource, "supportTicket.contactNumber");

  const ticketBase = {supportTicketId: TICKET, field: "phone", purpose: "show", reasonCode: "OTHER", reason: "Testing"};
  await expectCode(mod.revealContactForAdminData(call(SA, {...ticketBase, context: {type: "booking", id: BOOKING}, requestId: `req_${RUN}_t2`}), deps()), "invalid-argument", "INVALID_INPUT");
  await expectCode(mod.revealContactForAdminData(call(SA, {...ticketBase, context: {type: "support", id: TICKET_EMPTY}, requestId: `req_${RUN}_t3`}), deps()), "invalid-argument", "INVALID_INPUT");
  await expectCode(mod.revealContactForAdminData(call(SA, {...ticketBase, field: "email", purpose: "show", context: {type: "support", id: TICKET}, requestId: `req_${RUN}_t4`}), deps()), "invalid-argument", "INVALID_INPUT");
  await expectCode(mod.revealContactForAdminData(call(SA, {...ticketBase, supportTicketId: TICKET_EMPTY, context: {type: "support", id: TICKET_EMPTY}, requestId: `req_${RUN}_t5`}), deps()), "failed-precondition", "NO_CONTACT_ON_FILE");
  const missing = await expectCode(mod.revealContactForAdminData(call(SA, {...ticketBase, supportTicketId: id("no-ticket"), context: {type: "support", id: id("no-ticket")}, requestId: `req_${RUN}_t6`}), deps()), "not-found", "TARGET_NOT_FOUND");
  const deniedRow = (await db.collection("adminAuditLogs").doc(missing.details.logId).get()).data();
  assert.equal(deniedRow.action, "contact.reveal_denied");
  assert.equal(deniedRow.after.outcome, "TARGET_NOT_FOUND");
});

test("reveal: booking, support and paymentHold contexts are checked on the server", {skip}, async () => {
  const ok = [
    {type: "booking", id: BOOKING},
    {type: "support", id: TICKET},
    {type: "paymentHold", id: HOLD},
    {type: "moderation", id: "any-post"},
    {type: "provider", id: "anything"},
    {type: "chat", id: "any-chat"},
  ];
  for (const context of ok) {
    const result = await mod.revealContactForAdminData(call(SA, revealData({context})), deps());
    assert.equal(result.outcome, "REVEALED", context.type);
  }
  // The provider is part of the booking and the hold too.
  await mod.revealContactForAdminData(call(SA, revealData({userId: PROVIDER, context: {type: "paymentHold", id: HOLD}})), deps());

  const mismatches = [
    {userId: STRANGER, context: {type: "booking", id: BOOKING}},
    {userId: PARENT, context: {type: "booking", id: id("no-booking")}},
    {userId: PROVIDER, context: {type: "support", id: TICKET}},
    {userId: PARENT, context: {type: "support", id: id("no-ticket")}},
    {userId: STRANGER, context: {type: "paymentHold", id: HOLD}},
    {userId: PARENT, context: {type: "paymentHold", id: id("no-hold")}},
  ];
  for (const mismatch of mismatches) {
    const error = await expectCode(
      mod.revealContactForAdminData(call(SA, revealData(mismatch)), deps()),
      "failed-precondition",
      "CONTEXT_MISMATCH",
    );
    const row = (await db.collection("adminAuditLogs").doc(error.details.logId).get()).data();
    assert.equal(row.action, "contact.reveal_denied");
    assert.equal(row.after.outcome, "CONTEXT_MISMATCH");
    assert.equal(row.after.valueMasked, undefined);
  }
});

test("reveal: unknown user is TARGET_NOT_FOUND and logged", {skip}, async () => {
  const ghost = id("ghost");
  const error = await expectCode(
    mod.revealContactForAdminData(call(SA, revealData({userId: ghost, context: {type: "user", id: ghost}})), deps()),
    "not-found",
    "TARGET_NOT_FOUND",
  );
  assert.ok(error.details.logId);
});

test("reveal: CS, Finance, disabled Super Admins and signed-out callers get nothing and leave no row", {skip}, async () => {
  const refusals = [
    [CS, "permission-denied", "ROLE_NOT_ALLOWED"],
    [FA, "permission-denied", "ROLE_NOT_ALLOWED"],
    [SA_DISABLED, "permission-denied", "ADMIN_NOT_ACTIVE"],
    [SA_AUTH_DISABLED, "permission-denied", "ADMIN_NOT_ACTIVE"],
    [null, "unauthenticated", "UNAUTHENTICATED"],
  ];
  for (const [uid, code, appCode] of refusals) {
    await expectCode(mod.revealContactForAdminData(call(uid, revealData()), deps()), code, appCode);
    if (uid) assert.equal((await rowsBy(uid)).length, 0, `${uid} has no rows`);
  }
  const revoked = {auth: {uid: SA, token: {auth_time: Date.parse(VALID_AFTER) / 1000 - 5}}, data: revealData()};
  await expectCode(mod.revealContactForAdminData(revoked, deps()), "unauthenticated", "SESSION_REVOKED");
});

test("reveal: kill switch off is REVEAL_DISABLED and returns nothing", {skip}, async () => {
  await enableReveal(false);
  try {
    const before = (await rowsBy(SA2)).length;
    await expectCode(mod.revealContactForAdminData(call(SA2, revealData()), deps()), "failed-precondition", "REVEAL_DISABLED");
    await db.doc("_rollouts/adminContactReveal").delete();
    await expectCode(mod.revealContactForAdminData(call(SA2, revealData()), deps()), "failed-precondition", "REVEAL_DISABLED");
    assert.equal((await rowsBy(SA2)).length, before);
  } finally {
    await enableReveal(true);
  }
});

test("reveal: validation table", {skip}, async () => {
  const bad = [
    [{userId: undefined}, "userId"],
    [{supportTicketId: TICKET}, "userId"],
    [{userId: "a/b"}, "userId"],
    [{userId: ""}, "userId"],
    [{userId: "x".repeat(129)}, "userId"],
    [{field: "address"}, "field"],
    [{purpose: "email"}, "purpose"],
    [{field: "email", purpose: "whatsapp"}, "purpose"],
    [{purpose: undefined}, "purpose"],
    [{reasonCode: undefined}, "reasonCode"],
    [{reasonCode: "JUST_LOOKING"}, "reasonCode"],
    [{reasonCode: "OTHER"}, "reason"],
    [{reasonCode: "OTHER", reason: "ab"}, "reason"],
    [{reason: "x".repeat(201)}, "reason"],
    [{reason: 42}, "reason"],
    [{reason: "line\u0000break"}, "reason"],
    [{reasonCode: "OTHER", reason: `called ${P1}`}, "reason"],
    [{reason: `mailed ${E_PARENT}`}, "reason"],
    [{context: undefined}, "context"],
    [{context: {type: "pet", id: "x"}}, "context"],
    [{context: {type: "booking", id: ""}}, "context"],
    [{requestId: "short"}, "requestId"],
    [{requestId: "has space here"}, "requestId"],
    [{requestId: undefined}, "requestId"],
  ];
  for (const [overrides, field] of bad) {
    const error = await expectCode(
      mod.revealContactForAdminData(call(SA, revealData(overrides)), deps()),
      "invalid-argument",
      "INVALID_INPUT",
    );
    assert.equal(error.details.field, field, JSON.stringify(overrides));
  }
  const ok = await mod.revealContactForAdminData(
    call(SA, revealData({reasonCode: "OTHER", reason: "Following up on a refund"})),
    deps(),
  );
  const row = (await db.collection("adminAuditLogs").doc(ok.logId).get()).data();
  assert.equal(row.reasonCode, "OTHER");
  assert.equal(row.reason, "Following up on a refund");
});

test("reveal: a repeated requestId is logged as contact.reveal_repeat; reuse for another target is refused", {skip}, async () => {
  const data = revealData({requestId: `req_${RUN}_repeat`});
  const first = await mod.revealContactForAdminData(call(SA, data), deps());
  const second = await mod.revealContactForAdminData(call(SA, data), deps());
  assert.equal(first.repeat, false);
  assert.equal(second.repeat, true);
  assert.notEqual(second.logId, first.logId);
  assert.equal(second.value, P1);
  const row = (await db.collection("adminAuditLogs").doc(second.logId).get()).data();
  assert.equal(row.action, "contact.reveal_repeat");
  assert.equal(row.requestId, data.requestId);

  await expectCode(
    mod.revealContactForAdminData(call(SA, {...data, userId: PROVIDER}), deps()),
    "invalid-argument",
    "REQUEST_ID_REUSED",
  );
  await expectCode(
    mod.revealContactForAdminData(call(SA, {...data, field: "email", purpose: "show"}), deps()),
    "invalid-argument",
    "REQUEST_ID_REUSED",
  );
});

test("reveal: 20 per hour pass, the 21st is RATE_LIMITED with a denied row, and the window rolls", {skip}, async () => {
  autoAdvance = false;
  const start = clockMs;
  try {
    for (let index = 0; index < 20; index += 1) {
      clockMs = start + index * 1000;
      await mod.revealContactForAdminData(call(SA_RATE, revealData()), deps());
    }
    clockMs = start + 30_000;
    const error = await expectCode(
      mod.revealContactForAdminData(call(SA_RATE, revealData()), deps()),
      "resource-exhausted",
      "RATE_LIMITED",
    );
    assert.equal(error.details.retryAfterSeconds, 3600 - 30);
    const denied = (await db.collection("adminAuditLogs").doc(error.details.logId).get()).data();
    assert.equal(denied.action, "contact.reveal_denied");
    assert.equal(denied.after.outcome, "RATE_LIMITED");
    assert.equal(denied.after.valueMasked, undefined);
    const limit = (await db.doc(`adminRateLimits/${SA_RATE}_contactReveal`).get()).data();
    assert.equal(limit.events.length, 20, "a refused attempt is not counted");

    clockMs = start + 3600 * 1000 + 1;
    const after = await mod.revealContactForAdminData(call(SA_RATE, revealData()), deps());
    assert.equal(after.outcome, "REVEALED");
  } finally {
    clockMs = start + 2 * 3600 * 1000;
    autoAdvance = true;
  }
});

test("reveal: 100 per day is enforced across hours", {skip}, async () => {
  autoAdvance = false;
  const nowMs = clockMs;
  // 100 earlier reveals spread over the last 23 hours, at most 5 in any hour.
  const events = Array.from({length: 100}, (_, index) => nowMs - (23 * 3600 * 1000) + index * 800 * 1000);
  await db.doc(`adminRateLimits/${SA_DAY}_contactReveal`).set({adminUid: SA_DAY, bucket: "contactReveal", events});
  const error = await expectCode(
    mod.revealContactForAdminData(call(SA_DAY, revealData()), deps()),
    "resource-exhausted",
    "RATE_LIMITED",
  );
  assert.equal(error.details.retryAfterSeconds, 3600);
  autoAdvance = true;
});

test("reveal: if the audit write fails, no value is returned and nothing is stored", {skip}, async () => {
  const before = await rowsBy(SA_FAIL);
  // A Firestore whose transactions fail when the audit row is created.
  const failing = new Proxy(db, {
    get(target, prop) {
      if (prop === "runTransaction") {
        return (fn) => target.runTransaction((transaction) => fn(new Proxy(transaction, {
          get(tx, key) {
            if (key === "create") return () => { throw new Error("simulated audit write failure"); };
            const value = tx[key];
            return typeof value === "function" ? value.bind(tx) : value;
          },
        })), {maxAttempts: 1});
      }
      const value = target[prop];
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
  let result;
  const error = await expectCode(
    (async () => {
      result = await mod.revealContactForAdminData(call(SA_FAIL, revealData()), {firestore: failing, authClient, now});
    })(),
    "internal",
    "AUDIT_WRITE_FAILED",
  );
  assert.equal(result, undefined);
  assert.ok(!JSON.stringify(error.details ?? {}).includes(national(P1)));
  assert.ok(!error.message.includes(national(P1)));
  assert.equal((await rowsBy(SA_FAIL)).length, before.length);
  const limit = await db.doc(`adminRateLimits/${SA_FAIL}_contactReveal`).get();
  assert.equal(limit.exists, false, "the rate-limit update rolled back with the audit row");

  // A commit that fails after the callback (e.g. contention) also returns nothing.
  const commitFails = new Proxy(db, {
    get(target, prop) {
      if (prop === "runTransaction") return async () => { throw Object.assign(new Error("ABORTED"), {code: 10}); };
      const value = target[prop];
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
  await expectCode(
    mod.revealContactForAdminData(call(SA_FAIL, revealData()), {firestore: commitFails, authClient, now}),
    "internal",
    "AUDIT_WRITE_FAILED",
  );
});

// --- getMaskedContactsForAdmin ---------------------------------------------

test("masked contacts: users get dashboard-format masks; unknown ids get the empty shape", {skip}, async () => {
  const unknown = id("unknown");
  const result = await mod.getMaskedContactsForAdminData(call(SA, {userIds: [PARENT, LEGACY_PHONE, MOBILE_ONLY, AUTH_ONLY, unknown]}), deps());
  assert.deepEqual(result.contacts[PARENT], {maskedPhone: masked(P1), maskedEmail: "as***@example.com", hasPhone: true, hasEmail: true});
  assert.equal(result.contacts[LEGACY_PHONE].maskedPhone, masked(P3));
  assert.equal(result.contacts[MOBILE_ONLY].maskedPhone, masked(P4));
  // No Auth fallback for display.
  assert.deepEqual(result.contacts[AUTH_ONLY], {maskedPhone: null, maskedEmail: null, hasPhone: false, hasEmail: false});
  assert.deepEqual(result.contacts[unknown], {maskedPhone: null, maskedEmail: null, hasPhone: false, hasEmail: false});
  const serialized = JSON.stringify(result);
  for (const raw of RAW_VALUES) assert.ok(!serialized.includes(raw), raw);
});

test("masked contacts: support tickets", {skip}, async () => {
  const result = await mod.getMaskedContactsForAdminData(call(SA, {supportTicketIds: [TICKET, TICKET_EMPTY, id("none")]}), deps());
  assert.deepEqual(result.tickets[TICKET], {maskedPhone: masked(PT), hasPhone: true});
  assert.deepEqual(result.tickets[TICKET_EMPTY], {maskedPhone: null, hasPhone: false});
  assert.deepEqual(result.tickets[id("none")], {maskedPhone: null, hasPhone: false});
});

test("masked contacts: guard and input limits", {skip}, async () => {
  await expectCode(mod.getMaskedContactsForAdminData(call(CS, {userIds: [PARENT]}), deps()), "permission-denied", "ROLE_NOT_ALLOWED");
  await expectCode(mod.getMaskedContactsForAdminData(call(null, {userIds: [PARENT]}), deps()), "unauthenticated");
  for (const data of [
    {},
    {userIds: [PARENT], supportTicketIds: [TICKET]},
    {userIds: []},
    {userIds: Array.from({length: 51}, (_, index) => `u${index}`)},
    {userIds: [PARENT, PARENT]},
    {userIds: ["a/b"]},
    {userIds: "not-a-list"},
  ]) {
    await expectCode(mod.getMaskedContactsForAdminData(call(SA, data), deps()), "invalid-argument", "INVALID_INPUT");
  }
  const fifty = await mod.getMaskedContactsForAdminData(call(SA, {userIds: Array.from({length: 50}, (_, index) => `u${RUN}${index}`)}), deps());
  assert.equal(Object.keys(fifty.contacts).length, 50);
  assert.equal((await rowsBy(CS)).length, 0);
});

// --- findUsersByContactForAdmin --------------------------------------------

test("contact search: phone matches across phoneNumber, phone and mobileNumber; log keeps a count only", {skip}, async () => {
  const byPhone = await mod.findUsersByContactForAdminData(call(SA_SEARCH, {query: `${national(P3).slice(0, 5)} ${national(P3).slice(5)}`}), deps());
  assert.deepEqual(byPhone.matches, [{userId: LEGACY_PHONE, maskedPhone: masked(P3), maskedEmail: null, matchedOn: "phone"}]);
  const byMobile = await mod.findUsersByContactForAdminData(call(SA_SEARCH, {query: `+91 ${national(P4).slice(0, 5)}-${national(P4).slice(5)}`}), deps());
  assert.deepEqual(byMobile.matches.map((match) => match.userId), [MOBILE_ONLY]);
  const byNumber = await mod.findUsersByContactForAdminData(call(SA_SEARCH, {query: `0${national(P2)}`}), deps());
  assert.deepEqual(byNumber.matches.map((match) => match.userId), [PROVIDER]);

  const rows = (await rowsBy(SA_SEARCH)).filter((row) => row.action === "contact.search");
  assert.equal(rows.length, 3);
  for (const row of rows) {
    assert.deepEqual(Object.keys(row.after).sort(), ["matchCount", "matchedOn"]);
    assert.equal(row.after.matchCount, 1);
    assert.equal(row.targetType, "query");
    assert.equal(row.targetId, "");
    const serialized = JSON.stringify(row);
    for (const leak of [national(P3), national(P4), national(P2)]) {
      assert.ok(!serialized.includes(leak), leak);
    }
  }
});

test("contact search: email is matched lower-cased and as typed; misses return none", {skip}, async () => {
  const result = await mod.findUsersByContactForAdminData(call(SA_SEARCH, {query: ` ${E_PARENT.replace("asha.k", "Asha.K").replace("example.com", "Example.com")} `}), deps());
  assert.deepEqual(result.matches, [{userId: PARENT, maskedPhone: masked(P1), maskedEmail: "as***@example.com", matchedOn: "email"}]);
  const miss = await mod.findUsersByContactForAdminData(call(SA_SEARCH, {query: `nobody.${RUN}@example.com`}), deps());
  assert.deepEqual(miss.matches, []);
  const rows = (await rowsBy(SA_SEARCH)).filter((row) => row.action === "contact.search");
  assert.ok(rows.some((row) => row.after.matchCount === 0 && row.after.matchedOn === "email"));
  for (const row of rows) assert.ok(!JSON.stringify(row).toLowerCase().includes(E_PARENT.toLowerCase()));
});

test("contact search: invalid queries, guard and its own rate-limit bucket", {skip}, async () => {
  for (const query of ["priya", "12345", "a@b", "", "x".repeat(255), 42]) {
    await expectCode(mod.findUsersByContactForAdminData(call(SA_SEARCH, {query}), deps()), "invalid-argument");
  }
  await expectCode(mod.findUsersByContactForAdminData(call(FA, {query: national(P1)}), deps()), "permission-denied", "ROLE_NOT_ALLOWED");

  const searcher = id("sa-search-limit");
  await db.doc(`users/${searcher}`).set({adminRole: "superAdmin", accountStatus: "active"});
  authUsers.set(searcher, {});
  const events = Array.from({length: 20}, (_, index) => clockMs - index * 1000);
  await db.doc(`adminRateLimits/${searcher}_contactSearch`).set({events});
  const error = await expectCode(
    mod.findUsersByContactForAdminData(call(searcher, {query: national(P1)}), deps()),
    "resource-exhausted",
    "RATE_LIMITED",
  );
  assert.ok(error.details.retryAfterSeconds > 0);
  const rows = await rowsBy(searcher);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].action, "contact.search_denied");
  assert.deepEqual(rows[0].after, {matchedOn: "phone", outcome: "RATE_LIMITED"});
  // The reveal bucket is separate.
  const reveal = await mod.revealContactForAdminData(call(searcher, revealData()), deps());
  assert.equal(reveal.outcome, "REVEALED");
});

// --- listAdminMembersForSuperAdmin -----------------------------------------

test("admin members: admin accounts only, with email, role, status and providers", {skip}, async () => {
  const result = await mod.listAdminMembersForSuperAdminData(call(SA, {}), deps());
  const byUid = new Map(result.members.map((member) => [member.uid, member]));
  assert.deepEqual(byUid.get(SA2), {
    uid: SA2,
    displayName: "Admin superAdmin",
    email: E_TEAM,
    adminRole: "superAdmin",
    status: "active",
    providers: ["password"],
  });
  assert.equal(byUid.get(CS).adminRole, "customerSupportAdmin");
  assert.equal(byUid.get(FA).adminRole, "financeAdmin");
  assert.equal(byUid.get(SA_DISABLED).status, "inactive");
  assert.equal(byUid.get(SA_AUTH_DISABLED).status, "inactive");
  for (const nonAdmin of [PARENT, PROVIDER, AUTH_ONLY]) assert.equal(byUid.has(nonAdmin), false);
  // Not logged and not rate limited.
  assert.equal((await rowsBy(SA)).filter((row) => row.source === "listAdminMembersForSuperAdmin").length, 0);
  await expectCode(mod.listAdminMembersForSuperAdminData(call(CS, {}), deps()), "permission-denied", "ROLE_NOT_ALLOWED");
});

// --- global checks -----------------------------------------------------------

test("no adminAuditLogs row written by these tests contains a raw phone number or email", {skip}, async () => {
  const snapshot = await db.collection("adminAuditLogs").get();
  const ours = snapshot.docs.filter((doc) => String(doc.data().byUid ?? "").endsWith(RUN));
  assert.ok(ours.length > 20, `expected many rows, got ${ours.length}`);
  for (const doc of ours) {
    const serialized = JSON.stringify(doc.data());
    for (const raw of RAW_VALUES) {
      assert.ok(!serialized.includes(raw), `${doc.id} contains ${raw}`);
    }
  }
});

test("the payment-hold collection name matches the payment code", {skip}, () => {
  const {BLOCKED_RELATIONSHIP_PAYMENT_HOLDS_COLLECTION} = require("../lib/booking/application/paymentOrchestrationV3.js");
  assert.equal(mod.PAYMENT_HOLDS_COLLECTION, BLOCKED_RELATIONSHIP_PAYMENT_HOLDS_COLLECTION);
});
