import {createHash} from "crypto";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import type {
  CollectionReference,
  DocumentData,
  DocumentReference,
  DocumentSnapshot,
  Query,
  QueryDocumentSnapshot,
  WriteBatch,
} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onDocumentCreated, onDocumentWritten} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {
  anonymizeParticipantSnapshot,
  isIgnorableAuthDeletionErrorCode,
  calculateScheduledDeletionAtMillis,
  evaluateRestoreEligibility,
  evaluateSchedulerClaimDecision,
  deriveServiceRestorationDecision,
  usernameReservationBelongsToUid,
} from "./accountDeletionUtils";
import {normalizeUsername, validateNormalizedUsername} from "./identity/username";
import {isPersistedCompletedAccount} from "./identity/onboardingProfileUtils";
import {
  evaluatePasswordResetEligibility,
  normalizePasswordResetEmail,
  validatePasswordResetEmail,
} from "./passwordReset";
import {
  evaluatePhoneLoginEligibility,
  normalizePhoneLoginNumber,
  validatePhoneLoginNumber,
} from "./phoneLoginEligibility";
import {notificationDeliversPush} from "./notifications/notificationChannels";
import {
  calculateProviderVerificationDocumentDeletionAtMillis,
  cleanupReasonForVerificationStatus,
  collectProviderVerificationDocumentPaths,
  diffProviderVerificationDocumentPaths,
  normalizeProviderVerificationDocumentPath,
  providerVerificationDocumentPathBelongsToUser,
} from "./providerVerificationDocuments";
import {
  generateSlotWindows,
  normalizeServiceSchedulingMode,
  resolveSessionDurationMinutes,
  SERVICE_SCHEDULING_MODE_DAY_CARE,
  SERVICE_SCHEDULING_MODE_TWENTY_FOUR_HOURS,
} from "./serviceScheduling";
import {
  normalizeOfferAudienceInput,
  type OfferAudience,
} from "./offers/domain/offerAudience";
import {
  sanitizeOfferCampaignMutationInput,
} from "./offers/application/offerAdminContract";
import {db, messaging, storage} from "./shared/firebase";
const istOffsetMinutes = 330;
const slotGenerationDays = 30;
const minuteMs = 60 * 1000;
const hourMs = 60 * minuteMs;
const minimumBookingLeadMs = hourMs;
const defaultPushChannelId = "pettxo_general_notifications";
const chatPushChannelId = "pettxo_chat_messages";
const bookingsPaymentsPushChannelId = "pettxo_bookings_payments";
const socialActivityPushChannelId = "pettxo_social_activity";
const otherUpdatesPushChannelId = "pettxo_other_updates";
const passwordResetRequestCooldownMs = 60 * 1000;
const phoneLoginEligibilityCooldownMs = 30 * 1000;
const providerVerificationCleanupBatchLimit = 20;

const restrictionTypes = ["social", "booking", "hard"] as const;
const adminRoles = ["superAdmin", "customerSupportAdmin", "financeAdmin"] as const;
const offerCampaignTypes = ["firstBooking", "festival", "general", "rebooking"] as const;
const offerDiscountTypes = ["flat", "percent"] as const;
const socialNotificationTypes = ["socialFollow", "socialLike", "socialComment"] as const;

type RestrictionType = typeof restrictionTypes[number];
type AdminRole = typeof adminRoles[number];
type OfferCampaignType = typeof offerCampaignTypes[number];
type OfferDiscountType = typeof offerDiscountTypes[number];
type SocialNotificationType = typeof socialNotificationTypes[number];
type AccountStatus = "active" | "restricted" | "hardBanned";
type PublicAccountStatus = AccountStatus | "pendingDeletion" | "deletionInProgress";
type RestrictionState = {
  isBanned: boolean;
  reason: string;
  bannedAt: unknown | null;
  bannedBy: string;
};
type RestrictionMap = Record<RestrictionType, RestrictionState>;
type OfferTargeting = {
  firstBookingOnly: boolean;
  rebookingOnly: boolean;
};
type OfferPayload = {
  title: string;
  description: string;
  couponCode: string;
  campaignType: OfferCampaignType;
  discountType: OfferDiscountType;
  discountValue: number;
  maxDiscountAmount: number | null;
  minBookingAmount: number | null;
  isActive: boolean;
  startAt: Date;
  endAt: Date | null;
  usageLimitPerUser: number;
  targeting: OfferTargeting;
  audience: OfferAudience;
  priority: number;
};
type AccountDeletionJobStatus = "scheduled" | "inProgress" | "completed" | "failed";
type AccountDeletionStage =
  | "scheduled"
  | "claimed"
  | "sessionsRevoked"
  | "cleanupFirestore"
  | "retainedDataAnonymized"
  | "cleanupStorage"
  | "authUserDeleted"
  | "cleanupUsername"
  | "identityDocumentsDeleted"
  | "completed";
type AccountDeletionStats = {
  firestoreDeleted: Record<string, number>;
  firestoreUpdated: Record<string, number>;
  storageDeleted: Record<string, number>;
};

function requireUid(auth: {uid?: string} | undefined): string {
  const uid = auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return uid;
}

function requireAdmin(auth: {token?: {[key: string]: unknown}} | undefined): void {
  if (auth?.token?.admin !== true) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
}

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function maskIdentifier(value: string, visible = 4): string {
  const trimmed = value.trim();
  if (!trimmed) return "";
  if (trimmed.length <= visible) return trimmed;
  return `${"*".repeat(Math.max(trimmed.length - visible, 0))}${trimmed.slice(-visible)}`;
}

function passwordResetRequestHash(email: string): string {
  return createHash("sha256").update(email).digest("hex");
}

function phoneLoginEligibilityRequestHash(phoneNumber: string): string {
  return createHash("sha256").update(phoneNumber).digest("hex");
}

function passwordResetAppCodeForStatus(
  status: ReturnType<typeof evaluatePasswordResetEligibility>,
): string {
  switch (status) {
    case "accountDisabled":
      return "account-disabled";
    case "accountPendingDeletion":
      return "account-pending-deletion";
    case "phoneOnlyAccount":
      return "phone-only-account";
    default:
      return "unknown";
  }
}

function phoneLoginAppCodeForStatus(
  status: ReturnType<typeof evaluatePhoneLoginEligibility>,
): string {
  switch (status) {
    case "notFound":
      return "not_found";
    case "incompleteSignup":
      return "incomplete_signup";
    case "blocked":
      return "blocked";
    case "accountRecoveryRequired":
      return "account_recovery_required";
    case "active":
      return "active";
    default:
      return "unknown";
  }
}

function isRestrictionType(value: string): value is RestrictionType {
  return restrictionTypes.includes(value as RestrictionType);
}

function isAdminRole(value: string): value is AdminRole {
  return adminRoles.includes(value as AdminRole);
}

function isOfferCampaignType(value: string): value is OfferCampaignType {
  return offerCampaignTypes.includes(value as OfferCampaignType);
}

function isOfferDiscountType(value: string): value is OfferDiscountType {
  return offerDiscountTypes.includes(value as OfferDiscountType);
}

function normalizeRestrictionState(value: unknown): RestrictionState {
  const data = value && typeof value === "object" ? value as Record<string, unknown> : {};
  return {
    isBanned: data.isBanned === true,
    reason: asTrimmedString(data.reason),
    bannedAt: data.bannedAt ?? null,
    bannedBy: asTrimmedString(data.bannedBy),
  };
}

function normalizeRestrictions(value: unknown): RestrictionMap {
  const data = value && typeof value === "object" ? value as Record<string, unknown> : {};
  return {
    social: normalizeRestrictionState(data.social),
    booking: normalizeRestrictionState(data.booking),
    hard: normalizeRestrictionState(data.hard),
  };
}

function computeAccountStatus(restrictions: RestrictionMap): AccountStatus {
  if (restrictions.hard.isBanned) return "hardBanned";
  if (restrictions.social.isBanned || restrictions.booking.isBanned) return "restricted";
  return "active";
}

function buildRestrictionPatch(
  type: RestrictionType,
  isBanned: boolean,
  reason: string,
  adminUid: string,
): Record<string, unknown> {
  return {
    restrictions: {
      [type]: isBanned ? {
        isBanned: true,
        reason,
        bannedAt: FieldValue.serverTimestamp(),
        bannedBy: adminUid,
      } : {
        isBanned: false,
        reason: "",
        bannedAt: null,
        bannedBy: "",
      },
    },
  };
}

function nextRestrictions(
  restrictions: RestrictionMap,
  type: RestrictionType,
  isBanned: boolean,
  reason: string,
  adminUid: string,
): RestrictionMap {
  return {
    ...restrictions,
    [type]: isBanned ? {
      isBanned: true,
      reason,
      bannedAt: restrictions[type].bannedAt,
      bannedBy: adminUid,
    } : {
      isBanned: false,
      reason: "",
      bannedAt: null,
      bannedBy: "",
    },
  };
}

async function requireAdminActor(uid: string): Promise<{uid: string; role: AdminRole}> {
  const snapshot = await db.collection("users").doc(uid).get();
  if (!snapshot.exists) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }

  const role = asTrimmedString(snapshot.data()?.adminRole);
  if (!isAdminRole(role)) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }

  return {uid, role};
}

function assertRestrictionPermission(role: AdminRole, type: RestrictionType): void {
  if (role === "superAdmin") return;
  if (role === "customerSupportAdmin" && type !== "hard") return;
  throw new HttpsError("permission-denied", "You do not have access to manage this restriction.");
}

function assertOfferMutationPermission(role: AdminRole): void {
  if (role === "superAdmin" || role === "financeAdmin") return;
  throw new HttpsError("permission-denied", "You do not have access to manage offer campaigns.");
}

