/**
 * Operator CLI for the read-only relationship-blocking readiness audit.
 *
 * NOT exported from src/index.ts; defines no Cloud Function. Entry point:
 * scripts/read_only_relationship_audit.js, which locks every Firestore write
 * method process-wide before loading this module.
 *
 * Modes
 *   emulator (default): --project=demo-*; FIRESTORE_EMULATOR_HOST must be loopback.
 *   production: --project=pettexo-d9409 AND --confirm-production-read. Before
 *     any data read it requires a service-account ADC (impersonated preferred),
 *     refuses user credentials, verifies the principal, and refuses if
 *     projects.testIamPermissions reports any write-capable permission.
 *
 * Exit codes: 0 complete and nothing needs review (or count-only complete);
 *             2 complete with records needing review;
 *             1 refused, incomplete, or error.
 */

import {createHash, createHmac, randomBytes} from "node:crypto";
import {execFileSync} from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

import type {Firestore, Timestamp} from "firebase-admin/firestore";

import {
  evaluateRelationshipAudit,
  RELATIONSHIP_AUDIT_VERSION,
  type AuditEvaluation,
  type AuditRecord,
} from "./relationshipAuditEvaluation";
import {
  AuditIncompleteError,
  chooseReadTime,
  countRelationshipAuditSource,
  DEFAULT_PAGE_SIZE,
  MAX_PAGE_SIZE,
  scanRelationshipAuditSource,
  type CountOnlyResult,
  type ScanProgress,
} from "./relationshipAuditScanner";

export const PRODUCTION_PROJECT_ID = "pettexo-d9409";
export const DEFAULT_AUDIT_SERVICE_ACCOUNT = `pettxo-audit-readonly@${PRODUCTION_PROJECT_ID}.iam.gserviceaccount.com`;

/** Permissions whose presence makes the credential unacceptable for a read-only audit. */
export const FORBIDDEN_WRITE_PERMISSIONS = [
  "datastore.entities.create",
  "datastore.entities.update",
  "datastore.entities.delete",
  "datastore.databases.create",
  "datastore.databases.update",
  "datastore.databases.delete",
  "datastore.databases.import",
  "datastore.databases.export",
  "datastore.indexes.create",
  "datastore.indexes.update",
  "datastore.indexes.delete",
  "firebaserules.releases.create",
  "firebaserules.releases.update",
  "firebaserules.rulesets.create",
  "cloudfunctions.functions.create",
  "cloudfunctions.functions.update",
  "cloudfunctions.functions.delete",
  "storage.objects.create",
  "storage.objects.delete",
  "resourcemanager.projects.setIamPolicy",
  "iam.serviceAccountKeys.create",
] as const;

/** Permissions the audit needs; absence would produce a partial (misleading) result. */
export const REQUIRED_READ_PERMISSIONS = ["datastore.entities.get", "datastore.entities.list"] as const;

const LOOPBACK_HOST = /^(127\.0\.0\.1|localhost|\[::1\]):\d+$/;
const DEMO_PROJECT = /^demo-[a-z0-9-]+$/;
const EMULATOR_VARIABLES = ["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST", "FIREBASE_STORAGE_EMULATOR_HOST"];

export class AuditRefusedError extends Error {
  constructor(readonly reasonCode: string, message: string) {
    super(message);
    this.name = "AuditRefusedError";
  }
}

/* ------------------------------------------------------------------------ */
/* Arguments                                                                */
/* ------------------------------------------------------------------------ */

export type AuditArguments = {
  project: string;
  mode: "emulator" | "production";
  countOnly: boolean;
  maxReads: number | null;
  pageSize: number;
  outDir: string | null;
  expectServiceAccount: string;
};

const BOOLEAN_FLAGS = new Set(["--confirm-production-read", "--count-only"]);
const VALUE_FLAGS = new Set(["--project", "--max-reads", "--page-size", "--out-dir", "--expect-service-account"]);

