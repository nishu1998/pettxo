import {Timestamp, type Firestore} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";

import {db} from "../shared/firebase";
import {loadAdminActor} from "./bookingAdminOperationsV3";
import {
  buildCanonicalProviderPayoutDocumentV3,
  CANONICAL_DISPUTE_RESOLUTIONS_COLLECTION,
  CANONICAL_FINANCIAL_LEDGER_COLLECTION,
  CANONICAL_FINANCIAL_POLICY_VERSION,
  CANONICAL_MANUAL_SETTLEMENT_OBLIGATIONS_COLLECTION,
  CANONICAL_PROVIDER_PAYOUTS_COLLECTION,
  evaluateCanonicalProviderPayoutEligibilityV3,
  syncManualSettlementObligationsV3,
} from "./application/financialSettlementV3";
import {parseCanonicalBookingDocumentV3, type CanonicalBookingDocumentV3} from "./schema/bookingDocumentV3";
import {normalizeTimestampLike} from "./schema/timestampNormalization";
import {getProviderPayoutCredentialsForSuperAdminData} from "../providerVerification/providerPayoutDetailsFunctions";

type AdminRole = "superAdmin" | "financeAdmin" | "customerSupportAdmin";
type ManualSettlementRecipientType = "PROVIDER" | "CUSTOMER";
type ManualSettlementObligationType = "PROVIDER_PAYOUT" | "CUSTOMER_REFUND";
type ManualSettlementObligationSource = "NORMAL_COMPLETION" | "DISPUTE_RESOLUTION";
type ManualSettlementObligationStatus =
  | "HELD"
  | "READY"
  | "PROCESSING"
  | "COMPLETED"
  | "CANCELLED"
  | "NEEDS_ATTENTION";
type DisputeFinancialSettlementStatus =
  | "NONE"
  | "PENDING"
  | "PARTIALLY_COMPLETED"
  | "COMPLETED";

type CursorPayload = {
  createdAtIso: string;
  docId: string;
};

type ManualSettlementObligationRecord = {
  obligationId: string;
  bookingId: string;
  disputeId: string;
  disputeResolutionId: string;
  recipientType: ManualSettlementRecipientType;
  obligationType: ManualSettlementObligationType;
  recipientUserId: string;
  amountPaise: number;
  currency: string;
  source: ManualSettlementObligationSource;
  status: ManualSettlementObligationStatus;
  financialSettlementStatus: DisputeFinancialSettlementStatus;
  reasonCode: string;
  holdReason: string;
  relatedPayoutId: string;
  relatedRefundId: string;
  paymentAttemptId: string;
  razorpayOrderId: string;
  razorpayPaymentId: string;
  createdAt: Date | null;
  updatedAt: Date | null;
  readyAt: Date | null;
  completedAt: Date | null;
  completedByAdminUid: string;
  metadata: Record<string, unknown>;
};

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;
const MAX_SCAN_BATCHES = 4;

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asInt(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value) ? Math.trunc(value) : fallback;
}

function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value != null ? value as Record<string, unknown> : {};
}

function asDate(value: unknown): Date | null {
  return normalizeTimestampLike(value);
}

function mapStatus(value: unknown): ManualSettlementObligationStatus {
  const normalized = asString(value).toUpperCase();
  if (
    normalized === "HELD" ||
    normalized === "READY" ||
    normalized === "PROCESSING" ||
    normalized === "COMPLETED" ||
    normalized === "CANCELLED" ||
    normalized === "NEEDS_ATTENTION"
  ) {
    return normalized;
  }
  return "HELD";
}

function mapRecipientType(value: unknown): ManualSettlementRecipientType {
  return asString(value).toUpperCase() === "CUSTOMER" ? "CUSTOMER" : "PROVIDER";
}

function mapObligationType(value: unknown): ManualSettlementObligationType {
  return asString(value).toUpperCase() === "CUSTOMER_REFUND" ?
    "CUSTOMER_REFUND" :
    "PROVIDER_PAYOUT";
}

function mapSource(value: unknown): ManualSettlementObligationSource {
  return asString(value).toUpperCase() === "DISPUTE_RESOLUTION" ?
    "DISPUTE_RESOLUTION" :
    "NORMAL_COMPLETION";
}

function mapFinancialSettlementStatus(value: unknown): DisputeFinancialSettlementStatus {
  const normalized = asString(value).toUpperCase();
  if (
    normalized === "NONE" ||
    normalized === "PENDING" ||
    normalized === "PARTIALLY_COMPLETED" ||
    normalized === "COMPLETED"
  ) {
    return normalized;
  }
  return "NONE";
}

function parseObligation(data: Record<string, unknown>, obligationId: string): ManualSettlementObligationRecord {
  return {
    obligationId: asString(data.obligationId) || obligationId,
    bookingId: asString(data.bookingId),
    disputeId: asString(data.disputeId),
    disputeResolutionId: asString(data.disputeResolutionId),
    recipientType: mapRecipientType(data.recipientType),
    obligationType: mapObligationType(data.obligationType),
    recipientUserId: asString(data.recipientUserId),
    amountPaise: asInt(data.amountPaise, 0),
    currency: asString(data.currency) || "INR",
    source: mapSource(data.source),
    status: mapStatus(data.status),
    financialSettlementStatus:
      mapFinancialSettlementStatus(data.financialSettlementStatus),
    reasonCode: asString(data.reasonCode),
    holdReason: asString(data.holdReason),
    relatedPayoutId: asString(data.relatedPayoutId),
    relatedRefundId: asString(data.relatedRefundId),
    paymentAttemptId: asString(data.paymentAttemptId),
    razorpayOrderId: asString(data.razorpayOrderId),
    razorpayPaymentId: asString(data.razorpayPaymentId),
    createdAt: asDate(data.createdAt),
    updatedAt: asDate(data.updatedAt),
    readyAt: asDate(data.readyAt),
    completedAt: asDate(data.completedAt),
    completedByAdminUid: asString(data.completedByAdminUid),
    metadata: asRecord(data.metadata),
  };
}

function clampLimit(value: unknown): number {
  return Math.min(Math.max(asInt(value, DEFAULT_LIMIT), 1), MAX_LIMIT);
}

function encodeCursor(payload: CursorPayload | null): string | null {
  if (payload == null) return null;
  return Buffer.from(JSON.stringify(payload), "utf8").toString("base64");
}

function decodeCursor(rawValue: unknown): CursorPayload | null {
  const encoded = asString(rawValue);
  if (!encoded) return null;
  try {
    const parsed = JSON.parse(Buffer.from(encoded, "base64").toString("utf8"));
    const createdAtIso = asString(parsed.createdAtIso);
    const docId = asString(parsed.docId);
    if (!createdAtIso || !docId || Number.isNaN(new Date(createdAtIso).getTime())) {
      throw new Error("invalid");
    }
    return {createdAtIso, docId};
  } catch {
    throw new HttpsError("invalid-argument", "cursor is invalid.");
  }
}

