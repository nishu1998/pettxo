#!/usr/bin/env node
"use strict";

/**
 * Copies exact service location/private notes into servicePrivate and removes
 * them from the marketplace document. Dry-run is the default. This script is
 * intentionally separate from deployment and must be invoked explicitly.
 */
const fs = require("node:fs");
const {applicationDefault, initializeApp} = require("firebase-admin/app");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");

const EXPECTED_PROJECT_ID = "pettexo-d9409";

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
    throw new Error(
      `--apply requires --confirm-apply ${EXPECTED_PROJECT_ID}`,
    );
  }
}

function roundCoordinate(value) {
  return Math.round(Number(value) * 100) / 100;
}

// Precision five is intentionally coarse (roughly neighbourhood scale) and
// matches the Flutter writer. It is enough for discovery candidate filtering.
const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";
function encodeGeohash(latitude, longitude, precision = 5) {
  let lat = [-90, 90];
  let lng = [-180, 180];
  let even = true;
  let bits = 0;
  let value = 0;
  let hash = "";
  while (hash.length < precision) {
    const range = even ? lng : lat;
    const coordinate = even ? longitude : latitude;
    const midpoint = (range[0] + range[1]) / 2;
    if (coordinate >= midpoint) {
      value = value * 2 + 1;
      range[0] = midpoint;
    } else {
      value *= 2;
      range[1] = midpoint;
    }
    even = !even;
    bits += 1;
    if (bits === 5) {
      hash += BASE32[value];
      bits = 0;
      value = 0;
    }
  }
  return hash;
}

function privateCopyIsComplete(serviceId, publicData, privateData) {
  const location = privateData?.location;
  return privateData?.serviceId === serviceId &&
    privateData?.ownerUserId === String(publicData.ownerUserId || "").trim() &&
    typeof privateData?.privateNotes === "string" &&
    typeof location?.displayAddress === "string" &&
    location.displayAddress.trim().length > 0 &&
    typeof location?.latitude === "number" && Number.isFinite(location.latitude) &&
    location.latitude >= -90 && location.latitude <= 90 &&
    typeof location?.longitude === "number" && Number.isFinite(location.longitude) &&
    location.longitude >= -180 && location.longitude <= 180;
}

