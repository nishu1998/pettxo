export const ACCOUNT_DELETION_GRACE_PERIOD_MS = 30 * 24 * 60 * 60 * 1000;

export type RecoverableAccountStatus =
  | "active"
  | "pendingDeletion"
  | "deletionInProgress";

export type RestoreEligibility =
  | {allowed: true}
  | {allowed: false; reason: "not-pending-deletion" | "deletion-in-progress" | "expired-or-missing-schedule"};

export type SchedulerClaimDecision =
  | {shouldClaim: true; nextStatus: "deletionInProgress"}
  | {shouldClaim: false; reason: "not-pending-deletion" | "not-due" | "malformed-schedule"};

export type DeletionJobStage =
  | "scheduled"
  | "claimed"
  | "sessionsRevoked"
  | "firestoreCleanup"
  | "retainedDataAnonymized"
  | "storageCleanup"
  | "authUserDeleted"
  | "usernameReleased"
  | "identityDocumentsDeleted"
  | "completed";

export const deletionJobStageOrder: readonly DeletionJobStage[] = [
  "scheduled",
  "claimed",
  "sessionsRevoked",
  "firestoreCleanup",
  "retainedDataAnonymized",
  "storageCleanup",
  "authUserDeleted",
  "usernameReleased",
  "identityDocumentsDeleted",
  "completed",
] as const;

export function calculateScheduledDeletionAtMillis(nowMs: number): number {
  return nowMs + ACCOUNT_DELETION_GRACE_PERIOD_MS;
}

export function evaluateRestoreEligibility(params: {
  accountStatus: string;
  scheduledDeletionAtMs: number | null;
  nowMs: number;
}): RestoreEligibility {
  if (params.accountStatus === "deletionInProgress") {
    return {allowed: false, reason: "deletion-in-progress"};
  }
  if (params.accountStatus !== "pendingDeletion") {
    return {allowed: false, reason: "not-pending-deletion"};
  }
  if (
    params.scheduledDeletionAtMs == null ||
    !Number.isFinite(params.scheduledDeletionAtMs) ||
    params.scheduledDeletionAtMs <= params.nowMs
  ) {
    return {allowed: false, reason: "expired-or-missing-schedule"};
  }
  return {allowed: true};
}

export function evaluateSchedulerClaimDecision(params: {
  accountStatus: string;
  scheduledDeletionAtMs: number | null;
  nowMs: number;
}): SchedulerClaimDecision {
  if (
    params.accountStatus !== "pendingDeletion" &&
    params.accountStatus !== "deletionInProgress"
  ) {
    return {shouldClaim: false, reason: "not-pending-deletion"};
  }
  if (params.scheduledDeletionAtMs == null || !Number.isFinite(params.scheduledDeletionAtMs)) {
    return {shouldClaim: false, reason: "malformed-schedule"};
  }
  if (params.scheduledDeletionAtMs > params.nowMs) {
    return {shouldClaim: false, reason: "not-due"};
  }
  return {shouldClaim: true, nextStatus: "deletionInProgress"};
}

export function canAdvanceDeletionStage(
  currentStage: string | null | undefined,
  nextStage: DeletionJobStage,
): boolean {
  const currentIndex = currentStage == null ? -1 : deletionJobStageOrder.indexOf(currentStage as DeletionJobStage);
  const nextIndex = deletionJobStageOrder.indexOf(nextStage);
  if (nextIndex < 0) return false;
  if (currentIndex < 0) return true;
  return nextIndex >= currentIndex;
}

export function usernameReservationBelongsToUid(
  reservationUid: string | null | undefined,
  deletingUid: string,
): boolean {
  return (reservationUid ?? "").trim() !== "" &&
    (reservationUid ?? "").trim() === deletingUid.trim();
}

export function isIgnorableAuthDeletionErrorCode(code: string | null | undefined): boolean {
  return (code ?? "").trim() === "auth/user-not-found";
}

export type ServiceDeletionHoldSnapshot = {
  previousIsActive: boolean;
  previousIsPaused: boolean;
  previousIsPausedByVerification: boolean;
  previousPauseReason: string;
};

export type ServiceRestorationDecision = {
  isActive: boolean;
  isPaused: boolean;
  isVisibleToMarketplace: boolean;
  pauseReason: string;
};

export function deriveServiceRestorationDecision(params: {
  moderationStatus: string;
  isDeleted: boolean;
  isPausedByVerification: boolean;
  deletionHold: ServiceDeletionHoldSnapshot;
}): ServiceRestorationDecision {
  const moderationStatus = params.moderationStatus.trim();
  const blockedByModeration =
    moderationStatus === "rejected" ||
    moderationStatus === "removed" ||
    moderationStatus === "suspended";
  const canRestore =
    !params.isDeleted &&
    !blockedByModeration &&
    !params.deletionHold.previousIsPaused &&
    !params.deletionHold.previousIsPausedByVerification &&
    !params.isPausedByVerification;

  return {
    isActive: canRestore && params.deletionHold.previousIsActive,
    isPaused: !canRestore,
    isVisibleToMarketplace: canRestore && params.deletionHold.previousIsActive,
    pauseReason: canRestore ? "" : params.deletionHold.previousPauseReason,
  };
}

export function anonymizeParticipantSnapshot<T extends Record<string, unknown>>(snapshot: T): T {
  return {
    ...snapshot,
    name: "Deleted user",
    username: "",
    photoUrl: "",
    phoneMasked: "",
    phone: "",
    phoneNumber: "",
    mobileNumber: "",
    email: "",
  };
}
