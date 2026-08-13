import * as crypto from "node:crypto";

import {FieldValue} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {db} from "../../shared/firebase";
import {isPersistedCompletedAccount} from "../../identity/onboardingProfileUtils";
import {
  matchesOfferWallAudience,
} from "../domain/offerWallAudience";
import {normalizeOfferWallCampaignInput} from "../domain/offerWallCampaign";
import {
  shouldDisplayOfferWallAfterCount,
  sortOfferWallCampaignsForEvaluation,
} from "../domain/offerWallEligibility";
import {normalizeOfferWallUserState} from "../domain/offerWallUserState";

type OfferWallEvaluationPayload = {
  campaignId: string;
  name: string;
  creativeStoragePath: string;
  displayToken: string;
  sessionId: string;
};

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function logDiag(event: string, values: Record<string, unknown>): void {
  const parts = Object.entries(values).map(([key, value]) => {
    if (Array.isArray(value)) {
      return `${key}=[${value.join(",")}]`;
    }
    return `${key}=${value ?? ""}`;
  });
  console.info(`[OfferWallDiag] ${event} ${parts.join(" ")}`.trim());
}

function assertValidSessionId(sessionId: string): void {
  if (sessionId.length < 8 || sessionId.length > 160) {
    throw new HttpsError("invalid-argument", "sessionId is invalid.");
  }
}

function isAccountAvailable(userData: Record<string, unknown>): boolean {
  const status = asTrimmedString(userData.accountStatus);
  return !status || (status !== "pendingDeletion" && status !== "deletionInProgress");
}

function stateRef(uid: string, campaignId: string) {
  return db
    .collection("userPrivate")
    .doc(uid)
    .collection("offerWallState")
    .doc(campaignId);
}

function sessionRef(uid: string, sessionId: string) {
  return db
    .collection("userPrivate")
    .doc(uid)
    .collection("offerWallLaunchSessions")
    .doc(sessionId);
}

