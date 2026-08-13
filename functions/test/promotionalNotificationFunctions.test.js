const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildStoredPromotionalNotificationDocument,
} = require("../lib/notifications/notificationChannels.js");
const {
  assertAuthenticatedUid,
  assertPromotionalBroadcastPermission,
  matchesPromotionalAudience,
  promotionalBroadcastDocIdFromRequestId,
  promotionalNotificationDocId,
  validatePromotionalBroadcastRequest,
} = require("../lib/notifications/promotionalNotificationFunctions.js");

test("promotional broadcasts reject unauthenticated callers", () => {
  assert.throws(() => assertAuthenticatedUid(""), (error) => {
    assert.match(String(error.message), /Sign in to continue/);
    return true;
  });
  assert.doesNotThrow(() => assertAuthenticatedUid("admin_1"));
});

test("promotional broadcasts allow only superAdmin and financeAdmin roles", () => {
  assert.doesNotThrow(() => assertPromotionalBroadcastPermission("superAdmin"));
  assert.doesNotThrow(() => assertPromotionalBroadcastPermission("financeAdmin"));
  assert.throws(
    () => assertPromotionalBroadcastPermission("customerSupportAdmin"),
    (error) => {
      assert.equal(error.code, "permission-denied");
      return true;
    },
  );
  assert.throws(
    () => assertPromotionalBroadcastPermission(""),
    (error) => {
      assert.equal(error.code, "permission-denied");
      return true;
    },
  );
});

test("promotional broadcast request validation rejects invalid payloads", () => {
  assert.throws(() => validatePromotionalBroadcastRequest({}), /title is required/);
  assert.throws(
    () => validatePromotionalBroadcastRequest({
      title: "Hi",
      body: "",
      audience: "all",
      requestId: "req_1",
    }),
    /body is required/,
  );
  assert.throws(
    () => validatePromotionalBroadcastRequest({
      title: "Hi",
      body: "Body",
      audience: "everyone",
      requestId: "req_1",
    }),
    /audience is invalid/,
  );
  assert.throws(
    () => validatePromotionalBroadcastRequest({
      title: "Hi",
      body: "Body",
      audience: "all",
      requestId: "",
    }),
    /requestId is required/,
  );
  assert.throws(
    () => validatePromotionalBroadcastRequest({
      title: "x".repeat(121),
      body: "Body",
      audience: "all",
      requestId: "req_1",
    }),
    /title is too long/,
  );
  assert.throws(
    () => validatePromotionalBroadcastRequest({
      title: "Title",
      body: "x".repeat(241),
      audience: "all",
      requestId: "req_1",
    }),
    /body is too long/,
  );
  assert.throws(
    () => validatePromotionalBroadcastRequest({
      title: "Title",
      body: "Body",
      audience: "all",
      requestId: "bad request id",
    }),
    /requestId format is invalid/,
  );
});

test("promotional audience matching uses only persisted role values", () => {
  assert.equal(
    matchesPromotionalAudience("serviceProvider", {role: "serviceProvider"}),
    true,
  );
  assert.equal(matchesPromotionalAudience("serviceProvider", {role: "petParent"}), false);
  assert.equal(matchesPromotionalAudience("petParent", {role: "petParent"}), true);
  assert.equal(matchesPromotionalAudience("petParent", {role: "petLover"}), false);
  assert.equal(matchesPromotionalAudience("petParent", {}), false);
  assert.equal(matchesPromotionalAudience("petLover", {role: "petLover"}), true);
  assert.equal(matchesPromotionalAudience("all", {}), true);
});

test("promotional identifiers remain deterministic for idempotency", () => {
  assert.equal(
    promotionalBroadcastDocIdFromRequestId("req_123"),
    "promo_broadcast_req_123",
  );
  assert.equal(
    promotionalNotificationDocId("promo_broadcast_req_123", "user_1"),
    "promo_promo_broadcast_req_123_user_1",
  );
});

test("promotional notification documents use in-app plus push without action metadata", () => {
  const stored = buildStoredPromotionalNotificationDocument({
    recipientUserId: "user_1",
    broadcastId: "promo_broadcast_req_1",
    title: "Pettxo update",
    body: "Check out what's new this week.",
    createdAt: "created",
    updatedAt: "updated",
    source: "admin_promotional_broadcast",
  });

  assert.equal(stored.userId, "user_1");
  assert.equal(stored.category, "promotion");
  assert.equal(stored.type, "promotionalBroadcast");
  assert.deepEqual(stored.channels, ["in_app", "push"]);
  assert.equal(stored.visibleInApp, true);
  assert.equal(stored.broadcastId, "promo_broadcast_req_1");
  assert.deepEqual(stored.data, {
    category: "promotion",
    type: "promotionalBroadcast",
    broadcastId: "promo_broadcast_req_1",
  });
  assert.equal("bookingId" in stored, false);
  assert.equal("serviceId" in stored, false);
  assert.equal("ticketId" in stored, false);
  assert.equal("postId" in stored, false);
});
