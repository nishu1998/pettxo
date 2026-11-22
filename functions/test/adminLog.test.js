require("./helpers/firebaseTestSafety").assertUnitTestIsolation();
const test = require("node:test");
const assert = require("node:assert/strict");
const {FieldValue} = require("firebase-admin/firestore");

const {
  AdminLogValidationError,
  assertNoRawContactInLog,
  buildAdminLogRow,
  writeAdminLog,
} = require("../lib/admin/adminLog.js");

const actor = {uid: "sa-1", role: "superAdmin", displayName: "Asha Admin"};

function baseEntry(overrides = {}) {
  return {
    type: "contact",
    action: "contact.reveal",
    targetType: "user",
    targetId: "user-1",
    before: null,
    after: {field: "phone", valueMasked: "+91 90•••• •001", outcome: "REVEALED"},
    reason: "Customer asked for a call back",
    reasonCode: "CALLBACK_REQUESTED",
    context: {type: "booking", id: "bk-1", purpose: "call"},
    requestId: "req_12345678",
    source: "revealContactForAdmin",
    ...overrides,
  };
}

function fakeFirestore() {
  const writes = [];
  let counter = 0;
  return {
    writes,
    collection(name) {
      return {
        doc(id) {
          const ref = {id: id ?? `auto-${++counter}`, collection: name};
          ref.create = async (data) => writes.push({mode: "direct", ref, data});
          return ref;
        },
      };
    },
  };
}

test("buildAdminLogRow produces the exact schemaVersion 2 field set", () => {
  const row = buildAdminLogRow(actor, baseEntry());
  assert.deepEqual(Object.keys(row).sort(), [
    "action", "after", "before", "byName", "byRole", "byUid", "context", "reason",
    "reasonCode", "requestId", "schemaVersion", "source", "targetId", "targetType", "type",
  ]);
  assert.equal(row.schemaVersion, 2);
  assert.equal(row.byUid, "sa-1");
  assert.equal(row.byName, "Asha Admin");
  assert.equal(row.byRole, "superAdmin");
  assert.equal(row.before, null);
});

test("writeAdminLog sets at and createdAt to the same server timestamp", async () => {
  const firestore = fakeFirestore();
  const id = await writeAdminLog(firestore, actor, baseEntry());
  assert.equal(id, "auto-1");
  const [{data, ref}] = firestore.writes;
  assert.equal(ref.collection, "adminAuditLogs");
  assert.ok(data.at instanceof FieldValue);
  assert.equal(data.at, data.createdAt);
  assert.ok(data.at.isEqual(FieldValue.serverTimestamp()));
});

test("writeAdminLog writes inside a transaction with an optional fixed id", async () => {
  const firestore = fakeFirestore();
  const created = [];
  const transaction = {create: (ref, data) => created.push({ref, data})};
  const id = await writeAdminLog(firestore, actor, baseEntry(), {transaction, docId: "fixed-id"});
  assert.equal(id, "fixed-id");
  assert.equal(created.length, 1);
  assert.equal(firestore.writes.length, 0, "no direct write outside the transaction");
});

test("closed lists for type, action and targetType", () => {
  assert.throws(() => buildAdminLogRow(actor, baseEntry({type: "misc"})), AdminLogValidationError);
  assert.throws(() => buildAdminLogRow(actor, baseEntry({action: "contact.leak"})), AdminLogValidationError);
  assert.throws(() => buildAdminLogRow(actor, baseEntry({targetType: "pet"})), AdminLogValidationError);
  assert.throws(() => buildAdminLogRow(actor, baseEntry({source: ""})), AdminLogValidationError);
});

test("reason is trimmed and capped at 300 characters", () => {
  assert.equal(buildAdminLogRow(actor, baseEntry({reason: "  Booking problem  "})).reason, "Booking problem");
  assert.equal(buildAdminLogRow(actor, baseEntry({reason: "x".repeat(300)})).reason.length, 300);
  assert.throws(() => buildAdminLogRow(actor, baseEntry({reason: "x".repeat(301)})), AdminLogValidationError);
});

test("the raw-value guard refuses phones and emails anywhere in before/after/context/reason", () => {
  const leaks = [
    {after: {valueMasked: "+919000000001"}},
    {after: {nested: {list: ["ok", "9000000001"]}}},
    {before: {email: "asha@example.com"}},
    {context: {type: "user", id: "asha@example.com"}},
    {reason: "called +91 90000 00001 twice"},
  ];
  for (const leak of leaks) {
    assert.throws(() => buildAdminLogRow(actor, baseEntry(leak)), AdminLogValidationError, JSON.stringify(leak));
  }
  assert.throws(() => assertNoRawContactInLog({after: {v: "r.k@mail.example.in"}}), AdminLogValidationError);
});

test("masked values pass the guard", () => {
  const row = buildAdminLogRow(actor, baseEntry({
    after: {field: "email", valueMasked: "as***@example.com", other: "***@x.in"},
    before: {phone: "+14 ••••••123"},
  }));
  assert.equal(row.after.valueMasked, "as***@example.com");
});

test("a failed guard writes nothing", async () => {
  const firestore = fakeFirestore();
  await assert.rejects(
    writeAdminLog(firestore, actor, baseEntry({after: {value: "+919000000001"}})),
    AdminLogValidationError,
  );
  assert.equal(firestore.writes.length, 0);
});
