import {normalizeUsername, validateNormalizedUsername} from "./username";

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function displayNameFromPublicUser(user: Record<string, unknown>): string {
  return asTrimmedString(user.displayName || user.name || user.username);
}

function hasPersistedLocation(user: Record<string, unknown>): boolean {
  const state = asTrimmedString(user.state);
  const city = asTrimmedString(user.city);
  if (state.length > 0 && city.length > 0) {
    return true;
  }
  if (asTrimmedString(user.address).length > 0) {
    return true;
  }
  if (asTrimmedString(user.location).length > 0) {
    return true;
  }
  return false;
}

export function isPersistedCompletedAccount(params: {
  uid: string;
  publicUser: Record<string, unknown> | null | undefined;
}): boolean {
  const user = params.publicUser ?? {};
  if (asTrimmedString(user.uid) !== asTrimmedString(params.uid)) {
    return false;
  }
  if (asTrimmedString(user.role).length === 0) {
    return false;
  }
  if (displayNameFromPublicUser(user).length === 0) {
    return false;
  }
  if (!hasPersistedLocation(user)) {
    return false;
  }

  const normalizedUsername = normalizeUsername(
    asTrimmedString(user.usernameLowercase || user.username),
  );
  return validateNormalizedUsername(normalizedUsername) == null;
}
