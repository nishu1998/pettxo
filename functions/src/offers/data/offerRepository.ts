import {FieldPath, QueryDocumentSnapshot} from "firebase-admin/firestore";

import {db} from "../../shared/firebase";
import {
  isCanonicalOfferUserRole,
  type CanonicalOfferUserRole,
} from "../domain/offerAudience";

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