async function requireSuperAdminActor(
  firestore: Firestore,
  auth: CallableRequest["auth"],
): Promise<{uid: string; role: AdminRole}> {
  const actor = await loadAdminActor(firestore, auth, "financial");
  if (actor.role !== "superAdmin") {
    throw new HttpsError("permission-denied", "Super Admin access required.");
  }
  return {uid: actor.uid, role: actor.role};
}

async function loadCanonicalBooking(
  firestore: Firestore,
  bookingId: string,
): Promise<CanonicalBookingDocumentV3> {
  const bookingSnapshot = await firestore.collection("bookings").doc(bookingId).get();
  if (!bookingSnapshot.exists) {
    throw new HttpsError("not-found", "Booking not found.");
  }
  const parsed = parseCanonicalBookingDocumentV3(bookingSnapshot.data() ?? {});
  if (!parsed.ok) {
    throw new HttpsError("failed-precondition", "Canonical booking document is incomplete.", {
      issues: parsed.issues.map((issue) => ({code: issue.code, path: issue.path})),
    });
  }
  return parsed.booking;
}

function providerObligationIdForBooking(bookingId: string): string {
  return `provider_payout_${bookingId}`;
}

function resolutionIdForBooking(bookingId: string): string {
  return `resolution_${bookingId}`;
}

function customerObligationIdForBooking(bookingId: string): string {
  return `customer_refund_${resolutionIdForBooking(bookingId)}`;
}

function completionLedgerId(obligationId: string): string {
  return `manual_settlement_completion_${obligationId}`;
}

function providerPayoutLedgerId(bookingId: string, payoutId: string): string {
  return `${bookingId}_PROVIDER_PAYOUT_${payoutId}`;
}

function computeAggregateStatus(
  obligations: Array<ManualSettlementObligationRecord | null>,
): DisputeFinancialSettlementStatus {
  const actionable = obligations.filter((entry): entry is ManualSettlementObligationRecord =>
    entry != null && entry.amountPaise > 0,
  );
  if (actionable.length === 0) return "COMPLETED";
  const completedCount = actionable.filter((entry) => entry.status === "COMPLETED").length;
  const terminalCount = actionable.filter((entry) =>
    entry.status === "COMPLETED" || entry.status === "CANCELLED",
  ).length;
  if (completedCount === 0) return "PENDING";
  if (terminalCount >= actionable.length) return "COMPLETED";
  return "PARTIALLY_COMPLETED";
}

function payoutMethodSummary(summary: Record<string, unknown> | null) {
  if (summary == null) return null;
  const preferredPayoutMethod = asString(summary.preferredPayoutMethod).toUpperCase();
  return {
    preferredPayoutMethod: preferredPayoutMethod || null,
    status: asString(summary.status) || null,
    hasBankAccount: summary.hasBankAccount === true,
    hasUpi: summary.hasUpi === true,
    accountHolderName: asString(summary.accountHolderName) || null,
    bankName: asString(summary.bankName) || null,
    accountType: asString(summary.accountType) || null,
    accountNumberMasked: asString(summary.accountNumberMasked) || null,
    upiIdMasked: asString(summary.upiId) || null,
  };
}

async function loadProviderPayoutSummary(
  firestore: Firestore,
  providerId: string,
): Promise<Record<string, unknown> | null> {
  if (!providerId) return null;
  const snapshot = await firestore
    .collection("users")
    .doc(providerId)
    .collection("providerBankDetails")
    .doc("main")
    .get();
  return snapshot.exists ? asRecord(snapshot.data()) : null;
}

async function getObligationById(
  firestore: Firestore,
  obligationId: string,
): Promise<{
  ref: FirebaseFirestore.DocumentReference;
  raw: Record<string, unknown>;
  obligation: ManualSettlementObligationRecord;
}> {
  const ref = firestore
    .collection(CANONICAL_MANUAL_SETTLEMENT_OBLIGATIONS_COLLECTION)
    .doc(obligationId);
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Manual settlement obligation not found.");
  }
  const raw = asRecord(snapshot.data());
  return {
    ref,
    raw,
    obligation: parseObligation(raw, snapshot.id),
  };
}

async function buildListItem(
  firestore: Firestore,
  obligation: ManualSettlementObligationRecord,
) {
  const booking = await loadCanonicalBooking(firestore, obligation.bookingId);
  const payoutSummary =
    obligation.recipientType === "PROVIDER" ?
      await loadProviderPayoutSummary(firestore, booking.providerId) :
      null;
  const recipientDisplayName =
    obligation.recipientType === "PROVIDER" ?
      booking.participants.provider.displayName :
      `${booking.participants.parent.displayFirstName} ${booking.participants.parent.lastInitial}.`;
  return {
    obligationId: obligation.obligationId,
    bookingId: obligation.bookingId,
    disputeId: obligation.disputeId || null,
    disputeResolutionId: obligation.disputeResolutionId || null,
    recipientUserId: obligation.recipientUserId,
    recipientDisplayName,
    recipientType: obligation.recipientType,
    obligationType: obligation.obligationType,
    amountPaise: obligation.amountPaise,
    currency: obligation.currency,
    source: obligation.source,
    status: obligation.status,
    createdAt: obligation.createdAt?.toISOString() ?? null,
    readyAt: obligation.readyAt?.toISOString() ?? null,
    completedAt: obligation.completedAt?.toISOString() ?? null,
    reasonCode: obligation.reasonCode || null,
    holdReason: obligation.holdReason || null,
    payoutMethodSummary: payoutMethodSummary(payoutSummary),
  };
}

function obligationMatchesFilters(
  obligation: ManualSettlementObligationRecord,
  filters: {
    obligationType: string;
    recipientType: string;
    source: string;
    recipientUserId: string;
  },
) {
  if (filters.obligationType &&
      obligation.obligationType !== filters.obligationType) return false;
  if (filters.recipientType &&
      obligation.recipientType !== filters.recipientType) return false;
  if (filters.source &&
      obligation.source !== filters.source) return false;
  if (filters.recipientUserId &&
      obligation.recipientUserId !== filters.recipientUserId) return false;
  return true;
}

async function resolveSearchItems(
  firestore: Firestore,
  search: string,
  filters: {
    status: string;
    obligationType: string;
    recipientType: string;
    source: string;
    recipientUserId: string;
  },
) {
  const normalized = asString(search);
  if (!normalized) return null;

  const exactIds = new Set<string>();
  if (normalized.startsWith("provider_payout_") || normalized.startsWith("customer_refund_")) {
    exactIds.add(normalized);
  } else {
    exactIds.add(providerObligationIdForBooking(normalized));
    exactIds.add(customerObligationIdForBooking(normalized));
  }

  const candidates: ManualSettlementObligationRecord[] = [];
  for (const obligationId of exactIds) {
    const snapshot = await firestore
      .collection(CANONICAL_MANUAL_SETTLEMENT_OBLIGATIONS_COLLECTION)
      .doc(obligationId)
      .get();
    if (!snapshot.exists) continue;
    const obligation = parseObligation(asRecord(snapshot.data()), snapshot.id);
    if (filters.status && obligation.status !== filters.status) continue;
    if (!obligationMatchesFilters(obligation, filters)) continue;
    candidates.push(obligation);
  }
  return candidates;
}

