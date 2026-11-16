const test = require("node:test");
const assert = require("node:assert/strict");

const {
  parseReportId,
} = require("../lib/moderation/reportModeration.js");
const productionExports = require("../lib/index.js");

function assertHttpsCode(code) {
  return (error) => {
    assert.equal(error.code, code);
    return true;
  };
}

test("report moderation input preserves the dashboard reportId contract", () => {
  assert.equal(parseReportId({reportId: " report-1 "}), "report-1");
  for (const input of [null, {}, {reportId: ""}, {reportId: "bad/id"}]) {
    assert.throws(() => parseReportId(input), assertHttpsCode("invalid-argument"));
  }
  assert.throws(
    () => parseReportId({reportId: "report-1", targetPath: "services/forged"}),
    assertHttpsCode("invalid-argument"),
  );
});

test("the four report callables are Gen 2 functions in asia-south1", () => {
  for (const name of [
    "resolveReport",
    "rejectReport",
    "hideReportedService",
    "hideReportedReview",
  ]) {
    const endpoint = productionExports[name].__endpoint;
    assert.equal(endpoint.platform, "gcfv2", name);
    assert.deepEqual(endpoint.region, ["asia-south1"], name);
    assert.ok(endpoint.callableTrigger, name);
  }
});
