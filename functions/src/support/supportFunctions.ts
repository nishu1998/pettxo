import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {db, storage} from "../shared/firebase";
import {
  normalizePhoneLoginNumber,
  validatePhoneLoginNumber,
} from "../phoneLoginEligibility";

const SUPPORT_ADMIN_ROLES = new Set(["superAdmin", "customerSupportAdmin"]);
const SUPPORT_TICKET_CATEGORIES = new Set([
  "booking",
  "payment",
  "refund",
  "account",
  "provider",
  "safety",
  "technical_issue",
  "other",
]);
const SUPPORT_TICKET_STATUSES = new Set([
  "open",
  "awaiting_support",
  "awaiting_customer",
  "resolved",
]);
const MAX_SUBJECT_LENGTH = 120;
const MAX_MESSAGE_LENGTH = 4000;
const MAX_ATTACHMENT_COUNT = 3;
const MAX_ATTACHMENT_SIZE_BYTES = 5 * 1024 * 1024;
const SUPPORTED_ATTACHMENT_CONTENT_TYPES = new Set([
  "image/jpeg",
  "image/jpg",
  "image/png",
  "image/webp",
]);

type SupportActor = {
  uid: string;
  displayName: string;
  username: string;
  adminRole: string;
};

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function truncatedPreview(value: string, maxLength = 160): string {
  const normalized = value.replace(/\s+/g, " ").trim();
  if (normalized.length <= maxLength) return normalized;
  return `${normalized.slice(0, Math.max(0, maxLength - 1)).trimEnd()}…`;
}

function ensureValidCategory(value: string): string {
  if (!SUPPORT_TICKET_CATEGORIES.has(value)) {
    throw new HttpsError("invalid-argument", "Support category is invalid.");
  }
  return value;
}

function ensureValidStatus(value: string): string {
  if (!SUPPORT_TICKET_STATUSES.has(value)) {
    throw new HttpsError("invalid-argument", "Support status is invalid.");
  }
  return value;
}

export function assertSupportTicketAllowsAdminReply(status: unknown): void {
  if (asTrimmedString(status) === "resolved") {
    throw new HttpsError(
      "failed-precondition",
      "This support ticket has already been resolved.",
    );
  }
}

function ensureValidMessage(value: string): string {
  const message = value.trim();
  if (!message) {
    throw new HttpsError("invalid-argument", "Message is required.");
  }
  if (message.length > MAX_MESSAGE_LENGTH) {
    throw new HttpsError("invalid-argument", "Message is too long.");
  }
  return message;
}

function ensureValidContactNumber(value: unknown): string {
  const normalized = normalizePhoneLoginNumber(value);
  const validationError = validatePhoneLoginNumber(normalized);
  if (validationError) {
    throw new HttpsError("invalid-argument", validationError);
  }
  return normalized;
}

function sanitizeAttachmentFileName(value: unknown): string {
  const raw = asTrimmedString(value).replace(/\s+/g, " ");
  if (!raw) return "attachment.jpg";
  return raw.slice(0, 140);
}

function ensureValidAttachmentPath(path: string, uid: string, ticketId: string) {
  const normalized = path.trim();
  const expectedPrefix = `supportTickets/${uid}/${ticketId}/`;
  if (!normalized.startsWith(expectedPrefix) || normalized.includes("..")) {
    throw new HttpsError("invalid-argument", "Attachment path is invalid.");
  }
  return normalized;
}

async function loadSignedInActor(uid: string): Promise<SupportActor> {
  const snapshot = await db.collection("users").doc(uid).get();
  if (!snapshot.exists) {
    throw new HttpsError("failed-precondition", "User profile not found.");
  }

  const data = snapshot.data() ?? {};
  const accountStatus = asTrimmedString(data.accountStatus);
  if (accountStatus && accountStatus !== "active") {
    throw new HttpsError(
      "failed-precondition",
      "This account cannot use support right now.",
    );
  }

  const displayName = asTrimmedString(data.name) ||
    asTrimmedString(data.displayName) ||
    "Pettxo user";

  return {
    uid,
    displayName,
    username: asTrimmedString(data.username),
    adminRole: asTrimmedString(data.adminRole),
  };
}

