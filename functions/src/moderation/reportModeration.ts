import {FieldValue} from "firebase-admin/firestore";
import type {
  DocumentData,
  DocumentReference,
  DocumentSnapshot,
  Firestore,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {
  moderationQueueIdForReport,
  type SupportedReportTargetType,
} from "./reportContract";

export const reportModerationActions = [
  "resolve_report",
  "reject_report",
  "hide_reported_service",
  "hide_reported_review",
] as const;

export type ReportModerationAction = typeof reportModerationActions[number];

type ReportStatus = "pending" | "open" | "resolved" | "rejected";

type ModerationReport = {
  targetType: SupportedReportTargetType;
  targetId: string;
  reporterId: string;
  contextId: string;
  targetPath: string;
  claimedTargetOwnerId: string;
  status: ReportStatus;
  reason: string;
  completedAction: string;
  decisionVersion: number | null;
};

type AdminActor = {
  uid: string;
  role: "superAdmin" | "customerSupportAdmin";
};

export type ReportModerationResult = {
  success: true;
  status: "resolved" | "rejected";
  action: ReportModerationAction;
  duplicate: boolean;
};

type StringAliasResult = {present: boolean; value: string};

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function validDocumentId(value: string): boolean {
  return value.length > 0 &&
    value !== "." &&
    value !== ".." &&
    !value.includes("/") &&
    Buffer.byteLength(value, "utf8") <= 1500;
}

function readStringAlias(
  data: Record<string, unknown>,
  fields: readonly string[],
  label: string,
  normalize: (value: string) => string = (value) => value,
): StringAliasResult {
  const values = new Set<string>();
  let present = false;
  for (const field of fields) {
    if (!Object.prototype.hasOwnProperty.call(data, field)) continue;
    present = true;
    if (typeof data[field] !== "string") {
      throw new HttpsError("failed-precondition", `Report ${label} is invalid.`);
    }
    values.add(normalize((data[field] as string).trim()));
  }
  if (values.size > 1) {
    throw new HttpsError(
      "failed-precondition",
      `Report contains conflicting ${label} aliases.`,
    );
  }
  return {present, value: values.values().next().value ?? ""};
}

export function parseReportId(input: unknown): string {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new HttpsError("invalid-argument", "reportId is required.");
  }
  const data = input as Record<string, unknown>;
  if (Object.keys(data).some((field) => field !== "reportId")) {
    throw new HttpsError(
      "invalid-argument",
      "Report moderation request contains unsupported fields.",
    );
  }
  const reportId = asTrimmedString(data.reportId);
  if (!validDocumentId(reportId)) {
    throw new HttpsError("invalid-argument", "reportId is invalid.");
  }
  return reportId;
}

