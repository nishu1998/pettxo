import {createHash} from "node:crypto";

import {FieldValue, Timestamp, type Firestore} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {HttpsError} from "firebase-functions/https";

import {
  parseCanonicalBookingDocumentV3,
  type CanonicalBookingDocumentV3,
} from "../schema/bookingDocumentV3";
import {normalizeTimestampLike} from "../schema/timestampNormalization";
import {buildStoredBookingNotificationDocument} from "../../notifications/notificationChannels";

export const CANONICAL_DISPUTE_RESOLUTIONS_COLLECTION =
  "bookingDisputeResolutions";
export const CANONICAL_PROVIDER_PAYOUTS_COLLECTION = "providerPayouts";
export const CANONICAL_FINANCIAL_LEDGER_COLLECTION =
  "bookingFinancialLedger";
export const CANONICAL_FINANCIAL_RECONCILIATION_COLLECTION =
  "bookingFinancialReconciliation";
export const CANONICAL_FINANCIAL_POLICY_VERSION = "v3.2_slice9";
export const CANONICAL_PROVIDER_PAYOUTS_LIVE_ENABLED = false;

const PAYOUT_LEASE_MS = 2 * 60 * 1000;
const PAYOUT_RETRY_BASE_MS = 15 * 60 * 1000;
const PAYOUT_RETRY_MAX_MS = 24 * 60 * 60 * 1000;

type AdminRole = "superAdmin" | "financeAdmin" | "customerSupportAdmin";
type DisputeResolutionType =
  | "CUSTOMER_WINS"
  | "PROVIDER_WINS"
  | "CUSTOM_ALLOCATION"
  | "PARTIAL_REFUND"
  | "CUSTOM_ADJUSTMENT";
type ProviderPayoutStatus =
  | "HELD"
  | "READY"
  | "PROCESSING"
  | "PAID"
  | "FAILED"
  | "CANCELLED";
type LedgerEntryType =
  | "PAYMENT_CAPTURED"
  | "CUSTOMER_REFUND"
  | "PROVIDER_PAYOUT"
  | "PLATFORM_REVENUE"
  | "PETTXO_COUPON_COST"
  | "GATEWAY_FEE"
  | "CANCELLATION_ADJUSTMENT"
  | "NO_SHOW_ALLOCATION"
  | "DISPUTE_ADJUSTMENT"
  | "MANUAL_ADJUSTMENT";
type ReconciliationStatus =
  | "BALANCED"
  | "MISSING_ENTRY"
  | "DUPLICATE_ENTRY"
  | "AMOUNT_MISMATCH"
  | "OVER_REFUNDED"
  | "OVERPAID_PROVIDER"
  | "STALE_PAYOUT"
  | "INVALID_FINANCIAL_SNAPSHOT";
type ReconciliationAction =
  | "SAFE_AUTOMATIC_REPAIR"
  | "RETRY_EXTERNAL_OPERATION"
  | "MANUAL_REVIEW_REQUIRED"
  | "NO_ACTION";

export type ResolveBookingDisputeInput = {
  disputeId?: string;
  bookingId?: string;
  resolutionType: DisputeResolutionType;
  policyReason: string;
  notes?: string;
  publicResolutionMessage?: string;
  resolutionAttemptId: string;
  customerAllocationBasisPoints?: number | null;
  providerAllocationBasisPoints?: number | null;
  pettxoAllocationBasisPoints?: number | null;
  customerRefundBasisPoints?: number | null;
  customerRefundPaise?: number | null;
  providerFinalEntitlementPaise?: number | null;
};

export type ResolveBookingDisputeResult = {
  ok: true;
  bookingId: string;
  disputeId: string;
  resolutionId: string;
  adjustmentId: string;
  refundInstructionId: string;
  payoutId: string;
  resolutionType: DisputeResolutionType;
  disputeStatus: "RESOLVED";
  payoutStatus: ProviderPayoutStatus;
  customerPaidPaise: number;
  authoritativeAmountPaidPaise: number;
  customerAllocationBasisPoints: number | null;
  providerAllocationBasisPoints: number | null;
  pettxoAllocationBasisPoints: number | null;
  customerFinalPaise: number;
  customerRefundPaise: number;
  providerAllocationPaise: number;
  providerFinalEntitlementPaise: number;
  providerCouponSubsidyPaise: number;
  providerAlreadyPaidPaise: number;
  providerRemainingPayablePaise: number;
  pettxoFinalRetainedPaise: number;
  refundToIssuePaise: number;
  idempotentReplay: boolean;
};

export type PreviewBookingDisputeResolutionResult = {
  bookingId: string;
  disputeId: string;
  resolutionType: DisputeResolutionType;
  currency: string;
  customerPaidPaise: number;
  authoritativeAmountPaidPaise: number;
  alreadyRefundedPaise: number;
  providerBaseEntitlementPaise: number;
  providerAlreadyPaidPaise: number;
  providerRemainingPayablePaise: number;
  customerAllocationBasisPoints: number | null;
  providerAllocationBasisPoints: number | null;
  pettxoAllocationBasisPoints: number | null;
  customerRefundBasisPoints: number | null;
  customerFinalPaise: number;
  customerRefundPaise: number;
  providerAllocationPaise: number;
  providerFinalEntitlementPaise: number;
  providerCouponSubsidyPaise: number;
  pettxoFinalRetainedPaise: number;
  refundToIssuePaise: number;
};

export type ProviderPayoutDocumentV3 = {
  payoutId: string;
  bookingId: string;
  providerId: string;
  currency: string;
  grossServiceAmountPaise: number;
  providerEntitlementPaise: number;
  priorPaidPaise: number;
  remainingPayablePaise: number;
  pettxoRetainedPaise: number;
  couponCostPaise: number;
  gatewayFeePaise: number;
  financialAdjustmentTotalPaise: number;
  status: ProviderPayoutStatus;
  holdReason: string;
  eligibleAt: Date | null;
  readyAt: Date | null;
  processingAt: Date | null;
  paidAt: Date | null;
  failedAt: Date | null;
  failureCode: string;
  failureCategory: string;
  retryCount: number;
  nextRetryAt: Date | null;
  processorLease: string;
  lastAttemptAt: Date | null;
  externalPayoutId: string;
  externalTransactionId: string;
  policyVersion: string;
  createdAt: Date;
  updatedAt: Date;
};

type PayoutGatewaySuccess = {
  ok: true;
  status: "PAID";
  externalPayoutId: string;
  externalTransactionId: string;
};

type PayoutGatewayFailure = {
  ok: false;
  status: "FAILED";
  failureCode: string;
  failureCategory:
    | "retryable_gateway_failure"
    | "invalid_payout_destination"
    | "manual_review_required"
    | "configuration_error"
    | "duplicate_external_payout";
  retryable: boolean;
  externalPayoutId?: string;
  externalTransactionId?: string;
};

export type PayoutGatewayResult = PayoutGatewaySuccess | PayoutGatewayFailure;

export interface ProviderPayoutGatewayV3 {
  executePayout(params: {
    payout: ProviderPayoutDocumentV3;
    idempotencyKey: string;
  }): Promise<PayoutGatewayResult>;
}

export class DisabledProviderPayoutGatewayV3
implements ProviderPayoutGatewayV3 {
  async executePayout(): Promise<PayoutGatewayResult> {
    return {
      ok: false,
      status: "FAILED",
      failureCode: "LIVE_PAYOUT_DISABLED",
      failureCategory: "configuration_error",
      retryable: false,
    };
  }
}

export class FakeProviderPayoutGatewayV3 implements ProviderPayoutGatewayV3 {
  constructor(
    private readonly result:
      | PayoutGatewayResult
      | ((params: {
          payout: ProviderPayoutDocumentV3;
          idempotencyKey: string;
        }) => Promise<PayoutGatewayResult> | PayoutGatewayResult),
  ) {}

  async executePayout(params: {
    payout: ProviderPayoutDocumentV3;
    idempotencyKey: string;
  }): Promise<PayoutGatewayResult> {
    if (typeof this.result === "function") {
      return await this.result(params);
    }
    return this.result;
  }
}

export type ProviderPayoutProcessingResult =
  | {
      ok: true;
      code: "PAID" | "IDEMPOTENT_REPLAY";
      bookingId: string;
      payoutId: string;
      status: "PAID";
      externalPayoutId: string;
      externalTransactionId: string;
    }
  | {
      ok: false;
      code:
        | "NOT_FOUND"
        | "NOT_READY"
        | "ALREADY_PAID"
        | "LIVE_PAYOUT_DISABLED"
        | "FAILED";
      bookingId: string;
      payoutId: string;
      status: ProviderPayoutStatus | "";
      failureCode: string;
    };

export type BookingFinancialLedgerEntry = {
  entryId: string;
  bookingId: string;
  providerId: string;
  disputeId: string;
  payoutId: string;
  refundId: string;
  type: LedgerEntryType;
  direction: "credit" | "debit" | "memo";
  amountPaise: number;
  currency: string;
  account: string;
  sourceType: string;
  sourceId: string;
  policyVersion: string;
  occurredAt: Date;
  createdAt: Date;
  metadata: Record<string, unknown>;
};

export type BookingFinancialReconciliationResult = {
  bookingId: string;
  status: ReconciliationStatus;
  action: ReconciliationAction;
  issues: string[];
  repairWrites: Array<{path: string; data: Record<string, unknown>}>;
};

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asInt(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value) ?
    Math.max(Math.trunc(value), 0) :
    fallback;
}

function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value != null ?
    value as Record<string, unknown> :
    {};
}

function asDate(value: unknown): Date | null {
  return normalizeTimestampLike(value);
}

function stableHash(payload: unknown): string {
  return createHash("sha256").update(JSON.stringify(payload)).digest("hex");
}

function requireUid(auth: {uid?: string} | undefined): string {
  const uid = auth?.uid?.trim() ?? "";
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return uid;
}

async function requireFinanceAdminActor(
  firestore: Firestore,
  uid: string,
): Promise<{uid: string; role: AdminRole}> {
  const snapshot = await firestore.collection("users").doc(uid).get();
  const role = asString(snapshot.data()?.adminRole) as AdminRole;
  if (role !== "superAdmin" && role !== "financeAdmin") {
    throw new HttpsError(
      "permission-denied",
      "Finance admin access required.",
    );
  }
  return {uid, role};
}

function payoutIdForBooking(bookingId: string): string {
  return bookingId;
}

function disputeResolutionIdForBooking(bookingId: string): string {
  return `resolution_${bookingId}`;
}

function financialAdjustmentIdForDispute(
  bookingId: string,
  disputeId: string,
): string {
  return `${bookingId}_${disputeId}`;
}

function refundInstructionIdForDispute(disputeId: string): string {
  return `refund_${disputeId}`;
}

function ledgerEntryId(params: {
  bookingId: string;
  type: LedgerEntryType;
  sourceId: string;
}): string {
  return `${params.bookingId}_${params.type}_${params.sourceId}`;
}

function payoutLeaseExpiresAt(now: Date): Date {
  return new Date(now.getTime() + PAYOUT_LEASE_MS);
}

function parseCanonicalBookingForFinancials(
  rawValue: unknown,
  path: string,
): CanonicalBookingDocumentV3 {
  const parsed = parseCanonicalBookingDocumentV3(rawValue);
  if (parsed.ok) {
    return parsed.booking;
  }
  throw new HttpsError(
    "failed-precondition",
    `Canonical booking document at ${path} contains invalid timestamp or schema data.`,
    {
      code: "INVALID_CANONICAL_BOOKING_DOCUMENT",
      path,
      issues: parsed.issues.map((issue) => ({
        code: issue.code,
        path: issue.path,
      })),
    },
  );
}

function requireDate(value: unknown, field: string): Date {
  const normalized = asDate(value);
  if (normalized != null) {
    return normalized;
  }
  throw new HttpsError(
    "failed-precondition",
    `${field} is missing or malformed.`,
    {
      code: "INVALID_TIMESTAMP",
      field,
    },
  );
}

function resolveRequiredPayoutEligibleAt(params: {
  booking: CanonicalBookingDocumentV3;
  fallbackNow: Date;
}): Date {
  if (params.booking.payout.eligibleAt != null) {
    return requireDate(
      params.booking.payout.eligibleAt,
      "bookings.payout.eligibleAt",
    );
  }
  if (params.booking.lifecycle.finalizedAt != null) {
    return requireDate(
      params.booking.lifecycle.finalizedAt,
      "bookings.lifecycle.finalizedAt",
    );
  }
  return params.fallbackNow;
}

