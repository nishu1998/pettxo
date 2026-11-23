import {createHash} from "node:crypto";
import type {Auth} from "firebase-admin/auth";
import {
  FieldPath,
  FieldValue,
  Timestamp,
  type DocumentReference,
  type Firestore,
  type QueryDocumentSnapshot,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {auth as defaultAuth, db as defaultDb} from "../shared/firebase";
import {requireActiveSuperAdmin, type AdminGuardRequest} from "./adminActor";
import {ADMIN_AUDIT_LOGS_COLLECTION, writeAdminLog} from "./adminLog";
import {containsRawContact} from "./contactMasking";

/**
 * Test-booking flag (approach B, docs/PETTXO_TEST_BOOKING_FLAG_DECISIONS.md).
 *
 * `bookingTestFlags/{bookingId}` exists = the booking is a test booking; no
 * document = real. It only tidies the admin dashboard: booking documents and
 * every booking, payment, refund and payout record are never read for writing
 * or written here. Super Admin only; every change is in adminAuditLogs.
 */

export const BOOKING_TEST_FLAGS_COLLECTION = "bookingTestFlags";
export const SET_BOOKING_TEST_FLAG_SOURCE = "setBookingTestFlagForAdmin";

/** Owner decision Q8: the backfill can never mark bookings created after this. */
export const BACKFILL_CUTOFF_CEILING = new Date("2026-11-23T00:00:00+05:30");
/** Flag docs per backfill call; with the one log row this stays under 500 writes. */
export const BACKFILL_MAX_PER_CALL = 450;
export const BACKFILL_SAMPLE_IDS = 20;
const BOOKING_PAGE_SIZE = 500;

const REASON_MIN = 3;
const REASON_MAX = 200;
const ID_MAX = 128;
const REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{8,64}$/;
const FINGERPRINT_PATTERN = /^[0-9a-f]{12}$/;
// eslint-disable-next-line no-control-regex
const CONTROL_CHARS = /[\u0000-\u001f\u007f]/;
const ISO_WITH_ZONE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,3})?)?(Z|[+-]\d{2}:\d{2})$/;

export type BookingTestFlagDeps = {
  firestore?: Firestore;
  authClient?: Pick<Auth, "getUser">;
};

export type BookingTestFlagRequest = AdminGuardRequest & {data?: unknown};

function asRecord(value: unknown): Record<string, unknown> {
  return value != null && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> :
    {};
}

function invalid(field: string, message: string, appCode = "INVALID_INPUT"): HttpsError {
  return new HttpsError("invalid-argument", message, {appCode, field});
}

function validDocId(value: unknown): value is string {
  return typeof value === "string" &&
    value.length > 0 &&
    value.length <= ID_MAX &&
    value.trim() === value &&
    !value.includes("/") &&
    value !== "." &&
    value !== ".." &&
    !/^__.*__$/.test(value);
}

function parseReason(value: unknown): string {
  if (typeof value !== "string") throw invalid("reason", "reason is required.");
  const trimmed = value.trim();
  if (trimmed.length < REASON_MIN || trimmed.length > REASON_MAX) {
    throw invalid("reason", `reason must be ${REASON_MIN}-${REASON_MAX} characters.`);
  }
  if (CONTROL_CHARS.test(trimmed)) throw invalid("reason", "reason contains control characters.");
  if (containsRawContact(trimmed)) throw invalid("reason", "Don't put a phone number or email in the reason.");
  return trimmed;
}

function parseRequestId(value: unknown): string {
  if (typeof value !== "string" || !REQUEST_ID_PATTERN.test(value)) {
    throw invalid("requestId", "requestId must be 8-64 letters, digits, _ or -.");
  }
  return value;
}

export type SingleInput = {
  mode: "single";
  bookingId: string;
  isTest: boolean;
  reason: string;
  requestId: string;
};

export type BackfillInput = {
  mode: "backfill";
  cutoff: Date;
  dryRun: boolean;
  expectedTestCount: number | null;
  expectedFingerprint: string | null;
  reason: string;
  requestId: string;
};

