import {Timestamp, type Firestore} from "firebase-admin/firestore";
import {
  HttpsError,
  onCall,
  type CallableRequest,
} from "firebase-functions/v2/https";

import {db} from "../shared/firebase";

type AdminRole = "superAdmin" | "financeAdmin" | "customerSupportAdmin";
type PayoutMethod = "BANK_ACCOUNT" | "UPI";
type SummaryStatus = "notSubmitted" | "submitted" | "needsUpdate";

const SUMMARY_SCHEMA_VERSION = 2;
const SENSITIVE_SCHEMA_VERSION = 1;
const PROVIDER_PAYOUT_SUMMARY_COLLECTION = "providerBankDetails";
const PROVIDER_PAYOUT_SENSITIVE_COLLECTION = "providerPayoutSensitive";

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value != null ?
    value as Record<string, unknown> :
    {};
}

function requireUid(auth: CallableRequest["auth"]): string {
  const uid = auth?.uid?.trim() ?? "";
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return uid;
}

function summaryRef(firestore: Firestore, userId: string) {
  return firestore
    .collection("users")
    .doc(userId)
    .collection(PROVIDER_PAYOUT_SUMMARY_COLLECTION)
    .doc("main");
}

function sensitiveRef(firestore: Firestore, userId: string) {
  return firestore
    .collection("users")
    .doc(userId)
    .collection(PROVIDER_PAYOUT_SENSITIVE_COLLECTION)
    .doc("main");
}

function maskAccountNumber(accountNumber: string): string {
  const normalized = accountNumber.trim();
  if (normalized.length <= 4) return normalized;
  return `••••${normalized.slice(-4)}`;
}

function maskUpiId(upiId: string): string {
  const normalized = upiId.trim().toLowerCase();
  const [localPart, handle] = normalized.split("@");
  if (!localPart || !handle) return "";
  const visible = localPart.slice(0, Math.min(2, localPart.length));
  return `${visible}${"*".repeat(Math.max(localPart.length - visible.length, 2))}@${handle}`;
}

function normalizeAccountNumber(value: unknown): string {
  const normalized = asString(value).replaceAll(/\s+/g, "");
  if (!/^\d{6,20}$/.test(normalized)) {
    throw new HttpsError("invalid-argument", "Enter a valid account number.");
  }
  return normalized;
}

function normalizeIfscCode(value: unknown): string {
  const normalized = asString(value).replaceAll(/\s+/g, "").toUpperCase();
  if (!/^[A-Z]{4}0[A-Z0-9]{6}$/.test(normalized)) {
    throw new HttpsError("invalid-argument", "Enter a valid IFSC code.");
  }
  return normalized;
}

function normalizeAccountType(value: unknown): "SAVINGS" | "CURRENT" {
  const normalized = asString(value).toUpperCase();
  if (normalized !== "SAVINGS" && normalized !== "CURRENT") {
    throw new HttpsError("invalid-argument", "Select a valid account type.");
  }
  return normalized;
}

function normalizeUpiId(value: unknown): string {
  const normalized = asString(value).replaceAll(/\s+/g, "").toLowerCase();
  if (!/^[a-z0-9._-]{2,256}@[a-z]{2,64}$/.test(normalized)) {
    throw new HttpsError("invalid-argument", "Enter a valid UPI ID.");
  }
  return normalized;
}

function choosePreferredMethod(params: {
  requestedPreferredMethod: string;
  existingPreferredMethod: string;
  hasBankAccount: boolean;
  hasUpi: boolean;
}): PayoutMethod | "" {
  const requested = asString(params.requestedPreferredMethod).toUpperCase();
  const existing = asString(params.existingPreferredMethod).toUpperCase();
  if (requested === "BANK_ACCOUNT" && params.hasBankAccount) {
    return "BANK_ACCOUNT";
  }
  if (requested === "UPI" && params.hasUpi) {
    return "UPI";
  }
  if (existing === "BANK_ACCOUNT" && params.hasBankAccount) {
    return "BANK_ACCOUNT";
  }
  if (existing === "UPI" && params.hasUpi) {
    return "UPI";
  }
  if (params.hasBankAccount && !params.hasUpi) return "BANK_ACCOUNT";
  if (params.hasUpi && !params.hasBankAccount) return "UPI";
  if (params.hasBankAccount) return "BANK_ACCOUNT";
  if (params.hasUpi) return "UPI";
  return "";
}

