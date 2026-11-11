import {FieldValue} from "firebase-admin/firestore";
import type {
  DocumentData,
  DocumentReference,
  DocumentSnapshot,
  Firestore,
  Transaction,
} from "firebase-admin/firestore";

export const supportedReportTargetTypes = ["service", "review"] as const;

export type SupportedReportTargetType = typeof supportedReportTargetTypes[number];

export type NormalizedReportContract = {
  targetType: SupportedReportTargetType;
  targetId: string;
  reporterId: string;
  claimedTargetOwnerId: string;
  status: "pending" | "open";
  reason: string;
  description: string;
  serviceId: string;
};

export type ReportContractErrorCode =
  | "conflicting_reporter_aliases"
  | "conflicting_service_context_aliases"
  | "conflicting_type_aliases"
  | "invalid_description"
  | "invalid_reason"
  | "invalid_reporter"
  | "invalid_service_context"
  | "invalid_status"
  | "invalid_target_id"
  | "invalid_target_owner"
  | "invalid_timestamp"
  | "invalid_type"
  | "missing_reporter"
  | "missing_target_id"
  | "missing_type"
  | "unsupported_type";

export type ReportContractResult =
  | {ok: true; report: NormalizedReportContract}
  | {ok: false; code: ReportContractErrorCode};

type StringFieldResult =
  | {ok: true; present: boolean; value: string}
  | {ok: false};

function readStringField(
  data: Record<string, unknown>,
  field: string,
): StringFieldResult {
  if (!Object.prototype.hasOwnProperty.call(data, field)) {
    return {ok: true, present: false, value: ""};
  }
  const value = data[field];
  if (typeof value !== "string") return {ok: false};
  return {ok: true, present: true, value: value.trim()};
}

function resolveAlias(
  data: Record<string, unknown>,
  legacyField: string,
  normalizedField: string,
  normalize: (value: string) => string = (value) => value,
):
  | {ok: true; present: boolean; value: string}
  | {ok: false; conflict: boolean} {
  const legacy = readStringField(data, legacyField);
  const normalized = readStringField(data, normalizedField);
  if (!legacy.ok || !normalized.ok) return {ok: false, conflict: false};

  const legacyValue = normalize(legacy.value);
  const normalizedValue = normalize(normalized.value);
  if (legacy.present && normalized.present && legacyValue !== normalizedValue) {
    return {ok: false, conflict: true};
  }
  return {
    ok: true,
    present: legacy.present || normalized.present,
    value: normalized.present ? normalizedValue : legacyValue,
  };
}

function isValidTimestamp(value: unknown): boolean {
  if (value instanceof Date) return Number.isFinite(value.getTime());
  if (!value || typeof value !== "object") return false;

  const timestamp = value as {
    seconds?: unknown;
    nanoseconds?: unknown;
    toDate?: unknown;
  };
  return typeof timestamp.toDate === "function" &&
    typeof timestamp.seconds === "number" &&
    Number.isSafeInteger(timestamp.seconds) &&
    typeof timestamp.nanoseconds === "number" &&
    Number.isInteger(timestamp.nanoseconds) &&
    timestamp.nanoseconds >= 0 &&
    timestamp.nanoseconds < 1_000_000_000;
}

function hasInvalidTimestamp(data: Record<string, unknown>): boolean {
  for (const field of ["createdAt", "updatedAt"] as const) {
    if (Object.prototype.hasOwnProperty.call(data, field) &&
        !isValidTimestamp(data[field])) {
      return true;
    }
  }
  return false;
}

function isSupportedTargetType(value: string): value is SupportedReportTargetType {
  return supportedReportTargetTypes.includes(value as SupportedReportTargetType);
}

