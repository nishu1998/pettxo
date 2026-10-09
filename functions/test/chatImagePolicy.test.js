const test = require("node:test");
const assert = require("node:assert/strict");

const {
  allActiveDevicesSupportChatImages,
  anyActiveDeviceSupportsChatImages,
  buildChatImageMessageData,
  canAccountUseChatImageMessaging,
  chatImageUnreadField,
  chatImageStoragePath,
  inspectJpegDimensions,
  isIdenticalCommittedImageMessage,
  isValidChatImageMessageId,
  parseChatImageTesterUids,
  validateChatImageObjectMetadata,
} = require("../lib/chat/chatImagePolicy.js");

const messageId = "AbCdEfGhIjKlMnOpQrSt";
const chatId = "chat_uid-a_uid-b";
const storagePath = `chatMedia/${chatId}/${messageId}/image.jpg`;

function jpeg(width = 1200, height = 800) {
  return Uint8Array.from([
    0xff, 0xd8,
    0xff, 0xe0, 0x00, 0x04, 0x00, 0x00,
    0xff, 0xc0, 0x00, 0x0b, 0x08,
    (height >> 8) & 0xff, height & 0xff,
    (width >> 8) & 0xff, width & 0xff,
    0x01, 0x01, 0x11, 0x00,
    0xff, 0xd9,
  ]);
}

function metadata(overrides = {}) {
  return {
    contentType: "image/jpeg",
    size: "128",
    metadata: {chatId, messageId, senderId: "uid-a"},
    ...overrides,
  };
}

test("chat image IDs and paths are deterministic and reject path injection", () => {
  assert.equal(isValidChatImageMessageId(messageId), true);
  assert.equal(isValidChatImageMessageId("short"), false);
  assert.equal(isValidChatImageMessageId("../AbCdEfGhIjKlMnOpQrSt"), false);
  assert.equal(chatImageStoragePath(chatId, messageId), storagePath);
});

test("object metadata binds the upload to sender, chat, message, MIME, and size", () => {
  assert.deepEqual(validateChatImageObjectMetadata({
    metadata: metadata(), expectedPath: storagePath, actualPath: storagePath,
    chatId, messageId, senderId: "uid-a",
  }), {size: 128});

  const cases = [
    [metadata({contentType: "image/png"}), "invalid-content-type"],
    [metadata({size: "0"}), "empty-image"],
    [metadata({size: String(3 * 1024 * 1024 + 1)}), "image-too-large"],
    [metadata({metadata: {chatId: "wrong", messageId, senderId: "uid-a"}}), "chat-metadata-mismatch"],
    [metadata({metadata: {chatId, messageId: "wrong", senderId: "uid-a"}}), "message-metadata-mismatch"],
    [metadata({metadata: {chatId, messageId, senderId: "uid-c"}}), "sender-metadata-mismatch"],
  ];
  for (const [candidate, code] of cases) {
    assert.throws(() => validateChatImageObjectMetadata({
      metadata: candidate, expectedPath: storagePath, actualPath: storagePath,
      chatId, messageId, senderId: "uid-a",
    }), new RegExp(code));
  }
});

test("JPEG inspection derives dimensions and rejects corrupt or oversized images", () => {
  assert.deepEqual(inspectJpegDimensions(jpeg()), {width: 1200, height: 800});
  assert.throws(() => inspectJpegDimensions(Uint8Array.from([1, 2, 3])), /invalid-jpeg/);
  assert.throws(() => inspectJpegDimensions(jpeg(1601, 800)), /image-dimensions-too-large/);
});

test("idempotency accepts only the identical committed image identity", () => {
  const committed = {
    type: "image", senderId: "uid-a", receiverId: "uid-b", storagePath,
    mimeType: "image/jpeg", imageWidth: 1200, imageHeight: 800,
    imageSizeBytes: 128, mediaSchemaVersion: 1,
  };
  assert.equal(isIdenticalCommittedImageMessage({
    message: committed, senderId: "uid-a", receiverId: "uid-b", storagePath,
  }), true);
  assert.equal(isIdenticalCommittedImageMessage({
    message: {...committed, receiverId: "uid-c"},
    senderId: "uid-a", receiverId: "uid-b", storagePath,
  }), false);
  assert.equal(isIdenticalCommittedImageMessage({
    message: {...committed, type: "text"},
    senderId: "uid-a", receiverId: "uid-b", storagePath,
  }), false);
});

test("capability gate requires every active device and defaults missing data to false", () => {
  assert.equal(allActiveDevicesSupportChatImages([]), false);
  assert.equal(allActiveDevicesSupportChatImages([{disabled: false, chatImageV1: true}]), true);
  assert.equal(allActiveDevicesSupportChatImages([
    {disabled: false, chatImageV1: true},
    {disabled: false},
  ]), false);
  assert.equal(allActiveDevicesSupportChatImages([
    {disabled: false, chatImageV1: true},
    {disabled: true},
  ]), true);
});

test("sender capability accepts one current device and ignores stale recipient-style tokens", () => {
  assert.equal(anyActiveDeviceSupportsChatImages([]), false);
  assert.equal(anyActiveDeviceSupportsChatImages([{disabled: false}]), false);
  assert.equal(anyActiveDeviceSupportsChatImages([
    {disabled: false},
    {disabled: false, chatImageV1: true},
  ]), true);
  assert.equal(anyActiveDeviceSupportsChatImages([
    {disabled: true, chatImageV1: true},
  ]), false);
});

test("closed-testing allowlist overrides a disabled public gate without trusting request data", () => {
  const testers = parseChatImageTesterUids(" uid-a,uid-b, uid-a ,, ");
  assert.deepEqual([...testers], ["uid-a", "uid-b"]);
  assert.equal(canAccountUseChatImageMessaging({
    publicEnabled: false, testerUids: testers, uid: "uid-a",
  }), true);
  assert.equal(canAccountUseChatImageMessaging({
    publicEnabled: false, testerUids: testers, uid: "ordinary-user",
  }), false);
  assert.equal(canAccountUseChatImageMessaging({
    publicEnabled: true, testerUids: new Set(), uid: "ordinary-user",
  }), true);
});

test("image commit data preserves delivery fields and selects the receiver unread counter", () => {
  const data = buildChatImageMessageData({
    senderId: "uid-a", receiverId: "uid-b", storagePath,
    width: 1200, height: 800, size: 128,
  });
  assert.deepEqual(data, {
    senderId: "uid-a", receiverId: "uid-b", text: "", type: "image",
    deliveredTo: [], readBy: [], sourceServiceId: "", sourceServiceTitle: "",
    storagePath, imageWidth: 1200, imageHeight: 800, imageSizeBytes: 128,
    mimeType: "image/jpeg", mediaSchemaVersion: 1,
  });
  assert.equal(chatImageUnreadField(["uid-a", "uid-b"], "uid-a"), "unreadCountCustomer");
  assert.equal(chatImageUnreadField(["uid-a", "uid-b"], "uid-b"), "unreadCountProvider");
  assert.throws(
    () => chatImageUnreadField(["uid-a", "uid-b"], "uid-c"),
    /receiver-not-participant/,
  );
});
