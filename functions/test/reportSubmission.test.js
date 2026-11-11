const test = require("node:test");
const assert = require("node:assert/strict");

const {
  parseSubmitReportInput,
  reportIdForSubmission,
  submitReportData,
} = require("../lib/moderation/reportSubmission.js");

function assertHttpsCode(code) {
  return (error) => {
    assert.equal(error.code, code);
    return true;
  };
}

test("parses bounded canonical service and review requests", () => {
  assert.deepEqual(parseSubmitReportInput({
    type: "service",
    targetId: "service-1",
    reason: "inappropriate_content",
    description: "  Review this listing.  ",
    clientRequestId: "mobile-request:1",
  }), {
    type: "service",
    targetId: "service-1",
    contextId: "",
    reason: "inappropriate_content",
    description: "Review this listing.",
    clientRequestId: "mobile-request:1",
  });

  assert.equal(parseSubmitReportInput({
    type: "review",
    targetId: "review-1",
    contextId: "service-1",
    reason: "spam",
  }).contextId, "service-1");
});

test("requires review context and rejects service context", () => {
  assert.throws(() => parseSubmitReportInput({
    type: "review",
    targetId: "review-1",
    reason: "spam",
  }), assertHttpsCode("invalid-argument"));
  assert.throws(() => parseSubmitReportInput({
    type: "service",
    targetId: "service-1",
    contextId: "service-2",
    reason: "spam",
  }), assertHttpsCode("invalid-argument"));
});

test("rejects unsupported report types", () => {
  for (const type of ["user", "profile", "chat", "message", "post", "comment"]) {
    assert.throws(() => parseSubmitReportInput({
      type,
      targetId: "target-1",
      reason: "spam",
    }), assertHttpsCode("invalid-argument"));
  }
});

test("rejects forged server-owned and administrative fields", () => {
  for (const field of [
    "reportedBy",
    "reporterId",
    "targetOwnerId",
    "status",
    "targetPath",
    "evidencePaths",
    "assignedAdminId",
  ]) {
    assert.throws(() => parseSubmitReportInput({
      type: "service",
      targetId: "service-1",
      reason: "spam",
      [field]: "forged",
    }), assertHttpsCode("invalid-argument"));
  }
});

test("rejects invalid reasons, document IDs, request IDs, and descriptions", () => {
  assert.throws(() => parseSubmitReportInput({
    type: "service",
    targetId: "service/escape",
    reason: "spam",
  }), assertHttpsCode("invalid-argument"));
  assert.throws(() => parseSubmitReportInput({
    type: "service",
    targetId: "service-1",
    reason: "custom unbounded reason",
  }), assertHttpsCode("invalid-argument"));
  assert.throws(() => parseSubmitReportInput({
    type: "service",
    targetId: "service-1",
    reason: "spam",
    clientRequestId: "bad/request",
  }), assertHttpsCode("invalid-argument"));
  assert.throws(() => parseSubmitReportInput({
    type: "service",
    targetId: "service-1",
    reason: "spam",
    description: "x".repeat(2001),
  }), assertHttpsCode("invalid-argument"));
});

test("submission IDs are deterministic per reporter and target identity", () => {
  const input = {
    reporterId: "reporter-1",
    type: "review",
    targetId: "review-1",
    contextId: "service-1",
  };
  const first = reportIdForSubmission(input);
  assert.equal(first, reportIdForSubmission(input));
  assert.notEqual(first, reportIdForSubmission({...input, reporterId: "reporter-2"}));
  assert.notEqual(first, reportIdForSubmission({...input, targetId: "review-2"}));
  assert.match(first, /^report_[a-f0-9]{64}$/);
});

test("rejects unauthenticated submission before any Firestore access", async () => {
  await assert.rejects(submitReportData({
    firestore: null,
    authUid: "",
    input: {},
  }), assertHttpsCode("unauthenticated"));
});

test("submitReport is a Gen 2 callable in asia-south1 without App Check enforcement", () => {
  const {submitReport} = require("../lib/moderation/reportFunctions.js");
  assert.equal(submitReport.__endpoint.platform, "gcfv2");
  assert.deepEqual(submitReport.__endpoint.region, ["asia-south1"]);
  assert.deepEqual(submitReport.__endpoint.callableTrigger, {});
});
