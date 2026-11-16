const firebaseEmulator = require("./helpers/firebaseTestSafety").emulatorGate({services: ["firestore"], projectId: "demo-report-submission"});
const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");

const {
  enqueueReportModerationData,
  moderationQueueIdForReport,
} = require("../lib/moderation/reportContract.js");
const {
  submitReportData,
} = require("../lib/moderation/reportSubmission.js");

const enabled = firebaseEmulator.enabled;

function assertHttpsCode(code) {
  return (error) => {
    assert.equal(error.code, code);
    return true;
  };
}

async function fixture(run) {
  const app = initializeApp(
    {projectId: "demo-report-submission"},
    `report-submission-${randomUUID()}`,
  );
  const firestore = getFirestore(app);
  const projectId = app.options.projectId;
  const suffix = randomUUID();
  const ids = {
    reporter: `reporter-${suffix}`,
    provider: `provider-${suffix}`,
    reviewer: `reviewer-${suffix}`,
    targetUser: `target-user-${suffix}`,
    service: `service-${suffix}`,
    review: `review-${suffix}`,
  };
  try {
    await firestore.collection("users").doc(ids.reporter).set({
      uid: ids.reporter,
      accountStatus: "active",
      name: "Reporting User",
      username: "reporting_user",
    });
    await firestore.collection("services").doc(ids.service).set({
      ownerUserId: ids.provider,
    });
    await firestore.collection("services").doc(ids.service)
      .collection("reviews").doc(ids.review).set({
        providerUserId: ids.provider,
        reviewerUserId: ids.reviewer,
      });
    await firestore.collection("users").doc(ids.targetUser).set({
      accountStatus: "active",
      displayName: "Target User",
      username: "target_user",
    });
    await run({firestore, ids, projectId});
  } finally {
    await firestore.terminate();
    await deleteApp(app);
  }
}

function userInput(ids, overrides = {}) {
  return {
    type: "user",
    targetId: ids.targetUser,
    reason: "safety_concern",
    description: "Threatening messages",
    ...overrides,
  };
}

function serviceInput(ids, overrides = {}) {
  return {
    type: "service",
    targetId: ids.service,
    reason: "inappropriate_content",
    description: "Please review this listing.",
    ...overrides,
  };
}

function reviewInput(ids, overrides = {}) {
  return {
    type: "review",
    targetId: ids.review,
    contextId: ids.service,
    reason: "spam",
    ...overrides,
  };
}

test("submitReport emulator: service report stores dashboard and canonical fields", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    const result = await submitReportData({
      firestore,
      authUid: ids.reporter,
      input: serviceInput(ids),
    });
    assert.deepEqual(result, {
      reportId: result.reportId,
      status: "pending",
      duplicate: false,
    });

    const report = (await firestore.collection("reports").doc(result.reportId).get()).data();
    assert.equal(report.schemaVersion, 2);
    assert.equal(report.type, "service");
    assert.equal(report.targetType, "service");
    assert.equal(report.reportedBy, ids.reporter);
    assert.equal(report.reporterId, ids.reporter);
    assert.equal(report.reporterName, "Reporting User");
    assert.equal(report.targetOwnerId, ids.provider);
    assert.equal(report.targetId, ids.service);
    assert.equal(report.contextId, "");
    assert.equal(report.targetPath, `services/${ids.service}`);
    assert.equal(report.status, "pending");
    assert.equal(report.reason, "inappropriate_content");
    assert.equal(report.description, "Please review this listing.");
    assert.ok(report.createdAt instanceof Timestamp);
    assert.ok(report.updatedAt instanceof Timestamp);
    assert.equal((await firestore.collection("moderationQueue").get()).empty, true);
  });
});

test("submitReport emulator: review report resolves nested target and review author", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    const result = await submitReportData({
      firestore,
      authUid: ids.reporter,
      input: reviewInput(ids),
    });
    const report = (await firestore.collection("reports").doc(result.reportId).get()).data();
    assert.equal(report.type, "review");
    assert.equal(report.contextId, ids.service);
    assert.equal(report.targetOwnerId, ids.reviewer);
    assert.equal(
      report.targetPath,
      `services/${ids.service}/reviews/${ids.review}`,
    );
  });
});

