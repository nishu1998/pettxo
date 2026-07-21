export type PhoneLoginEligibilityStatus =
  | "active"
  | "notFound"
  | "incompleteSignup"
  | "blocked"
  | "accountRecoveryRequired";

export function normalizePhoneLoginNumber(phoneNumber: unknown): string {
  return typeof phoneNumber === "string" ? phoneNumber.trim() : "";
}

export function validatePhoneLoginNumber(phoneNumber: string): string | null {
  if (!phoneNumber) return "Phone number is required.";
  if (!/^\+\d{10,15}$/.test(phoneNumber)) {
    return "Enter a valid phone number.";
  }
  return null;
}

export function evaluatePhoneLoginEligibility(params: {
  disabled: boolean;
  accountStatus: string;
  hasPublicProfile: boolean;
  hasPrivateProfile: boolean;
}): PhoneLoginEligibilityStatus {
  if (params.disabled) return "blocked";
  if (
    params.accountStatus === "pendingDeletion" ||
    params.accountStatus === "deletionInProgress"
  ) {
    return "accountRecoveryRequired";
  }
  if (
    params.accountStatus === "restricted" ||
    params.accountStatus === "hardBanned"
  ) {
    return "blocked";
  }
  if (!params.hasPublicProfile || !params.hasPrivateProfile) {
    return "incompleteSignup";
  }
  return "active";
}