function parseStoredReport(data: DocumentData): ModerationReport {
  const type = readStringAlias(
    data,
    ["type", "targetType"],
    "type",
    (value) => value.toLowerCase(),
  );
  if (!type.present ||
      (type.value !== "service" &&
       type.value !== "review" &&
       type.value !== "user")) {
    throw new HttpsError("failed-precondition", "Report target type is unsupported.");
  }

  const reporter = readStringAlias(data, ["reportedBy", "reporterId"], "reporter");
  if (!reporter.present || !validDocumentId(reporter.value)) {
    throw new HttpsError("failed-precondition", "Report reporter is invalid.");
  }

  const targetId = asTrimmedString(data.targetId);
  if (!validDocumentId(targetId)) {
    throw new HttpsError("failed-precondition", "Report target ID is invalid.");
  }

  const context = readStringAlias(
    data,
    ["serviceId", "targetServiceId", "contextId"],
    "service context",
  );
  if (context.value && !validDocumentId(context.value)) {
    throw new HttpsError("failed-precondition", "Report service context is invalid.");
  }

  const status = asTrimmedString(data.status).toLowerCase();
  if (!["pending", "open", "resolved", "rejected"].includes(status)) {
    throw new HttpsError("failed-precondition", "Report status is invalid.");
  }

  const schemaVersion = data.schemaVersion;
  if (schemaVersion !== undefined && schemaVersion !== null &&
      schemaVersion !== 1 && schemaVersion !== 2) {
    throw new HttpsError(
      "failed-precondition",
      "Report schema version is unsupported.",
    );
  }

  const canonicalShape = schemaVersion === 2 ||
    Object.prototype.hasOwnProperty.call(data, "targetType") ||
    Object.prototype.hasOwnProperty.call(data, "reporterId") ||
    Object.prototype.hasOwnProperty.call(data, "targetPath");
  if ((type.value === "service" || type.value === "user") && context.value) {
    throw new HttpsError(
      "failed-precondition",
      "Non-review report contains an invalid review context.",
    );
  }
  if (type.value === "review" && canonicalShape && !context.value) {
    throw new HttpsError(
      "failed-precondition",
      "Canonical review report is missing its service context.",
    );
  }

  const expectedPath = type.value === "service" ?
    `services/${targetId}` : type.value === "user" ?
      `users/${targetId}` :
      context.value ? `services/${context.value}/reviews/${targetId}` : "";
  const targetPath = readStringAlias(data, ["targetPath"], "target path");
  if (targetPath.present && (!expectedPath || targetPath.value !== expectedPath)) {
    throw new HttpsError(
      "failed-precondition",
      "Report target path does not match its authoritative target.",
    );
  }

  const targetOwner = readStringAlias(
    data,
    ["targetOwnerId"],
    "target owner",
  );
  if (targetOwner.value && !validDocumentId(targetOwner.value)) {
    throw new HttpsError("failed-precondition", "Report target owner is invalid.");
  }
  const targetSubject = readStringAlias(
    data,
    ["targetSubjectId"],
    "target subject",
  );
  if (targetSubject.value && !validDocumentId(targetSubject.value)) {
    throw new HttpsError("failed-precondition", "Report target subject is invalid.");
  }
  if (type.value === "user" &&
      targetSubject.present &&
      targetSubject.value !== targetId) {
    throw new HttpsError(
      "failed-precondition",
      "Report target subject does not match its authoritative target.",
    );
  }
  if (type.value !== "user" && targetSubject.present) {
    throw new HttpsError(
      "failed-precondition",
      "Content report contains account subject metadata.",
    );
  }

  const decisionVersion = data.moderationDecisionVersion;
  if (decisionVersion !== undefined && decisionVersion !== 1) {
    throw new HttpsError(
      "failed-precondition",
      "Report moderation decision metadata is invalid.",
    );
  }

  return {
    targetType: type.value,
    targetId,
    reporterId: reporter.value,
    contextId: context.value,
    targetPath: expectedPath,
    claimedTargetOwnerId: targetOwner.value,
    status: status as ReportStatus,
    reason: asTrimmedString(data.reason) || "User report",
    completedAction: asTrimmedString(data.moderationAction),
    decisionVersion: decisionVersion === 1 ? 1 : null,
  };
}

function requireModerationAdmin(
  uid: string,
  snapshot: DocumentSnapshot<DocumentData>,
): AdminActor {
  const data = snapshot.data() ?? {};
  const role = asTrimmedString(data.adminRole);
  const accountStatus = asTrimmedString(data.accountStatus);
  const disabled = data.disabled === true ||
    data.isDisabled === true ||
    data.adminDisabled === true ||
    data.isActive === false ||
    (accountStatus.length > 0 && accountStatus !== "active");
  if (!snapshot.exists || disabled ||
      (role !== "superAdmin" && role !== "customerSupportAdmin")) {
    throw new HttpsError(
      "permission-denied",
      "Only active support admins and super admins can moderate reports.",
    );
  }
  return {uid, role};
}

function expectedStatus(action: ReportModerationAction): "resolved" | "rejected" {
  return action === "reject_report" ? "rejected" : "resolved";
}

function assertActionMatchesTarget(
  report: ModerationReport,
  action: ReportModerationAction,
): void {
  if (action === "hide_reported_service" && report.targetType !== "service") {
    throw new HttpsError(
      "failed-precondition",
      "hideReportedService requires a service report.",
    );
  }
  if (action === "hide_reported_review" && report.targetType !== "review") {
    throw new HttpsError(
      "failed-precondition",
      "hideReportedReview requires a review report.",
    );
  }
  if (action === "hide_reported_review" && !report.contextId) {
    throw new HttpsError(
      "failed-precondition",
      "A contextless historical review report cannot hide a review.",
    );
  }
}

function duplicateResult(
  report: ModerationReport,
  action: ReportModerationAction,
): ReportModerationResult | null {
  if (report.status === "pending" || report.status === "open") return null;
  const desiredStatus = expectedStatus(action);
  if (report.status === desiredStatus &&
      report.completedAction === action &&
      report.decisionVersion === 1) {
    return {success: true, status: desiredStatus, action, duplicate: true};
  }
  throw new HttpsError(
    "failed-precondition",
    "This report already has a different or ambiguous moderation decision.",
  );
}

function targetOwnerFromReview(
  service: DocumentData,
  review: DocumentData,
): {serviceOwnerId: string; reviewOwnerId: string} {
  const serviceOwnerId = asTrimmedString(service.ownerUserId);
  if (!validDocumentId(serviceOwnerId)) {
    throw new HttpsError(
      "failed-precondition",
      "Review parent service owner is invalid.",
    );
  }
  const providerId = asTrimmedString(review.providerUserId) ||
    asTrimmedString(review.providerId);
  if (providerId && providerId !== serviceOwnerId) {
    throw new HttpsError(
      "failed-precondition",
      "Review owner metadata conflicts with its parent service.",
    );
  }
  const reviewOwnerId = asTrimmedString(review.reviewerUserId) ||
    asTrimmedString(review.reviewerId);
  if (!validDocumentId(reviewOwnerId)) {
    throw new HttpsError("failed-precondition", "Review author is invalid.");
  }
  return {serviceOwnerId, reviewOwnerId};
}

