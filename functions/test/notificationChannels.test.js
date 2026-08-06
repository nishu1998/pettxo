const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildStoredBookingNotificationDocument,
  normalizeNotificationChannels,
  notificationDeliversPush,
  notificationVisibleInApp,
} = require("../lib/notifications/notificationChannels.js");

test("notification channels normalize in deterministic order without duplicates", () => {
  assert.deepEqual(
    normalizeNotificationChannels(["push", "in_app", "push", "whatsapp"]),
    ["in_app", "push", "whatsapp"],
  );
  assert.deepEqual(normalizeNotificationChannels([]), []);
});

test("stored booking notifications persist normalized channels and visibleInApp", () => {
  const stored = buildStoredBookingNotificationDocument({
    notification: {
      recipientUserId: "parent-1",
      type: "payment_required",
      title: "Provider accepted your request",
      body: "Complete payment within 60 minutes.",
      channels: ["push", "in_app", "push"],
      data: {
        bookingId: "booking-1",
        recipientRole: "customer",
      },
    },
    actorId: "system",
    createdAt: "created",
    updatedAt: "updated",
    source: "canonical_v3",
  });

  assert.deepEqual(stored.channels, ["in_app", "push"]);
  assert.equal(stored.visibleInApp, true);
  assert.equal(stored.recipientRole, "customer");
});

test("push delivery enforcement respects explicit channel intent and legacy fallback", () => {
  assert.equal(notificationDeliversPush(["push"]), true);
  assert.equal(notificationDeliversPush(["in_app", "push"]), true);
  assert.equal(notificationDeliversPush(["in_app"]), false);
  assert.equal(notificationDeliversPush(["whatsapp"]), false);
  assert.equal(notificationDeliversPush([]), false);
  assert.equal(notificationDeliversPush(undefined), true);
});

test("in-app visibility respects explicit channel intent and legacy fallback", () => {
  assert.equal(notificationVisibleInApp(["in_app"]), true);
  assert.equal(notificationVisibleInApp(["push"]), false);
  assert.equal(notificationVisibleInApp(["whatsapp"]), false);
  assert.equal(notificationVisibleInApp(["in_app", "push"]), true);
  assert.equal(notificationVisibleInApp(undefined), true);
});