export async function listManualSettlementObligationsDataV3(params: {
  firestore: Firestore;
  auth: CallableRequest["auth"];
  input: Record<string, unknown>;
}) {
  await requireSuperAdminActor(params.firestore, params.auth);
  const limit = clampLimit(params.input.limit);
  let scanCursor = decodeCursor(params.input.cursor);
  const status = mapStatus(params.input.status);
  const rawStatus = asString(params.input.status).toUpperCase();
  const filters = {
    status: rawStatus ? status : "",
    obligationType: asString(params.input.obligationType).toUpperCase(),
    recipientType: asString(params.input.recipientType).toUpperCase(),
    source: asString(params.input.source).toUpperCase(),
    recipientUserId: asString(params.input.recipientUserId),
  };
  const search = asString(params.input.search);

  const searched = await resolveSearchItems(params.firestore, search, filters);
  if (searched != null) {
    const items = await Promise.all(
      searched.slice(0, limit).map((entry) => buildListItem(params.firestore, entry)),
    );
    return {items, nextCursor: null};
  }

  let query = params.firestore
    .collection(CANONICAL_MANUAL_SETTLEMENT_OBLIGATIONS_COLLECTION)
    .orderBy("createdAt", "desc");
  if (filters.status) {
    query = query.where("status", "==", filters.status);
  }
  if (scanCursor != null) {
    query = query.where(
      "createdAt",
      "<=",
      Timestamp.fromDate(new Date(scanCursor.createdAtIso)),
    );
  }

  const items: Array<Record<string, unknown>> = [];
  let lastDocId = "";
  let lastCreatedAtIso = "";
  let skippingCursor = scanCursor != null;

  for (let batch = 0; batch < MAX_SCAN_BATCHES && items.length < limit; batch += 1) {
    const snapshot = await query.limit(limit * 3).get();
    if (snapshot.empty) break;
    for (const doc of snapshot.docs) {
      const obligation = parseObligation(asRecord(doc.data()), doc.id);
      const createdAtIso = obligation.createdAt?.toISOString() ?? "";
      if (skippingCursor) {
        if (doc.id === scanCursor?.docId && createdAtIso === scanCursor.createdAtIso) {
          skippingCursor = false;
        }
        continue;
      }
      if (!obligationMatchesFilters(obligation, filters)) continue;
      items.push(await buildListItem(params.firestore, obligation));
      lastDocId = doc.id;
      lastCreatedAtIso = createdAtIso;
      if (items.length >= limit) break;
    }
    if (items.length >= limit) break;
    const tail = snapshot.docs[snapshot.docs.length - 1];
    const tailDate = asDate(tail.data()?.createdAt);
    if (tailDate == null) break;
    query = params.firestore
      .collection(CANONICAL_MANUAL_SETTLEMENT_OBLIGATIONS_COLLECTION)
      .orderBy("createdAt", "desc")
      .where("createdAt", "<=", Timestamp.fromDate(tailDate));
    if (filters.status) {
      query = query.where("status", "==", filters.status);
    }
    skippingCursor = true;
    scanCursor ??= {
      createdAtIso: tailDate.toISOString(),
      docId: tail.id,
    };
  }

  return {
    items,
    nextCursor:
      items.length >= limit && lastDocId && lastCreatedAtIso ?
        encodeCursor({docId: lastDocId, createdAtIso: lastCreatedAtIso}) :
        null,
  };
}

function buildManualSettlementStatusForReadiness(params: {
  providerObligation: ManualSettlementObligationRecord | null;
  customerObligation: ManualSettlementObligationRecord | null;
}): string {
  if (params.customerObligation != null &&
      params.customerObligation.status !== "COMPLETED" &&
      params.customerObligation.status !== "CANCELLED") {
    return params.customerObligation.status;
  }
  if (params.providerObligation != null) return params.providerObligation.status;
  if (params.customerObligation != null) return params.customerObligation.status;
  return "COMPLETED";
}

async function loadDisputeContext(
  firestore: Firestore,
  obligation: ManualSettlementObligationRecord,
) {
  const resolutionId = obligation.disputeResolutionId || resolutionIdForBooking(obligation.bookingId);
  const [resolutionSnapshot, disputeSnapshot] = await Promise.all([
    firestore.collection(CANONICAL_DISPUTE_RESOLUTIONS_COLLECTION).doc(resolutionId).get(),
    obligation.disputeId ?
      firestore.collection("disputes").doc(obligation.disputeId).get() :
      Promise.resolve(null),
  ]);
  return {
    resolution:
      resolutionSnapshot.exists ? asRecord(resolutionSnapshot.data()) : null,
    dispute:
      disputeSnapshot != null && disputeSnapshot.exists ?
        asRecord(disputeSnapshot.data()) :
        null,
  };
}