function assertClaimedOwner(
  report: ModerationReport,
  authoritativeOwnerId: string,
): void {
  if (report.claimedTargetOwnerId &&
      report.claimedTargetOwnerId !== authoritativeOwnerId) {
    throw new HttpsError(
      "failed-precondition",
      "Report target owner metadata conflicts with the authoritative target.",
    );
  }
}

function selectQueueReference(params: {
  firestore: Firestore;
  reportId: string;
  deterministicRef: DocumentReference<DocumentData>;
  snapshots: DocumentSnapshot<DocumentData>[];
}): {ref: DocumentReference<DocumentData>; exists: boolean; data: DocumentData} {
  const relevant = params.snapshots.filter((snapshot) => {
    if (!snapshot.exists) return false;
    const data = snapshot.data() ?? {};
    if (snapshot.ref.path === params.deterministicRef.path &&
        asTrimmedString(data.reportId) !== params.reportId) {
      throw new HttpsError(
        "failed-precondition",
        "The deterministic moderation queue case conflicts with this report.",
      );
    }
    return asTrimmedString(data.reportId) === params.reportId;
  });
  const unique = new Map(relevant.map((snapshot) => [snapshot.ref.path, snapshot]));
  if (unique.size > 1) {
    throw new HttpsError(
      "failed-precondition",
      "This report has ambiguous historical moderation queue cases.",
    );
  }
  const existing = unique.values().next().value as
    DocumentSnapshot<DocumentData> | undefined;
  return existing ? {
    ref: existing.ref,
    exists: true,
    data: existing.data() ?? {},
  } : {
    ref: params.deterministicRef,
    exists: false,
    data: {},
  };
}

function assertQueueIsPending(queue: {exists: boolean; data: DocumentData}): void {
  if (!queue.exists) return;
  const status = asTrimmedString(queue.data.status).toLowerCase();
  if (status !== "pending" && status !== "open") {
    throw new HttpsError(
      "failed-precondition",
      "The moderation queue case already has an incompatible decision.",
    );
  }
}

async function loadTargetInTransaction(params: {
  firestore: Firestore;
  transaction: Transaction;
  report: ModerationReport;
}): Promise<{
  targetRef: DocumentReference<DocumentData> | null;
  targetReference: string;
  authoritativeOwnerId: string;
}> {
  const {firestore, transaction, report} = params;
  if (report.targetType === "service") {
    const serviceRef = firestore.collection("services").doc(report.targetId);
    const snapshot = await transaction.get(serviceRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Reported service was not found.");
    }
    const ownerId = asTrimmedString(snapshot.data()?.ownerUserId);
    if (!validDocumentId(ownerId)) {
      throw new HttpsError("failed-precondition", "Service owner is invalid.");
    }
    assertClaimedOwner(report, ownerId);
    return {
      targetRef: serviceRef,
      targetReference: serviceRef.path,
      authoritativeOwnerId: ownerId,
    };
  }

  if (report.targetType === "user") {
    const userRef = firestore.collection("users").doc(report.targetId);
    const snapshot = await transaction.get(userRef);
    assertClaimedOwner(report, report.targetId);
    return {
      targetRef: snapshot.exists ? userRef : null,
      targetReference: userRef.path,
      authoritativeOwnerId: report.targetId,
    };
  }

  if (!report.contextId) {
    return {targetRef: null, targetReference: "", authoritativeOwnerId: ""};
  }
  const serviceRef = firestore.collection("services").doc(report.contextId);
  const reviewRef = serviceRef.collection("reviews").doc(report.targetId);
  const [serviceSnapshot, reviewSnapshot] = await Promise.all([
    transaction.get(serviceRef),
    transaction.get(reviewRef),
  ]);
  if (!serviceSnapshot.exists) {
    throw new HttpsError("not-found", "Review parent service was not found.");
  }
  if (!reviewSnapshot.exists) {
    throw new HttpsError("not-found", "Reported review was not found.");
  }
  const ownership = targetOwnerFromReview(
    serviceSnapshot.data() ?? {},
    reviewSnapshot.data() ?? {},
  );
  assertClaimedOwner(report, ownership.reviewOwnerId);
  return {
    targetRef: reviewRef,
    targetReference: reviewRef.path,
    authoritativeOwnerId: ownership.reviewOwnerId,
  };
}