function computeSummaryStatus(params: {
  hasBankAccount: boolean;
  hasUpi: boolean;
  legacyBankMasked: string;
  legacyUpiRaw: string;
}): SummaryStatus {
  if (params.hasBankAccount || params.hasUpi) {
    return "submitted";
  }
  if (params.legacyBankMasked || params.legacyUpiRaw) {
    return "needsUpdate";
  }
  return "notSubmitted";
}

function buildSummaryDocument(params: {
  userId: string;
  sensitive: Record<string, unknown>;
  previousSummary: Record<string, unknown> | null;
  now: Date;
}) {
  const sensitive = params.sensitive;
  const previousSummary = params.previousSummary ?? {};
  const bankAccount = asRecord(sensitive.bankAccount);
  const upi = asRecord(sensitive.upi);
  const hasBankAccount = bankAccount.accountNumber != null;
  const hasUpi = asString(upi.upiId).length > 0;
  const legacyBankMasked = asString(previousSummary.accountNumberMasked);
  const legacyUpiRaw = asString(previousSummary.upiId);
  const preferredPayoutMethod = choosePreferredMethod({
    requestedPreferredMethod: asString(sensitive.preferredPayoutMethod),
    existingPreferredMethod: asString(previousSummary.preferredPayoutMethod),
    hasBankAccount,
    hasUpi,
  });
  const summaryStatus = computeSummaryStatus({
    hasBankAccount,
    hasUpi,
    legacyBankMasked,
    legacyUpiRaw,
  });
  return {
    userId: params.userId,
    schemaVersion: SUMMARY_SCHEMA_VERSION,
    hasBankAccount,
    hasUpi,
    preferredPayoutMethod,
    accountHolderName: asString(bankAccount.accountHolderName),
    bankName: asString(bankAccount.bankName),
    accountType: asString(bankAccount.accountType),
    accountNumberMasked:
      hasBankAccount ?
        maskAccountNumber(asString(bankAccount.accountNumber)) :
        legacyBankMasked,
    accountNumberLast4:
      hasBankAccount ?
        asString(bankAccount.accountNumber).slice(-4) :
        "",
    ifscCode: asString(bankAccount.ifscCode),
    upiId:
      hasUpi ?
        maskUpiId(asString(upi.upiId)) :
        "",
    bankStatus:
      hasBankAccount ? "configured" :
      legacyBankMasked ? "needsUpdate" :
      "notSubmitted",
    upiStatus:
      hasUpi ? "configured" :
      legacyUpiRaw ? "needsUpdate" :
      "notSubmitted",
    status: summaryStatus,
    createdAt:
      previousSummary.createdAt instanceof Timestamp ?
        previousSummary.createdAt :
        Timestamp.fromDate(params.now),
    updatedAt: Timestamp.fromDate(params.now),
  };
}

async function requireSuperAdmin(
  firestore: Firestore,
  auth: CallableRequest["auth"],
): Promise<string> {
  const uid = requireUid(auth);
  const snapshot = await firestore.collection("users").doc(uid).get();
  const role = asString(snapshot.data()?.adminRole) as AdminRole;
  if (role !== "superAdmin") {
    throw new HttpsError("permission-denied", "Super Admin access required.");
  }
  return uid;
}

