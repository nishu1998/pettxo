import type {Firestore, Transaction} from "firebase-admin/firestore";
import {FieldValue} from "firebase-admin/firestore";

/** Server-only rate-limit docs: adminRateLimits/{adminUid}_{bucket} (rules: deny-all). */
export const ADMIN_RATE_LIMITS_COLLECTION = "adminRateLimits";

export type RateLimitBucket = "contactReveal" | "contactSearch";

export type RateLimits = {perHour: number; perDay: number};

/** Owner decision Q3: 20 per hour and 100 per day per admin. */
export const CONTACT_REVEAL_LIMITS: RateLimits = {perHour: 20, perDay: 100};
/** Contact search has its own bucket with the same limits. */
export const CONTACT_SEARCH_LIMITS: RateLimits = {perHour: 20, perDay: 100};

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

export type RateLimitDecision = {
  allowed: boolean;
  retryAfterSeconds: number;
  /** Events still inside the day window, plus `nowMs` when allowed. */
  nextEvents: number[];
  /** Events in the hour window after this one (when allowed). */
  hourCount: number;
  dayCount: number;
};

/** Pure sliding-window decision over a list of event times (ms). */
export function evaluateRateLimit(events: unknown, nowMs: number, limits: RateLimits): RateLimitDecision {
  const list = Array.isArray(events) ?
    events.filter((value): value is number => typeof value === "number" && Number.isFinite(value)) :
    [];
  const inDay = list.filter((time) => time > nowMs - DAY_MS && time <= nowMs).sort((a, b) => a - b);
  const inHour = inDay.filter((time) => time > nowMs - HOUR_MS);
  let retryAfterMs = 0;
  if (inHour.length >= limits.perHour) {
    retryAfterMs = Math.max(retryAfterMs, inHour[inHour.length - limits.perHour] + HOUR_MS - nowMs);
  }
  if (inDay.length >= limits.perDay) {
    retryAfterMs = Math.max(retryAfterMs, inDay[inDay.length - limits.perDay] + DAY_MS - nowMs);
  }
  if (retryAfterMs > 0) {
    return {
      allowed: false,
      retryAfterSeconds: Math.max(1, Math.ceil(retryAfterMs / 1000)),
      nextEvents: inDay,
      hourCount: inHour.length,
      dayCount: inDay.length,
    };
  }
  return {
    allowed: true,
    retryAfterSeconds: 0,
    nextEvents: [...inDay, nowMs],
    hourCount: inHour.length + 1,
    dayCount: inDay.length + 1,
  };
}

export function rateLimitRef(firestore: Firestore, adminUid: string, bucket: RateLimitBucket) {
  return firestore.collection(ADMIN_RATE_LIMITS_COLLECTION).doc(`${adminUid}_${bucket}`);
}

/**
 * Reads the bucket inside `transaction` and decides. Nothing is written here;
 * call recordRateLimitInTransaction after the other reads to record an event.
 */
export async function readRateLimitInTransaction(params: {
  transaction: Transaction;
  firestore: Firestore;
  adminUid: string;
  bucket: RateLimitBucket;
  limits: RateLimits;
  nowMs: number;
}): Promise<RateLimitDecision> {
  const ref = rateLimitRef(params.firestore, params.adminUid, params.bucket);
  const snapshot = await params.transaction.get(ref);
  return evaluateRateLimit(snapshot.data()?.events, params.nowMs, params.limits);
}

export function recordRateLimitInTransaction(params: {
  transaction: Transaction;
  firestore: Firestore;
  adminUid: string;
  bucket: RateLimitBucket;
  decision: RateLimitDecision;
}): void {
  params.transaction.set(rateLimitRef(params.firestore, params.adminUid, params.bucket), {
    adminUid: params.adminUid,
    bucket: params.bucket,
    events: params.decision.nextEvents,
    updatedAt: FieldValue.serverTimestamp(),
  });
}
