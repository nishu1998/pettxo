export const offerWallAudienceValues = [
  "allUsers",
  "petParent",
  "petLover",
  "serviceProvider",
] as const;

export type OfferWallAudience = typeof offerWallAudienceValues[number];

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function isOfferWallAudience(value: string): value is OfferWallAudience {
  return offerWallAudienceValues.includes(value as OfferWallAudience);
}

export function normalizeOfferWallAudiences(
  value: unknown,
): OfferWallAudience[] {
  if (!Array.isArray(value)) {
    throw new Error("audiences must be an array.");
  }

  const normalized: OfferWallAudience[] = [];
  for (const entry of value) {
    const audience = asTrimmedString(entry);
    if (!isOfferWallAudience(audience)) {
      throw new Error(`Unsupported audience "${audience}".`);
    }
    if (audience === "allUsers") {
      return ["allUsers"];
    }
    if (!normalized.includes(audience)) {
      normalized.push(audience);
    }
  }

  if (normalized.length === 0) {
    throw new Error("At least one audience is required.");
  }

  normalized.sort();
  return normalized;
}

export function matchesOfferWallAudience(params: {
  audiences: OfferWallAudience[];
  role: string;
}): boolean {
  if (params.audiences.includes("allUsers")) return true;
  return isOfferWallAudience(params.role) && params.audiences.includes(params.role);
}
