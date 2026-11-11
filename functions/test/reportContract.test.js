const test = require("node:test");
const assert = require("node:assert/strict");

const {
  moderationQueueIdForReport,
  normalizeReportContract,
  shouldCreateReportModerationQueueItem,
} = require("../lib/moderation/reportContract.js");

const timestamp = {
  seconds: 1_700_000_000,
  nanoseconds: 123_000_000,
  toDate: () => new Date(1_700_000_000_123),
};

function legacyReport(overrides = {}) {
  return {
    type: "service",
    targetId: "service-1",
    reportedBy: "reporter-1",
    status: "pending",
    reason: "Misleading listing",
    description: "The listing details are inconsistent.",
    createdAt: timestamp,
    ...overrides,
  };
}

test("normalizes the live legacy service report shape", () => {
  const result = normalizeReportContract(legacyReport());

  assert.equal(result.ok, true);
  assert.deepEqual(result.report, {
    targetType: "service",
    targetId: "service-1",
    reporterId: "reporter-1",
    claimedTargetOwnerId: "",
    status: "pending",
    reason: "Misleading listing",
    description: "The listing details are inconsistent.",
    serviceId: "",
  });
});

test("normalizes the live legacy review report without requiring service context", () => {
  const result = normalizeReportContract(legacyReport({
    type: "review",
    targetId: "review-1",
  }));

  assert.equal(result.ok, true);
  assert.equal(result.report.targetType, "review");
  assert.equal(result.report.targetId, "review-1");
  assert.equal(result.report.serviceId, "");
});

test("normalizes the canonical report aliases", () => {
  const result = normalizeReportContract({
    targetType: "review",
    targetId: "review-2",
    reporterId: "reporter-2",
    targetOwnerId: "provider-2",
    contextId: "service-2",
    status: "open",
    reason: "Spam",
    updatedAt: new Date("2026-01-01T00:00:00.000Z"),
  });

  assert.equal(result.ok, true);
  assert.equal(result.report.targetType, "review");
  assert.equal(result.report.reporterId, "reporter-2");
  assert.equal(result.report.claimedTargetOwnerId, "provider-2");
  assert.equal(result.report.serviceId, "service-2");
  assert.equal(result.report.status, "open");
});

test("normalizes matching dual legacy and canonical aliases", () => {
  const result = normalizeReportContract(legacyReport({
    type: " Service ",
    targetType: "service",
    reportedBy: "reporter-1",
    reporterId: " reporter-1 ",
    serviceId: "service-1",
    contextId: "service-1",
  }));

  assert.equal(result.ok, true);
  assert.equal(result.report.targetType, "service");
  assert.equal(result.report.reporterId, "reporter-1");
});

test("rejects conflicting aliases", () => {
  assert.deepEqual(
    normalizeReportContract(legacyReport({targetType: "review"})),
    {ok: false, code: "conflicting_type_aliases"},
  );
  assert.deepEqual(
    normalizeReportContract(legacyReport({reporterId: "different-reporter"})),
    {ok: false, code: "conflicting_reporter_aliases"},
  );
  assert.deepEqual(
    normalizeReportContract(legacyReport({
      serviceId: "service-1",
      contextId: "service-2",
    })),
    {ok: false, code: "conflicting_service_context_aliases"},
  );
});

test("rejects a missing type", () => {
  const report = legacyReport();
  delete report.type;
  assert.deepEqual(normalizeReportContract(report), {
    ok: false,
    code: "missing_type",
  });
});

test("rejects a missing reporter", () => {
  const report = legacyReport();
  delete report.reportedBy;
  assert.deepEqual(normalizeReportContract(report), {
    ok: false,
    code: "missing_reporter",
  });
});

test("rejects a missing target ID", () => {
  const report = legacyReport();
  delete report.targetId;
  assert.deepEqual(normalizeReportContract(report), {
    ok: false,
    code: "missing_target_id",
  });
});

test("rejects unsupported report types without enabling post or comment reports", () => {
  for (const type of ["post", "comment", "user", "message"]) {
    assert.deepEqual(normalizeReportContract(legacyReport({type})), {
      ok: false,
      code: "unsupported_type",
    });
  }
});

test("rejects invalid statuses and does not accept canonical open on legacy shapes", () => {
  for (const status of ["resolved", "rejected", "closed", ""]) {
    assert.deepEqual(normalizeReportContract(legacyReport({status})), {
      ok: false,
      code: "invalid_status",
    });
  }
  assert.deepEqual(normalizeReportContract(legacyReport({status: "open"})), {
    ok: false,
    code: "invalid_status",
  });
});

test("rejects invalid timestamps and malformed fields", () => {
  assert.deepEqual(
    normalizeReportContract(legacyReport({createdAt: "yesterday"})),
    {ok: false, code: "invalid_timestamp"},
  );
  assert.deepEqual(
    normalizeReportContract(legacyReport({reason: {text: "Spam"}})),
    {ok: false, code: "invalid_reason"},
  );
  assert.deepEqual(
    normalizeReportContract(legacyReport({targetOwnerId: ["provider-1"]})),
    {ok: false, code: "invalid_target_owner"},
  );
  assert.deepEqual(normalizeReportContract([]), {
    ok: false,
    code: "invalid_type",
  });
});

test("queue IDs are deterministic and retry decisions preserve existing cases", () => {
  assert.equal(moderationQueueIdForReport("report-id-1"), "report_report-id-1");
  assert.equal(moderationQueueIdForReport(" report-id-1 "), "report_report-id-1");
  assert.equal(shouldCreateReportModerationQueueItem(null), true);
  assert.equal(shouldCreateReportModerationQueueItem(undefined), true);
  assert.equal(shouldCreateReportModerationQueueItem({status: "pending"}), false);
  assert.equal(shouldCreateReportModerationQueueItem({
    status: "resolved",
    assignedAdminId: "admin-1",
  }), false);
  assert.throws(() => moderationQueueIdForReport("bad/report"), /Invalid report ID/);
});
