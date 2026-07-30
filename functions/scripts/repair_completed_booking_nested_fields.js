const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const {FieldValue, FieldPath} = admin.firestore;

const DOTTED_TO_NESTED_PATHS = [
  ["lifecycle.completedAt", "lifecycle.completedAt"],
  ["lifecycle.otpEnteredAt", "lifecycle.otpEnteredAt"],
  ["lifecycle.serviceEndedAt", "lifecycle.serviceEndedAt"],
  ["lifecycle.disputeDeadlineAt", "lifecycle.disputeDeadlineAt"],
  ["lifecycle.reviewWindowEndsAt", "lifecycle.reviewWindowEndsAt"],
  ["payout.status", "payout.status"],
  ["payout.eligibleAt", "payout.eligibleAt"],
  ["payout.providerPayoutPaise", "payout.providerPayoutPaise"],
  ["privacy.otpVisibleToParent", "privacy.otpVisibleToParent"],
  ["completion.policyVersion", "completion.policyVersion"],
  ["completion.reasonCode", "completion.reasonCode"],
  ["audit.lastUpdatedBy", "audit.lastUpdatedBy"],
];

function getNestedValue(source, path) {
  return path.split(".").reduce((current, segment) => {
    if (current == null || typeof current !== "object") return undefined;
    return current[segment];
  }, source);
}

async function main() {
  const bookingId = (process.argv[2] || "").trim();
  if (!bookingId) {
    console.error("Usage: node scripts/repair_completed_booking_nested_fields.js <bookingId>");
    process.exit(1);
  }

  const docRef = db.collection("bookings").doc(bookingId);
  const snapshot = await docRef.get();
  if (!snapshot.exists) {
    console.error(`Booking not found: ${bookingId}`);
    process.exit(1);
  }

  const data = snapshot.data() || {};
  const updates = [];
  let appliedCount = 0;
  let deletedLiteralCount = 0;

  for (const [literalKey, nestedPath] of DOTTED_TO_NESTED_PATHS) {
    const literalValue = data[literalKey];
    if (literalValue !== undefined) {
      updates.push(nestedPath, literalValue);
      appliedCount += 1;
      updates.push(new FieldPath(literalKey), FieldValue.delete());
      deletedLiteralCount += 1;
      continue;
    }

    const nestedValue = getNestedValue(data, nestedPath);
    if (nestedValue !== undefined) {
      continue;
    }
  }

  if (updates.length > 0) {
    await docRef.update(...updates);
  }

  const repaired = await docRef.get();
  const repairedData = repaired.data() || {};

  const validation = {
    bookingExists: repaired.exists,
    state: typeof repairedData.state === "string" ? repairedData.state : null,
    customerIdPresent:
      typeof repairedData.customerId === "string" &&
      repairedData.customerId.trim().length > 0,
    serviceOwnerIdPresent:
      typeof repairedData.serviceOwnerId === "string" &&
      repairedData.serviceOwnerId.trim().length > 0,
    lifecycleCompletedAtPresent: getNestedValue(repairedData, "lifecycle.completedAt") != null,
    lifecycleOtpEnteredAtPresent: getNestedValue(repairedData, "lifecycle.otpEnteredAt") != null,
    lifecycleServiceEndedAtPresent:
      getNestedValue(repairedData, "lifecycle.serviceEndedAt") != null,
    lifecycleDisputeDeadlineAtPresent:
      getNestedValue(repairedData, "lifecycle.disputeDeadlineAt") != null,
    lifecycleReviewWindowEndsAtPresent:
      getNestedValue(repairedData, "lifecycle.reviewWindowEndsAt") != null,
    payoutStatusPresent: typeof getNestedValue(repairedData, "payout.status") === "string",
    payoutEligibleAtPresent: getNestedValue(repairedData, "payout.eligibleAt") != null,
    payoutProviderPayoutPresent:
      typeof getNestedValue(repairedData, "payout.providerPayoutPaise") === "number",
    otpVisibleToParent:
      typeof getNestedValue(repairedData, "privacy.otpVisibleToParent") === "boolean"
        ? getNestedValue(repairedData, "privacy.otpVisibleToParent")
        : null,
    completionPolicyVersionPresent:
      typeof getNestedValue(repairedData, "completion.policyVersion") === "string" &&
      getNestedValue(repairedData, "completion.policyVersion").trim().length > 0,
    completionReasonCodePresent:
      typeof getNestedValue(repairedData, "completion.reasonCode") === "string" &&
      getNestedValue(repairedData, "completion.reasonCode").trim().length > 0,
    auditLastUpdatedByPresent:
      typeof getNestedValue(repairedData, "audit.lastUpdatedBy") === "string" &&
      getNestedValue(repairedData, "audit.lastUpdatedBy").trim().length > 0,
    literalDottedKeysRemaining: DOTTED_TO_NESTED_PATHS.filter(
      ([literalKey]) => repairedData[literalKey] !== undefined,
    ).map(([literalKey]) => literalKey),
    appliedNestedAssignments: appliedCount,
    deletedLiteralFields: deletedLiteralCount,
  };

  console.log(JSON.stringify(validation, null, 2));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
