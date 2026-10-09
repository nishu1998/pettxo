const test = require("node:test");
const assert = require("node:assert/strict");

const hasEmulators = Boolean(
  process.env.FIRESTORE_EMULATOR_HOST &&
  process.env.FIREBASE_STORAGE_EMULATOR_HOST,
);

let auth;
let db;
let storage;
let sendChatImageMessage;
let getChatImageMessagingCapability;
const disabledAuthUids = new Set();

const senderId = "chat-image-call-a";
const receiverId = "chat-image-call-b";
const outsiderId = "chat-image-call-c";
const closedReceiverId = "chat-image-call-d";
const oldRecipientId = "chat-image-call-e";
const chatId = `chat_${senderId}_${receiverId}`;
const closedChatId = `chat_${senderId}_${closedReceiverId}`;
const outsiderChatId = `chat_${receiverId}_${outsiderId}`;
const oldRecipientChatId = `chat_${senderId}_${oldRecipientId}`;

function jpeg(width = 1200, height = 800) {
  return Buffer.from([
    0xff, 0xd8,
    0xff, 0xe0, 0x00, 0x04, 0x00, 0x00,
    0xff, 0xc0, 0x00, 0x0b, 0x08,
    (height >> 8) & 0xff, height & 0xff,
    (width >> 8) & 0xff, width & 0xff,
    0x01, 0x01, 0x11, 0x00,
    0xff, 0xd9,
  ]);
}

function pathFor(targetChatId, messageId) {
  return `chatMedia/${targetChatId}/${messageId}/image.jpg`;
}

async function upload(targetChatId, messageId, ownerId = senderId) {
  const storagePath = pathFor(targetChatId, messageId);
  await storage.bucket().file(storagePath).save(jpeg(), {
    contentType: "image/jpeg",
    metadata: {metadata: {chatId: targetChatId, messageId, senderId: ownerId}},
  });
  return storagePath;
}

function request(uid, targetChatId, messageId) {
  return {
    auth: {uid},
    data: {
      chatId: targetChatId,
      messageId,
      storagePath: pathFor(targetChatId, messageId),
    },
  };
}

async function expectCode(promise, code) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, code);
    return true;
  });
}

test.before(async () => {
  if (!hasEmulators) return;
  process.env.CHAT_IMAGE_MESSAGING_ENABLED = "false";
  process.env.CHAT_IMAGE_TESTER_UIDS = `${senderId},${receiverId}`;
  ({auth, db, storage} = require("../lib/shared/firebase.js"));
  ({sendChatImageMessage, getChatImageMessagingCapability} =
    require("../lib/chat/chatImageFunctions.js"));
  auth.getUser = async (uid) => ({uid, disabled: disabledAuthUids.has(uid)});

  for (const uid of [senderId, receiverId, outsiderId, closedReceiverId, oldRecipientId]) {
    await db.collection("users").doc(uid).set({
      uid,
      displayName: uid,
      accountStatus: "active",
    });
    await db.collection("users").doc(uid).collection("notificationTokens").doc("device").set({
      token: `${uid}-token`,
      disabled: false,
      chatImageV1: true,
    });
  }
  await db.collection("chats").doc(chatId).set({
    chatType: "directUser",
    status: "active",
    customerId: senderId,
    providerId: receiverId,
    participantIds: [senderId, receiverId],
    unreadCountCustomer: 0,
    unreadCountProvider: 0,
  });
  await db.collection("chats").doc(closedChatId).set({
    chatType: "directUser",
    status: "closed",
    customerId: senderId,
    providerId: closedReceiverId,
    participantIds: [senderId, closedReceiverId],
  });
  await db.collection("chats").doc(outsiderChatId).set({
    chatType: "directUser",
    status: "active",
    customerId: receiverId,
    providerId: outsiderId,
    participantIds: [receiverId, outsiderId],
  });
  await db.collection("chats").doc(oldRecipientChatId).set({
    chatType: "directUser",
    status: "active",
    customerId: senderId,
    providerId: oldRecipientId,
    participantIds: [senderId, oldRecipientId],
    unreadCountCustomer: 0,
    unreadCountProvider: 0,
  });
});