async function requireSupportAdmin(uid: string): Promise<SupportActor> {
  const actor = await loadSignedInActor(uid);
  if (!SUPPORT_ADMIN_ROLES.has(actor.adminRole)) {
    throw new HttpsError(
      "permission-denied",
      "You are not allowed to manage support tickets.",
    );
  }
  return actor;
}

async function loadOwnedTicketForCustomer(ticketId: string, uid: string) {
  const ticketRef = db.collection("supportTickets").doc(ticketId);
  const snapshot = await ticketRef.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Support ticket not found.");
  }
  const data = snapshot.data() ?? {};
  if (asTrimmedString(data.userId) !== uid) {
    throw new HttpsError(
      "permission-denied",
      "This support ticket is not available to your account.",
    );
  }
  return {ticketRef, snapshot, data};
}

async function createSupportReplyNotification(params: {
  ticketId: string;
  recipientUserId: string;
  senderId: string;
  senderDisplayName: string;
  subject: string;
  message: string;
}) {
  if (!params.recipientUserId || params.recipientUserId === params.senderId) {
    return;
  }

  await db.collection("notifications").add({
    userId: params.recipientUserId,
    recipientId: params.recipientUserId,
    senderId: params.senderId,
    category: "support",
    type: "supportReply",
    title: `Pettxo Support replied to your support ticket`,
    body: truncatedPreview(params.message, 120),
    ticketId: params.ticketId,
    subject: params.subject,
    read: false,
    isRead: false,
    visibleInApp: true,
    channels: ["in_app", "push"],
    data: {
      category: "support",
      type: "supportReply",
      ticketId: params.ticketId,
      subject: params.subject,
    },
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
}

export const createSupportTicket = onCall({invoker: "public"}, async (request) => {
  const uid = request.auth?.uid ?? "";
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to continue.");
  }

  const actor = await loadSignedInActor(uid);
  const payload = (request.data ?? {}) as Record<string, unknown>;
  const category = ensureValidCategory(asTrimmedString(payload.category));
  const subject = asTrimmedString(payload.subject);
  const message = ensureValidMessage(asTrimmedString(payload.message));
  const contactNumber = ensureValidContactNumber(payload.contactNumber);

  if (!subject) {
    throw new HttpsError("invalid-argument", "Subject is required.");
  }
  if (subject.length > MAX_SUBJECT_LENGTH) {
    throw new HttpsError("invalid-argument", "Subject is too long.");
  }

  const ticketRef = db.collection("supportTickets").doc();
  const messageRef = ticketRef.collection("messages").doc();

  await db.runTransaction(async (transaction) => {
    transaction.set(ticketRef, {
      ticketId: ticketRef.id,
      userId: actor.uid,
      category,
      subject,
      initialMessage: message,
      status: "awaiting_support",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      lastMessageAt: FieldValue.serverTimestamp(),
      lastMessagePreview: truncatedPreview(message),
      lastMessageSenderType: "customer",
      customerUnreadCount: 0,
      adminUnreadCount: 1,
      userDisplayName: actor.displayName,
      username: actor.username,
      contactNumber,
      attachments: [],
    });
    transaction.set(messageRef, {
      messageId: messageRef.id,
      senderId: actor.uid,
      senderType: "customer",
      message,
      createdAt: FieldValue.serverTimestamp(),
    });
  });

  return {ok: true, ticketId: ticketRef.id};
});

export const finalizeSupportTicketAttachments = onCall(
  {invoker: "public"},
  async (request) => {
    const uid = request.auth?.uid ?? "";
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in to continue.");
    }

    await loadSignedInActor(uid);
    const payload = (request.data ?? {}) as Record<string, unknown>;
    const ticketId = asTrimmedString(payload.ticketId);
    if (!ticketId) {
      throw new HttpsError("invalid-argument", "Ticket id is required.");
    }

    const rawAttachments = Array.isArray(payload.attachments) ?
      payload.attachments :
      [];
    if (rawAttachments.length === 0) {
      return {ok: true, ticketId, attachmentsRegistered: 0};
    }
    if (rawAttachments.length > MAX_ATTACHMENT_COUNT) {
      throw new HttpsError(
        "invalid-argument",
        "Too many attachments were provided.",
      );
    }

    const {ticketRef, snapshot} = await loadOwnedTicketForCustomer(ticketId, uid);
    const ticketData = snapshot.data() ?? {};
    const existingAttachments = Array.isArray(ticketData.attachments) ?
      ticketData.attachments :
      [];
    if (existingAttachments.length > 0) {
      throw new HttpsError(
        "failed-precondition",
        "Attachments have already been registered for this ticket.",
      );
    }

    const bucket = storage.bucket();
    const normalizedAttachments = await Promise.all(rawAttachments.map(async (rawAttachment) => {
      const data = rawAttachment as Record<string, unknown>;
      const attachmentId = asTrimmedString(data.attachmentId);
      const storagePath = ensureValidAttachmentPath(
        asTrimmedString(data.storagePath),
        uid,
        ticketId,
      );
      if (!attachmentId) {
        throw new HttpsError("invalid-argument", "Attachment id is required.");
      }
      const [metadata] = await bucket.file(storagePath).getMetadata();
      const contentType = asTrimmedString(metadata.contentType).toLowerCase();
      if (!SUPPORTED_ATTACHMENT_CONTENT_TYPES.has(contentType)) {
        throw new HttpsError(
          "invalid-argument",
          "Only image attachments are supported.",
        );
      }
      const size = Number(metadata.size ?? 0);
      if (size <= 0 || size > MAX_ATTACHMENT_SIZE_BYTES) {
        throw new HttpsError(
          "invalid-argument",
          "Attachment size is invalid.",
        );
      }

      return {
        attachmentId,
        storagePath,
        fileName: sanitizeAttachmentFileName(data.fileName),
        contentType,
        createdAt: Timestamp.now(),
      };
    }));

    await ticketRef.update({
      attachments: normalizedAttachments,
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      ok: true,
      ticketId,
      attachmentsRegistered: normalizedAttachments.length,
    };
  },
);

export const replyToSupportTicket = onCall({invoker: "public"}, async (request) => {
  const uid = request.auth?.uid ?? "";
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to continue.");
  }

  await loadSignedInActor(uid);
  const payload = (request.data ?? {}) as Record<string, unknown>;
  const ticketId = asTrimmedString(payload.ticketId);
  const message = ensureValidMessage(asTrimmedString(payload.message));
  if (!ticketId) {
    throw new HttpsError("invalid-argument", "Ticket id is required.");
  }

  const {ticketRef, snapshot} = await loadOwnedTicketForCustomer(ticketId, uid);
  const ticketData = snapshot.data() ?? {};
  if (ticketData.status === "resolved") {
    throw new HttpsError(
      "failed-precondition",
      "Resolved tickets cannot receive more customer replies.",
    );
  }
  const nextStatus = "awaiting_support";
  const messageRef = ticketRef.collection("messages").doc();

  await db.runTransaction(async (transaction) => {
    transaction.set(messageRef, {
      messageId: messageRef.id,
      senderId: uid,
      senderType: "customer",
      message,
      createdAt: FieldValue.serverTimestamp(),
    });
    transaction.update(ticketRef, {
      status: nextStatus,
      updatedAt: FieldValue.serverTimestamp(),
      lastMessageAt: FieldValue.serverTimestamp(),
      lastMessagePreview: truncatedPreview(message),
      lastMessageSenderType: "customer",
      customerUnreadCount: 0,
      adminUnreadCount: (Number(ticketData.adminUnreadCount) || 0) + 1,
    });
  });

  return {ok: true, ticketId};
});