function asOptionalFiniteNumber(value: unknown): number | null {
  if (value == null) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function asOptionalPositiveInt(value: unknown): number | null {
  if (value == null) return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return null;
  const normalized = Math.trunc(parsed);
  return normalized > 0 ? normalized : null;
}

function asBoolean(value: unknown, fallback = false): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function asDate(value: unknown): Date | null {
  if (value == null) return null;
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (typeof value === "number") {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  if (typeof value === "string" && value.trim()) {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? value as Record<string, unknown> : {};
}

function writeOfferAuditLog(
  batch: WriteBatch,
  admin: {uid: string; role: AdminRole},
  action: string,
  campaignId: string,
  metadata: Record<string, unknown> = {},
): void {
  const auditRef = db.collection("adminAuditLogs").doc();
  batch.set(auditRef, {
    action,
    targetType: "offerCampaign",
    targetId: campaignId,
    performedBy: admin.uid,
    performedByRole: admin.role,
    createdAt: FieldValue.serverTimestamp(),
    metadata,
  });
}

function normalizeOfferPayload(
  data: Record<string, unknown>,
  options: {requireAllFields: boolean},
): OfferPayload {
  const title = asTrimmedString(data.title);
  const couponCode = asTrimmedString(data.couponCode);
  const campaignType = asTrimmedString(data.campaignType);
  const discountType = asTrimmedString(data.discountType);
  const startAt = asDate(data.startAt);
  const endAt = asDate(data.endAt);
  const discountValue = asOptionalFiniteNumber(data.discountValue);
  const maxDiscountAmount = asOptionalFiniteNumber(data.maxDiscountAmount);
  const minBookingAmount = asOptionalFiniteNumber(data.minBookingAmount);
  const usageLimitPerUser = asOptionalPositiveInt(data.usageLimitPerUser);
  const targetingData = asRecord(data.targeting);
  const targeting: OfferTargeting = {
    firstBookingOnly: asBoolean(targetingData.firstBookingOnly),
    rebookingOnly: asBoolean(targetingData.rebookingOnly),
  };
  let audience: OfferAudience;
  try {
    audience = normalizeOfferAudienceInput(data.audience, {
      allowLegacyMissing: true,
    });
  } catch (error) {
    throw new HttpsError(
      "invalid-argument",
      error instanceof Error ? error.message : "audience is invalid.",
    );
  }

  if (!title) {
    throw new HttpsError("invalid-argument", "title is required.");
  }
  if (!couponCode) {
    throw new HttpsError("invalid-argument", "couponCode is required.");
  }
  if (!isOfferCampaignType(campaignType)) {
    throw new HttpsError(
      "invalid-argument",
      "campaignType must be firstBooking, festival, general, or rebooking.",
    );
  }
  if (!isOfferDiscountType(discountType)) {
    throw new HttpsError("invalid-argument", "discountType must be flat or percent.");
  }
  if (discountValue == null || discountValue <= 0) {
    throw new HttpsError("invalid-argument", "discountValue must be greater than 0.");
  }
  if (discountType === "percent" && discountValue > 100) {
    throw new HttpsError("invalid-argument", "Percent discountValue must be 100 or less.");
  }
  if (usageLimitPerUser == null || usageLimitPerUser < 1) {
    throw new HttpsError("invalid-argument", "usageLimitPerUser must be at least 1.");
  }
  if (!startAt) {
    throw new HttpsError("invalid-argument", "startAt is required.");
  }
  if (endAt && endAt.getTime() <= startAt.getTime()) {
    throw new HttpsError("invalid-argument", "endAt must be after startAt.");
  }
  if (targeting.firstBookingOnly && targeting.rebookingOnly) {
    throw new HttpsError(
      "invalid-argument",
      "targeting.firstBookingOnly and targeting.rebookingOnly cannot both be true.",
    );
  }

  return {
    title,
    description: asTrimmedString(data.description),
    couponCode,
    campaignType,
    discountType,
    discountValue,
    maxDiscountAmount,
    minBookingAmount,
    isActive: asBoolean(data.isActive, options.requireAllFields ? false : false),
    startAt,
    endAt,
    usageLimitPerUser,
    targeting,
    audience,
    priority: toInt(data.priority, 0),
  };
}

function assertAllowedOfferKeys(
  data: Record<string, unknown>,
  allowedKeys: readonly string[],
): void {
  const invalidKeys = Object.keys(data).filter((key) => !allowedKeys.includes(key));
  if (invalidKeys.length > 0) {
    throw new HttpsError(
      "invalid-argument",
      `Unsupported fields: ${invalidKeys.join(", ")}.`,
    );
  }
}

function toInt(value: unknown, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : fallback;
}

function dateKey(year: number, month: number, day: number): string {
  return `${year.toString().padStart(4, "0")}-${month
    .toString()
    .padStart(2, "0")}-${day.toString().padStart(2, "0")}`;
}

function localMidnightUtcMs(year: number, month: number, day: number): number {
  return Date.UTC(year, month - 1, day, 0, 0, 0, 0) - istOffsetMinutes * 60 * 1000;
}

function localDatePartsFromUtcMs(utcMs: number): {
  year: number;
  month: number;
  day: number;
  weekday: string;
} {
  const local = new Date(utcMs + istOffsetMinutes * 60 * 1000);
  const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  return {
    year: local.getUTCFullYear(),
    month: local.getUTCMonth() + 1,
    day: local.getUTCDate(),
    weekday: weekdays[local.getUTCDay()],
  };
}

function serviceSlotConfigChanged(
  before: DocumentData | undefined,
  after: DocumentData,
): boolean {
  if (!before) return true;
  const keys = [
    "ownerUserId",
    "schedulingMode",
    "sessionDurationMinutes",
    "capacity",
    "availableDays",
    "startMinutes",
    "endMinutes",
    "status",
    "isActive",
    "isDeleted",
    "isPaused",
    "isVisibleToMarketplace",
  ];
  return keys.some((key) => JSON.stringify(before[key]) !== JSON.stringify(after[key]));
}

async function commitBatches(
  batches: WriteBatch[],
): Promise<void> {
  for (const batch of batches) {
    await batch.commit();
  }
}

async function regenerateServiceSlots(
  serviceId: string,
  service: DocumentData,
): Promise<void> {
  const slotsRef = db.collection("services").doc(serviceId).collection("slots");
  const now = Date.now();
  const existing = await slotsRef
    .where("startAt", ">=", Timestamp.fromMillis(now))
    .get();

  const batches: WriteBatch[] = [];
  let batch = db.batch();
  let writes = 0;

  const queue = (
    action: (targetBatch: WriteBatch) => void,
  ): void => {
    action(batch);
    writes += 1;
    if (writes >= 450) {
      batches.push(batch);
      batch = db.batch();
      writes = 0;
    }
  };

  for (const doc of existing.docs) {
    const acceptedCount = toInt(doc.data().acceptedCount, 0);
    if (acceptedCount <= 0) {
      queue((targetBatch) => targetBatch.delete(doc.ref));
    }
  }

  const isServiceBookable =
    service.status === "active" &&
    service.isActive === true &&
    service.isDeleted !== true &&
    service.isPaused !== true &&
    service.isVisibleToMarketplace === true;

  if (isServiceBookable) {
    const schedulingMode = normalizeServiceSchedulingMode(service);
    const durationMinutes = resolveSessionDurationMinutes(service);
    const capacity = Math.max(toInt(service.capacity, 1), 1);
    const selectedDays = new Set(
      Array.isArray(service.availableDays) ? service.availableDays.map(String) : [],
    );
    const startMinutes = Math.max(toInt(service.startMinutes, 0), 0);
    const endMinutes = Math.min(toInt(service.endMinutes, 24 * 60), 24 * 60);
    const today = localDatePartsFromUtcMs(now);
    const todayMidnight = localMidnightUtcMs(today.year, today.month, today.day);

    if (selectedDays.size > 0 && durationMinutes > 0) {
      for (let dayOffset = 0; dayOffset < slotGenerationDays; dayOffset += 1) {
        const dayUtcMs = todayMidnight + dayOffset * 24 * 60 * 60 * 1000;
        const parts = localDatePartsFromUtcMs(dayUtcMs);
        if (!selectedDays.has(parts.weekday)) continue;

        const key = dateKey(parts.year, parts.month, parts.day);
        const slotWindows = generateSlotWindows({
          schedulingMode,
          sessionDurationMinutes: durationMinutes,
          startMinutes,
          endMinutes,
        });
        for (const slotWindow of slotWindows) {
          const slotStartMs = dayUtcMs + slotWindow.startMinutes * 60 * 1000;
          const slotEndMs = schedulingMode === SERVICE_SCHEDULING_MODE_TWENTY_FOUR_HOURS ?
            slotStartMs + slotWindow.durationMinutes * 60 * 1000 :
            slotWindow.endMinutes > slotWindow.startMinutes ?
              dayUtcMs + slotWindow.endMinutes * 60 * 1000 :
              slotStartMs + slotWindow.durationMinutes * 60 * 1000;
          const slotId = schedulingMode === SERVICE_SCHEDULING_MODE_DAY_CARE ?
            `${key}_${slotWindow.startMinutes.toString().padStart(4, "0")}_${slotWindow.endMinutes.toString().padStart(4, "0")}` :
            schedulingMode === SERVICE_SCHEDULING_MODE_TWENTY_FOUR_HOURS ?
              `${key}_${slotWindow.startMinutes.toString().padStart(4, "0")}_${slotWindow.durationMinutes.toString().padStart(4, "0")}` :
              slotWindow.endMinutes < slotWindow.startMinutes ?
                `${key}_${slotWindow.startMinutes.toString().padStart(4, "0")}_${slotWindow.endMinutes.toString().padStart(4, "0")}` :
                `${key}_${slotWindow.startMinutes.toString().padStart(4, "0")}`;
          const slotRef = slotsRef.doc(slotId);
          queue((targetBatch) =>
            targetBatch.set(slotRef, {
              serviceId,
              serviceOwnerId: service.ownerUserId ?? "",
              startAt: Timestamp.fromMillis(slotStartMs),
              endAt: Timestamp.fromMillis(slotEndMs),
              dateKey: key,
              serviceDateKey: key,
              startMinutes: slotWindow.startMinutes,
              endMinutes: slotWindow.endMinutes,
              durationMinutes: slotWindow.durationMinutes,
              capacity,
              acceptedCount: 0,
              isBookable: slotStartMs - now >= minimumBookingLeadMs,
              status: slotStartMs - now >= minimumBookingLeadMs ? "open" : "closed",
              timezone: "Asia/Kolkata",
              generatedAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            }),
          );
        }
      }
    }
  }

  if (writes > 0) batches.push(batch);
  await commitBatches(batches);
}

function safeText(value: unknown, fallback: string): string {
  const text = String(value ?? "").trim();
  return text || fallback;
}

function chatIdForPair(leftUid: string, rightUid: string): string {
  return [leftUid.trim(), rightUid.trim()].sort().join("_");
}

function canonicalChatIdForPair(leftUid: string, rightUid: string): string {
  return `chat_${chatIdForPair(leftUid, rightUid)}`;
}

function legacyChatIdsForPair(leftUid: string, rightUid: string): string[] {
  const pairId = chatIdForPair(leftUid, rightUid);
  return [pairId, `direct_${pairId}`];
}

function timestampMillis(value: unknown): number {
  if (value instanceof Timestamp) {
    return value.toMillis();
  }
  return 0;
}

function choosePreferredLegacyChat(
  snapshots: Array<DocumentSnapshot<DocumentData>>,
): DocumentSnapshot<DocumentData> | null {
  let preferred: DocumentSnapshot<DocumentData> | null = null;
  let preferredMillis = -1;

  for (const snapshot of snapshots) {
    if (!snapshot.exists) continue;
    const data = snapshot.data() ?? {};
    const millis = Math.max(
      timestampMillis(data.lastMessageAt),
      timestampMillis(data.updatedAt),
      timestampMillis(data.createdAt),
    );
    if (preferred == null || millis > preferredMillis) {
      preferred = snapshot;
      preferredMillis = millis;
    }
  }

  return preferred;
}

async function migrateLegacyChatsToCanonical(params: {
  canonicalChatRef: DocumentReference<DocumentData>;
  legacySnapshots: Array<DocumentSnapshot<DocumentData>>;
  extraServiceId?: string;
  extraServiceTitle?: string;
  extraServiceImageUrl?: string;
}): Promise<void> {
  const existingLegacySnapshots = params.legacySnapshots.filter((snapshot) => snapshot.exists);
  if (existingLegacySnapshots.length === 0) return;

  const preferredLegacySnapshot = choosePreferredLegacyChat(existingLegacySnapshots);
  let batch = db.batch();
  let writes = 0;
  const commitBatchIfNeeded = async () => {
    if (writes < 400) return;
    await batch.commit();
    batch = db.batch();
    writes = 0;
  };

  const preferredLegacy = preferredLegacySnapshot?.data() ?? {};
  const mergedServiceIds = new Set<string>();
  for (const snapshot of existingLegacySnapshots) {
    const data = snapshot.data() ?? {};
    const serviceIds = Array.isArray(data.sourceServiceIds) ? data.sourceServiceIds : [];
    for (const value of serviceIds) {
      const serviceId = asTrimmedString(value);
      if (serviceId) mergedServiceIds.add(serviceId);
    }
    const lastServiceId = asTrimmedString(data.lastServiceId);
    if (lastServiceId) mergedServiceIds.add(lastServiceId);
  }
  if (params.extraServiceId) {
    mergedServiceIds.add(params.extraServiceId);
  }

  batch.set(params.canonicalChatRef, {
    lastMessage: safeText(preferredLegacy.lastMessage, ""),
    lastMessageAt: preferredLegacy.lastMessageAt ?? FieldValue.serverTimestamp(),
    lastSenderId: asTrimmedString(preferredLegacy.lastSenderId),
    unreadCountCustomer: toInt(preferredLegacy.unreadCountCustomer, 0),
    unreadCountProvider: toInt(preferredLegacy.unreadCountProvider, 0),
    customerLastReadAt: preferredLegacy.customerLastReadAt ?? null,
    providerLastReadAt: preferredLegacy.providerLastReadAt ?? null,
    status: asTrimmedString(preferredLegacy.status) || "active",
    createdAt: preferredLegacy.createdAt ?? FieldValue.serverTimestamp(),
    updatedAt: preferredLegacy.updatedAt ?? preferredLegacy.lastMessageAt ?? FieldValue.serverTimestamp(),
    sourceServiceIds: Array.from(mergedServiceIds),
    lastServiceId: params.extraServiceId || asTrimmedString(preferredLegacy.lastServiceId),
    lastServiceTitle: params.extraServiceTitle || safeText(preferredLegacy.lastServiceTitle, ""),
    lastServiceImageUrl: params.extraServiceImageUrl || safeText(preferredLegacy.lastServiceImageUrl, ""),
  }, {merge: true});
  writes += 1;

  for (const legacySnapshot of existingLegacySnapshots) {
    const messagesSnapshot = await legacySnapshot.ref.collection("messages").get();
    for (const messageDoc of messagesSnapshot.docs) {
      batch.set(
        params.canonicalChatRef.collection("messages").doc(messageDoc.id),
        messageDoc.data(),
        {merge: true},
      );
      writes += 1;
      await commitBatchIfNeeded();
    }
  }

  if (writes > 0) {
    await batch.commit();
  }
}

function displayNameFromUser(user: Record<string, unknown>, fallback: string): string {
  return safeText(user.displayName ?? user.name ?? user.username, fallback);
}

function photoUrlFromUser(user: Record<string, unknown>): string {
  return safeText(user.photoUrl ?? user.profileImage, "");
}

function providerIdsFromAuthUser(user: {
  providerData?: Array<{providerId?: string | null} | null> | null;
}): string[] {
  const providerIds = new Set<string>();
  for (const provider of user.providerData ?? []) {
    const providerId = asTrimmedString(provider?.providerId);
    if (providerId) {
      providerIds.add(providerId);
    }
  }
  return Array.from(providerIds).sort();
}

function usernameFromUser(user: Record<string, unknown>): string {
  const username = safeText(user.username, "");
  if (!username) return "";
  return username.startsWith("@") ? username : `@${username}`;
}

function participantSnapshotForChat(userId: string, user: Record<string, unknown>) {
  return {
    userId,
    name: displayNameFromUser(user, "User"),
    username: usernameFromUser(user),
    photoUrl: photoUrlFromUser(user),
  };
}

function assertChatRestrictions(
  restrictions: RestrictionMap,
  message = "Chat is unavailable for this account.",
): void {
  if (restrictions.hard.isBanned || restrictions.social.isBanned) {
    throw new HttpsError("failed-precondition", message);
  }
}

function asTimestamp(value: unknown): Timestamp | null {
  return value instanceof Timestamp ? value : null;
}

function publicAccountStatusFromUser(user: Record<string, unknown>): PublicAccountStatus {
  const explicitStatus = asTrimmedString(user.accountStatus);
  if (
    explicitStatus === "pendingDeletion" ||
    explicitStatus === "deletionInProgress" ||
    explicitStatus === "restricted" ||
    explicitStatus === "hardBanned" ||
    explicitStatus === "active"
  ) {
    return explicitStatus;
  }
  return computeAccountStatus(normalizeRestrictions(user.restrictions));
}

function isPendingDeletionStatus(status: string): boolean {
  return status === "pendingDeletion";
}

function isDeletionProcessingStatus(status: string): boolean {
  return status === "deletionInProgress";
}

function isAccountUnavailableForNormalUse(user: Record<string, unknown>): boolean {
  const status = publicAccountStatusFromUser(user);
  return isPendingDeletionStatus(status) || isDeletionProcessingStatus(status);
}

function assertAccountAvailable(
  user: Record<string, unknown>,
  message = "This account is unavailable right now.",
): void {
  if (isAccountUnavailableForNormalUse(user)) {
    throw new HttpsError("failed-precondition", message, {
      appCode: "account-pending-deletion",
    });
  }
}

function scheduledDeletionTimestampFromNow(now = Timestamp.now()): Timestamp {
  return Timestamp.fromMillis(calculateScheduledDeletionAtMillis(now.toMillis()));
}

function createDeletionStats(): AccountDeletionStats {
  return {
    firestoreDeleted: {},
    firestoreUpdated: {},
    storageDeleted: {},
  };
}

function incrementCounter(target: Record<string, number>, key: string, amount = 1): void {
  target[key] = (target[key] ?? 0) + amount;
}

async function deleteDocumentTree(
  docRef: DocumentReference,
  stats: AccountDeletionStats,
): Promise<void> {
  const subcollections = await docRef.listCollections();
  for (const collectionRef of subcollections) {
    await deleteCollectionTree(collectionRef, stats);
  }
  await docRef.delete();
  incrementCounter(stats.firestoreDeleted, docRef.parent.id);
}

async function deleteCollectionTree(
  collectionRef: CollectionReference,
  stats: AccountDeletionStats,
): Promise<void> {
  while (true) {
    const snapshot = await collectionRef.limit(50).get();
    if (snapshot.empty) return;
    for (const doc of snapshot.docs) {
      await deleteDocumentTree(doc.ref, stats);
    }
  }
}

async function deleteQueryDocumentTrees(
  query: Query,
  stats: AccountDeletionStats,
): Promise<void> {
  while (true) {
    const snapshot = await query.limit(50).get();
    if (snapshot.empty) return;
    for (const doc of snapshot.docs) {
      await deleteDocumentTree(doc.ref, stats);
    }
  }
}

async function updateQueryDocuments(
  query: Query<DocumentData>,
  dataBuilder: (doc: QueryDocumentSnapshot<DocumentData>) => Record<string, unknown> | null,
  stats: AccountDeletionStats,
): Promise<void> {
  let lastDoc: QueryDocumentSnapshot<DocumentData> | null = null;
  while (true) {
    const page: Query<DocumentData> =
      lastDoc == null ? query.limit(100) : query.startAfter(lastDoc).limit(100);
    const snapshot = await page.get();
    if (snapshot.empty) return;
    const batch = db.batch();
    let updates = 0;
    for (const doc of snapshot.docs) {
      const data = dataBuilder(doc);
      if (data == null) continue;
      batch.set(doc.ref, data, {merge: true});
      updates += 1;
      incrementCounter(stats.firestoreUpdated, doc.ref.parent.id);
    }
    if (updates === 0) return;
    await batch.commit();
    lastDoc = snapshot.docs[snapshot.docs.length - 1];
  }
}

async function deleteStoragePrefix(
  prefix: string,
  stats: AccountDeletionStats,
): Promise<void> {
  const [files] = await storage.bucket().getFiles({prefix});
  if (files.length === 0) return;

  for (const file of files) {
    await file.delete({ignoreNotFound: true});
    incrementCounter(stats.storageDeleted, prefix);
  }
}

async function deleteUserOwnedStorageArtifacts(
  uid: string,
  stats: AccountDeletionStats,
): Promise<void> {
  await deleteStoragePrefix(`users/${uid}/`, stats);
  await deleteStoragePrefix(`socialPosts/${uid}/`, stats);
  await deleteStoragePrefix(`providerVerification/${uid}/`, stats);
  await deleteStoragePrefix(`disputes/${uid}/`, stats);
}

async function pauseServicesForPendingDeletion(
  uid: string,
  now: FieldValue,
): Promise<number> {
  const servicesSnapshot = await db
    .collection("services")
    .where("ownerUserId", "==", uid)
    .where("isDeleted", "==", false)
    .get();

  if (servicesSnapshot.empty) return 0;

  const batch = db.batch();
  for (const serviceDoc of servicesSnapshot.docs) {
    const service = serviceDoc.data();
    batch.set(serviceDoc.ref, {
      isActive: false,
      isPaused: true,
      isVisibleToMarketplace: false,
      pauseReason: "Account deletion requested",
      deletionHold: {
        appliedAt: now,
        previousIsActive: service.isActive !== false,
        previousIsPaused: service.isPaused === true,
        previousIsPausedByVerification: service.isPausedByVerification === true,
        previousIsVisibleToMarketplace: service.isVisibleToMarketplace === true,
        previousPauseReason: asTrimmedString(service.pauseReason),
      },
      updatedAt: now,
    }, {merge: true});
  }

  await batch.commit();
  return servicesSnapshot.docs.length;
}

async function restoreServicesAfterPendingDeletion(
  uid: string,
  now: FieldValue,
): Promise<number> {
  const servicesSnapshot = await db
    .collection("services")
    .where("ownerUserId", "==", uid)
    .where("isDeleted", "==", false)
    .get();

  if (servicesSnapshot.empty) return 0;

  const batch = db.batch();
  let updatedCount = 0;
  for (const serviceDoc of servicesSnapshot.docs) {
    const service = serviceDoc.data();
    const deletionHold = asRecord(service.deletionHold);
    if (Object.keys(deletionHold).length === 0) continue;

    const decision = deriveServiceRestorationDecision({
      moderationStatus: asTrimmedString(service.moderationStatus),
      isDeleted: service.isDeleted === true,
      isPausedByVerification: service.isPausedByVerification === true,
      deletionHold: {
        previousIsActive: deletionHold.previousIsActive !== false,
        previousIsPaused: deletionHold.previousIsPaused === true,
        previousIsPausedByVerification: deletionHold.previousIsPausedByVerification === true,
        previousPauseReason: asTrimmedString(deletionHold.previousPauseReason),
      },
    });
    batch.set(serviceDoc.ref, {
      isActive: decision.isActive,
      isPaused: decision.isPaused,
      isVisibleToMarketplace: decision.isVisibleToMarketplace &&
        deletionHold.previousIsVisibleToMarketplace === true,
      pauseReason: decision.pauseReason,
      deletionHold: FieldValue.delete(),
      updatedAt: now,
    }, {merge: true});
    updatedCount += 1;
  }

  if (updatedCount > 0) {
    await batch.commit();
  }
  return updatedCount;
}

async function anonymizeRetainedBookingRecords(
  uid: string,
  stats: AccountDeletionStats,
): Promise<void> {
  const anonymizeBookings = async (query: Query, role: "customer" | "provider") => {
    await updateQueryDocuments(query, (doc) => {
      const data = doc.data();
      const payload: Record<string, unknown> = {
        updatedAt: FieldValue.serverTimestamp(),
      };

      if (role === "customer") {
        payload.customerSnapshot = anonymizeParticipantSnapshot(
          asRecord(data.customerSnapshot),
        );
      } else {
        payload.providerSnapshot = anonymizeParticipantSnapshot(
          asRecord(data.providerSnapshot),
        );
      }

      return payload;
    }, stats);
  };

  await anonymizeBookings(
    db.collection("bookings").where("customerId", "==", uid),
    "customer",
  );
  await anonymizeBookings(
    db.collection("bookings").where("serviceOwnerId", "==", uid),
    "provider",
  );
}

async function closeChatsForDeletedAccount(
  uid: string,
  stats: AccountDeletionStats,
): Promise<void> {
  await updateQueryDocuments(
    db.collection("chats").where("participantIds", "array-contains", uid),
    (doc) => {
      const data = doc.data();
      const snapshots = Array.isArray(data.participantSnapshots) ?
        data.participantSnapshots.map((value) => {
          const participant = asRecord(value);
          if (asTrimmedString(participant.userId) !== uid) return participant;
          return anonymizeParticipantSnapshot(participant);
        }) :
        [];

      return {
        participantSnapshots: snapshots,
        status: "closed",
        lastMessage: asTrimmedString(data.lastMessage),
        updatedAt: FieldValue.serverTimestamp(),
      };
    },
    stats,
  );
}

export async function cleanupAccountFirestoreData(
  uid: string,
  stats: AccountDeletionStats,
): Promise<void> {
  const userRef = db.collection("users").doc(uid);

  await deleteCollectionTree(userRef.collection("notificationTokens"), stats);
  await deleteCollectionTree(userRef.collection("pets"), stats);
  await deleteCollectionTree(userRef.collection("claimedOffers"), stats);
  // User-to-campaign usage records remain backend-owned until permanent deletion.
  await deleteCollectionTree(userRef.collection("offerUsage"), stats);
  await deleteCollectionTree(userRef.collection("providerVerification"), stats);
  await deleteCollectionTree(userRef.collection("providerBankDetails"), stats);

  await deleteQueryDocumentTrees(
    db.collection("follows").where("followerId", "==", uid),
    stats,
  );
  await deleteQueryDocumentTrees(
    db.collection("follows").where("followeeId", "==", uid),
    stats,
  );
  await deleteQueryDocumentTrees(
    db.collection("socialPosts").where("authorId", "==", uid),
    stats,
  );
  await deleteQueryDocumentTrees(
    db.collectionGroup("likes").where("userId", "==", uid),
    stats,
  );
  await deleteQueryDocumentTrees(
    db.collectionGroup("comments").where("authorId", "==", uid),
    stats,
  );
  await deleteQueryDocumentTrees(
    db.collection("services").where("ownerUserId", "==", uid),
    stats,
  );
  await deleteQueryDocumentTrees(
    db.collection("notifications").where("userId", "==", uid),
    stats,
  );

}

async function anonymizeRetainedAccountData(
  uid: string,
  stats: AccountDeletionStats,
): Promise<void> {
  await closeChatsForDeletedAccount(uid, stats);
  await anonymizeRetainedBookingRecords(uid, stats);
}

async function deleteNotificationTokensForUser(userId: string): Promise<number> {
  const snapshot = await db
    .collection("users")
    .doc(userId)
    .collection("notificationTokens")
    .get();
  if (snapshot.empty) return 0;

  let deletedCount = 0;
  let batch = db.batch();
  let ops = 0;
  for (const doc of snapshot.docs) {
    batch.delete(doc.ref);
    deletedCount += 1;
    ops += 1;
    if (ops === 450) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) {
    await batch.commit();
  }
  return deletedCount;
}

function assertChatMonitorPermission(role: AdminRole): void {
  if (role === "superAdmin" || role === "customerSupportAdmin") return;
  throw new HttpsError("permission-denied", "You do not have access to monitor chats.");
}

function chatServiceImage(service: Record<string, unknown>): string {
  const primary = asTrimmedString(service.primaryPhotoUrl);
  if (primary) return primary;
  const urls = Array.isArray(service.photoUrls) ? service.photoUrls : [];
  const first = urls.find((value) => typeof value === "string" && value.trim());
  return typeof first === "string" ? first.trim() : "";
}

function isChatEligibleService(service: Record<string, unknown>, nowMs = Date.now()): boolean {
  return asTrimmedString(service.ownerUserId) !== "" &&
    asTrimmedString(service.status) === "active" &&
    service.isActive === true &&
    service.isDeleted === false &&
    service.isVisibleToMarketplace === true &&
    service.isPaused !== true &&
    service.isPausedByVerification !== true;
}

async function createSocialNotificationDoc(params: {
  recipientId: string;
  senderId: string;
  senderDisplayName: string;
  senderPhotoUrl: string;
  type: SocialNotificationType;
  title: string;
  body: string;
  postId?: string;
  commentId?: string;
}): Promise<void> {
  if (!params.recipientId || params.recipientId === params.senderId) return;
  const recipientSnapshot = await db.collection("users").doc(params.recipientId).get();
  const recipientData = recipientSnapshot.data() ?? {};
  if (isAccountUnavailableForNormalUse(recipientData)) {
    return;
  }

  await db.collection("notifications").add({
    userId: params.recipientId,
    category: "social",
    type: params.type,
    title: params.title,
    body: params.body,
    read: false,
    isRead: false,
    senderId: params.senderId,
    senderDisplayName: params.senderDisplayName,
    senderPhotoUrl: params.senderPhotoUrl,
    postId: params.postId ?? "",
    commentId: params.commentId ?? "",
    data: {
      senderId: params.senderId,
      senderDisplayName: params.senderDisplayName,
      senderPhotoUrl: params.senderPhotoUrl,
      postId: params.postId ?? "",
      commentId: params.commentId ?? "",
      type: params.type,
      category: "social",
    },
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
}

function notificationData(data: Record<string, unknown>): Record<string, string> {
  const payload: Record<string, string> = {};
  for (const [key, value] of Object.entries(data)) {
    if (value === undefined || value === null) continue;
    payload[key] = String(value);
  }
  return payload;
}

function isInvalidMessagingToken(code: string | undefined): boolean {
  return code === "messaging/registration-token-not-registered" ||
    code === "messaging/invalid-registration-token";
}

function notificationTokenDocId(token: string): string {
  return Buffer.from(token, "utf8").toString("base64url");
}

function defaultPushPayload(params: {
  title: string;
  body: string;
  data: Record<string, string>;
  tokens: string[];
  channelId?: string;
}) {
  return {
    tokens: params.tokens,
    notification: {
      title: params.title,
      body: params.body,
    },
    data: params.data,
    android: {
      priority: "high" as const,
      ttl: 60 * 60 * 1000,
      notification: {
        channelId: params.channelId || defaultPushChannelId,
        sound: "default",
        priority: "high" as const,
        visibility: "public" as const,
      },
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
          badge: 1,
        },
      },
    },
  };
}

function normalizedNotificationType(type: unknown, category: unknown): string {
  const trimmedType = asTrimmedString(type);
  const trimmedCategory = asTrimmedString(category);
  if (trimmedCategory === "chat" || trimmedType === "chatMessage") {
    return "chat";
  }
  return trimmedType;
}

type PushRouting = {
  channelId: string;
  emoji: string;
  categoryName: string;
};

function resolvePushRouting(notificationType: string): PushRouting {
  switch (notificationType) {
    case "chat":
    case "message":
    case "providerChat":
      return {
        channelId: chatPushChannelId,
        emoji: "💬",
        categoryName: "chat",
      };
    case "bookingRequest":
    case "bookingAccepted":
    case "bookingRejected":
    case "bookingCancelled":
    case "bookingReminder":
      return {
        channelId: bookingsPaymentsPushChannelId,
        emoji: "📅",
        categoryName: "bookings_payments",
      };
    case "paymentSuccess":
    case "paymentFailed":
    case "payout":
      return {
        channelId: bookingsPaymentsPushChannelId,
        emoji: "💳",
        categoryName: "bookings_payments",
      };
    case "refund":
      return {
        channelId: bookingsPaymentsPushChannelId,
        emoji: "↩️",
        categoryName: "bookings_payments",
      };
    case "socialLike":
    case "like":
      return {
        channelId: socialActivityPushChannelId,
        emoji: "❤️",
        categoryName: "social",
      };
    case "socialComment":
    case "comment":
      return {
        channelId: socialActivityPushChannelId,
        emoji: "💬",
        categoryName: "social",
      };
    case "socialFollow":
    case "follow":
      return {
        channelId: socialActivityPushChannelId,
        emoji: "👤",
        categoryName: "social",
      };
    case "promotion":
      return {
        channelId: otherUpdatesPushChannelId,
        emoji: "🎉",
        categoryName: "other",
      };
    case "general":
    case "announcement":
      return {
        channelId: otherUpdatesPushChannelId,
        emoji: "📢",
        categoryName: "other",
      };
    default:
      return {
        channelId: otherUpdatesPushChannelId,
        emoji: "📢",
        categoryName: "other",
      };
  }
}

function ensureSingleLeadingEmoji(text: string, emoji: string): string {
  const trimmed = text.trim();
  if (!trimmed || !emoji) return trimmed;
  return trimmed.startsWith(emoji) ? trimmed : `${emoji} ${trimmed}`;
}

function notificationPreferenceValue(
  data: Record<string, unknown>,
  key: string,
): boolean | null {
  if (typeof data[key] === "boolean") {
    return data[key] as boolean;
  }

  const preferences = data.notificationPreferences;
  if (preferences && typeof preferences === "object" && !Array.isArray(preferences)) {
    const nested = preferences as Record<string, unknown>;
    if (typeof nested[key] === "boolean") {
      return nested[key] as boolean;
    }
  }

  return null;
}

function userAllowsNotification(
  userData: Record<string, unknown>,
  category: string,
): boolean {
  if (isAccountUnavailableForNormalUse(userData)) return false;

  const notificationsBlocked = notificationPreferenceValue(userData, "notificationsBlocked");
  if (notificationsBlocked === true) return false;

  const pushNotificationsBlocked = notificationPreferenceValue(userData, "pushNotificationsBlocked");
  if (pushNotificationsBlocked === true) return false;

  const notificationsEnabled = notificationPreferenceValue(userData, "notificationsEnabled");
  if (notificationsEnabled === false) return false;

  const pushNotificationsEnabled = notificationPreferenceValue(userData, "pushNotificationsEnabled");
  if (pushNotificationsEnabled === false) return false;

  if (category === "chat") {
    const chatNotificationsBlocked = notificationPreferenceValue(userData, "chatNotificationsBlocked");
    if (chatNotificationsBlocked === true) return false;

    const chatNotificationsEnabled = notificationPreferenceValue(userData, "chatNotificationsEnabled");
    if (chatNotificationsEnabled === false) return false;

    const messageNotificationsEnabled = notificationPreferenceValue(userData, "messageNotificationsEnabled");
    if (messageNotificationsEnabled === false) return false;
  }

  return true;
}

type ProviderVerificationSnapshot = {
  status: string;
  documentFrontPath: string;
  documentBackPath: string;
  gracePeriodEndsAt: Timestamp | null;
  reviewedAt: Timestamp | null;
  documentDeletionScheduledAt: Timestamp | null;
  documentDeletedAt: Timestamp | null;
  reviewedBy: string;
  rejectionReason: string;
};

function normalizeProviderVerification(data: DocumentData | undefined): ProviderVerificationSnapshot {
  return {
    status: asTrimmedString(data?.status) || "notSubmitted",
    documentFrontPath: normalizeProviderVerificationDocumentPath(data?.documentFrontPath),
    documentBackPath: normalizeProviderVerificationDocumentPath(data?.documentBackPath),
    gracePeriodEndsAt: data?.gracePeriodEndsAt instanceof Timestamp ? data.gracePeriodEndsAt as Timestamp : null,
    reviewedAt: data?.reviewedAt instanceof Timestamp ? data.reviewedAt as Timestamp : null,
    documentDeletionScheduledAt:
      data?.documentDeletionScheduledAt instanceof Timestamp ? data.documentDeletionScheduledAt as Timestamp : null,
    documentDeletedAt:
      data?.documentDeletedAt instanceof Timestamp ? data.documentDeletedAt as Timestamp : null,
    reviewedBy: asTrimmedString(data?.reviewedBy),
    rejectionReason: asTrimmedString(data?.rejectionReason),
  };
}

function providerVerificationDocumentPaths(
  verification: ProviderVerificationSnapshot,
): string[] {
  return collectProviderVerificationDocumentPaths([
    verification.documentFrontPath,
    verification.documentBackPath,
  ]);
}

function providerVerificationCleanupDocId(params: {
  userId: string;
  verificationId: string;
  reason: string;
  storagePaths: string[];
}): string {
  const digest = createHash("sha256")
    .update(JSON.stringify({
      userId: params.userId,
      verificationId: params.verificationId,
      reason: params.reason,
      storagePaths: [...params.storagePaths].sort(),
    }))
    .digest("hex")
    .slice(0, 32);
  return `${params.verificationId}_${params.reason}_${digest}`;
}

async function enqueueProviderVerificationDocumentCleanup(params: {
  userId: string;
  verificationId: string;
  storagePaths: string[];
  reason: "approved" | "rejected" | "resubmitted";
  scheduledDeletionAtMs: number;
}): Promise<void> {
  const normalizedPaths = collectProviderVerificationDocumentPaths(params.storagePaths);
  if (normalizedPaths.length === 0) return;
  if (normalizedPaths.some((path) => !providerVerificationDocumentPathBelongsToUser(params.userId, path))) {
    throw new Error(`Invalid provider verification cleanup path for ${params.userId}.`);
  }

  const cleanupId = providerVerificationCleanupDocId({
    userId: params.userId,
    verificationId: params.verificationId,
    reason: params.reason,
    storagePaths: normalizedPaths,
  });

  await db.collection("verificationDocumentCleanup").doc(cleanupId).set({
    userId: params.userId,
    verificationId: params.verificationId,
    storagePaths: normalizedPaths,
    reason: params.reason,
    status: "scheduled",
    attemptCount: 0,
    scheduledDeletionAt: Timestamp.fromMillis(params.scheduledDeletionAtMs),
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    completedAt: null,
    lastError: "",
  }, {merge: true});
}

async function claimProviderVerificationCleanupJob(
  ref: DocumentReference,
  now: Timestamp,
): Promise<DocumentData | null> {
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return null;
    const data = snapshot.data() ?? {};
    const scheduledDeletionAt = data.scheduledDeletionAt instanceof Timestamp ?
      data.scheduledDeletionAt as Timestamp :
      null;
    if (asTrimmedString(data.status) !== "scheduled" ||
      !scheduledDeletionAt ||
      scheduledDeletionAt.toMillis() > now.toMillis()) {
      return null;
    }
    transaction.set(ref, {
      status: "processing",
      attemptCount: FieldValue.increment(1),
      processingStartedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return data;
  });
}

async function markProviderVerificationCleanupCompleted(params: {
  ref: DocumentReference;
  userId: string;
  verificationId: string;
  storagePaths: string[];
}): Promise<void> {
  const verificationRef = db
    .collection("users")
    .doc(params.userId)
    .collection("providerVerification")
    .doc(params.verificationId);

  await db.runTransaction(async (transaction) => {
    const verificationSnapshot = await transaction.get(verificationRef);
    if (verificationSnapshot.exists) {
      const data = verificationSnapshot.data() ?? {};
      const currentFrontPath = normalizeProviderVerificationDocumentPath(data.documentFrontPath);
      const currentBackPath = normalizeProviderVerificationDocumentPath(data.documentBackPath);
      const deletedPaths = new Set(params.storagePaths);
      const updates: Record<string, unknown> = {};

      if (deletedPaths.has(currentFrontPath)) {
        updates.documentFrontPath = "";
        updates.documentFrontUrl = "";
      }
      if (deletedPaths.has(currentBackPath)) {
        updates.documentBackPath = "";
        updates.documentBackUrl = "";
      }

      if (Object.keys(updates).length > 0) {
        updates.documentDeletedAt = FieldValue.serverTimestamp();
        updates.updatedAt = FieldValue.serverTimestamp();
        transaction.set(verificationRef, updates, {merge: true});
      }
    }

    transaction.set(params.ref, {
      status: "completed",
      completedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      lastError: "",
    }, {merge: true});
  });
}

async function markProviderVerificationCleanupRetryable(
  ref: DocumentReference,
  errorMessage: string,
): Promise<void> {
  await ref.set({
    status: "scheduled",
    updatedAt: FieldValue.serverTimestamp(),
    lastError: errorMessage,
  }, {merge: true});
}

async function markProviderVerificationCleanupFailed(
  ref: DocumentReference,
  errorMessage: string,
): Promise<void> {
  await ref.set({
    status: "failed",
    updatedAt: FieldValue.serverTimestamp(),
    lastError: errorMessage,
  }, {merge: true});
}

function shouldPauseServicesForVerification(verification: ProviderVerificationSnapshot, now = Timestamp.now()): boolean {
  if (verification.status === "approved") return false;
  if (!verification.gracePeriodEndsAt) return false;
  return verification.gracePeriodEndsAt.toMillis() <= now.toMillis();
}

async function updateProviderServicesForVerification(
  userId: string,
  verification: ProviderVerificationSnapshot,
): Promise<number> {
  const snapshot = await db
    .collection("services")
    .where("ownerUserId", "==", userId)
    .where("isDeleted", "==", false)
    .get();

  if (snapshot.empty) return 0;

  const shouldPause = shouldPauseServicesForVerification(verification);
  const verificationPauseReason = "Provider verification pending";
  let updatedCount = 0;
  let batch = db.batch();
  let ops = 0;

  for (const doc of snapshot.docs) {
    const current = doc.data();
    const currentPauseReason = asTrimmedString(current.pauseReason);
    const nextPauseReason = shouldPause ?
      verificationPauseReason :
      (currentPauseReason === verificationPauseReason ? "" : currentPauseReason);
    const alreadyMatches =
      asTrimmedString(current.providerVerificationStatus) === verification.status &&
      Boolean(current.isPausedByVerification) === shouldPause &&
      currentPauseReason === nextPauseReason;

    if (alreadyMatches) continue;

    batch.set(doc.ref, {
      providerVerificationStatus: verification.status,
      providerVerificationGraceEndsAt: verification.gracePeriodEndsAt,
      isPausedByVerification: shouldPause,
      pauseReason: nextPauseReason,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    updatedCount += 1;
    ops += 1;

    if (ops === 450) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }

  if (ops > 0) {
    await batch.commit();
  }

  return updatedCount;
}

export const syncNotificationToken = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const token = asTrimmedString(request.data?.token);
  const platform = asTrimmedString(request.data?.platform) || "unknown";
  if (!token) {
    throw new HttpsError("invalid-argument", "token is required.");
  }

  const tokenId = notificationTokenDocId(token);
  const existingTokenSnapshots = await db
    .collectionGroup("notificationTokens")
    .where("token", "==", token)
    .get();

  const removedFromUserIds = new Set<string>();
  const batch = db.batch();
  for (const doc of existingTokenSnapshots.docs) {
    const ownerUserId = doc.ref.parent.parent?.id ?? "";
    if (!ownerUserId || ownerUserId === uid) continue;
    removedFromUserIds.add(ownerUserId);
    batch.delete(doc.ref);
  }

  const tokenRef = db
    .collection("users")
    .doc(uid)
    .collection("notificationTokens")
    .doc(tokenId);
  const savedPath = tokenRef.path;
  const currentTokenSnapshot = await tokenRef.get();
  const tokenPayload: Record<string, unknown> = {
    token,
    platform,
    disabled: false,
    disabledAt: FieldValue.delete(),
    errorCode: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
    lastSeenAt: FieldValue.serverTimestamp(),
  };
  if (!currentTokenSnapshot.exists) {
    tokenPayload.createdAt = FieldValue.serverTimestamp();
  }
  batch.set(tokenRef, tokenPayload, {merge: true});
  await batch.commit();

  const removedList = Array.from(removedFromUserIds);
  console.info("Notification token synced", {
    uid,
    tokenReceived: token,
    tokenMasked: maskIdentifier(token),
    savedPath,
    platform,
    removedFromUserIds: removedList,
    savedToUserId: uid,
  });

  return {
    currentUserId: uid,
    savedPath,
    removedFromUserIds: removedList,
    savedToUserId: uid,
  };
});

export const removeNotificationToken = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const token = asTrimmedString(request.data?.token);
  if (!token) {
    throw new HttpsError("invalid-argument", "token is required.");
  }

  const removedFromUserIds = new Set<string>();
  const removedPaths: string[] = [];
  const batch = db.batch();
  const tokenId = notificationTokenDocId(token);
  const directTokenRef = db
    .collection("users")
    .doc(uid)
    .collection("notificationTokens")
    .doc(tokenId);
  const directTokenSnapshot = await directTokenRef.get();
  if (directTokenSnapshot.exists) {
    removedFromUserIds.add(uid);
    removedPaths.push(directTokenRef.path);
    batch.delete(directTokenRef);
  }

  const sameUserTokenSnapshots = await db
    .collection("users")
    .doc(uid)
    .collection("notificationTokens")
    .where("token", "==", token)
    .get();

  for (const doc of sameUserTokenSnapshots.docs) {
    if (doc.id == tokenId && directTokenSnapshot.exists) continue;
    removedFromUserIds.add(uid);
    removedPaths.push(doc.ref.path);
    batch.delete(doc.ref);
  }
  await batch.commit();

  const removedList = Array.from(removedFromUserIds);
  console.info("Notification token removed", {
    currentUserId: uid,
    tokenMasked: maskIdentifier(token),
    removedFromUserIds: removedList,
    removedPaths,
  });

  return {
    currentUserId: uid,
    removedFromUserIds: removedList,
    removedPaths,
  };
});

export const sendTestPushToSelf = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const title = safeText(request.data?.title, "Pettxo test notification");
  const body = safeText(
    request.data?.body,
    "This is a direct push test from Pettxo.",
  );
  const rawData = request.data?.data;
  const extraData =
    rawData && typeof rawData === "object" && !Array.isArray(rawData) ?
      rawData as Record<string, unknown> :
      {};

  const tokenSnapshot = await db
    .collection("users")
    .doc(uid)
    .collection("notificationTokens")
    .where("disabled", "!=", true)
    .get();

  const tokens = Array.from(new Set(
    tokenSnapshot.docs
      .map((doc) => asTrimmedString(doc.data().token))
      .filter((token) => token.length > 0),
  ));

  if (tokens.length === 0) {
    console.info("Test push skipped", {
      userId: uid,
      reason: "no-active-tokens",
      tokenCount: 0,
    });
    return {
      ok: false,
      tokenCount: 0,
      successCount: 0,
      failureCount: 0,
      fcmErrorCodes: [],
      message: "No active notification tokens found for this user.",
    };
  }

  const data = notificationData({
    ...extraData,
    type: "testPush",
    category: "system",
    senderId: uid,
    recipientId: uid,
    click_action: "FLUTTER_NOTIFICATION_CLICK",
  });

  const response = await messaging.sendEachForMulticast(defaultPushPayload({
    tokens,
    title,
    body,
    data,
    channelId: otherUpdatesPushChannelId,
  }));

  const failureCodes = Array.from(new Set(
    response.responses
      .map((result) => result.error?.code)
      .filter((code): code is string => Boolean(code)),
  ));

  console.info("Test push completed", {
    userId: uid,
    tokenCount: tokens.length,
    successCount: response.successCount,
    failureCount: response.failureCount,
    fcmErrorCodes: failureCodes,
  });

  return {
    ok: response.successCount > 0,
    tokenCount: tokens.length,
    successCount: response.successCount,
    failureCount: response.failureCount,
    fcmErrorCodes: failureCodes,
  };
});

