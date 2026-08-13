import {FieldPath, FieldValue, QueryDocumentSnapshot} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {db} from "../shared/firebase";
import {buildStoredPromotionalNotificationDocument} from "./notificationChannels";

const promotionalAudienceValues = [
  "all",
  "serviceProvider",
  "petParent",
  "petLover",
] as const;

const allowedPromotionalAdminRoles = new Set([
  "superAdmin",
  "financeAdmin",
]);

const maxPromotionalTitleLength = 120;
const maxPromotionalBodyLength = 240;
const maxPromotionalRequestIdLength = 120;
const promotionalRequestIdPattern = /^[A-Za-z0-9_-]{1,120}$/;
const promotionalBroadcastPageSize = 200;

type PromotionalAudience = typeof promotionalAudienceValues[number];
type PromotionalBroadcastStatus =
  | "processing"
  | "completed"
  | "partially_completed"
  | "failed";

type PromotionalBroadcastRequest = {
  title: string;
  body: string;
  audience: PromotionalAudience;
  requestId: string;
};

type PromotionalBroadcastResult = {
  success: boolean;
  broadcastId: string;
  status: PromotionalBroadcastStatus;
  audience: PromotionalAudience;
  targetedUsers: number;
  notificationsCreated: number;
  skipped: number;
  failed: number;
};

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function isPromotionalAudience(value: string): value is PromotionalAudience {
  return promotionalAudienceValues.includes(value as PromotionalAudience);
}

export function assertPromotionalBroadcastPermission(role: string): void {
  if (allowedPromotionalAdminRoles.has(role)) return;
  throw new HttpsError(
    "permission-denied",
    "You are not allowed to send promotional notifications.",
  );
}

export function assertAuthenticatedUid(uid: string): void {
  if (uid) return;
  throw new HttpsError("unauthenticated", "Sign in to continue.");
}

async function requirePromotionalBroadcastAdmin(uid: string): Promise<{
  uid: string;
  role: string;
}> {
  const snapshot = await db.collection("users").doc(uid).get();
  if (!snapshot.exists) {
    throw new HttpsError("permission-denied", "Admin profile not found.");
  }

  const role = asTrimmedString(snapshot.data()?.adminRole);
  assertPromotionalBroadcastPermission(role);
  return {uid, role};
}

export function validatePromotionalBroadcastRequest(
  payload: unknown,
): PromotionalBroadcastRequest {
  const data =
    payload && typeof payload === "object" && !Array.isArray(payload) ?
      payload as Record<string, unknown> :
      {};

  const title = asTrimmedString(data.title);
  const body = asTrimmedString(data.body);
  const audience = asTrimmedString(data.audience);
  const requestId = asTrimmedString(data.requestId);

  if (!title) {
    throw new HttpsError("invalid-argument", "title is required.");
  }
  if (title.length > maxPromotionalTitleLength) {
    throw new HttpsError("invalid-argument", "title is too long.");
  }
  if (!body) {
    throw new HttpsError("invalid-argument", "body is required.");
  }
  if (body.length > maxPromotionalBodyLength) {
    throw new HttpsError("invalid-argument", "body is too long.");
  }
  if (!isPromotionalAudience(audience)) {
    throw new HttpsError("invalid-argument", "audience is invalid.");
  }
  if (!requestId) {
    throw new HttpsError("invalid-argument", "requestId is required.");
  }
  if (requestId.length > maxPromotionalRequestIdLength) {
    throw new HttpsError("invalid-argument", "requestId is too long.");
  }
  if (!promotionalRequestIdPattern.test(requestId)) {
    throw new HttpsError("invalid-argument", "requestId format is invalid.");
  }

  return {
    title,
    body,
    audience,
    requestId,
  };
}

export function promotionalBroadcastDocIdFromRequestId(requestId: string): string {
  return `promo_broadcast_${requestId}`;
}

export function promotionalNotificationDocId(
  broadcastId: string,
  uid: string,
): string {
  return `promo_${broadcastId}_${uid}`;
}

export function matchesPromotionalAudience(
  audience: PromotionalAudience,
  user: Record<string, unknown>,
): boolean {
  if (audience === "all") return true;
  return asTrimmedString(user.role) === audience;
}

function accountStatusFromUser(user: Record<string, unknown>): string {
  const status = asTrimmedString(user.accountStatus);
  return status || "active";
}

function isAccountUnavailableForPromotionalNotifications(
  user: Record<string, unknown>,
): boolean {
  const status = accountStatusFromUser(user);
  return status === "pendingDeletion" || status === "deletionInProgress";
}

type ResolvedRecipientPage = {
  matchingUserIds: string[];
  skippedUserCount: number;
  nextCursor: QueryDocumentSnapshot | null;
};

async function resolvePromotionalRecipientPage(params: {
  audience: PromotionalAudience;
  startAfter: QueryDocumentSnapshot | null;
}): Promise<ResolvedRecipientPage> {
  let query = db
    .collection("users")
    .orderBy(FieldPath.documentId())
    .limit(promotionalBroadcastPageSize);

  if (params.audience !== "all") {
    query = query.where("role", "==", params.audience);
  }
  if (params.startAfter) {
    query = query.startAfter(params.startAfter);
  }

  const snapshot = await query.get();
  const matchingUserIds: string[] = [];
  let skippedUserCount = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data() ?? {};
    if (!matchesPromotionalAudience(params.audience, data)) {
      continue;
    }
    if (isAccountUnavailableForPromotionalNotifications(data)) {
      skippedUserCount += 1;
      continue;
    }
    matchingUserIds.push(doc.id);
  }

  return {
    matchingUserIds,
    skippedUserCount,
    nextCursor: snapshot.docs.length > 0 ? snapshot.docs[snapshot.docs.length - 1] : null,
  };
}

