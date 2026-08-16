import type {
  CanonicalPaymentMethod,
  CanonicalPaymentState,
  CanonicalQrState,
  PaymentVerificationSource,
} from "../domain/paymentContracts";
import {
  isCanonicalPaymentMethod,
  isCanonicalPaymentState,
  isCanonicalQrState,
  isPaymentVerificationSource,
} from "../domain/paymentContracts";
import {normalizeTimestampLike} from "./timestampNormalization";

export const CANONICAL_PAYMENT_ATTEMPT_SCHEMA_VERSION = 1;

export type CanonicalCouponSnapshotV3 = {
  offerCampaignId: string;
  couponId: string;
  couponClaimId: string;
  couponCode: string;
  usageLimitPerUser: number | null;
  discountType: string;
  discountValue: number;
  maxDiscountAmountPaise: number | null;
  minBookingValuePaise: number | null;
  campaignType: string;
  validUntil: Date | null;
};

export type CanonicalPaymentAttemptDocumentV3 = {
  schemaVersion: 1;
  paymentAttemptId: string;
  bookingId: string;
  parentId: string;
  providerId: string;
  requestAttemptId: string;
  razorpayOrderId: string;
  razorpayPaymentId: string;
  amountPaise: number;
  currency: string;
  paymentMethod: CanonicalPaymentMethod;
  offerCampaignId: string;
  couponId: string;
  couponClaimId: string;
  pricingHash: string;
  availabilityHash: string;
  state: CanonicalPaymentState;
  orderExpiresAt: Date | null;
  createdAt: Date;
  orderCreatedAt: Date | null;
  checkoutOpenedAt: Date | null;
  captureReportedAt: Date | null;
  captureCreatedAt: Date | null;
  confirmedAt: Date | null;
  failedAt: Date | null;
  refundRequiredAt: Date | null;
  refundedAt: Date | null;
  nextReconciliationAt: Date | null;
  lastReconciledAt: Date | null;
  reconciliationAttemptCount: number;
  lastReconciliationCode: string;
  terminalFailureAt: Date | null;
  leaseOwner: string;
  leaseExpiresAt: Date | null;
  verificationSource: PaymentVerificationSource | "";
  failureCode: string;
  failureMessage: string;
  retryCount: number;
  updatedAt: Date;
  pricingSnapshot: Record<string, unknown>;
  couponSnapshot: CanonicalCouponSnapshotV3 | null;
  razorpayQrCodeId: string;
  razorpayQrImageUrl: string;
  qrState: CanonicalQrState | "";
  qrCreatedAt: Date | null;
  qrExpiresAt: Date | null;
  qrClosedAt: Date | null;
  qrCloseReason: string;
};

export type CanonicalBookingPrivateDocumentV3 = {
  schemaVersion: 1;
  bookingId: string;
  parentId: string;
  providerId: string;
  parentOtpCode: string;
  providerOtpHash: string;
  otpState: "ACTIVE" | "USED" | "REVOKED";
  failedAttemptCount: number;
  lastFailedAttemptAt: Date | null;
  lockedUntil: Date | null;
  verifiedAt: Date | null;
  successfulAttemptNumber: number | null;
  lastVerificationAttemptId: string;
  lastVerificationOutcome: string;
  contactUnlockedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
};

type ValidationIssue = {
  code: string;
  message: string;
  path: string;
};

type ValidationResult<T> =
  | {ok: true; value: T; issues: []}
  | {ok: false; value: null; issues: ValidationIssue[]};

function issue(code: string, message: string, path: string): ValidationIssue {
  return {code, message, path};
}

function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value != null ? value as Record<string, unknown> : {};
}

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asNullableDate(value: unknown): Date | null {
  return normalizeTimestampLike(value);
}

function asInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) ? value : null;
}

function asNullableNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