function buildMigration(serviceId, data) {
  const location = data.location || {};
  const latitude = location.latitude;
  const longitude = location.longitude;
  const alreadyPublic = typeof location.approximateLatitude === "number" &&
    Number.isFinite(location.approximateLatitude) &&
    location.approximateLatitude >= -90 && location.approximateLatitude <= 90 &&
    typeof location.approximateLongitude === "number" &&
    Number.isFinite(location.approximateLongitude) &&
    location.approximateLongitude >= -180 && location.approximateLongitude <= 180 &&
    typeof location.geohash === "string" && location.geohash.length > 0 &&
    !Object.hasOwn(location, "latitude") &&
    !Object.hasOwn(location, "longitude") && !Object.hasOwn(data, "privateNotes");
  if (alreadyPublic) return null;
  if (typeof latitude !== "number" || !Number.isFinite(latitude) ||
      latitude < -90 || latitude > 90 ||
      typeof longitude !== "number" || !Number.isFinite(longitude) ||
      longitude < -180 || longitude > 180) {
    return {error: "missing-or-invalid-exact-coordinates"};
  }
  const city = String(location.city || "").trim();
  const state = String(location.state || "").trim();
  const ownerUserId = String(data.ownerUserId || "").trim();
  const privateNotes = String(data.privateNotes || "");
  if (!city || !state) return {error: "missing-city-or-state"};
  if (!ownerUserId) return {error: "missing-owner-user-id"};
  if (privateNotes.length > 300) return {error: "private-notes-exceed-300-characters"};
  const approximateLatitude = roundCoordinate(latitude);
  const approximateLongitude = roundCoordinate(longitude);
  return {
    privateData: {
      serviceId,
      ownerUserId,
      privateNotes,
      location: {
        displayAddress: String(location.displayAddress || `${city}, ${state}`),
        latitude,
        longitude,
      },
    },
    publicLocation: {
      approximateLatitude,
      approximateLongitude,
      geohash: encodeGeohash(approximateLatitude, approximateLongitude),
      city,
      state,
      country: String(location.country || "IN").trim().length === 2 ?
        String(location.country || "IN").trim().toUpperCase() :
        "IN",
    },
  };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.projectId) {
    console.log(`Usage: node scripts/migrate_service_private_data.js --project ${EXPECTED_PROJECT_ID} [--page-size 100] [--checkpoint FILE] [--apply --confirm-apply ${EXPECTED_PROJECT_ID}]`);
    console.log("Default mode is read-only dry-run. Apply mode requires both --apply and the exact --confirm-apply project ID.");
    process.exitCode = options.help ? 0 : 2;
    return;
  }
  validateSafetyOptions(options);
  initializeApp({credential: applicationDefault(), projectId: options.projectId});
  const db = getFirestore();
  let lastId = "";
  let totals = {scanned: 0, candidates: 0, migrated: 0, skipped: 0, invalid: 0};
  if (options.apply && options.checkpoint && fs.existsSync(options.checkpoint)) {
    const checkpoint = JSON.parse(fs.readFileSync(options.checkpoint, "utf8"));
    if (checkpoint.projectId !== EXPECTED_PROJECT_ID) {
      throw new Error("Checkpoint is missing the expected project binding.");
    }
    lastId = typeof checkpoint.lastId === "string" ? checkpoint.lastId : "";
    if (checkpoint.totals && typeof checkpoint.totals === "object") {
      totals = {...totals, ...checkpoint.totals};
    }
  }
  const saveCheckpoint = () => {
    if (options.apply && options.checkpoint) {
      fs.writeFileSync(options.checkpoint, JSON.stringify({
        version: 1,
        projectId: EXPECTED_PROJECT_ID,
        lastId,
        totals,
      }, null, 2));
    }
  };
  while (true) {
    let query = db.collection("services").orderBy("__name__").limit(options.pageSize);
    if (lastId) query = query.startAfter(lastId);
    const page = await query.get();
    if (page.empty) break;
    for (const document of page.docs) {
      totals.scanned += 1;
      const migration = buildMigration(document.id, document.data());
      if (!migration) {
        const privateSnapshot = await db.collection("servicePrivate").doc(document.id).get();
        if (!privateSnapshot.exists ||
            !privateCopyIsComplete(document.id, document.data(), privateSnapshot.data())) {
          totals.invalid += 1;
          console.error(JSON.stringify({
            serviceId: document.id,
            error: "sanitized-service-is-missing-complete-private-copy",
          }));
        } else {
          totals.skipped += 1;
        }
        lastId = document.id;
        saveCheckpoint();
        continue;
      }
      if (migration.error) {
        totals.invalid += 1;
        console.error(JSON.stringify({serviceId: document.id, error: migration.error}));
        lastId = document.id;
        saveCheckpoint();
        continue;
      }
      totals.candidates += 1;
      console.log(JSON.stringify({mode: options.apply ? "apply" : "dry-run", serviceId: document.id}));
      if (options.apply) {
        const privateRef = db.collection("servicePrivate").doc(document.id);
        const existingPrivate = await privateRef.get();
        const privateWrite = {
          ...migration.privateData,
          updatedAt: FieldValue.serverTimestamp(),
        };
        if (!existingPrivate.exists) privateWrite.createdAt = FieldValue.serverTimestamp();
        await privateRef.set(privateWrite, {merge: true});
        const verified = await privateRef.get();
        const privateData = verified.data() || {};
        if (!verified.exists || privateData.ownerUserId !== migration.privateData.ownerUserId ||
            privateData.serviceId !== migration.privateData.serviceId ||
            privateData.privateNotes !== migration.privateData.privateNotes ||
            privateData.location?.displayAddress !== migration.privateData.location.displayAddress ||
            Number(privateData.location?.latitude) !== migration.privateData.location.latitude ||
            Number(privateData.location?.longitude) !== migration.privateData.location.longitude) {
          throw new Error(`Private copy verification failed for service ${document.id}`);
        }
        await document.ref.update({
          location: migration.publicLocation,
          privateNotes: FieldValue.delete(),
        }, {lastUpdateTime: document.updateTime});
        const sanitized = (await document.ref.get()).data() || {};
        const sanitizedLocation = sanitized.location || {};
        if (Object.hasOwn(sanitized, "privateNotes") ||
            Object.hasOwn(sanitizedLocation, "displayAddress") ||
            Object.hasOwn(sanitizedLocation, "latitude") ||
            Object.hasOwn(sanitizedLocation, "longitude")) {
          throw new Error(`Public sanitization verification failed for service ${document.id}`);
        }
        totals.migrated += 1;
      }
      lastId = document.id;
      saveCheckpoint();
    }
    if (page.size < options.pageSize) break;
  }
  console.log(JSON.stringify({mode: options.apply ? "apply" : "dry-run", totals}, null, 2));
  if (totals.invalid > 0) process.exitCode = 1;
}

module.exports = {
  EXPECTED_PROJECT_ID,
  buildMigration,
  encodeGeohash,
  parseArgs,
  privateCopyIsComplete,
  roundCoordinate,
  validateSafetyOptions,
};
if (require.main === module) main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
