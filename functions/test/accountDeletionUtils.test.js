const test = require("node:test");
const assert = require("node:assert/strict");

const {
  ACCOUNT_DELETION_GRACE_PERIOD_MS,
  calculateScheduledDeletionAtMillis,
  evaluateRestoreEligibility,
  evaluateSchedulerClaimDecision,
  canAdvanceDeletionStage,
  usernameReservationBelongsToUid,
  deriveServiceRestorationDecision,
  anonymizeParticipantSnapshot,
  isIgnorableAuthDeletionErrorCode,
} = require("../lib/accountDeletionUtils.js");

test("calculateScheduledDeletionAtMillis adds 30 days", () => {
  const nowMs = Date.UTC(2026, 6, 18, 0, 0, 0);
  assert.equal(
    calculateScheduledDeletionAtMillis(nowMs),
    nowMs + ACCOUNT_DELETION_GRACE_PERIOD_MS,
  );
});

test("evaluateRestoreEligibility allows only pending deletion before schedule", () => {
  const nowMs = Date.UTC(2026, 6, 18, 0, 0, 0);
  assert.deepEqual(
    evaluateRestoreEligibility({
      accountStatus: "pendingDeletion",
      scheduledDeletionAtMs: nowMs + 1,
      nowMs,
    }),
    {allowed: true},
  );
  assert.deepEqual(
    evaluateRestoreEligibility({
      accountStatus: "deletionInProgress",
      scheduledDeletionAtMs: nowMs + 1,
      nowMs,
    }),
    {allowed: false, reason: "deletion-in-progress"},
  );
  assert.deepEqual(
    evaluateRestoreEligibility({
      accountStatus: "pendingDeletion",
      scheduledDeletionAtMs: nowMs,
      nowMs,
    }),
    {allowed: false, reason: "expired-or-missing-schedule"},
  );
});

test("evaluateSchedulerClaimDecision only claims expired pending accounts", () => {
  const nowMs = Date.UTC(2026, 6, 18, 0, 0, 0);
  assert.deepEqual(
    evaluateSchedulerClaimDecision({
      accountStatus: "pendingDeletion",
      scheduledDeletionAtMs: nowMs - 1,
      nowMs,
    }),
    {shouldClaim: true, nextStatus: "deletionInProgress"},
  );
  assert.deepEqual(
    evaluateSchedulerClaimDecision({
      accountStatus: "active",
      scheduledDeletionAtMs: nowMs - 1,
      nowMs,
    }),
    {shouldClaim: false, reason: "not-pending-deletion"},
  );
  assert.deepEqual(
    evaluateSchedulerClaimDecision({
      accountStatus: "pendingDeletion",
      scheduledDeletionAtMs: null,
      nowMs,
    }),
    {shouldClaim: false, reason: "malformed-schedule"},
  );
});

test("canAdvanceDeletionStage is monotonic", () => {
  assert.equal(canAdvanceDeletionStage(null, "claimed"), true);
  assert.equal(canAdvanceDeletionStage("claimed", "sessionsRevoked"), true);
  assert.equal(canAdvanceDeletionStage("storageCleanup", "claimed"), false);
});

test("usernameReservationBelongsToUid requires exact ownership", () => {
  assert.equal(usernameReservationBelongsToUid("uid_123", "uid_123"), true);
  assert.equal(usernameReservationBelongsToUid("uid_other", "uid_123"), false);
  assert.equal(usernameReservationBelongsToUid("", "uid_123"), false);
});

test("deriveServiceRestorationDecision keeps manually paused or verification-paused services hidden", () => {
  assert.deepEqual(
    deriveServiceRestorationDecision({
      moderationStatus: "approved",
      isDeleted: false,
      isPausedByVerification: false,
      deletionHold: {
        previousIsActive: true,
        previousIsPaused: false,
        previousIsPausedByVerification: false,
        previousPauseReason: "",
      },
    }),
    {
      isActive: true,
      isPaused: false,
      isVisibleToMarketplace: true,
      pauseReason: "",
    },
  );

  assert.deepEqual(
    deriveServiceRestorationDecision({
      moderationStatus: "approved",
      isDeleted: false,
      isPausedByVerification: false,
      deletionHold: {
        previousIsActive: true,
        previousIsPaused: true,
        previousIsPausedByVerification: false,
        previousPauseReason: "Manually paused",
      },
    }),
    {
      isActive: false,
      isPaused: true,
      isVisibleToMarketplace: false,
      pauseReason: "Manually paused",
    },
  );
});

test("anonymizeParticipantSnapshot strips personal fields and preserves structure", () => {
  assert.deepEqual(
    anonymizeParticipantSnapshot({
      name: "Nishant",
      username: "@nishant",
      photoUrl: "x",
      phoneNumber: "+91999",
      custom: "keep",
    }),
    {
      name: "Deleted user",
      username: "",
      photoUrl: "",
      phoneMasked: "",
      phone: "",
      phoneNumber: "",
      mobileNumber: "",
      email: "",
      custom: "keep",
    },
  );
});

test("isIgnorableAuthDeletionErrorCode treats missing auth user as safe", () => {
  assert.equal(isIgnorableAuthDeletionErrorCode("auth/user-not-found"), true);
  assert.equal(isIgnorableAuthDeletionErrorCode("auth/internal-error"), false);
});