export function parseCanonicalPaymentAttemptDocumentV3(
  rawValue: unknown,
): ValidationResult<CanonicalPaymentAttemptDocumentV3> {
  const raw = asRecord(rawValue);
  const issues: ValidationIssue[] = [];
  const state = asString(raw.state);
  const verificationSource = asString(raw.verificationSource);
  const paymentMethod = asString(raw.paymentMethod) || "checkout";
  const qrState = asString(raw.qrState);
  const schemaVersion = asInteger(raw.schemaVersion);
  if (schemaVersion !== CANONICAL_PAYMENT_ATTEMPT_SCHEMA_VERSION) {
    issues.push(issue(
      "INVALID_SCHEMA_VERSION",
      "payment attempt schemaVersion must be 1.",
      "schemaVersion",
    ));
  }
  if (!isCanonicalPaymentState(state)) {
    issues.push(issue("INVALID_STATE", "payment attempt state is invalid.", "state"));
  }
  if (verificationSource && !isPaymentVerificationSource(verificationSource)) {
    issues.push(issue(
      "INVALID_VERIFICATION_SOURCE",
      "verificationSource is invalid.",
      "verificationSource",
    ));
  }
  if (!isCanonicalPaymentMethod(paymentMethod)) {
    issues.push(issue("INVALID_PAYMENT_METHOD", "paymentMethod is invalid.", "paymentMethod"));
  }
  if (qrState && !isCanonicalQrState(qrState)) {
    issues.push(issue("INVALID_QR_STATE", "qrState is invalid.", "qrState"));
  }

  const amountPaise = asInteger(raw.amountPaise);
  const retryCount = asInteger(raw.retryCount);
  if (amountPaise == null || amountPaise < 0) {
    issues.push(issue("INVALID_AMOUNT", "amountPaise must be a non-negative integer.", "amountPaise"));
  }
  if (retryCount == null || retryCount < 0) {
    issues.push(issue("INVALID_RETRY_COUNT", "retryCount must be a non-negative integer.", "retryCount"));
  }

  const createdAt = asNullableDate(raw.createdAt);
  const updatedAt = asNullableDate(raw.updatedAt);
  if (createdAt == null) {
    issues.push(issue("MISSING_CREATED_AT", "createdAt is required.", "createdAt"));
  }
  if (updatedAt == null) {
    issues.push(issue("MISSING_UPDATED_AT", "updatedAt is required.", "updatedAt"));
  }

  if (issues.length > 0) {
    return {ok: false, value: null, issues};
  }

  const couponRaw = raw.couponSnapshot == null ? null : asRecord(raw.couponSnapshot);

  return {
    ok: true,
    value: {
      schemaVersion: 1,
      paymentAttemptId: asString(raw.paymentAttemptId),
      bookingId: asString(raw.bookingId),
      parentId: asString(raw.parentId),
      providerId: asString(raw.providerId),
      requestAttemptId: asString(raw.requestAttemptId),
      razorpayOrderId: asString(raw.razorpayOrderId),
      razorpayPaymentId: asString(raw.razorpayPaymentId),
      amountPaise: amountPaise ?? 0,
      currency: asString(raw.currency) || "INR",
      paymentMethod: (paymentMethod || "checkout") as CanonicalPaymentMethod,
      offerCampaignId: asString(raw.offerCampaignId) || asString(raw.couponId),
      couponId: asString(raw.couponId),
      couponClaimId: asString(raw.couponClaimId),
      pricingHash: asString(raw.pricingHash),
      availabilityHash: asString(raw.availabilityHash),
      state: state as CanonicalPaymentState,
      orderExpiresAt: asNullableDate(raw.orderExpiresAt),
      createdAt: createdAt ?? new Date("invalid"),
      orderCreatedAt: asNullableDate(raw.orderCreatedAt),
      checkoutOpenedAt: asNullableDate(raw.checkoutOpenedAt),
      captureReportedAt: asNullableDate(raw.captureReportedAt),
      captureCreatedAt: asNullableDate(raw.captureCreatedAt),
      confirmedAt: asNullableDate(raw.confirmedAt),
      failedAt: asNullableDate(raw.failedAt),
      refundRequiredAt: asNullableDate(raw.refundRequiredAt),
      refundedAt: asNullableDate(raw.refundedAt),
      nextReconciliationAt: asNullableDate(raw.nextReconciliationAt),
      lastReconciledAt: asNullableDate(raw.lastReconciledAt),
      reconciliationAttemptCount: asInteger(raw.reconciliationAttemptCount) ?? 0,
      lastReconciliationCode: asString(raw.lastReconciliationCode),
      terminalFailureAt: asNullableDate(raw.terminalFailureAt),
      leaseOwner: asString(raw.leaseOwner),
      leaseExpiresAt: asNullableDate(raw.leaseExpiresAt),
      verificationSource: (verificationSource || "") as PaymentVerificationSource | "",
      failureCode: asString(raw.failureCode),
      failureMessage: asString(raw.failureMessage),
      retryCount: retryCount ?? 0,
      updatedAt: updatedAt ?? new Date("invalid"),
      pricingSnapshot: asRecord(raw.pricingSnapshot),
      couponSnapshot: couponRaw == null ? null : {
        offerCampaignId:
          asString(couponRaw.offerCampaignId) || asString(couponRaw.couponId),
        couponId: asString(couponRaw.couponId),
        couponClaimId: asString(couponRaw.couponClaimId),
        couponCode: asString(couponRaw.couponCode),
        usageLimitPerUser: asInteger(couponRaw.usageLimitPerUser),
        discountType: asString(couponRaw.discountType),
        discountValue: asNullableNumber(couponRaw.discountValue) ?? 0,
        maxDiscountAmountPaise: asInteger(couponRaw.maxDiscountAmountPaise),
        minBookingValuePaise: asInteger(couponRaw.minBookingValuePaise),
        campaignType: asString(couponRaw.campaignType),
        validUntil: asNullableDate(couponRaw.validUntil),
      },
      razorpayQrCodeId: asString(raw.razorpayQrCodeId),
      razorpayQrImageUrl: asString(raw.razorpayQrImageUrl),
      qrState: qrState as CanonicalQrState | "",
      qrCreatedAt: asNullableDate(raw.qrCreatedAt),
      qrExpiresAt: asNullableDate(raw.qrExpiresAt),
      qrClosedAt: asNullableDate(raw.qrClosedAt),
      qrCloseReason: asString(raw.qrCloseReason),
    },
    issues: [],
  };
}

export function assertValidCanonicalPaymentAttemptDocumentV3(
  rawValue: unknown,
): CanonicalPaymentAttemptDocumentV3 {
  const parsed = parseCanonicalPaymentAttemptDocumentV3(rawValue);
  if (!parsed.ok) {
    throw new Error(parsed.issues.map((entry) => `${entry.code}:${entry.path}`).join(", "));
  }
  return parsed.value;
}
