import type {OfferWallCampaign} from "./offerWallCampaign";
import type {OfferWallUserState} from "./offerWallUserState";

export function isOfferWallCampaignCompleted(params: {
  campaign: Pick<OfferWallCampaign, "repetitionLimit">;
  state: Pick<OfferWallUserState, "impressionsShown">;
}): boolean {
  return params.state.impressionsShown >= params.campaign.repetitionLimit;
}

export function shouldDisplayOfferWallAfterCount(params: {
  campaign: Pick<OfferWallCampaign, "openInterval" | "repetitionLimit">;
  state: Pick<OfferWallUserState, "eligibleOpenCount" | "impressionsShown">;
}): boolean {
  if (isOfferWallCampaignCompleted(params)) {
    return false;
  }
  const targetOpenCount =
    (params.state.impressionsShown + 1) * params.campaign.openInterval;
  return params.state.eligibleOpenCount >= targetOpenCount;
}

export function sortOfferWallCampaignsForEvaluation<
  T extends Pick<OfferWallCampaign, "id" | "createdAt">
>(campaigns: T[]): T[] {
  return [...campaigns].sort((left, right) => {
    const leftTime = left.createdAt?.getTime() ?? 0;
    const rightTime = right.createdAt?.getTime() ?? 0;
    if (leftTime != rightTime) {
      return leftTime - rightTime;
    }
    return left.id.localeCompare(right.id);
  });
}
