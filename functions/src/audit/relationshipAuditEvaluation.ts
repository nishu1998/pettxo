/**
 * Pure evaluation for the read-only relationship-blocking readiness audit.
 *
 * NOT exported from src/index.ts; defines no Cloud Function and performs no I/O.
 * Its only project import is the canonical booking schema validator, whose own
 * imports are pure domain modules (see test/relationshipAuditSafety.test.js).
 *
 * The audit REPORTS; it does not decide blocking policy. Anything it cannot
 * classify with certainty is reported as needing manual review (fail-closed).
 */

import {createHash} from "node:crypto";

import {parseCanonicalBookingDocumentV3} from "../booking/schema/bookingDocumentV3";
import type {CanonicalBookingDocumentV3} from "../booking/schema/bookingDocumentV3";

export const RELATIONSHIP_AUDIT_VERSION = 2;

/* ------------------------------------------------------------------------ */
/* Inputs                                                                   */
/* ------------------------------------------------------------------------ */

export type AuditDoc = {
  id: string;
  path: string;
  data: Record<string, unknown>;
};

export type AuditSourceData = {
  userBlocks: AuditDoc[];
  userRelationshipGuards: AuditDoc[];
  bookings: AuditDoc[];
  paymentAttempts: AuditDoc[];
  paymentOrderMappings: AuditDoc[];
  qrPaymentMappings: AuditDoc[];
  refunds: AuditDoc[];
  paymentRefunds: AuditDoc[];
  disputes: AuditDoc[];
  bookingFinancialReconciliation: AuditDoc[];
  manualSettlementObligations: AuditDoc[];
  providerPayouts: AuditDoc[];
  providerEarnings: AuditDoc[];
  payoutReadiness: AuditDoc[];
  /** UIDs referenced by userBlocks that were checked for a users/{uid} document. */
  checkedUserIds: ReadonlySet<string>;
  existingUserIds: ReadonlySet<string>;
};

/** Collection names read by the audit, keyed by AuditSourceData property. */
export const AUDIT_COLLECTIONS = {
  userBlocks: {collection: "userBlocks", group: false},
  userRelationshipGuards: {collection: "userRelationshipGuards", group: false},
  bookings: {collection: "bookings", group: false},
  paymentAttempts: {collection: "paymentAttempts", group: true},
  paymentOrderMappings: {collection: "canonicalPaymentOrderMappings", group: false},
  qrPaymentMappings: {collection: "canonicalQrPaymentMappings", group: false},
  refunds: {collection: "refunds", group: false},
  paymentRefunds: {collection: "paymentRefunds", group: false},
  disputes: {collection: "disputes", group: false},
  bookingFinancialReconciliation: {collection: "bookingFinancialReconciliation", group: false},
  manualSettlementObligations: {collection: "manualSettlementObligations", group: false},
  providerPayouts: {collection: "providerPayouts", group: false},
  providerEarnings: {collection: "providerEarnings", group: false},
  payoutReadiness: {collection: "payoutReadiness", group: false},
} as const;

export type AuditCollectionKey = keyof typeof AUDIT_COLLECTIONS;

/* ------------------------------------------------------------------------ */
/* Outputs                                                                  */
/* ------------------------------------------------------------------------ */

export type ReviewDetail = Record<string, string | number | boolean | null>;

/** A record needing manual reconciliation. Raw UIDs live only in the 0600 file. */
export type AuditRecord = {
  category: string;
  reasonCode: string;
  collection: string;
  documentId: string;
  bookingId?: string;
  pairKey?: string;
  uids?: string[];
  detail?: ReviewDetail;
};

export type CountMap = Record<string, number>;

export type AuditFindings = {
  auditVersion: number;
  evaluatedAt: string;
  sourceCounts: Record<AuditCollectionKey, number>;
  bookings: {
    total: number;
    byState: CountMap;
    byFormat: CountMap;
    protectionByReason: CountMap;
    nonTerminal: number;
    completedInDisputeWindow: number;
    completedPastDisputeWindow: number;
    completedWithoutDisputeDeadline: number;
  };
  malformedBookings: {count: number; byReason: CountMap};
  multiDayPackages: {
    total: number;
    byState: CountMap;
    protected: number;
    partiallyElapsed: number;
    terminalBeforePackageEnd: number;
  };
  payments: {
    attemptsTotal: number;
    attemptsByState: CountMap;
    attemptsOutsideBookings: number;
    orderMappingsTotal: number;
    qrMappingsTotal: number;
    orphanMappings: number;
    bookingsWithAnyPaymentEvidence: number;
    bookingsWithPaymentEvidenceByState: CountMap;
    bookingsWithCapturedMoney: number;
    bookingsWithOpenPaymentOrder: number;
    strandedMoney: {count: number; byReason: CountMap};
  };
  customerProviderProtections: {
    protectedBookings: number;
    openDisputes: number;
    openRefunds: number;
    openPaymentRefundEvents: number;
    unresolvedReconciliations: number;
    openCustomerRefundObligations: number;
  };
  pettxoProviderSettlement: {
    openProviderPayouts: number;
    providerPayoutsByStatus: CountMap;
    heldPayouts: number;
    openProviderEarnings: number;
    providerEarningsByStatus: CountMap;
    openPayoutReadiness: number;
    payoutReadinessHolds: number;
    openProviderPayoutObligations: number;
  };
  userBlocks: {
    total: number;
    schemaVariants: CountMap;
    sourceVariants: CountMap;
    reciprocalPairs: number;
    distinctBlockedPairs: number;
    invalid: number;
    idMismatch: number;
    missingUsers: number;
    blockBookingConflicts: number;
    blockConflictsWithOpenPaymentOrder: number;
    blockConflictsWithSettlementOnly: number;
  };
  relationshipGuards: {
    total: number;
    byStatus: CountMap;
    blockedTrue: number;
    historicalProtectionBlockedTrue: number;
    inconsistent: number;
  };
  unknownFinancialStatuses: number;
  reviewRecordCount: number;
  reviewByCategory: CountMap;
  informationalRecordCount: number;
};

export type AuditEvaluation = {
  findings: AuditFindings;
  /** Records that need manual review before activation (drive exit code 2). */
  reviewRecords: AuditRecord[];
  /** Reported for owner policy decisions; not by themselves review items. */
  informationalRecords: AuditRecord[];
};

/* ------------------------------------------------------------------------ */
/* Shared helpers                                                           */
/* ------------------------------------------------------------------------ */