function nextPayoutRetryAt(now: Date, retryCount: number): Date {
  const multiplier = Math.max(retryCount, 1);
  const delay = Math.min(
    PAYOUT_RETRY_BASE_MS * multiplier,
    PAYOUT_RETRY_MAX_MS,
  );
  return new Date(now.getTime() + delay);
}

function writeNotification(
  transaction: FirebaseFirestore.Transaction,
  firestore: Firestore,
  params: {
    idempotencyKey: string;
    userId: string;
    type: string;
    title: string;
    body: string;
    bookingId: string;
    actorId: string;
    now: Date;
    channels?: ReadonlyArray<string>;
  },
): void {
  transaction.set(
    firestore.collection("notifications").doc(params.idempotencyKey),
    buildStoredBookingNotificationDocument({
      notification: {
        recipientUserId: params.userId,
        type: params.type,
        title: params.title,
        body: params.body,
        channels: params.channels ?? ["in_app", "push"],
        data: {
          bookingId: params.bookingId,
        },
      },
      actorId: params.actorId,
      createdAt: Timestamp.fromDate(params.now),
      updatedAt: Timestamp.fromDate(params.now),
      source: "canonical_v3_financials",
    }),
    {merge: true},
  );
}

function buildBaseLedgerEntries(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  now: Date;
}): BookingFinancialLedgerEntry[] {
  const financials = params.booking.financials;
  if (financials == null) return [];
  const baseCurrency = financials.currency;
  const entries: BookingFinancialLedgerEntry[] = [
    {
      entryId: ledgerEntryId({
        bookingId: params.bookingId,
        type: "PAYMENT_CAPTURED",
        sourceId: params.booking.payment.paymentAttemptId || params.bookingId,
      }),
      bookingId: params.bookingId,
      providerId: params.booking.providerId,
      disputeId: "",
      payoutId: "",
      refundId: "",
      type: "PAYMENT_CAPTURED",
      direction: "credit",
      amountPaise: financials.customerPaidPaise,
      currency: baseCurrency,
      account: "customer_cash",
      sourceType: "booking_payment",
      sourceId: params.booking.payment.paymentAttemptId || params.bookingId,
      policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
      occurredAt:
        params.booking.lifecycle.paidAt ??
        params.booking.payment.capturedAt ??
        params.now,
      createdAt: params.now,
      metadata: {},
    },
    {
      entryId: ledgerEntryId({
        bookingId: params.bookingId,
        type: "PLATFORM_REVENUE",
        sourceId: params.bookingId,
      }),
      bookingId: params.bookingId,
      providerId: params.booking.providerId,
      disputeId: "",
      payoutId: "",
      refundId: "",
      type: "PLATFORM_REVENUE",
      direction: "credit",
      amountPaise: financials.platformCommissionPaise,
      currency: baseCurrency,
      account: "pettxo_revenue",
      sourceType: "canonical_financial_snapshot",
      sourceId: params.bookingId,
      policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
      occurredAt:
        params.booking.lifecycle.paidAt ??
        params.booking.payment.capturedAt ??
        params.now,
      createdAt: params.now,
      metadata: {},
    },
    {
      entryId: ledgerEntryId({
        bookingId: params.bookingId,
        type: "PETTXO_COUPON_COST",
        sourceId: params.bookingId,
      }),
      bookingId: params.bookingId,
      providerId: params.booking.providerId,
      disputeId: "",
      payoutId: "",
      refundId: "",
      type: "PETTXO_COUPON_COST",
      direction: "debit",
      amountPaise: financials.pettxoCouponFundingPaise,
      currency: baseCurrency,
      account: "pettxo_coupon_cost",
      sourceType: "canonical_financial_snapshot",
      sourceId: params.bookingId,
      policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
      occurredAt:
        params.booking.lifecycle.paidAt ??
        params.booking.payment.capturedAt ??
        params.now,
      createdAt: params.now,
      metadata: {},
    },
    {
      entryId: ledgerEntryId({
        bookingId: params.bookingId,
        type: "GATEWAY_FEE",
        sourceId: params.bookingId,
      }),
      bookingId: params.bookingId,
      providerId: params.booking.providerId,
      disputeId: "",
      payoutId: "",
      refundId: "",
      type: "GATEWAY_FEE",
      direction: "debit",
      amountPaise: financials.gatewayFeeSunkPaise,
      currency: baseCurrency,
      account: "gateway_fee",
      sourceType: "canonical_financial_snapshot",
      sourceId: params.bookingId,
      policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
      occurredAt:
        params.booking.lifecycle.paidAt ??
        params.booking.payment.capturedAt ??
        params.now,
      createdAt: params.now,
      metadata: {},
    },
  ];
  return entries.filter((entry) => entry.amountPaise > 0);
}

function serializeLedgerEntry(
  entry: BookingFinancialLedgerEntry,
): Record<string, unknown> {
  const occurredAt = serializeRequiredTimestampLike(
    entry.occurredAt,
    "bookingFinancialLedger.occurredAt",
  );
  const createdAt = serializeRequiredTimestampLike(
    entry.createdAt,
    "bookingFinancialLedger.createdAt",
  );
  return {
    entryId: entry.entryId,
    bookingId: entry.bookingId,
    providerId: entry.providerId,
    disputeId: entry.disputeId,
    payoutId: entry.payoutId,
    refundId: entry.refundId,
    type: entry.type,
    direction: entry.direction,
    amountPaise: entry.amountPaise,
    currency: entry.currency,
    account: entry.account,
    sourceType: entry.sourceType,
    sourceId: entry.sourceId,
    policyVersion: entry.policyVersion,
    occurredAt,
    createdAt,
    metadata: entry.metadata,
  };
}

function serializeRequiredTimestampLike(
  value: unknown,
  field: string,
): Timestamp {
  if (value instanceof Timestamp) {
    return value;
  }
  const normalized = asDate(value);
  if (normalized != null) {
    return Timestamp.fromDate(normalized);
  }
  throw new HttpsError(
    "failed-precondition",
    `${field} is missing or malformed.`,
    {
      code: "INVALID_TIMESTAMP",
      field,
    },
  );
}

function buildPayoutProfileSnapshot(
  providerBankDetails: Record<string, unknown> | null,
): {isValid: boolean; maskedDestination: string} {
  if (!providerBankDetails) {
    return {isValid: false, maskedDestination: ""};
  }
  const status = asString(providerBankDetails.status).toLowerCase();
  const maskedAccount = asString(providerBankDetails.accountNumberMasked);
  return {
    isValid: status === "submitted" && maskedAccount.length >= 4,
    maskedDestination: maskedAccount,
  };
}

export function buildCanonicalProviderPayoutDocumentV3(params: {
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  financialAdjustmentTotalPaise?: number;
  priorPaidPaise?: number;
  holdReason?: string;
  status?: ProviderPayoutStatus;
  eligibleAt?: Date | null;
  readyAt?: Date | null;
  now: Date;
}): ProviderPayoutDocumentV3 {
  const financials = params.booking.financials;
  if (financials == null) {
    throw new HttpsError(
      "failed-precondition",
      "Canonical booking financial snapshot is missing.",
    );
  }
  const providerEntitlementPaise = Math.max(
    params.status === "CANCELLED" ? 0 : financials.providerPayoutPaise,
    0,
  );
  const priorPaidPaise = Math.max(params.priorPaidPaise ?? 0, 0);
  return {
    payoutId: payoutIdForBooking(params.bookingId),
    bookingId: params.bookingId,
    providerId: params.booking.providerId,
    currency: financials.currency,
    grossServiceAmountPaise: financials.serviceSubtotalPaise,
    providerEntitlementPaise,
    priorPaidPaise,
    remainingPayablePaise: Math.max(providerEntitlementPaise - priorPaidPaise, 0),
    pettxoRetainedPaise:
      Math.max(financials.customerPaidPaise - providerEntitlementPaise, 0),
    couponCostPaise: financials.pettxoCouponFundingPaise,
    gatewayFeePaise: financials.gatewayFeeSunkPaise,
    financialAdjustmentTotalPaise: Math.max(
      params.financialAdjustmentTotalPaise ?? 0,
      0,
    ),
    status: params.status ?? "HELD",
    holdReason: params.holdReason ?? "",
    eligibleAt: params.eligibleAt ?? params.booking.payout.eligibleAt,
    readyAt: params.readyAt ?? null,
    processingAt: null,
    paidAt: null,
    failedAt: null,
    failureCode: "",
    failureCategory: "",
    retryCount: 0,
    nextRetryAt: null,
    processorLease: "",
    lastAttemptAt: null,
    externalPayoutId: "",
    externalTransactionId: "",
    policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
    createdAt: params.now,
    updatedAt: params.now,
  };
}

export function evaluateCanonicalProviderPayoutEligibilityV3(params: {
  booking: CanonicalBookingDocumentV3;
  existingPayout: Record<string, unknown> | null;
  existingRefund: Record<string, unknown> | null;
  providerBankDetails: Record<string, unknown> | null;
  authoritativeNow: Date;
}): {
  status: ProviderPayoutStatus;
  holdReason: string;
  providerEntitlementPaise: number;
  remainingPayablePaise: number;
  readyAt: Date | null;
} {
  const financials = params.booking.financials;
  if (financials == null) {
    return {
      status: "HELD",
      holdReason: "Missing canonical financial snapshot.",
      providerEntitlementPaise: 0,
      remainingPayablePaise: 0,
      readyAt: null,
    };
  }
  const priorPaidPaise = asInt(params.existingPayout?.priorPaidPaise, 0);
  const providerEntitlementPaise = Math.max(
    asInt(
      params.existingPayout?.providerEntitlementPaise,
      financials.providerPayoutPaise,
    ),
    0,
  );
  const remainingPayablePaise = Math.max(
    providerEntitlementPaise - priorPaidPaise,
    0,
  );
  const disputeStatus = params.booking.dispute.status.trim().toUpperCase();
  const payoutEligibleAt =
    asDate(params.existingPayout?.eligibleAt) ??
    resolveRequiredPayoutEligibleAt({
      booking: params.booking,
      fallbackNow: params.authoritativeNow,
    });
  const refundState = asString(params.existingRefund?.state).toLowerCase();
  const payoutProfile = buildPayoutProfileSnapshot(params.providerBankDetails);

  if (
    params.booking.state !== "COMPLETED_FINAL" &&
    params.booking.state !== "NO_SHOW"
  ) {
    return {
      status: "HELD",
      holdReason: "Booking is not in a financially payable terminal state.",
      providerEntitlementPaise,
      remainingPayablePaise,
      readyAt: null,
    };
  }
  if (
    params.booking.payment.status.trim().toLowerCase() !== "paid" &&
    params.booking.payment.status.trim().toLowerCase() !== "confirmed"
  ) {
    return {
      status: "HELD",
      holdReason: "Payment is not confirmed.",
      providerEntitlementPaise,
      remainingPayablePaise,
      readyAt: null,
    };
  }
  if (providerEntitlementPaise <= 0 || remainingPayablePaise <= 0) {
    return {
      status: "CANCELLED",
      holdReason: "No remaining provider payout is due for this booking.",
      providerEntitlementPaise,
      remainingPayablePaise,
      readyAt: null,
    };
  }
  if (disputeStatus === "OPEN" || disputeStatus === "UNDER_REVIEW") {
    return {
      status: "HELD",
      holdReason: "Payout is held while the dispute is under review.",
      providerEntitlementPaise,
      remainingPayablePaise,
      readyAt: null,
    };
  }
  if (
    refundState === "required" ||
    refundState === "submitted" ||
    refundState === "pending"
  ) {
    return {
      status: "HELD",
      holdReason: "Payout remains held while a refund is pending.",
      providerEntitlementPaise,
      remainingPayablePaise,
      readyAt: null,
    };
  }
  if (!payoutProfile.isValid) {
    return {
      status: "HELD",
      holdReason: "Provider payout profile is missing or incomplete.",
      providerEntitlementPaise,
      remainingPayablePaise,
      readyAt: null,
    };
  }
  if (
    payoutEligibleAt != null &&
    payoutEligibleAt.getTime() > params.authoritativeNow.getTime()
  ) {
    return {
      status: "HELD",
      holdReason: "Payout is not eligible yet.",
      providerEntitlementPaise,
      remainingPayablePaise,
      readyAt: null,
    };
  }
  return {
    status: "READY",
    holdReason: "",
    providerEntitlementPaise,
    remainingPayablePaise,
    readyAt: params.authoritativeNow,
  };
}

function resolutionMatches(
  stored: Record<string, unknown>,
  expectedFingerprint: string,
): boolean {
  return asString(stored.inputFingerprint) === expectedFingerprint;
}