export const requestAccountDeletion = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const userRef = db.collection("users").doc(uid);
  const privateUserRef = db.collection("userPrivate").doc(uid);
  const [userSnapshot, privateUserSnapshot, authUser] = await Promise.all([
    userRef.get(),
    privateUserRef.get(),
    getAuth().getUser(uid),
  ]);

  if (!userSnapshot.exists) {
    throw new HttpsError("not-found", "Profile not found.");
  }

  const user = userSnapshot.data() ?? {};
  const privateUser = privateUserSnapshot.data() ?? {};
  const publicStatus = publicAccountStatusFromUser(user);
  const privateStatus = asTrimmedString(privateUser.accountStatus);

  if (isDeletionProcessingStatus(publicStatus) || isDeletionProcessingStatus(privateStatus)) {
    throw new HttpsError(
      "failed-precondition",
      "Permanent deletion has already started for this account.",
      {appCode: "deletion-in-progress"},
    );
  }

  if (isPendingDeletionStatus(publicStatus) || isPendingDeletionStatus(privateStatus)) {
    const existingScheduledDeletionAt = asTimestamp(privateUser.scheduledDeletionAt);
    return {
      status: "pendingDeletion",
      scheduledDeletionAt: existingScheduledDeletionAt?.toDate().toISOString() ?? null,
    };
  }

  const now = Timestamp.now();
  const scheduledDeletionAt = scheduledDeletionTimestampFromNow(now);
  const nowFieldValue = FieldValue.serverTimestamp();
  const serviceCount = await pauseServicesForPendingDeletion(uid, nowFieldValue);

  const batch = db.batch();
  batch.set(userRef, {
    accountStatus: "pendingDeletion",
    deletionRequested: true,
    profileVisibility: "hidden",
    updatedAt: nowFieldValue,
  }, {merge: true});
  batch.set(privateUserRef, {
    uid,
    accountStatus: "pendingDeletion",
    deletionRequestedAt: nowFieldValue,
    scheduledDeletionAt,
    deletionReason: asTrimmedString(request.data?.reason),
    deletionRequestVersion: 1,
    restoredAt: FieldValue.delete(),
    previousProfileVisibility: asTrimmedString(user.profileVisibility) || "public",
    updatedAt: nowFieldValue,
  }, {merge: true});
  batch.set(db.collection("adminAuditLogs").doc(), {
    eventType: "accountDeletionRequested",
    userId: uid,
    emailPresent: asTrimmedString(authUser.email) !== "",
    hadServices: serviceCount > 0,
    serviceCount,
    createdAt: nowFieldValue,
    actorUserId: uid,
    source: "mobileApp",
    status: "pendingDeletion",
    scheduledDeletionAt,
  });
  await batch.commit();
  let removedTokenCount = 0;
  try {
    removedTokenCount = await deleteNotificationTokensForUser(uid);
  } catch (error) {
    console.warn("Account deletion token cleanup failed", {
      userId: uid,
      stage: "notificationTokenCleanup",
      status: "warning",
      errorCode: error instanceof Error ? error.message : String(error),
    });
  }
  try {
    await getAuth().revokeRefreshTokens(uid);
  } catch (error) {
    console.warn("Account deletion refresh-token revoke failed", {
      userId: uid,
      stage: "sessionsRevoked",
      status: "warning",
      errorCode: error instanceof Error ? error.message : String(error),
    });
  }

  console.info("Account deletion requested", {
    userId: uid,
    removedTokenCount,
    serviceCount,
    scheduledDeletionAt: scheduledDeletionAt.toDate().toISOString(),
  });

  return {
    status: "pendingDeletion",
    scheduledDeletionAt: scheduledDeletionAt.toDate().toISOString(),
  };
});