export async function getProviderPayoutCredentialsForSuperAdminData(params: {
  firestore: Firestore;
  providerId: string;
  payoutMethod?: string;
}) {
  const providerId = asString(params.providerId);
  const requestedMethod = asString(params.payoutMethod).toUpperCase();
  if (!providerId) {
    throw new HttpsError("invalid-argument", "providerId is required.");
  }
  const sensitiveSnapshot = await sensitiveRef(params.firestore, providerId).get();
  if (!sensitiveSnapshot.exists) {
    throw new HttpsError("not-found", "Payout credentials are not configured.");
  }
  const sensitive = asRecord(sensitiveSnapshot.data());
  const bankAccount = asRecord(sensitive.bankAccount);
  const upi = asRecord(sensitive.upi);
  const hasBankAccount = asString(bankAccount.accountNumber).length > 0;
  const hasUpi = asString(upi.upiId).length > 0;
  const selectedMethod = choosePreferredMethod({
    requestedPreferredMethod: requestedMethod,
    existingPreferredMethod: asString(sensitive.preferredPayoutMethod),
    hasBankAccount,
    hasUpi,
  });
  if (!selectedMethod) {
    throw new HttpsError("failed-precondition", "No payout method is configured.");
  }
  if (selectedMethod === "BANK_ACCOUNT" && !hasBankAccount) {
    throw new HttpsError("failed-precondition", "Requested payout method is unavailable.");
  }
  if (selectedMethod === "UPI" && !hasUpi) {
    throw new HttpsError("failed-precondition", "Requested payout method is unavailable.");
  }
  return {
    providerId,
    payoutMethod: selectedMethod,
    preferredPayoutMethod: asString(sensitive.preferredPayoutMethod),
    bankAccount:
      selectedMethod === "BANK_ACCOUNT" ? {
        accountHolderName: asString(bankAccount.accountHolderName),
        bankName: asString(bankAccount.bankName),
        accountType: asString(bankAccount.accountType),
        accountNumber: asString(bankAccount.accountNumber),
        ifscCode: asString(bankAccount.ifscCode),
      } : null,
    upi:
      selectedMethod === "UPI" ? {
        upiId: asString(upi.upiId),
      } : null,
  };
}

async function migrateLegacyUpiIfNeeded(params: {
  firestore: Firestore;
  userId: string;
  summaryData: Record<string, unknown> | null;
  sensitiveData: Record<string, unknown> | null;
  now: Date;
}): Promise<{
  summaryData: Record<string, unknown> | null;
  sensitiveData: Record<string, unknown> | null;
}> {
  const summaryData = params.summaryData ?? {};
  const sensitiveData = params.sensitiveData ?? {};
  const legacySchemaVersion = Number(summaryData.schemaVersion ?? 0);
  const existingUpi = asString(asRecord(sensitiveData.upi).upiId);
  const legacyUpi = asString(summaryData.upiId);
  if (legacySchemaVersion >= SUMMARY_SCHEMA_VERSION || existingUpi || !legacyUpi.includes("@")) {
    return {
      summaryData: params.summaryData,
      sensitiveData: params.sensitiveData,
    };
  }

  const nowTimestamp = Timestamp.fromDate(params.now);
  const nextSensitive = {
    userId: params.userId,
    schemaVersion: SENSITIVE_SCHEMA_VERSION,
    hasBankAccount: false,
    hasUpi: true,
    preferredPayoutMethod: "UPI",
    bankAccount: asRecord(sensitiveData.bankAccount),
    upi: {
      upiId: normalizeUpiId(legacyUpi),
      updatedAt: nowTimestamp,
    },
    createdAt:
      sensitiveData.createdAt instanceof Timestamp ?
        sensitiveData.createdAt :
        nowTimestamp,
    updatedAt: nowTimestamp,
  };
  const nextSummary = buildSummaryDocument({
    userId: params.userId,
    sensitive: nextSensitive,
    previousSummary: summaryData,
    now: params.now,
  });
  await params.firestore.runTransaction(async (transaction) => {
    transaction.set(sensitiveRef(params.firestore, params.userId), nextSensitive, {merge: false});
    transaction.set(summaryRef(params.firestore, params.userId), nextSummary, {merge: false});
  });
  return {
    summaryData: nextSummary,
    sensitiveData: nextSensitive,
  };
}