function validateAllocationBasisPoints(
  value: number,
  field: string,
): number {
  if (!Number.isInteger(value) || value < 0 || value > 10000) {
    throw new HttpsError(
      "invalid-argument",
      `${field} must be an integer between 0 and 10000.`,
    );
  }
  return value;
}

function safeBigIntToNumber(value: bigint, field: string): number {
  const numberValue = Number(value);
  if (!Number.isSafeInteger(numberValue)) {
    throw new HttpsError(
      "failed-precondition",
      `${field} exceeds the supported integer range.`,
    );
  }
  return numberValue;
}

function allocatePoolPaiseByBasisPoints(params: {
  customerPaidPaise: number;
  customerAllocationBasisPoints: number;
  providerAllocationBasisPoints: number;
  pettxoAllocationBasisPoints: number;
}): {
  customerFinalPaise: number;
  providerAllocationPaise: number;
  pettxoFinalRetainedPaise: number;
} {
  const allocations = [
    {
      key: "customer" as const,
      basisPoints: params.customerAllocationBasisPoints,
      tieOrder: 0,
    },
    {
      key: "provider" as const,
      basisPoints: params.providerAllocationBasisPoints,
      tieOrder: 1,
    },
    {
      key: "pettxo" as const,
      basisPoints: params.pettxoAllocationBasisPoints,
      tieOrder: 2,
    },
  ];
  const paidBigInt = BigInt(params.customerPaidPaise);
  const denominator = 10000n;
  const computed = allocations.map((allocation) => {
    const product = paidBigInt * BigInt(allocation.basisPoints);
    return {
      ...allocation,
      floorPaise: safeBigIntToNumber(
        product / denominator,
        `${allocation.key} allocation`,
      ),
      remainderBasisPoints: safeBigIntToNumber(
        product % denominator,
        `${allocation.key} remainder`,
      ),
    };
  });
  const totalFloorPaise = computed.reduce(
    (sum, allocation) => sum + allocation.floorPaise,
    0,
  );
  let undistributedPaise = params.customerPaidPaise - totalFloorPaise;
  const result = new Map(
    computed.map((allocation) => [allocation.key, allocation.floorPaise]),
  );
  const remainderOrder = [...computed].sort((left, right) => {
    if (right.remainderBasisPoints !== left.remainderBasisPoints) {
      return right.remainderBasisPoints - left.remainderBasisPoints;
    }
    return left.tieOrder - right.tieOrder;
  });
  for (const allocation of remainderOrder) {
    if (undistributedPaise <= 0) break;
    result.set(allocation.key, (result.get(allocation.key) ?? 0) + 1);
    undistributedPaise -= 1;
  }
  return {
    customerFinalPaise: result.get("customer") ?? 0,
    providerAllocationPaise: result.get("provider") ?? 0,
    pettxoFinalRetainedPaise: result.get("pettxo") ?? 0,
  };
}

function deriveAllocationBasisPointsFromPaise(params: {
  customerPaidPaise: number;
  customerFinalPaise: number;
  providerAllocationPaise: number;
  pettxoFinalRetainedPaise: number;
}): {
  customerAllocationBasisPoints: number;
  providerAllocationBasisPoints: number;
  pettxoAllocationBasisPoints: number;
} {
  if (params.customerPaidPaise <= 0) {
    return {
      customerAllocationBasisPoints:
        params.customerFinalPaise > 0 ? 10000 : 0,
      providerAllocationBasisPoints:
        params.providerAllocationPaise > 0 ? 10000 : 0,
      pettxoAllocationBasisPoints:
        params.customerFinalPaise === 0 &&
          params.providerAllocationPaise === 0 &&
          params.pettxoFinalRetainedPaise === 0 ?
          10000 :
          0,
    };
  }
  const customerAllocationBasisPoints = Math.floor(
    (params.customerFinalPaise * 10000) / params.customerPaidPaise,
  );
  const providerAllocationBasisPoints = Math.floor(
    (params.providerAllocationPaise * 10000) / params.customerPaidPaise,
  );
  return {
    customerAllocationBasisPoints,
    providerAllocationBasisPoints,
    pettxoAllocationBasisPoints:
      10000 - customerAllocationBasisPoints - providerAllocationBasisPoints,
  };
}

function normalizeThreePartyAllocationRequest(params: {
  resolutionType: DisputeResolutionType;
  customerPaidPaise: number;
  providerBaseEntitlementPaise: number;
  requestedCustomerAllocationBasisPoints: number | null;
  requestedProviderAllocationBasisPoints: number | null;
  requestedPettxoAllocationBasisPoints: number | null;
  requestedCustomerRefundBasisPoints: number | null;
  requestedCustomerRefundPaise: number | null;
  requestedProviderEntitlementPaise: number | null;
}): {
  customerAllocationBasisPoints: number | null;
  providerAllocationBasisPoints: number | null;
  pettxoAllocationBasisPoints: number | null;
  customerFinalPaise: number;
  providerAllocationPaise: number;
  providerFinalEntitlementPaise: number;
  pettxoFinalRetainedPaise: number;
  customerRefundBasisPoints: number | null;
} {
  const normalizedResolutionType =
    params.resolutionType === "PARTIAL_REFUND" ?
      "CUSTOM_ALLOCATION" :
      params.resolutionType;
  const providerBaseEntitlementPaise = Math.max(
    params.providerBaseEntitlementPaise,
    0,
  );

  if (normalizedResolutionType === "CUSTOMER_WINS") {
    return {
      customerAllocationBasisPoints: 10000,
      providerAllocationBasisPoints: 0,
      pettxoAllocationBasisPoints: 0,
      customerFinalPaise: params.customerPaidPaise,
      providerAllocationPaise: 0,
      providerFinalEntitlementPaise: 0,
      pettxoFinalRetainedPaise: 0,
      customerRefundBasisPoints: 10000,
    };
  }

  if (normalizedResolutionType === "PROVIDER_WINS") {
    const providerAllocationBasisPoints = 8500;
    const pettxoAllocationBasisPoints = 1500;
    const allocated = allocatePoolPaiseByBasisPoints({
      customerPaidPaise: params.customerPaidPaise,
      customerAllocationBasisPoints: 0,
      providerAllocationBasisPoints,
      pettxoAllocationBasisPoints,
    });
    return {
      customerAllocationBasisPoints: 0,
      providerAllocationBasisPoints,
      pettxoAllocationBasisPoints,
      customerFinalPaise: 0,
      providerAllocationPaise: allocated.providerAllocationPaise,
      providerFinalEntitlementPaise: providerBaseEntitlementPaise,
      pettxoFinalRetainedPaise: allocated.pettxoFinalRetainedPaise,
      customerRefundBasisPoints: 0,
    };
  }

  if (normalizedResolutionType === "CUSTOM_ADJUSTMENT") {
    const customerFinalPaise = params.requestedCustomerRefundPaise ?? 0;
    const providerFinalEntitlementPaise =
      params.requestedProviderEntitlementPaise ??
      Math.max(params.customerPaidPaise - customerFinalPaise, 0);
    const providerAllocationPaise = providerFinalEntitlementPaise;
    const pettxoFinalRetainedPaise =
      params.customerPaidPaise -
      customerFinalPaise -
      providerAllocationPaise;
    const basisPoints = deriveAllocationBasisPointsFromPaise({
      customerPaidPaise: params.customerPaidPaise,
      customerFinalPaise,
      providerAllocationPaise,
      pettxoFinalRetainedPaise: Math.max(pettxoFinalRetainedPaise, 0),
    });
    return {
      customerAllocationBasisPoints: basisPoints.customerAllocationBasisPoints,
      providerAllocationBasisPoints: basisPoints.providerAllocationBasisPoints,
      pettxoAllocationBasisPoints: basisPoints.pettxoAllocationBasisPoints,
      customerFinalPaise,
      providerAllocationPaise,
      providerFinalEntitlementPaise,
      pettxoFinalRetainedPaise,
      customerRefundBasisPoints: null,
    };
  }

  const hasThreePartyAllocationInput =
    params.requestedCustomerAllocationBasisPoints != null ||
    params.requestedProviderAllocationBasisPoints != null ||
    params.requestedPettxoAllocationBasisPoints != null;

  if (
    (
      hasThreePartyAllocationInput ||
      params.resolutionType === "CUSTOM_ALLOCATION"
    ) &&
    (
      params.requestedCustomerAllocationBasisPoints == null ||
      params.requestedProviderAllocationBasisPoints == null ||
      params.requestedPettxoAllocationBasisPoints == null
    )
  ) {
    throw new HttpsError(
      "invalid-argument",
      "customerAllocationBasisPoints, providerAllocationBasisPoints, and pettxoAllocationBasisPoints are required.",
    );
  }

  if (
    params.requestedCustomerAllocationBasisPoints != null &&
    params.requestedProviderAllocationBasisPoints != null &&
    params.requestedPettxoAllocationBasisPoints != null
  ) {
    const customerAllocationBasisPoints = validateAllocationBasisPoints(
      params.requestedCustomerAllocationBasisPoints,
      "customerAllocationBasisPoints",
    );
    const providerAllocationBasisPoints = validateAllocationBasisPoints(
      params.requestedProviderAllocationBasisPoints,
      "providerAllocationBasisPoints",
    );
    const pettxoAllocationBasisPoints = validateAllocationBasisPoints(
      params.requestedPettxoAllocationBasisPoints,
      "pettxoAllocationBasisPoints",
    );
    if (
      customerAllocationBasisPoints +
        providerAllocationBasisPoints +
        pettxoAllocationBasisPoints !==
      10000
    ) {
      throw new HttpsError(
        "invalid-argument",
        "customerAllocationBasisPoints + providerAllocationBasisPoints + pettxoAllocationBasisPoints must equal 10000.",
      );
    }
    const allocated = allocatePoolPaiseByBasisPoints({
      customerPaidPaise: params.customerPaidPaise,
      customerAllocationBasisPoints,
      providerAllocationBasisPoints,
      pettxoAllocationBasisPoints,
    });
    return {
      customerAllocationBasisPoints,
      providerAllocationBasisPoints,
      pettxoAllocationBasisPoints,
      customerFinalPaise: allocated.customerFinalPaise,
      providerAllocationPaise: allocated.providerAllocationPaise,
      providerFinalEntitlementPaise: allocated.providerAllocationPaise,
      pettxoFinalRetainedPaise: allocated.pettxoFinalRetainedPaise,
      customerRefundBasisPoints: customerAllocationBasisPoints,
    };
  }

  let customerFinalPaise = 0;
  if (params.requestedCustomerRefundBasisPoints != null) {
    const customerRefundBasisPoints = validateAllocationBasisPoints(
      params.requestedCustomerRefundBasisPoints,
      "customerRefundBasisPoints",
    );
    customerFinalPaise = safeBigIntToNumber(
      (BigInt(params.customerPaidPaise) * BigInt(customerRefundBasisPoints)) /
        10000n,
      "customerRefundPaise",
    );
  } else {
    customerFinalPaise = params.requestedCustomerRefundPaise ?? 0;
  }
  const providerAllocationPaise = Math.min(
    providerBaseEntitlementPaise,
    Math.max(params.customerPaidPaise - customerFinalPaise, 0),
  );
  const pettxoFinalRetainedPaise =
    params.customerPaidPaise -
    customerFinalPaise -
    providerAllocationPaise;
  const basisPoints = deriveAllocationBasisPointsFromPaise({
    customerPaidPaise: params.customerPaidPaise,
    customerFinalPaise,
    providerAllocationPaise,
    pettxoFinalRetainedPaise: Math.max(pettxoFinalRetainedPaise, 0),
  });
  return {
    customerAllocationBasisPoints: basisPoints.customerAllocationBasisPoints,
    providerAllocationBasisPoints: basisPoints.providerAllocationBasisPoints,
    pettxoAllocationBasisPoints: basisPoints.pettxoAllocationBasisPoints,
    customerFinalPaise,
    providerAllocationPaise,
    providerFinalEntitlementPaise: providerAllocationPaise,
    pettxoFinalRetainedPaise,
    customerRefundBasisPoints: params.requestedCustomerRefundBasisPoints ?? null,
  };
}

