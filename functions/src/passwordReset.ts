export type PasswordResetEligibilityStatus =
  | "approved"
  | "invalidEmail"
  | "accountNotFound"
  | "phoneOnlyAccount"
  | "accountPendingDeletion"
  | "accountDisabled";

export function normalizePasswordResetEmail(email: unknown): string {
  return typeof email === "string" ? email.trim().toLowerCase() : "";
}

export function validatePasswordResetEmail(email: string): string | null {
  if (!email) return "Email is required.";
  const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailPattern.test(email)) {
    return "Enter a valid email address.";
  }
  return null;
}

export function evaluatePasswordResetEligibility(params: {
  providerIds: string[];
  disabled: boolean;
  accountStatus: string;
}): PasswordResetEligibilityStatus {
  if (params.disabled) return "accountDisabled";
  if (
    params.accountStatus === "pendingDeletion" ||
    params.accountStatus === "deletionInProgress"
  ) {
    return "accountPendingDeletion";
  }
  if (!params.providerIds.includes("password")) {
    return "phoneOnlyAccount";
  }
  return "approved";
}
