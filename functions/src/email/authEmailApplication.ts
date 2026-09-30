import {HttpsError} from "firebase-functions/v2/https";
import {
  evaluatePasswordResetEligibility,
  normalizePasswordResetEmail,
  validatePasswordResetEmail,
} from "../passwordReset";
import type {AuthEmailMessage} from "./authEmailTransport";
import {
  passwordResetEmailSubject,
  renderPasswordResetEmail,
  renderVerificationEmail,
  verificationEmailSubject,
} from "./authEmailTemplates";

export interface AuthEmailUser {
  uid: string;
  email?: string;
  emailVerified: boolean;
  disabled: boolean;
  displayName?: string;
  providerIds: string[];
}

export interface AuthEmailProfile {
  displayName?: string;
  name?: string;
  accountStatus?: string;
}

export interface AuthEmailDependencies {
  getUserByUid(uid: string): Promise<AuthEmailUser | null>;
  getUserByEmail(email: string): Promise<AuthEmailUser | null>;
  getProfiles(uid: string): Promise<{
    publicProfile: AuthEmailProfile;
    privateProfile: AuthEmailProfile;
  }>;
  reserveVerificationCooldown(uid: string, email: string): Promise<boolean>;
  reservePasswordResetCooldown(email: string): Promise<boolean>;
  generateVerificationLink(email: string): Promise<string>;
  generatePasswordResetLink(email: string): Promise<string>;
  sendEmail(message: AuthEmailMessage): Promise<void>;
  reportPasswordResetFailure(
    stage: string,
    normalizedEmail: string,
    error: unknown,
  ): void;
}

const genericSuccess = Object.freeze({success: true});

function trimmed(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function resolveAuthEmailDisplayName(
  publicProfile: AuthEmailProfile,
  authDisplayName: string | undefined,
): string {
  return (
    trimmed(publicProfile.displayName) ||
    trimmed(publicProfile.name) ||
    trimmed(authDisplayName) ||
    "there"
  ).slice(0, 100);
}

export async function handleSendVerificationEmailV2(
  authUid: string | undefined,
  dependencies: AuthEmailDependencies,
): Promise<{success: true}> {
  if (!authUid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  let user: AuthEmailUser | null;
  try {
    user = await dependencies.getUserByUid(authUid);
  } catch {
    throw new HttpsError(
      "unavailable",
      "Unable to send a verification email right now.",
    );
  }
  if (!user) {
    throw new HttpsError("failed-precondition", "Account is unavailable.");
  }
  const email = trimmed(user.email);
  if (!email) {
    throw new HttpsError(
      "failed-precondition",
      "This account does not have an email address.",
    );
  }
  if (user.emailVerified) return genericSuccess;

  let cooldownReserved: boolean;
  try {
    cooldownReserved = await dependencies.reserveVerificationCooldown(
      user.uid,
      email.toLowerCase(),
    );
  } catch {
    throw new HttpsError(
      "unavailable",
      "Unable to send a verification email right now.",
    );
  }
  if (!cooldownReserved) {
    throw new HttpsError(
      "resource-exhausted",
      "Please wait before requesting another verification email.",
    );
  }

  try {
    const {publicProfile} = await dependencies.getProfiles(user.uid);
    const name = resolveAuthEmailDisplayName(publicProfile, user.displayName);
    const actionLink = await dependencies.generateVerificationLink(email);
    await dependencies.sendEmail({
      to: email,
      subject: verificationEmailSubject,
      html: renderVerificationEmail({name, email, actionLink}),
    });
    return genericSuccess;
  } catch {
    throw new HttpsError(
      "unavailable",
      "Unable to send a verification email right now.",
    );
  }
}

export async function handleRequestPasswordResetV2(
  data: unknown,
  dependencies: AuthEmailDependencies,
): Promise<{success: true}> {
  const rawEmail =
    typeof data === "object" && data !== null && "email" in data ?
      (data as {email?: unknown}).email :
      undefined;
  const normalizedEmail = normalizePasswordResetEmail(rawEmail);
  const validationError = validatePasswordResetEmail(normalizedEmail);
  if (validationError) {
    throw new HttpsError("invalid-argument", validationError);
  }

  try {
    const reserved = await dependencies.reservePasswordResetCooldown(
      normalizedEmail,
    );
    if (!reserved) return genericSuccess;

    const user = await dependencies.getUserByEmail(normalizedEmail);
    if (!user) return genericSuccess;

    const {publicProfile, privateProfile} = await dependencies.getProfiles(
      user.uid,
    );
    const accountStatus =
      trimmed(privateProfile.accountStatus) ||
      trimmed(publicProfile.accountStatus);
    const eligibility = evaluatePasswordResetEligibility({
      providerIds: user.providerIds,
      disabled: user.disabled,
      accountStatus,
    });
    if (eligibility !== "approved") return genericSuccess;

    const name = resolveAuthEmailDisplayName(publicProfile, user.displayName);
    const actionLink = await dependencies.generatePasswordResetLink(
      normalizedEmail,
    );
    await dependencies.sendEmail({
      to: normalizedEmail,
      subject: passwordResetEmailSubject,
      html: renderPasswordResetEmail({
        name,
        email: normalizedEmail,
        actionLink,
      }),
    });
  } catch (error) {
    dependencies.reportPasswordResetFailure(
      "request",
      normalizedEmail,
      error,
    );
  }

  return genericSuccess;
}
