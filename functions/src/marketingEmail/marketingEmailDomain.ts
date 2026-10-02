import {createHash} from "crypto";
import {HttpsError} from "firebase-functions/v2/https";

export const signupTermsCommunicationsPolicyVersion = "terms_communications_v1";

export type SignupTermsCommunicationsContract = "legacy" | "current";

export function resolveSignupTermsCommunicationsContract(
  payload: unknown,
): SignupTermsCommunicationsContract {
  const data = payload && typeof payload === "object" && !Array.isArray(payload) ?
    payload as Record<string, unknown> : {};
  if (!Object.prototype.hasOwnProperty.call(data, "termsCommunicationsPolicyVersion")) {
    return "legacy";
  }
  const suppliedVersion = typeof data.termsCommunicationsPolicyVersion === "string" ?
    data.termsCommunicationsPolicyVersion.trim() : "";
  if (suppliedVersion === signupTermsCommunicationsPolicyVersion) return "current";
  throw new HttpsError("failed-precondition", "Current Terms & Communications acceptance is required.", {
    appCode: "legal-acceptance-required",
  });
}

export type MarketingEmailPreferenceSource =
  | "signup"
  | "settings"
  | "unsubscribe"
  | "preproduction_test_migration";

export function marketingEmailPreferencePatch(
  enabled: boolean,
  source: MarketingEmailPreferenceSource,
  updatedAt: unknown,
): Record<string, unknown> {
  return {
    marketingEmailEnabled: enabled,
    marketingEmailPreferenceSource: source,
    marketingEmailPreferenceUpdatedAt: updatedAt,
  };
}

export function signupMarketingEmailPreferencePatch(
  privateProfile: Record<string, unknown>,
  acceptedPolicyVersion: string,
  updatedAt: unknown,
): Record<string, unknown> {
  if (acceptedPolicyVersion !== signupTermsCommunicationsPolicyVersion) {
    throw new HttpsError("failed-precondition", "Current Terms & Communications acceptance is required.", {
      appCode: "legal-acceptance-required",
    });
  }
  if (typeof privateProfile.marketingEmailEnabled === "boolean") return {};
  return {
    ...marketingEmailPreferencePatch(true, "signup", updatedAt),
    marketingEmailSignupPolicyVersion: signupTermsCommunicationsPolicyVersion,
  };
}

export const marketingCampaignStatuses = [
  "DRAFT", "SCHEDULED", "QUEUED", "SENDING", "COMPLETED", "FAILED", "CANCELLED",
] as const;
export type MarketingCampaignStatus = typeof marketingCampaignStatuses[number];

export const marketingAudienceModes = [
  "all", "role", "state", "city", "roleState", "roleCity", "selected",
] as const;
export type MarketingAudienceMode = typeof marketingAudienceModes[number];

export type MarketingContent = {
  subject: string;
  preheader: string;
  heading: string;
  body: string;
  imageUrl: string;
  ctaText: string;
  ctaDestination: string;
};

export type MarketingAudience = {
  mode: MarketingAudienceMode;
  role: string;
  state: string;
  city: string;
  selectedUids: string[];
};

export type MarketingCampaignInput = {
  internalName: string;
  content: MarketingContent;
  audience: MarketingAudience;
};

export type MarketingEligibilityInput = {
  profileExists: boolean;
  profile: Record<string, unknown>;
  privateProfile: Record<string, unknown>;
  authUser: {email?: string | null; disabled?: boolean} | null;
  audience: MarketingAudience;
  uid: string;
};

export type MarketingEligibility =
  | {category: "notMatched"}
  | {category: "noCanonicalEmail"}
  | {category: "marketingOptedOut"}
  | {category: "otherExclusion"}
  | {category: "eligible"; email: string};

export function assertMarketingAdminRole(uid: string, role: string): void {
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to continue.", {appCode: "UNAUTHORIZED"});
  }
  if (role !== "superAdmin") {
    throw new HttpsError("permission-denied", "Super Admin access required.", {appCode: "UNAUTHORIZED"});
  }
}

export function canTransitionMarketingCampaign(from: MarketingCampaignStatus, to: MarketingCampaignStatus): boolean {
  return (
    (from === "DRAFT" && (to === "SCHEDULED" || to === "QUEUED")) ||
    (from === "SCHEDULED" && (to === "QUEUED" || to === "CANCELLED")) ||
    (from === "QUEUED" && to === "SENDING") ||
    (from === "SENDING" && (to === "QUEUED" || to === "COMPLETED" || to === "FAILED"))
  );
}