export const getProviderPayoutSummary = onCall(
  {region: "asia-south1", invoker: "private", enforceAppCheck: false},
  async (request) => {
    const userId = requireUid(request.auth);
    const now = new Date();
    const [summarySnapshot, sensitiveSnapshot] = await Promise.all([
      summaryRef(db, userId).get(),
      sensitiveRef(db, userId).get(),
    ]);
    const migrated = await migrateLegacyUpiIfNeeded({
      firestore: db,
      userId,
      summaryData: summarySnapshot.exists ? asRecord(summarySnapshot.data()) : null,
      sensitiveData: sensitiveSnapshot.exists ? asRecord(sensitiveSnapshot.data()) : null,
      now,
    });
    const safeSummary = migrated.summaryData ?? buildSummaryDocument({
      userId,
      sensitive: migrated.sensitiveData ?? {},
      previousSummary: summarySnapshot.exists ? asRecord(summarySnapshot.data()) : null,
      now,
    });
    return {
      summary: {
        ...safeSummary,
        createdAt:
          safeSummary.createdAt instanceof Timestamp ?
            safeSummary.createdAt.toDate().toISOString() :
            null,
        updatedAt:
          safeSummary.updatedAt instanceof Timestamp ?
            safeSummary.updatedAt.toDate().toISOString() :
            null,
      },
    };
  },
);

export const saveProviderBankPayoutDetails = onCall(
  {region: "asia-south1", invoker: "private", enforceAppCheck: false},
  async (request) => {
    const userId = requireUid(request.auth);
    const accountHolderName = asString(request.data?.accountHolderName);
    const bankName = asString(request.data?.bankName);
    const accountNumber = normalizeAccountNumber(request.data?.accountNumber);
    const ifscCode = normalizeIfscCode(request.data?.ifscCode);
    const accountType = normalizeAccountType(request.data?.accountType);
    if (!accountHolderName) {
      throw new HttpsError("invalid-argument", "Enter the account holder name.");
    }
    if (!bankName) {
      throw new HttpsError("invalid-argument", "Enter the bank name.");
    }
    const now = new Date();
    await db.runTransaction(async (transaction) => {
      const summarySnapshot = await transaction.get(summaryRef(db, userId));
      const sensitiveSnapshot = await transaction.get(sensitiveRef(db, userId));
      const currentSensitive = sensitiveSnapshot.exists ? asRecord(sensitiveSnapshot.data()) : {};
      const nextSensitive = {
        userId,
        schemaVersion: SENSITIVE_SCHEMA_VERSION,
        hasBankAccount: true,
        hasUpi: asString(asRecord(currentSensitive.upi).upiId).length > 0,
        preferredPayoutMethod: choosePreferredMethod({
          requestedPreferredMethod: "BANK_ACCOUNT",
          existingPreferredMethod: asString(currentSensitive.preferredPayoutMethod),
          hasBankAccount: true,
          hasUpi: asString(asRecord(currentSensitive.upi).upiId).length > 0,
        }),
        bankAccount: {
          accountHolderName,
          bankName,
          accountNumber,
          ifscCode,
          accountType,
          updatedAt: Timestamp.fromDate(now),
        },
        upi: asRecord(currentSensitive.upi),
        createdAt:
          currentSensitive.createdAt instanceof Timestamp ?
            currentSensitive.createdAt :
            Timestamp.fromDate(now),
        updatedAt: Timestamp.fromDate(now),
      };
      const nextSummary = buildSummaryDocument({
        userId,
        sensitive: nextSensitive,
        previousSummary:
          summarySnapshot.exists ? asRecord(summarySnapshot.data()) : null,
        now,
      });
      transaction.set(sensitiveRef(db, userId), nextSensitive, {merge: false});
      transaction.set(summaryRef(db, userId), nextSummary, {merge: false});
    });
    return {ok: true};
  },
);

