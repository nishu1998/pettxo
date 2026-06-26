import {createHash, createHmac, randomInt, timingSafeEqual} from "crypto";
import {initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import type {
  DocumentData,
  DocumentReference,
  DocumentSnapshot,
  Transaction,
  WriteBatch,
} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {setGlobalOptions} from "firebase-functions/v2";
import {onCall, onRequest, HttpsError} from "firebase-functions/v2/https";
import {onDocumentCreated, onDocumentWritten} from "firebase-functions/v2/firestore";
import {defineSecret} from "firebase-functions/params";
import {onSchedule} from "firebase-functions/v2/scheduler";

setGlobalOptions({
  region: "asia-south1",
  maxInstances: 20,
});

initializeApp();

const db = getFirestore();
const messaging = getMessaging();
const RAZORPAY_KEY_ID = defineSecret("RAZORPAY_KEY_ID");
const RAZORPAY_KEY_SECRET = defineSecret("RAZORPAY_KEY_SECRET");
const RAZORPAY_WEBHOOK_SECRET = defineSecret("RAZORPAY_WEBHOOK_SECRET");
const istOffsetMinutes = 330;
const slotGenerationDays = 30;
const minuteMs = 60 * 1000;
const hourMs = 60 * minuteMs;
const requestResponseWindowMs = 24 * hourMs;
const serviceResponseCutoffMs = hourMs;
const minimumBookingLeadMs = serviceResponseCutoffMs;
const otpAvailabilityWindowMs = hourMs;
const otpValidityMs = hourMs;

type BookingStatus =
  | "paymentPending"
  | "paymentExpired"
  | "requested"
  | "accepted"
  | "rejected"
  | "cancelledByCustomer"
  | "cancelledByProvider"
  | "expired"
  | "inProgress"
  | "completed"
  | "disputed"
  | "noShow";

const restrictionTypes = ["social", "booking", "hard"] as const;
const adminRoles = ["superAdmin", "customerSupportAdmin", "financeAdmin"] as const;
const offerDisplayTypes = ["offerWall", "popup"] as const;
const offerCampaignTypes = ["firstBooking", "festival", "general", "rebooking"] as const;
const offerDiscountTypes = ["flat", "percent"] as const;
const offerClaimValidityTypes = ["lifelong", "fixedDate", "daysAfterClaim"] as const;
const socialNotificationTypes = ["socialFollow", "socialLike", "socialComment"] as const;
const offerCampaignMutableFields = [
  "title",
  "description",
  "imageUrl",
  "couponCode",
  "displayType",
  "campaignType",
  "discountType",
  "discountValue",
  "maxDiscountAmount",
  "minBookingAmount",
  "isActive",
  "startAt",
  "endAt",
  "claimValidityType",
  "claimValidUntil",
  "validDaysAfterClaim",
  "usageLimitPerUser",
  "targeting",
  "priority",
] as const;

type RestrictionType = typeof restrictionTypes[number];
type AdminRole = typeof adminRoles[number];
type OfferDisplayType = typeof offerDisplayTypes[number];
type OfferCampaignType = typeof offerCampaignTypes[number];
type OfferDiscountType = typeof offerDiscountTypes[number];
type OfferClaimValidityType = typeof offerClaimValidityTypes[number];
type SocialNotificationType = typeof socialNotificationTypes[number];
type AccountStatus = "active" | "restricted" | "hardBanned";
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
  imageUrl: string;
  couponCode: string;
  displayType: OfferDisplayType;
  campaignType: OfferCampaignType;
  discountType: OfferDiscountType;
  discountValue: number;
  maxDiscountAmount: number | null;
  minBookingAmount: number | null;
  isActive: boolean;
  startAt: Date;
  endAt: Date | null;
  claimValidityType: OfferClaimValidityType;
  claimValidUntil: Date | null;
  validDaysAfterClaim: number | null;
  usageLimitPerUser: number;
  targeting: OfferTargeting;
  priority: number;
};
type EligibleOfferResponse = {
  id: string;
  title: string;
  description: string;
  imageUrl: string;
  couponCode: string;
  displayType: OfferDisplayType;
  campaignType: OfferCampaignType;
  discountType: OfferDiscountType;
  discountValue: number;
  maxDiscountAmount: number | null;
  minBookingAmount: number | null;
  claimValidityType: OfferClaimValidityType;
  usageLimitPerUser: number;
  priority: number;
  startAt: string | null;
  endAt: string | null;
};

class OfferValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "OfferValidationError";
  }
}

type CancellationActor = "user" | "provider" | "system";
type CancellationBreakdown = {
  refundPercent: number;
  refundAmount: number;
  refundAmountPaise: number;
  pettxoPercent: number;
  pettxoAmount: number;
  pettxoAmountPaise: number;
  providerPercent: number;
  providerAmount: number;
  providerAmountPaise: number;
  totalAmountPaise: number;
  cancellationCase: string;
  graceWindowMinutes: number;
  graceWindowEndsAt: Timestamp;
  isWithinGraceWindow: boolean;
  timeGapMinutes: number;
};
type StandardRevenueBreakdown = {
  pettxoPercent: number;
  pettxoAmount: number;
  pettxoAmountPaise: number;
  providerPercent: number;
  providerAmount: number;
  providerAmountPaise: number;
  totalAmountPaise: number;
};
type CheckoutPricing = {
  serviceAmount: number;
  serviceAmountPaise: number;
  platformFee: number;
  platformFeePaise: number;
  discountAmount: number;
  discountAmountPaise: number;
  totalPayable: number;
  totalPayablePaise: number;
  providerAmount: number;
  providerAmountPaise: number;
  currency: string;
};

const standardCompletedPettxoPercent = 15;
const standardCompletedProviderPercent = 85;
const disputeWindowMs = 24 * hourMs;
const noShowFinalizationDelayMs = 24 * hourMs;

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

function isRestrictionType(value: string): value is RestrictionType {
  return restrictionTypes.includes(value as RestrictionType);
}

function isAdminRole(value: string): value is AdminRole {
  return adminRoles.includes(value as AdminRole);
}

function isOfferDisplayType(value: string): value is OfferDisplayType {
  return offerDisplayTypes.includes(value as OfferDisplayType);
}

function isOfferCampaignType(value: string): value is OfferCampaignType {
  return offerCampaignTypes.includes(value as OfferCampaignType);
}

function isOfferDiscountType(value: string): value is OfferDiscountType {
  return offerDiscountTypes.includes(value as OfferDiscountType);
}

