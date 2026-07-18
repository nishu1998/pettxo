#!/usr/bin/env node
/**
 * WARNING: Destructive admin utility for Pettxo pre-launch test-data reset only.
 *
 * This script can permanently delete:
 * - Firebase Authentication users
 * - Firestore application documents and nested subcollections
 * - Firebase Storage user-generated objects
 *
 * Safety rails:
 * - Refuses to operate on any Firebase project except pettexo-d9409
 * - Requires --confirm=RESET_PETTXO_TEST_DATA for destructive mode
 * - Supports --dry-run inventory mode
 * - Stops before destructive work if payment/live-risk signals are detected
 *
 * Do not add this script to app startup, CI/CD, or normal deployment flows.
 */

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {spawnSync} = require("node:child_process");

const EXPECTED_PROJECT_ID = "pettexo-d9409";
const REQUIRED_CONFIRMATION = "RESET_PETTXO_TEST_DATA";
const ADMIN_ROLES = new Set([
  "admin",
  "superAdmin",
  "customerSupportAdmin",
  "financeAdmin",
]);
const DEFAULT_COLLECTIONS = [
  "adminAuditLogs",
  "bookingFinancials",
  "bookings",
  "chats",
  "disputes",
  "follows",
  "hashtags",
  "invoices",
  "moderationQueue",
  "notifications",
  "offerCampaigns",
  "offers",
  "paymentWebhookEvents",
  "payments",
  "payoutReadiness",
  "payouts",
  "providerEarnings",
  "refunds",
  "reports",
  "services",
  "socialPosts",
  "userPrivate",
  "users",
  "usernames",
  "waitlist",
];
const USER_GENERATED_STORAGE_PREFIXES = [
  "users/",
  "socialPosts/",
  "providerVerification/",
  "disputes/",
];
const MAX_SAMPLE_PATHS = 12;
const MAX_SUBCOLLECTION_PARENT_DOCS_TO_SAMPLE = 25;
const MAX_ROOT_SAMPLE_DOCUMENTS = 25;
const AUTH_DELETE_BATCH_LIMIT = 1000;
const FIRESTORE_ROOT_DELETE_CONCURRENCY = 4;
const STORAGE_PREFIX_DELETE_CONCURRENCY = 3;
const FIRESTORE_DOCUMENT_DELETE_CONCURRENCY = 12;

function parseArgs(argv) {
  return {
    dryRun: argv.includes("--dry-run"),
    cleanupOrphans:
      argv.find((arg) => arg.startsWith("--cleanup-orphans="))?.slice(18) || "",
    confirmation:
      argv.find((arg) => arg.startsWith("--confirm="))?.slice(10) || "",
  };
}

function safeJsonParse(value, fallback) {
  try {
    return JSON.parse(value);
  } catch (_) {
    return fallback;
  }
}

function extractJsonValues(text) {
  const values = [];
  let depth = 0;
  let start = -1;
  let inString = false;
  let escaped = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char === "\\") {
        escaped = true;
      } else if (char === "\"") {
        inString = false;
      }
      continue;
    }
    if (char === "\"") {
      inString = true;
      continue;
    }
    if (char === "{" || char === "[") {
      if (depth === 0) {
        start = index;
      }
      depth += 1;
      continue;
    }
    if (char === "}" || char === "]") {
      if (depth === 0) continue;
      depth -= 1;
      if (depth === 0 && start >= 0) {
        const parsed = safeJsonParse(text.slice(start, index + 1), undefined);
        if (parsed !== undefined) {
          values.push(parsed);
        }
        start = -1;
      }
    }
  }

  return values;
}

