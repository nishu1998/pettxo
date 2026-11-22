// Phase 3B-4a: existing blocks are enforced, and unblock works, whatever the
// state of the blocking activation gate (_rollouts/userBlockingV1). The gate
// controls only block creation (blockingActivationGate.ts:99-118).
//
// Every state runs against the default emulator project, because the deployed
// handlers under test use lib/shared/firebase. The gate documents are written
// (or deleted) explicitly before each state and removed afterwards, and every
// state uses its own user IDs.
const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({
  services: ["firestore", "storage"],
});
const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");

const enabled = firebaseEmulator.enabled;

const GATE_STATES = ["absent", "disabled", "malformed", "enabled"];
const GATE_DOCS = [
  "_rollouts/userBlockingV1",
  "_migrations/userRelationshipGuardV1",
  "userBlockingActivationAudit/gate-independence-activation",
];

let db;
let applyFollowState;
let startDirectUserChat;
let sendChatMessage;
let getChatImageMessagingCapability;
let sendChatImageMessage;
let createRazorpayPaymentOrderV3;
let persistFinalizePaymentResultV3;
let readOpenRelationshipGuardInTransaction;
let getUserRelationshipStateDataV1;
let unblockUserDataV1;
let readBlockingActivationState;
let bookingFixtures;
let chatImageStoragePath;

function relationshipBlocked(error) {
  assert.equal(error.details?.code, "USER_RELATIONSHIP_BLOCKED");
  return true;
}

async function clearGate() {
  await Promise.all(GATE_DOCS.map((path) => db.doc(path).delete()));
}

async function setGate(state) {
  await clearGate();
  if (state === "absent") return;
  if (state === "disabled") {
    await db.doc("_rollouts/userBlockingV1").set({
      schemaVersion: 1,
      enabled: false,
      status: "disabled",
      migrationRunId: "",
      sourceFingerprint: "",
      activationAuditId: "",
      rolloutVersion: 2,
    });
    return;
  }
  if (state === "malformed") {
    // Rollout claims active, but there is no verified migration or audit, and
    // field types are wrong. The gate must fail closed.
    await db.doc("_rollouts/userBlockingV1").set({
      enabled: true,
      status: "active",
      migrationRunId: 42,
      sourceFingerprint: null,
      activationAuditId: ["not-a-string"],
      rolloutVersion: "one",
    });
    return;
  }
  const runId = "gate-independence-run";
  await Promise.all([
    db.doc("_migrations/userRelationshipGuardV1").set({
      migrationVersion: 1,
      runId,
      status: "verified",
      sourceFingerprint: "gate-independence-fingerprint",
      verificationValidUntil: new Date(Date.now() + 60 * 60 * 1000),
      reconciliationPassed: true,
      anomalyCount: 0,
      mismatchCount: 0,
    }),
    db.doc("userBlockingActivationAudit/gate-independence-activation").set({
      event: "ACTIVATE",
      enabled: true,
      migrationRunId: runId,
      sourceFingerprint: "gate-independence-fingerprint",
      rolloutVersion: 1,
    }),
    db.doc("_rollouts/userBlockingV1").set({
      enabled: true,
      status: "active",
      migrationRunId: runId,
      sourceFingerprint: "gate-independence-fingerprint",
      activationAuditId: "gate-independence-activation",
      rolloutVersion: 1,
    }),
  ]);
}

const EXPECTED_ACTIVATION = {
  absent: {enabled: false, reasonCode: "USER_BLOCKING_DISABLED"},
  disabled: {enabled: false, reasonCode: "USER_BLOCKING_DISABLED"},
  malformed: {enabled: false, reasonCode: "RELATIONSHIP_MIGRATION_NOT_VERIFIED"},
  enabled: {enabled: true, reasonCode: ""},
};

function pairIds(state) {
  const suffix = randomUUID().slice(0, 8);
  // a < b keeps chat_a_b canonical (customer a, provider b).
  return {a: `gate-${state}-${suffix}-a`, b: `gate-${state}-${suffix}-b`};
}

