#!/usr/bin/env node
"use strict";

/**
 * Moves literal dotted keys (for example a top-level field named
 * "lifecycle.completedAt") on one booking into the nested path they were
 * meant to be.
 *
 * Usage (emulator only, or a non-production project via --allow-project):
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
 *     node scripts/repair_completed_booking_nested_fields.js <bookingId> \
 *     --project=demo-<name> [--apply]
 *
 * Default is a dry run that prints the planned field moves. --apply writes.
 * The target guard runs before firebase-admin is loaded and can never target
 * pettexo-d9409.
 */

const {assertAppTarget, assertSafeScriptTarget} = require("./lib/targetGuard");

const SCRIPT_NAME = "repair_completed_booking_nested_fields";

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

function parseArgs(argv) {
  const positional = argv.filter((arg) => !arg.startsWith("--"));
  const flags = argv.filter((arg) => arg.startsWith("--"));
  const known = (flag) => flag === "--apply" || flag === "--dry-run" ||
    flag.startsWith("--project=") || flag.startsWith("--allow-project=");
  const unknown = flags.filter((flag) => !known(flag));
  if (unknown.length > 0) {
    throw new Error(`Unknown option(s): ${unknown.join(", ")}`);
  }
  const apply = flags.includes("--apply");
  if (apply && flags.includes("--dry-run")) {
    throw new Error("--apply and --dry-run cannot be combined.");
  }
  return {bookingId: (positional[0] || "").trim(), apply};
}

function planFieldMoves(data) {
  const moves = [];
  for (const [literalKey, nestedPath] of DOTTED_TO_NESTED_PATHS) {
    const literalValue = data[literalKey];
    if (literalValue !== undefined) {
      moves.push({from: literalKey, to: nestedPath, value: literalValue});
    }
  }
  return moves;
}

async function main() {
  const argv = process.argv.slice(2);
  // Guard first: before firebase-admin is loaded or any credential is used.
  const target = assertSafeScriptTarget({scriptName: SCRIPT_NAME, argv});
  const options = parseArgs(argv);
  if (!options.bookingId || options.bookingId.includes("/")) {
    console.error(
      "Usage: node scripts/repair_completed_booking_nested_fields.js <bookingId> " +
      "--project=demo-<name> [--apply]",
    );
    process.exit(1);
  }

  const {deleteApp, initializeApp} = require("firebase-admin/app");
  const {FieldPath, FieldValue, getFirestore} = require("firebase-admin/firestore");
  const app = initializeApp({projectId: target.projectId}, `${SCRIPT_NAME}-${Date.now()}`);
  try {
    assertAppTarget(app, target);
    await repairBooking({
      db: getFirestore(app),
      FieldPath,
      FieldValue,
      bookingId: options.bookingId,
      apply: options.apply,
      target,
    });
  } finally {
    await deleteApp(app);
  }
}

async function repairBooking({db, FieldPath, FieldValue, bookingId, apply, target}) {
  const docRef = db.collection("bookings").doc(bookingId);
  const snapshot = await docRef.get();
  if (!snapshot.exists) {
    throw new Error(`Booking not found: ${bookingId}`);
  }

  const data = snapshot.data() || {};
  const moves = planFieldMoves(data);
  console.log(JSON.stringify({
    mode: apply ? "apply" : "dry-run",
    target: target.mode,
    projectId: target.projectId,
    bookingId,
    plannedFieldMoves: moves.map((move) => ({from: move.from, to: move.to})),
  }, null, 2));

  if (!apply) {
    console.log("Dry run: no changes written. Re-run with --apply to write.");
    return;
  }

  const updates = [];
  let appliedCount = 0;
  let deletedLiteralCount = 0;
  for (const move of moves) {
    updates.push(move.to, move.value);
    appliedCount += 1;
    updates.push(new FieldPath(move.from), FieldValue.delete());
    deletedLiteralCount += 1;
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
