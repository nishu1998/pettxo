import {
  FieldPath,
  getFirestore,
  type DocumentData,
  type Firestore,
  type Query,
  type QueryDocumentSnapshot,
} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onCall} from "firebase-functions/v2/https";

import {
  effectiveCanonicalBookingStateForAdmin,
  loadAdminActor,
} from "./bookingAdminOperationsV3";
import {
  CANONICAL_BOOKING_STATES,
} from "./domain/bookingContracts";
import {parseCanonicalBookingDocumentV3} from "./schema/bookingDocumentV3";
import {isCanonicalBookingDocumentCandidate} from "./schema/bookingReadModel";

const db = getFirestore();
const DASHBOARD_SCAN_PAGE_SIZE = 250;
const CANONICAL_SOURCE = "canonical_v3";

const ACTIVE_BOOKING_STATES = new Set([
  "CONFIRMED",
  "IN_PROGRESS",
]);
const COMPLETED_BOOKING_STATES = new Set([
  "COMPLETED_PENDING_REVIEW",
  "UNDER_DISPUTE",
  "DISPUTE_RESOLVED",
  "COMPLETED_FINAL",
]);
const KNOWN_EFFECTIVE_BOOKING_STATES = new Set([
  ...CANONICAL_BOOKING_STATES,
  "UNDER_DISPUTE",
  "DISPUTE_RESOLVED",
]);
const CANONICAL_DISPUTE_STATES = new Set(["OPEN", "RESOLVED"]);

export type DashboardMetricResult =
  | {available: true; value: number}
  | {available: false; value: null; errorCode: string; message: string};

export type DashboardDocumentRecord = {
  id: string;
  data: Record<string, unknown>;
};

export type CanonicalDisputeMetricState = {
  openDisputes: number;
  statusByBookingId: Map<string, string>;
};

export type CanonicalBookingMetricCounts = {
  activeBookings: number;
  completedBookings: number;
};

export type BookingMetricScanAnomaly = {
  bookingId: string;
  documentFormat: string;
  schemaVersion: string | number | null;
  bookingModelVersion: string;
  storedState: string;
  stateQueryValue: string;
  failureStage: "eligibility" | "parse" | "effective-state" | "classification";
  errorCode: string;
  errorMessage: string;
  issues: Array<{code: string; path: string}>;
};

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function safeVersion(value: unknown): string | number | null {
  return typeof value === "string" || typeof value === "number" ? value : null;
}

function hasCanonicalBookingMarker(data: Record<string, unknown>): boolean {
  return asString(data.documentFormat) === CANONICAL_SOURCE ||
    data.schemaVersion === 3 ||
    asString(data.bookingModelVersion) === "3.2";
}

function safeError(error: unknown): {code: string; message: string} {
  const candidate = error as {code?: unknown; message?: unknown} | null;
  const code = asString(candidate?.code) || "unknown";
  const message = asString(candidate?.message);
  return {
    code,
    message: message ? message.slice(0, 200) : "Booking metric calculation failed.",
  };
}

function anomalyBase(
  record: DashboardDocumentRecord,
): Omit<BookingMetricScanAnomaly, "failureStage" | "errorCode" | "errorMessage" | "issues"> {
  return {
    bookingId: record.id,
    documentFormat: asString(record.data.documentFormat),
    schemaVersion: safeVersion(record.data.schemaVersion),
    bookingModelVersion: asString(record.data.bookingModelVersion),
    storedState: asString(record.data.state),
    stateQueryValue: asString(record.data.stateQueryValue),
  };
}

function logBookingMetricAnomaly(anomaly: BookingMetricScanAnomaly): void {
  if (anomaly.failureStage === "effective-state" ||
    anomaly.failureStage === "classification") {
    logger.error("admin-dashboard-booking-failed", anomaly);
    return;
  }
  logger.warn("admin-dashboard-booking-skipped", anomaly);
}

export function collectCanonicalDisputeMetricState(
  records: ReadonlyArray<DashboardDocumentRecord>,
): CanonicalDisputeMetricState {
  const statusByBookingId = new Map<string, string>();
  let openDisputes = 0;

  for (const record of records) {
    if (asString(record.data.source) !== CANONICAL_SOURCE) continue;
    const bookingId = asString(record.data.bookingId);
    const status = asString(record.data.status).toUpperCase();
    if (
      !bookingId ||
      bookingId !== record.id ||
      !CANONICAL_DISPUTE_STATES.has(status)
    ) {
      continue;
    }
    statusByBookingId.set(bookingId, status);
    if (status === "OPEN") openDisputes += 1;
  }

  return {openDisputes, statusByBookingId};
}

