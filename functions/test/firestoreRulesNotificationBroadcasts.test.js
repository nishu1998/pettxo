const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const rules = fs.readFileSync(
  path.resolve(__dirname, "../../firestore.rules"),
  "utf8",
);

test("notification broadcast records are fully denied to clients", () => {
  assert.match(
    rules,
    /match \/notificationBroadcasts\/\{broadcastId\}\s*\{\s*allow read, write: if false;\s*\}/s,
  );
});
