import {
  FieldPath,
  FieldValue,
  QueryDocumentSnapshot,
  Timestamp,
  type Transaction,
} from "firebase-admin/firestore";

import {db} from "../../shared/firebase";
import {
  isCanonicalOfferUserRole,
  type CanonicalOfferUserRole,
} from "../domain/offerAudience";
import {normalizePromoCode, promoCodeHash} from "../domain/promoCode";

const PROMO_ATTEMPT_WINDOW_MS = 10 * 60 * 1000;
export const PROMO_ATTEMPT_LIMIT = 8;

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asOptionalPositiveInt(value: unknown): number | null {
  return typeof value === "number" &&
      Number.isInteger(value) &&
      value >= 0 ?
    value :
    null;
}

function asDate(value: unknown): Date | null {
  if (
    value &&
    typeof value === "object" &&
    typeof (value as {toDate?: unknown}).toDate === "function"
  ) {
    return ((value as {toDate: () => Date}).toDate());
  }
  return null;
}

export type OfferUserProfileRecord = {
  uid: string;
  role: CanonicalOfferUserRole | "";
  completedBookingCount: number;
};

export type OfferUsageRecord = {
  offerCampaignId: string;
  usedCount: number;
  consumedBookingIds: string[];
  lastUsedAt: Date | null;
};

function toOfferUsageRecord(params: {
  campaignId: string;
  data: Record<string, unknown>;
}): OfferUsageRecord {
  const consumedBookingIds = Array.isArray(params.data.consumedBookingIds) ?
    params.data.consumedBookingIds
      .map((entry) => asTrimmedString(entry))
      .filter(Boolean) :
    [];

  return {
    offerCampaignId: asTrimmedString(params.data.offerCampaignId) || params.campaignId,
    usedCount: asOptionalPositiveInt(params.data.usedCount) ?? 0,
    consumedBookingIds,
    lastUsedAt: asDate(params.data.lastUsedAt),
  };
}

export async function loadOfferUserProfile(
  uid: string,
): Promise<OfferUserProfileRecord> {
  const userSnapshot = await db.collection("users").doc(uid).get();
  if (!userSnapshot.exists) {
    throw new Error("User document not found.");
  }

  const userData = userSnapshot.data() ?? {};
  const rawRole = asTrimmedString(userData.role);
  const explicitCount =
    asOptionalPositiveInt(userData.completedBookingCount) ??
    asOptionalPositiveInt(userData.completedBookingsCount);
  const completedBookingCount = explicitCount ??
    await loadCompletedBookingCountForUser(uid);

  return {
    uid,
    role: isCanonicalOfferUserRole(rawRole) ? rawRole : "",
    completedBookingCount,
  };
}

async function loadCompletedBookingCountForUser(uid: string): Promise<number> {
  const aggregate = await db
    .collection("bookings")
    .where("customerId", "==", uid)
    .where("status", "==", "completed")
    .count()
    .get();
  return aggregate.data().count;
}

export async function listActiveOfferCampaignDocs(): Promise<
  QueryDocumentSnapshot[]
> {
  const snapshot = await db
    .collection("offerCampaigns")
    .where("isActive", "==", true)
    .orderBy(FieldPath.documentId())
    .get();
  return snapshot.docs;
}

export async function loadOfferCampaignDoc(
  campaignId: string,
): Promise<QueryDocumentSnapshot | null> {
  const snapshot = await db.collection("offerCampaigns").doc(campaignId).get();
  if (!snapshot.exists) return null;
  return snapshot as QueryDocumentSnapshot;
}

export async function loadOfferUsageRecord(
  uid: string,
  campaignId: string,
): Promise<OfferUsageRecord> {
  const snapshot = await db
    .collection("users")
    .doc(uid)
    .collection("offerUsage")
    .doc(campaignId)
    .get();
  if (!snapshot.exists) {
    return {
      offerCampaignId: campaignId,
      usedCount: 0,
      consumedBookingIds: [],
      lastUsedAt: null,
    };
  }

  return toOfferUsageRecord({
    campaignId,
    data: snapshot.data() ?? {},
  });
}

export async function listOfferUsageRecords(
  uid: string,
): Promise<OfferUsageRecord[]> {
  const snapshot = await db
    .collection("users")
    .doc(uid)
    .collection("offerUsage")
    .get();

  return snapshot.docs.map((doc) => toOfferUsageRecord({
    campaignId: doc.id,
    data: doc.data(),
  }));
}

export type ResolvedPromoCode = {
  normalizedCode: string;
  campaignId: string;
};

