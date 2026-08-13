import {
  matchesOfferAudience,
  type CanonicalOfferUserRole,
} from "./offerAudience";
import {type OfferCampaignRecord} from "./offerCampaign";

export type OfferUserEligibilityContext = {
  uid: string;
  role: CanonicalOfferUserRole | "";
  completedBookingCount: number;
};

export type OfferBookingEligibilityContext = {
  bookingAmount?: number | null;
  serviceId?: string | null;
  providerId?: string | null;
  serviceCategory?: string | null;
};

export type OfferEligibilityResult =
  | {ok: true}
  | {ok: false; reason: string};

function failure(reason: string): OfferEligibilityResult {
  return {ok: false, reason};
}

export function evaluateUserLevelOfferEligibility(params: {
  campaign: OfferCampaignRecord;
  user: OfferUserEligibilityContext;
  now?: Date;
}): OfferEligibilityResult {
  const now = params.now ?? new Date();
  const {campaign, user} = params;

  if (campaign.isDeleted) {
    return failure("deleted");
  }
  if (!campaign.isActive) {
    return failure("inactive");
  }
  if (campaign.startAt == null) {
    return failure("missing-start-at");
  }
  if (campaign.startAt.getTime() > now.getTime()) {
    return failure("future");
  }
  if (campaign.endAt != null && campaign.endAt.getTime() < now.getTime()) {
    return failure("expired");
  }
  if (!matchesOfferAudience(campaign.audience, user.role)) {
    return failure("audience-mismatch");
  }
  if (campaign.targeting.firstBookingOnly && user.completedBookingCount > 0) {
    return failure("first-booking-only");
  }
  if (campaign.targeting.rebookingOnly && user.completedBookingCount <= 0) {
    return failure("rebooking-only");
  }
  return {ok: true};
}

export function evaluateBookingContextOfferEligibility(params: {
  campaign: OfferCampaignRecord;
  bookingContext?: OfferBookingEligibilityContext | null;
}): OfferEligibilityResult {
  const bookingContext = params.bookingContext;
  if (bookingContext == null) {
    return {ok: true};
  }

  const bookingAmount = bookingContext.bookingAmount ?? null;
  if (
    bookingAmount != null &&
    Number.isFinite(bookingAmount) &&
    params.campaign.minBookingAmount != null &&
    bookingAmount < params.campaign.minBookingAmount
  ) {
    return failure("min-booking-amount");
  }

  const serviceId = bookingContext.serviceId?.trim() ?? "";
  if (
    params.campaign.serviceIds.length > 0 &&
    (!serviceId || !params.campaign.serviceIds.includes(serviceId))
  ) {
    return failure("service-restriction");
  }

  const providerId = bookingContext.providerId?.trim() ?? "";
  if (
    params.campaign.providerIds.length > 0 &&
    (!providerId || !params.campaign.providerIds.includes(providerId))
  ) {
    return failure("provider-restriction");
  }

  const serviceCategory = bookingContext.serviceCategory?.trim() ?? "";
  if (
    params.campaign.categoryRestrictions.length > 0 &&
    (!serviceCategory ||
      !params.campaign.categoryRestrictions.includes(serviceCategory))
  ) {
    return failure("category-restriction");
  }

  return {ok: true};
}

export function evaluateOfferAvailability(params: {
  campaign: OfferCampaignRecord;
  user: OfferUserEligibilityContext;
  now?: Date;
  bookingContext?: OfferBookingEligibilityContext | null;
}): OfferEligibilityResult {
  const userLevelResult = evaluateUserLevelOfferEligibility({
    campaign: params.campaign,
    user: params.user,
    now: params.now,
  });
  if (!userLevelResult.ok) return userLevelResult;
  return evaluateBookingContextOfferEligibility({
    campaign: params.campaign,
    bookingContext: params.bookingContext,
  });
}