function spawnFirebaseCli(args) {
  return spawnSync("firebase", args, {
    cwd: path.resolve(__dirname, "..", ".."),
    encoding: "utf8",
    env: {
      ...process.env,
      CI: "1",
      FIREBASE_SKIP_UPDATE_CHECK: "1",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
}

function runFirebaseCliJson(args) {
  const result = spawnFirebaseCli(args);
  const stdout = (result.stdout || "").trim();
  const stderr = (result.stderr || "").trim();
  const parsedValues = extractJsonValues(stdout);
  const successful =
    parsedValues.find((value) => value?.status === "success") ||
    parsedValues.find((value) => Array.isArray(value)) ||
    parsedValues[0] ||
    null;

  if (successful) {
    return successful;
  }

  throw new Error(
    [stdout, stderr].filter(Boolean).join("\n") ||
      `firebase ${args.join(" ")} failed with status ${result.status}`,
  );
}

function runFirebaseCliCommand(args) {
  const result = spawnFirebaseCli(args);
  const stdout = (result.stdout || "").trim();
  const stderr = (result.stderr || "").trim();
  if (result.status !== 0 && !stdout) {
    throw new Error(
      [stdout, stderr].filter(Boolean).join("\n") ||
        `firebase ${args.join(" ")} failed with status ${result.status}`,
    );
  }
  return {stdout, stderr, status: result.status};
}

function getCliContext() {
  const activeProjectJson = runFirebaseCliJson(["use", "--json"]);
  const activeProjectId =
    activeProjectJson?.result ||
    activeProjectJson?.project ||
    activeProjectJson?.activeProject ||
    "";

  const loginJson = runFirebaseCliJson(["login:list", "--json"]);
  const accounts = Array.isArray(loginJson?.result)
    ? loginJson.result
    : Array.isArray(loginJson)
    ? loginJson
    : [];
  const activeEntry =
    accounts.find((entry) => entry.status === "ACTIVE") || accounts[0] || null;

  let storageBuckets = [];
  try {
    const bucketsJson = runFirebaseCliJson([
      "storage:buckets:list",
      "--project",
      activeProjectId || EXPECTED_PROJECT_ID,
      "--json",
    ]);
    const rawBuckets = Array.isArray(bucketsJson?.result)
      ? bucketsJson.result
      : Array.isArray(bucketsJson)
      ? bucketsJson
      : [];
    storageBuckets = rawBuckets
      .map((bucket) => String(bucket.name || bucket.bucket || "").trim())
      .filter(Boolean);
  } catch (_) {
    storageBuckets = [];
  }

  return {
    activeProjectId,
    currentAccountEmail: activeEntry?.user?.email || "",
    currentAccessToken: String(activeEntry?.tokens?.access_token || "").trim(),
    currentAccessTokenExpiresAt: Number(
      activeEntry?.tokens?.expires_at || 0,
    ),
    storageBuckets,
  };
}

function ensureAccessToken(cli) {
  if (!cli.currentAccessToken) {
    throw new Error(
      "No Firebase CLI access token found. Run `firebase login` and try again.",
    );
  }
}

function refreshCliAccessToken(cli) {
  const loginJson = runFirebaseCliJson(["login:list", "--json"]);
  const accounts = Array.isArray(loginJson?.result)
    ? loginJson.result
    : Array.isArray(loginJson)
    ? loginJson
    : [];
  const activeEntry =
    accounts.find((entry) => entry.status === "ACTIVE") || accounts[0] || null;

  cli.currentAccountEmail = activeEntry?.user?.email || cli.currentAccountEmail;
  cli.currentAccessToken = String(
    activeEntry?.tokens?.access_token || "",
  ).trim();
  cli.currentAccessTokenExpiresAt = Number(
    activeEntry?.tokens?.expires_at || 0,
  );
  ensureAccessToken(cli);
}

async function googleJsonRequest(cli, url, options = {}) {
  for (let attempt = 0; attempt < 2; attempt += 1) {
    ensureAccessToken(cli);
    const headers = {
      Authorization: `Bearer ${cli.currentAccessToken}`,
      ...(options.body ? {"Content-Type": "application/json"} : {}),
      ...(options.headers || {}),
    };
    const response = await fetch(url, {
      method: options.method || "GET",
      headers,
      body: options.body ? JSON.stringify(options.body) : undefined,
    });

    const text = await response.text();
    const json = text ? safeJsonParse(text, null) : null;

    if (response.ok) {
      return json;
    }

    if (response.status === 401 && attempt === 0) {
      refreshCliAccessToken(cli);
      continue;
    }

    const message =
      json?.error?.message ||
      json?.error_description ||
      text ||
      `${response.status} ${response.statusText}`;
    throw new Error(
      `${options.method || "GET"} ${url} failed: ${message}`,
    );
  }
  return null;
}

function firestoreBaseUrl(projectId) {
  return `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
}

function encodeFirestorePath(collectionOrDocPath) {
  return collectionOrDocPath
    .split("/")
    .map((segment) => encodeURIComponent(segment))
    .join("/");
}

async function listCollectionIds(cli, projectId, parentDocPath = "") {
  const endpoint = parentDocPath
    ? `${firestoreBaseUrl(projectId)}/${encodeFirestorePath(parentDocPath)}:listCollectionIds`
    : `${firestoreBaseUrl(projectId)}:listCollectionIds`;
  const collectionIds = [];
  let pageToken = "";

  do {
    const json = await googleJsonRequest(cli, endpoint, {
      method: "POST",
      body: pageToken ? {pageSize: 1000, pageToken} : {pageSize: 1000},
    });
    collectionIds.push(...(json?.collectionIds || []));
    pageToken = String(json?.nextPageToken || "");
  } while (pageToken);

  return collectionIds;
}

async function listDocumentsInCollection(
  cli,
  projectId,
  collectionPath,
  options = {},
) {
  const {pageSize = 1000, maxDocuments = Number.POSITIVE_INFINITY} = options;
  const documents = [];
  let pageToken = "";
  do {
    const url = new URL(
      `${firestoreBaseUrl(projectId)}/${encodeFirestorePath(collectionPath)}`,
    );
    url.searchParams.set("pageSize", String(pageSize));
    if (pageToken) {
      url.searchParams.set("pageToken", pageToken);
    }
    const json = await googleJsonRequest(cli, url.toString());
    documents.push(...(json?.documents || []));
    if (documents.length >= maxDocuments) {
      return documents.slice(0, maxDocuments);
    }
    pageToken = String(json?.nextPageToken || "");
  } while (pageToken);
  return documents;
}

async function countDocumentsInCollection(cli, projectId, collectionPath) {
  const url = `${firestoreBaseUrl(projectId)}:runAggregationQuery`;
  const json = await googleJsonRequest(cli, url, {
    method: "POST",
    body: {
      structuredAggregationQuery: {
        aggregations: [{alias: "documentCount", count: {}}],
        structuredQuery: {
          from: [{collectionId: collectionPath}],
        },
      },
    },
  });
  const results = Array.isArray(json) ? json : [];
  const countValue = results.find(
    (entry) => entry?.result?.aggregateFields?.documentCount,
  )?.result?.aggregateFields?.documentCount;
  return Number(
    countValue?.integerValue ??
      countValue?.doubleValue ??
      countValue ??
      0,
  );
}

async function countCollectionGroupDocuments(cli, projectId, collectionId) {
  const url = `${firestoreBaseUrl(projectId)}:runAggregationQuery`;
  const json = await googleJsonRequest(cli, url, {
    method: "POST",
    body: {
      structuredAggregationQuery: {
        aggregations: [{alias: "documentCount", count: {}}],
        structuredQuery: {
          from: [{collectionId, allDescendants: true}],
        },
      },
    },
  });
  const results = Array.isArray(json) ? json : [];
  const countValue = results.find(
    (entry) => entry?.result?.aggregateFields?.documentCount,
  )?.result?.aggregateFields?.documentCount;
  return Number(
    countValue?.integerValue ??
      countValue?.doubleValue ??
      countValue ??
      0,
  );
}

async function listCollectionGroupDocuments(cli, projectId, collectionId) {
  const url = `${firestoreBaseUrl(projectId)}:runQuery`;
  const json = await googleJsonRequest(cli, url, {
    method: "POST",
    body: {
      structuredQuery: {
        from: [{collectionId, allDescendants: true}],
        orderBy: [
          {
            field: {fieldPath: "__name__"},
            direction: "ASCENDING",
          },
        ],
      },
    },
  });
  const results = Array.isArray(json) ? json : [];
  return results
    .map((entry) => entry?.document)
    .filter(Boolean);
}

function decodeFirestoreValue(value) {
  if (value == null || typeof value !== "object") return value;
  if ("nullValue" in value) return null;
  if ("booleanValue" in value) return Boolean(value.booleanValue);
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return Number(value.doubleValue);
  if ("timestampValue" in value) return String(value.timestampValue);
  if ("stringValue" in value) return String(value.stringValue);
  if ("bytesValue" in value) return String(value.bytesValue);
  if ("referenceValue" in value) return String(value.referenceValue);
  if ("geoPointValue" in value) return value.geoPointValue;
  if ("arrayValue" in value) {
    return (value.arrayValue.values || []).map(decodeFirestoreValue);
  }
  if ("mapValue" in value) {
    const output = {};
    const fields = value.mapValue.fields || {};
    for (const [key, nestedValue] of Object.entries(fields)) {
      output[key] = decodeFirestoreValue(nestedValue);
    }
    return output;
  }
  return value;
}

function decodeFirestoreDocument(document) {
  const fields = document?.fields || {};
  const decoded = {};
  for (const [key, value] of Object.entries(fields)) {
    decoded[key] = decodeFirestoreValue(value);
  }
  return decoded;
}

function documentNameToPath(documentName) {
  const marker = "/documents/";
  const index = documentName.indexOf(marker);
  return index >= 0 ? documentName.slice(index + marker.length) : documentName;
}

function buildState() {
  return {
    totalFirestoreDocuments: 0,
    rootCollectionStats: {},
    nestedCollectionPaths: new Set(),
    adminAccounts: {
      firestoreAdmins: [],
      authAdmins: [],
    },
    paymentSignals: {
      testLike: [],
      liveRisk: [],
      unknown: [],
    },
  };
}

function analyzeAdminUserDoc(uid, data, state) {
  const adminRole = String(data.adminRole || "").trim();
  if (ADMIN_ROLES.has(adminRole)) {
    state.adminAccounts.firestoreAdmins.push({
      uid,
      role: adminRole,
      path: `users/${uid}`,
    });
  }
}

function analyzePaymentDoc(collectionId, docId, data, state) {
  if (
    !["payments", "refunds", "invoices", "bookingFinancials", "payouts"].includes(
      collectionId,
    )
  ) {
    return;
  }

  const normalized = JSON.stringify(data).toLowerCase();
  const hasTestHint =
    normalized.includes("test") ||
    normalized.includes("sandbox") ||
    normalized.includes("dummy");
  const hasLiveHint =
    normalized.includes("live") ||
    normalized.includes("captured") ||
    normalized.includes("settled") ||
    normalized.includes("payout");

  const record = {
    collection: collectionId,
    id: docId,
    status: String(data.status || data.paymentStatus || "").trim(),
    mode: String(data.mode || data.environment || "").trim(),
    razorpayOrderIdPresent: Boolean(
      data.razorpayOrderId || data.razorpay_order_id,
    ),
    razorpayPaymentIdPresent: Boolean(
      data.razorpayPaymentId || data.razorpay_payment_id,
    ),
  };

  if (hasTestHint) {
    state.paymentSignals.testLike.push(record);
  } else if (
    hasLiveHint ||
    record.razorpayOrderIdPresent ||
    record.razorpayPaymentIdPresent
  ) {
    state.paymentSignals.liveRisk.push(record);
  } else {
    state.paymentSignals.unknown.push(record);
  }
}

async function scanCollectionPath(
  cli,
  projectId,
  collectionPath,
  rootCollectionId,
  state,
  options = {},
) {
  const {recurse = true} = options;
  const documents = await listDocumentsInCollection(cli, projectId, collectionPath);
  const rootStat = state.rootCollectionStats[rootCollectionId];
  rootStat.directDocumentCount += collectionPath === rootCollectionId
    ? documents.length
    : 0;

  for (const document of documents) {
    const docPath = documentNameToPath(document.name);
    const docId = docPath.split("/").pop() || "";
    const data = decodeFirestoreDocument(document);

    state.totalFirestoreDocuments += 1;
    rootStat.totalDocumentsUnderRoot += 1;
    if (rootStat.sampleDocumentPaths.length < MAX_SAMPLE_PATHS) {
      rootStat.sampleDocumentPaths.push(docPath);
    }

    if (rootCollectionId === "users") {
      analyzeAdminUserDoc(docId, data, state);
    }
    analyzePaymentDoc(rootCollectionId, docId, data, state);

    const shouldInspectNestedCollections =
      recurse ||
      (collectionPath === rootCollectionId &&
        rootStat.sampledParentDocumentsForNestedScan <
          MAX_SUBCOLLECTION_PARENT_DOCS_TO_SAMPLE);

    if (shouldInspectNestedCollections) {
      const subcollectionIds = await listCollectionIds(cli, projectId, docPath);
      rootStat.nestedCollectionCount += subcollectionIds.length;
      if (collectionPath === rootCollectionId && !recurse) {
        rootStat.sampledParentDocumentsForNestedScan += 1;
      }
      for (const subcollectionId of subcollectionIds) {
        const subcollectionPath = `${docPath}/${subcollectionId}`;
        state.nestedCollectionPaths.add(subcollectionPath);
        if (!recurse) {
          continue;
        }
        await scanCollectionPath(
          cli,
          projectId,
          subcollectionPath,
          rootCollectionId,
          state,
          options,
        );
      }
    }
  }
}

async function inspectRootCollectionForDryRun(
  cli,
  projectId,
  collectionId,
  state,
) {
  const rootStat = state.rootCollectionStats[collectionId];
  rootStat.directDocumentCount = await countDocumentsInCollection(
    cli,
    projectId,
    collectionId,
  );
  rootStat.totalDocumentsUnderRoot = rootStat.directDocumentCount;

  const sampledDocuments = await listDocumentsInCollection(
    cli,
    projectId,
    collectionId,
    {
      pageSize: MAX_ROOT_SAMPLE_DOCUMENTS,
      maxDocuments: MAX_ROOT_SAMPLE_DOCUMENTS,
    },
  );

  for (const document of sampledDocuments) {
    const docPath = documentNameToPath(document.name);
    const docId = docPath.split("/").pop() || "";
    const data = decodeFirestoreDocument(document);

    if (rootStat.sampleDocumentPaths.length < MAX_SAMPLE_PATHS) {
      rootStat.sampleDocumentPaths.push(docPath);
    }

    if (collectionId === "users") {
      analyzeAdminUserDoc(docId, data, state);
    }
    analyzePaymentDoc(collectionId, docId, data, state);

    if (
      rootStat.sampledParentDocumentsForNestedScan >=
      MAX_SUBCOLLECTION_PARENT_DOCS_TO_SAMPLE
    ) {
      continue;
    }

    const subcollectionIds = await listCollectionIds(cli, projectId, docPath);
    rootStat.nestedCollectionCount += subcollectionIds.length;
    rootStat.sampledParentDocumentsForNestedScan += 1;
    for (const subcollectionId of subcollectionIds) {
      state.nestedCollectionPaths.add(`${docPath}/${subcollectionId}`);
    }
  }
}

async function getRootCollections(cli, projectId) {
  const collections = await listCollectionIds(cli, projectId, "");
  return collections.sort((a, b) => a.localeCompare(b));
}

async function exportAuthUsers(cli, projectId) {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "pettxo-auth-export-"));
  const tempFile = path.join(tempDir, "auth-users.json");
  try {
    runFirebaseCliCommand([
      "auth:export",
      tempFile,
      "--format=json",
      "--project",
      projectId,
    ]);
    const json = safeJsonParse(fs.readFileSync(tempFile, "utf8"), []);
    return Array.isArray(json) ? json : [];
  } finally {
    try {
      fs.rmSync(tempDir, {recursive: true, force: true});
    } catch (_) {
      // Best-effort cleanup only.
    }
  }
}

function parseCustomClaims(rawClaims) {
  if (!rawClaims) return {};
  if (typeof rawClaims === "object") return rawClaims;
  if (typeof rawClaims === "string") {
    const parsed = safeJsonParse(rawClaims, {});
    return parsed && typeof parsed === "object" ? parsed : {};
  }
  return {};
}

function summarizeAdminAccessImpact(authUsers, state) {
  state.adminAccounts.authAdmins = authUsers
    .map((user) => ({
      uid: String(user.localId || user.uid || "").trim(),
      email: String(user.email || "").trim(),
      customClaims: parseCustomClaims(user.customClaims),
    }))
    .filter((entry) => entry.uid && entry.customClaims.admin === true);

  const combined = new Set([
    ...state.adminAccounts.authAdmins.map((entry) => entry.uid),
    ...state.adminAccounts.firestoreAdmins.map((entry) => entry.uid),
  ]);

  return {
    totalAdminLikeAccounts: combined.size,
    authAdmins: state.adminAccounts.authAdmins,
    firestoreAdmins: state.adminAccounts.firestoreAdmins,
    deletingAllAuthUsersRemovesAdminDashboardAccess: combined.size > 0,
    recreateFirstSuperAdminProcess:
      "After reset, create the bootstrap admin directly with a trusted server-side script, then assign custom claim {admin:true} and write /users/{uid}.adminRole='superAdmin'. Do not expose admin role assignment in any client-accessible flow.",
  };
}

async function listStorageObjects(cli, bucketName, prefix = "") {
  const files = [];
  let pageToken = "";
  do {
    const url = new URL(
      `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(bucketName)}/o`,
    );
    url.searchParams.set("maxResults", "1000");
    if (prefix) {
      url.searchParams.set("prefix", prefix);
    }
    if (pageToken) {
      url.searchParams.set("pageToken", pageToken);
    }
    const json = await googleJsonRequest(cli, url.toString());
    files.push(...(json?.items || []));
    pageToken = String(json?.nextPageToken || "");
  } while (pageToken);
  return files;
}

async function listStorageTopLevelPrefixes(cli, bucketName) {
  const url = new URL(
    `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(bucketName)}/o`,
  );
  url.searchParams.set("delimiter", "/");
  url.searchParams.set("includeTrailingDelimiter", "true");
  url.searchParams.set("maxResults", "1000");
  const json = await googleJsonRequest(cli, url.toString());
  return (json?.prefixes || []).map((prefix) => ({
    prefix: String(prefix).replace(/\/$/, ""),
    objectCount: null,
    samplePaths: [String(prefix)],
  }));
}

async function inventoryStorage(cli, bucketNames) {
  const bucketName =
    bucketNames.find((name) => name === `${EXPECTED_PROJECT_ID}.firebasestorage.app`) ||
    `${EXPECTED_PROJECT_ID}.firebasestorage.app`;
  const topLevelPrefixes = await listStorageTopLevelPrefixes(cli, bucketName);

  return {
    bucketName,
    bucketNames: Array.from(new Set([bucketName, ...bucketNames])).sort(),
    objectCount: null,
    topLevelPrefixes: topLevelPrefixes.sort((a, b) =>
      a.prefix.localeCompare(b.prefix),
    ),
  };
}

function buildResetPlan(rootCollections, storageInventory) {
  const collectionsToDelete = Array.from(
    new Set([...DEFAULT_COLLECTIONS, ...rootCollections]),
  ).sort((a, b) => a.localeCompare(b));

  const storagePrefixes = new Set(USER_GENERATED_STORAGE_PREFIXES);
  for (const entry of storageInventory.topLevelPrefixes) {
    if (entry.prefix === "(root)") continue;
    storagePrefixes.add(`${entry.prefix}/`);
  }

  return {
    collectionsToDelete,
    storagePrefixesToDelete: Array.from(storagePrefixes).sort((a, b) =>
      a.localeCompare(b),
    ),
  };
}

function createDeletionCounters() {
  return {
    firestoreDeletedDocuments: 0,
    firestoreDeletedByRootCollection: {},
    orphanCleanupFoundDocuments: 0,
    orphanCleanupDeletedDocuments: 0,
    orphanCleanupFailedDocuments: 0,
    orphanCleanupDocumentPaths: [],
    storageDeletedObjects: 0,
    storageDeletedByPrefix: {},
    authDeletedUsers: 0,
  };
}

function parseCleanupTargets(rawValue) {
  if (!rawValue) return [];
  return rawValue
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
}

async function runWithConcurrency(items, concurrency, worker) {
  const queue = [...items];
  const workers = Array.from({length: Math.min(concurrency, queue.length)}, async () => {
    while (queue.length > 0) {
      const nextItem = queue.shift();
      if (nextItem === undefined) return;
      await worker(nextItem);
    }
  });
  await Promise.all(workers);
}

async function deleteFirestoreDocument(cli, projectId, docPath) {
  const url = `${firestoreBaseUrl(projectId)}/${encodeFirestorePath(docPath)}`;
  await googleJsonRequest(cli, url, {method: "DELETE"});
}

async function deleteCollectionRecursively(
  cli,
  projectId,
  collectionPath,
  counters,
  rootCollectionId = collectionPath.split("/")[0],
) {
  const documents = await listDocumentsInCollection(cli, projectId, collectionPath);
  await runWithConcurrency(
    documents,
    FIRESTORE_DOCUMENT_DELETE_CONCURRENCY,
    async (document) => {
    const docPath = documentNameToPath(document.name);
    const subcollectionIds = await listCollectionIds(cli, projectId, docPath);
    for (const subcollectionId of subcollectionIds) {
      await deleteCollectionRecursively(
        cli,
        projectId,
        `${docPath}/${subcollectionId}`,
        counters,
        rootCollectionId,
      );
    }
    await deleteFirestoreDocument(cli, projectId, docPath);
    counters.firestoreDeletedDocuments += 1;
    counters.firestoreDeletedByRootCollection[rootCollectionId] =
      (counters.firestoreDeletedByRootCollection[rootCollectionId] || 0) + 1;
    },
  );
}

async function deleteStoragePrefix(cli, bucketName, prefix, counters) {
  const files = await listStorageObjects(cli, bucketName, prefix);
  for (const file of files) {
    const url = `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(
      bucketName,
    )}/o/${encodeURIComponent(file.name)}`;
    await googleJsonRequest(cli, url, {method: "DELETE"});
    counters.storageDeletedObjects += 1;
    counters.storageDeletedByPrefix[prefix] =
      (counters.storageDeletedByPrefix[prefix] || 0) + 1;
  }
}

async function cleanupOrphanCollectionGroup(
  cli,
  projectId,
  collectionId,
  counters,
) {
  const documents = await listCollectionGroupDocuments(cli, projectId, collectionId);
  const docPaths = documents.map((document) => documentNameToPath(document.name));
  counters.orphanCleanupFoundDocuments += docPaths.length;
  counters.orphanCleanupDocumentPaths.push(
    ...docPaths.map((docPath) => ({
      collectionGroup: collectionId,
      path: docPath,
    })),
  );

  await runWithConcurrency(
    docPaths,
    FIRESTORE_DOCUMENT_DELETE_CONCURRENCY,
    async (docPath) => {
      try {
        await deleteFirestoreDocument(cli, projectId, docPath);
        counters.orphanCleanupDeletedDocuments += 1;
      } catch (error) {
        counters.orphanCleanupFailedDocuments += 1;
        throw new Error(
          `Failed to delete orphan ${docPath}: ${
            error instanceof Error ? error.message : String(error)
          }`,
        );
      }
    },
  );
}

async function deleteAuthUsers(cli, projectId, authUsers, counters) {
  for (let index = 0; index < authUsers.length; index += AUTH_DELETE_BATCH_LIMIT) {
    const batch = authUsers.slice(index, index + AUTH_DELETE_BATCH_LIMIT);
    const localIds = batch
      .map((user) => String(user.localId || user.uid || "").trim())
      .filter(Boolean);
    if (localIds.length === 0) continue;

    const url = `https://identitytoolkit.googleapis.com/v1/projects/${projectId}/accounts:batchDelete`;
    await googleJsonRequest(cli, url, {
      method: "POST",
      body: {
        localIds,
        force: true,
      },
    });
    counters.authDeletedUsers += localIds.length;
  }
}

