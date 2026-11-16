const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({services: ["firestore"]});
const test = require("node:test");
const assert = require("node:assert/strict");

const enabled = firebaseEmulator.enabled;
let db;
let startDirectUserChat;
let sendChatMessage;
let markChatDelivered;
let markChatRead;
let createSocialNotification;

const userA = "blocking-chat-a";
const userB = "blocking-chat-b";
const chatId = `chat_${userA}_${userB}`;

function expectRelationshipBlocked(promise) {
  return assert.rejects(promise, (error) => {
    assert.equal(error.details?.code, "USER_RELATIONSHIP_BLOCKED");
    return true;
  });
}

test.before(async () => {
  if (!enabled) return;
  ({db} = require("../lib/shared/firebase.js"));
  ({
    startDirectUserChat,
    sendChatMessage,
    markChatDelivered,
    markChatRead,
    createSocialNotification,
  } = require("../lib/legacyFunctions.js"));
  await Promise.all([
    db.collection("users").doc(userA).set({
      uid: userA, displayName: "User A", accountStatus: "active",
    }),
    db.collection("users").doc(userB).set({
      uid: userB, displayName: "User B", accountStatus: "active",
    }),
  ]);
  await db.collection("chats").doc(chatId).set({
    chatType: "directUser",
    status: "active",
    customerId: userA,
    providerId: userB,
    participantIds: [userA, userB],
    unreadCountCustomer: 0,
    unreadCountProvider: 0,
  });
  await db.collection("chats").doc(chatId).collection("messages").doc("history").set({
    senderId: userA,
    receiverId: userB,
    type: "text",
    text: "historical evidence",
    createdAt: new Date(),
    deliveredTo: [],
    readBy: [],
  });
  // Deliberately no pair guard: this is the historical legacy-record case.
  await db.collection("userBlocks").doc(`${userB}_${userA}`).set({
    ownerUserId: userB,
    blockedUserId: userA,
    createdAt: new Date(),
  });
});

test.after(async () => {
  if (!enabled) return;
  const batch = db.batch();
  batch.delete(db.collection("userBlocks").doc(`${userB}_${userA}`));
  batch.delete(db.collection("chats").doc(chatId).collection("messages").doc("history"));
  batch.delete(db.collection("chats").doc(chatId));
  batch.delete(db.collection("users").doc(userA));
  batch.delete(db.collection("users").doc(userB));
  await batch.commit();
});

test("historical directed block denies opening and text messaging in both directions", {
  skip: !enabled,
}, async () => {
  await expectRelationshipBlocked(startDirectUserChat.run({
    auth: {uid: userA}, data: {otherUserId: userB},
  }));
  await expectRelationshipBlocked(startDirectUserChat.run({
    auth: {uid: userB}, data: {otherUserId: userA},
  }));
  await expectRelationshipBlocked(sendChatMessage.run({
    auth: {uid: userA}, data: {chatId, text: "blocked"},
  }));
  await expectRelationshipBlocked(sendChatMessage.run({
    auth: {uid: userB}, data: {chatId, text: "blocked"},
  }));
});

test("blocked chat activity and ordinary social notifications are suppressed", {
  skip: !enabled,
}, async () => {
  await expectRelationshipBlocked(markChatDelivered.run({
    auth: {uid: userA}, data: {chatId},
  }));
  await expectRelationshipBlocked(markChatRead.run({
    auth: {uid: userB}, data: {chatId},
  }));
  await expectRelationshipBlocked(createSocialNotification.run({
    auth: {uid: userA}, data: {type: "socialFollow", recipientId: userB},
  }));
  const notifications = await db.collection("notifications")
    .where("senderId", "==", userA).get();
  assert.equal(notifications.docs.some((doc) => doc.data().userId === userB), false);
});

test("blocking preserves historical chat and message evidence", {skip: !enabled}, async () => {
  assert.equal((await db.collection("chats").doc(chatId).get()).exists, true);
  assert.equal((await db.collection("chats").doc(chatId)
    .collection("messages").doc("history").get()).data().text, "historical evidence");
});
