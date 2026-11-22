import {
  FieldValue,
  type DocumentData,
  type DocumentReference,
  type Firestore,
  type QueryDocumentSnapshot,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {buildBookingEventPlan} from "../booking/application/bookingEventsWriter";
import {evaluateBookingTransition} from "../booking/application/bookingStateMachine";
import {
  CANONICAL_PAYMENT_ORDER_MAPPINGS_COLLECTION,
  CANONICAL_QR_PAYMENT_MAPPINGS_COLLECTION,
} from "../booking/application/paymentOrchestrationV3";
import {
  assertValidCanonicalBookingDocumentV3,
  type CanonicalBookingDocumentV3,
} from "../booking/schema/bookingDocumentV3";
import {buildStoredBookingNotificationDocument} from "../notifications/notificationChannels";
import {
  assertBlockingCreationEnabledInTransaction,
  readBlockingActivationState,
} from "./blockingActivationGate";
import {
  directReader,
  judgeHistoricalProtection,
  transactionReader,
} from "./historicalProtection";
import {
  USER_BLOCKS_COLLECTION,
  USER_RELATIONSHIP_GUARD_SCHEMA_VERSION,
  USER_RELATIONSHIP_GUARDS_COLLECTION,
  canonicalUserPair,
  directedBlockId,
} from "./relationshipGuard";

const MAX_PAIR_BOOKINGS = 100;
const ACTIVE_DISPUTE_STATUSES = new Set([
  "open",
  "under_review",
  "pending",
  "escalated",
  "disputed",
]);
const SETTLED_PAYMENT_STATUSES = new Set([
  "",
  "not_started",
  "confirmed",
  "paid",
  "refunded",
  "cancelled",
]);

export type RelationshipProtection =
  | {kind: "accepted_unpaid"; reason: "ACCEPTED_UNPAID"}
  | {kind: "protected"; reason: string}
  | {kind: "unprotected"; reason: "NO_PROTECTED_OBLIGATION"};

export type BlockUserResult = {
  success: true;
  pairKey: string;
  relationshipBlocked: true;
  blockedByCaller: true;
  cancelledBookingIds: string[];
  idempotentReplay: boolean;
};

export type UnblockUserResult = {
  success: true;
  pairKey: string;
  relationshipBlocked: boolean;
  blockedByCaller: false;
  idempotentReplay: boolean;
};

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

/**
 * Customer-side money only. A pending Pettxo->provider payout
 * (booking.payout.status) never protects a pair (Phase 3B-4 D4).
 */
function financialObligationIsUnresolved(booking: CanonicalBookingDocumentV3): boolean {
  const paymentStatus = normalized(booking.payment.status).toLowerCase();
  return !SETTLED_PAYMENT_STATUSES.has(paymentStatus);
}

export function classifyRelationshipProtectionV1(params: {
  booking: CanonicalBookingDocumentV3;
  authoritativeNow: Date;
}): RelationshipProtection {
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
  if (booking.state !== "COMPLETED_FINAL" &&
    !["CANCELLED", "NO_SHOW", "SERVICE_NOT_STARTED"].includes(booking.state)) {
    return {kind: "protected", reason: `PAID_STATE_${booking.state}`};
  }
  return {kind: "unprotected", reason: "NO_PROTECTED_OBLIGATION"};
}

function acceptedBookingHasUncertainPaymentData(
  booking: CanonicalBookingDocumentV3,
): boolean {
  return booking.financials != null ||
    normalized(booking.payment.paymentAttemptId).length > 0 ||
    normalized(booking.payment.razorpayOrderId).length > 0 ||
    normalized(booking.payment.razorpayPaymentId).length > 0 ||
    !["", "not_started", "awaiting_customer_payment"].includes(
      normalized(booking.payment.status).toLowerCase(),
    ) ||
    booking.lifecycle.paymentStartedAt != null;
}

export function cancelAcceptedUnpaidBookingForBlockV1(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  blockerUid: string;
  targetUid: string;
  authoritativeNow: Date;
}): {
  booking: CanonicalBookingDocumentV3;
  event: ReturnType<typeof buildBookingEventPlan>;
} {
  const transition = evaluateBookingTransition({
    fromState: params.booking.state,
    toState: "CANCELLED",
    actor: "system",
    now: params.authoritativeNow,
  });
  if (!transition.ok) {
    throw new HttpsError(
      "failed-precondition",
      "The unpaid booking could not be cancelled safely.",
      {
        code: "BLOCK_CANCELLATION_TRANSITION_REJECTED",
        bookingId: params.bookingId,
        transitionCode: transition.code,
      },
    );
  }
  const next = structuredClone(params.booking);
  next.state = "CANCELLED";
  next.stateQueryValue = "CANCELLED";
  next.lifecycle.cancelledAt = new Date(params.authoritativeNow.getTime());
  next.cancellation = {
    ...next.cancellation,
    cancelledAt: new Date(params.authoritativeNow.getTime()),
    cancelledBy: "system",
    cancelReasonCode: "USER_BLOCKED_BEFORE_PAYMENT",
    cancelReasonText: "Cancelled before payment because a participant blocked the other user.",
    hoursBeforeServiceAtCancel: null,
    refundBand: "unpaid_no_refund",
    refundBasisPoints: 0,
    refundAmountPaise: 0,
    providerCompensationPaise: 0,
    pettxoRetainedPaise: 0,
    cancellationType: "user_blocked",
  };
  next.updatedAt = new Date(params.authoritativeNow.getTime());
  next.audit = {
    ...next.audit,
    lastUpdatedBy: "system",
    source: "user_blocking_v1",
  };
  return {
    booking: next,
    event: buildBookingEventPlan({
      bookingId: params.bookingId,
      event: "cancelled",
      actor: "system",
      at: params.authoritativeNow,
      meta: {
        reasonCode: "USER_BLOCKED_BEFORE_PAYMENT",
        blockerUid: params.blockerUid,
        targetUid: params.targetUid,
      },
    }),
  };
}

