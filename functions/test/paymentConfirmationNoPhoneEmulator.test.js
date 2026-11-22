// Phase 3B-4e: payment confirmation must not fail when a participant has no
// phone number on their Firebase Auth record. Uses the default Admin app
// (lib/shared/firebase), which does NOT ignore undefined values, exactly as
// production does.
const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({services: ["firestore"]});
const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");

const enabled = firebaseEmulator.enabled;

function strip(value) {
  if (Array.isArray(value)) return value.map(strip);
  if (value && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype) {
    return Object.fromEntries(Object.entries(value)
      .filter(([, entry]) => entry !== undefined)
      .map(([key, entry]) => [key, strip(entry)]));
  }
  return value;
}

function hasUndefined(value) {
  if (value === undefined) return true;
  if (Array.isArray(value)) return value.some(hasUndefined);
  if (value && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype) {
    return Object.values(value).some(hasUndefined);
  }
  return false;
}

test("confirmation succeeds when neither customer nor provider has an auth phone", {skip: !enabled}, async () => {
  const {db, auth} = require("../lib/shared/firebase.js");
  const originalGetUser = auth.getUser;
  auth.getUser = async (uid) => ({uid, displayName: uid});
  const race = require("./helpers/canonicalPaymentRaceFixture.js");
  const {finalizeCapturedCanonicalPaymentV3} = require("../lib/booking/application/paymentOrchestrationV3.js");
  const sfx = randomUUID().slice(0, 6);
  const parent = `nophone-par-${sfx}`;
  const provider = `nophone-pro-${sfx}`;
  const serviceId = `nophone-svc-${sfx}`;
  const ids = {
    bookingId: `nophone-bk-${sfx}`, paymentAttemptId: `nophone-at-${sfx}`,
    razorpayOrderId: `order_np_${sfx}`, razorpayPaymentId: `pay_np_${sfx}`,
    webhookEventId: "unused", refundInstructionId: "unused",
  };
  const base = race.buildCanonicalPaymentRaceFixture({ids});
  const booking = base.booking;
  booking.parentId = parent; booking.customerId = parent;
  booking.providerId = provider; booking.serviceOwnerId = provider;
  booking.participantIds = [parent, provider];
  booking.participants.parent.parentId = parent;
  booking.participants.provider.providerId = provider;
  booking.serviceId = serviceId; booking.service.serviceId = serviceId; booking.service.providerId = provider;
  for (const slot of booking.schedule.slots) {
    slot.serviceId = serviceId; slot.providerId = provider;
  }
  try {
    await Promise.all([
      db.doc(`users/${parent}`).set({uid: parent, displayName: "No Phone Parent", accountStatus: "active"}),
      db.doc(`users/${provider}`).set({uid: provider, displayName: "No Phone Provider", accountStatus: "active"}),
      db.doc(`services/${serviceId}`).set(strip({...race.liveService(), serviceId, ownerUserId: provider})),
      db.doc(`bookings/${ids.bookingId}`).set(strip({...booking, bookingId: ids.bookingId})),
      db.doc(`bookings/${ids.bookingId}/paymentAttempts/${ids.paymentAttemptId}`)
        .set(strip({...base.paymentAttempt, parentId: parent, providerId: provider, bookingId: ids.bookingId})),
    ]);
    const result = await finalizeCapturedCanonicalPaymentV3({
      firestore: db,
      facts: {
        bookingId: ids.bookingId,
        paymentAttemptId: ids.paymentAttemptId,
        razorpayOrderId: ids.razorpayOrderId,
        razorpayPaymentId: ids.razorpayPaymentId,
        capturedAmountPaise: base.paymentAttempt.amountPaise,
        currency: "INR",
        capturedAt: new Date("2026-07-22T10:25:05Z"),
        verificationSource: "webhook",
        sourceEventId: `evt-${sfx}`,
      },
      authoritativeNow: base.authoritativeNow,
    });
    assert.equal(result.ok, true, result.code);
    assert.equal(result.code, "CONFIRMED");
    assert.equal(hasUndefined(result.bookingPrivateParticipants), false);
    assert.equal((await db.doc(`bookings/${ids.bookingId}`).get()).data().state, "CONFIRMED");
    const participants = (await db.doc(`bookingPrivateParticipants/${ids.bookingId}`).get()).data();
    assert.equal("providerPrivate" in participants, false, "the key is omitted, never undefined");
    assert.equal(participants.parentPrivate.phoneNumber, "");
  } finally {
    auth.getUser = originalGetUser;
  }
});