export async function evaluateOfferWallForLaunch(params: {
  uid: string;
  sessionId: string;
}): Promise<OfferWallEvaluationPayload | null> {
  const uid = asTrimmedString(params.uid);
  const sessionId = asTrimmedString(params.sessionId);
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to continue.");
  }
  assertValidSessionId(sessionId);

  const [userSnapshot, privateSnapshot] = await Promise.all([
    db.collection("users").doc(uid).get(),
    db.collection("userPrivate").doc(uid).get(),
  ]);
  const userData = userSnapshot.data() ?? {};
  const profileComplete = isPersistedCompletedAccount({uid, publicUser: userData});
  logDiag("user-context", {
    uid,
    profileExists: userSnapshot.exists,
    privateProfileExists: privateSnapshot.exists,
    profileComplete,
    canonicalRole: asTrimmedString(userData.role),
  });
  if (!userSnapshot.exists || !isAccountAvailable(userData)) {
    logDiag("evaluate-exit", {
      reason: userSnapshot.exists ? "account-unavailable" : "profile-missing",
    });
    return null;
  }
  if (!profileComplete) {
    logDiag("evaluate-exit", {reason: "profile-incomplete"});
    return null;
  }

  const userRole = asTrimmedString(userData.role);
  const campaignSnapshots = await db
    .collection("offerWallCampaigns")
    .where("status", "==", "active")
    .get();
  logDiag("active-campaign-query", {count: campaignSnapshots.docs.length});
  if (campaignSnapshots.docs.length === 0) {
    logDiag("evaluate-exit", {reason: "no-active-campaign"});
    return null;
  }

  const parsedCampaigns = [];
  for (const doc of campaignSnapshots.docs) {
    try {
      const campaign = normalizeOfferWallCampaignInput({
        id: doc.id,
        data: doc.data() ?? {},
      });
      logDiag("campaign-loaded", {
        campaignId: campaign.id,
        name: campaign.name,
        status: campaign.status,
        audiences: campaign.audiences,
        openInterval: campaign.openInterval,
        repetitionLimit: campaign.repetitionLimit,
        creativeStoragePathPresent: campaign.creativeStoragePath.length > 0,
      });
      parsedCampaigns.push(campaign);
    } catch (error) {
      logDiag("campaign-parse-failed", {
        campaignId: doc.id,
        errorType: error instanceof Error ? error.name : typeof error,
        safeMessage: error instanceof Error ? error.message.trim() : "unknown",
      });
    }
  }

  const matchingCampaigns = sortOfferWallCampaignsForEvaluation(
    parsedCampaigns.filter((campaign) => {
      const matched = matchesOfferWallAudience({
        audiences: campaign.audiences,
        role: userRole,
      });
      logDiag("audience-check", {
        campaignId: campaign.id,
        canonicalRole: userRole,
        campaignAudiences: campaign.audiences,
        matched,
      });
      if (!matched) {
        logDiag("campaign-rejected", {
          campaignId: campaign.id,
          reason: "audience-mismatch",
        });
      }
      return matched;
    }),
  );

  if (matchingCampaigns.length === 0) {
    logDiag("evaluate-return", {
      hasCampaign: false,
      reason: "no-eligible-campaign",
    });
    return null;
  }

  const launchSessionRef = sessionRef(uid, sessionId);

  return db.runTransaction(async (transaction) => {
    const sessionSnapshot = await transaction.get(launchSessionRef);
    logDiag("session-check", {
      sessionId,
      alreadyProcessed: sessionSnapshot.exists,
    });
    if (sessionSnapshot.exists) {
      const sessionData = sessionSnapshot.data() ?? {};
      const selectedCampaignId = asTrimmedString(sessionData.selectedCampaignId);
      const selectedToken = asTrimmedString(sessionData.displayToken);
      if (
        selectedCampaignId &&
        selectedToken &&
        sessionData.acknowledged !== true
      ) {
        const selectedCampaign = matchingCampaigns.find(
          (campaign) => campaign.id === selectedCampaignId,
        );
        if (selectedCampaign) {
          logDiag("campaign-selected", {
            campaignId: selectedCampaign.id,
            selectionPolicy: "existing-session-pending-selectedCampaignId",
          });
          logDiag("evaluate-return", {
            hasCampaign: true,
            campaignId: selectedCampaign.id,
            creativeStoragePathPresent:
              selectedCampaign.creativeStoragePath.length > 0,
            openInterval: selectedCampaign.openInterval,
            repetitionLimit: selectedCampaign.repetitionLimit,
          });
          return {
            campaignId: selectedCampaign.id,
            name: selectedCampaign.name,
            creativeStoragePath: selectedCampaign.creativeStoragePath,
            displayToken: selectedToken,
            sessionId,
          };
        }
      }
      logDiag("evaluate-exit", {reason: "already-processed-session"});
      logDiag("evaluate-return", {
        hasCampaign: false,
        reason: "already-processed-session",
      });
      return null;
    }

    let selectedPayload: OfferWallEvaluationPayload | null = null;
    let selectedReason = "no-threshold-match";

    for (const campaign of matchingCampaigns) {
      logDiag("eligible-campaign", {
        campaignId: campaign.id,
        createdAt: campaign.createdAt?.toISOString() ?? "",
      });
      const campaignStateRef = stateRef(uid, campaign.id);
      const campaignStateSnapshot = await transaction.get(campaignStateRef);
      const currentState = normalizeOfferWallUserState({
        uid,
        campaignId: campaign.id,
        data: campaignStateSnapshot.data(),
      });
      logDiag("user-campaign-state-before", {
        campaignId: campaign.id,
        stateExists: campaignStateSnapshot.exists,
        eligibleOpenCount: currentState.eligibleOpenCount,
        impressionsShown: currentState.impressionsShown,
        repetitionLimit: campaign.repetitionLimit,
        lastCountedSessionIdPresent:
          currentState.lastCountedSessionId.length > 0,
      });

      if (currentState.impressionsShown >= campaign.repetitionLimit) {
        logDiag("campaign-rejected", {
          campaignId: campaign.id,
          reason: "repetition-complete",
        });
        continue;
      }

      const countedThisSession =
        currentState.lastCountedSessionId === sessionId;
      logDiag("cadence-before", {
        campaignId: campaign.id,
        eligibleOpenCount: currentState.eligibleOpenCount,
        impressionsShown: currentState.impressionsShown,
        openInterval: campaign.openInterval,
        nextThreshold:
          (currentState.impressionsShown + 1) * campaign.openInterval,
      });
      const nextEligibleOpenCount = countedThisSession ?
        currentState.eligibleOpenCount :
        currentState.eligibleOpenCount + 1;
      const nextState = {
        campaignId: campaign.id,
        uid,
        eligibleOpenCount: nextEligibleOpenCount,
        impressionsShown: currentState.impressionsShown,
        lastCountedSessionId: sessionId,
        pendingDisplayToken: currentState.pendingDisplayToken,
        pendingSessionId: currentState.pendingSessionId,
      };

      const dueForDisplay = shouldDisplayOfferWallAfterCount({
        campaign,
        state: nextState,
      });
      logDiag("cadence-after", {
        campaignId: campaign.id,
        eligibleOpenCount: nextEligibleOpenCount,
        thresholdReached: dueForDisplay,
      });
      logDiag("creative-check", {
        campaignId: campaign.id,
        creativeStoragePathPresent: campaign.creativeStoragePath.length > 0,
      });
      if (!campaign.creativeStoragePath) {
        logDiag("campaign-rejected", {
          campaignId: campaign.id,
          reason: "creative-missing",
        });
        selectedReason = "creative-missing";
        continue;
      }

      if (!selectedPayload && dueForDisplay) {
        const displayToken =
          currentState.pendingDisplayToken ||
          crypto.randomUUID().replace(/-/g, "");
        selectedPayload = {
          campaignId: campaign.id,
          name: campaign.name,
          creativeStoragePath: campaign.creativeStoragePath,
          displayToken,
          sessionId,
        };
        selectedReason = "selected";
        logDiag("campaign-selected", {
          campaignId: campaign.id,
          selectionPolicy: "oldest-createdAt-then-id",
        });
        transaction.set(campaignStateRef, {
          campaignId: campaign.id,
          uid,
          eligibleOpenCount: nextEligibleOpenCount,
          impressionsShown: currentState.impressionsShown,
          lastCountedSessionId: sessionId,
          pendingDisplayToken: displayToken,
          pendingSessionId: sessionId,
          pendingIssuedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          ...(campaignStateSnapshot.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
        }, {merge: true});
        continue;
      }

      if (!countedThisSession) {
        transaction.set(campaignStateRef, {
          campaignId: campaign.id,
          uid,
          eligibleOpenCount: nextEligibleOpenCount,
          lastCountedSessionId: sessionId,
          updatedAt: FieldValue.serverTimestamp(),
          ...(campaignStateSnapshot.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
        }, {merge: true});
      }
    }

    transaction.set(launchSessionRef, {
      sessionId,
      selectedCampaignId: selectedPayload?.campaignId ?? "",
      displayToken: selectedPayload?.displayToken ?? "",
      acknowledged: false,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    logDiag("evaluate-return", {
      hasCampaign: selectedPayload != null,
      campaignId: selectedPayload?.campaignId ?? "",
      creativeStoragePathPresent:
        (selectedPayload?.creativeStoragePath ?? "").length > 0,
      reason: selectedPayload == null ? selectedReason : "",
    });
    return selectedPayload;
  });
}

export async function acknowledgeOfferWallImpression(params: {
  uid: string;
  campaignId: string;
  sessionId: string;
  displayToken: string;
}): Promise<{counted: boolean}> {
  const uid = asTrimmedString(params.uid);
  const campaignId = asTrimmedString(params.campaignId);
  const sessionId = asTrimmedString(params.sessionId);
  const displayToken = asTrimmedString(params.displayToken);
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to continue.");
  }
  if (!campaignId || !displayToken) {
    throw new HttpsError(
      "invalid-argument",
      "campaignId and displayToken are required.",
    );
  }
  assertValidSessionId(sessionId);
  logDiag("acknowledge-start", {campaignId, sessionId});

  return db.runTransaction(async (transaction) => {
    const [campaignSnapshot, stateSnapshot, launchSessionSnapshot] = await Promise.all([
      transaction.get(db.collection("offerWallCampaigns").doc(campaignId)),
      transaction.get(stateRef(uid, campaignId)),
      transaction.get(sessionRef(uid, sessionId)),
    ]);

    if (!campaignSnapshot.exists || !launchSessionSnapshot.exists) {
      logDiag("acknowledge-failed", {
        campaignId,
        code: "missing-campaign-or-session",
      });
      return {counted: false};
    }

    const campaign = normalizeOfferWallCampaignInput({
      id: campaignSnapshot.id,
      data: campaignSnapshot.data() ?? {},
    });
    const state = normalizeOfferWallUserState({
      uid,
      campaignId,
      data: stateSnapshot.data(),
    });
    const launchSession = launchSessionSnapshot.data() ?? {};

    if (launchSession.acknowledged === true) {
      logDiag("acknowledge-failed", {
        campaignId,
        code: "already-acknowledged",
      });
      return {counted: false};
    }
    if (
      asTrimmedString(launchSession.selectedCampaignId) !== campaignId ||
      asTrimmedString(launchSession.displayToken) != displayToken
    ) {
      logDiag("acknowledge-failed", {
        campaignId,
        code: "session-payload-mismatch",
      });
      return {counted: false};
    }
    if (state.pendingDisplayToken !== displayToken) {
      logDiag("acknowledge-failed", {
        campaignId,
        code: "pending-token-mismatch",
      });
      return {counted: false};
    }
    if (state.impressionsShown >= campaign.repetitionLimit) {
      transaction.set(launchSessionSnapshot.ref, {
        acknowledged: true,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      logDiag("acknowledge-failed", {
        campaignId,
        code: "repetition-complete",
      });
      return {counted: false};
    }

    const nextImpressionsShown = state.impressionsShown + 1;
    transaction.set(stateSnapshot.ref, {
      campaignId,
      uid,
      impressionsShown: nextImpressionsShown,
      lastShownAt: FieldValue.serverTimestamp(),
      pendingDisplayToken: "",
      pendingSessionId: "",
      pendingIssuedAt: null,
      updatedAt: FieldValue.serverTimestamp(),
      ...(nextImpressionsShown >= campaign.repetitionLimit ?
        {completedAt: FieldValue.serverTimestamp()} :
        {}),
    }, {merge: true});
    transaction.set(launchSessionSnapshot.ref, {
      acknowledged: true,
      acknowledgedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    logDiag("acknowledge-success", {campaignId});
    return {counted: true};
  });
}