export function parseAuditArguments(argv: string[], env: NodeJS.ProcessEnv): AuditArguments {
  const values = new Map<string, string>();
  const booleans = new Set<string>();
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    const [flag, inline] = token.includes("=") ? [token.slice(0, token.indexOf("=")), token.slice(token.indexOf("=") + 1)] :
      [token, undefined];
    if (BOOLEAN_FLAGS.has(flag) && inline === undefined) {
      booleans.add(flag);
    } else if (VALUE_FLAGS.has(flag)) {
      const value = inline ?? argv[index + 1];
      if (inline === undefined) index += 1;
      if (value === undefined || value.startsWith("--")) throw new AuditRefusedError("MISSING_FLAG_VALUE", `${flag} requires a value`);
      if (values.has(flag)) throw new AuditRefusedError("DUPLICATE_FLAG", `${flag} given twice`);
      values.set(flag, value.trim());
    } else if (flag === "--confirm-read-only") {
      throw new AuditRefusedError("LEGACY_FLAG",
        "--confirm-read-only is retired; production reads require --project=pettexo-d9409 --confirm-production-read");
    } else {
      throw new AuditRefusedError("UNKNOWN_FLAG", `unknown argument: ${token}`);
    }
  }
  const project = values.get("--project") ?? (DEMO_PROJECT.test(env.GCLOUD_PROJECT ?? "") ? env.GCLOUD_PROJECT! : "");
  if (!project) throw new AuditRefusedError("PROJECT_REQUIRED", "--project is required (demo-* for the emulator)");
  const confirmProduction = booleans.has("--confirm-production-read");
  let mode: AuditArguments["mode"];
  if (DEMO_PROJECT.test(project)) {
    if (confirmProduction) {
      throw new AuditRefusedError("CONTRADICTORY_FLAGS", "--confirm-production-read cannot be used with a demo-* project");
    }
    mode = "emulator";
  } else if (project === PRODUCTION_PROJECT_ID) {
    if (!confirmProduction) {
      throw new AuditRefusedError("PRODUCTION_CONFIRMATION_REQUIRED",
        `--project=${PRODUCTION_PROJECT_ID} requires --confirm-production-read`);
    }
    mode = "production";
  } else {
    throw new AuditRefusedError("PROJECT_NOT_ALLOWED",
      `project ${project} is not allowed; use a demo-* emulator project or ${PRODUCTION_PROJECT_ID}`);
  }
  const integer = (flag: string, min: number, max: number): number | null => {
    const raw = values.get(flag);
    if (raw === undefined) return null;
    if (!/^\d+$/.test(raw)) throw new AuditRefusedError("INVALID_FLAG_VALUE", `${flag} must be a positive integer`);
    const parsed = Number(raw);
    if (parsed < min || parsed > max) throw new AuditRefusedError("INVALID_FLAG_VALUE", `${flag} must be between ${min} and ${max}`);
    return parsed;
  };
  return {
    project,
    mode,
    countOnly: booleans.has("--count-only"),
    maxReads: integer("--max-reads", 1, 50_000_000),
    pageSize: integer("--page-size", 1, MAX_PAGE_SIZE) ?? DEFAULT_PAGE_SIZE,
    outDir: values.get("--out-dir") ?? null,
    expectServiceAccount: values.get("--expect-service-account") ?? DEFAULT_AUDIT_SERVICE_ACCOUNT,
  };
}

/* ------------------------------------------------------------------------ */
/* Environment and credential checks                                        */
/* ------------------------------------------------------------------------ */

export function assertEnvironmentForMode(args: AuditArguments, env: NodeJS.ProcessEnv): void {
  if (args.mode === "emulator") {
    const host = env.FIRESTORE_EMULATOR_HOST ?? "";
    if (!LOOPBACK_HOST.test(host)) {
      throw new AuditRefusedError("EMULATOR_REQUIRED",
        "emulator mode requires FIRESTORE_EMULATOR_HOST to be a loopback address");
    }
    return;
  }
  const emulatorVariables = EMULATOR_VARIABLES.filter((name) => env[name]);
  if (emulatorVariables.length > 0) {
    throw new AuditRefusedError("EMULATOR_VARIABLES_IN_PRODUCTION",
      `production mode refuses while ${emulatorVariables.join(", ")} is set`);
  }
}

export type CredentialIdentity = {
  type: "impersonated_service_account" | "service_account";
  principal: string;
  source: "GOOGLE_APPLICATION_CREDENTIALS" | "well-known ADC file";
  keyFileOnDisk: boolean;
};

/**
 * Inspects the ADC file that google-auth-library will use, reading only its
 * `type` and the service-account identity. Never prints or returns secrets.
 */
