import {FieldValue, type DocumentData, type DocumentSnapshot} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {defineBoolean, defineSecret} from "firebase-functions/params";

import {auth, db, storage} from "../shared/firebase";
import {
  canonicalDirectChatDocumentIdentity,
  canonicalUserDocumentMatches,
  chatStatusAllowsMessages,
  otherDirectParticipantUid,
  type CanonicalDirectChatIdentity,
} from "./chatIdentity";
import {
  anyActiveDeviceSupportsChatImages,
  buildChatImageMessageData,
  canAccountUseChatImageMessaging,
  chatImageUnreadField,
  chatImageStoragePath,
  inspectJpegDimensions,
  isIdenticalCommittedImageMessage,
  isValidChatImageMessageId,
  parseChatImageTesterUids,
  validateChatImageObjectMetadata,
} from "./chatImagePolicy";

const CHAT_IMAGE_MESSAGING_ENABLED = defineBoolean(
  "CHAT_IMAGE_MESSAGING_ENABLED",
  {default: false, description: "Enables canonical direct-chat image messages."},
);

// Server-owned Secret Manager configuration. Never accept tester eligibility
// from callable data or a user-writable Firestore document.
const CHAT_IMAGE_TESTER_UIDS = defineSecret("CHAT_IMAGE_TESTER_UIDS");

function trimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function requireUid(authContext: {uid?: string} | undefined): string {
  const uid = trimmedString(authContext?.uid);
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to continue.");
  return uid;
}

function assertCanonicalUser(
  uid: string,
  snapshot: DocumentSnapshot<DocumentData>,
): Record<string, unknown> {
  const data = snapshot.data() ?? {};
  if (!snapshot.exists || !canonicalUserDocumentMatches(uid, data)) {
    throw new HttpsError(
      "failed-precondition",
      "A direct chat participant is not a canonical Pettxo user.",
    );
  }
  return data;
}

function assertAccountCanSendImages(user: Record<string, unknown>): void {
  const status = trimmedString(user.accountStatus);
  if (status === "pendingDeletion" || status === "deletionInProgress") {
    throw new HttpsError(
      "failed-precondition",
      "This account cannot send chat images right now.",
    );
  }
  const restrictions = user.restrictions as Record<string, unknown> | undefined;
  const hard = restrictions?.hard as Record<string, unknown> | undefined;
  const social = restrictions?.social as Record<string, unknown> | undefined;
  if (hard?.isBanned === true || social?.isBanned === true) {
    throw new HttpsError(
      "failed-precondition",
      "This account cannot send chat images right now.",
    );
  }
}

function requireCanonicalIdentity(
  chatId: string,
  chat: Record<string, unknown>,
): CanonicalDirectChatIdentity {
  const identity = canonicalDirectChatDocumentIdentity(chatId, chat);
  if (!identity) {
    throw new HttpsError(
      "failed-precondition",
      "This direct chat has invalid participant identity.",
    );
  }
  return identity;
}

async function userSupportsChatImages(uid: string): Promise<boolean> {
  const snapshot = await db.collection("users").doc(uid).collection("notificationTokens").get();
  return anyActiveDeviceSupportsChatImages(snapshot.docs.map((doc) => doc.data()));
}

function publicFeatureEnabled(): boolean {
  return CHAT_IMAGE_MESSAGING_ENABLED.value() === true;
}

function accountFeatureEnabled(uid: string): boolean {
  return canAccountUseChatImageMessaging({
    publicEnabled: publicFeatureEnabled(),
    testerUids: parseChatImageTesterUids(CHAT_IMAGE_TESTER_UIDS.value()),
    uid,
  });
}

function mapObjectValidationError(error: unknown): HttpsError {
  const code = error instanceof Error ? error.message : "invalid-image";
  switch (code) {
    case "empty-image":
      return new HttpsError("invalid-argument", "The uploaded image is empty.");
    case "image-too-large":
      return new HttpsError("invalid-argument", "The processed image exceeds 3 MB.");
    case "image-dimensions-too-large":
      return new HttpsError("invalid-argument", "The processed image dimensions are too large.");
    case "invalid-content-type":
    case "invalid-jpeg":
    case "invalid-dimensions":
    case "jpeg-dimensions-missing":
      return new HttpsError("invalid-argument", "The uploaded object is not a valid JPEG image.");
    case "sender-metadata-mismatch":
    case "chat-metadata-mismatch":
    case "message-metadata-mismatch":
    case "storage-path-mismatch":
      return new HttpsError("permission-denied", "The uploaded image does not belong to this send request.");
    default:
      return new HttpsError("invalid-argument", "The uploaded image is invalid.");
  }
}

