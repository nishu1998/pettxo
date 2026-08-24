import {FieldPath, type Firestore} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";

import {db} from "../shared/firebase";
import {
  BOOKING_CANCELLATION_COLLECTION,
} from "./application/cancellationOrchestrationV3";
import {
  CANONICAL_FINANCIAL_LEDGER_COLLECTION,
  CANONICAL_FINANCIAL_POLICY_VERSION,
  CANONICAL_FINANCIAL_RECONCILIATION_COLLECTION,
  CANONICAL_PROVIDER_PAYOUTS_COLLECTION,
  CANONICAL_PROVIDER_PAYOUTS_LIVE_ENABLED,
} from "./application/financialSettlementV3";
import {
  BOOKING_NO_SHOWS_COLLECTION,
} from "./application/serviceStartOrchestrationV3";
import type {
  CanonicalBookingDocumentV3,
  CanonicalRangeScheduleV3,
  CanonicalSlotScheduleV3,
} from "./schema/bookingDocumentV3";
import {parseCanonicalBookingDocumentV3} from "./schema/bookingDocumentV3";
import {normalizeTimestampLike} from "./schema/timestampNormalization";

type AdminRole = "superAdmin" | "financeAdmin" | "customerSupportAdmin";
type AdminScope = "dispute_nonfinancial" | "financial";
type CanonicalActor = {
  uid: string;
  role: AdminRole;
  canViewFinancials: boolean;
};

type CursorPayload = {
  sortValue: string;
  docId: string;
};

type LedgerTotals = {
  count: number;
  paymentCapturedPaise: number;
  refundPaise: number;
  payoutPaise: number;
  platformRevenuePaise: number;
};

type CanonicalListInput = {
  cursor?: string;
  limit?: number;
  search?: string;
  status?: string;
  role?: string;
  bookingType?: string;
  paymentStatus?: string;
  disputeStatus?: string;
  payoutStatus?: string;
  failureCode?: string;
  sortField?: string;
  dateFrom?: string;
  dateTo?: string;
  failedOnly?: boolean;
  retryableOnly?: boolean;
};

type CanonicalCustomerSummary = {
  userId: string;
  displayName: string;
  photoUrl: string;
  rating: number;
  completedBookingCount: number;
  maskedIdentity: string;
  maskedEmail: string | null;
  maskedPhone: string | null;
};

type CanonicalProviderSummary = {
  userId: string;
  displayName: string;
  username: string;
  photoUrl: string;
  rating: number;
  completedBookingCount: number;
  maskedIdentity: string;
  bankReadiness: string | null;
};

type CanonicalServiceSummary = {
  serviceId: string;
  providerId: string;
  title: string;
  category: string;
  animalType: string;
  bookingType: string;
  timezone: string;
  scheduledStartAt: string | null;
  scheduledEndAt: string | null;
  serviceAnchorAt: string | null;
  locationType: string;
};

type CanonicalDisputeSummaryForAdmin = {
  disputeId: string;
  bookingId: string;
  status: string;
  reasonCode: string;
  raisedAt: string | null;
  raisedByRole: string;
  raisedByMaskedIdentity: string;
  customer: CanonicalCustomerSummary;
  provider: CanonicalProviderSummary;
  service: CanonicalServiceSummary;
  disputedAmountPaise: number | null;
  paymentStatus: string | null;
  refundStatus: string | null;
  payoutStatus: string | null;
  evidenceCount: number;
  adminActionRequired: boolean;
  lastActivityAt: string | null;
};

const DEFAULT_LIMIT = 25;
const MAX_LIMIT = 50;
const MAX_BATCH_MULTIPLIER = 4;
const MAX_SCAN_BATCHES = 4;

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asInt(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value) ?
    Math.trunc(value) :
    fallback;
}

function asBool(value: unknown): boolean {
  return value === true;
}

function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value != null ?
    value as Record<string, unknown> :
    {};
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function asDate(value: unknown): Date | null {
  return normalizeTimestampLike(value);
}

