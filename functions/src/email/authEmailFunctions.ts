import {createHash} from "crypto";
import type {UserRecord} from "firebase-admin/auth";
import {onCall} from "firebase-functions/v2/https";
import {RESEND_API_KEY} from "../config/secrets";
import {auth, db} from "../shared/firebase";
import {
  handleRequestEmailChangeV2,
  handleRequestPasswordResetV2,
  handleSendVerificationEmailV2,
  type AuthEmailDependencies,
  type AuthEmailProfile,
  type AuthEmailUser,
} from "./authEmailApplication";
import {
  authEmailRateLimitKey,
  reserveAuthEmailCooldown,
} from "./authEmailRateLimit";
import {sendAuthEmail} from "./authEmailTransport";

function toAuthEmailUser(user: UserRecord): AuthEmailUser {
  return {
    uid: user.uid,
    email: user.email,
    emailVerified: user.emailVerified,
    disabled: user.disabled,
    displayName: user.displayName,
    providerIds: user.providerData.map((provider) => provider.providerId),
  };
}

function profileData(value: unknown): AuthEmailProfile {
  if (typeof value !== "object" || value === null) return {};
  const data = value as Record<string, unknown>;
  return {
    displayName:
      typeof data.displayName === "string" ? data.displayName : undefined,
    name: typeof data.name === "string" ? data.name : undefined,
    accountStatus:
      typeof data.accountStatus === "string" ? data.accountStatus : undefined,
  };
}

function buildDependencies(): AuthEmailDependencies {
  return {
    async getUserByUid(uid) {
      try {
        return toAuthEmailUser(await auth.getUser(uid));
      } catch (error) {
        const code = (error as {code?: string}).code;
        if (code === "auth/user-not-found") return null;
        throw error;
      }
    },
    async getUserByEmail(email) {
      try {
        return toAuthEmailUser(await auth.getUserByEmail(email));
      } catch (error) {
        const code = (error as {code?: string}).code;
        if (code === "auth/user-not-found") return null;
        throw error;
      }
    },
    async getProfiles(uid) {
      const [publicSnapshot, privateSnapshot] = await Promise.all([
        db.collection("users").doc(uid).get(),
        db.collection("userPrivate").doc(uid).get(),
      ]);
      return {
        publicProfile: profileData(publicSnapshot.data()),
        privateProfile: profileData(privateSnapshot.data()),
      };
    },
    reserveVerificationCooldown(uid, email) {
      const key = authEmailRateLimitKey(`${uid}:${email}`);
      return reserveAuthEmailCooldown("verificationEmailRequests", key);
    },
    reservePasswordResetCooldown(email) {
      const key = authEmailRateLimitKey(email);
      return reserveAuthEmailCooldown("passwordResetV2Requests", key);
    },
    reserveEmailChangeCooldown(uid) {
      const key = authEmailRateLimitKey(uid);
      return reserveAuthEmailCooldown("emailChangeV2Requests", key);
    },
    generateVerificationLink(email) {
      return auth.generateEmailVerificationLink(email);
    },
    generatePasswordResetLink(email) {
      return auth.generatePasswordResetLink(email);
    },
    generateVerifyAndChangeEmailLink(currentEmail, newEmail) {
      return auth.generateVerifyAndChangeEmailLink(currentEmail, newEmail);
    },
    sendEmail(message) {
      return sendAuthEmail(RESEND_API_KEY.value(), message);
    },
    reportPasswordResetFailure(stage, normalizedEmail, error) {
      const emailHashPrefix = createHash("sha256")
        .update(normalizedEmail)
        .digest("hex")
        .slice(0, 12);
      console.error("Password reset V2 processing failed", {
        stage,
        emailHashPrefix,
        errorCode: (error as {code?: string}).code ?? "unknown",
      });
    },
  };
}

export const sendVerificationEmailV2 = onCall(
  {
    invoker: "public",
    region: "asia-south1",
    secrets: [RESEND_API_KEY],
  },
  (request) =>
    handleSendVerificationEmailV2(request.auth?.uid, buildDependencies()),
);

export const requestPasswordResetV2 = onCall(
  {
    invoker: "public",
    region: "asia-south1",
    secrets: [RESEND_API_KEY],
  },
  (request) => handleRequestPasswordResetV2(request.data, buildDependencies()),
);

export const requestEmailChangeV2 = onCall(
  {
    invoker: "public",
    region: "asia-south1",
    secrets: [RESEND_API_KEY],
  },
  (request) =>
    handleRequestEmailChangeV2(
      request.data,
      request.auth ? {
        uid: request.auth.uid,
        email:
          typeof request.auth.token.email === "string" ?
            request.auth.token.email :
            undefined,
        authTimeSeconds:
          typeof request.auth.token.auth_time === "number" ?
            request.auth.token.auth_time :
            undefined,
      } : undefined,
      buildDependencies(),
    ),
);
