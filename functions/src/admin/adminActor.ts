import type {Auth} from "firebase-admin/auth";
import type {Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {auth as defaultAuth, db as defaultDb} from "../shared/firebase";

export const ADMIN_ROLES = ["superAdmin", "customerSupportAdmin", "financeAdmin"] as const;
export type AdminRole = typeof ADMIN_ROLES[number];

export type ActiveAdmin = {
  uid: string;
  role: AdminRole;
  displayName: string;
};

/** The part of a callable request the guard needs. */
export type AdminGuardRequest = {
  auth?: {
    uid: string;
    token?: {auth_time?: number} & Record<string, unknown>;
  } | null;
};

export type AdminGuardDeps = {
  firestore?: Firestore;
  authClient?: Pick<Auth, "getUser">;
};

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function isAdminRole(value: unknown): value is AdminRole {
  return typeof value === "string" && (ADMIN_ROLES as readonly string[]).includes(value);
}

/**
 * True when the admin's users doc marks the account inactive. This is the
 * union of the two existing partial checks (reportModeration.ts
 * requireModerationAdmin and supportFunctions.ts loadSignedInActor).
 */
export function adminAccountIsInactive(data: Record<string, unknown>): boolean {
  const accountStatus = text(data.accountStatus);
  return (accountStatus.length > 0 && accountStatus !== "active") ||
    data.disabled === true ||
    data.isDisabled === true ||
    data.adminDisabled === true ||
    data.isActive === false;
}

function denied(appCode: "ROLE_NOT_ALLOWED" | "ADMIN_NOT_ACTIVE", message: string): HttpsError {
  return new HttpsError("permission-denied", message, {appCode});
}

/**
 * One role and active-account check for new admin callables.
 *
 * In order: a signed-in caller; the Firebase Auth record exists and the
 * session was not revoked (`auth_time` before `tokensValidAfterTime`);
 * `users/{uid}.adminRole` is in `roles`; no inactive or disabled flag on the
 * users doc; the Auth record is not disabled.
 *
 * Stable appCodes: UNAUTHENTICATED, SESSION_REVOKED, ROLE_NOT_ALLOWED,
 * ADMIN_NOT_ACTIVE.
 */
export async function requireActiveAdmin(
  request: AdminGuardRequest,
  roles: readonly AdminRole[],
  deps: AdminGuardDeps = {},
): Promise<ActiveAdmin> {
  const firestore = deps.firestore ?? defaultDb;
  const authClient = deps.authClient ?? defaultAuth;
  const uid = text(request.auth?.uid);
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.", {appCode: "UNAUTHENTICATED"});
  }

  let authRecord: {disabled?: boolean; tokensValidAfterTime?: string};
  try {
    authRecord = await authClient.getUser(uid);
  } catch {
    throw denied("ADMIN_NOT_ACTIVE", "Admin access required.");
  }
  const authTime = request.auth?.token?.auth_time;
  const validAfter = authRecord.tokensValidAfterTime ?
    Date.parse(authRecord.tokensValidAfterTime) :
    Number.NaN;
  if (typeof authTime === "number" && Number.isFinite(validAfter) && authTime * 1000 < validAfter) {
    throw new HttpsError("unauthenticated", "Your session has ended. Sign in again.", {
      appCode: "SESSION_REVOKED",
    });
  }

  const snapshot = await firestore.collection("users").doc(uid).get();
  const data = (snapshot.exists ? snapshot.data() : null) ?? null;
  const role = data ? data.adminRole : null;
  if (!data || !isAdminRole(role) || !roles.includes(role)) {
    throw denied("ROLE_NOT_ALLOWED", "Admin access required.");
  }
  if (adminAccountIsInactive(data) || authRecord.disabled === true) {
    throw denied("ADMIN_NOT_ACTIVE", "This admin account is not active.");
  }

  return {
    uid,
    role,
    displayName: text(data.displayName) || text(data.name) || "Admin",
  };
}

export function requireActiveSuperAdmin(
  request: AdminGuardRequest,
  deps: AdminGuardDeps = {},
): Promise<ActiveAdmin> {
  return requireActiveAdmin(request, ["superAdmin"], deps);
}