function buildDisputeResolutionOutcome(params: {
  resolutionType: DisputeResolutionType;
  customerPaidPaise: number;
  alreadyRefundedPaise: number;
  providerBaseEntitlementPaise: number;
  providerAlreadyPaidPaise: number;
  requestedCustomerAllocationBasisPoints: number | null;
  requestedProviderAllocationBasisPoints: number | null;
  requestedPettxoAllocationBasisPoints: number | null;
  requestedCustomerRefundBasisPoints: number | null;
  requestedCustomerRefundPaise: number | null;
  requestedProviderEntitlementPaise: number | null;
}): {
  customerAllocationBasisPoints: number | null;
  providerAllocationBasisPoints: number | null;
  pettxoAllocationBasisPoints: number | null;
  customerRefundBasisPoints: number | null;
  customerFinalPaise: number;
  customerRefundPaise: number;
  providerAllocationPaise: number;
  providerFinalEntitlementPaise: number;
  providerCouponSubsidyPaise: number;
  providerAlreadyPaidPaise: number;
  providerRemainingPayablePaise: number;
  pettxoFinalRetainedPaise: number;
  refundToIssuePaise: number;
} {
  const availableCustomerRefundPaise = Math.max(
    params.customerPaidPaise - params.alreadyRefundedPaise,
    0,
  );
  const normalized = normalizeThreePartyAllocationRequest({
    resolutionType: params.resolutionType,
    customerPaidPaise: params.customerPaidPaise,
    providerBaseEntitlementPaise: params.providerBaseEntitlementPaise,
    requestedCustomerAllocationBasisPoints:
      params.requestedCustomerAllocationBasisPoints,
    requestedProviderAllocationBasisPoints:
      params.requestedProviderAllocationBasisPoints,
    requestedPettxoAllocationBasisPoints:
      params.requestedPettxoAllocationBasisPoints,
    requestedCustomerRefundBasisPoints:
      params.requestedCustomerRefundBasisPoints,
    requestedCustomerRefundPaise: params.requestedCustomerRefundPaise,
    requestedProviderEntitlementPaise:
      params.requestedProviderEntitlementPaise,
  });
  if (normalized.customerFinalPaise < params.alreadyRefundedPaise) {
    throw new HttpsError(
      "failed-precondition",
      "Resolved refund cannot be less than the amount already refunded.",
    );
  }
  if (normalized.customerFinalPaise > params.customerPaidPaise) {
    throw new HttpsError(
      "failed-precondition",
      "Customer refund exceeds the amount paid.",
    );
  }
  if (normalized.providerFinalEntitlementPaise < params.providerAlreadyPaidPaise) {
    throw new HttpsError(
      "failed-precondition",
      "Provider final entitlement cannot be less than the amount already paid.",
    );
  }
  if (normalized.providerFinalEntitlementPaise < 0) {
    throw new HttpsError(
      "failed-precondition",
      "Provider entitlement cannot be negative.",
    );
  }
  if (normalized.providerAllocationPaise < 0) {
    throw new HttpsError(
      "failed-precondition",
      "Provider allocation cannot be negative.",
    );
  }
  if (normalized.pettxoFinalRetainedPaise < 0) {
    throw new HttpsError(
      "failed-precondition",
      "Pettxo final retained amount cannot be negative.",
    );
  }
  if (
    normalized.customerFinalPaise +
      normalized.providerAllocationPaise +
      normalized.pettxoFinalRetainedPaise !==
    params.customerPaidPaise
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Final pool allocations must fully account for the captured customer payment.",
    );
  }
  const providerCouponSubsidyPaise = Math.max(
    normalized.providerFinalEntitlementPaise -
      normalized.providerAllocationPaise,
    0,
  );
  const providerRemainingPayablePaise = Math.max(
    normalized.providerFinalEntitlementPaise - params.providerAlreadyPaidPaise,
    0,
  );
  return {
    customerAllocationBasisPoints:
      normalized.customerAllocationBasisPoints,
    providerAllocationBasisPoints:
      normalized.providerAllocationBasisPoints,
    pettxoAllocationBasisPoints:
      normalized.pettxoAllocationBasisPoints,
    customerRefundBasisPoints: normalized.customerRefundBasisPoints,
    customerFinalPaise: normalized.customerFinalPaise,
    customerRefundPaise: normalized.customerFinalPaise,
    providerAllocationPaise: normalized.providerAllocationPaise,
    providerFinalEntitlementPaise:
      normalized.providerFinalEntitlementPaise,
    providerCouponSubsidyPaise,
    providerAlreadyPaidPaise: params.providerAlreadyPaidPaise,
    providerRemainingPayablePaise,
    pettxoFinalRetainedPaise:
      normalized.pettxoFinalRetainedPaise,
    refundToIssuePaise: Math.min(
      Math.max(normalized.customerFinalPaise - params.alreadyRefundedPaise, 0),
      availableCustomerRefundPaise,
    ),
  };
}

function writeLedgerEntriesIfMissing(params: {
  transaction: FirebaseFirestore.Transaction;
  firestore: Firestore;
  entries: BookingFinancialLedgerEntry[];
}): void {
  for (const entry of params.entries) {
    params.transaction.set(
      params.firestore
        .collection(CANONICAL_FINANCIAL_LEDGER_COLLECTION)
        .doc(entry.entryId),
      serializeLedgerEntry(entry),
      {merge: true},
    );
  }
}

async function loadDisputeResolutionContext(params: {
  firestore: Firestore;
  disputeLookupId: string;
}): Promise<{
  disputeRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
  dispute: Record<string, unknown>;
  bookingId: string;
  booking: CanonicalBookingDocumentV3;
  refundData: Record<string, unknown> | null;
  payoutData: Record<string, unknown> | null;
}> {
  const disputeRef = params.firestore.collection("disputes").doc(params.disputeLookupId);
  const disputeSnapshot = await disputeRef.get();
  if (!disputeSnapshot.exists) {
    throw new HttpsError("not-found", "Dispute not found.");
  }
  const dispute = asRecord(disputeSnapshot.data());
  const bookingId = asString(dispute.bookingId) || disputeRef.id;
  const bookingRef = params.firestore.collection("bookings").doc(bookingId);
  const refundRef = params.firestore.collection("refunds").doc(bookingId);
  const payoutRef = params.firestore
    .collection(CANONICAL_PROVIDER_PAYOUTS_COLLECTION)
    .doc(payoutIdForBooking(bookingId));
  const [bookingSnapshot, refundSnapshot, payoutSnapshot] = await Promise.all([
    bookingRef.get(),
    refundRef.get(),
    payoutRef.get(),
  ]);
  if (!bookingSnapshot.exists) {
    throw new HttpsError("not-found", "Booking not found.");
  }
  const booking = bookingSnapshot.data() as CanonicalBookingDocumentV3;
  if (booking.financials == null) {
    throw new HttpsError(
      "failed-precondition",
      "Canonical booking financial snapshot is missing.",
    );
  }
  return {
    disputeRef,
    dispute,
    bookingId,
    booking,
    refundData: refundSnapshot.exists ? asRecord(refundSnapshot.data()) : null,
    payoutData: payoutSnapshot.exists ? asRecord(payoutSnapshot.data()) : null,
  };
}

function deriveDisputeSettlementFinancialContext(params: {
  booking: CanonicalBookingDocumentV3;
  payoutData: Record<string, unknown> | null;
  resolutionType: DisputeResolutionType;
}): {
  customerPaidPaise: number;
  providerBaseEntitlementPaise: number;
  providerAlreadyPaidPaise: number;
  currency: string;
} {
  const financials = asRecord(params.booking.financials);
  const customerPaidPaise = asInt(financials.customerPaidPaise, -1);
  if (customerPaidPaise < 0) {
    throw new HttpsError(
      "failed-precondition",
      "Financial settlement context is incomplete for this booking.",
      {code: "INCOMPLETE_SETTLEMENT_CONTEXT", field: "customerPaidPaise"},
    );
  }
  const providerBaseEntitlementPaise = asInt(
    params.payoutData?.providerEntitlementPaise,
    asInt(financials.providerPayoutPaise, -1),
  );
  if (
    providerBaseEntitlementPaise < 0 &&
    params.resolutionType !== "CUSTOMER_WINS"
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Financial settlement context is incomplete for this booking.",
      {code: "INCOMPLETE_SETTLEMENT_CONTEXT", field: "providerPayoutPaise"},
    );
  }
  return {
    customerPaidPaise,
    providerBaseEntitlementPaise: Math.max(providerBaseEntitlementPaise, 0),
    providerAlreadyPaidPaise: asInt(params.payoutData?.priorPaidPaise, 0),
    currency: asString(financials.currency) || "INR",
  };
}

export async function previewBookingDisputeResolutionV3(params: {
  firestore: Firestore;
  input: ResolveBookingDisputeInput;
  auth: {uid?: string} | undefined;
}): Promise<PreviewBookingDisputeResolutionResult> {
  const adminUid = requireUid(params.auth);
  await requireFinanceAdminActor(params.firestore, adminUid);
  const disputeLookupId =
    params.input.disputeId?.trim() || params.input.bookingId?.trim();
  if (!disputeLookupId) {
    throw new HttpsError(
      "invalid-argument",
      "disputeId or bookingId is required.",
    );
  }
  const context = await loadDisputeResolutionContext({
    firestore: params.firestore,
    disputeLookupId,
  });
  const financialContext = deriveDisputeSettlementFinancialContext({
    booking: context.booking,
    payoutData: context.payoutData,
    resolutionType: params.input.resolutionType,
  });
  const outcome = buildDisputeResolutionOutcome({
    resolutionType: params.input.resolutionType,
    customerPaidPaise: financialContext.customerPaidPaise,
    alreadyRefundedPaise: asInt(context.refundData?.refundAmountPaise, 0),
    providerBaseEntitlementPaise:
      financialContext.providerBaseEntitlementPaise,
    providerAlreadyPaidPaise: financialContext.providerAlreadyPaidPaise,
    requestedCustomerAllocationBasisPoints:
      params.input.customerAllocationBasisPoints ?? null,
    requestedProviderAllocationBasisPoints:
      params.input.providerAllocationBasisPoints ?? null,
    requestedPettxoAllocationBasisPoints:
      params.input.pettxoAllocationBasisPoints ?? null,
    requestedCustomerRefundBasisPoints:
      params.input.customerRefundBasisPoints ?? null,
    requestedCustomerRefundPaise: params.input.customerRefundPaise ?? null,
    requestedProviderEntitlementPaise:
      params.input.providerFinalEntitlementPaise ?? null,
  });
  return {
    bookingId: context.bookingId,
    disputeId: context.disputeRef.id,
    resolutionType: params.input.resolutionType,
    currency: financialContext.currency,
    customerPaidPaise: financialContext.customerPaidPaise,
    authoritativeAmountPaidPaise: financialContext.customerPaidPaise,
    alreadyRefundedPaise: asInt(context.refundData?.refundAmountPaise, 0),
    providerBaseEntitlementPaise:
      financialContext.providerBaseEntitlementPaise,
    providerAlreadyPaidPaise: financialContext.providerAlreadyPaidPaise,
    providerRemainingPayablePaise: outcome.providerRemainingPayablePaise,
    customerAllocationBasisPoints: outcome.customerAllocationBasisPoints,
    providerAllocationBasisPoints: outcome.providerAllocationBasisPoints,
    pettxoAllocationBasisPoints: outcome.pettxoAllocationBasisPoints,
    customerRefundBasisPoints: outcome.customerRefundBasisPoints,
    customerFinalPaise: outcome.customerFinalPaise,
    customerRefundPaise: outcome.customerRefundPaise,
    providerAllocationPaise: outcome.providerAllocationPaise,
    providerFinalEntitlementPaise: outcome.providerFinalEntitlementPaise,
    providerCouponSubsidyPaise: outcome.providerCouponSubsidyPaise,
    pettxoFinalRetainedPaise: outcome.pettxoFinalRetainedPaise,
    refundToIssuePaise: outcome.refundToIssuePaise,
  };
}