test("submitReport emulator: user report verifies target and stores canonical identity", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    const now = new Date("2026-06-15T00:00:00.000Z");
    const first = await submitReportData({
      firestore,
      authUid: ids.reporter,
      input: userInput(ids),
      authoritativeNow: now,
    });
    const duplicate = await submitReportData({
      firestore,
      authUid: ids.reporter,
      input: userInput(ids, {description: "Different wording"}),
      authoritativeNow: now,
    });
    const report = (await firestore.collection("reports").doc(first.reportId).get()).data();
    assert.equal(duplicate.reportId, first.reportId);
    assert.equal(duplicate.duplicate, true);
    assert.equal(report.type, "user");
    assert.equal(report.targetSubjectId, ids.targetUser);
    assert.equal(report.targetOwnerId, undefined);
    assert.equal(report.targetPath, `users/${ids.targetUser}`);
    assert.equal(report.contextId, "");
    assert.equal(report.deduplicationPolicy, "reporter_target_30_day_bucket_v1");
    assert.ok(report.incidentBucket);

    const queueFirst = await enqueueReportModerationData({
      firestore,
      reportId: first.reportId,
      reportData: report,
    });
    const queueRetry = await enqueueReportModerationData({
      firestore,
      reportId: first.reportId,
      reportData: report,
    });
    const queue = (await firestore.collection("moderationQueue")
      .doc(moderationQueueIdForReport(first.reportId)).get()).data();
    assert.equal(queueFirst.outcome, "created");
    assert.equal(queueRetry.outcome, "duplicate");
    assert.equal(queue.targetType, "user");
    assert.equal(queue.targetOwnerId, ids.targetUser);
    assert.equal(queue.targetSubjectId, ids.targetUser);
    assert.equal(queue.targetDisplayName, "Target User");
    assert.equal(queue.targetUsername, "target_user");
    assert.equal(JSON.stringify(queue).includes("email"), false);
  });
});

test("submitReport emulator: user duplicates are concurrent-safe and later incidents remain possible", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    const firstTime = new Date("2026-06-15T00:00:00.000Z");
    const concurrent = await Promise.all([
      submitReportData({
        firestore, authUid: ids.reporter, input: userInput(ids),
        authoritativeNow: firstTime,
      }),
      submitReportData({
        firestore, authUid: ids.reporter,
        input: userInput(ids, {description: "Insignificant wording change"}),
        authoritativeNow: firstTime,
      }),
    ]);
    assert.equal(concurrent[0].reportId, concurrent[1].reportId);
    assert.deepEqual(concurrent.map((entry) => entry.duplicate).sort(), [false, true]);

    const later = await submitReportData({
      firestore,
      authUid: ids.reporter,
      input: userInput(ids, {description: "A later distinct incident"}),
      authoritativeNow: new Date(firstTime.getTime() + 31 * 24 * 60 * 60 * 1000),
    });
    assert.notEqual(later.reportId, concurrent[0].reportId);
    assert.equal(later.duplicate, false);
    assert.equal((await firestore.collection("reports")
      .where("reportedBy", "==", ids.reporter).get()).size, 2);
  });
});

test("submitReport emulator: blocks, disputes, and protected bookings do not gate user reports", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await firestore.collection("userRelationshipGuards").doc("guard").set({
      userIds: [ids.reporter, ids.targetUser],
      relationshipBlocked: true,
      blockedByUid: ids.targetUser,
    });
    await firestore.collection("bookings").doc("protected-booking").set({
      customerId: ids.reporter,
      providerId: ids.targetUser,
      paymentStatus: "PAID",
      status: "IN_PROGRESS",
      disputeStatus: "OPEN",
    });
    const result = await submitReportData({
      firestore, authUid: ids.reporter, input: userInput(ids),
    });
    assert.equal(result.status, "pending");
    assert.equal(result.duplicate, false);
  });
});

test("submitReport emulator: self, missing, and deleted user targets fail closed", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await assert.rejects(submitReportData({
      firestore, authUid: ids.reporter, input: userInput(ids, {targetId: ids.reporter}),
    }), assertHttpsCode("failed-precondition"));
    await assert.rejects(submitReportData({
      firestore, authUid: ids.reporter, input: userInput(ids, {targetId: `missing-${randomUUID()}`}),
    }), assertHttpsCode("not-found"));
    await firestore.collection("users").doc(ids.targetUser).update({isDeleted: true});
    await assert.rejects(submitReportData({
      firestore, authUid: ids.reporter, input: userInput(ids),
    }), assertHttpsCode("failed-precondition"));
  });
});

test("submitReport emulator: nonexistent targets are rejected without a report write", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await assert.rejects(submitReportData({
      firestore,
      authUid: ids.reporter,
      input: serviceInput(ids, {targetId: `missing-${randomUUID()}`}),
    }), assertHttpsCode("not-found"));
    assert.equal((await firestore.collection("reports")
      .where("reportedBy", "==", ids.reporter).get()).empty, true);
  });
});