export async function assertPromoCodeAttemptAllowed(params: {
  uid: string;
  now?: Date;
}): Promise<void> {
  const now = params.now ?? new Date();
  const ref = db.collection("offerRedemptionRateLimits").doc(params.uid);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.data() ?? {};
    const windowStartedAt = asDate(data.windowStartedAt);
    const inCurrentWindow = windowStartedAt != null &&
      now.getTime() - windowStartedAt.getTime() < PROMO_ATTEMPT_WINDOW_MS;
    const attemptCount = inCurrentWindow ?
      (asOptionalPositiveInt(data.attemptCount) ?? 0) :
      0;
    if (attemptCount >= PROMO_ATTEMPT_LIMIT) {
      throw new Error("PROMO_CODE_RATE_LIMITED");
    }
    transaction.set(ref, {
      uid: params.uid,
      attemptCount: attemptCount + 1,
      windowStartedAt: Timestamp.fromDate(inCurrentWindow ? windowStartedAt! : now),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

export async function resolveOfferCampaignByPromoCode(
  rawCode: unknown,
): Promise<ResolvedPromoCode | null> {
  const normalizedCode = normalizePromoCode(rawCode);
  const indexRef = db.collection("offerCodeIndex").doc(promoCodeHash(normalizedCode));
  const indexed = await indexRef.get();
  if (indexed.exists) {
    const data = indexed.data() ?? {};
    const campaignId = asTrimmedString(data.campaignId);
    return data.state === "active" && campaignId ?
      {normalizedCode, campaignId} :
      null;
  }

  // Legacy campaigns predate offerCodeIndex. Exact equality against the
  // canonical value keeps this bounded and non-enumerating. A successful
  // legacy resolution is indexed transactionally for future direct reads.
  const legacy = await db.collection("offerCampaigns")
    .where("couponCode", "==", normalizedCode)
    .limit(3)
    .get();
  const matches = legacy.docs.filter((doc) => {
    try {
      return normalizePromoCode(doc.data().couponCode) === normalizedCode;
    } catch {
      return false;
    }
  });
  if (matches.length !== 1) return null;
  const campaignId = matches[0].id;
  const owner = await db.runTransaction(async (transaction) => {
    const current = await transaction.get(indexRef);
    if (current.exists) {
      const data = current.data() ?? {};
      return data.state === "active" ? asTrimmedString(data.campaignId) : "";
    }
    transaction.create(indexRef, {
      campaignId,
      state: "active",
      codeHashVersion: 1,
      reservedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      source: "legacy_exact_lookup",
    });
    return campaignId;
  });
  return owner === campaignId ? {normalizedCode, campaignId} : null;
}

export async function reserveOfferCodeInTransaction(params: {
  transaction: Transaction;
  campaignId: string;
  couponCode: unknown;
  previousCouponCode?: unknown;
}): Promise<string> {
  const normalizedCode = normalizePromoCode(params.couponCode);
  const newRef = db.collection("offerCodeIndex").doc(promoCodeHash(normalizedCode));
  let previousNormalized = "";
  try {
    previousNormalized = params.previousCouponCode == null ?
      "" : normalizePromoCode(params.previousCouponCode);
  } catch {
    // Invalid legacy codes cannot be safely indexed, but remain in their
    // historical campaign document.
  }
  const oldRef = previousNormalized && previousNormalized !== normalizedCode ?
    db.collection("offerCodeIndex").doc(promoCodeHash(previousNormalized)) :
    null;
  const [newSnapshot, oldSnapshot] = await Promise.all([
    params.transaction.get(newRef),
    oldRef ? params.transaction.get(oldRef) : Promise.resolve(null),
  ]);
  if (newSnapshot.exists &&
    asTrimmedString(newSnapshot.data()?.campaignId) !== params.campaignId) {
    throw new Error("PROMO_CODE_ALREADY_RESERVED");
  }
  if (oldRef && oldSnapshot) {
    const oldOwner = asTrimmedString(oldSnapshot.data()?.campaignId);
    if (oldSnapshot.exists && oldOwner && oldOwner !== params.campaignId) {
      throw new Error("PROMO_CODE_ALREADY_RESERVED");
    }
    params.transaction.set(oldRef, {
      campaignId: params.campaignId,
      state: "retired",
      codeHashVersion: 1,
      retiredAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  params.transaction.set(newRef, {
    campaignId: params.campaignId,
    state: "active",
    codeHashVersion: 1,
    reservedAt: newSnapshot.exists ?
      (newSnapshot.data()?.reservedAt ?? FieldValue.serverTimestamp()) :
      FieldValue.serverTimestamp(),
    retiredAt: null,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  return normalizedCode;
}
