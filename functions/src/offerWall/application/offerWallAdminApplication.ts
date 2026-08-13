import {FieldValue} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {db} from "../../shared/firebase";
import {
  normalizeOfferWallCampaignInput,
  normalizeOfferWallStatus,
  serializeOfferWallCampaign,
  type OfferWallCampaign,
} from "../domain/offerWallCampaign";

const allowedOfferWallAdminRoles = new Set([
  "superAdmin",
  "financeAdmin",
]);

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export async function requireOfferWallAdminActor(uid: string): Promise<{
  uid: string;
  role: string;
}> {
  const snapshot = await db.collection("users").doc(uid).get();
  if (!snapshot.exists) {
    throw new HttpsError("permission-denied", "Admin profile not found.");
  }

  const role = asTrimmedString(snapshot.data()?.adminRole);
  if (!allowedOfferWallAdminRoles.has(role)) {
    throw new HttpsError(
      "permission-denied",
      "You are not allowed to manage Offer Wall campaigns.",
    );
  }

  return {uid, role};
}

function offerWallCampaignRef(campaignId: string) {
  return db.collection("offerWallCampaigns").doc(campaignId);
}

function logOfferWallMutation(params: {
  event: string;
  campaignId: string;
  creativeStoragePathPresent: boolean;
}) {
  console.info(
    `[OfferWall] ${params.event} campaignId=${params.campaignId} creativeStoragePathPresent=${params.creativeStoragePathPresent}`,
  );
}

function toOfferWallValidationHttpsError(error: unknown): HttpsError {
  if (error instanceof HttpsError) {
    return error;
  }

  const message = error instanceof Error ? error.message.trim() : "";
  if (message === "Offer Wall creative is required before activation.") {
    return new HttpsError("failed-precondition", message);
  }
  if (message) {
    return new HttpsError("invalid-argument", message);
  }
  return new HttpsError(
    "internal",
    "Offer Wall campaign validation failed unexpectedly.",
  );
}

function normalizeOfferWallCampaignOrThrow(params: {
  id: string;
  data: Record<string, unknown>;
}): OfferWallCampaign {
  try {
    return normalizeOfferWallCampaignInput(params);
  } catch (error) {
    throw toOfferWallValidationHttpsError(error);
  }
}

function buildStoredCampaign(params: {
  campaignId: string;
  payload: Record<string, unknown>;
  existing?: OfferWallCampaign | null;
  actor: {uid: string; role: string};
}): Record<string, unknown> {
  const existing = params.existing;
  const mergedData = {
    name: existing?.name ?? "",
    creativeStoragePath: existing?.creativeStoragePath ?? "",
    creativeDownloadUrl: existing?.creativeDownloadUrl ?? "",
    audiences: existing?.audiences ?? [],
    openInterval: existing?.openInterval ?? 0,
    repetitionLimit: existing?.repetitionLimit ?? 0,
    status: existing?.status ?? "draft",
    createdAt: existing?.createdAt ?? null,
    updatedAt: existing?.updatedAt ?? null,
    createdBy: existing?.createdBy ?? params.actor.uid,
    createdByRole: existing?.createdByRole ?? params.actor.role,
    updatedBy: params.actor.uid,
    updatedByRole: params.actor.role,
    ...params.payload,
  };
  const candidate = normalizeOfferWallCampaignOrThrow({
    id: params.campaignId,
    data: mergedData,
  });

  return {
    id: params.campaignId,
    name: candidate.name,
    creativeStoragePath: candidate.creativeStoragePath,
    creativeDownloadUrl: candidate.creativeDownloadUrl,
    audiences: [...candidate.audiences],
    openInterval: candidate.openInterval,
    repetitionLimit: candidate.repetitionLimit,
    status: candidate.status,
    createdBy: existing?.createdBy || params.actor.uid,
    createdByRole: existing?.createdByRole || params.actor.role,
    updatedBy: params.actor.uid,
    updatedByRole: params.actor.role,
    ...(existing ? {} : {createdAt: FieldValue.serverTimestamp()}),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

export async function createOfferWallCampaignDocument(params: {
  payload: Record<string, unknown>;
  actor: {uid: string; role: string};
}): Promise<{campaignId: string}> {
  const campaignRef = db.collection("offerWallCampaigns").doc();
  const stored = buildStoredCampaign({
    campaignId: campaignRef.id,
    payload: params.payload,
    actor: params.actor,
  });
  await campaignRef.set(stored);
  return {campaignId: campaignRef.id};
}

export async function updateOfferWallCampaignDocument(params: {
  campaignId: string;
  payload: Record<string, unknown>;
  actor: {uid: string; role: string};
}): Promise<void> {
  const ref = offerWallCampaignRef(params.campaignId);
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Offer Wall campaign not found.");
  }
  const existing = normalizeOfferWallCampaignOrThrow({
    id: snapshot.id,
    data: snapshot.data() ?? {},
  });
  const mergedCreativeStoragePath =
    typeof params.payload.creativeStoragePath === "string" ?
      params.payload.creativeStoragePath.trim() :
      existing.creativeStoragePath;
  logOfferWallMutation({
    event: "update campaign",
    campaignId: params.campaignId,
    creativeStoragePathPresent: mergedCreativeStoragePath.length > 0,
  });
  await ref.set(
    buildStoredCampaign({
      campaignId: params.campaignId,
      payload: params.payload,
      existing,
      actor: params.actor,
    }),
    {merge: true},
  );
}

export async function setOfferWallCampaignStatusDocument(params: {
  campaignId: string;
  status: unknown;
  actor: {uid: string; role: string};
}): Promise<void> {
  const ref = offerWallCampaignRef(params.campaignId);
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Offer Wall campaign not found.");
  }
  const existing = normalizeOfferWallCampaignOrThrow({
    id: snapshot.id,
    data: snapshot.data() ?? {},
  });
  logOfferWallMutation({
    event: "loaded campaign for activation",
    campaignId: params.campaignId,
    creativeStoragePathPresent: existing.creativeStoragePath.length > 0,
  });
  const status = normalizeOfferWallStatus(params.status);
  await ref.set(
    buildStoredCampaign({
      campaignId: params.campaignId,
      payload: {status},
      existing,
      actor: params.actor,
    }),
    {merge: true},
  );
}

export async function listOfferWallCampaignDocuments(): Promise<Record<string, unknown>[]> {
  const snapshot = await db.collection("offerWallCampaigns").get();
  const campaigns = snapshot.docs.map((doc) => normalizeOfferWallCampaignOrThrow({
    id: doc.id,
    data: doc.data() ?? {},
  }));
  campaigns.sort((left, right) => {
    const leftUpdatedAt = left.updatedAt?.getTime() ?? 0;
    const rightUpdatedAt = right.updatedAt?.getTime() ?? 0;
    if (leftUpdatedAt != rightUpdatedAt) {
      return rightUpdatedAt - leftUpdatedAt;
    }
    return left.id.localeCompare(right.id);
  });
  return campaigns.map((campaign) => serializeOfferWallCampaign(campaign));
}