function printSection(title, value) {
  console.log(`\n=== ${title} ===`);
  console.log(
    typeof value === "string" ? value : JSON.stringify(value, null, 2),
  );
}

function shouldBlockDestructiveRun(cli, inventory) {
  if (cli.activeProjectId !== EXPECTED_PROJECT_ID) {
    return `Active Firebase project mismatch: expected ${EXPECTED_PROJECT_ID}, got ${cli.activeProjectId || "(empty)"}.`;
  }
  return "";
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const cli = getCliContext();
  if (!cli.activeProjectId) {
    throw new Error("Unable to determine the active Firebase project from Firebase CLI.");
  }
  if (cli.activeProjectId !== EXPECTED_PROJECT_ID) {
    throw new Error(
      `Active Firebase project mismatch: expected ${EXPECTED_PROJECT_ID}, got ${cli.activeProjectId}.`,
    );
  }

  const cleanupTargets = parseCleanupTargets(args.cleanupOrphans);
  if (cleanupTargets.length > 0) {
    if (args.confirmation !== REQUIRED_CONFIRMATION) {
      throw new Error(
        `Refusing to run orphan cleanup without --confirm=${REQUIRED_CONFIRMATION}`,
      );
    }

    const counters = createDeletionCounters();
    for (const collectionId of cleanupTargets) {
      await cleanupOrphanCollectionGroup(
        cli,
        cli.activeProjectId,
        collectionId,
        counters,
      );
    }

    printSection("Orphan Cleanup Summary", {
      collectionGroups: cleanupTargets,
      foundDocuments: counters.orphanCleanupFoundDocuments,
      deletedDocuments: counters.orphanCleanupDeletedDocuments,
      failedDocuments: counters.orphanCleanupFailedDocuments,
      documentPaths: counters.orphanCleanupDocumentPaths,
    });

    if (counters.orphanCleanupFailedDocuments > 0) {
      process.exitCode = 1;
    }
    return;
  }

  const authUsers = await exportAuthUsers(cli, cli.activeProjectId);
  const rootCollections = await getRootCollections(cli, cli.activeProjectId);
  const storageInventory = await inventoryStorage(cli, cli.storageBuckets);
  const resetPlan = buildResetPlan(rootCollections, storageInventory);

  if (args.dryRun) {
    const firestoreState = buildState();

    for (const collectionId of rootCollections) {
      firestoreState.rootCollectionStats[collectionId] = {
        rootCollection: collectionId,
        directDocumentCount: 0,
        totalDocumentsUnderRoot: 0,
        nestedCollectionCount: 0,
        sampledParentDocumentsForNestedScan: 0,
        sampleDocumentPaths: [],
      };
      await inspectRootCollectionForDryRun(
        cli,
        cli.activeProjectId,
        collectionId,
        firestoreState,
      );
    }

    firestoreState.totalFirestoreDocuments = Object.values(
      firestoreState.rootCollectionStats,
    ).reduce((sum, stat) => sum + stat.directDocumentCount, 0);

    const adminImpact = summarizeAdminAccessImpact(authUsers, firestoreState);
    const inventory = {
      activeFirebaseProjectId: cli.activeProjectId,
      currentFirebaseCliAccount: cli.currentAccountEmail || "(unknown)",
      firebaseAuthUserCount: authUsers.length,
      rootFirestoreCollections: rootCollections,
      firestoreDocumentCounts: {
        totalDocumentsTraversed: firestoreState.totalFirestoreDocuments,
        note:
          "Counts are exact for root-level documents. Nested subcollections are sampled during dry run for structure discovery only. Destructive deletion still walks nested subcollections recursively before removing documents.",
        byRootCollection: firestoreState.rootCollectionStats,
        nestedCollectionPaths: Array.from(firestoreState.nestedCollectionPaths)
          .sort((a, b) => a.localeCompare(b))
          .slice(0, 200),
      },
      storage: {
        bucketNames: storageInventory.bucketNames,
        totalObjects: storageInventory.objectCount,
        topLevelPrefixes: storageInventory.topLevelPrefixes,
      },
      adminImpact,
      paymentSignals: firestoreState.paymentSignals,
      warnings: firestoreState.paymentSignals.liveRisk.length > 0 ? [
        "Payment-related Firestore records with Razorpay-linked fields were detected. This reset deletes only Firebase-stored copies and does not call Razorpay APIs or modify Razorpay dashboard records.",
      ] : [],
      dataOutsideExpectedProject: [],
      resetPlan,
      resourcesIntentionallyPreserved: [
        "Firebase project",
        "Firebase apps",
        "Cloud Functions",
        "Functions secrets",
        "Firestore rules",
        "Firestore indexes",
        "Storage rules",
        "Remote Config",
        "Hosting",
        "Authentication provider configuration",
        "Android and iOS Firebase app configuration",
        "Razorpay secrets and function configuration",
        "App Check configuration",
        "Play Integrity configuration",
      ],
    };

    printSection("Dry Run Summary", inventory);
    const destructiveBlocker = shouldBlockDestructiveRun(cli, inventory);
    if (destructiveBlocker) {
      printSection("Destructive Run Blocked", destructiveBlocker);
    }
    return;
  }

  if (args.confirmation !== REQUIRED_CONFIRMATION) {
    throw new Error(
      `Refusing to run destructive reset without --confirm=${REQUIRED_CONFIRMATION}`,
    );
  }
  const destructiveBlocker = shouldBlockDestructiveRun(cli, {
    activeProjectId: cli.activeProjectId,
  });
  if (destructiveBlocker) throw new Error(destructiveBlocker);

  const counters = createDeletionCounters();

  await runWithConcurrency(
    resetPlan.collectionsToDelete,
    FIRESTORE_ROOT_DELETE_CONCURRENCY,
    async (collectionId) => {
      await deleteCollectionRecursively(
        cli,
        cli.activeProjectId,
        collectionId,
        counters,
        collectionId,
      );
    },
  );

  await runWithConcurrency(
    resetPlan.storagePrefixesToDelete,
    STORAGE_PREFIX_DELETE_CONCURRENCY,
    async (prefix) => {
      await deleteStoragePrefix(
        cli,
        storageInventory.bucketName,
        prefix,
        counters,
      );
    },
  );

  await deleteAuthUsers(cli, cli.activeProjectId, authUsers, counters);
  printSection("Destructive Run Summary", counters);
}

main().catch((error) => {
  console.error("\n=== Reset Script Failed ===");
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
