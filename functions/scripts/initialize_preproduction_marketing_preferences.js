#!/usr/bin/env node
"use strict";

/**
 * One-time initialization for Pettxo's pre-production test accounts.
 * Dry-run is the default. Apply requires explicit production-project confirmation.
 */
const fs = require("node:fs");
const {applicationDefault, initializeApp} = require("firebase-admin/app");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");

const EXPECTED_PROJECT_ID = "pettexo-d9409";
const MIGRATION_SOURCE = "preproduction_test_migration";

function parseArgs(argv) {
  const options = {
    apply: false,
    pageSize: 100,
    projectId: "",
    checkpoint: "",
    applyConfirmation: "",
  };
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--apply") options.apply = true;
    else if (value === "--project") options.projectId = argv[++index] || "";
    else if (value === "--confirm-apply") options.applyConfirmation = argv[++index] || "";
    else if (value === "--page-size") options.pageSize = Number(argv[++index]);
    else if (value === "--checkpoint") options.checkpoint = argv[++index] || "";
    else if (value === "--help") options.help = true;
    else throw new Error(`Unknown argument: ${value}`);
  }
  if (!Number.isInteger(options.pageSize) || options.pageSize < 1 || options.pageSize > 400) {
    throw new Error("--page-size must be an integer from 1 to 400");
  }
  return options;
}

function validateSafetyOptions(options) {
  if (options.projectId !== EXPECTED_PROJECT_ID) {
    throw new Error(`--project must be exactly ${EXPECTED_PROJECT_ID}`);
  }
  if (options.apply && options.applyConfirmation !== EXPECTED_PROJECT_ID) {
    throw new Error(`--apply requires --confirm-apply ${EXPECTED_PROJECT_ID}`);
  }
}

function classifyPreference(uid, privateExists, privateData) {
  if (privateExists && privateData.uid != null &&
      String(privateData.uid).trim() !== "" &&
      String(privateData.uid).trim() !== uid) {
    return {kind: "error", reason: "private-profile-uid-mismatch"};
  }
  if (privateData.marketingEmailEnabled === true) return {kind: "alreadyEnabled"};
  if (privateData.marketingEmailEnabled === false) {
    return {kind: "error", reason: "explicit-disabled-preference-requires-review"};
  }
  return {kind: "candidate"};
}

function migrationPatch(uid, timestamp) {
  return {
    uid,
    marketingEmailEnabled: true,
    marketingEmailPreferenceSource: MIGRATION_SOURCE,
    marketingEmailPreferenceUpdatedAt: timestamp,
    updatedAt: timestamp,
  };
}

async function executeInitialization({apply, privateSnapshot, uid, timestamp}) {
  if (!apply) return false;
  const patch = migrationPatch(uid, timestamp);
  if (privateSnapshot.exists) {
    await privateSnapshot.ref.update(patch, {lastUpdateTime: privateSnapshot.updateTime});
  } else {
    await privateSnapshot.ref.create({...patch, createdAt: timestamp});
  }
  const verified = await privateSnapshot.ref.get();
  const data = verified.data() || {};
  if (!verified.exists || data.uid !== uid ||
      data.marketingEmailEnabled !== true ||
      data.marketingEmailPreferenceSource !== MIGRATION_SOURCE) {
    throw new Error(`Preference verification failed for UID ${uid}`);
  }
  return true;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.projectId) {
    console.log(`Usage: node scripts/initialize_preproduction_marketing_preferences.js --project ${EXPECTED_PROJECT_ID} [--page-size 100] [--checkpoint FILE] [--apply --confirm-apply ${EXPECTED_PROJECT_ID}]`);
    console.log("Default mode is read-only dry-run. Apply mode requires both --apply and the exact --confirm-apply project ID.");
    process.exitCode = options.help ? 0 : 2;
    return;
  }
  validateSafetyOptions(options);
  initializeApp({credential: applicationDefault(), projectId: options.projectId});
  const db = getFirestore();
  let lastId = "";
  let totals = {
    scanned: 0,
    candidates: 0,
    wouldChange: 0,
    changed: 0,
    alreadyEnabled: 0,
    skipped: 0,
    errors: 0,
  };
  if (options.apply && options.checkpoint && fs.existsSync(options.checkpoint)) {
    const checkpoint = JSON.parse(fs.readFileSync(options.checkpoint, "utf8"));
    if (checkpoint.projectId !== EXPECTED_PROJECT_ID || checkpoint.version !== 1) {
      throw new Error("Checkpoint is missing the expected project binding or version.");
    }
    lastId = typeof checkpoint.lastId === "string" ? checkpoint.lastId : "";
    totals = {...totals, ...(checkpoint.totals || {})};
  }
  const saveCheckpoint = () => {
    if (!options.apply || !options.checkpoint) return;
    fs.writeFileSync(options.checkpoint, JSON.stringify({
      version: 1,
      projectId: EXPECTED_PROJECT_ID,
      lastId,
      totals,
    }, null, 2));
  };

  while (true) {
    let query = db.collection("users").orderBy("__name__").limit(options.pageSize);
    if (lastId) query = query.startAfter(lastId);
    const page = await query.get();
    if (page.empty) break;
    for (const user of page.docs) {
      totals.scanned += 1;
      const privateRef = db.collection("userPrivate").doc(user.id);
      const privateSnapshot = await privateRef.get();
      const privateData = privateSnapshot.data() || {};
      const classification = classifyPreference(user.id, privateSnapshot.exists, privateData);
      if (classification.kind === "alreadyEnabled") {
        totals.alreadyEnabled += 1;
      } else if (classification.kind === "error") {
        totals.errors += 1;
        console.error(JSON.stringify({uid: user.id, error: classification.reason}));
      } else {
        totals.candidates += 1;
        if (options.apply) {
          try {
            if (await executeInitialization({
              apply: true,
              privateSnapshot,
              uid: user.id,
              timestamp: FieldValue.serverTimestamp(),
            })) totals.changed += 1;
          } catch (error) {
            totals.errors += 1;
            console.error(JSON.stringify({
              uid: user.id,
              error: "conditional-write-or-verification-failed",
              code: typeof error?.code === "string" ? error.code : "unknown",
            }));
          }
        } else {
          totals.wouldChange += 1;
        }
      }
      lastId = user.id;
      saveCheckpoint();
    }
    if (page.size < options.pageSize) break;
  }
  console.log(JSON.stringify({mode: options.apply ? "apply" : "dry-run", totals}, null, 2));
  if (totals.errors > 0) process.exitCode = 1;
}

module.exports = {
  EXPECTED_PROJECT_ID,
  MIGRATION_SOURCE,
  classifyPreference,
  executeInitialization,
  migrationPatch,
  parseArgs,
  validateSafetyOptions,
};

if (require.main === module) main().catch((error) => {
  console.error(error.message || error);
  process.exitCode = 1;
});
