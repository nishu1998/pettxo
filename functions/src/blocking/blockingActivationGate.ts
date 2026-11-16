import type {
  DocumentData,
  DocumentReference,
  DocumentSnapshot,
  Firestore,
  Transaction,
} from "firebase-admin/firestore";
import {FieldValue} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

const REQUIRED_RELATIONSHIP_MIGRATION_VERSION = 1;

export const USER_BLOCKING_ROLLOUT_PATH = "_rollouts/userBlockingV1";
export const RELATIONSHIP_MIGRATION_PATH = "_migrations/userRelationshipGuardV1";
export const USER_BLOCKING_ACTIVATION_AUDIT_COLLECTION =
  "userBlockingActivationAudit";

type ActivationDocuments = {
  rollout: DocumentSnapshot<DocumentData>;
  migration: DocumentSnapshot<DocumentData>;
  audit: DocumentSnapshot<DocumentData> | null;
};

export type BlockingActivationState = {
  enabled: boolean;
  reasonCode: string;
  migrationRunId: string;
  activationAuditId: string;
};

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function millis(value: unknown): number {
  if (value instanceof Date) return value.getTime();
  if (typeof value === "object" && value !== null && "toMillis" in value &&
    typeof (value as {toMillis?: unknown}).toMillis === "function") {
    return (value as {toMillis: () => number}).toMillis();
  }
  return 0;
}

function activationState(documents: ActivationDocuments): BlockingActivationState {
  const rollout = documents.rollout.data() ?? {};
  const migration = documents.migration.data() ?? {};
  const audit = documents.audit?.data() ?? {};
  const migrationRunId = text(rollout.migrationRunId);
  const activationAuditId = text(rollout.activationAuditId);
  const rolloutVersion = Number(rollout.rolloutVersion ?? 0);
  const sourceFingerprint = text(migration.sourceFingerprint);

  if (!documents.rollout.exists || rollout.enabled !== true ||
    text(rollout.status) !== "active") {
    return {enabled: false, reasonCode: "USER_BLOCKING_DISABLED", migrationRunId, activationAuditId};
  }
  if (!migrationRunId || !documents.migration.exists ||
    text(migration.status) !== "verified" ||
    text(migration.runId) !== migrationRunId ||
    Number(migration.migrationVersion ?? -1) !== REQUIRED_RELATIONSHIP_MIGRATION_VERSION ||
    !sourceFingerprint || text(rollout.sourceFingerprint) !== sourceFingerprint ||
    migration.reconciliationPassed !== true ||
    Number(migration.anomalyCount ?? -1) !== 0 ||
    Number(migration.mismatchCount ?? -1) !== 0) {
    return {enabled: false, reasonCode: "RELATIONSHIP_MIGRATION_NOT_VERIFIED", migrationRunId, activationAuditId};
  }
  if (!activationAuditId || !documents.audit?.exists ||
    text(audit.event) !== "ACTIVATE" || audit.enabled !== true ||
    text(audit.migrationRunId) !== migrationRunId ||
    text(audit.sourceFingerprint) !== sourceFingerprint ||
    Number(audit.rolloutVersion ?? -1) !== rolloutVersion) {
    return {enabled: false, reasonCode: "BLOCKING_ACTIVATION_NOT_AUDITED", migrationRunId, activationAuditId};
  }
  return {enabled: true, reasonCode: "", migrationRunId, activationAuditId};
}

function auditRef(
  firestore: Firestore,
  rollout: DocumentSnapshot<DocumentData>,
): DocumentReference<DocumentData> | null {
  const activationAuditId = text(rollout.data()?.activationAuditId);
  return activationAuditId ? firestore.collection(
    USER_BLOCKING_ACTIVATION_AUDIT_COLLECTION,
  ).doc(activationAuditId) : null;
}

export async function readBlockingActivationState(
  firestore: Firestore,
): Promise<BlockingActivationState> {
  const [rollout, migration] = await Promise.all([
    firestore.doc(USER_BLOCKING_ROLLOUT_PATH).get(),
    firestore.doc(RELATIONSHIP_MIGRATION_PATH).get(),
  ]);
  const ref = auditRef(firestore, rollout);
  const audit = ref ? await ref.get() : null;
  return activationState({rollout, migration, audit});
}