function writeTargetMutation(params: {
  transaction: Transaction;
  targetRef: DocumentReference<DocumentData> | null;
  action: ReportModerationAction;
  report: ModerationReport;
  adminUid: string;
}): void {
  const {transaction, targetRef, action, report, adminUid} = params;
  if (action === "hide_reported_service") {
    if (!targetRef) throw new HttpsError("internal", "Service target is unavailable.");
    transaction.set(targetRef, {
      moderationStatus: "removed",
      moderationReason: report.reason,
      isVisibleToMarketplace: false,
      isActive: false,
      status: "removed",
      updatedAt: FieldValue.serverTimestamp(),
      removedAt: FieldValue.serverTimestamp(),
      removedBy: adminUid,
    }, {merge: true});
  } else if (action === "hide_reported_review") {
    if (!targetRef) throw new HttpsError("internal", "Review target is unavailable.");
    transaction.set(targetRef, {
      moderationStatus: "hidden",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
}

export async function moderateReportData(params: {
  firestore: Firestore;
  authUid: string;
  input: unknown;
  action: ReportModerationAction;
}): Promise<ReportModerationResult> {
  const authUid = params.authUid.trim();
  if (!authUid) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  const reportId = parseReportId(params.input);
  const reportRef = params.firestore.collection("reports").doc(reportId);
  const deterministicQueueRef = params.firestore.collection("moderationQueue")
    .doc(moderationQueueIdForReport(reportId));

  // This is a bounded compatibility lookup for old randomly-ID'd queue cases.
  // All state validation and every mutation still occur in the transaction.
  const historicalQueue = await params.firestore.collection("moderationQueue")
    .where("reportId", "==", reportId)
    .limit(3)
    .get();
  const queueRefs = new Map<string, DocumentReference<DocumentData>>();
  queueRefs.set(deterministicQueueRef.path, deterministicQueueRef);
  for (const document of historicalQueue.docs) {
    queueRefs.set(document.ref.path, document.ref);
  }
  const auditRef = params.firestore.collection("adminAuditLogs").doc();
  const desiredStatus = expectedStatus(params.action);

  return params.firestore.runTransaction(async (transaction) => {
    const adminRef = params.firestore.collection("users").doc(authUid);
    const [adminSnapshot, reportSnapshot, ...queueSnapshots] = await Promise.all([
      transaction.get(adminRef),
      transaction.get(reportRef),
      ...Array.from(queueRefs.values()).map((reference) => transaction.get(reference)),
    ]);
    const admin = requireModerationAdmin(authUid, adminSnapshot);
    if (!reportSnapshot.exists) {
      throw new HttpsError("not-found", "Report was not found.");
    }
    const report = parseStoredReport(reportSnapshot.data() ?? {});
    assertActionMatchesTarget(report, params.action);
    const duplicate = duplicateResult(report, params.action);
    if (duplicate) return duplicate;

    const queue = selectQueueReference({
      firestore: params.firestore,
      reportId,
      deterministicRef: deterministicQueueRef,
      snapshots: queueSnapshots,
    });
    assertQueueIsPending(queue);

    const target = await loadTargetInTransaction({
      firestore: params.firestore,
      transaction,
      report,
    });
    writeTargetMutation({
      transaction,
      targetRef: target.targetRef,
      action: params.action,
      report,
      adminUid: admin.uid,
    });

    const reportUpdate: DocumentData = {
      status: desiredStatus,
      moderationAction: params.action,
      moderationDecisionVersion: 1,
      moderatedBy: admin.uid,
      moderatedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (desiredStatus === "resolved") {
      reportUpdate.resolvedBy = admin.uid;
      reportUpdate.resolvedAt = FieldValue.serverTimestamp();
    }
    transaction.update(reportRef, reportUpdate);

    const queueUpdate = {
      targetType: report.targetType,
      targetId: report.targetId,
      targetOwnerId: target.authoritativeOwnerId,
      source: "report",
      reportId,
      status: desiredStatus,
      moderationAction: params.action,
      assignedAdminId: admin.uid,
      updatedAt: FieldValue.serverTimestamp(),
      resolvedAt: FieldValue.serverTimestamp(),
    };
    if (queue.exists) {
      transaction.set(queue.ref, queueUpdate, {merge: true});
    } else {
      transaction.create(queue.ref, {
        ...queueUpdate,
        severity: "medium",
        reason: report.reason,
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    transaction.create(auditRef, {
      adminId: admin.uid,
      adminRole: admin.role,
      action: params.action,
      targetType: "report",
      targetId: reportId,
      reportId,
      moderationAction: params.action,
      reportedTargetType: report.targetType,
      targetRef: target.targetReference,
      previousStatus: report.status,
      newStatus: desiredStatus,
      createdAt: FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      status: desiredStatus,
      action: params.action,
      duplicate: false,
    };
  });
}
