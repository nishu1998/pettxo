// Test-booking flag (approach B): setBookingTestFlagForAdmin against the
// Firestore emulator. Each test uses its own demo-* project so the backfill
// scan sees only the bookings that test seeds. Firebase Auth is a fake passed
// through deps (the test emulators run Firestore and Storage only).
const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({services: ["firestore"]});
const test = require("node:test");
const assert = require("node:assert/strict");
const {createHash, randomUUID} = require("node:crypto");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");

const skip = !firebaseEmulator.enabled;

const VALID_AFTER = "Sat, 01 Nov 2026 00:00:00 GMT";
const AUTH_TIME = Date.parse(VALID_AFTER) / 1000 + 3600;
const CUTOFF = "2026-11-23T00:00:00+05:30";
const CUTOFF_MS = Date.parse(CUTOFF);

let mod;
const apps = [];

const authClient = {
  async getUser(uid) {
    return {uid, disabled: false, tokensValidAfterTime: VALID_AFTER, providerData: []};
  },
};

const ADMINS = {
  sa: {adminRole: "superAdmin", displayName: "Asha Admin", accountStatus: "active"},
  sa2: {adminRole: "superAdmin", displayName: "Second Admin", accountStatus: "active"},
  cs: {adminRole: "customerSupportAdmin", displayName: "CS Admin", accountStatus: "active"},
  fa: {adminRole: "financeAdmin", displayName: "Finance Admin", accountStatus: "active"},
  saDisabled: {adminRole: "superAdmin", displayName: "Disabled Admin", accountStatus: "active", adminDisabled: true},
  saSuspended: {adminRole: "superAdmin", displayName: "Suspended Admin", accountStatus: "suspended"},
  parent: {role: "petParent", displayName: "Parent"},
};

async function world() {
  const projectId = `demo-btf-${randomUUID().slice(0, 8)}`;
  const app = initializeApp({projectId}, `btf-${randomUUID()}`);
  apps.push(app);
  const db = getFirestore(app);
  await Promise.all(Object.entries(ADMINS).map(([uid, data]) => db.doc(`users/${uid}`).set(data)));
  let counter = 0;
  const requestId = () => `req_${randomUUID().slice(0, 8)}_${++counter}`;
  const run = (uid, data) => mod.setBookingTestFlagForAdminData(
    {auth: uid ? {uid, token: {auth_time: AUTH_TIME}} : null, data},
    {firestore: db, authClient},
  );
  return {db, run, requestId};
}

function booking(createdAt, extra = {}) {
  return {
    schemaVersion: 3,
    stateQueryValue: "COMPLETED",
    customerId: "parent",
    serviceOwnerId: "provider",
    createdAt: createdAt == null ? null : Timestamp.fromMillis(createdAt),
    updatedAt: Timestamp.fromMillis(Date.parse("2026-11-01T00:00:00Z")),
    payment: {amountPaise: 49900, status: "CAPTURED"},
    ...extra,
  };
}

async function seedBookings(db, entries) {
  for (let i = 0; i < entries.length; i += 400) {
    const batch = db.batch();
    for (const [id, data] of entries.slice(i, i + 400)) batch.set(db.doc(`bookings/${id}`), data);
    await batch.commit();
  }
}

/** Booking data plus update time, to prove the callable never writes bookings. */
async function bookingSnapshot(db) {
  const snapshot = await db.collection("bookings").get();
  return Object.fromEntries(snapshot.docs.map((doc) => [doc.id, {
    data: doc.data(),
    updateTime: doc.updateTime.toMillis(),
  }]));
}

async function flagIds(db) {
  return (await db.collection("bookingTestFlags").get()).docs.map((doc) => doc.id).sort();
}

async function logRows(db) {
  return (await db.collection("adminAuditLogs").get()).docs.map((doc) => ({id: doc.id, ...doc.data()}));
}

async function expectCode(promise, code, appCode, field) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, code, error.message);
    assert.equal(error.details?.appCode, appCode, error.message);
    if (field) assert.equal(error.details?.field, field);
    return true;
  });
}