export function countCanonicalBookingMetrics(params: {
  records: ReadonlyArray<DashboardDocumentRecord>;
  disputeStatusByBookingId: ReadonlyMap<string, string>;
  now: Date;
  onAnomaly?: (anomaly: BookingMetricScanAnomaly) => void;
}): CanonicalBookingMetricCounts {
  let activeBookings = 0;
  let completedBookings = 0;

  for (const record of params.records) {
    if (!isCanonicalBookingDocumentCandidate(record.data)) {
      if (hasCanonicalBookingMarker(record.data)) {
        params.onAnomaly?.({
          ...anomalyBase(record),
          failureStage: "eligibility",
          errorCode: "NON_CANONICAL_BOOKING_DOCUMENT",
          errorMessage: "Booking markers do not match the canonical v3.2 contract.",
          issues: [],
        });
      }
      continue;
    }
    const parsed = parseCanonicalBookingDocumentV3(record.data);
    if (!parsed.ok || parsed.booking == null) {
      params.onAnomaly?.({
        ...anomalyBase(record),
        failureStage: "parse",
        errorCode: "MALFORMED_CANONICAL_BOOKING",
        errorMessage: "Canonical booking failed schema validation.",
        issues: parsed.issues.map((issue) => ({
          code: issue.code,
          path: issue.path,
        })),
      });
      continue;
    }
    let effectiveState: string;
    try {
      effectiveState = effectiveCanonicalBookingStateForAdmin(
        parsed.booking,
        params.disputeStatusByBookingId.get(record.id),
        params.now,
      );
    } catch (error) {
      const safe = safeError(error);
      params.onAnomaly?.({
        ...anomalyBase(record),
        failureStage: "effective-state",
        errorCode: safe.code,
        errorMessage: safe.message,
        issues: [],
      });
      throw error;
    }
    if (!KNOWN_EFFECTIVE_BOOKING_STATES.has(effectiveState)) {
      params.onAnomaly?.({
        ...anomalyBase(record),
        failureStage: "classification",
        errorCode: "UNKNOWN_EFFECTIVE_STATE",
        errorMessage: "Effective booking state is not recognized.",
        issues: [],
      });
      throw new Error("Effective booking state is not recognized.");
    }
    if (ACTIVE_BOOKING_STATES.has(effectiveState)) activeBookings += 1;
    if (COMPLETED_BOOKING_STATES.has(effectiveState)) completedBookings += 1;
  }

  return {activeBookings, completedBookings};
}

export function isCanonicalVisibleReview(
  data: Record<string, unknown>,
): boolean {
  return asString(data.source) === CANONICAL_SOURCE &&
    asString(data.moderationStatus).toLowerCase() === "approved";
}

export function countCanonicalVisibleReviews(
  records: ReadonlyArray<DashboardDocumentRecord>,
): number {
  return records.filter((record) => isCanonicalVisibleReview(record.data)).length;
}

export async function forEachQueryDocument(params: {
  query: Query<DocumentData>;
  visit: (document: QueryDocumentSnapshot<DocumentData>) => void;
}): Promise<void> {
  let cursor: QueryDocumentSnapshot<DocumentData> | null = null;
  while (true) {
    let pageQuery = params.query
      .orderBy(FieldPath.documentId())
      .limit(DASHBOARD_SCAN_PAGE_SIZE);
    if (cursor != null) pageQuery = pageQuery.startAfter(cursor);
    const snapshot = await pageQuery.get();
    for (const document of snapshot.docs) params.visit(document);
    if (snapshot.docs.length < DASHBOARD_SCAN_PAGE_SIZE) return;
    cursor = snapshot.docs[snapshot.docs.length - 1];
  }
}

async function loadCanonicalDisputeMetricState(
  firestore: Firestore,
): Promise<CanonicalDisputeMetricState> {
  const result: CanonicalDisputeMetricState = {
    openDisputes: 0,
    statusByBookingId: new Map<string, string>(),
  };
  await forEachQueryDocument({
    query: firestore.collection("disputes"),
    visit: (document) => {
      const pageResult = collectCanonicalDisputeMetricState([{
        id: document.id,
        data: document.data() as Record<string, unknown>,
      }]);
      result.openDisputes += pageResult.openDisputes;
      for (const [bookingId, status] of pageResult.statusByBookingId) {
        result.statusByBookingId.set(bookingId, status);
      }
    },
  });
  return result;
}

