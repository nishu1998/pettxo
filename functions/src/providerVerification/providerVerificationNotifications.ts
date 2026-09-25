import {createHash} from "crypto";

export type ProviderVerificationDecision = "approved" | "rejected";

export type ProviderVerificationDecisionNotification = {
  documentId: string;
  document: {
    userId: string;
    category: "account";
    type: "providerVerificationApproved" | "providerVerificationRejected";
    title: string;
    body: string;
    read: false;
    isRead: false;
    data: {
      category: "account";
      type: "providerVerificationApproved" | "providerVerificationRejected";
      navigationIntent: "provider_verification";
    };
    channels: ["in_app", "push"];
    visibleInApp: true;
    source: "provider_verification_review";
  };
};

export function buildProviderVerificationDecisionNotification(params: {
  beforeStatus: string;
  afterStatus: string;
  providerUserId: string;
  submissionId: string;
}): ProviderVerificationDecisionNotification | null {
  const providerUserId = params.providerUserId.trim();
  const submissionId = params.submissionId.trim();
  if (params.beforeStatus !== "pending" || !providerUserId || !submissionId) {
    return null;
  }

  const decision: ProviderVerificationDecision | null =
    params.afterStatus === "approved" ?
      "approved" :
      params.afterStatus === "rejected" ?
        "rejected" :
        null;
  if (!decision) return null;

  const approved = decision === "approved";
  const type = approved ?
    "providerVerificationApproved" as const :
    "providerVerificationRejected" as const;
  const digest = createHash("sha256")
    .update(`${decision}:${providerUserId}:${submissionId}`)
    .digest("hex")
    .slice(0, 32);

  return {
    documentId: `provider_verification_${decision}_${digest}`,
    document: {
      userId: providerUserId,
      category: "account",
      type,
      title: approved ? "Verification approved" : "Verification needs attention",
      body: approved ?
        "You can now offer services as a verified provider." :
        "Review the details and resubmit your verification.",
      read: false,
      isRead: false,
      data: {
        category: "account",
        type,
        navigationIntent: "provider_verification",
      },
      channels: ["in_app", "push"],
      visibleInApp: true,
      source: "provider_verification_review",
    },
  };
}