export async function resolveBookingDisputeV3(params: {
  firestore: Firestore;
  input: ResolveBookingDisputeInput;
  auth: {uid?: string} | undefined;
  authoritativeNow?: Date;
}): Promise<ResolveBookingDisputeResult> {
  const now = params.authoritativeNow ?? new Date();
  const adminUid = requireUid(params.auth);
  await requireFinanceAdminActor(params.firestore, adminUid);
  const disputeLookupId =
    params.input.disputeId?.trim() || params.input.bookingId?.trim();
  if (!disputeLookupId) {
    throw new HttpsError(
      "invalid-argument",
      "disputeId or bookingId is required.",
    );
  }
  const attemptId = params.input.resolutionAttemptId.trim();
  if (!attemptId) {
    throw new HttpsError(
      "invalid-argument",
      "resolutionAttemptId is required.",
    );
  }
  logger.info("booking.dispute.resolve.start", {
    disputeLookupId,
    resolutionType: params.input.resolutionType,
    resolutionAttemptId: attemptId,
  });
  const fingerprint = stableHash({
    disputeId: disputeLookupId,
    resolutionType: params.input.resolutionType,
    policyReason: params.input.policyReason.trim(),
        notes: params.input.notes?.trim() ?? "",
        publicResolutionMessage:
          params.input.publicResolutionMessage?.trim() ?? "",
        customerAllocationBasisPoints:
      params.input.customerAllocationBasisPoints ?? null,
    providerAllocationBasisPoints:
      params.input.providerAllocationBasisPoints ?? null,
    pettxoAllocationBasisPoints:
      params.input.pettxoAllocationBasisPoints ?? null,
    customerRefundBasisPoints: params.input.customerRefundBasisPoints ?? null,
    customerRefundPaise: params.input.customerRefundPaise ?? null,
    providerFinalEntitlementPaise:
      params.input.providerFinalEntitlementPaise ?? null,
  });

  try {
    return await params.firestore.runTransaction(async (transaction) => {
    const disputeRef = params.firestore.collection("disputes").doc(disputeLookupId);
    const disputeSnapshot = await transaction.get(disputeRef);
    if (!disputeSnapshot.exists) {
      throw new HttpsError("not-found", "Dispute not found.");
    }
    const dispute = asRecord(disputeSnapshot.data());
    const bookingId = asString(dispute.bookingId) || disputeRef.id;
    const bookingRef = params.firestore.collection("bookings").doc(bookingId);
    const bookingFinancialRef =
      params.firestore.collection("bookingFinancials").doc(bookingId);
    const providerEarningRef =
      params.firestore.collection("providerEarnings").doc(bookingId);
    const payoutReadinessRef =
      params.firestore.collection("payoutReadiness").doc(bookingId);
    const payoutRef =
      params.firestore.collection(CANONICAL_PROVIDER_PAYOUTS_COLLECTION)
        .doc(payoutIdForBooking(bookingId));
    const providerBankDetailsRef = params.firestore
      .collection("users")
      .doc(asString(dispute.providerId))
      .collection("providerBankDetails")
      .doc("main");
    const refundRef = params.firestore.collection("refunds").doc(bookingId);
    const resolutionRef = params.firestore
      .collection(CANONICAL_DISPUTE_RESOLUTIONS_COLLECTION)
      .doc(disputeResolutionIdForBooking(bookingId));
    const adjustmentRef = params.firestore
      .collection("bookingFinancialAdjustments")
      .doc(financialAdjustmentIdForDispute(bookingId, disputeRef.id));

    const [
      bookingSnapshot,
      bookingFinancialSnapshot,
      providerEarningSnapshot,
      payoutReadinessSnapshot,
      providerBankDetailsSnapshot,
      refundSnapshot,
      payoutSnapshot,
      resolutionSnapshot,
      adjustmentSnapshot,
    ] = await Promise.all([
      transaction.get(bookingRef),
      transaction.get(bookingFinancialRef),
      transaction.get(providerEarningRef),
      transaction.get(payoutReadinessRef),
      transaction.get(providerBankDetailsRef),
      transaction.get(refundRef),
      transaction.get(payoutRef),
      transaction.get(resolutionRef),
      transaction.get(adjustmentRef),
    ]);

    if (!bookingSnapshot.exists) {
      throw new HttpsError("not-found", "Booking not found.");
    }
    const booking = bookingSnapshot.data() as CanonicalBookingDocumentV3;
    if (booking.financials == null) {
      throw new HttpsError(
        "failed-precondition",
        "Canonical booking financial snapshot is missing.",
      );
    }
    const financialContext = deriveDisputeSettlementFinancialContext({
      booking,
      payoutData: payoutSnapshot.exists ? asRecord(payoutSnapshot.data()) : null,
      resolutionType: params.input.resolutionType,
    });
    if (resolutionSnapshot.exists) {
      const existing = asRecord(resolutionSnapshot.data());
      if (resolutionMatches(existing, fingerprint)) {
        return {
          ok: true,
          bookingId,
          disputeId: disputeRef.id,
          resolutionId: resolutionRef.id,
          adjustmentId: adjustmentRef.id,
          refundInstructionId:
            asString(existing.refundInstructionId) ||
            refundInstructionIdForDispute(disputeRef.id),
          payoutId: payoutRef.id,
          resolutionType:
            asString(existing.resolutionType) as DisputeResolutionType,
          disputeStatus: "RESOLVED",
          payoutStatus:
            (asString(existing.payoutStatus) as ProviderPayoutStatus) ||
            "HELD",
          customerPaidPaise: asInt(existing.customerPaidPaise, 0),
          authoritativeAmountPaidPaise: asInt(existing.customerPaidPaise, 0),
          customerAllocationBasisPoints:
            asInt(existing.customerAllocationBasisPoints, 0),
          providerAllocationBasisPoints:
            asInt(existing.providerAllocationBasisPoints, 0),
          pettxoAllocationBasisPoints:
            asInt(existing.pettxoAllocationBasisPoints, 0),
          customerFinalPaise: asInt(existing.customerRefundPaise, 0),
          customerRefundPaise: asInt(existing.customerRefundPaise, 0),
          providerAllocationPaise: asInt(
            existing.providerAllocationPaise,
            asInt(existing.providerFinalEntitlementPaise, 0),
          ),
          providerFinalEntitlementPaise: asInt(
            existing.providerFinalEntitlementPaise,
            0,
          ),
          providerCouponSubsidyPaise: asInt(
            existing.providerCouponSubsidyPaise,
            0,
          ),
          providerAlreadyPaidPaise: asInt(existing.providerAlreadyPaidPaise, 0),
          providerRemainingPayablePaise: asInt(
            existing.providerRemainingPayablePaise,
            0,
          ),
          pettxoFinalRetainedPaise: asInt(
            existing.pettxoFinalRetainedPaise,
            0,
          ),
          refundToIssuePaise: asInt(existing.refundToIssuePaise, 0),
          idempotentReplay: true,
        };
      }
      throw new HttpsError(
        "failed-precondition",
        "This dispute has already been resolved with a different outcome.",
      );
    }

    const disputeStatus = asString(dispute.status).toUpperCase();
    if (disputeStatus === "RESOLVED" || disputeStatus === "CLOSED") {
      throw new HttpsError(
        "failed-precondition",
        "This dispute is already resolved.",
      );
    }

    const alreadyRefundedPaise = asInt(refundSnapshot.data()?.refundAmountPaise, 0);
    const outcome = buildDisputeResolutionOutcome({
      resolutionType: params.input.resolutionType,
      customerPaidPaise: financialContext.customerPaidPaise,
      alreadyRefundedPaise,
      providerBaseEntitlementPaise:
        financialContext.providerBaseEntitlementPaise,
      providerAlreadyPaidPaise: financialContext.providerAlreadyPaidPaise,
      requestedCustomerAllocationBasisPoints:
        params.input.customerAllocationBasisPoints ?? null,
      requestedProviderAllocationBasisPoints:
        params.input.providerAllocationBasisPoints ?? null,
      requestedPettxoAllocationBasisPoints:
        params.input.pettxoAllocationBasisPoints ?? null,
      requestedCustomerRefundBasisPoints:
        params.input.customerRefundBasisPoints ?? null,
      requestedCustomerRefundPaise: params.input.customerRefundPaise ?? null,
      requestedProviderEntitlementPaise:
        params.input.providerFinalEntitlementPaise ?? null,
    });
    logger.info("booking.dispute.resolve.outcome_built", {
      bookingId,
      disputeId: disputeRef.id,
      resolutionType: params.input.resolutionType,
      customerRefundPaise: outcome.customerRefundPaise,
      providerFinalEntitlementPaise: outcome.providerFinalEntitlementPaise,
      refundToIssuePaise: outcome.refundToIssuePaise,
    });
    const adjustmentTotalPaise =
      Math.abs(
        booking.financials.providerPayoutPaise -
          outcome.providerFinalEntitlementPaise,
      ) + outcome.refundToIssuePaise;
    const payoutEligibility = evaluateCanonicalProviderPayoutEligibilityV3({
      booking: {
        ...booking,
        dispute: {
          ...booking.dispute,
          status: "RESOLVED",
          resolvedAt: now,
          resolvedBy: "admin",
          resolution: params.input.resolutionType,
          customerRefundPaise: outcome.customerRefundPaise,
          providerReleasePaise: outcome.providerFinalEntitlementPaise,
        },
      },
      existingPayout: {
        ...(payoutSnapshot.data() ?? {}),
        providerEntitlementPaise: outcome.providerFinalEntitlementPaise,
        priorPaidPaise: asInt(payoutSnapshot.data()?.priorPaidPaise, 0),
      },
      existingRefund: outcome.refundToIssuePaise > 0 ?
        {state: "required"} :
        (refundSnapshot.data() ?? null),
      providerBankDetails:
        providerBankDetailsSnapshot.exists ?
          providerBankDetailsSnapshot.data() ?? {} :
          null,
      authoritativeNow: now,
    });
    logger.info("booking.dispute.resolve.transaction_start", {
      bookingId,
      disputeId: disputeRef.id,
      resolutionType: params.input.resolutionType,
      payoutStatus: payoutEligibility.status,
    });

    const payoutDoc =
      payoutSnapshot.exists ?
        asRecord(payoutSnapshot.data()) :
        buildCanonicalProviderPayoutDocumentV3({
          bookingId,
          booking,
          financialAdjustmentTotalPaise: adjustmentTotalPaise,
          now,
        });
    const payoutEligibleAt = resolveRequiredPayoutEligibleAt({
      booking,
      fallbackNow: now,
    });

    const resolutionRecord = {
      resolutionId: resolutionRef.id,
      disputeId: disputeRef.id,
      bookingId,
      resolutionType: params.input.resolutionType,
      policyReason: params.input.policyReason.trim(),
      notes: params.input.notes?.trim() ?? "",
      resolutionAttemptId: attemptId,
      inputFingerprint: fingerprint,
      customerPaidPaise: booking.financials.customerPaidPaise,
      customerAllocationBasisPoints:
        outcome.customerAllocationBasisPoints ?? null,
      providerAllocationBasisPoints:
        outcome.providerAllocationBasisPoints ?? null,
      pettxoAllocationBasisPoints:
        outcome.pettxoAllocationBasisPoints ?? null,
      customerRefundBasisPoints: outcome.customerRefundBasisPoints ?? null,
      customerRefundPaise: outcome.customerRefundPaise,
      providerAllocationPaise: outcome.providerAllocationPaise,
      providerFinalEntitlementPaise: outcome.providerFinalEntitlementPaise,
      providerCouponSubsidyPaise: outcome.providerCouponSubsidyPaise,
      providerAlreadyPaidPaise: outcome.providerAlreadyPaidPaise,
      providerRemainingPayablePaise: outcome.providerRemainingPayablePaise,
      pettxoFinalRetainedPaise: outcome.pettxoFinalRetainedPaise,
      refundToIssuePaise: outcome.refundToIssuePaise,
      refundInstructionId:
        outcome.refundToIssuePaise > 0 ?
          refundInstructionIdForDispute(disputeRef.id) :
          "",
      payoutStatus: payoutEligibility.status,
      resolvedByAdminId: adminUid,
      resolvedAt: Timestamp.fromDate(now),
      policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
      createdAt: Timestamp.fromDate(now),
      updatedAt: Timestamp.fromDate(now),
    };
    transaction.set(resolutionRef, resolutionRecord, {merge: false});
    if (!adjustmentSnapshot.exists) {
      transaction.set(
        adjustmentRef,
        {
          bookingId,
          disputeId: disputeRef.id,
          providerId: booking.providerId,
          userId: booking.parentId,
          adjustmentType: "DISPUTE_RESOLUTION",
          policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
          customerAllocationBasisPoints:
            outcome.customerAllocationBasisPoints ?? null,
          providerAllocationBasisPoints:
            outcome.providerAllocationBasisPoints ?? null,
          pettxoAllocationBasisPoints:
            outcome.pettxoAllocationBasisPoints ?? null,
          customerRefundPaise: outcome.customerRefundPaise,
          providerAllocationPaise: outcome.providerAllocationPaise,
          providerEntitlementPaise: outcome.providerFinalEntitlementPaise,
          providerCouponSubsidyPaise: outcome.providerCouponSubsidyPaise,
          pettxoFinalRetainedPaise: outcome.pettxoFinalRetainedPaise,
          gatewayFeeSunkPaise: booking.financials.gatewayFeeSunkPaise,
          couponCostPaise: booking.financials.pettxoCouponFundingPaise,
          createdAt: Timestamp.fromDate(now),
          updatedAt: Timestamp.fromDate(now),
        },
        {merge: false},
      );
    }

    if (outcome.refundToIssuePaise > 0) {
      transaction.set(
        refundRef,
        {
          bookingId,
          paymentAttemptId: booking.payment.paymentAttemptId,
          userId: booking.parentId,
          providerId: booking.providerId,
          razorpayPaymentId: booking.payment.razorpayPaymentId,
          refundAmountPaise: outcome.customerRefundPaise,
          refundInstructionId: refundInstructionIdForDispute(disputeRef.id),
          reasonCode: `dispute_${params.input.resolutionType.toLowerCase()}`,
          state: "required",
          createdAt:
            refundSnapshot.data()?.createdAt ??
            Timestamp.fromDate(now),
          submittedAt: refundSnapshot.data()?.submittedAt ?? null,
          confirmedAt: refundSnapshot.data()?.confirmedAt ?? null,
          razorpayRefundId:
            asString(refundSnapshot.data()?.razorpayRefundId),
          attemptCount: asInt(refundSnapshot.data()?.attemptCount, 0),
          lastErrorCode: asString(refundSnapshot.data()?.lastErrorCode),
          schemaVersion: 3,
          bookingModelVersion: booking.bookingModelVersion,
          updatedAt: Timestamp.fromDate(now),
        },
        {merge: true},
      );
    }

    const payoutWrite = {
      payoutId: payoutRef.id,
      bookingId,
      providerId: booking.providerId,
      currency: booking.financials.currency,
      grossServiceAmountPaise: booking.financials.serviceSubtotalPaise,
      providerEntitlementPaise: outcome.providerFinalEntitlementPaise,
      priorPaidPaise: asInt(payoutDoc.priorPaidPaise, 0),
      remainingPayablePaise: Math.max(
        outcome.providerFinalEntitlementPaise -
          asInt(payoutDoc.priorPaidPaise, 0),
        0,
      ),
      pettxoRetainedPaise: outcome.pettxoFinalRetainedPaise,
      couponCostPaise: booking.financials.pettxoCouponFundingPaise,
      gatewayFeePaise: booking.financials.gatewayFeeSunkPaise,
      financialAdjustmentTotalPaise: adjustmentTotalPaise,
      status: payoutEligibility.status,
      holdReason: payoutEligibility.holdReason,
      eligibleAt: Timestamp.fromDate(payoutEligibleAt),
      readyAt:
        payoutEligibility.readyAt == null ?
          null :
          Timestamp.fromDate(payoutEligibility.readyAt),
      processingAt: payoutDoc.processingAt ?? null,
      paidAt: payoutDoc.paidAt ?? null,
      failedAt: payoutDoc.failedAt ?? null,
      failureCode: asString(payoutDoc.failureCode),
      failureCategory: asString(payoutDoc.failureCategory),
      retryCount: asInt(payoutDoc.retryCount, 0),
      nextRetryAt: payoutDoc.nextRetryAt ?? null,
      processorLease: asString(payoutDoc.processorLease),
      lastAttemptAt: payoutDoc.lastAttemptAt ?? null,
      externalPayoutId: asString(payoutDoc.externalPayoutId),
      externalTransactionId: asString(payoutDoc.externalTransactionId),
      policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
      createdAt: payoutDoc.createdAt ?? Timestamp.fromDate(now),
      updatedAt: Timestamp.fromDate(now),
    };
    transaction.set(payoutRef, payoutWrite, {merge: true});

    transaction.set(
      disputeRef,
      {
        bookingStateAtCreation: dispute.bookingStateAtCreation ??
          booking.state,
        customerId: booking.parentId,
        providerId: booking.providerId,
        disputeId: disputeRef.id,
        parentId: booking.parentId,
        disputeType: "SERVICE_COMPLETION",
        reasonCode: asString(dispute.reasonCode) || asString(dispute.reason),
        description: asString(dispute.description),
        attachmentPaths:
          Array.isArray(dispute.attachments) ?
            dispute.attachments :
            (Array.isArray(dispute.attachmentPaths) ?
              dispute.attachmentPaths :
              []),
        status: "RESOLVED",
        resolution: {
          type: params.input.resolutionType,
          policyReason: params.input.policyReason.trim(),
          notes: params.input.notes?.trim() ?? "",
          publicMessage:
            params.input.publicResolutionMessage?.trim() ?? "",
          customerAllocationBasisPoints:
            outcome.customerAllocationBasisPoints ?? null,
          providerAllocationBasisPoints:
            outcome.providerAllocationBasisPoints ?? null,
          pettxoAllocationBasisPoints:
            outcome.pettxoAllocationBasisPoints ?? null,
          customerRefundBasisPoints: outcome.customerRefundBasisPoints ?? null,
          customerRefundPaise: outcome.customerRefundPaise,
          providerAllocationPaise: outcome.providerAllocationPaise,
          providerFinalEntitlementPaise:
            outcome.providerFinalEntitlementPaise,
          providerCouponSubsidyPaise: outcome.providerCouponSubsidyPaise,
          pettxoFinalRetainedPaise: outcome.pettxoFinalRetainedPaise,
          refundToIssuePaise: outcome.refundToIssuePaise,
        },
        resolutionVersion: 1,
        resolvedAt: Timestamp.fromDate(now),
        resolvedByAdminId: adminUid,
        publicResolutionMessage:
          params.input.publicResolutionMessage?.trim() ?? "",
        financialAdjustmentId: adjustmentRef.id,
        auditEntryId: `booking.dispute_resolved.${bookingId}`,
        updatedAt: Timestamp.fromDate(now),
        source: "canonical_v3",
      },
      {merge: true},
    );

    transaction.set(
      bookingRef,
      {
        updatedAt: Timestamp.fromDate(now),
        "audit.lastUpdatedBy": "admin",
        "dispute.status": "RESOLVED",
        "dispute.resolvedAt": Timestamp.fromDate(now),
        "dispute.resolvedBy": "admin",
        "dispute.resolution": params.input.resolutionType,
        "dispute.customerRefundPaise": outcome.customerRefundPaise,
        "dispute.providerReleasePaise":
          outcome.providerFinalEntitlementPaise,
        "dispute.publicResolutionMessage":
          params.input.publicResolutionMessage?.trim() ?? "",
        "payout.status": payoutEligibility.status,
        "payout.eligibleAt":
          payoutEligibility.readyAt == null ?
            booking.payout.eligibleAt == null ?
              null :
              Timestamp.fromDate(payoutEligibleAt) :
            Timestamp.fromDate(payoutEligibility.readyAt),
        "payout.providerPayoutPaise":
          outcome.providerFinalEntitlementPaise,
        "payout.failureCode": "",
        "payout.retryCount": 0,
      },
      {merge: true},
    );
    transaction.set(
      bookingFinancialRef,
      {
        status:
          payoutEligibility.status === "READY" ? "READY" : "HELD",
        disputeStatus: "RESOLVED",
        refundAmountPaise: outcome.customerRefundPaise,
        providerAmountPaise: outcome.providerFinalEntitlementPaise,
        pettxoAmountPaise: outcome.pettxoFinalRetainedPaise,
        payoutEligibleAt:
          payoutEligibility.readyAt == null ?
            bookingFinancialSnapshot.data()?.payoutEligibleAt ?? null :
            Timestamp.fromDate(payoutEligibility.readyAt),
        updatedAt: Timestamp.fromDate(now),
        policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
      },
      {merge: true},
    );
    transaction.set(
      providerEarningRef,
      {
        amountPaise: outcome.providerFinalEntitlementPaise,
        status:
          payoutEligibility.status === "READY" ? "READY" : "HELD",
        eligibleAt:
          payoutEligibility.readyAt == null ?
            providerEarningSnapshot.data()?.eligibleAt ?? null :
            Timestamp.fromDate(payoutEligibility.readyAt),
        updatedAt: Timestamp.fromDate(now),
        policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
      },
      {merge: true},
    );
    transaction.set(
      payoutReadinessRef,
      {
        status: payoutEligibility.status,
        payoutStatus: payoutEligibility.status,
        providerAmount: outcome.providerFinalEntitlementPaise,
        providerAmountPaise: outcome.providerFinalEntitlementPaise,
        pettxoAmount: outcome.pettxoFinalRetainedPaise,
        pettxoAmountPaise: outcome.pettxoFinalRetainedPaise,
        eligibilityReason:
          payoutEligibility.holdReason ||
          "Ready because the dispute was resolved.",
        eligibleAt:
          payoutEligibility.readyAt == null ?
            payoutReadinessSnapshot.data()?.eligibleAt ?? null :
            Timestamp.fromDate(payoutEligibility.readyAt),
        updatedAt: Timestamp.fromDate(now),
      },
      {merge: true},
    );

    const ledgerEntries = [
      ...buildBaseLedgerEntries({bookingId, booking, now}),
      {
        entryId: ledgerEntryId({
          bookingId,
          type: "DISPUTE_ADJUSTMENT",
          sourceId: disputeRef.id,
        }),
        bookingId,
        providerId: booking.providerId,
        disputeId: disputeRef.id,
        payoutId: payoutRef.id,
        refundId: refundRef.id,
        type: "DISPUTE_ADJUSTMENT" as const,
        direction: "memo" as const,
        amountPaise: adjustmentTotalPaise,
        currency: booking.financials.currency,
        account: "dispute_adjustment",
        sourceType: "dispute_resolution",
        sourceId: disputeRef.id,
        policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
        occurredAt: now,
        createdAt: now,
        metadata: {
          resolutionType: params.input.resolutionType,
        },
      },
      ...(outcome.customerRefundPaise > 0 ?
        [{
          entryId: ledgerEntryId({
            bookingId,
            type: "CUSTOMER_REFUND",
            sourceId: disputeRef.id,
          }),
          bookingId,
          providerId: booking.providerId,
          disputeId: disputeRef.id,
          payoutId: payoutRef.id,
          refundId: refundRef.id,
          type: "CUSTOMER_REFUND" as const,
          direction: "debit" as const,
          amountPaise: outcome.customerRefundPaise,
          currency: booking.financials.currency,
          account: "customer_refund",
          sourceType: "dispute_resolution",
          sourceId: disputeRef.id,
          policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
          occurredAt: now,
          createdAt: now,
          metadata: {},
        }] :
        []),
    ];
    logger.info("booking.dispute.resolve.ledger_prepare", {
      bookingId,
      disputeId: disputeRef.id,
      resolutionType: params.input.resolutionType,
      ledgerEntryCount: ledgerEntries.length,
    });
    writeLedgerEntriesIfMissing({
      transaction,
      firestore: params.firestore,
      entries: ledgerEntries,
    });

    transaction.set(
      bookingRef.collection("events").doc("dispute_resolved"),
      {
        bookingId,
        event: "dispute_resolved",
        actor: "admin",
        at: Timestamp.fromDate(now),
        meta: {
          disputeId: disputeRef.id,
          resolutionType: params.input.resolutionType,
          customerRefundPaise: outcome.customerRefundPaise,
          providerFinalEntitlementPaise:
            outcome.providerFinalEntitlementPaise,
        },
        schemaVersion: 1,
      },
      {merge: true},
    );
    transaction.set(
      params.firestore.collection("adminAuditLogs").doc(
        `booking.dispute_resolved.${bookingId}`,
      ),
      {
        action: "booking.disputeResolved",
        bookingId,
        disputeId: disputeRef.id,
        resolutionType: params.input.resolutionType,
        adminUid,
        customerRefundPaise: outcome.customerRefundPaise,
        providerFinalEntitlementPaise:
          outcome.providerFinalEntitlementPaise,
        createdAt: Timestamp.fromDate(now),
        updatedAt: Timestamp.fromDate(now),
      },
      {merge: true},
    );
    writeNotification(transaction, params.firestore, {
      idempotencyKey: `booking_dispute_resolved:${bookingId}:${booking.parentId}`,
      userId: booking.parentId,
      type: "booking_dispute_resolved",
      title: "Dispute resolved",
      body:
        outcome.customerRefundPaise > 0 ?
          "Your booking dispute has been resolved and any approved refund is now queued safely." :
          "Your booking dispute has been resolved.",
      bookingId,
      actorId: adminUid,
      now,
    });
    writeNotification(transaction, params.firestore, {
      idempotencyKey: `booking_dispute_resolved:${bookingId}:${booking.providerId}`,
      userId: booking.providerId,
      type: "booking_dispute_resolved",
      title: "Dispute resolved",
      body:
        payoutEligibility.status === "READY" ?
          "The dispute has been resolved and your payout is now ready." :
          "The dispute has been resolved. Payout remains on hold until the remaining financial checks clear.",
      bookingId,
      actorId: adminUid,
      now,
    });

    logger.info("booking.dispute.resolve.transaction_success", {
      bookingId,
      disputeId: disputeRef.id,
      resolutionType: params.input.resolutionType,
      payoutStatus: payoutEligibility.status,
    });
    return {
      ok: true,
      bookingId,
      disputeId: disputeRef.id,
      resolutionId: resolutionRef.id,
      adjustmentId: adjustmentRef.id,
      refundInstructionId:
        outcome.refundToIssuePaise > 0 ?
          refundInstructionIdForDispute(disputeRef.id) :
          "",
      payoutId: payoutRef.id,
      resolutionType: params.input.resolutionType,
      disputeStatus: "RESOLVED",
      payoutStatus: payoutEligibility.status,
      customerRefundPaise: outcome.customerRefundPaise,
      customerFinalPaise: outcome.customerFinalPaise,
      customerAllocationBasisPoints: outcome.customerAllocationBasisPoints,
      providerAllocationBasisPoints: outcome.providerAllocationBasisPoints,
      pettxoAllocationBasisPoints: outcome.pettxoAllocationBasisPoints,
      providerAllocationPaise: outcome.providerAllocationPaise,
      providerFinalEntitlementPaise:
        outcome.providerFinalEntitlementPaise,
      providerCouponSubsidyPaise: outcome.providerCouponSubsidyPaise,
      providerAlreadyPaidPaise: outcome.providerAlreadyPaidPaise,
      providerRemainingPayablePaise: outcome.providerRemainingPayablePaise,
      pettxoFinalRetainedPaise: outcome.pettxoFinalRetainedPaise,
      customerPaidPaise: booking.financials.customerPaidPaise,
      authoritativeAmountPaidPaise: booking.financials.customerPaidPaise,
      refundToIssuePaise: outcome.refundToIssuePaise,
      idempotentReplay: false,
    };
    });
  } catch (error) {
    const errorRecord = asRecord(error);
    logger.error("booking.dispute.resolve.failed", {
      disputeLookupId,
      resolutionType: params.input.resolutionType,
      resolutionAttemptId: attemptId,
      errorCode: asString(errorRecord.code),
      errorMessage:
        error instanceof Error ? error.message : asString(errorRecord.message),
    });
    throw error;
  }
}