const fingerprint = (ids) => createHash("sha256").update([...ids].sort().join("\n")).digest("hex").slice(0, 12);
const before = (minutes) => CUTOFF_MS - minutes * 60_000;

test.before(() => {
  if (skip) return;
  mod = require("../lib/admin/bookingTestFlag.js");
});

test.after(async () => {
  await Promise.all(apps.map((app) => deleteApp(app)));
});

test("single: mark, idempotent repeat and retry, unmark, audit row shape; booking never written", {skip}, async () => {
  const {db, run, requestId} = await world();
  await seedBookings(db, [["bk-1", booking(before(60))]]);
  const bookingsBefore = await bookingSnapshot(db);

  const markId = requestId();
  const marked = await run("sa", {mode: "single", bookingId: "bk-1", isTest: true, reason: "Owner test booking", requestId: markId});
  assert.deepEqual(marked, {
    mode: "single", bookingId: "bk-1", isTest: true, changed: true, logId: `bookingTestFlag_sa_${markId}`,
  });

  const flag = (await db.doc("bookingTestFlags/bk-1").get()).data();
  assert.deepEqual(Object.keys(flag).sort(), ["bookingId", "markedAt", "markedByUid", "source"]);
  assert.equal(flag.bookingId, "bk-1");
  assert.equal(flag.source, "admin");
  assert.equal(flag.markedByUid, "sa");
  assert.ok(flag.markedAt instanceof Timestamp);

  let rows = await logRows(db);
  assert.equal(rows.length, 1);
  const row = rows[0];
  assert.deepEqual(Object.keys(row).sort(), [
    "action", "after", "at", "before", "byName", "byRole", "byUid", "context", "createdAt", "id",
    "reason", "reasonCode", "requestId", "schemaVersion", "source", "targetId", "targetType", "type",
  ]);
  assert.equal(row.id, marked.logId);
  assert.equal(row.schemaVersion, 2);
  assert.equal(row.type, "booking");
  assert.equal(row.action, "booking.test_marked");
  assert.equal(row.targetType, "booking");
  assert.equal(row.targetId, "bk-1");
  assert.deepEqual(row.before, {isTest: false});
  assert.deepEqual(row.after, {isTest: true});
  assert.equal(row.reason, "Owner test booking");
  assert.equal(row.reasonCode, null);
  assert.deepEqual(row.context, {bookingState: "COMPLETED"});
  assert.equal(row.requestId, markId);
  assert.equal(row.source, "setBookingTestFlagForAdmin");
  assert.equal(row.byUid, "sa");
  assert.equal(row.byName, "Asha Admin");
  assert.equal(row.byRole, "superAdmin");
  assert.ok(row.createdAt instanceof Timestamp);

  // Already test: ok, no new row (another admin, new requestId).
  const again = await run("sa2", {mode: "single", bookingId: "bk-1", isTest: true, reason: "Again", requestId: requestId()});
  assert.deepEqual(again, {mode: "single", bookingId: "bk-1", isTest: true, changed: false, logId: null});
  // A retry of the committed request: same log id, no new row.
  const retry = await run("sa", {mode: "single", bookingId: "bk-1", isTest: true, reason: "Owner test booking", requestId: markId});
  assert.equal(retry.changed, false);
  assert.equal(retry.logId, marked.logId);
  assert.equal((await logRows(db)).length, 1);
  // The same requestId for a different change is refused.
  await expectCode(
    run("sa", {mode: "single", bookingId: "bk-1", isTest: false, reason: "Different", requestId: markId}),
    "invalid-argument", "REQUEST_ID_REUSED",
  );

  const unmarkId = requestId();
  const unmarked = await run("sa", {mode: "single", bookingId: "bk-1", isTest: false, reason: "Real after all", requestId: unmarkId});
  assert.equal(unmarked.changed, true);
  assert.equal((await db.doc("bookingTestFlags/bk-1").get()).exists, false);
  rows = await logRows(db);
  assert.equal(rows.length, 2);
  const unmarkRow = rows.find((entry) => entry.id === unmarked.logId);
  assert.equal(unmarkRow.action, "booking.test_unmarked");
  assert.deepEqual(unmarkRow.before, {isTest: true});
  assert.deepEqual(unmarkRow.after, {isTest: false});

  const noop = await run("sa", {mode: "single", bookingId: "bk-1", isTest: false, reason: "Still real", requestId: requestId()});
  assert.equal(noop.changed, false);
  assert.equal((await logRows(db)).length, 2);

  assert.deepEqual(await bookingSnapshot(db), bookingsBefore);
});