export function normalizeReportContract(value: unknown): ReportContractResult {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {ok: false, code: "invalid_type"};
  }
  const data = value as Record<string, unknown>;

  const type = resolveAlias(data, "type", "targetType", (entry) =>
    entry.toLowerCase());
  if (!type.ok) {
    return {
      ok: false,
      code: type.conflict ? "conflicting_type_aliases" : "invalid_type",
    };
  }
  if (!type.present || !type.value) return {ok: false, code: "missing_type"};
  if (!isSupportedTargetType(type.value)) {
    return {ok: false, code: "unsupported_type"};
  }

  const reporter = resolveAlias(data, "reportedBy", "reporterId");
  if (!reporter.ok) {
    return {
      ok: false,
      code: reporter.conflict ?
        "conflicting_reporter_aliases" :
        "invalid_reporter",
    };
  }
  if (!reporter.present || !reporter.value) {
    return {ok: false, code: "missing_reporter"};
  }

  const targetId = readStringField(data, "targetId");
  if (!targetId.ok) return {ok: false, code: "invalid_target_id"};
  if (!targetId.present || !targetId.value) {
    return {ok: false, code: "missing_target_id"};
  }

  const status = readStringField(data, "status");
  const normalizedStatus = status.ok ? status.value.toLowerCase() : "";
  const canonicalOnlyShape =
    !Object.prototype.hasOwnProperty.call(data, "type") &&
    !Object.prototype.hasOwnProperty.call(data, "reportedBy") &&
    Object.prototype.hasOwnProperty.call(data, "targetType") &&
    Object.prototype.hasOwnProperty.call(data, "reporterId");
  if (!status.ok || !status.present ||
      (normalizedStatus !== "pending" &&
       !(normalizedStatus === "open" && canonicalOnlyShape))) {
    return {ok: false, code: "invalid_status"};
  }

  const targetOwner = readStringField(data, "targetOwnerId");
  if (!targetOwner.ok) return {ok: false, code: "invalid_target_owner"};

  const serviceContext = resolveAlias(data, "serviceId", "contextId");
  if (!serviceContext.ok) {
    return {
      ok: false,
      code: serviceContext.conflict ?
        "conflicting_service_context_aliases" :
        "invalid_service_context",
    };
  }

  const reason = readStringField(data, "reason");
  if (!reason.ok) return {ok: false, code: "invalid_reason"};
  const description = readStringField(data, "description");
  if (!description.ok) return {ok: false, code: "invalid_description"};
  if (hasInvalidTimestamp(data)) return {ok: false, code: "invalid_timestamp"};

  return {
    ok: true,
    report: {
      targetType: type.value,
      targetId: targetId.value,
      reporterId: reporter.value,
      claimedTargetOwnerId: targetOwner.value,
      status: normalizedStatus as "pending" | "open",
      reason: reason.value || "User report",
      description: description.value,
      serviceId: serviceContext.value,
    },
  };
}

export function moderationQueueIdForReport(reportId: string): string {
  const normalized = reportId.trim();
  if (!normalized || normalized.includes("/") ||
      Buffer.byteLength(normalized, "utf8") > 1493) {
    throw new Error("Invalid report ID.");
  }
  return `report_${normalized}`;
}

export function shouldCreateReportModerationQueueItem(
  existingQueueItem: unknown,
): boolean {
  return existingQueueItem === undefined || existingQueueItem === null;
}

export async function createReportModerationQueueItemOnce(params: {
  firestore: Firestore;
  reportId: string;
  queueItem: DocumentData;
}): Promise<boolean> {
  const queue = params.firestore.collection("moderationQueue");
  const historicalQueueItem = await queue
    .where("reportId", "==", params.reportId)
    .limit(1)
    .get();
  if (!historicalQueueItem.empty) return false;

  const queueRef = queue.doc(moderationQueueIdForReport(params.reportId));
  return params.firestore.runTransaction(async (transaction) => {
    const existing = await transaction.get(queueRef);
    if (!shouldCreateReportModerationQueueItem(
      existing.exists ? existing.data() : null,
    )) {
      return false;
    }
    transaction.create(queueRef, params.queueItem);
    return true;
  });
}

export type ReportTargetOwnership = {
  status: "resolved" | "unresolved";
  targetOwnerId: string;
  diagnosticCode:
    | "resolved_from_review_parent"
    | "resolved_from_service"
    | "review_context_missing"
    | "review_not_found"
    | "review_owner_mismatch"
    | "service_not_found"
    | "target_owner_missing";
};

function trimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export async function resolveReportTargetOwnership(params: {
  firestore: Firestore;
  report: NormalizedReportContract;
  transaction?: Transaction;
}): Promise<ReportTargetOwnership> {
  const {firestore, report, transaction} = params;
  const read = <T extends DocumentData>(reference: DocumentReference<T>):
    Promise<DocumentSnapshot<T>> => transaction ?
      transaction.get(reference) :
      reference.get();
  if (report.targetType === "service") {
    const serviceSnapshot = await read(
      firestore.collection("services").doc(report.targetId),
    );
    if (!serviceSnapshot.exists) {
      return {
        status: "unresolved",
        targetOwnerId: "",
        diagnosticCode: "service_not_found",
      };
    }
    const targetOwnerId = trimmedString(serviceSnapshot.data()?.ownerUserId);
    if (!targetOwnerId) {
      return {
        status: "unresolved",
        targetOwnerId: "",
        diagnosticCode: "target_owner_missing",
      };
    }
    return {
      status: "resolved",
      targetOwnerId,
      diagnosticCode: "resolved_from_service",
    };
  }

  if (!report.serviceId) {
    return {
      status: "unresolved",
      targetOwnerId: "",
      diagnosticCode: "review_context_missing",
    };
  }

  const serviceRef = firestore.collection("services").doc(report.serviceId);
  const [serviceSnapshot, reviewSnapshot] = await Promise.all([
    read(serviceRef),
    read(serviceRef.collection("reviews").doc(report.targetId)),
  ]);
  if (!serviceSnapshot.exists || !reviewSnapshot.exists) {
    return {
      status: "unresolved",
      targetOwnerId: "",
      diagnosticCode: reviewSnapshot.exists ? "service_not_found" : "review_not_found",
    };
  }

  const targetOwnerId = trimmedString(serviceSnapshot.data()?.ownerUserId);
  if (!targetOwnerId) {
    return {
      status: "unresolved",
      targetOwnerId: "",
      diagnosticCode: "target_owner_missing",
    };
  }
  const review = reviewSnapshot.data() ?? {};
  const reviewOwnerId = trimmedString(review.providerUserId) ||
    trimmedString(review.providerId);
  if (reviewOwnerId && reviewOwnerId !== targetOwnerId) {
    return {
      status: "unresolved",
      targetOwnerId: "",
      diagnosticCode: "review_owner_mismatch",
    };
  }
  const reviewAuthorId = trimmedString(review.reviewerUserId) ||
    trimmedString(review.reviewerId);
  if (!reviewAuthorId) {
    return {
      status: "unresolved",
      targetOwnerId: "",
      diagnosticCode: "target_owner_missing",
    };
  }
  return {
    status: "resolved",
    targetOwnerId: reviewAuthorId,
    diagnosticCode: "resolved_from_review_parent",
  };
}

export type ReportModerationEnqueueResult = {
  outcome: "created" | "duplicate" | "skipped";
  diagnosticCode: string;
  targetType: SupportedReportTargetType | "";
};

export async function enqueueReportModerationData(params: {
  firestore: Firestore;
  reportId: string;
  reportData: unknown;
}): Promise<ReportModerationEnqueueResult> {
  const result = normalizeReportContract(params.reportData);
  if (!result.ok) {
    return {
      outcome: "skipped",
      diagnosticCode: result.code,
      targetType: "",
    };
  }

  const ownership = await resolveReportTargetOwnership({
    firestore: params.firestore,
    report: result.report,
  });
  const created = await createReportModerationQueueItemOnce({
    firestore: params.firestore,
    reportId: params.reportId,
    queueItem: {
      targetType: result.report.targetType,
      targetId: result.report.targetId,
      targetOwnerId: ownership.targetOwnerId,
      source: "report",
      reportId: params.reportId,
      severity: "medium",
      status: "pending",
      reason: result.report.reason,
      assignedAdminId: "",
      targetResolutionStatus: ownership.status,
      targetResolutionReason: ownership.diagnosticCode,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
  });
  return {
    outcome: created ? "created" : "duplicate",
    diagnosticCode: ownership.diagnosticCode,
    targetType: result.report.targetType,
  };
}
