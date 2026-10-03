import {createHash} from "node:crypto";

export const PROMO_CODE_MIN_LENGTH = 3;
export const PROMO_CODE_MAX_LENGTH = 32;
export const PROMO_CODE_DEFINITION_MAX_LENGTH = 20;
const PROMO_CODE_PATTERN = /^[A-Z0-9][A-Z0-9_-]{2,31}$/;

export class PromoCodeValidationError extends Error {
  constructor(message = "Promo code is invalid.") {
    super(message);
    this.name = "PromoCodeValidationError";
  }
}

export function normalizePromoCode(value: unknown): string {
  if (typeof value !== "string") throw new PromoCodeValidationError();
  const normalized = value.normalize("NFKC").trim().toUpperCase();
  if (!PROMO_CODE_PATTERN.test(normalized)) {
    throw new PromoCodeValidationError();
  }
  return normalized;
}

export function normalizePromoCodeForDefinition(value: unknown): string {
  const normalized = normalizePromoCode(value);
  if (normalized.length > PROMO_CODE_DEFINITION_MAX_LENGTH) {
    throw new PromoCodeValidationError();
  }
  return normalized;
}

export function promoCodeHash(normalizedCode: string): string {
  return createHash("sha256").update(normalizedCode, "utf8").digest("hex");
}

export function promoCodeAuditId(normalizedCode: string): string {
  return promoCodeHash(normalizedCode).slice(0, 12);
}
