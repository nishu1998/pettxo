const test = require("node:test");
const assert = require("node:assert/strict");

const {
  PROVIDER_VERIFICATION_DOCUMENT_RETENTION_MS,
  calculateProviderVerificationDocumentDeletionAtMillis,
  providerVerificationDocumentPathBelongsToUser,
  collectProviderVerificationDocumentPaths,
  diffProviderVerificationDocumentPaths,
  cleanupReasonForVerificationStatus,
} = require("../lib/providerVerificationDocuments.js");

test("provider verification document retention is 30 days", () => {
  const nowMs = Date.UTC(2026, 6, 20, 0, 0, 0);
  assert.equal(
    calculateProviderVerificationDocumentDeletionAtMillis(nowMs),
    nowMs + PROVIDER_VERIFICATION_DOCUMENT_RETENTION_MS,
  );
});

test("provider verification paths stay scoped to the same uid", () => {
  assert.equal(
    providerVerificationDocumentPathBelongsToUser(
      "uid_123",
      "providerVerification/uid_123/identity/front.jpg",
    ),
    true,
  );
  assert.equal(
    providerVerificationDocumentPathBelongsToUser(
      "uid_123",
      "providerVerification/uid_other/identity/front.jpg",
    ),
    false,
  );
  assert.equal(
    providerVerificationDocumentPathBelongsToUser(
      "uid_123",
      "providerVerification/uid_123/identity/nested/front.jpg",
    ),
    false,
  );
  assert.equal(
    providerVerificationDocumentPathBelongsToUser(
      "uid_123",
      "providerVerification/uid_123/identity/../front.jpg",
    ),
    false,
  );
});

test("provider verification path helpers dedupe and diff replaced files", () => {
  assert.deepEqual(
    collectProviderVerificationDocumentPaths([
      "providerVerification/uid_123/identity/front.jpg",
      "providerVerification/uid_123/identity/front.jpg",
      "",
      null,
    ]),
    ["providerVerification/uid_123/identity/front.jpg"],
  );

  assert.deepEqual(
    diffProviderVerificationDocumentPaths(
      [
        "providerVerification/uid_123/identity/front-old.jpg",
        "providerVerification/uid_123/identity/back-old.jpg",
      ],
      ["providerVerification/uid_123/identity/front-new.jpg"],
    ),
    [
      "providerVerification/uid_123/identity/front-old.jpg",
      "providerVerification/uid_123/identity/back-old.jpg",
    ],
  );
});

test("cleanup reason maps only final review statuses", () => {
  assert.equal(cleanupReasonForVerificationStatus("approved"), "approved");
  assert.equal(cleanupReasonForVerificationStatus("rejected"), "rejected");
  assert.equal(cleanupReasonForVerificationStatus("pending"), null);
});