function resultFromBroadcastSnapshot(
  data: Record<string, unknown>,
): PromotionalBroadcastResult {
  return {
    success:
      asTrimmedString(data.status) === "completed" ||
      asTrimmedString(data.status) === "partially_completed",
    broadcastId: asTrimmedString(data.broadcastId),
    status: (asTrimmedString(data.status) || "failed") as PromotionalBroadcastStatus,
    audience: (asTrimmedString(data.audience) || "all") as PromotionalAudience,
    targetedUsers: Number(data.targetedUserCount) || 0,
    notificationsCreated: Number(data.notificationCreatedCount) || 0,
    skipped: Number(data.skippedUserCount) || 0,
    failed: Number(data.failureCount) || 0,
  };
}

export const sendAdminPromotionalNotification = onCall(
  {invoker: "public"},
  async (request): Promise<PromotionalBroadcastResult> => {
    const callerUid = request.auth?.uid ?? "";
    assertAuthenticatedUid(callerUid);

    const admin = await requirePromotionalBroadcastAdmin(callerUid);
    const payload = validatePromotionalBroadcastRequest(request.data);
    const broadcastId = promotionalBroadcastDocIdFromRequestId(payload.requestId);
    const broadcastRef = db.collection("notificationBroadcasts").doc(broadcastId);

    const existingResult = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(broadcastRef);
      if (snapshot.exists) {
        return resultFromBroadcastSnapshot(snapshot.data() ?? {});
      }

      transaction.create(broadcastRef, {
        broadcastId,
        requestId: payload.requestId,
        title: payload.title,
        body: payload.body,
        audience: payload.audience,
        createdBy: admin.uid,
        createdByAdminRole: admin.role,
        status: "processing",
        targetedUserCount: 0,
        notificationCreatedCount: 0,
        skippedUserCount: 0,
        failureCount: 0,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return null;
    });

    if (existingResult) {
      console.info("Promotional broadcast idempotent replay", {
        broadcastId,
        audience: existingResult.audience,
        adminUid: admin.uid,
        adminRole: admin.role,
        status: existingResult.status,
        targetedUsers: existingResult.targetedUsers,
        notificationsCreated: existingResult.notificationsCreated,
        skipped: existingResult.skipped,
        failed: existingResult.failed,
      });
      return existingResult;
    }

    console.info("Promotional broadcast processing started", {
      broadcastId,
      audience: payload.audience,
      adminUid: admin.uid,
      adminRole: admin.role,
    });

    let cursor: QueryDocumentSnapshot | null = null;
    let targetedUserCount = 0;
    let notificationCreatedCount = 0;
    let skippedUserCount = 0;
    let failureCount = 0;

    try {
      while (true) {
        const page = await resolvePromotionalRecipientPage({
          audience: payload.audience,
          startAfter: cursor,
        });
        cursor = page.nextCursor;
        skippedUserCount += page.skippedUserCount;
        targetedUserCount += page.matchingUserIds.length;

        if (page.matchingUserIds.length > 0) {
          const batch = db.batch();
          for (const userId of page.matchingUserIds) {
            const notificationRef = db
              .collection("notifications")
              .doc(promotionalNotificationDocId(broadcastId, userId));
            batch.set(notificationRef, buildStoredPromotionalNotificationDocument({
              recipientUserId: userId,
              broadcastId,
              title: payload.title,
              body: payload.body,
              createdAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
              source: "admin_promotional_broadcast",
            }));
          }
          await batch.commit();
          notificationCreatedCount += page.matchingUserIds.length;
        }

        if (!cursor) break;
      }

      const status: PromotionalBroadcastStatus =
        failureCount > 0 ? "partially_completed" : "completed";
      await broadcastRef.set({
        status,
        targetedUserCount,
        notificationCreatedCount,
        skippedUserCount,
        failureCount,
        completedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});

      console.info("Promotional broadcast processing completed", {
        broadcastId,
        audience: payload.audience,
        adminUid: admin.uid,
        adminRole: admin.role,
        status,
        targetedUsers: targetedUserCount,
        notificationsCreated: notificationCreatedCount,
        skipped: skippedUserCount,
        failed: failureCount,
      });

      return {
        success: status === "completed" || status === "partially_completed",
        broadcastId,
        status,
        audience: payload.audience,
        targetedUsers: targetedUserCount,
        notificationsCreated: notificationCreatedCount,
        skipped: skippedUserCount,
        failed: failureCount,
      };
    } catch (error) {
      failureCount += 1;
      await broadcastRef.set({
        status: "failed",
        targetedUserCount,
        notificationCreatedCount,
        skippedUserCount,
        failureCount,
        errorCode: error instanceof HttpsError ? error.code : "internal",
        errorMessage: error instanceof Error ? error.message : "Unknown error",
        completedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});

      console.error("Promotional broadcast processing failed", {
        broadcastId,
        audience: payload.audience,
        adminUid: admin.uid,
        adminRole: admin.role,
        targetedUsers: targetedUserCount,
        notificationsCreated: notificationCreatedCount,
        skipped: skippedUserCount,
        failed: failureCount,
        error: error instanceof Error ? error.message : String(error),
      });

      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError(
        "internal",
        "Promotional notification delivery failed.",
      );
    }
  },
);