async function seedPair(ids) {
  const chatId = `chat_${ids.a}_${ids.b}`;
  await Promise.all([
    db.collection("users").doc(ids.a).set({
      uid: ids.a, displayName: "Gate A", accountStatus: "active",
      followingCount: 0, followerCount: 0,
    }),
    db.collection("users").doc(ids.b).set({
      uid: ids.b, displayName: "Gate B", accountStatus: "active",
      profileVisibility: "public", isActive: true,
      followingCount: 0, followerCount: 0,
    }),
    db.collection("chats").doc(chatId).set({
      chatType: "directUser",
      status: "active",
      customerId: ids.a,
      providerId: ids.b,
      participantIds: [ids.a, ids.b],
      unreadCountCustomer: 0,
      unreadCountProvider: 0,
    }),
  ]);
  return chatId;
}

// The default app does not set ignoreUndefinedProperties; fixtures contain
// optional fields left undefined.
function withoutUndefined(value) {
  if (Array.isArray(value)) return value.map(withoutUndefined);
  if (value && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype) {
    return Object.fromEntries(Object.entries(value)
      .filter(([, entry]) => entry !== undefined)
      .map(([key, entry]) => [key, withoutUndefined(entry)]));
  }
  return value;
}

function bookingFor(ids, builder) {
  const booking = builder();
  booking.parentId = ids.a;
  booking.customerId = ids.a;
  booking.providerId = ids.b;
  booking.serviceOwnerId = ids.b;
  booking.participantIds = [ids.a, ids.b];
  booking.participants.parent.parentId = ids.a;
  booking.participants.provider.providerId = ids.b;
  booking.service.providerId = ids.b;
  for (const slot of booking.schedule.slots) slot.providerId = ids.b;
  return booking;
}

test.before(async () => {
  if (!enabled) return;
  ({db} = require("../lib/shared/firebase.js"));
  ({applyFollowState} = require("../lib/social/followFunctions.js"));
  ({startDirectUserChat, sendChatMessage} = require("../lib/legacyFunctions.js"));
  ({getChatImageMessagingCapability, sendChatImageMessage} =
    require("../lib/chat/chatImageFunctions.js"));
  ({chatImageStoragePath} = require("../lib/chat/chatImagePolicy.js"));
  ({createRazorpayPaymentOrderV3} = require("../lib/booking/bookingV3FlowFunctions.js"));
  ({persistFinalizePaymentResultV3} =
    require("../lib/booking/application/paymentOrchestrationV3.js"));
  ({readOpenRelationshipGuardInTransaction} =
    require("../lib/blocking/relationshipGuard.js"));
  ({getUserRelationshipStateDataV1, unblockUserDataV1} =
    require("../lib/blocking/userBlocking.js"));
  ({readBlockingActivationState} = require("../lib/blocking/blockingActivationGate.js"));
  bookingFixtures = require("../lib/booking/schema/bookingFixtures.js");
});

test.after(async () => {
  if (!enabled) return;
  await clearGate();
});