function relationshipCancellationNotification(params: {
  bookingId: string;
  recipientUserId: string;
  recipientRole: "customer" | "provider";
  bookingType: string;
}): {idempotencyKey: string; document: Record<string, unknown>} {
  const idempotencyKey = `request_cancelled_by_user_block:${params.bookingId}:${params.recipientUserId}`;
  const notification = {
    recipientUserId: params.recipientUserId,
    type: "request_cancelled_by_user_block",
    title: "Booking request cancelled",
    body: "This unpaid booking was cancelled because interaction between the participants is no longer available.",
    channels: ["push", "in_app"],
    data: {
      bookingId: params.bookingId,
      bookingType: params.bookingType,
      state: "CANCELLED",
      recipientRole: params.recipientRole,
      navigationIntent: "request_status",
      bookingFlowVersion: "3.2",
    },
  };
  return {
    idempotencyKey,
    document: buildStoredBookingNotificationDocument({
      notification,
      actorId: "system",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      source: "user_blocking_v1",
    }),
  };
}

async function loadPairBookings(params: {
  firestore: Firestore;
  transaction: FirebaseFirestore.Transaction;
  uidA: string;
  uidB: string;
}): Promise<QueryDocumentSnapshot<DocumentData>[]> {
  const bookings = params.firestore.collection("bookings");
  const [aToB, bToA] = await Promise.all([
    params.transaction.get(
      bookings.where("parentId", "==", params.uidA)
        .where("providerId", "==", params.uidB)
        .limit(MAX_PAIR_BOOKINGS + 1),
    ),
    params.transaction.get(
      bookings.where("parentId", "==", params.uidB)
        .where("providerId", "==", params.uidA)
        .limit(MAX_PAIR_BOOKINGS + 1),
    ),
  ]);
  const byId = new Map<string, QueryDocumentSnapshot<DocumentData>>();
  for (const doc of [...aToB.docs, ...bToA.docs]) byId.set(doc.id, doc);
  if (byId.size > MAX_PAIR_BOOKINGS ||
    aToB.size > MAX_PAIR_BOOKINGS || bToA.size > MAX_PAIR_BOOKINGS) {
    throw new HttpsError(
      "resource-exhausted",
      "This relationship has too many bookings for automatic blocking. Contact support.",
      {code: "PAIR_BOOKING_LIMIT_EXCEEDED"},
    );
  }
  return [...byId.values()];
}

