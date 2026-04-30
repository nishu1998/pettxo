import {createHash, randomInt, timingSafeEqual} from "crypto";
import {initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import type {DocumentData, Transaction, WriteBatch} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onDocumentCreated, onDocumentWritten} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";

initializeApp();

const db = getFirestore();
const messaging = getMessaging();
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
  const standard = computeStandardRevenueBreakdown(totalAmount);
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
  if (params.refundAmount <= 0) {
    return {
      status: "processed",
      razorpayRefundId: "",
      error: "",
      processedAt: Timestamp.now(),
    };
  }

  const paymentId = asTrimmedString(params.razorpayPaymentId);
  const keyId = asTrimmedString(process.env.RAZORPAY_KEY_ID);
  const keySecret = asTrimmedString(process.env.RAZORPAY_KEY_SECRET);

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
          amount: String(Math.max(params.refundAmount, 0) * 100),
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

export const sendPushForNotification = onDocumentCreated(
  "notifications/{notificationId}",
  async (event) => {
    const notification = event.data?.data();
    if (!notification) return;
    if (notification.category !== "booking") return;

    const userId = String(notification.userId ?? "");
    if (!userId) return;

    const tokenSnapshot = await db
      .collection("users")
      .doc(userId)
      .collection("notificationTokens")
      .where("disabled", "!=", true)
      .get();

    const tokenDocs = tokenSnapshot.docs.filter((doc) => {
      const token = String(doc.data().token ?? "");
      return token.length > 0;
    });
    const tokens = tokenDocs.map((doc) => String(doc.data().token));
    if (tokens.length === 0) return;

    const rawData = notification.data;
    const notificationPayload =
      rawData && typeof rawData === "object" && !Array.isArray(rawData) ?
        rawData as Record<string, unknown> :
        {};
    const data = notificationData({
      ...notificationPayload,
      notificationId: event.params.notificationId,
      bookingId: notification.bookingId ?? "",
      serviceId: notification.serviceId ?? "",
      type: notification.type ?? "",
      category: notification.category ?? "booking",
      click_action: "FLUTTER_NOTIFICATION_CLICK",
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
          tag: String(notification.bookingId ?? event.params.notificationId),
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
      await cleanupBatch.commit();
    }
  },
);

export const enqueueServiceModeration = onDocumentCreated(
  "services/{serviceId}",
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
  {document: "services/{serviceId}", timeoutSeconds: 120, memory: "512MiB"},
  async (event) => {
    const serviceId = event.params.serviceId;
    const after = event.data?.after.data();
    if (!after) return;

    const before = event.data?.before.data();
    if (!serviceSlotConfigChanged(before, after)) return;

    await regenerateServiceSlots(serviceId, after);
  },
);

export const enqueueReportModeration = onDocumentCreated(
  "reports/{reportId}",
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

export const requestBooking = onCall(async (request) => {
  const uid = requireUid(request.auth);
  const serviceId = String(request.data?.serviceId ?? "");
  const slotId = String(request.data?.slotId ?? "");
  const requestedAmount = Number(request.data?.amount ?? 0);
  const userId = String(request.data?.userId ?? uid);
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
  const claimedOfferRef = claimedOfferId ?
    customerRef.collection("claimedOffers").doc(claimedOfferId) :
    null;
  const customerSnapshot = await customerRef.get();
  const customerData = customerSnapshot.exists ? customerSnapshot.data() ?? {} : {};
  const completedBookingCount = claimedOfferId ?
    await getCompletedBookingCountForUser(uid, customerData) :
    0;

  try {
    await db.runTransaction(async (transaction) => {
    const serviceSnapshot = await transaction.get(serviceRef);
    const slotSnapshot = await transaction.get(slotRef);
    const transactionCustomerSnapshot = await transaction.get(customerRef);
    const claimedOfferSnapshot = claimedOfferRef ? await transaction.get(claimedOfferRef) : null;

    if (!serviceSnapshot.exists) {
      throw new HttpsError("not-found", "Service not found.");
    }
    if (!slotSnapshot.exists) {
      throw new HttpsError("not-found", "Slot not found.");
    }

    const service = serviceSnapshot.data()!;
    const slot = slotSnapshot.data()!;
    if (
      service.status !== "active" ||
      service.isActive !== true ||
      service.isDeleted === true ||
      service.isPaused === true ||
      service.isVisibleToMarketplace !== true
    ) {
      throw new HttpsError("failed-precondition", "This service is not bookable.");
    }

    const serviceOwnerId = String(service.ownerUserId ?? "");
    if (!serviceOwnerId) {
      throw new HttpsError("failed-precondition", "Service owner is missing.");
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
    const nowMs = Date.now();
    if (scheduledStartAt.toMillis() - nowMs < minimumBookingLeadMs) {
      throw new HttpsError("failed-precondition", "This slot is too soon to book.");
    }
    if (scheduledEndAt.toMillis() <= scheduledStartAt.toMillis()) {
      throw new HttpsError("failed-precondition", "Slot timing is invalid.");
    }

    const requestExpiresAt = computeBookingRequestExpiresAt(
      nowMs,
      scheduledStartAt.toMillis(),
    );
    if (requestExpiresAt.toMillis() <= nowMs) {
      throw new HttpsError(
        "failed-precondition",
        "This slot is too soon for the provider response window.",
      );
    }

    const price = Number(service.pricePerSession ?? requestedAmount);
    const bookingCreatedAt = Timestamp.now();
    const graceWindow = buildGraceWindow(
      bookingCreatedAt.toDate(),
      scheduledStartAt.toDate(),
    );

    const durationMinutes = Math.round(
      (scheduledEndAt.toMillis() - scheduledStartAt.toMillis()) / 60000,
    );
    const ownerSnapshot = service.ownerSnapshot ?? {};
    const customer = transactionCustomerSnapshot.exists ? transactionCustomerSnapshot.data()! : {};
    const location = service.location ?? {};
    let discountAmount = 0;
    let finalAmount = price;
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
      finalAmount = computed.finalAmount;
      const nextUsedCount = usedCount + 1;
      const nextStatus = nextUsedCount >= usageLimit ? "used" : "claimed";

      appliedOfferData = {
        claimedOfferId,
        offerId,
        couponCode,
        discountType,
        discountValue,
        discountAmount,
        finalAmount,
        appliedAt: FieldValue.serverTimestamp(),
      };

      transaction.set(claimedOfferRef, {
        usedCount: FieldValue.increment(1),
        status: nextStatus,
      }, {merge: true});
      transaction.set(db.collection("adminAuditLogs").doc(), {
        action: "offer.redeemed",
        userId: uid,
        claimedOfferId,
        bookingId: bookingRef.id,
        discountAmount,
        createdAt: FieldValue.serverTimestamp(),
      });
    } else if (requestedAmount > 0 && price > 0 && requestedAmount !== price) {
      throw new HttpsError("failed-precondition", "Booking amount does not match service price.");
    }

    const standardRevenue = computeStandardRevenueBreakdown(finalAmount);

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
        currency: service.currency ?? "INR",
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
      status: "requested",
      paymentConfirmedAt: bookingCreatedAt,
      graceWindowMinutes: graceWindow.graceWindowMinutes,
      graceWindowEndsAt: graceWindow.graceWindowEndsAt,
      request: {
        message: "",
        // Provider must respond within 24h or 1h before service, whichever is earlier.
        expiresAt: requestExpiresAt,
        respondedAt: null,
        responseReason: "",
      },
      pricing: {
        grossAmount: price,
        grossAmountPaise: toPaise(price),
        discountAmount,
        discountAmountPaise: toPaise(discountAmount),
        finalAmount,
        finalAmountPaise: toPaise(finalAmount),
        platformFee: standardRevenue.pettxoAmount,
        platformFeePaise: standardRevenue.pettxoAmountPaise,
        providerEarnings: standardRevenue.providerAmount,
        providerEarningsPaise: standardRevenue.providerAmountPaise,
        currency: service.currency ?? "INR",
        paymentStatus: "paid",
      },
      ...(appliedOfferData == null ? {} : {offer: appliedOfferData}),
      otp: {
        status: "notGenerated",
        attempts: 0,
        maxAttempts: 5,
      },
      payoutReadiness: {
        status: "notEligible",
        reason: "Booking has not completed.",
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
        requestNotificationSent: true,
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
      totalAmount: finalAmount,
      totalAmountPaise: toPaise(finalAmount),
      currency: service.currency ?? "INR",
      razorpayPaymentId: "",
      razorpayOrderId: "",
      status: "paid",
      graceWindowMinutes: graceWindow.graceWindowMinutes,
      graceWindowEndsAt: graceWindow.graceWindowEndsAt,
      refundAmount: 0,
      refundAmountPaise: 0,
      pettxoCommissionAmount: standardRevenue.pettxoAmount,
      pettxoAmountPaise: standardRevenue.pettxoAmountPaise,
      providerEarningAmount: standardRevenue.providerAmount,
      providerAmountPaise: standardRevenue.providerAmountPaise,
      refundPercent: 0,
      pettxoPercent: standardRevenue.pettxoPercent,
      providerPercent: standardRevenue.providerPercent,
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
    queueBookingNotification({
      transaction,
      userId: serviceOwnerId,
      bookingId: bookingRef.id,
      type: "bookingRequested",
      title: "New booking request",
      body: `${snapshotName(
        bookingPayload.customerSnapshot,
        "A pet parent",
      )} requested ${serviceTitleFromBooking(bookingPayload)}.`,
      recipientRole: "provider",
      actorId: uid,
      status: "requested",
      booking: bookingPayload,
      extraData: {event: "booking_requested"},
    });
    });
  } catch (error) {
    if (error instanceof OfferValidationError) {
      return {ok: false, message: error.message};
    }
    throw error;
  }

  await writeBookingEvent({
    bookingId: bookingRef.id,
    actorId: uid,
    actorType: "customer",
    type: "created",
    fromStatus: "none",
    toStatus: "requested",
    message: "Booking request created after payment simulation.",
    metadata: {serviceId, slotId},
  });

  return {ok: true, bookingId: bookingRef.id};
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

export const rejectBookingRequest = onCall({invoker: "public"}, async (request) => {
  const uid = requireUid(request.auth);
  const bookingId = String(request.data?.bookingId ?? "");
  const reason = String(request.data?.reason ?? "Rejected by provider");
  if (!bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }

  const bookingRef = db.collection("bookings").doc(bookingId);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(bookingRef);
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

    transaction.update(bookingRef, {
      status: "rejected",
      rejectedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      "request.respondedAt": FieldValue.serverTimestamp(),
      "request.responseReason": reason,
      "notificationState.rejectionNotificationSent": true,
    });

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

  return {ok: true};
});

export const expireStaleBookingRequests = onSchedule(
  {schedule: "every 5 minutes", timeZone: "Asia/Kolkata"},
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
      await db.runTransaction(async (transaction) => {
        const freshSnapshot = await transaction.get(doc.ref);
        if (!freshSnapshot.exists) return;

        const booking = freshSnapshot.data()!;
        if (booking.status !== "requested" || !requestHasExpired(booking)) return;

        transaction.update(doc.ref, {
          status: "expired",
          expiredAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          "request.respondedAt": FieldValue.serverTimestamp(),
          "request.responseReason": "Auto-cancelled because provider did not respond in time.",
        });

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

export const cancelBooking = onCall({invoker: "public"}, async (request) => {
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
    const standardRevenue = computeStandardRevenueBreakdown(totalAmount);
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
      const standardRevenue = computeStandardRevenueBreakdown(totalAmount);
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
        const pettxoAmountPaise = Math.round((totalAmountPaise * 15) / 100);
        const providerAmountPaise = Math.max(totalAmountPaise - pettxoAmountPaise, 0);
        const noShowSnapshot = {
          refundPercent: 0,
          providerPercent: 85,
          pettxoPercent: 15,
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
          pettxoPercent: 15,
          providerPercent: 85,
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
          platformFee: toMoneyAmount((totalAmount * 15) / 100),
          providerEarnings: Math.max(totalAmount - toMoneyAmount((totalAmount * 15) / 100), 0),
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