export const getChatImageMessagingCapability = onCall(
  {invoker: "public", secrets: [CHAT_IMAGE_TESTER_UIDS]},
  async (request) => {
    const uid = requireUid(request.auth);
    const chatId = trimmedString(request.data?.chatId);
    if (!chatId) throw new HttpsError("invalid-argument", "chatId is required.");

    const chatSnapshot = await db.collection("chats").doc(chatId).get();
    if (!chatSnapshot.exists) throw new HttpsError("not-found", "Chat not found.");
    const identity = requireCanonicalIdentity(chatId, chatSnapshot.data() ?? {});
    if (!identity.participantIds.includes(uid)) {
      throw new HttpsError("permission-denied", "You are not a participant in this chat.");
    }
    if (!accountFeatureEnabled(uid)) {
      return {enabled: false, reason: "sender-not-allowed"};
    }
    const compatible = await userSupportsChatImages(uid);
    return {
      enabled: compatible,
      reason: compatible ? "enabled" : "sender-incompatible",
    };
  },
);

export const sendChatImageMessage = onCall(
  {
    invoker: "public",
    timeoutSeconds: 60,
    memory: "256MiB",
    secrets: [CHAT_IMAGE_TESTER_UIDS],
  },
  async (request) => {
    const senderId = requireUid(request.auth);
    const chatId = trimmedString(request.data?.chatId);
    const messageId = trimmedString(request.data?.messageId);
    if (!chatId) throw new HttpsError("invalid-argument", "chatId is required.");
    if (!isValidChatImageMessageId(messageId)) {
      throw new HttpsError("invalid-argument", "messageId is invalid.");
    }

    const expectedStoragePath = chatImageStoragePath(chatId, messageId);
    const requestedStoragePath = trimmedString(request.data?.storagePath);
    if (requestedStoragePath !== expectedStoragePath) {
      throw new HttpsError("invalid-argument", "storagePath is invalid.");
    }

    const chatRef = db.collection("chats").doc(chatId);
    const messageRef = chatRef.collection("messages").doc(messageId);
    const [chatSnapshot, existingMessageSnapshot] = await Promise.all([
      chatRef.get(),
      messageRef.get(),
    ]);
    if (!chatSnapshot.exists) throw new HttpsError("not-found", "Chat not found.");
    const chat = chatSnapshot.data() ?? {};
    const identity = requireCanonicalIdentity(chatId, chat);
    if (!identity.participantIds.includes(senderId)) {
      throw new HttpsError("permission-denied", "You are not a participant in this chat.");
    }
    const receiverId = otherDirectParticipantUid(identity, senderId) ?? "";
    if (!receiverId) throw new HttpsError("failed-precondition", "Chat receiver is missing.");

    if (!accountFeatureEnabled(senderId)) {
      throw new HttpsError("failed-precondition", "Image messaging is not enabled yet.");
    }
    if (!await userSupportsChatImages(senderId)) {
      throw new HttpsError(
        "failed-precondition",
        "Update Pettxo on this device before sending chat images.",
      );
    }

    if (existingMessageSnapshot.exists) {
      if (isIdenticalCommittedImageMessage({
        message: existingMessageSnapshot.data() ?? {},
        senderId,
        receiverId,
        storagePath: expectedStoragePath,
      })) {
        return {chatId, messageId, idempotent: true};
      }
      throw new HttpsError("already-exists", "messageId is already used by different content.");
    }

    if (!chatStatusAllowsMessages(trimmedString(chat.chatType), trimmedString(chat.status))) {
      throw new HttpsError("failed-precondition", "This chat is closed.");
    }

    const [senderSnapshot, receiverSnapshot, senderAuthUser] = await Promise.all([
      db.collection("users").doc(senderId).get(),
      db.collection("users").doc(receiverId).get(),
      auth.getUser(senderId),
    ]);
    const sender = assertCanonicalUser(senderId, senderSnapshot);
    assertCanonicalUser(receiverId, receiverSnapshot);
    assertAccountCanSendImages(sender);
    if (senderAuthUser.disabled) {
      throw new HttpsError("failed-precondition", "This account cannot send chat images right now.");
    }
    const file = storage.bucket().file(expectedStoragePath);
    let metadata;
    try {
      [metadata] = await file.getMetadata();
    } catch (error) {
      const statusCode = Number((error as {code?: unknown})?.code ?? 0);
      if (statusCode === 404) {
        throw new HttpsError("not-found", "Uploaded image not found.");
      }
      throw new HttpsError("unavailable", "Unable to validate the uploaded image.");
    }

    let size: number;
    try {
      ({size} = validateChatImageObjectMetadata({
        metadata,
        expectedPath: expectedStoragePath,
        actualPath: file.name,
        chatId,
        messageId,
        senderId,
      }));
    } catch (error) {
      throw mapObjectValidationError(error);
    }

    let imageBytes: Buffer;
    try {
      [imageBytes] = await file.download();
    } catch (_) {
      throw new HttpsError("unavailable", "Unable to inspect the uploaded image.");
    }
    let dimensions;
    try {
      dimensions = inspectJpegDimensions(imageBytes);
    } catch (error) {
      throw mapObjectValidationError(error);
    }

    const notificationRef = db.collection("notifications").doc(`chat_${receiverId}_${chatId}`);
    const transactionResult = await db.runTransaction(async (transaction) => {
      const [latestChatSnapshot, latestMessageSnapshot, latestSenderSnapshot, latestReceiverSnapshot] =
        await Promise.all([
          transaction.get(chatRef),
          transaction.get(messageRef),
          transaction.get(db.collection("users").doc(senderId)),
          transaction.get(db.collection("users").doc(receiverId)),
        ]);
      if (!latestChatSnapshot.exists) throw new HttpsError("not-found", "Chat not found.");
      const latestChat = latestChatSnapshot.data() ?? {};
      const latestIdentity = requireCanonicalIdentity(chatId, latestChat);
      const latestReceiverId = otherDirectParticipantUid(latestIdentity, senderId);
      if (latestReceiverId !== receiverId) {
        throw new HttpsError("failed-precondition", "Direct chat participant identity changed unexpectedly.");
      }

      if (latestMessageSnapshot.exists) {
        if (isIdenticalCommittedImageMessage({
          message: latestMessageSnapshot.data() ?? {},
          senderId,
          receiverId,
          storagePath: expectedStoragePath,
        })) {
          return {idempotent: true};
        }
        throw new HttpsError("already-exists", "messageId is already used by different content.");
      }

      if (!chatStatusAllowsMessages(trimmedString(latestChat.chatType), trimmedString(latestChat.status))) {
        throw new HttpsError("failed-precondition", "This chat is closed.");
      }
      const latestSender = assertCanonicalUser(senderId, latestSenderSnapshot);
      assertCanonicalUser(receiverId, latestReceiverSnapshot);
      assertAccountCanSendImages(latestSender);

      const existingNotification = await transaction.get(notificationRef);
      const now = FieldValue.serverTimestamp();
      const senderName = trimmedString(latestSender.displayName) ||
        trimmedString(latestSender.name) ||
        trimmedString(latestSender.username) ||
        "Pettxo user";

      transaction.create(messageRef, {
        ...buildChatImageMessageData({
          senderId,
          receiverId,
          storagePath: expectedStoragePath,
          width: dimensions.width,
          height: dimensions.height,
          size,
        }),
        createdAt: now,
      });

      const chatUpdate: Record<string, unknown> = {
        lastMessage: "📷 Photo",
        lastMessageAt: now,
        lastSenderId: senderId,
        updatedAt: now,
      };
      chatUpdate[chatImageUnreadField(latestIdentity.participantIds, receiverId)] =
        FieldValue.increment(1);
      transaction.set(chatRef, chatUpdate, {merge: true});

      const notificationPayload: Record<string, unknown> = {
        userId: receiverId,
        recipientId: receiverId,
        senderId,
        senderName,
        category: "chat",
        type: "chat",
        title: senderName,
        body: "Sent you a photo",
        read: false,
        isRead: false,
        unreadCount: existingNotification.exists ? FieldValue.increment(1) : 1,
        serviceId: "",
        chatId,
        lastMessageId: messageId,
        data: {
          chatId,
          senderId,
          senderName,
          recipientId: receiverId,
          receiverId,
          serviceId: "",
          type: "chat",
          category: "chat",
        },
        updatedAt: now,
      };
      if (!existingNotification.exists) notificationPayload.createdAt = now;
      transaction.set(notificationRef, notificationPayload, {merge: true});
      return {idempotent: false};
    });

    return {chatId, messageId, idempotent: transactionResult.idempotent};
  },
);
