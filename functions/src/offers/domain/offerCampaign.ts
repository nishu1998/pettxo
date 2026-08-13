import {Timestamp} from "firebase-admin/firestore";

import {
  asTrimmedString,
  normalizeOfferAudienceInput,
  type OfferAudience,
} from "./offerAudience";

export type OfferCampaignTargeting = {
  firstBookingOnly: boolean;
  rebookingOnly: boolean;
};

export type OfferCampaignRecord = {
  id: string;
  title: string;
  description: string;
  couponCode: string;
  displayType: string;
  isDeleted: boolean;
  campaignType: string;
  discountType: string;
  discountValue: number;
  maxDiscountAmount: number | null;
  minBookingAmount: number | null;
  isActive: boolean;
  startAt: Date | null;
  endAt: Date | null;
  usageLimitPerUser: number;
  targeting: OfferCampaignTargeting;
  priority: number;
  audience: OfferAudience;
  serviceIds: string[];
  providerIds: string[];
  categoryRestrictions: string[];
};

function asFiniteNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function asInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) ? value : null;
}

function asDate(value: unknown): Date | null {
  if (value instanceof Date) return value;
  if (value instanceof Timestamp) return value.toDate();
  if (typeof value === "string" && value.trim()) {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const normalized: string[] = [];
  for (const entry of value) {
    const trimmed = asTrimmedString(entry);
    if (!trimmed || normalized.includes(trimmed)) continue;
    normalized.push(trimmed);
  }
  normalized.sort();
  return normalized;
}

export function parseOfferCampaignRecord(
  id: string,
  rawValue: unknown,
): OfferCampaignRecord {
  const data =
    rawValue && typeof rawValue === "object" && !Array.isArray(rawValue) ?
      rawValue as Record<string, unknown> :
      {};

  return {
    id: id.trim(),
    title: asTrimmedString(data.title),
    description: asTrimmedString(data.description),
    couponCode: asTrimmedString(data.couponCode),
    displayType: asTrimmedString(data.displayType) || "offerWall",
    isDeleted: data.isDeleted === true,
    campaignType: asTrimmedString(data.campaignType),
    discountType: asTrimmedString(data.discountType),
    discountValue: asFiniteNumber(data.discountValue) ?? 0,
    maxDiscountAmount: asFiniteNumber(data.maxDiscountAmount),
    minBookingAmount: asFiniteNumber(data.minBookingAmount),
    isActive: data.isActive === true,
    startAt: asDate(data.startAt),
    endAt: asDate(data.endAt),
    usageLimitPerUser: asInteger(data.usageLimitPerUser) ?? 1,
    targeting: {
      firstBookingOnly:
        !!(data.targeting &&
          typeof data.targeting === "object" &&
          !Array.isArray(data.targeting) &&
          (data.targeting as Record<string, unknown>).firstBookingOnly === true),
      rebookingOnly:
        !!(data.targeting &&
          typeof data.targeting === "object" &&
          !Array.isArray(data.targeting) &&
          (data.targeting as Record<string, unknown>).rebookingOnly === true),
    },
    priority: asInteger(data.priority) ?? 0,
    audience: normalizeOfferAudienceInput(data.audience, {
      allowLegacyMissing: true,
    }),
    serviceIds: asStringArray(data.serviceIds),
    providerIds: asStringArray(data.providerIds),
    categoryRestrictions: asStringArray(data.categoryRestrictions),
  };
}

export function toAvailableOfferResponse(
  campaign: OfferCampaignRecord,
): Record<string, unknown> {
  return {
    id: campaign.id,
    title: campaign.title,
    description: campaign.description,
    couponCode: campaign.couponCode,
    displayType: campaign.displayType,
    campaignType: campaign.campaignType,
    discountType: campaign.discountType,
    discountValue: campaign.discountValue,
    maxDiscountAmount: campaign.maxDiscountAmount,
    minBookingAmount: campaign.minBookingAmount,
    usageLimitPerUser: campaign.usageLimitPerUser,
    priority: campaign.priority,
    startAt: campaign.startAt?.toISOString() ?? null,
    endAt: campaign.endAt?.toISOString() ?? null,
  };
}