export function resolveCredentialIdentity(env: NodeJS.ProcessEnv, readFile: (file: string) => string = (file) =>
  fs.readFileSync(file, "utf8"), exists: (file: string) => boolean = fs.existsSync): CredentialIdentity {
  const explicit = env.GOOGLE_APPLICATION_CREDENTIALS || env.google_application_credentials || "";
  const wellKnown = env.HOME ? path.join(env.HOME, ".config", "gcloud", "application_default_credentials.json") : "";
  const file = explicit || wellKnown;
  const source = explicit ? "GOOGLE_APPLICATION_CREDENTIALS" : "well-known ADC file";
  if (!file || !exists(file)) {
    throw new AuditRefusedError("NO_SERVICE_ACCOUNT_CREDENTIAL",
      "no application default credential file found; metadata-server and other ambient credentials are not accepted");
  }
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(readFile(file)) as Record<string, unknown>;
  } catch {
    throw new AuditRefusedError("CREDENTIAL_UNREADABLE", "the application default credential file is not valid JSON");
  }
  const type = typeof parsed.type === "string" ? parsed.type : "";
  if (type === "authorized_user") {
    throw new AuditRefusedError("USER_CREDENTIAL_REFUSED",
      "application default credentials are a user account (authorized_user); a read-only service account is required");
  }
  if (type === "impersonated_service_account") {
    const url = typeof parsed.service_account_impersonation_url === "string" ? parsed.service_account_impersonation_url : "";
    const match = /\/serviceAccounts\/([^/:]+):generateAccessToken$/.exec(url);
    if (!match) throw new AuditRefusedError("CREDENTIAL_PRINCIPAL_UNKNOWN", "impersonated credential has no target service account");
    if (Array.isArray(parsed.delegates) && parsed.delegates.length > 0) {
      throw new AuditRefusedError("DELEGATION_REFUSED", "impersonation delegation chains are not accepted");
    }
    return {type, principal: decodeURIComponent(match[1]), source, keyFileOnDisk: false};
  }
  if (type === "service_account") {
    const email = typeof parsed.client_email === "string" ? parsed.client_email : "";
    if (!email) throw new AuditRefusedError("CREDENTIAL_PRINCIPAL_UNKNOWN", "service account key has no client_email");
    return {type, principal: email, source, keyFileOnDisk: true};
  }
  throw new AuditRefusedError("CREDENTIAL_TYPE_REFUSED", `credential type "${type || "(none)"}" is not accepted`);
}

export function assertPermissionsAreReadOnly(granted: readonly string[]): void {
  const grantedSet = new Set(granted);
  const write = FORBIDDEN_WRITE_PERMISSIONS.filter((permission) => grantedSet.has(permission));
  if (write.length > 0) {
    throw new AuditRefusedError("WRITE_PERMISSION_GRANTED",
      `credential holds write-capable permissions: ${write.join(", ")}`);
  }
  const missing = REQUIRED_READ_PERMISSIONS.filter((permission) => !grantedSet.has(permission));
  if (missing.length > 0) {
    throw new AuditRefusedError("READ_PERMISSION_MISSING", `credential lacks required read permissions: ${missing.join(", ")}`);
  }
}

/* ------------------------------------------------------------------------ */
/* Output                                                                   */
/* ------------------------------------------------------------------------ */

const REPO_ROOT = path.resolve(__dirname, "..", "..", "..");

export function defaultOutputDirectory(startedAt: Date, home: string = os.homedir()): string {
  const stamp = startedAt.toISOString().replace(/[:.]/g, "-");
  return path.join(home, "PettxoReleaseBackups", "audits", stamp);
}

function realpathOrSelf(target: string): string {
  try {
    return fs.realpathSync(target);
  } catch {
    return path.resolve(target);
  }
}

export function assertOutputDirectoryAllowed(outDir: string, repoRoot: string = REPO_ROOT): void {
  let probe = path.resolve(outDir);
  while (!fs.existsSync(probe) && path.dirname(probe) !== probe) probe = path.dirname(probe);
  const resolvedExisting = realpathOrSelf(probe);
  const resolved = path.join(resolvedExisting, path.relative(probe, path.resolve(outDir)));
  const repo = realpathOrSelf(repoRoot);
  if (resolved === repo || resolved.startsWith(`${repo}${path.sep}`)) {
    throw new AuditRefusedError("OUTPUT_INSIDE_REPOSITORY", "the audit output directory must be outside the repository");
  }
  if (fs.existsSync(outDir) && fs.readdirSync(outDir).length > 0) {
    throw new AuditRefusedError("OUTPUT_NOT_EMPTY", "the audit output directory must not already contain files");
  }
}

function sha256File(file: string): string {
  return createHash("sha256").update(fs.readFileSync(file)).digest("hex");
}

