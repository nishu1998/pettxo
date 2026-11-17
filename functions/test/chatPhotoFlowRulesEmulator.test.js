const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({services: ["firestore", "storage"]});
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  collection, doc, getDoc, getDocs, limit, orderBy, query,
} = require("firebase/firestore");
const {deleteObject, getBytes, getMetadata, ref, uploadBytes} = require("firebase/storage");

// Phase 3C-4: end-to-end chat photo send exactly as build 23 (1.0.4, ff9da9f)
// and 1.0.5 perform it. Their Storage/Firestore media code is identical
// (chat_media_repository.dart is unchanged ff9da9f..HEAD):
//   1. listen chats/{chatId}; query chats/{chatId}/messages orderBy createdAt desc
//   2. callable getChatImageMessagingCapability {chatId}
//   3. client-generated 20-character messageId
//   4. Storage put chatMedia/{chatId}/{messageId}/image.jpg, contentType
//      image/jpeg, customMetadata {chatId, messageId, senderId}
//   5. retry path: Storage getMetadata; cancel path: Storage delete
//   6. callable sendChatImageMessage {chatId, messageId, storagePath}
//   7. both participants read the message and getData the object
// Client steps run under the repository Rules; callables run the compiled
// handlers against the same emulators. 1.0.5 additionally needs
// getUserRelationshipStateV1 to report the relationship as not blocked before
// it shows the photo button.
const RULES_DIR = path.resolve(__dirname, "../..");
const FUNCTIONS_LIB = path.resolve(__dirname, "../lib");

const hasEmulators = firebaseEmulator.enabled;
let environment;
let admin;
let chatImage;
let relationshipGuard = null;
let userBlocking = null;
// Client uploads must land in the bucket the callable handlers read (the Admin
// SDK default bucket), which differs from the rules-unit-testing default.
let bucketUrl;

const jpegBytes = new Uint8Array([
  0xff, 0xd8,
  0xff, 0xe0, 0x00, 0x04, 0x00, 0x00,
  0xff, 0xc0, 0x00, 0x0b, 0x08, 0x03, 0x20, 0x04, 0xb0, 0x01, 0x01, 0x11, 0x00,
  0xff, 0xd9,
]);

function optionalRequire(modulePath) {
  return fs.existsSync(modulePath) ? require(modulePath) : null;
}

function messageIdFor(seed) {
  // 20 alphanumeric characters, unique per seed (matches the Rules pattern).
  return `PhotoFlow${String(seed).padStart(11, "0")}`;
}

async function seedPair(customerId, providerId) {
  const chatId = `chat_${customerId}_${providerId}`;
  for (const uid of [customerId, providerId]) {
    await admin.db.collection("users").doc(uid).set({uid, displayName: uid, accountStatus: "active"});
    await admin.db.collection("users").doc(uid).collection("notificationTokens").doc("device").set({
      token: `${uid}-token`, disabled: false, chatImageV1: true,
    });
  }
  await admin.db.collection("chats").doc(chatId).set({
    chatType: "directUser",
    status: "active",
    customerId,
    providerId,
    participantIds: [customerId, providerId],
    unreadCountCustomer: 0,
    unreadCountProvider: 0,
    lastMessageAt: new Date(),
  });
  return chatId;
}

async function setRelationship(customerId, providerId, state) {
  if (state === "no-guard") return;
  const pair = relationshipGuard.canonicalUserPair(customerId, providerId);
  const blocked = state === "blocked";
  await admin.db.collection("userRelationshipGuards").doc(pair.pairKey).set({
    schemaVersion: 1,
    pairKey: pair.pairKey,
    uidA: pair.uidA,
    uidB: pair.uidB,
    blocked,
    status: blocked ? "blocked" : "open",
    activeDirectedBlockIds: blocked ? [`${providerId}_${customerId}`] : [],
  });
  if (blocked) {
    await admin.db.collection("userBlocks").doc(`${providerId}_${customerId}`).set({
      schemaVersion: 1,
      ownerUserId: providerId,
      blockerUid: providerId,
      blockedUserId: customerId,
      pairKey: pair.pairKey,
      status: "active",
      createdAt: new Date(),
    });
  }
}

// Other test files reload Storage Rules into the shared emulator when they start
// (initializeTestEnvironment), and node --test runs files in parallel. During a
// reload the emulator denies with "no Storage ruleset is currently loaded".
// Retry expected successes: a real Rules denial is deterministic and fails
// every attempt. Expected denials are confirmed through the Admin SDK instead.
async function eventually(step, operation, attempts = 3) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      return await assertSucceeds(operation());
    } catch (error) {
      if (attempt >= attempts) throw new Error(`[step: ${step}] ${error.message}`, {cause: error});
      await new Promise((resolve) => setTimeout(resolve, 500 * attempt));
    }
  }
}

async function at(step, promise) {
  try {
    return await promise;
  } catch (error) {
    throw new Error(`[step: ${step}] ${error.message}`, {cause: error});
  }
}