test("single: booking not found and invalid input write nothing", {skip}, async () => {
  const {db, run, requestId} = await world();
  await seedBookings(db, [["bk-1", booking(before(60))]]);
  await expectCode(
    run("sa", {mode: "single", bookingId: "bk-missing", isTest: true, reason: "Test booking", requestId: requestId()}),
    "not-found", "BOOKING_NOT_FOUND",
  );
  const base = {mode: "single", bookingId: "bk-1", isTest: true, reason: "Test booking"};
  const cases = [
    [{reason: undefined}, "reason"],
    [{reason: "ok"}, "reason"],
    [{reason: "x".repeat(201)}, "reason"],
    [{reason: "call him on +91 98123 45678"}, "reason"],
    [{reason: "mail asha@example.com"}, "reason"],
    [{reason: "bad\u0007reason"}, "reason"],
    [{bookingId: "a/b"}, "bookingId"],
    [{bookingId: ""}, "bookingId"],
    [{isTest: "yes"}, "isTest"],
    [{requestId: "short"}, "requestId"],
    [{mode: "bulk"}, "mode"],
  ];
  for (const [override, field] of cases) {
    await expectCode(run("sa", {...base, requestId: requestId(), ...override}), "invalid-argument", "INVALID_INPUT", field);
  }
  // 200 characters is allowed.
  const ok = await run("sa", {...base, reason: "y".repeat(200), requestId: requestId()});
  assert.equal(ok.changed, true);
  assert.equal((await logRows(db)).length, 1);
  assert.deepEqual(await flagIds(db), ["bk-1"]);
});

test("roles: only an active Super Admin; refusals write nothing", {skip}, async () => {
  const {db, run, requestId} = await world();
  await seedBookings(db, [["bk-1", booking(before(60))]]);
  const single = () => ({mode: "single", bookingId: "bk-1", isTest: true, reason: "Test booking", requestId: requestId()});
  const dry = () => ({mode: "backfill", cutoff: CUTOFF, dryRun: true, reason: "Backfill", requestId: requestId()});
  for (const data of [single, dry]) {
    await expectCode(run(null, data()), "unauthenticated", "UNAUTHENTICATED");
    await expectCode(run("cs", data()), "permission-denied", "ROLE_NOT_ALLOWED");
    await expectCode(run("fa", data()), "permission-denied", "ROLE_NOT_ALLOWED");
    await expectCode(run("parent", data()), "permission-denied", "ROLE_NOT_ALLOWED");
    await expectCode(run("saDisabled", data()), "permission-denied", "ADMIN_NOT_ACTIVE");
    await expectCode(run("saSuspended", data()), "permission-denied", "ADMIN_NOT_ACTIVE");
  }
  assert.deepEqual(await flagIds(db), []);
  assert.equal((await logRows(db)).length, 0);
});

