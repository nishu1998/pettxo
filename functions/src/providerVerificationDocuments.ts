export const PROVIDER_VERIFICATION_DOCUMENT_RETENTION_MS =
  30 * 24 * 60 * 60 * 1000;

export type ProviderVerificationCleanupReason =
  | "approved"
  | "rejected"
  | "resubmitted";

export function calculateProviderVerificationDocumentDeletionAtMillis(
  nowMs: number,
): number {
  return nowMs + PROVIDER_VERIFICATION_DOCUMENT_RETENTION_MS;
}

export function normalizeProviderVerificationDocumentPath(
  value: unknown,
): string {
  return typeof value === "string" ? value.trim() : "";
}

export function providerVerificationDocumentPathBelongsToUser(
  userId: string,
  path: string,
): boolean {
  const normalizedUserId = userId.trim();
  const normalizedPath = normalizeProviderVerificationDocumentPath(path);
  if (!normalizedUserId || !normalizedPath || normalizedPath.includes("..")) {
    return false;
  }
  const segments = normalizedPath.split("/");
  return segments.length === 4 &&
    segments[0] === "providerVerification" &&
    segments[1] === normalizedUserId &&
    segments[2] === "identity" &&
    segments[3].trim().length > 0;
}

export function collectProviderVerificationDocumentPaths(paths: unknown[]): string[] {
  const unique = new Set<string>();
  for (const candidate of paths) {
    const normalized = normalizeProviderVerificationDocumentPath(candidate);
    if (normalized) unique.add(normalized);
  }
  return [...unique];
}

export function diffProviderVerificationDocumentPaths(
  previousPaths: string[],
  currentPaths: string[],
): string[] {
  const current = new Set(collectProviderVerificationDocumentPaths(currentPaths));
  return collectProviderVerificationDocumentPaths(previousPaths)
    .filter((path) => !current.has(path));
}

export function cleanupReasonForVerificationStatus(
  status: string,
): ProviderVerificationCleanupReason | null {
  if (status === "approved") return "approved";
  if (status === "rejected") return "rejected";
  return null;
}
