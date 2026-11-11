import {createHash} from "crypto";
import {FieldValue} from "firebase-admin/firestore";
import type {Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {
  normalizeReportContract,
  resolveReportTargetOwnership,
  type NormalizedReportContract,
  type SupportedReportTargetType,
} from "./reportContract";

const allowedRequestFields = new Set([
  "type",
  "targetId",
  "contextId",
  "reason",
  "description",
  "clientRequestId",
]);
const supportedReasons = new Set([
  "spam",
  "fake_information",
  "abusive_or_harmful",
  "inappropriate_content",
  "safety_concern",
  "other",
]);
const maxDescriptionLength = 2000;
const maxClientRequestIdLength = 128;

export type SubmitReportInput = {
  type: SupportedReportTargetType;
  targetId: string;
  contextId: string;
  reason: string;
  description: string;
  clientRequestId: string;
};

export type SubmitReportResult = {
  reportId: string;
  status: "pending";
  duplicate: boolean;
};

function trimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function validDocumentId(value: string): boolean {
  return value.length > 0 &&
    value !== "." &&
    value !== ".." &&
    !value.includes("/") &&
    Buffer.byteLength(value, "utf8") <= 1500;
}

function validateOptionalString(
  value: unknown,
  field: string,
  maxLength: number,
): string {
  if (value === undefined || value === null) return "";
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be text.`);
  }
  const normalized = value.trim();
  if (normalized.length > maxLength) {
    throw new HttpsError("invalid-argument", `${field} is too long.`);
  }
  return normalized;
}

export function parseSubmitReportInput(value: unknown): SubmitReportInput {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "Report request is invalid.");
  }
  const data = value as Record<string, unknown>;
  if (Object.keys(data).some((field) => !allowedRequestFields.has(field))) {
    throw new HttpsError(
      "invalid-argument",
      "Report request contains unsupported fields.",
    );
  }

  const type = trimmedString(data.type).toLowerCase();
  if (type !== "service" && type !== "review") {
    throw new HttpsError("invalid-argument", "Report type is unsupported.");
  }
  const targetId = trimmedString(data.targetId);
  if (!validDocumentId(targetId)) {
    throw new HttpsError("invalid-argument", "Target ID is invalid.");
  }
  const contextId = validateOptionalString(data.contextId, "contextId", 1500);
  if (type === "review" && !validDocumentId(contextId)) {
    throw new HttpsError(
      "invalid-argument",
      "A valid service context is required for review reports.",
    );
  }
  if (type === "service" && contextId) {
    throw new HttpsError(
      "invalid-argument",
      "Service reports do not accept a context ID.",
    );
  }

  const reason = trimmedString(data.reason).toLowerCase();
  if (!supportedReasons.has(reason)) {
    throw new HttpsError("invalid-argument", "Report reason is invalid.");
  }
  const description = validateOptionalString(
    data.description,
    "description",
    maxDescriptionLength,
  );
  const clientRequestId = validateOptionalString(
    data.clientRequestId,
    "clientRequestId",
    maxClientRequestIdLength,
  );
  if (clientRequestId && !/^[A-Za-z0-9._:-]+$/.test(clientRequestId)) {
    throw new HttpsError("invalid-argument", "clientRequestId is invalid.");
  }

  return {
    type,
    targetId,
    contextId,
    reason,
    description,
    clientRequestId,
  };
}

export function reportIdForSubmission(params: {
  reporterId: string;
  type: SupportedReportTargetType;
  targetId: string;
  contextId: string;
}): string {
  const identity = [
    "v1",
    params.reporterId,
    params.type,
    params.contextId,
    params.targetId,
  ].join("\u001f");
  return `report_${createHash("sha256").update(identity).digest("hex")}`;
}

function reporterNameFromUser(data: Record<string, unknown>): string {
  const name = trimmedString(data.name) || trimmedString(data.displayName);
  if (name) return name.slice(0, 120);
  const username = trimmedString(data.username).replace(/^@/, "");
  return username ? username.slice(0, 120) : "Pettxo user";
}

function assertReporterAccountAvailable(
  exists: boolean,
  data: Record<string, unknown>,
): void {
  const status = trimmedString(data.accountStatus);
  if (!exists || data.isDeleted === true || (status && status !== "active")) {
    throw new HttpsError(
      "failed-precondition",
      "This account cannot submit reports right now.",
    );
  }
}

function normalizedContractForSubmission(
  input: SubmitReportInput,
  reporterId: string,
): NormalizedReportContract {
  const result = normalizeReportContract({
    targetType: input.type,
    targetId: input.targetId,
    reporterId,
    status: "pending",
    contextId: input.contextId,
    reason: input.reason,
    description: input.description,
  });
  if (!result.ok) {
    throw new HttpsError("invalid-argument", "Report request is invalid.");
  }
  return result.report;
}

function existingReportMatches(
  data: Record<string, unknown>,
  report: NormalizedReportContract,
): boolean {
  const type = trimmedString(data.targetType) || trimmedString(data.type);
  const reporter = trimmedString(data.reporterId) || trimmedString(data.reportedBy);
  return type === report.targetType &&
    reporter === report.reporterId &&
    trimmedString(data.targetId) === report.targetId &&
    trimmedString(data.contextId) === report.serviceId;
}

export async function submitReportData(params: {
  firestore: Firestore;
  authUid: string;
  input: unknown;
}): Promise<SubmitReportResult> {
  const reporterId = params.authUid.trim();
  if (!reporterId) {
    throw new HttpsError("unauthenticated", "Sign in to submit a report.");
  }
  const input = parseSubmitReportInput(params.input);
  const report = normalizedContractForSubmission(input, reporterId);
  const reportId = reportIdForSubmission({
    reporterId,
    type: report.targetType,
    targetId: report.targetId,
    contextId: report.serviceId,
  });
  const userRef = params.firestore.collection("users").doc(reporterId);
  const reportRef = params.firestore.collection("reports").doc(reportId);

  const result = await params.firestore.runTransaction(async (transaction) => {
    const [userSnapshot, existingReport] = await Promise.all([
      transaction.get(userRef),
      transaction.get(reportRef),
    ]);
    const user = userSnapshot.data() ?? {};
    assertReporterAccountAvailable(userSnapshot.exists, user);

    if (existingReport.exists) {
      if (!existingReportMatches(existingReport.data() ?? {}, report)) {
        throw new HttpsError(
          "internal",
          "The report could not be submitted safely.",
        );
      }
      return {duplicate: true};
    }

    const ownership = await resolveReportTargetOwnership({
      firestore: params.firestore,
      report,
      transaction,
    });
    if (ownership.status !== "resolved") {
      const missing = ownership.diagnosticCode === "service_not_found" ||
        ownership.diagnosticCode === "review_not_found";
      throw new HttpsError(
        missing ? "not-found" : "failed-precondition",
        missing ? "Report target not found." : "Report target is unavailable.",
      );
    }
    if (ownership.targetOwnerId === reporterId) {
      throw new HttpsError(
        "failed-precondition",
        "You cannot report your own content.",
      );
    }

    const targetPath = report.targetType === "service" ?
      `services/${report.targetId}` :
      `services/${report.serviceId}/reviews/${report.targetId}`;
    transaction.create(reportRef, {
      schemaVersion: 2,
      type: report.targetType,
      targetType: report.targetType,
      targetId: report.targetId,
      contextId: report.serviceId,
      targetPath,
      reportedBy: reporterId,
      reporterId,
      reporterName: reporterNameFromUser(user),
      targetOwnerId: ownership.targetOwnerId,
      status: "pending",
      reason: report.reason,
      description: report.description,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {duplicate: false};
  });

  return {reportId, status: "pending", duplicate: result.duplicate};
}
