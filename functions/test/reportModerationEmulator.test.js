const test = require("node:test");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");

const {
  moderateReportData,
} = require("../lib/moderation/reportModeration.js");
const {
  moderationQueueIdForReport,
} = require("../lib/moderation/reportContract.js");

const enabled = /^(127\.0\.0\.1|localhost):\d+$/.test(
  process.env.FIRESTORE_EMULATOR_HOST ?? "",
);

function assertHttpsCode(code) {
  return (error) => {
    assert.equal(error.code, code);
    return true;
  };
}

async function fixture(run) {
  const suffix = randomUUID();
  const app = initializeApp(
    {projectId: "demo-report-moderation"},
    `report-moderation-${suffix}`,
  );
  const firestore = getFirestore(app);
  const ids = {
    suffix,
    report: `report-${suffix}`,
    service: `service-${suffix}`,
    review: `review-${suffix}`,
    reporter: `reporter-${suffix}`,
    provider: `provider-${suffix}`,
    reviewer: `reviewer-${suffix}`,
    targetUser: `target-user-${suffix}`,
    regular: `regular-${suffix}`,
    finance: `finance-${suffix}`,
    support: `support-${suffix}`,
    superAdmin: `super-${suffix}`,
    disabled: `disabled-${suffix}`,
    malformed: `malformed-${suffix}`,
    booking: `booking-${suffix}`,
    payment: `payment-${suffix}`,
    payout: `payout-${suffix}`,
  };
  try {
    const batch = firestore.batch();
    const users = {
      [ids.regular]: {accountStatus: "active"},
      [ids.finance]: {accountStatus: "active", adminRole: "financeAdmin"},
      [ids.support]: {accountStatus: "active", adminRole: "customerSupportAdmin"},
      [ids.superAdmin]: {accountStatus: "active", adminRole: "superAdmin"},
      [ids.disabled]: {
        accountStatus: "disabled", adminRole: "customerSupportAdmin",
      },
      [ids.malformed]: {accountStatus: "active", adminRole: 42},
      [ids.targetUser]: {accountStatus: "active", displayName: "Target User"},
    };
    for (const [uid, data] of Object.entries(users)) {
      batch.set(firestore.collection("users").doc(uid), data);
    }
    batch.set(firestore.collection("services").doc(ids.service), {
      ownerUserId: ids.provider,
      moderationStatus: "approved",
      isVisibleToMarketplace: true,
      isActive: true,
      status: "active",
      stats: {ratingAverage: 4.5, ratingCount: 8},
    });
    batch.set(firestore.collection("services").doc(ids.service)
      .collection("reviews").doc(ids.review), {
      providerUserId: ids.provider,
      reviewerUserId: ids.reviewer,
      moderationStatus: "approved",
      rating: 5,
    });
    batch.set(firestore.collection("bookings").doc(ids.booking), {
      serviceId: ids.service, status: "CONFIRMED", total: 100,
    });
    batch.set(firestore.collection("payments").doc(ids.payment), {
      bookingId: ids.booking, status: "captured",
    });
    batch.set(firestore.collection("providerPayouts").doc(ids.payout), {
      bookingId: ids.booking, status: "pending",
    });
    await batch.commit();
    await run({firestore, ids});
  } finally {
    await firestore.terminate();
    await deleteApp(app);
  }
}

function legacyServiceReport(ids, overrides = {}) {
  return {
    type: "service",
    targetId: ids.service,
    reportedBy: ids.reporter,
    status: "pending",
    reason: "Safety concern",
    createdAt: Timestamp.now(),
    ...overrides,
  };
}

function canonicalServiceReport(ids, overrides = {}) {
  return {
    schemaVersion: 2,
    type: "service",
    targetType: "service",
    targetId: ids.service,
    reportedBy: ids.reporter,
    reporterId: ids.reporter,
    targetOwnerId: ids.provider,
    contextId: "",
    targetPath: `services/${ids.service}`,
    status: "pending",
    reason: "safety_concern",
    ...overrides,
  };
}