function parseIsoDateString(value: string): Date | null {
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function iso(value: unknown): string | null {
  return asDate(value)?.toISOString() ?? null;
}

function clampLimit(value: unknown): number {
  return Math.min(Math.max(asInt(value, DEFAULT_LIMIT), 1), MAX_LIMIT);
}

function encodeCursor(payload: CursorPayload | null): string | null {
  if (payload == null || !payload.sortValue || !payload.docId) return null;
  return Buffer.from(JSON.stringify(payload), "utf8").toString("base64");
}

function decodeCursor(rawValue: unknown): CursorPayload | null {
  const value = asString(rawValue);
  if (!value) return null;
  try {
    const parsed = JSON.parse(Buffer.from(value, "base64").toString("utf8"));
    const sortValue = asString(parsed.sortValue);
    const docId = asString(parsed.docId);
    if (!sortValue || !docId || parseIsoDateString(sortValue) == null) {
      throw new Error("invalid cursor");
    }
    return {sortValue, docId};
  } catch (_) {
    throw new HttpsError("invalid-argument", "cursor is invalid.");
  }
}

function ensureDateInput(value: unknown, field: string): Date | null {
  const normalized = asString(value);
  if (!normalized) return null;
  const parsed = parseIsoDateString(normalized);
  if (parsed == null) {
    throw new HttpsError("invalid-argument", `${field} must be a valid ISO date string.`);
  }
  return parsed;
}

function normalizeSearch(value: unknown): string {
  return asString(value);
}

function normalizeBookingIdSearchKey(value: unknown): string {
  return asString(value).toLowerCase();
}

function fileNameFromPath(path: string): string {
  const segments = path.split("/").filter(Boolean);
  return segments.length > 0 ? segments[segments.length - 1] : path;
}

function contentTypeFromPath(path: string): string {
  const fileName = fileNameFromPath(path).toLowerCase();
  if (fileName.endsWith(".pdf")) return "application/pdf";
  if (fileName.endsWith(".png")) return "image/png";
  if (fileName.endsWith(".jpg") || fileName.endsWith(".jpeg")) return "image/jpeg";
  if (fileName.endsWith(".webp")) return "image/webp";
  return "application/octet-stream";
}

function maskEmail(email: string): string | null {
  const normalized = asString(email);
  if (!normalized.includes("@")) return null;
  const [local, domain] = normalized.split("@");
  if (!local || !domain) return null;
  const head = local.slice(0, Math.min(local.length, 2));
  return `${head}***@${domain}`;
}

function maskPhone(phone: string): string | null {
  const digits = phone.replace(/\D/g, "");
  if (digits.length < 4) return null;
  return `${"*".repeat(Math.max(digits.length - 4, 0))}${digits.slice(-4)}`;
}

function maskDisplayName(first: string, second = ""): string {
  const head = asString(first);
  const tail = asString(second);
  if (!head) return "";
  if (tail) return `${head} ${tail.slice(0, 1)}.`;
  if (head.length <= 2) return `${head.slice(0, 1)}*`;
  return `${head.slice(0, 2)}***`;
}

function buildRaisedByMaskedIdentity(params: {
  booking: CanonicalBookingDocumentV3 | null;
  dispute: Record<string, unknown>;
}): string {
  const raisedBy = asString(asRecord(params.dispute.raisedBy).role) ||
    asString(asRecord(params.dispute).raisedBy) ||
    (params.booking?.dispute.raisedBy ?? "");
  if (raisedBy === "provider") {
    return params.booking == null ?
      "Provider" :
      maskDisplayName(
        params.booking.participants.provider.displayName,
        params.booking.participants.provider.username,
      );
  }
  return params.booking == null ?
    "Customer" :
    maskDisplayName(
      params.booking.participants.parent.displayFirstName,
      params.booking.participants.parent.lastInitial,
    );
}

function customerSummaryFromBooking(
  booking: CanonicalBookingDocumentV3,
  rawUser: Record<string, unknown> | null,
): CanonicalCustomerSummary {
  return {
    userId: booking.parentId,
    displayName: `${booking.participants.parent.displayFirstName} ${booking.participants.parent.lastInitial}.`,
    photoUrl: booking.participants.parent.photoUrl,
    rating: booking.participants.parent.rating,
    completedBookingCount: booking.participants.parent.completedBookingCount,
    maskedIdentity: maskDisplayName(
      booking.participants.parent.displayFirstName,
      booking.participants.parent.lastInitial,
    ),
    maskedEmail: maskEmail(asString(rawUser?.email)),
    maskedPhone: maskPhone(asString(rawUser?.phoneNumber)),
  };
}

function providerSummaryFromBooking(params: {
  booking: CanonicalBookingDocumentV3;
  bank: Record<string, unknown> | null;
}): CanonicalProviderSummary {
  return {
    userId: params.booking.providerId,
    displayName: params.booking.participants.provider.displayName,
    username: params.booking.participants.provider.username,
    photoUrl: params.booking.participants.provider.photoUrl,
    rating: params.booking.participants.provider.rating,
    completedBookingCount:
      params.booking.participants.provider.completedBookingCount,
    maskedIdentity: params.booking.participants.provider.displayName,
    bankReadiness: asString(params.bank?.status) || null,
  };
}

function serviceSummaryFromBooking(
  booking: CanonicalBookingDocumentV3,
): CanonicalServiceSummary {
  const schedule = booking.schedule;
  const scheduledStartAt =
    booking.bookingType === "SLOT" ?
      iso(asRecord(schedule).scheduledStartAt) :
      iso(asRecord(schedule).checkInDateTime);
  const scheduledEndAt =
    booking.bookingType === "SLOT" ?
      iso(asRecord(schedule).scheduledEndAt) :
      iso(asRecord(schedule).checkOutDateTime);
  return {
    serviceId: booking.serviceId,
    providerId: booking.providerId,
    title: booking.service.serviceTitle,
    category: booking.service.category,
    animalType: booking.service.animalType,
    bookingType: booking.bookingType,
    timezone: booking.service.timezone,
    scheduledStartAt,
    scheduledEndAt,
    serviceAnchorAt: booking.serviceAnchorAt?.toISOString() ?? null,
    locationType: booking.service.serviceLocationType,
  };
}

async function loadUserDoc(
  firestore: Firestore,
  uid: string,
): Promise<Record<string, unknown> | null> {
  if (!uid) return null;
  const snapshot = await firestore.collection("users").doc(uid).get();
  return snapshot.exists ? asRecord(snapshot.data()) : null;
}

async function loadBankDoc(
  firestore: Firestore,
  providerId: string,
): Promise<Record<string, unknown> | null> {
  if (!providerId) return null;
  const snapshot = await firestore
    .collection("users")
    .doc(providerId)
    .collection("providerBankDetails")
    .doc("main")
    .get();
  return snapshot.exists ? asRecord(snapshot.data()) : null;
}

export async function loadAdminActor(
  firestore: Firestore,
  authContext: CallableRequest["auth"],
  scope: AdminScope,
): Promise<CanonicalActor> {
  const uid = authContext?.uid?.trim() ?? "";
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const snapshot = await firestore.collection("users").doc(uid).get();
  const role = asString(snapshot.data()?.adminRole) as AdminRole;
  if (!role) {
    throw new HttpsError(
      "permission-denied",
      scope === "financial" ?
        "Finance admin access required." :
        "Admin access required.",
    );
  }
  if (scope === "dispute_nonfinancial") {
    if (
      role !== "superAdmin" &&
      role !== "financeAdmin" &&
      role !== "customerSupportAdmin"
    ) {
      throw new HttpsError("permission-denied", "Admin access required.");
    }
  } else if (role !== "superAdmin" && role !== "financeAdmin") {
    throw new HttpsError("permission-denied", "Finance admin access required.");
  }
  return {
    uid,
    role,
    canViewFinancials: role === "superAdmin" || role === "financeAdmin",
  };
}

function matchesDateRange(value: unknown, dateFrom: Date | null, dateTo: Date | null): boolean {
  const candidate = asDate(value);
  if (candidate == null) return dateFrom == null && dateTo == null;
  if (dateFrom != null && candidate.getTime() < dateFrom.getTime()) return false;
  if (dateTo != null && candidate.getTime() > dateTo.getTime()) return false;
  return true;
}

async function loadCanonicalBooking(
  firestore: Firestore,
  bookingId: string,
): Promise<{
  raw: Record<string, unknown> | null;
  booking: CanonicalBookingDocumentV3 | null;
  issues: Array<{code: string; path: string}>;
}> {
  const snapshot = await firestore.collection("bookings").doc(bookingId).get();
  if (!snapshot.exists) {
    return {raw: null, booking: null, issues: []};
  }
  const raw = asRecord(snapshot.data());
  const parsed = parseCanonicalBookingDocumentV3(raw);
  return parsed.ok ?
    {raw, booking: parsed.booking, issues: []} :
    {
      raw,
      booking: null,
      issues: parsed.issues.map((issue) => ({
        code: issue.code,
        path: issue.path,
      })),
    };
}

function hasConfirmedPaymentStatus(paymentStatus: string): boolean {
  const normalized = paymentStatus.trim().toLowerCase();
  return normalized === "paid" || normalized === "confirmed";
}

function canonicalBookingNoShowDeadlineFromRaw(
  booking: CanonicalBookingDocumentV3,
): Date | null {
  if (booking.bookingType === "RANGE") {
    const schedule = booking.schedule as CanonicalRangeScheduleV3 & {serviceAnchorAt: Date};
    return schedule.checkOutDateTime;
  }
  const schedule = booking.schedule as CanonicalSlotScheduleV3 & {serviceAnchorAt: Date};
  if (schedule.firstSegmentEndAt instanceof Date) {
    return schedule.firstSegmentEndAt;
  }
  const segments = Array.isArray(schedule.segments) ?
    schedule.segments.filter((segment) => segment.endAt.getTime() > segment.startAt.getTime()) :
    [];
  if (segments.length > 0) {
    return segments[0].endAt;
  }
  return schedule.scheduledEndAt;
}

function canonicalBookingCompletionAvailableAtFromRaw(
  booking: CanonicalBookingDocumentV3,
): Date | null {
  if (booking.bookingType === "RANGE") {
    const schedule = booking.schedule as CanonicalRangeScheduleV3 & {serviceAnchorAt: Date};
    return schedule.checkOutDateTime;
  }
  const schedule = booking.schedule as CanonicalSlotScheduleV3 & {serviceAnchorAt: Date};
  if (schedule.finalEndAt instanceof Date) {
    return schedule.finalEndAt;
  }
  const segments = Array.isArray(schedule.segments) ?
    schedule.segments.filter((segment) => segment.endAt.getTime() > segment.startAt.getTime()) :
    [];
  if (segments.length > 0) {
    return segments[segments.length - 1].endAt;
  }
  return schedule.scheduledEndAt;
}

function effectiveCanonicalBookingStateForAdmin(
  booking: CanonicalBookingDocumentV3,
  disputeStatus?: string,
  now = new Date(),
): string {
  if (booking.state === "ACCEPTED_AWAITING_PAYMENT" &&
    booking.lifecycle.payDeadlineAt != null &&
    booking.lifecycle.payDeadlineAt.getTime() <= now.getTime()) {
    return "PAYMENT_EXPIRED";
  }
  const paymentConfirmed =
    booking.lifecycle.paidAt != null ||
    hasConfirmedPaymentStatus(booking.payment.status);
  const noShowDeadlineAt = canonicalBookingNoShowDeadlineFromRaw(booking);
  if (booking.state === "CONFIRMED" &&
    paymentConfirmed &&
    booking.lifecycle.otpEnteredAt == null &&
    noShowDeadlineAt != null &&
    noShowDeadlineAt.getTime() <= now.getTime()) {
    return "NO_SHOW";
  }
  const completionAvailableAt = canonicalBookingCompletionAvailableAtFromRaw(booking);
  if (booking.state === "IN_PROGRESS" &&
    completionAvailableAt != null &&
    completionAvailableAt.getTime() <= now.getTime()) {
    if (booking.lifecycle.otpEnteredAt != null) {
      return "COMPLETED_PENDING_REVIEW";
    }
    if (paymentConfirmed) {
      return "NO_SHOW";
    }
  }
  const normalizedDisputeStatus = (disputeStatus ?? booking.dispute.status)
    .trim()
    .toUpperCase();
  if ((booking.state === "COMPLETED_PENDING_REVIEW" ||
    booking.state === "COMPLETED_FINAL") &&
    normalizedDisputeStatus === "OPEN") {
    return "UNDER_DISPUTE";
  }
  if ((booking.state === "COMPLETED_PENDING_REVIEW" ||
    booking.state === "COMPLETED_FINAL") &&
    normalizedDisputeStatus === "RESOLVED") {
    return "DISPUTE_RESOLVED";
  }
  return booking.state;
}

async function findCanonicalBookingByCaseInsensitiveId(
  firestore: Firestore,
  rawSearch: string,
): Promise<{
  bookingId: string | null;
  booking: CanonicalBookingDocumentV3 | null;
  issues: Array<{code: string; path: string}>;
}> {
  const exactSearch = asString(rawSearch);
  if (!exactSearch) {
    return {bookingId: null, booking: null, issues: []};
  }

  const exact = await loadCanonicalBooking(firestore, exactSearch);
  if (exact.booking != null) {
    return {
      bookingId: exactSearch,
      booking: exact.booking,
      issues: exact.issues,
    };
  }

  const searchKey = normalizeBookingIdSearchKey(exactSearch);
  const indexedSnapshot = await firestore
    .collection("bookings")
    .where("bookingIdSearchKey", "==", searchKey)
    .limit(2)
    .get();
  if (indexedSnapshot.docs.length === 1) {
    const doc = indexedSnapshot.docs[0];
    const parsed = parseCanonicalBookingDocumentV3(asRecord(doc.data()));
    return parsed.ok ?
      {bookingId: doc.id, booking: parsed.booking, issues: []} :
      {
        bookingId: doc.id,
        booking: null,
        issues: parsed.issues.map((issue) => ({code: issue.code, path: issue.path})),
      };
  }

  const legacySnapshot = await firestore
    .collection("bookings")
    .orderBy("updatedAt", "desc")
    .limit(MAX_LIMIT * MAX_SCAN_BATCHES)
    .get();
  for (const doc of legacySnapshot.docs) {
    if (doc.id.toLowerCase() !== searchKey) {
      continue;
    }
    const parsed = parseCanonicalBookingDocumentV3(asRecord(doc.data()));
    return parsed.ok ?
      {bookingId: doc.id, booking: parsed.booking, issues: []} :
      {
        bookingId: doc.id,
        booking: null,
        issues: parsed.issues.map((issue) => ({code: issue.code, path: issue.path})),
      };
  }

  return {bookingId: null, booking: null, issues: []};
}

function bookingIdPrefixUpperBound(prefix: string): string {
  return `${prefix}\uf8ff`;
}

async function listCanonicalBookingsByPrefixForAdmin(params: {
  firestore: Firestore;
  actor: CanonicalActor;
  search: string;
  stateFilter: string;
  paymentStatusFilter: string;
  bookingTypeFilter: string;
}): Promise<Array<Record<string, unknown>>> {
  const normalizedPrefix = normalizeBookingIdSearchKey(params.search);
  if (!normalizedPrefix) {
    return [];
  }

  let query = params.firestore
    .collection("bookings")
    .where("bookingIdSearchKey", ">=", normalizedPrefix)
    .where("bookingIdSearchKey", "<", bookingIdPrefixUpperBound(normalizedPrefix))
    .orderBy("bookingIdSearchKey", "asc");

  const snapshot = await query.get();
  const summaries = await Promise.all(snapshot.docs.map(async (doc) => {
    const parsed = parseCanonicalBookingDocumentV3(asRecord(doc.data()));
    if (!parsed.ok) return null;
    const related = await loadBookingRelatedState(params.firestore, doc.id);
    const disputeStatus = canonicalDisputeStatusForAdmin({
      booking: parsed.booking,
      dispute: related.dispute,
    });
    const effectiveState = effectiveCanonicalBookingStateForAdmin(
      parsed.booking,
      disputeStatus,
    );
    if (params.stateFilter && effectiveState.toUpperCase() !== params.stateFilter) {
      return null;
    }
    if (params.paymentStatusFilter &&
      parsed.booking.payment.status.toLowerCase() !== params.paymentStatusFilter) {
      return null;
    }
    if (params.bookingTypeFilter &&
      parsed.booking.bookingType.toUpperCase() !== params.bookingTypeFilter) {
      return null;
    }
    return await buildBookingSummaryForAdmin({
      firestore: params.firestore,
      actor: params.actor,
      bookingId: doc.id,
      booking: parsed.booking,
    });
  }));

  const items = summaries.filter(Boolean) as Array<Record<string, unknown>>;
  if (items.length === 0) {
    return [];
  }

  const exactMatches = items.filter(
    (item) => normalizeBookingIdSearchKey(item.bookingId) === normalizedPrefix,
  );
  if (exactMatches.length === 1) {
    return exactMatches;
  }
  return items;
}

async function listRefundDetailsByBookingPrefix(params: {
  firestore: Firestore;
  actor: CanonicalActor;
  search: string;
  statusFilter: string;
  limit: number;
}): Promise<Array<Record<string, unknown>>> {
  const normalizedPrefix = normalizeBookingIdSearchKey(params.search);
  if (!normalizedPrefix) {
    return [];
  }

  const bookingSnapshot = await params.firestore
    .collection("bookings")
    .where("bookingIdSearchKey", ">=", normalizedPrefix)
    .where("bookingIdSearchKey", "<", bookingIdPrefixUpperBound(normalizedPrefix))
    .orderBy("bookingIdSearchKey", "asc")
    .limit(params.limit)
    .get();

  const refundDetails = await Promise.all(
    bookingSnapshot.docs.map(async (bookingDoc) => {
      const refundSnapshot = await params.firestore
        .collection("refunds")
        .doc(bookingDoc.id)
        .get();
      if (!refundSnapshot.exists) return null;
      const refund = asRecord(refundSnapshot.data());
      if (asInt(refund.schemaVersion, 0) !== 3) return null;
      if (
        params.statusFilter &&
        asString(refund.state).toLowerCase() !== params.statusFilter
      ) {
        return null;
      }
      return await getCanonicalRefundAdminDetailDataV3({
        firestore: params.firestore,
        actor: params.actor,
        bookingId: bookingDoc.id,
      });
    }),
  );

  const details = refundDetails.filter(Boolean) as Array<Record<string, unknown>>;
  if (details.length === 0) {
    return [];
  }

  const exactMatches = details.filter(
    (detail) => normalizeBookingIdSearchKey(detail.bookingId) === normalizedPrefix,
  );
  if (exactMatches.length === 1) {
    return exactMatches;
  }
  return details;
}

async function loadBookingRelatedState(
  firestore: Firestore,
  bookingId: string,
): Promise<{
  dispute: Record<string, unknown> | null;
  refund: Record<string, unknown> | null;
  payout: Record<string, unknown> | null;
  reconciliation: Record<string, unknown> | null;
  cancellation: Record<string, unknown> | null;
  noShow: Record<string, unknown> | null;
  bookingFinancial: Record<string, unknown> | null;
  providerEarning: Record<string, unknown> | null;
  payoutReadiness: Record<string, unknown> | null;
  bookingPrivate: Record<string, unknown> | null;
}> {
  const [
    disputeSnapshot,
    refundSnapshot,
    payoutSnapshot,
    reconciliationSnapshot,
    cancellationSnapshot,
    noShowSnapshot,
    bookingFinancialSnapshot,
    providerEarningSnapshot,
    payoutReadinessSnapshot,
    bookingPrivateSnapshot,
  ] = await Promise.all([
    firestore.collection("disputes").doc(bookingId).get(),
    firestore.collection("refunds").doc(bookingId).get(),
    firestore.collection(CANONICAL_PROVIDER_PAYOUTS_COLLECTION).doc(bookingId).get(),
    firestore.collection(CANONICAL_FINANCIAL_RECONCILIATION_COLLECTION).doc(bookingId).get(),
    firestore.collection(BOOKING_CANCELLATION_COLLECTION).doc(bookingId).get(),
    firestore.collection(BOOKING_NO_SHOWS_COLLECTION).doc(bookingId).get(),
    firestore.collection("bookingFinancials").doc(bookingId).get(),
    firestore.collection("providerEarnings").doc(bookingId).get(),
    firestore.collection("payoutReadiness").doc(bookingId).get(),
    firestore.collection("bookingPrivate").doc(bookingId).get(),
  ]);
  return {
    dispute: disputeSnapshot.exists ? asRecord(disputeSnapshot.data()) : null,
    refund: refundSnapshot.exists ? asRecord(refundSnapshot.data()) : null,
    payout: payoutSnapshot.exists ? asRecord(payoutSnapshot.data()) : null,
    reconciliation: reconciliationSnapshot.exists ? asRecord(reconciliationSnapshot.data()) : null,
    cancellation: cancellationSnapshot.exists ? asRecord(cancellationSnapshot.data()) : null,
    noShow: noShowSnapshot.exists ? asRecord(noShowSnapshot.data()) : null,
    bookingFinancial:
      bookingFinancialSnapshot.exists ? asRecord(bookingFinancialSnapshot.data()) : null,
    providerEarning:
      providerEarningSnapshot.exists ? asRecord(providerEarningSnapshot.data()) : null,
    payoutReadiness:
      payoutReadinessSnapshot.exists ? asRecord(payoutReadinessSnapshot.data()) : null,
    bookingPrivate:
      bookingPrivateSnapshot.exists ? asRecord(bookingPrivateSnapshot.data()) : null,
  };
}

function canonicalDisputeStatusForAdmin(params: {
  booking: CanonicalBookingDocumentV3;
  dispute: Record<string, unknown> | null;
}): string {
  const canonicalStatus = asString(params.dispute?.status);
  if (canonicalStatus) {
    return canonicalStatus;
  }
  return params.booking.dispute.status;
}

function canonicalDisputeResolutionTypeForAdmin(params: {
  booking: CanonicalBookingDocumentV3;
  dispute: Record<string, unknown> | null;
}): string {
  const disputeResolution = asRecord(params.dispute?.resolution);
  const canonicalResolutionType = asString(disputeResolution.type);
  if (canonicalResolutionType) {
    return canonicalResolutionType;
  }
  return params.booking.dispute.resolution;
}

function canonicalDisputeRaisedAtForAdmin(params: {
  booking: CanonicalBookingDocumentV3;
  dispute: Record<string, unknown> | null;
}): Date | null {
  return asDate(params.dispute?.createdAt) ?? params.booking.dispute.raisedAt;
}

function canonicalDisputeResolvedAtForAdmin(params: {
  booking: CanonicalBookingDocumentV3;
  dispute: Record<string, unknown> | null;
}): Date | null {
  return asDate(params.dispute?.resolvedAt) ?? params.booking.dispute.resolvedAt;
}

async function loadLedgerSummary(
  firestore: Firestore,
  bookingId: string,
): Promise<{
  entries: Record<string, unknown>[];
  totals: LedgerTotals;
}> {
  const snapshot = await firestore
    .collection(CANONICAL_FINANCIAL_LEDGER_COLLECTION)
    .where("bookingId", "==", bookingId)
    .get();
  const entries: Record<string, unknown>[] = snapshot.docs.map((doc) => ({
    entryId: doc.id,
    ...asRecord(doc.data()),
  }));
  const totals = entries.reduce<LedgerTotals>((aggregate, entry) => {
    const amountPaise = asInt(entry.amountPaise, 0);
    switch (asString(entry.type)) {
    case "PAYMENT_CAPTURED":
      aggregate.paymentCapturedPaise += amountPaise;
      break;
    case "CUSTOMER_REFUND":
      aggregate.refundPaise += amountPaise;
      break;
    case "PROVIDER_PAYOUT":
      aggregate.payoutPaise += amountPaise;
      break;
    case "PLATFORM_REVENUE":
      aggregate.platformRevenuePaise += amountPaise;
      break;
    default:
      break;
    }
    aggregate.count += 1;
    return aggregate;
  }, {
    count: 0,
    paymentCapturedPaise: 0,
    refundPaise: 0,
    payoutPaise: 0,
    platformRevenuePaise: 0,
  });
  return {entries, totals};
}

async function loadBookingEvents(
  firestore: Firestore,
  bookingId: string,
  limit = 100,
): Promise<Record<string, unknown>[]> {
  const snapshot = await firestore
    .collection("bookings")
    .doc(bookingId)
    .collection("events")
    .limit(Math.max(limit, 1))
    .get();
  const entries: Array<Record<string, unknown> & {eventId: string}> = snapshot.docs
    .map((doc) => ({eventId: doc.id, ...asRecord(doc.data())}))
    .sort((
      left: Record<string, unknown> & {eventId: string},
      right: Record<string, unknown> & {eventId: string},
    ) => {
      const leftAt = asDate(left.at)?.getTime() ?? 0;
      const rightAt = asDate(right.at)?.getTime() ?? 0;
      return leftAt - rightAt;
    });
  return entries;
}

function evidenceMetadataFromPaths(params: {
  paths: string[];
  raisedAt: unknown;
  defaultRole: string;
}): Array<Record<string, unknown>> {
  return params.paths.map((path, index) => ({
    evidenceId: `${index + 1}`,
    uploaderRole: params.defaultRole || "customer",
    fileName: fileNameFromPath(path),
    contentType: contentTypeFromPath(path),
    sizeBytes: null,
    submittedAt: iso(params.raisedAt),
    storagePath: path,
    secureRetrievalRequired: true,
  }));
}

async function loadCanonicalDisputeEvidenceMetadata(params: {
  firestore: Firestore;
  disputeId: string;
  fallbackPaths: string[];
  raisedAt: unknown;
  defaultRole: string;
}): Promise<Array<Record<string, unknown>>> {
  const snapshot = await params.firestore
    .collection("disputes")
    .doc(params.disputeId)
    .collection("evidence")
    .get();
  if (snapshot.docs.length === 0) {
    return evidenceMetadataFromPaths({
      paths: params.fallbackPaths,
      raisedAt: params.raisedAt,
      defaultRole: params.defaultRole,
    });
  }
  const entries: Array<Record<string, unknown>> = snapshot.docs
    .map((doc) => ({evidenceId: doc.id, ...asRecord(doc.data())}));
  return entries
    .sort((left, right) =>
      (asDate(left.createdAt)?.getTime() ?? 0) -
      (asDate(right.createdAt)?.getTime() ?? 0))
    .map((entry, index) => ({
      evidenceId: asString(entry.evidenceId) || `${index + 1}`,
      uploaderRole: asString(entry.uploadedByRole) || params.defaultRole || "customer",
      fileName: fileNameFromPath(asString(entry.storagePath)),
      contentType: asString(entry.mimeType) || contentTypeFromPath(asString(entry.storagePath)),
      sizeBytes: asInt(entry.sizeBytes, 0) || null,
      submittedAt: iso(entry.createdAt) ?? iso(params.raisedAt),
      storagePath: asString(entry.storagePath),
      width: asInt(entry.width, 0) || null,
      height: asInt(entry.height, 0) || null,
      secureRetrievalRequired: true,
    }));
}

function buildAdminActionMatrix(params: {
  actor: CanonicalActor;
  booking: CanonicalBookingDocumentV3 | null;
  dispute: Record<string, unknown> | null;
  payout: Record<string, unknown> | null;
}): Record<string, boolean> {
  const disputeStatus = asString(params.dispute?.status).toUpperCase();
  const payoutStatus = asString(params.payout?.status).toUpperCase();
  return {
    canResolveDispute:
      params.actor.canViewFinancials && disputeStatus === "OPEN",
    canRetryPayout:
      params.actor.canViewFinancials &&
      (payoutStatus === "FAILED" || payoutStatus === "READY") &&
      !CANONICAL_PROVIDER_PAYOUTS_LIVE_ENABLED,
    canRunReconciliation: params.actor.canViewFinancials,
    canViewLedger: params.actor.canViewFinancials,
    canViewEvidence: true,
    canViewFinancials: params.actor.canViewFinancials,
    canViewPrivateIdentity:
      params.actor.role === "superAdmin" || params.actor.role === "financeAdmin",
    canViewBooking:
      params.booking != null,
  };
}

async function buildDisputeSummaryForAdmin(params: {
  firestore: Firestore;
  actor: CanonicalActor;
  disputeId: string;
  dispute: Record<string, unknown>;
}): Promise<CanonicalDisputeSummaryForAdmin | null> {
  const bookingId = asString(params.dispute.bookingId);
  if (!bookingId) return null;
  const bookingState = await loadCanonicalBooking(params.firestore, bookingId);
  if (bookingState.booking == null) return null;
  const related = await loadBookingRelatedState(params.firestore, bookingId);
  const customerUser = await loadUserDoc(params.firestore, bookingState.booking.parentId);
  const providerBank = await loadBankDoc(params.firestore, bookingState.booking.providerId);
  return {
    disputeId: params.disputeId,
    bookingId,
    status: asString(params.dispute.status),
    reasonCode: asString(params.dispute.reasonCode) || asString(params.dispute.reason),
    raisedAt: iso(params.dispute.createdAt) ??
      bookingState.booking.dispute.raisedAt?.toISOString() ??
      null,
    raisedByRole:
      asString(params.dispute.raisedBy) ||
      bookingState.booking.dispute.raisedBy ||
      "customer",
    raisedByMaskedIdentity: buildRaisedByMaskedIdentity({
      booking: bookingState.booking,
      dispute: params.dispute,
    }),
    customer: customerSummaryFromBooking(bookingState.booking, customerUser),
    provider: providerSummaryFromBooking({
      booking: bookingState.booking,
      bank: providerBank,
    }),
    service: serviceSummaryFromBooking(bookingState.booking),
    disputedAmountPaise:
      params.actor.canViewFinancials ?
        bookingState.booking.financials?.customerPaidPaise ?? 0 :
        null,
    paymentStatus:
      params.actor.canViewFinancials ? bookingState.booking.payment.status : null,
    refundStatus:
      params.actor.canViewFinancials ?
        (asString(related.refund?.state) || bookingState.booking.payment.status || null) :
        null,
    payoutStatus:
      params.actor.canViewFinancials ?
        (asString(related.payout?.status) || bookingState.booking.payout.status || null) :
        null,
    evidenceCount:
      asInt(params.dispute.evidenceCount, 0) ||
      asArray(params.dispute.attachmentPaths).length ||
      asArray(params.dispute.attachments).length ||
      bookingState.booking.dispute.evidenceRefs.length,
    adminActionRequired:
      asString(params.dispute.status).toUpperCase() === "OPEN",
    lastActivityAt:
      iso(params.dispute.updatedAt) ??
      bookingState.booking.updatedAt.toISOString(),
  };
}

async function queryCursorBatch(params: {
  query:
    FirebaseFirestore.Query<FirebaseFirestore.DocumentData>;
  limit: number;
  cursor: CursorPayload | null;
  sortField: string;
}) {
  const batchLimit = Math.max(params.limit * MAX_BATCH_MULTIPLIER, params.limit);
  let query = params.query
    .orderBy(params.sortField, "desc")
    .orderBy(FieldPath.documentId(), "desc")
    .limit(batchLimit);
  if (params.cursor != null) {
    query = query.startAfter(new Date(params.cursor.sortValue), params.cursor.docId);
  }
  return await query.get();
}

async function collectFilteredPage<T>(params: {
  baseQuery: FirebaseFirestore.Query<FirebaseFirestore.DocumentData>;
  sortField: string;
  limit: number;
  cursor: CursorPayload | null;
  filter: (
    doc: FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>,
  ) => Promise<boolean>;
  map: (
    doc: FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>,
  ) => Promise<T | null>;
}): Promise<{items: T[]; nextCursor: string | null}> {
  const items: T[] = [];
  let cursor = params.cursor;
  let rawLastCursor: CursorPayload | null = null;
  for (let batchIndex = 0; batchIndex < MAX_SCAN_BATCHES; batchIndex += 1) {
    const snapshot = await queryCursorBatch({
      query: params.baseQuery,
      sortField: params.sortField,
      limit: params.limit,
      cursor,
    });
    if (snapshot.empty) {
      return {items, nextCursor: null};
    }
    for (const doc of snapshot.docs) {
      rawLastCursor = {
        sortValue: (asDate(doc.get(params.sortField)) ?? new Date(0)).toISOString(),
        docId: doc.id,
      };
      if (!(await params.filter(doc))) {
        continue;
      }
      const mapped = await params.map(doc);
      if (mapped != null) {
        items.push(mapped);
      }
      if (items.length >= params.limit) {
        return {items, nextCursor: encodeCursor(rawLastCursor)};
      }
    }
    cursor = rawLastCursor;
    if (snapshot.docs.length < Math.max(params.limit * MAX_BATCH_MULTIPLIER, params.limit)) {
      break;
    }
  }
  return {items, nextCursor: encodeCursor(rawLastCursor)};
}

function ensureSearchNoCursor(input: CanonicalListInput): void {
  if (input.search && input.cursor) {
    throw new HttpsError("invalid-argument", "cursor cannot be combined with search.");
  }
}

export async function listCanonicalDisputesForAdminDataV3(params: {
  firestore: Firestore;
  actor: CanonicalActor;
  input: CanonicalListInput;
}) {
  ensureSearchNoCursor(params.input);
  const limit = clampLimit(params.input.limit);
  const cursor = decodeCursor(params.input.cursor);
  const status = asString(params.input.status).toUpperCase();
  const roleFilter = asString(params.input.role).toLowerCase();
  const dateFrom = ensureDateInput(params.input.dateFrom, "dateFrom");
  const dateTo = ensureDateInput(params.input.dateTo, "dateTo");
  const search = normalizeSearch(params.input.search);

  if (search) {
    const results = new Map<string, CanonicalDisputeSummaryForAdmin>();
    const exactPromise = params.firestore.collection("disputes").doc(search).get();
    const queryPromises = [
      params.firestore.collection("disputes").where("bookingId", "==", search).limit(limit).get(),
      params.firestore.collection("disputes").where("providerId", "==", search).limit(limit).get(),
      params.firestore.collection("disputes").where("parentId", "==", search).limit(limit).get(),
      params.firestore.collection("disputes").where("customerId", "==", search).limit(limit).get(),
    ];
    const [exactSnapshot, ...querySnapshots] = await Promise.all([exactPromise, ...queryPromises]);
    const docs: FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>[] = [];
    if (exactSnapshot.exists) {
      docs.push(exactSnapshot as FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>);
    }
    for (const snapshot of querySnapshots) {
      if ("docs" in snapshot) docs.push(...snapshot.docs);
    }
    for (const doc of docs) {
      const data = asRecord(doc.data());
      if (asString(data.source) !== "canonical_v3") continue;
      const summary = await buildDisputeSummaryForAdmin({
        firestore: params.firestore,
        actor: params.actor,
        disputeId: doc.id,
        dispute: data,
      });
      if (summary == null) continue;
      if (status && summary.status.toUpperCase() !== status) continue;
      if (roleFilter && summary.raisedByRole.toLowerCase() !== roleFilter) continue;
      if (!matchesDateRange(summary.raisedAt, dateFrom, dateTo)) continue;
      results.set(summary.disputeId, summary);
    }
    return {
      items: [...results.values()].sort((left, right) =>
        (asDate(right.lastActivityAt)?.getTime() ?? 0) -
        (asDate(left.lastActivityAt)?.getTime() ?? 0)).slice(0, limit),
      nextCursor: null,
    };
  }

  const baseQuery = params.firestore.collection("disputes");
  return await collectFilteredPage({
    baseQuery,
    sortField: "updatedAt",
    limit,
    cursor,
    filter: async (doc) => {
      const data = asRecord(doc.data());
      if (asString(data.source) !== "canonical_v3") return false;
      if (status && asString(data.status).toUpperCase() !== status) return false;
      if (roleFilter) {
        const raisedByRole =
          asString(data.raisedBy) ||
          asString(asRecord(data.resolution).raisedBy) ||
          "customer";
        if (raisedByRole.toLowerCase() !== roleFilter) return false;
      }
      return matchesDateRange(data.createdAt, dateFrom, dateTo);
    },
    map: async (doc) => await buildDisputeSummaryForAdmin({
      firestore: params.firestore,
      actor: params.actor,
      disputeId: doc.id,
      dispute: asRecord(doc.data()),
    }),
  });
}

export async function getCanonicalDisputeAdminDetailDataV3(params: {
  firestore: Firestore;
  actor: CanonicalActor;
  disputeId: string;
}) {
  const disputeSnapshot = await params.firestore.collection("disputes").doc(params.disputeId).get();
  if (!disputeSnapshot.exists) {
    throw new HttpsError("not-found", "Dispute not found.");
  }
  const dispute = asRecord(disputeSnapshot.data());
  if (asString(dispute.source) !== "canonical_v3") {
    throw new HttpsError("not-found", "Canonical dispute not found.");
  }
  const bookingId = asString(dispute.bookingId);
  const bookingState = await loadCanonicalBooking(params.firestore, bookingId);
  if (bookingState.booking == null) {
    throw new HttpsError("failed-precondition", "Canonical booking document is incomplete.", {
      code: "INVALID_CANONICAL_BOOKING_DOCUMENT",
      issues: bookingState.issues,
    });
  }
  const related = await loadBookingRelatedState(params.firestore, bookingId);
  const [customerUser, providerBank, ledger, statusHistory] = await Promise.all([
    loadUserDoc(params.firestore, bookingState.booking.parentId),
    loadBankDoc(params.firestore, bookingState.booking.providerId),
    loadLedgerSummary(params.firestore, bookingId),
    loadBookingEvents(params.firestore, bookingId),
  ]);
  const providerBaseEntitlementPaise = asInt(
    related.payout?.providerEntitlementPaise,
    bookingState.booking.financials?.providerPayoutPaise ?? 0,
  );
  const providerAlreadyPaidPaise = asInt(related.payout?.priorPaidPaise, 0);
  const alreadyRefundedPaise = asInt(related.refund?.refundAmountPaise, 0);
  const currentPettxoRetainedPaise = asInt(
    related.payout?.pettxoRetainedPaise,
    Math.max(
      (bookingState.booking.financials?.customerPaidPaise ?? 0) -
        providerBaseEntitlementPaise,
      0,
    ),
  );
  const evidencePaths = asArray(dispute.attachmentPaths).length > 0 ?
    asArray(dispute.attachmentPaths).map((value) => asString(value)).filter(Boolean) :
    asArray(dispute.attachments).map((value) => asString(value)).filter(Boolean);
  const defaultRole =
    asString(dispute.raisedBy) ||
    bookingState.booking.dispute.raisedBy ||
    "customer";
  const evidence = await loadCanonicalDisputeEvidenceMetadata({
    firestore: params.firestore,
    disputeId: params.disputeId,
    fallbackPaths: evidencePaths,
    raisedAt: dispute.createdAt,
    defaultRole,
  });
  const summary = await buildDisputeSummaryForAdmin({
    firestore: params.firestore,
    actor: params.actor,
    disputeId: params.disputeId,
    dispute,
  });
  const disputeStatus = canonicalDisputeStatusForAdmin({
    booking: bookingState.booking,
    dispute,
  });
  return {
    disputeId: params.disputeId,
    canonicalRecord: {
      ...dispute,
      createdAt: iso(dispute.createdAt),
      updatedAt: iso(dispute.updatedAt),
      resolvedAt: iso(dispute.resolvedAt),
    },
    bookingSummary: summary == null ? null : {
      bookingId,
      state: bookingState.booking.state,
      bookingType: bookingState.booking.bookingType,
      paymentStatus: bookingState.booking.payment.status,
      disputeStatus,
      payoutStatus: bookingState.booking.payout.status,
      schedule: serviceSummaryFromBooking(bookingState.booking),
    },
    serviceSummary: serviceSummaryFromBooking(bookingState.booking),
    customer: customerSummaryFromBooking(bookingState.booking, customerUser),
    provider: providerSummaryFromBooking({
      booking: bookingState.booking,
      bank: providerBank,
    }),
    raisedByRole: defaultRole,
    raisedByMaskedIdentity: buildRaisedByMaskedIdentity({
      booking: bookingState.booking,
      dispute,
    }),
    disputeTimeline: statusHistory.map((event) => ({
      eventId: asString(event.eventId),
      event: asString(event.event),
      actor: asString(event.actor),
      at: iso(event.at),
      meta: asRecord(event.meta),
    })),
    messages: [],
    evidence,
    financialSnapshot: params.actor.canViewFinancials ? {
      bookingFinancial: related.bookingFinancial,
      bookingFinancialPolicyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
      immutableSnapshot: bookingState.booking.financials,
      disputeFinancialContext: {
        currency: bookingState.booking.financials?.currency ?? "INR",
        customerPaidPaise: bookingState.booking.financials?.customerPaidPaise ?? 0,
        alreadyRefundedPaise,
        providerBaseEntitlementPaise,
        providerAlreadyPaidPaise,
        providerRemainingPayablePaise: Math.max(
          providerBaseEntitlementPaise - providerAlreadyPaidPaise,
          0,
        ),
        currentPettxoRetainedPaise,
        canonicalPlatformCommissionPaise:
          bookingState.booking.financials?.platformCommissionPaise ?? 0,
        pettxoCouponFundingPaise:
          bookingState.booking.financials?.pettxoCouponFundingPaise ?? 0,
        currentResolution: asRecord(dispute.resolution),
      },
    } : null,
    cancellationContext: related.cancellation,
    noShowContext: related.noShow,
    refundState: params.actor.canViewFinancials ? related.refund : null,
    payoutState: params.actor.canViewFinancials ? related.payout : null,
    ledgerSummary: params.actor.canViewFinancials ? ledger : null,
    reconciliationSummary: params.actor.canViewFinancials ? related.reconciliation : null,
    permittedAdminActions: buildAdminActionMatrix({
      actor: params.actor,
      booking: bookingState.booking,
      dispute,
      payout: related.payout,
    }),
    resolutionHistory: [asRecord(dispute.resolution)].filter((entry) => Object.keys(entry).length > 0),
    auditReferences: {
      auditEntryId: asString(dispute.auditEntryId),
      disputeResolutionDocId: params.disputeId,
      adminAuditLogId: asString(dispute.auditEntryId),
    },
  };
}

async function buildBookingSummaryForAdmin(params: {
  firestore: Firestore;
  actor: CanonicalActor;
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
}): Promise<Record<string, unknown>> {
  const related = await loadBookingRelatedState(params.firestore, params.bookingId);
  const [customerUser, providerBank] = await Promise.all([
    loadUserDoc(params.firestore, params.booking.parentId),
    loadBankDoc(params.firestore, params.booking.providerId),
  ]);
  const disputeStatus = canonicalDisputeStatusForAdmin({
    booking: params.booking,
    dispute: related.dispute,
  });
  const effectiveState = effectiveCanonicalBookingStateForAdmin(
    params.booking,
    disputeStatus,
  );
  return {
    bookingId: params.bookingId,
    state: effectiveState,
    storedState: params.booking.state,
    paymentStatus:
      params.actor.canViewFinancials ? params.booking.payment.status : null,
    bookingType: params.booking.bookingType,
    customer: customerSummaryFromBooking(params.booking, customerUser),
    provider: providerSummaryFromBooking({booking: params.booking, bank: providerBank}),
    service: serviceSummaryFromBooking(params.booking),
    disputeStatus,
    disputeResolutionType: canonicalDisputeResolutionTypeForAdmin({
      booking: params.booking,
      dispute: related.dispute,
    }),
    disputeCreatedAt: iso(canonicalDisputeRaisedAtForAdmin({
      booking: params.booking,
      dispute: related.dispute,
    })),
    disputeResolvedAt: iso(canonicalDisputeResolvedAtForAdmin({
      booking: params.booking,
      dispute: related.dispute,
    })),
    payoutStatus:
      params.actor.canViewFinancials ?
        (asString(related.payout?.status) || params.booking.payout.status) :
        null,
    refundStatus:
      params.actor.canViewFinancials ?
        (asString(related.refund?.state) || null) :
        null,
    updatedAt: params.booking.updatedAt.toISOString(),
    createdAt: params.booking.createdAt.toISOString(),
  };
}

export async function listCanonicalBookingsForAdminDataV3(params: {
  firestore: Firestore;
  actor: CanonicalActor;
  input: CanonicalListInput;
}) {
  ensureSearchNoCursor(params.input);
  const limit = clampLimit(params.input.limit);
  const cursor = decodeCursor(params.input.cursor);
  const stateFilter = asString(params.input.status).toUpperCase();
  const paymentStatusFilter = asString(params.input.paymentStatus).toLowerCase();
  const disputeStatusFilter = asString(params.input.disputeStatus).toUpperCase();
  const payoutStatusFilter = asString(params.input.payoutStatus).toUpperCase();
  const bookingTypeFilter = asString(params.input.bookingType).toUpperCase();
  const dateFrom = ensureDateInput(params.input.dateFrom, "dateFrom");
  const dateTo = ensureDateInput(params.input.dateTo, "dateTo");
  const search = normalizeSearch(params.input.search);

  if (search) {
    const prefixed = await listCanonicalBookingsByPrefixForAdmin({
      firestore: params.firestore,
      actor: params.actor,
      search,
      stateFilter,
      paymentStatusFilter,
      bookingTypeFilter,
    });
    if (prefixed.length > 0) {
      return {
        items: prefixed,
        nextCursor: null,
      };
    }

    const exact = await findCanonicalBookingByCaseInsensitiveId(
      params.firestore,
      search,
    );
    if (exact.booking != null && exact.bookingId != null) {
      const summary = await buildBookingSummaryForAdmin({
        firestore: params.firestore,
        actor: params.actor,
        bookingId: exact.bookingId,
        booking: exact.booking,
      });
      const effectiveState = asString(summary.state).toUpperCase();
      const paymentStatus = asString(summary.paymentStatus).toLowerCase();
      const bookingType = asString(summary.bookingType).toUpperCase();
      if (stateFilter && effectiveState !== stateFilter) {
        return {items: [], nextCursor: null};
      }
      if (paymentStatusFilter && paymentStatus !== paymentStatusFilter) {
        return {items: [], nextCursor: null};
      }
      if (bookingTypeFilter && bookingType !== bookingTypeFilter) {
        return {items: [], nextCursor: null};
      }
      return {
        items: [summary],
        nextCursor: null,
      };
    }
    return {items: [], nextCursor: null};
  }

  const baseQuery = params.firestore.collection("bookings");
  return await collectFilteredPage({
    baseQuery,
    sortField: "updatedAt",
    limit,
    cursor,
    filter: async (doc) => {
      const parsed = parseCanonicalBookingDocumentV3(asRecord(doc.data()));
      if (!parsed.ok) return false;
      const booking = parsed.booking;
      const related = await loadBookingRelatedState(params.firestore, doc.id);
      const disputeStatus = canonicalDisputeStatusForAdmin({
        booking,
        dispute: related.dispute,
      });
      const effectiveState = effectiveCanonicalBookingStateForAdmin(
        booking,
        disputeStatus,
      );
      if (stateFilter && effectiveState.toUpperCase() !== stateFilter) return false;
      if (paymentStatusFilter &&
        booking.payment.status.toLowerCase() !== paymentStatusFilter) return false;
      if (disputeStatusFilter &&
        disputeStatus.toUpperCase() !== disputeStatusFilter) return false;
      if (bookingTypeFilter &&
        booking.bookingType.toUpperCase() !== bookingTypeFilter) return false;
      if (!matchesDateRange(booking.serviceAnchorAt, dateFrom, dateTo)) return false;
      if (!payoutStatusFilter) return true;
      return booking.payout.status.toUpperCase() === payoutStatusFilter;
    },
    map: async (doc) => {
      const parsed = parseCanonicalBookingDocumentV3(asRecord(doc.data()));
      if (!parsed.ok) return null;
      return await buildBookingSummaryForAdmin({
        firestore: params.firestore,
        actor: params.actor,
        bookingId: doc.id,
        booking: parsed.booking,
      });
    },
  });
}

export async function getCanonicalBookingAdminDetailDataV3(params: {
  firestore: Firestore;
  actor: CanonicalActor;
  bookingId: string;
}) {
  const bookingState = await findCanonicalBookingByCaseInsensitiveId(
    params.firestore,
    params.bookingId,
  );
  if (bookingState.booking == null || bookingState.bookingId == null) {
    throw new HttpsError("not-found", "Canonical booking not found.", {
      issues: bookingState.issues,
    });
  }
  const [related, customerUser, providerBank, ledger, statusHistory] = await Promise.all([
    loadBookingRelatedState(params.firestore, bookingState.bookingId),
    loadUserDoc(params.firestore, bookingState.booking.parentId),
    loadBankDoc(params.firestore, bookingState.booking.providerId),
    loadLedgerSummary(params.firestore, bookingState.bookingId),
    loadBookingEvents(params.firestore, bookingState.bookingId),
  ]);
  const disputeStatus = canonicalDisputeStatusForAdmin({
    booking: bookingState.booking,
    dispute: related.dispute,
  });
  const effectiveState = effectiveCanonicalBookingStateForAdmin(
    bookingState.booking,
    disputeStatus,
  );
  return {
    bookingId: bookingState.bookingId,
    canonicalState: bookingState.booking.state,
    storedState: bookingState.booking.state,
    effectiveState,
    effectiveBookingStatus: effectiveState,
    paymentState: bookingState.booking.payment.status,
    bookingType: bookingState.booking.bookingType,
    customer: customerSummaryFromBooking(bookingState.booking, customerUser),
    provider: providerSummaryFromBooking({
      booking: bookingState.booking,
      bank: providerBank,
    }),
    service: serviceSummaryFromBooking(bookingState.booking),
    lifecycleTimestamps: {
      requestedAt: iso(bookingState.booking.lifecycle.requestedAt),
      timerStartsAt: iso(bookingState.booking.lifecycle.timerStartsAt),
      acceptDeadlineAt: iso(bookingState.booking.lifecycle.acceptDeadlineAt),
      respondedAt: iso(bookingState.booking.lifecycle.respondedAt),
      payDeadlineAt: iso(bookingState.booking.lifecycle.payDeadlineAt),
      paidAt: iso(bookingState.booking.lifecycle.paidAt),
      otpGeneratedAt: iso(bookingState.booking.lifecycle.otpGeneratedAt),
      otpEnteredAt: iso(bookingState.booking.lifecycle.otpEnteredAt),
      noShowAt: iso(bookingState.booking.lifecycle.noShowAt),
      serviceEndedAt: iso(bookingState.booking.lifecycle.serviceEndedAt),
      disputeDeadlineAt: iso(bookingState.booking.lifecycle.disputeDeadlineAt),
      completedAt: iso(bookingState.booking.lifecycle.completedAt),
      reviewWindowEndsAt: iso(bookingState.booking.lifecycle.reviewWindowEndsAt),
      finalizedAt: iso(bookingState.booking.lifecycle.finalizedAt),
      cancelledAt: iso(bookingState.booking.lifecycle.cancelledAt),
    },
    pricingBreakdown: params.actor.canViewFinancials ? {
      immutableFinancialSnapshot: bookingState.booking.financials,
      bookingFinancial: related.bookingFinancial,
      providerEarning: related.providerEarning,
      payoutReadiness: related.payoutReadiness,
    } : null,
    couponFunding: params.actor.canViewFinancials ? {
      couponDiscountPaise:
        bookingState.booking.financials?.couponDiscountPaise ?? 0,
      couponFundedPaise:
        bookingState.booking.financials?.pettxoCouponFundingPaise ?? 0,
    } : null,
    platformFeePaise:
      params.actor.canViewFinancials ?
        bookingState.booking.financials?.platformCommissionPaise ?? 0 :
        null,
    providerAmountPaise:
      params.actor.canViewFinancials ?
        bookingState.booking.financials?.providerPayoutPaise ?? 0 :
        null,
    cancellation: related.cancellation,
    noShow: related.noShow,
    refund: params.actor.canViewFinancials ? related.refund : null,
    payout: params.actor.canViewFinancials ? related.payout : null,
    dispute: {
      ...bookingState.booking.dispute,
      status: disputeStatus,
      raisedAt:
        canonicalDisputeRaisedAtForAdmin({
          booking: bookingState.booking,
          dispute: related.dispute,
        })?.toISOString() ?? null,
      resolvedAt:
        canonicalDisputeResolvedAtForAdmin({
          booking: bookingState.booking,
          dispute: related.dispute,
        })?.toISOString() ?? null,
      resolution: canonicalDisputeResolutionTypeForAdmin({
        booking: bookingState.booking,
        dispute: related.dispute,
      }),
    },
    ledgerSummary: params.actor.canViewFinancials ? ledger : null,
    reconciliation: params.actor.canViewFinancials ? related.reconciliation : null,
    statusHistory: statusHistory.map((entry) => ({
      eventId: asString(entry.eventId),
      event: asString(entry.event),
      actor: asString(entry.actor),
      at: iso(entry.at),
      meta: asRecord(entry.meta),
    })),
    permittedAdminActions: buildAdminActionMatrix({
      actor: params.actor,
      booking: bookingState.booking,
      dispute:
        (related.dispute ??
          bookingState.booking.dispute as unknown as Record<string, unknown>),
      payout: related.payout,
    }),
  };
}

export async function listCanonicalProviderPayoutsForAdminDataV3(params: {
  firestore: Firestore;
  actor: CanonicalActor;
  input: CanonicalListInput;
}) {
  ensureSearchNoCursor(params.input);
  const limit = clampLimit(params.input.limit);
  const cursor = decodeCursor(params.input.cursor);
  const statusFilter = asString(params.input.status).toUpperCase();
  const failureCodeFilter = asString(params.input.failureCode).toUpperCase();
  const failedOnly = asBool(params.input.failedOnly);
  const retryableOnly = asBool(params.input.retryableOnly);
  const dateFrom = ensureDateInput(params.input.dateFrom, "dateFrom");
  const dateTo = ensureDateInput(params.input.dateTo, "dateTo");
  const search = normalizeSearch(params.input.search);

  if (search) {
    const targeted = new Map<string, Record<string, unknown>>();
    const [exact, byProvider] = await Promise.all([
      params.firestore.collection(CANONICAL_PROVIDER_PAYOUTS_COLLECTION).doc(search).get(),
      params.firestore.collection(CANONICAL_PROVIDER_PAYOUTS_COLLECTION).where("providerId", "==", search).limit(limit).get(),
    ]);
    if (exact.exists) targeted.set(exact.id, asRecord(exact.data()));
    for (const doc of byProvider.docs) targeted.set(doc.id, asRecord(doc.data()));
    const items = await Promise.all([...targeted.entries()].map(async ([docId, payout]) => {
      const bookingState = await loadCanonicalBooking(params.firestore, asString(payout.bookingId) || docId);
      if (bookingState.booking == null) return null;
      const [bank, related] = await Promise.all([
        loadBankDoc(params.firestore, bookingState.booking.providerId),
        loadBookingRelatedState(params.firestore, asString(payout.bookingId) || docId),
      ]);
      return {
        payoutId: docId,
        bookingId: asString(payout.bookingId) || docId,
        providerId: bookingState.booking.providerId,
        provider: providerSummaryFromBooking({booking: bookingState.booking, bank}),
        service: serviceSummaryFromBooking(bookingState.booking),
        status: asString(payout.status),
        failureCode: asString(payout.failureCode),
        retryCount: asInt(payout.retryCount, 0),
        nextRetryAt: iso(payout.nextRetryAt),
        eligibleAt: iso(payout.eligibleAt),
        payoutAmountPaise: asInt(payout.remainingPayablePaise, 0),
        holdReason: asString(payout.holdReason),
        bankReadiness: asString(bank?.status) || "unknown",
        providerEarningsSummary: related.providerEarning,
        disputeBlocker: canonicalDisputeStatusForAdmin({
          booking: bookingState.booking,
          dispute: related.dispute,
        }).toUpperCase() === "OPEN",
        refundBlocker:
          ["required", "submitted", "pending"].includes(asString(related.refund?.state).toLowerCase()),
        reconciliationStatus:
          asString(related.reconciliation?.status),
        livePayoutEnabled: CANONICAL_PROVIDER_PAYOUTS_LIVE_ENABLED,
      };
    }));
    return {items: items.filter(Boolean), nextCursor: null, livePayoutEnabled: CANONICAL_PROVIDER_PAYOUTS_LIVE_ENABLED};
  }

  const baseQuery = params.firestore.collection(CANONICAL_PROVIDER_PAYOUTS_COLLECTION);
  const page = await collectFilteredPage({
    baseQuery,
    sortField: "updatedAt",
    limit,
    cursor,
    filter: async (doc) => {
      const payout = asRecord(doc.data());
      const status = asString(payout.status).toUpperCase();
      if (statusFilter && status !== statusFilter) return false;
      if (failedOnly && status !== "FAILED") return false;
      if (retryableOnly && asDate(payout.nextRetryAt) == null) return false;
      if (failureCodeFilter &&
        asString(payout.failureCode).toUpperCase() !== failureCodeFilter) return false;
      return matchesDateRange(payout.eligibleAt, dateFrom, dateTo);
    },
    map: async (doc) => {
      const payout = asRecord(doc.data());
      const bookingId = asString(payout.bookingId) || doc.id;
      const bookingState = await loadCanonicalBooking(params.firestore, bookingId);
      if (bookingState.booking == null) return null;
      const [bank, related] = await Promise.all([
        loadBankDoc(params.firestore, bookingState.booking.providerId),
        loadBookingRelatedState(params.firestore, bookingId),
      ]);
      return {
        payoutId: doc.id,
        bookingId,
        providerId: bookingState.booking.providerId,
        provider: providerSummaryFromBooking({booking: bookingState.booking, bank}),
        service: serviceSummaryFromBooking(bookingState.booking),
        status: asString(payout.status),
        failureCode: asString(payout.failureCode),
        retryCount: asInt(payout.retryCount, 0),
        nextRetryAt: iso(payout.nextRetryAt),
        eligibleAt: iso(payout.eligibleAt),
        payoutAmountPaise: asInt(payout.remainingPayablePaise, 0),
        holdReason: asString(payout.holdReason),
        bankReadiness: asString(bank?.status) || "unknown",
        providerEarningsSummary: related.providerEarning,
        disputeBlocker: canonicalDisputeStatusForAdmin({
          booking: bookingState.booking,
          dispute: related.dispute,
        }).toUpperCase() === "OPEN",
        refundBlocker:
          ["required", "submitted", "pending"].includes(asString(related.refund?.state).toLowerCase()),
        reconciliationStatus: asString(related.reconciliation?.status),
        livePayoutEnabled: CANONICAL_PROVIDER_PAYOUTS_LIVE_ENABLED,
      };
    },
  });
  return {...page, livePayoutEnabled: CANONICAL_PROVIDER_PAYOUTS_LIVE_ENABLED};
}

export async function getCanonicalProviderPayoutAdminDetailDataV3(params: {
  firestore: Firestore;
  actor: CanonicalActor;
  bookingId: string;
}) {
  const payoutSnapshot = await params.firestore
    .collection(CANONICAL_PROVIDER_PAYOUTS_COLLECTION)
    .doc(params.bookingId)
    .get();
  if (!payoutSnapshot.exists) {
    throw new HttpsError("not-found", "Provider payout not found.");
  }
  const payout = asRecord(payoutSnapshot.data());
  const bookingState = await loadCanonicalBooking(params.firestore, params.bookingId);
  if (bookingState.booking == null) {
    throw new HttpsError("failed-precondition", "Canonical booking is missing or invalid.", {
      issues: bookingState.issues,
    });
  }
  const [bank, related, ledger] = await Promise.all([
    loadBankDoc(params.firestore, bookingState.booking.providerId),
    loadBookingRelatedState(params.firestore, params.bookingId),
    loadLedgerSummary(params.firestore, params.bookingId),
  ]);
  return {
    payoutId: payoutSnapshot.id,
    bookingId: params.bookingId,
    status: asString(payout.status),
    failureCode: asString(payout.failureCode),
    failureCategory: asString(payout.failureCategory),
    retryCount: asInt(payout.retryCount, 0),
    nextRetryAt: iso(payout.nextRetryAt),
    eligibleAt: iso(payout.eligibleAt),
    readyAt: iso(payout.readyAt),
    processingAt: iso(payout.processingAt),
    paidAt: iso(payout.paidAt),
    failedAt: iso(payout.failedAt),
    provider: providerSummaryFromBooking({booking: bookingState.booking, bank}),
    customer: customerSummaryFromBooking(bookingState.booking, null),
    service: serviceSummaryFromBooking(bookingState.booking),
    providerBankDetailsReadiness: {
      status: asString(bank?.status),
      accountNumberMasked: asString(bank?.accountNumberMasked),
    },
    providerEarningsSummary: related.providerEarning,
    payoutAmounts: {
      grossServiceAmountPaise: asInt(payout.grossServiceAmountPaise, 0),
      providerEntitlementPaise: asInt(payout.providerEntitlementPaise, 0),
      priorPaidPaise: asInt(payout.priorPaidPaise, 0),
      remainingPayablePaise: asInt(payout.remainingPayablePaise, 0),
      pettxoRetainedPaise: asInt(payout.pettxoRetainedPaise, 0),
      couponCostPaise: asInt(payout.couponCostPaise, 0),
      gatewayFeePaise: asInt(payout.gatewayFeePaise, 0),
      financialAdjustmentTotalPaise:
        asInt(payout.financialAdjustmentTotalPaise, 0),
    },
    holdReason: asString(payout.holdReason),
    linkedBlockers: {
      refundState: related.refund,
      disputeState: bookingState.booking.dispute,
      noShowState: related.noShow,
      payoutReadiness: related.payoutReadiness,
    },
    reconciliation: related.reconciliation,
    ledgerSummary: ledger,
    livePayoutEnabled: CANONICAL_PROVIDER_PAYOUTS_LIVE_ENABLED,
    permittedAdminActions: buildAdminActionMatrix({
      actor: params.actor,
      booking: bookingState.booking,
      dispute: bookingState.booking.dispute as unknown as Record<string, unknown>,
      payout,
    }),
  };
}

export async function getCanonicalFinancialSummaryDataV3(params: {
  firestore: Firestore;
  actor: CanonicalActor;
  bookingId?: string;
}) {
  const bookingId = asString(params.bookingId);
  if (bookingId) {
    const bookingState = await loadCanonicalBooking(params.firestore, bookingId);
    if (bookingState.booking == null) {
      throw new HttpsError("not-found", "Canonical booking not found.");
    }
    const [related, ledger] = await Promise.all([
      loadBookingRelatedState(params.firestore, bookingId),
      loadLedgerSummary(params.firestore, bookingId),
    ]);
    return {
      scope: "booking",
      bookingId,
      paymentStatus: bookingState.booking.payment.status,
      payoutStatus: bookingState.booking.payout.status,
      refundStatus: asString(related.refund?.state),
      reconciliationStatus: asString(related.reconciliation?.status),
      financialSnapshot: bookingState.booking.financials,
      bookingFinancial: related.bookingFinancial,
      providerEarning: related.providerEarning,
      payoutReadiness: related.payoutReadiness,
      ledgerTotals: ledger.totals,
      livePayoutEnabled: CANONICAL_PROVIDER_PAYOUTS_LIVE_ENABLED,
    };
  }

  const [disputesSnapshot, payoutsSnapshot, refundsSnapshot, noShowsSnapshot] = await Promise.all([
    params.firestore.collection("disputes").get(),
    params.firestore.collection(CANONICAL_PROVIDER_PAYOUTS_COLLECTION).get(),
    params.firestore.collection("refunds").get(),
    params.firestore.collection(BOOKING_NO_SHOWS_COLLECTION).get(),
  ]);
  const disputes = disputesSnapshot.docs
    .map((doc) => asRecord(doc.data()))
    .filter((data) => asString(data.source) === "canonical_v3");
  const payouts = payoutsSnapshot.docs.map((doc) => asRecord(doc.data()));
  const refunds = refundsSnapshot.docs.map((doc) => asRecord(doc.data()))
    .filter((data) => asInt(data.schemaVersion, 0) === 3);
  const noShows = noShowsSnapshot.docs.map((doc) => asRecord(doc.data()));
  return {
    scope: "overview",
    config: {
      livePayoutEnabled: CANONICAL_PROVIDER_PAYOUTS_LIVE_ENABLED,
      policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
    },
    counts: {
      canonicalDisputesOpen: disputes.filter((entry) => asString(entry.status).toUpperCase() === "OPEN").length,
      canonicalDisputesResolved: disputes.filter((entry) => asString(entry.status).toUpperCase() === "RESOLVED").length,
      providerPayoutsReady: payouts.filter((entry) => asString(entry.status).toUpperCase() === "READY").length,
      providerPayoutsFailed: payouts.filter((entry) => asString(entry.status).toUpperCase() === "FAILED").length,
      refundsPending: refunds.filter((entry) => ["required", "submitted", "pending"].includes(asString(entry.state).toLowerCase())).length,
      refundsProcessed: refunds.filter((entry) => asString(entry.state).toLowerCase() === "processed").length,
      noShows: noShows.length,
    },
  };
}

export async function listCanonicalNoShowCasesDataV3(params: {
  firestore: Firestore;
  actor: CanonicalActor;
  input: CanonicalListInput;
}) {
  ensureSearchNoCursor(params.input);
  const limit = clampLimit(params.input.limit);
  const cursor = decodeCursor(params.input.cursor);
  const search = normalizeSearch(params.input.search);
  const dateFrom = ensureDateInput(params.input.dateFrom, "dateFrom");
  const dateTo = ensureDateInput(params.input.dateTo, "dateTo");

  if (search) {
    const snapshot = await params.firestore.collection(BOOKING_NO_SHOWS_COLLECTION).doc(search).get();
    if (!snapshot.exists) {
      return {items: [], nextCursor: null};
    }
    const record = asRecord(snapshot.data());
    const bookingState = await loadCanonicalBooking(params.firestore, search);
    if (bookingState.booking == null) return {items: [], nextCursor: null};
    const related = await loadBookingRelatedState(params.firestore, search);
    return {
      items: [{
        bookingId: search,
        status: "NO_SHOW",
        noShowAt: iso(record.noShowAt),
        customer: customerSummaryFromBooking(bookingState.booking, null),
        provider: providerSummaryFromBooking({booking: bookingState.booking, bank: await loadBankDoc(params.firestore, bookingState.booking.providerId)}),
        service: serviceSummaryFromBooking(bookingState.booking),
        scheduledWindow: {
          startAt: serviceSummaryFromBooking(bookingState.booking).scheduledStartAt,
          endAt: serviceSummaryFromBooking(bookingState.booking).scheduledEndAt,
        },
        otpStatus: asString(related.bookingPrivate?.otpState) || "unknown",
        classification: asString(record.noShowReasonCode),
        defaultSettlement: {
          customerRefundPaise: asInt(record.customerRefundPaise, 0),
          providerCompensationPaise: asInt(record.providerCompensationPaise, 0),
          pettxoRetainedPaise: asInt(record.pettxoRetainedPaise, 0),
        },
        disputed: bookingState.booking.dispute.status.toUpperCase() === "OPEN",
        refundStatus: asString(related.refund?.state),
        payoutStatus: asString(related.payout?.status) || bookingState.booking.payout.status,
        reconciliationStatus: asString(related.reconciliation?.status),
        permittedActions: {
          canViewFinancials: params.actor.canViewFinancials,
          canResolveDispute: params.actor.canViewFinancials &&
            bookingState.booking.dispute.status.toUpperCase() === "OPEN",
        },
      }],
      nextCursor: null,
    };
  }

  return await collectFilteredPage({
    baseQuery: params.firestore.collection(BOOKING_NO_SHOWS_COLLECTION),
    sortField: "updatedAt",
    limit,
    cursor,
    filter: async (doc) => matchesDateRange(doc.get("noShowAt"), dateFrom, dateTo),
    map: async (doc) => {
      const bookingId = doc.id;
      const record = asRecord(doc.data());
      const bookingState = await loadCanonicalBooking(params.firestore, bookingId);
      if (bookingState.booking == null) return null;
      const [related, bank] = await Promise.all([
        loadBookingRelatedState(params.firestore, bookingId),
        loadBankDoc(params.firestore, bookingState.booking.providerId),
      ]);
      const service = serviceSummaryFromBooking(bookingState.booking);
      return {
        bookingId,
        status: "NO_SHOW",
        noShowAt: iso(record.noShowAt),
        customer: customerSummaryFromBooking(bookingState.booking, null),
        provider: providerSummaryFromBooking({booking: bookingState.booking, bank}),
        service,
        scheduledWindow: {
          startAt: service.scheduledStartAt,
          endAt: service.scheduledEndAt,
        },
        otpStatus: asString(related.bookingPrivate?.otpState) || "unknown",
        classification: asString(record.noShowReasonCode),
        defaultSettlement: params.actor.canViewFinancials ? {
          customerRefundPaise: asInt(record.customerRefundPaise, 0),
          providerCompensationPaise: asInt(record.providerCompensationPaise, 0),
          pettxoRetainedPaise: asInt(record.pettxoRetainedPaise, 0),
        } : null,
        disputed: bookingState.booking.dispute.status.toUpperCase() === "OPEN",
        providerAvailabilityEvidence: [],
        customerDisputeEvidence:
          bookingState.booking.dispute.evidenceRefs.map((path, index) => ({
            evidenceId: `${index + 1}`,
            storagePath: path,
          })),
        refundStatus: params.actor.canViewFinancials ? asString(related.refund?.state) : null,
        payoutStatus: params.actor.canViewFinancials ?
          (asString(related.payout?.status) || bookingState.booking.payout.status) :
          null,
        reconciliationStatus: params.actor.canViewFinancials ?
          asString(related.reconciliation?.status) :
          null,
        permittedActions: {
          canViewFinancials: params.actor.canViewFinancials,
          canResolveDispute:
            params.actor.canViewFinancials &&
            bookingState.booking.dispute.status.toUpperCase() === "OPEN",
        },
      };
    },
  });
}

export async function listCanonicalRefundsForAdminDataV3(params: {
  firestore: Firestore;
  actor: CanonicalActor;
  input: CanonicalListInput;
}) {
  ensureSearchNoCursor(params.input);
  const limit = clampLimit(params.input.limit);
  const cursor = decodeCursor(params.input.cursor);
  const statusFilter = asString(params.input.status).toLowerCase();
  const dateFrom = ensureDateInput(params.input.dateFrom, "dateFrom");
  const dateTo = ensureDateInput(params.input.dateTo, "dateTo");
  const search = normalizeSearch(params.input.search);

  if (search) {
    const prefixed = await listRefundDetailsByBookingPrefix({
      firestore: params.firestore,
      actor: params.actor,
      search,
      statusFilter,
      limit,
    });
    if (prefixed.length > 0) {
      return {
        items: prefixed.map((detail) => asRecord(detail.summary)),
        nextCursor: null,
      };
    }

    const exact = await findCanonicalBookingByCaseInsensitiveId(
      params.firestore,
      search,
    );
    if (exact.bookingId != null) {
      const snapshot = await params.firestore
        .collection("refunds")
        .doc(exact.bookingId)
        .get();
      if (!snapshot.exists) {
        return {items: [], nextCursor: null};
      }
      const refund = asRecord(snapshot.data());
      if (asInt(refund.schemaVersion, 0) !== 3) {
        return {items: [], nextCursor: null};
      }
      if (statusFilter && asString(refund.state).toLowerCase() !== statusFilter) {
        return {items: [], nextCursor: null};
      }
      const detail = await getCanonicalRefundAdminDetailDataV3({
        firestore: params.firestore,
        actor: params.actor,
        bookingId: exact.bookingId,
      });
      return {items: [detail.summary], nextCursor: null};
    }

    return {items: [], nextCursor: null};
  }

  return await collectFilteredPage({
    baseQuery: params.firestore.collection("refunds"),
    sortField: "updatedAt",
    limit,
    cursor,
    filter: async (doc) => {
      const refund = asRecord(doc.data());
      if (asInt(refund.schemaVersion, 0) !== 3) return false;
      if (statusFilter && asString(refund.state).toLowerCase() !== statusFilter) return false;
      return matchesDateRange(refund.updatedAt, dateFrom, dateTo);
    },
    map: async (doc) => {
      const detail = await getCanonicalRefundAdminDetailDataV3({
        firestore: params.firestore,
        actor: params.actor,
        bookingId: doc.id,
      });
      return detail.summary;
    },
  });
}

export async function getCanonicalRefundAdminDetailDataV3(params: {
  firestore: Firestore;
  actor: CanonicalActor;
  bookingId: string;
}) {
  const refundSnapshot = await params.firestore.collection("refunds").doc(params.bookingId).get();
  if (!refundSnapshot.exists) {
    throw new HttpsError("not-found", "Refund record not found.");
  }
  const refund = asRecord(refundSnapshot.data());
  if (asInt(refund.schemaVersion, 0) !== 3) {
    throw new HttpsError("not-found", "Canonical refund record not found.");
  }
  const bookingState = await loadCanonicalBooking(params.firestore, params.bookingId);
  if (bookingState.booking == null) {
    throw new HttpsError("failed-precondition", "Canonical booking document is incomplete.", {
      issues: bookingState.issues,
    });
  }
  const [related, ledger] = await Promise.all([
    loadBookingRelatedState(params.firestore, params.bookingId),
    loadLedgerSummary(params.firestore, params.bookingId),
  ]);
  const summary = {
    bookingId: params.bookingId,
    status: asString(refund.state),
    cancellationActor:
      related.cancellation == null ? "" : asString(related.cancellation.actorType),
    cancellationReason:
      related.cancellation == null ? "" : asString(related.cancellation.reasonCode),
    cancelledAt:
      related.cancellation == null ? null : iso(related.cancellation.effectiveAt),
    customerPaidPaise: bookingState.booking.financials?.customerPaidPaise ?? 0,
    customerRefundPaise: asInt(refund.refundAmountPaise, 0),
    providerAllocationPaise:
      asInt(related.cancellation?.providerCompensationPaise, 0),
    pettxoAllocationPaise:
      asInt(related.cancellation?.pettxoRetainedPaise, 0),
    couponFundedPaise:
      bookingState.booking.financials?.pettxoCouponFundingPaise ?? 0,
    gatewayFeeTreatment:
      asInt(related.cancellation?.gatewayFeeSunkPaise, 0) > 0 ?
        "sunk_fee_retained" :
        "none",
    razorpayRefundReference: asString(refund.razorpayRefundId) || null,
    failureReason: asString(refund.lastErrorCode) || null,
    reconciliationStatus: asString(related.reconciliation?.status) || null,
  };
  return {
    bookingId: params.bookingId,
    summary,
    booking: {
      state: bookingState.booking.state,
      bookingType: bookingState.booking.bookingType,
      service: serviceSummaryFromBooking(bookingState.booking),
    },
    refund: {
      ...refund,
      createdAt: iso(refund.createdAt),
      updatedAt: iso(refund.updatedAt),
      submittedAt: iso(refund.submittedAt),
      confirmedAt: iso(refund.confirmedAt),
    },
    cancellation: related.cancellation,
    payout: related.payout,
    dispute: bookingState.booking.dispute,
    ledgerSummary: ledger,
  };
}

export const listCanonicalDisputesForAdminV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const actor = await loadAdminActor(db, request.auth, "dispute_nonfinancial");
    return await listCanonicalDisputesForAdminDataV3({
      firestore: db,
      actor,
      input: asRecord(request.data),
    });
  },
);