export function parseBookingTestFlagInput(raw: unknown): SingleInput | BackfillInput {
  const data = asRecord(raw);
  if (data.mode === "single") {
    if (!validDocId(data.bookingId)) throw invalid("bookingId", "bookingId is invalid.");
    if (typeof data.isTest !== "boolean") throw invalid("isTest", "isTest must be true or false.");
    return {
      mode: "single",
      bookingId: data.bookingId,
      isTest: data.isTest,
      reason: parseReason(data.reason),
      requestId: parseRequestId(data.requestId),
    };
  }
  if (data.mode === "backfill") {
    if (typeof data.cutoff !== "string" || !ISO_WITH_ZONE.test(data.cutoff)) {
      throw invalid("cutoff", "cutoff must be an ISO-8601 time with a zone, e.g. 2026-11-23T00:00:00+05:30.");
    }
    const cutoff = new Date(data.cutoff);
    if (Number.isNaN(cutoff.getTime())) throw invalid("cutoff", "cutoff is not a valid time.");
    if (cutoff.getTime() > BACKFILL_CUTOFF_CEILING.getTime()) {
      throw invalid("cutoff", "cutoff can't be later than 2026-11-23T00:00:00+05:30.");
    }
    if (typeof data.dryRun !== "boolean") throw invalid("dryRun", "dryRun must be true or false.");
    let expectedTestCount: number | null = null;
    let expectedFingerprint: string | null = null;
    if (!data.dryRun) {
      if (typeof data.expectedTestCount !== "number" || !Number.isInteger(data.expectedTestCount) ||
          data.expectedTestCount < 0 || data.expectedTestCount > BACKFILL_MAX_PER_CALL) {
        throw invalid("expectedTestCount", "expectedTestCount from the dry run is required.");
      }
      if (typeof data.expectedFingerprint !== "string" || !FINGERPRINT_PATTERN.test(data.expectedFingerprint)) {
        throw invalid("expectedFingerprint", "expectedFingerprint from the dry run is required.");
      }
      expectedTestCount = data.expectedTestCount;
      expectedFingerprint = data.expectedFingerprint;
    }
    return {
      mode: "backfill",
      cutoff,
      dryRun: data.dryRun,
      expectedTestCount,
      expectedFingerprint,
      reason: parseReason(data.reason),
      requestId: parseRequestId(data.requestId),
    };
  }
  throw invalid("mode", "mode must be single or backfill.");
}

function resolveDeps(deps: BookingTestFlagDeps) {
  return {
    firestore: deps.firestore ?? defaultDb,
    authClient: deps.authClient ?? defaultAuth,
  };
}

function auditFailed(error: unknown, details: Record<string, unknown>): HttpsError {
  logger.error("setBookingTestFlagForAdmin transaction failed", {
    ...details,
    error: error instanceof Error ? error.message : String(error),
  });
  return new HttpsError("internal", "Could not save the change, so nothing was changed.", {
    appCode: "AUDIT_WRITE_FAILED",
  });
}

export function singleLogDocId(adminUid: string, requestId: string): string {
  return `bookingTestFlag_${adminUid}_${requestId}`;
}

export function backfillLogDocId(adminUid: string, requestId: string): string {
  return `bookingTestBackfill_${adminUid}_${requestId}`;
}

/** sha256 of the sorted ids joined by "\n", first 12 hex characters. */
export function bookingIdsFingerprint(ids: readonly string[]): string {
  return createHash("sha256").update([...ids].sort().join("\n")).digest("hex").slice(0, 12);
}

// ---------------------------------------------------------------------------
// mode "single"
// ---------------------------------------------------------------------------

export type SingleResult = {
  mode: "single";
  bookingId: string;
  isTest: boolean;
  changed: boolean;
  logId: string | null;
};

async function setSingle(
  firestore: Firestore,
  actor: Awaited<ReturnType<typeof requireActiveSuperAdmin>>,
  input: SingleInput,
): Promise<SingleResult> {
  const bookingRef = firestore.collection("bookings").doc(input.bookingId);
  const flagRef = firestore.collection(BOOKING_TEST_FLAGS_COLLECTION).doc(input.bookingId);
  const logRef = firestore.collection(ADMIN_AUDIT_LOGS_COLLECTION).doc(singleLogDocId(actor.uid, input.requestId));
  try {
    return await firestore.runTransaction<SingleResult>(async (transaction) => {
      const [booking, flag, previousLog] = await transaction.getAll(bookingRef, flagRef, logRef);
      if (previousLog.exists) {
        // A retry of a request that already committed: same answer, no new row.
        const previous = previousLog.data() ?? {};
        if (previous.targetId === input.bookingId && asRecord(previous.after).isTest === input.isTest) {
          return {mode: "single", bookingId: input.bookingId, isTest: input.isTest, changed: false, logId: logRef.id};
        }
        throw invalid("requestId", "requestId was already used for a different change.", "REQUEST_ID_REUSED");
      }
      if (!booking.exists) {
        throw new HttpsError("not-found", "Booking not found.", {appCode: "BOOKING_NOT_FOUND"});
      }
      const wasTest = flag.exists;
      if (wasTest === input.isTest) {
        return {mode: "single", bookingId: input.bookingId, isTest: input.isTest, changed: false, logId: null};
      }
      const bookingData = booking.data() ?? {};
      const state = typeof bookingData.stateQueryValue === "string" ? bookingData.stateQueryValue :
        (typeof bookingData.state === "string" ? bookingData.state : null);
      const logId = await writeAdminLog(firestore, actor, {
        type: "booking",
        action: input.isTest ? "booking.test_marked" : "booking.test_unmarked",
        targetType: "booking",
        targetId: input.bookingId,
        before: {isTest: wasTest},
        after: {isTest: input.isTest},
        reason: input.reason,
        context: {bookingState: state},
        requestId: input.requestId,
        source: SET_BOOKING_TEST_FLAG_SOURCE,
      }, {transaction, docId: logRef.id});
      if (input.isTest) {
        transaction.create(flagRef, {
          bookingId: input.bookingId,
          source: "admin",
          markedAt: FieldValue.serverTimestamp(),
          markedByUid: actor.uid,
        });
      } else {
        transaction.delete(flagRef);
      }
      return {mode: "single", bookingId: input.bookingId, isTest: input.isTest, changed: true, logId};
    });
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw auditFailed(error, {adminUid: actor.uid, mode: "single", bookingId: input.bookingId});
  }
}