for (const state of GATE_STATES) {
  test(`gate ${state}: an existing directed block is enforced everywhere`, {
    skip: !enabled,
  }, async () => {
    await setGate(state);
    assert.deepEqual(
      (({enabled: on, reasonCode}) => ({enabled: on, reasonCode}))(
        await readBlockingActivationState(db),
      ),
      EXPECTED_ACTIVATION[state],
    );

    const ids = pairIds(state);
    const chatId = await seedPair(ids);
    // B blocked A, with no relationship guard (historical-record shape).
    await db.collection("userBlocks").doc(`${ids.b}_${ids.a}`).set({
      ownerUserId: ids.b,
      blockedUserId: ids.a,
      createdAt: new Date(),
    });

    // Relationship state before any booking exists (userBlocking.ts:535-638).
    const forBlocked = await getUserRelationshipStateDataV1({
      firestore: db, actorUid: ids.a, targetUid: ids.b,
    });
    const forBlocker = await getUserRelationshipStateDataV1({
      firestore: db, actorUid: ids.b, targetUid: ids.a,
    });
    assert.equal(forBlocked.relationshipBlocked, true);
    assert.equal(forBlocked.blockedByCaller, false);
    assert.equal(forBlocker.relationshipBlocked, true);
    assert.equal(forBlocker.blockedByCaller, true);
    if (state === "enabled") {
      // Gate on and no bookings: the blocked user may add their own block.
      assert.equal(forBlocked.canBlock, true);
      assert.equal(forBlocked.reasonCode, "");
    } else {
      for (const view of [forBlocked, forBlocker]) {
        assert.equal(view.canBlock, false);
        assert.equal(view.reasonCode, EXPECTED_ACTIVATION[state].reasonCode);
      }
    }

    // Follow, both directions (social/followFunctions.ts:141-163).
    await assert.rejects(applyFollowState({
      followerId: ids.a, followeeId: ids.b, desiredFollowing: true,
    }), relationshipBlocked);
    await assert.rejects(applyFollowState({
      followerId: ids.b, followeeId: ids.a, desiredFollowing: true,
    }), relationshipBlocked);

    // Legacy chat open and text send (legacyFunctions.ts).
    await assert.rejects(startDirectUserChat.run({
      auth: {uid: ids.a}, data: {otherUserId: ids.b},
    }), relationshipBlocked);
    await assert.rejects(sendChatMessage.run({
      auth: {uid: ids.b}, data: {chatId, text: "blocked"},
    }), relationshipBlocked);

    // Chat image capability reports the block (chatImageFunctions.ts:140-146)
    // and the image commit is refused before any Storage read (:193).
    assert.deepEqual(await getChatImageMessagingCapability.run({
      auth: {uid: ids.a}, data: {chatId},
    }), {enabled: false, reason: "relationship-blocked"});
    assert.deepEqual(await getChatImageMessagingCapability.run({
      auth: {uid: ids.b}, data: {chatId},
    }), {enabled: false, reason: "relationship-blocked"});
    const messageId = "GateIndependence0001".slice(0, 20);
    await assert.rejects(sendChatImageMessage.run({
      auth: {uid: ids.a},
      data: {chatId, messageId, storagePath: chatImageStoragePath(chatId, messageId)},
    }), relationshipBlocked);

    // Booking create: the relationship check createBookingRequestV3 runs in
    // its transaction (bookingV3FlowFunctions.ts:2394).
    await assert.rejects(db.runTransaction((transaction) =>
      readOpenRelationshipGuardInTransaction({
        firestore: db, transaction, firstUid: ids.a, secondUid: ids.b,
      })), relationshipBlocked);

    // Payment order callable (bookingV3FlowFunctions.ts:2803, check at :2158).
    const acceptedId = `gate-${state}-accepted-${randomUUID().slice(0, 8)}`;
    const accepted = bookingFor(ids, bookingFixtures.buildAcceptedAwaitingPaymentSlotBookingFixture);
    await Promise.all([
      db.collection("bookings").doc(acceptedId).set(withoutUndefined(accepted)),
      db.collection("services").doc(accepted.serviceId).set({
        ownerUserId: ids.b,
        title: "Gate test service",
        status: "active",
        isActive: true,
        isDeleted: false,
        isPaused: false,
        isVisibleToMarketplace: true,
      }),
    ]);
    await assert.rejects(createRazorpayPaymentOrderV3.run({
      auth: {uid: ids.a}, data: {bookingId: acceptedId},
    }), relationshipBlocked);

    // Capture persistence refuses to confirm (paymentOrchestrationV3.ts:1929).
    const confirmedId = `gate-${state}-capture-${randomUUID().slice(0, 8)}`;
    const confirmed = bookingFor(ids, bookingFixtures.buildConfirmedSlotBookingFixture);
    const attempt = {paymentAttemptId: "gate-attempt", razorpayPaymentId: "gate-payment"};
    await Promise.all([
      db.collection("bookings").doc(confirmedId).set(withoutUndefined(confirmed)),
      db.collection("bookings").doc(confirmedId)
        .collection("paymentAttempts").doc(attempt.paymentAttemptId).set(attempt),
    ]);
    await assert.rejects(persistFinalizePaymentResultV3({
      firestore: db,
      bookingId: confirmedId,
      result: {
        ok: true,
        booking: confirmed,
        paymentAttempt: attempt,
        couponWrite: null,
        notifications: [],
        events: [],
        occupancyWrites: {},
      },
    }), relationshipBlocked);

    // With pair bookings: gate on, a CONFIRMED booking protects the pair.
    const withBookings = await getUserRelationshipStateDataV1({
      firestore: db, actorUid: ids.a, targetUid: ids.b,
    });
    assert.equal(withBookings.relationshipBlocked, true);
    assert.equal(withBookings.canBlock, false);
    assert.equal(
      withBookings.reasonCode,
      state === "enabled" ? "PROTECTED_STATE_CONFIRMED" : EXPECTED_ACTIVATION[state].reasonCode,
    );
  });

  test(`gate ${state}: unblock works, is idempotent and needs no gate documents`, {
    skip: !enabled,
  }, async () => {
    await setGate(state);
    const ids = pairIds(state);
    await seedPair(ids);
    await Promise.all([
      db.collection("userBlocks").doc(`${ids.a}_${ids.b}`).set({
        ownerUserId: ids.a, blockedUserId: ids.b, createdAt: new Date(),
      }),
      db.collection("userBlocks").doc(`${ids.b}_${ids.a}`).set({
        ownerUserId: ids.b, blockedUserId: ids.a, createdAt: new Date(),
      }),
    ]);

    const first = await unblockUserDataV1({firestore: db, actorUid: ids.a, targetUid: ids.b});
    assert.equal(first.relationshipBlocked, true, "the other direction stays");
    assert.equal(first.blockedByCaller, false);
    assert.equal(first.idempotentReplay, false);
    assert.equal((await db.collection("userBlocks").doc(`${ids.a}_${ids.b}`).get()).exists, false);
    assert.equal((await db.collection("userBlocks").doc(`${ids.b}_${ids.a}`).get()).exists, true);

    const replay = await unblockUserDataV1({firestore: db, actorUid: ids.a, targetUid: ids.b});
    assert.equal(replay.idempotentReplay, true);
    assert.equal(replay.relationshipBlocked, true);

    const second = await unblockUserDataV1({firestore: db, actorUid: ids.b, targetUid: ids.a});
    assert.equal(second.relationshipBlocked, false);
    const guard = (await db.collection("userRelationshipGuards").doc(second.pairKey).get()).data();
    assert.equal(guard.blocked, false);
    assert.equal(guard.status, "open");

    // No block at all: still succeeds.
    const fresh = pairIds(state);
    await seedPair(fresh);
    const none = await unblockUserDataV1({firestore: db, actorUid: fresh.a, targetUid: fresh.b});
    assert.equal(none.relationshipBlocked, false);
    assert.equal(none.blockedByCaller, false);

    // After unblocking, follow is allowed again in every gate state.
    const followed = await applyFollowState({
      followerId: ids.a, followeeId: ids.b, desiredFollowing: true,
    });
    assert.equal(followed.isFollowing, true);
  });
}

