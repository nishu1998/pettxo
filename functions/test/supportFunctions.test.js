const test = require("node:test");
const assert = require("node:assert/strict");

const {
  assertSupportTicketAllowsAdminReply,
} = require("../lib/support/supportFunctions.js");

test("admin replies remain allowed for active support-ticket states", () => {
  assert.doesNotThrow(() => assertSupportTicketAllowsAdminReply("open"));
  assert.doesNotThrow(() =>
    assertSupportTicketAllowsAdminReply("awaiting_support"),
  );
  assert.doesNotThrow(() =>
    assertSupportTicketAllowsAdminReply("awaiting_customer"),
  );
});

test("admin replies are rejected once a support ticket is resolved", () => {
  assert.throws(
    () => assertSupportTicketAllowsAdminReply("resolved"),
    (error) => {
      assert.equal(error.code, "failed-precondition");
      assert.equal(
        error.message,
        "This support ticket has already been resolved.",
      );
      return true;
    },
  );
});