// ---------------------------------------------------------------------------
// mode "backfill"
// ---------------------------------------------------------------------------

export type BackfillResult = {
  mode: "backfill";
  dryRun: boolean;
  cutoff: string;
  /** Bookings this call marks (or would mark): at most BACKFILL_MAX_PER_CALL. */
  testCount: number;
  /** All bookings before the cutoff without a flag, before the per-call cap. */
  candidateCount: number;
  /** Candidates left for another call after this one. */
  remainingAfterThisCall: number;
  alreadyTest: number;
  afterCutoff: number;
  missingCreatedAt: number;
  bookingsScanned: number;
  earliestCreatedAt: string | null;
  latestCreatedAt: string | null;
  sampleIds: string[];
  fingerprint: string;
  logId: string | null;
};

function createdAtOf(doc: QueryDocumentSnapshot): Date | null {
  const value = doc.get("createdAt");
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value;
  return null;
}

async function readAllIds(firestore: Firestore, collection: string): Promise<QueryDocumentSnapshot[]> {
  const docs: QueryDocumentSnapshot[] = [];
  let last: QueryDocumentSnapshot | null = null;
  for (;;) {
    let query = firestore.collection(collection).orderBy(FieldPath.documentId()).limit(BOOKING_PAGE_SIZE);
    if (last) query = query.startAfter(last);
    const page = await query.get();
    docs.push(...page.docs);
    if (page.size < BOOKING_PAGE_SIZE) return docs;
    last = page.docs[page.docs.length - 1];
  }
}

type BackfillPlan = Omit<BackfillResult, "dryRun" | "logId"> & {ids: string[]};

async function planBackfill(firestore: Firestore, cutoff: Date): Promise<BackfillPlan> {
  const [bookings, flags] = await Promise.all([
    readAllIds(firestore, "bookings"),
    readAllIds(firestore, BOOKING_TEST_FLAGS_COLLECTION),
  ]);
  const flagged = new Set(flags.map((doc) => doc.id));
  const candidates: Array<{id: string; createdAt: Date}> = [];
  let alreadyTest = 0;
  let afterCutoff = 0;
  let missingCreatedAt = 0;
  for (const doc of bookings) {
    const createdAt = createdAtOf(doc);
    if (createdAt == null) {
      missingCreatedAt += 1;
    } else if (createdAt.getTime() >= cutoff.getTime()) {
      afterCutoff += 1;
    } else if (flagged.has(doc.id)) {
      alreadyTest += 1;
    } else {
      candidates.push({id: doc.id, createdAt});
    }
  }
  candidates.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  const batch = candidates.slice(0, BACKFILL_MAX_PER_CALL);
  const ids = batch.map((entry) => entry.id);
  const times = batch.map((entry) => entry.createdAt.getTime());
  return {
    mode: "backfill",
    cutoff: cutoff.toISOString(),
    testCount: batch.length,
    candidateCount: candidates.length,
    remainingAfterThisCall: candidates.length - batch.length,
    alreadyTest,
    afterCutoff,
    missingCreatedAt,
    bookingsScanned: bookings.length,
    earliestCreatedAt: times.length ? new Date(Math.min(...times)).toISOString() : null,
    latestCreatedAt: times.length ? new Date(Math.max(...times)).toISOString() : null,
    sampleIds: ids.slice(0, BACKFILL_SAMPLE_IDS),
    fingerprint: bookingIdsFingerprint(ids),
    ids,
  };
}

function withoutIds(plan: BackfillPlan): Omit<BackfillPlan, "ids"> {
  const copy: Partial<BackfillPlan> = {...plan};
  delete copy.ids;
  return copy as Omit<BackfillPlan, "ids">;
}