async function sendPhoto({chatId, senderId, receiverId, seed, expectBlocked}) {
  const sender = environment.authenticatedContext(senderId);
  const receiver = environment.authenticatedContext(receiverId);
  const steps = {};

  await assertSucceeds(getDoc(doc(sender.firestore(), `chats/${chatId}`)));
  await assertSucceeds(getDocs(query(
    collection(sender.firestore(), `chats/${chatId}/messages`),
    orderBy("createdAt", "desc"),
    limit(30),
  )));
  steps.firestoreReads = "allowed";

  if (userBlocking) {
    const state = await userBlocking.getUserRelationshipStateV1.run({
      auth: {uid: senderId}, data: {targetUid: receiverId},
    });
    assert.equal(state.relationshipBlocked, expectBlocked);
    steps.relationshipState = state.relationshipBlocked ? "blocked" : "open";
  }

  const capability = await chatImage.getChatImageMessagingCapability.run({
    auth: {uid: senderId}, data: {chatId},
  });
  assert.equal(capability.enabled, !expectBlocked, JSON.stringify(capability));
  steps.capability = capability.reason ?? String(capability.enabled);

  const messageId = messageIdFor(seed);
  const storagePath = `chatMedia/${chatId}/${messageId}/image.jpg`;
  await eventually("storage upload", () => uploadBytes(ref(sender.storage(bucketUrl), storagePath), jpegBytes, {
    contentType: "image/jpeg",
    customMetadata: {chatId, messageId, senderId},
  }));
  steps.storageUpload = "allowed";
  await eventually("retry getMetadata", () => getMetadata(ref(sender.storage(bucketUrl), storagePath)));

  const commit = chatImage.sendChatImageMessage.run({
    auth: {uid: senderId}, data: {chatId, messageId, storagePath},
  });
  if (expectBlocked) {
    await assert.rejects(commit, (error) => error.code === "failed-precondition");
    assert.equal((await admin.db.doc(`chats/${chatId}/messages/${messageId}`).get()).exists, false);
    steps.commit = "refused (failed-precondition)";
    // The uncommitted upload can still be cleaned up by its sender.
    await eventually("blocked cleanup delete", () => deleteObject(ref(sender.storage(bucketUrl), storagePath)));
    return steps;
  }
  await at("sendChatImageMessage commit", commit);
  steps.commit = "committed";

  await at("receiver reads message doc", assertSucceeds(getDoc(doc(receiver.firestore(), `chats/${chatId}/messages/${messageId}`))));
  await eventually("receiver getData", () => getBytes(ref(receiver.storage(bucketUrl), storagePath)));
  await eventually("sender getData", () => getBytes(ref(sender.storage(bucketUrl), storagePath)));
  await at("sender delete after commit (must fail)", assertFails(deleteObject(ref(sender.storage(bucketUrl), storagePath))));
  const [stillExists] = await admin.storage.bucket().file(storagePath).exists();
  assert.equal(stillExists, true, "committed media must not be deletable");
  steps.readBack = "allowed";

  const cancelledId = messageIdFor(seed + 1000);
  const cancelledPath = `chatMedia/${chatId}/${cancelledId}/image.jpg`;
  await eventually("cancel path upload", () => uploadBytes(ref(sender.storage(bucketUrl), cancelledPath), jpegBytes, {
    contentType: "image/jpeg",
    customMetadata: {chatId, messageId: cancelledId, senderId},
  }));
  await eventually("cancel path delete", () => deleteObject(ref(sender.storage(bucketUrl), cancelledPath)));
  steps.cancelPath = "allowed";
  return steps;
}

test.before(async () => {
  if (!hasEmulators) return;
  process.env.CHAT_IMAGE_MESSAGING_ENABLED = "true";
  environment = await initializeTestEnvironment({
    projectId: firebaseEmulator.projectId,
    firestore: {rules: fs.readFileSync(path.join(RULES_DIR, "firestore.rules"), "utf8")},
    storage: {rules: fs.readFileSync(path.join(RULES_DIR, "storage.rules"), "utf8")},
  });
  admin = require(path.join(FUNCTIONS_LIB, "shared/firebase.js"));
  admin.auth.getUser = async (uid) => ({uid, disabled: false});
  bucketUrl = `gs://${admin.storage.bucket().name}`;
  chatImage = require(path.join(FUNCTIONS_LIB, "chat/chatImageFunctions.js"));
  relationshipGuard = optionalRequire(path.join(FUNCTIONS_LIB, "blocking/relationshipGuard.js"));
  userBlocking = optionalRequire(path.join(FUNCTIONS_LIB, "blocking/userBlockingFunctions.js"));
});

test.after(async () => environment?.cleanup());

const scenarios = [
  {state: "no-guard", label: "no relationship guard (old functions, or new functions before any booking)"},
  {state: "open", label: "open guard written by new booking functions", needsNewFunctions: true},
  {state: "blocked", label: "blocked pair (Phase 3B-4 only)", needsNewFunctions: true},
];

scenarios.forEach((scenario, index) => {
  test(`chat photo send, both directions: ${scenario.label}`, {skip: !hasEmulators}, async (t) => {
    if (scenario.needsNewFunctions && !relationshipGuard) {
      t.skip("old functions never write relationship guards or blocks");
      return;
    }
    const customerId = `photo-flow-c${index}`;
    const providerId = `photo-flow-p${index}`;
    const chatId = await seedPair(customerId, providerId);
    await setRelationship(customerId, providerId, scenario.state);
    const expectBlocked = scenario.state === "blocked";
    const forward = await sendPhoto({
      chatId, senderId: customerId, receiverId: providerId, seed: index * 10 + 1, expectBlocked,
    });
    const reverse = await sendPhoto({
      chatId, senderId: providerId, receiverId: customerId, seed: index * 10 + 2, expectBlocked,
    });
    t.diagnostic(`functions=${relationshipGuard ? "new" : "old"} forward=${JSON.stringify(forward)}`);
    t.diagnostic(`functions=${relationshipGuard ? "new" : "old"} reverse=${JSON.stringify(reverse)}`);
  });
});
