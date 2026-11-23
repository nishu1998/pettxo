// Test-booking flag (approach B): unit checks that need no emulator.
require("./helpers/firebaseTestSafety").assertUnitTestIsolation();
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {createHash} = require("node:crypto");

const {
  BACKFILL_CUTOFF_CEILING,
  BACKFILL_MAX_PER_CALL,
  BOOKING_TEST_FLAGS_COLLECTION,
  bookingIdsFingerprint,
  parseBookingTestFlagInput,
} = require("../lib/admin/bookingTestFlag.js");
const {buildAdminLogRow} = require("../lib/admin/adminLog.js");

const actor = {uid: "sa-1", role: "superAdmin", displayName: "Asha Admin"};

function appCodeOf(fn) {
  try {
    fn();
  } catch (error) {
    return `${error.details?.appCode}:${error.details?.field}`;
  }
  return "no error";
}

test("constants match the owner decisions", () => {
  assert.equal(BOOKING_TEST_FLAGS_COLLECTION, "bookingTestFlags");
  assert.equal(BACKFILL_CUTOFF_CEILING.toISOString(), "2026-11-22T18:30:00.000Z");
  assert.equal(BACKFILL_MAX_PER_CALL, 450);
});

test("single input", () => {
  const ok = parseBookingTestFlagInput({
    mode: "single", bookingId: "bk-1", isTest: false, reason: "  Real booking  ", requestId: "req_12345678",
  });
  assert.deepEqual(ok, {mode: "single", bookingId: "bk-1", isTest: false, reason: "Real booking", requestId: "req_12345678"});
  const base = {mode: "single", bookingId: "bk-1", isTest: true, reason: "Test booking", requestId: "req_12345678"};
  assert.equal(appCodeOf(() => parseBookingTestFlagInput({...base, bookingId: " bk"})), "INVALID_INPUT:bookingId");
  assert.equal(appCodeOf(() => parseBookingTestFlagInput({...base, bookingId: "__x__"})), "INVALID_INPUT:bookingId");
  assert.equal(appCodeOf(() => parseBookingTestFlagInput({...base, isTest: 1})), "INVALID_INPUT:isTest");
  assert.equal(appCodeOf(() => parseBookingTestFlagInput({...base, reason: "98123 45678 called"})), "INVALID_INPUT:reason");
  assert.equal(appCodeOf(() => parseBookingTestFlagInput({...base, requestId: "has space 123"})), "INVALID_INPUT:requestId");
  assert.equal(appCodeOf(() => parseBookingTestFlagInput(null)), "INVALID_INPUT:mode");
});

test("backfill input: ceiling, zone, and apply needs the dry-run count and fingerprint", () => {
  const base = {mode: "backfill", cutoff: "2026-11-23T00:00:00+05:30", dryRun: true, reason: "Backfill", requestId: "req_12345678"};
  const dry = parseBookingTestFlagInput(base);
  assert.equal(dry.cutoff.toISOString(), "2026-11-22T18:30:00.000Z");
  assert.equal(dry.expectedTestCount, null);
  assert.equal(appCodeOf(() => parseBookingTestFlagInput({...base, cutoff: "2026-11-23T00:00:00.001+05:30"})), "INVALID_INPUT:cutoff");
  assert.equal(appCodeOf(() => parseBookingTestFlagInput({...base, cutoff: "2026-11-20"})), "INVALID_INPUT:cutoff");
  const apply = {...base, dryRun: false, expectedTestCount: 115, expectedFingerprint: "0123456789ab"};
  assert.equal(parseBookingTestFlagInput(apply).expectedTestCount, 115);
  assert.equal(appCodeOf(() => parseBookingTestFlagInput({...apply, expectedTestCount: 451})), "INVALID_INPUT:expectedTestCount");
  assert.equal(appCodeOf(() => parseBookingTestFlagInput({...apply, expectedTestCount: 1.5})), "INVALID_INPUT:expectedTestCount");
  assert.equal(appCodeOf(() => parseBookingTestFlagInput({...apply, expectedFingerprint: "ABCDEF012345"})), "INVALID_INPUT:expectedFingerprint");
});

test("fingerprint is sha256 of the sorted ids, 12 hex", () => {
  const expected = createHash("sha256").update("a\nb\nc").digest("hex").slice(0, 12);
  assert.equal(bookingIdsFingerprint(["c", "a", "b"]), expected);
  assert.match(bookingIdsFingerprint([]), /^[0-9a-f]{12}$/);
});

test("adminLog accepts the new booking types and still refuses unknown ones", () => {
  for (const [action, targetType] of [
    ["booking.test_marked", "booking"],
    ["booking.test_unmarked", "booking"],
    ["booking.test_backfill", "bookingSet"],
  ]) {
    const row = buildAdminLogRow(actor, {type: "booking", action, targetType, targetId: "bk-1", source: "setBookingTestFlagForAdmin"});
    assert.equal(row.type, "booking");
    assert.equal(row.action, action);
  }
  assert.throws(() => buildAdminLogRow(actor, {
    type: "booking", action: "booking.delete", targetType: "booking", targetId: "bk-1", source: "x",
  }));
});

test("the flag module never writes bookings or any booking or payment record", () => {
  const source = fs.readFileSync(path.join(__dirname, "..", "src", "admin", "bookingTestFlag.ts"), "utf8");
  const collections = [...source.matchAll(/collection\(\s*"([^"]+)"/g)].map((match) => match[1]);
  assert.deepEqual([...new Set(collections)].sort(), ["bookings"]);
  // Bookings are only read: by id inside the single transaction and by the paged scan.
  assert.doesNotMatch(source, /bookingRef\s*,\s*\{|transaction\.(set|update|delete|create)\(\s*bookingRef/);
  // (createHash(...).update is the fingerprint, not a write.)
  assert.doesNotMatch(source.replace(/createHash\("sha256"\)\.update/g, ""), /\.(set|update)\(/);
  assert.doesNotMatch(source, /bookingFinancials|refunds|payments|providerPayouts|manualSettlementObligations|disputes/);
});