function writePrivate(file: string, content: string): void {
  fs.writeFileSync(file, content, {mode: 0o600, flag: "wx"});
  fs.chmodSync(file, 0o600);
}

type Hasher = (value: string) => string;

function hashedRecord(record: AuditRecord, hash: Hasher) {
  return {
    category: record.category,
    reasonCode: record.reasonCode,
    recordRef: hash(`${record.collection}/${record.documentId}`),
    bookingRef: record.bookingId ? hash(`bookings/${record.bookingId}`) : null,
    pairRef: record.pairKey ? hash(record.pairKey) : null,
    hashedUids: (record.uids ?? []).map(hash),
  };
}

function markdownTable(title: string, counts: Record<string, unknown>): string {
  const rows = Object.entries(counts)
    .filter(([, value]) => typeof value === "number")
    .map(([key, value]) => `| ${key} | ${value} |`);
  return [`### ${title}`, "", "| Item | Count |", "|---|---|", ...rows, ""].join("\n");
}

function summaryMarkdown(summary: Record<string, unknown>): string {
  const lines = [
    "# Pettxo relationship-blocking readiness audit (summary)",
    "",
    `- Status: **${summary.status}**${summary.incompleteReason ? ` (${summary.incompleteReason})` : ""}`,
    `- Mode: ${summary.mode}; project: ${summary.project}; count-only: ${summary.countOnly}`,
    `- Snapshot readTime: ${summary.readTime}; started ${summary.startedAt}; finished ${summary.finishedAt}`,
    `- Reads: ${summary.readCount}${summary.maxReads != null ? ` of max ${summary.maxReads}` : ""}`,
    `- Exit code: ${summary.exitCode}`,
    "",
    "Counts only. UIDs and record references are salted HMAC-SHA256 hashes; the salt and raw IDs are in review_records.json (mode 0600).",
    "",
  ];
  const findings = summary.findings as Record<string, unknown> | undefined;
  if (findings) {
    for (const [section, value] of Object.entries(findings)) {
      if (value && typeof value === "object" && !Array.isArray(value)) {
        lines.push(markdownTable(section, value as Record<string, unknown>));
        for (const [nested, nestedValue] of Object.entries(value as Record<string, unknown>)) {
          if (nestedValue && typeof nestedValue === "object") {
            lines.push(markdownTable(`${section}.${nested}`, nestedValue as Record<string, unknown>));
          }
        }
      }
    }
    lines.push(`Review records: **${findings.reviewRecordCount}**; informational records: ${findings.informationalRecordCount}`, "");
  }
  const countOnly = summary.countOnlyResult as Record<string, unknown> | undefined;
  if (countOnly) {
    lines.push(markdownTable("collectionCounts", countOnly.collectionCounts as Record<string, unknown>));
    lines.push(markdownTable("bookingsByState", countOnly.bookingsByState as Record<string, unknown>));
    lines.push(`- bookingsWithNonCanonicalState: ${countOnly.bookingsWithNonCanonicalState}`);
    lines.push(`- estimatedFullRunReads: ${countOnly.estimatedFullRunReads}`);
    lines.push(`- suggestedMaxReads: ${countOnly.suggestedMaxReads}`, "");
  }
  const progress = summary.partialProgress as Record<string, unknown> | undefined;
  if (progress) {
    lines.push("## INCOMPLETE - partial progress (do not use for decisions)", "");
    lines.push(markdownTable("collectionsCompleted", progress.collectionsCompleted as Record<string, unknown>));
    lines.push(`- inProgress: ${progress.inProgress ?? "(none)"}`, "");
  }
  return `${lines.join("\n")}\n`;
}

/* ------------------------------------------------------------------------ */
/* Runner                                                                   */
/* ------------------------------------------------------------------------ */

export type FirestoreHandle = {
  db: Firestore;
  appProjectId: string;
  close: () => Promise<void>;
};

export type AuditCliDependencies = {
  env: NodeJS.ProcessEnv;
  now: () => Date;
  log: (line: string) => void;
  error: (line: string) => void;
  /** Must return a Firestore already passed through enforceReadOnlyFirestore. */
  createFirestore: (projectId: string, mode: "emulator" | "production") => Promise<FirestoreHandle>;
  resolveCredential: (env: NodeJS.ProcessEnv) => CredentialIdentity;
  /** Production only: verifies the runtime auth client principal and returns granted permissions. */
  testIamPermissions: (projectId: string, permissions: string[], expectedPrincipal: string) => Promise<string[]>;
  gitState: () => {sha: string; dirtyAuditSources: boolean};
  lockedWriteMethods: string[];
  home?: string;
};

