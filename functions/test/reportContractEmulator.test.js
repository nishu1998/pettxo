const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const {
  createReportModerationQueueItemOnce,
  moderationQueueIdForReport,
  normalizeReportContract,
  resolveReportTargetOwnership,
} = require("../lib/moderation/reportContract.js");

const enabled = /^(127\.0\.0\.1|localhost):\d+$/.test(
  process.env.FIRESTORE_EMULATOR_HOST ?? "",
);

async function fixture(run) {
  const app = initializeApp(
    {projectId: "demo-report-contract"},
    `report-contract-${randomUUID()}`,
  );
  const firestore = getFirestore(app);
  try {
    await run(firestore);
  } finally {
    await firestore.terminate();
    await deleteApp(app);
  }
}

function queueItem(reportId, overrides = {}) {
  return {
    targetType: "service",
    targetId: "service-1",
    targetOwnerId: "provider-1",
    source: "report",
    reportId,
    severity: "medium",
    status: "pending",
    reason: "User report",
    assignedAdminId: "",
    createdAt: "initial-created-at",
    updatedAt: "initial-updated-at",
    ...overrides,
  };
}

function normalizedReport(overrides = {}) {
  const result = normalizeReportContract({
    type: "service",
    targetId: "service-1",
    reportedBy: "reporter-1",
    targetOwnerId: "untrusted-client-claim",
    status: "pending",
    ...overrides,
  });
  assert.equal(result.ok, true);
  return result.report;
}

test("report ownership emulator: service owner is resolved authoritatively", {
  skip: !enabled,
}, async () => {
  await fixture(async (firestore) => {
    await firestore.doc("services/service-1").set({ownerUserId: "provider-1"});
    const ownership = await resolveReportTargetOwnership({
      firestore,
      report: normalizedReport(),
    });

    assert.deepEqual(ownership, {
      status: "resolved",
      targetOwnerId: "provider-1",
      diagnosticCode: "resolved_from_service",
    });
  });
});

test("report ownership emulator: legacy review without service context stays unresolved", {
  skip: !enabled,
}, async () => {
  await fixture(async (firestore) => {
    const ownership = await resolveReportTargetOwnership({
      firestore,
      report: normalizedReport({type: "review", targetId: "review-1"}),
    });

    assert.deepEqual(ownership, {
      status: "unresolved",
      targetOwnerId: "",
      diagnosticCode: "review_context_missing",
    });
  });
});

test("report ownership emulator: contextual review resolves only through its parent service", {
  skip: !enabled,
}, async () => {
  await fixture(async (firestore) => {
    await firestore.doc("services/service-2").set({ownerUserId: "provider-2"});
    await firestore.doc("services/service-2/reviews/review-2").set({
      providerUserId: "provider-2",
      reviewerUserId: "reviewer-2",
    });
    const ownership = await resolveReportTargetOwnership({
      firestore,
      report: normalizedReport({
        type: "review",
        targetId: "review-2",
        serviceId: "service-2",
      }),
    });

    assert.deepEqual(ownership, {
      status: "resolved",
      targetOwnerId: "reviewer-2",
      diagnosticCode: "resolved_from_review_parent",
    });
  });
});

test("report queue emulator: concurrent deliveries create one deterministic case", {
  skip: !enabled,
}, async () => {
  await fixture(async (firestore) => {
    const reportId = `concurrent-${randomUUID()}`;
    const results = await Promise.all([
      createReportModerationQueueItemOnce({
        firestore,
        reportId,
        queueItem: queueItem(reportId),
      }),
      createReportModerationQueueItemOnce({
        firestore,
        reportId,
        queueItem: queueItem(reportId),
      }),
    ]);

    assert.equal(results.filter(Boolean).length, 1);
    const matches = await firestore.collection("moderationQueue")
      .where("reportId", "==", reportId)
      .get();
    assert.equal(matches.size, 1);
    assert.equal(matches.docs[0].id, moderationQueueIdForReport(reportId));
  });
});

test("report queue emulator: retry cannot overwrite a resolved administrator case", {
  skip: !enabled,
}, async () => {
  await fixture(async (firestore) => {
    const reportId = `resolved-${randomUUID()}`;
    const created = await createReportModerationQueueItemOnce({
      firestore,
      reportId,
      queueItem: queueItem(reportId),
    });
    assert.equal(created, true);

    const queueRef = firestore.collection("moderationQueue")
      .doc(moderationQueueIdForReport(reportId));
    await queueRef.update({
      status: "resolved",
      assignedAdminId: "admin-1",
      resolution: "keep",
      updatedAt: "administrator-updated-at",
    });

    const retried = await createReportModerationQueueItemOnce({
      firestore,
      reportId,
      queueItem: queueItem(reportId, {status: "pending", resolution: "overwrite"}),
    });
    assert.equal(retried, false);
    assert.deepEqual((await queueRef.get()).data(), {
      ...queueItem(reportId),
      status: "resolved",
      assignedAdminId: "admin-1",
      resolution: "keep",
      updatedAt: "administrator-updated-at",
    });
  });
});

test("report queue emulator: a legacy random-ID case prevents migration duplicates", {
  skip: !enabled,
}, async () => {
  await fixture(async (firestore) => {
    const reportId = `legacy-${randomUUID()}`;
    await firestore.collection("moderationQueue").doc("legacy-random-id").set(
      queueItem(reportId, {status: "resolved", assignedAdminId: "admin-2"}),
    );

    const created = await createReportModerationQueueItemOnce({
      firestore,
      reportId,
      queueItem: queueItem(reportId),
    });
    assert.equal(created, false);
    assert.equal(
      (await firestore.collection("moderationQueue")
        .doc(moderationQueueIdForReport(reportId)).get()).exists,
      false,
    );
  });
});
