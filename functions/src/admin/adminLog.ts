import {
  FieldValue,
  type DocumentReference,
  type Firestore,
  type Transaction,
} from "firebase-admin/firestore";
import type {ActiveAdmin} from "./adminActor";
import {containsRawContact} from "./contactMasking";

/**
 * Shared writer for NEW admin actions (adminAuditLogs, schemaVersion 2).
 *
 * The six older row shapes (offer, restriction, service moderation, report
 * moderation, dispute resolution and account events) are written by their
 * own code and are not migrated here.
 */

export const ADMIN_AUDIT_LOGS_COLLECTION = "adminAuditLogs";
export const ADMIN_LOG_SCHEMA_VERSION = 2;

export const ADMIN_LOG_TYPES = ["contact", "booking"] as const;
export type AdminLogType = typeof ADMIN_LOG_TYPES[number];

export const ADMIN_LOG_ACTIONS = [
  "contact.reveal",
  "contact.reveal_repeat",
  "contact.reveal_empty",
  "contact.reveal_denied",
  "contact.search",
  "contact.search_denied",
  "booking.test_marked",
  "booking.test_unmarked",
  "booking.test_backfill",
] as const;
export type AdminLogAction = typeof ADMIN_LOG_ACTIONS[number];

export const ADMIN_LOG_TARGET_TYPES = ["user", "supportTicket", "query", "booking", "bookingSet"] as const;
export type AdminLogTargetType = typeof ADMIN_LOG_TARGET_TYPES[number];

export const ADMIN_LOG_REASON_MAX_LENGTH = 300;

export type AdminLogEntry = {
  type: AdminLogType;
  action: AdminLogAction;
  targetType: AdminLogTargetType;
  targetId: string;
  before?: Record<string, unknown> | null;
  after?: Record<string, unknown> | null;
  reason?: string | null;
  reasonCode?: string | null;
  context?: Record<string, unknown> | null;
  requestId?: string | null;
  /** The callable that wrote the row, e.g. "revealContactForAdmin". */
  source: string;
};

export class AdminLogValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AdminLogValidationError";
  }
}

function collectStrings(value: unknown, path: string, out: Array<[string, string]>): void {
  if (typeof value === "string") {
    out.push([path, value]);
  } else if (Array.isArray(value)) {
    value.forEach((entry, index) => collectStrings(entry, `${path}[${index}]`, out));
  } else if (value != null && typeof value === "object" && !(value instanceof Date)) {
    for (const [key, entry] of Object.entries(value as Record<string, unknown>)) {
      collectStrings(entry, `${path}.${key}`, out);
    }
  }
}

/**
 * Throws if any string in before/after/context/reason looks like a raw phone
 * number or email address. Masked values (`+91 90•••• •001`,
 * `as***@example.com`) pass. This is a backstop so a full value can never be
 * logged by mistake.
 */
export function assertNoRawContactInLog(entry: Pick<AdminLogEntry, "before" | "after" | "context" | "reason">): void {
  const strings: Array<[string, string]> = [];
  collectStrings(entry.before ?? null, "before", strings);
  collectStrings(entry.after ?? null, "after", strings);
  collectStrings(entry.context ?? null, "context", strings);
  collectStrings(entry.reason ?? null, "reason", strings);
  for (const [path, value] of strings) {
    if (containsRawContact(value)) {
      throw new AdminLogValidationError(`Admin log field ${path} looks like a raw phone number or email.`);
    }
  }
}

/** Validates an entry and builds the stored row (without timestamps). */
export function buildAdminLogRow(actor: ActiveAdmin, entry: AdminLogEntry): Record<string, unknown> {
  if (!(ADMIN_LOG_TYPES as readonly string[]).includes(entry.type)) {
    throw new AdminLogValidationError(`Unknown admin log type: ${entry.type}`);
  }
  if (!(ADMIN_LOG_ACTIONS as readonly string[]).includes(entry.action)) {
    throw new AdminLogValidationError(`Unknown admin log action: ${entry.action}`);
  }
  if (!(ADMIN_LOG_TARGET_TYPES as readonly string[]).includes(entry.targetType)) {
    throw new AdminLogValidationError(`Unknown admin log target type: ${entry.targetType}`);
  }
  if (typeof entry.targetId !== "string") {
    throw new AdminLogValidationError("targetId must be a string.");
  }
  if (!actor.uid) throw new AdminLogValidationError("Admin log requires an actor.");
  if (!entry.source) throw new AdminLogValidationError("Admin log requires a source.");
  const reason = typeof entry.reason === "string" ? entry.reason.trim() : null;
  if (reason && reason.length > ADMIN_LOG_REASON_MAX_LENGTH) {
    throw new AdminLogValidationError(`reason is longer than ${ADMIN_LOG_REASON_MAX_LENGTH} characters.`);
  }
  assertNoRawContactInLog({...entry, reason});

  return {
    schemaVersion: ADMIN_LOG_SCHEMA_VERSION,
    byUid: actor.uid,
    byName: actor.displayName,
    byRole: actor.role,
    type: entry.type,
    action: entry.action,
    targetType: entry.targetType,
    targetId: entry.targetId,
    before: entry.before ?? null,
    after: entry.after ?? null,
    reason: reason || null,
    reasonCode: entry.reasonCode ?? null,
    context: entry.context ?? null,
    requestId: entry.requestId ?? null,
    source: entry.source,
  };
}

export type WriteAdminLogOptions = {
  /** Write inside this transaction; the row commits with the caller's writes. */
  transaction?: Transaction;
  /** Fixed document id. The write fails if the document already exists. */
  docId?: string;
};

/**
 * Writes one schemaVersion 2 row to adminAuditLogs and returns its id.
 *
 * `at` and `createdAt` hold the same server timestamp (`createdAt` is what
 * the dashboard Team log orders by). With `transaction`, the row is created
 * in that transaction and only exists if it commits; otherwise the write is
 * awaited before this resolves.
 */
export async function writeAdminLog(
  firestore: Firestore,
  actor: ActiveAdmin,
  entry: AdminLogEntry,
  options: WriteAdminLogOptions = {},
): Promise<string> {
  const row = buildAdminLogRow(actor, entry);
  const now = FieldValue.serverTimestamp();
  const collection = firestore.collection(ADMIN_AUDIT_LOGS_COLLECTION);
  const ref: DocumentReference = options.docId ? collection.doc(options.docId) : collection.doc();
  const data = {...row, at: now, createdAt: now};
  if (options.transaction) {
    options.transaction.create(ref, data);
  } else {
    await ref.create(data);
  }
  return ref.id;
}
