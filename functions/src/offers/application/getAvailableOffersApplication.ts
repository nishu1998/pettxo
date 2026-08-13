import {
  evaluateOfferAvailability,
  type OfferBookingEligibilityContext,
} from "../domain/offerEligibility";
import {
  parseOfferCampaignRecord,
  toAvailableOfferResponse,
} from "../domain/offerCampaign";
import {
  listOfferUsageRecords,
  listActiveOfferCampaignDocs,
  loadOfferUserProfile,
} from "../data/offerRepository";
import {isOfferUsageAvailable} from "../domain/offerUsagePolicy";

type AvailableOfferResponse = Record<string, unknown>;

export type GetAvailableOffersResult = {
  ok: true;
  offerWall: AvailableOfferResponse | null;
  popup: AvailableOfferResponse | null;
  offers: AvailableOfferResponse[];
};

export function buildAvailableOffersResult(params: {
  user: {
    uid: string;
    role: "" | "petParent" | "petLover" | "serviceProvider";
    completedBookingCount: number;
  };
  campaigns: Array<{
    id: string;
    data: Record<string, unknown>;
    createdAt: Date | null;
  }>;
  usageByCampaignId?: ReadonlyMap<string, {usedCount: number}>;
  now?: Date;
  bookingContext?: OfferBookingEligibilityContext | null;
}): GetAvailableOffersResult {
  const now = params.now ?? new Date();
  const usageByCampaignId = params.usageByCampaignId ?? new Map();
  const offersWithMeta = params.campaigns.map((campaignDoc) => {
    let campaign;
    try {
      campaign = parseOfferCampaignRecord(campaignDoc.id, campaignDoc.data);
    } catch {
      return null;
    }
    const eligibility = evaluateOfferAvailability({
      campaign,
      user: params.user,
      now,
      bookingContext: params.bookingContext,
    });
    if (!eligibility.ok) return null;
    const usage = usageByCampaignId.get(campaign.id);
    if (!isOfferUsageAvailable({
      usedCount: usage?.usedCount ?? 0,
      usageLimitPerUser: campaign.usageLimitPerUser,
    })) {
      return null;
    }
    return {
      createdAt: campaignDoc.createdAt,
      offer: toAvailableOfferResponse(campaign),
    };
  });

  const offers = offersWithMeta
    .filter((entry): entry is NonNullable<typeof entry> => entry != null)
    .sort((left, right) => {
      const rightPriority =
        typeof right.offer.priority === "number" ? right.offer.priority : 0;
      const leftPriority =
        typeof left.offer.priority === "number" ? left.offer.priority : 0;
      if (rightPriority !== leftPriority) {
        return rightPriority - leftPriority;
      }
      const rightCreatedAt = right.createdAt?.getTime() ?? 0;
      const leftCreatedAt = left.createdAt?.getTime() ?? 0;
      return rightCreatedAt - leftCreatedAt;
    })
    .map((entry) => entry.offer);

  return {
    ok: true,
    offerWall:
      offers.find((offer) => offer.displayType === "offerWall") ?? null,
    popup: offers.find((offer) => offer.displayType === "popup") ?? null,
    offers,
  };
}

export async function getAvailableOffersForUser(params: {
  uid: string;
  now?: Date;
  bookingContext?: OfferBookingEligibilityContext | null;
}): Promise<GetAvailableOffersResult> {
  const [user, campaignDocs, usageRecords] = await Promise.all([
    loadOfferUserProfile(params.uid),
    listActiveOfferCampaignDocs(),
    listOfferUsageRecords(params.uid),
  ]);

  return buildAvailableOffersResult({
    user,
    campaigns: campaignDocs.map((doc) => ({
      id: doc.id,
      data: doc.data(),
      createdAt:
        typeof doc.data().createdAt?.toDate === "function" ?
          doc.data().createdAt.toDate() as Date :
          null,
    })),
    usageByCampaignId: new Map(
      usageRecords.map((record) => [
        record.offerCampaignId,
        {usedCount: record.usedCount},
      ]),
    ),
    now: params.now,
    bookingContext: params.bookingContext,
  });
}