function canonicalReviewReport(ids, overrides = {}) {
  return {
    schemaVersion: 2,
    type: "review",
    targetType: "review",
    targetId: ids.review,
    reportedBy: ids.reporter,
    reporterId: ids.reporter,
    targetOwnerId: ids.reviewer,
    contextId: ids.service,
    targetPath: `services/${ids.service}/reviews/${ids.review}`,
    status: "pending",
    reason: "spam",
    ...overrides,
  };
}

function canonicalUserReport(ids, overrides = {}) {
  return {
    schemaVersion: 2,
    type: "user",
    targetType: "user",
    targetId: ids.targetUser,
    reportedBy: ids.reporter,
    reporterId: ids.reporter,
    targetSubjectId: ids.targetUser,
    contextId: "",
    targetPath: `users/${ids.targetUser}`,
    status: "pending",
    reason: "safety_concern",
    ...overrides,
  };
}

async function setReport(firestore, ids, data) {
  await firestore.collection("reports").doc(ids.report).set(data);
}

async function decide(firestore, ids, action, authUid = ids.support) {
  return moderateReportData({
    firestore,
    authUid,
    input: {reportId: ids.report},
    action,
  });
}

test("authorization denies unauthenticated, user, finance, disabled, and malformed admins", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await setReport(firestore, ids, legacyServiceReport(ids));
    await assert.rejects(decide(firestore, ids, "resolve_report", ""),
      assertHttpsCode("unauthenticated"));
    for (const uid of [ids.regular, ids.finance, ids.disabled, ids.malformed]) {
      await assert.rejects(decide(firestore, ids, "resolve_report", uid),
        assertHttpsCode("permission-denied"));
    }
    assert.equal((await firestore.collection("reports").doc(ids.report).get())
      .data().status, "pending");
  });
});

test("support and super admins resolve legacy and historical-open reports", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await setReport(firestore, ids, legacyServiceReport(ids));
    const supportResult = await decide(firestore, ids, "resolve_report");
    assert.deepEqual(supportResult, {
      success: true, status: "resolved", action: "resolve_report", duplicate: false,
    });

    ids.report = `open-${ids.suffix}`;
    await setReport(firestore, ids, canonicalServiceReport(ids, {status: "open"}));
    const superResult = await decide(
      firestore, ids, "reject_report", ids.superAdmin,
    );
    assert.equal(superResult.status, "rejected");
  });
});

test("hide service reuses removal fields without changing protected financial history", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await setReport(firestore, ids, canonicalServiceReport(ids));
    const before = await Promise.all([
      firestore.collection("bookings").doc(ids.booking).get(),
      firestore.collection("payments").doc(ids.payment).get(),
      firestore.collection("providerPayouts").doc(ids.payout).get(),
    ]);
    const result = await decide(firestore, ids, "hide_reported_service");
    assert.equal(result.duplicate, false);
    const service = (await firestore.collection("services").doc(ids.service).get()).data();
    assert.equal(service.moderationStatus, "removed");
    assert.equal(service.isVisibleToMarketplace, false);
    assert.equal(service.isActive, false);
    assert.equal(service.status, "removed");
    const after = await Promise.all([
      firestore.collection("bookings").doc(ids.booking).get(),
      firestore.collection("payments").doc(ids.payment).get(),
      firestore.collection("providerPayouts").doc(ids.payout).get(),
    ]);
    assert.deepEqual(after.map((entry) => entry.data()), before.map((entry) => entry.data()));
  });
});

test("hide review uses its exact canonical nested path and preserves aggregates", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await setReport(firestore, ids, canonicalReviewReport(ids));
    const beforeService = (await firestore.collection("services").doc(ids.service).get()).data();
    await decide(firestore, ids, "hide_reported_review");
    const review = (await firestore.collection("services").doc(ids.service)
      .collection("reviews").doc(ids.review).get()).data();
    const afterService = (await firestore.collection("services").doc(ids.service).get()).data();
    assert.equal(review.moderationStatus, "hidden");
    assert.equal(review.rating, 5);
    assert.deepEqual(afterService.stats, beforeService.stats);
  });
});