export async function assertBlockingCreationEnabledInTransaction(params: {
  firestore: Firestore;
  transaction: Transaction;
}): Promise<BlockingActivationState> {
  const [rollout, migration] = await Promise.all([
    params.transaction.get(params.firestore.doc(USER_BLOCKING_ROLLOUT_PATH)),
    params.transaction.get(params.firestore.doc(RELATIONSHIP_MIGRATION_PATH)),
  ]);
  const ref = auditRef(params.firestore, rollout);
  const audit = ref ? await params.transaction.get(ref) : null;
  const state = activationState({rollout, migration, audit});
  if (!state.enabled) {
    throw new HttpsError(
      "failed-precondition",
      "User blocking is not available yet. Reporting remains available.",
      {code: state.reasonCode},
    );
  }
  return state;
}

export async function recordBlockingRolloutTransition(params: {
  firestore: Firestore;
  enabled: boolean;
  operatorUid: string;
  reason: string;
  auditId: string;
  migrationRunId: string;
}): Promise<{enabled: boolean; rolloutVersion: number; idempotentReplay: boolean}> {
  const operatorUid = params.operatorUid.trim();
  const reason = params.reason.trim();
  const auditId = params.auditId.trim();
  const migrationRunId = params.migrationRunId.trim();
  if (!operatorUid || !reason || !auditId || auditId.includes("/") ||
    (params.enabled && !migrationRunId)) {
    throw new Error("invalid_blocking_rollout_transition");
  }
  const rolloutRef = params.firestore.doc(USER_BLOCKING_ROLLOUT_PATH);
  const migrationRef = params.firestore.doc(RELATIONSHIP_MIGRATION_PATH);
  const activationAuditRef = params.firestore.collection(
    USER_BLOCKING_ACTIVATION_AUDIT_COLLECTION,
  ).doc(auditId);
  return params.firestore.runTransaction(async (transaction) => {
    const [rollout, migration, existingAudit] = await Promise.all([
      transaction.get(rolloutRef),
      transaction.get(migrationRef),
      transaction.get(activationAuditRef),
    ]);
    const currentVersion = Number(rollout.data()?.rolloutVersion ?? 0);
    const nextVersion = currentVersion + 1;
    if (existingAudit.exists) {
      const data = existingAudit.data() ?? {};
      if (data.enabled !== params.enabled || text(data.operatorUid) !== operatorUid ||
        text(data.reason) !== reason || text(data.migrationRunId) !== migrationRunId) {
        throw new Error("blocking_rollout_audit_id_conflict");
      }
      return {
        enabled: params.enabled,
        rolloutVersion: Number(data.rolloutVersion ?? currentVersion),
        idempotentReplay: true,
      };
    }
    if (params.enabled) {
      const migrationData = migration.data() ?? {};
      if (!migration.exists || text(migrationData.status) !== "verified" ||
        text(migrationData.runId) !== migrationRunId ||
        Number(migrationData.migrationVersion ?? -1) !==
          REQUIRED_RELATIONSHIP_MIGRATION_VERSION ||
        !text(migrationData.sourceFingerprint) ||
        millis(migrationData.verificationValidUntil) <= Date.now() ||
        migrationData.reconciliationPassed !== true ||
        Number(migrationData.anomalyCount ?? -1) !== 0 ||
        Number(migrationData.mismatchCount ?? -1) !== 0) {
        throw new Error("relationship_migration_not_verified");
      }
    }
    transaction.create(activationAuditRef, {
      schemaVersion: 1,
      event: params.enabled ? "ACTIVATE" : "DEACTIVATE",
      enabled: params.enabled,
      migrationRunId,
      sourceFingerprint: text(migration.data()?.sourceFingerprint),
      rolloutVersion: nextVersion,
      operatorUid,
      reason,
      createdAt: FieldValue.serverTimestamp(),
    });
    transaction.set(rolloutRef, {
      schemaVersion: 1,
      enabled: params.enabled,
      status: params.enabled ? "active" : "disabled",
      migrationRunId,
      sourceFingerprint: params.enabled ? text(migration.data()?.sourceFingerprint) : "",
      activationAuditId: params.enabled ? auditId : "",
      lastAuditId: auditId,
      rolloutVersion: nextVersion,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: false});
    return {enabled: params.enabled, rolloutVersion: nextVersion, idempotentReplay: false};
  });
}
