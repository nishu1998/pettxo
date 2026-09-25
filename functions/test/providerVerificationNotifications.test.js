const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildProviderVerificationDecisionNotification,
} = require("../lib/providerVerification/providerVerificationNotifications.js");

function build(params = {}) {
  return buildProviderVerificationDecisionNotification({
    beforeStatus: "pending",
    afterStatus: "approved",
    providerUserId: "provider-123",
    submissionId: "submission-abc",
    ...params,
  });
}

function serialized(value) {
  return JSON.stringify(value).toLowerCase();
}

test("pending to approved creates one canonical provider notification", () => {
  const notification = build();

  assert.ok(notification);
  assert.equal(notification.document.userId, "provider-123");
  assert.equal(notification.document.category, "account");
  assert.equal(notification.document.type, "providerVerificationApproved");
  assert.equal(notification.document.title, "Verification approved");
  assert.equal(
    notification.document.body,
    "You can now offer services as a verified provider.",
  );
  assert.deepEqual(notification.document.channels, ["in_app", "push"]);
  assert.equal(notification.document.visibleInApp, true);
  assert.deepEqual(notification.document.data, {
    category: "account",
    type: "providerVerificationApproved",
    navigationIntent: "provider_verification",
  });
});

test("pending to rejected omits rejection and identity evidence", () => {
  const notification = build({
    afterStatus: "rejected",
    rejectionReason: "Identity document did not match",
    documentFrontPath: "providerVerification/provider-123/private/front.jpg",
  });

  assert.ok(notification);
  assert.equal(notification.document.userId, "provider-123");
  assert.equal(notification.document.type, "providerVerificationRejected");
  assert.equal(notification.document.title, "Verification needs attention");
  assert.match(notification.document.body, /review the details and resubmit/i);

  const payload = serialized(notification);
  for (const sensitiveTerm of [
    "rejectionreason",
    "documentfront",
    "documentback",
    "storagepath",
    "filename",
    "aadhaar",
    "pan",
    "voter id",
    "driving licence",
  ]) {
    assert.equal(payload.includes(sensitiveTerm), false, sensitiveTerm);
  }
});

test("retry returns the same deterministic notification identity", () => {
  const first = build();
  const retry = build();

  assert.ok(first);
  assert.ok(retry);
  assert.equal(first.documentId, retry.documentId);
  assert.match(first.documentId, /^provider_verification_approved_[a-f0-9]{32}$/);
});

test("non-decision and repeated states create no notification", () => {
  assert.equal(build({beforeStatus: "approved"}), null);
  assert.equal(build({beforeStatus: "rejected", afterStatus: "rejected"}), null);
  assert.equal(build({afterStatus: "pending"}), null);
  assert.equal(build({afterStatus: "pending", submissionId: "submission-new"}), null);
  assert.equal(build({afterStatus: "approved", submissionId: ""}), null);
});

test("new resubmission can receive its own later decision notification", () => {
  const original = build();
  const resubmission = build({submissionId: "submission-new"});

  assert.ok(original);
  assert.ok(resubmission);
  assert.notEqual(original.documentId, resubmission.documentId);
});

test("document-path provider uid is the sole notification recipient input", () => {
  const notification = build({providerUserId: "provider-from-path"});

  assert.ok(notification);
  assert.equal(notification.document.userId, "provider-from-path");
  assert.equal(serialized(notification).includes("admin-user"), false);
});
