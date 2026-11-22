require("./helpers/firebaseTestSafety").assertUnitTestIsolation();
const test = require("node:test");
const assert = require("node:assert/strict");

const {
  containsRawContact,
  maskEmail,
  maskEmailOrNull,
  maskPhone,
  maskPhoneOrNull,
  normalizeIndianPhone,
  pickPrivateEmail,
  pickPrivatePhone,
} = require("../lib/admin/contactMasking.js");

// Cases copied from pettxo-admin-dashboard test/core/formatting/formatting_test.dart
// and test/features/people/people_rules_test.dart, so server masking matches the UI.

test("maskPhone: Indian E.164 numbers (dashboard cases)", () => {
  assert.equal(maskPhone("+919000000001"), "+91 90•••• •001");
  assert.equal(maskPhone("+91 90000 00001"), "+91 90•••• •001");
  assert.equal(maskPhone("9000000001"), "+91 90•••• •001");
});

test("maskPhone: never shows the middle digits (dashboard cases)", () => {
  const masked = maskPhone("+919000000001");
  assert.ok(!masked.includes("12345"));
  assert.ok(!masked.includes("9000000001"));
});

test("maskPhone: other countries keep only country digits and last 3 (dashboard cases)", () => {
  assert.equal(maskPhone("+14155550123"), "+14 ••••••123");
  assert.equal(maskPhone("+4479460000"), "+4 ••••••000");
});

test("maskPhone: bad input (dashboard cases)", () => {
  assert.equal(maskPhone(null), "•••");
  assert.equal(maskPhone(""), "•••");
  assert.equal(maskPhone("call me"), "•••");
});

test("maskPhone: short and unprefixed numbers", () => {
  assert.equal(maskPhone("123456"), "••••••456");
  assert.equal(maskPhone("12345"), "•••");
  assert.equal(maskPhone("(090) 000-0001"), "+91 09•••• •001");
});

test("normalizeIndianPhone: normalises to +91 (dashboard cases)", () => {
  assert.equal(normalizeIndianPhone("90000 00001"), "+919000000001");
  assert.equal(normalizeIndianPhone("09000000001"), "+919000000001");
  assert.equal(normalizeIndianPhone("919000000001"), "+919000000001");
  assert.equal(normalizeIndianPhone("+91 90000-00001"), "+919000000001");
});

test("normalizeIndianPhone: rejects non-phones (dashboard cases)", () => {
  assert.equal(normalizeIndianPhone("12345"), null);
  assert.equal(normalizeIndianPhone("BK-12345"), null);
  assert.equal(normalizeIndianPhone("priya"), null);
  assert.equal(normalizeIndianPhone("+12345"), null);
});

test("maskEmail: dashboard cases", () => {
  assert.equal(maskEmail("asha@example.com"), "as***@example.com");
  assert.equal(maskEmail(" Test.Person@Example.com "), "Te***@Example.com");
  assert.equal(maskEmail("r@x.in"), "***@x.in");
  assert.equal(maskEmail(null), "•••");
  assert.equal(maskEmail(""), "•••");
  assert.equal(maskEmail("not an email"), "•••");
  assert.equal(maskEmail("a@b"), "•••");
  assert.equal(maskEmail("@gmail.com"), "•••");
});

test("OrNull variants return null for missing values", () => {
  assert.equal(maskPhoneOrNull(""), null);
  assert.equal(maskPhoneOrNull(undefined), null);
  assert.equal(maskPhoneOrNull("+919000000001"), "+91 90•••• •001");
  assert.equal(maskEmailOrNull("  "), null);
  assert.equal(maskEmailOrNull("asha@example.com"), "as***@example.com");
});

test("pickPrivatePhone uses phoneNumber, then phone, then mobileNumber", () => {
  assert.deepEqual(pickPrivatePhone({phoneNumber: "+911", phone: "+912"}), {value: "+911", source: "phoneNumber"});
  assert.deepEqual(pickPrivatePhone({phoneNumber: " ", phone: "+912"}), {value: "+912", source: "phone"});
  assert.deepEqual(pickPrivatePhone({mobileNumber: "+913"}), {value: "+913", source: "mobileNumber"});
  assert.equal(pickPrivatePhone({}), null);
  assert.equal(pickPrivatePhone(null), null);
  assert.equal(pickPrivateEmail({email: " a@b.co "}), "a@b.co");
  assert.equal(pickPrivateEmail({}), null);
});

test("containsRawContact flags raw values and lets masked values pass", () => {
  for (const raw of [
    "+919000000001",
    "9000000001",
    "+91 90000 00001",
    "call 090-0000-0001 now",
    "asha@example.com",
    "x asha.k@mail.example.in y",
  ]) {
    assert.equal(containsRawContact(raw), true, raw);
  }
  for (const safe of [
    "+91 90•••• •001",
    "+14 ••••••123",
    "••••••456",
    "as***@example.com",
    "***@x.in",
    "2026-11-22",
    "2026-11-22T10:15:30.000Z",
    "booking-123456",
    "Customer asked for a call back",
  ]) {
    assert.equal(containsRawContact(safe), false, safe);
  }
});
