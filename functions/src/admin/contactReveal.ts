import type {Auth, UserRecord} from "firebase-admin/auth";
import type {DocumentSnapshot, Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {auth as defaultAuth, db as defaultDb} from "../shared/firebase";
import {
  ADMIN_ROLES,
  adminAccountIsInactive,
  requireActiveSuperAdmin,
  type AdminGuardRequest,
} from "./adminActor";
import {ADMIN_AUDIT_LOGS_COLLECTION, writeAdminLog, type AdminLogEntry} from "./adminLog";
import {
  CONTACT_REVEAL_LIMITS,
  CONTACT_SEARCH_LIMITS,
  readRateLimitInTransaction,
  recordRateLimitInTransaction,
} from "./adminRateLimit";
import {
  containsRawContact,
  maskEmail,
  maskEmailOrNull,
  maskPhone,
  maskPhoneOrNull,
  normalizeIndianPhone,
  pickPrivateEmail,
  pickPrivatePhone,
} from "./contactMasking";

// ---------------------------------------------------------------------------
// Shared types and constants
// ---------------------------------------------------------------------------

export type ContactDeps = {
  firestore?: Firestore;
  authClient?: Pick<Auth, "getUser" | "getUsers">;
  now?: () => Date;
};

export type ContactRequest = AdminGuardRequest & {data?: unknown};

/** Kill switch: reveals are refused unless this doc has `enabled: true`. */
export const CONTACT_REVEAL_ROLLOUT_PATH = "_rollouts/adminContactReveal";
/** Same value as BLOCKED_RELATIONSHIP_PAYMENT_HOLDS_COLLECTION (tested). */
export const PAYMENT_HOLDS_COLLECTION = "blockedRelationshipPaymentHolds";

/** Owner decision Q4. */
export const REVEAL_EXPIRES_IN_SECONDS = 30;
export const MASKED_CONTACTS_MAX_IDS = 50;
export const CONTACT_SEARCH_MAX_RESULTS = 5;
export const ADMIN_MEMBERS_MAX = 200;

/** Owner decision Q2. */
export const REVEAL_REASON_CODES = {
  CALLBACK_REQUESTED: "Customer asked for a call back",
  BOOKING_PROBLEM: "Booking problem",
  PAYMENT_HOLD: "Payment hold",
  SAFETY_MODERATION: "Safety or moderation",
  PROVIDER_VERIFICATION: "Provider verification",
  OTHER: "Other",
} as const;
export type RevealReasonCode = keyof typeof REVEAL_REASON_CODES;

export const REVEAL_FIELDS = ["phone", "email"] as const;
export type RevealField = typeof REVEAL_FIELDS[number];

export const REVEAL_PURPOSES = ["show", "call", "whatsapp", "email", "copy"] as const;
export type RevealPurpose = typeof REVEAL_PURPOSES[number];

const PURPOSES_BY_FIELD: Record<RevealField, readonly RevealPurpose[]> = {
  phone: ["show", "call", "whatsapp", "copy"],
  email: ["show", "email", "copy"],
};

export const REVEAL_CONTEXT_TYPES = [
  "booking",
  "user",
  "support",
  "moderation",
  "provider",
  "chat",
  "paymentHold",
] as const;
export type RevealContextType = typeof REVEAL_CONTEXT_TYPES[number];

const REASON_MIN = 3;
const REASON_MAX = 200;
const ID_MAX = 128;
const QUERY_MAX = 254;
const REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{8,64}$/;
// eslint-disable-next-line no-control-regex
const CONTROL_CHARS = /[\u0000-\u001f\u007f]/;

function asRecord(value: unknown): Record<string, unknown> {
  return value != null && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> :
    {};
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function invalid(field: string, message: string, appCode = "INVALID_INPUT"): HttpsError {
  return new HttpsError("invalid-argument", message, {appCode, field});
}

function validDocId(value: unknown): value is string {
  return typeof value === "string" &&
    value.length > 0 &&
    value.length <= ID_MAX &&
    value.trim() === value &&
    !value.includes("/");
}

function resolveDeps(deps: ContactDeps) {
  return {
    firestore: deps.firestore ?? defaultDb,
    authClient: deps.authClient ?? defaultAuth,
    now: deps.now ?? (() => new Date()),
  };
}

async function loadAuthUser(
  authClient: Pick<Auth, "getUser">,
  uid: string,
): Promise<UserRecord | null> {
  try {
    return await authClient.getUser(uid);
  } catch (error) {
    if (asRecord(error).code === "auth/user-not-found") return null;
    throw error;
  }
}

// ---------------------------------------------------------------------------
// getMaskedContactsForAdmin
// ---------------------------------------------------------------------------

export type MaskedUserContact = {
  maskedPhone: string | null;
  maskedEmail: string | null;
  hasPhone: boolean;
  hasEmail: boolean;
};

export type MaskedTicketContact = {
  maskedPhone: string | null;
  hasPhone: boolean;
};

function parseIdList(value: unknown, field: string): string[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > MASKED_CONTACTS_MAX_IDS) {
    throw invalid(field, `${field} must list 1-${MASKED_CONTACTS_MAX_IDS} ids.`);
  }
  if (!value.every(validDocId)) throw invalid(field, `${field} contains an invalid id.`);
  if (new Set(value).size !== value.length) throw invalid(field, `${field} contains duplicates.`);
  return value as string[];
}

/**
 * Masked phone and email for display. Reads userPrivate only (no Auth
 * fallback). Unknown ids get the empty shape, never not-found, so the call
 * can't probe which accounts exist. No audit row: masked values reveal
 * nothing new.
 */
export async function getMaskedContactsForAdminData(request: ContactRequest, deps: ContactDeps = {}) {
  const {firestore, authClient} = resolveDeps(deps);
  await requireActiveSuperAdmin(request, {firestore, authClient});
  const data = asRecord(request.data);
  const hasUsers = data.userIds !== undefined;
  const hasTickets = data.supportTicketIds !== undefined;
  if (hasUsers === hasTickets) {
    throw invalid("userIds", "Send exactly one of userIds or supportTicketIds.");
  }

  if (hasUsers) {
    const userIds = parseIdList(data.userIds, "userIds");
    const snapshots = await firestore.getAll(
      ...userIds.map((uid) => firestore.collection("userPrivate").doc(uid)),
    );
    const contacts: Record<string, MaskedUserContact> = {};
    userIds.forEach((uid, index) => {
      const privateData = snapshots[index]?.exists ? snapshots[index].data() ?? {} : {};
      const phone = pickPrivatePhone(privateData)?.value ?? null;
      const email = pickPrivateEmail(privateData);
      contacts[uid] = {
        maskedPhone: maskPhoneOrNull(phone),
        maskedEmail: maskEmailOrNull(email),
        hasPhone: phone != null,
        hasEmail: email != null,
      };
    });
    return {contacts};
  }

  const ticketIds = parseIdList(data.supportTicketIds, "supportTicketIds");
  const snapshots = await firestore.getAll(
    ...ticketIds.map((id) => firestore.collection("supportTickets").doc(id)),
  );
  const tickets: Record<string, MaskedTicketContact> = {};
  ticketIds.forEach((id, index) => {
    const phone = snapshots[index]?.exists ? text(snapshots[index].data()?.contactNumber) : "";
    tickets[id] = {maskedPhone: maskPhoneOrNull(phone), hasPhone: phone.length > 0};
  });
  return {tickets};
}

// ---------------------------------------------------------------------------
// findUsersByContactForAdmin
// ---------------------------------------------------------------------------

type ContactQuery =
  | {matchedOn: "email"; values: string[]}
  | {matchedOn: "phone"; values: string[]};

export function classifyContactQuery(raw: unknown): ContactQuery {
  if (typeof raw !== "string") throw invalid("query", "query must be a string.");
  const query = raw.trim();
  if (!query || query.length > QUERY_MAX) throw invalid("query", "query is empty or too long.");
  if (query.includes("@")) {
    if (maskEmail(query) === "•••") {
      throw invalid("query", "Enter a full email address or phone number.", "INVALID_QUERY");
    }
    const lower = query.toLowerCase();
    return {matchedOn: "email", values: lower === query ? [lower] : [lower, query]};
  }
  const phone = normalizeIndianPhone(query);
  if (!phone) throw invalid("query", "Enter a full email address or phone number.", "INVALID_QUERY");
  return {matchedOn: "phone", values: [phone]};
}

/**
 * Exact-match search on userPrivate by email (lower-cased and as typed) or by
 * phone (E.164, across phoneNumber, phone and mobileNumber). Rate limited in
 * its own bucket. Logs `contact.search` with the match count only: the query
 * itself is never stored, not even as a hash (owner decision Q8).
 */
export async function findUsersByContactForAdminData(request: ContactRequest, deps: ContactDeps = {}) {
  const {firestore, authClient, now} = resolveDeps(deps);
  const actor = await requireActiveSuperAdmin(request, {firestore, authClient});
  const classified = classifyContactQuery(asRecord(request.data).query);
  const nowMs = now().getTime();

  const limited = await firestore.runTransaction(async (transaction) => {
    const decision = await readRateLimitInTransaction({
      transaction, firestore, adminUid: actor.uid, bucket: "contactSearch",
      limits: CONTACT_SEARCH_LIMITS, nowMs,
    });
    if (!decision.allowed) {
      await writeAdminLog(firestore, actor, {
        type: "contact",
        action: "contact.search_denied",
        targetType: "query",
        targetId: "",
        after: {matchedOn: classified.matchedOn, outcome: "RATE_LIMITED"},
        source: "findUsersByContactForAdmin",
      }, {transaction});
      return decision;
    }
    recordRateLimitInTransaction({transaction, firestore, adminUid: actor.uid, bucket: "contactSearch", decision});
    return null;
  });
  if (limited) {
    throw new HttpsError("resource-exhausted", "Too many contact searches. Try again later.", {
      appCode: "RATE_LIMITED",
      retryAfterSeconds: limited.retryAfterSeconds,
    });
  }

  const fields = classified.matchedOn === "email" ?
    ["email"] :
    ["phoneNumber", "phone", "mobileNumber"];
  const queries: Promise<{docs: DocumentSnapshot[]}>[] = [];
  for (const field of fields) {
    for (const value of classified.values) {
      queries.push(firestore.collection("userPrivate")
        .where(field, "==", value)
        .limit(CONTACT_SEARCH_MAX_RESULTS)
        .get());
    }
  }
  const results = await Promise.all(queries);
  const seen = new Map<string, Record<string, unknown>>();
  for (const result of results) {
    for (const doc of result.docs) {
      if (!seen.has(doc.id) && seen.size < CONTACT_SEARCH_MAX_RESULTS) {
        seen.set(doc.id, doc.data() ?? {});
      }
    }
  }
  const matches = [...seen.entries()].map(([userId, privateData]) => ({
    userId,
    maskedPhone: maskPhoneOrNull(pickPrivatePhone(privateData)?.value),
    maskedEmail: maskEmailOrNull(pickPrivateEmail(privateData)),
    matchedOn: classified.matchedOn,
  }));

  await writeAdminLog(firestore, actor, {
    type: "contact",
    action: "contact.search",
    targetType: "query",
    targetId: "",
    after: {matchCount: matches.length, matchedOn: classified.matchedOn},
    source: "findUsersByContactForAdmin",
  });
  return {matches};
}

// ---------------------------------------------------------------------------
// revealContactForAdmin
// ---------------------------------------------------------------------------

export type RevealInput = {
  target: {kind: "user"; userId: string} | {kind: "supportTicket"; ticketId: string};
  field: RevealField;
  purpose: RevealPurpose;
  reasonCode: RevealReasonCode;
  reasonText: string | null;
  context: {type: RevealContextType; id: string};
  requestId: string;
};

export function parseRevealInput(raw: unknown): RevealInput {
  const data = asRecord(raw);
  const hasUser = data.userId !== undefined;
  const hasTicket = data.supportTicketId !== undefined;
  if (hasUser === hasTicket) throw invalid("userId", "Send exactly one of userId or supportTicketId.");
  if (hasUser && !validDocId(data.userId)) throw invalid("userId", "userId is invalid.");
  if (hasTicket && !validDocId(data.supportTicketId)) throw invalid("supportTicketId", "supportTicketId is invalid.");

  const field = data.field;
  if (typeof field !== "string" || !(REVEAL_FIELDS as readonly string[]).includes(field)) {
    throw invalid("field", "field must be phone or email.");
  }
  const purpose = data.purpose;
  if (typeof purpose !== "string" || !PURPOSES_BY_FIELD[field as RevealField].includes(purpose as RevealPurpose)) {
    throw invalid("purpose", `purpose is not allowed for ${field}.`);
  }
  if (hasTicket && field !== "phone") throw invalid("field", "A support ticket only has a phone number.");

  const reasonCode = data.reasonCode;
  if (typeof reasonCode !== "string" || !Object.prototype.hasOwnProperty.call(REVEAL_REASON_CODES, reasonCode)) {
    throw invalid("reasonCode", "reasonCode is required.");
  }
  let reasonText: string | null = null;
  if (data.reason !== undefined && data.reason !== null) {
    if (typeof data.reason !== "string") throw invalid("reason", "reason must be text.");
    const trimmed = data.reason.trim();
    if (trimmed.length < REASON_MIN || trimmed.length > REASON_MAX) {
      throw invalid("reason", `reason must be ${REASON_MIN}-${REASON_MAX} characters.`);
    }
    if (CONTROL_CHARS.test(trimmed)) throw invalid("reason", "reason contains control characters.");
    if (containsRawContact(trimmed)) {
      throw invalid("reason", "Don't put a phone number or email in the reason.");
    }
    reasonText = trimmed;
  }
  if (reasonCode === "OTHER" && !reasonText) throw invalid("reason", "Describe the reason for Other.");

  const context = asRecord(data.context);
  const contextType = context.type;
  if (typeof contextType !== "string" || !(REVEAL_CONTEXT_TYPES as readonly string[]).includes(contextType)) {
    throw invalid("context", "context.type is invalid.");
  }
  if (!validDocId(context.id)) throw invalid("context", "context.id is invalid.");
  if (hasTicket && (contextType !== "support" || context.id !== data.supportTicketId)) {
    throw invalid("context", "A support ticket reveal needs the support context for that ticket.");
  }

  if (typeof data.requestId !== "string" || !REQUEST_ID_PATTERN.test(data.requestId)) {
    throw invalid("requestId", "requestId must be 8-64 letters, digits, _ or -.");
  }

  return {
    target: hasUser ?
      {kind: "user", userId: data.userId as string} :
      {kind: "supportTicket", ticketId: data.supportTicketId as string},
    field: field as RevealField,
    purpose: purpose as RevealPurpose,
    reasonCode: reasonCode as RevealReasonCode,
    reasonText,
    context: {type: contextType as RevealContextType, id: context.id as string},
    requestId: data.requestId,
  };
}

/** Owner decision Q9: server-side checks for booking, support and paymentHold only. */
async function contextMatchesUser(firestore: Firestore, input: RevealInput, userId: string): Promise<boolean> {
  const {type, id} = input.context;
  if (type === "booking") {
    const snapshot = await firestore.collection("bookings").doc(id).get();
    if (!snapshot.exists) return false;
    const booking = snapshot.data() ?? {};
    return ["parentId", "customerId", "providerId", "serviceOwnerId"]
      .some((key) => text(booking[key]) === userId);
  }
  if (type === "support") {
    const snapshot = await firestore.collection("supportTickets").doc(id).get();
    return snapshot.exists && text(snapshot.data()?.userId) === userId;
  }
  if (type === "paymentHold") {
    const snapshot = await firestore.collection(PAYMENT_HOLDS_COLLECTION).doc(id).get();
    if (!snapshot.exists) return false;
    const hold = snapshot.data() ?? {};
    return text(hold.parentId) === userId || text(hold.providerId) === userId;
  }
  return true;
}

type LoadedValue = {
  value: string | null;
  valueSource: string;
};

export function revealLogDocId(adminUid: string, requestId: string): string {
  return `contactReveal_${adminUid}_${requestId}`;
}

export type RevealResult = {
  value: string;
  valueMasked: string;
  field: RevealField;
  purpose: RevealPurpose;
  outcome: "REVEALED";
  repeat: boolean;
  expiresInSeconds: number;
  logId: string;
};

/**
 * Returns one full phone number or email to an active Super Admin, once.
 *
 * The audit row is written in the same transaction as the rate-limit update
 * and is committed before the value leaves this function; if the commit
 * fails, nothing is returned. The full value is never stored: rows carry
 * only the masked value. Refused (rate limit, context mismatch, unknown
 * target) and empty attempts are logged too.
 */
export async function revealContactForAdminData(
  request: ContactRequest,
  deps: ContactDeps = {},
): Promise<RevealResult> {
  const {firestore, authClient, now} = resolveDeps(deps);
  const actor = await requireActiveSuperAdmin(request, {firestore, authClient});
  const input = parseRevealInput(request.data);

  const rollout = await firestore.doc(CONTACT_REVEAL_ROLLOUT_PATH).get();
  if (rollout.data()?.enabled !== true) {
    throw new HttpsError("failed-precondition", "Contact reveal is switched off.", {appCode: "REVEAL_DISABLED"});
  }

  const targetType = input.target.kind === "user" ? "user" : "supportTicket";
  const targetId = input.target.kind === "user" ? input.target.userId : input.target.ticketId;
  const reason = input.reasonText ?? REVEAL_REASON_CODES[input.reasonCode];
  const context = {type: input.context.type, id: input.context.id, purpose: input.purpose};
  const baseEntry = {
    type: "contact" as const,
    targetType: targetType as AdminLogEntry["targetType"],
    targetId,
    before: null,
    reason,
    reasonCode: input.reasonCode,
    context,
    requestId: input.requestId,
    source: "revealContactForAdmin",
  };
  const logDenied = (outcome: string) => writeAdminLog(firestore, actor, {
    ...baseEntry,
    action: "contact.reveal_denied",
    after: {field: input.field, outcome},
  });

  // Load the target and the value (outside the transaction: Auth can't join one).
  let loaded: LoadedValue;
  if (input.target.kind === "supportTicket") {
    const ticket = await firestore.collection("supportTickets").doc(input.target.ticketId).get();
    if (!ticket.exists) {
      const logId = await logDenied("TARGET_NOT_FOUND");
      throw new HttpsError("not-found", "Support ticket not found.", {appCode: "TARGET_NOT_FOUND", logId});
    }
    loaded = {value: text(ticket.data()?.contactNumber) || null, valueSource: "supportTicket.contactNumber"};
  } else {
    const userId = input.target.userId;
    if (!(await contextMatchesUser(firestore, input, userId))) {
      const logId = await logDenied("CONTEXT_MISMATCH");
      throw new HttpsError("failed-precondition", "This user is not part of that context.", {
        appCode: "CONTEXT_MISMATCH",
        logId,
      });
    }
    const [privateSnapshot, userSnapshot] = await Promise.all([
      firestore.collection("userPrivate").doc(userId).get(),
      firestore.collection("users").doc(userId).get(),
    ]);
    if (!privateSnapshot.exists && !userSnapshot.exists) {
      const logId = await logDenied("TARGET_NOT_FOUND");
      throw new HttpsError("not-found", "User not found.", {appCode: "TARGET_NOT_FOUND", logId});
    }
    const privateData = privateSnapshot.data() ?? {};
    if (input.field === "phone") {
      const phone = pickPrivatePhone(privateData);
      loaded = phone ?
        {value: phone.value, valueSource: `userPrivate.${phone.source}`} :
        {value: null, valueSource: "auth.phoneNumber"};
    } else {
      const email = pickPrivateEmail(privateData);
      loaded = email ? {value: email, valueSource: "userPrivate.email"} : {value: null, valueSource: "auth.email"};
    }
    if (loaded.value == null) {
      const authUser = await loadAuthUser(authClient, userId);
      const authValue = input.field === "phone" ? text(authUser?.phoneNumber) : text(authUser?.email);
      loaded = {value: authValue || null, valueSource: authValue ? loaded.valueSource : "none"};
    }
  }

  const valueMasked = loaded.value == null ?
    null :
    (input.field === "phone" ? maskPhone(loaded.value) : maskEmail(loaded.value));
  const outcome = loaded.value == null ? "NOT_AVAILABLE" : "REVEALED";
  const nowMs = now().getTime();
  const firstLogRef = firestore.collection(ADMIN_AUDIT_LOGS_COLLECTION).doc(revealLogDocId(actor.uid, input.requestId));

  type TxResult =
    | {kind: "rate_limited"; retryAfterSeconds: number; logId: string}
    | {kind: "logged"; logId: string; repeat: boolean};
  let txResult: TxResult;
  try {
    txResult = await firestore.runTransaction<TxResult>(async (transaction) => {
      const decision = await readRateLimitInTransaction({
        transaction, firestore, adminUid: actor.uid, bucket: "contactReveal",
        limits: CONTACT_REVEAL_LIMITS, nowMs,
      });
      const firstLog = await transaction.get(firstLogRef);
      if (firstLog.exists) {
        const previous = firstLog.data() ?? {};
        const previousAfter = asRecord(previous.after);
        if (previous.targetId !== targetId || previous.targetType !== targetType ||
            previousAfter.field !== input.field) {
          throw invalid("requestId", "requestId was already used for a different reveal.", "REQUEST_ID_REUSED");
        }
      }
      if (!decision.allowed) {
        const logId = await writeAdminLog(firestore, actor, {
          ...baseEntry,
          action: "contact.reveal_denied",
          after: {field: input.field, outcome: "RATE_LIMITED", retryAfterSeconds: decision.retryAfterSeconds},
        }, {transaction});
        return {kind: "rate_limited", retryAfterSeconds: decision.retryAfterSeconds, logId};
      }
      const repeat = firstLog.exists;
      const action = outcome === "NOT_AVAILABLE" ?
        "contact.reveal_empty" :
        (repeat ? "contact.reveal_repeat" : "contact.reveal");
      const logId = await writeAdminLog(firestore, actor, {
        ...baseEntry,
        action,
        after: {
          field: input.field,
          outcome,
          valueMasked,
          valueSource: loaded.valueSource,
          hourCount: decision.hourCount,
          dayCount: decision.dayCount,
        },
      }, repeat ? {transaction} : {transaction, docId: firstLogRef.id});
      recordRateLimitInTransaction({transaction, firestore, adminUid: actor.uid, bucket: "contactReveal", decision});
      return {kind: "logged", logId, repeat};
    });
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    logger.error("revealContactForAdmin audit transaction failed", {
      adminUid: actor.uid,
      targetType,
      targetId,
      field: input.field,
      error: error instanceof Error ? error.message : String(error),
    });
    throw new HttpsError("internal", "Could not record the reveal, so nothing was shown.", {
      appCode: "AUDIT_WRITE_FAILED",
    });
  }

  if (txResult.kind === "rate_limited") {
    throw new HttpsError("resource-exhausted", "You've shown a lot of contact details. Try again later.", {
      appCode: "RATE_LIMITED",
      retryAfterSeconds: txResult.retryAfterSeconds,
      logId: txResult.logId,
    });
  }
  logger.info("revealContactForAdmin", {
    logId: txResult.logId,
    adminUid: actor.uid,
    targetType,
    targetId,
    field: input.field,
    outcome,
  });
  if (loaded.value == null || valueMasked == null) {
    throw new HttpsError("failed-precondition", "No contact detail on file.", {
      appCode: "NO_CONTACT_ON_FILE",
      logId: txResult.logId,
    });
  }
  return {
    value: loaded.value,
    valueMasked,
    field: input.field,
    purpose: input.purpose,
    outcome: "REVEALED",
    repeat: txResult.repeat,
    expiresInSeconds: REVEAL_EXPIRES_IN_SECONDS,
    logId: txResult.logId,
  };
}

// ---------------------------------------------------------------------------
// listAdminMembersForSuperAdmin
// ---------------------------------------------------------------------------

export type AdminMember = {
  uid: string;
  displayName: string;
  email: string | null;
  adminRole: string;
  status: "active" | "inactive";
  providers: string[];
};

function stringList(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((entry): entry is string => typeof entry === "string" && entry.length > 0) : [];
}

/**
 * Admin accounts only (users.adminRole is one of the three roles), for the
 * Team page. Not a contact reveal: not logged and not rate limited (owner
 * decision Q11).
 */
export async function listAdminMembersForSuperAdminData(request: ContactRequest, deps: ContactDeps = {}) {
  const {firestore, authClient} = resolveDeps(deps);
  await requireActiveSuperAdmin(request, {firestore, authClient});
  const snapshot = await firestore.collection("users")
    .where("adminRole", "in", [...ADMIN_ROLES])
    .limit(ADMIN_MEMBERS_MAX)
    .get();
  const docs = snapshot.docs;
  if (docs.length === 0) return {members: [] as AdminMember[]};

  const privateSnapshots = await firestore.getAll(
    ...docs.map((doc) => firestore.collection("userPrivate").doc(doc.id)),
  );
  const authById = new Map<string, UserRecord>();
  for (let index = 0; index < docs.length; index += 100) {
    const chunk = docs.slice(index, index + 100).map((doc) => ({uid: doc.id}));
    const result = await authClient.getUsers(chunk);
    for (const user of result.users) authById.set(user.uid, user);
  }

  const members: AdminMember[] = docs.map((doc, index) => {
    const data = doc.data() ?? {};
    const privateData = privateSnapshots[index]?.exists ? privateSnapshots[index].data() ?? {} : {};
    const authUser = authById.get(doc.id);
    const privateProviders = stringList(privateData.providers);
    const authProviders = (authUser?.providerData ?? []).map((entry) => entry.providerId).filter(Boolean);
    const inactive = adminAccountIsInactive(data) || authUser?.disabled === true || authUser == null;
    return {
      uid: doc.id,
      displayName: text(data.displayName) || text(data.name) || "",
      email: pickPrivateEmail(privateData) ?? (text(authUser?.email) || null),
      adminRole: text(data.adminRole),
      status: inactive ? "inactive" : "active",
      providers: privateProviders.length > 0 ? privateProviders : authProviders,
    };
  });
  members.sort((a, b) => a.displayName.localeCompare(b.displayName) || a.uid.localeCompare(b.uid));
  return {members};
}