export async function getManualSettlementObligationDetailDataV3(params: {
  firestore: Firestore;
  auth: CallableRequest["auth"];
  obligationId: string;
}) {
  await requireSuperAdminActor(params.firestore, params.auth);
  const {obligation} = await getObligationById(params.firestore, params.obligationId);
  const booking = await loadCanonicalBooking(params.firestore, obligation.bookingId);
  const [payoutSummary, payoutSnapshot, payoutReadinessSnapshot, refundSnapshot, disputeContext] =
    await Promise.all([
      loadProviderPayoutSummary(params.firestore, booking.providerId),
      params.firestore.collection(CANONICAL_PROVIDER_PAYOUTS_COLLECTION).doc(obligation.bookingId).get(),
      params.firestore.collection("payoutReadiness").doc(obligation.bookingId).get(),
      params.firestore.collection("refunds").doc(obligation.bookingId).get(),
      loadDisputeContext(params.firestore, obligation),
    ]);
  const payout = payoutSnapshot.exists ? asRecord(payoutSnapshot.data()) : null;
  const payoutReadiness =
    payoutReadinessSnapshot.exists ? asRecord(payoutReadinessSnapshot.data()) : null;
  const refund = refundSnapshot.exists ? asRecord(refundSnapshot.data()) : null;
  return {
    obligation: {
      ...obligation,
      createdAt: obligation.createdAt?.toISOString() ?? null,
      updatedAt: obligation.updatedAt?.toISOString() ?? null,
      readyAt: obligation.readyAt?.toISOString() ?? null,
      completedAt: obligation.completedAt?.toISOString() ?? null,
    },
    booking: {
      bookingId: obligation.bookingId,
      serviceId: booking.serviceId,
      providerId: booking.providerId,
      parentId: booking.parentId,
      bookingType: booking.bookingType,
      state: booking.state,
      serviceTitle: booking.service.serviceTitle,
    },
    recipient: {
      userId: obligation.recipientUserId,
      type: obligation.recipientType,
      displayName:
        obligation.recipientType === "PROVIDER" ?
          booking.participants.provider.displayName :
          `${booking.participants.parent.displayFirstName} ${booking.participants.parent.lastInitial}.`,
    },
    financials: {
      customerPaidPaise: booking.financials?.customerPaidPaise ?? 0,
      serviceSubtotalPaise: booking.financials?.serviceSubtotalPaise ?? 0,
      pettxoCouponFundingPaise: booking.financials?.pettxoCouponFundingPaise ?? 0,
      platformCommissionPaise: booking.financials?.platformCommissionPaise ?? 0,
      canonicalProviderBasePaise: booking.financials?.providerPayoutPaise ?? 0,
      canonicalProviderEntitlementPaise:
        asInt(
          disputeContext.resolution?.providerFinalEntitlementPaise,
          asInt(payout?.providerEntitlementPaise, booking.financials?.providerPayoutPaise ?? 0),
        ),
      finalProviderPayablePaise:
        asInt(payout?.remainingPayablePaise, obligation.amountPaise),
      pettxoRetainedPaise:
        asInt(
          disputeContext.resolution?.pettxoFinalRetainedPaise,
          asInt(payout?.pettxoRetainedPaise, 0),
        ),
      customerRefundPaise:
        asInt(
          disputeContext.resolution?.customerRefundPaise,
          asInt(refund?.refundAmountPaise, 0),
        ),
    },
    dispute: obligation.source === "DISPUTE_RESOLUTION" ? {
      disputeId: obligation.disputeId || null,
      resolutionId: obligation.disputeResolutionId || null,
      resolutionType: asString(disputeContext.resolution?.resolutionType) || null,
      financialSettlementStatus:
        asString(disputeContext.resolution?.financialSettlementStatus) ||
        asString(disputeContext.dispute?.financialSettlementStatus) ||
        obligation.financialSettlementStatus,
      customerRefundAllocationPaise:
        asInt(disputeContext.resolution?.customerRefundPaise, 0),
      providerFinalEntitlementPaise:
        asInt(disputeContext.resolution?.providerFinalEntitlementPaise, 0),
      pettxoFinalRetainedPaise:
        asInt(disputeContext.resolution?.pettxoFinalRetainedPaise, 0),
      resolutionNotes: asString(disputeContext.resolution?.notes) || null,
    } : null,
    payout: {
      status: asString(payout?.status) || null,
      holdReason: asString(payout?.holdReason) || null,
      payoutReadinessStatus: asString(payoutReadiness?.status) || null,
      manualSettlementStatus:
        asString(payoutReadiness?.manualSettlementStatus) || null,
      payoutMethodSummary: payoutMethodSummary(payoutSummary),
    },
    refund: obligation.obligationType === "CUSTOMER_REFUND" ? {
      refundId: obligation.relatedRefundId || obligation.bookingId,
      state: asString(refund?.state) || null,
      executionMode: asString(refund?.executionMode) || null,
      origin: asString(refund?.origin) || null,
      razorpayOrderId: obligation.razorpayOrderId || null,
      razorpayPaymentId: obligation.razorpayPaymentId || null,
      paymentAttemptId: obligation.paymentAttemptId || null,
      razorpayRefundId: asString(refund?.razorpayRefundId) || null,
      manualRefundStatus: asString(refund?.manualRefundStatus) || null,
    } : null,
  };
}

export async function revealManualSettlementProviderDestinationDataV3(params: {
  firestore: Firestore;
  auth: CallableRequest["auth"];
  obligationId: string;
}) {
  await requireSuperAdminActor(params.firestore, params.auth);
  const {obligation} = await getObligationById(params.firestore, params.obligationId);
  if (obligation.obligationType !== "PROVIDER_PAYOUT") {
    throw new HttpsError("failed-precondition", "This obligation is not a provider payout.");
  }
  if (obligation.status === "COMPLETED" || obligation.status === "CANCELLED") {
    throw new HttpsError("failed-precondition", "Payout destination is not actionable for this obligation.");
  }
  const credentials = await getProviderPayoutCredentialsForSuperAdminData({
    firestore: params.firestore,
    providerId: obligation.recipientUserId,
  });
  return {
    obligationId: obligation.obligationId,
    bookingId: obligation.bookingId,
    providerId: obligation.recipientUserId,
    payoutMethod: credentials.payoutMethod,
    preferredPayoutMethod: credentials.preferredPayoutMethod,
    bankAccount: credentials.bankAccount,
    upi: credentials.upi,
  };
}

async function computeDisputeSettlementUpdate(params: {
  firestore: Firestore;
  bookingId: string;
  disputeId: string;
  resolutionId: string;
  providerOverride?: ManualSettlementObligationRecord | null;
  customerOverride?: ManualSettlementObligationRecord | null;
}) {
  const [providerSnapshot, customerSnapshot] = await Promise.all([
    params.firestore
      .collection(CANONICAL_MANUAL_SETTLEMENT_OBLIGATIONS_COLLECTION)
      .doc(providerObligationIdForBooking(params.bookingId))
      .get(),
    params.firestore
      .collection(CANONICAL_MANUAL_SETTLEMENT_OBLIGATIONS_COLLECTION)
      .doc(`customer_refund_${params.resolutionId}`)
      .get(),
  ]);
  const providerObligation =
    params.providerOverride ??
    (providerSnapshot.exists ?
      parseObligation(asRecord(providerSnapshot.data()), providerSnapshot.id) :
      null);
  const customerObligation =
    params.customerOverride ??
    (customerSnapshot.exists ?
      parseObligation(asRecord(customerSnapshot.data()), customerSnapshot.id) :
      null);
  const financialSettlementStatus = computeAggregateStatus([
    providerObligation,
    customerObligation,
  ]);
  const obligationIds = [
    ...(providerObligation != null && providerObligation.amountPaise > 0 ?
      [providerObligation.obligationId] :
      []),
    ...(customerObligation != null && customerObligation.amountPaise > 0 ?
      [customerObligation.obligationId] :
      []),
  ];
  return {
    providerObligation,
    customerObligation,
    financialSettlementStatus,
    obligationIds,
  };
}

