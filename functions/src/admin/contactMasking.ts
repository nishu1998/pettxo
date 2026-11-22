/**
 * Contact masking for admin surfaces.
 *
 * maskPhone / maskEmail / normalizeIndianPhone are exact ports of the admin
 * dashboard's helpers (pettxo-admin-dashboard lib/core/formatting/
 * phone_mask.dart and email_mask.dart) so that values masked on the server
 * look identical to what the dashboard shows today. Keep them in sync: the
 * unit tests copy the dashboard's test cases.
 */

const PHONE_SEPARATORS = /[\s\-()]/g;

/**
 * `+919000000001` → `+91 90•••• •001`. Other numbers keep the leading `+`,
 * one or two country digits and the last 3 digits. Anything unrecognisable
 * becomes `•••`.
 */
export function maskPhone(raw: string | null | undefined): string {
  if (raw == null) return "•••";
  const compact = raw.replace(PHONE_SEPARATORS, "");
  if (!/^\+?\d{6,15}$/.test(compact)) return "•••";
  const digits = compact.replace(/\+/g, "");
  if (digits.length === 12 && digits.startsWith("91")) {
    const national = digits.substring(2);
    return `+91 ${national.substring(0, 2)}•••• •${national.substring(7)}`;
  }
  if (digits.length === 10 && !compact.startsWith("+")) {
    return `+91 ${digits.substring(0, 2)}•••• •${digits.substring(7)}`;
  }
  const last = digits.substring(digits.length - 3);
  if (compact.startsWith("+") && digits.length > 6) {
    const country = digits.substring(0, digits.length >= 11 ? 2 : 1);
    return `+${country} ••••••${last}`;
  }
  return `••••••${last}`;
}

/**
 * Normalises admin input into an E.164 Indian number for an exact match on
 * `userPrivate` phone fields. Returns null when the input is not a phone.
 */
export function normalizeIndianPhone(input: string): string | null {
  const compact = input.trim().replace(PHONE_SEPARATORS, "");
  if (!/^\+?\d+$/.test(compact)) return null;
  const hasPlus = compact.startsWith("+");
  const digits = compact.replace(/\+/g, "");
  if (hasPlus) return digits.length >= 10 && digits.length <= 15 ? `+${digits}` : null;
  if (digits.length === 10) return `+91${digits}`;
  if (digits.length === 11 && digits.startsWith("0")) return `+91${digits.substring(1)}`;
  if (digits.length === 12 && digits.startsWith("91")) return `+${digits}`;
  return null;
}

/**
 * `asha@example.com` → `as***@example.com`; a one-letter name keeps nothing
 * (`r@x.in` → `***@x.in`). Anything that isn't an email becomes `•••`.
 */
export function maskEmail(raw: string | null | undefined): string {
  const value = (raw ?? "").trim();
  const at = value.lastIndexOf("@");
  if (at <= 0 || at === value.length - 1 || value.includes(" ")) return "•••";
  const name = value.substring(0, at);
  const domain = value.substring(at + 1);
  if (!domain.includes(".") || domain.startsWith(".") || domain.endsWith(".")) return "•••";
  const kept = name.length >= 2 ? name.substring(0, 2) : "";
  return `${kept}***@${domain}`;
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export type PhoneSource = "phoneNumber" | "phone" | "mobileNumber";

/** The dashboard's fallback order: phoneNumber, then phone, then mobileNumber. */
export function pickPrivatePhone(
  data: Record<string, unknown> | null | undefined,
): {value: string; source: PhoneSource} | null {
  if (!data) return null;
  for (const source of ["phoneNumber", "phone", "mobileNumber"] as const) {
    const value = text(data[source]);
    if (value) return {value, source};
  }
  return null;
}

export function pickPrivateEmail(data: Record<string, unknown> | null | undefined): string | null {
  const value = text(data?.email);
  return value || null;
}

/** Masked phone, or null when there is no value (not `•••`). */
export function maskPhoneOrNull(value: string | null | undefined): string | null {
  return value && value.trim() ? maskPhone(value) : null;
}

/** Masked email, or null when there is no value (not `•••`). */
export function maskEmailOrNull(value: string | null | undefined): string | null {
  return value && value.trim() ? maskEmail(value) : null;
}

const EMAIL_PATTERN = /[^\s@]+@[^\s@]+\.[^\s@]+/g;
const PHONE_LIKE_PATTERN = /\+?\d[\d\s().-]{6,}\d/g;

/**
 * True when a string contains something that looks like a raw phone number
 * (10 or more digits in one run of digits and separators) or a raw email.
 * Masked forms pass: masked phones keep at most 4 digits together, and masked
 * emails have a local part that ends in `***`.
 */
export function containsRawContact(value: string): boolean {
  for (const match of value.matchAll(PHONE_LIKE_PATTERN)) {
    if (match[0].replace(/\D/g, "").length >= 10) return true;
  }
  for (const match of value.matchAll(EMAIL_PATTERN)) {
    const local = match[0].substring(0, match[0].lastIndexOf("@"));
    if (!local.endsWith("***")) return true;
  }
  return false;
}