function isOfferClaimValidityType(value: string): value is OfferClaimValidityType {
  return offerClaimValidityTypes.includes(value as OfferClaimValidityType);
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

function toIsoStringOrNull(value: Date | null): string | null {
  return value ? value.toISOString() : null;
}

function isOfferLive(offer: OfferPayload, now: Date): boolean {
  if (!offer.isActive) return false;
  if (offer.startAt.getTime() > now.getTime()) return false;
  if (offer.endAt && offer.endAt.getTime() < now.getTime()) return false;
  return true;
}

function toEligibleOfferResponse(id: string, offer: OfferPayload): EligibleOfferResponse {
  return {
    id,
    title: offer.title,
    description: offer.description,
    imageUrl: offer.imageUrl,
    couponCode: offer.couponCode,
    displayType: offer.displayType,
    campaignType: offer.campaignType,
    discountType: offer.discountType,
    discountValue: offer.discountValue,
    maxDiscountAmount: offer.maxDiscountAmount,
    minBookingAmount: offer.minBookingAmount,
    claimValidityType: offer.claimValidityType,
    usageLimitPerUser: offer.usageLimitPerUser,
    priority: offer.priority,
    startAt: toIsoStringOrNull(offer.startAt),
    endAt: toIsoStringOrNull(offer.endAt),
  };
}

async function getCompletedBookingCountForUser(
  uid: string,
  userData?: Record<string, unknown>,
): Promise<number> {
  const explicitCount =
    asOptionalPositiveInt(userData?.completedBookingCount) ??
    asOptionalPositiveInt(userData?.completedBookingsCount);
  if (explicitCount != null) return explicitCount;

  const aggregate = await db
    .collection("bookings")
    .where("customerId", "==", uid)
    .where("status", "==", "completed")
    .count()
    .get();
  return aggregate.data().count;
}

async function hasClaimedOfferCampaign(uid: string, campaignId: string): Promise<boolean> {
  const snapshot = await db
    .collection("users")
    .doc(uid)
    .collection("claimedOffers")
    .where("offerId", "==", campaignId)
    .limit(1)
    .get();
  return !snapshot.empty;
}

function isOfferEligibleForUser(
  offer: OfferPayload,
  completedBookingCount: number,
): boolean {
  if (offer.targeting.firstBookingOnly && completedBookingCount > 0) {
    return false;
  }
  if (offer.targeting.rebookingOnly && completedBookingCount <= 0) {
    return false;
  }
  return true;
}

function computeOfferValidUntil(offer: OfferPayload, now: Date): Timestamp | null {
  if (offer.claimValidityType === "lifelong") return null;
  if (offer.claimValidityType === "fixedDate") {
    return offer.claimValidUntil ? Timestamp.fromDate(offer.claimValidUntil) : null;
  }
  if (offer.validDaysAfterClaim == null) return null;
  return Timestamp.fromMillis(now.getTime() + (offer.validDaysAfterClaim * 24 * hourMs));
}

function computeOfferDiscount(
  bookingAmount: number,
  discountType: OfferDiscountType,
  discountValue: number,
  maxDiscountAmount: number | null,
): {discountAmount: number; finalAmount: number} {
  const safeBookingAmount = Math.max(0, bookingAmount);
  let discountAmount = discountType === "flat" ?
    Math.min(discountValue, safeBookingAmount) :
    (safeBookingAmount * discountValue) / 100;
  if (maxDiscountAmount != null) {
    discountAmount = Math.min(discountAmount, maxDiscountAmount);
  }
  discountAmount = roundTo(Math.max(0, discountAmount), 2);
  const finalAmount = roundTo(Math.max(safeBookingAmount - discountAmount, 0), 2);
  return {discountAmount, finalAmount};
}

function normalizeOfferPayload(
  data: Record<string, unknown>,
  options: {requireAllFields: boolean},
): OfferPayload {
  const title = asTrimmedString(data.title);
  const couponCode = asTrimmedString(data.couponCode);
  const displayType = asTrimmedString(data.displayType);
  const campaignType = asTrimmedString(data.campaignType);
  const discountType = asTrimmedString(data.discountType);
  const claimValidityType = asTrimmedString(data.claimValidityType);
  const startAt = asDate(data.startAt);
  const endAt = asDate(data.endAt);
  const claimValidUntil = asDate(data.claimValidUntil);
  const discountValue = asOptionalFiniteNumber(data.discountValue);
  const maxDiscountAmount = asOptionalFiniteNumber(data.maxDiscountAmount);
  const minBookingAmount = asOptionalFiniteNumber(data.minBookingAmount);
  const validDaysAfterClaim = asOptionalPositiveInt(data.validDaysAfterClaim);
  const usageLimitPerUser = asOptionalPositiveInt(data.usageLimitPerUser);
  const targetingData = asRecord(data.targeting);
  const targeting: OfferTargeting = {
    firstBookingOnly: asBoolean(targetingData.firstBookingOnly),
    rebookingOnly: asBoolean(targetingData.rebookingOnly),
  };

  if (!title) {
    throw new HttpsError("invalid-argument", "title is required.");
  }
  if (!couponCode) {
    throw new HttpsError("invalid-argument", "couponCode is required.");
  }
  if (!isOfferDisplayType(displayType)) {
    throw new HttpsError("invalid-argument", "displayType must be offerWall or popup.");
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
  if (!isOfferClaimValidityType(claimValidityType)) {
    throw new HttpsError(
      "invalid-argument",
      "claimValidityType must be lifelong, fixedDate, or daysAfterClaim.",
    );
  }
  if (claimValidityType === "fixedDate" && !claimValidUntil) {
    throw new HttpsError("invalid-argument", "claimValidUntil is required for fixedDate.");
  }
  if (claimValidityType === "fixedDate" && claimValidUntil && claimValidUntil.getTime() <= startAt.getTime()) {
    throw new HttpsError("invalid-argument", "claimValidUntil must be after startAt.");
  }
  if (claimValidityType === "daysAfterClaim" && validDaysAfterClaim == null) {
    throw new HttpsError("invalid-argument", "validDaysAfterClaim must be greater than 0.");
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
    imageUrl: asTrimmedString(data.imageUrl),
    couponCode,
    displayType,
    campaignType,
    discountType,
    discountValue,
    maxDiscountAmount,
    minBookingAmount,
    isActive: asBoolean(data.isActive, options.requireAllFields ? false : false),
    startAt,
    endAt,
    claimValidityType,
    claimValidUntil: claimValidityType === "fixedDate" ? claimValidUntil : null,
    validDaysAfterClaim: claimValidityType === "daysAfterClaim" ? validDaysAfterClaim : null,
    usageLimitPerUser,
    targeting,
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

function toMoneyAmount(value: number): number {
  return Math.max(Math.round(value), 0);
}

function toPaise(value: number): number {
  return Math.max(Math.round(value * 100), 0);
}

function fromPaise(value: number): number {
  return roundTo(value / 100, 2);
}

function computeStandardRevenueBreakdown(totalAmount: number): StandardRevenueBreakdown {
  const safeTotalPaise = toPaise(Math.max(totalAmount, 0));
  const pettxoAmountPaise = Math.round(
    (safeTotalPaise * standardCompletedPettxoPercent) / 100,
  );
  const providerAmountPaise = Math.max(safeTotalPaise - pettxoAmountPaise, 0);
  return {
    pettxoPercent: standardCompletedPettxoPercent,
    pettxoAmount: toMoneyAmount(fromPaise(pettxoAmountPaise)),
    pettxoAmountPaise,
    providerPercent: standardCompletedProviderPercent,
    providerAmount: toMoneyAmount(fromPaise(providerAmountPaise)),
    providerAmountPaise,
    totalAmountPaise: safeTotalPaise,
  };
}

function computeCheckoutPricing(params: {
  serviceAmount: number;
  discountAmount: number;
  currency: string;
}): CheckoutPricing {
  const serviceAmountPaise = toPaise(Math.max(params.serviceAmount, 0));
  const platformFeePaise = Math.round(serviceAmountPaise * 0.15);
  const discountAmountPaise = toPaise(Math.max(params.discountAmount, 0));
  const totalPayablePaise = Math.max(
    serviceAmountPaise + platformFeePaise - discountAmountPaise,
    0,
  );

  return {
    serviceAmount: toMoneyAmount(fromPaise(serviceAmountPaise)),
    serviceAmountPaise,
    platformFee: toMoneyAmount(fromPaise(platformFeePaise)),
    platformFeePaise,
    discountAmount: toMoneyAmount(fromPaise(discountAmountPaise)),
    discountAmountPaise,
    totalPayable: toMoneyAmount(fromPaise(totalPayablePaise)),
    totalPayablePaise,
    providerAmount: toMoneyAmount(fromPaise(serviceAmountPaise)),
    providerAmountPaise: serviceAmountPaise,
    currency: params.currency || "INR",
  };
}

function readStoredRevenueBreakdown(
  pricingLike: Record<string, unknown>,
  fallbackTotalAmount?: number,
): StandardRevenueBreakdown {
  const providerAmountPaise = asOptionalPositiveInt(
    pricingLike.providerEarningsPaise ?? pricingLike.providerAmountPaise,
  );
  const pettxoAmountPaise = asOptionalPositiveInt(
    pricingLike.platformFeePaise ?? pricingLike.pettxoAmountPaise,
  );
  const totalAmountPaise = asOptionalPositiveInt(
    pricingLike.finalAmountPaise ?? pricingLike.totalAmountPaise,
  );

  if (
    providerAmountPaise != null &&
    pettxoAmountPaise != null &&
    totalAmountPaise != null
  ) {
    const safeTotalPaise = Math.max(totalAmountPaise, 0);
    const safeProviderPaise = Math.max(providerAmountPaise, 0);
    const safePettxoPaise = Math.max(pettxoAmountPaise, 0);
    return {
      pettxoPercent: safeTotalPaise > 0 ?
        Math.round((safePettxoPaise / safeTotalPaise) * 100) :
        0,
      pettxoAmount: toMoneyAmount(fromPaise(safePettxoPaise)),
      pettxoAmountPaise: safePettxoPaise,
      providerPercent: safeTotalPaise > 0 ?
        Math.round((safeProviderPaise / safeTotalPaise) * 100) :
        0,
      providerAmount: toMoneyAmount(fromPaise(safeProviderPaise)),
      providerAmountPaise: safeProviderPaise,
      totalAmountPaise: safeTotalPaise,
    };
  }

  return computeStandardRevenueBreakdown(fallbackTotalAmount ?? 0);
}

function paymentExpiryTimestamp(nowMs = Date.now()): Timestamp {
  return Timestamp.fromMillis(nowMs + (15 * minuteMs));
}

function isRetryablePaymentState(params: {
  booking: DocumentData;
  payment: DocumentData | undefined;
  nowMs: number;
}): boolean {
  const bookingStatus = asTrimmedString(params.booking.status);
  const pricing = asRecord(params.booking.pricing);
  const paymentStatus = asTrimmedString(
    pricing.paymentStatus || params.payment?.paymentStatus,
  );
  const paymentExpiresAt = (params.booking.paymentExpiresAt as Timestamp | undefined) ??
    (params.payment?.paymentExpiresAt as Timestamp | undefined);

  if (bookingStatus !== "paymentPending") return false;
  if (paymentExpiresAt && paymentExpiresAt.toMillis() <= params.nowMs) return false;
  return paymentStatus === "pending" || paymentStatus === "failed";
}

function pendingPaymentSnapshotFromDocs(params: {
  bookingId: string;
  booking: DocumentData;
  payment: DocumentData | undefined;
  bookingFinancial: DocumentData | undefined;
}): {
  bookingId: string;
  orderId: string;
  amount: number;
  currency: string;
  serviceAmountPaise: number;
  platformFeePaise: number;
  discountPaise: number;
  totalPayablePaise: number;
  paymentExpiresAt: Timestamp | null;
  paymentStatus: string;
  providerId: string;
  serviceId: string;
  slotId: string;
  scheduledStartAt: Timestamp | null;
  scheduledEndAt: Timestamp | null;
} {
  const pricing = asRecord(params.booking.pricing);
  const paymentStatus = asTrimmedString(
    pricing.paymentStatus || params.payment?.paymentStatus,
  ) || "pending";
  const totalPayablePaise = toInt(
    pricing.finalAmountPaise,
    toInt(params.payment?.amountPaise, 0),
  );
  const serviceAmountPaise = toInt(
    pricing.serviceAmountPaise,
    toInt(pricing.grossAmountPaise, 0),
  );
  const platformFeePaise = toInt(
    pricing.platformFeePaise,
    toInt(params.bookingFinancial?.pettxoAmountPaise, 0),
  );
  const discountPaise = toInt(
    pricing.discountAmountPaise,
    toInt(params.bookingFinancial?.discountAmountPaise, 0),
  );
  return {
    bookingId: params.bookingId,
    orderId: asTrimmedString(
      pricing.razorpayOrderId ??
      params.payment?.razorpayOrderId ??
      params.bookingFinancial?.razorpayOrderId,
    ),
    amount: totalPayablePaise,
    currency: asTrimmedString(pricing.currency) || "INR",
    serviceAmountPaise,
    platformFeePaise,
    discountPaise,
    totalPayablePaise,
    paymentExpiresAt: (params.booking.paymentExpiresAt as Timestamp | undefined) ??
      (params.payment?.paymentExpiresAt as Timestamp | undefined) ??
      null,
    paymentStatus,
    providerId: asTrimmedString(params.booking.serviceOwnerId ?? params.booking.providerId),
    serviceId: asTrimmedString(params.booking.serviceId),
    slotId: asTrimmedString(params.booking.slotId),
    scheduledStartAt: (params.booking.scheduledStartAt as Timestamp | undefined) ?? null,
    scheduledEndAt: (params.booking.scheduledEndAt as Timestamp | undefined) ?? null,
  };
}

async function createRazorpayOrder(params: {
  bookingId: string;
  amountPaise: number;
  currency: string;
  customerId: string;
  serviceId: string;
  slotId: string;
}): Promise<{orderId: string; amount: number; currency: string; keyId: string}> {
  const keyId = asTrimmedString(RAZORPAY_KEY_ID.value());
  const keySecret = asTrimmedString(RAZORPAY_KEY_SECRET.value());
  if (!keyId || !keySecret) {
    throw new HttpsError(
      "failed-precondition",
      "Razorpay credentials are not configured in Functions.",
    );
  }

  const response = await fetch("https://api.razorpay.com/v1/orders", {
    method: "POST",
    headers: {
      Authorization: `Basic ${Buffer.from(`${keyId}:${keySecret}`).toString("base64")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      amount: Math.max(params.amountPaise, 0),
      currency: params.currency || "INR",
      receipt: params.bookingId,
      notes: {
        bookingId: params.bookingId,
        customerId: params.customerId,
        serviceId: params.serviceId,
        slotId: params.slotId,
      },
    }),
  });

  const raw = await response.text();
  let data: Record<string, unknown> = {};
  try {
    data = raw ? JSON.parse(raw) as Record<string, unknown> : {};
  } catch (_) {
    data = {};
  }

  if (!response.ok) {
    throw new HttpsError(
      "internal",
      asTrimmedString(data.error) || "Unable to create Razorpay order right now.",
    );
  }

  const orderId = asTrimmedString(data.id);
  if (!orderId) {
    throw new HttpsError("internal", "Razorpay order ID was missing.");
  }

  return {
    orderId,
    amount: toInt(data.amount, params.amountPaise),
    currency: asTrimmedString(data.currency) || params.currency || "INR",
    keyId,
  };
}

function verifyRazorpaySignature(params: {
  orderId: string;
  paymentId: string;
  signature: string;
}): boolean {
  const keySecret = asTrimmedString(RAZORPAY_KEY_SECRET.value());
  if (!keySecret) {
    throw new HttpsError(
      "failed-precondition",
      "Razorpay credentials are not configured in Functions.",
    );
  }

  const expected = createHmac("sha256", keySecret)
    .update(`${params.orderId}|${params.paymentId}`)
    .digest("hex");

  const expectedBuffer = Buffer.from(expected, "utf8");
  const signatureBuffer = Buffer.from(params.signature, "utf8");
  return expectedBuffer.length === signatureBuffer.length &&
    timingSafeEqual(expectedBuffer, signatureBuffer);
}

function verifyRazorpayWebhookSignature(params: {
  rawBody: Buffer;
  signature: string;
}): boolean {
  const secret = asTrimmedString(RAZORPAY_WEBHOOK_SECRET.value());
  if (!secret) {
    throw new HttpsError(
      "failed-precondition",
      "Razorpay webhook secret is not configured in Functions.",
    );
  }

  const expected = createHmac("sha256", secret)
    .update(params.rawBody)
    .digest("hex");
  const expectedBuffer = Buffer.from(expected, "utf8");
  const signatureBuffer = Buffer.from(params.signature, "utf8");
  return expectedBuffer.length === signatureBuffer.length &&
    timingSafeEqual(expectedBuffer, signatureBuffer);
}

async function fetchRazorpayPayment(params: {
  paymentId: string;
}): Promise<{id: string; orderId: string; status: string; amountPaise: number; currency: string}> {
  const keyId = asTrimmedString(RAZORPAY_KEY_ID.value());
  const keySecret = asTrimmedString(RAZORPAY_KEY_SECRET.value());
  if (!keyId || !keySecret) {
    throw new HttpsError(
      "failed-precondition",
      "Razorpay credentials are not configured in Functions.",
    );
  }

  const response = await fetch(
    `https://api.razorpay.com/v1/payments/${encodeURIComponent(params.paymentId)}`,
    {
      method: "GET",
      headers: {
        Authorization: `Basic ${Buffer.from(`${keyId}:${keySecret}`).toString("base64")}`,
        "Content-Type": "application/json",
      },
    },
  );

  const raw = await response.text();
  let data: Record<string, unknown> = {};
  try {
    data = raw ? JSON.parse(raw) as Record<string, unknown> : {};
  } catch (_) {
    data = {};
  }

  if (!response.ok) {
    throw new HttpsError(
      "internal",
      safeText(data.error ?? data.description, "Unable to verify Razorpay payment."),
    );
  }

  return {
    id: asTrimmedString(data.id),
    orderId: asTrimmedString(data.order_id),
    status: asTrimmedString(data.status),
    amountPaise: toInt(data.amount, 0),
    currency: asTrimmedString(data.currency) || "INR",
  };
}

async function fetchRazorpayOrderPayments(params: {
  orderId: string;
}): Promise<Array<{id: string; orderId: string; status: string; amountPaise: number; currency: string}>> {
  const keyId = asTrimmedString(RAZORPAY_KEY_ID.value());
  const keySecret = asTrimmedString(RAZORPAY_KEY_SECRET.value());
  if (!keyId || !keySecret) {
    throw new HttpsError(
      "failed-precondition",
      "Razorpay credentials are not configured in Functions.",
    );
  }

  const response = await fetch(
    `https://api.razorpay.com/v1/orders/${encodeURIComponent(params.orderId)}/payments`,
    {
      method: "GET",
      headers: {
        Authorization: `Basic ${Buffer.from(`${keyId}:${keySecret}`).toString("base64")}`,
        "Content-Type": "application/json",
      },
    },
  );

  const raw = await response.text();
  let data: Record<string, unknown> = {};
  try {
    data = raw ? JSON.parse(raw) as Record<string, unknown> : {};
  } catch (_) {
    data = {};
  }

  if (!response.ok) {
    throw new HttpsError(
      "internal",
      safeText(data.error ?? data.description, "Unable to verify Razorpay order payment."),
    );
  }

  const payments = Array.isArray(data.items) ? data.items : [];
  return payments.map((item) => {
    const payment = asRecord(item);
    return {
      id: asTrimmedString(payment.id),
      orderId: asTrimmedString(payment.order_id) || params.orderId,
      status: asTrimmedString(payment.status),
      amountPaise: toInt(payment.amount, 0),
      currency: asTrimmedString(payment.currency) || "INR",
    };
  });
}

function sleepMs(durationMs: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, durationMs));
}

async function resolveCapturedRazorpayPayment(params: {
  paymentId: string;
  orderId: string;
  attempts?: number;
  delayMs?: number;
}): Promise<{id: string; orderId: string; status: string; amountPaise: number; currency: string}> {
  const maxAttempts = Math.max(params.attempts ?? 5, 1);
  const delayMs = Math.max(params.delayMs ?? 1500, 250);
  let lastPayment = await fetchRazorpayPayment({paymentId: params.paymentId});

  if (lastPayment.orderId !== params.orderId) {
    throw new HttpsError("failed-precondition", "Razorpay payment order mismatch.");
  }
  if (lastPayment.status === "captured") {
    return lastPayment;
  }

  for (let attempt = 1; attempt < maxAttempts; attempt += 1) {
    const orderPayments = await fetchRazorpayOrderPayments({orderId: params.orderId});
    const capturedMatch = orderPayments.find((payment) =>
      payment.id === params.paymentId && payment.status === "captured",
    );
    if (capturedMatch) {
      return capturedMatch;
    }

    await sleepMs(delayMs);
    lastPayment = await fetchRazorpayPayment({paymentId: params.paymentId});
    if (lastPayment.orderId !== params.orderId) {
      throw new HttpsError("failed-precondition", "Razorpay payment order mismatch.");
    }
    if (lastPayment.status === "captured") {
      return lastPayment;
    }
  }

  throw new HttpsError("failed-precondition", "Razorpay payment is not captured yet.");
}

function getBookingPaidAmountPaise(booking: DocumentData): number {
  const pricing = asRecord(booking.pricing);
  const finalAmountPaise = asOptionalPositiveInt(pricing.finalAmountPaise);
  if (finalAmountPaise != null) return finalAmountPaise;
  const financialTotalPaise = asOptionalPositiveInt(booking.totalAmountPaise);
  if (financialTotalPaise != null) return financialTotalPaise;
  return toPaise(getBookingPaidAmount(booking));
}

function getBookingPaidAmount(booking: DocumentData): number {
  const pricing = asRecord(booking.pricing);
  const finalAmount = asOptionalFiniteNumber(pricing.finalAmount);
  if (finalAmount != null && finalAmount >= 0) return toMoneyAmount(finalAmount);
  return Math.max(toInt(pricing.grossAmount, 0), 0);
}

function getBookingCurrency(booking: DocumentData): string {
  const pricing = asRecord(booking.pricing);
  const serviceSnapshot = asRecord(booking.serviceSnapshot);
  return asTrimmedString(pricing.currency) || asTrimmedString(serviceSnapshot.currency) || "INR";
}

async function finalizeCapturedBookingPayment(params: {
  bookingId: string;
  uid: string;
  razorpayOrderId: string;
  razorpayPayment: {id: string; orderId: string; status: string; amountPaise: number; currency: string};
}): Promise<{bookingId: string; providerId: string}> {
  const bookingId = params.bookingId;
  const uid = params.uid;
  const razorpayOrderId = params.razorpayOrderId;
  const razorpayPaymentId = params.razorpayPayment.id;
  const bookingRef = db.collection("bookings").doc(bookingId);
  const bookingFinancialRef = db.collection("bookingFinancials").doc(bookingId);
  const paymentRef = db.collection("payments").doc(bookingId);
  const invoiceRef = db.collection("invoices").doc(bookingId);
  const providerEarningRef = db.collection("providerEarnings").doc(bookingId);
  let providerId = "";

  await db.runTransaction(async (transaction) => {
    const bookingSnapshot = await transaction.get(bookingRef);
    const bookingFinancialSnapshot = await transaction.get(bookingFinancialRef);
    const paymentSnapshot = await transaction.get(paymentRef);

    if (!bookingSnapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }

    const booking = bookingSnapshot.data()!;
    if (asTrimmedString(booking.customerId) !== uid) {
      throw new HttpsError("permission-denied", "Only the booking owner can verify payment.");
    }

    const status = asTrimmedString(booking.status);
    const paymentStatus = asTrimmedString(asRecord(booking.pricing).paymentStatus);
    if (status === "requested" && paymentStatus === "paid") {
      providerId = asTrimmedString(booking.serviceOwnerId ?? booking.providerId);
      return;
    }
    if (status !== "paymentPending") {
      throw new HttpsError("failed-precondition", "This booking is not awaiting payment.");
    }

    const paymentExpiresAt = booking.paymentExpiresAt as Timestamp | undefined;
    if (paymentExpiresAt && paymentExpiresAt.toMillis() <= Date.now()) {
      throw new HttpsError("deadline-exceeded", "This payment window has expired.");
    }

    const storedOrderId = asTrimmedString(
      asRecord(booking.pricing).razorpayOrderId ??
      bookingFinancialSnapshot.data()?.razorpayOrderId ??
      paymentSnapshot.data()?.razorpayOrderId,
    );
    if (!storedOrderId || storedOrderId !== razorpayOrderId) {
      throw new HttpsError("failed-precondition", "Razorpay order does not match this booking.");
    }
    const scheduledStartAt = booking.scheduledStartAt as Timestamp | undefined;
    if (!scheduledStartAt) {
      throw new HttpsError("failed-precondition", "Booking service time is missing.");
    }
    const requestExpiresAt = computeBookingRequestExpiresAt(
      Date.now(),
      scheduledStartAt.toMillis(),
    );
    if (requestExpiresAt.toMillis() <= Date.now()) {
      throw new HttpsError(
        "failed-precondition",
        "This slot is too soon for the provider response window.",
      );
    }

    providerId = asTrimmedString(booking.serviceOwnerId ?? booking.providerId);
    const pricing = asRecord(booking.pricing);
    const serviceAmountPaise = toInt(
      pricing.serviceAmountPaise,
      toInt(pricing.grossAmountPaise, 0),
    );
    const platformFeePaise = toInt(pricing.platformFeePaise, 0);
    const discountAmountPaise = toInt(pricing.discountAmountPaise, 0);
    const finalAmountPaise = toInt(
      pricing.finalAmountPaise,
      serviceAmountPaise + platformFeePaise - discountAmountPaise,
    );
    const currency = asTrimmedString(pricing.currency) || "INR";
    const paymentConfirmedAt = Timestamp.now();
    const graceWindow = buildGraceWindow(
      paymentConfirmedAt.toDate(),
      scheduledStartAt.toDate(),
    );
    const offer = asRecord(booking.offer);
    const claimedOfferId = asTrimmedString(offer.claimedOfferId);
    const claimedOfferRef = claimedOfferId ?
      db.collection("users").doc(uid).collection("claimedOffers").doc(claimedOfferId) :
      null;
    const claimedOfferSnapshot = claimedOfferRef ? await transaction.get(claimedOfferRef) : null;
    if (claimedOfferRef) {
      if (!claimedOfferSnapshot?.exists) {
        throw new HttpsError("failed-precondition", "Offer is no longer valid.");
      }
      const claimedOffer = claimedOfferSnapshot.data() ?? {};
      const claimedStatus = asTrimmedString(claimedOffer.status);
      const usageLimit = toInt(claimedOffer.usageLimit, 0);
      const usedCount = Math.max(toInt(claimedOffer.usedCount, 0), 0);
      const claimedValidUntil = asDate(claimedOffer.validUntil);
      if (claimedStatus !== "claimed" || usedCount >= usageLimit) {
        throw new HttpsError("failed-precondition", "Offer is no longer valid.");
      }
      if (claimedValidUntil && claimedValidUntil.getTime() < Date.now()) {
        throw new HttpsError("failed-precondition", "Offer is no longer valid.");
      }
    }
    if (params.razorpayPayment.amountPaise !== finalAmountPaise) {
      throw new HttpsError("failed-precondition", "Razorpay amount does not match this booking.");
    }
    if (params.razorpayPayment.currency !== currency) {
      throw new HttpsError("failed-precondition", "Razorpay currency does not match this booking.");
    }

    transaction.update(bookingRef, {
      status: "requested",
      paymentConfirmedAt,
      paymentExpiresAt: null,
      graceWindowMinutes: graceWindow.graceWindowMinutes,
      graceWindowEndsAt: graceWindow.graceWindowEndsAt,
      updatedAt: FieldValue.serverTimestamp(),
      "request.expiresAt": requestExpiresAt,
      "pricing.paymentStatus": "paid",
      "pricing.razorpayOrderId": razorpayOrderId,
      "pricing.razorpayPaymentId": razorpayPaymentId,
      "notificationState.requestNotificationSent": true,
      ...(claimedOfferId ? {"offer.status": "applied"} : {}),
    });
    transaction.set(bookingFinancialRef, {
      bookingId,
      userId: uid,
      providerId,
      serviceId: asTrimmedString(booking.serviceId),
      totalAmount: toMoneyAmount(fromPaise(finalAmountPaise)),
      totalAmountPaise: finalAmountPaise,
      serviceAmount: toMoneyAmount(fromPaise(serviceAmountPaise)),
      serviceAmountPaise,
      currency,
      razorpayPaymentId,
      razorpayOrderId,
      status: "paid",
      paymentStatus: "paid",
      graceWindowMinutes: graceWindow.graceWindowMinutes,
      graceWindowEndsAt: graceWindow.graceWindowEndsAt,
      paymentConfirmedAt,
      refundAmount: 0,
      refundAmountPaise: 0,
      pettxoCommissionAmount: toMoneyAmount(fromPaise(platformFeePaise)),
      pettxoAmountPaise: platformFeePaise,
      providerEarningAmount: toMoneyAmount(fromPaise(serviceAmountPaise)),
      providerAmountPaise: serviceAmountPaise,
      discountAmount: toMoneyAmount(fromPaise(discountAmountPaise)),
      discountAmountPaise,
      refundPercent: 0,
      pettxoPercent: 15,
      providerPercent: finalAmountPaise > 0 ?
        Math.round((serviceAmountPaise / finalAmountPaise) * 100) :
        0,
      cancellationCase: "",
      cancelledBy: null,
      cancelledAt: null,
      disputeStatus: "none",
      otpUsed: false,
      serviceTime: scheduledStartAt,
      completedAt: null,
      payoutEligibleAt: null,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(paymentRef, {
      bookingId,
      userId: uid,
      providerId,
      serviceId: asTrimmedString(booking.serviceId),
      status: "paid",
      paymentStatus: "paid",
      currency,
      amount: toMoneyAmount(fromPaise(finalAmountPaise)),
      amountPaise: finalAmountPaise,
      serviceAmount: toMoneyAmount(fromPaise(serviceAmountPaise)),
      serviceAmountPaise,
      platformFee: toMoneyAmount(fromPaise(platformFeePaise)),
      platformFeePaise,
      discountAmount: toMoneyAmount(fromPaise(discountAmountPaise)),
      discountAmountPaise,
      razorpayOrderId,
      razorpayPaymentId,
      paymentConfirmedAt,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(invoiceRef, {
      invoiceId: bookingId,
      bookingId,
      userId: uid,
      providerId,
      serviceId: asTrimmedString(booking.serviceId),
      status: "issued",
      currency,
      serviceAmountPaise,
      platformFeePaise,
      discountAmountPaise,
      totalPayablePaise: finalAmountPaise,
      taxLabel: "GST",
      taxAmountPaise: 0,
      taxStatus: "Not applicable",
      issuedAt: paymentConfirmedAt,
      createdAt: paymentConfirmedAt,
      updatedAt: paymentConfirmedAt,
    }, {merge: true});
    transaction.set(providerEarningRef, {
      bookingId,
      providerId,
      userId: uid,
      serviceId: asTrimmedString(booking.serviceId),
      amount: toMoneyAmount(fromPaise(serviceAmountPaise)),
      amountPaise: serviceAmountPaise,
      pettxoCommissionAmount: toMoneyAmount(fromPaise(platformFeePaise)),
      pettxoCommissionAmountPaise: platformFeePaise,
      totalAmount: toMoneyAmount(fromPaise(finalAmountPaise)),
      totalAmountPaise: finalAmountPaise,
      source: "paidBooking",
      status: "notEligible",
      eligibleAt: null,
      paidAt: null,
      createdAt: paymentConfirmedAt,
      updatedAt: paymentConfirmedAt,
    }, {merge: true});

    if (claimedOfferRef) {
      transaction.set(claimedOfferRef, {
        usedCount: FieldValue.increment(1),
        status: "used",
      }, {merge: true});
      transaction.set(db.collection("adminAuditLogs").doc(), {
        action: "offer.redeemed",
        userId: uid,
        claimedOfferId,
        bookingId,
        discountAmount: toMoneyAmount(fromPaise(discountAmountPaise)),
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    queueBookingNotification({
      transaction,
      userId: providerId,
      bookingId,
      type: "bookingRequested",
      title: "New booking request",
      body: `${snapshotName(
        booking.customerSnapshot,
        "A pet parent",
      )} requested ${serviceTitleFromBooking(booking)}.`,
      recipientRole: "provider",
      actorId: uid,
      status: "requested",
      booking: {
        ...booking,
        status: "requested",
      },
      extraData: {event: "booking_requested"},
    });
  });

  await writeBookingEvent({
    bookingId,
    actorId: uid,
    actorType: "customer",
    type: "paymentVerified",
    fromStatus: "paymentPending",
    toStatus: "requested",
    message: "Razorpay payment verified and booking request created.",
    metadata: {
      razorpayOrderId,
      razorpayPaymentId,
      providerId,
    },
  });

  return {bookingId, providerId};
}

function bookingCreatedAtDate(booking: DocumentData): Date {
  return asDate(booking.createdAt) ?? asDate(booking.acceptedAt) ?? new Date();
}

function bookingServiceTimeDate(booking: DocumentData): Date | null {
  return asDate(booking.scheduledStartAt);
}

function getGraceWindowMinutes(bookingTime: Date, serviceTime: Date): number {
  const diffMs = serviceTime.getTime() - bookingTime.getTime();
  if (diffMs <= 6 * hourMs) return 10;
  if (diffMs <= 12 * hourMs) return 15;
  return 30;
}

function buildGraceWindow(bookingTime: Date, serviceTime: Date): {
  graceWindowMinutes: number;
  graceWindowEndsAt: Timestamp;
} {
  const graceWindowMinutes = getGraceWindowMinutes(bookingTime, serviceTime);
  return {
    graceWindowMinutes,
    graceWindowEndsAt: Timestamp.fromMillis(
      bookingTime.getTime() + (graceWindowMinutes * minuteMs),
    ),
  };
}

function hasOtpBeenUsed(booking: DocumentData): boolean {
  const otp = asRecord(booking.otp);
  return asTrimmedString(booking.status) === "inProgress" ||
    asTrimmedString(booking.status) === "completed" ||
    asTrimmedString(otp.status) === "verified" ||
    asDate(otp.verifiedAt) != null;
}

function calculateCancellationBreakdown(params: {
  bookingTime: Date;
  serviceTime: Date;
  cancellationTime: Date;
  otpUsed: boolean;
  totalAmountPaise: number;
  cancelledBy: CancellationActor;
}): CancellationBreakdown {
  const {
    bookingTime,
    serviceTime,
    cancellationTime,
    otpUsed,
    totalAmountPaise,
    cancelledBy,
  } = params;

  if (otpUsed) {
    throw new HttpsError(
      "failed-precondition",
      "Bookings cannot be cancelled after the service OTP has been used.",
    );
  }

  const safeTotalAmountPaise = Math.max(totalAmountPaise, 0);
  const {graceWindowMinutes, graceWindowEndsAt} = buildGraceWindow(bookingTime, serviceTime);
  const isWithinGraceWindow = cancellationTime.getTime() <= graceWindowEndsAt.toMillis();

  let refundPercent = 0;
  let pettxoPercent = 0;
  let providerPercent = 0;
  let cancellationCase = "outsidePolicy";

  if (cancelledBy === "provider" || cancelledBy === "system") {
    refundPercent = 100;
    pettxoPercent = 0;
    providerPercent = 0;
    cancellationCase = cancelledBy === "provider" ?
      "providerCancellation" :
      "systemCancellation";
  } else if (isWithinGraceWindow) {
    refundPercent = 100;
    pettxoPercent = 0;
    providerPercent = 0;
    cancellationCase = "graceWindow";
  } else {
    const hoursBeforeService = (serviceTime.getTime() - cancellationTime.getTime()) / hourMs;
    if (hoursBeforeService > 24) {
      refundPercent = 90;
      pettxoPercent = 10;
      providerPercent = 0;
      cancellationCase = "userMoreThan24Hours";
    } else if (hoursBeforeService > 12) {
      refundPercent = 50;
      pettxoPercent = 15;
      providerPercent = 35;
      cancellationCase = "user24To12Hours";
    } else if (hoursBeforeService > 6) {
      refundPercent = 35;
      pettxoPercent = 15;
      providerPercent = 50;
      cancellationCase = "user12To6Hours";
    } else if (hoursBeforeService > 2) {
      refundPercent = 20;
      pettxoPercent = 15;
      providerPercent = 65;
      cancellationCase = "user6To2Hours";
    } else {
      refundPercent = 0;
      pettxoPercent = 15;
      providerPercent = 85;
      cancellationCase = "userLessThan2Hours";
    }
  }

  if (refundPercent + pettxoPercent + providerPercent !== 100) {
    throw new HttpsError(
      "internal",
      "Cancellation policy percentages are invalid.",
    );
  }

  const refundAmountPaise = Math.round((safeTotalAmountPaise * refundPercent) / 100);
  const pettxoAmountPaise = Math.round((safeTotalAmountPaise * pettxoPercent) / 100);
  const providerAmountPaise = Math.max(
    safeTotalAmountPaise - refundAmountPaise - pettxoAmountPaise,
    0,
  );
  const timeGapMinutes = Math.max(
    Math.floor((serviceTime.getTime() - cancellationTime.getTime()) / minuteMs),
    0,
  );

  return {
    refundPercent,
    refundAmount: toMoneyAmount(fromPaise(refundAmountPaise)),
    refundAmountPaise,
    pettxoPercent,
    pettxoAmount: toMoneyAmount(fromPaise(pettxoAmountPaise)),
    pettxoAmountPaise,
    providerPercent,
    providerAmount: toMoneyAmount(fromPaise(providerAmountPaise)),
    providerAmountPaise,
    totalAmountPaise: safeTotalAmountPaise,
    cancellationCase,
    graceWindowMinutes,
    graceWindowEndsAt,
    isWithinGraceWindow,
    timeGapMinutes,
  };
}

function bookingFinancialStatusForCancellation(
  breakdown: CancellationBreakdown,
): string {
  if (breakdown.refundAmountPaise >= 0 && breakdown.refundPercent === 100) {
    return "refunded";
  }
  if (breakdown.refundAmountPaise > 0) {
    return "partiallyRefunded";
  }
  return "cancelled";
}

function paymentStatusForCancellation(
  breakdown: CancellationBreakdown,
): string {
  if (breakdown.refundPercent === 100) return "refunded";
  if (breakdown.refundAmountPaise > 0) return "partiallyRefunded";
  return "paid";
}

function canBookingBeCancelled(
  booking: DocumentData,
  actor: CancellationActor,
  nowMs: number,
): void {
  const status = asTrimmedString(booking.status) as BookingStatus;
  if (hasOtpBeenUsed(booking) || status === "inProgress") {
    throw new HttpsError(
      "failed-precondition",
      "Bookings cannot be cancelled after the service has started.",
    );
  }
  if (status === "completed" || status === "cancelledByCustomer" ||
    status === "cancelledByProvider" || status === "rejected" ||
    status === "expired" || status === "noShow") {
    throw new HttpsError(
      "failed-precondition",
      `Booking cannot be cancelled from status ${status}.`,
    );
  }
  if (status === "requested" && actor === "provider") {
    throw new HttpsError(
      "failed-precondition",
      "Providers should reject requested bookings instead of cancelling them.",
    );
  }

  const serviceTime = bookingServiceTimeDate(booking);
  if (serviceTime && serviceTime.getTime() <= nowMs) {
    throw new HttpsError(
      "failed-precondition",
      "Bookings can only be cancelled before the scheduled service time.",
    );
  }
}

function disputeWindowEndsAtForBooking(booking: DocumentData): Date {
  const completedAt = asDate(booking.completedAt);
  if (completedAt) {
    return new Date(completedAt.getTime() + disputeWindowMs);
  }

  const serviceTime = bookingServiceTimeDate(booking);
  if (serviceTime) {
    return new Date(serviceTime.getTime() + disputeWindowMs);
  }

  return new Date(bookingCreatedAtDate(booking).getTime() + disputeWindowMs);
}

function hasBlockingDispute(booking: DocumentData): boolean {
  const dispute = asRecord(booking.dispute);
  const status = asTrimmedString(dispute.status) || asTrimmedString(booking.disputeStatus);
  return status === "open" || status === "underReview";
}

function buildCancellationSnapshot(params: {
  breakdown: CancellationBreakdown;
  cancelledBy: string;
  cancellationType: string;
  cancellationTime: Timestamp;
  serviceTime: Timestamp;
  bookingTime: Timestamp;
  otpUsedAtCancellation: boolean;
}): Record<string, unknown> {
  const {
    breakdown,
    cancelledBy,
    cancellationType,
    cancellationTime,
    serviceTime,
    bookingTime,
    otpUsedAtCancellation,
  } = params;
  return {
    refundPercent: breakdown.refundPercent,
    providerPercent: breakdown.providerPercent,
    pettxoPercent: breakdown.pettxoPercent,
    refundAmountPaise: breakdown.refundAmountPaise,
    providerAmountPaise: breakdown.providerAmountPaise,
    pettxoAmountPaise: breakdown.pettxoAmountPaise,
    totalAmountPaise: breakdown.totalAmountPaise,
    cancellationCase: breakdown.cancellationCase,
    cancelledBy,
    cancellationType,
    cancellationTime,
    serviceTime,
    bookingTime,
    timeGapMinutes: breakdown.timeGapMinutes,
    wasWithinGraceWindow: breakdown.isWithinGraceWindow,
    otpUsedAtCancellation,
  };
}

function readExistingCancellationBreakdown(
  booking: DocumentData,
  financialData: DocumentData | undefined,
): CancellationBreakdown | null {
  const snapshot = asRecord(financialData?.cancellationSnapshot);
  const fallback = asRecord(financialData);
  const totalAmountPaise = toInt(
    snapshot.totalAmountPaise,
    toInt(fallback.totalAmountPaise, toPaise(getBookingPaidAmount(booking))),
  );
  const refundAmountPaise = toInt(snapshot.refundAmountPaise, toInt(fallback.refundAmountPaise, 0));
  const pettxoAmountPaise = toInt(snapshot.pettxoAmountPaise, toInt(fallback.pettxoAmountPaise, 0));
  const providerAmountPaise = toInt(snapshot.providerAmountPaise, toInt(fallback.providerAmountPaise, 0));
  const cancellationCase = asTrimmedString(snapshot.cancellationCase) ||
    asTrimmedString(fallback.cancellationCase) ||
    asTrimmedString(asRecord(booking.cancellation).cancellationCase);
  if (!cancellationCase && totalAmountPaise <= 0) return null;
  return {
    refundPercent: toInt(snapshot.refundPercent, toInt(fallback.refundPercent, 0)),
    refundAmount: toMoneyAmount(fromPaise(refundAmountPaise)),
    refundAmountPaise,
    pettxoPercent: toInt(snapshot.pettxoPercent, toInt(fallback.pettxoPercent, 0)),
    pettxoAmount: toMoneyAmount(fromPaise(pettxoAmountPaise)),
    pettxoAmountPaise,
    providerPercent: toInt(snapshot.providerPercent, toInt(fallback.providerPercent, 0)),
    providerAmount: toMoneyAmount(fromPaise(providerAmountPaise)),
    providerAmountPaise,
    totalAmountPaise,
    cancellationCase,
    graceWindowMinutes: toInt(
      snapshot.graceWindowMinutes,
      toInt(financialData?.graceWindowMinutes, 0),
    ),
    graceWindowEndsAt: (snapshot.graceWindowEndsAt as Timestamp | undefined) ??
      (financialData?.graceWindowEndsAt as Timestamp | undefined) ??
      Timestamp.now(),
    isWithinGraceWindow: snapshot.wasWithinGraceWindow === true,
    timeGapMinutes: toInt(snapshot.timeGapMinutes, 0),
  };
}

function buildBookingSnapshotForDispute(bookingId: string, booking: DocumentData): Record<string, unknown> {
  return {
    bookingId,
    status: asTrimmedString(booking.status),
    customerId: asTrimmedString(booking.customerId),
    providerId: asTrimmedString(booking.serviceOwnerId ?? booking.providerId),
    serviceId: asTrimmedString(booking.serviceId),
    slotId: asTrimmedString(booking.slotId),
    scheduledStartAt: booking.scheduledStartAt ?? null,
    scheduledEndAt: booking.scheduledEndAt ?? null,
    createdAt: booking.createdAt ?? null,
    completedAt: booking.completedAt ?? null,
    cancellation: booking.cancellation ?? {},
    pricing: booking.pricing ?? {},
    serviceSnapshot: booking.serviceSnapshot ?? {},
    providerSnapshot: booking.providerSnapshot ?? {},
    customerSnapshot: booking.customerSnapshot ?? {},
  };
}

function buildFinancialSnapshotForDispute(
  financialData: DocumentData | undefined,
  booking: DocumentData,
): Record<string, unknown> {
  if (financialData) {
    return {
      status: asTrimmedString(financialData.status),
      totalAmount: toInt(financialData.totalAmount, getBookingPaidAmount(booking)),
      totalAmountPaise: toInt(
        financialData.totalAmountPaise,
        toPaise(toInt(financialData.totalAmount, getBookingPaidAmount(booking))),
      ),
      refundAmount: toInt(financialData.refundAmount, 0),
      refundAmountPaise: toInt(
        financialData.refundAmountPaise,
        toPaise(toInt(financialData.refundAmount, 0)),
      ),
      pettxoCommissionAmount: toInt(financialData.pettxoCommissionAmount, 0),
      pettxoAmountPaise: toInt(
        financialData.pettxoAmountPaise,
        toPaise(toInt(financialData.pettxoCommissionAmount, 0)),
      ),
      providerEarningAmount: toInt(financialData.providerEarningAmount, 0),
      providerAmountPaise: toInt(
        financialData.providerAmountPaise,
        toPaise(toInt(financialData.providerEarningAmount, 0)),
      ),
      refundPercent: toInt(financialData.refundPercent, 0),
      pettxoPercent: toInt(financialData.pettxoPercent, 0),
      providerPercent: toInt(financialData.providerPercent, 0),
      cancellationCase: asTrimmedString(financialData.cancellationCase),
      disputeStatus: asTrimmedString(financialData.disputeStatus),
    };
  }

  const totalAmount = getBookingPaidAmount(booking);
  const standard = readStoredRevenueBreakdown(asRecord(booking.pricing), totalAmount);
  return {
    status: asTrimmedString(asRecord(booking.pricing).paymentStatus) || "paid",
    totalAmount,
    totalAmountPaise: toPaise(totalAmount),
    refundAmount: 0,
    refundAmountPaise: 0,
    pettxoCommissionAmount: standard.pettxoAmount,
    pettxoAmountPaise: standard.pettxoAmountPaise,
    providerEarningAmount: standard.providerAmount,
    providerAmountPaise: standard.providerAmountPaise,
    refundPercent: 0,
    pettxoPercent: standard.pettxoPercent,
    providerPercent: standard.providerPercent,
    cancellationCase: "",
    disputeStatus: asTrimmedString(asRecord(booking.dispute).status) || "none",
  };
}

async function processRazorpayRefund(params: {
  bookingId: string;
  refundAmount: number;
  razorpayPaymentId: string;
  reason: string;
}): Promise<{status: "pending" | "processed" | "failed"; razorpayRefundId: string; error: string; processedAt: Timestamp | null}> {
  console.log(JSON.stringify({
    event: "createBookingRefund.start",
    bookingId: params.bookingId,
    userId: "",
    providerId: "",
    razorpayOrderId: "",
    razorpayPaymentId: params.razorpayPaymentId,
    refundId: params.bookingId,
    amountPaise: Math.max(Math.round(params.refundAmount * 100), 0),
  }));
  if (params.refundAmount <= 0) {
    return {
      status: "processed",
      razorpayRefundId: "",
      error: "",
      processedAt: Timestamp.now(),
    };
  }

  const paymentId = asTrimmedString(params.razorpayPaymentId);
  const keyId = asTrimmedString(RAZORPAY_KEY_ID.value());
  const keySecret = asTrimmedString(RAZORPAY_KEY_SECRET.value());

  if (!paymentId || !keyId || !keySecret) {
    return {
      status: "pending",
      razorpayRefundId: "",
      error: !paymentId ?
        "Razorpay payment ID is missing for this booking." :
        "Razorpay credentials are not configured in Functions.",
      processedAt: null,
    };
  }

  try {
    const response = await fetch(
      `https://api.razorpay.com/v1/payments/${encodeURIComponent(paymentId)}/refund`,
      {
        method: "POST",
        headers: {
          "Authorization": `Basic ${Buffer.from(`${keyId}:${keySecret}`).toString("base64")}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: new URLSearchParams({
          amount: String(Math.max(Math.round(params.refundAmount * 100), 0)),
          speed: "optimum",
          notes: JSON.stringify({
            bookingId: params.bookingId,
            reason: params.reason,
          }),
        }).toString(),
      },
    );

    const json = await response.json() as Record<string, unknown>;
    if (!response.ok) {
      return {
        status: "failed",
        razorpayRefundId: "",
        error: safeText(json.error ?? json.description, "Refund request failed."),
        processedAt: null,
      };
    }

    return {
      status: "processed",
      razorpayRefundId: asTrimmedString(json.id),
      error: "",
      processedAt: Timestamp.now(),
    };
  } catch (error) {
    return {
      status: "failed",
      razorpayRefundId: "",
      error: error instanceof Error ? error.message : "Refund request failed.",
      processedAt: null,
    };
  } finally {
    console.log(JSON.stringify({
      event: "createBookingRefund.finish",
      bookingId: params.bookingId,
      userId: "",
      providerId: "",
      razorpayOrderId: "",
      razorpayPaymentId: params.razorpayPaymentId,
      refundId: params.bookingId,
      amountPaise: Math.max(Math.round(params.refundAmount * 100), 0),
    }));
  }
}

function hashOtp(bookingId: string, otp: string): string {
  return createHash("sha256").update(`${bookingId}:${otp}`).digest("hex");
}

function assertStatus(current: BookingStatus, expected: BookingStatus): void {
  if (current !== expected) {
    throw new HttpsError(
      "failed-precondition",
      `Booking must be ${expected}; current status is ${current}.`,
    );
  }
}

function toInt(value: unknown, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : fallback;
}

function toFiniteNumber(value: unknown, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function roundTo(value: number, decimals: number): number {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

function nextRatingAverage(currentAverage: number, currentCount: number, nextRating: number): number {
  const safeCount = Math.max(0, currentCount);
  const total = (currentAverage * safeCount) + nextRating;
  return roundTo(total / (safeCount + 1), 2);
}

function computeTrustScore(ratingAverage: number, completedBookingCount: number): number {
  const ratingSignal = Math.min(Math.max(ratingAverage / 5, 0), 1);
  const completionSignal = Math.min(Math.max(completedBookingCount, 0) / 25, 1);
  return Math.round(((ratingSignal * 0.8) + (completionSignal * 0.2)) * 100);
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

function effectiveDurationMinutes(service: DocumentData): number {
  const startMinutes = toInt(service.startMinutes, 0);
  const endMinutes = toInt(service.endMinutes, 0);
  const configured = toInt(service.sessionDurationMinutes, 60);
  if (configured > 0) return configured;
  if (endMinutes > startMinutes) return endMinutes - startMinutes;
  return 24 * 60;
}

function computeBookingRequestExpiresAt(nowMs: number, scheduledStartMs: number): Timestamp {
  const responseDeadlineMs = nowMs + requestResponseWindowMs;
  const serviceCutoffMs = scheduledStartMs - serviceResponseCutoffMs;
  return Timestamp.fromMillis(Math.min(responseDeadlineMs, serviceCutoffMs));
}

function requestHasExpired(booking: DocumentData, nowMs = Date.now()): boolean {
  const request = booking.request ?? {};
  const expiresAt = request.expiresAt as Timestamp | undefined;
  return !!expiresAt && expiresAt.toMillis() <= nowMs;
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
    const durationMinutes = effectiveDurationMinutes(service);
    const capacity = Math.max(toInt(service.capacity, 1), 1);
    const selectedDays = new Set(
      Array.isArray(service.availableDays) ? service.availableDays.map(String) : [],
    );
    const startMinutes = Math.max(toInt(service.startMinutes, 0), 0);
    const endMinutes = Math.min(toInt(service.endMinutes, 24 * 60), 24 * 60);
    const today = localDatePartsFromUtcMs(now);
    const todayMidnight = localMidnightUtcMs(today.year, today.month, today.day);

    if (
      selectedDays.size > 0 &&
      durationMinutes > 0 &&
      endMinutes > startMinutes
    ) {
      for (let dayOffset = 0; dayOffset < slotGenerationDays; dayOffset += 1) {
        const dayUtcMs = todayMidnight + dayOffset * 24 * 60 * 60 * 1000;
        const parts = localDatePartsFromUtcMs(dayUtcMs);
        if (!selectedDays.has(parts.weekday)) continue;

        const key = dateKey(parts.year, parts.month, parts.day);
        let cursor = startMinutes;
        while (cursor + durationMinutes <= endMinutes) {
          const slotStartMs = dayUtcMs + cursor * 60 * 1000;
          const slotEndMs = slotStartMs + durationMinutes * 60 * 1000;
          const slotId = `${key}_${cursor.toString().padStart(4, "0")}`;
          const slotRef = slotsRef.doc(slotId);
          queue((targetBatch) =>
            targetBatch.set(slotRef, {
              serviceId,
              serviceOwnerId: service.ownerUserId ?? "",
              startAt: Timestamp.fromMillis(slotStartMs),
              endAt: Timestamp.fromMillis(slotEndMs),
              dateKey: key,
              startMinutes: cursor,
              endMinutes: cursor + durationMinutes,
              durationMinutes,
              capacity,
              acceptedCount: 0,
              isBookable: slotStartMs - now >= minimumBookingLeadMs,
              status: slotStartMs - now >= minimumBookingLeadMs ? "open" : "closed",
              timezone: "Asia/Kolkata",
              generatedAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            }),
          );
          cursor += durationMinutes;
        }
      }
    }
  }

  if (writes > 0) batches.push(batch);
  await commitBatches(batches);
}

async function writeBookingEvent(params: {
  bookingId: string;
  actorId: string;
  actorType: "customer" | "provider" | "admin" | "system";
  type: string;
  fromStatus: string;
  toStatus: string;
  message: string;
  metadata?: Record<string, unknown>;
}): Promise<void> {
  await db.collection("bookings").doc(params.bookingId).collection("events").add({
    actorId: params.actorId,
    actorType: params.actorType,
    type: params.type,
    fromStatus: params.fromStatus,
    toStatus: params.toStatus,
    message: params.message,
    metadata: params.metadata ?? {},
    createdAt: FieldValue.serverTimestamp(),
  });
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
  return safeText(user.name ?? user.username, fallback);
}

function photoUrlFromUser(user: Record<string, unknown>): string {
  return safeText(user.profileImage, "");
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

function assertBookingRestrictions(
  restrictions: RestrictionMap,
  message = "Bookings are unavailable for this account.",
): void {
  if (restrictions.hard.isBanned || restrictions.booking.isBanned) {
    throw new HttpsError("failed-precondition", message);
  }
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

function snapshotName(snapshot: unknown, fallback: string): string {
  if (!snapshot || typeof snapshot !== "object") return fallback;
  const data = snapshot as Record<string, unknown>;
  return safeText(data.name ?? data.username, fallback);
}

function serviceTitleFromBooking(booking: DocumentData): string {
  const serviceSnapshot = booking.serviceSnapshot ?? {};
  return safeText(serviceSnapshot.title, "your service");
}

function queueBookingNotification(params: {
  transaction: Transaction;
  userId: string;
  bookingId: string;
  type: string;
  title: string;
  body: string;
  recipientRole: "customer" | "provider";
  actorId: string;
  status: string;
  booking: DocumentData;
  extraData?: Record<string, unknown>;
}): void {
  if (!params.userId) return;

  const notificationRef = db.collection("notifications").doc();
  params.transaction.set(notificationRef, {
    userId: params.userId,
    category: "booking",
    type: params.type,
    title: params.title,
    body: params.body,
    read: false,
    isRead: false,
    bookingId: params.bookingId,
    serviceId: params.booking.serviceId ?? "",
    recipientRole: params.recipientRole,
    actorId: params.actorId,
    data: {
      bookingId: params.bookingId,
      serviceId: params.booking.serviceId ?? "",
      slotId: params.booking.slotId ?? "",
      status: params.status,
      recipientRole: params.recipientRole,
      ...params.extraData,
    },
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
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
    code === "messaging/invalid-registration-token" ||
    code === "messaging/invalid-argument";
}

function notificationTokenDocId(token: string): string {
  return Buffer.from(token, "utf8").toString("base64url");
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
  gracePeriodEndsAt: Timestamp | null;
  reviewedAt: Timestamp | null;
  reviewedBy: string;
  rejectionReason: string;
};

function normalizeProviderVerification(data: DocumentData | undefined): ProviderVerificationSnapshot {
  return {
    status: asTrimmedString(data?.status) || "notSubmitted",
    gracePeriodEndsAt: data?.gracePeriodEndsAt instanceof Timestamp ? data.gracePeriodEndsAt as Timestamp : null,
    reviewedAt: data?.reviewedAt instanceof Timestamp ? data.reviewedAt as Timestamp : null,
    reviewedBy: asTrimmedString(data?.reviewedBy),
    rejectionReason: asTrimmedString(data?.rejectionReason),
  };
}

function shouldPauseServicesForVerification(verification: ProviderVerificationSnapshot, now = Timestamp.now()): boolean {
  if (verification.status === "approved") return false;
  if (!verification.gracePeriodEndsAt) return false;
  return verification.gracePeriodEndsAt.toMillis() <= now.toMillis();
}

function isServiceVerificationPaused(
  service: Record<string, unknown>,
  nowMs = Date.now(),
): boolean {
  if (service.isPausedByVerification === true) return true;
  const status = asTrimmedString(service.providerVerificationStatus);
  if (status === "approved") return false;
  const grace = service.providerVerificationGraceEndsAt instanceof Timestamp ?
    service.providerVerificationGraceEndsAt as Timestamp :
    null;
  if (!grace) return false;
  return grace.toMillis() <= nowMs;
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
  const currentTokenSnapshot = await tokenRef.get();
  const tokenPayload: Record<string, unknown> = {
    token,
    platform,
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
    currentUserId: uid,
    tokenMasked: maskIdentifier(token),
    removedFromUserIds: removedList,
    savedToUserId: uid,
  });

  return {
    currentUserId: uid,
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

  const existingTokenSnapshots = await db
    .collectionGroup("notificationTokens")
    .where("token", "==", token)
    .get();

  const removedFromUserIds = new Set<string>();
  const batch = db.batch();
  for (const doc of existingTokenSnapshots.docs) {
    const ownerUserId = doc.ref.parent.parent?.id ?? "";
    if (!ownerUserId) continue;
    removedFromUserIds.add(ownerUserId);
    batch.delete(doc.ref);
  }
  await batch.commit();

  const removedList = Array.from(removedFromUserIds);
  console.info("Notification token removed", {
    currentUserId: uid,
    tokenMasked: maskIdentifier(token),
    removedFromUserIds: removedList,
  });

  return {
    currentUserId: uid,
    removedFromUserIds: removedList,
  };
});

export const requestAccountDeletion = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const userRef = db.collection("users").doc(uid);
  const privateUserRef = db.collection("userPrivate").doc(uid);
  const servicesQuery = db
    .collection("services")
    .where("ownerUserId", "==", uid)
    .where("isDeleted", "==", false);

  const [userSnapshot, privateUserSnapshot, servicesSnapshot] = await Promise.all([
    userRef.get(),
    privateUserRef.get(),
    servicesQuery.get(),
  ]);

  if (!userSnapshot.exists) {
    throw new HttpsError("not-found", "Profile not found.");
  }

  const user = userSnapshot.data() ?? {};
  if (user.deletionRequested === true) {
    return {
      ok: true,
      message: "Your account deletion request is already in progress.",
    };
  }

  const restrictions = normalizeRestrictions(user.restrictions);
  const updatedRestrictions = nextRestrictions(
    nextRestrictions(restrictions, "social", true, "Account deletion requested", uid),
    "booking",
    true,
    "Account deletion requested",
    uid,
  );
  const nextAccountStatus = computeAccountStatus(updatedRestrictions);
  const anonymizedName = "Deleted user";
  const anonymizedUsername = `deleted_${uid.slice(-8).toLowerCase()}`;
  const now = FieldValue.serverTimestamp();

  const batch = db.batch();
  batch.set(userRef, {
    name: anonymizedName,
    username: anonymizedUsername,
    usernameLowercase: anonymizedUsername,
    bio: "",
    profileImage: "",
    city: "",
    state: "",
    location: "",
    accountStatus: nextAccountStatus,
    restrictions: updatedRestrictions,
    deletionRequested: true,
    deletionRequestedAt: now,
    profileVisibility: "hidden",
    updatedAt: now,
  }, {merge: true});
  batch.set(privateUserRef, {
    uid,
    deletionRequestedAt: now,
    deletionRequestStatus: "requested",
    updatedAt: now,
  }, {merge: true});

  for (const serviceDoc of servicesSnapshot.docs) {
    batch.set(serviceDoc.ref, {
      isActive: false,
      isPaused: true,
      isVisibleToMarketplace: false,
      pauseReason: "Account deletion requested",
      updatedAt: now,
    }, {merge: true});
  }

  batch.set(db.collection("adminAuditLogs").doc(), {
    eventType: "accountDeletionRequested",
    userId: uid,
    emailPresent: asTrimmedString(privateUserSnapshot.data()?.email) !== "",
    hadServices: servicesSnapshot.docs.length > 0,
    serviceCount: servicesSnapshot.docs.length,
    createdAt: now,
    actorUserId: uid,
    source: "mobileApp",
  });

  await batch.commit();
  const removedTokenCount = await deleteNotificationTokensForUser(uid);

  console.info("Account deletion requested", {
    userId: uid,
    removedTokenCount,
    serviceCount: servicesSnapshot.docs.length,
  });

  return {
    ok: true,
    message:
      "Your account deletion request has been submitted. Pettxo has restricted the account while records required for legal and payment retention are preserved.",
  };
});

export const sendPushForNotification = onDocumentWritten(
  {
    document: "notifications/{notificationId}",
    region: "us-central1",
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
    const notificationType = category === "chat" || String(notification.type ?? "") === "chatMessage" ?
      "chat" :
      String(notification.type ?? "");
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

    console.info("Notification created", {
      notificationId: event.params.notificationId,
      recipientUserId: recipientId,
      senderUserId: senderId,
      chatId,
      notificationType,
      targetTokenCount: tokens.length,
      skippedSenderTokenCount: skippedSenderTokens.length,
      skippedStaleTokenCount: skippedStaleTokens.length,
    });

    const response = await messaging.sendEachForMulticast({
      tokens,
      notification: {
        title: safeText(notification.title, "Pettxo booking update"),
        body: safeText(notification.body, "You have a new booking update."),
      },
      data,
      android: {
        priority: "high",
        notification: {
          sound: "default",
          tag: String(
            notification.bookingId ??
              notification.postId ??
              event.params.notificationId,
          ),
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
    });

    const cleanupBatch = db.batch();
    let cleanupCount = 0;
    response.responses.forEach((result, index) => {
      const code = result.error?.code;
      if (!result.success) {
        console.warn("Push delivery failed", {
          notificationId: event.params.notificationId,
          recipientUserId: recipientId,
          senderUserId: senderId,
          chatId,
          notificationType,
          targetTokenCount: tokens.length,
          skippedSenderTokenCount: skippedSenderTokens.length,
          skippedStaleTokenCount: skippedStaleTokens.length,
          tokenDocIdMasked: maskIdentifier(tokenDocs[index]?.id ?? ""),
          code: code ?? "unknown",
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
  },
);

export const enqueueServiceModeration = onDocumentCreated(
  {
    document: "services/{serviceId}",
    region: "us-central1",
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
    region: "us-central1",
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

    const relevantChange =
      beforeVerification.status !== afterVerification.status ||
      beforeVerification.gracePeriodEndsAt?.toMillis() !==
        afterVerification.gracePeriodEndsAt?.toMillis();

    if (!relevantChange) return;

    await updateProviderServicesForVerification(
      event.params.userId,
      afterVerification,
    );
  },
);

export const enqueueReportModeration = onDocumentCreated(
  {
    document: "reports/{reportId}",
    region: "us-central1",
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

export const createRazorpayBookingOrder = onCall({
  secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET],
}, async (request) => {
  const uid = requireUid(request.auth);
  const serviceId = asTrimmedString(request.data?.serviceId);
  const slotId = asTrimmedString(request.data?.slotId);
  const userId = asTrimmedString(request.data?.userId) || uid;
  const claimedOfferId = asTrimmedString(request.data?.claimedOfferId);

  if (!serviceId || !slotId) {
    throw new HttpsError("invalid-argument", "serviceId and slotId are required.");
  }
  if (userId !== uid) {
    throw new HttpsError("permission-denied", "userId must match the authenticated user.");
  }

  const serviceRef = db.collection("services").doc(serviceId);
  const slotRef = serviceRef.collection("slots").doc(slotId);
  const customerRef = db.collection("users").doc(uid);
  const bookingRef = db.collection("bookings").doc();
  const bookingFinancialRef = db.collection("bookingFinancials").doc(bookingRef.id);
  const paymentRef = db.collection("payments").doc(bookingRef.id);
  const claimedOfferRef = claimedOfferId ?
    customerRef.collection("claimedOffers").doc(claimedOfferId) :
    null;
  const existingPendingQuery = db
    .collection("bookings")
    .where("customerId", "==", uid)
    .where("serviceId", "==", serviceId)
    .where("slotId", "==", slotId)
    .where("status", "==", "paymentPending")
    .limit(5);

  const customerSnapshot = await customerRef.get();
  const customerData = customerSnapshot.exists ? customerSnapshot.data() ?? {} : {};
  assertBookingRestrictions(
    normalizeRestrictions(customerData.restrictions),
    "Your account cannot create new bookings right now.",
  );
  const completedBookingCount = claimedOfferId ?
    await getCompletedBookingCountForUser(uid, customerData) :
    0;

  const checkoutPayload = await db.runTransaction(async (transaction) => {
    const serviceSnapshot = await transaction.get(serviceRef);
    const slotSnapshot = await transaction.get(slotRef);
    const transactionCustomerSnapshot = await transaction.get(customerRef);
    const claimedOfferSnapshot = claimedOfferRef ? await transaction.get(claimedOfferRef) : null;
    const existingPendingSnapshots = await transaction.get(existingPendingQuery);

    if (!serviceSnapshot.exists) {
      throw new HttpsError("not-found", "Service not found.");
    }
    if (!slotSnapshot.exists) {
      throw new HttpsError("not-found", "Slot not found.");
    }

    const service = serviceSnapshot.data()!;
    const slot = slotSnapshot.data()!;
    const nowMs = Date.now();
    const transactionCustomer = transactionCustomerSnapshot.exists ?
      transactionCustomerSnapshot.data() ?? {} :
      {};
    assertBookingRestrictions(
      normalizeRestrictions(transactionCustomer.restrictions),
      "Your account cannot create new bookings right now.",
    );

    if (
      service.status !== "active" ||
      service.isActive !== true ||
      service.isDeleted === true ||
      service.isPaused === true ||
      service.isVisibleToMarketplace !== true
    ) {
      throw new HttpsError("failed-precondition", "This service is not bookable.");
    }
    if (isServiceVerificationPaused(service, nowMs)) {
      throw new HttpsError(
        "failed-precondition",
        "Provider verification is pending. This service is temporarily unavailable.",
      );
    }

    const serviceOwnerId = asTrimmedString(service.ownerUserId);
    if (!serviceOwnerId) {
      throw new HttpsError("failed-precondition", "Service owner is missing.");
    }
    if (serviceOwnerId === uid) {
      throw new HttpsError("failed-precondition", "You cannot book your own service.");
    }
    if (slot.serviceId !== serviceId || slot.serviceOwnerId !== serviceOwnerId) {
      throw new HttpsError("failed-precondition", "Slot does not belong to this service.");
    }
    if (slot.isBookable !== true || slot.status !== "open") {
      throw new HttpsError("failed-precondition", "This slot is not bookable.");
    }

    const capacity = Math.max(toInt(slot.capacity, 1), 1);
    const acceptedCount = Math.max(toInt(slot.acceptedCount, 0), 0);
    if (acceptedCount >= capacity) {
      throw new HttpsError("failed-precondition", "This slot is already full.");
    }

    const scheduledStartAt = slot.startAt as Timestamp | undefined;
    const scheduledEndAt = slot.endAt as Timestamp | undefined;
    if (!scheduledStartAt || !scheduledEndAt) {
      throw new HttpsError("failed-precondition", "Slot timing is missing.");
    }
    if (scheduledStartAt.toMillis() - nowMs < minimumBookingLeadMs) {
      throw new HttpsError("failed-precondition", "This slot is too soon to book.");
    }
    if (scheduledEndAt.toMillis() <= scheduledStartAt.toMillis()) {
      throw new HttpsError("failed-precondition", "Slot timing is invalid.");
    }

    for (const existingDoc of existingPendingSnapshots.docs) {
      const existingBooking = existingDoc.data();
      const existingPaymentRef = db.collection("payments").doc(existingDoc.id);
      const existingFinancialRef = db.collection("bookingFinancials").doc(existingDoc.id);
      const [existingPaymentSnapshot, existingFinancialSnapshot] = await Promise.all([
        transaction.get(existingPaymentRef),
        transaction.get(existingFinancialRef),
      ]);

      if (!isRetryablePaymentState({
        booking: existingBooking,
        payment: existingPaymentSnapshot.exists ? existingPaymentSnapshot.data() ?? {} : undefined,
        nowMs,
      })) {
        continue;
      }

      const existingPending = pendingPaymentSnapshotFromDocs({
        bookingId: existingDoc.id,
        booking: existingBooking,
        payment: existingPaymentSnapshot.exists ? existingPaymentSnapshot.data() ?? {} : undefined,
        bookingFinancial: existingFinancialSnapshot.exists ? existingFinancialSnapshot.data() ?? {} : undefined,
      });
      if (existingPending.orderId !== "" && existingPending.paymentStatus === "pending") {
        return existingPending;
      }

      const refreshedExpiry = paymentExpiryTimestamp(nowMs);
      transaction.set(existingDoc.ref, {
        paymentExpiresAt: refreshedExpiry,
        updatedAt: FieldValue.serverTimestamp(),
        "pricing.paymentStatus": "pending",
      }, {merge: true});
      transaction.set(existingFinancialRef, {
        paymentStatus: "pending",
        status: "pending",
        paymentExpiresAt: refreshedExpiry,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.set(existingPaymentRef, {
        paymentStatus: "pending",
        status: "pending",
        paymentExpiresAt: refreshedExpiry,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});

      return {
        ...existingPending,
        orderId: "",
        paymentStatus: "pending",
        paymentExpiresAt: refreshedExpiry,
      };
    }

    const price = Number(service.pricePerSession ?? 0);
    const currency = asTrimmedString(service.currency) || "INR";
    const bookingCreatedAt = Timestamp.now();
    const paymentExpiresAt = paymentExpiryTimestamp(nowMs);
    const durationMinutes = Math.round(
      (scheduledEndAt.toMillis() - scheduledStartAt.toMillis()) / 60000,
    );
    const ownerSnapshot = service.ownerSnapshot ?? {};
    const customer = transactionCustomerSnapshot.exists ? transactionCustomerSnapshot.data()! : {};
    const location = service.location ?? {};

    let discountAmount = 0;
    let appliedOfferData: Record<string, unknown> | null = null;

    if (claimedOfferRef && claimedOfferSnapshot) {
      if (!claimedOfferSnapshot.exists) {
        throw new OfferValidationError("Offer is no longer valid");
      }

      const claimedOffer = claimedOfferSnapshot.data() ?? {};
      const claimedStatus = asTrimmedString(claimedOffer.status);
      const claimedValidUntil = asDate(claimedOffer.validUntil);
      const usageLimit = toInt(claimedOffer.usageLimit, 0);
      const usedCount = Math.max(toInt(claimedOffer.usedCount, 0), 0);
      const minBookingAmount = asOptionalFiniteNumber(claimedOffer.minBookingAmount);
      const campaignType = asTrimmedString((claimedOffer.campaignSnapshot as Record<string, unknown> | undefined)?.campaignType);
      const discountType = asTrimmedString(claimedOffer.discountType);
      const discountValue = asOptionalFiniteNumber(claimedOffer.discountValue) ?? 0;
      const maxDiscountAmount = asOptionalFiniteNumber(claimedOffer.maxDiscountAmount);
      const offerId = asTrimmedString(claimedOffer.offerId);
      const couponCode = asTrimmedString(claimedOffer.couponCode);

      if (claimedStatus !== "claimed") {
        throw new OfferValidationError("Offer is no longer valid");
      }
      if (claimedValidUntil && claimedValidUntil.getTime() < nowMs) {
        throw new OfferValidationError("Offer is no longer valid");
      }
      if (usedCount >= usageLimit) {
        throw new OfferValidationError("Offer is no longer valid");
      }
      if (minBookingAmount != null && price < minBookingAmount) {
        throw new OfferValidationError("Offer is no longer valid");
      }
      if (campaignType === "firstBooking" && completedBookingCount > 0) {
        throw new OfferValidationError("Offer is no longer valid");
      }
      if (!isOfferDiscountType(discountType)) {
        throw new OfferValidationError("Offer is no longer valid");
      }

      const computed = computeOfferDiscount(
        price,
        discountType,
        discountValue,
        maxDiscountAmount,
      );
      discountAmount = computed.discountAmount;
      appliedOfferData = {
        claimedOfferId,
        offerId,
        couponCode,
        discountType,
        discountValue,
        discountAmount,
        status: "reserved",
      };
    }

    const pricing = computeCheckoutPricing({
      serviceAmount: price,
      discountAmount,
      currency,
    });

    const bookingPayload = {
      serviceId,
      slotId,
      serviceOwnerId,
      providerId: serviceOwnerId,
      customerId: uid,
      serviceSnapshot: {
        title: service.title ?? "",
        animalType: service.animalType ?? "",
        category: service.category ?? "",
        pricePerSession: price,
        currency,
        durationMinutes,
        serviceType: service.serviceType ?? "",
        primaryPhotoUrl: service.primaryPhotoUrl ?? "",
      },
      providerSnapshot: {
        name: ownerSnapshot.name ?? "",
        username: ownerSnapshot.username ?? "",
        photoUrl: ownerSnapshot.photoUrl ?? "",
        phoneMasked: "",
      },
      customerSnapshot: {
        name: customer.name ?? "",
        username: customer.username ?? "",
        photoUrl: customer.profileImage ?? "",
        phoneMasked: "",
      },
      locationSnapshot: {
        displayAddress: location.displayAddress ?? "",
        latitude: location.latitude ?? 0,
        longitude: location.longitude ?? 0,
        geohash: location.geohash ?? "",
      },
      scheduledStartAt,
      scheduledEndAt,
      timezone: "Asia/Kolkata",
      status: "paymentPending",
      paymentCreatedAt: bookingCreatedAt,
      paymentExpiresAt,
      request: {
        message: "",
        expiresAt: null,
        respondedAt: null,
        responseReason: "",
      },
      pricing: {
        serviceAmount: pricing.serviceAmount,
        serviceAmountPaise: pricing.serviceAmountPaise,
        grossAmount: pricing.serviceAmount,
        grossAmountPaise: pricing.serviceAmountPaise,
        discountAmount: pricing.discountAmount,
        discountAmountPaise: pricing.discountAmountPaise,
        finalAmount: pricing.totalPayable,
        finalAmountPaise: pricing.totalPayablePaise,
        platformFee: pricing.platformFee,
        platformFeePaise: pricing.platformFeePaise,
        providerEarnings: pricing.providerAmount,
        providerEarningsPaise: pricing.providerAmountPaise,
        currency,
        paymentStatus: "pending",
        payoutStatus: "notEligible",
      },
      ...(appliedOfferData == null ? {} : {offer: appliedOfferData}),
      otp: {
        status: "notGenerated",
        attempts: 0,
        maxAttempts: 5,
      },
      payoutReadiness: {
        status: "notEligible",
        reason: "Payment is pending.",
        eligibleAt: null,
        payoutId: "",
      },
      dispute: {
        hasDispute: false,
        disputeId: "",
        status: "none",
      },
      disputeStatus: "none",
      notificationState: {
        requestNotificationSent: false,
        acceptanceNotificationSent: false,
        rejectionNotificationSent: false,
        cancellationNotificationSent: false,
        otpNotificationSent: false,
        startNotificationSent: false,
        reminderNotificationSent: false,
        completionNotificationSent: false,
      },
      createdAt: bookingCreatedAt,
      updatedAt: bookingCreatedAt,
    };

    transaction.set(bookingRef, bookingPayload);
    transaction.set(bookingFinancialRef, {
      bookingId: bookingRef.id,
      userId: uid,
      providerId: serviceOwnerId,
      serviceId,
      totalAmount: pricing.totalPayable,
      totalAmountPaise: pricing.totalPayablePaise,
      serviceAmount: pricing.serviceAmount,
      serviceAmountPaise: pricing.serviceAmountPaise,
      currency,
      razorpayPaymentId: "",
      razorpayOrderId: "",
      status: "pending",
      paymentStatus: "pending",
      paymentExpiresAt,
      refundAmount: 0,
      refundAmountPaise: 0,
      pettxoCommissionAmount: pricing.platformFee,
      pettxoAmountPaise: pricing.platformFeePaise,
      providerEarningAmount: pricing.providerAmount,
      providerAmountPaise: pricing.providerAmountPaise,
      discountAmount: pricing.discountAmount,
      discountAmountPaise: pricing.discountAmountPaise,
      refundPercent: 0,
      pettxoPercent: 15,
      providerPercent: pricing.totalPayablePaise > 0 ?
        Math.round((pricing.providerAmountPaise / pricing.totalPayablePaise) * 100) :
        0,
      cancellationCase: "",
      cancelledBy: null,
      cancelledAt: null,
      disputeStatus: "none",
      otpUsed: false,
      serviceTime: scheduledStartAt,
      completedAt: null,
      payoutEligibleAt: null,
      createdAt: bookingCreatedAt,
      updatedAt: bookingCreatedAt,
    });
    transaction.set(paymentRef, {
      bookingId: bookingRef.id,
      userId: uid,
      providerId: serviceOwnerId,
      serviceId,
      status: "pending",
      paymentStatus: "pending",
      currency,
      amount: pricing.totalPayable,
      amountPaise: pricing.totalPayablePaise,
      serviceAmount: pricing.serviceAmount,
      serviceAmountPaise: pricing.serviceAmountPaise,
      platformFee: pricing.platformFee,
      platformFeePaise: pricing.platformFeePaise,
      discountAmount: pricing.discountAmount,
      discountAmountPaise: pricing.discountAmountPaise,
      razorpayOrderId: "",
      razorpayPaymentId: "",
      razorpaySignature: "",
      paymentExpiresAt,
      createdAt: bookingCreatedAt,
      updatedAt: bookingCreatedAt,
    });

    return {
      bookingId: bookingRef.id,
      orderId: "",
      amount: pricing.totalPayablePaise,
      amountPaise: pricing.totalPayablePaise,
      currency,
      serviceAmountPaise: pricing.serviceAmountPaise,
      platformFeePaise: pricing.platformFeePaise,
      discountPaise: pricing.discountAmountPaise,
      totalPayablePaise: pricing.totalPayablePaise,
      paymentExpiresAt,
      paymentStatus: "pending",
      providerId: serviceOwnerId,
      serviceId,
      slotId,
      scheduledStartAt,
      scheduledEndAt,
    };
  }).catch((error) => {
    if (error instanceof OfferValidationError) {
      throw new HttpsError("failed-precondition", error.message);
    }
    throw error;
  });
  const preparedCheckout = checkoutPayload;
  console.log(JSON.stringify({
    event: "createRazorpayBookingOrder.prepared",
    bookingId: preparedCheckout.bookingId,
    userId: uid,
    providerId: preparedCheckout.providerId,
    razorpayOrderIdMasked: maskIdentifier(preparedCheckout.orderId),
    razorpayPaymentIdMasked: "",
    refundId: "",
    amountPaise: preparedCheckout.totalPayablePaise,
    serviceId,
    slotId,
  }));

  if (preparedCheckout.orderId !== "") {
    const capturedPayment = (await fetchRazorpayOrderPayments({
      orderId: preparedCheckout.orderId,
    })).find((payment) => payment.status === "captured");

    if (capturedPayment) {
      await finalizeCapturedBookingPayment({
        bookingId: preparedCheckout.bookingId,
        uid,
        razorpayOrderId: preparedCheckout.orderId,
        razorpayPayment: capturedPayment,
      });
      return {
        ok: true,
        bookingId: preparedCheckout.bookingId,
        orderId: "",
        amount: 0,
        currency: capturedPayment.currency,
        keyId: "",
        serviceAmountPaise: preparedCheckout.serviceAmountPaise,
        platformFeePaise: preparedCheckout.platformFeePaise,
        discountPaise: preparedCheckout.discountPaise,
        totalPayablePaise: preparedCheckout.totalPayablePaise,
        paymentExpiresAt: "",
        alreadyVerified: true,
      };
    }
  }

  const paymentExpiresAt = preparedCheckout.paymentExpiresAt ?? paymentExpiryTimestamp(Date.now());

  const order = preparedCheckout.orderId !== "" ? {
    orderId: preparedCheckout.orderId,
    amount: preparedCheckout.amount,
    currency: preparedCheckout.currency,
    keyId: asTrimmedString(RAZORPAY_KEY_ID.value()),
  } : await createRazorpayOrder({
    bookingId: preparedCheckout.bookingId,
    amountPaise: preparedCheckout.amount,
    currency: preparedCheckout.currency,
    customerId: uid,
    serviceId,
    slotId,
  });

  await Promise.all([
    db.collection("bookings").doc(preparedCheckout.bookingId).set({
      paymentExpiresAt,
      "pricing.razorpayOrderId": order.orderId,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true}),
    db.collection("bookingFinancials").doc(preparedCheckout.bookingId).set({
      razorpayOrderId: order.orderId,
      paymentExpiresAt,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true}),
    db.collection("payments").doc(preparedCheckout.bookingId).set({
      razorpayOrderId: order.orderId,
      paymentExpiresAt,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true}),
  ]);
  console.log(JSON.stringify({
    event: "createRazorpayBookingOrder.success",
    bookingId: preparedCheckout.bookingId,
    userId: uid,
    providerId: preparedCheckout.providerId,
    razorpayOrderIdMasked: maskIdentifier(order.orderId),
    razorpayPaymentIdMasked: "",
    refundId: "",
    amountPaise: preparedCheckout.totalPayablePaise,
    serviceId,
    slotId,
  }));

  return {
    ok: true,
    bookingId: preparedCheckout.bookingId,
    orderId: order.orderId,
    amount: order.amount,
    currency: order.currency,
    keyId: order.keyId,
    serviceAmountPaise: preparedCheckout.serviceAmountPaise,
    platformFeePaise: preparedCheckout.platformFeePaise,
    discountPaise: preparedCheckout.discountPaise,
    totalPayablePaise: preparedCheckout.totalPayablePaise,
    paymentExpiresAt: paymentExpiresAt.toDate().toISOString(),
  };
});

export const getPendingPaymentBooking = onCall(async (request) => {
  const uid = requireUid(request.auth);
  const bookingId = asTrimmedString(request.data?.bookingId);
  const serviceId = asTrimmedString(request.data?.serviceId);
  const slotId = asTrimmedString(request.data?.slotId);

  let bookingSnapshot: DocumentSnapshot<DocumentData> | null = null;

  if (bookingId) {
    const snapshot = await db.collection("bookings").doc(bookingId).get();
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }
    bookingSnapshot = snapshot;
  } else {
    if (!serviceId || !slotId) {
      throw new HttpsError(
        "invalid-argument",
        "Provide bookingId or both serviceId and slotId.",
      );
    }
    const snapshots = await db
      .collection("bookings")
      .where("customerId", "==", uid)
      .where("serviceId", "==", serviceId)
      .where("slotId", "==", slotId)
      .where("status", "==", "paymentPending")
      .limit(5)
      .get();
    bookingSnapshot = snapshots.docs.find(
      (doc) => isRetryablePaymentState({
        booking: doc.data(),
        payment: undefined,
        nowMs: Date.now(),
      }),
    ) ?? null;
  }

  if (bookingSnapshot == null || !bookingSnapshot.exists) {
    return {"ok": true, "pendingBooking": null};
  }

  const booking = bookingSnapshot.data()!;
  if (asTrimmedString(booking.customerId) != uid) {
    throw new HttpsError("permission-denied", "Only the booking owner can access pending payment.");
  }

  const paymentSnapshot = await db.collection("payments").doc(bookingSnapshot.id).get();
  const bookingFinancialSnapshot = await db
    .collection("bookingFinancials")
    .doc(bookingSnapshot.id)
    .get();

  if (!isRetryablePaymentState({
    booking: booking,
    payment: paymentSnapshot.exists ? paymentSnapshot.data() ?? {} : undefined,
    nowMs: Date.now(),
  })) {
    return {"ok": true, "pendingBooking": null};
  }

  const pending = pendingPaymentSnapshotFromDocs({
    bookingId: bookingSnapshot.id,
    booking: booking,
    payment: paymentSnapshot.exists ? paymentSnapshot.data() ?? {} : undefined,
    bookingFinancial: bookingFinancialSnapshot.exists ? bookingFinancialSnapshot.data() ?? {} : undefined,
  });

  return {
    ok: true,
    pendingBooking: {
      bookingId: pending.bookingId,
      paymentStatus: pending.paymentStatus,
      razorpayOrderId: pending.orderId,
      paymentExpiresAt: pending.paymentExpiresAt?.toDate().toISOString(),
      serviceId: pending.serviceId,
      slotId: pending.slotId,
      providerId: pending.providerId,
      amountPaise: pending.totalPayablePaise,
      currency: pending.currency,
      serviceAmountPaise: pending.serviceAmountPaise,
      platformFeePaise: pending.platformFeePaise,
      discountPaise: pending.discountPaise,
      totalPayablePaise: pending.totalPayablePaise,
      scheduledStartAt: pending.scheduledStartAt?.toDate().toISOString(),
      scheduledEndAt: pending.scheduledEndAt?.toDate().toISOString(),
    },
  };
});

export const verifyRazorpayPayment = onCall({
  secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET],
}, async (request) => {
  const uid = requireUid(request.auth);
  const bookingId = asTrimmedString(request.data?.bookingId);
  const razorpayOrderId = asTrimmedString(request.data?.razorpay_order_id);
  const razorpayPaymentId = asTrimmedString(request.data?.razorpay_payment_id);
  const razorpaySignature = asTrimmedString(request.data?.razorpay_signature);

  if (!bookingId || !razorpayOrderId || !razorpayPaymentId || !razorpaySignature) {
    throw new HttpsError("invalid-argument", "Booking and Razorpay payment fields are required.");
  }

  const initialBookingSnapshot = await db.collection("bookings").doc(bookingId).get();
  if (!initialBookingSnapshot.exists) {
    throw new HttpsError("not-found", "Booking not found.");
  }
  const initialBooking = initialBookingSnapshot.data()!;
  if (asTrimmedString(initialBooking.customerId) !== uid) {
    throw new HttpsError("permission-denied", "Only the booking owner can verify payment.");
  }
  const initialStatus = asTrimmedString(initialBooking.status);
  const initialPaymentStatus = asTrimmedString(asRecord(initialBooking.pricing).paymentStatus);
  if (!(initialStatus === "paymentPending" || (initialStatus === "requested" && initialPaymentStatus === "paid"))) {
    throw new HttpsError("failed-precondition", "This booking is not awaiting payment.");
  }
  const initialStoredOrderId = asTrimmedString(asRecord(initialBooking.pricing).razorpayOrderId);
  if (!initialStoredOrderId || initialStoredOrderId !== razorpayOrderId) {
    throw new HttpsError("failed-precondition", "Razorpay order does not match this booking.");
  }
  if (!verifyRazorpaySignature({
    orderId: razorpayOrderId,
    paymentId: razorpayPaymentId,
    signature: razorpaySignature,
  })) {
    throw new HttpsError("permission-denied", "Payment signature verification failed.");
  }
  const razorpayPayment = await resolveCapturedRazorpayPayment({
    paymentId: razorpayPaymentId,
    orderId: razorpayOrderId,
  });
  if (razorpayPayment.id !== razorpayPaymentId) {
    throw new HttpsError("failed-precondition", "Razorpay payment ID is invalid.");
  }
  let providerId = "";
  console.log(JSON.stringify({
    event: "verifyRazorpayPayment.start",
    bookingId,
    userId: uid,
    providerId: asTrimmedString(initialBooking.serviceOwnerId ?? initialBooking.providerId),
    razorpayOrderIdMasked: maskIdentifier(razorpayOrderId),
    razorpayPaymentIdMasked: maskIdentifier(razorpayPaymentId),
    refundId: "",
    amountPaise: razorpayPayment.amountPaise,
  }));

  ({providerId} = await finalizeCapturedBookingPayment({
    bookingId,
    uid,
    razorpayOrderId,
    razorpayPayment,
  }));
  console.log(JSON.stringify({
    event: "verifyRazorpayPayment.success",
    bookingId,
    userId: uid,
    providerId,
    razorpayOrderIdMasked: maskIdentifier(razorpayOrderId),
    razorpayPaymentIdMasked: maskIdentifier(razorpayPaymentId),
    refundId: "",
    amountPaise: razorpayPayment.amountPaise,
  }));

  return {ok: true, bookingId};
});

export const markRazorpayPaymentFailed = onCall({
  secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET],
}, async (request) => {
  const uid = requireUid(request.auth);
  const bookingId = asTrimmedString(request.data?.bookingId);
  const code = asTrimmedString(request.data?.code);
  const message = asTrimmedString(request.data?.message);
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }

  const bookingRef = db.collection("bookings").doc(bookingId);
  const bookingFinancialRef = db.collection("bookingFinancials").doc(bookingId);
  const paymentRef = db.collection("payments").doc(bookingId);
  const initialBookingSnapshot = await bookingRef.get();
  if (!initialBookingSnapshot.exists) {
    throw new HttpsError("not-found", "Booking not found.");
  }
  const initialBooking = initialBookingSnapshot.data()!;
  if (asTrimmedString(initialBooking.customerId) !== uid) {
    throw new HttpsError("permission-denied", "Only the booking owner can update payment status.");
  }
  const storedPaymentId = asTrimmedString(
    asRecord(initialBooking.pricing).razorpayPaymentId,
  );
  let remotePaymentStatus = "";
  if (storedPaymentId !== "") {
    try {
      remotePaymentStatus = (
        await fetchRazorpayPayment({paymentId: storedPaymentId})
      ).status;
    } catch (_) {
      remotePaymentStatus = "";
    }
  }

  await db.runTransaction(async (transaction) => {
    const bookingSnapshot = await transaction.get(bookingRef);
    if (!bookingSnapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }
    const booking = bookingSnapshot.data()!;
    if (asTrimmedString(booking.customerId) !== uid) {
      throw new HttpsError("permission-denied", "Only the booking owner can update payment status.");
    }
    if (asTrimmedString(asRecord(booking.pricing).paymentStatus) === "paid") {
      return;
    }
    if (asTrimmedString(booking.status) !== "paymentPending") {
      return;
    }
    if (remotePaymentStatus == "captured" || remotePaymentStatus == "refunded") {
      return;
    }

    const nextPaymentStatus = remotePaymentStatus === "failed" ? "failed" : "pending";
    const nextFinancialStatus = remotePaymentStatus === "failed" ? "failed" : "pending";

    transaction.set(bookingRef, {
      updatedAt: FieldValue.serverTimestamp(),
      "pricing.paymentStatus": nextPaymentStatus,
      lastPaymentError: {
        code,
        message,
        recordedAt: FieldValue.serverTimestamp(),
      },
    }, {merge: true});
    transaction.set(bookingFinancialRef, {
      paymentStatus: nextPaymentStatus,
      status: nextFinancialStatus,
      lastPaymentError: {
        code,
        message,
        recordedAt: FieldValue.serverTimestamp(),
      },
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(paymentRef, {
      paymentStatus: nextPaymentStatus,
      status: nextFinancialStatus,
      lastPaymentError: {
        code,
        message,
        recordedAt: FieldValue.serverTimestamp(),
      },
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });

  return {ok: true};
});

export const razorpayWebhook = onRequest({
  secrets: [RAZORPAY_WEBHOOK_SECRET],
}, async (request, response) => {
  if (request.method !== "POST") {
    response.status(405).send("Method not allowed");
    return;
  }

  const signature = asTrimmedString(request.header("x-razorpay-signature"));
  if (!signature) {
    response.status(400).send("Missing signature");
    return;
  }

  try {
    const rawBody = request.rawBody as Buffer | undefined;
    if (!rawBody || !verifyRazorpayWebhookSignature({rawBody, signature})) {
      response.status(401).send("Invalid signature");
      return;
    }

    const payload = typeof request.body === "object" && request.body ?
      request.body as Record<string, unknown> :
      {};
    const eventName = asTrimmedString(payload.event);
    const paymentEntity = asRecord(asRecord(asRecord(payload.payload).payment).entity);
    const refundEntity = asRecord(asRecord(asRecord(payload.payload).refund).entity);
    const paymentId = asTrimmedString(paymentEntity.id);
    const orderId = asTrimmedString(paymentEntity.order_id);
    const refundId = asTrimmedString(refundEntity.id);
    const eventKey = refundId !== "" ?
      `${eventName}:${refundId}` :
      `${eventName}:${paymentId || orderId}`;
    const eventRef = db.collection("paymentWebhookEvents").doc(eventKey);

    const existingEvent = await eventRef.get();
    if (existingEvent.exists) {
      response.status(200).send("ok");
      return;
    }

    if (eventName === "payment.captured") {
      const paymentQuery = paymentId ?
        await db.collection("payments").where("razorpayPaymentId", "==", paymentId).limit(1).get() :
        await db.collection("payments").where("razorpayOrderId", "==", orderId).limit(1).get();
      if (!paymentQuery.empty) {
        const paymentDoc = paymentQuery.docs[0];
        const bookingId = paymentDoc.id;
        const bookingRef = db.collection("bookings").doc(bookingId);
        const bookingFinancialRef = db.collection("bookingFinancials").doc(bookingId);
        const invoiceRef = db.collection("invoices").doc(bookingId);
        const providerEarningRef = db.collection("providerEarnings").doc(bookingId);
        await db.runTransaction(async (transaction) => {
          const bookingSnapshot = await transaction.get(bookingRef);
          if (!bookingSnapshot.exists) return;
          const booking = bookingSnapshot.data() ?? {};
          if (asTrimmedString(booking.status) !== "paymentPending") return;
          const pricing = asRecord(booking.pricing);
          const scheduledStartAt = booking.scheduledStartAt as Timestamp | undefined;
          if (!scheduledStartAt) return;
          const requestExpiresAt = computeBookingRequestExpiresAt(
            Date.now(),
            scheduledStartAt.toMillis(),
          );
          if (requestExpiresAt.toMillis() <= Date.now()) return;

          const serviceAmountPaise = toInt(
            pricing.serviceAmountPaise,
            toInt(pricing.grossAmountPaise, 0),
          );
          const platformFeePaise = toInt(pricing.platformFeePaise, 0);
          const discountAmountPaise = toInt(pricing.discountAmountPaise, 0);
          const finalAmountPaise = toInt(
            pricing.finalAmountPaise,
            serviceAmountPaise + platformFeePaise - discountAmountPaise,
          );
          if (toInt(paymentEntity.amount, 0) != finalAmountPaise) return;
          const currency = asTrimmedString(pricing.currency) || "INR";
          if (asTrimmedString(paymentEntity.currency) && asTrimmedString(paymentEntity.currency) != currency) {
            return;
          }

          const paymentConfirmedAt = Timestamp.now();
          const graceWindow = buildGraceWindow(
            paymentConfirmedAt.toDate(),
            scheduledStartAt.toDate(),
          );
          const providerId = asTrimmedString(booking.serviceOwnerId ?? booking.providerId);

          transaction.set(bookingRef, {
            status: "requested",
            paymentConfirmedAt,
            paymentExpiresAt: null,
            graceWindowMinutes: graceWindow.graceWindowMinutes,
            graceWindowEndsAt: graceWindow.graceWindowEndsAt,
            updatedAt: FieldValue.serverTimestamp(),
            "request.expiresAt": requestExpiresAt,
            "pricing.paymentStatus": "paid",
            "pricing.razorpayOrderId": orderId,
            "pricing.razorpayPaymentId": paymentId,
            "notificationState.requestNotificationSent": true,
          }, {merge: true});
          transaction.set(bookingFinancialRef, {
            bookingId,
            userId: asTrimmedString(booking.customerId),
            providerId,
            serviceId: asTrimmedString(booking.serviceId),
            totalAmount: toMoneyAmount(fromPaise(finalAmountPaise)),
            totalAmountPaise: finalAmountPaise,
            serviceAmount: toMoneyAmount(fromPaise(serviceAmountPaise)),
            serviceAmountPaise,
            currency,
            razorpayPaymentId: paymentId,
            razorpayOrderId: orderId,
            status: "paid",
            paymentStatus: "paid",
            graceWindowMinutes: graceWindow.graceWindowMinutes,
            graceWindowEndsAt: graceWindow.graceWindowEndsAt,
            paymentConfirmedAt,
            refundAmount: 0,
            refundAmountPaise: 0,
            pettxoCommissionAmount: toMoneyAmount(fromPaise(platformFeePaise)),
            pettxoAmountPaise: platformFeePaise,
            providerEarningAmount: toMoneyAmount(fromPaise(serviceAmountPaise)),
            providerAmountPaise: serviceAmountPaise,
            discountAmount: toMoneyAmount(fromPaise(discountAmountPaise)),
            discountAmountPaise,
            refundPercent: 0,
            pettxoPercent: 15,
            providerPercent: finalAmountPaise > 0 ?
              Math.round((serviceAmountPaise / finalAmountPaise) * 100) :
              0,
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
          transaction.set(paymentDoc.ref, {
            status: "paid",
            paymentStatus: "paid",
            razorpayOrderId: orderId,
            razorpayPaymentId: paymentId,
            paymentConfirmedAt,
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
          transaction.set(invoiceRef, {
            invoiceId: bookingId,
            bookingId,
            userId: asTrimmedString(booking.customerId),
            providerId,
            serviceId: asTrimmedString(booking.serviceId),
            status: "issued",
            currency,
            serviceAmountPaise,
            platformFeePaise,
            discountAmountPaise,
            totalPayablePaise: finalAmountPaise,
            taxLabel: "GST",
            taxAmountPaise: 0,
            taxStatus: "Not applicable",
            issuedAt: paymentConfirmedAt,
            createdAt: paymentConfirmedAt,
            updatedAt: paymentConfirmedAt,
          }, {merge: true});
          transaction.set(providerEarningRef, {
            bookingId,
            providerId,
            userId: asTrimmedString(booking.customerId),
            serviceId: asTrimmedString(booking.serviceId),
            amount: toMoneyAmount(fromPaise(serviceAmountPaise)),
            amountPaise: serviceAmountPaise,
            pettxoCommissionAmount: toMoneyAmount(fromPaise(platformFeePaise)),
            pettxoCommissionAmountPaise: platformFeePaise,
            totalAmount: toMoneyAmount(fromPaise(finalAmountPaise)),
            totalAmountPaise: finalAmountPaise,
            source: "paidBooking",
            status: "notEligible",
            eligibleAt: null,
            paidAt: null,
            createdAt: paymentConfirmedAt,
            updatedAt: paymentConfirmedAt,
          }, {merge: true});

          queueBookingNotification({
            transaction,
            userId: providerId,
            bookingId,
            type: "bookingRequested",
            title: "New booking request",
            body: `${snapshotName(
              booking.customerSnapshot,
              "A pet parent",
            )} requested ${serviceTitleFromBooking(booking)}.`,
            recipientRole: "provider",
            actorId: asTrimmedString(booking.customerId),
            status: "requested",
            booking: {
              ...booking,
              status: "requested",
            },
            extraData: {event: "booking_requested_webhook"},
          });
        });
      }
    } else if (eventName === "payment.failed") {
      const paymentQuery = paymentId ?
        await db.collection("payments").where("razorpayPaymentId", "==", paymentId).limit(1).get() :
        await db.collection("payments").where("razorpayOrderId", "==", orderId).limit(1).get();
      if (!paymentQuery.empty) {
        const paymentDoc = paymentQuery.docs[0];
        await Promise.all([
          db.collection("bookings").doc(paymentDoc.id).set({
            "pricing.paymentStatus": "failed",
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true}),
          db.collection("bookingFinancials").doc(paymentDoc.id).set({
            paymentStatus: "failed",
            status: "failed",
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true}),
          paymentDoc.ref.set({
            paymentStatus: "failed",
            status: "failed",
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true}),
        ]);
      }
    } else if (eventName === "refund.processed" && refundId !== "") {
      const refundQuery = await db
        .collection("refunds")
        .where("razorpayPaymentId", "==", asTrimmedString(refundEntity.payment_id))
        .limit(5)
        .get();
      for (const refundDoc of refundQuery.docs) {
        await refundDoc.ref.set({
          status: "processed",
          razorpayRefundId: refundId,
          processedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }
    }

    await eventRef.set({
      event: eventName,
      paymentId,
      orderId,
      refundId,
      createdAt: FieldValue.serverTimestamp(),
    });
    response.status(200).send("ok");
  } catch (error) {
    console.error("razorpayWebhook.error", error);
    response.status(500).send("error");
  }
});

export const acceptBookingRequest = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const bookingId = String(request.data?.bookingId ?? "");
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }

  const bookingRef = db.collection("bookings").doc(bookingId);
  const providerRef = db.collection("users").doc(uid);
  let slotId = "";

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(bookingRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }

    const booking = snapshot.data()!;
    if (booking.serviceOwnerId !== uid) {
      throw new HttpsError("permission-denied", "Only the service owner can accept.");
    }

    assertStatus(booking.status as BookingStatus, "requested");
    if (requestHasExpired(booking)) {
      throw new HttpsError(
        "deadline-exceeded",
        "This booking request has expired and can no longer be accepted.",
      );
    }
    slotId = String(booking.slotId ?? "");
    const serviceId = String(booking.serviceId ?? "");
    if (!serviceId || !slotId) {
      throw new HttpsError("failed-precondition", "Booking slot is missing.");
    }

    const slotRef = db.collection("services").doc(serviceId).collection("slots").doc(slotId);
    const slotSnapshot = await transaction.get(slotRef);
    if (!slotSnapshot.exists) {
      throw new HttpsError("not-found", "Slot not found.");
    }

    const slot = slotSnapshot.data()!;
    if (slot.serviceId !== serviceId || slot.serviceOwnerId !== uid) {
      throw new HttpsError("failed-precondition", "Slot does not match this booking.");
    }

    const capacity = Math.max(toInt(slot.capacity, 1), 1);
    const acceptedCount = Math.max(toInt(slot.acceptedCount, 0), 0);
    if (acceptedCount >= capacity) {
      throw new HttpsError("failed-precondition", "This slot is already full.");
    }

    const nextAcceptedCount = acceptedCount + 1;
    transaction.update(slotRef, {
      acceptedCount: FieldValue.increment(1),
      isBookable: nextAcceptedCount < capacity,
      status: nextAcceptedCount >= capacity ? "full" : "open",
      updatedAt: FieldValue.serverTimestamp(),
    });

    transaction.update(bookingRef, {
      status: "accepted",
      acceptedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      "notificationState.acceptanceNotificationSent": true,
    });
    transaction.set(providerRef, {
      totalProviderBookings: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    queueBookingNotification({
      transaction,
      userId: String(booking.customerId ?? ""),
      bookingId,
      type: "bookingAccepted",
      title: "Booking confirmed",
      body: `${snapshotName(
        booking.providerSnapshot,
        "Your provider",
      )} accepted your ${serviceTitleFromBooking(booking)} booking.`,
      recipientRole: "customer",
      actorId: uid,
      status: "accepted",
      booking,
      extraData: {event: "booking_accepted"},
    });
  });

  await writeBookingEvent({
    bookingId,
    actorId: uid,
    actorType: "provider",
    type: "accepted",
    fromStatus: "requested",
    toStatus: "accepted",
    message: "Booking request accepted.",
    metadata: {slotId},
  });

  return {ok: true};
});

export const rejectBookingRequest = onCall({
  invoker: "public",
  secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET],
}, async (request) => {
  const uid = requireUid(request.auth);
  const bookingId = String(request.data?.bookingId ?? "");
  const reason = String(request.data?.reason ?? "Rejected by provider");
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }

  const bookingRef = db.collection("bookings").doc(bookingId);
  const bookingFinancialRef = db.collection("bookingFinancials").doc(bookingId);
  const paymentRef = db.collection("payments").doc(bookingId);
  const refundRef = db.collection("refunds").doc(bookingId);
  let refundAmountPaise = 0;
  let razorpayPaymentId = "";
  let providerId = "";

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(bookingRef);
    const bookingFinancialSnapshot = await transaction.get(bookingFinancialRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }

    const booking = snapshot.data()!;
    if (booking.serviceOwnerId !== uid) {
      throw new HttpsError("permission-denied", "Only the service owner can reject.");
    }

    assertStatus(booking.status as BookingStatus, "requested");
    if (requestHasExpired(booking)) {
      throw new HttpsError(
        "deadline-exceeded",
        "This booking request has expired and can no longer be rejected.",
      );
    }

    providerId = asTrimmedString(booking.serviceOwnerId ?? booking.providerId);
    refundAmountPaise = getBookingPaidAmountPaise(booking);
    razorpayPaymentId = asTrimmedString(
      bookingFinancialSnapshot.data()?.razorpayPaymentId ??
      asRecord(booking.pricing).razorpayPaymentId,
    );

    transaction.update(bookingRef, {
      status: "rejected",
      rejectedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      "request.respondedAt": FieldValue.serverTimestamp(),
      "request.responseReason": reason,
      "notificationState.rejectionNotificationSent": true,
      "pricing.paymentStatus": refundAmountPaise > 0 ? "refundPending" : "failed",
      "payoutReadiness.status": "cancelled",
      "payoutReadiness.reason": "Booking was rejected by the provider.",
      "payoutReadiness.eligibleAt": null,
    });
    transaction.set(bookingFinancialRef, {
      paymentStatus: refundAmountPaise > 0 ? "refundPending" : "failed",
      status: refundAmountPaise > 0 ? "refundPending" : "rejected",
      refundAmount: toMoneyAmount(fromPaise(refundAmountPaise)),
      refundAmountPaise,
      providerEarningAmount: 0,
      providerAmountPaise: 0,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(paymentRef, {
      paymentStatus: refundAmountPaise > 0 ? "refundPending" : "failed",
      status: refundAmountPaise > 0 ? "refundPending" : "failed",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(db.collection("providerEarnings").doc(bookingId), {
      bookingId,
      providerId,
      userId: asTrimmedString(booking.customerId),
      serviceId: asTrimmedString(booking.serviceId),
      amount: 0,
      amountPaise: 0,
      source: "providerRejected",
      status: "notEligible",
      eligibleAt: null,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    if (refundAmountPaise > 0) {
      transaction.set(refundRef, {
        bookingId,
        userId: asTrimmedString(booking.customerId),
        providerId,
        totalAmount: getBookingPaidAmount(booking),
        totalAmountPaise: refundAmountPaise,
        refundAmount: toMoneyAmount(fromPaise(refundAmountPaise)),
        refundAmountPaise,
        refundPercent: 100,
        razorpayPaymentId,
        reason,
        status: "pending",
        createdAt: FieldValue.serverTimestamp(),
        processedAt: null,
        error: "",
      }, {merge: true});
    }

    queueBookingNotification({
      transaction,
      userId: String(booking.customerId ?? ""),
      bookingId,
      type: "bookingRejected",
      title: "Booking request declined",
      body: `${snapshotName(
        booking.providerSnapshot,
        "The provider",
      )} declined your ${serviceTitleFromBooking(booking)} request.`,
      recipientRole: "customer",
      actorId: uid,
      status: "rejected",
      booking,
      extraData: {event: "booking_rejected"},
    });
  });

  await writeBookingEvent({
    bookingId,
    actorId: uid,
    actorType: "provider",
    type: "rejected",
    fromStatus: "requested",
    toStatus: "rejected",
    message: reason,
  });

  if (refundAmountPaise > 0) {
    const refundResult = await processRazorpayRefund({
      bookingId,
      refundAmount: refundAmountPaise / 100,
      razorpayPaymentId,
      reason,
    });
    await Promise.all([
      refundRef.set({
        status: refundResult.status,
        razorpayRefundId: refundResult.razorpayRefundId,
        processedAt: refundResult.processedAt,
        error: refundResult.error,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true}),
      bookingRef.set({
        "pricing.paymentStatus": refundResult.status === "processed" ?
          "refunded" :
          refundResult.status === "failed" ? "refundFailed" : "refundPending",
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true}),
      bookingFinancialRef.set({
        paymentStatus: refundResult.status === "processed" ? "refunded" : "refundPending",
        status: refundResult.status === "processed" ? "refunded" : "refundPending",
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true}),
      paymentRef.set({
        paymentStatus: refundResult.status === "processed" ? "refunded" : "refundPending",
        status: refundResult.status === "processed" ? "refunded" : "refundPending",
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true}),
    ]);
  }

  return {ok: true};
});

export const expireStaleBookingRequests = onSchedule(
  {
    schedule: "every 5 minutes",
    timeZone: "Asia/Kolkata",
    secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET],
  },
  async () => {
    const now = Timestamp.now();
    const expiredRequests = await db
      .collection("bookings")
      .where("status", "==", "requested")
      .where("request.expiresAt", "<=", now)
      .limit(100)
      .get();

    let expiredCount = 0;

    for (const doc of expiredRequests.docs) {
      let didExpire = false;
      let refundAmountPaise = 0;
      let razorpayPaymentId = "";
      let providerId = "";
      await db.runTransaction(async (transaction) => {
        const freshSnapshot = await transaction.get(doc.ref);
        const bookingFinancialRef = db.collection("bookingFinancials").doc(doc.id);
        const paymentRef = db.collection("payments").doc(doc.id);
        const refundRef = db.collection("refunds").doc(doc.id);
        const bookingFinancialSnapshot = await transaction.get(bookingFinancialRef);
        if (!freshSnapshot.exists) return;

        const booking = freshSnapshot.data()!;
        if (booking.status !== "requested" || !requestHasExpired(booking)) return;
        refundAmountPaise = getBookingPaidAmountPaise(booking);
        razorpayPaymentId = asTrimmedString(
          bookingFinancialSnapshot.data()?.razorpayPaymentId ??
          asRecord(booking.pricing).razorpayPaymentId,
        );
        providerId = asTrimmedString(booking.serviceOwnerId ?? booking.providerId);

        transaction.update(doc.ref, {
          status: "expired",
          expiredAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          "request.respondedAt": FieldValue.serverTimestamp(),
          "request.responseReason": "Auto-cancelled because provider did not respond in time.",
          "pricing.paymentStatus": refundAmountPaise > 0 ? "refundPending" : "expired",
        });
        transaction.set(bookingFinancialRef, {
          paymentStatus: refundAmountPaise > 0 ? "refundPending" : "expired",
          status: refundAmountPaise > 0 ? "refundPending" : "expired",
          refundAmount: toMoneyAmount(fromPaise(refundAmountPaise)),
          refundAmountPaise,
          providerEarningAmount: 0,
          providerAmountPaise: 0,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        transaction.set(paymentRef, {
          paymentStatus: refundAmountPaise > 0 ? "refundPending" : "expired",
          status: refundAmountPaise > 0 ? "refundPending" : "expired",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        transaction.set(db.collection("providerEarnings").doc(doc.id), {
          bookingId: doc.id,
          providerId,
          userId: asTrimmedString(booking.customerId),
          serviceId: asTrimmedString(booking.serviceId),
          amount: 0,
          amountPaise: 0,
          source: "providerTimeout",
          status: "notEligible",
          eligibleAt: null,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        if (refundAmountPaise > 0) {
          transaction.set(refundRef, {
            bookingId: doc.id,
            userId: asTrimmedString(booking.customerId),
            providerId,
            totalAmount: getBookingPaidAmount(booking),
            totalAmountPaise: refundAmountPaise,
            refundAmount: toMoneyAmount(fromPaise(refundAmountPaise)),
            refundAmountPaise,
            refundPercent: 100,
            razorpayPaymentId,
            reason: "Auto-cancelled because provider did not respond in time.",
            status: "pending",
            createdAt: FieldValue.serverTimestamp(),
            processedAt: null,
            error: "",
          }, {merge: true});
        }

        queueBookingNotification({
          transaction,
          userId: String(booking.customerId ?? ""),
          bookingId: doc.id,
          type: "bookingExpired",
          title: "Booking request expired",
          body: `${serviceTitleFromBooking(
            booking,
          )} was auto-cancelled because the provider did not respond in time.`,
          recipientRole: "customer",
          actorId: "system",
          status: "expired",
          booking,
          extraData: {event: "booking_expired"},
        });
        queueBookingNotification({
          transaction,
          userId: String(booking.serviceOwnerId ?? booking.providerId ?? ""),
          bookingId: doc.id,
          type: "bookingExpired",
          title: "Booking request expired",
          body: `The response timer ended for ${serviceTitleFromBooking(booking)}.`,
          recipientRole: "provider",
          actorId: "system",
          status: "expired",
          booking,
          extraData: {event: "booking_expired"},
        });

        didExpire = true;
      });

      if (didExpire) {
        expiredCount += 1;
        if (refundAmountPaise > 0) {
          const refundRef = db.collection("refunds").doc(doc.id);
          const bookingFinancialRef = db.collection("bookingFinancials").doc(doc.id);
          const paymentRef = db.collection("payments").doc(doc.id);
          const refundResult = await processRazorpayRefund({
            bookingId: doc.id,
            refundAmount: refundAmountPaise / 100,
            razorpayPaymentId,
            reason: "Auto-cancelled because provider did not respond in time.",
          });
          await Promise.all([
            refundRef.set({
              status: refundResult.status,
              razorpayRefundId: refundResult.razorpayRefundId,
              processedAt: refundResult.processedAt,
              error: refundResult.error,
              updatedAt: FieldValue.serverTimestamp(),
            }, {merge: true}),
            doc.ref.set({
              "pricing.paymentStatus": refundResult.status === "processed" ?
                "refunded" :
                refundResult.status === "failed" ? "refundFailed" : "refundPending",
              updatedAt: FieldValue.serverTimestamp(),
            }, {merge: true}),
            bookingFinancialRef.set({
              paymentStatus: refundResult.status === "processed" ? "refunded" : "refundPending",
              status: refundResult.status === "processed" ? "refunded" : "refundPending",
              updatedAt: FieldValue.serverTimestamp(),
            }, {merge: true}),
            paymentRef.set({
              paymentStatus: refundResult.status === "processed" ? "refunded" : "refundPending",
              status: refundResult.status === "processed" ? "refunded" : "refundPending",
              updatedAt: FieldValue.serverTimestamp(),
            }, {merge: true}),
          ]);
        }
        await writeBookingEvent({
          bookingId: doc.id,
          actorId: "system",
          actorType: "system",
          type: "expired",
          fromStatus: "requested",
          toStatus: "expired",
          message: "Booking request auto-cancelled after provider response timer expired.",
        });
      }
    }

    console.log(`Expired ${expiredCount} stale booking request(s).`);
  },
);

export const expirePendingPayments = onSchedule(
  {schedule: "every 5 minutes", timeZone: "Asia/Kolkata"},
  async () => {
    const now = Timestamp.now();
    const pendingBookings = await db
      .collection("bookings")
      .where("status", "==", "paymentPending")
      .where("paymentExpiresAt", "<=", now)
      .limit(100)
      .get();

    let expiredCount = 0;

    for (const doc of pendingBookings.docs) {
      let didExpire = false;
      let customerId = "";
      let providerId = "";
      await db.runTransaction(async (transaction) => {
        const bookingFinancialRef = db.collection("bookingFinancials").doc(doc.id);
        const paymentRef = db.collection("payments").doc(doc.id);
        const freshSnapshot = await transaction.get(doc.ref);
        if (!freshSnapshot.exists) return;

        const booking = freshSnapshot.data()!;
        customerId = asTrimmedString(booking.customerId);
        providerId = asTrimmedString(booking.serviceOwnerId ?? booking.providerId);
        if (asTrimmedString(booking.status) !== "paymentPending") return;
        const paymentExpiresAt = booking.paymentExpiresAt as Timestamp | undefined;
        if (!paymentExpiresAt || paymentExpiresAt.toMillis() > Date.now()) return;

        transaction.set(doc.ref, {
          status: "paymentExpired",
          expiredAt: FieldValue.serverTimestamp(),
          paymentExpiresAt: null,
          updatedAt: FieldValue.serverTimestamp(),
          "pricing.paymentStatus": "expired",
        }, {merge: true});
        transaction.set(bookingFinancialRef, {
          paymentStatus: "expired",
          status: "expired",
          paymentExpiresAt: null,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        transaction.set(paymentRef, {
          paymentStatus: "expired",
          status: "expired",
          paymentExpiresAt: null,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});

        didExpire = true;
      });

      if (didExpire) {
        expiredCount += 1;
        console.log(JSON.stringify({
          event: "expirePendingPayments.expired",
          bookingId: doc.id,
          userId: customerId,
          providerId,
          razorpayOrderId: "",
          razorpayPaymentId: "",
          refundId: "",
          amountPaise: 0,
        }));
        await writeBookingEvent({
          bookingId: doc.id,
          actorId: "system",
          actorType: "system",
          type: "paymentExpired",
          fromStatus: "paymentPending",
          toStatus: "paymentExpired",
          message: "Pending payment expired after 15 minutes.",
        });
      }
    }

    console.log(`Expired ${expiredCount} pending booking payment(s).`);
  },
);

export const cancelBooking = onCall({
  invoker: "public",
  secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET],
}, async (request) => {
  const uid = requireUid(request.auth);
  const bookingId = String(request.data?.bookingId ?? "");
  const reason = String(request.data?.reason ?? "Cancelled by user");
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }

  const bookingRef = db.collection("bookings").doc(bookingId);
  const bookingFinancialRef = db.collection("bookingFinancials").doc(bookingId);
  let fromStatus = "";
  let toStatus: BookingStatus = "cancelledByCustomer";
  let actorType: "customer" | "provider" = "customer";
  let releasedCapacity = false;
  let slotId = "";
  let refundAmount = 0;
  let razorpayPaymentId = "";
  let providerId = "";
  let finalPaymentStatus = "paid";
  let breakdown: CancellationBreakdown | null = null;
  let refundAmountPaise = 0;
  let cancellationSnapshot: Record<string, unknown> | null = null;
  let processedRefundStatus = "";
  const refundRef = db.collection("refunds").doc(bookingId);

  await db.runTransaction(async (transaction) => {
    const bookingSnapshot = await transaction.get(bookingRef);
    const bookingFinancialSnapshot = await transaction.get(bookingFinancialRef);
    const refundSnapshot = await transaction.get(refundRef);
    if (!bookingSnapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }

    const booking = bookingSnapshot.data()!;
    const status = booking.status as BookingStatus;
    fromStatus = String(status);

    const isCustomer = booking.customerId === uid;
    const isProvider = booking.serviceOwnerId === uid || booking.providerId === uid;
    if (!isCustomer && !isProvider) {
      throw new HttpsError("permission-denied", "Only booking participants can cancel.");
    }

    actorType = isProvider && !isCustomer ? "provider" : "customer";
    const cancellationActor: CancellationActor = actorType === "provider" ? "provider" : "user";
    const now = Timestamp.now();
    const nowMs = now.toMillis();

    if (
      status === "cancelledByCustomer" ||
      status === "cancelledByProvider"
    ) {
      breakdown = readExistingCancellationBreakdown(
        booking,
        bookingFinancialSnapshot.exists ? bookingFinancialSnapshot.data() ?? {} : undefined,
      );
      refundAmount = breakdown?.refundAmount ?? 0;
      refundAmountPaise = breakdown?.refundAmountPaise ?? 0;
      finalPaymentStatus = asTrimmedString(asRecord(booking.pricing).paymentStatus) || "paid";
      processedRefundStatus = refundSnapshot.exists ?
        asTrimmedString(refundSnapshot.data()?.status) :
        "";
      return;
    }

    canBookingBeCancelled(booking, cancellationActor, nowMs);

    const bookingTime = bookingCreatedAtDate(booking);
    const serviceTime = bookingServiceTimeDate(booking);
    if (!serviceTime) {
      throw new HttpsError("failed-precondition", "Booking service time is missing.");
    }

    breakdown = calculateCancellationBreakdown({
      bookingTime,
      serviceTime,
      cancellationTime: now.toDate(),
      otpUsed: hasOtpBeenUsed(booking),
      totalAmountPaise: getBookingPaidAmountPaise(booking),
      cancelledBy: cancellationActor,
    });
    refundAmount = breakdown.refundAmount;
    refundAmountPaise = breakdown.refundAmountPaise;
    finalPaymentStatus = paymentStatusForCancellation(breakdown);
    providerId = asTrimmedString(booking.serviceOwnerId ?? booking.providerId);
    razorpayPaymentId = asTrimmedString(
      (bookingFinancialSnapshot.data() ?? {}).razorpayPaymentId ??
      asRecord(booking.pricing).razorpayPaymentId,
    );
    cancellationSnapshot = buildCancellationSnapshot({
      breakdown,
      cancelledBy: uid,
      cancellationType: actorType,
      cancellationTime: now,
      serviceTime: booking.scheduledStartAt as Timestamp | undefined ?? Timestamp.now(),
      bookingTime: booking.createdAt as Timestamp | undefined ?? now,
      otpUsedAtCancellation: hasOtpBeenUsed(booking),
    });

    if (status === "requested") {
      if (!isCustomer) {
        throw new HttpsError(
          "failed-precondition",
          "Providers should reject requested bookings instead of cancelling.",
        );
      }
      toStatus = "cancelledByCustomer";
    } else if (status === "accepted") {
      toStatus = actorType === "provider" ? "cancelledByProvider" : "cancelledByCustomer";

      const serviceId = String(booking.serviceId ?? "");
      slotId = String(booking.slotId ?? "");
      if (!serviceId || !slotId) {
        throw new HttpsError("failed-precondition", "Booking slot is missing.");
      }

      const slotRef = db.collection("services").doc(serviceId).collection("slots").doc(slotId);
      const slotSnapshot = await transaction.get(slotRef);
      if (!slotSnapshot.exists) {
        throw new HttpsError("not-found", "Slot not found.");
      }

      const slot = slotSnapshot.data()!;
      const currentAcceptedCount = Math.max(toInt(slot.acceptedCount, 0), 0);
      const nextAcceptedCount = Math.max(currentAcceptedCount - 1, 0);
      const capacity = Math.max(toInt(slot.capacity, 1), 1);
      const slotStartAt = slot.startAt as Timestamp | undefined;
      const canBookAgain =
        nextAcceptedCount < capacity &&
        (!slotStartAt || slotStartAt.toMillis() - Date.now() >= 30 * 60 * 1000);

      transaction.update(slotRef, {
        acceptedCount: nextAcceptedCount,
        isBookable: canBookAgain,
        status: canBookAgain ? "open" : "closed",
        updatedAt: FieldValue.serverTimestamp(),
      });
      releasedCapacity = currentAcceptedCount > nextAcceptedCount;
    } else {
      throw new HttpsError(
        "failed-precondition",
        `Booking cannot be cancelled from status ${status}.`,
      );
    }

    transaction.update(bookingRef, {
      status: toStatus,
      cancelledAt: FieldValue.serverTimestamp(),
      cancelledBy: uid,
      cancellationLocked: true,
      cancellationProcessedAt: now,
      cancellationType: actorType,
      cancellationCase: breakdown.cancellationCase,
      updatedAt: FieldValue.serverTimestamp(),
      "pricing.paymentStatus": finalPaymentStatus,
      "payoutReadiness.status": "cancelled",
      "payoutReadiness.reason": "Booking was cancelled before payout eligibility.",
      "payoutReadiness.eligibleAt": null,
      disputeStatus: hasBlockingDispute(booking) ? "underReview" : "none",
      "notificationState.cancellationNotificationSent": true,
      cancellation: {
        actorId: uid,
        actorType,
        reason,
        releasedCapacity,
        cancelledAt: FieldValue.serverTimestamp(),
        refundAmount: breakdown.refundAmount,
        refundPercent: breakdown.refundPercent,
        pettxoAmount: breakdown.pettxoAmount,
        pettxoPercent: breakdown.pettxoPercent,
        providerAmount: breakdown.providerAmount,
        providerPercent: breakdown.providerPercent,
        cancellationCase: breakdown.cancellationCase,
        graceWindowMinutes: breakdown.graceWindowMinutes,
        graceWindowEndsAt: breakdown.graceWindowEndsAt,
        isWithinGraceWindow: breakdown.isWithinGraceWindow,
        snapshot: cancellationSnapshot,
      },
    });
    transaction.set(bookingFinancialRef, {
      bookingId,
      userId: asTrimmedString(booking.customerId),
      providerId,
      serviceId: asTrimmedString(booking.serviceId),
      totalAmount: getBookingPaidAmount(booking),
      totalAmountPaise: toPaise(getBookingPaidAmount(booking)),
      currency: getBookingCurrency(booking),
      razorpayPaymentId,
      status: hasBlockingDispute(booking) ? "disputed" : bookingFinancialStatusForCancellation(breakdown),
      refundAmount: breakdown.refundAmount,
      refundAmountPaise: breakdown.refundAmountPaise,
      pettxoCommissionAmount: breakdown.pettxoAmount,
      pettxoAmountPaise: breakdown.pettxoAmountPaise,
      providerEarningAmount: breakdown.providerAmount,
      providerAmountPaise: breakdown.providerAmountPaise,
      refundPercent: breakdown.refundPercent,
      pettxoPercent: breakdown.pettxoPercent,
      providerPercent: breakdown.providerPercent,
      cancellationCase: breakdown.cancellationCase,
      cancelledBy: actorType,
      cancelledAt: FieldValue.serverTimestamp(),
      cancellationLocked: true,
      cancellationProcessedAt: now,
      cancellationRequestId: bookingId,
      cancellationSnapshot,
      graceWindowMinutes: breakdown.graceWindowMinutes,
      graceWindowEndsAt: breakdown.graceWindowEndsAt,
      disputeStatus: hasBlockingDispute(booking) ? "underReview" : "none",
      otpUsed: false,
      serviceTime: booking.scheduledStartAt ?? null,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(db.collection("providerEarnings").doc(bookingId), {
      bookingId,
      providerId,
      userId: asTrimmedString(booking.customerId),
      serviceId: asTrimmedString(booking.serviceId),
      amount: breakdown.providerAmount,
      amountPaise: breakdown.providerAmountPaise,
      pettxoCommissionAmount: breakdown.pettxoAmount,
      pettxoCommissionAmountPaise: breakdown.pettxoAmountPaise,
      totalAmount: getBookingPaidAmount(booking),
      totalAmountPaise: toPaise(getBookingPaidAmount(booking)),
      source: actorType === "provider" ? "providerCancellation" : "userCancellation",
      status: breakdown.providerAmount > 0 ?
        (hasBlockingDispute(booking) ? "disputed" : "payoutEligible") :
        "cancelled",
      eligibleAt: breakdown.providerAmount > 0 ? Timestamp.now() : null,
      paidAt: null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    if (refundAmountPaise > 0) {
      transaction.set(refundRef, {
        bookingId,
        userId: asTrimmedString(booking.customerId),
        providerId,
        totalAmount: getBookingPaidAmount(booking),
        totalAmountPaise: toPaise(getBookingPaidAmount(booking)),
        refundAmount,
        refundAmountPaise: refundAmountPaise,
        refundPercent: breakdown.refundPercent,
        razorpayPaymentId,
        razorpayRefundId: "",
        reason,
        status: "pending",
        createdAt: FieldValue.serverTimestamp(),
        processedAt: null,
        error: "",
      });
    }

    if (actorType === "provider" && providerId) {
      const providerRef = db.collection("users").doc(providerId);
      const providerSnapshot = await transaction.get(providerRef);
      const providerData = providerSnapshot.exists ? providerSnapshot.data() ?? {} : {};
      const nextCancellationCount = Math.max(
        toInt(providerData.providerCancellationCount, 0) + 1,
        1,
      );
      const totalProviderBookings = Math.max(
        toInt(providerData.totalProviderBookings, 0),
        nextCancellationCount,
      );
      transaction.set(providerRef, {
        providerCancellationCount: nextCancellationCount,
        providerCancellationRate: roundTo(
          (nextCancellationCount / Math.max(totalProviderBookings, 1)) * 100,
          2,
        ),
        lastProviderCancellationAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    const recipientId =
      actorType === "customer" ?
        String(booking.serviceOwnerId ?? booking.providerId ?? "") :
        String(booking.customerId ?? "");
    const recipientRole = actorType === "customer" ? "provider" : "customer";
    const actorName =
      actorType === "customer" ?
        snapshotName(booking.customerSnapshot, "The customer") :
        snapshotName(booking.providerSnapshot, "The provider");

    queueBookingNotification({
      transaction,
      userId: recipientId,
      bookingId,
      type: "bookingCancelled",
      title: "Booking cancelled",
      body: `${actorName} cancelled ${serviceTitleFromBooking(booking)}.`,
      recipientRole,
      actorId: uid,
      status: toStatus,
      booking,
      extraData: {event: "booking_cancelled", releasedCapacity},
    });
  });

  if (refundAmountPaise > 0 && processedRefundStatus.length === 0) {
    const refundResult = await processRazorpayRefund({
      bookingId,
      refundAmount: refundAmountPaise / 100,
      razorpayPaymentId,
      reason,
    });
    await refundRef.set({
      status: refundResult.status,
      razorpayRefundId: refundResult.razorpayRefundId,
      processedAt: refundResult.processedAt,
      error: refundResult.error,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    await bookingRef.set({
      "pricing.paymentStatus": refundResult.status === "processed" ?
        finalPaymentStatus :
        refundResult.status === "failed" ? "refundFailed" : "refundPending",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }

  await writeBookingEvent({
    bookingId,
    actorId: uid,
    actorType,
    type: "cancelled",
    fromStatus,
    toStatus,
    message: reason,
    metadata: {releasedCapacity, slotId},
  });

  const resultBreakdown = breakdown ?? {
    refundAmount: 0,
    refundAmountPaise: 0,
    providerAmount: 0,
    providerAmountPaise: 0,
    pettxoAmount: 0,
    pettxoAmountPaise: 0,
    totalAmountPaise: 0,
    cancellationCase: "",
    refundPercent: 0,
    providerPercent: 0,
    pettxoPercent: 0,
    graceWindowMinutes: 0,
    isWithinGraceWindow: false,
    timeGapMinutes: 0,
  };

  return {
    ok: true,
    releasedCapacity,
    refundAmount: resultBreakdown.refundAmount,
    refundAmountPaise: resultBreakdown.refundAmountPaise,
    providerAmount: resultBreakdown.providerAmount,
    providerAmountPaise: resultBreakdown.providerAmountPaise,
    pettxoAmount: resultBreakdown.pettxoAmount,
    pettxoAmountPaise: resultBreakdown.pettxoAmountPaise,
    totalAmountPaise: resultBreakdown.totalAmountPaise,
    cancellationCase: resultBreakdown.cancellationCase,
    refundPercent: resultBreakdown.refundPercent,
    providerPercent: resultBreakdown.providerPercent,
    pettxoPercent: resultBreakdown.pettxoPercent,
    graceWindowMinutes: resultBreakdown.graceWindowMinutes,
    isWithinGraceWindow: resultBreakdown.isWithinGraceWindow,
  };
});

export const previewCancellation = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const bookingId = asTrimmedString(request.data?.bookingId);
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }

  const snapshot = await db.collection("bookings").doc(bookingId).get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Booking not found.");
  }

  const booking = snapshot.data() ?? {};
  const isCustomer = asTrimmedString(booking.customerId) === uid;
  const isProvider =
    asTrimmedString(booking.serviceOwnerId) === uid ||
    asTrimmedString(booking.providerId) === uid;
  if (!isCustomer && !isProvider) {
    throw new HttpsError("permission-denied", "Only booking participants can preview cancellation.");
  }

  const cancellationActor: CancellationActor = isProvider && !isCustomer ? "provider" : "user";
  const now = Timestamp.now();
  canBookingBeCancelled(booking, cancellationActor, now.toMillis());
  const serviceTime = bookingServiceTimeDate(booking);
  if (!serviceTime) {
    throw new HttpsError("failed-precondition", "Booking service time is missing.");
  }

  const breakdown = calculateCancellationBreakdown({
    bookingTime: bookingCreatedAtDate(booking),
    serviceTime,
    cancellationTime: now.toDate(),
    otpUsed: hasOtpBeenUsed(booking),
    totalAmountPaise: getBookingPaidAmountPaise(booking),
    cancelledBy: cancellationActor,
  });

  const message = cancellationActor === "provider" ?
    "Cancelling now will issue a full refund to the customer." :
    `Refund will be Rs. ${breakdown.refundAmount} based on the current cancellation timing.`;

  return {
    ok: true,
    refundAmount: breakdown.refundAmount,
    refundAmountPaise: breakdown.refundAmountPaise,
    providerAmount: breakdown.providerAmount,
    providerAmountPaise: breakdown.providerAmountPaise,
    pettxoAmount: breakdown.pettxoAmount,
    pettxoAmountPaise: breakdown.pettxoAmountPaise,
    totalAmountPaise: breakdown.totalAmountPaise,
    refundPercent: breakdown.refundPercent,
    providerPercent: breakdown.providerPercent,
    pettxoPercent: breakdown.pettxoPercent,
    cancellationCase: breakdown.cancellationCase,
    graceWindowMinutes: breakdown.graceWindowMinutes,
    graceWindowEndsAt: breakdown.graceWindowEndsAt.toDate().toISOString(),
    isWithinGraceWindow: breakdown.isWithinGraceWindow,
    message,
  };
});

export const raiseDispute = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const bookingId = asTrimmedString(request.data?.bookingId);
  const reason = asTrimmedString(request.data?.reason);
  const description = asTrimmedString(request.data?.description);
  if (!bookingId || !reason || !description) {
    throw new HttpsError(
      "invalid-argument",
      "bookingId, reason, and description are required.",
    );
  }

  const bookingRef = db.collection("bookings").doc(bookingId);
  const bookingFinancialRef = db.collection("bookingFinancials").doc(bookingId);
  const disputeRef = db.collection("disputes").doc(`${bookingId}_${uid}`);
  let raisedByRole = "user";

  await db.runTransaction(async (transaction) => {
    const [bookingSnapshot, financialSnapshot, existingDisputeSnapshot] = await Promise.all([
      transaction.get(bookingRef),
      transaction.get(bookingFinancialRef),
      transaction.get(disputeRef),
    ]);

    if (!bookingSnapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }

    const booking = bookingSnapshot.data() ?? {};
    const isCustomer = asTrimmedString(booking.customerId) === uid;
    const isProvider =
      asTrimmedString(booking.serviceOwnerId) === uid ||
      asTrimmedString(booking.providerId) === uid;
    if (!isCustomer && !isProvider) {
      throw new HttpsError("permission-denied", "Only booking participants can raise disputes.");
    }

    if (disputeWindowEndsAtForBooking(booking).getTime() < Date.now()) {
      throw new HttpsError("failed-precondition", "The dispute window has expired.");
    }

    if (hasBlockingDispute(booking)) {
      throw new HttpsError(
        "failed-precondition",
        "An active dispute already exists for this booking.",
      );
    }

    if (existingDisputeSnapshot.exists) {
      const existingStatus = asTrimmedString(existingDisputeSnapshot.data()?.status);
      if (existingStatus === "open" || existingStatus === "underReview") {
        throw new HttpsError(
          "failed-precondition",
          "An active dispute already exists for this booking.",
        );
      }
    }

    const financialData = financialSnapshot.exists ? financialSnapshot.data() ?? {} : undefined;
    raisedByRole = isProvider && !isCustomer ? "provider" : "user";
    transaction.set(disputeRef, {
      bookingId,
      raisedByUserId: uid,
      raisedByRole,
      customerId: asTrimmedString(booking.customerId),
      providerId: asTrimmedString(booking.serviceOwnerId ?? booking.providerId),
      reason,
      description,
      status: "open",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      bookingSnapshot: buildBookingSnapshotForDispute(bookingId, booking),
      financialSnapshot: buildFinancialSnapshotForDispute(financialData, booking),
    }, {merge: true});

    transaction.set(bookingRef, {
      dispute: {
        hasDispute: true,
        disputeId: disputeRef.id,
        status: "open",
      },
      disputeStatus: "open",
      payoutReadiness: {
        ...asRecord(booking.payoutReadiness),
        status: "hold",
        reason: "Payout is on hold while the dispute is under review.",
      },
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    transaction.set(bookingFinancialRef, {
      status: "disputed",
      disputeStatus: "open",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(db.collection("providerEarnings").doc(bookingId), {
      status: "disputed",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(db.collection("adminAuditLogs").doc(), {
      action: "booking.disputeRaised",
      bookingId,
      disputeId: disputeRef.id,
      raisedBy: uid,
      raisedByRole,
      createdAt: FieldValue.serverTimestamp(),
    });
  });

  await writeBookingEvent({
    bookingId,
    actorId: uid,
    actorType: raisedByRole === "provider" ? "provider" : "customer",
    type: "disputeRaised",
    fromStatus: "",
    toStatus: "",
    message: reason,
  });

  return {ok: true};
});

export const generateBookingOtp = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const bookingId = String(request.data?.bookingId ?? "");
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }

  const bookingRef = db.collection("bookings").doc(bookingId);
  const otp = randomInt(100000, 999999).toString();

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(bookingRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }

    const booking = snapshot.data()!;
    if (booking.customerId !== uid) {
      throw new HttpsError("permission-denied", "Only the customer can request the OTP.");
    }

    assertStatus(booking.status as BookingStatus, "accepted");

    const scheduledStartAt = booking.scheduledStartAt as Timestamp | undefined;
    if (
      scheduledStartAt &&
      Date.now() < scheduledStartAt.toMillis() - otpAvailabilityWindowMs
    ) {
      throw new HttpsError(
        "failed-precondition",
        "OTP can be generated 1 hour before service start.",
      );
    }

    transaction.update(bookingRef, {
      "otp.status": "generated",
      "otp.hash": hashOtp(bookingId, otp),
      "otp.attempts": 0,
      "otp.maxAttempts": 5,
      "otp.generatedAt": FieldValue.serverTimestamp(),
      "otp.expiresAt": Timestamp.fromMillis(Date.now() + otpValidityMs),
      "notificationState.otpNotificationSent": true,
      updatedAt: FieldValue.serverTimestamp(),
    });

    queueBookingNotification({
      transaction,
      userId: String(booking.serviceOwnerId ?? ""),
      bookingId,
      type: "bookingOtpGenerated",
      title: "OTP ready",
      body: `${snapshotName(
        booking.customerSnapshot,
        "The customer",
      )} generated the start OTP for ${serviceTitleFromBooking(booking)}.`,
      recipientRole: "provider",
      actorId: uid,
      status: "accepted",
      booking,
      extraData: {event: "otp_generated"},
    });
  });

  await writeBookingEvent({
    bookingId,
    actorId: uid,
    actorType: "customer",
    type: "otpGenerated",
    fromStatus: "accepted",
    toStatus: "accepted",
    message: "Booking OTP generated.",
  });

  return {otp};
});

export const verifyBookingOtpAndStart = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const bookingId = String(request.data?.bookingId ?? "");
  const otpAttempt = String(request.data?.otp ?? "");
  if (!bookingId || !otpAttempt) {
    throw new HttpsError("invalid-argument", "bookingId and otp are required.");
  }

  const bookingRef = db.collection("bookings").doc(bookingId);
  const bookingFinancialRef = db.collection("bookingFinancials").doc(bookingId);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(bookingRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }

    const booking = snapshot.data()!;
    if (booking.serviceOwnerId !== uid) {
      throw new HttpsError("permission-denied", "Only the provider can verify OTP.");
    }

    assertStatus(booking.status as BookingStatus, "accepted");

    const otp = booking.otp ?? {};
    if (otp.status !== "generated" || !otp.hash) {
      throw new HttpsError("failed-precondition", "OTP is not ready.");
    }

    const expiresAt = otp.expiresAt as Timestamp | undefined;
    if (expiresAt && expiresAt.toMillis() < Date.now()) {
      transaction.update(bookingRef, {
        "otp.status": "expired",
        updatedAt: FieldValue.serverTimestamp(),
      });
      throw new HttpsError("deadline-exceeded", "OTP expired.");
    }

    const expected = Buffer.from(String(otp.hash), "hex");
    const actual = Buffer.from(hashOtp(bookingId, otpAttempt), "hex");
    const isMatch = expected.length === actual.length && timingSafeEqual(expected, actual);
    if (!isMatch) {
      transaction.update(bookingRef, {
        "otp.attempts": FieldValue.increment(1),
        "otp.status": "failed",
        updatedAt: FieldValue.serverTimestamp(),
      });
      throw new HttpsError("permission-denied", "Invalid OTP.");
    }

    transaction.update(bookingRef, {
      status: "inProgress",
      startedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      "otp.status": "verified",
      "otp.verifiedAt": FieldValue.serverTimestamp(),
      "otp.verifiedBy": uid,
      "notificationState.startNotificationSent": true,
    });
    transaction.set(bookingFinancialRef, {
      bookingId,
      otpUsed: true,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    queueBookingNotification({
      transaction,
      userId: String(booking.customerId ?? ""),
      bookingId,
      type: "bookingStarted",
      title: "Service started",
      body: `${snapshotName(
        booking.providerSnapshot,
        "Your provider",
      )} started ${serviceTitleFromBooking(booking)}.`,
      recipientRole: "customer",
      actorId: uid,
      status: "inProgress",
      booking,
      extraData: {event: "service_started"},
    });
  });

  await writeBookingEvent({
    bookingId,
    actorId: uid,
    actorType: "provider",
    type: "otpVerified",
    fromStatus: "accepted",
    toStatus: "inProgress",
    message: "Booking OTP verified and service started.",
  });

  return {ok: true};
});

export const completeBooking = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const bookingId = String(request.data?.bookingId ?? "");
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }

  const bookingRef = db.collection("bookings").doc(bookingId);
  const payoutRef = db.collection("payoutReadiness").doc(bookingId);
  const bookingFinancialRef = db.collection("bookingFinancials").doc(bookingId);
  const providerEarningRef = db.collection("providerEarnings").doc(bookingId);
  const now = FieldValue.serverTimestamp();
  const completedAt = Timestamp.now();
  let providerId = "";

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(bookingRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }

    const booking = snapshot.data()!;
    if (booking.serviceOwnerId !== uid) {
      throw new HttpsError("permission-denied", "Only the provider can complete.");
    }
    assertStatus(booking.status as BookingStatus, "inProgress");

    providerId = booking.serviceOwnerId;
    const serviceId = String(booking.serviceId ?? "").trim();
    const customerId = asTrimmedString(booking.customerId);
    const totalAmount = getBookingPaidAmount(booking);
    const currency = getBookingCurrency(booking);
    const standardRevenue = readStoredRevenueBreakdown(
      asRecord(booking.pricing),
      totalAmount,
    );
    const payoutEligibleAt = Timestamp.fromMillis(completedAt.toMillis() + disputeWindowMs);
    const serviceRef = serviceId ? db.collection("services").doc(serviceId) : null;
    const providerRef = providerId ? db.collection("users").doc(providerId) : null;
    const [serviceSnapshot, providerSnapshot] = await Promise.all([
      serviceRef ? transaction.get(serviceRef) : Promise.resolve(null),
      providerRef ? transaction.get(providerRef) : Promise.resolve(null),
    ]);

    transaction.update(bookingRef, {
      status: "completed",
      completedAt,
      disputeStatus: hasBlockingDispute(booking) ? "underReview" : "none",
      updatedAt: now,
      "payoutReadiness.status": "hold",
      "payoutReadiness.reason": "Payout is held for 24 hours after completion unless a dispute is raised.",
      "payoutReadiness.eligibleAt": payoutEligibleAt,
      "notificationState.completionNotificationSent": true,
    });

    transaction.set(payoutRef, {
      bookingId,
      serviceId: booking.serviceId,
      providerId,
      customerId: booking.customerId,
      grossAmount: totalAmount,
      platformFee: standardRevenue.pettxoAmount,
      providerEarnings: standardRevenue.providerAmount,
      currency,
      status: "hold",
      eligibilityReason: "Payout unlocks 24 hours after completion if no dispute is raised.",
      eligibleAt: payoutEligibleAt,
      payoutId: "",
      createdAt: completedAt,
      updatedAt: now,
    });
    transaction.set(bookingFinancialRef, {
      bookingId,
      userId: customerId,
      providerId,
      serviceId,
      totalAmount,
      totalAmountPaise: toPaise(totalAmount),
      currency,
      status: hasBlockingDispute(booking) ? "disputed" : "completed",
      refundAmount: 0,
      refundAmountPaise: 0,
      pettxoCommissionAmount: standardRevenue.pettxoAmount,
      pettxoAmountPaise: standardRevenue.pettxoAmountPaise,
      providerEarningAmount: standardRevenue.providerAmount,
      providerAmountPaise: standardRevenue.providerAmountPaise,
      refundPercent: 0,
      pettxoPercent: standardRevenue.pettxoPercent,
      providerPercent: standardRevenue.providerPercent,
      disputeStatus: hasBlockingDispute(booking) ? "underReview" : "none",
      completedAt,
      payoutEligibleAt,
      updatedAt: now,
    }, {merge: true});
    transaction.set(providerEarningRef, {
      bookingId,
      providerId,
      userId: customerId,
      serviceId,
      amount: standardRevenue.providerAmount,
      amountPaise: standardRevenue.providerAmountPaise,
      pettxoCommissionAmount: standardRevenue.pettxoAmount,
      pettxoCommissionAmountPaise: standardRevenue.pettxoAmountPaise,
      totalAmount,
      totalAmountPaise: toPaise(totalAmount),
      source: "completedBooking",
      status: hasBlockingDispute(booking) ? "disputed" : "hold",
      eligibleAt: payoutEligibleAt,
      paidAt: null,
      createdAt: completedAt,
      updatedAt: now,
    }, {merge: true});

    if (serviceRef && serviceSnapshot?.exists == true) {
      const serviceData = serviceSnapshot.data() ?? {};
      const serviceStats = (serviceData.stats as Record<string, unknown> | undefined) ?? {};
      const currentCompletedCount = Math.max(
        0,
        toInt(serviceStats.completedBookingsCount ?? serviceData.completedBookingCount, 0),
      );
      const nextCompletedCount = currentCompletedCount + 1;
      const ratingAverage = toFiniteNumber(
        serviceStats.ratingAverage ?? serviceData.ratingAverage,
        0,
      );

      transaction.set(serviceRef, {
        completedBookingCount: nextCompletedCount,
        trustScore: computeTrustScore(ratingAverage, nextCompletedCount),
        stats: {
          ...serviceStats,
          completedBookingsCount: nextCompletedCount,
          trustScore: computeTrustScore(ratingAverage, nextCompletedCount),
        },
        updatedAt: now,
      }, {merge: true});
      console.log(
        "[completeBooking] service completedBookingCount updated",
        {
          bookingId,
          serviceId,
          previousCompletedBookingCount: currentCompletedCount,
          nextCompletedBookingCount: nextCompletedCount,
        },
      );
    }

    if (providerRef && providerSnapshot?.exists == true) {
      const providerData = providerSnapshot.data() ?? {};
      const currentCompletedCount = Math.max(
        0,
        toInt(providerData.completedBookingCount ?? providerData.completedBookingsCount, 0),
      );
      const nextCompletedCount = currentCompletedCount + 1;
      const ratingAverage = toFiniteNumber(providerData.ratingAverage, 0);

      transaction.set(providerRef, {
        completedBookingCount: nextCompletedCount,
        completedBookingsCount: nextCompletedCount,
        totalProviderBookings: Math.max(
          toInt(providerData.totalProviderBookings, 0),
          nextCompletedCount,
        ),
        trustScore: computeTrustScore(ratingAverage, nextCompletedCount),
        updatedAt: now,
      }, {merge: true});
      console.log(
        "[completeBooking] provider completedBookingCount updated",
        {
          bookingId,
          providerId,
          previousCompletedBookingCount: currentCompletedCount,
          nextCompletedBookingCount: nextCompletedCount,
        },
      );
    }

    queueBookingNotification({
      transaction,
      userId: String(booking.customerId ?? ""),
      bookingId,
      type: "bookingCompleted",
      title: "Service completed",
      body: `${serviceTitleFromBooking(booking)} has been marked complete.`,
      recipientRole: "customer",
      actorId: uid,
      status: "completed",
      booking,
      extraData: {event: "service_completed"},
    });
    queueBookingNotification({
      transaction,
      userId: providerId,
      bookingId,
      type: "bookingCompleted",
      title: "Payout eligibility updated",
      body: `${serviceTitleFromBooking(booking)} is complete. Payout eligibility is now ready.`,
      recipientRole: "provider",
      actorId: uid,
      status: "completed",
      booking,
      extraData: {event: "service_completed", payoutStatus: "eligible"},
    });
  });

  await writeBookingEvent({
    bookingId,
    actorId: uid,
    actorType: "provider",
    type: "completed",
    fromStatus: "inProgress",
    toStatus: "completed",
    message: "Booking completed and payout moved to the dispute hold window.",
    metadata: {providerId},
  });

  return {ok: true};
});

export const finalizeCompletedBookingPayoutEligibility = onSchedule(
  {schedule: "every 15 minutes", timeZone: "Asia/Kolkata"},
  async () => {
    const completedBookings = await db
      .collection("bookings")
      .where("status", "==", "completed")
      .limit(100)
      .get();

    let finalizedCount = 0;

    for (const doc of completedBookings.docs) {
      const booking = doc.data();
      const completedAt = asDate(booking.completedAt);
      if (!completedAt) continue;
      if (completedAt.getTime() + disputeWindowMs > Date.now()) continue;
      if (hasBlockingDispute(booking)) continue;
      if (asTrimmedString(asRecord(booking.payoutReadiness).status) === "eligible") continue;

      const bookingId = doc.id;
      const totalAmount = getBookingPaidAmount(booking);
      const currency = getBookingCurrency(booking);
      const standardRevenue = readStoredRevenueBreakdown(
        asRecord(booking.pricing),
        totalAmount,
      );
      const eligibleAt = Timestamp.now();

      await db.runTransaction(async (transaction) => {
        const freshBookingSnapshot = await transaction.get(doc.ref);
        if (!freshBookingSnapshot.exists) return;
        const freshBooking = freshBookingSnapshot.data() ?? {};
        const freshCompletedAt = asDate(freshBooking.completedAt);
        if (!freshCompletedAt) return;
        if (freshCompletedAt.getTime() + disputeWindowMs > Date.now()) return;
        if (hasBlockingDispute(freshBooking)) return;

        transaction.set(doc.ref, {
          payoutReadiness: {
            ...asRecord(freshBooking.payoutReadiness),
            status: "eligible",
            reason: "Payout is now eligible because the 24-hour dispute hold has passed.",
            eligibleAt,
          },
          disputeStatus: "none",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        transaction.set(db.collection("payoutReadiness").doc(bookingId), {
          bookingId,
          providerId: asTrimmedString(freshBooking.serviceOwnerId ?? freshBooking.providerId),
          customerId: asTrimmedString(freshBooking.customerId),
          serviceId: asTrimmedString(freshBooking.serviceId),
          grossAmount: totalAmount,
          platformFee: standardRevenue.pettxoAmount,
          providerEarnings: standardRevenue.providerAmount,
          currency,
          status: "eligible",
          eligibilityReason: "24-hour dispute hold passed after completed booking.",
          eligibleAt,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        transaction.set(db.collection("providerEarnings").doc(bookingId), {
          status: "payoutEligible",
          eligibleAt,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        transaction.set(db.collection("bookingFinancials").doc(bookingId), {
          status: "payoutEligible",
          payoutEligibleAt: eligibleAt,
          disputeStatus: "none",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        transaction.set(db.collection("adminAuditLogs").doc(), {
          action: "booking.payoutEligible",
          bookingId,
          providerId: asTrimmedString(freshBooking.serviceOwnerId ?? freshBooking.providerId),
          createdAt: FieldValue.serverTimestamp(),
        });
      });

      finalizedCount += 1;
    }

    console.log(`Marked ${finalizedCount} completed booking payout(s) as eligible.`);
  },
);

export const finalizeNoShows = onSchedule(
  {schedule: "every 30 minutes", timeZone: "Asia/Kolkata"},
  async () => {
    const acceptedBookings = await db
      .collection("bookings")
      .where("status", "==", "accepted")
      .limit(100)
      .get();

    let finalizedCount = 0;

    for (const doc of acceptedBookings.docs) {
      const booking = doc.data();
      const serviceTime = bookingServiceTimeDate(booking);
      if (!serviceTime) continue;
      if (serviceTime.getTime() + noShowFinalizationDelayMs > Date.now()) continue;
      if (hasOtpBeenUsed(booking)) continue;
      if (hasBlockingDispute(booking)) continue;

      const bookingId = doc.id;
      const totalAmount = getBookingPaidAmount(booking);
      const totalAmountPaise = getBookingPaidAmountPaise(booking);
      const currency = getBookingCurrency(booking);
      const eligibleAt = Timestamp.now();
      const providerId = asTrimmedString(booking.serviceOwnerId ?? booking.providerId);
      const customerId = asTrimmedString(booking.customerId);

      await db.runTransaction(async (transaction) => {
        const freshBookingSnapshot = await transaction.get(doc.ref);
        if (!freshBookingSnapshot.exists) return;
        const freshBooking = freshBookingSnapshot.data() ?? {};
        const freshServiceTime = bookingServiceTimeDate(freshBooking);
        if (!freshServiceTime) return;
        if (freshServiceTime.getTime() + noShowFinalizationDelayMs > Date.now()) return;
        if (hasOtpBeenUsed(freshBooking) || hasBlockingDispute(freshBooking)) return;
        if (asTrimmedString(freshBooking.status) !== "accepted") return;
        const storedRevenue = readStoredRevenueBreakdown(
          asRecord(freshBooking.pricing),
          totalAmount,
        );
        const pettxoAmountPaise = storedRevenue.pettxoAmountPaise;
        const providerAmountPaise = storedRevenue.providerAmountPaise;
        const noShowSnapshot = {
          refundPercent: 0,
          providerPercent: storedRevenue.providerPercent,
          pettxoPercent: storedRevenue.pettxoPercent,
          refundAmountPaise: 0,
          providerAmountPaise,
          pettxoAmountPaise,
          totalAmountPaise,
          cancellationCase: "noShow",
          cancelledBy: "system",
          cancellationType: "system",
          cancellationTime: eligibleAt,
          serviceTime: freshBooking.scheduledStartAt ?? null,
          bookingTime: freshBooking.createdAt ?? null,
          timeGapMinutes: 24 * 60,
          wasWithinGraceWindow: false,
          otpUsedAtCancellation: false,
        };

        transaction.set(doc.ref, {
          status: "noShow",
          noShowAt: eligibleAt,
          cancellationLocked: true,
          cancellationProcessedAt: eligibleAt,
          cancellationType: "system",
          cancelledBy: "system",
          cancelledAt: eligibleAt,
          cancellationCase: "noShow",
          disputeStatus: "none",
          updatedAt: FieldValue.serverTimestamp(),
          payoutReadiness: {
            ...asRecord(freshBooking.payoutReadiness),
            status: "eligible",
            reason: "Booking finalized as no-show after the service window passed without OTP verification.",
            eligibleAt,
          },
        }, {merge: true});
        transaction.set(db.collection("bookingFinancials").doc(bookingId), {
          bookingId,
          userId: customerId,
          providerId,
          serviceId: asTrimmedString(freshBooking.serviceId),
          totalAmount,
          totalAmountPaise,
          currency,
          status: "payoutEligible",
          refundAmount: 0,
          refundAmountPaise: 0,
          pettxoCommissionAmount: toMoneyAmount(fromPaise(pettxoAmountPaise)),
          pettxoAmountPaise,
          providerEarningAmount: toMoneyAmount(fromPaise(providerAmountPaise)),
          providerAmountPaise,
          refundPercent: 0,
          pettxoPercent: storedRevenue.pettxoPercent,
          providerPercent: storedRevenue.providerPercent,
          cancellationCase: "noShow",
          disputeStatus: "none",
          cancelledBy: "system",
          cancelledAt: eligibleAt,
          cancellationLocked: true,
          cancellationProcessedAt: eligibleAt,
          cancellationRequestId: bookingId,
          cancellationSnapshot: noShowSnapshot,
          serviceTime: freshBooking.scheduledStartAt ?? null,
          payoutEligibleAt: eligibleAt,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        transaction.set(db.collection("providerEarnings").doc(bookingId), {
          bookingId,
          providerId,
          userId: customerId,
          serviceId: asTrimmedString(freshBooking.serviceId),
          amount: toMoneyAmount(fromPaise(providerAmountPaise)),
          amountPaise: providerAmountPaise,
          pettxoCommissionAmount: toMoneyAmount(fromPaise(pettxoAmountPaise)),
          pettxoCommissionAmountPaise: pettxoAmountPaise,
          totalAmount,
          totalAmountPaise,
          source: "noShow",
          status: "payoutEligible",
          eligibleAt,
          paidAt: null,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        transaction.set(db.collection("payoutReadiness").doc(bookingId), {
          bookingId,
          providerId,
          customerId,
          serviceId: asTrimmedString(freshBooking.serviceId),
          grossAmount: totalAmount,
          platformFee: storedRevenue.pettxoAmount,
          providerEarnings: storedRevenue.providerAmount,
          currency,
          status: "eligible",
          eligibilityReason: "Booking finalized as no-show.",
          eligibleAt,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        transaction.set(db.collection("adminAuditLogs").doc(), {
          action: "booking.noShowFinalized",
          bookingId,
          providerId,
          createdAt: FieldValue.serverTimestamp(),
        });
      });

      await writeBookingEvent({
        bookingId,
        actorId: "system",
        actorType: "system",
        type: "noShowFinalized",
        fromStatus: "accepted",
        toStatus: "noShow",
        message: "Booking marked as no-show because the service time passed without OTP verification or a dispute.",
      });
      finalizedCount += 1;
    }

    console.log(`Finalized ${finalizedCount} no-show booking(s).`);
  },
);

export const submitBookingReview = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const bookingId = String(request.data?.bookingId ?? "").trim();
  const rating = toInt(request.data?.rating, 0);
  const comment = String(request.data?.comment ?? "").trim();
  const rawTags = Array.isArray(request.data?.tags) ? request.data?.tags : [];
  const tags = rawTags
    .map((value: unknown) => String(value ?? "").trim())
    .filter((value: string) => value.length > 0);

  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }
  if (rating < 1 || rating > 5) {
    throw new HttpsError("invalid-argument", "rating must be between 1 and 5.");
  }

  const bookingRef = db.collection("bookings").doc(bookingId);
  let reviewRefPath = "";
  const now = FieldValue.serverTimestamp();

  await db.runTransaction(async (transaction) => {
    const bookingSnapshot = await transaction.get(bookingRef);
    if (!bookingSnapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }

    const booking = bookingSnapshot.data()!;
    if ((booking.status as BookingStatus) !== "completed") {
      throw new HttpsError("failed-precondition", "Only completed bookings can be reviewed.");
    }
    if (String(booking.customerId ?? "") !== uid) {
      console.log("[submitBookingReview] invalid reviewer blocked", {
        bookingId,
        requesterUid: uid,
        customerId: String(booking.customerId ?? ""),
      });
      throw new HttpsError("permission-denied", "Only the booking customer can submit a review.");
    }

    const existingReviewId = String(booking.reviewId ?? booking.review?.reviewId ?? "").trim();
    const existingReviewStatus = String(
      booking.reviewStatus ?? booking.review?.status ?? "",
    ).trim();
    if (existingReviewId || existingReviewStatus.toLowerCase() === "submitted") {
      console.log("[submitBookingReview] duplicate review blocked", {
        bookingId,
        existingReviewId,
        existingReviewStatus,
        requesterUid: uid,
      });
      throw new HttpsError("failed-precondition", "Only one review is allowed per booking.");
    }

    const serviceId = String(booking.serviceId ?? "").trim();
    const providerUserId = String(
      booking.serviceOwnerId ?? booking.providerId ?? "",
    ).trim();
    if (!serviceId || !providerUserId) {
      throw new HttpsError(
        "failed-precondition",
        "Booking is missing service or provider details.",
      );
    }

    const reviewRef = db.collection("services").doc(serviceId).collection("reviews").doc(bookingId);
    const serviceRef = db.collection("services").doc(serviceId);
    const providerRef = db.collection("users").doc(providerUserId);
    reviewRefPath = reviewRef.path;

    const [reviewSnapshot, serviceSnapshot, providerSnapshot] = await Promise.all([
      transaction.get(reviewRef),
      transaction.get(serviceRef),
      transaction.get(providerRef),
    ]);
    if (reviewSnapshot.exists) {
      console.log("[submitBookingReview] duplicate review blocked", {
        bookingId,
        reviewPath: reviewRef.path,
        requesterUid: uid,
      });
      throw new HttpsError("failed-precondition", "Only one review is allowed per booking.");
    }
    if (!serviceSnapshot.exists) {
      throw new HttpsError("failed-precondition", "Service no longer exists.");
    }
    if (!providerSnapshot.exists) {
      throw new HttpsError("failed-precondition", "Provider profile no longer exists.");
    }

    const serviceData = serviceSnapshot.data() ?? {};
    const serviceStats = (serviceData.stats as Record<string, unknown> | undefined) ?? {};
    const currentServiceRatingCount = Math.max(
      0,
      toInt(serviceStats.ratingCount ?? serviceData.ratingCount, 0),
    );
    const currentServiceRatingAverage = toFiniteNumber(
      serviceStats.ratingAverage ?? serviceData.ratingAverage,
      0,
    );
    const currentServiceCompletedCount = Math.max(
      0,
      toInt(serviceStats.completedBookingsCount ?? serviceData.completedBookingCount, 0),
    );
    const nextServiceRatingCount = currentServiceRatingCount + 1;
    const nextServiceRatingAverage = nextRatingAverage(
      currentServiceRatingAverage,
      currentServiceRatingCount,
      rating,
    );
    const nextServiceTrustScore = computeTrustScore(
      nextServiceRatingAverage,
      currentServiceCompletedCount,
    );
    const currentServiceReviewedCount = Math.max(
      0,
      toInt(serviceStats.reviewedBookingCount ?? serviceData.reviewedBookingCount, 0),
    );

    const providerData = providerSnapshot.data() ?? {};
    const currentProviderRatingCount = Math.max(
      0,
      toInt(providerData.ratingCount, 0),
    );
    const currentProviderRatingAverage = toFiniteNumber(providerData.ratingAverage, 0);
    const currentProviderCompletedCount = Math.max(
      0,
      toInt(providerData.completedBookingCount ?? providerData.completedBookingsCount, 0),
    );
    const nextProviderRatingCount = currentProviderRatingCount + 1;
    const nextProviderRatingAverage = nextRatingAverage(
      currentProviderRatingAverage,
      currentProviderRatingCount,
      rating,
    );
    const nextProviderTrustScore = computeTrustScore(
      nextProviderRatingAverage,
      currentProviderCompletedCount,
    );
    const currentProviderReviewedCount = Math.max(
      0,
      toInt(providerData.reviewedBookingCount, 0),
    );

    const customerSnapshot = booking.customerSnapshot ?? {};
    transaction.set(reviewRef, {
      bookingId,
      serviceId,
      providerUserId,
      reviewerUserId: uid,
      reviewerId: uid,
      reviewerName: customerSnapshot.name ?? "",
      reviewerPhotoUrl: customerSnapshot.photoUrl ?? "",
      rating,
      comment,
      tags,
      isEdited: false,
      moderationStatus: "approved",
      createdAt: now,
      updatedAt: now,
    });

    transaction.update(bookingRef, {
      reviewStatus: "submitted",
      reviewId: reviewRef.id,
      review: {
        status: "submitted",
        reviewId: reviewRef.id,
        submittedAt: now,
      },
      updatedAt: now,
    });

    transaction.set(serviceRef, {
      ratingAverage: nextServiceRatingAverage,
      ratingCount: nextServiceRatingCount,
      reviewedBookingCount: currentServiceReviewedCount + 1,
      trustScore: nextServiceTrustScore,
      stats: {
        ...serviceStats,
        ratingAverage: nextServiceRatingAverage,
        ratingCount: nextServiceRatingCount,
        reviewedBookingCount: currentServiceReviewedCount + 1,
        trustScore: nextServiceTrustScore,
      },
      updatedAt: now,
    }, {merge: true});

    transaction.set(providerRef, {
      ratingAverage: nextProviderRatingAverage,
      ratingCount: nextProviderRatingCount,
      reviewedBookingCount: currentProviderReviewedCount + 1,
      trustScore: nextProviderTrustScore,
      updatedAt: now,
    }, {merge: true});

    console.log("[submitBookingReview] service rating summary updated", {
      bookingId,
      serviceId,
      ratingAverage: nextServiceRatingAverage,
      ratingCount: nextServiceRatingCount,
      trustScore: nextServiceTrustScore,
      reviewedBookingCount: currentServiceReviewedCount + 1,
    });
    console.log("[submitBookingReview] provider rating summary updated", {
      bookingId,
      providerUserId,
      ratingAverage: nextProviderRatingAverage,
      ratingCount: nextProviderRatingCount,
      trustScore: nextProviderTrustScore,
      reviewedBookingCount: currentProviderReviewedCount + 1,
    });
  });

  await writeBookingEvent({
    bookingId,
    actorId: uid,
    actorType: "customer",
    type: "reviewSubmitted",
    fromStatus: "completed",
    toStatus: "completed",
    message: "Booking review submitted.",
    metadata: {reviewRefPath, rating},
  });

  return {ok: true, reviewId: bookingId};
});

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

  const data = asRecord(request.data);
  assertAllowedOfferKeys(data, offerCampaignMutableFields);
  const normalized = normalizeOfferPayload(data, {requireAllFields: true});

  const campaignRef = db.collection("offerCampaigns").doc();
  const batch = db.batch();
  batch.set(campaignRef, {
    ...normalized,
    isActive: asBoolean(data.isActive, false),
    createdAt: FieldValue.serverTimestamp(),
    createdBy: admin.uid,
    createdByRole: admin.role,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: admin.uid,
    updatedByRole: admin.role,
  });
  writeOfferAuditLog(batch, admin, "offerCampaign.create", campaignRef.id, {
    couponCode: normalized.couponCode,
    displayType: normalized.displayType,
    campaignType: normalized.campaignType,
  });
  await batch.commit();

  return {ok: true, campaignId: campaignRef.id};
});

export const updateOfferCampaign = onCall(async (request) => {
  const adminUid = requireUid(request.auth);
  const admin = await requireAdminActor(adminUid);
  assertOfferMutationPermission(admin.role);

  const data = asRecord(request.data);
  const campaignId = asTrimmedString(data.campaignId);
  if (!campaignId) {
    throw new HttpsError("invalid-argument", "campaignId is required.");
  }

  const updateData: Record<string, unknown> = {...data};
  delete updateData.campaignId;
  assertAllowedOfferKeys(updateData, offerCampaignMutableFields);
  if (Object.keys(updateData).length === 0) {
    throw new HttpsError("invalid-argument", "At least one offer field must be provided.");
  }

  const campaignRef = db.collection("offerCampaigns").doc(campaignId);
  const snapshot = await campaignRef.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Offer campaign not found.");
  }

  const existingData = snapshot.data() ?? {};
  const mergedData: Record<string, unknown> = {
    ...existingData,
    ...updateData,
    targeting: updateData.targeting === undefined ?
      existingData.targeting :
      {...asRecord(existingData.targeting), ...asRecord(updateData.targeting)},
  };
  const normalized = normalizeOfferPayload(mergedData, {requireAllFields: true});

  const batch = db.batch();
  batch.set(campaignRef, {
    ...normalized,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: admin.uid,
    updatedByRole: admin.role,
  }, {merge: true});
  writeOfferAuditLog(batch, admin, "offerCampaign.update", campaignId, {
    updatedFields: Object.keys(updateData),
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

export const getEligibleOffers = onCall(async (request) => {
  const uid = requireUid(request.auth);
  const userRef = db.collection("users").doc(uid);
  const userSnapshot = await userRef.get();
  if (!userSnapshot.exists) {
    throw new HttpsError("not-found", "User document not found.");
  }

  const userData = userSnapshot.data() ?? {};
  const completedBookingCount = await getCompletedBookingCountForUser(uid, userData);
  const now = new Date();
  const campaignsSnapshot = await db
    .collection("offerCampaigns")
    .where("isActive", "==", true)
    .get();

  const offersWithMeta = await Promise.all(campaignsSnapshot.docs.map(async (doc) => {
    const normalized = normalizeOfferPayload(doc.data() ?? {}, {requireAllFields: true});
    if (!isOfferLive(normalized, now)) return null;
    if (!isOfferEligibleForUser(normalized, completedBookingCount)) return null;
    if (await hasClaimedOfferCampaign(uid, doc.id)) return null;
    return {
      id: doc.id,
      createdAt: asDate(doc.data().createdAt),
      offer: toEligibleOfferResponse(doc.id, normalized),
    };
  }));

  const offers = offersWithMeta
    .filter((entry): entry is NonNullable<typeof entry> => entry != null)
    .sort((left, right) => {
      if (right.offer.priority !== left.offer.priority) {
        return right.offer.priority - left.offer.priority;
      }
      const rightCreatedAt = right.createdAt?.getTime() ?? 0;
      const leftCreatedAt = left.createdAt?.getTime() ?? 0;
      return rightCreatedAt - leftCreatedAt;
    })
    .map((entry) => entry.offer);

  return {
    ok: true,
    offerWall: offers.find((offer) => offer.displayType === "offerWall") ?? null,
    popup: offers.find((offer) => offer.displayType === "popup") ?? null,
    offers,
  };
});

export const claimOffer = onCall(async (request) => {
  const uid = requireUid(request.auth);
  const data = asRecord(request.data);
  const campaignId = asTrimmedString(data.campaignId);
  const sourceDisplayType = asTrimmedString(data.sourceDisplayType);

  if (!campaignId) {
    throw new HttpsError("invalid-argument", "campaignId is required.");
  }
  if (!isOfferDisplayType(sourceDisplayType)) {
    throw new HttpsError("invalid-argument", "sourceDisplayType must be offerWall or popup.");
  }

  const userRef = db.collection("users").doc(uid);
  const campaignRef = db.collection("offerCampaigns").doc(campaignId);
  const claimedOfferRef = userRef.collection("claimedOffers").doc(campaignId);
  const now = new Date();

  const [userSnapshot, campaignSnapshot] = await Promise.all([
    userRef.get(),
    campaignRef.get(),
  ]);
  if (!userSnapshot.exists) {
    throw new HttpsError("not-found", "User document not found.");
  }
  if (!campaignSnapshot.exists) {
    throw new HttpsError("not-found", "Offer campaign not found.");
  }

  const userData = userSnapshot.data() ?? {};
  const completedBookingCount = await getCompletedBookingCountForUser(uid, userData);

  await db.runTransaction(async (transaction) => {
    const [freshCampaignSnapshot, freshClaimedSnapshot] = await Promise.all([
      transaction.get(campaignRef),
      transaction.get(claimedOfferRef),
    ]);

    if (!freshCampaignSnapshot.exists) {
      throw new HttpsError("not-found", "Offer campaign not found.");
    }
    if (freshClaimedSnapshot.exists) {
      throw new HttpsError("already-exists", "Offer already claimed.");
    }

    const normalized = normalizeOfferPayload(freshCampaignSnapshot.data() ?? {}, {requireAllFields: true});
    if (!isOfferLive(normalized, now)) {
      throw new HttpsError("failed-precondition", "Offer is no longer available.");
    }
    if (!isOfferEligibleForUser(normalized, completedBookingCount)) {
      throw new HttpsError("failed-precondition", "You are not eligible for this offer.");
    }

    const validUntil = computeOfferValidUntil(normalized, now);
    transaction.set(claimedOfferRef, {
      offerId: campaignId,
      couponCode: normalized.couponCode,
      discountType: normalized.discountType,
      discountValue: normalized.discountValue,
      maxDiscountAmount: normalized.maxDiscountAmount,
      minBookingAmount: normalized.minBookingAmount,
      claimedAt: FieldValue.serverTimestamp(),
      validUntil,
      usageLimit: normalized.usageLimitPerUser,
      usedCount: 0,
      status: "claimed",
      sourceDisplayType,
      campaignSnapshot: {
        title: normalized.title,
        description: normalized.description,
        imageUrl: normalized.imageUrl,
        couponCode: normalized.couponCode,
        displayType: normalized.displayType,
        campaignType: normalized.campaignType,
        discountType: normalized.discountType,
        discountValue: normalized.discountValue,
        maxDiscountAmount: normalized.maxDiscountAmount,
        minBookingAmount: normalized.minBookingAmount,
        claimValidityType: normalized.claimValidityType,
        usageLimitPerUser: normalized.usageLimitPerUser,
        startAt: Timestamp.fromDate(normalized.startAt),
        endAt: normalized.endAt ? Timestamp.fromDate(normalized.endAt) : null,
        version: 1,
      },
    });
    transaction.set(campaignRef, {
      claimCount: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(db.collection("adminAuditLogs").doc(), {
      action: "offer.claim",
      targetType: "offerCampaign",
      targetId: campaignId,
      performedBy: uid,
      performedByRole: "user",
      createdAt: FieldValue.serverTimestamp(),
      metadata: {
        claimedOfferId: claimedOfferRef.id,
        sourceDisplayType,
      },
    });
  });

  return {
    ok: true,
    claimedOfferId: claimedOfferRef.id,
  };
});

export const previewOfferForBooking = onCall(async (request) => {
  const uid = requireUid(request.auth);
  const data = asRecord(request.data);
  const claimedOfferId = asTrimmedString(data.claimedOfferId);
  const bookingAmount = asOptionalFiniteNumber(data.bookingAmount);

  if (!claimedOfferId) {
    throw new HttpsError("invalid-argument", "claimedOfferId is required.");
  }
  if (bookingAmount == null || bookingAmount < 0) {
    throw new HttpsError("invalid-argument", "bookingAmount must be 0 or greater.");
  }

  const claimedOfferSnapshot = await db
    .collection("users")
    .doc(uid)
    .collection("claimedOffers")
    .doc(claimedOfferId)
    .get();

  if (!claimedOfferSnapshot.exists) {
    return {
      ok: true,
      isValid: false,
      message: "Claimed offer not found.",
      claimedOfferId,
      campaignId: "",
    };
  }

  const claimedData = claimedOfferSnapshot.data() ?? {};
  const status = asTrimmedString(claimedData.status);
  const validUntil = asDate(claimedData.validUntil);
  const usageLimit = toInt(claimedData.usageLimit, 0);
  const usedCount = toInt(claimedData.usedCount, 0);
  const minBookingAmount = asOptionalFiniteNumber(claimedData.minBookingAmount);
  const campaignId = asTrimmedString(claimedData.offerId);
  const now = new Date();

  if (status !== "claimed") {
    return {
      ok: true,
      isValid: false,
      message: "This offer is no longer available to apply.",
      claimedOfferId,
      campaignId,
    };
  }
  if (validUntil && validUntil.getTime() < now.getTime()) {
    return {
      ok: true,
      isValid: false,
      message: "This offer has expired.",
      claimedOfferId,
      campaignId,
    };
  }
  if (usedCount >= usageLimit) {
    return {
      ok: true,
      isValid: false,
      message: "This offer has already been fully used.",
      claimedOfferId,
      campaignId,
    };
  }
  if (minBookingAmount != null && bookingAmount < minBookingAmount) {
    return {
      ok: true,
      isValid: false,
      message: `Minimum booking amount is ${minBookingAmount}.`,
      claimedOfferId,
      campaignId,
    };
  }

  const discountType = asTrimmedString(claimedData.discountType);
  if (!isOfferDiscountType(discountType)) {
    return {
      ok: true,
      isValid: false,
      message: "This offer is misconfigured.",
      claimedOfferId,
      campaignId,
    };
  }

  const discountValue = asOptionalFiniteNumber(claimedData.discountValue) ?? 0;
  const maxDiscountAmount = asOptionalFiniteNumber(claimedData.maxDiscountAmount);
  const {discountAmount, finalAmount} = computeOfferDiscount(
    bookingAmount,
    discountType,
    discountValue,
    maxDiscountAmount,
  );

  return {
    ok: true,
    isValid: true,
    discountAmount,
    finalAmount,
    message: "Offer applied successfully.",
    claimedOfferId,
    campaignId,
  };
});

export const createSocialNotification = onCall({invoker: "public"}, async (request) => {
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
  const senderDisplayName = safeText(
    senderData.name ?? senderData.username,
    "Someone",
  );
  const senderPhotoUrl = safeText(senderData.profileImage, "");

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

export const startProviderChat = onCall({invoker: "public"}, async (request) => {
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

export const startDirectUserChat = onCall({invoker: "public"}, async (request) => {
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

export const sendChatMessage = onCall({invoker: "public"}, async (request) => {
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

  let sourceServiceId = requestedSourceServiceId || asTrimmedString(chat.lastServiceId);
  let sourceServiceTitle = requestedSourceServiceId ? "" : asTrimmedString(chat.lastServiceTitle);
  let lastServiceImageUrl = requestedSourceServiceId ? "" : asTrimmedString(chat.lastServiceImageUrl);

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
      lastServiceId: sourceServiceId,
      lastServiceTitle: sourceServiceTitle,
      lastServiceImageUrl,
    };
    if (sourceServiceId) {
      chatUpdate.sourceServiceIds = FieldValue.arrayUnion(sourceServiceId);
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

export const markChatRead = onCall({invoker: "public"}, async (request) => {
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
  const customerId = asTrimmedString(chat.customerId);
  const providerId = asTrimmedString(chat.providerId);
  if (uid !== customerId && uid !== providerId) {
    throw new HttpsError("permission-denied", "You are not a participant in this chat.");
  }

  const otherUid = uid === customerId ? providerId : customerId;
  if (!otherUid) {
    throw new HttpsError("failed-precondition", "Chat participant is missing.");
  }

  const recentMessages = await chatRef
    .collection("messages")
    .where("senderId", "==", otherUid)
    .orderBy("createdAt", "desc")
    .limit(30)
    .get();

  const batch = db.batch();
  let updated = 0;
  for (const doc of recentMessages.docs) {
    const readBy = Array.isArray(doc.data().readBy) ?
      doc.data().readBy.map((value: unknown) => String(value)) :
      [];
    if (readBy.includes(uid)) continue;
    batch.set(doc.ref, {
      readBy: FieldValue.arrayUnion(uid),
      deliveredTo: FieldValue.arrayUnion(uid),
    }, {merge: true});
    updated += 1;
  }

  batch.set(chatRef, uid === customerId ? {
    customerLastReadAt: FieldValue.serverTimestamp(),
    unreadCountCustomer: 0,
  } : {
    providerLastReadAt: FieldValue.serverTimestamp(),
    unreadCountProvider: 0,
  }, {merge: true});

  await batch.commit();
  return {updated};
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