export const restoreAccount = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const userRef = db.collection("users").doc(uid);
  const privateUserRef = db.collection("userPrivate").doc(uid);
  const [userSnapshot, privateUserSnapshot] = await Promise.all([
    userRef.get(),
    privateUserRef.get(),
  ]);

  if (!userSnapshot.exists) {
    throw new HttpsError("not-found", "Profile not found.");
  }

  const user = userSnapshot.data() ?? {};
  const privateUser = privateUserSnapshot.data() ?? {};
  const publicStatus = publicAccountStatusFromUser(user);
  const privateStatus = asTrimmedString(privateUser.accountStatus);

  if (isDeletionProcessingStatus(publicStatus) || isDeletionProcessingStatus(privateStatus)) {
    throw new HttpsError(
      "failed-precondition",
      "Permanent deletion has already started and can no longer be restored.",
      {appCode: "deletion-in-progress"},
    );
  }

  if (!isPendingDeletionStatus(publicStatus) && !isPendingDeletionStatus(privateStatus)) {
    return {status: "active", restored: false};
  }

  const restoreEligibility = evaluateRestoreEligibility({
    accountStatus: privateStatus || publicStatus,
    scheduledDeletionAtMs: asTimestamp(privateUser.scheduledDeletionAt)?.toMillis() ?? null,
    nowMs: Date.now(),
  });
  if (!restoreEligibility.allowed) {
    throw new HttpsError(
      "failed-precondition",
      "Permanent deletion has already started and can no longer be restored.",
      {appCode: restoreEligibility.reason},
    );
  }

  const now = FieldValue.serverTimestamp();
  const restoredStatus = computeAccountStatus(normalizeRestrictions(user.restrictions));
  const previousProfileVisibility = asTrimmedString(privateUser.previousProfileVisibility) || "public";
  const batch = db.batch();
  batch.set(userRef, {
    accountStatus: restoredStatus,
    deletionRequested: false,
    profileVisibility: previousProfileVisibility,
    updatedAt: now,
  }, {merge: true});
  batch.set(privateUserRef, {
    accountStatus: "active",
    deletionRequestedAt: null,
    scheduledDeletionAt: null,
    deletionReason: FieldValue.delete(),
    deletionRequestVersion: FieldValue.delete(),
    previousProfileVisibility: FieldValue.delete(),
    restoredAt: now,
    updatedAt: now,
  }, {merge: true});
  batch.set(db.collection("adminAuditLogs").doc(), {
    eventType: "accountRestored",
    userId: uid,
    actorUserId: uid,
    source: "mobileApp",
    createdAt: now,
  });
  await batch.commit();

  const restoredServiceCount = await restoreServicesAfterPendingDeletion(uid, now);

  console.info("Account restored", {
    userId: uid,
    restoredServiceCount,
  });

  return {
    status: "active",
    restored: true,
  };
});

