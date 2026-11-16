import {HttpsError, onCall} from "firebase-functions/v2/https";

import {auth, db} from "../shared/firebase";
import {
  blockUserDataV1,
  getUserRelationshipStateDataV1,
  unblockUserDataV1,
} from "./userBlocking";

const callableOptions = {region: "asia-south1", invoker: "public"} as const;

function requireUid(authContext: {uid?: string} | undefined): string {
  const uid = authContext?.uid?.trim() ?? "";
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  return uid;
}

function targetUidFromInput(input: unknown): string {
  const data = typeof input === "object" && input != null ?
    input as Record<string, unknown> : {};
  const targetUid = typeof data.targetUid === "string" ? data.targetUid.trim() : "";
  if (!targetUid || targetUid.includes("/")) {
    throw new HttpsError("invalid-argument", "targetUid is required.", {
      code: "INVALID_TARGET_USER",
    });
  }
  return targetUid;
}

async function assertAuthUserExists(targetUid: string): Promise<void> {
  try {
    await auth.getUser(targetUid);
  } catch {
    throw new HttpsError("not-found", "User not found.", {
      code: "TARGET_USER_NOT_FOUND",
    });
  }
}

export const blockUserV1 = onCall(callableOptions, async (request) => {
  const actorUid = requireUid(request.auth);
  const targetUid = targetUidFromInput(request.data);
  if (actorUid === targetUid) {
    throw new HttpsError("invalid-argument", "You cannot block yourself.", {
      code: "SELF_BLOCK_NOT_ALLOWED",
    });
  }
  await assertAuthUserExists(targetUid);
  return blockUserDataV1({firestore: db, actorUid, targetUid});
});

export const unblockUserV1 = onCall(callableOptions, async (request) => {
  const actorUid = requireUid(request.auth);
  const targetUid = targetUidFromInput(request.data);
  if (actorUid === targetUid) {
    throw new HttpsError("invalid-argument", "You cannot unblock yourself.", {
      code: "SELF_BLOCK_NOT_ALLOWED",
    });
  }
  await assertAuthUserExists(targetUid);
  return unblockUserDataV1({firestore: db, actorUid, targetUid});
});

export const getUserRelationshipStateV1 = onCall(callableOptions, async (request) => {
  const actorUid = requireUid(request.auth);
  const targetUid = targetUidFromInput(request.data);
  if (actorUid === targetUid) {
    throw new HttpsError("invalid-argument", "A relationship requires two users.", {
      code: "SELF_BLOCK_NOT_ALLOWED",
    });
  }
  await assertAuthUserExists(targetUid);
  return getUserRelationshipStateDataV1({firestore: db, actorUid, targetUid});
});
