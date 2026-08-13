import {HttpsError} from "firebase-functions/https";

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> :
    {};
}

export const offerCampaignMutationFields = [
  "title",
  "description",
  "couponCode",
  "campaignType",
  "discountType",
  "discountValue",
  "maxDiscountAmount",
  "minBookingAmount",
  "isActive",
  "startAt",
  "endAt",
  "usageLimitPerUser",
  "targeting",
  "audience",
  "priority",
] as const;

const legacyOfferMutationIdentityAliases = ["offerCampaignId", "id"] as const;
const ignoredLegacyOfferMutationFields = [
  "claimValidityType",
  "claimValidUntil",
  "validDaysAfterClaim",
  "displayType",
] as const;

function throwUnsupportedOfferFields(fields: string[]): never {
  throw new HttpsError(
    "invalid-argument",
    `Unsupported fields: ${fields.join(", ")}.`,
  );
}

export function sanitizeOfferCampaignMutationInput(params: {
  rawData: unknown;
  requireCampaignId: boolean;
  allowLegacyIdentityAliases?: boolean;
}): {
  campaignId: string;
  payload: Record<string, unknown>;
  ignoredLegacyFields: string[];
  usedLegacyIdentityAlias: boolean;
} {
  const data = asRecord(params.rawData);
  const allowLegacyIdentityAliases = params.allowLegacyIdentityAliases !== false;

  const campaignId = asTrimmedString(data.campaignId);
  const legacyIds = allowLegacyIdentityAliases ?
    legacyOfferMutationIdentityAliases
      .map((key) => asTrimmedString(data[key]))
      .filter(Boolean) :
    [];
  const distinctIds = [...new Set([campaignId, ...legacyIds].filter(Boolean))];
  if (distinctIds.length > 1) {
    throw new HttpsError(
      "invalid-argument",
      "Provide exactly one campaign identity. Use campaignId as the canonical field.",
    );
  }

  const resolvedCampaignId = distinctIds[0] ?? "";
  if (params.requireCampaignId && !resolvedCampaignId) {
    throw new HttpsError("invalid-argument", "campaignId is required.");
  }

  const payload: Record<string, unknown> = {...data};
  delete payload.campaignId;
  for (const key of legacyOfferMutationIdentityAliases) {
    delete payload[key];
  }

  const ignoredLegacyFields: string[] = [];
  for (const key of ignoredLegacyOfferMutationFields) {
    if (Object.prototype.hasOwnProperty.call(payload, key)) {
      ignoredLegacyFields.push(key);
      delete payload[key];
    }
  }

  const invalidKeys = Object.keys(payload).filter(
    (key) => !offerCampaignMutationFields.includes(
      key as typeof offerCampaignMutationFields[number],
    ),
  );
  if (invalidKeys.length > 0) {
    throwUnsupportedOfferFields(invalidKeys);
  }

  return {
    campaignId: resolvedCampaignId,
    payload,
    ignoredLegacyFields,
    usedLegacyIdentityAlias: !campaignId && legacyIds.length > 0,
  };
}