export async function runAuditCli(argv: string[], deps: AuditCliDependencies): Promise<number> {
  const startedAt = deps.now();
  let args!: AuditArguments;
  let identity: CredentialIdentity | null = null;
  try {
    args = parseAuditArguments(argv, deps.env);
    assertEnvironmentForMode(args, deps.env);
    if (deps.lockedWriteMethods.length === 0) {
      throw new AuditRefusedError("WRITE_LOCK_MISSING", "process-wide Firestore write lock is not installed");
    }
    if (args.mode === "production") {
      identity = deps.resolveCredential(deps.env);
      if (identity.principal !== args.expectServiceAccount) {
        throw new AuditRefusedError("UNEXPECTED_PRINCIPAL",
          `credential principal ${identity.principal} is not the expected ${args.expectServiceAccount}`);
      }
      const granted = await deps.testIamPermissions(args.project,
        [...FORBIDDEN_WRITE_PERMISSIONS, ...REQUIRED_READ_PERMISSIONS], identity.principal);
      assertPermissionsAreReadOnly(granted);
      deps.log(`[audit] credential ${identity.type} principal=${identity.principal} write permissions: none; read permissions: ok`);
    }
  } catch (error) {
    deps.error(`[audit] REFUSED: ${error instanceof Error ? error.message : String(error)}`);
    return 1;
  }

  const outDir = path.resolve(args.outDir ?? defaultOutputDirectory(startedAt, deps.home));
  try {
    assertOutputDirectoryAllowed(outDir);
  } catch (error) {
    deps.error(`[audit] REFUSED: ${error instanceof Error ? error.message : String(error)}`);
    return 1;
  }

  const progress: ScanProgress = {readCount: 0, maxReads: args.maxReads, collectionsCompleted: {}, inProgress: null};
  let handle: FirestoreHandle | null = null;
  let readTime: Timestamp | null = null;
  let evaluation: AuditEvaluation | null = null;
  let countOnlyResult: CountOnlyResult | null = null;
  let status: "COMPLETE" | "INCOMPLETE" = "INCOMPLETE";
  let incompleteReason: string | null = null;
  try {
    handle = await deps.createFirestore(args.project, args.mode);
    // Public runtime getters of @google-cloud/firestore (absent from the typings).
    const runtime = handle.db as unknown as {projectId: string; formattedName: string};
    const resolvedProject = runtime.projectId;
    if (handle.appProjectId !== args.project || resolvedProject !== args.project ||
      runtime.formattedName !== `projects/${args.project}/databases/(default)`) {
      throw new AuditRefusedError("PROJECT_MISMATCH",
        `initialised project ${handle.appProjectId}/${resolvedProject} does not equal --project=${args.project}`);
    }
    readTime = chooseReadTime(deps.now().getTime());
    deps.log(`[audit] mode=${args.mode} project=${args.project} readTime=${readTime.toDate().toISOString()} ` +
      `countOnly=${args.countOnly} maxReads=${args.maxReads ?? "unlimited"}`);
    if (args.countOnly) {
      countOnlyResult = await countRelationshipAuditSource({db: handle.db, readTime, maxReads: args.maxReads,
        pageSize: args.pageSize, progress, clock: () => deps.now().getTime()});
    } else {
      const source = await scanRelationshipAuditSource({db: handle.db, readTime, maxReads: args.maxReads,
        pageSize: args.pageSize, progress, clock: () => deps.now().getTime()});
      evaluation = evaluateRelationshipAudit(source, readTime.toDate());
    }
    status = "COMPLETE";
  } catch (error) {
    incompleteReason = error instanceof AuditIncompleteError || error instanceof AuditRefusedError ?
      error.reasonCode : `ERROR:${(error as {code?: unknown})?.code ?? "UNKNOWN"}`;
    deps.error(`[audit] INCOMPLETE (${incompleteReason}): ${error instanceof Error ? error.message : String(error)}`);
  } finally {
    if (handle) await handle.close().catch(() => undefined);
  }

  const finishedAt = deps.now();
  const reviewCount = evaluation?.reviewRecords.length ?? 0;
  const exitCode = status !== "COMPLETE" ? 1 : reviewCount > 0 ? 2 : 0;

  fs.mkdirSync(outDir, {recursive: true, mode: 0o700});
  fs.chmodSync(outDir, 0o700);
  const salt = randomBytes(32).toString("hex");
  const hash: Hasher = (value) => `h_${createHmac("sha256", salt).update(value).digest("hex").slice(0, 16)}`;
  const summary: Record<string, unknown> = {
    status,
    incompleteReason,
    mode: args.mode,
    project: args.project,
    countOnly: args.countOnly,
    auditVersion: RELATIONSHIP_AUDIT_VERSION,
    readTime: readTime?.toDate().toISOString() ?? null,
    startedAt: startedAt.toISOString(),
    finishedAt: finishedAt.toISOString(),
    readCount: progress.readCount,
    maxReads: args.maxReads,
    exitCode,
    reviewDetermination: args.countOnly ? "NOT_EVALUATED_IN_COUNT_ONLY_MODE" :
      status === "COMPLETE" ? (reviewCount > 0 ? "RECORDS_NEED_REVIEW" : "NO_RECORDS_NEED_REVIEW") : "UNKNOWN_INCOMPLETE",
    findings: evaluation?.findings ?? null,
    countOnlyResult,
    reviewIndex: evaluation ? evaluation.reviewRecords.map((record) => hashedRecord(record, hash)) : [],
    partialProgress: status === "COMPLETE" ? null : {
      collectionsCompleted: progress.collectionsCompleted,
      inProgress: progress.inProgress,
    },
  };
  const files: Record<string, string> = {};
  const summaryJson = path.join(outDir, "summary.json");
  writePrivate(summaryJson, `${JSON.stringify(summary, null, 2)}\n`);
  files["summary.json"] = sha256File(summaryJson);
  const summaryMd = path.join(outDir, "summary.md");
  writePrivate(summaryMd, summaryMarkdown(summary));
  files["summary.md"] = sha256File(summaryMd);
  if (evaluation) {
    const reviewFile = path.join(outDir, "review_records.json");
    writePrivate(reviewFile, `${JSON.stringify({
      warning: "RESTRICTED: contains raw document IDs and UIDs for reconciliation. Delete after reconciliation.",
      salt,
      hashFormat: "h_ + first 16 hex chars of HMAC-SHA256(salt, value)",
      readTime: readTime?.toDate().toISOString() ?? null,
      reviewRecords: evaluation.reviewRecords,
      informationalRecords: evaluation.informationalRecords,
    }, null, 2)}\n`);
    files["review_records.json"] = sha256File(reviewFile);
  }
  const git = deps.gitState();
  const manifest = {
    script: "functions/scripts/read_only_relationship_audit.js",
    auditVersion: RELATIONSHIP_AUDIT_VERSION,
    gitSha: git.sha,
    auditSourcesDirty: git.dirtyAuditSources,
    mode: args.mode,
    project: args.project,
    countOnly: args.countOnly,
    credential: identity ? {type: identity.type, principal: identity.principal, source: identity.source,
      keyFileOnDisk: identity.keyFileOnDisk} : null,
    readTime: readTime?.toDate().toISOString() ?? null,
    startedAt: startedAt.toISOString(),
    finishedAt: finishedAt.toISOString(),
    readCount: progress.readCount,
    maxReads: args.maxReads,
    pageSize: args.pageSize,
    status,
    incompleteReason,
    exitCode,
    writeLock: {processWideMethodsLocked: deps.lockedWriteMethods.length, rpcAllowlist: true},
    outputFiles: files,
  };
  writePrivate(path.join(outDir, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
  deps.log(`[audit] ${status} exit=${exitCode} reads=${progress.readCount} reviewRecords=${reviewCount} out=${outDir}`);
  return exitCode;
}

/* ------------------------------------------------------------------------ */
/* Real dependencies                                                        */
/* ------------------------------------------------------------------------ */

export function gitStateFor(repoRoot: string = REPO_ROOT): {sha: string; dirtyAuditSources: boolean} {
  try {
    const sha = execFileSync("git", ["-C", repoRoot, "rev-parse", "HEAD"], {encoding: "utf8"}).trim();
    const dirty = execFileSync("git", ["-C", repoRoot, "status", "--porcelain", "--",
      "functions/src/audit", "functions/scripts/read_only_relationship_audit.js"], {encoding: "utf8"}).trim();
    return {sha, dirtyAuditSources: dirty.length > 0};
  } catch {
    return {sha: "unknown", dirtyAuditSources: true};
  }
}