function string(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function requiredText(value: unknown, name: string, max: number): string {
  const result = string(value);
  if (!result) throw validation(`${name} is required.`);
  if (result.length > max) throw validation(`${name} is too long.`);
  if (/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/.test(result)) {
    throw validation(`${name} contains unsupported control characters.`);
  }
  return result;
}

function requiredSingleLine(value: unknown, name: string, max: number): string {
  const result = requiredText(value, name, max);
  if (/[\r\n]/.test(result)) throw validation(`${name} must be one line.`);
  return result;
}

function optionalText(value: unknown, name: string, max: number): string {
  const result = string(value);
  if (result.length > max) throw validation(`${name} is too long.`);
  if (/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/.test(result)) {
    throw validation(`${name} contains unsupported control characters.`);
  }
  return result;
}

function optionalSingleLine(value: unknown, name: string, max: number): string {
  const result = optionalText(value, name, max);
  if (/[\r\n]/.test(result)) throw validation(`${name} must be one line.`);
  return result;
}

function validation(message: string): HttpsError {
  return new HttpsError("invalid-argument", message, {appCode: "INVALID_CAMPAIGN_CONTENT"});
}

function validHttpsUrl(value: string, name: string): URL {
  let url: URL;
  try {
    url = new URL(value);
  } catch (_) {
    throw validation(`${name} must be a valid HTTPS URL.`);
  }
  if (url.protocol !== "https:") throw validation(`${name} must use HTTPS.`);
  return url;
}

function validateImageUrl(value: string): string {
  if (!value) return "";
  const url = validHttpsUrl(value, "content.imageUrl");
  const approvedHost = url.hostname === "firebasestorage.googleapis.com";
  const approvedBucket = url.pathname.startsWith(
    "/v0/b/pettexo-d9409.firebasestorage.app/o/marketingCampaigns%2F",
  );
  if (!approvedHost || !approvedBucket) {
    throw validation("content.imageUrl must reference the Pettxo marketing campaign storage path.");
  }
  return url.toString();
}

export function normalizeMarketingContent(value: unknown): MarketingContent {
  const data = value && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> : {};
  const ctaText = optionalSingleLine(data.ctaText, "content.ctaText", 80);
  const ctaDestination = optionalText(data.ctaDestination, "content.ctaDestination", 2048);
  if ((ctaText.length > 0) !== (ctaDestination.length > 0)) {
    throw validation("CTA text and destination must be supplied together.");
  }
  if (ctaDestination) validHttpsUrl(ctaDestination, "content.ctaDestination");
  return {
    subject: requiredSingleLine(data.subject, "content.subject", 160),
    preheader: optionalSingleLine(data.preheader, "content.preheader", 200),
    heading: requiredSingleLine(data.heading, "content.heading", 180),
    body: requiredText(data.body, "content.body", 10000),
    imageUrl: validateImageUrl(optionalText(data.imageUrl, "content.imageUrl", 2048)),
    ctaText,
    ctaDestination,
  };
}

export function normalizeMarketingAudience(value: unknown): MarketingAudience {
  const data = value && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> : {};
  const mode = string(data.mode) as MarketingAudienceMode;
  if (!marketingAudienceModes.includes(mode)) {
    throw new HttpsError("invalid-argument", "Audience mode is invalid.", {appCode: "INVALID_AUDIENCE"});
  }
  const role = string(data.role);
  if (role && role !== "petParent" && role !== "serviceProvider") {
    throw new HttpsError("invalid-argument", "Audience role is invalid.", {appCode: "INVALID_AUDIENCE"});
  }
  const state = string(data.state);
  const city = string(data.city);
  const rawUids = Array.isArray(data.selectedUids) ? data.selectedUids : [];
  if (rawUids.some((item) => typeof item !== "string")) {
    throw new HttpsError("invalid-argument", "Selected users must be UIDs.", {appCode: "INVALID_AUDIENCE"});
  }
  const selectedUids = [...new Set(rawUids.map(string).filter(Boolean))];
  if (selectedUids.some((uid) => !/^[A-Za-z0-9:_-]{1,128}$/.test(uid))) {
    throw new HttpsError("invalid-argument", "Selected users must contain valid Pettxo UIDs.", {appCode: "INVALID_AUDIENCE"});
  }
  if (selectedUids.length > 500) {
    throw new HttpsError("invalid-argument", "At most 500 users may be selected.", {appCode: "INVALID_AUDIENCE"});
  }
  if ((mode === "role" || mode === "roleState" || mode === "roleCity") && !role) {
    throw new HttpsError("invalid-argument", "Audience role is required.", {appCode: "INVALID_AUDIENCE"});
  }
  if ((mode === "state" || mode === "roleState") && !state) {
    throw new HttpsError("invalid-argument", "Audience state is required.", {appCode: "INVALID_AUDIENCE"});
  }
  if ((mode === "city" || mode === "roleCity") && !city) {
    throw new HttpsError("invalid-argument", "Audience city is required.", {appCode: "INVALID_AUDIENCE"});
  }
  if (mode === "selected" && selectedUids.length === 0) {
    throw new HttpsError("invalid-argument", "Select at least one registered user.", {appCode: "INVALID_AUDIENCE"});
  }
  return {mode, role, state, city, selectedUids};
}

export function normalizeMarketingCampaignInput(value: unknown): MarketingCampaignInput {
  const data = value && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> : {};
  if ("email" in data || "emails" in data || "recipientEmail" in data || "recipientEmails" in data) {
    throw new HttpsError("invalid-argument", "Arbitrary recipient emails are not supported.", {appCode: "INVALID_AUDIENCE"});
  }
  return {
    internalName: requiredSingleLine(data.internalName, "internalName", 120),
    content: normalizeMarketingContent(data.content),
    audience: normalizeMarketingAudience(data.audience),
  };
}

export function marketingAudienceMatches(uid: string, profile: Record<string, unknown>, audience: MarketingAudience): boolean {
  const role = string(profile.role);
  const state = string(profile.state).toLocaleLowerCase();
  const city = string(profile.city).toLocaleLowerCase();
  switch (audience.mode) {
  case "all": return true;
  case "role": return role === audience.role;
  case "state": return state === audience.state.toLocaleLowerCase();
  case "city": return city === audience.city.toLocaleLowerCase();
  case "roleState": return role === audience.role && state === audience.state.toLocaleLowerCase();
  case "roleCity": return role === audience.role && city === audience.city.toLocaleLowerCase();
  case "selected": return audience.selectedUids.includes(uid);
  }
}

export function classifyMarketingEligibility(input: MarketingEligibilityInput): MarketingEligibility {
  if (!input.profileExists) {
    return input.audience.mode === "selected" && input.audience.selectedUids.includes(input.uid) ?
      {category: "otherExclusion"} : {category: "notMatched"};
  }
  if (!marketingAudienceMatches(input.uid, input.profile, input.audience)) {
    return {category: "notMatched"};
  }
  const publicStatus = string(input.profile.accountStatus);
  const privateStatus = string(input.privateProfile.accountStatus);
  if ([publicStatus, privateStatus].some((status) =>
    ["pendingDeletion", "deletionInProgress", "deleted", "restricted", "hardBanned"].includes(status)) ||
    input.privateProfile.scheduledDeletionAt != null || input.authUser?.disabled === true || !input.authUser) {
    return {category: "otherExclusion"};
  }
  const email = string(input.authUser.email).toLowerCase();
  if (!email) return {category: "noCanonicalEmail"};
  if (input.privateProfile.marketingEmailEnabled !== true) {
    return {category: "marketingOptedOut"};
  }
  return {category: "eligible", email};
}

export function stableMarketingId(prefix: string, ...parts: string[]): string {
  return `${prefix}_${createHash("sha256").update(parts.join("\u001f")).digest("hex").slice(0, 40)}`;
}

export function isMarketingUnsubscribeToken(value: string): boolean {
  // A 32-byte base64url token is exactly 43 characters without padding.
  return /^[A-Za-z0-9_-]{43}$/.test(value);
}

export function durableMarketingUnsubscribeUid(
  recordExists: boolean,
  data: Record<string, unknown>,
): string {
  if (!recordExists) return "";
  return typeof data.uid === "string" ? data.uid.trim() : "";
}

export function escapeMarketingHtml(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;").replace(/'/g, "&#39;");
}