test("backfill: dry run vs apply, mismatches write nothing, re-run is 0, only before the cutoff", {skip}, async () => {
  const {db, run, requestId} = await world();
  await seedBookings(db, [
    ["bk-b", booking(before(60 * 24 * 10))],
    ["bk-a", booking(before(60 * 24 * 30))],
    ["bk-d", booking(before(1))],
    ["bk-c", booking(before(60 * 24))],
    ["bk-flagged", booking(before(60 * 24 * 2))],
    ["bk-at-cutoff", booking(CUTOFF_MS)],
    ["bk-after", booking(CUTOFF_MS + 60_000)],
    ["bk-no-created", booking(null)],
  ]);
  await db.doc("bookingTestFlags/bk-flagged").set({bookingId: "bk-flagged", source: "admin", markedByUid: "sa"});
  const bookingsBefore = await bookingSnapshot(db);
  const expectedIds = ["bk-a", "bk-b", "bk-c", "bk-d"];

  const dry = await run("sa", {mode: "backfill", cutoff: CUTOFF, dryRun: true, reason: "Attested test data", requestId: requestId()});
  assert.deepEqual(dry, {
    mode: "backfill",
    dryRun: true,
    cutoff: "2026-11-22T18:30:00.000Z",
    testCount: 4,
    candidateCount: 4,
    remainingAfterThisCall: 0,
    alreadyTest: 1,
    afterCutoff: 2,
    missingCreatedAt: 1,
    bookingsScanned: 8,
    earliestCreatedAt: new Date(before(60 * 24 * 30)).toISOString(),
    latestCreatedAt: new Date(before(1)).toISOString(),
    sampleIds: expectedIds,
    fingerprint: fingerprint(expectedIds),
    logId: null,
  });
  // Dry runs write nothing and are not logged (Q3).
  assert.deepEqual(await flagIds(db), ["bk-flagged"]);
  assert.equal((await logRows(db)).length, 0);

  const apply = (overrides = {}) => run("sa", {
    mode: "backfill", cutoff: CUTOFF, dryRun: false, reason: "Attested test data", requestId: requestId(),
    expectedTestCount: dry.testCount, expectedFingerprint: dry.fingerprint, ...overrides,
  });
  await expectCode(apply({expectedTestCount: undefined}), "invalid-argument", "INVALID_INPUT", "expectedTestCount");
  await expectCode(apply({expectedFingerprint: undefined}), "invalid-argument", "INVALID_INPUT", "expectedFingerprint");
  await expectCode(apply({expectedTestCount: 115}), "failed-precondition", "COUNT_MISMATCH");
  await expectCode(apply({expectedFingerprint: "0123456789ab"}), "failed-precondition", "FINGERPRINT_MISMATCH");
  assert.deepEqual(await flagIds(db), ["bk-flagged"]);
  assert.equal((await logRows(db)).length, 0);

  const applyId = requestId();
  const applied = await apply({requestId: applyId});
  assert.equal(applied.dryRun, false);
  assert.equal(applied.testCount, 4);
  assert.equal(applied.logId, `bookingTestBackfill_sa_${applyId}`);
  assert.deepEqual(await flagIds(db), [...expectedIds, "bk-flagged"].sort());
  for (const id of expectedIds) {
    const flag = (await db.doc(`bookingTestFlags/${id}`).get()).data();
    assert.deepEqual(Object.keys(flag).sort(), ["backfillLogId", "bookingId", "markedAt", "markedByUid", "source"]);
    assert.equal(flag.bookingId, id);
    assert.equal(flag.source, "backfill");
    assert.equal(flag.markedByUid, "sa");
    assert.equal(flag.backfillLogId, applied.logId);
  }
  const rows = await logRows(db);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].id, applied.logId);
  assert.equal(rows[0].type, "booking");
  assert.equal(rows[0].action, "booking.test_backfill");
  assert.equal(rows[0].targetType, "bookingSet");
  assert.equal(rows[0].targetId, dry.fingerprint);
  assert.deepEqual(rows[0].after, {cutoff: "2026-11-22T18:30:00.000Z", testCount: 4, bookingIds: expectedIds});
  assert.equal(rows[0].reason, "Attested test data");
  assert.equal(rows[0].source, "setBookingTestFlagForAdmin");

  // The same requestId can't be applied twice.
  const rerunDry = await run("sa", {mode: "backfill", cutoff: CUTOFF, dryRun: true, reason: "Check", requestId: requestId()});
  assert.equal(rerunDry.testCount, 0);
  assert.equal(rerunDry.alreadyTest, 5);
  assert.equal(rerunDry.fingerprint, fingerprint([]));
  const empty = await apply({expectedTestCount: 0, expectedFingerprint: rerunDry.fingerprint});
  assert.equal(empty.testCount, 0);
  assert.equal(empty.logId, null);
  assert.equal((await logRows(db)).length, 1);

  // Bookings are never modified.
  assert.deepEqual(await bookingSnapshot(db), bookingsBefore);
});

