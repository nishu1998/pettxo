const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  STORAGE_RULES_FIRESTORE_DOCUMENT_LIMIT,
  analyzeStorageRules,
} = require("./helpers/storageRulesFirestoreBudget");

// Production Storage Rules may access at most two distinct Firestore documents
// per evaluation; a third is a permission-denied error. The Storage emulator
// does not enforce this, so it is checked statically. Phase 3C-4: the 9ce090a
// chat media create rule read chats/{chatId} plus both directed userBlocks
// documents (three) and denied every chat photo in production.

test("every Storage Rules allow statement reaches at most two Firestore documents", () => {
  const source = fs.readFileSync(path.resolve(__dirname, "../../storage.rules"), "utf8");
  const results = analyzeStorageRules(source);
  assert.ok(results.length >= 30, `expected the full rule set, parsed ${results.length}`);
  const overBudget = results.filter((entry) => entry.paths.length > STORAGE_RULES_FIRESTORE_DOCUMENT_LIMIT);
  assert.deepEqual(overBudget, [], JSON.stringify(overBudget, null, 2));
  const chatMediaCreate = results.find((entry) =>
    entry.match.endsWith("/chatMedia/{chatId}/{messageId}/image.jpg") && entry.methods.includes("create"));
  assert.ok(chatMediaCreate, "chat media create rule must exist");
  assert.equal(chatMediaCreate.paths.length, 1);
});

test("the 9ce090a chat media create rule is detected as over budget", () => {
  const prefix = `rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    function chatForMedia(chatId) {
      return firestore.get(/databases/(default)/documents/chats/$(chatId));
    }
    function directedUserBlockExists(ownerUid, blockedUid) {
      return firestore.exists(
        /databases/(default)/documents/userBlocks/$(ownerUid + "_" + blockedUid)
      );
    }
    function chatRelationshipAllowsMedia(chatId) {
      let chat = chatForMedia(chatId).data;
      let firstUid = chat.participantIds[0];
      let secondUid = chat.participantIds[1];
      return !directedUserBlockExists(firstUid, secondUid) &&
        !directedUserBlockExists(secondUid, firstUid);
    }
    function isChatMediaParticipant(chatId) {
      return firestore.exists(/databases/(default)/documents/chats/$(chatId)) &&
        request.auth.uid in chatForMedia(chatId).data.participantIds;
    }
    match /chatMedia/{chatId}/{messageId}/image.jpg {
      allow create: if isChatMediaParticipant(chatId) &&
        chatRelationshipAllowsMedia(chatId) &&
        chatForMedia(chatId).data.status == "active";
    }
  }
}`;
  const [entry] = analyzeStorageRules(prefix);
  assert.equal(entry.paths.length, 3, JSON.stringify(entry.paths));
  assert.ok(entry.paths.length > STORAGE_RULES_FIRESTORE_DOCUMENT_LIMIT);
});

test("repeated get and exists of the same document count once", () => {
  const source = `service firebase.storage {
  match /b/{bucket}/o {
    function chat(chatId) {
      return firestore.get(/databases/(default)/documents/chats/$(chatId));
    }
    match /x/{chatId} {
      allow read: if firestore.exists(/databases/(default)/documents/chats/$(chatId)) &&
        chat(chatId).data.a == 1 && chat(chatId).data.b == 2;
    }
  }
}`;
  const [entry] = analyzeStorageRules(source);
  assert.equal(entry.paths.length, 1, JSON.stringify(entry.paths));
});