test("user reports resolve and reject without mutating the account", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await setReport(firestore, ids, canonicalUserReport(ids));
    const before = (await firestore.collection("users").doc(ids.targetUser).get()).data();
    const result = await decide(firestore, ids, "resolve_report");
    assert.equal(result.status, "resolved");
    assert.deepEqual(
      (await firestore.collection("users").doc(ids.targetUser).get()).data(),
      before,
    );
    const audit = (await firestore.collection("adminAuditLogs")
      .where("reportId", "==", ids.report).get()).docs[0].data();
    assert.equal(audit.reportedTargetType, "user");
    assert.equal(audit.targetRef, `users/${ids.targetUser}`);

    ids.report = `rejected-user-${ids.suffix}`;
    await setReport(firestore, ids, canonicalUserReport(ids));
    const rejected = await decide(firestore, ids, "reject_report", ids.superAdmin);
    assert.equal(rejected.status, "rejected");
    assert.deepEqual(
      (await firestore.collection("users").doc(ids.targetUser).get()).data(),
      before,
    );
  });
});

test("user reports can never invoke service or review hide actions", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await setReport(firestore, ids, canonicalUserReport(ids));
    for (const action of ["hide_reported_service", "hide_reported_review"]) {
      await assert.rejects(decide(firestore, ids, action),
        assertHttpsCode("failed-precondition"));
    }
    assert.equal((await firestore.collection("reports").doc(ids.report).get())
      .data().status, "pending");
  });
});

test("contextless historical review can resolve but can never hide", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await setReport(firestore, ids, {
      type: "review", targetId: ids.review, reportedBy: ids.reporter,
      status: "pending", reason: "Spam",
    });
    await assert.rejects(
      decide(firestore, ids, "hide_reported_review"),
      assertHttpsCode("failed-precondition"),
    );
    assert.equal((await firestore.collection("reports").doc(ids.report).get())
      .data().status, "pending");
    const resolved = await decide(firestore, ids, "resolve_report");
    assert.equal(resolved.status, "resolved");
  });
});

test("conflicting aliases, forged paths, owners, and unsupported schemas fail closed", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    const invalidReports = [
      canonicalServiceReport(ids, {targetType: "review"}),
      canonicalServiceReport(ids, {targetPath: "services/forged"}),
      canonicalServiceReport(ids, {targetOwnerId: "forged-owner"}),
      canonicalServiceReport(ids, {schemaVersion: 99}),
      canonicalUserReport(ids, {targetSubjectId: "forged-subject"}),
    ];
    for (let index = 0; index < invalidReports.length; index += 1) {
      ids.report = `invalid-${index}-${ids.suffix}`;
      await setReport(firestore, ids, invalidReports[index]);
      await assert.rejects(
        decide(firestore, ids, "resolve_report"),
        assertHttpsCode("failed-precondition"),
      );
    }
  });
});

test("missing report and targets fail with no queue or audit side effects", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await assert.rejects(decide(firestore, ids, "resolve_report"),
      assertHttpsCode("not-found"));
    await setReport(firestore, ids, canonicalServiceReport(ids, {
      targetId: `missing-${ids.suffix}`,
      targetOwnerId: "",
      targetPath: `services/missing-${ids.suffix}`,
    }));
    await assert.rejects(decide(firestore, ids, "resolve_report"),
      assertHttpsCode("not-found"));
    assert.equal((await firestore.collection("moderationQueue")
      .where("reportId", "==", ids.report).get()).empty, true);
    assert.equal((await firestore.collection("adminAuditLogs")
      .where("reportId", "==", ids.report).get()).empty, true);
  });
});

