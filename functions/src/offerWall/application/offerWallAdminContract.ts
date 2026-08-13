import {HttpsError} from "firebase-functions/https";

const offerWallMutationFields = [
  "name",
  "creativeStoragePath",
  "audiences",
  "openInterval",
  "repetitionLimit",
  "status",
] as const;

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> :
    {};
}

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function sanitizeOfferWallMutationInput(params: {
  rawData: unknown;
  requireCampaignId: boolean;
}): {
  campaignId: string;
  payload: Record<string, unknown>;
} {
  const data = asRecord(params.rawData);
  const campaignId = asTrimmedString(data.campaignId);
  if (params.requireCampaignId && !campaignId) {
    throw new HttpsError("invalid-argument", "campaignId is required.");
  }

  const payload = {...data};
  delete payload.campaignId;

  const invalidKeys = Object.keys(payload).filter(
    (key) => !offerWallMutationFields.includes(
      key as typeof offerWallMutationFields[number],
    ),
  );
  if (invalidKeys.length > 0) {
    throw new HttpsError(
      "invalid-argument",
      `Unsupported fields: ${invalidKeys.join(", ")}.`,
    );
  }

  return {campaignId, payload};
}