const CANONICAL_BOOKING_STATES = new Set([
  "REQUESTED", "PENDING_PROVIDER", "ACCEPTED_AWAITING_PAYMENT", "CONFIRMED", "IN_PROGRESS",
  "COMPLETED_PENDING_REVIEW", "COMPLETED_FINAL", "DECLINED", "EXPIRED", "PAYMENT_EXPIRED",
  "CANCELLED_BY_PARENT", "CANCELLED", "DISPUTED", "SERVICE_NOT_STARTED", "NO_SHOW",
]);
/** States in which the booking still involves an active customer-provider relationship. */
const NON_TERMINAL_BOOKING_STATES = new Set([
  "REQUESTED", "PENDING_PROVIDER", "ACCEPTED_AWAITING_PAYMENT", "CONFIRMED", "IN_PROGRESS",
  "COMPLETED_PENDING_REVIEW", "DISPUTED",
]);
/** States where captured money is expected to be held (not stranded). */
const MONEY_EXPECTED_STATES = new Set([
  "CONFIRMED", "IN_PROGRESS", "COMPLETED_PENDING_REVIEW", "COMPLETED_FINAL", "DISPUTED",
]);

const OPEN_ORDER_ATTEMPT_STATES = new Set(["ORDER_CREATING", "ORDER_CREATED", "CHECKOUT_OPENED"]);
const CAPTURED_ATTEMPT_STATES = new Set([
  "CAPTURE_REPORTED", "CONFIRMING", "CONFIRMED", "CAPTURED_REQUIRES_RECONCILIATION",
  "REFUND_REQUIRED", "REFUND_PENDING", "REFUNDED",
]);
const NO_MONEY_ATTEMPT_STATES = new Set(["NOT_STARTED", "FAILED", "EXPIRED"]);
const OPEN_QR_STATES = new Set(["ACTIVE"]);
const CAPTURED_QR_STATES = new Set(["PAYMENT_CAPTURED", "CONFIRMED", "REFUND_REQUIRED"]);
const CLOSED_QR_STATES = new Set(["CLOSED", "EXPIRED", "SUPERSEDED"]);

type StatusVocabulary = {terminal: ReadonlySet<string>; open: ReadonlySet<string>; hold?: ReadonlySet<string>};
const set = (...values: string[]) => new Set(values);

export const FINANCIAL_STATUS_VOCABULARY: Record<string, StatusVocabulary> = {
  refunds: {
    terminal: set("PROCESSED", "REFUNDED", "COMPLETED", "CANCELLED", "PAID", "ISOLATED_EXCESS", "NOT_REQUIRED"),
    open: set("REQUIRED", "PENDING", "SUBMITTED", "SUBMISSION_UNKNOWN", "MANUAL_RECORDED",
      "MANUAL_REQUIRED", "INITIATED", "PROCESSING", "FAILED", "REFUND_PENDING", "REFUND_FAILED"),
  },
  paymentRefunds: {
    terminal: set("PROCESSED"),
    open: set("SUBMITTED", "PENDING", "FAILED", "CREATED"),
  },
  disputes: {
    terminal: set("RESOLVED", "CLOSED", "REJECTED", "WITHDRAWN"),
    open: set("OPEN", "UNDER_REVIEW", "PENDING", "ESCALATED", "DISPUTED"),
  },
  bookingFinancialReconciliation: {
    terminal: set("BALANCED", "RESOLVED", "CLEAN", "COMPLETED"),
    open: set("MISSING_ENTRY", "DUPLICATE_ENTRY", "AMOUNT_MISMATCH", "OVER_REFUNDED",
      "OVERPAID_PROVIDER", "STALE_PAYOUT", "INVALID_FINANCIAL_SNAPSHOT", "MANUAL_REVIEW_REQUIRED"),
  },
  manualSettlementObligations: {
    terminal: set("COMPLETED", "CANCELLED"),
    open: set("READY", "PROCESSING", "NEEDS_ATTENTION"),
    hold: set("HELD"),
  },
  providerPayouts: {
    terminal: set("PAID", "CANCELLED"),
    open: set("READY", "PROCESSING", "FAILED"),
    hold: set("HELD"),
  },
  providerEarnings: {
    terminal: set("FINALIZED", "ADJUSTED", "PAID", "CANCELLED"),
    open: set("PROVISIONAL", "READY", "PROCESSING", "FAILED"),
    hold: set("HELD"),
  },
  payoutReadiness: {
    terminal: set("PAID", "RELEASED", "COMPLETED", "CANCELLED", "NOT_ELIGIBLE"),
    open: set("READY", "PROCESSING", "FAILED", "ELIGIBLE", "PENDING"),
    hold: set("HELD"),
  },
};

export type StatusClass = "terminal" | "open" | "hold" | "unknown";

