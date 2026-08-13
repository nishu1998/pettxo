import {HttpsError, onCall} from "firebase-functions/v2/https";

import {
  createOfferWallCampaignDocument,
  listOfferWallCampaignDocuments,
  requireOfferWallAdminActor,
  setOfferWallCampaignStatusDocument,
  updateOfferWallCampaignDocument,
} from "./application/offerWallAdminApplication";
import {sanitizeOfferWallMutationInput} from "./application/offerWallAdminContract";
import {
  acknowledgeOfferWallImpression,
  evaluateOfferWallForLaunch,
} from "./application/evaluateOfferWallForLaunch";

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function requireUid(uid: string): string {
  if (uid) return uid;
  throw new HttpsError("unauthenticated", "Sign in to continue.");
}

export const createOfferWallCampaign = onCall(
  {invoker: "public"},
  async (request) => {
    const actor = await requireOfferWallAdminActor(
      requireUid(request.auth?.uid ?? ""),
    );
    const {payload} = sanitizeOfferWallMutationInput({
      rawData: request.data,
      requireCampaignId: false,
    });
    const result = await createOfferWallCampaignDocument({payload, actor});
    return {ok: true, ...result};
  },
);

export const updateOfferWallCampaign = onCall(
  {invoker: "public"},
  async (request) => {
    const actor = await requireOfferWallAdminActor(
      requireUid(request.auth?.uid ?? ""),
    );
    const {campaignId, payload} = sanitizeOfferWallMutationInput({
      rawData: request.data,
      requireCampaignId: true,
    });
    await updateOfferWallCampaignDocument({campaignId, payload, actor});
    return {ok: true};
  },
);

export const setOfferWallCampaignStatus = onCall(
  {invoker: "public"},
  async (request) => {
    const actor = await requireOfferWallAdminActor(
      requireUid(request.auth?.uid ?? ""),
    );
    const campaignId = asTrimmedString(request.data?.campaignId);
    if (!campaignId) {
      throw new HttpsError("invalid-argument", "campaignId is required.");
    }
    await setOfferWallCampaignStatusDocument({
      campaignId,
      status: request.data?.status,
      actor,
    });
    return {ok: true};
  },
);

export const listOfferWallCampaigns = onCall(
  {invoker: "public"},
  async (request) => {
    await requireOfferWallAdminActor(requireUid(request.auth?.uid ?? ""));
    return {
      ok: true,
      campaigns: await listOfferWallCampaignDocuments(),
    };
  },
);

export const evaluateOfferWallLaunch = onCall(
  {invoker: "public"},
  async (request) => {
    const uid = requireUid(request.auth?.uid ?? "");
    const sessionId = asTrimmedString(request.data?.sessionId);
    console.info(
      `[OfferWallDiag] evaluate-entry uid=${uid} sessionId=${sessionId || "<missing>"} authPresent=true`,
    );
    if (!sessionId) {
      console.info(
        "[OfferWallDiag] evaluate-exit reason=invalid-session-id",
      );
    }
    const campaign = await evaluateOfferWallForLaunch({uid, sessionId});
    return {
      ok: true,
      campaign,
    };
  },
);

export const acknowledgeOfferWallDisplay = onCall(
  {invoker: "public"},
  async (request) => {
    const uid = requireUid(request.auth?.uid ?? "");
    return {
      ok: true,
      ...await acknowledgeOfferWallImpression({
        uid,
        campaignId: asTrimmedString(request.data?.campaignId),
        sessionId: asTrimmedString(request.data?.sessionId),
        displayToken: asTrimmedString(request.data?.displayToken),
      }),
    };
  },
);