function validateProviderManualSettlementEligibility(params: {
  obligation: ManualSettlementObligationRecord;
  booking: CanonicalBookingDocumentV3;
  payout: Record<string, unknown> | null;
  refund: Record<string, unknown> | null;
  providerBankSummary: Record<string, unknown> | null;
  now: Date;
}) {
  if (params.obligation.obligationType !== "PROVIDER_PAYOUT") {
    throw new HttpsError("failed-precondition", "This obligation is not a provider payout.");
  }
  if (params.obligation.amountPaise <= 0) {
    throw new HttpsError("failed-precondition", "No provider payout is due for this obligation.");
  }
  const payoutEligibility = evaluateCanonicalProviderPayoutEligibilityV3({
    booking: params.booking,
    existingPayout: params.payout,
    existingRefund: params.refund,
    providerBankDetails: params.providerBankSummary,
    authoritativeNow: params.now,
  });
  if (payoutEligibility.status !== "READY") {
    throw new HttpsError("failed-precondition", payoutEligibility.holdReason || "Provider payout is not ready.");
  }
  if (params.booking.dispute.status.trim().toUpperCase() === "OPEN" &&
      params.obligation.source !== "DISPUTE_RESOLUTION") {
    throw new HttpsError("failed-precondition", "A new dispute is blocking this provider payout.");
  }
  return payoutEligibility;
}

export async function recordManualProviderPayoutDataV3(params: {
  firestore: Firestore;
  auth: CallableRequest["auth"];
  input: Record<string, unknown>;
}) {
  const admin = await requireSuperAdminActor(params.firestore, params.auth);
  const obligationId = asString(params.input.obligationId);
  const transactionReference = asString(params.input.transactionReference);
  const paymentMethod = asString(params.input.paymentMethod).toUpperCase();
  const adminNote = asString(params.input.adminNote);
  const proofStoragePath = asString(params.input.proofStoragePath);
  if (!obligationId) {
    throw new HttpsError("invalid-argument", "obligationId is required.");
  }
  if (!transactionReference) {
    throw new HttpsError("invalid-argument", "transactionReference is required.");
  }
  const now = new Date();
  return await params.firestore.runTransaction(async (transaction) => {
    const obligationRef = params.firestore
      .collection(CANONICAL_MANUAL_SETTLEMENT_OBLIGATIONS_COLLECTION)
      .doc(obligationId);
    const obligationSnapshot = await transaction.get(obligationRef);
    if (!obligationSnapshot.exists) {
      throw new HttpsError("not-found", "Manual settlement obligation not found.");
    }
    const obligation = parseObligation(asRecord(obligationSnapshot.data()), obligationSnapshot.id);
    const booking = await loadCanonicalBooking(params.firestore, obligation.bookingId);
    const payoutRef = params.firestore
      .collection(CANONICAL_PROVIDER_PAYOUTS_COLLECTION)
      .doc(obligation.bookingId);
    const [payoutSnapshot, refundSnapshot, providerBankSummary] =
      await Promise.all([
        transaction.get(payoutRef),
        transaction.get(params.firestore.collection("refunds").doc(obligation.bookingId)),
        loadProviderPayoutSummary(params.firestore, booking.providerId),
      ]);

    if (obligation.status === "COMPLETED") {
      const existingReference = asString(obligation.metadata.manualTransactionReference);
      if (!existingReference || existingReference === transactionReference) {
        return {
          ok: true,
          code: "ALREADY_COMPLETED",
          obligationId: obligation.obligationId,
          bookingId: obligation.bookingId,
          payoutId: obligation.relatedPayoutId || obligation.bookingId,
          idempotentReplay: true,
        };
      }
      throw new HttpsError("failed-precondition", "This obligation was already completed with different evidence.");
    }
    if (obligation.status !== "READY") {
      throw new HttpsError("failed-precondition", "Only READY provider payout obligations can be completed.");
    }

    const payout = payoutSnapshot.exists ?
      asRecord(payoutSnapshot.data()) :
      buildCanonicalProviderPayoutDocumentV3({
        bookingId: obligation.bookingId,
        booking,
        status: obligation.status === "READY" ? "READY" : "HELD",
        holdReason: obligation.holdReason,
        eligibleAt: obligation.readyAt,
        readyAt: obligation.readyAt,
        now,
      });

    if (asString(payout.status).toUpperCase() === "PAID") {
      throw new HttpsError("failed-precondition", "Provider payout is already marked paid.");
    }
    if (asString(payout.status).toUpperCase() === "CANCELLED") {
      throw new HttpsError("failed-precondition", "Provider payout was cancelled.");
    }

    validateProviderManualSettlementEligibility({
      obligation,
      booking,
      payout,
      refund: refundSnapshot.exists ? asRecord(refundSnapshot.data()) : null,
      providerBankSummary,
      now,
    });

    const amountPaise = obligation.amountPaise;
    const priorPaidPaise = asInt(payout.priorPaidPaise, 0);
    const paidAt = now;
    const completedObligation: ManualSettlementObligationRecord = {
      ...obligation,
      status: "COMPLETED",
      financialSettlementStatus: "COMPLETED",
      completedAt: paidAt,
      completedByAdminUid: admin.uid,
      updatedAt: paidAt,
      metadata: {
        ...obligation.metadata,
        manualTransactionReference: transactionReference,
        manualSettlementMethod: paymentMethod || null,
        manualAdminNote: adminNote || null,
        proofStoragePath: proofStoragePath || null,
        completedByAdminRole: admin.role,
      },
    };

    transaction.set(obligationRef, {
      status: "COMPLETED",
      financialSettlementStatus: "COMPLETED",
      completedAt: Timestamp.fromDate(paidAt),
      completedByAdminUid: admin.uid,
      updatedAt: Timestamp.fromDate(paidAt),
      metadata: completedObligation.metadata,
    }, {merge: true});
    transaction.set(payoutRef, {
      status: "PAID",
      paidAt: Timestamp.fromDate(paidAt),
      priorPaidPaise: priorPaidPaise + amountPaise,
      remainingPayablePaise: 0,
      externalTransactionId: transactionReference,
      failureCode: "",
      failureCategory: "",
      updatedAt: Timestamp.fromDate(paidAt),
      manualSettlementRecordedAt: Timestamp.fromDate(paidAt),
      manualSettlementRecordedByAdminUid: admin.uid,
      manualSettlementRecordedByAdminRole: admin.role,
      manualSettlementMethod: paymentMethod || null,
      manualSettlementReference: transactionReference,
      manualSettlementNote: adminNote || null,
      manualSettlementProofStoragePath: proofStoragePath || null,
    }, {merge: true});
    transaction.set(
      params.firestore.collection("providerEarnings").doc(obligation.bookingId),
      {
        status: "PAID",
        paidAt: Timestamp.fromDate(paidAt),
        updatedAt: Timestamp.fromDate(paidAt),
      },
      {merge: true},
    );
    transaction.set(
      params.firestore.collection("payoutReadiness").doc(obligation.bookingId),
      {
        status: "PAID",
        payoutStatus: "PAID",
        manualSettlementStatus: "COMPLETED",
        updatedAt: Timestamp.fromDate(paidAt),
      },
      {merge: true},
    );
    transaction.set(
      params.firestore.collection("bookings").doc(obligation.bookingId),
      {
        updatedAt: Timestamp.fromDate(paidAt),
        "audit.lastUpdatedBy": "admin",
        "payout.status": "PAID",
        "payout.releasedAt": Timestamp.fromDate(paidAt),
        "payout.payoutReference": transactionReference,
        "payout.failureCode": "",
      },
      {merge: true},
    );

    if (obligation.source === "DISPUTE_RESOLUTION" && obligation.disputeId) {
      const aggregate = await computeDisputeSettlementUpdate({
        firestore: params.firestore,
        bookingId: obligation.bookingId,
        disputeId: obligation.disputeId,
        resolutionId: obligation.disputeResolutionId || resolutionIdForBooking(obligation.bookingId),
        providerOverride: completedObligation,
      });
      transaction.set(
        params.firestore
          .collection(CANONICAL_DISPUTE_RESOLUTIONS_COLLECTION)
          .doc(obligation.disputeResolutionId || resolutionIdForBooking(obligation.bookingId)),
        {
          financialSettlementStatus: aggregate.financialSettlementStatus,
          manualSettlementObligationIds: aggregate.obligationIds,
          updatedAt: Timestamp.fromDate(paidAt),
        },
        {merge: true},
      );
      transaction.set(obligationRef, {
        financialSettlementStatus: aggregate.financialSettlementStatus,
      }, {merge: true});
      transaction.set(
        params.firestore.collection("disputes").doc(obligation.disputeId),
        {
          financialSettlementStatus: aggregate.financialSettlementStatus,
          "resolution.financialSettlementStatus": aggregate.financialSettlementStatus,
          "resolution.manualSettlementObligationIds": aggregate.obligationIds,
          updatedAt: Timestamp.fromDate(paidAt),
        },
        {merge: true},
      );
      transaction.set(
        params.firestore.collection("bookings").doc(obligation.bookingId),
        {
          "dispute.financialSettlementStatus": aggregate.financialSettlementStatus,
          "dispute.manualSettlementObligationIds": aggregate.obligationIds,
        },
        {merge: true},
      );
      transaction.set(
        params.firestore.collection("payoutReadiness").doc(obligation.bookingId),
        {
          manualSettlementStatus: buildManualSettlementStatusForReadiness({
            providerObligation: completedObligation,
            customerObligation: aggregate.customerObligation,
          }),
        },
        {merge: true},
      );
    }

    transaction.set(
      params.firestore.collection(CANONICAL_FINANCIAL_LEDGER_COLLECTION)
        .doc(providerPayoutLedgerId(obligation.bookingId, obligation.relatedPayoutId || obligation.bookingId)),
      {
        entryId: providerPayoutLedgerId(
          obligation.bookingId,
          obligation.relatedPayoutId || obligation.bookingId,
        ),
        bookingId: obligation.bookingId,
        providerId: booking.providerId,
        disputeId: obligation.disputeId,
        payoutId: obligation.relatedPayoutId || obligation.bookingId,
        refundId: obligation.relatedRefundId,
        type: "PROVIDER_PAYOUT",
        direction: "debit",
        amountPaise,
        currency: obligation.currency,
        account: "provider_payout",
        sourceType: "manual_settlement_completion",
        sourceId: obligation.obligationId,
        policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
        occurredAt: Timestamp.fromDate(paidAt),
        createdAt: Timestamp.fromDate(paidAt),
        metadata: {
          manualSettlement: true,
          transactionReference,
          method: paymentMethod || null,
        },
      },
      {merge: false},
    );
    transaction.set(
      params.firestore.collection(CANONICAL_FINANCIAL_LEDGER_COLLECTION)
        .doc(completionLedgerId(obligation.obligationId)),
      {
        entryId: completionLedgerId(obligation.obligationId),
        bookingId: obligation.bookingId,
        providerId: booking.providerId,
        disputeId: obligation.disputeId,
        payoutId: obligation.relatedPayoutId,
        refundId: obligation.relatedRefundId,
        type: "MANUAL_SETTLEMENT_OBLIGATION",
        direction: "memo",
        amountPaise,
        currency: obligation.currency,
        account: "manual_settlement_completion",
        sourceType: "manual_settlement_completion",
        sourceId: obligation.obligationId,
        policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
        occurredAt: Timestamp.fromDate(paidAt),
        createdAt: Timestamp.fromDate(paidAt),
        metadata: {
          action: "PROVIDER_PAYOUT_RECORDED",
          completedByAdminUid: admin.uid,
          completedByAdminRole: admin.role,
          transactionReference,
          method: paymentMethod || null,
        },
      },
      {merge: false},
    );

    return {
      ok: true,
      code: "RECORDED",
      obligationId: obligation.obligationId,
      bookingId: obligation.bookingId,
      payoutId: obligation.relatedPayoutId || obligation.bookingId,
      idempotentReplay: false,
    };
  });
}