function historicalProtectionError(reason: string): never {
  throw new HttpsError(
    "failed-precondition",
    "A historical booking or financial obligation must be reconciled before these users can be blocked.",
    {code: "HISTORICAL_RELATIONSHIP_RECONCILIATION_REQUIRED", reason},
  );
}

function protectedBookingError(bookingId: string, reason: string): never {
  throw new HttpsError(
    "failed-precondition",
    "You can't block this user while you have an active paid booking or an open dispute. You can still report them or contact support.",
    {code: "PROTECTED_BOOKING_EXISTS", bookingId, reason},
  );
}

async function assertAcceptedBookingHasNoPaymentEvidence(params: {
  firestore: Firestore;
  transaction: FirebaseFirestore.Transaction;
  bookingRef: DocumentReference<DocumentData>;
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
}): Promise<void> {
  if (acceptedBookingHasUncertainPaymentData(params.booking)) {
    throw new HttpsError(
      "failed-precondition",
      "Payment status must be reconciled before these users can be blocked.",
      {code: "PAYMENT_RECONCILIATION_REQUIRED", bookingId: params.bookingId},
    );
  }
  const [attempts, orderMappings, qrMappings] = await Promise.all([
    params.transaction.get(params.bookingRef.collection("paymentAttempts").limit(1)),
    params.transaction.get(
      params.firestore.collection(CANONICAL_PAYMENT_ORDER_MAPPINGS_COLLECTION)
        .where("bookingId", "==", params.bookingId)
        .limit(1),
    ),
    params.transaction.get(
      params.firestore.collection(CANONICAL_QR_PAYMENT_MAPPINGS_COLLECTION)
        .where("bookingId", "==", params.bookingId)
        .limit(1),
    ),
  ]);
  if (!attempts.empty || !orderMappings.empty || !qrMappings.empty) {
    throw new HttpsError(
      "failed-precondition",
      "Payment status must be reconciled before these users can be blocked.",
      {code: "PAYMENT_RECONCILIATION_REQUIRED", bookingId: params.bookingId},
    );
  }
}