async function processScheduledDeletionForUser(uid: string): Promise<{
  skipped: boolean;
  reason?: string;
  stats?: AccountDeletionStats;
}> {
  const userRef = db.collection("users").doc(uid);
  const privateUserRef = db.collection("userPrivate").doc(uid);
  const jobRef = db.collection("accountDeletionJobs").doc(uid);
  const [userSnapshot, privateUserSnapshot] = await Promise.all([
    userRef.get(),
    privateUserRef.get(),
  ]);
  const user = userSnapshot.data() ?? {};
  const privateUser = privateUserSnapshot.data() ?? {};
  if (!userSnapshot.exists) {
    return {skipped: true, reason: "not-pending-deletion"};
  }
  const publicStatus = publicAccountStatusFromUser(user);
  const privateStatus = asTrimmedString(privateUser.accountStatus);

  const currentUsername = normalizeUsername(
    asTrimmedString(user.usernameLowercase || user.username),
  );
  const stats = createDeletionStats();
  const now = FieldValue.serverTimestamp();
  let attemptCount = 0;

  const shouldProceed = await db.runTransaction(async (transaction) => {
    const freshPrivate = await transaction.get(privateUserRef);
    const freshPrivateData = freshPrivate.data() ?? {};
    const freshStatus = asTrimmedString(freshPrivateData.accountStatus);
    const freshScheduledDeletionAtMs =
      asTimestamp(freshPrivateData.scheduledDeletionAt)?.toMillis() ?? null;
    const claimDecision = evaluateSchedulerClaimDecision({
      accountStatus: freshStatus || privateStatus || publicStatus,
      scheduledDeletionAtMs: freshScheduledDeletionAtMs,
      nowMs: Date.now(),
    });
    if (!freshPrivate.exists || !claimDecision.shouldClaim) {
      return false;
    }
    attemptCount =
      (typeof freshPrivateData.attemptCount === "number" ?
        freshPrivateData.attemptCount :
        0) + 1;

    transaction.set(jobRef, {
      uid,
      status: "inProgress" as AccountDeletionJobStatus,
      requestedAt: freshPrivateData.deletionRequestedAt ?? null,
      scheduledAt: freshPrivateData.scheduledDeletionAt ?? null,
      startedAt: now,
      completedAt: null,
      lastError: "",
      attemptCount,
      currentStage: "claimed" as AccountDeletionStage,
      updatedAt: now,
    }, {merge: true});

    transaction.set(userRef, {
      accountStatus: "deletionInProgress",
      profileVisibility: "hidden",
      updatedAt: now,
    }, {merge: true});
    transaction.set(privateUserRef, {
      accountStatus: "deletionInProgress",
      updatedAt: now,
    }, {merge: true});
    transaction.set(db.collection("adminAuditLogs").doc(), {
      eventType: "accountPermanentDeletionStarted",
      userId: uid,
      actorUserId: uid,
      source: "scheduler",
      createdAt: now,
    });
    return true;
  });

  if (!shouldProceed) {
    return {skipped: true, reason: "restored-before-processing"};
  }

  try {
    console.info("Scheduled account deletion stage", {
      userId: uid,
      stage: "claimed",
      attemptCount,
      status: "started",
    });
    await getAuth().revokeRefreshTokens(uid);

    await jobRef.set({
      currentStage: "sessionsRevoked",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    console.info("Scheduled account deletion stage", {
      userId: uid,
      stage: "sessionsRevoked",
      attemptCount,
      status: "success",
    });

    await jobRef.set({
      currentStage: "cleanupFirestore",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    await cleanupAccountFirestoreData(uid, stats);
    console.info("Scheduled account deletion stage", {
      userId: uid,
      stage: "firestoreCleanup",
      attemptCount,
      status: "success",
    });

    await jobRef.set({
      currentStage: "retainedDataAnonymized",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    await anonymizeRetainedAccountData(uid, stats);
    console.info("Scheduled account deletion stage", {
      userId: uid,
      stage: "retainedDataAnonymized",
      attemptCount,
      status: "success",
    });

    await jobRef.set({
      currentStage: "cleanupStorage",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    await deleteUserOwnedStorageArtifacts(uid, stats);
    console.info("Scheduled account deletion stage", {
      userId: uid,
      stage: "storageCleanup",
      attemptCount,
      status: "success",
    });

    await jobRef.set({
      currentStage: "authUserDeleted",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    try {
      await getAuth().deleteUser(uid);
    } catch (error) {
      const authError = error as {code?: string};
      if (!isIgnorableAuthDeletionErrorCode(authError.code)) {
        throw error;
      }
    }
    console.info("Scheduled account deletion stage", {
      userId: uid,
      stage: "authUserDeleted",
      attemptCount,
      status: "success",
    });

    if (currentUsername) {
      await jobRef.set({
        currentStage: "cleanupUsername",
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      const usernameSnapshot = await db.collection("usernames").doc(currentUsername).get();
      if (
        usernameSnapshot.exists &&
        usernameReservationBelongsToUid(
          asTrimmedString(usernameSnapshot.data()?.uid),
          uid,
        )
      ) {
        await usernameSnapshot.ref.delete();
        incrementCounter(stats.firestoreDeleted, "usernames");
      } else if (usernameSnapshot.exists) {
        await jobRef.set({
          lastError: "username-reservation-ownership-mismatch",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }
      console.info("Scheduled account deletion stage", {
        userId: uid,
        stage: "cleanupUsername",
        attemptCount,
        status: "success",
      });
    }

    await jobRef.set({
      currentStage: "identityDocumentsDeleted",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    await deleteDocumentTree(privateUserRef, stats);
    await deleteDocumentTree(userRef, stats);
    console.info("Scheduled account deletion stage", {
      userId: uid,
      stage: "identityDocumentsDeleted",
      attemptCount,
      status: "success",
    });

    await jobRef.set({
      status: "completed" as AccountDeletionJobStatus,
      currentStage: "completed" as AccountDeletionStage,
      completedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      stats,
    }, {merge: true});
    await db.collection("adminAuditLogs").add({
      eventType: "accountPermanentDeletionCompleted",
      userId: uid,
      actorUserId: uid,
      source: "scheduler",
      createdAt: FieldValue.serverTimestamp(),
      stats,
    });

    console.info("Account permanently deleted", {userId: uid, stats});
    return {skipped: false, stats};
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await jobRef.set({
      status: "failed" as AccountDeletionJobStatus,
      lastError: message,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    await db.collection("adminAuditLogs").add({
      eventType: "accountPermanentDeletionFailed",
      userId: uid,
      actorUserId: uid,
      source: "scheduler",
      createdAt: FieldValue.serverTimestamp(),
      error: message,
    });
    console.error("Scheduled account deletion stage", {
      userId: uid,
      stage: "failed",
      attemptCount,
      status: "error",
      errorCode: message,
    });
    throw error;
  }
}

export const processScheduledAccountDeletions = onSchedule(
  {
    schedule: "every 6 hours",
    timeZone: "Asia/Kolkata",
    region: "asia-south1",
    timeoutSeconds: 540,
    memory: "1GiB",
    maxInstances: 1,
  },
  async () => {
    const snapshot = await db
      .collection("userPrivate")
      .where("accountStatus", "in", ["pendingDeletion", "deletionInProgress"])
      .where("scheduledDeletionAt", "<=", Timestamp.now())
      .orderBy("scheduledDeletionAt", "asc")
      .limit(20)
      .get();

    if (snapshot.empty) {
      console.info("No scheduled account deletions are due.");
      return;
    }

    for (const doc of snapshot.docs) {
      try {
        const result = await processScheduledDeletionForUser(doc.id);
        if (result.skipped) {
          console.info("Scheduled account deletion skipped", {
            userId: doc.id,
            reason: result.reason,
          });
        }
      } catch (error) {
        console.error("Scheduled account deletion failed", {
          userId: doc.id,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }
  },
);

export const changeUsername = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const requestedUsername = normalizeUsername(request.data?.username);
  const validationError = validateNormalizedUsername(requestedUsername);
  if (validationError) {
    throw new HttpsError("invalid-argument", validationError, {
      appCode: "invalid-username",
    });
  }

  const userRef = db.collection("users").doc(uid);
  const usernamesRef = db.collection("usernames");
  const now = FieldValue.serverTimestamp();

  const username = await db.runTransaction(async (transaction) => {
    const userSnapshot = await transaction.get(userRef);
    if (!userSnapshot.exists) {
      throw new HttpsError("not-found", "Profile not found.");
    }

    const user = userSnapshot.data() ?? {};
    assertAccountAvailable(
      user,
      "Usernames cannot be changed while the account is pending deletion.",
    );
    const currentUsername = normalizeUsername(
      asTrimmedString(user.usernameLowercase || user.username),
    );
    if (!currentUsername) {
      throw new HttpsError(
        "failed-precondition",
        "Current username is missing.",
        {appCode: "username-reservation-mismatch"},
      );
    }

    if (currentUsername === requestedUsername) {
      return requestedUsername;
    }

    const currentUsernameRef = usernamesRef.doc(currentUsername);
    const nextUsernameRef = usernamesRef.doc(requestedUsername);
    const [currentUsernameSnapshot, nextUsernameSnapshot] = await Promise.all([
      transaction.get(currentUsernameRef),
      transaction.get(nextUsernameRef),
    ]);

    const currentReservedUid = asTrimmedString(currentUsernameSnapshot.data()?.uid);
    if (!currentUsernameSnapshot.exists || currentReservedUid !== uid) {
      throw new HttpsError(
        "failed-precondition",
        "Current username ownership could not be verified.",
        {appCode: "username-reservation-mismatch"},
      );
    }

    const nextReservedUid = asTrimmedString(nextUsernameSnapshot.data()?.uid);
    if (nextUsernameSnapshot.exists && nextReservedUid && nextReservedUid !== uid) {
      throw new HttpsError("already-exists", "Username is already taken.", {
        appCode: "username-taken",
      });
    }

    transaction.set(nextUsernameRef, {
      uid,
      username: requestedUsername,
      usernameLowercase: requestedUsername,
      ...(nextUsernameSnapshot.exists ? {} : {createdAt: now}),
      updatedAt: now,
    }, {merge: true});
    transaction.set(userRef, {
      username: requestedUsername,
      usernameLowercase: requestedUsername,
      updatedAt: now,
    }, {merge: true});
    transaction.delete(currentUsernameRef);
    transaction.set(db.collection("adminAuditLogs").doc(), {
      eventType: "usernameChanged",
      userId: uid,
      previousUsername: currentUsername,
      nextUsername: requestedUsername,
      createdAt: now,
      actorUserId: uid,
      source: "mobileApp",
    });

    return requestedUsername;
  });

  return {
    ok: true,
    username,
  };
});

export const completeOnboardingProfile = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const role = asTrimmedString(request.data?.role);
  const displayName = asTrimmedString(request.data?.displayName || request.data?.name);
  const requestedUsername = normalizeUsername(request.data?.username);
  const state = asTrimmedString(request.data?.state);
  const city = asTrimmedString(request.data?.city);
  const acceptedTerms = request.data?.acceptedTerms === true;
  const acceptedPrivacy = request.data?.acceptedPrivacy === true;
  const acceptedProviderAgreement = request.data?.acceptedProviderAgreement === true;

  if (!role) {
    throw new HttpsError("invalid-argument", "Profile role is required.", {
      appCode: "invalid-profile-role",
    });
  }
  if (!displayName) {
    throw new HttpsError("invalid-argument", "Display name is required.", {
      appCode: "invalid-display-name",
    });
  }
  const usernameValidationError = validateNormalizedUsername(requestedUsername);
  if (usernameValidationError) {
    throw new HttpsError("invalid-argument", usernameValidationError, {
      appCode: "invalid-username",
    });
  }
  if (!state) {
    throw new HttpsError("invalid-argument", "State is required.", {
      appCode: "invalid-state",
    });
  }
  if (!city) {
    throw new HttpsError("invalid-argument", "City is required.", {
      appCode: "invalid-city",
    });
  }
  if (!acceptedTerms || !acceptedPrivacy) {
    throw new HttpsError("failed-precondition", "Legal acceptance is required.", {
      appCode: "legal-acceptance-required",
    });
  }
  if (role === "serviceProvider" && !acceptedProviderAgreement) {
    throw new HttpsError("failed-precondition", "Provider agreement is required.", {
      appCode: "provider-agreement-required",
    });
  }

  const authUser = await getAuth().getUser(uid);
  const providers = providerIdsFromAuthUser(authUser);
  const email = asTrimmedString(authUser.email);
  const phoneNumber = asTrimmedString(authUser.phoneNumber);
  const emailVerified = authUser.emailVerified === true;
  const phoneVerified = phoneNumber.length > 0 && providers.includes("phone");
  if (!phoneVerified) {
    throw new HttpsError(
      "failed-precondition",
      "Phone verification is required before completing your profile.",
      {appCode: "phone-verification-required"},
    );
  }

  const userRef = db.collection("users").doc(uid);
  const privateUserRef = db.collection("userPrivate").doc(uid);
  const usernamesRef = db.collection("usernames");
  const targetUsernameRef = usernamesRef.doc(requestedUsername);
  const now = FieldValue.serverTimestamp();

  const completion = await db.runTransaction(async (transaction) => {
    const [userSnapshot, privateSnapshot, targetUsernameSnapshot] = await Promise.all([
      transaction.get(userRef),
      transaction.get(privateUserRef),
      transaction.get(targetUsernameRef),
    ]);

    const user = userSnapshot.data() ?? {};
    if (userSnapshot.exists) {
      assertAccountAvailable(
        user,
        "This account cannot complete onboarding right now.",
      );
      if (isPersistedCompletedAccount({uid, publicUser: user})) {
        return {
          username: normalizeUsername(
            asTrimmedString(user.usernameLowercase || user.username),
          ),
          status: "alreadyComplete" as const,
        };
      }
    }

    const currentUsername = normalizeUsername(
      asTrimmedString(user.usernameLowercase || user.username),
    );
    const currentPhotoUrl = asTrimmedString(user.photoUrl || user.profileImage);
    const currentBio = asTrimmedString(user.bio);

    const reservedUid = asTrimmedString(targetUsernameSnapshot.data()?.uid);
    if (targetUsernameSnapshot.exists && reservedUid && reservedUid !== uid) {
      throw new HttpsError("already-exists", "Username is already taken.", {
        appCode: "username-taken",
      });
    }

    if (currentUsername && currentUsername !== requestedUsername) {
      const previousUsernameRef = usernamesRef.doc(currentUsername);
      const previousUsernameSnapshot = await transaction.get(previousUsernameRef);
      if (asTrimmedString(previousUsernameSnapshot.data()?.uid) === uid) {
        transaction.delete(previousUsernameRef);
      }
    }

    transaction.set(targetUsernameRef, {
      uid,
      username: requestedUsername,
      usernameLowercase: requestedUsername,
      ...(targetUsernameSnapshot.exists ? {} : {createdAt: now}),
      updatedAt: now,
    }, {merge: true});

    transaction.set(userRef, {
      uid,
      role,
      displayName,
      name: displayName,
      username: requestedUsername,
      usernameLowercase: requestedUsername,
      state,
      city,
      photoUrl: currentPhotoUrl,
      profileImage: currentPhotoUrl,
      bio: currentBio,
      providers,
      ...(userSnapshot.exists ? {} : {createdAt: now}),
      updatedAt: now,
    }, {merge: true});

    const privateUser = privateSnapshot.data() ?? {};
    transaction.set(privateUserRef, {
      uid,
      email,
      phoneNumber,
      phone: phoneNumber,
      mobileNumber: phoneNumber,
      emailVerified,
      phoneVerified,
      providers,
      ...(!privateUser.createdAt ? {createdAt: now} : {}),
      ...(!privateUser.acceptedTermsAt && acceptedTerms ?
        {acceptedTermsAt: now} :
        {}),
      ...(!privateUser.acceptedPrivacyAt && acceptedPrivacy ?
        {acceptedPrivacyAt: now} :
        {}),
      ...(!privateUser.acceptedProviderAgreementAt && acceptedProviderAgreement ?
        {acceptedProviderAgreementAt: now} :
        {}),
      updatedAt: now,
    }, {merge: true});

    return {
      username: requestedUsername,
      status: "completed" as const,
    };
  });

  return {
    ok: true,
    uid,
    username: completion.username,
    status: completion.status,
  };
});

export const syncAuthIdentity = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const authUser = await getAuth().getUser(uid);
  const providers = providerIdsFromAuthUser(authUser);
  const email = asTrimmedString(authUser.email);
  const phoneNumber = asTrimmedString(authUser.phoneNumber);
  const emailVerified = authUser.emailVerified === true;
  const phoneVerified = phoneNumber.length > 0 && providers.includes("phone");
  const userRef = db.collection("users").doc(uid);
  const privateUserRef = db.collection("userPrivate").doc(uid);
  const [userSnapshot, privateUserSnapshot] = await Promise.all([
    userRef.get(),
    privateUserRef.get(),
  ]);
  const now = FieldValue.serverTimestamp();
  const batch = db.batch();

  batch.set(privateUserRef, {
    uid,
    email,
    phoneNumber,
    phone: phoneNumber,
    mobileNumber: phoneNumber,
    emailVerified,
    phoneVerified,
    providers,
    ...(privateUserSnapshot.exists ? {} : {createdAt: now}),
    updatedAt: now,
  }, {merge: true});

  if (userSnapshot.exists) {
    batch.set(userRef, {
      uid,
      providers,
      updatedAt: now,
    }, {merge: true});
  }

  await batch.commit();

  return {
    uid,
    email,
    phoneNumber,
    emailVerified,
    phoneVerified,
    providers,
    publicProfileExists: userSnapshot.exists,
  };
});

export const checkPhoneLoginEligibility = onCall(
  {
    invoker: "public",
    region: "asia-south1",
  },
  async (request) => {
    const normalizedPhoneNumber = normalizePhoneLoginNumber(
      request.data?.phoneNumber,
    );
    const maskedPhoneNumber = maskIdentifier(normalizedPhoneNumber, 4);
    console.info("Phone login eligibility request received", {
      maskedPhoneNumber,
      region: "asia-south1",
    });
    const validationError = validatePhoneLoginNumber(normalizedPhoneNumber);
    if (validationError) {
      throw new HttpsError("invalid-argument", validationError, {
        appCode: "invalid-phone",
      });
    }

    const phoneHash = phoneLoginEligibilityRequestHash(normalizedPhoneNumber);
    const rateLimitRef = db
      .collection("phoneLoginEligibilityChecks")
      .doc(phoneHash);
    const nowMs = Date.now();
    const rateLimitResult = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(rateLimitRef);
      const lastRequestedAtMs =
        asTimestamp(snapshot.data()?.lastRequestedAt)?.toMillis() ?? 0;
      if (lastRequestedAtMs > 0) {
        const elapsedMs = nowMs - lastRequestedAtMs;
        if (elapsedMs < phoneLoginEligibilityCooldownMs) {
          return {
            allowed: false,
            retryAfterMs: phoneLoginEligibilityCooldownMs - elapsedMs,
          };
        }
      }

      transaction.set(
        rateLimitRef,
        {
          lastRequestedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      return {allowed: true, retryAfterMs: 0};
    });

    if (!rateLimitResult.allowed) {
      console.info("Phone login eligibility rate limited", {
        phoneHashPrefix: phoneHash.slice(0, 12),
        retryAfterMs: rateLimitResult.retryAfterMs,
      });
      throw new HttpsError(
        "resource-exhausted",
        "Please wait before trying again.",
        {appCode: "rate-limited"},
      );
    }

    let authUser;
    try {
      authUser = await getAuth().getUserByPhoneNumber(normalizedPhoneNumber);
      console.info("Phone login auth lookup succeeded", {
        maskedPhoneNumber,
        authDisabled: authUser.disabled === true,
      });
    } catch (error) {
      const authError = error as {code?: string};
      if (authError.code === "auth/user-not-found") {
        console.info("Phone login auth lookup returned user-not-found", {
          maskedPhoneNumber,
          phoneHashPrefix: phoneHash.slice(0, 12),
        });
        const response = {
          exists: false,
          canLogin: false,
          reason: phoneLoginAppCodeForStatus("notFound"),
        };
        console.info("Phone login eligibility response", {
          maskedPhoneNumber,
          ...response,
        });
        return response;
      }
      console.error("Phone login lookup failed", {
        maskedPhoneNumber,
        phoneHashPrefix: phoneHash.slice(0, 12),
        errorCode: authError.code ?? "unknown",
      });
      throw new HttpsError("internal", "Unable to process this request right now.");
    }

    const publicUserRef = db.collection("users").doc(authUser.uid);
    const privateUserRef = db.collection("userPrivate").doc(authUser.uid);
    const [publicUserSnapshot, privateUserSnapshot] = await Promise.all([
      publicUserRef.get(),
      privateUserRef.get(),
    ]);
    const publicUser = publicUserSnapshot.data() ?? {};
    const privateUser = privateUserSnapshot.data() ?? {};
    const normalizedUsername = normalizeUsername(
      asTrimmedString(publicUser.usernameLowercase || publicUser.username),
    );
    const hasCompletedPublicProfile =
      publicUserSnapshot.exists &&
      asTrimmedString(publicUser.uid) === authUser.uid &&
      asTrimmedString(publicUser.role).length > 0 &&
      displayNameFromUser(publicUser, "").length > 0 &&
      asTrimmedString(publicUser.state).length > 0 &&
      asTrimmedString(publicUser.city).length > 0 &&
      validateNormalizedUsername(normalizedUsername) == null;
    const trustedAccountStatus = asTrimmedString(
      privateUser.accountStatus ?? publicUser.accountStatus,
    ) || "active";
    console.info("Phone login registration snapshot", {
      maskedPhoneNumber,
      usersExists: publicUserSnapshot.exists,
      userPrivateExists: privateUserSnapshot.exists,
      accountStatusPublic: asTrimmedString(publicUser.accountStatus) || "missing",
      accountStatusPrivate: asTrimmedString(privateUser.accountStatus) || "missing",
      trustedAccountStatus,
    });

    const eligibilityStatus = evaluatePhoneLoginEligibility({
      disabled: authUser.disabled === true,
      accountStatus: trustedAccountStatus,
      hasPublicProfile: publicUserSnapshot.exists,
      hasPrivateProfile: privateUserSnapshot.exists,
      hasCompletedPublicProfile,
    });
    const response = {
      exists: true,
      canLogin:
        eligibilityStatus === "active" || eligibilityStatus === "incompleteSignup",
      reason: phoneLoginAppCodeForStatus(eligibilityStatus),
    };
    console.info("Phone login eligibility response", {
      maskedPhoneNumber,
      ...response,
    });
    return response;
  },
);

export const requestPasswordReset = onCall(
  {
    invoker: "public",
    region: "asia-south1",
  },
  async (request) => {
    const normalizedEmail = normalizePasswordResetEmail(request.data?.email);
    const validationError = validatePasswordResetEmail(normalizedEmail);
    if (validationError) {
      throw new HttpsError("invalid-argument", validationError, {
        appCode: "invalid-email",
      });
    }

    const emailHash = passwordResetRequestHash(normalizedEmail);
    const rateLimitRef = db.collection("passwordResetRequests").doc(emailHash);
    const nowMs = Date.now();
    const rateLimitResult = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(rateLimitRef);
      const lastRequestedAtMs =
        asTimestamp(snapshot.data()?.lastRequestedAt)?.toMillis() ?? 0;
      if (lastRequestedAtMs > 0) {
        const elapsedMs = nowMs - lastRequestedAtMs;
        if (elapsedMs < passwordResetRequestCooldownMs) {
          return {
            allowed: false,
            retryAfterMs: passwordResetRequestCooldownMs - elapsedMs,
          };
        }
      }

      transaction.set(rateLimitRef, {
        lastRequestedAt: Timestamp.fromMillis(nowMs),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      return {allowed: true, retryAfterMs: 0};
    });

    if (!rateLimitResult.allowed) {
      console.info("Password reset rejected due to cooldown", {
        emailHashPrefix: emailHash.slice(0, 12),
        retryAfterMs: rateLimitResult.retryAfterMs,
      });
      throw new HttpsError(
        "resource-exhausted",
        "Please wait before requesting another reset email.",
        {appCode: "rate-limited"},
      );
    }

    let authUser;
    try {
      authUser = await getAuth().getUserByEmail(normalizedEmail);
    } catch (error) {
      const authError = error as {code?: string};
      if (authError.code === "auth/user-not-found") {
        console.info("Password reset rejected because auth account was missing", {
          emailHashPrefix: emailHash.slice(0, 12),
        });
        throw new HttpsError(
          "not-found",
          "No password-enabled account found.",
          {appCode: "account-not-found"},
        );
      }
      console.error("Password reset lookup failed", {
        emailHashPrefix: emailHash.slice(0, 12),
        errorCode: authError.code ?? "unknown",
      });
      throw new HttpsError("internal", "Unable to process this request right now.");
    }

    const [privateUserSnapshot, publicUserSnapshot] = await Promise.all([
      db.collection("userPrivate").doc(authUser.uid).get(),
      db.collection("users").doc(authUser.uid).get(),
    ]);
    const trustedAccountStatus = asTrimmedString(
      privateUserSnapshot.data()?.accountStatus ??
        publicUserSnapshot.data()?.accountStatus,
    );
    const eligibilityStatus = evaluatePasswordResetEligibility({
      providerIds: providerIdsFromAuthUser(authUser),
      disabled: authUser.disabled === true,
      accountStatus: trustedAccountStatus,
    });

    if (eligibilityStatus !== "approved") {
      console.info("Password reset rejected", {
        emailHashPrefix: emailHash.slice(0, 12),
        eligibilityStatus,
      });
      throw new HttpsError(
        "failed-precondition",
        "This account cannot use password reset.",
        {appCode: passwordResetAppCodeForStatus(eligibilityStatus)},
      );
    }

    console.info("Password reset approved", {
      emailHashPrefix: emailHash.slice(0, 12),
    });
    return {status: "approved"};
  },
);

export const sendPushForNotification = onDocumentWritten(
  {
    document: "notifications/{notificationId}",
  },
  async (event) => {
    const notification = event.data?.after.data();
    if (!notification) return;
    const previousNotification = event.data?.before.data();

    const userId = String(notification.userId ?? "");
    const recipientId = String(notification.recipientId ?? notification.userId ?? "");
    const senderId = String(notification.senderId ?? notification.actorId ?? "");
    const bookingId = String(notification.bookingId ?? "");
    const postId = String(notification.postId ?? "");
    const chatId = String(notification.chatId ?? "");
    const category = String(notification.category ?? "");
    const notificationType = normalizedNotificationType(notification.type, category);
    const currentLastMessageId = String(notification.lastMessageId ?? "");
    const previousLastMessageId = String(previousNotification?.lastMessageId ?? "");

    if (previousNotification) {
      const isChatNotification = category === "chat" || notificationType === "chat";
      const shouldSendChatUpdate = isChatNotification &&
        currentLastMessageId.length > 0 &&
        currentLastMessageId !== previousLastMessageId;
      if (!shouldSendChatUpdate) {
        console.info("Notification skipped", {
          notificationId: event.params.notificationId,
          reason: "non-push-notification-update",
          recipientUserId: recipientId,
          senderUserId: senderId,
          chatId,
          notificationType,
          tokenCount: 0,
        });
        return;
      }
    }

    if (!userId || !recipientId) {
      console.info("Notification skipped", {
        notificationId: event.params.notificationId,
        reason: "missing-recipient",
        recipientUserId: recipientId,
        senderUserId: senderId,
        chatId,
        notificationType,
        tokenCount: 0,
      });
      return;
    }
    if (!notificationDeliversPush(notification.channels)) {
      console.info("Notification skipped", {
        notificationId: event.params.notificationId,
        reason: "push-channel-disabled",
        recipientUserId: recipientId,
        senderUserId: senderId,
        chatId,
        notificationType,
        tokenCount: 0,
      });
      return;
    }
    if (senderId && senderId === recipientId) {
      console.info("Notification skipped", {
        notificationId: event.params.notificationId,
        reason: "self-notification",
        recipientUserId: recipientId,
        senderUserId: senderId,
        chatId,
        notificationType,
        tokenCount: 0,
      });
      return;
    }

    const recipientSnapshot = await db.collection("users").doc(userId).get();
    const recipientData = recipientSnapshot.data() ?? {};
    if (!userAllowsNotification(recipientData, category)) {
      console.info("Notification skipped", {
        notificationId: event.params.notificationId,
        reason: "recipient-notifications-disabled",
        recipientUserId: recipientId,
        senderUserId: senderId,
        chatId,
        notificationType,
        tokenCount: 0,
      });
      return;
    }

    const tokenSnapshot = await db
      .collection("users")
      .doc(userId)
      .collection("notificationTokens")
      .where("disabled", "!=", true)
      .get();

    const senderTokenSnapshot = senderId ?
      await db
        .collection("users")
        .doc(senderId)
        .collection("notificationTokens")
        .where("disabled", "!=", true)
        .get() :
      null;
    const senderTokens = new Set(
      (senderTokenSnapshot?.docs ?? [])
        .map((doc) => String(doc.data().token ?? ""))
        .filter((token) => token.length > 0),
    );

    const skippedSenderTokens: string[] = [];
    const skippedStaleTokens: string[] = [];
    const seenRecipientTokens = new Set<string>();
    const tokenDocs = tokenSnapshot.docs.filter((doc) => {
      const token = String(doc.data().token ?? "");
      if (!token.length) {
        skippedStaleTokens.push(doc.id);
        return false;
      }
      if (seenRecipientTokens.has(token)) {
        skippedStaleTokens.push(token);
        return false;
      }
      if (senderTokens.has(token)) {
        skippedSenderTokens.push(token);
        return false;
      }
      seenRecipientTokens.add(token);
      return true;
    });
    const tokens = tokenDocs.map((doc) => String(doc.data().token));
    if (tokens.length === 0) {
      console.info("Notification skipped", {
        notificationId: event.params.notificationId,
        reason: "no-active-tokens",
        recipientUserId: recipientId,
        senderUserId: senderId,
        chatId,
        notificationType,
        tokenCount: 0,
        skippedSenderTokenCount: skippedSenderTokens.length,
        skippedStaleTokenCount: skippedStaleTokens.length,
      });
      return;
    }

    const rawData = notification.data;
    const notificationPayload =
      rawData && typeof rawData === "object" && !Array.isArray(rawData) ?
        rawData as Record<string, unknown> :
        {};
    const data = notificationData({
      ...notificationPayload,
      notificationId: event.params.notificationId,
      recipientId,
      senderId,
      bookingId,
      postId,
      chatId,
      serviceId: notification.serviceId ?? "",
      senderName: notification.senderName ?? notification.title ?? "",
      type: notificationType,
      category: category || "booking",
      recipientRole: notification.recipientRole ?? "",
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    });
    const routing = resolvePushRouting(notificationType);
    const selectedChannelId = routing.channelId;
    const selectedCategoryName = routing.categoryName;
    const emojiUsed = routing.emoji;
    const pushTitle = ensureSingleLeadingEmoji(
      safeText(notification.title, "Pettxo booking update"),
      emojiUsed,
    );
    const pushBody = safeText(notification.body, "You have a new booking update.");

    console.info("Notification created", {
      notificationId: event.params.notificationId,
      recipientId,
      senderId,
      notificationType,
      selectedCategoryName,
      selectedChannelId,
      emojiUsed,
      chatId,
      tokenCount: tokens.length,
      skippedSenderTokenCount: skippedSenderTokens.length,
      skippedStaleTokenCount: skippedStaleTokens.length,
    });

    const response = await messaging.sendEachForMulticast(defaultPushPayload({
      tokens,
      title: pushTitle,
      body: pushBody,
      data,
      channelId: selectedChannelId,
    }));

    const cleanupBatch = db.batch();
    let cleanupCount = 0;
    const failureCodes = new Set<string>();
    response.responses.forEach((result, index) => {
      const code = result.error?.code;
      if (!result.success) {
        if (code) {
          failureCodes.add(code);
        }
        console.warn("Push delivery failed", {
          notificationId: event.params.notificationId,
          recipientId,
          senderId,
          notificationType,
          selectedCategoryName,
          selectedChannelId,
          emojiUsed,
          chatId,
          tokenCount: tokens.length,
          skippedSenderTokenCount: skippedSenderTokens.length,
          skippedStaleTokenCount: skippedStaleTokens.length,
          tokenDocIdMasked: maskIdentifier(tokenDocs[index]?.id ?? ""),
          fcmErrorCode: code ?? "unknown",
          message: result.error?.message ?? "",
        });
      }
      if (!isInvalidMessagingToken(code)) return;
      cleanupBatch.set(tokenDocs[index].ref, {
        disabled: true,
        disabledAt: FieldValue.serverTimestamp(),
        errorCode: code,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      cleanupCount += 1;
    });

    if (cleanupCount > 0) {
      console.info("Disabled invalid notification tokens", {
        notificationId: event.params.notificationId,
        cleanupCount,
      });
      await cleanupBatch.commit();
    }

    console.info("Push delivery completed", {
      notificationId: event.params.notificationId,
      recipientId,
      senderId,
      notificationType,
      selectedCategoryName,
      selectedChannelId,
      emojiUsed,
      chatId,
      tokenCount: tokens.length,
      successCount: response.successCount,
      failureCount: response.failureCount,
      fcmErrorCodes: Array.from(failureCodes),
      skippedSenderTokenCount: skippedSenderTokens.length,
      skippedStaleTokenCount: skippedStaleTokens.length,
    });
  },
);

export const enqueueServiceModeration = onDocumentCreated(
  {
    document: "services/{serviceId}",
  },
  async (event) => {
    const serviceId = event.params.serviceId;
    const service = event.data?.data();
    if (!service) return;

    await db.collection("moderationQueue").add({
      targetType: "service",
      targetId: serviceId,
      targetOwnerId: service.ownerUserId ?? "",
      source: "system",
      reportId: "",
      severity: "low",
      status: "pending",
      reason: "New service listing pending review",
      assignedAdminId: "",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  },
);

export const syncServiceSlots = onDocumentWritten(
  {
    document: "services/{serviceId}",
    timeoutSeconds: 120,
    memory: "512MiB",
  },
  async (event) => {
    const serviceId = event.params.serviceId;
    const after = event.data?.after.data();
    if (!after) return;

    const before = event.data?.before.data();
    if (!serviceSlotConfigChanged(before, after)) return;

    await regenerateServiceSlots(serviceId, after);
  },
);

export const pauseServicesForExpiredProviderVerification = onSchedule(
  {
    schedule: "every 60 minutes",
    timeZone: "Asia/Kolkata",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
    const now = Timestamp.now();
    const snapshot = await db
      .collectionGroup("providerVerification")
      .where("gracePeriodEndsAt", "<=", now)
      .get();

    for (const doc of snapshot.docs) {
      const userId = doc.ref.parent.parent?.id;
      if (!userId) continue;
      const verification = normalizeProviderVerification(doc.data());
      if (!shouldPauseServicesForVerification(verification, now)) continue;
      await updateProviderServicesForVerification(userId, verification);
    }
  },
);

export const syncProviderServicesOnVerificationUpdate = onDocumentWritten(
  {
    document: "users/{userId}/providerVerification/main",
    timeoutSeconds: 180,
    memory: "512MiB",
  },
  async (event) => {
    const after = event.data?.after.data();
    if (!after) return;

    const before = event.data?.before.data();
    const beforeVerification = normalizeProviderVerification(before);
    const afterVerification = normalizeProviderVerification(after);

    const verificationStateChanged =
      beforeVerification.status !== afterVerification.status ||
      beforeVerification.gracePeriodEndsAt?.toMillis() !==
        afterVerification.gracePeriodEndsAt?.toMillis();
    const documentPathChanged =
      beforeVerification.documentFrontPath !== afterVerification.documentFrontPath ||
      beforeVerification.documentBackPath !== afterVerification.documentBackPath;

    if (verificationStateChanged) {
      await updateProviderServicesForVerification(
        event.params.userId,
        afterVerification,
      );
    }

    if (documentPathChanged &&
      (beforeVerification.status === "pending" || beforeVerification.status === "rejected") &&
      afterVerification.status === "pending") {
      const replacedPaths = diffProviderVerificationDocumentPaths(
        providerVerificationDocumentPaths(beforeVerification),
        providerVerificationDocumentPaths(afterVerification),
      );
      if (replacedPaths.length > 0) {
        await enqueueProviderVerificationDocumentCleanup({
          userId: event.params.userId,
          verificationId: "main",
          storagePaths: replacedPaths,
          reason: "resubmitted",
          scheduledDeletionAtMs:
            calculateProviderVerificationDocumentDeletionAtMillis(Date.now()),
        });
      }
    }

    const reviewCleanupReason =
      beforeVerification.status !== afterVerification.status ?
        cleanupReasonForVerificationStatus(afterVerification.status) :
        null;
    const activePaths = providerVerificationDocumentPaths(afterVerification);
    if (reviewCleanupReason &&
      activePaths.length > 0 &&
      afterVerification.documentDeletionScheduledAt == null &&
      afterVerification.documentDeletedAt == null) {
      const scheduledDeletionAtMs =
        calculateProviderVerificationDocumentDeletionAtMillis(Date.now());
      await enqueueProviderVerificationDocumentCleanup({
        userId: event.params.userId,
        verificationId: "main",
        storagePaths: activePaths,
        reason: reviewCleanupReason,
        scheduledDeletionAtMs,
      });
      await event.data?.after.ref.set({
        documentDeletionScheduledAt: Timestamp.fromMillis(scheduledDeletionAtMs),
        documentDeletedAt: null,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  },
);

export const processProviderVerificationDocumentCleanup = onSchedule(
  {
    schedule: "every 12 hours",
    timeZone: "Asia/Kolkata",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
    const now = Timestamp.now();
    const snapshot = await db
      .collection("verificationDocumentCleanup")
      .where("scheduledDeletionAt", "<=", now)
      .orderBy("scheduledDeletionAt")
      .limit(providerVerificationCleanupBatchLimit * 3)
      .get();

    for (const doc of snapshot.docs) {
      const job = await claimProviderVerificationCleanupJob(doc.ref, now);
      if (!job) continue;

      const userId = asTrimmedString(job.userId);
      const verificationId = asTrimmedString(job.verificationId) || "main";
      const storagePaths = collectProviderVerificationDocumentPaths(
        Array.isArray(job.storagePaths) ? job.storagePaths : [],
      );
      const invalidPath = storagePaths.find(
        (path) => !providerVerificationDocumentPathBelongsToUser(userId, path),
      );

      if (!userId || storagePaths.length === 0 || invalidPath) {
        await markProviderVerificationCleanupFailed(
          doc.ref,
          invalidPath ?
            `invalid-storage-path:${invalidPath}` :
            "missing-user-or-storage-paths",
        );
        continue;
      }

      try {
        for (const path of storagePaths) {
          await storage.bucket().file(path).delete({ignoreNotFound: true});
        }
        await markProviderVerificationCleanupCompleted({
          ref: doc.ref,
          userId,
          verificationId,
          storagePaths,
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        console.error("Provider verification cleanup failed", {
          cleanupId: doc.id,
          userId,
          verificationId,
          message,
        });
        await markProviderVerificationCleanupRetryable(doc.ref, message);
      }
    }
  },
);

export const enqueueReportModeration = onDocumentCreated(
  {
    document: "reports/{reportId}",
  },
  async (event) => {
    const reportId = event.params.reportId;
    const report = event.data?.data();
    if (!report) return;

    await db.collection("moderationQueue").add({
      targetType: report.targetType ?? "",
      targetId: report.targetId ?? "",
      targetOwnerId: report.targetOwnerId ?? "",
      source: "report",
      reportId,
      severity: "medium",
      status: "pending",
      reason: report.reason ?? "User report",
      assignedAdminId: "",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  },
);


export const moderateService = onCall(async (request) => {
  requireAdmin(request.auth);
  const adminUid = request.auth!.uid;
  const serviceId = String(request.data?.serviceId ?? "");
  const moderationItemId = String(request.data?.moderationItemId ?? "");
  const action = String(request.data?.action ?? "");
  const reason = String(request.data?.reason ?? "");

  if (!serviceId || !action) {
    throw new HttpsError("invalid-argument", "serviceId and action are required.");
  }

  const serviceRef = db.collection("services").doc(serviceId);
  const auditRef = db.collection("adminAuditLogs").doc();
  const queueRef = moderationItemId
    ? db.collection("moderationQueue").doc(moderationItemId)
    : null;

  const isApproved = action === "approve";
  const servicePatch = isApproved
    ? {
        moderationStatus: "approved",
        isVisibleToMarketplace: true,
        updatedAt: FieldValue.serverTimestamp(),
      }
    : {
        moderationStatus: "removed",
        moderationReason: reason,
        isVisibleToMarketplace: false,
        isActive: false,
        status: "removed",
        updatedAt: FieldValue.serverTimestamp(),
        removedAt: FieldValue.serverTimestamp(),
      };

  const batch = db.batch();
  batch.set(serviceRef, servicePatch, {merge: true});
  if (queueRef) {
    batch.set(queueRef, {
      status: isApproved ? "approved" : "removed",
      assignedAdminId: adminUid,
      reason,
      updatedAt: FieldValue.serverTimestamp(),
      resolvedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  batch.set(auditRef, {
    adminId: adminUid,
    action: isApproved ? "service.approve" : "service.remove",
    targetType: "service",
    targetId: serviceId,
    reason,
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();

  return {ok: true};
});

export const applyUserRestriction = onCall(async (request) => {
  const adminUid = requireUid(request.auth);
  const admin = await requireAdminActor(adminUid);
  const userId = asTrimmedString(request.data?.userId);
  const type = asTrimmedString(request.data?.type);
  const reason = asTrimmedString(request.data?.reason);

  if (!userId || !type || !reason) {
    throw new HttpsError("invalid-argument", "userId, type, and reason are required.");
  }
  if (!isRestrictionType(type)) {
    throw new HttpsError("invalid-argument", "Restriction type must be social, booking, or hard.");
  }
  assertRestrictionPermission(admin.role, type);
  if (type === "hard" && userId === adminUid) {
    throw new HttpsError("failed-precondition", "You cannot apply a hard restriction to yourself.");
  }

  const userRef = db.collection("users").doc(userId);
  const userSnapshot = await userRef.get();
  if (!userSnapshot.exists) {
    throw new HttpsError("not-found", "User document not found.");
  }

  const auth = getAuth();
  let previousAuthDisabled: boolean | null = null;
  if (type === "hard") {
    const authUser = await auth.getUser(userId);
    previousAuthDisabled = authUser.disabled;
    if (!previousAuthDisabled) {
      await auth.updateUser(userId, {disabled: true});
    }
  }

  try {
    const result = await db.runTransaction(async (transaction) => {
      const freshSnapshot = await transaction.get(userRef);
      if (!freshSnapshot.exists) {
        throw new HttpsError("not-found", "User document not found.");
      }

      const data = freshSnapshot.data() ?? {};
      const restrictions = normalizeRestrictions(data.restrictions);
      const previousAccountStatus = asTrimmedString(data.accountStatus) || computeAccountStatus(restrictions);
      const updatedRestrictions = nextRestrictions(restrictions, type, true, reason, admin.uid);
      const newAccountStatus = computeAccountStatus(updatedRestrictions);
      const auditRef = db.collection("adminAuditLogs").doc();

      transaction.set(userRef, {
        ...buildRestrictionPatch(type, true, reason, admin.uid),
        accountStatus: newAccountStatus,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});

      transaction.set(auditRef, {
        action: "applyUserRestriction",
        targetUserId: userId,
        restrictionType: type,
        reason,
        performedBy: admin.uid,
        performedByRole: admin.role,
        createdAt: FieldValue.serverTimestamp(),
        metadata: {
          previousAccountStatus,
          newAccountStatus,
        },
      });

      return {newAccountStatus};
    });

    return {ok: true, accountStatus: result.newAccountStatus};
  } catch (error) {
    if (type === "hard" && previousAuthDisabled === false) {
      await auth.updateUser(userId, {disabled: false});
    }
    throw error;
  }
});

export const removeUserRestriction = onCall(async (request) => {
  const adminUid = requireUid(request.auth);
  const admin = await requireAdminActor(adminUid);
  const userId = asTrimmedString(request.data?.userId);
  const type = asTrimmedString(request.data?.type);
  const reason = asTrimmedString(request.data?.reason);

  if (!userId || !type) {
    throw new HttpsError("invalid-argument", "userId and type are required.");
  }
  if (!isRestrictionType(type)) {
    throw new HttpsError("invalid-argument", "Restriction type must be social, booking, or hard.");
  }
  assertRestrictionPermission(admin.role, type);

  const userRef = db.collection("users").doc(userId);
  const userSnapshot = await userRef.get();
  if (!userSnapshot.exists) {
    throw new HttpsError("not-found", "User document not found.");
  }

  const auth = getAuth();
  let previousAuthDisabled: boolean | null = null;
  if (type === "hard") {
    const authUser = await auth.getUser(userId);
    previousAuthDisabled = authUser.disabled;
    if (previousAuthDisabled) {
      await auth.updateUser(userId, {disabled: false});
    }
  }

  try {
    const result = await db.runTransaction(async (transaction) => {
      const freshSnapshot = await transaction.get(userRef);
      if (!freshSnapshot.exists) {
        throw new HttpsError("not-found", "User document not found.");
      }

      const data = freshSnapshot.data() ?? {};
      const restrictions = normalizeRestrictions(data.restrictions);
      const previousAccountStatus = asTrimmedString(data.accountStatus) || computeAccountStatus(restrictions);
      const updatedRestrictions = nextRestrictions(restrictions, type, false, "", admin.uid);
      const newAccountStatus = computeAccountStatus(updatedRestrictions);
      const auditRef = db.collection("adminAuditLogs").doc();

      transaction.set(userRef, {
        ...buildRestrictionPatch(type, false, "", admin.uid),
        accountStatus: newAccountStatus,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});

      transaction.set(auditRef, {
        action: "removeUserRestriction",
        targetUserId: userId,
        restrictionType: type,
        reason,
        performedBy: admin.uid,
        performedByRole: admin.role,
        createdAt: FieldValue.serverTimestamp(),
        metadata: {
          previousAccountStatus,
          newAccountStatus,
        },
      });

      return {newAccountStatus};
    });

    return {ok: true, accountStatus: result.newAccountStatus};
  } catch (error) {
    if (type === "hard" && previousAuthDisabled === true) {
      await auth.updateUser(userId, {disabled: true});
    }
    throw error;
  }
});

export const createOfferCampaign = onCall(async (request) => {
  const adminUid = requireUid(request.auth);
  const admin = await requireAdminActor(adminUid);
  assertOfferMutationPermission(admin.role);

  const mutation = sanitizeOfferCampaignMutationInput({
    rawData: request.data,
    requireCampaignId: false,
  });
  const normalized = normalizeOfferPayload({
    ...mutation.payload,
    displayType: "offerWall",
  }, {requireAllFields: true});

  const campaignRef = db.collection("offerCampaigns").doc();
  const batch = db.batch();
  batch.set(campaignRef, {
    ...normalized,
    displayType: "offerWall",
    isActive: asBoolean(mutation.payload.isActive, false),
    isDeleted: false,
    createdAt: FieldValue.serverTimestamp(),
    createdBy: admin.uid,
    createdByRole: admin.role,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: admin.uid,
    updatedByRole: admin.role,
  });
  writeOfferAuditLog(batch, admin, "offerCampaign.create", campaignRef.id, {
    couponCode: normalized.couponCode,
    campaignType: normalized.campaignType,
    ignoredLegacyFields: mutation.ignoredLegacyFields,
  });
  await batch.commit();

  return {ok: true, campaignId: campaignRef.id};
});

export const updateOfferCampaign = onCall(async (request) => {
  const adminUid = requireUid(request.auth);
  const admin = await requireAdminActor(adminUid);
  assertOfferMutationPermission(admin.role);

  const mutation = sanitizeOfferCampaignMutationInput({
    rawData: request.data,
    requireCampaignId: true,
  });
  if (Object.keys(mutation.payload).length === 0) {
    throw new HttpsError("invalid-argument", "At least one offer field must be provided.");
  }

  const campaignId = mutation.campaignId;
  const campaignRef = db.collection("offerCampaigns").doc(campaignId);
  const snapshot = await campaignRef.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Offer campaign not found.");
  }

  const existingData = snapshot.data() ?? {};
  if (existingData.isDeleted === true) {
    throw new HttpsError(
      "failed-precondition",
      "Deleted offer campaigns cannot be edited.",
    );
  }
  const mergedData: Record<string, unknown> = {
    ...existingData,
    ...mutation.payload,
    displayType: asTrimmedString(existingData.displayType) || "offerWall",
    targeting: mutation.payload.targeting === undefined ?
      existingData.targeting :
      {...asRecord(existingData.targeting), ...asRecord(mutation.payload.targeting)},
  };
  const normalized = normalizeOfferPayload(mergedData, {requireAllFields: true});

  const batch = db.batch();
  batch.set(campaignRef, {
    ...normalized,
    displayType: asTrimmedString(existingData.displayType) || "offerWall",
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: admin.uid,
    updatedByRole: admin.role,
  }, {merge: true});
  writeOfferAuditLog(batch, admin, "offerCampaign.update", campaignId, {
    updatedFields: Object.keys(mutation.payload),
    ignoredLegacyFields: mutation.ignoredLegacyFields,
    usedLegacyIdentityAlias: mutation.usedLegacyIdentityAlias,
  });
  await batch.commit();

  return {ok: true, campaignId};
});

export const setOfferCampaignStatus = onCall(async (request) => {
  const adminUid = requireUid(request.auth);
  const admin = await requireAdminActor(adminUid);
  assertOfferMutationPermission(admin.role);

  const data = asRecord(request.data);
  const campaignId = asTrimmedString(data.campaignId);
  if (!campaignId) {
    throw new HttpsError("invalid-argument", "campaignId is required.");
  }
  assertAllowedOfferKeys(data, ["campaignId", "isActive"]);
  if (typeof data.isActive !== "boolean") {
    throw new HttpsError("invalid-argument", "isActive must be true or false.");
  }

  const campaignRef = db.collection("offerCampaigns").doc(campaignId);
  const snapshot = await campaignRef.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Offer campaign not found.");
  }
  if (snapshot.data()?.isDeleted === true) {
    throw new HttpsError(
      "failed-precondition",
      "Deleted offer campaigns cannot be reactivated or paused.",
    );
  }

  const isActive = data.isActive;
  const batch = db.batch();
  batch.set(campaignRef, {
    isActive,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: admin.uid,
    updatedByRole: admin.role,
  }, {merge: true});
  writeOfferAuditLog(
    batch,
    admin,
    isActive ? "offerCampaign.activate" : "offerCampaign.pause",
    campaignId,
    {isActive},
  );
  await batch.commit();

  return {ok: true, campaignId, isActive};
});

export const deleteOfferCampaign = onCall(async (request) => {
  const adminUid = requireUid(request.auth);
  const admin = await requireAdminActor(adminUid);
  assertOfferMutationPermission(admin.role);

  const data = asRecord(request.data);
  assertAllowedOfferKeys(data, ["campaignId"]);
  const campaignId = asTrimmedString(data.campaignId);
  if (!campaignId) {
    throw new HttpsError("invalid-argument", "campaignId is required.");
  }

  const campaignRef = db.collection("offerCampaigns").doc(campaignId);
  const snapshot = await campaignRef.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Offer campaign not found.");
  }

  const batch = db.batch();
  batch.set(campaignRef, {
    isActive: false,
    isDeleted: true,
    deletedAt: FieldValue.serverTimestamp(),
    deletedBy: admin.uid,
    deletedByRole: admin.role,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: admin.uid,
    updatedByRole: admin.role,
  }, {merge: true});
  writeOfferAuditLog(batch, admin, "offerCampaign.delete", campaignId, {});
  await batch.commit();

  return {ok: true, campaignId, isDeleted: true};
});

function readCountValue(data: DocumentData | undefined, key: string): number {
  const value = data?.[key];
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

async function applyUserFollowCountDelta(
  userId: string,
  {
    followerDelta = 0,
    followingDelta = 0,
  }: {
    followerDelta?: number;
    followingDelta?: number;
  },
): Promise<void> {
  const trimmedUserId = userId.trim();
  if (!trimmedUserId || (followerDelta === 0 && followingDelta === 0)) {
    return;
  }

  const userRef = db.collection("users").doc(trimmedUserId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(userRef);
    if (!snapshot.exists) return;

    const data = snapshot.data();
    const nextFollowerCount = Math.max(
      0,
      readCountValue(data, "followerCount") + followerDelta,
    );
    const nextFollowingCount = Math.max(
      0,
      readCountValue(data, "followingCount") + followingDelta,
    );

    transaction.set(userRef, {
      followerCount: nextFollowerCount,
      followingCount: nextFollowingCount,
    }, {merge: true});
  });
}

export const syncProfileFollowCounts = onDocumentWritten(
  "follows/{followId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!before && !after) return;
    if (before && after) return;

    const source = after ?? before;
    const followerId = String(source?.followerId ?? "").trim();
    const followeeId = String(source?.followeeId ?? "").trim();
    if (!followerId || !followeeId || followerId === followeeId) return;

    const delta = after ? 1 : -1;
    await Promise.all([
      applyUserFollowCountDelta(followerId, {followingDelta: delta}),
      applyUserFollowCountDelta(followeeId, {followerDelta: delta}),
    ]);
  },
);

export const getProfileFollowCounts = onCall({invoker: "public"}, async (request) => {
  requireUid(request.auth);

  const payload = (request.data ?? {}) as Record<string, unknown>;
  const userId = asTrimmedString(payload.userId);
  if (!userId) {
    throw new HttpsError("invalid-argument", "User id is required.");
  }

  const [followerAggregate, followingAggregate] = await Promise.all([
    db.collection("follows").where("followeeId", "==", userId).count().get(),
    db.collection("follows").where("followerId", "==", userId).count().get(),
  ]);

  return {
    userId,
    followerCount: followerAggregate.data().count,
    followingCount: followingAggregate.data().count,
  };
});

export const createSocialNotification = onCall({
  invoker: "public",
}, async (request) => {
  const senderId = request.auth?.uid ?? "";
  if (!senderId) {
    throw new HttpsError("unauthenticated", "Sign in to continue.");
  }

  const payload = (request.data ?? {}) as Record<string, unknown>;
  const type = String(payload.type ?? "").trim() as SocialNotificationType;
  const recipientId = String(payload.recipientId ?? "").trim();
  const postId = String(payload.postId ?? "").trim();
  const commentId = String(payload.commentId ?? "").trim();

  if (!socialNotificationTypes.includes(type)) {
    throw new HttpsError("invalid-argument", "Notification type is invalid.");
  }
  if (!recipientId || recipientId === senderId) {
    return {ok: true, created: false};
  }

  const senderSnapshot = await db.collection("users").doc(senderId).get();
  if (!senderSnapshot.exists) {
    throw new HttpsError("failed-precondition", "Sender profile not found.");
  }
  const senderData = senderSnapshot.data() ?? {};
  assertAccountAvailable(
    senderData,
    "Your account is pending deletion and cannot create social activity.",
  );
  const senderDisplayName = displayNameFromUser(senderData, "Someone");
  const senderPhotoUrl = photoUrlFromUser(senderData);

  if (type === "socialFollow") {
    const followId = `${senderId}_${recipientId}`;
    const followSnapshot = await db.collection("follows").doc(followId).get();
    if (!followSnapshot.exists) {
      throw new HttpsError("failed-precondition", "Follow relationship not found.");
    }

    await createSocialNotificationDoc({
      recipientId,
      senderId,
      senderDisplayName,
      senderPhotoUrl,
      type,
      title: `${senderDisplayName} followed you`,
      body: "See what they are sharing on Pettxo.",
    });
    return {ok: true, created: true};
  }

  if (!postId) {
    throw new HttpsError("invalid-argument", "Post id is required.");
  }

  const postSnapshot = await db.collection("socialPosts").doc(postId).get();
  if (!postSnapshot.exists) {
    throw new HttpsError("failed-precondition", "Post not found.");
  }
  const postData = postSnapshot.data() ?? {};
  const postAuthorId = String(postData.authorId ?? "").trim();
  if (!postAuthorId || postAuthorId !== recipientId) {
    throw new HttpsError("failed-precondition", "Recipient does not match post author.");
  }

  if (type === "socialLike") {
    const likeSnapshot = await db
      .collection("socialPosts")
      .doc(postId)
      .collection("likes")
      .doc(senderId)
      .get();
    if (!likeSnapshot.exists) {
      throw new HttpsError("failed-precondition", "Like not found.");
    }

    await createSocialNotificationDoc({
      recipientId,
      senderId,
      senderDisplayName,
      senderPhotoUrl,
      type,
      title: `${senderDisplayName} liked your post`,
      body: "Tap to see the post in your feed.",
      postId,
    });
    return {ok: true, created: true};
  }

  if (!commentId) {
    throw new HttpsError("invalid-argument", "Comment id is required.");
  }

  const commentSnapshot = await db
    .collection("socialPosts")
    .doc(postId)
    .collection("comments")
    .doc(commentId)
    .get();
  if (!commentSnapshot.exists) {
    throw new HttpsError("failed-precondition", "Comment not found.");
  }
  const commentData = commentSnapshot.data() ?? {};
  if (String(commentData.authorId ?? "").trim() !== senderId) {
    throw new HttpsError("failed-precondition", "Comment author does not match sender.");
  }

  await createSocialNotificationDoc({
    recipientId,
    senderId,
    senderDisplayName,
    senderPhotoUrl,
    type,
    title: `${senderDisplayName} commented on your post`,
    body: safeText(commentData.text, "Tap to see the conversation."),
    postId,
    commentId,
  });
  return {ok: true, created: true};
});

export const startProviderChat = onCall({
  invoker: "public",
}, async (request) => {
  const customerId = requireUid(request.auth);
  const serviceId = asTrimmedString(request.data?.serviceId);

  if (!serviceId) {
    throw new HttpsError("invalid-argument", "serviceId is required.");
  }

  const serviceRef = db.collection("services").doc(serviceId);
  const serviceSnapshot = await serviceRef.get();
  if (!serviceSnapshot.exists) {
    throw new HttpsError("not-found", "Service not found.");
  }

  const service = serviceSnapshot.data() ?? {};
  const providerId = asTrimmedString(service.ownerUserId);
  if (!providerId) {
    throw new HttpsError("failed-precondition", "Service owner is missing.");
  }
  if (providerId === customerId) {
    throw new HttpsError("failed-precondition", "You cannot message yourself.");
  }
  if (!isChatEligibleService(service)) {
    throw new HttpsError("failed-precondition", "This service is not available for chat.");
  }

  const canonicalChatId = canonicalChatIdForPair(customerId, providerId);
  const legacyChatRefs = legacyChatIdsForPair(customerId, providerId)
    .filter((chatId) => chatId !== canonicalChatId)
    .map((chatId) => db.collection("chats").doc(chatId));
  const canonicalChatRef = db.collection("chats").doc(canonicalChatId);
  const [canonicalBefore, ...legacySnapshots] = await Promise.all([
    canonicalChatRef.get(),
    ...legacyChatRefs.map((ref) => ref.get()),
  ]);

  const result = await db.runTransaction(async (transaction) => {
    const serviceSnapshot = await transaction.get(serviceRef);
    if (!serviceSnapshot.exists) {
      throw new HttpsError("not-found", "Service not found.");
    }

    const service = serviceSnapshot.data() ?? {};
    const providerId = asTrimmedString(service.ownerUserId);
    if (!providerId) {
      throw new HttpsError("failed-precondition", "Service owner is missing.");
    }
    if (providerId === customerId) {
      throw new HttpsError("failed-precondition", "You cannot message yourself.");
    }
    if (!isChatEligibleService(service)) {
      throw new HttpsError("failed-precondition", "This service is not available for chat.");
    }

    const customerRef = db.collection("users").doc(customerId);
    const providerRef = db.collection("users").doc(providerId);
    const customerSnapshot = await transaction.get(customerRef);
    const providerSnapshot = await transaction.get(providerRef);

    if (!customerSnapshot.exists || !providerSnapshot.exists) {
      throw new HttpsError("failed-precondition", "User profile not found.");
    }

    const customer = customerSnapshot.data() ?? {};
    const provider = providerSnapshot.data() ?? {};
    assertAccountAvailable(
      customer,
      "Your account is pending deletion and cannot start chats.",
    );
    assertAccountAvailable(
      provider,
      "This provider is unavailable right now.",
    );
    assertChatRestrictions(
      normalizeRestrictions(customer.restrictions),
      "Your account cannot start chats right now.",
    );
    assertChatRestrictions(
      normalizeRestrictions(provider.restrictions),
      "This provider is unavailable for chat right now.",
    );

    const chatSnapshot = await transaction.get(canonicalChatRef);
    const now = FieldValue.serverTimestamp();
    const serviceTitle = safeText(service.title, "Service");
    const serviceImageUrl = chatServiceImage(service);
    const orderedParticipantIds = [customerId, providerId].sort();
    const leftUserId = orderedParticipantIds[0];
    const rightUserId = orderedParticipantIds[1];
    const leftUser = leftUserId === customerId ? customer : provider;
    const rightUser = rightUserId === customerId ? customer : provider;
    const basePayload = {
      chatType: "directUser",
      customerId: leftUserId,
      providerId: rightUserId,
      participantIds: orderedParticipantIds,
      participantSnapshots: [
        participantSnapshotForChat(leftUserId, leftUser),
        participantSnapshotForChat(rightUserId, rightUser),
      ],
      customerName: displayNameFromUser(leftUser, "User"),
      customerPhotoUrl: photoUrlFromUser(leftUser),
      providerName: displayNameFromUser(rightUser, "User"),
      providerPhotoUrl: photoUrlFromUser(rightUser),
      lastServiceId: serviceId,
      lastServiceTitle: serviceTitle,
      lastServiceImageUrl: serviceImageUrl,
      chatSource: "serviceDetail",
      updatedAt: now,
    };

    if (!chatSnapshot.exists) {
      transaction.set(canonicalChatRef, {
        ...basePayload,
        sourceServiceIds: [serviceId],
        lastMessage: "",
        lastMessageAt: now,
        lastSenderId: "",
        unreadCountCustomer: 0,
        unreadCountProvider: 0,
        customerLastReadAt: null,
        providerLastReadAt: null,
        status: "active",
        createdAt: now,
      });
    } else {
      transaction.set(canonicalChatRef, {
        ...basePayload,
        sourceServiceIds: FieldValue.arrayUnion(serviceId),
      }, {merge: true});
    }

    return {
      chatId: canonicalChatId,
      createdCanonical: !chatSnapshot.exists,
      serviceTitle,
      serviceImageUrl,
    };
  });

  if (!canonicalBefore.exists && legacySnapshots.some((snapshot) => snapshot.exists)) {
    await migrateLegacyChatsToCanonical({
      canonicalChatRef,
      legacySnapshots,
      extraServiceId: serviceId,
      extraServiceTitle: result.serviceTitle,
      extraServiceImageUrl: result.serviceImageUrl,
    });
  }

  return {chatId: result.chatId};
});

export const startDirectUserChat = onCall({
  invoker: "public",
}, async (request) => {
  const currentUserId = requireUid(request.auth);
  const otherUserId = asTrimmedString(request.data?.otherUserId);

  if (!otherUserId) {
    throw new HttpsError("invalid-argument", "otherUserId is required.");
  }
  if (otherUserId === currentUserId) {
    throw new HttpsError("failed-precondition", "You cannot message yourself.");
  }

  const chatId = canonicalChatIdForPair(currentUserId, otherUserId);
  const chatRef = db.collection("chats").doc(chatId);
  const legacyChatRefs = legacyChatIdsForPair(currentUserId, otherUserId)
    .filter((legacyChatId) => legacyChatId !== chatId)
    .map((legacyChatId) => db.collection("chats").doc(legacyChatId));
  const currentUserRef = db.collection("users").doc(currentUserId);
  const otherUserRef = db.collection("users").doc(otherUserId);
  const [canonicalBefore, ...legacySnapshots] = await Promise.all([
    chatRef.get(),
    ...legacyChatRefs.map((ref) => ref.get()),
  ]);

  const result = await db.runTransaction(async (transaction) => {
    const [currentUserSnapshot, otherUserSnapshot, chatSnapshot] =
      await Promise.all([
        transaction.get(currentUserRef),
        transaction.get(otherUserRef),
        transaction.get(chatRef),
      ]);

    if (!currentUserSnapshot.exists || !otherUserSnapshot.exists) {
      throw new HttpsError("failed-precondition", "User profile not found.");
    }

    const currentUser = currentUserSnapshot.data() ?? {};
    const otherUser = otherUserSnapshot.data() ?? {};
    assertAccountAvailable(
      currentUser,
      "Your account is pending deletion and cannot start chats.",
    );
    assertAccountAvailable(
      otherUser,
      "This user is unavailable right now.",
    );
    assertChatRestrictions(
      normalizeRestrictions(currentUser.restrictions),
      "Your account cannot start chats right now.",
    );
    assertChatRestrictions(
      normalizeRestrictions(otherUser.restrictions),
      "This user is unavailable for chat right now.",
    );

    const orderedParticipantIds = [currentUserId, otherUserId].sort();
    const leftUserId = orderedParticipantIds[0];
    const rightUserId = orderedParticipantIds[1];
    const leftUser = leftUserId == currentUserId ? currentUser : otherUser;
    const rightUser = rightUserId == currentUserId ? currentUser : otherUser;
    const now = FieldValue.serverTimestamp();
    const basePayload = {
      chatType: "directUser",
      customerId: leftUserId,
      providerId: rightUserId,
      participantIds: orderedParticipantIds,
      participantSnapshots: [
        participantSnapshotForChat(leftUserId, leftUser),
        participantSnapshotForChat(rightUserId, rightUser),
      ],
      customerName: displayNameFromUser(leftUser, "User"),
      customerPhotoUrl: photoUrlFromUser(leftUser),
      providerName: displayNameFromUser(rightUser, "User"),
      providerPhotoUrl: photoUrlFromUser(rightUser),
      lastServiceId: "",
      lastServiceTitle: "",
      lastServiceImageUrl: "",
      updatedAt: now,
    };

    if (!chatSnapshot.exists) {
      transaction.set(chatRef, {
        ...basePayload,
        sourceServiceIds: [],
        lastMessage: "",
        lastMessageAt: now,
        lastSenderId: "",
        unreadCountCustomer: 0,
        unreadCountProvider: 0,
        customerLastReadAt: null,
        providerLastReadAt: null,
        status: "active",
        createdAt: now,
      });
    } else {
      transaction.set(chatRef, basePayload, {merge: true});
    }

    return {chatId, createdCanonical: !chatSnapshot.exists};
  });

  if (!canonicalBefore.exists && legacySnapshots.some((snapshot) => snapshot.exists)) {
    await migrateLegacyChatsToCanonical({
      canonicalChatRef: chatRef,
      legacySnapshots,
    });
  }

  return {chatId: result.chatId};
});

export const sendChatMessage = onCall({
  invoker: "public",
}, async (request) => {
  const senderId = requireUid(request.auth);
  const chatId = asTrimmedString(request.data?.chatId);
  const text = asTrimmedString(request.data?.text);
  const requestedSourceServiceId = asTrimmedString(request.data?.sourceServiceId);

  if (!chatId) {
    throw new HttpsError("invalid-argument", "chatId is required.");
  }
  if (!text) {
    throw new HttpsError("invalid-argument", "Message text is required.");
  }
  if (text.length > 1000) {
    throw new HttpsError("invalid-argument", "Message text is too long.");
  }

  const chatRef = db.collection("chats").doc(chatId);
  const senderRef = db.collection("users").doc(senderId);
  const chatSnapshot = await chatRef.get();
  if (!chatSnapshot.exists) {
    throw new HttpsError("not-found", "Chat not found.");
  }
  const chat = chatSnapshot.data() ?? {};
  const participantIds = Array.isArray(chat.participantIds) ?
    chat.participantIds.map((value) => String(value)) :
    [];
  if (!participantIds.includes(senderId)) {
    throw new HttpsError("permission-denied", "You are not a participant in this chat.");
  }
  if (asTrimmedString(chat.status) !== "active") {
    throw new HttpsError("failed-precondition", "This chat is closed.");
  }

  const senderSnapshot = await senderRef.get();
  if (!senderSnapshot.exists) {
    throw new HttpsError("failed-precondition", "Sender profile not found.");
  }
  const sender = senderSnapshot.data() ?? {};
  assertAccountAvailable(
    sender,
    "Your account is pending deletion and cannot send chat messages.",
  );
  assertChatRestrictions(
    normalizeRestrictions(sender.restrictions),
    "Your account cannot send chat messages right now.",
  );

  const customerId = asTrimmedString(chat.customerId);
  const providerId = asTrimmedString(chat.providerId);
  const receiverId = senderId === customerId ? providerId : customerId;
  if (!receiverId) {
    throw new HttpsError("failed-precondition", "Chat receiver is missing.");
  }

  let sourceServiceId = "";
  let sourceServiceTitle = "";
  let lastServiceImageUrl = "";

  if (requestedSourceServiceId) {
    const serviceSnapshot = await db.collection("services").doc(requestedSourceServiceId).get();
    if (!serviceSnapshot.exists) {
      throw new HttpsError("failed-precondition", "Source service not found.");
    }
    const service = serviceSnapshot.data() ?? {};
    const serviceOwnerId = asTrimmedString(service.ownerUserId);
    if (!participantIds.includes(serviceOwnerId)) {
      throw new HttpsError("failed-precondition", "Source service does not belong to this provider.");
    }
    sourceServiceId = requestedSourceServiceId;
    sourceServiceTitle = safeText(service.title, "Service");
    lastServiceImageUrl = chatServiceImage(service);
  }

  const now = FieldValue.serverTimestamp();
  const messageRef = chatRef.collection("messages").doc();
  const notificationRef = db
    .collection("notifications")
    .doc(`chat_${receiverId}_${chatId}`);
  const senderName = senderId === customerId ?
    safeText(chat.customerName, "Customer") :
    safeText(chat.providerName, "Service Provider");

  if (receiverId === senderId) {
    console.info("Notification skipped", {
      notificationId: notificationRef.id,
      reason: "self-chat-message",
      recipientUserId: receiverId,
      senderUserId: senderId,
      chatId,
      notificationType: "chat",
      tokenCount: 0,
    });
  } else {
    console.info("Notification created", {
      notificationId: notificationRef.id,
      recipientUserId: receiverId,
      senderUserId: senderId,
      chatId,
      notificationType: "chat",
      tokenCount: -1,
    });
  }

  await db.runTransaction(async (transaction) => {
    const latestChatSnapshot = await transaction.get(chatRef);
    if (!latestChatSnapshot.exists) {
      throw new HttpsError("not-found", "Chat not found.");
    }

    const latestChat = latestChatSnapshot.data() ?? {};
    if (asTrimmedString(latestChat.status) !== "active") {
      throw new HttpsError("failed-precondition", "This chat is closed.");
    }

    const existingNotification = receiverId !== senderId ?
      await transaction.get(notificationRef) :
      null;

    transaction.set(messageRef, {
      senderId,
      receiverId,
      text,
      type: "text",
      createdAt: now,
      deliveredTo: [],
      readBy: [],
      sourceServiceId,
      sourceServiceTitle,
    });

    const chatUpdate: Record<string, unknown> = {
      lastMessage: text,
      lastMessageAt: now,
      lastSenderId: senderId,
      updatedAt: now,
    };
    if (sourceServiceId) {
      chatUpdate.sourceServiceIds = FieldValue.arrayUnion(sourceServiceId);
      chatUpdate.lastServiceId = sourceServiceId;
      chatUpdate.lastServiceTitle = sourceServiceTitle;
      chatUpdate.lastServiceImageUrl = lastServiceImageUrl;
    }
    if (receiverId === customerId) {
      chatUpdate.unreadCountCustomer = FieldValue.increment(1);
    }
    if (receiverId === providerId) {
      chatUpdate.unreadCountProvider = FieldValue.increment(1);
    }
    transaction.set(chatRef, chatUpdate, {merge: true});

    if (receiverId !== senderId) {
      if (!existingNotification) {
        throw new HttpsError("internal", "Chat notification state missing.");
      }
      const notificationPayload: Record<string, unknown> = {
        userId: receiverId,
        recipientId: receiverId,
        senderId,
        senderName,
        category: "chat",
        type: "chat",
        title: senderName,
        body: text,
        read: false,
        isRead: false,
        unreadCount: existingNotification.exists ?
          FieldValue.increment(1) :
          1,
        serviceId: sourceServiceId,
        chatId,
        lastMessageId: messageRef.id,
        data: {
          chatId,
          senderId,
          senderName,
          recipientId: receiverId,
          receiverId,
          serviceId: sourceServiceId,
          type: "chat",
          category: "chat",
        },
        updatedAt: now,
      };
      if (!existingNotification.exists) {
        notificationPayload.createdAt = now;
      }
      transaction.set(notificationRef, notificationPayload, {merge: true});
    }
  });

  return {chatId, messageId: messageRef.id};
});

export const markChatDelivered = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const chatId = asTrimmedString(request.data?.chatId);
  if (!chatId) {
    throw new HttpsError("invalid-argument", "chatId is required.");
  }

  const chatRef = db.collection("chats").doc(chatId);
  const chatSnapshot = await chatRef.get();
  if (!chatSnapshot.exists) {
    throw new HttpsError("not-found", "Chat not found.");
  }
  const chat = chatSnapshot.data() ?? {};
  const participantIds = Array.isArray(chat.participantIds) ?
    chat.participantIds.map((value) => String(value)) :
    [];
  if (!participantIds.includes(uid)) {
    throw new HttpsError("permission-denied", "You are not a participant in this chat.");
  }

  const otherUid = uid === asTrimmedString(chat.customerId) ?
    asTrimmedString(chat.providerId) :
    asTrimmedString(chat.customerId);
  if (!otherUid) return {updated: 0};

  const recentMessages = await chatRef
    .collection("messages")
    .where("senderId", "==", otherUid)
    .orderBy("createdAt", "desc")
    .limit(30)
    .get();

  const batch = db.batch();
  let updated = 0;
  for (const doc of recentMessages.docs) {
    const deliveredTo = Array.isArray(doc.data().deliveredTo) ?
      doc.data().deliveredTo.map((value: unknown) => String(value)) :
      [];
    if (deliveredTo.includes(uid)) continue;
    batch.set(doc.ref, {
      deliveredTo: FieldValue.arrayUnion(uid),
    }, {merge: true});
    updated += 1;
  }

  if (updated > 0) {
    await batch.commit();
  }
  return {updated};
});

export const markChatRead = onCall({
  invoker: "public",
}, async (request) => {
  const uid = requireUid(request.auth);
  const chatId = asTrimmedString(request.data?.chatId);
  const openedChatId = asTrimmedString(request.data?.openedChatId);
  if (!chatId) {
    throw new HttpsError("invalid-argument", "chatId is required.");
  }

  const chatRef = db.collection("chats").doc(chatId);
  const chatSnapshot = await chatRef.get();
  if (!chatSnapshot.exists) {
    throw new HttpsError("not-found", "Chat not found.");
  }
  const chat = chatSnapshot.data() ?? {};
  const customerId = asTrimmedString(chat.customerId);
  const providerId = asTrimmedString(chat.providerId);
  if (uid !== customerId && uid !== providerId) {
    throw new HttpsError("permission-denied", "You are not a participant in this chat.");
  }

  const otherUid = uid === customerId ? providerId : customerId;
  if (!otherUid) {
    throw new HttpsError("failed-precondition", "Chat participant is missing.");
  }

  const expectedPairKey = [customerId, providerId].sort().join("_");
  const clearTargets: Array<{
    id: string;
    ref: DocumentReference<DocumentData>;
    unreadField: "unreadCountCustomer" | "unreadCountProvider";
    lastReadField: "customerLastReadAt" | "providerLastReadAt";
    unreadCount: number;
    lastReadAt: unknown;
  }> = [];

  const addClearTarget = (
    id: string,
    ref: DocumentReference<DocumentData>,
    data: DocumentData,
  ) => {
    const targetCustomerId = asTrimmedString(data.customerId);
    const targetProviderId = asTrimmedString(data.providerId);
    const targetPairKey = [targetCustomerId, targetProviderId].sort().join("_");
    if (targetPairKey !== expectedPairKey) return;

    if (uid === targetCustomerId) {
      clearTargets.push({
        id,
        ref,
        unreadField: "unreadCountCustomer",
        lastReadField: "customerLastReadAt",
        unreadCount: toInt(data.unreadCountCustomer, 0),
        lastReadAt: data.customerLastReadAt,
      });
    } else if (uid === targetProviderId) {
      clearTargets.push({
        id,
        ref,
        unreadField: "unreadCountProvider",
        lastReadField: "providerLastReadAt",
        unreadCount: toInt(data.unreadCountProvider, 0),
        lastReadAt: data.providerLastReadAt,
      });
    }
  };

  addClearTarget(chatId, chatRef, chat);
  if (openedChatId && openedChatId !== chatId) {
    const openedChatRef = db.collection("chats").doc(openedChatId);
    const openedChatSnapshot = await openedChatRef.get();
    if (openedChatSnapshot.exists) {
      addClearTarget(openedChatId, openedChatRef, openedChatSnapshot.data() ?? {});
    }
  }

  const currentUnreadCount = uid === customerId ?
    toInt(chat.unreadCountCustomer, 0) :
    toInt(chat.unreadCountProvider, 0);
  const targetsToUpdate = clearTargets.filter((target) =>
    target.unreadCount > 0 || target.lastReadAt == null,
  );

  console.info("markChatRead request", {
    uid,
    chatId,
    openedChatId,
    customerId,
    providerId,
    currentUnreadCount,
    clearTargets: clearTargets.map((target) => ({
      id: target.id,
      unreadField: target.unreadField,
      unreadCount: target.unreadCount,
    })),
  });

  const chatStateBatch = db.batch();
  for (const target of targetsToUpdate) {
    chatStateBatch.set(target.ref, {
      [target.lastReadField]: FieldValue.serverTimestamp(),
      [target.unreadField]: 0,
    }, {merge: true});

    chatStateBatch.set(db.collection("notifications").doc(`chat_${uid}_${target.id}`), {
      read: true,
      isRead: true,
      unreadCount: 0,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }

  if (targetsToUpdate.length > 0) {
    await chatStateBatch.commit();
  }

  let updated = 0;
  try {
    const recentMessages = await chatRef
      .collection("messages")
      .where("senderId", "==", otherUid)
      .orderBy("createdAt", "desc")
      .limit(30)
      .get();

    const messageBatch = db.batch();
    for (const doc of recentMessages.docs) {
      const readBy = Array.isArray(doc.data().readBy) ?
        doc.data().readBy.map((value: unknown) => String(value)) :
        [];
      if (readBy.includes(uid)) continue;
      messageBatch.set(doc.ref, {
        readBy: FieldValue.arrayUnion(uid),
        deliveredTo: FieldValue.arrayUnion(uid),
      }, {merge: true});
      updated += 1;
    }

    if (updated > 0) {
      await messageBatch.commit();
    }
  } catch (error) {
    console.error("markChatRead message acknowledgement failed", {
      uid,
      chatId,
      openedChatId,
      error: error instanceof Error ? error.message : String(error),
    });
  }
  return {updated, clearedChatIds: targetsToUpdate.map((target) => target.id)};
});

export const closeChat = onCall(async (request) => {
  const adminUid = requireUid(request.auth);
  const admin = await requireAdminActor(adminUid);
  assertChatMonitorPermission(admin.role);

  const chatId = asTrimmedString(request.data?.chatId);
  const reason = asTrimmedString(request.data?.reason);
  if (!chatId) {
    throw new HttpsError("invalid-argument", "chatId is required.");
  }

  const chatRef = db.collection("chats").doc(chatId);
  const result = await db.runTransaction(async (transaction) => {
    const chatSnapshot = await transaction.get(chatRef);
    if (!chatSnapshot.exists) {
      throw new HttpsError("not-found", "Chat not found.");
    }

    const chat = chatSnapshot.data() ?? {};
    const previousStatus = asTrimmedString(chat.status) || "active";
    if (previousStatus === "closed") {
      return {status: "closed", alreadyClosed: true};
    }

    transaction.set(chatRef, {
      status: "closed",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    transaction.set(db.collection("adminAuditLogs").doc(), {
      action: "chat.close",
      targetType: "chat",
      targetId: chatId,
      performedBy: admin.uid,
      performedByRole: admin.role,
      createdAt: FieldValue.serverTimestamp(),
      metadata: {
        previousStatus,
        newStatus: "closed",
        reason,
      },
    });

    return {status: "closed", alreadyClosed: false};
  });

  return {ok: true, ...result};
});
