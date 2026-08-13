function normalizeCount(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ?
    Math.trunc(value) :
    0;
}

export function isOfferUsageExhausted(params: {
  usedCount: unknown;
  usageLimitPerUser: unknown;
}): boolean {
  const usageLimitPerUser = normalizeCount(params.usageLimitPerUser);
  if (usageLimitPerUser <= 0) {
    return false;
  }
  return normalizeCount(params.usedCount) >= usageLimitPerUser;
}

export function isOfferUsageAvailable(params: {
  usedCount: unknown;
  usageLimitPerUser: unknown;
}): boolean {
  return !isOfferUsageExhausted(params);
}
