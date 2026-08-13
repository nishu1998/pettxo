export const canonicalOfferUserRoles = [
  "petParent",
  "petLover",
  "serviceProvider",
] as const;

export type CanonicalOfferUserRole = typeof canonicalOfferUserRoles[number];

export type OfferAudience =
  | {type: "all"}
  | {type: "roles"; roles: CanonicalOfferUserRole[]};

export function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function isCanonicalOfferUserRole(
  value: string,
): value is CanonicalOfferUserRole {
  return canonicalOfferUserRoles.includes(value as CanonicalOfferUserRole);
}

export function normalizeOfferAudienceInput(
  value: unknown,
  options: {allowLegacyMissing?: boolean} = {},
): OfferAudience {
  const allowLegacyMissing = options.allowLegacyMissing !== false;
  if (value == null) {
    if (allowLegacyMissing) {
      return {type: "all"};
    }
    throw new Error("audience is required.");
  }

  if (typeof value !== "object" || Array.isArray(value)) {
    throw new Error("audience must be an object.");
  }

  const data = value as Record<string, unknown>;
  const type = asTrimmedString(data.type);

  if (!type) {
    if (allowLegacyMissing && Object.keys(data).length === 0) {
      return {type: "all"};
    }
    throw new Error("audience.type is required.");
  }

  if (type === "all") {
    return {type: "all"};
  }

  if (type !== "roles") {
    throw new Error("audience.type is invalid.");
  }

  if (!Array.isArray(data.roles)) {
    throw new Error("audience.roles must be an array for role audiences.");
  }

  const roles = data.roles.map(asTrimmedString);
  const normalizedRoles: CanonicalOfferUserRole[] = [];
  for (const role of roles) {
    if (!isCanonicalOfferUserRole(role)) {
      throw new Error(`audience.roles contains invalid role "${role}".`);
    }
    if (!normalizedRoles.includes(role)) {
      normalizedRoles.push(role);
    }
  }

  if (normalizedRoles.length === 0) {
    throw new Error("audience.roles must contain at least one valid role.");
  }

  normalizedRoles.sort();
  return {
    type: "roles",
    roles: normalizedRoles,
  };
}

export function serializeOfferAudience(
  audience: OfferAudience,
): Record<string, unknown> {
  if (audience.type === "all") {
    return {type: "all"};
  }
  return {
    type: "roles",
    roles: [...audience.roles],
  };
}

export function matchesOfferAudience(
  audience: OfferAudience,
  role: string,
): boolean {
  if (audience.type === "all") return true;
  const trimmedRole = asTrimmedString(role);
  return isCanonicalOfferUserRole(trimmedRole) &&
    audience.roles.includes(trimmedRole);
}