export async function recordManualCustomerRefundDataV3(params: {
  firestore: Firestore;
  auth: CallableRequest["auth"];
  input: Record<string, unknown>;
}) {
  const admin = await requireSuperAdminActor(params.firestore, params.auth);
  const obligationId = asString(params.input.obligationId);
  const razorpayRefundId = asString(params.input.razorpayRefundId);
  const manualReference = asString(params.input.reference);
  const adminNote = asString(params.input.adminNote);
  const proofStoragePath = asString(params.input.proofStoragePath);
  if (!obligationId) {
    throw new HttpsError("invalid-argument", "obligationId is required.");
  }
  const now = new Date();
  return await params.firestore.runTransaction(async (transaction) => {
    const obligationRef = params.firestore
      .collection(CANONICAL_MANUAL_SETTLEMENT_OBLIGATIONS_COLLECTION)
      .doc(obligationId);
    const obligationSnapshot = await transaction.get(obligationRef);
    if (!obligationSnapshot.exists) {
      throw new HttpsError("not-found", "Manual settlement obligation not found.");
    }
    const obligation = parseObligation(asRecord(obligationSnapshot.data()), obligationSnapshot.id);
    if (obligation.obligationType !== "CUSTOMER_REFUND") {
      throw new HttpsError("failed-precondition", "This obligation is not a customer refund.");
    }
    if (obligation.source !== "DISPUTE_RESOLUTION") {
      throw new HttpsError("failed-precondition", "Only dispute manual refunds can be recorded here.");
    }
    if (obligation.amountPaise <= 0) {
      throw new HttpsError("failed-precondition", "No customer refund is due for this obligation.");
    }
    const refundRef = params.firestore.collection("refunds").doc(obligation.bookingId);
    const [refundSnapshot, resolutionSnapshot] = await Promise.all([
      transaction.get(refundRef),
      transaction.get(
        params.firestore
          .collection(CANONICAL_DISPUTE_RESOLUTIONS_COLLECTION)
          .doc(obligation.disputeResolutionId || resolutionIdForBooking(obligation.bookingId)),
      ),
    ]);
    const booking = await loadCanonicalBooking(params.firestore, obligation.bookingId);
    const refund = refundSnapshot.exists ? asRecord(refundSnapshot.data()) : null;
    if (refund == null) {
      throw new HttpsError("failed-precondition", "Canonical refund record is missing.");
    }
    if (obligation.status === "COMPLETED") {
      const existingRefundId = asString(obligation.metadata.razorpayRefundId);
      if (!existingRefundId || existingRefundId === razorpayRefundId || !razorpayRefundId) {
        return {
          ok: true,
          code: "ALREADY_COMPLETED",
          obligationId: obligation.obligationId,
          bookingId: obligation.bookingId,
          idempotentReplay: true,
        };
      }
      throw new HttpsError("failed-precondition", "This obligation was already completed with different refund evidence.");
    }
    const existingRecordedRefundId = asString(obligation.metadata.razorpayRefundId);
    if (
      obligation.status === "PROCESSING" &&
      existingRecordedRefundId &&
      razorpayRefundId &&
      existingRecordedRefundId !== razorpayRefundId
    ) {
      throw new HttpsError("failed-precondition", "This obligation is already processing with different refund evidence.");
    }
    if (
      obligation.status !== "READY" &&
      obligation.status !== "PROCESSING" &&
      obligation.status !== "NEEDS_ATTENTION"
    ) {
      throw new HttpsError("failed-precondition", "Only READY, PROCESSING, or NEEDS_ATTENTION customer refund obligations can be recorded.");
    }
    if (asString(refund.executionMode).toUpperCase() !== "MANUAL" ||
        asString(refund.origin).toUpperCase() !== "DISPUTE_RESOLUTION") {
      throw new HttpsError("failed-precondition", "Refund record is not a manual dispute refund.");
    }
    if (obligation.amountPaise > (booking.financials?.customerPaidPaise ?? 0)) {
      throw new HttpsError("failed-precondition", "Refund amount exceeds the canonical customer-paid amount.");
    }
    if (asString(resolutionSnapshot.data()?.resolutionId) &&
        asString(resolutionSnapshot.data()?.resolutionId) !==
          (obligation.disputeResolutionId || resolutionIdForBooking(obligation.bookingId))) {
      throw new HttpsError("failed-precondition", "Dispute resolution does not match this obligation.");
    }

    const completedObligation: ManualSettlementObligationRecord = {
      ...obligation,
      status: "PROCESSING",
      financialSettlementStatus: "PENDING",
      completedAt: null,
      completedByAdminUid: "",
      updatedAt: now,
      metadata: {
        ...obligation.metadata,
        razorpayRefundId: razorpayRefundId || null,
        manualReference: manualReference || null,
        manualAdminNote: adminNote || null,
        proofStoragePath: proofStoragePath || null,
        completedByAdminRole: admin.role,
      },
    };

    transaction.set(obligationRef, {
      status: "PROCESSING",
      financialSettlementStatus: "PENDING",
      completedAt: null,
      completedByAdminUid: "",
      updatedAt: Timestamp.fromDate(now),
      metadata: completedObligation.metadata,
    }, {merge: true});
    transaction.set(refundRef, {
      state: "manual_recorded",
      executionMode: "MANUAL",
      origin: "DISPUTE_RESOLUTION",
      manualRefundStatus: "INITIATED",
      manualRecordedAt: Timestamp.fromDate(now),
      manualRecordedByAdminUid: admin.uid,
      manualRecordedByAdminRole: admin.role,
      razorpayRefundId: razorpayRefundId || asString(refund.razorpayRefundId),
      manualReference: manualReference || null,
      manualNote: adminNote || null,
      manualProofStoragePath: proofStoragePath || null,
      updatedAt: Timestamp.fromDate(now),
      confirmedAt: refund.confirmedAt ?? null,
    }, {merge: true});

    const aggregate = await computeDisputeSettlementUpdate({
      firestore: params.firestore,
      bookingId: obligation.bookingId,
      disputeId: obligation.disputeId,
      resolutionId: obligation.disputeResolutionId || resolutionIdForBooking(obligation.bookingId),
      customerOverride: completedObligation,
    });
    transaction.set(obligationRef, {
      financialSettlementStatus: aggregate.financialSettlementStatus,
    }, {merge: true});
    transaction.set(
      params.firestore
        .collection(CANONICAL_DISPUTE_RESOLUTIONS_COLLECTION)
        .doc(obligation.disputeResolutionId || resolutionIdForBooking(obligation.bookingId)),
      {
        financialSettlementStatus: aggregate.financialSettlementStatus,
        manualSettlementObligationIds: aggregate.obligationIds,
        updatedAt: Timestamp.fromDate(now),
      },
      {merge: true},
    );
    transaction.set(
      params.firestore.collection("disputes").doc(obligation.disputeId),
      {
        financialSettlementStatus: aggregate.financialSettlementStatus,
        "resolution.financialSettlementStatus": aggregate.financialSettlementStatus,
        "resolution.manualSettlementObligationIds": aggregate.obligationIds,
        updatedAt: Timestamp.fromDate(now),
      },
      {merge: true},
    );
    transaction.set(
      params.firestore.collection("bookings").doc(obligation.bookingId),
      {
        updatedAt: Timestamp.fromDate(now),
        "audit.lastUpdatedBy": "admin",
        "dispute.financialSettlementStatus": aggregate.financialSettlementStatus,
        "dispute.manualSettlementObligationIds": aggregate.obligationIds,
      },
      {merge: true},
    );
    transaction.set(
      params.firestore.collection("payoutReadiness").doc(obligation.bookingId),
      {
      manualSettlementStatus: buildManualSettlementStatusForReadiness({
          providerObligation: aggregate.providerObligation,
          customerObligation: completedObligation,
        }),
        updatedAt: Timestamp.fromDate(now),
      },
      {merge: true},
    );
    transaction.set(
      params.firestore.collection(CANONICAL_FINANCIAL_LEDGER_COLLECTION)
        .doc(completionLedgerId(obligation.obligationId)),
      {
        entryId: completionLedgerId(obligation.obligationId),
        bookingId: obligation.bookingId,
        providerId: booking.providerId,
        disputeId: obligation.disputeId,
        payoutId: obligation.relatedPayoutId,
        refundId: obligation.relatedRefundId || obligation.bookingId,
        type: "MANUAL_SETTLEMENT_OBLIGATION",
        direction: "memo",
        amountPaise: obligation.amountPaise,
        currency: obligation.currency,
        account: "manual_settlement_completion",
        sourceType: "manual_settlement_completion",
        sourceId: obligation.obligationId,
        policyVersion: CANONICAL_FINANCIAL_POLICY_VERSION,
        occurredAt: Timestamp.fromDate(now),
        createdAt: Timestamp.fromDate(now),
        metadata: {
          action: "CUSTOMER_REFUND_RECORDED",
          completedByAdminUid: admin.uid,
          completedByAdminRole: admin.role,
          razorpayRefundId: razorpayRefundId || null,
          manualReference: manualReference || null,
        },
      },
      {merge: false},
    );

    return {
      ok: true,
      code: "RECORDED",
      obligationId: obligation.obligationId,
      bookingId: obligation.bookingId,
      refundId: obligation.relatedRefundId || obligation.bookingId,
      idempotentReplay: false,
    };
  });
}

