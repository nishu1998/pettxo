import type {AuthEmailMessage} from "./authEmailTransport";
import {
  renderWelcomeEmail,
  welcomeEmailSubject,
} from "./authEmailTemplates";

export interface WelcomeAuthUser {
  uid: string;
  email?: string;
  displayName?: string;
}

export interface WelcomeProfile {
  displayName?: string;
  name?: string;
}

export type WelcomeReservation =
  | {decision: "send"; leaseId: string; idempotencyKey: string}
  | {decision: "sent"}
  | {decision: "busy"}
  | {decision: "skippedNoEmail"};

export interface WelcomeEmailDependencies {
  getAuthUser(uid: string): Promise<WelcomeAuthUser | null>;
  reserveDelivery(uid: string, recipientEmail: string): Promise<WelcomeReservation>;
  recordNoEmail(uid: string): Promise<void>;
  recordMissingAuthUser(uid: string): Promise<void>;
  markSent(uid: string, leaseId: string): Promise<void>;
  markRetryableFailure(uid: string, leaseId: string, error: unknown): Promise<void>;
  sendEmail(message: AuthEmailMessage, idempotencyKey: string): Promise<void>;
}

export type WelcomeEmailResult =
  | "sent"
  | "alreadySent"
  | "skippedNoEmail"
  | "skippedMissingAuthUser";

function trimmed(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function resolveWelcomeName(
  profile: WelcomeProfile,
  authDisplayName: string | undefined,
): string {
  return (
    trimmed(profile.displayName) ||
    trimmed(profile.name) ||
    trimmed(authDisplayName) ||
    "there"
  ).slice(0, 100);
}

export async function handleCanonicalUserCreated(
  uid: string,
  profile: WelcomeProfile,
  dependencies: WelcomeEmailDependencies,
): Promise<WelcomeEmailResult> {
  const authUser = await dependencies.getAuthUser(uid);
  if (!authUser) {
    await dependencies.recordMissingAuthUser(uid);
    return "skippedMissingAuthUser";
  }

  const email = trimmed(authUser.email);
  if (!email) {
    await dependencies.recordNoEmail(uid);
    return "skippedNoEmail";
  }

  const reservation = await dependencies.reserveDelivery(uid, email);
  if (reservation.decision === "sent" || reservation.decision === "skippedNoEmail") {
    return reservation.decision === "sent" ? "alreadySent" : "skippedNoEmail";
  }
  if (reservation.decision === "busy") {
    throw new Error("welcome_email_delivery_in_progress");
  }

  const name = resolveWelcomeName(profile, authUser.displayName);
  try {
    await dependencies.sendEmail(
      {
        to: email,
        subject: welcomeEmailSubject(name),
        html: renderWelcomeEmail({name}),
      },
      reservation.idempotencyKey,
    );
    await dependencies.markSent(uid, reservation.leaseId);
    return "sent";
  } catch (error) {
    try {
      await dependencies.markRetryableFailure(uid, reservation.leaseId, error);
    } catch {
      // The trigger retry and lease expiry recover if failure recording fails.
    }
    throw error;
  }
}
