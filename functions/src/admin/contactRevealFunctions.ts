import {onCall} from "firebase-functions/v2/https";
import {
  findUsersByContactForAdminData,
  getMaskedContactsForAdminData,
  listAdminMembersForSuperAdminData,
  revealContactForAdminData,
} from "./contactReveal";

/**
 * Item 27 admin contact callables (Super Admin only). Region asia-south1 via
 * the global options. Declared private like the other admin callables: each
 * NEW service needs the Cloud Run invoker step after its first deploy
 * (--no-invoker-iam-check, then an unauthenticated POST must return 401).
 */
const adminContactCallableOptions = {
  invoker: "private" as const,
  enforceAppCheck: false,
};

export const getMaskedContactsForAdmin = onCall(
  adminContactCallableOptions,
  (request) => getMaskedContactsForAdminData(request),
);

export const findUsersByContactForAdmin = onCall(
  adminContactCallableOptions,
  (request) => findUsersByContactForAdminData(request),
);

export const revealContactForAdmin = onCall(
  adminContactCallableOptions,
  (request) => revealContactForAdminData(request),
);

export const listAdminMembersForSuperAdmin = onCall(
  adminContactCallableOptions,
  (request) => listAdminMembersForSuperAdminData(request),
);
