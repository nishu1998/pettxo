import {createHash} from "node:crypto";

import {
  FieldValue,
  type DocumentData,
  type DocumentReference,
  type DocumentSnapshot,
  type Firestore,
  type Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

export const USER_BLOCKS_COLLECTION = "userBlocks";
export const USER_RELATIONSHIP_GUARDS_COLLECTION = "userRelationshipGuards";
export const USER_RELATIONSHIP_GUARD_SCHEMA_VERSION = 1;

export type CanonicalUserPair = {
  uidA: string;
  uidB: string;
  pairKey: string;
};

export type EffectiveRelationshipState = {
  pair: CanonicalUserPair;
  blocked: boolean;
  blockedByGuard: boolean;
  blockedByUidA: boolean;
  blockedByUidB: boolean;
};

function normalizedUid(value: string): string {
  const uid = value.trim();
  if (!uid || uid.includes("/")) {
    throw new HttpsError("failed-precondition", "Booking participants are invalid.", {
      code: "INVALID_RELATIONSHIP_PARTICIPANTS",
    });
  }
  return uid;
}

export function canonicalUserPair(firstUid: string, secondUid: string): CanonicalUserPair {
  const sorted = [normalizedUid(firstUid), normalizedUid(secondUid)].sort();
  if (sorted[0] === sorted[1]) {
    throw new HttpsError("invalid-argument", "You cannot block yourself.", {
      code: "SELF_BLOCK_NOT_ALLOWED",
    });
  }
  const pairKey = `pair_${createHash("sha256")
    .update(JSON.stringify(sorted))
    .digest("hex")}`;
  return {uidA: sorted[0], uidB: sorted[1], pairKey};
}

export function directedBlockId(ownerUserId: string, blockedUserId: string): string {
  return `${normalizedUid(ownerUserId)}_${normalizedUid(blockedUserId)}`;
}

export function relationshipGuardRef(
  firestore: Firestore,
  firstUid: string,
  secondUid: string,
): DocumentReference<DocumentData> {
  return firestore
    .collection(USER_RELATIONSHIP_GUARDS_COLLECTION)
    .doc(canonicalUserPair(firstUid, secondUid).pairKey);
}

export function relationshipIsBlocked(
  snapshot: DocumentSnapshot<DocumentData> | null | undefined,
): boolean {
  return snapshot?.exists === true && snapshot.data()?.blocked === true;
}

export function assertRelationshipAllowsProtectedMutation(
  snapshot: DocumentSnapshot<DocumentData> | null | undefined,
  directedBlockSnapshots: Array<DocumentSnapshot<DocumentData>> = [],
): void {
  if (relationshipIsBlocked(snapshot) || directedBlockSnapshots.some((entry) => entry.exists)) {
    throw new HttpsError(
      "failed-precondition",
      "This action is unavailable because the users have blocked each other.",
      {code: "USER_RELATIONSHIP_BLOCKED"},
    );
  }
}

function effectiveRelationshipState(params: {
  pair: CanonicalUserPair;
  guardSnapshot: DocumentSnapshot<DocumentData>;
  firstBlockSnapshot: DocumentSnapshot<DocumentData>;
  secondBlockSnapshot: DocumentSnapshot<DocumentData>;
}): EffectiveRelationshipState {
  const blockedByGuard = relationshipIsBlocked(params.guardSnapshot);
  const blockedByUidA = params.firstBlockSnapshot.exists;
  const blockedByUidB = params.secondBlockSnapshot.exists;
  return {
    pair: params.pair,
    blocked: blockedByGuard || blockedByUidA || blockedByUidB,
    blockedByGuard,
    blockedByUidA,
    blockedByUidB,
  };
}

export async function getEffectiveRelationshipState(params: {
  firestore: Firestore;
  firstUid: string;
  secondUid: string;
}): Promise<EffectiveRelationshipState> {
  const pair = canonicalUserPair(params.firstUid, params.secondUid);
  const [guardSnapshot, firstBlockSnapshot, secondBlockSnapshot] = await Promise.all([
    params.firestore.collection(USER_RELATIONSHIP_GUARDS_COLLECTION).doc(pair.pairKey).get(),
    params.firestore.collection(USER_BLOCKS_COLLECTION)
      .doc(directedBlockId(pair.uidA, pair.uidB)).get(),
    params.firestore.collection(USER_BLOCKS_COLLECTION)
      .doc(directedBlockId(pair.uidB, pair.uidA)).get(),
  ]);
  return effectiveRelationshipState({
    pair,
    guardSnapshot,
    firstBlockSnapshot,
    secondBlockSnapshot,
  });
}

export async function getEffectiveRelationshipStateInTransaction(params: {
  firestore: Firestore;
  transaction: Transaction;
  firstUid: string;
  secondUid: string;
}): Promise<EffectiveRelationshipState & {
  ref: DocumentReference<DocumentData>;
  snapshot: DocumentSnapshot<DocumentData>;
}> {
  const pair = canonicalUserPair(params.firstUid, params.secondUid);
  const ref = params.firestore.collection(USER_RELATIONSHIP_GUARDS_COLLECTION).doc(pair.pairKey);
  const [snapshot, firstBlockSnapshot, secondBlockSnapshot] = await Promise.all([
    params.transaction.get(ref),
    params.transaction.get(params.firestore.collection(USER_BLOCKS_COLLECTION)
      .doc(directedBlockId(pair.uidA, pair.uidB))),
    params.transaction.get(params.firestore.collection(USER_BLOCKS_COLLECTION)
      .doc(directedBlockId(pair.uidB, pair.uidA))),
  ]);
  return {
    ...effectiveRelationshipState({
      pair,
      guardSnapshot: snapshot,
      firstBlockSnapshot,
      secondBlockSnapshot,
    }),
    ref,
    snapshot,
  };
}

export function assertEffectiveRelationshipOpen(state: EffectiveRelationshipState): void {
  if (state.blocked) {
    throw new HttpsError(
      "failed-precondition",
      "This action is unavailable because the users have blocked each other.",
      {code: "USER_RELATIONSHIP_BLOCKED"},
    );
  }
}

export function openRelationshipGuardMutation(params: {
  pair: CanonicalUserPair;
  bookingId: string;
  operation: string;
}): Record<string, unknown> {
  return {
    schemaVersion: USER_RELATIONSHIP_GUARD_SCHEMA_VERSION,
    pairKey: params.pair.pairKey,
    uidA: params.pair.uidA,
    uidB: params.pair.uidB,
    blocked: false,
    status: "open",
    bookingMutationVersion: FieldValue.increment(1),
    lastBookingId: params.bookingId,
    lastBookingOperation: params.operation,
    lastBookingMutationAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

export async function readOpenRelationshipGuardInTransaction(params: {
  firestore: Firestore;
  transaction: Transaction;
  firstUid: string;
  secondUid: string;
}): Promise<{
  pair: CanonicalUserPair;
  ref: DocumentReference<DocumentData>;
  snapshot: DocumentSnapshot<DocumentData>;
}> {
  const state = await getEffectiveRelationshipStateInTransaction(params);
  assertEffectiveRelationshipOpen(state);
  return {pair: state.pair, ref: state.ref, snapshot: state.snapshot};
}

export async function assertRelationshipOpen(params: {
  firestore: Firestore;
  firstUid: string;
  secondUid: string;
}): Promise<void> {
  assertEffectiveRelationshipOpen(await getEffectiveRelationshipState(params));
}