async function runBackfill(
  firestore: Firestore,
  actor: Awaited<ReturnType<typeof requireActiveSuperAdmin>>,
  input: BackfillInput,
): Promise<BackfillResult> {
  // Read-only scan of bookings and existing flags.
  const plan = await planBackfill(firestore, input.cutoff);
  if (input.dryRun) {
    return {...withoutIds(plan), dryRun: true, logId: null};
  }
  if (plan.testCount !== input.expectedTestCount) {
    throw new HttpsError("failed-precondition", "The bookings to mark changed since the dry run. Run it again.", {
      appCode: "COUNT_MISMATCH",
      expected: input.expectedTestCount,
      actual: plan.testCount,
    });
  }
  if (plan.fingerprint !== input.expectedFingerprint) {
    throw new HttpsError("failed-precondition", "The bookings to mark changed since the dry run. Run it again.", {
      appCode: "FINGERPRINT_MISMATCH",
    });
  }
  if (plan.testCount === 0) {
    return {...withoutIds(plan), dryRun: false, logId: null};
  }

  const logRef = firestore.collection(ADMIN_AUDIT_LOGS_COLLECTION).doc(backfillLogDocId(actor.uid, input.requestId));
  const flagRefs: DocumentReference[] = plan.ids.map((id) =>
    firestore.collection(BOOKING_TEST_FLAGS_COLLECTION).doc(id));
  try {
    const logId = await firestore.runTransaction<string>(async (transaction) => {
      const [previousLog, ...existingFlags] = await transaction.getAll(logRef, ...flagRefs);
      if (previousLog.exists) {
        throw invalid("requestId", "requestId was already used.", "REQUEST_ID_REUSED");
      }
      if (existingFlags.some((snapshot) => snapshot.exists)) {
        // Another change landed between the scan and this transaction.
        throw new HttpsError("failed-precondition", "The bookings to mark changed since the dry run. Run it again.", {
          appCode: "FINGERPRINT_MISMATCH",
        });
      }
      const id = await writeAdminLog(firestore, actor, {
        type: "booking",
        action: "booking.test_backfill",
        targetType: "bookingSet",
        targetId: plan.fingerprint,
        before: null,
        after: {cutoff: plan.cutoff, testCount: plan.testCount, bookingIds: plan.ids},
        reason: input.reason,
        context: {
          remainingAfterThisCall: plan.remainingAfterThisCall,
          alreadyTest: plan.alreadyTest,
          bookingsScanned: plan.bookingsScanned,
        },
        requestId: input.requestId,
        source: SET_BOOKING_TEST_FLAG_SOURCE,
      }, {transaction, docId: logRef.id});
      for (const ref of flagRefs) {
        transaction.create(ref, {
          bookingId: ref.id,
          source: "backfill",
          markedAt: FieldValue.serverTimestamp(),
          markedByUid: actor.uid,
          backfillLogId: id,
        });
      }
      return id;
    });
    logger.info("setBookingTestFlagForAdmin backfill", {
      logId,
      adminUid: actor.uid,
      testCount: plan.testCount,
      fingerprint: plan.fingerprint,
    });
    return {...withoutIds(plan), dryRun: false, logId};
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw auditFailed(error, {adminUid: actor.uid, mode: "backfill", fingerprint: plan.fingerprint});
  }
}

/**
 * setBookingTestFlagForAdmin. Active Super Admin only.
 *
 * - `single`: `{bookingId, isTest, reason, requestId}`. true creates the flag
 *   document, false deletes it. The booking must exist. Already in that
 *   state: `changed: false`, no log row. A retried requestId returns the same
 *   answer; a reused one for a different change is REQUEST_ID_REUSED.
 * - `backfill`: `{cutoff, dryRun, expectedTestCount?, expectedFingerprint?,
 *   reason, requestId}`. Flags bookings created before `cutoff` (never after
 *   BACKFILL_CUTOFF_CEILING) that have no flag yet, at most
 *   BACKFILL_MAX_PER_CALL per call. Dry runs write nothing and are not logged.
 *
 * Stable appCodes: UNAUTHENTICATED, SESSION_REVOKED, ROLE_NOT_ALLOWED,
 * ADMIN_NOT_ACTIVE, INVALID_INPUT, BOOKING_NOT_FOUND, REQUEST_ID_REUSED,
 * COUNT_MISMATCH, FINGERPRINT_MISMATCH, AUDIT_WRITE_FAILED.
 */
export async function setBookingTestFlagForAdminData(
  request: BookingTestFlagRequest,
  deps: BookingTestFlagDeps = {},
): Promise<SingleResult | BackfillResult> {
  const {firestore, authClient} = resolveDeps(deps);
  const actor = await requireActiveSuperAdmin(request, {firestore, authClient});
  const input = parseBookingTestFlagInput(request.data);
  return input.mode === "single" ?
    setSingle(firestore, actor, input) :
    runBackfill(firestore, actor, input);
}
