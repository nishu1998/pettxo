import {
  FieldValue,
  type Firestore,
  type Transaction,
} from "firebase-admin/firestore";

import {loadOfferCampaignDoc} from "../data/offerRepository";
import {isOfferUsageExhausted} from "../domain/offerUsagePolicy";

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asNonNegativeInt(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ?
    Math.trunc(value) :
    0;
}

export type OfferUsageConsumptionOutcome =
  | "consumed"
  | "idempotent"
  | "exhausted";

async function resolveUsageLimitPerUser(params: {
  offerCampaignId: string;
  usageLimitPerUser: number | null;
}): Promise<number> {
  if (
    typeof params.usageLimitPerUser === "number" &&
    Number.isFinite(params.usageLimitPerUser)
  ) {
    return Math.trunc(params.usageLimitPerUser);
  }

  const campaignDoc = await loadOfferCampaignDoc(params.offerCampaignId);
  const rawUsageLimit = campaignDoc?.data()?.usageLimitPerUser;
  return typeof rawUsageLimit === "number" && Number.isFinite(rawUsageLimit) ?
    Math.trunc(rawUsageLimit) :
    1;
}

export async function consumeOfferUsageInTransaction(params: {
  firestore: Firestore;
  transaction: Transaction;
  uid: string;
  offerCampaignId: string;
  bookingId: string;
  paymentAttemptId: string;
  couponCode: string;
  usageLimitPerUser: number | null;
}): Promise<OfferUsageConsumptionOutcome> {
  const usageLimitPerUser = await resolveUsageLimitPerUser({
    offerCampaignId: params.offerCampaignId,
    usageLimitPerUser: params.usageLimitPerUser,
  });
  const usageRef = params.firestore
    .collection("users")
    .doc(params.uid)
    .collection("offerUsage")
    .doc(params.offerCampaignId);
  const usageSnapshot = await params.transaction.get(usageRef);
  const usageData = usageSnapshot.data() ?? {};
  const consumedBookingIds = Array.isArray(usageData.consumedBookingIds) ?
    usageData.consumedBookingIds.map((entry) => asString(entry)).filter(Boolean) :
    [];
  if (consumedBookingIds.includes(params.bookingId)) {
    return "idempotent";
  }

  const usedCount = asNonNegativeInt(usageData.usedCount);
  if (isOfferUsageExhausted({usedCount, usageLimitPerUser})) {
    return "exhausted";
  }

  const usageUpdate: Record<string, unknown> = {
    offerCampaignId: params.offerCampaignId,
    usedCount: FieldValue.increment(1),
    consumedBookingIds: FieldValue.arrayUnion(params.bookingId),
    lastUsedAt: FieldValue.serverTimestamp(),
    lastBookingId: params.bookingId,
    lastPaymentAttemptId: params.paymentAttemptId,
    couponCode: params.couponCode,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (!usageSnapshot.exists) {
    usageUpdate.createdAt = FieldValue.serverTimestamp();
  }
  params.transaction.set(usageRef, usageUpdate, {merge: true});
  return "consumed";
}