export const saveProviderUpiPayoutDetails = onCall(
  {region: "asia-south1", invoker: "private", enforceAppCheck: false},
  async (request) => {
    const userId = requireUid(request.auth);
    const upiId = normalizeUpiId(request.data?.upiId);
    const now = new Date();
    await db.runTransaction(async (transaction) => {
      const summarySnapshot = await transaction.get(summaryRef(db, userId));
      const sensitiveSnapshot = await transaction.get(sensitiveRef(db, userId));
      const currentSensitive = sensitiveSnapshot.exists ? asRecord(sensitiveSnapshot.data()) : {};
      const bankAccount = asRecord(currentSensitive.bankAccount);
      const hasBankAccount = asString(bankAccount.accountNumber).length > 0;
      const nextSensitive = {
        userId,
        schemaVersion: SENSITIVE_SCHEMA_VERSION,
        hasBankAccount,
        hasUpi: true,
        preferredPayoutMethod: choosePreferredMethod({
          requestedPreferredMethod: "UPI",
          existingPreferredMethod: asString(currentSensitive.preferredPayoutMethod),
          hasBankAccount,
          hasUpi: true,
        }),
        bankAccount,
        upi: {
          upiId,
          updatedAt: Timestamp.fromDate(now),
        },
        createdAt:
          currentSensitive.createdAt instanceof Timestamp ?
            currentSensitive.createdAt :
            Timestamp.fromDate(now),
        updatedAt: Timestamp.fromDate(now),
      };
      const nextSummary = buildSummaryDocument({
        userId,
        sensitive: nextSensitive,
        previousSummary:
          summarySnapshot.exists ? asRecord(summarySnapshot.data()) : null,
        now,
      });
      transaction.set(sensitiveRef(db, userId), nextSensitive, {merge: false});
      transaction.set(summaryRef(db, userId), nextSummary, {merge: false});
    });
    return {ok: true};
  },
);

export const setPreferredProviderPayoutMethod = onCall(
  {region: "asia-south1", invoker: "private", enforceAppCheck: false},
  async (request) => {
    const userId = requireUid(request.auth);
    const requestedMethod = asString(request.data?.preferredPayoutMethod).toUpperCase();
    if (requestedMethod !== "BANK_ACCOUNT" && requestedMethod !== "UPI") {
      throw new HttpsError("invalid-argument", "Select a valid payout method.");
    }
    const now = new Date();
    await db.runTransaction(async (transaction) => {
      const summarySnapshot = await transaction.get(summaryRef(db, userId));
      const sensitiveSnapshot = await transaction.get(sensitiveRef(db, userId));
      const currentSensitive = sensitiveSnapshot.exists ? asRecord(sensitiveSnapshot.data()) : {};
      const bankAccount = asRecord(currentSensitive.bankAccount);
      const upi = asRecord(currentSensitive.upi);
      const hasBankAccount = asString(bankAccount.accountNumber).length > 0;
      const hasUpi = asString(upi.upiId).length > 0;
      if (requestedMethod === "BANK_ACCOUNT" && !hasBankAccount) {
        throw new HttpsError("failed-precondition", "Add a bank account before selecting it.");
      }
      if (requestedMethod === "UPI" && !hasUpi) {
        throw new HttpsError("failed-precondition", "Add a UPI ID before selecting it.");
      }
      const nextSensitive = {
        userId,
        schemaVersion: SENSITIVE_SCHEMA_VERSION,
        hasBankAccount,
        hasUpi,
        preferredPayoutMethod: requestedMethod,
        bankAccount,
        upi,
        createdAt:
          currentSensitive.createdAt instanceof Timestamp ?
            currentSensitive.createdAt :
            Timestamp.fromDate(now),
        updatedAt: Timestamp.fromDate(now),
      };
      const nextSummary = buildSummaryDocument({
        userId,
        sensitive: nextSensitive,
        previousSummary:
          summarySnapshot.exists ? asRecord(summarySnapshot.data()) : null,
        now,
      });
      transaction.set(sensitiveRef(db, userId), nextSensitive, {merge: false});
      transaction.set(summaryRef(db, userId), nextSummary, {merge: false});
    });
    return {ok: true};
  },
);

export const getProviderPayoutCredentialsForSuperAdmin = onCall(
  {region: "asia-south1", invoker: "private", enforceAppCheck: false},
  async (request) => {
    await requireSuperAdmin(db, request.auth);
    return await getProviderPayoutCredentialsForSuperAdminData({
      firestore: db,
      providerId: asString(request.data?.providerId),
      payoutMethod: asString(request.data?.payoutMethod),
    });
  },
);