test("unblock never reads the gate documents", {skip: !enabled}, async () => {
  // Gate documents with hostile shapes: unblock must not care.
  await clearGate();
  await Promise.all([
    db.doc("_rollouts/userBlockingV1").set({enabled: "yes", status: 7}),
    db.doc("_migrations/userRelationshipGuardV1").set({status: ["verified"]}),
  ]);
  const ids = pairIds("hostile");
  await seedPair(ids);
  await db.collection("userBlocks").doc(`${ids.a}_${ids.b}`).set({
    ownerUserId: ids.a, blockedUserId: ids.b, createdAt: new Date(),
  });
  const result = await unblockUserDataV1({firestore: db, actorUid: ids.a, targetUid: ids.b});
  assert.equal(result.relationshipBlocked, false);
  assert.equal((await db.collection("userBlocks").doc(`${ids.a}_${ids.b}`).get()).exists, false);
  await clearGate();
});

// Callable wrappers (userBlockingFunctions.ts:40-74): auth and self checks run
// before any data access, so these need no emulator.
test("blocking callables reject unauthenticated, missing-target and self requests", async () => {
  const {
    blockUserV1,
    getUserRelationshipStateV1,
    unblockUserV1,
  } = require("../lib/blocking/userBlockingFunctions.js");
  for (const callable of [blockUserV1, unblockUserV1, getUserRelationshipStateV1]) {
    await assert.rejects(callable.run({data: {targetUid: "someone"}}), (error) => {
      assert.equal(error.code, "unauthenticated");
      return true;
    });
    for (const data of [{}, {targetUid: ""}, {targetUid: "a/b"}]) {
      await assert.rejects(callable.run({auth: {uid: "me"}, data}), (error) => {
        assert.equal(error.code, "invalid-argument");
        assert.equal(error.details?.code, "INVALID_TARGET_USER");
        return true;
      });
    }
    await assert.rejects(callable.run({auth: {uid: "me"}, data: {targetUid: "me"}}), (error) => {
      assert.equal(error.code, "invalid-argument");
      assert.equal(error.details?.code, "SELF_BLOCK_NOT_ALLOWED");
      return true;
    });
  }
});