export const getCanonicalDisputeAdminDetailV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const actor = await loadAdminActor(db, request.auth, "dispute_nonfinancial");
    const disputeId = asString(request.data?.disputeId);
    if (!disputeId) {
      throw new HttpsError("invalid-argument", "disputeId is required.");
    }
    return await getCanonicalDisputeAdminDetailDataV3({
      firestore: db,
      actor,
      disputeId,
    });
  },
);

export const listCanonicalBookingsForAdminV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const actor = await loadAdminActor(db, request.auth, "financial");
    return await listCanonicalBookingsForAdminDataV3({
      firestore: db,
      actor,
      input: asRecord(request.data),
    });
  },
);

export const getCanonicalBookingAdminDetailV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const actor = await loadAdminActor(db, request.auth, "financial");
    const bookingId = asString(request.data?.bookingId);
    if (!bookingId) {
      throw new HttpsError("invalid-argument", "bookingId is required.");
    }
    return await getCanonicalBookingAdminDetailDataV3({
      firestore: db,
      actor,
      bookingId,
    });
  },
);

export const listCanonicalProviderPayoutsForAdminV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const actor = await loadAdminActor(db, request.auth, "financial");
    return await listCanonicalProviderPayoutsForAdminDataV3({
      firestore: db,
      actor,
      input: asRecord(request.data),
    });
  },
);