export const markSupportTicketRead = onCall({invoker: "public"}, async (request) => {
  const uid = request.auth?.uid ?? "";
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to continue.");
  }

  const payload = (request.data ?? {}) as Record<string, unknown>;
  const ticketId = asTrimmedString(payload.ticketId);
  if (!ticketId) {
    throw new HttpsError("invalid-argument", "Ticket id is required.");
  }

  const {ticketRef} = await loadOwnedTicketForCustomer(ticketId, uid);
  await ticketRef.update({
    customerUnreadCount: 0,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {ok: true, ticketId};
});

export const adminReplyToSupportTicket = onCall(
  {invoker: "public"},
  async (request) => {
    const uid = request.auth?.uid ?? "";
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in to continue.");
    }

    const actor = await requireSupportAdmin(uid);
    const payload = (request.data ?? {}) as Record<string, unknown>;
    const ticketId = asTrimmedString(payload.ticketId);
    const message = ensureValidMessage(asTrimmedString(payload.message));
    const requestedStatus = asTrimmedString(payload.status);
    const status = requestedStatus ?
      ensureValidStatus(requestedStatus) :
      "awaiting_customer";

    if (!ticketId) {
      throw new HttpsError("invalid-argument", "Ticket id is required.");
    }

    const ticketRef = db.collection("supportTickets").doc(ticketId);
    const messageRef = ticketRef.collection("messages").doc();
    const notificationContext = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ticketRef);
      if (!snapshot.exists) {
        throw new HttpsError("not-found", "Support ticket not found.");
      }
      const ticketData = snapshot.data() ?? {};
      assertSupportTicketAllowsAdminReply(ticketData.status);
      const customerId = asTrimmedString(ticketData.userId);
      const subject = asTrimmedString(ticketData.subject);

      transaction.set(messageRef, {
        messageId: messageRef.id,
        senderId: actor.uid,
        senderType: "admin",
        message,
        adminRole: actor.adminRole,
        adminDisplayName: actor.displayName,
        createdAt: FieldValue.serverTimestamp(),
      });
      transaction.update(ticketRef, {
        status,
        updatedAt: FieldValue.serverTimestamp(),
        lastMessageAt: FieldValue.serverTimestamp(),
        lastMessagePreview: truncatedPreview(message),
        lastMessageSenderType: "admin",
        customerUnreadCount: (Number(ticketData.customerUnreadCount) || 0) + 1,
        adminUnreadCount: 0,
      });

      return {customerId, subject};
    });

    await createSupportReplyNotification({
      ticketId,
      recipientUserId: notificationContext.customerId,
      senderId: actor.uid,
      senderDisplayName: actor.displayName,
      subject: notificationContext.subject,
      message,
    });

    return {ok: true, ticketId, status};
  },
);

