#!/usr/bin/env node
"use strict";

/**
 * Read-only relationship-blocking readiness audit (Phase 3B-3b).
 *
 * Emulator rehearsal (default mode):
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node scripts/read_only_relationship_audit.js \
 *     --project=demo-pettxo-audit [--count-only] [--max-reads=N] [--out-dir=DIR]
 *
 * Production (only after owner approval; see
 * docs/PETTXO_PHASE3B3B_PRODUCTION_AUDIT_APPROVAL_PACKAGE.md):
 *   node scripts/read_only_relationship_audit.js --project=pettexo-d9409 \
 *     --confirm-production-read [--count-only] [--max-reads=N]
 *
 * Safety layers, in order:
 *   1. Every Firestore write method is locked process-wide BEFORE any other
 *      project code loads (lockFirestoreWritePrototypes).
 *   2. Mode/flag/environment checks refuse before any client is created.
 *   3. Production: user ADC refused; the service-account principal must match;
 *      projects.testIamPermissions must report no write-capable permission.
 *   4. The Firestore instance only forwards read RPCs (enforceReadOnlyFirestore).
 *   5. All reads run in one read-only transaction pinned to a single readTime.
 */

const firestoreModule = require("firebase-admin/firestore");
const {
  enforceReadOnlyFirestore,
  lockFirestoreWritePrototypes,
} = require("../lib/audit/readOnlyFirestore.js");

const lockedWriteMethods = lockFirestoreWritePrototypes({
  DocumentReference: firestoreModule.DocumentReference,
  CollectionReference: firestoreModule.CollectionReference,
  WriteBatch: firestoreModule.WriteBatch,
  Transaction: firestoreModule.Transaction,
  BulkWriter: firestoreModule.BulkWriter,
});

const {createRequire} = require("node:module");
const {randomUUID} = require("node:crypto");
const {applicationDefault, deleteApp, initializeApp} = require("firebase-admin/app");
const {
  gitStateFor,
  resolveCredentialIdentity,
  runAuditCli,
} = require("../lib/audit/relationshipAuditCli.js");

async function createFirestore(projectId, mode) {
  const options = mode === "production" ?
    {projectId, credential: applicationDefault()} :
    {projectId};
  const app = initializeApp(options, `relationship-audit-${randomUUID()}`);
  const db = enforceReadOnlyFirestore(firestoreModule.getFirestore(app));
  return {db, appProjectId: app.options.projectId, close: () => deleteApp(app)};
}

/**
 * Uses the same google-auth-library instance as @google-cloud/firestore, so the
 * principal checked here is the principal Firestore will authenticate as.
 * (firebase-admin's own ImpersonatedServiceAccountCredential returns the source
 * user's token in firebase-admin 12.x, so it must not be used for this check.)
 */
async function testIamPermissions(projectId, permissions, expectedPrincipal) {
  const firestoreRequire = createRequire(require.resolve("@google-cloud/firestore"));
  const {GoogleAuth} = firestoreRequire("google-auth-library");
  const auth = new GoogleAuth({scopes: ["https://www.googleapis.com/auth/cloud-platform"]});
  const client = await auth.getClient();
  const runtimePrincipal = client.targetPrincipal || client.email || "";
  if (runtimePrincipal !== expectedPrincipal) {
    throw new Error(`runtime auth client principal (${runtimePrincipal || "unknown"}) does not match ${expectedPrincipal}`);
  }
  const response = await client.request({
    url: `https://cloudresourcemanager.googleapis.com/v1/projects/${encodeURIComponent(projectId)}:testIamPermissions`,
    method: "POST",
    data: {permissions},
  });
  return Array.isArray(response.data?.permissions) ? response.data.permissions : [];
}

runAuditCli(process.argv.slice(2), {
  env: process.env,
  now: () => new Date(),
  log: (line) => process.stdout.write(`${line}\n`),
  error: (line) => process.stderr.write(`${line}\n`),
  createFirestore,
  resolveCredential: (env) => resolveCredentialIdentity(env),
  testIamPermissions,
  gitState: () => gitStateFor(),
  lockedWriteMethods,
}).then((code) => {
  process.exitCode = code;
}, (error) => {
  process.stderr.write(`[audit] ERROR: ${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
});