export async function materializeManualSettlementObligationsForBookingDataV3(params: {
  firestore: Firestore;
  auth: CallableRequest["auth"];
  bookingId: string;
}) {
  await requireSuperAdminActor(params.firestore, params.auth);
  if (!params.bookingId) {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }
  const booking = await loadCanonicalBooking(params.firestore, params.bookingId);
  if (booking.financials == null) {
    throw new HttpsError("failed-precondition", "Canonical financial snapshot is missing.");
  }
  if (booking.dispute.status.trim().toUpperCase() === "OPEN" ||
      booking.dispute.status.trim().toUpperCase() === "UNDER_REVIEW") {
    return {
      ok: true,
      code: "BLOCKED_BY_DISPUTE",
      bookingId: params.bookingId,
      obligationId: null,
    };
  }
  return await params.firestore.runTransaction(async (transaction) => {
    const providerObligationRef = params.firestore
      .collection(CANONICAL_MANUAL_SETTLEMENT_OBLIGATIONS_COLLECTION)
      .doc(providerObligationIdForBooking(params.bookingId));
    const payoutRef = params.firestore
      .collection(CANONICAL_PROVIDER_PAYOUTS_COLLECTION)
      .doc(params.bookingId);
    const [providerObligationSnapshot, payoutSnapshot, refundSnapshot, providerBankSummary] =
      await Promise.all([
        transaction.get(providerObligationRef),
        transaction.get(payoutRef),
        transaction.get(params.firestore.collection("refunds").doc(params.bookingId)),
        loadProviderPayoutSummary(params.firestore, booking.providerId),
      ]);
    if (providerObligationSnapshot.exists) {
      return {
        ok: true,
        code: "ALREADY_EXISTS",
        bookingId: params.bookingId,
        obligationId: providerObligationSnapshot.id,
      };
    }
    const payout = payoutSnapshot.exists ?
      asRecord(payoutSnapshot.data()) :
      null;
    if (asString(payout?.status).toUpperCase() === "PAID") {
      return {
        ok: true,
        code: "NO_ACTION_ALREADY_PAID",
        bookingId: params.bookingId,
        obligationId: null,
      };
    }
    const eligibility = evaluateCanonicalProviderPayoutEligibilityV3({
      booking,
      existingPayout: payout,
      existingRefund: refundSnapshot.exists ? asRecord(refundSnapshot.data()) : null,
      providerBankDetails: providerBankSummary,
      authoritativeNow: new Date(),
    });
    const payoutDocument = payout ?? buildCanonicalProviderPayoutDocumentV3({
      bookingId: params.bookingId,
      booking,
      priorPaidPaise: 0,
      status: eligibility.status,
      holdReason: eligibility.holdReason,
      eligibleAt: booking.payout.eligibleAt,
      readyAt: eligibility.readyAt,
      now: new Date(),
    });
    if (asInt(payoutDocument.remainingPayablePaise, 0) <= 0) {
      return {
        ok: true,
        code: "NO_ACTION_ZERO_AMOUNT",
        bookingId: params.bookingId,
        obligationId: null,
      };
    }
    if (!payoutSnapshot.exists) {
      transaction.set(payoutRef, payoutDocument, {merge: true});
    }
    const sync = syncManualSettlementObligationsV3({
      transaction,
      firestore: params.firestore,
      bookingId: params.bookingId,
      booking,
      now: new Date(),
      providerPayout: {
        payoutId: asString(payoutDocument.payoutId) || params.bookingId,
        providerEntitlementPaise:
          asInt(payoutDocument.providerEntitlementPaise, booking.financials?.providerPayoutPaise ?? 0),
        remainingPayablePaise:
          asInt(payoutDocument.remainingPayablePaise, booking.financials?.providerPayoutPaise ?? 0),
        status: mapStatus(payoutDocument.status) === "COMPLETED" ? "PAID" :
          mapStatus(payoutDocument.status) === "CANCELLED" ? "CANCELLED" :
          mapStatus(payoutDocument.status) === "READY" ? "READY" :
          mapStatus(payoutDocument.status) === "NEEDS_ATTENTION" ? "FAILED" :
          "HELD",
        holdReason: asString(payoutDocument.holdReason),
        readyAt: asDate(payoutDocument.readyAt),
        paidAt: asDate(payoutDocument.paidAt),
      },
      source: "NORMAL_COMPLETION",
      existingProviderObligation: null,
    });
    return {
      ok: true,
      code: sync.providerObligation == null ? "NO_ACTION_ZERO_AMOUNT" : "MATERIALIZED",
      bookingId: params.bookingId,
      obligationId: sync.providerObligation?.obligationId ?? null,
    };
  });
}

