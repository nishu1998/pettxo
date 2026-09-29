const test = require("node:test");
const assert = require("node:assert/strict");

const {
  canClaimProtectedUsername,
  classifyUsernameReservation,
  normalizeUsername,
  usernameReservationConflicts,
  validateNormalizedUsername,
} = require("../lib/identity/username.js");

const officialClaimant = {
  uid: "Yo5HtRbusBNl9NkPhelXp5naNF93",
  email: "hello@pettxo.com",
  emailVerified: true,
};

test("normalization makes casing, at-prefix, and surrounding whitespace equivalent", () => {
  for (const value of ["pettxo", "Pettxo", "PETTXO", "@pettxo", " pettxo "]) {
    assert.equal(normalizeUsername(value), "pettxo");
  }
});

test("normalization does not hide unsupported Unicode or interior characters", () => {
  const zeroWidth = normalizeUsername("pet\u200Btxo");
  const nonAscii = normalizeUsername("pèttxo");
  assert.match(validateNormalizedUsername(zeroWidth), /lowercase letters/);
  assert.match(validateNormalizedUsername(nonAscii), /lowercase letters/);
});

test("pettxo stays reserved unless the exact verified official identity claims it", () => {
  assert.equal(validateNormalizedUsername("pettxo"), "This username is reserved.");
  assert.equal(canClaimProtectedUsername("pettxo", officialClaimant), true);
  assert.equal(
    validateNormalizedUsername("pettxo", {
      allowReserved: canClaimProtectedUsername("pettxo", officialClaimant),
    }),
    null,
  );

  for (const claimant of [
    {...officialClaimant, uid: "another-uid"},
    {...officialClaimant, email: "other@pettxo.com"},
    {...officialClaimant, emailVerified: false},
  ]) {
    assert.equal(canClaimProtectedUsername("pettxo", claimant), false);
  }
});

test("reservation classification separates taken, owned, stale, and unused names", () => {
  const base = {
    requestingUid: "requester",
    requestedUsername: "sample_name",
    reservationExists: true,
    reservationUid: "owner",
    ownerExists: true,
    ownerUsername: "sample_name",
  };
  assert.equal(classifyUsernameReservation(base), "taken");
  assert.equal(
    classifyUsernameReservation({...base, reservationUid: "requester"}),
    "owned",
  );
  assert.equal(
    classifyUsernameReservation({...base, reservationExists: false}),
    "available",
  );
  assert.equal(
    classifyUsernameReservation({...base, ownerExists: false}),
    "staleReservation",
  );
  assert.equal(
    classifyUsernameReservation({...base, ownerUsername: "different_name"}),
    "staleReservation",
  );
  assert.equal(
    classifyUsernameReservation({...base, reservationUid: ""}),
    "staleReservation",
  );
});

test("a concurrent claim retry rejects the second claimant", () => {
  let reservationUid = "";
  const firstRead = usernameReservationConflicts({
    reservationExists: false,
    reservationUid,
    requestingUid: "first-user",
  });
  assert.equal(firstRead, false);

  reservationUid = "first-user";
  const secondTransactionRetry = usernameReservationConflicts({
    reservationExists: true,
    reservationUid,
    requestingUid: "second-user",
  });
  assert.equal(secondTransactionRetry, true);
  assert.equal(
    usernameReservationConflicts({
      reservationExists: true,
      reservationUid,
      requestingUid: "first-user",
    }),
    false,
  );
  assert.equal(
    usernameReservationConflicts({
      reservationExists: true,
      reservationUid: "",
      requestingUid: "first-user",
    }),
    true,
  );
});
