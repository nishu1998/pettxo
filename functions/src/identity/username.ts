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

type AuthenticatedUsernameClaimant = {
  uid: string;
  email?: string | null;
  emailVerified?: boolean;
};

export type UsernameReservationStatus =
  | "available"
  | "owned"
  | "taken"
  | "staleReservation";

const protectedUsernameOwners = new Map([
  [
    "pettxo",
    {
      uid: "Yo5HtRbusBNl9NkPhelXp5naNF93",
      email: "hello@pettxo.com",
    },
  ],
]);

export function normalizeUsername(value: unknown): string {
  return typeof value === "string" ?
    value.trim().replaceAll("@", "").toLowerCase() :
    "";
}

export function isReservedUsername(value: string): boolean {
  return reservedUsernames.has(value);
}

export function canClaimProtectedUsername(
  username: string,
  claimant: AuthenticatedUsernameClaimant,
): boolean {
  const owner = protectedUsernameOwners.get(username);
  if (!owner) return false;

  return claimant.uid === owner.uid &&
    claimant.emailVerified === true &&
    (claimant.email ?? "").trim().toLowerCase() === owner.email;
}

export function classifyUsernameReservation(params: {
  requestingUid: string;
  requestedUsername: string;
  reservationExists: boolean;
  reservationUid: string;
  ownerExists: boolean;
  ownerUsername: string;
}): UsernameReservationStatus {
  if (!params.reservationExists) return "available";
  if (params.reservationUid === params.requestingUid) return "owned";
  if (!params.reservationUid) return "staleReservation";
  if (
    params.ownerExists &&
    params.ownerUsername === params.requestedUsername
  ) {
    return "taken";
  }
  return "staleReservation";
}

export function usernameReservationConflicts(params: {
  reservationExists: boolean;
  reservationUid: string;
  requestingUid: string;
}): boolean {
  return params.reservationExists &&
    params.reservationUid !== params.requestingUid;
}

export function validateNormalizedUsername(
  value: string,
  options: {allowReserved?: boolean} = {},
): string | null {
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

  if (!options.allowReserved && isReservedUsername(value)) {
    return "This username is reserved.";
  }

  return null;
}