export const listManualSettlementObligationsV3 = onCall(
  {invoker: "private"},
  async (request) => {
    return await listManualSettlementObligationsDataV3({
      firestore: db,
      auth: request.auth,
      input: asRecord(request.data),
    });
  },
);

export const getManualSettlementObligationV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const obligationId = asString(request.data?.obligationId);
    if (!obligationId) {
      throw new HttpsError("invalid-argument", "obligationId is required.");
    }
    return await getManualSettlementObligationDetailDataV3({
      firestore: db,
      auth: request.auth,
      obligationId,
    });
  },
);

export const revealManualSettlementProviderDestinationV3 = onCall(
  {invoker: "private"},
  async (request) => {
    const obligationId = asString(request.data?.obligationId);
    if (!obligationId) {
      throw new HttpsError("invalid-argument", "obligationId is required.");
    }
    return await revealManualSettlementProviderDestinationDataV3({
      firestore: db,
      auth: request.auth,
      obligationId,
    });
  },
);

export const recordManualProviderPayoutV3 = onCall(
  {invoker: "private"},
  async (request) => {
    return await recordManualProviderPayoutDataV3({
      firestore: db,
      auth: request.auth,
      input: asRecord(request.data),
    });
  },
);

export const recordManualCustomerRefundV3 = onCall(
  {invoker: "private"},
  async (request) => {
    return await recordManualCustomerRefundDataV3({
      firestore: db,
      auth: request.auth,
      input: asRecord(request.data),
    });
  },
);

export const materializeManualSettlementObligationsForBookingV3 = onCall(
  {invoker: "private"},
  async (request) => {
    return await materializeManualSettlementObligationsForBookingDataV3({
      firestore: db,
      auth: request.auth,
      bookingId: asString(request.data?.bookingId),
    });
  },
);