test("submitReport emulator: unavailable accounts and self reports are rejected", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await firestore.collection("users").doc(ids.reporter).update({
      accountStatus: "pendingDeletion",
    });
    await assert.rejects(submitReportData({
      firestore,
      authUid: ids.reporter,
      input: serviceInput(ids),
    }), assertHttpsCode("failed-precondition"));

    await firestore.collection("users").doc(ids.reporter).update({
      accountStatus: "active",
    });
    await firestore.collection("services").doc(ids.service).update({
      ownerUserId: ids.reporter,
    });
    await assert.rejects(submitReportData({
      firestore,
      authUid: ids.reporter,
      input: serviceInput(ids),
    }), assertHttpsCode("failed-precondition"));

    await firestore.collection("services").doc(ids.service).update({
      ownerUserId: ids.provider,
    });
    await firestore.collection("users").doc(ids.reviewer).set({
      accountStatus: "active",
    });
    await assert.rejects(submitReportData({
      firestore,
      authUid: ids.reviewer,
      input: reviewInput(ids),
    }), assertHttpsCode("failed-precondition"));
    assert.equal((await firestore.collection("reports")
      .where("reportedBy", "==", ids.reporter).get()).empty, true);
  });
});

test("submitReport emulator: sequential and concurrent duplicates create one report", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    const first = await submitReportData({
      firestore,
      authUid: ids.reporter,
      input: serviceInput(ids, {clientRequestId: "first"}),
    });
    const replay = await submitReportData({
      firestore,
      authUid: ids.reporter,
      input: serviceInput(ids, {clientRequestId: "second"}),
    });
    assert.equal(replay.reportId, first.reportId);
    assert.equal(replay.duplicate, true);

    const secondReporter = `second-${randomUUID()}`;
    await firestore.collection("users").doc(secondReporter).set({accountStatus: "active"});
    const concurrent = await Promise.all([
      submitReportData({
        firestore,
        authUid: secondReporter,
        input: serviceInput(ids, {clientRequestId: "concurrent-a"}),
      }),
      submitReportData({
        firestore,
        authUid: secondReporter,
        input: serviceInput(ids, {clientRequestId: "concurrent-b"}),
      }),
    ]);
    assert.equal(concurrent[0].reportId, concurrent[1].reportId);
    assert.deepEqual(concurrent.map((entry) => entry.duplicate).sort(), [false, true]);
    assert.equal((await firestore.collection("reports")
      .where("reportedBy", "==", ids.reporter).get()).size, 1);
    assert.equal((await firestore.collection("reports")
      .where("reportedBy", "==", secondReporter).get()).size, 1);
  });
});

test("submitReport emulator: callable report coordinates with one idempotent queue case", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    const submitted = await submitReportData({
      firestore,
      authUid: ids.reporter,
      input: reviewInput(ids),
    });
    const reportRef = firestore.collection("reports").doc(submitted.reportId);
    const before = (await reportRef.get()).data();
    const first = await enqueueReportModerationData({
      firestore,
      reportId: submitted.reportId,
      reportData: before,
    });
    const retry = await enqueueReportModerationData({
      firestore,
      reportId: submitted.reportId,
      reportData: before,
    });
    assert.equal(first.outcome, "created");
    assert.equal(retry.outcome, "duplicate");

    const queueRef = firestore.collection("moderationQueue")
      .doc(moderationQueueIdForReport(submitted.reportId));
    const queue = (await queueRef.get()).data();
    assert.equal(queue.reportId, submitted.reportId);
    assert.equal(queue.targetType, "review");
    assert.equal(queue.targetOwnerId, ids.reviewer);
    assert.equal(queue.status, "pending");
    assert.deepEqual((await reportRef.get()).data(), before);
    assert.equal((await firestore.collection("moderationQueue")
      .where("reportId", "==", submitted.reportId).get()).size, 1);
  });
});

test("submitReport emulator: existing legacy direct report still projects to the queue", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    const reportId = `legacy-${randomUUID()}`;
    const legacy = {
      type: "service",
      targetId: ids.service,
      reportedBy: ids.reporter,
      reporterName: "Reporting User",
      status: "pending",
      reason: "Spam",
      description: "Legacy Android report",
      createdAt: Timestamp.now(),
    };
    await firestore.collection("reports").doc(reportId).set(legacy);
    const result = await enqueueReportModerationData({
      firestore,
      reportId,
      reportData: legacy,
    });
    assert.equal(result.outcome, "created");
    assert.equal(
      (await firestore.collection("moderationQueue")
        .doc(moderationQueueIdForReport(reportId)).get()).data().targetOwnerId,
      ids.provider,
    );
    assert.deepEqual((await firestore.collection("reports").doc(reportId).get()).data(), legacy);
  });
});

test("submitReport emulator: injected demo Firestore is the only write destination", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids, projectId}) => {
    assert.equal(projectId, "demo-report-submission");
    const result = await submitReportData({
      firestore,
      authUid: ids.reporter,
      input: serviceInput(ids),
    });
    assert.equal((await firestore.collection("reports")
      .where("reportedBy", "==", ids.reporter).get()).size, 1);
    assert.equal((await firestore.collection("moderationQueue")
      .where("reportId", "==", result.reportId).get()).size, 0);
  });
});
