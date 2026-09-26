import {FieldValue} from "firebase-admin/firestore";
import type {DocumentData} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {db} from "../shared/firebase";

type FollowTransitionInput = {
  relationshipExists: boolean;
  desiredFollowing: boolean;
  followerFollowingCount: number;
  followeeFollowerCount: number;
};

export type FollowTransition = {
  changed: boolean;
  following: boolean;
  delta: -1 | 0 | 1;
  followerFollowingCount: number;
  followeeFollowerCount: number;
};

function storedCount(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? Math.max(0, value) : 0;
}

export function deriveFollowTransition(input: FollowTransitionInput): FollowTransition {
  if (input.relationshipExists === input.desiredFollowing) {
    return {
      changed: false,
      following: input.relationshipExists,
      delta: 0,
      followerFollowingCount: storedCount(input.followerFollowingCount),
      followeeFollowerCount: storedCount(input.followeeFollowerCount),
    };
  }

  const delta = input.desiredFollowing ? 1 : -1;
  return {
    changed: true,
    following: input.desiredFollowing,
    delta,
    followerFollowingCount: Math.max(0, storedCount(input.followerFollowingCount) + delta),
    followeeFollowerCount: Math.max(0, storedCount(input.followeeFollowerCount) + delta),
  };
}

function trimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function restrictionIsBanned(value: unknown): boolean {
  return typeof value === "object" && value !== null &&
    (value as Record<string, unknown>).isBanned === true;
}

export function accountCanUseFollow(data: DocumentData): boolean {
  const status = trimmedString(data.accountStatus) || "active";
  const restrictions = typeof data.restrictions === "object" && data.restrictions !== null ?
    data.restrictions as Record<string, unknown> : {};
  return status === "active" &&
    data.isDeleted !== true &&
    data.deletionRequested !== true &&
    restrictionIsBanned(restrictions.social) !== true &&
    restrictionIsBanned(restrictions.hard) !== true;
}

function profileIsPubliclyVisible(data: DocumentData): boolean {
  const visibility = trimmedString(data.profileVisibility).toLowerCase() || "public";
  return accountCanUseFollow(data) && data.isActive !== false && visibility !== "hidden";
}

function validatePayload(data: unknown): {followeeId: string; desiredFollowing: boolean} {
  if (typeof data !== "object" || data === null || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "Follow request is invalid.");
  }
  const payload = data as Record<string, unknown>;
  const allowedKeys = new Set(["followeeId", "desiredFollowing"]);
  if (Object.keys(payload).some((key) => !allowedKeys.has(key))) {
    throw new HttpsError("invalid-argument", "Follow request contains unsupported fields.");
  }
  const followeeId = trimmedString(payload.followeeId);
  if (!followeeId || typeof payload.desiredFollowing !== "boolean") {
    throw new HttpsError("invalid-argument", "Followee and desired state are required.");
  }
  return {followeeId, desiredFollowing: payload.desiredFollowing};
}

export const getFollowState = onCall({invoker: "public"}, async (request) => {
  const followerId = trimmedString(request.auth?.uid);
  if (!followerId) {
    throw new HttpsError("unauthenticated", "Sign in to continue.");
  }
  const {followeeId} = validatePayload({
    followeeId: (request.data as Record<string, unknown> | null)?.followeeId,
    desiredFollowing: false,
  });
  if (followerId === followeeId) return {isFollowing: false};

  const followId = `${followerId}_${followeeId}`;
  const snapshot = await db.collection("follows").doc(followId).get();
  return {isFollowing: snapshot.exists};
});

export const setFollowState = onCall({invoker: "public"}, async (request) => {
  const followerId = trimmedString(request.auth?.uid);
  if (!followerId) {
    throw new HttpsError("unauthenticated", "Sign in to continue.");
  }
  const {followeeId, desiredFollowing} = validatePayload(request.data);
  if (followerId === followeeId) {
    throw new HttpsError("invalid-argument", "You cannot follow yourself.");
  }

  return applyFollowState({followerId, followeeId, desiredFollowing});
});

