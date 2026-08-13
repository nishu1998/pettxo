import {type CanonicalBookingDocumentV3} from "../../booking/schema/bookingDocumentV3";
import {
  loadOfferCampaignDoc,
  loadOfferUsageRecord,
  loadOfferUserProfile,
} from "../data/offerRepository";
import {parseOfferCampaignRecord} from "../domain/offerCampaign";
import {evaluateOfferAvailability} from "../domain/offerEligibility";
import {isOfferUsageAvailable} from "../domain/offerUsagePolicy";

function asCategory(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export type ValidatedOfferCampaignSelection = {
  offerCampaignId: string;
  couponCode: string;
  discountType: string;
  discountValue: number;
  maxDiscountAmount: number | null;
  minBookingAmount: number | null;
  campaignType: string;
  usageLimitPerUser: number;
  usedCount: number;
  validUntil: Date | null;
  serviceIds: string[];
  providerIds: string[];
  categoryRestrictions: string[];
  title: string;
  description: string;
};

export type ValidateOfferCampaignForBookingResult =
  | {ok: true; selection: ValidatedOfferCampaignSelection}
  | {ok: false; code: string; message: string};

export async function validateOfferCampaignForBooking(params: {
  uid: string;
  offerCampaignId: string;
  booking: CanonicalBookingDocumentV3;
  serviceSubtotalAmount: number;
  now?: Date;
}): Promise<ValidateOfferCampaignForBookingResult> {
  const offerCampaignId = params.offerCampaignId.trim();
  if (!offerCampaignId) {
    return {
      ok: false,
      code: "COUPON_INVALID",
      message: "Coupon is no longer available.",
    };
  }

  const now = params.now ?? new Date();
  const [user, campaignDoc, usage] = await Promise.all([
    loadOfferUserProfile(params.uid),
    loadOfferCampaignDoc(offerCampaignId),
    loadOfferUsageRecord(params.uid, offerCampaignId),
  ]);

  if (campaignDoc == null) {
    return {
      ok: false,
      code: "COUPON_INVALID",
      message: "Coupon is no longer available.",
    };
  }

  let campaign;
  try {
    campaign = parseOfferCampaignRecord(campaignDoc.id, campaignDoc.data());
  } catch {
    return {
      ok: false,
      code: "COUPON_INVALID",
      message: "Coupon configuration is invalid.",
    };
  }

  const eligibility = evaluateOfferAvailability({
    campaign,
    user,
    now,
    bookingContext: {
      bookingAmount: params.serviceSubtotalAmount,
      serviceId: params.booking.serviceId,
      providerId: params.booking.providerId,
      serviceCategory: asCategory(params.booking.service.category),
    },
  });
  if (!eligibility.ok) {
    return {
      ok: false,
      code: "COUPON_INVALID",
      message: "Coupon is no longer available.",
    };
  }

  if (!isOfferUsageAvailable({
    usedCount: usage.usedCount,
    usageLimitPerUser: campaign.usageLimitPerUser,
  })) {
    return {
      ok: false,
      code: "COUPON_INVALID",
      message: "Coupon has already been fully used.",
    };
  }

  return {
    ok: true,
    selection: {
      offerCampaignId,
      couponCode: campaign.couponCode,
      discountType: campaign.discountType,
      discountValue: campaign.discountValue,
      maxDiscountAmount: campaign.maxDiscountAmount,
      minBookingAmount: campaign.minBookingAmount,
      campaignType: campaign.campaignType,
      usageLimitPerUser: campaign.usageLimitPerUser,
      usedCount: usage.usedCount,
      validUntil: campaign.endAt,
      serviceIds: campaign.serviceIds,
      providerIds: campaign.providerIds,
      categoryRestrictions: campaign.categoryRestrictions,
      title: campaign.title,
      description: campaign.description,
    },
  };
}