test("missing reviews and conflicting review ownership roll back atomically", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await setReport(firestore, ids, canonicalReviewReport(ids, {
      targetId: `missing-review-${ids.suffix}`,
      targetOwnerId: "",
      targetPath: `services/${ids.service}/reviews/missing-review-${ids.suffix}`,
    }));
    await assert.rejects(decide(firestore, ids, "resolve_report"),
      assertHttpsCode("not-found"));
    assert.equal((await firestore.collection("reports").doc(ids.report).get())
      .data().status, "pending");

    ids.report = `owner-conflict-${ids.suffix}`;
    await firestore.collection("services").doc(ids.service)
      .collection("reviews").doc(ids.review).update({
        providerUserId: `wrong-provider-${ids.suffix}`,
      });
    await setReport(firestore, ids, canonicalReviewReport(ids));
    await assert.rejects(decide(firestore, ids, "hide_reported_review"),
      assertHttpsCode("failed-precondition"));
    assert.equal((await firestore.collection("services").doc(ids.service)
      .collection("reviews").doc(ids.review).get()).data().moderationStatus,
    "approved");
    assert.equal((await firestore.collection("adminAuditLogs")
      .where("reportId", "==", ids.report).get()).empty, true);
  });
});

test("same decision is idempotent and conflicting decisions fail", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await setReport(firestore, ids, canonicalServiceReport(ids));
    const first = await decide(firestore, ids, "resolve_report");
    const duplicate = await decide(firestore, ids, "resolve_report");
    assert.equal(first.duplicate, false);
    assert.equal(duplicate.duplicate, true);
    await assert.rejects(decide(firestore, ids, "reject_report"),
      assertHttpsCode("failed-precondition"));
    const audits = await firestore.collection("adminAuditLogs")
      .where("reportId", "==", ids.report).get();
    assert.equal(audits.size, 1);
  });
});

test("concurrent decisions cannot create contradictory state or duplicate audits", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await setReport(firestore, ids, canonicalReviewReport(ids));
    const results = await Promise.allSettled([
      decide(firestore, ids, "hide_reported_review"),
      decide(firestore, ids, "reject_report", ids.superAdmin),
    ]);
    assert.equal(results.filter((entry) => entry.status === "fulfilled").length, 1);
    assert.equal(results.filter((entry) => entry.status === "rejected").length, 1);
    const report = (await firestore.collection("reports").doc(ids.report).get()).data();
    assert.ok(report.status === "resolved" || report.status === "rejected");
    assert.equal((await firestore.collection("adminAuditLogs")
      .where("reportId", "==", ids.report).get()).size, 1);
  });
});

test("queue synchronization supports deterministic and one legacy queue case", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await setReport(firestore, ids, legacyServiceReport(ids));
    const legacyQueueRef = firestore.collection("moderationQueue")
      .doc(`legacy-queue-${ids.suffix}`);
    await legacyQueueRef.set({
      reportId: ids.report, status: "pending", targetType: "service",
      targetId: ids.service,
    });
    await decide(firestore, ids, "reject_report");
    assert.equal((await legacyQueueRef.get()).data().status, "rejected");
    assert.equal((await firestore.collection("moderationQueue")
      .doc(moderationQueueIdForReport(ids.report)).get()).exists, false);
  });
});

test("ambiguous terminal reports and duplicate historical queues fail closed", {
  skip: !enabled,
}, async () => {
  await fixture(async ({firestore, ids}) => {
    await setReport(firestore, ids, legacyServiceReport(ids, {status: "resolved"}));
    await assert.rejects(decide(firestore, ids, "resolve_report"),
      assertHttpsCode("failed-precondition"));

    ids.report = `duplicate-queues-${ids.suffix}`;
    await setReport(firestore, ids, legacyServiceReport(ids));
    await Promise.all(["a", "b"].map((entry) => firestore
      .collection("moderationQueue").doc(`${entry}-${ids.suffix}`)
      .set({reportId: ids.report, status: "pending"})));
    await assert.rejects(decide(firestore, ids, "reject_report"),
      assertHttpsCode("failed-precondition"));
  });
});