test("backfill: cutoff ceiling and format", {skip}, async () => {
  const {db, run, requestId} = await world();
  await seedBookings(db, [["bk-1", booking(before(60))]]);
  const dry = (cutoff) => run("sa", {mode: "backfill", cutoff, dryRun: true, reason: "Backfill", requestId: requestId()});
  await expectCode(dry("2026-11-23T00:00:01+05:30"), "invalid-argument", "INVALID_INPUT", "cutoff");
  await expectCode(dry("2026-12-01T00:00:00Z"), "invalid-argument", "INVALID_INPUT", "cutoff");
  await expectCode(dry("2026-11-22T10:00:00"), "invalid-argument", "INVALID_INPUT", "cutoff");
  await expectCode(dry("yesterday"), "invalid-argument", "INVALID_INPUT", "cutoff");
  await expectCode(dry(undefined), "invalid-argument", "INVALID_INPUT", "cutoff");
  await expectCode(
    run("sa", {mode: "backfill", cutoff: CUTOFF, reason: "Backfill", requestId: requestId()}),
    "invalid-argument", "INVALID_INPUT", "dryRun",
  );
  // Exactly the ceiling, in another zone, is allowed.
  assert.equal((await dry("2026-11-22T18:30:00Z")).testCount, 1);
  assert.equal((await dry("2026-11-01T00:00:00+05:30")).testCount, 0);
});

test("backfill: 450 per call, paged scan past 500 bookings, then the rest, then 0", {skip}, async () => {
  const {db, run, requestId} = await world();
  const entries = [];
  for (let i = 0; i < 501; i++) entries.push([`bk-${String(i).padStart(4, "0")}`, booking(before(10 + i))]);
  entries.push(["bk-zz-after", booking(CUTOFF_MS + 1)]);
  await seedBookings(db, entries);

  const step = async () => {
    const dry = await run("sa", {mode: "backfill", cutoff: CUTOFF, dryRun: true, reason: "Backfill", requestId: requestId()});
    const applied = dry.testCount === 0 ? null : await run("sa", {
      mode: "backfill", cutoff: CUTOFF, dryRun: false, reason: "Backfill", requestId: requestId(),
      expectedTestCount: dry.testCount, expectedFingerprint: dry.fingerprint,
    });
    return {dry, applied};
  };

  const first = await step();
  assert.equal(first.dry.bookingsScanned, 502);
  assert.equal(first.dry.candidateCount, 501);
  assert.equal(first.dry.testCount, 450);
  assert.equal(first.dry.remainingAfterThisCall, 51);
  assert.equal(first.dry.sampleIds.length, 20);
  assert.equal(first.dry.sampleIds[0], "bk-0000");
  assert.equal(first.applied.testCount, 450);
  assert.equal((await flagIds(db)).length, 450);

  const second = await step();
  assert.equal(second.dry.testCount, 51);
  assert.equal(second.dry.alreadyTest, 450);
  assert.equal(second.applied.testCount, 51);

  const third = await step();
  assert.equal(third.dry.testCount, 0);
  assert.equal(third.applied, null);

  const ids = await flagIds(db);
  assert.equal(ids.length, 501);
  assert.equal(ids.includes("bk-zz-after"), false);
  const rows = await logRows(db);
  assert.equal(rows.length, 2);
  assert.deepEqual(rows.map((row) => row.after.testCount).sort((a, b) => a - b), [51, 450]);
});
