const test = require("node:test");
const assert = require("node:assert/strict");

const {
  canonicalChatIdForUidPair,
  canonicalDirectChatDocumentIdentity,
  canonicalDirectChatIdentity,
  canonicalParticipantIds,
  canonicalUserDocumentMatches,
  chatStatusAllowsMessages,
  otherDirectParticipantUid,
} = require("../lib/chat/chatIdentity.js");

function directChat(overrides = {}) {
  return {
    chatType: "directUser",
    participantIds: ["uid-a", "uid-b"],
    customerId: "uid-a",
    providerId: "uid-b",
    customerName: "Old display name",
    providerName: "Pettxo Community",
    ...overrides,
  };
}

test("direct chat id is deterministic for both creation directions", () => {
  assert.equal(
    canonicalChatIdForUidPair("uid-a", "uid-b"),
    "chat_uid-a_uid-b",
  );
  assert.equal(
    canonicalChatIdForUidPair("uid-b", "uid-a"),
    "chat_uid-a_uid-b",
  );
});

test("canonical participants are sorted and independent of booking roles", () => {
  assert.deepEqual(canonicalParticipantIds("provider-1", "parent-1"), [
    "parent-1",
    "provider-1",
  ]);
  assert.deepEqual(canonicalParticipantIds("parent-1", "provider-1"), [
    "parent-1",
    "provider-1",
  ]);
  assert.equal(canonicalParticipantIds("same", "same"), null);
});

test("mutable profile fields cannot affect direct chat identity", () => {
  const before = directChat({
    providerName: "Pettxo Community",
    providerUsername: "pettxocommunity",
    providerEmail: "old@example.com",
    providerPhone: "+910000000000",
  });
  const after = directChat({
    providerName: "Pettxo",
    providerUsername: "pettxo",
    providerEmail: "new@example.com",
    providerPhone: "+919999999999",
  });

  assert.deepEqual(canonicalDirectChatIdentity(before), canonicalDirectChatIdentity(after));
  assert.equal(canonicalChatIdForUidPair("uid-a", "uid-b"), "chat_uid-a_uid-b");
});

test("canonical user validation rejects arbitrary and mismatched document IDs", () => {
  assert.equal(canonicalUserDocumentMatches("uid-b", {uid: "uid-b"}), true);
  assert.equal(
    canonicalUserDocumentMatches("pettxocommunity", {uid: "uid-b"}),
    false,
  );
  assert.equal(canonicalUserDocumentMatches("pettxo", {}), false);
});

test("direct participant identity must be sorted, distinct, and compatible", () => {
  assert.ok(canonicalDirectChatIdentity(directChat()));
  assert.equal(
    canonicalDirectChatIdentity(directChat({participantIds: ["uid-b", "uid-a"]})),
    null,
  );
  assert.equal(
    canonicalDirectChatIdentity(directChat({participantIds: ["uid-a", "uid-a"]})),
    null,
  );
  assert.equal(
    canonicalDirectChatIdentity(directChat({providerId: "pettxocommunity"})),
    null,
  );
});

test("direct operations reject a noncanonical document ID", () => {
  assert.ok(canonicalDirectChatDocumentIdentity("chat_uid-a_uid-b", directChat()));
  assert.equal(
    canonicalDirectChatDocumentIdentity("direct_uid-a_uid-b", directChat()),
    null,
  );
  assert.equal(
    canonicalDirectChatDocumentIdentity("chat_uid-a_pettxocommunity", directChat()),
    null,
  );
});

test("message recipient comes only from canonical participant UIDs", () => {
  const identity = canonicalDirectChatIdentity(directChat({
    customerName: "Mutable A",
    providerName: "Mutable B",
  }));
  assert.ok(identity);
  assert.equal(otherDirectParticipantUid(identity, "uid-a"), "uid-b");
  assert.equal(otherDirectParticipantUid(identity, "uid-b"), "uid-a");
  assert.equal(otherDirectParticipantUid(identity, "username-b"), null);
});

test("booking chats are not interpreted as UID-pair direct chats", () => {
  assert.equal(
    canonicalDirectChatIdentity(directChat({chatType: "booking"})),
    null,
  );
});

test("only an active canonical user conversation can send messages", () => {
  assert.equal(chatStatusAllowsMessages("directUser", "active"), true);
  assert.equal(chatStatusAllowsMessages("directUser", "unlocked"), false);
  assert.equal(chatStatusAllowsMessages("booking", "unlocked"), false);
  assert.equal(chatStatusAllowsMessages("booking", "active"), false);
  assert.equal(chatStatusAllowsMessages("booking", "closed"), false);
});
