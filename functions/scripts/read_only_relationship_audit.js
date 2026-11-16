"use strict";

const {applicationDefault, deleteApp, initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {
  runReadOnlyHistoricalRelationshipAudit,
} = require("../lib/blocking/historicalRelationshipMigration.js");

function argumentValue(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? String(process.argv[index + 1] ?? "").trim() : "";
}

async function main() {
  const projectId = argumentValue("--project");
  if (!projectId || !process.argv.includes("--confirm-read-only")) {
    throw new Error(
      "Usage: node scripts/read_only_relationship_audit.js " +
      "--project <project-id> --confirm-read-only",
    );
  }
  const app = initializeApp({credential: applicationDefault(), projectId},
    `read-only-relationship-audit-${Date.now()}`);
  try {
    const result = await runReadOnlyHistoricalRelationshipAudit({
      firestore: getFirestore(app),
      authoritativeNow: new Date(),
    });
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  } finally {
    await deleteApp(app);
  }
}

main().catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
});