export async function blockUserDataV1(params: {
  firestore: Firestore;
  actorUid: string;
  targetUid: string;
  authoritativeNow?: Date;
}): Promise<BlockUserResult> {
  const authoritativeNow = params.authoritativeNow ?? new Date();
  const pair = canonicalUserPair(params.actorUid, params.targetUid);
  const guardRef = params.firestore
    .collection(USER_RELATIONSHIP_GUARDS_COLLECTION)
    .doc(pair.pairKey);
  const ownBlockRef = params.firestore.collection(USER_BLOCKS_COLLECTION)
    .doc(directedBlockId(params.actorUid, params.targetUid));
  const oppositeBlockRef = params.firestore.collection(USER_BLOCKS_COLLECTION)
    .doc(directedBlockId(params.targetUid, params.actorUid));
  const targetRef = params.firestore.collection("users").doc(params.targetUid);

  return params.firestore.runTransaction(async (transaction) => {
    await assertBlockingCreationEnabledInTransaction({
      firestore: params.firestore,
      transaction,
    });
    const [guardSnapshot, ownBlockSnapshot, oppositeBlockSnapshot, targetSnapshot] =
      await Promise.all([
        transaction.get(guardRef),
        transaction.get(ownBlockRef),
        transaction.get(oppositeBlockRef),
        transaction.get(targetRef),
      ]);
    if (!targetSnapshot.exists) {
      throw new HttpsError("not-found", "User not found.", {code: "TARGET_USER_NOT_FOUND"});
    }
    const bookingDocs = await loadPairBookings({
      firestore: params.firestore,
      transaction,
      uidA: pair.uidA,
      uidB: pair.uidB,
    });
    const acceptedToCancel: Array<{
      ref: DocumentReference<DocumentData>;
      bookingId: string;
      booking: CanonicalBookingDocumentV3;
    }> = [];
    for (const bookingDoc of bookingDocs) {
      let booking: CanonicalBookingDocumentV3;
      try {
        booking = assertValidCanonicalBookingDocumentV3(bookingDoc.data());
      } catch {
        throw new HttpsError(
          "failed-precondition",
          "A booking requires server repair before these users can be blocked.",
          {code: "INVALID_CANONICAL_BOOKING", bookingId: bookingDoc.id},
        );
      }
      const protection = classifyRelationshipProtectionV1({booking, authoritativeNow});
      if (protection.kind === "protected") {
        protectedBookingError(bookingDoc.id, protection.reason);
      }
      if (protection.kind === "accepted_unpaid") {
        acceptedToCancel.push({ref: bookingDoc.ref, bookingId: bookingDoc.id, booking});
      }
    }
    for (const accepted of acceptedToCancel) {
      await assertAcceptedBookingHasNoPaymentEvidence({
        firestore: params.firestore,
        transaction,
        bookingRef: accepted.ref,
        bookingId: accepted.bookingId,
        booking: accepted.booking,
      });
    }
    // D2: a historical mark protects only while something live still does.
    const historical = await judgeHistoricalProtection({
      firestore: params.firestore,
      reader: transactionReader(transaction),
      pairKey: pair.pairKey,
      guardData: guardSnapshot.data(),
      liveBookingIds: bookingDocs.map((doc) => doc.id),
    });
    if (historical.marked && historical.stillProtected) {
      historicalProtectionError(historical.reason);
    }

    const cancelledBookingIds: string[] = [];
    for (const accepted of acceptedToCancel) {
      const cancelled = cancelAcceptedUnpaidBookingForBlockV1({
        bookingId: accepted.bookingId,
        booking: accepted.booking,
        blockerUid: params.actorUid,
        targetUid: params.targetUid,
        authoritativeNow,
      });
      transaction.set(accepted.ref, cancelled.booking, {merge: false});
      transaction.set(
        accepted.ref.collection("events").doc(cancelled.event.eventId),
        cancelled.event.record,
        {merge: false},
      );
      for (const notification of [
        relationshipCancellationNotification({
          bookingId: accepted.bookingId,
          recipientUserId: accepted.booking.parentId,
          recipientRole: "customer",
          bookingType: accepted.booking.bookingType,
        }),
        relationshipCancellationNotification({
          bookingId: accepted.bookingId,
          recipientUserId: accepted.booking.providerId,
          recipientRole: "provider",
          bookingType: accepted.booking.bookingType,
        }),
      ]) {
        transaction.set(
          params.firestore.collection("notifications").doc(notification.idempotencyKey),
          notification.document,
          {merge: true},
        );
      }
      cancelledBookingIds.push(accepted.bookingId);
    }

    if (!ownBlockSnapshot.exists) {
      transaction.create(ownBlockRef, {
        schemaVersion: 1,
        ownerUserId: params.actorUid,
        blockerUid: params.actorUid,
        blockedUserId: params.targetUid,
        pairKey: pair.pairKey,
        status: "active",
        source: "server_block_user_v1",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    const activeDirectedBlockIds = [
      ownBlockRef.id,
      ...(oppositeBlockSnapshot.exists ? [oppositeBlockRef.id] : []),
    ].sort();
    transaction.set(guardRef, {
      schemaVersion: USER_RELATIONSHIP_GUARD_SCHEMA_VERSION,
      pairKey: pair.pairKey,
      uidA: pair.uidA,
      uidB: pair.uidB,
      blocked: true,
      status: "blocked",
      activeDirectedBlockIds,
      relationshipVersion: FieldValue.increment(1),
      blockedAt: guardSnapshot.data()?.blockedAt ?? FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      // historicalProtectionReasons is left untouched as history.
      ...(historical.marked ? {
        historicalProtectionBlocked: false,
        historicalProtectionClearedAt: FieldValue.serverTimestamp(),
        historicalProtectionClearedReason: "LIVE_OBLIGATION_ENDED",
      } : {}),
    }, {merge: true});
    return {
      success: true,
      pairKey: pair.pairKey,
      relationshipBlocked: true,
      blockedByCaller: true,
      cancelledBookingIds,
      idempotentReplay: ownBlockSnapshot.exists,
    };
  });
}

export async function unblockUserDataV1(params: {
  firestore: Firestore;
  actorUid: string;
  targetUid: string;
}): Promise<UnblockUserResult> {
  const pair = canonicalUserPair(params.actorUid, params.targetUid);
  const guardRef = params.firestore.collection(USER_RELATIONSHIP_GUARDS_COLLECTION).doc(pair.pairKey);
  const ownBlockRef = params.firestore.collection(USER_BLOCKS_COLLECTION)
    .doc(directedBlockId(params.actorUid, params.targetUid));
  const oppositeBlockRef = params.firestore.collection(USER_BLOCKS_COLLECTION)
    .doc(directedBlockId(params.targetUid, params.actorUid));
  return params.firestore.runTransaction(async (transaction) => {
    const [guardSnapshot, ownBlockSnapshot, oppositeBlockSnapshot] = await Promise.all([
      transaction.get(guardRef),
      transaction.get(ownBlockRef),
      transaction.get(oppositeBlockRef),
    ]);
    if (ownBlockSnapshot.exists) transaction.delete(ownBlockRef);
    const relationshipBlocked = oppositeBlockSnapshot.exists;
    transaction.set(guardRef, {
      schemaVersion: USER_RELATIONSHIP_GUARD_SCHEMA_VERSION,
      pairKey: pair.pairKey,
      uidA: pair.uidA,
      uidB: pair.uidB,
      blocked: relationshipBlocked,
      status: relationshipBlocked ? "blocked" : "open",
      activeDirectedBlockIds: relationshipBlocked ? [oppositeBlockRef.id] : [],
      relationshipVersion: FieldValue.increment(1),
      unblockedAt: relationshipBlocked ? null : FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return {
      success: true,
      pairKey: pair.pairKey,
      relationshipBlocked,
      blockedByCaller: false,
      idempotentReplay: !ownBlockSnapshot.exists &&
        guardSnapshot.data()?.blocked === relationshipBlocked,
    };
  });
}

export async function getUserRelationshipStateDataV1(params: {
  firestore: Firestore;
  actorUid: string;
  targetUid: string;
  authoritativeNow?: Date;
}): Promise<Record<string, unknown>> {
  const authoritativeNow = params.authoritativeNow ?? new Date();
  const pair = canonicalUserPair(params.actorUid, params.targetUid);
  const [activation, guardSnapshot, ownBlockSnapshot, oppositeBlockSnapshot, targetSnapshot, aToB, bToA] = await Promise.all([
    readBlockingActivationState(params.firestore),
    params.firestore.collection(USER_RELATIONSHIP_GUARDS_COLLECTION).doc(pair.pairKey).get(),
    params.firestore.collection(USER_BLOCKS_COLLECTION)
      .doc(directedBlockId(params.actorUid, params.targetUid)).get(),
    params.firestore.collection(USER_BLOCKS_COLLECTION)
      .doc(directedBlockId(params.targetUid, params.actorUid)).get(),
    params.firestore.collection("users").doc(params.targetUid).get(),
    params.firestore.collection("bookings")
      .where("parentId", "==", pair.uidA).where("providerId", "==", pair.uidB)
      .limit(MAX_PAIR_BOOKINGS + 1).get(),
    params.firestore.collection("bookings")
      .where("parentId", "==", pair.uidB).where("providerId", "==", pair.uidA)
      .limit(MAX_PAIR_BOOKINGS + 1).get(),
  ]);
  if (!targetSnapshot.exists) {
    throw new HttpsError("not-found", "User not found.", {code: "TARGET_USER_NOT_FOUND"});
  }
  if (!activation.enabled) {
    return {
      pairKey: pair.pairKey,
      relationshipBlocked: guardSnapshot.data()?.blocked === true ||
        ownBlockSnapshot.exists || oppositeBlockSnapshot.exists,
      blockedByCaller: ownBlockSnapshot.exists,
      canBlock: false,
      reasonCode: activation.reasonCode,
      acceptedUnpaidBookingCount: 0,
    };
  }
  const docs = new Map([...aToB.docs, ...bToA.docs].map((doc) => [doc.id, doc]));
  if (docs.size > MAX_PAIR_BOOKINGS) {
    return {
      pairKey: pair.pairKey,
      relationshipBlocked: guardSnapshot.data()?.blocked === true ||
        ownBlockSnapshot.exists || oppositeBlockSnapshot.exists,
      blockedByCaller: ownBlockSnapshot.exists,
      canBlock: false,
      reasonCode: "PAIR_BOOKING_LIMIT_EXCEEDED",
      acceptedUnpaidBookingCount: 0,
    };
  }
  let acceptedUnpaidBookingCount = 0;
  let protectedReason = "";
  const acceptedBookingDocs: QueryDocumentSnapshot<DocumentData>[] = [];
  for (const doc of docs.values()) {
    try {
      const booking = assertValidCanonicalBookingDocumentV3(doc.data());
      const protection = classifyRelationshipProtectionV1({booking, authoritativeNow});
      if (protection.kind === "accepted_unpaid") {
        acceptedUnpaidBookingCount += 1;
        acceptedBookingDocs.push(doc);
        if (acceptedBookingHasUncertainPaymentData(booking)) {
          protectedReason = "PAYMENT_RECONCILIATION_REQUIRED";
        }
      }
      if (protection.kind === "protected" && !protectedReason) {
        protectedReason = protection.reason;
      }
    } catch {
      protectedReason = "INVALID_CANONICAL_BOOKING";
    }
  }
  if (!protectedReason && acceptedBookingDocs.length > 0) {
    const evidence = await Promise.all(acceptedBookingDocs.map(async (bookingDoc) => {
      const [attempts, orderMappings, qrMappings] = await Promise.all([
        bookingDoc.ref.collection("paymentAttempts").limit(1).get(),
        params.firestore.collection(CANONICAL_PAYMENT_ORDER_MAPPINGS_COLLECTION)
          .where("bookingId", "==", bookingDoc.id).limit(1).get(),
        params.firestore.collection(CANONICAL_QR_PAYMENT_MAPPINGS_COLLECTION)
          .where("bookingId", "==", bookingDoc.id).limit(1).get(),
      ]);
      return !attempts.empty || !orderMappings.empty || !qrMappings.empty;
    }));
    if (evidence.some(Boolean)) protectedReason = "PAYMENT_RECONCILIATION_REQUIRED";
  }
  if (!protectedReason) {
    // D2, read-only: the same judgement blockUserDataV1 makes.
    const historical = await judgeHistoricalProtection({
      firestore: params.firestore,
      reader: directReader,
      pairKey: pair.pairKey,
      guardData: guardSnapshot.data(),
      liveBookingIds: [...docs.keys()],
    });
    if (historical.marked && historical.stillProtected) {
      protectedReason = "HISTORICAL_RELATIONSHIP_RECONCILIATION_REQUIRED";
    }
  }
  return {
    pairKey: pair.pairKey,
    relationshipBlocked: guardSnapshot.data()?.blocked === true ||
      ownBlockSnapshot.exists || oppositeBlockSnapshot.exists,
    blockedByCaller: ownBlockSnapshot.exists,
    canBlock: !protectedReason,
    reasonCode: protectedReason || "",
    acceptedUnpaidBookingCount,
  };
}