function mapPayoutDocument(
  data: Record<string, unknown>,
): ProviderPayoutDocumentV3 {
  return {
    payoutId: asString(data.payoutId),
    bookingId: asString(data.bookingId),
    providerId: asString(data.providerId),
    currency: asString(data.currency) || "INR",
    grossServiceAmountPaise: asInt(data.grossServiceAmountPaise, 0),
    providerEntitlementPaise: asInt(data.providerEntitlementPaise, 0),
    priorPaidPaise: asInt(data.priorPaidPaise, 0),
    remainingPayablePaise: asInt(data.remainingPayablePaise, 0),
    pettxoRetainedPaise: asInt(data.pettxoRetainedPaise, 0),
    couponCostPaise: asInt(data.couponCostPaise, 0),
    gatewayFeePaise: asInt(data.gatewayFeePaise, 0),
    financialAdjustmentTotalPaise: asInt(
      data.financialAdjustmentTotalPaise,
      0,
    ),
    status: (asString(data.status) as ProviderPayoutStatus) || "HELD",
    holdReason: asString(data.holdReason),
    eligibleAt: asDate(data.eligibleAt),
    readyAt: asDate(data.readyAt),
    processingAt: asDate(data.processingAt),
    paidAt: asDate(data.paidAt),
    failedAt: asDate(data.failedAt),
    failureCode: asString(data.failureCode),
    failureCategory: asString(data.failureCategory),
    retryCount: asInt(data.retryCount, 0),
    nextRetryAt: asDate(data.nextRetryAt),
    processorLease: asString(data.processorLease),
    lastAttemptAt: asDate(data.lastAttemptAt),
    externalPayoutId: asString(data.externalPayoutId),
    externalTransactionId: asString(data.externalTransactionId),
    policyVersion: asString(data.policyVersion) || CANONICAL_FINANCIAL_POLICY_VERSION,
    createdAt: asDate(data.createdAt) ?? new Date(0),
    updatedAt: asDate(data.updatedAt) ?? new Date(0),
  };
}

