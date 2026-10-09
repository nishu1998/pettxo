const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {doc, setDoc} = require("firebase/firestore");
const {deleteObject, getBytes, listAll, ref, uploadBytes} = require("firebase/storage");

const hasEmulators = Boolean(
  process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_STORAGE_EMULATOR_HOST,
);
let environment;
const chatId = "chat_uid-a_uid-b";
const messageId = "AbCdEfGhIjKlMnOpQrSt";
const imagePath = `chatMedia/${chatId}/${messageId}/image.jpg`;
const bytes = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);

function uploadMetadata(overrides = {}) {
  return {
    contentType: "image/jpeg",
    customMetadata: {chatId, messageId, senderId: "uid-a"},
    ...overrides,
  };
}

test.before(async () => {
  if (!hasEmulators) return;
  environment = await initializeTestEnvironment({
    projectId: "pettexo-d9409",
    firestore: {rules: fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8")},
    storage: {rules: fs.readFileSync(path.resolve(__dirname, "../../storage.rules"), "utf8")},
  });
  await environment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await setDoc(doc(firestore, "users/uid-a"), {uid: "uid-a"});
    await setDoc(doc(firestore, "users/uid-b"), {uid: "uid-b"});
    await setDoc(doc(firestore, "users/uid-c"), {uid: "uid-c"});
    await setDoc(doc(firestore, "users/super"), {adminRole: "superAdmin"});
    await setDoc(doc(firestore, "users/support"), {adminRole: "customerSupportAdmin"});
    await setDoc(doc(firestore, "users/finance"), {adminRole: "financeAdmin"});
    await setDoc(doc(firestore, `chats/${chatId}`), {
      chatType: "directUser", status: "active",
      customerId: "uid-a", providerId: "uid-b", participantIds: ["uid-a", "uid-b"],
    });
    await setDoc(doc(firestore, "chats/not-canonical"), {
      chatType: "directUser", status: "active",
      customerId: "uid-a", providerId: "uid-b", participantIds: ["uid-a", "uid-b"],
    });
  });
});

test.after(async () => environment?.cleanup());

test("participants can create and read historical media after either app upgrades", {skip: !hasEmulators}, async () => {
  await assertSucceeds(uploadBytes(
    ref(environment.authenticatedContext("uid-a").storage(), imagePath),
    bytes,
    uploadMetadata(),
  ));
  await assertSucceeds(getBytes(ref(environment.authenticatedContext("uid-a").storage(), imagePath)));
  await assertSucceeds(getBytes(ref(environment.authenticatedContext("uid-b").storage(), imagePath)));
  await assertFails(getBytes(ref(environment.authenticatedContext("uid-c").storage(), imagePath)));
  await assertFails(uploadBytes(
    ref(environment.authenticatedContext("uid-c").storage(),
      `chatMedia/${chatId}/BcDeFgHiJkLmNoPqRsTu/image.jpg`),
    bytes,
    {contentType: "image/jpeg", customMetadata: {
      chatId, messageId: "BcDeFgHiJkLmNoPqRsTu", senderId: "uid-c",
    }},
  ));
});

test("metadata, MIME, size, overwrite, and listing restrictions are enforced", {skip: !hasEmulators}, async () => {
  const storage = environment.authenticatedContext("uid-a").storage();
  const candidates = [
    ["BcDeFgHiJkLmNoPqRsTu", uploadMetadata({customMetadata: {chatId: "wrong", messageId: "BcDeFgHiJkLmNoPqRsTu", senderId: "uid-a"}}), bytes],
    ["CdEfGhIjKlMnOpQrStUv", uploadMetadata({contentType: "image/png", customMetadata: {chatId, messageId: "CdEfGhIjKlMnOpQrStUv", senderId: "uid-a"}}), bytes],
    ["DeFgHiJkLmNoPqRsTuVw", uploadMetadata({customMetadata: {chatId, messageId: "DeFgHiJkLmNoPqRsTuVw", senderId: "uid-a"}}), new Uint8Array()],
    ["EfGhIjKlMnOpQrStUvWx", uploadMetadata({customMetadata: {chatId, messageId: "EfGhIjKlMnOpQrStUvWx", senderId: "uid-a"}}), new Uint8Array(3 * 1024 * 1024 + 1)],
  ];
  for (const [id, metadata, data] of candidates) {
    await assertFails(uploadBytes(ref(storage, `chatMedia/${chatId}/${id}/image.jpg`), data, metadata));
  }
  const overwriteMessageId = "FgHiJkLmNoPqRsTuVwXy";
  const overwritePath = `chatMedia/${chatId}/${overwriteMessageId}/image.jpg`;
  const overwriteMetadata = uploadMetadata({customMetadata: {
    chatId, messageId: overwriteMessageId, senderId: "uid-a",
  }});
  await assertSucceeds(uploadBytes(ref(storage, overwritePath), bytes, overwriteMetadata));
  await assertFails(uploadBytes(ref(storage, overwritePath), bytes, overwriteMetadata));
  await assertFails(listAll(ref(storage, `chatMedia/${chatId}`)));
  await assertFails(uploadBytes(
    ref(storage, `chatMedia/not-canonical/GhIjKlMnOpQrStUvWxYz/image.jpg`),
    bytes,
    {contentType: "image/jpeg", customMetadata: {
      chatId: "not-canonical", messageId: "GhIjKlMnOpQrStUvWxYz", senderId: "uid-a",
    }},
  ));
});

test("only chat moderators can inspect media and finance admin cannot", {skip: !hasEmulators}, async () => {
  await assertSucceeds(getBytes(ref(environment.authenticatedContext("super").storage(), imagePath)));
  await assertSucceeds(getBytes(ref(environment.authenticatedContext("support").storage(), imagePath)));
  await assertFails(getBytes(ref(environment.authenticatedContext("finance").storage(), imagePath)));
});

test("only the uploader may delete an uncommitted upload", {skip: !hasEmulators}, async () => {
  await assertFails(deleteObject(ref(environment.authenticatedContext("uid-b").storage(), imagePath)));
  await assertSucceeds(deleteObject(ref(environment.authenticatedContext("uid-a").storage(), imagePath)));
});