test("public gate stays disabled while approved testers alone receive capability", {skip: !hasEmulators}, async () => {
  const approved = await getChatImageMessagingCapability.run({
    auth: {uid: senderId}, data: {chatId},
  });
  const ordinary = await getChatImageMessagingCapability.run({
    auth: {uid: outsiderId}, data: {chatId: outsiderChatId},
  });
  assert.deepEqual(approved, {enabled: true, reason: "enabled"});
  assert.deepEqual(ordinary, {enabled: false, reason: "sender-not-allowed"});
});

test("non-tester cannot send even with a current capable token", {skip: !hasEmulators}, async () => {
  const messageId = "ZzYyXxWwVvUuTtSsRrQq";
  await upload(outsiderChatId, messageId, outsiderId);
  await expectCode(
    sendChatImageMessage.run(request(outsiderId, outsiderChatId, messageId)),
    "failed-precondition",
  );
});

test("approved tester can send to an old recipient and stale recipient tokens do not block", {skip: !hasEmulators}, async () => {
  const messageId = "YyXxWwVvUuTtSsRrQqPp";
  await db.collection("users").doc(oldRecipientId).collection("notificationTokens")
    .doc("device").set({token: `${oldRecipientId}-old-token`, disabled: false});
  await db.collection("users").doc(oldRecipientId).collection("notificationTokens")
    .doc("stale").set({token: `${oldRecipientId}-stale-token`, disabled: false});
  const storagePath = await upload(oldRecipientChatId, messageId);
  const result = await sendChatImageMessage.run(
    request(senderId, oldRecipientChatId, messageId),
  );
  assert.equal(result.idempotent, false);
  const message = (await db.collection("chats").doc(oldRecipientChatId)
    .collection("messages").doc(messageId).get()).data();
  assert.equal(message.storagePath, storagePath);
  assert.equal(message.type, "image");
});

test("old sender capability cannot invoke the image callable", {skip: !hasEmulators}, async () => {
  const messageId = "XxWwVvUuTtSsRrQqPpOo";
  await db.collection("users").doc(senderId).collection("notificationTokens")
    .doc("device").set({token: `${senderId}-old-token`, disabled: false});
  await upload(chatId, messageId);
  try {
    await expectCode(
      sendChatImageMessage.run(request(senderId, chatId, messageId)),
      "failed-precondition",
    );
  } finally {
    await db.collection("users").doc(senderId).collection("notificationTokens")
      .doc("device").set({chatImageV1: true}, {merge: true});
  }
});

test("concurrent identical sends commit once and target only the receiver", {skip: !hasEmulators}, async () => {
  const messageId = "AaBbCcDdEeFfGgHhIiJj";
  const storagePath = await upload(chatId, messageId);
  const results = await Promise.all([
    sendChatImageMessage.run(request(senderId, chatId, messageId)),
    sendChatImageMessage.run(request(senderId, chatId, messageId)),
  ]);

  assert.deepEqual(results.map((result) => result.idempotent).sort(), [false, true]);
  const message = (await db.collection("chats").doc(chatId)
    .collection("messages").doc(messageId).get()).data();
  assert.equal(message.senderId, senderId);
  assert.equal(message.receiverId, receiverId);
  assert.equal(message.storagePath, storagePath);
  assert.equal(message.type, "image");

  const chat = (await db.collection("chats").doc(chatId).get()).data();
  assert.equal(chat.unreadCountCustomer, 0);
  assert.equal(chat.unreadCountProvider, 1);
  assert.equal(chat.lastSenderId, senderId);
  assert.equal(chat.lastMessage, "📷 Photo");

  const notification = (await db.collection("notifications")
    .doc(`chat_${receiverId}_${chatId}`).get()).data();
  assert.equal(notification.userId, receiverId);
  assert.equal(notification.recipientId, receiverId);
  assert.equal(notification.senderId, senderId);
  assert.equal(notification.lastMessageId, messageId);
  assert.equal(notification.unreadCount, 1);
  assert.equal(notification.body, "Sent you a photo");
  assert.equal(notification.storagePath, undefined);
});