export const adminUpdateSupportTicketStatus = onCall(
  {invoker: "public"},
  async (request) => {
    const uid = request.auth?.uid ?? "";
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in to continue.");
    }

    await requireSupportAdmin(uid);
    const payload = (request.data ?? {}) as Record<string, unknown>;
    const ticketId = asTrimmedString(payload.ticketId);
    const status = ensureValidStatus(asTrimmedString(payload.status));

    if (!ticketId) {
      throw new HttpsError("invalid-argument", "Ticket id is required.");
    }

    const ticketRef = db.collection("supportTickets").doc(ticketId);
    const snapshot = await ticketRef.get();
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Support ticket not found.");
    }

    await ticketRef.update({
      status,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {ok: true, ticketId, status};
  },
);

export const markSupportTicketReadAsAdmin = onCall(
  {invoker: "public"},
  async (request) => {
    const uid = request.auth?.uid ?? "";
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in to continue.");
    }

    await requireSupportAdmin(uid);
    const payload = (request.data ?? {}) as Record<string, unknown>;
    const ticketId = asTrimmedString(payload.ticketId);
    if (!ticketId) {
      throw new HttpsError("invalid-argument", "Ticket id is required.");
    }

    const ticketRef = db.collection("supportTickets").doc(ticketId);
    const snapshot = await ticketRef.get();
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Support ticket not found.");
    }

    await ticketRef.update({
      adminUnreadCount: 0,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {ok: true, ticketId};
  },
);