export const getCanonicalProviderPayoutAdminDetailV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const actor = await loadAdminActor(db, request.auth, "financial");
    const bookingId = asString(request.data?.bookingId);
    if (!bookingId) {
      throw new HttpsError("invalid-argument", "bookingId is required.");
    }
    return await getCanonicalProviderPayoutAdminDetailDataV3({
      firestore: db,
      actor,
      bookingId,
    });
  },
);

export const getCanonicalFinancialSummaryV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const actor = await loadAdminActor(db, request.auth, "financial");
    return await getCanonicalFinancialSummaryDataV3({
      firestore: db,
      actor,
      bookingId: asString(request.data?.bookingId),
    });
  },
);

export const listCanonicalNoShowCasesV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const actor = await loadAdminActor(db, request.auth, "financial");
    return await listCanonicalNoShowCasesDataV3({
      firestore: db,
      actor,
      input: asRecord(request.data),
    });
  },
);

export const listCanonicalRefundsForAdminV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const actor = await loadAdminActor(db, request.auth, "financial");
    return await listCanonicalRefundsForAdminDataV3({
      firestore: db,
      actor,
      input: asRecord(request.data),
    });
  },
);

export const getCanonicalRefundAdminDetailV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const actor = await loadAdminActor(db, request.auth, "financial");
    const bookingId = asString(request.data?.bookingId);
    if (!bookingId) {
      throw new HttpsError("invalid-argument", "bookingId is required.");
    }
    return await getCanonicalRefundAdminDetailDataV3({
      firestore: db,
      actor,
      bookingId,
    });
  },
);