function str(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

/** Status values are reported as codes only; anything unexpected is reduced to a safe token. */
export function safeCode(value: unknown): string {
  const raw = str(value);
  if (!raw) return "(missing)";
  const cleaned = raw.toUpperCase().replace(/[^A-Z0-9_]/g, "_").slice(0, 40);
  return cleaned || "(invalid)";
}

function upper(value: unknown): string {
  return str(value).toUpperCase();
}

export function financialStatus(collection: string, data: Record<string, unknown>): string {
  if (collection === "providerEarnings") return upper(data.earningsStatus ?? data.status);
  return upper(data.status ?? data.state ?? data.payoutStatus);
}

export function classifyFinancialStatus(collection: string, status: string): StatusClass {
  const vocabulary = FINANCIAL_STATUS_VOCABULARY[collection];
  if (!vocabulary) return "unknown";
  if (vocabulary.terminal.has(status)) return "terminal";
  if (vocabulary.hold?.has(status)) return "hold";
  if (vocabulary.open.has(status)) return "open";
  return "unknown";
}

function increment(map: CountMap, key: string, by = 1): void {
  map[key] = (map[key] ?? 0) + by;
}

function toMillis(value: unknown): number | null {
  if (value == null) return null;
  if (value instanceof Date) return Number.isFinite(value.getTime()) ? value.getTime() : null;
  if (typeof value === "object") {
    const candidate = value as {toMillis?: () => number; seconds?: number; _seconds?: number; nanoseconds?: number};
    if (typeof candidate.toMillis === "function") return candidate.toMillis();
    const seconds = candidate.seconds ?? candidate._seconds;
    if (typeof seconds === "number") return seconds * 1000;
  }
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function money(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

/** Same derivation as src/blocking/relationshipGuard.ts canonicalUserPair (parity-tested). */
export function auditPairKey(firstUid: string, secondUid: string): {uidA: string; uidB: string; pairKey: string} | null {
  const first = firstUid.trim();
  const second = secondUid.trim();
  if (!first || !second || first === second || first.includes("/") || second.includes("/")) return null;
  const sorted = [first, second].sort();
  const pairKey = `pair_${createHash("sha256").update(JSON.stringify(sorted)).digest("hex")}`;
  return {uidA: sorted[0], uidB: sorted[1], pairKey};
}

/**
 * Participant extraction mirroring historicalRelationshipMigration.ts `value`:
 * primary and legacy fields must agree when both are present.
 */
function participant(data: Record<string, unknown>, primary: string, legacy: string): {uid: string; conflict: boolean} {
  const first = str(data[primary]);
  const second = str(data[legacy]);
  if (first && second && first !== second) return {uid: "", conflict: true};
  return {uid: first || second, conflict: false};
}

/* ------------------------------------------------------------------------ */
/* Parity copy of classifyRelationshipProtectionV1                          */
/* ------------------------------------------------------------------------ */

/*
 * The runtime classifier lives in src/blocking/userBlocking.ts, which also
 * imports Firestore write paths and lib/shared/firebase (default Admin app).
 * Importing it would put write-capable code into the audit's import graph, so
 * this is a line-for-line copy. test/relationshipAuditEvaluation.test.js
 * asserts identical output against the runtime classifier for every canonical
 * state and payment/dispute/payout variant.
 */

const ACTIVE_DISPUTE_STATUSES = new Set(["open", "under_review", "pending", "escalated", "disputed"]);
const SETTLED_PAYMENT_STATUSES = new Set(["", "not_started", "confirmed", "paid", "refunded", "cancelled"]);

export type AuditRelationshipProtection =
  | {kind: "accepted_unpaid"; reason: "ACCEPTED_UNPAID"}
  | {kind: "protected"; reason: string}
  | {kind: "unprotected"; reason: "NO_PROTECTED_OBLIGATION"};

function normalized(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function hasPaidEvidence(booking: CanonicalBookingDocumentV3): boolean {
  const paymentStatus = normalized(booking.payment.status).toLowerCase();
  return booking.lifecycle.paidAt != null ||
    booking.payment.capturedAt != null ||
    booking.payment.verifiedAt != null ||
    normalized(booking.payment.razorpayPaymentId).length > 0 ||
    [
      "captured",
      "payment_captured",
      "confirmed",
      "paid",
      "refund_required",
      "refund_pending",
      "refunded",
    ].includes(paymentStatus);
}

function disputeIsActive(booking: CanonicalBookingDocumentV3): boolean {
  return ACTIVE_DISPUTE_STATUSES.has(normalized(booking.dispute.status).toLowerCase());
}

// Parity with userBlocking.ts: provider payouts never protect (D4).
function financialObligationIsUnresolved(booking: CanonicalBookingDocumentV3): boolean {
  const paymentStatus = normalized(booking.payment.status).toLowerCase();
  return !SETTLED_PAYMENT_STATUSES.has(paymentStatus);
}

export function classifyRelationshipProtectionForAudit(params: {
  booking: CanonicalBookingDocumentV3;
  authoritativeNow: Date;
}): AuditRelationshipProtection {
  const {booking, authoritativeNow} = params;
  const paid = hasPaidEvidence(booking);
  if (booking.state === "ACCEPTED_AWAITING_PAYMENT" && !paid) {
    return {kind: "accepted_unpaid", reason: "ACCEPTED_UNPAID"};
  }
  if (disputeIsActive(booking) || booking.state === "DISPUTED") {
    return {kind: "protected", reason: "ACTIVE_DISPUTE"};
  }
  if (["CONFIRMED", "IN_PROGRESS", "COMPLETED_PENDING_REVIEW"].includes(booking.state)) {
    return {kind: "protected", reason: `PROTECTED_STATE_${booking.state}`};
  }
  if (!paid) {
    return {kind: "unprotected", reason: "NO_PROTECTED_OBLIGATION"};
  }
  const disputeDeadline = booking.lifecycle.disputeDeadlineAt ??
    booking.lifecycle.reviewWindowEndsAt;
  if (disputeDeadline && authoritativeNow.getTime() <= disputeDeadline.getTime()) {
    return {kind: "protected", reason: "DISPUTE_WINDOW_ACTIVE"};
  }
  if (financialObligationIsUnresolved(booking)) {
    return {kind: "protected", reason: "FINANCIAL_OBLIGATION_UNRESOLVED"};
  }
  // Paid bookings stop protecting once customer money is settled (checked
  // above) and the booking reached a terminal state. PAYMENT_EXPIRED covers a
  // late capture that was refunded; EXPIRED and DECLINED are defensive
  // (Phase 3B-4e R2).
  if (booking.state !== "COMPLETED_FINAL" &&
    !["CANCELLED", "NO_SHOW", "SERVICE_NOT_STARTED", "PAYMENT_EXPIRED", "EXPIRED", "DECLINED"]
      .includes(booking.state)) {
    return {kind: "protected", reason: `PAID_STATE_${booking.state}`};
  }
  return {kind: "unprotected", reason: "NO_PROTECTED_OBLIGATION"};
}

/* ------------------------------------------------------------------------ */
/* Booking-level evaluation                                                 */
/* ------------------------------------------------------------------------ */

type BookingContext = {
  doc: AuditDoc;
  state: string;
  parentId: string;
  providerId: string;
  pair: ReturnType<typeof auditPairKey>;
  malformedReasons: string[];
  booking: CanonicalBookingDocumentV3 | null;
  protection: AuditRelationshipProtection | null;
  nonTerminal: boolean;
};

function bookingFormat(data: Record<string, unknown>): string {
  if (data.documentFormat === "canonical_v3" && data.schemaVersion === 3) return "canonical_v3";
  if (data.schemaVersion == null && data.documentFormat == null) return "legacy_unversioned";
  return `other:${safeCode(data.documentFormat)}:${safeCode(String(data.schemaVersion ?? ""))}`;
}

function evaluateBooking(doc: AuditDoc, now: Date): BookingContext {
  const data = doc.data;
  const malformedReasons: string[] = [];
  const parent = participant(data, "parentId", "customerId");
  const provider = participant(data, "providerId", "serviceOwnerId");
  if (parent.conflict || provider.conflict) malformedReasons.push("PARTICIPANT_FIELD_CONFLICT");
  const pair = parent.uid && provider.uid ? auditPairKey(parent.uid, provider.uid) : null;
  if (!pair) malformedReasons.push("INVALID_PARTICIPANTS");
  const rawState = str(data.state) || str(data.status);
  const state = CANONICAL_BOOKING_STATES.has(rawState) ? rawState : `UNKNOWN:${safeCode(rawState)}`;
  if (!CANONICAL_BOOKING_STATES.has(rawState)) malformedReasons.push("UNKNOWN_OR_MISSING_STATE");
  const format = bookingFormat(data);
  if (format !== "canonical_v3") malformedReasons.push("LEGACY_OR_OLD_SCHEMA");
  let booking: CanonicalBookingDocumentV3 | null = null;
  const parsed = parseCanonicalBookingDocumentV3(data);
  if (parsed.ok) {
    booking = parsed.booking;
  } else {
    const codes = [...new Set(parsed.issues.map((entry) => safeCode(entry.code)))].sort().slice(0, 5);
    malformedReasons.push(`INVALID_CANONICAL_DOCUMENT:${codes.join("+")}`);
  }
  const protection = booking && malformedReasons.length === 0 ?
    classifyRelationshipProtectionForAudit({booking, authoritativeNow: now}) : null;
  return {
    doc,
    state,
    parentId: parent.uid,
    providerId: provider.uid,
    pair,
    malformedReasons,
    booking,
    protection,
    // Fail-closed: a booking we cannot classify is treated as non-terminal.
    nonTerminal: NON_TERMINAL_BOOKING_STATES.has(state) || malformedReasons.length > 0,
  };
}

type PackageWindow = {multiDay: boolean; startMillis: number | null; endMillis: number | null};

/** Package-level window for SLOT (multi-day segments/slots) and RANGE (multi-night) bookings. */
export function packageWindow(data: Record<string, unknown>): PackageWindow {
  const schedule = (data.schedule ?? {}) as Record<string, unknown>;
  const bookingType = str(data.bookingType) || str(schedule.bookingType);
  if (bookingType === "RANGE") {
    const start = toMillis(schedule.checkInDateTime ?? data.checkInDateTime);
    const end = toMillis(schedule.checkOutDateTime);
    const nights = typeof schedule.nights === "number" ? schedule.nights : 0;
    return {multiDay: nights >= 1, startMillis: start, endMillis: end};
  }
  const slots = Array.isArray(schedule.slots) ? schedule.slots as Array<Record<string, unknown>> : [];
  const dayKeys = new Set(slots.map((slot) => str(slot.serviceDateKey) || str(slot.dateKey)).filter(Boolean));
  const ends = [
    toMillis(schedule.finalEndAt),
    toMillis(schedule.scheduledEndAt),
    ...slots.map((slot) => toMillis(slot.endAt)),
  ].filter((value): value is number => value != null);
  const serviceDayCount = typeof schedule.serviceDayCount === "number" ? schedule.serviceDayCount : 0;
  return {
    multiDay: dayKeys.size > 1 || serviceDayCount > 1,
    startMillis: toMillis(schedule.scheduledStartAt ?? data.scheduledStartAt),
    endMillis: ends.length > 0 ? Math.max(...ends) : null,
  };
}

/* ------------------------------------------------------------------------ */
/* Main evaluation                                                          */
/* ------------------------------------------------------------------------ */

function bookingIdOf(doc: AuditDoc): string {
  return str(doc.data.bookingId) || doc.id;
}

export function evaluateRelationshipAudit(source: AuditSourceData, now: Date): AuditEvaluation {
  const reviewRecords: AuditRecord[] = [];
  const informationalRecords: AuditRecord[] = [];
  const review = (record: AuditRecord) => reviewRecords.push(record);
  const inform = (record: AuditRecord) => informationalRecords.push(record);

  const sourceCounts = Object.fromEntries(
    (Object.keys(AUDIT_COLLECTIONS) as AuditCollectionKey[]).map((key) => [key, source[key].length]),
  ) as Record<AuditCollectionKey, number>;

  /* ---- bookings ---- */
  const bookingContexts = new Map<string, BookingContext>();
  const bookingsSummary: AuditFindings["bookings"] = {
    total: source.bookings.length,
    byState: {},
    byFormat: {},
    protectionByReason: {},
    nonTerminal: 0,
    completedInDisputeWindow: 0,
    completedPastDisputeWindow: 0,
    completedWithoutDisputeDeadline: 0,
  };
  const malformed: AuditFindings["malformedBookings"] = {count: 0, byReason: {}};
  const multiDay: AuditFindings["multiDayPackages"] = {
    total: 0, byState: {}, protected: 0, partiallyElapsed: 0, terminalBeforePackageEnd: 0,
  };
  for (const doc of source.bookings) {
    const context = evaluateBooking(doc, now);
    bookingContexts.set(doc.id, context);
    increment(bookingsSummary.byState, context.state);
    increment(bookingsSummary.byFormat, bookingFormat(doc.data));
    if (context.nonTerminal) bookingsSummary.nonTerminal += 1;
    const uids = [context.parentId, context.providerId].filter(Boolean);
    if (context.malformedReasons.length > 0) {
      malformed.count += 1;
      for (const reason of context.malformedReasons) increment(malformed.byReason, reason.split(":")[0]);
      review({
        category: "MALFORMED_BOOKING",
        reasonCode: context.malformedReasons.join("|"),
        collection: "bookings",
        documentId: doc.id,
        bookingId: doc.id,
        pairKey: context.pair?.pairKey,
        uids,
        detail: {state: context.state, format: bookingFormat(doc.data)},
      });
    }
    if (context.protection) increment(bookingsSummary.protectionByReason, context.protection.reason);
    if (context.booking && (context.state === "COMPLETED_FINAL" || context.state === "COMPLETED_PENDING_REVIEW")) {
      const deadline = context.booking.lifecycle.disputeDeadlineAt ?? context.booking.lifecycle.reviewWindowEndsAt;
      if (!deadline) bookingsSummary.completedWithoutDisputeDeadline += 1;
      else if (now.getTime() <= deadline.getTime()) bookingsSummary.completedInDisputeWindow += 1;
      else bookingsSummary.completedPastDisputeWindow += 1;
    }
    const window = packageWindow(doc.data);
    if (window.multiDay) {
      multiDay.total += 1;
      increment(multiDay.byState, context.state);
      const isProtected = context.protection?.kind === "protected" || context.malformedReasons.length > 0;
      if (isProtected) multiDay.protected += 1;
      const started = window.startMillis != null && window.startMillis <= now.getTime();
      const ended = window.endMillis != null && window.endMillis <= now.getTime();
      const partiallyElapsed = started && !ended;
      if (partiallyElapsed) multiDay.partiallyElapsed += 1;
      const terminalEarly = !ended && ["COMPLETED_FINAL", "COMPLETED_PENDING_REVIEW"].includes(context.state);
      if (terminalEarly) multiDay.terminalBeforePackageEnd += 1;
      inform({
        category: "MULTI_DAY_PACKAGE",
        reasonCode: context.protection?.reason ?? "UNCLASSIFIED",
        collection: "bookings",
        documentId: doc.id,
        bookingId: doc.id,
        pairKey: context.pair?.pairKey,
        uids,
        detail: {state: context.state, packageProtected: isProtected, partiallyElapsed, terminalBeforePackageEnd: terminalEarly},
      });
      if (terminalEarly) {
        review({
          category: "MULTI_DAY_PACKAGE_INCONSISTENT",
          reasonCode: "COMPLETED_BEFORE_PACKAGE_END",
          collection: "bookings",
          documentId: doc.id,
          bookingId: doc.id,
          pairKey: context.pair?.pairKey,
          uids,
          detail: {state: context.state},
        });
      }
    }
  }

  /* ---- financial records keyed by booking ---- */
  type FinancialEntry = {collection: string; doc: AuditDoc; status: string; statusClass: StatusClass};
  const financialByBooking = new Map<string, FinancialEntry[]>();
  let unknownFinancialStatuses = 0;
  const addFinancial = (collection: AuditCollectionKey, doc: AuditDoc) => {
    const status = financialStatus(collection, doc.data);
    const statusClass = classifyFinancialStatus(collection, status);
    const entry = {collection, doc, status, statusClass};
    const bookingId = bookingIdOf(doc);
    const list = financialByBooking.get(bookingId) ?? [];
    list.push(entry);
    financialByBooking.set(bookingId, list);
    if (statusClass === "unknown") {
      unknownFinancialStatuses += 1;
      const context = bookingContexts.get(bookingId);
      review({
        category: "UNKNOWN_FINANCIAL_STATUS",
        reasonCode: `${collection}:${safeCode(status)}`,
        collection: AUDIT_COLLECTIONS[collection].collection,
        documentId: doc.id,
        bookingId,
        pairKey: context?.pair?.pairKey,
        uids: context ? [context.parentId, context.providerId].filter(Boolean) : undefined,
      });
    }
    return entry;
  };

  const protections: AuditFindings["customerProviderProtections"] = {
    protectedBookings: 0, openDisputes: 0, openRefunds: 0, openPaymentRefundEvents: 0,
    unresolvedReconciliations: 0, openCustomerRefundObligations: 0,
  };
  const settlement: AuditFindings["pettxoProviderSettlement"] = {
    openProviderPayouts: 0, providerPayoutsByStatus: {}, heldPayouts: 0, openProviderEarnings: 0,
    providerEarningsByStatus: {}, openPayoutReadiness: 0, payoutReadinessHolds: 0, openProviderPayoutObligations: 0,
  };
  const customerProtectionBookings = new Set<string>();
  const settlementBookings = new Set<string>();
  const isOpen = (entry: FinancialEntry) => entry.statusClass !== "terminal";

  const informFinancial = (category: string, entry: FinancialEntry) => {
    const bookingId = bookingIdOf(entry.doc);
    const context = bookingContexts.get(bookingId);
    inform({
      category,
      reasonCode: `${entry.collection}:${safeCode(entry.status)}`,
      collection: AUDIT_COLLECTIONS[entry.collection as AuditCollectionKey].collection,
      documentId: entry.doc.id,
      bookingId,
      pairKey: context?.pair?.pairKey,
      uids: context ? [context.parentId, context.providerId].filter(Boolean) : undefined,
      detail: {status: safeCode(entry.status), statusClass: entry.statusClass},
    });
  };

  for (const doc of source.disputes) {
    const entry = addFinancial("disputes", doc);
    if (isOpen(entry)) {
      protections.openDisputes += 1;
      customerProtectionBookings.add(bookingIdOf(doc));
      informFinancial("CUSTOMER_PROVIDER_PROTECTION", entry);
    }
  }
  for (const doc of source.refunds) {
    const entry = addFinancial("refunds", doc);
    if (isOpen(entry)) {
      protections.openRefunds += 1;
      customerProtectionBookings.add(bookingIdOf(doc));
      informFinancial("CUSTOMER_PROVIDER_PROTECTION", entry);
    }
  }
  for (const doc of source.paymentRefunds) {
    const entry = addFinancial("paymentRefunds", doc);
    if (isOpen(entry)) {
      protections.openPaymentRefundEvents += 1;
      customerProtectionBookings.add(bookingIdOf(doc));
      informFinancial("CUSTOMER_PROVIDER_PROTECTION", entry);
    }
  }
  for (const doc of source.bookingFinancialReconciliation) {
    const entry = addFinancial("bookingFinancialReconciliation", doc);
    if (isOpen(entry)) {
      protections.unresolvedReconciliations += 1;
      customerProtectionBookings.add(bookingIdOf(doc));
      informFinancial("CUSTOMER_PROVIDER_PROTECTION", entry);
    }
  }
  for (const doc of source.manualSettlementObligations) {
    const entry = addFinancial("manualSettlementObligations", doc);
    if (!isOpen(entry)) continue;
    const type = upper(doc.data.obligationType ?? doc.data.type);
    if (type === "CUSTOMER_REFUND") {
      protections.openCustomerRefundObligations += 1;
      customerProtectionBookings.add(bookingIdOf(doc));
      informFinancial("CUSTOMER_PROVIDER_PROTECTION", entry);
    } else {
      settlement.openProviderPayoutObligations += 1;
      settlementBookings.add(bookingIdOf(doc));
      informFinancial("PETTXO_PROVIDER_SETTLEMENT", entry);
    }
  }
  for (const doc of source.providerPayouts) {
    const entry = addFinancial("providerPayouts", doc);
    increment(settlement.providerPayoutsByStatus, safeCode(entry.status));
    if (entry.statusClass === "hold") settlement.heldPayouts += 1;
    if (isOpen(entry)) {
      settlement.openProviderPayouts += 1;
      settlementBookings.add(bookingIdOf(doc));
      informFinancial("PETTXO_PROVIDER_SETTLEMENT", entry);
    }
  }
  for (const doc of source.providerEarnings) {
    const entry = addFinancial("providerEarnings", doc);
    increment(settlement.providerEarningsByStatus, safeCode(entry.status));
    if (isOpen(entry)) {
      settlement.openProviderEarnings += 1;
      settlementBookings.add(bookingIdOf(doc));
      informFinancial("PETTXO_PROVIDER_SETTLEMENT", entry);
    }
  }
  for (const doc of source.payoutReadiness) {
    const entry = addFinancial("payoutReadiness", doc);
    const holdReason = str(doc.data.payoutHoldReason) || str(doc.data.holdReason);
    if (entry.statusClass === "hold" || holdReason) settlement.payoutReadinessHolds += 1;
    if (isOpen(entry)) {
      settlement.openPayoutReadiness += 1;
      settlementBookings.add(bookingIdOf(doc));
      informFinancial("PETTXO_PROVIDER_SETTLEMENT", entry);
    }
  }

  /* ---- payment evidence on bookings in every state ---- */
  type PaymentEvidence = {attempts: AuditDoc[]; orderMappings: AuditDoc[]; qrMappings: AuditDoc[]};
  const paymentByBooking = new Map<string, PaymentEvidence>();
  const evidenceFor = (bookingId: string) => {
    let evidence = paymentByBooking.get(bookingId);
    if (!evidence) {
      evidence = {attempts: [], orderMappings: [], qrMappings: []};
      paymentByBooking.set(bookingId, evidence);
    }
    return evidence;
  };
  const payments: AuditFindings["payments"] = {
    attemptsTotal: source.paymentAttempts.length,
    attemptsByState: {},
    attemptsOutsideBookings: 0,
    orderMappingsTotal: source.paymentOrderMappings.length,
    qrMappingsTotal: source.qrPaymentMappings.length,
    orphanMappings: 0,
    bookingsWithAnyPaymentEvidence: 0,
    bookingsWithPaymentEvidenceByState: {},
    bookingsWithCapturedMoney: 0,
    bookingsWithOpenPaymentOrder: 0,
    strandedMoney: {count: 0, byReason: {}},
  };
  for (const doc of source.paymentAttempts) {
    increment(payments.attemptsByState, safeCode(doc.data.state));
    const segments = doc.path.split("/");
    if (segments.length !== 4 || segments[0] !== "bookings") {
      payments.attemptsOutsideBookings += 1;
      continue;
    }
    const parentBookingId = segments[1];
    const declared = str(doc.data.bookingId);
    if (declared && declared !== parentBookingId) {
      review({
        category: "PAYMENT_EVIDENCE_INCONSISTENT",
        reasonCode: "ATTEMPT_BOOKING_ID_MISMATCH",
        collection: "bookings/*/paymentAttempts",
        documentId: doc.id,
        bookingId: parentBookingId,
      });
    }
    evidenceFor(parentBookingId).attempts.push(doc);
  }
  const attemptIds = new Set(source.paymentAttempts.map((doc) => doc.id));
  for (const [mappings, key, collection] of [
    [source.paymentOrderMappings, "orderMappings", "canonicalPaymentOrderMappings"],
    [source.qrPaymentMappings, "qrMappings", "canonicalQrPaymentMappings"],
  ] as const) {
    for (const doc of mappings) {
      const bookingId = str(doc.data.bookingId);
      const attemptId = str(doc.data.paymentAttemptId);
      if (!bookingId || !bookingContexts.has(bookingId) || (attemptId && !attemptIds.has(attemptId))) {
        payments.orphanMappings += 1;
        review({
          category: "PAYMENT_EVIDENCE_INCONSISTENT",
          reasonCode: !bookingId ? "MAPPING_WITHOUT_BOOKING_ID" :
            !bookingContexts.has(bookingId) ? "MAPPING_BOOKING_MISSING" : "MAPPING_ATTEMPT_MISSING",
          collection,
          documentId: doc.id,
          bookingId: bookingId || undefined,
          detail: {mappingStatus: safeCode(doc.data.status)},
        });
      }
      if (bookingId) evidenceFor(bookingId)[key].push(doc);
    }
  }

  type BookingMoney = {captured: boolean; open: boolean; fullyRefunded: boolean; unknownAttemptState: boolean};
  const moneyByBooking = new Map<string, BookingMoney>();
  for (const [bookingId, context] of bookingContexts) {
    const evidence = paymentByBooking.get(bookingId) ?? {attempts: [], orderMappings: [], qrMappings: []};
    const data = context.doc.data;
    const payment = (data.payment ?? {}) as Record<string, unknown>;
    const lifecycle = (data.lifecycle ?? {}) as Record<string, unknown>;
    const bookingPaymentStatus = str(payment.status).toLowerCase();
    let captured = lifecycle.paidAt != null || payment.capturedAt != null || payment.verifiedAt != null ||
      str(payment.razorpayPaymentId).length > 0 ||
      ["captured", "payment_captured", "confirmed", "paid", "refund_required", "refund_pending", "refunded"]
        .includes(bookingPaymentStatus);
    let open = false;
    let unknownAttemptState = false;
    let capturedPaise = 0;
    let refundedPaise = 0;
    let allCapturedRefunded = true;
    for (const attempt of evidence.attempts) {
      const state = upper(attempt.data.state);
      const qrState = upper(attempt.data.qrState);
      if (OPEN_ORDER_ATTEMPT_STATES.has(state) || OPEN_QR_STATES.has(qrState)) open = true;
      if (CAPTURED_ATTEMPT_STATES.has(state) || CAPTURED_QR_STATES.has(qrState) ||
        str(attempt.data.razorpayPaymentId).length > 0) {
        captured = true;
        capturedPaise += money(attempt.data.capturedAmountPaise ?? attempt.data.amountPaise);
        refundedPaise += money(attempt.data.refundedAmountPaise);
        if (state !== "REFUNDED") allCapturedRefunded = false;
      }
      if (!OPEN_ORDER_ATTEMPT_STATES.has(state) && !CAPTURED_ATTEMPT_STATES.has(state) &&
        !NO_MONEY_ATTEMPT_STATES.has(state)) unknownAttemptState = true;
      if (qrState && !OPEN_QR_STATES.has(qrState) && !CAPTURED_QR_STATES.has(qrState) &&
        !CLOSED_QR_STATES.has(qrState)) unknownAttemptState = true;
    }
    for (const mapping of [...evidence.orderMappings, ...evidence.qrMappings]) {
      if (upper(mapping.data.status) === "ACTIVE") open = true;
    }
    const hasEvidence = evidence.attempts.length + evidence.orderMappings.length + evidence.qrMappings.length > 0 ||
      captured;
    if (hasEvidence) {
      payments.bookingsWithAnyPaymentEvidence += 1;
      increment(payments.bookingsWithPaymentEvidenceByState, context.state);
    }
    if (captured) payments.bookingsWithCapturedMoney += 1;
    if (open) payments.bookingsWithOpenPaymentOrder += 1;
    const fullyRefunded = captured && evidence.attempts.length > 0 &&
      (allCapturedRefunded || (capturedPaise > 0 && refundedPaise >= capturedPaise));
    moneyByBooking.set(bookingId, {captured, open, fullyRefunded, unknownAttemptState});
    const uids = [context.parentId, context.providerId].filter(Boolean);
    if (unknownAttemptState) {
      review({
        category: "PAYMENT_EVIDENCE_INCONSISTENT",
        reasonCode: "UNKNOWN_PAYMENT_ATTEMPT_STATE",
        collection: "bookings",
        documentId: bookingId,
        bookingId,
        pairKey: context.pair?.pairKey,
        uids,
      });
    }
    if (!MONEY_EXPECTED_STATES.has(context.state) && (open || (captured && !fullyRefunded))) {
      const refundEntries = (financialByBooking.get(bookingId) ?? [])
        .filter((entry) => entry.collection === "refunds" || entry.collection === "paymentRefunds");
      const refundOpen = refundEntries.some(isOpen);
      const reason = open && !captured ? "PENDING_PAYMENT_ON_UNCONFIRMED_BOOKING" :
        refundEntries.length === 0 ? "CAPTURED_NO_REFUND_RECORD" :
          refundOpen ? "CAPTURED_REFUND_OPEN" : "CAPTURED_REFUND_SETTLED_PARTIAL";
      payments.strandedMoney.count += 1;
      increment(payments.strandedMoney.byReason, reason);
      review({
        category: "STRANDED_MONEY",
        reasonCode: reason,
        collection: "bookings",
        documentId: bookingId,
        bookingId,
        pairKey: context.pair?.pairKey,
        uids,
        detail: {
          state: context.state,
          attempts: evidence.attempts.length,
          orderMappings: evidence.orderMappings.length,
          qrMappings: evidence.qrMappings.length,
          capturedPaise,
          refundedPaise,
          openOrder: open,
        },
      });
    }
    if (context.protection?.kind === "protected" ||
      customerProtectionBookings.has(bookingId)) {
      protections.protectedBookings += 1;
    }
  }

  /* ---- relationship guards ---- */
  const guards: AuditFindings["relationshipGuards"] = {
    total: source.userRelationshipGuards.length,
    byStatus: {},
    blockedTrue: 0,
    historicalProtectionBlockedTrue: 0,
    inconsistent: 0,
  };
  const guardsByPair = new Map<string, AuditDoc>();
  for (const doc of source.userRelationshipGuards) guardsByPair.set(doc.id, doc);

  /* ---- user blocks ---- */
  const blocks: AuditFindings["userBlocks"] = {
    total: source.userBlocks.length,
    schemaVariants: {},
    sourceVariants: {},
    reciprocalPairs: 0,
    distinctBlockedPairs: 0,
    invalid: 0,
    idMismatch: 0,
    missingUsers: 0,
    blockBookingConflicts: 0,
    blockConflictsWithOpenPaymentOrder: 0,
    blockConflictsWithSettlementOnly: 0,
  };
  const directedByPair = new Map<string, Array<{doc: AuditDoc; owner: string; blocked: string}>>();
  const pairUids = new Map<string, string[]>();
  for (const doc of source.userBlocks) {
    const data = doc.data;
    const ownerUserId = str(data.ownerUserId);
    const blockerUid = str(data.blockerUid);
    const blockedUserId = str(data.blockedUserId);
    const variant = data.schemaVersion === 1 && ownerUserId && blockerUid && str(data.pairKey) ?
      "server_v1" : ownerUserId ? "owner_field" : blockerUid ? "legacy_blocker_field" : "unrecognised";
    increment(blocks.schemaVariants, variant);
    increment(blocks.sourceVariants, data.source == null ? "(none)" : safeCode(data.source));
    const owner = participant(data, "ownerUserId", "blockerUid");
    const pair = owner.uid && blockedUserId ? auditPairKey(owner.uid, blockedUserId) : null;
    if (!pair || owner.conflict) {
      blocks.invalid += 1;
      review({
        category: "INVALID_USER_BLOCK",
        reasonCode: owner.conflict ? "OWNER_FIELD_CONFLICT" : "INVALID_PARTICIPANTS",
        collection: "userBlocks",
        documentId: doc.id,
        uids: [owner.uid, blockedUserId].filter(Boolean),
        detail: {schemaVariant: variant},
      });
      continue;
    }
    if (doc.id !== `${owner.uid}_${blockedUserId}`) {
      blocks.idMismatch += 1;
      review({
        category: "INVALID_USER_BLOCK",
        reasonCode: "DOCUMENT_ID_MISMATCH",
        collection: "userBlocks",
        documentId: doc.id,
        pairKey: pair.pairKey,
        uids: [owner.uid, blockedUserId],
      });
    }
    if (str(data.pairKey) && str(data.pairKey) !== pair.pairKey) {
      review({
        category: "INVALID_USER_BLOCK",
        reasonCode: "PAIR_KEY_MISMATCH",
        collection: "userBlocks",
        documentId: doc.id,
        pairKey: pair.pairKey,
        uids: [owner.uid, blockedUserId],
      });
    }
    const missing = [owner.uid, blockedUserId].filter((uid) =>
      source.checkedUserIds.has(uid) && !source.existingUserIds.has(uid));
    if (missing.length > 0) {
      blocks.missingUsers += 1;
      review({
        category: "USER_BLOCK_MISSING_USER",
        reasonCode: missing.length === 2 ? "BOTH_USERS_MISSING" :
          missing[0] === owner.uid ? "OWNER_MISSING" : "BLOCKED_USER_MISSING",
        collection: "userBlocks",
        documentId: doc.id,
        pairKey: pair.pairKey,
        uids: [owner.uid, blockedUserId],
      });
    }
    const list = directedByPair.get(pair.pairKey) ?? [];
    list.push({doc, owner: owner.uid, blocked: blockedUserId});
    directedByPair.set(pair.pairKey, list);
    pairUids.set(pair.pairKey, [pair.uidA, pair.uidB]);
  }
  blocks.distinctBlockedPairs = directedByPair.size;
  for (const [pairKey, list] of directedByPair) {
    const owners = new Set(list.map((entry) => entry.owner));
    if (owners.size >= 2) {
      blocks.reciprocalPairs += 1;
      inform({
        category: "RECIPROCAL_BLOCK_PAIR",
        reasonCode: "BOTH_DIRECTIONS_BLOCKED",
        collection: "userBlocks",
        documentId: list.map((entry) => entry.doc.id).sort().join(","),
        pairKey,
        uids: pairUids.get(pairKey),
      });
    }
  }

  /* ---- block + booking/payment conflicts (pair level) ---- */
  const bookingsByPair = new Map<string, BookingContext[]>();
  for (const context of bookingContexts.values()) {
    if (!context.pair) continue;
    const list = bookingsByPair.get(context.pair.pairKey) ?? [];
    list.push(context);
    bookingsByPair.set(context.pair.pairKey, list);
  }
  for (const [pairKey, directed] of directedByPair) {
    const pairBookings = bookingsByPair.get(pairKey) ?? [];
    const conflicts: string[] = [];
    let openOrder = false;
    let customerProtection = false;
    let settlementOnly = false;
    for (const context of pairBookings) {
      const bookingId = context.doc.id;
      const money = moneyByBooking.get(bookingId);
      const financial = financialByBooking.get(bookingId) ?? [];
      const openCustomer = financial.some((entry) => isOpen(entry) &&
        !["providerPayouts", "providerEarnings", "payoutReadiness"].includes(entry.collection) &&
        !(entry.collection === "manualSettlementObligations" &&
          upper(entry.doc.data.obligationType ?? entry.doc.data.type) !== "CUSTOMER_REFUND"));
      const openSettlement = settlementBookings.has(bookingId);
      const strandedCapture = Boolean(money?.captured && !money.fullyRefunded &&
        !MONEY_EXPECTED_STATES.has(context.state));
      const relevant = context.nonTerminal || context.protection?.kind === "protected" ||
        money?.open || strandedCapture || openCustomer;
      if (relevant) {
        conflicts.push(bookingId);
        if (money?.open) openOrder = true;
        customerProtection = true;
      } else if (openSettlement) {
        conflicts.push(bookingId);
        settlementOnly = true;
      }
    }
    if (conflicts.length === 0) continue;
    if (customerProtection) {
      blocks.blockBookingConflicts += 1;
      if (openOrder) blocks.blockConflictsWithOpenPaymentOrder += 1;
      review({
        category: "BLOCK_BOOKING_CONFLICT",
        reasonCode: openOrder ? "BLOCK_WITH_OPEN_PAYMENT_ORDER" : "BLOCK_WITH_ACTIVE_OR_PROTECTED_BOOKING",
        collection: "userBlocks",
        documentId: directed.map((entry) => entry.doc.id).sort().join(","),
        pairKey,
        uids: pairUids.get(pairKey),
        detail: {bookingIds: conflicts.sort().join(","), directedBlocks: directed.length},
      });
    } else if (settlementOnly) {
      blocks.blockConflictsWithSettlementOnly += 1;
      inform({
        category: "BLOCK_WITH_PETTXO_PROVIDER_SETTLEMENT_ONLY",
        reasonCode: "OWNER_POLICY_DECISION",
        collection: "userBlocks",
        documentId: directed.map((entry) => entry.doc.id).sort().join(","),
        pairKey,
        uids: pairUids.get(pairKey),
        detail: {bookingIds: conflicts.sort().join(",")},
      });
    }
  }

  /* ---- relationship guard consistency ---- */
  for (const doc of source.userRelationshipGuards) {
    const data = doc.data;
    increment(guards.byStatus, safeCode(data.status));
    if (data.blocked === true) guards.blockedTrue += 1;
    if (data.historicalProtectionBlocked === true) guards.historicalProtectionBlockedTrue += 1;
    const reasons: string[] = [];
    const pair = auditPairKey(str(data.uidA), str(data.uidB));
    if (!pair || pair.pairKey !== doc.id || str(data.uidA) !== pair.uidA) reasons.push("PAIR_KEY_OR_UID_ORDER_INVALID");
    const directed = directedByPair.get(doc.id) ?? [];
    const declared = Array.isArray(data.activeDirectedBlockIds) ?
      (data.activeDirectedBlockIds as unknown[]).map(String).sort() : [];
    const actual = directed.map((entry) => entry.doc.id).sort();
    if (data.blocked === true && actual.length === 0) reasons.push("GUARD_BLOCKED_WITHOUT_DIRECTED_BLOCK");
    if (data.blocked !== true && actual.length > 0) reasons.push("DIRECTED_BLOCK_WITHOUT_BLOCKED_GUARD");
    if (JSON.stringify(declared) !== JSON.stringify(actual)) reasons.push("ACTIVE_DIRECTED_BLOCK_IDS_MISMATCH");
    if (data.blocked === true && upper(data.status) !== "BLOCKED") reasons.push("STATUS_FLAG_MISMATCH");
    if (data.historicalProtectionBlocked === true) reasons.push("HISTORICAL_PROTECTION_MARK_PRESENT");
    if (reasons.length > 0) {
      guards.inconsistent += 1;
      review({
        category: "RELATIONSHIP_GUARD_INCONSISTENT",
        reasonCode: reasons.join("|"),
        collection: "userRelationshipGuards",
        documentId: doc.id,
        pairKey: doc.id,
        uids: [str(data.uidA), str(data.uidB)].filter(Boolean),
      });
    }
  }
  for (const [pairKey, directed] of directedByPair) {
    if (!guardsByPair.has(pairKey)) {
      inform({
        category: "DIRECTED_BLOCK_WITHOUT_GUARD",
        reasonCode: "PRE_MIGRATION_EXPECTED",
        collection: "userBlocks",
        documentId: directed.map((entry) => entry.doc.id).sort().join(","),
        pairKey,
        uids: pairUids.get(pairKey),
      });
    }
  }

  const reviewByCategory: CountMap = {};
  for (const record of reviewRecords) increment(reviewByCategory, record.category);

  return {
    findings: {
      auditVersion: RELATIONSHIP_AUDIT_VERSION,
      evaluatedAt: now.toISOString(),
      sourceCounts,
      bookings: bookingsSummary,
      malformedBookings: malformed,
      multiDayPackages: multiDay,
      payments,
      customerProviderProtections: protections,
      pettxoProviderSettlement: settlement,
      userBlocks: blocks,
      relationshipGuards: guards,
      unknownFinancialStatuses,
      reviewRecordCount: reviewRecords.length,
      reviewByCategory,
      informationalRecordCount: informationalRecords.length,
    },
    reviewRecords,
    informationalRecords,
  };
}
