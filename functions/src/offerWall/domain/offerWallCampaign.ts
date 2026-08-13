import {Timestamp} from "firebase-admin/firestore";

import {
  normalizeOfferWallAudiences,
  type OfferWallAudience,
} from "./offerWallAudience";

export const offerWallStatusValues = [
  "draft",
  "active",
  "paused",
  "ended",
] as const;

export type OfferWallStatus = typeof offerWallStatusValues[number];

export type OfferWallCampaign = {
  id: string;
  name: string;
  creativeStoragePath: string;
  creativeDownloadUrl: string;
  audiences: OfferWallAudience[];
  openInterval: number;
  repetitionLimit: number;
  status: OfferWallStatus;
  createdAt: Date | null;
  updatedAt: Date | null;
  createdBy: string;
  createdByRole: string;
  updatedBy: string;
  updatedByRole: string;
};

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asPositiveInt(value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) {
    throw new Error("Expected a positive integer.");
  }
  return value;
}

function asDate(value: unknown): Date | null {
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  return null;
}

export function isOfferWallStatus(value: string): value is OfferWallStatus {
  return offerWallStatusValues.includes(value as OfferWallStatus);
}

export function normalizeOfferWallStatus(value: unknown): OfferWallStatus {
  const status = asTrimmedString(value);
  if (!isOfferWallStatus(status)) {
    throw new Error("Offer Wall status is invalid.");
  }
  return status;
}

export function normalizeOfferWallCampaignInput(params: {
  id: string;
  data: Record<string, unknown>;
}): OfferWallCampaign {
  const name = asTrimmedString(params.data.name);
  if (!name) {
    throw new Error("Offer Wall name is required.");
  }

  const creativeStoragePath = asTrimmedString(params.data.creativeStoragePath);
  const creativeDownloadUrl = asTrimmedString(params.data.creativeDownloadUrl);
  const audiences = normalizeOfferWallAudiences(params.data.audiences);
  const openInterval = asPositiveInt(params.data.openInterval);
  const repetitionLimit = asPositiveInt(params.data.repetitionLimit);
  const status = normalizeOfferWallStatus(params.data.status);

  if (status === "active" && !creativeStoragePath) {
    throw new Error("Offer Wall creative is required before activation.");
  }

  return {
    id: params.id,
    name,
    creativeStoragePath,
    creativeDownloadUrl,
    audiences,
    openInterval,
    repetitionLimit,
    status,
    createdAt: asDate(params.data.createdAt),
    updatedAt: asDate(params.data.updatedAt),
    createdBy: asTrimmedString(params.data.createdBy),
    createdByRole: asTrimmedString(params.data.createdByRole),
    updatedBy: asTrimmedString(params.data.updatedBy),
    updatedByRole: asTrimmedString(params.data.updatedByRole),
  };
}

export function serializeOfferWallCampaign(
  campaign: OfferWallCampaign,
): Record<string, unknown> {
  return {
    id: campaign.id,
    name: campaign.name,
    creativeStoragePath: campaign.creativeStoragePath,
    creativeDownloadUrl: campaign.creativeDownloadUrl,
    audiences: [...campaign.audiences],
    openInterval: campaign.openInterval,
    repetitionLimit: campaign.repetitionLimit,
    status: campaign.status,
    createdAt: campaign.createdAt,
    updatedAt: campaign.updatedAt,
    createdBy: campaign.createdBy,
    createdByRole: campaign.createdByRole,
    updatedBy: campaign.updatedBy,
    updatedByRole: campaign.updatedByRole,
  };
}