export async function loadCanonicalBookingMetricCounts(params: {
  firestore: Firestore;
  disputeStatusByBookingId: ReadonlyMap<string, string>;
  now: Date;
}): Promise<CanonicalBookingMetricCounts> {
  const totals: CanonicalBookingMetricCounts = {
    activeBookings: 0,
    completedBookings: 0,
  };
  await forEachQueryDocument({
    query: params.firestore.collection("bookings"),
    visit: (document) => {
      const counts = countCanonicalBookingMetrics({
        records: [{
          id: document.id,
          data: document.data() as Record<string, unknown>,
        }],
        disputeStatusByBookingId: params.disputeStatusByBookingId,
        now: params.now,
        onAnomaly: logBookingMetricAnomaly,
      });
      totals.activeBookings += counts.activeBookings;
      totals.completedBookings += counts.completedBookings;
    },
  });
  return totals;
}

function isCanonicalReviewPath(document: QueryDocumentSnapshot<DocumentData>): boolean {
  const serviceRef = document.ref.parent.parent;
  return serviceRef != null && serviceRef.parent.id === "services";
}

async function loadCanonicalVisibleReviewCount(
  firestore: Firestore,
): Promise<number> {
  let count = 0;
  await forEachQueryDocument({
    query: firestore.collectionGroup("reviews"),
    visit: (document) => {
      if (!isCanonicalReviewPath(document)) return;
      if (isCanonicalVisibleReview(document.data() as Record<string, unknown>)) {
        count += 1;
      }
    },
  });
  return count;
}

function available(value: number): DashboardMetricResult {
  return {available: true, value};
}

function failedMetric(metric: string, error: unknown): DashboardMetricResult {
  const rawCode = asString((error as {code?: unknown} | null)?.code).toLowerCase();
  const unavailable = rawCode.includes("unavailable") || rawCode === "14";
  logger.error("admin-dashboard-metric-failed", {
    metric,
    errorCode: rawCode || "unknown",
  });
  return {
    available: false,
    value: null,
    errorCode: unavailable ? "unavailable" : "internal",
    message: unavailable ?
      "Dashboard metric service is temporarily unavailable." :
      "Dashboard metric could not be calculated.",
  };
}

export async function getAdminDashboardMetricsDataV3(params: {
  firestore: Firestore;
  now?: Date;
}) {
  const now = params.now ?? new Date();
  const reviewPromise = loadCanonicalVisibleReviewCount(params.firestore);

  let activeBookings: DashboardMetricResult;
  let completedBookings: DashboardMetricResult;
  let openDisputes: DashboardMetricResult;
  try {
    const disputes = await loadCanonicalDisputeMetricState(params.firestore);
    openDisputes = available(disputes.openDisputes);
    try {
      const bookings = await loadCanonicalBookingMetricCounts({
        firestore: params.firestore,
        disputeStatusByBookingId: disputes.statusByBookingId,
        now,
      });
      activeBookings = available(bookings.activeBookings);
      completedBookings = available(bookings.completedBookings);
    } catch (error) {
      activeBookings = failedMetric("activeBookings", error);
      completedBookings = failedMetric("completedBookings", error);
    }
  } catch (error) {
    openDisputes = failedMetric("openDisputes", error);
    activeBookings = failedMetric("activeBookings", error);
    completedBookings = failedMetric("completedBookings", error);
  }

  let visibleReviews: DashboardMetricResult;
  try {
    visibleReviews = available(await reviewPromise);
  } catch (error) {
    visibleReviews = failedMetric("visibleReviews", error);
  }

  return {
    metrics: {
      activeBookings,
      completedBookings,
      openDisputes,
      visibleReviews,
    },
    calculatedAt: now.toISOString(),
  };
}

export const getAdminDashboardMetricsV3 = onCall(
  {invoker: "private"},
  async (request) => {
    await loadAdminActor(db, request.auth, "dispute_nonfinancial");
    return await getAdminDashboardMetricsDataV3({firestore: db});
  },
);
