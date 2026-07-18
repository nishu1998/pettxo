export const usernamePattern = /^[a-z0-9_.]{3,20}$/;
export const reservedUsernames = new Set([
  "admin",
  "administrator",
  "api",
  "auth",
  "help",
  "me",
  "notifications",
  "pettxo",
  "root",
  "security",
  "settings",
  "signin",
  "signup",
  "support",
  "system",
  "user",
  "username",
]);

export function normalizeUsername(value: unknown): string {
  return typeof value === "string" ?
    value.trim().replaceAll("@", "").toLowerCase() :
    "";
}

export function validateNormalizedUsername(value: string): string | null {
  if (!value) {
    return "Username is required.";
  }

  if (!usernamePattern.test(value)) {
    return "Username must be 3-20 characters using lowercase letters, numbers, dots, or underscores.";
  }

  if (value.startsWith(".") || value.endsWith(".")) {
    return "Username cannot start or end with a dot.";
  }

  if (value.includes("..")) {
    return "Username cannot contain consecutive dots.";
  }

  if (reservedUsernames.has(value)) {
    return "This username is reserved.";
  }

  return null;
}