export async function processProviderPayoutV3(params: {
  firestore: Firestore;
  bookingId: string;
  gateway?: ProviderPayoutGatewayV3;
  processorLeaseOwner: string;
  authoritativeNow?: Date;
}): Promise<ProviderPayoutProcessingResult> {
  const now = params.authoritativeNow ?? new Date();
  const gateway = params.gateway ?? new DisabledProviderPayoutGatewayV3();
  const bookingRef = params.firestore.collection("bookings").doc(params.bookingId);
  const payoutRef = params.firestore
    .collection(CANONICAL_PROVIDER_PAYOUTS_COLLECTION)
    .doc(payoutIdForBooking(params.bookingId));
  const refundRef = params.firestore.collection("refunds").doc(params.bookingId);

  const seed = await Promise.all([
    bookingRef.get(),
    payoutRef.get(),
    refundRef.get(),
  ]);
  if (!seed[0].exists) {
    return {
      ok: false,
      code: "NOT_FOUND",
      bookingId: params.bookingId,
      payoutId: payoutRef.id,
      status: "",
      failureCode: "BOOKING_NOT_FOUND",
    };
  }
  const booking = parseCanonicalBookingForFinancials(
    seed[0].data(),
    `bookings/${params.bookingId}`,
  );
  if (booking.financials == null) {
    return {
      ok: false,
      code: "NOT_READY",
      bookingId: params.bookingId,
      payoutId: payoutRef.id,
      status: "HELD",
      failureCode: "MISSING_FINANCIALS",
    };
  }
  const seededPayout = seed[1].exists ?
    mapPayoutDocument(asRecord(seed[1].data())) :
    null;
  if (seededPayout?.status === "PAID") {
    return {
      ok: true,
      code: "IDEMPOTENT_REPLAY",
      bookingId: params.bookingId,
      payoutId: seededPayout.payoutId,
      status: "PAID",
      externalPayoutId: seededPayout.externalPayoutId,
      externalTransactionId: seededPayout.externalTransactionId,
    };
  }

  const providerBankDetailsSnapshot = await params.firestore
    .collection("users")
    .doc(booking.providerId)
    .collection("providerBankDetails")
    .doc("main")
    .get();

  const eligibility = evaluateCanonicalProviderPayoutEligibilityV3({
    booking,
    existingPayout: seed[1].exists ? seed[1].data() ?? {} : null,
    existingRefund: seed[2].exists ? seed[2].data() ?? {} : null,
    providerBankDetails:
      providerBankDetailsSnapshot.exists ?
        providerBankDetailsSnapshot.data() ?? {} :
        null,
    authoritativeNow: now,
  });

  if (eligibility.status === "CANCELLED") {
    await payoutRef.set({
      bookingId: params.bookingId,
      providerId: booking.providerId,
      status: "CANCELLED",
      holdReason: eligibility.holdReason,
      providerEntitlementPaise: eligibility.providerEntitlementPaise,
      remainingPayablePaise: 0,
      updatedAt: Timestamp.fromDate(now),
      policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
    }, {merge: true});
    return {
      ok: false,
      code: "NOT_READY",
      bookingId: params.bookingId,
      payoutId: payoutRef.id,
      status: "CANCELLED",
      failureCode: "NO_REMAINING_PAYOUT",
    };
  }

  await params.firestore.runTransaction(async (transaction) => {
    const [freshBookingSnapshot, freshPayoutSnapshot] = await Promise.all([
      transaction.get(bookingRef),
      transaction.get(payoutRef),
    ]);
    const freshBooking = parseCanonicalBookingForFinancials(
      freshBookingSnapshot.data(),
      `bookings/${params.bookingId}`,
    );
    const freshPayoutData = freshPayoutSnapshot.exists ?
      freshPayoutSnapshot.data() ?? {} :
      buildCanonicalProviderPayoutDocumentV3({
        bookingId: params.bookingId,
        booking: freshBooking,
        status: eligibility.status,
        holdReason: eligibility.holdReason,
        eligibleAt: freshBooking.payout.eligibleAt,
        readyAt: eligibility.readyAt,
        now,
      });
    const freshPayout = mapPayoutDocument(asRecord(freshPayoutData));

    if (freshPayout.status === "PAID") {
      return;
    }
    if (eligibility.status !== "READY") {
      throw new HttpsError("failed-precondition", eligibility.holdReason);
    }
    if (
      freshPayout.status === "PROCESSING" &&
      freshPayout.lastAttemptAt != null &&
      freshPayout.lastAttemptAt.getTime() + PAYOUT_LEASE_MS >
        now.getTime() &&
      freshPayout.processorLease !== params.processorLeaseOwner
    ) {
      throw new HttpsError(
        "aborted",
        "Payout is already being processed by another worker.",
      );
    }

    transaction.set(
      payoutRef,
      {
        payoutId: payoutRef.id,
        bookingId: params.bookingId,
        providerId: freshBooking.providerId,
        currency: freshPayout.currency || freshBooking.financials?.currency || "INR",
        providerEntitlementPaise: eligibility.providerEntitlementPaise,
        remainingPayablePaise: eligibility.remainingPayablePaise,
        status: "PROCESSING",
        holdReason: "",
        readyAt: Timestamp.fromDate(eligibility.readyAt ?? now),
        processingAt: Timestamp.fromDate(now),
        lastAttemptAt: Timestamp.fromDate(now),
        processorLease: params.processorLeaseOwner,
        leaseExpiresAt: Timestamp.fromDate(payoutLeaseExpiresAt(now)),
        updatedAt: Timestamp.fromDate(now),
        policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
      },
      {merge: true},
    );
    transaction.set(
      bookingRef,
      {
        updatedAt: Timestamp.fromDate(now),
        "audit.lastUpdatedBy": "system",
        "payout.status": "PROCESSING",
      },
      {merge: true},
    );
  });

  const processingSnapshot = await payoutRef.get();
  const processingPayout = mapPayoutDocument(asRecord(processingSnapshot.data()));
  if (processingPayout.status === "PAID") {
    return {
      ok: true,
      code: "IDEMPOTENT_REPLAY",
      bookingId: params.bookingId,
      payoutId: processingPayout.payoutId,
      status: "PAID",
      externalPayoutId: processingPayout.externalPayoutId,
      externalTransactionId: processingPayout.externalTransactionId,
    };
  }

  const gatewayResult = await gateway.executePayout({
    payout: processingPayout,
    idempotencyKey: stableHash({
      bookingId: params.bookingId,
      payoutId: processingPayout.payoutId,
      remainingPayablePaise: processingPayout.remainingPayablePaise,
    }),
  });

  if (!gatewayResult.ok &&
    gatewayResult.failureCode === "LIVE_PAYOUT_DISABLED") {
    await payoutRef.set({
      status: "FAILED",
      failedAt: Timestamp.fromDate(now),
      failureCode: "LIVE_PAYOUT_DISABLED",
      failureCategory: "configuration_error",
      retryCount: FieldValue.increment(1),
      nextRetryAt: null,
      processorLease: "",
      updatedAt: Timestamp.fromDate(now),
    }, {merge: true});
    await bookingRef.set({
      updatedAt: Timestamp.fromDate(now),
      "payout.status": "FAILED",
      "payout.failureCode": "LIVE_PAYOUT_DISABLED",
      "payout.retryCount": FieldValue.increment(1),
    }, {merge: true});
    return {
      ok: false,
      code: "LIVE_PAYOUT_DISABLED",
      bookingId: params.bookingId,
      payoutId: processingPayout.payoutId,
      status: "FAILED",
      failureCode: "LIVE_PAYOUT_DISABLED",
    };
  }

  await params.firestore.runTransaction(async (transaction) => {
    const [latestPayoutSnapshot, latestBookingSnapshot] = await Promise.all([
      transaction.get(payoutRef),
      transaction.get(bookingRef),
    ]);
    const latestPayout = mapPayoutDocument(asRecord(latestPayoutSnapshot.data()));
    const latestBooking = parseCanonicalBookingForFinancials(
      latestBookingSnapshot.data(),
      `bookings/${params.bookingId}`,
    );
    if (latestPayout.status === "PAID") {
      return;
    }
    if (latestPayout.processorLease !== params.processorLeaseOwner) {
      throw new HttpsError(
        "aborted",
        "Payout lease is no longer owned by this worker.",
      );
    }

    if (gatewayResult.ok) {
      transaction.set(
        payoutRef,
        {
          status: "PAID",
          paidAt: Timestamp.fromDate(now),
          priorPaidPaise:
            latestPayout.priorPaidPaise + latestPayout.remainingPayablePaise,
          remainingPayablePaise: 0,
          externalPayoutId: gatewayResult.externalPayoutId,
          externalTransactionId: gatewayResult.externalTransactionId,
          processorLease: "",
          failureCode: "",
          failureCategory: "",
          updatedAt: Timestamp.fromDate(now),
        },
        {merge: true},
      );
      transaction.set(
        params.firestore.collection("providerEarnings").doc(params.bookingId),
        {
          status: "PAID",
          paidAt: Timestamp.fromDate(now),
          updatedAt: Timestamp.fromDate(now),
        },
        {merge: true},
      );
      transaction.set(
        params.firestore.collection("payoutReadiness").doc(params.bookingId),
        {
          status: "PAID",
          payoutStatus: "PAID",
          updatedAt: Timestamp.fromDate(now),
        },
        {merge: true},
      );
      transaction.set(
        bookingRef,
        {
          updatedAt: Timestamp.fromDate(now),
          "audit.lastUpdatedBy": "system",
          "payout.status": "PAID",
          "payout.releasedAt": Timestamp.fromDate(now),
          "payout.payoutReference": gatewayResult.externalTransactionId,
          "payout.failureCode": "",
        },
        {merge: true},
      );
      writeLedgerEntriesIfMissing({
        transaction,
        firestore: params.firestore,
        entries: [{
          entryId: ledgerEntryId({
            bookingId: params.bookingId,
            type: "PROVIDER_PAYOUT",
            sourceId: payoutRef.id,
          }),
          bookingId: params.bookingId,
          providerId: latestBooking.providerId,
          disputeId: "",
          payoutId: payoutRef.id,
          refundId: "",
          type: "PROVIDER_PAYOUT",
          direction: "debit",
          amountPaise: latestPayout.remainingPayablePaise,
          currency: latestPayout.currency,
          account: "provider_payout",
          sourceType: "provider_payout",
          sourceId: payoutRef.id,
          policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
          occurredAt: now,
          createdAt: now,
          metadata: {},
        }],
      });
      transaction.set(
        bookingRef.collection("events").doc("payout_released"),
        {
          bookingId: params.bookingId,
          event: "payout_released",
          actor: "system",
          at: Timestamp.fromDate(now),
          meta: {
            payoutId: payoutRef.id,
            externalTransactionId: gatewayResult.externalTransactionId,
          },
          schemaVersion: 1,
        },
        {merge: true},
      );
      writeNotification(transaction, params.firestore, {
        idempotencyKey: `booking_payout_completed:${params.bookingId}:${latestBooking.providerId}`,
        userId: latestBooking.providerId,
        type: "booking_payout_completed",
        title: "Payout completed",
        body: "Your Pettxo payout for this booking has been completed.",
        bookingId: params.bookingId,
        actorId: "system",
        now,
      });
    } else {
      transaction.set(
        payoutRef,
        {
          status: "FAILED",
          failedAt: Timestamp.fromDate(now),
          failureCode: gatewayResult.failureCode,
          failureCategory: gatewayResult.failureCategory,
          retryCount: FieldValue.increment(1),
          nextRetryAt:
            gatewayResult.retryable ?
              Timestamp.fromDate(
                nextPayoutRetryAt(now, latestPayout.retryCount + 1),
              ) :
              null,
          processorLease: "",
          externalPayoutId: gatewayResult.externalPayoutId ?? "",
          externalTransactionId:
            gatewayResult.externalTransactionId ?? "",
          updatedAt: Timestamp.fromDate(now),
        },
        {merge: true},
      );
      transaction.set(
        bookingRef,
        {
          updatedAt: Timestamp.fromDate(now),
          "payout.status": "FAILED",
          "payout.failureCode": gatewayResult.failureCode,
          "payout.retryCount": FieldValue.increment(1),
        },
        {merge: true},
      );
      writeNotification(transaction, params.firestore, {
        idempotencyKey: `booking_payout_failed:${params.bookingId}:${latestBooking.providerId}`,
        userId: latestBooking.providerId,
        type: "booking_payout_failed",
        title: "Payout needs attention",
        body: gatewayResult.retryable ?
          "Your payout is being retried safely in the background." :
          "Your payout needs manual Pettxo review before it can proceed.",
        bookingId: params.bookingId,
        actorId: "system",
        now,
      });
    }
  });

  if (gatewayResult.ok) {
    return {
      ok: true,
      code: "PAID",
      bookingId: params.bookingId,
      payoutId: processingPayout.payoutId,
      status: "PAID",
      externalPayoutId: gatewayResult.externalPayoutId,
      externalTransactionId: gatewayResult.externalTransactionId,
    };
  }
  return {
    ok: false,
    code: "FAILED",
    bookingId: params.bookingId,
    payoutId: processingPayout.payoutId,
    status: "FAILED",
    failureCode: gatewayResult.failureCode,
  };
}