test("the receiver can send and increments the sender-side unread counter", {skip: !hasEmulators}, async () => {
  const messageId = "BbCcDdEeFfGgHhIiJjKk";
  const storagePath = await upload(chatId, messageId, receiverId);
  const result = await sendChatImageMessage.run({
    auth: {uid: receiverId},
    data: {chatId, messageId, storagePath},
  });
  assert.equal(result.idempotent, false);

  const message = (await db.collection("chats").doc(chatId)
    .collection("messages").doc(messageId).get()).data();
  assert.equal(message.senderId, receiverId);
  assert.equal(message.receiverId, senderId);
  const chat = (await db.collection("chats").doc(chatId).get()).data();
  assert.equal(chat.unreadCountCustomer, 1);
  assert.equal(chat.unreadCountProvider, 1);
});

test("unauthorized, closed, missing, conflicting, and malformed sends fail safely", {skip: !hasEmulators}, async () => {
  await expectCode(
    sendChatImageMessage.run(request(outsiderId, chatId, "CcDdEeFfGgHhIiJjKkLl")),
    "permission-denied",
  );
  await expectCode(
    sendChatImageMessage.run(request(senderId, closedChatId, "DdEeFfGgHhIiJjKkLlMm")),
    "failed-precondition",
  );
  await expectCode(
    sendChatImageMessage.run(request(senderId, chatId, "EeFfGgHhIiJjKkLlMmNn")),
    "not-found",
  );

  const conflictId = "FfGgHhIiJjKkLlMmNnOo";
  await db.collection("chats").doc(chatId).collection("messages").doc(conflictId).set({
    type: "text",
    senderId,
    receiverId,
    text: "existing",
  });
  await expectCode(
    sendChatImageMessage.run(request(senderId, chatId, conflictId)),
    "already-exists",
  );

  const malformedId = "GgHhIiJjKkLlMmNnOoPp";
  await upload(chatId, malformedId, outsiderId);
  await expectCode(
    sendChatImageMessage.run(request(senderId, chatId, malformedId)),
    "permission-denied",
  );
});

test("a disabled Firebase Auth account cannot commit an uploaded image", {skip: !hasEmulators}, async () => {
  const messageId = "HhIiJjKkLlMmNnOoPpQq";
  await upload(chatId, messageId);
  disabledAuthUids.add(senderId);
  try {
    await expectCode(
      sendChatImageMessage.run(request(senderId, chatId, messageId)),
      "failed-precondition",
    );
  } finally {
    disabledAuthUids.delete(senderId);
  }
  assert.equal((await db.collection("chats").doc(chatId)
    .collection("messages").doc(messageId).get()).exists, false);
});

test("booking-only restrictions remain compatible with normal chat messaging", {skip: !hasEmulators}, async () => {
  const messageId = "IiJjKkLlMmNnOoPpQqRr";
  await upload(chatId, messageId);
  await db.collection("users").doc(senderId).set({
    accountStatus: "restricted",
    restrictions: {
      booking: {isBanned: true},
      hard: {isBanned: false},
      social: {isBanned: false},
    },
  }, {merge: true});
  try {
    const result = await sendChatImageMessage.run(request(senderId, chatId, messageId));
    assert.equal(result.idempotent, false);
  } finally {
    await db.collection("users").doc(senderId).set({
      accountStatus: "active",
      restrictions: {
        booking: {isBanned: false},
        hard: {isBanned: false},
        social: {isBanned: false},
      },
    }, {merge: true});
  }
});

test("deletion and social restrictions block image commits", {skip: !hasEmulators}, async () => {
  const messageId = "JjKkLlMmNnOoPpQqRrSs";
  await upload(chatId, messageId);
  try {
    await db.collection("users").doc(senderId).set({accountStatus: "pendingDeletion"}, {merge: true});
    await expectCode(
      sendChatImageMessage.run(request(senderId, chatId, messageId)),
      "failed-precondition",
    );

    await db.collection("users").doc(senderId).set({
      accountStatus: "restricted",
      restrictions: {hard: {isBanned: false}, social: {isBanned: true}},
    }, {merge: true});
    await expectCode(
      sendChatImageMessage.run(request(senderId, chatId, messageId)),
      "failed-precondition",
    );
  } finally {
    await db.collection("users").doc(senderId).set({
      accountStatus: "active",
      restrictions: {
        booking: {isBanned: false},
        hard: {isBanned: false},
        social: {isBanned: false},
      },
    }, {merge: true});
  }
  assert.equal((await db.collection("chats").doc(chatId)
    .collection("messages").doc(messageId).get()).exists, false);
});