export async function applyFollowState({
  followerId,
  followeeId,
  desiredFollowing,
}: {
  followerId: string;
  followeeId: string;
  desiredFollowing: boolean;
}) {

  const followerRef = db.collection("users").doc(followerId);
  const followeeRef = db.collection("users").doc(followeeId);
  const followRef = db.collection("follows").doc(`${followerId}_${followeeId}`);

  return db.runTransaction(async (transaction) => {
    const [followerSnapshot, followeeSnapshot, followSnapshot] = await Promise.all([
      transaction.get(followerRef),
      transaction.get(followeeRef),
      transaction.get(followRef),
    ]);
    if (!followerSnapshot.exists) {
      throw new HttpsError("failed-precondition", "Your profile is unavailable.");
    }
    if (desiredFollowing && !followeeSnapshot.exists) {
      throw new HttpsError("not-found", "This account is no longer available.");
    }

    const follower = followerSnapshot.data() ?? {};
    const followee = followeeSnapshot.data() ?? {};
    if (!accountCanUseFollow(follower)) {
      throw new HttpsError("permission-denied", "Your account cannot update follows right now.");
    }
    if (desiredFollowing && !profileIsPubliclyVisible(followee)) {
      throw new HttpsError("failed-precondition", "This account is no longer available.");
    }

    const transition = deriveFollowTransition({
      relationshipExists: followSnapshot.exists,
      desiredFollowing,
      followerFollowingCount: storedCount(follower.followingCount),
      followeeFollowerCount: storedCount(followee.followerCount),
    });
    if (!transition.changed) {
      return {
        changed: false,
        isFollowing: transition.following,
        followerFollowingCount: transition.followerFollowingCount,
        followeeFollowerCount: transition.followeeFollowerCount,
      };
    }

    if (transition.following) {
      transaction.create(followRef, {
        followerId,
        followeeId,
        createdAt: FieldValue.serverTimestamp(),
      });
    } else {
      transaction.delete(followRef);
    }
    transaction.set(followerRef, {
      followingCount: transition.followerFollowingCount,
    }, {merge: true});
    if (followeeSnapshot.exists) {
      transaction.set(followeeRef, {
        followerCount: transition.followeeFollowerCount,
      }, {merge: true});
    }

    return {
      changed: true,
      isFollowing: transition.following,
      followerFollowingCount: transition.followerFollowingCount,
      followeeFollowerCount: transition.followeeFollowerCount,
    };
  });
}

/**
 * Compatibility path for relationships written by older clients. Recounting
 * from canonical relationship documents makes retries idempotent and also
 * converges counters after any successful callable mutation.
 */
export const syncProfileFollowCounts = onDocumentWritten(
  "follows/{followId}",
  async (event) => {
    const source = event.data?.after.data() ?? event.data?.before.data();
    const followerId = trimmedString(source?.followerId);
    const followeeId = trimmedString(source?.followeeId);
    if (!followerId || !followeeId || followerId === followeeId) return;

    const followerRef = db.collection("users").doc(followerId);
    const followeeRef = db.collection("users").doc(followeeId);
    const followingQuery = db.collection("follows").where("followerId", "==", followerId);
    const followerQuery = db.collection("follows").where("followeeId", "==", followeeId);

    await db.runTransaction(async (transaction) => {
      const [followerSnapshot, followeeSnapshot] = await Promise.all([
        transaction.get(followerRef),
        transaction.get(followeeRef),
      ]);
      const followingSnapshot = await transaction.get(followingQuery);
      const followersSnapshot = await transaction.get(followerQuery);
      if (followerSnapshot.exists) {
        transaction.set(followerRef, {followingCount: followingSnapshot.size}, {merge: true});
      }
      if (followeeSnapshot.exists) {
        transaction.set(followeeRef, {followerCount: followersSnapshot.size}, {merge: true});
      }
    });
  },
);