export async function reconcileBookingFinancialsV3(params: {
  firestore: Firestore;
  bookingId: string;
  authoritativeNow?: Date;
}): Promise<BookingFinancialReconciliationResult> {
  const now = params.authoritativeNow ?? new Date();
  const bookingSnapshot = await params.firestore
    .collection("bookings")
    .doc(params.bookingId)
    .get();
  if (!bookingSnapshot.exists) {
    throw new HttpsError("not-found", "Booking not found.");
  }
  const booking = parseCanonicalBookingForFinancials(
    bookingSnapshot.data(),
    `bookings/${params.bookingId}`,
  );
  const financials = booking.financials;
  if (financials == null) {
    return {
      bookingId: params.bookingId,
      status: "INVALID_FINANCIAL_SNAPSHOT",
      action: "MANUAL_REVIEW_REQUIRED",
      issues: ["Canonical financial snapshot is missing."],
      repairWrites: [],
    };
  }

  const [ledgerSnapshot, payoutSnapshot, refundSnapshot] = await Promise.all([
    params.firestore
      .collection(CANONICAL_FINANCIAL_LEDGER_COLLECTION)
      .where("bookingId", "==", params.bookingId)
      .get(),
    params.firestore
      .collection(CANONICAL_PROVIDER_PAYOUTS_COLLECTION)
      .doc(payoutIdForBooking(params.bookingId))
      .get(),
    params.firestore.collection("refunds").doc(params.bookingId).get(),
  ]);

  const issues: string[] = [];
  const repairWrites: Array<{path: string; data: Record<string, unknown>}> = [];
  const ledgerEntries = ledgerSnapshot.docs.map((doc) => asRecord(doc.data()));
  const hasPaymentEntry = ledgerEntries.some((entry) =>
    asString(entry.type) === "PAYMENT_CAPTURED",
  );
  if (!hasPaymentEntry && booking.lifecycle.paidAt != null) {
    issues.push("Missing payment ledger entry.");
    for (const entry of buildBaseLedgerEntries({
      bookingId: params.bookingId,
      booking,
      now,
    })) {
      repairWrites.push({
        path: `${CANONICAL_FINANCIAL_LEDGER_COLLECTION}/${entry.entryId}`,
        data: serializeLedgerEntry(entry),
      });
    }
  }
  const totalRefundLedgerPaise = ledgerEntries
    .filter((entry) => asString(entry.type) === "CUSTOMER_REFUND")
    .reduce((sum, entry) => sum + asInt(entry.amountPaise, 0), 0);
  const refundAmountPaise = asInt(refundSnapshot.data()?.refundAmountPaise, 0);
  if (
    refundAmountPaise > 0 &&
    totalRefundLedgerPaise === 0 &&
    asString(refundSnapshot.data()?.state) === "processed"
  ) {
    issues.push("Refund processed but missing ledger entry.");
    repairWrites.push({
      path:
        `${CANONICAL_FINANCIAL_LEDGER_COLLECTION}/${ledgerEntryId({
          bookingId: params.bookingId,
          type: "CUSTOMER_REFUND",
          sourceId: params.bookingId,
        })}`,
      data: serializeLedgerEntry({
        entryId: ledgerEntryId({
          bookingId: params.bookingId,
          type: "CUSTOMER_REFUND",
          sourceId: params.bookingId,
        }),
        bookingId: params.bookingId,
        providerId: booking.providerId,
        disputeId: "",
        payoutId: payoutIdForBooking(params.bookingId),
        refundId: params.bookingId,
        type: "CUSTOMER_REFUND",
        direction: "debit",
        amountPaise: refundAmountPaise,
        currency: financials.currency,
        account: "customer_refund",
        sourceType: "reconciliation",
        sourceId: params.bookingId,
        policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
        occurredAt: now,
        createdAt: now,
        metadata: {},
      }),
    });
  }
  const payoutData = payoutSnapshot.exists ?
    mapPayoutDocument(asRecord(payoutSnapshot.data())) :
    null;
  if (
    payoutData != null &&
    payoutData.status === "PAID" &&
    !ledgerEntries.some((entry) => asString(entry.type) === "PROVIDER_PAYOUT")
  ) {
    issues.push("Paid provider payout is missing a payout ledger entry.");
  }
  if (
    payoutData != null &&
    payoutData.status === "READY" &&
    payoutData.readyAt != null &&
    payoutData.readyAt.getTime() + (6 * 60 * 60 * 1000) < now.getTime()
  ) {
    issues.push("Payout has stayed READY for too long.");
  }
  if (
    booking.dispute.status.trim().toUpperCase() === "OPEN" &&
    payoutData?.status === "READY"
  ) {
    issues.push("Open dispute detected while payout is marked READY.");
  }

  let status: ReconciliationStatus = "BALANCED";
  let action: ReconciliationAction = "NO_ACTION";
  if (issues.some((issue) => issue.includes("Missing"))) {
    status = "MISSING_ENTRY";
    action = repairWrites.length > 0 ?
      "SAFE_AUTOMATIC_REPAIR" :
      "MANUAL_REVIEW_REQUIRED";
  } else if (issues.some((issue) => issue.includes("READY"))) {
    status = "STALE_PAYOUT";
    action = "MANUAL_REVIEW_REQUIRED";
  } else if (issues.length > 0) {
    status = "AMOUNT_MISMATCH";
    action = "MANUAL_REVIEW_REQUIRED";
  }

  await params.firestore
    .collection(CANONICAL_FINANCIAL_RECONCILIATION_COLLECTION)
    .doc(params.bookingId)
    .set({
      bookingId: params.bookingId,
      status,
      action,
      issues,
      repairWriteCount: repairWrites.length,
      updatedAt: Timestamp.fromDate(now),
      createdAt: FieldValue.serverTimestamp(),
      policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
    }, {merge: true});

  return {
    bookingId: params.bookingId,
    status,
    action,
    issues,
    repairWrites,
  };
}

export async function processReadyProviderPayoutBatchV3(params: {
  firestore: Firestore;
  gateway?: ProviderPayoutGatewayV3;
  processorLeaseOwner: string;
  authoritativeNow?: Date;
  limit?: number;
}): Promise<ProviderPayoutProcessingResult[]> {
  const readySnapshot = await params.firestore
    .collection(CANONICAL_PROVIDER_PAYOUTS_COLLECTION)
    .where("status", "==", "READY")
    .limit(Math.max(params.limit ?? 25, 1))
    .get();
  const results: ProviderPayoutProcessingResult[] = [];
  for (const doc of readySnapshot.docs) {
    results.push(await processProviderPayoutV3({
      firestore: params.firestore,
      bookingId: asString(doc.data().bookingId) || doc.id,
      gateway: params.gateway,
      processorLeaseOwner: params.processorLeaseOwner,
      authoritativeNow: params.authoritativeNow,
    }));
  }
  return results;
}

export async function processRetryableProviderPayoutBatchV3(params: {
  firestore: Firestore;
  gateway?: ProviderPayoutGatewayV3;
  processorLeaseOwner: string;
  authoritativeNow?: Date;
  limit?: number;
}): Promise<ProviderPayoutProcessingResult[]> {
  const now = params.authoritativeNow ?? new Date();
  const failedSnapshot = await params.firestore
    .collection(CANONICAL_PROVIDER_PAYOUTS_COLLECTION)
    .where("status", "==", "FAILED")
    .limit(Math.max(params.limit ?? 25, 1))
    .get();
  const results: ProviderPayoutProcessingResult[] = [];
  for (const doc of failedSnapshot.docs) {
    const nextRetryAt = asDate(doc.data().nextRetryAt);
    if (nextRetryAt != null && nextRetryAt.getTime() > now.getTime()) continue;
    results.push(await processProviderPayoutV3({
      firestore: params.firestore,
      bookingId: asString(doc.data().bookingId) || doc.id,
      gateway: params.gateway,
      processorLeaseOwner: params.processorLeaseOwner,
      authoritativeNow: now,
    }));
  }
  return results;
}
