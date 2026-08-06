import {FieldPath, FieldValue, Timestamp} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {db} from "../shared/firebase";

const DISCOVER_RANK_VERSION = 2;
const HOME_RANK_VERSION = 1;
const FEED_LOCATION_VERSION = 2;
const HOUR_MS = 60 * 60 * 1000;
const MAX_REPORT_PENALTY = 5;
const REPORT_PENALTY_PER_REPORT = 0.75;
const HOME_REPORT_PENALTY_PER_REPORT = 0.85;
const HOME_MAX_REPORT_PENALTY = 6;
const NEARBY_REPORT_PENALTY_PER_REPORT = 0.50;
const NEARBY_MAX_REPORT_PENALTY = 3;
const REFRESH_BATCH_SIZE = 100;
const BACKFILL_DEFAULT_LIMIT = 100;
const BACKFILL_MAX_LIMIT = 200;
const BACKFILL_AUTHOR_CACHE_LIMIT = 500;
const NEARBY_DEFAULT_LIMIT = 12;
const NEARBY_MAX_LIMIT = 20;
const NEARBY_MAX_CANDIDATES = 240;
const NEARBY_FRESH_POOL_LIMIT = 40;
const NEARBY_ENGAGED_POOL_LIMIT = 40;
const NEARBY_LOCAL_FRESH_POOL_LIMIT = 30;
const NEARBY_LOCAL_ENGAGED_POOL_LIMIT = 30;
const NEARBY_MAX_QUERIES = 12;
const NEARBY_SESSION_MAX_POSTS = 240;
const NEARBY_SESSION_TTL_MS = 30 * 60 * 1000;
const REFRESH_LOCK_PATH = "systemLocks/refreshSocialPostDiscoverScores";
const USER_PRIVATE_LOCATION_FIELD = "exploreLocation";
const SOCIAL_POST_PRIVATE_COLLECTION = "socialPostPrivate";
const NEARBY_FEED_SESSION_COLLECTION = "nearbyFeedSessions";
const NEARBY_RADIUS_TIERS_KM = [5, 15, 30, 50] as const;
const GEOHASH_BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";
const ADMIN_ROLES = new Set([
  "superAdmin",
  "customerSupportAdmin",
  "financeAdmin",
]);

type SocialPostSnapshot = Record<string, unknown>;

type NearbyLocationMetadata = {
  nearbyEligible: boolean;
  feedGeohash3: string;
  feedGeohash4: string;
  feedGeohash5: string;
  feedLocationVersion: number;
  feedCityKey: string;
  feedStateKey: string;
};

type PrivatePostLocationMetadata = {
  latitudeBucket: number;
  longitudeBucket: number;
  feedLocationVersion: number;
};

type FeedMetadata = NearbyLocationMetadata & {
  discoverScore: number;
  discoverRankVersion: number;
  discoverEligible: boolean;
  homeScore: number;
  homeRankVersion: number;
  homeEligible: boolean;
};

type DiscoverScoreBreakdown = {
  discoverEligible: boolean;
  weightedEngagement: number;
  engagementScore: number;
  freshnessMultiplier: number;
  newPostBaseline: number;
  reportPenalty: number;
  discoverScore: number;
};

type HomeScoreBreakdown = {
  homeEligible: boolean;
  weightedEngagement: number;
  engagementScore: number;
  freshnessMultiplier: number;
  newPostBaseline: number;
  adminBoost: number;
  reportPenalty: number;
  homeScore: number;
};

type NearbyScoreBreakdown = {
  nearbyEligible: boolean;
  weightedEngagement: number;
  engagementScore: number;
  freshnessMultiplier: number;
  newPostBaseline: number;
  distanceScore: number;
  reportPenalty: number;
  nearbyScore: number;
  distanceKm: number;
};

type RankingInputs = {
  likeCount: number;
  commentCount: number;
  shareCount: number;
  reportCount: number;
  visibilityStatus: string;
  moderationStatus: string;
  createdAtEpoch: number;
  authorCity: string;
  authorState: string;
  recentEngagementScore: number;
  adminPriorityBoost: number;
  isAdminPost: boolean;
  authorType: string;
};

type RefreshSummary = {
  scanned: number;
  updated: number;
  skipped: number;
  failed: number;
  durationMs: number;
  overlapSkipped: boolean;
};

type BackfillSummary = {
  scanned: number;
  updated: number;
  skipped: number;
  failed: number;
  privateLocationCreated: number;
  publicBucketsRemoved: number;
  alreadyMigrated: number;
  missingLocation: number;
  invalidLocation: number;
  nextCursor: string | null;
  hasMore: boolean;
  dryRun: boolean;
  uniqueAuthorsRead: number;
  authorCacheHits: number;
  authorCacheMisses: number;
  postsProcessed: number;
  reasonCounts?: Record<string, number>;
};

type HomeBackfillSummary = {
  scanned: number;
  updated: number;
  skipped: number;
  failed: number;
  nextCursor: string | null;
  hasMore: boolean;
  dryRun: boolean;
  reasonCounts?: Record<string, number>;
};

type PrivateLocationSnapshot = {
  latitude: number;
  longitude: number;
  city: string;
  state: string;
  country: string;
  geohash3: string;
  geohash4: string;
  geohash5: string;
};

type ViewerLocationContext =
  | {
      kind: "coordinates";
      latitude: number;
      longitude: number;
      cityKey: string;
      stateKey: string;
      geohash3: string;
      geohash4: string;
      geohash5: string;
    }
  | {
      kind: "fallback";
      cityKey: string;
      stateKey: string;
    }
  | {
      kind: "missing";
      cityKey: string;
      stateKey: string;
    };

type NearbyFeedCursor = {
  sessionId: string;
  offset: number;
};

type NearbyFeedPostResult = {
  id: string;
  nearbyDistanceKm: number | null;
  nearbyDistanceLabel: string;
  usesNearbyFallback: boolean;
  score: number;
  createdAtEpoch: number;
  data: Record<string, unknown>;
};

type NearbyFeedSessionPost = {
  id: string;
  nearbyDistanceKm: number | null;
  nearbyDistanceLabel: string;
  usesNearbyFallback: boolean;
};

type NearbyFeedSessionRecord = {
  ownerUid: string;
  rankingAsOfEpoch: number;
  activeRadiusKm: number | null;
  usedCityStateFallback: boolean;
  emptyStateReason: string | null;
  orderedPosts: NearbyFeedSessionPost[];
  expiresAt: Date | null;
};

type ViewerFilterContext = {
  blockedCreatorIds: Set<string>;
  mutedCreatorIds: Set<string>;
  creatorsWhoBlockedViewerIds: Set<string>;
};

type RequestAuthorVisibility = {
  publiclyVisible: boolean;
};

type RequestDiagnostics = {
  queriesExecuted: number;
  documentsRead: number;
  deduplicatedCandidates: number;
  rankedCandidates: number;
  filteredByBlocked: number;
  filteredByMuted: number;
  filteredByBlockedByCreator: number;
  filteredByVisibility: number;
  filteredByMissingPrivateLocation: number;
  filteredByRadius: number;
  filteredByDuplicate: number;
  radiusStages: number[];
  poolCounts: Record<string, number>;
};

type NearbyFeedResponse = {
  posts: Record<string, unknown>[];
  nextCursor: NearbyFeedCursor | null;
  hasMore: boolean;
  activeRadiusKm: number | null;
  usedCityStateFallback: boolean;
  emptyStateReason: string | null;
};

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asNumber(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  return 0;
}

function asInteger(value: unknown): number {
  return Math.trunc(asNumber(value));
}

function clampNonNegativeInteger(value: unknown): number {
  return Math.max(0, asInteger(value));
}

function normalizeLocationKey(value: unknown): string {
  return asTrimmedString(value).toLowerCase();
}

function roundScore(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return Math.round(value * 1_000_000) / 1_000_000;
}

function roundCoordinateBucket(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return Math.round(value * 100) / 100;
}

function isValidLatitude(value: number): boolean {
  return Number.isFinite(value) && value >= -90 && value <= 90;
}

function isValidLongitude(value: number): boolean {
  return Number.isFinite(value) && value >= -180 && value <= 180;
}

function hasUsableCoordinates(latitude: number, longitude: number): boolean {
  return isValidLatitude(latitude) &&
    isValidLongitude(longitude) &&
    (latitude !== 0 || longitude !== 0);
}

function encodeGeohash(latitude: number, longitude: number, precision = 5): string {
  if (!hasUsableCoordinates(latitude, longitude)) return "";
  let isEven = true;
  let bit = 0;
  let ch = 0;
  let geohash = "";
  let latRange = [-90.0, 90.0];
  let lonRange = [-180.0, 180.0];

  while (geohash.length < precision) {
    if (isEven) {
      const mid = (lonRange[0] + lonRange[1]) / 2;
      if (longitude >= mid) {
        ch |= 1 << (4 - bit);
        lonRange[0] = mid;
      } else {
        lonRange[1] = mid;
      }
    } else {
      const mid = (latRange[0] + latRange[1]) / 2;
      if (latitude >= mid) {
        ch |= 1 << (4 - bit);
        latRange[0] = mid;
      } else {
        latRange[1] = mid;
      }
    }

    isEven = !isEven;
    if (bit < 4) {
      bit += 1;
    } else {
      geohash += GEOHASH_BASE32[ch];
      bit = 0;
      ch = 0;
    }
  }

  return geohash;
}

function decodeGeohashBounds(geohash: string): {
  minLat: number;
  maxLat: number;
  minLon: number;
  maxLon: number;
} | null {
  const normalized = geohash.trim().toLowerCase();
  if (normalized.length === 0) return null;

  let isEven = true;
  const latRange = [-90.0, 90.0];
  const lonRange = [-180.0, 180.0];

  for (const char of normalized) {
    const charIndex = GEOHASH_BASE32.indexOf(char);
    if (charIndex < 0) return null;
    for (const mask of [16, 8, 4, 2, 1]) {
      if (isEven) {
        const mid = (lonRange[0] + lonRange[1]) / 2;
        if ((charIndex & mask) !== 0) {
          lonRange[0] = mid;
        } else {
          lonRange[1] = mid;
        }
      } else {
        const mid = (latRange[0] + latRange[1]) / 2;
        if ((charIndex & mask) !== 0) {
          latRange[0] = mid;
        } else {
          latRange[1] = mid;
        }
      }
      isEven = !isEven;
    }
  }

  return {
    minLat: latRange[0],
    maxLat: latRange[1],
    minLon: lonRange[0],
    maxLon: lonRange[1],
  };
}

function geohashPrefixesAround(geohash: string): string[] {
  const normalized = geohash.trim().toLowerCase();
  if (normalized.length === 0) return [];
  const bounds = decodeGeohashBounds(normalized);
  if (bounds == null) return [normalized];

  const centerLat = (bounds.minLat + bounds.maxLat) / 2;
  const centerLon = (bounds.minLon + bounds.maxLon) / 2;
  const latStep = bounds.maxLat - bounds.minLat;
  const lonStep = bounds.maxLon - bounds.minLon;
  const precision = normalized.length;
  const hashes = new Set<string>();

  for (let latOffset = -1; latOffset <= 1; latOffset += 1) {
    for (let lonOffset = -1; lonOffset <= 1; lonOffset += 1) {
      const nextLat = Math.max(-89.999999, Math.min(89.999999, centerLat + (latOffset * latStep)));
      const nextLon = Math.max(-179.999999, Math.min(179.999999, centerLon + (lonOffset * lonStep)));
      hashes.add(encodeGeohash(nextLat, nextLon, precision));
    }
  }

  return Array.from(hashes).filter((value) => value.length > 0);
}

function asDateLike(value: unknown): Date | null {
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value;
  }
  if (value instanceof Timestamp) {
    const date = value.toDate();
    return Number.isNaN(date.getTime()) ? null : date;
  }
  if (
    value != null &&
    typeof value === "object" &&
    typeof (value as {toDate?: unknown}).toDate === "function"
  ) {
    try {
      const date = (value as {toDate: () => Date}).toDate();
      return date instanceof Date && !Number.isNaN(date.getTime()) ? date : null;
    } catch (_) {
      return null;
    }
  }
  if (
    value != null &&
    typeof value === "object" &&
    typeof (value as {_seconds?: unknown})._seconds === "number"
  ) {
    const seconds = Number((value as {_seconds: number})._seconds);
    const nanos = Number((value as {_nanoseconds?: number})._nanoseconds ?? 0);
    const millis = (seconds * 1000) + Math.floor(nanos / 1_000_000);
    const date = new Date(millis);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  if (
    value != null &&
    typeof value === "object" &&
    typeof (value as {seconds?: unknown}).seconds === "number"
  ) {
    const seconds = Number((value as {seconds: number}).seconds);
    const nanos = Number((value as {nanoseconds?: number}).nanoseconds ?? 0);
    const millis = (seconds * 1000) + Math.floor(nanos / 1_000_000);
    const date = new Date(millis);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

export function createdAtMillisFromPost(data: SocialPostSnapshot): number {
  const createdAtEpoch = asInteger(data.createdAtEpoch);
  if (createdAtEpoch > 0) return createdAtEpoch;
  const createdAt = asDateLike(data.createdAt);
  return createdAt?.getTime() ?? 0;
}

function ageHoursFromCreatedAt(createdAtMs: number, nowMs: number): number {
  if (createdAtMs <= 0) return Number.POSITIVE_INFINITY;
  return Math.max(0, (nowMs - createdAtMs) / HOUR_MS);
}

function freshnessMultiplierForAge(ageHours: number): number {
  if (ageHours <= 6) return 1.00;
  if (ageHours <= 24) return 0.90;
  if (ageHours <= 72) return 0.72;
  if (ageHours <= 168) return 0.50;
  if (ageHours <= 336) return 0.30;
  if (ageHours <= 720) return 0.15;
  return 0.05;
}

function newPostBaselineForAge(ageHours: number): number {
  if (ageHours <= 2) return 1.25;
  if (ageHours <= 6) return 0.80;
  if (ageHours <= 24) return 0.30;
  return 0;
}

function homeFreshnessMultiplierForAge(ageHours: number): number {
  if (ageHours <= 6) return 1.00;
  if (ageHours <= 24) return 0.92;
  if (ageHours <= 72) return 0.74;
  if (ageHours <= 168) return 0.52;
  if (ageHours <= 336) return 0.30;
  if (ageHours <= 720) return 0.14;
  return 0.06;
}

function homeNewPostBaselineForAge(ageHours: number): number {
  if (ageHours <= 2) return 1.10;
  if (ageHours <= 6) return 0.75;
  if (ageHours <= 24) return 0.35;
  if (ageHours <= 72) return 0.12;
  return 0;
}

function nearbyFreshnessMultiplierForAge(ageHours: number): number {
  if (ageHours <= 6) return 1.00;
  if (ageHours <= 24) return 0.90;
  if (ageHours <= 72) return 0.75;
  if (ageHours <= 168) return 0.55;
  if (ageHours <= 336) return 0.30;
  if (ageHours <= 720) return 0.12;
  return 0.04;
}

function nearbyNewPostBaselineForAge(ageHours: number): number {
  if (ageHours <= 2) return 1.00;
  if (ageHours <= 6) return 0.65;
  if (ageHours <= 24) return 0.25;
  return 0;
}

export function buildRankingInputs(data: SocialPostSnapshot): RankingInputs {
  return {
    likeCount: clampNonNegativeInteger(data.likeCount),
    commentCount: clampNonNegativeInteger(data.commentCount),
    shareCount: clampNonNegativeInteger(data.shareCount),
    reportCount: clampNonNegativeInteger(data.reportCount),
    visibilityStatus: asTrimmedString(data.visibilityStatus),
    moderationStatus: asTrimmedString(data.moderationStatus),
    createdAtEpoch: createdAtMillisFromPost(data),
    authorCity: normalizeLocationKey(data.authorCity),
    authorState: normalizeLocationKey(data.authorState),
    recentEngagementScore: asNumber(data.recentEngagementScore),
    adminPriorityBoost: clampNonNegativeInteger(data.adminPriorityBoost),
    isAdminPost: data.isAdminPost === true,
    authorType: asTrimmedString(data.authorType),
  };
}

export function rankingInputsEqual(
  left: RankingInputs,
  right: RankingInputs,
): boolean {
  return left.likeCount === right.likeCount &&
    left.commentCount === right.commentCount &&
    left.shareCount === right.shareCount &&
    left.reportCount === right.reportCount &&
    left.visibilityStatus === right.visibilityStatus &&
    left.moderationStatus === right.moderationStatus &&
    left.createdAtEpoch === right.createdAtEpoch &&
    left.authorCity === right.authorCity &&
    left.authorState === right.authorState &&
    left.recentEngagementScore === right.recentEngagementScore &&
    left.adminPriorityBoost === right.adminPriorityBoost &&
    left.isAdminPost === right.isAdminPost &&
    left.authorType === right.authorType;
}

export function computeDiscoverScoreBreakdown(
  data: SocialPostSnapshot,
  nowMs = Date.now(),
): DiscoverScoreBreakdown {
  const inputs = buildRankingInputs(data);
  const discoverEligible =
    inputs.visibilityStatus === "visible" &&
    inputs.moderationStatus === "approved";

  if (!discoverEligible) {
    return {
      discoverEligible: false,
      weightedEngagement: 0,
      engagementScore: 0,
      freshnessMultiplier: 0,
      newPostBaseline: 0,
      reportPenalty: 0,
      discoverScore: 0,
    };
  }

  const weightedEngagement =
    inputs.likeCount +
    (inputs.commentCount * 3) +
    (inputs.shareCount * 5);
  const engagementScore = Math.log(1 + Math.max(0, weightedEngagement));
  const ageHours = ageHoursFromCreatedAt(inputs.createdAtEpoch, nowMs);
  const freshnessMultiplier = freshnessMultiplierForAge(ageHours);
  const newPostBaseline = newPostBaselineForAge(ageHours);
  const reportPenalty = Math.min(
    inputs.reportCount * REPORT_PENALTY_PER_REPORT,
    MAX_REPORT_PENALTY,
  );
  const discoverScore = roundScore(
    Math.max(
      0,
      newPostBaseline + (engagementScore * freshnessMultiplier) - reportPenalty,
    ),
  );

  return {
    discoverEligible: true,
    weightedEngagement,
    engagementScore: roundScore(engagementScore),
    freshnessMultiplier,
    newPostBaseline,
    reportPenalty: roundScore(reportPenalty),
    discoverScore,
  };
}

export function computeHomeScoreBreakdown(
  data: SocialPostSnapshot,
  nowMs = Date.now(),
): HomeScoreBreakdown {
  const inputs = buildRankingInputs(data);
  const homeEligible =
    inputs.visibilityStatus === "visible" &&
    inputs.moderationStatus === "approved";

  if (!homeEligible) {
    return {
      homeEligible: false,
      weightedEngagement: 0,
      engagementScore: 0,
      freshnessMultiplier: 0,
      newPostBaseline: 0,
      adminBoost: 0,
      reportPenalty: 0,
      homeScore: 0,
    };
  }

  const recentEngagementBoost = Math.min(
    6,
    Math.max(0, inputs.recentEngagementScore),
  );
  const weightedEngagement =
    inputs.likeCount +
    (inputs.commentCount * 3) +
    (inputs.shareCount * 5) +
    recentEngagementBoost;
  const engagementScore = Math.log(1 + Math.max(0, weightedEngagement));
  const ageHours = ageHoursFromCreatedAt(inputs.createdAtEpoch, nowMs);
  const freshnessMultiplier = homeFreshnessMultiplierForAge(ageHours);
  const newPostBaseline = homeNewPostBaselineForAge(ageHours);
  const adminBoost = roundScore(
    Math.min(1.8, inputs.adminPriorityBoost * 0.06) +
      ((inputs.isAdminPost || inputs.authorType === "admin") ? 0.4 : 0),
  );
  const reportPenalty = Math.min(
    inputs.reportCount * HOME_REPORT_PENALTY_PER_REPORT,
    HOME_MAX_REPORT_PENALTY,
  );
  const homeScore = roundScore(
    Math.max(
      0,
      newPostBaseline +
        (engagementScore * freshnessMultiplier) +
        adminBoost -
        reportPenalty,
    ),
  );

  return {
    homeEligible: true,
    weightedEngagement: roundScore(weightedEngagement),
    engagementScore: roundScore(engagementScore),
    freshnessMultiplier,
    newPostBaseline,
    adminBoost,
    reportPenalty: roundScore(reportPenalty),
    homeScore,
  };
}

function readPrivateLocationSnapshot(data: Record<string, unknown> | undefined): PrivateLocationSnapshot | null {
  const raw = data?.[USER_PRIVATE_LOCATION_FIELD];
  if (raw == null || typeof raw !== "object") return null;
  const location = raw as Record<string, unknown>;
  const latitude = asNumber(location.latitude);
  const longitude = asNumber(location.longitude);
  const geohash5 = asTrimmedString(location.geohash5) || encodeGeohash(latitude, longitude, 5);
  if (!hasUsableCoordinates(latitude, longitude) || geohash5.length === 0) {
    return null;
  }
  return {
    latitude,
    longitude,
    city: asTrimmedString(location.city),
    state: asTrimmedString(location.state),
    country: asTrimmedString(location.country),
    geohash3: asTrimmedString(location.geohash3) || geohash5.slice(0, 3),
    geohash4: asTrimmedString(location.geohash4) || geohash5.slice(0, 4),
    geohash5,
  };
}

function readStoredNearbyLocation(data: SocialPostSnapshot): NearbyLocationMetadata {
  return {
    nearbyEligible: data.nearbyEligible === true,
    feedGeohash3: asTrimmedString(data.feedGeohash3),
    feedGeohash4: asTrimmedString(data.feedGeohash4),
    feedGeohash5: asTrimmedString(data.feedGeohash5),
    feedLocationVersion: asInteger(data.feedLocationVersion),
    feedCityKey: normalizeLocationKey(data.feedCityKey || data.authorCity),
    feedStateKey: normalizeLocationKey(data.feedStateKey || data.authorState),
  };
}

function hasCurrentNearbyLocationMetadata(data: SocialPostSnapshot): boolean {
  const metadata = readStoredNearbyLocation(data);
  return metadata.feedLocationVersion >= FEED_LOCATION_VERSION &&
    (
      metadata.feedGeohash5.length > 0 ||
      metadata.feedCityKey.length > 0 ||
      metadata.feedStateKey.length > 0
    );
}

function buildNearbyLocationMetadata(
  data: SocialPostSnapshot,
  authorLocation: PrivateLocationSnapshot | null,
  privateLocation: PrivatePostLocationMetadata | null,
): NearbyLocationMetadata {
  const existing = readStoredNearbyLocation(data);
  const existingCityKey =
    existing.feedCityKey || normalizeLocationKey(data.authorCity);
  const existingStateKey =
    existing.feedStateKey || normalizeLocationKey(data.authorState);
  const feedCityKey = authorLocation?.city ?
    normalizeLocationKey(authorLocation.city) :
    existingCityKey;
  const feedStateKey = authorLocation?.state ?
    normalizeLocationKey(authorLocation.state) :
    existingStateKey;

  if (existing.feedLocationVersion >= FEED_LOCATION_VERSION) {
    return {
      ...existing,
      feedCityKey: existingCityKey,
      feedStateKey: existingStateKey,
    };
  }

  if (privateLocation != null) {
    return {
      nearbyEligible: true,
      feedGeohash3: encodeGeohash(
        privateLocation.latitudeBucket,
        privateLocation.longitudeBucket,
        3,
      ),
      feedGeohash4: encodeGeohash(
        privateLocation.latitudeBucket,
        privateLocation.longitudeBucket,
        4,
      ),
      feedGeohash5: encodeGeohash(
        privateLocation.latitudeBucket,
        privateLocation.longitudeBucket,
        5,
      ),
      feedLocationVersion: Math.max(
        FEED_LOCATION_VERSION,
        privateLocation.feedLocationVersion,
      ),
      feedCityKey: existingCityKey,
      feedStateKey: existingStateKey,
    };
  }

  if (authorLocation != null) {
    return {
      nearbyEligible: true,
      feedGeohash3: authorLocation.geohash3,
      feedGeohash4: authorLocation.geohash4,
      feedGeohash5: authorLocation.geohash5,
      feedLocationVersion: FEED_LOCATION_VERSION,
      feedCityKey,
      feedStateKey,
    };
  }

  return {
    nearbyEligible: false,
    feedGeohash3: existing.feedGeohash3,
    feedGeohash4: existing.feedGeohash4,
    feedGeohash5: existing.feedGeohash5,
    feedLocationVersion: existing.feedLocationVersion,
    feedCityKey,
    feedStateKey,
  };
}

function buildPrivatePostLocationMetadata(
  authorLocation: PrivateLocationSnapshot | null,
): PrivatePostLocationMetadata | null {
  if (authorLocation == null) return null;
  return {
    latitudeBucket: roundCoordinateBucket(authorLocation.latitude),
    longitudeBucket: roundCoordinateBucket(authorLocation.longitude),
    feedLocationVersion: FEED_LOCATION_VERSION,
  };
}

export function buildFeedMetadata(
  data: SocialPostSnapshot,
  nowMs = Date.now(),
  options?: {
    authorLocation?: PrivateLocationSnapshot | null;
    privateLocation?: PrivatePostLocationMetadata | null;
  },
): FeedMetadata {
  const breakdown = computeDiscoverScoreBreakdown(data, nowMs);
  const homeBreakdown = computeHomeScoreBreakdown(data, nowMs);
  const nearbyLocation = buildNearbyLocationMetadata(
    data,
    options?.authorLocation ?? null,
    options?.privateLocation ?? null,
  );
  return {
    discoverScore: breakdown.discoverScore,
    discoverRankVersion: DISCOVER_RANK_VERSION,
    discoverEligible: breakdown.discoverEligible,
    homeScore: homeBreakdown.homeScore,
    homeRankVersion: HOME_RANK_VERSION,
    homeEligible: homeBreakdown.homeEligible,
    ...nearbyLocation,
  };
}

export function metadataMatchesCurrent(
  data: SocialPostSnapshot,
  next: FeedMetadata,
): boolean {
  return asNumber(data.discoverScore) === next.discoverScore &&
    asInteger(data.discoverRankVersion) === next.discoverRankVersion &&
    data.discoverEligible === next.discoverEligible &&
    asNumber(data.homeScore) === next.homeScore &&
    asInteger(data.homeRankVersion) === next.homeRankVersion &&
    data.homeEligible === next.homeEligible &&
    data.nearbyEligible === next.nearbyEligible &&
    asTrimmedString(data.feedGeohash3) === next.feedGeohash3 &&
    asTrimmedString(data.feedGeohash4) === next.feedGeohash4 &&
    asTrimmedString(data.feedGeohash5) === next.feedGeohash5 &&
    asInteger(data.feedLocationVersion) === next.feedLocationVersion &&
    asTrimmedString(data.feedCityKey) === next.feedCityKey &&
    asTrimmedString(data.feedStateKey) === next.feedStateKey;
}

function buildPublicNearbyMetadataWrite(nextMetadata: FeedMetadata): Record<string, unknown> {
  return {
    ...nextMetadata,
    feedLatitudeBucket: FieldValue.delete(),
    feedLongitudeBucket: FieldValue.delete(),
    discoverScoreUpdatedAt: FieldValue.serverTimestamp(),
    homeScoreUpdatedAt: FieldValue.serverTimestamp(),
    feedLocationUpdatedAt: FieldValue.serverTimestamp(),
  };
}

function sanitizeNearbyResponseData(
  data: SocialPostSnapshot,
  fallbackId: string,
): Record<string, unknown> {
  const payload: Record<string, unknown> = {
    ...data,
    id: asTrimmedString(data.id) || fallbackId,
  };
  const timestampFields = [
    "feedLocationUpdatedAt",
    "moderatedAt",
    "lastReportedAt",
    "createdAt",
    "updatedAt",
    "discoverScoreUpdatedAt",
    "homeScoreUpdatedAt",
  ] as const;
  for (const field of timestampFields) {
    const date = asDateLike(payload[field]);
    if (date != null) {
      payload[field] = date.getTime();
    }
  }
  delete payload.feedLatitudeBucket;
  delete payload.feedLongitudeBucket;
  return payload;
}

function buildPrivateNearbyLocationWrite(
  privateLocation: PrivatePostLocationMetadata | null,
): Record<string, unknown> | null {
  if (privateLocation == null) return null;
  return {
    feedLocation: {
      latitudeBucket: privateLocation.latitudeBucket,
      longitudeBucket: privateLocation.longitudeBucket,
      feedLocationVersion: privateLocation.feedLocationVersion,
      updatedAt: FieldValue.serverTimestamp(),
    },
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function normalizeError(error: unknown): Error {
  if (error instanceof Error) return error;
  if (typeof error === "string") return new Error(error);
  return new Error("Unknown error");
}

async function requireAdminActor(uid: string): Promise<{uid: string; role: string}> {
  const snapshot = await db.collection("users").doc(uid).get();
  if (!snapshot.exists) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
  const role = asTrimmedString(snapshot.data()?.adminRole);
  if (!ADMIN_ROLES.has(role)) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
  return {uid, role};
}

function coerceBackfillLimit(value: unknown): number {
  const limit = clampNonNegativeInteger(value);
  if (limit <= 0) return BACKFILL_DEFAULT_LIMIT;
  return Math.min(limit, BACKFILL_MAX_LIMIT);
}

function coerceNearbyLimit(value: unknown): number {
  const limit = clampNonNegativeInteger(value);
  if (limit <= 0) return NEARBY_DEFAULT_LIMIT;
  return Math.min(limit, NEARBY_MAX_LIMIT);
}

function parseNearbyCursor(value: unknown): NearbyFeedCursor | null {
  if (value == null || typeof value !== "object") return null;
  const cursor = value as Record<string, unknown>;
  const sessionId = asTrimmedString(cursor.sessionId);
  const offset = clampNonNegativeInteger(cursor.offset);
  if (sessionId.length === 0) return null;
  return {
    sessionId,
    offset,
  };
}

function randomSessionId(): string {
  return `nearby_${Date.now()}_${Math.random().toString(36).slice(2, 12)}`;
}

async function acquireRefreshLease(
  firestore: typeof db,
  now: Date,
  leaseDurationMs = 55 * 60 * 1000,
): Promise<{acquired: boolean; leaseId: string}> {
  const lockRef = firestore.doc(REFRESH_LOCK_PATH);
  const leaseId = `refresh:${now.toISOString()}`;
  let acquired = false;

  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(lockRef);
    const data = snapshot.data() ?? {};
    const expiresAt = asDateLike(data.expiresAt);
    if (expiresAt != null && expiresAt.getTime() > now.getTime()) {
      return;
    }
    acquired = true;
    transaction.set(lockRef, {
      leaseId,
      acquiredAt: Timestamp.fromDate(now),
      expiresAt: Timestamp.fromMillis(now.getTime() + leaseDurationMs),
    }, {merge: true});
  });

  return {acquired, leaseId};
}

async function releaseRefreshLease(
  firestore: typeof db,
  leaseId: string,
  now: Date,
): Promise<void> {
  await firestore.doc(REFRESH_LOCK_PATH).set({
    leaseId: FieldValue.delete(),
    releasedAt: Timestamp.fromDate(now),
    expiresAt: Timestamp.fromDate(now),
  }, {merge: true});
}

async function loadAuthorLocationSnapshot(
  firestore: typeof db,
  authorId: string,
): Promise<PrivateLocationSnapshot | null> {
  const normalizedAuthorId = authorId.trim();
  if (normalizedAuthorId.length === 0) return null;
  const snapshot = await firestore.collection("userPrivate").doc(normalizedAuthorId).get();
  return readPrivateLocationSnapshot(snapshot.data());
}

function readLegacyPublicLocationBuckets(data: SocialPostSnapshot): PrivatePostLocationMetadata | null {
  const latitudeBucket = asNumber(data.feedLatitudeBucket);
  const longitudeBucket = asNumber(data.feedLongitudeBucket);
  if (!hasUsableCoordinates(latitudeBucket, longitudeBucket)) {
    return null;
  }
  return {
    latitudeBucket,
    longitudeBucket,
    feedLocationVersion: Math.max(1, asInteger(data.feedLocationVersion)),
  };
}

function readPrivatePostLocation(data: Record<string, unknown> | undefined): PrivatePostLocationMetadata | null {
  const raw = data?.feedLocation;
  if (raw == null || typeof raw !== "object") return null;
  const location = raw as Record<string, unknown>;
  const latitudeBucket = asNumber(location.latitudeBucket);
  const longitudeBucket = asNumber(location.longitudeBucket);
  if (!hasUsableCoordinates(latitudeBucket, longitudeBucket)) {
    return null;
  }
  return {
    latitudeBucket,
    longitudeBucket,
    feedLocationVersion: Math.max(FEED_LOCATION_VERSION, asInteger(location.feedLocationVersion)),
  };
}

function hasLegacyPublicLocationBuckets(data: SocialPostSnapshot): boolean {
  return readLegacyPublicLocationBuckets(data) != null;
}

function isPubliclyVisibleUser(data: Record<string, unknown> | undefined): boolean {
  const source = data ?? {};
  const accountStatus = asTrimmedString(source.accountStatus).toLowerCase();
  const profileVisibility = asTrimmedString(source.profileVisibility).toLowerCase();
  const normalizedName = asTrimmedString(source.name || source.displayName).toLowerCase();
  const normalizedUsername = asTrimmedString(source.usernameLowercase || source.username).toLowerCase();
  const isDeleted = source.isDeleted === true;
  const isActive = source.isActive !== false;
  const deletionRequested = source.deletionRequested === true;
  const isPendingDeletion = accountStatus === "pendingdeletion" || deletionRequested;
  const isUnavailableAccountStatus = [
    "deleted",
    "deactivated",
    "disabled",
    "pendingdeletion",
    "deletioninprogress",
  ].includes(accountStatus);
  const isLegacyDeletedProfile = normalizedName === "deleted user" || normalizedUsername.startsWith("deleted_");
  if (
    isDeleted ||
    isPendingDeletion ||
    profileVisibility === "hidden" ||
    isUnavailableAccountStatus ||
    isLegacyDeletedProfile
  ) {
    return false;
  }
  return isActive;
}

async function loadViewerFilterContext(
  firestore: typeof db,
  uid: string,
): Promise<ViewerFilterContext> {
  const [blockedByViewerSnapshot, mutedSnapshot, blockedViewerSnapshot] = await Promise.all([
    firestore.collection("userBlocks").where("ownerUserId", "==", uid).get(),
    firestore.collection("userMutes").where("ownerUserId", "==", uid).get(),
    firestore.collection("userBlocks").where("blockedUserId", "==", uid).get(),
  ]);

  return {
    blockedCreatorIds: new Set(
      blockedByViewerSnapshot.docs
        .map((doc) => asTrimmedString(doc.data()?.blockedUserId))
        .filter((value) => value.length > 0),
    ),
    mutedCreatorIds: new Set(
      mutedSnapshot.docs
        .map((doc) => asTrimmedString(doc.data()?.mutedUserId))
        .filter((value) => value.length > 0),
    ),
    creatorsWhoBlockedViewerIds: new Set(
      blockedViewerSnapshot.docs
        .map((doc) => asTrimmedString(doc.data()?.ownerUserId))
        .filter((value) => value.length > 0),
    ),
  };
}

async function resolveViewerLocationContext(
  firestore: typeof db,
  uid: string,
): Promise<ViewerLocationContext> {
  const privateSnapshot = await firestore.collection("userPrivate").doc(uid).get();
  const privateLocation = readPrivateLocationSnapshot(privateSnapshot.data());
  if (privateLocation != null) {
    return {
      kind: "coordinates",
      latitude: privateLocation.latitude,
      longitude: privateLocation.longitude,
      cityKey: normalizeLocationKey(privateLocation.city),
      stateKey: normalizeLocationKey(privateLocation.state),
      geohash3: privateLocation.geohash3,
      geohash4: privateLocation.geohash4,
      geohash5: privateLocation.geohash5,
    };
  }

  const profileSnapshot = await firestore.collection("users").doc(uid).get();
  const profileData = profileSnapshot.data() ?? {};
  const cityKey = normalizeLocationKey(profileData.city);
  const stateKey = normalizeLocationKey(profileData.state);
  if (cityKey.length > 0 || stateKey.length > 0) {
    return {
      kind: "fallback",
      cityKey,
      stateKey,
    };
  }

  return {
    kind: "missing",
    cityKey: "",
    stateKey: "",
  };
}

function toRadians(value: number): number {
  return value * (Math.PI / 180);
}

export function calculateDistanceKm(
  latitudeA: number,
  longitudeA: number,
  latitudeB: number,
  longitudeB: number,
): number | null {
  if (
    !hasUsableCoordinates(latitudeA, longitudeA) ||
    !hasUsableCoordinates(latitudeB, longitudeB)
  ) {
    return null;
  }

  const earthRadiusKm = 6371;
  const dLat = toRadians(latitudeB - latitudeA);
  const dLon = toRadians(longitudeB - longitudeA);
  const lat1 = toRadians(latitudeA);
  const lat2 = toRadians(latitudeB);
  const haversine =
    (Math.sin(dLat / 2) ** 2) +
    (Math.cos(lat1) * Math.cos(lat2) * (Math.sin(dLon / 2) ** 2));
  const arc = 2 * Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine));
  return earthRadiusKm * arc;
}

function distanceScoreForKm(distanceKm: number): number {
  if (distanceKm <= 2) return 1.00;
  if (distanceKm <= 5) return 0.85;
  if (distanceKm <= 10) return 0.65;
  if (distanceKm <= 20) return 0.40;
  if (distanceKm <= 30) return 0.20;
  if (distanceKm <= 50) return 0.08;
  return 0;
}

export function formatNearbyDistanceLabel(distanceKm: number | null): string {
  if (distanceKm == null || !Number.isFinite(distanceKm) || distanceKm <= 0) {
    return "";
  }
  const distanceMeters = distanceKm * 1000;
  if (distanceMeters < 1000) {
    return `${Math.max(100, Math.round(distanceMeters))} m away`;
  }
  if (distanceKm < 10) {
    return `${distanceKm.toFixed(1)} km away`;
  }
  return `${distanceKm.toFixed(0)} km away`;
}

export function computeNearbyScoreBreakdown(
  data: SocialPostSnapshot,
  viewerLatitude: number,
  viewerLongitude: number,
  nowMs = Date.now(),
  locationOverride?: PrivatePostLocationMetadata | null,
): NearbyScoreBreakdown {
  const inputs = buildRankingInputs(data);
  const locationSource = locationOverride ?? readLegacyPublicLocationBuckets(data);
  const distanceKm = calculateDistanceKm(
    viewerLatitude,
    viewerLongitude,
    locationSource?.latitudeBucket ?? 0,
    locationSource?.longitudeBucket ?? 0,
  );
  const nearbyEligible =
    data.nearbyEligible === true &&
    inputs.visibilityStatus === "visible" &&
    inputs.moderationStatus === "approved" &&
    distanceKm != null &&
    distanceKm <= 50;

  if (!nearbyEligible || distanceKm == null) {
    return {
      nearbyEligible: false,
      weightedEngagement: 0,
      engagementScore: 0,
      freshnessMultiplier: 0,
      newPostBaseline: 0,
      distanceScore: 0,
      reportPenalty: 0,
      nearbyScore: 0,
      distanceKm: distanceKm ?? Number.POSITIVE_INFINITY,
    };
  }

  const weightedEngagement =
    inputs.likeCount +
    (inputs.commentCount * 3) +
    (inputs.shareCount * 5);
  const engagementScore = Math.log(1 + Math.max(0, weightedEngagement));
  const ageHours = ageHoursFromCreatedAt(inputs.createdAtEpoch, nowMs);
  const freshnessMultiplier = nearbyFreshnessMultiplierForAge(ageHours);
  const newPostBaseline = nearbyNewPostBaselineForAge(ageHours);
  const distanceScore = distanceScoreForKm(distanceKm);
  const reportPenalty = Math.min(
    inputs.reportCount * NEARBY_REPORT_PENALTY_PER_REPORT,
    NEARBY_MAX_REPORT_PENALTY,
  );
  const nearbyScore = roundScore(
    Math.max(
      0,
      (
        (distanceScore * 0.50) +
        ((newPostBaseline + (engagementScore * freshnessMultiplier)) * 0.50)
      ) - reportPenalty,
    ),
  );

  return {
    nearbyEligible: true,
    weightedEngagement,
    engagementScore: roundScore(engagementScore),
    freshnessMultiplier,
    newPostBaseline,
    distanceScore,
    reportPenalty: roundScore(reportPenalty),
    nearbyScore,
    distanceKm: roundScore(distanceKm),
  };
}

function compareNearbyFeedPosts(left: NearbyFeedPostResult, right: NearbyFeedPostResult): number {
  if (left.score !== right.score) {
    return right.score - left.score;
  }
  if (left.createdAtEpoch !== right.createdAtEpoch) {
    return right.createdAtEpoch - left.createdAtEpoch;
  }
  return left.id.localeCompare(right.id);
}

function geohashFieldForRadius(radiusKm: number): "feedGeohash5" | "feedGeohash4" | "feedGeohash3" {
  if (radiusKm <= 5) return "feedGeohash5";
  if (radiusKm <= 15) return "feedGeohash4";
  return "feedGeohash3";
}

function viewerGeohashForRadius(
  viewerLocation: ViewerLocationContext & {kind: "coordinates"},
  radiusKm: number,
): string {
  if (radiusKm <= 5) return viewerLocation.geohash5;
  if (radiusKm <= 15) return viewerLocation.geohash4;
  return viewerLocation.geohash3;
}

type NearbyPoolQueryDefinition = {
  key: string;
  radiusKm: number;
  poolName: string;
  fieldPath: "feedGeohash5" | "feedGeohash4" | "feedGeohash3";
  prefixes: string[];
  order: "fresh" | "engaged";
  limit: number;
};

function buildNearbyPoolDefinitions(params: {
  viewerLocation: ViewerLocationContext & {kind: "coordinates"};
  radiusKm: number;
}): NearbyPoolQueryDefinition[] {
  const radiusFieldPath = geohashFieldForRadius(params.radiusKm);
  const radiusViewerGeohash = viewerGeohashForRadius(params.viewerLocation, params.radiusKm);
  const radiusPrefixes = geohashPrefixesAround(radiusViewerGeohash).slice(0, 10);
  const localPrefixes = geohashPrefixesAround(params.viewerLocation.geohash5).slice(0, 10);
  const definitions: NearbyPoolQueryDefinition[] = [];

  const addDefinition = (
    poolName: string,
    fieldPath: "feedGeohash5" | "feedGeohash4" | "feedGeohash3",
    prefixes: string[],
    order: "fresh" | "engaged",
    limit: number,
  ) => {
    const normalizedPrefixes = Array.from(
      new Set(prefixes.map((value) => value.trim()).filter((value) => value.length > 0)),
    );
    if (normalizedPrefixes.length === 0) return;
    definitions.push({
      key: [
        params.radiusKm,
        poolName,
        fieldPath,
        order,
        limit,
        normalizedPrefixes.join(","),
      ].join(":"),
      radiusKm: params.radiusKm,
      poolName,
      fieldPath,
      prefixes: normalizedPrefixes,
      order,
      limit,
    });
  };

  addDefinition("fresh", radiusFieldPath, radiusPrefixes, "fresh", NEARBY_FRESH_POOL_LIMIT);
  addDefinition("engaged", radiusFieldPath, radiusPrefixes, "engaged", NEARBY_ENGAGED_POOL_LIMIT);
  if (params.radiusKm > 5) {
    addDefinition("localFresh", "feedGeohash5", localPrefixes, "fresh", NEARBY_LOCAL_FRESH_POOL_LIMIT);
    addDefinition("localEngaged", "feedGeohash5", localPrefixes, "engaged", NEARBY_LOCAL_ENGAGED_POOL_LIMIT);
  }

  return definitions;
}

async function fetchNearbyPoolCandidates(params: {
  firestore: typeof db;
  definition: NearbyPoolQueryDefinition;
  diagnostics: RequestDiagnostics;
}): Promise<FirebaseFirestore.QueryDocumentSnapshot[]> {
  if (params.definition.prefixes.length === 0) return [];
  let query = params.firestore
    .collection("socialPosts")
    .where("visibilityStatus", "==", "visible")
    .where("moderationStatus", "==", "approved")
    .where("nearbyEligible", "==", true)
    .where(params.definition.fieldPath, "in", params.definition.prefixes);
  if (params.definition.order === "engaged") {
    query = query.orderBy("discoverScore", "desc").orderBy("createdAtEpoch", "desc");
  } else {
    query = query.orderBy("createdAtEpoch", "desc");
  }
  const snapshot = await query.limit(params.definition.limit).get();
  params.diagnostics.queriesExecuted += 1;
  params.diagnostics.documentsRead += snapshot.docs.length;
  params.diagnostics.poolCounts[
    `${params.definition.radiusKm}:${params.definition.poolName}`
  ] = snapshot.docs.length;
  return snapshot.docs;
}

async function loadAuthorVisibilityByIds(params: {
  firestore: typeof db;
  authorIds: string[];
  cache: Map<string, RequestAuthorVisibility>;
}): Promise<void> {
  const missingIds = params.authorIds
    .map((value) => value.trim())
    .filter((value) => value.length > 0)
    .filter((value) => !params.cache.has(value));
  if (missingIds.length === 0) return;
  for (let start = 0; start < missingIds.length; start += 10) {
    const chunk = missingIds.slice(start, start + 10);
    const snapshot = await params.firestore
      .collection("users")
      .where("uid", "in", chunk)
      .get();
    const foundIds = new Set<string>();
    for (const doc of snapshot.docs) {
      const raw = doc.data() ?? {};
      const uid = asTrimmedString(raw.uid) || doc.id;
      if (uid.length === 0) continue;
      foundIds.add(uid);
      params.cache.set(uid, {publiclyVisible: isPubliclyVisibleUser(raw)});
    }
    for (const uid of chunk) {
      if (!foundIds.has(uid)) {
        params.cache.set(uid, {publiclyVisible: false});
      }
    }
  }
}

async function loadPrivatePostLocations(params: {
  firestore: typeof db;
  postIds: string[];
  cache: Map<string, PrivatePostLocationMetadata | null>;
}): Promise<void> {
  const missingIds = params.postIds
    .map((value) => value.trim())
    .filter((value) => value.length > 0)
    .filter((value) => !params.cache.has(value));
  if (missingIds.length === 0) return;
  await Promise.all(missingIds.map(async (postId) => {
    const snapshot = await params.firestore
      .collection(SOCIAL_POST_PRIVATE_COLLECTION)
      .doc(postId)
      .get();
    params.cache.set(postId, readPrivatePostLocation(snapshot.data()) ?? null);
  }));
}

function buildNearbyResultFromDoc(params: {
  doc: FirebaseFirestore.QueryDocumentSnapshot;
  viewerLocation: ViewerLocationContext & {kind: "coordinates"};
  rankingAsOfMs: number;
  radiusKm: number;
  privateLocation: PrivatePostLocationMetadata | null;
}): NearbyFeedPostResult | null {
  const data = params.doc.data() ?? {};
  const breakdown = computeNearbyScoreBreakdown(
    data,
    params.viewerLocation.latitude,
    params.viewerLocation.longitude,
    params.rankingAsOfMs,
    params.privateLocation ?? readLegacyPublicLocationBuckets(data),
  );
  if (!breakdown.nearbyEligible || breakdown.distanceKm > params.radiusKm) {
    return null;
  }
  return {
    id: params.doc.id,
    nearbyDistanceKm: breakdown.distanceKm,
    nearbyDistanceLabel: formatNearbyDistanceLabel(breakdown.distanceKm),
    usesNearbyFallback: false,
    score: breakdown.nearbyScore,
    createdAtEpoch: createdAtMillisFromPost(data),
    data: {
      ...sanitizeNearbyResponseData(data, params.doc.id),
      nearbyDistanceKm: breakdown.distanceKm,
      nearbyDistanceLabel: formatNearbyDistanceLabel(breakdown.distanceKm),
      usesNearbyFallback: false,
    },
  };
}

function sliceSessionPage(params: {
  session: NearbyFeedSessionRecord;
  limit: number;
  offset: number;
}): {
  pageEntries: NearbyFeedSessionPost[];
  nextCursor: NearbyFeedCursor | null;
  hasMore: boolean;
} {
  const safeOffset = clampNonNegativeInteger(params.offset);
  const pageEntries = params.session.orderedPosts.slice(
    safeOffset,
    safeOffset + params.limit,
  );
  const nextOffset = safeOffset + pageEntries.length;
  const hasMore = nextOffset < params.session.orderedPosts.length;
  return {
    pageEntries,
    nextCursor: hasMore ? {sessionId: "", offset: nextOffset} : null,
    hasMore,
  };
}

async function fetchFallbackCandidates(params: {
  firestore: typeof db;
  viewerLocation: ViewerLocationContext & {kind: "fallback"};
  limit: number;
  authorVisibilityCache: Map<string, RequestAuthorVisibility>;
  viewerFilterContext: ViewerFilterContext;
  diagnostics: RequestDiagnostics;
}): Promise<NearbyFeedPostResult[]> {
  const queryLimit = Math.max(NEARBY_FRESH_POOL_LIMIT, params.limit * 3);
  let query = params.firestore
    .collection("socialPosts")
    .where("visibilityStatus", "==", "visible")
    .where("moderationStatus", "==", "approved");

  let label = "In your area";
  if (params.viewerLocation.cityKey.length > 0) {
    query = query.where("feedCityKey", "==", params.viewerLocation.cityKey);
    label = "Near your city";
  } else if (params.viewerLocation.stateKey.length > 0) {
    query = query.where("feedStateKey", "==", params.viewerLocation.stateKey);
  } else {
    return [];
  }

  const snapshot = await query
    .orderBy("discoverScore", "desc")
    .orderBy("createdAtEpoch", "desc")
    .limit(queryLimit)
    .get();
  params.diagnostics.queriesExecuted += 1;
  params.diagnostics.documentsRead += snapshot.docs.length;
  params.diagnostics.poolCounts.fallback = snapshot.docs.length;

  const authorIds = Array.from(
    new Set(
      snapshot.docs
        .map((doc) => asTrimmedString(doc.data()?.authorId))
        .filter((value) => value.length > 0),
    ),
  );
  await loadAuthorVisibilityByIds({
    firestore: params.firestore,
    authorIds,
    cache: params.authorVisibilityCache,
  });

  const results: NearbyFeedPostResult[] = [];
  for (const doc of snapshot.docs) {
    const data = doc.data() ?? {};
    const authorId = asTrimmedString(data.authorId);
    if (authorId.length === 0) continue;
    if (params.viewerFilterContext.blockedCreatorIds.has(authorId)) {
      params.diagnostics.filteredByBlocked += 1;
      continue;
    }
    if (params.viewerFilterContext.mutedCreatorIds.has(authorId)) {
      params.diagnostics.filteredByMuted += 1;
      continue;
    }
    if (params.viewerFilterContext.creatorsWhoBlockedViewerIds.has(authorId)) {
      params.diagnostics.filteredByBlockedByCreator += 1;
      continue;
    }
    if ((params.authorVisibilityCache.get(authorId)?.publiclyVisible ?? false) !== true) {
      params.diagnostics.filteredByVisibility += 1;
      continue;
    }

    results.push({
      id: doc.id,
      nearbyDistanceKm: null,
      nearbyDistanceLabel: label,
      usesNearbyFallback: true,
      score: asNumber(data.discoverScore),
      createdAtEpoch: createdAtMillisFromPost(data),
      data: {
        ...sanitizeNearbyResponseData(data, doc.id),
        nearbyDistanceLabel: label,
        usesNearbyFallback: true,
      },
    });
  }
  results.sort(compareNearbyFeedPosts);
  return results;
}

async function createNearbyFeedSession(params: {
  firestore: typeof db;
  uid: string;
  viewerLocation: ViewerLocationContext;
  limit: number;
  rankingAsOfMs: number;
  diagnostics: RequestDiagnostics;
}): Promise<{sessionId: string; record: NearbyFeedSessionRecord}> {
  const sessionId = randomSessionId();
  const expiresAt = new Date(params.rankingAsOfMs + NEARBY_SESSION_TTL_MS);
  let record: NearbyFeedSessionRecord;

  if (params.viewerLocation.kind === "fallback") {
    const authorVisibilityCache = new Map<string, RequestAuthorVisibility>();
    const viewerFilterContext = await loadViewerFilterContext(params.firestore, params.uid);
    const fallbackPosts = await fetchFallbackCandidates({
      firestore: params.firestore,
      viewerLocation: params.viewerLocation,
      limit: params.limit,
      authorVisibilityCache,
      viewerFilterContext,
      diagnostics: params.diagnostics,
    });
    record = {
      ownerUid: params.uid,
      rankingAsOfEpoch: params.rankingAsOfMs,
      activeRadiusKm: null,
      usedCityStateFallback: true,
      emptyStateReason: fallbackPosts.length === 0 ? "noNearbyPosts" : null,
      orderedPosts: fallbackPosts.slice(0, NEARBY_SESSION_MAX_POSTS).map((post) => ({
        id: post.id,
        nearbyDistanceKm: null,
        nearbyDistanceLabel: post.nearbyDistanceLabel,
        usesNearbyFallback: true,
      })),
      expiresAt,
    };
  } else {
    if (params.viewerLocation.kind !== "coordinates") {
      record = {
        ownerUid: params.uid,
        rankingAsOfEpoch: params.rankingAsOfMs,
        activeRadiusKm: null,
        usedCityStateFallback: false,
        emptyStateReason: "missingLocation",
        orderedPosts: [],
        expiresAt,
      };
      await params.firestore.collection(NEARBY_FEED_SESSION_COLLECTION).doc(sessionId).set({
        ownerUid: record.ownerUid,
        rankingAsOfEpoch: record.rankingAsOfEpoch,
        activeRadiusKm: record.activeRadiusKm,
        usedCityStateFallback: record.usedCityStateFallback,
        emptyStateReason: record.emptyStateReason,
        orderedPosts: record.orderedPosts,
        expiresAt: Timestamp.fromDate(expiresAt),
        createdAt: FieldValue.serverTimestamp(),
      }, {merge: false});
      return {sessionId, record};
    }
    const allCandidates = new Map<string, FirebaseFirestore.QueryDocumentSnapshot>();
    const authorVisibilityCache = new Map<string, RequestAuthorVisibility>();
    const privateLocationCache = new Map<string, PrivatePostLocationMetadata | null>();
    const viewerFilterContext = await loadViewerFilterContext(params.firestore, params.uid);
    const executedPoolKeys = new Set<string>();
    let activeRadiusKm: number | null = null;

    for (const radiusKm of NEARBY_RADIUS_TIERS_KM) {
      params.diagnostics.radiusStages.push(radiusKm);
      activeRadiusKm = radiusKm;
      for (const definition of buildNearbyPoolDefinitions({
        viewerLocation: params.viewerLocation,
        radiusKm,
      })) {
        if (executedPoolKeys.size >= NEARBY_MAX_QUERIES || allCandidates.size >= NEARBY_MAX_CANDIDATES) {
          break;
        }
        if (executedPoolKeys.has(definition.key)) {
          continue;
        }
        executedPoolKeys.add(definition.key);
        const docs = await fetchNearbyPoolCandidates({
          firestore: params.firestore,
          definition,
          diagnostics: params.diagnostics,
        });
        for (const doc of docs) {
          if (!allCandidates.has(doc.id)) {
            allCandidates.set(doc.id, doc);
          } else {
            params.diagnostics.filteredByDuplicate += 1;
          }
        }
      }
      if (executedPoolKeys.size >= NEARBY_MAX_QUERIES || allCandidates.size >= NEARBY_MAX_CANDIDATES) {
        break;
      }
    }

    params.diagnostics.deduplicatedCandidates = allCandidates.size;
    const candidateDocs = Array.from(allCandidates.values()).slice(0, NEARBY_MAX_CANDIDATES);
    const authorIds = Array.from(
      new Set(
        candidateDocs
          .map((doc) => asTrimmedString(doc.data()?.authorId))
          .filter((value) => value.length > 0),
      ),
    );
    await loadAuthorVisibilityByIds({
      firestore: params.firestore,
      authorIds,
      cache: authorVisibilityCache,
    });
    await loadPrivatePostLocations({
      firestore: params.firestore,
      postIds: candidateDocs.map((doc) => doc.id),
      cache: privateLocationCache,
    });

    const rankedResults: NearbyFeedPostResult[] = [];
    for (const doc of candidateDocs) {
      const data = doc.data() ?? {};
      const authorId = asTrimmedString(data.authorId);
      if (authorId.length === 0) {
        params.diagnostics.filteredByVisibility += 1;
        continue;
      }
      if (viewerFilterContext.blockedCreatorIds.has(authorId)) {
        params.diagnostics.filteredByBlocked += 1;
        continue;
      }
      if (viewerFilterContext.mutedCreatorIds.has(authorId)) {
        params.diagnostics.filteredByMuted += 1;
        continue;
      }
      if (viewerFilterContext.creatorsWhoBlockedViewerIds.has(authorId)) {
        params.diagnostics.filteredByBlockedByCreator += 1;
        continue;
      }
      if ((authorVisibilityCache.get(authorId)?.publiclyVisible ?? false) !== true) {
        params.diagnostics.filteredByVisibility += 1;
        continue;
      }

      const privateLocation = privateLocationCache.get(doc.id) ?? null;
      if (privateLocation == null && readLegacyPublicLocationBuckets(data) == null) {
        params.diagnostics.filteredByMissingPrivateLocation += 1;
        continue;
      }

      const result = buildNearbyResultFromDoc({
        doc,
        viewerLocation: params.viewerLocation,
        rankingAsOfMs: params.rankingAsOfMs,
        radiusKm: activeRadiusKm ?? NEARBY_RADIUS_TIERS_KM[NEARBY_RADIUS_TIERS_KM.length - 1],
        privateLocation,
      });
      if (result == null) {
        params.diagnostics.filteredByRadius += 1;
        continue;
      }
      rankedResults.push(result);
    }

    rankedResults.sort(compareNearbyFeedPosts);
    params.diagnostics.rankedCandidates = rankedResults.length;
    record = {
      ownerUid: params.uid,
      rankingAsOfEpoch: params.rankingAsOfMs,
      activeRadiusKm,
      usedCityStateFallback: false,
      emptyStateReason: rankedResults.length === 0 ? "noNearbyPosts" : null,
      orderedPosts: rankedResults.slice(0, NEARBY_SESSION_MAX_POSTS).map((post) => ({
        id: post.id,
        nearbyDistanceKm: post.nearbyDistanceKm,
        nearbyDistanceLabel: post.nearbyDistanceLabel,
        usesNearbyFallback: false,
      })),
      expiresAt,
    };
  }

  await params.firestore.collection(NEARBY_FEED_SESSION_COLLECTION).doc(sessionId).set({
    ownerUid: record.ownerUid,
    rankingAsOfEpoch: record.rankingAsOfEpoch,
    activeRadiusKm: record.activeRadiusKm,
    usedCityStateFallback: record.usedCityStateFallback,
    emptyStateReason: record.emptyStateReason,
    orderedPosts: record.orderedPosts,
    expiresAt: Timestamp.fromDate(expiresAt),
    createdAt: FieldValue.serverTimestamp(),
  }, {merge: false});
  return {sessionId, record};
}

async function loadNearbyFeedSession(params: {
  firestore: typeof db;
  uid: string;
  sessionId: string;
  now: Date;
}): Promise<NearbyFeedSessionRecord> {
  const snapshot = await params.firestore
    .collection(NEARBY_FEED_SESSION_COLLECTION)
    .doc(params.sessionId)
    .get();
  if (!snapshot.exists) {
    throw new HttpsError("invalid-argument", "Nearby feed session is no longer available.");
  }
  const data = snapshot.data() ?? {};
  const ownerUid = asTrimmedString(data.ownerUid);
  if (ownerUid !== params.uid) {
    throw new HttpsError("permission-denied", "Nearby feed session is not available.");
  }
  const expiresAt = asDateLike(data.expiresAt);
  if (expiresAt == null || expiresAt.getTime() <= params.now.getTime()) {
    throw new HttpsError("deadline-exceeded", "Nearby feed session expired. Refresh to continue.");
  }
  return {
    ownerUid,
    rankingAsOfEpoch: asInteger(data.rankingAsOfEpoch),
    activeRadiusKm: data.activeRadiusKm == null ? null : asNumber(data.activeRadiusKm),
    usedCityStateFallback: data.usedCityStateFallback === true,
    emptyStateReason: asTrimmedString(data.emptyStateReason) || null,
    orderedPosts: Array.isArray(data.orderedPosts) ?
      data.orderedPosts
        .filter((item) => item != null && typeof item === "object")
        .map((item) => {
          const entry = item as Record<string, unknown>;
          return {
            id: asTrimmedString(entry.id),
            nearbyDistanceKm: Number.isFinite(asNumber(entry.nearbyDistanceKm)) ?
              asNumber(entry.nearbyDistanceKm) :
              null,
            nearbyDistanceLabel: asTrimmedString(entry.nearbyDistanceLabel),
            usesNearbyFallback: entry.usesNearbyFallback === true,
          };
        })
        .filter((entry) => entry.id.length > 0)
        .slice(0, NEARBY_SESSION_MAX_POSTS) :
      [],
    expiresAt,
  };
}

async function hydrateSessionPagePosts(params: {
  firestore: typeof db;
  pageEntries: NearbyFeedSessionPost[];
}): Promise<Record<string, unknown>[]> {
  const docs = await Promise.all(
    params.pageEntries.map((entry) => params.firestore.collection("socialPosts").doc(entry.id).get()),
  );
  const hydrated: Record<string, unknown>[] = [];
  for (let index = 0; index < docs.length; index += 1) {
    const snapshot = docs[index];
    const entry = params.pageEntries[index];
    const data = snapshot.data() ?? {};
    if (!snapshot.exists) continue;
    if (asTrimmedString(data.visibilityStatus) !== "visible") continue;
    if (asTrimmedString(data.moderationStatus) !== "approved") continue;
    hydrated.push({
      ...sanitizeNearbyResponseData(data, snapshot.id),
      nearbyDistanceKm: entry.nearbyDistanceKm,
      nearbyDistanceLabel: entry.nearbyDistanceLabel,
      usesNearbyFallback: entry.usesNearbyFallback,
    });
  }
  return hydrated;
}

export async function runNearbyFeedQuery(params: {
  uid: string;
  limit?: number;
  cursor?: NearbyFeedCursor | null;
  authoritativeNow?: Date;
  firestore?: typeof db;
}): Promise<NearbyFeedResponse> {
  const firestore = params.firestore ?? db;
  const limit = coerceNearbyLimit(params.limit);
  const cursor = params.cursor ?? null;
  const authoritativeNow = params.authoritativeNow ?? new Date();
  const startedAtMs = Date.now();
  const diagnostics: RequestDiagnostics = {
    queriesExecuted: 0,
    documentsRead: 0,
    deduplicatedCandidates: 0,
    rankedCandidates: 0,
    filteredByBlocked: 0,
    filteredByMuted: 0,
    filteredByBlockedByCreator: 0,
    filteredByVisibility: 0,
    filteredByMissingPrivateLocation: 0,
    filteredByRadius: 0,
    filteredByDuplicate: 0,
    radiusStages: [],
    poolCounts: {},
  };

  if (cursor != null) {
    const session = await loadNearbyFeedSession({
      firestore,
      uid: params.uid,
      sessionId: cursor.sessionId,
      now: authoritativeNow,
    });
    const sliced = sliceSessionPage({
      session,
      limit,
      offset: cursor.offset,
    });
    const posts = await hydrateSessionPagePosts({
      firestore,
      pageEntries: sliced.pageEntries,
    });
    const response = {
      posts,
      nextCursor: sliced.nextCursor == null ? null : {
        sessionId: cursor.sessionId,
        offset: sliced.nextCursor.offset,
      },
      hasMore: sliced.hasMore,
      activeRadiusKm: session.activeRadiusKm,
      usedCityStateFallback: session.usedCityStateFallback,
      emptyStateReason: posts.length === 0 ? session.emptyStateReason : null,
    };
    logger.info("social.nearby.session.reused", {
      uid: params.uid,
      sessionId: cursor.sessionId,
      offset: cursor.offset,
      resultCount: posts.length,
      hasMore: sliced.hasMore,
      activeRadiusKm: session.activeRadiusKm,
      usedCityStateFallback: session.usedCityStateFallback,
      durationMs: Date.now() - startedAtMs,
    });
    return response;
  }

  const viewerLocation = await resolveViewerLocationContext(firestore, params.uid);
  if (viewerLocation.kind === "missing") {
    return {
      posts: [],
      nextCursor: null,
      hasMore: false,
      activeRadiusKm: null,
      usedCityStateFallback: false,
      emptyStateReason: "missingLocation",
    };
  }

  const {sessionId, record} = await createNearbyFeedSession({
    firestore,
    uid: params.uid,
    viewerLocation,
    limit,
    rankingAsOfMs: authoritativeNow.getTime(),
    diagnostics,
  });
  logger.info("social.nearby.session.created", {
    uid: params.uid,
    pageSize: limit,
    sessionId,
    radiusStages: diagnostics.radiusStages,
    queriesExecuted: diagnostics.queriesExecuted,
    documentsRead: diagnostics.documentsRead,
    deduplicatedCandidates: diagnostics.deduplicatedCandidates,
    rankedCandidates: diagnostics.rankedCandidates,
    filteredByBlocked: diagnostics.filteredByBlocked,
    filteredByMuted: diagnostics.filteredByMuted,
    filteredByBlockedByCreator: diagnostics.filteredByBlockedByCreator,
    filteredByVisibility: diagnostics.filteredByVisibility,
    filteredByMissingPrivateLocation: diagnostics.filteredByMissingPrivateLocation,
    filteredByRadius: diagnostics.filteredByRadius,
    filteredByDuplicate: diagnostics.filteredByDuplicate,
    resultCount: record.orderedPosts.length,
    usedCityStateFallback: record.usedCityStateFallback,
    activeRadiusKm: record.activeRadiusKm,
    poolCounts: diagnostics.poolCounts,
    durationMs: Date.now() - startedAtMs,
  });

  const sliced = sliceSessionPage({
    session: record,
    limit,
    offset: 0,
  });
  const posts = await hydrateSessionPagePosts({
    firestore,
    pageEntries: sliced.pageEntries,
  });
  return {
    posts,
    nextCursor: sliced.nextCursor == null ? null : {
      sessionId,
      offset: sliced.nextCursor.offset,
    },
    hasMore: sliced.hasMore,
    activeRadiusKm: record.activeRadiusKm,
    usedCityStateFallback: record.usedCityStateFallback,
    emptyStateReason: posts.length === 0 ? record.emptyStateReason : null,
  };
}

export const syncSocialPostFeedMetadata = onDocumentWritten(
  {document: "socialPosts/{postId}", region: "asia-south1"},
  async (event) => {
    const afterSnapshot = event.data?.after;
    if (!afterSnapshot?.exists) return;

    const beforeData = event.data?.before?.data() ?? {};
    const afterData = afterSnapshot.data() ?? {};
    const beforeInputs = buildRankingInputs(beforeData);
    const afterInputs = buildRankingInputs(afterData);
    const needsLocationMetadata = !hasCurrentNearbyLocationMetadata(afterData);

    if (
      event.data?.before.exists &&
      rankingInputsEqual(beforeInputs, afterInputs) &&
      !needsLocationMetadata
    ) {
      return;
    }

    const legacyPrivateLocation = readLegacyPublicLocationBuckets(afterData);
    const existingPrivateLocation = needsLocationMetadata || legacyPrivateLocation != null ?
      readPrivatePostLocation(
        (
          await db.collection(SOCIAL_POST_PRIVATE_COLLECTION).doc(afterSnapshot.id).get()
        ).data(),
      ) :
      null;
    const preferredPrivateLocation = existingPrivateLocation ?? legacyPrivateLocation;
    const authorLocation = preferredPrivateLocation == null && needsLocationMetadata ?
      await loadAuthorLocationSnapshot(db, asTrimmedString(afterData.authorId)) :
      null;
    const nextMetadata = buildFeedMetadata(afterData, Date.now(), {
      authorLocation,
      privateLocation: preferredPrivateLocation,
    });
    const nextPrivateLocation =
      preferredPrivateLocation ?? buildPrivatePostLocationMetadata(authorLocation);
    const legacyBucketsPresent = hasLegacyPublicLocationBuckets(afterData);
    const hasPrivateLocationState =
      existingPrivateLocation != null || nextPrivateLocation == null;
    if (
      metadataMatchesCurrent(afterData, nextMetadata) &&
      !legacyBucketsPresent &&
      hasPrivateLocationState
    ) {
      return;
    }

    const batch = db.batch();
    batch.set(afterSnapshot.ref, buildPublicNearbyMetadataWrite(nextMetadata), {merge: true});
    const privateWrite = buildPrivateNearbyLocationWrite(nextPrivateLocation);
    if (privateWrite != null) {
      batch.set(db.collection(SOCIAL_POST_PRIVATE_COLLECTION).doc(afterSnapshot.id), privateWrite, {merge: true});
    }
    await batch.commit();
  },
);

export const refreshSocialPostDiscoverScores = onSchedule(
  {
    schedule: "every 60 minutes",
    timeZone: "Asia/Kolkata",
    region: "asia-south1",
  },
  async () => {
    await runRefreshSocialPostDiscoverScores();
  },
);

export async function runRefreshSocialPostDiscoverScores(params?: {
  authoritativeNow?: Date;
  firestore?: typeof db;
  schedulerLogger?: typeof logger;
  skipLease?: boolean;
}): Promise<RefreshSummary> {
  const authoritativeNow = params?.authoritativeNow ?? new Date();
  const firestore = params?.firestore ?? db;
  const schedulerLogger = params?.schedulerLogger ?? logger;
  const startedAtMs = Date.now();
  const summary: RefreshSummary = {
    scanned: 0,
    updated: 0,
    skipped: 0,
    failed: 0,
    durationMs: 0,
    overlapSkipped: false,
  };

  const lease = params?.skipLease ?
    {acquired: true, leaseId: "test-lease"} :
    await acquireRefreshLease(firestore, authoritativeNow);
  if (!lease.acquired) {
    summary.overlapSkipped = true;
    summary.durationMs = Date.now() - startedAtMs;
    schedulerLogger.info("social.discoverRefresh.skipped.overlap", {
      authoritativeAt: authoritativeNow.toISOString(),
      durationMs: summary.durationMs,
    });
    return summary;
  }

  try {
    let lastDocumentId: string | null = null;
    while (true) {
      let query = firestore
        .collection("socialPosts")
        .where("visibilityStatus", "==", "visible")
        .where("moderationStatus", "==", "approved")
        .orderBy(FieldPath.documentId())
        .limit(REFRESH_BATCH_SIZE);
      if (lastDocumentId != null) {
        query = query.startAfter(lastDocumentId);
      }

      const snapshot = await query.get();
      if (snapshot.empty) break;

      const batch = firestore.batch();
      let pageUpdates = 0;
      for (const doc of snapshot.docs) {
        summary.scanned += 1;
        try {
          const data = doc.data() ?? {};
          const nextMetadata = buildFeedMetadata(data, authoritativeNow.getTime(), {
            authorLocation: null,
          });
          if (metadataMatchesCurrent(data, nextMetadata)) {
            summary.skipped += 1;
            continue;
          }
          batch.set(doc.ref, {
            ...nextMetadata,
            discoverScoreUpdatedAt: FieldValue.serverTimestamp(),
            homeScoreUpdatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
          summary.updated += 1;
          pageUpdates += 1;
        } catch (error) {
          summary.failed += 1;
          const normalized = normalizeError(error);
          schedulerLogger.error("social.discoverRefresh.postFailed", {
            postId: doc.id,
            message: normalized.message,
            stack: normalized.stack,
          });
        }
      }

      if (pageUpdates > 0) {
        await batch.commit();
      }

      lastDocumentId = snapshot.docs[snapshot.docs.length - 1]?.id ?? null;
      if (snapshot.size < REFRESH_BATCH_SIZE) break;
    }
  } finally {
    summary.durationMs = Date.now() - startedAtMs;
    if (!params?.skipLease) {
      await releaseRefreshLease(firestore, lease.leaseId, new Date());
    }
  }

  schedulerLogger.info("social.discoverRefresh.completed", {
    scanned: summary.scanned,
    updated: summary.updated,
    skipped: summary.skipped,
    failed: summary.failed,
    durationMs: summary.durationMs,
    authoritativeAt: authoritativeNow.toISOString(),
  });
  return summary;
}

export const backfillSocialPostFeedMetadata = onCall(
  {region: "asia-south1"},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    await requireAdminActor(uid);

    const dryRun = request.data?.dryRun === true;
    const limit = coerceBackfillLimit(request.data?.limit);
    const cursor = asTrimmedString(request.data?.cursor);

    return runSocialPostFeedMetadataBackfill({
      cursor: cursor || null,
      limit,
      dryRun,
    });
  },
);

export const backfillSocialPostHomeMetadata = onCall(
  {region: "asia-south1"},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    await requireAdminActor(uid);

    const dryRun = request.data?.dryRun === true;
    const limit = coerceBackfillLimit(request.data?.limit);
    const cursor = asTrimmedString(request.data?.cursor);

    return runSocialPostHomeMetadataBackfill({
      cursor: cursor || null,
      limit,
      dryRun,
    });
  },
);

export const getNearbySocialPosts = onCall(
  {region: "asia-south1"},
  async (request) => {
    logger.info("social.nearby.authDiagnostic", {
      authPresent: Boolean(request.auth),
      authUid: request.auth?.uid ?? null,
      authorizationHeaderPresent:
        typeof request.rawRequest.headers.authorization === "string",
      authorizationScheme:
        request.rawRequest.headers.authorization?.split(" ", 1)[0] ?? null,
      appCheckPresent: Boolean(request.app),
      userAgentPresent:
        typeof request.rawRequest.headers["user-agent"] === "string",
    });
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const startedAtMs = Date.now();
    const cursor = parseNearbyCursor(request.data?.cursor);
    try {
      return await runNearbyFeedQuery({
        uid,
        limit: request.data?.limit,
        cursor,
      });
    } catch (error) {
      const normalized = normalizeError(error);
      logger.error("social.nearby.request.failed", {
        uid,
        code: error instanceof HttpsError ? error.code : "internal",
        hasCursor: cursor != null,
        durationMs: Date.now() - startedAtMs,
        message: normalized.message,
      });
      throw error;
    }
  },
);

export async function runSocialPostFeedMetadataBackfill(params?: {
  cursor?: string | null;
  limit?: number;
  dryRun?: boolean;
  authoritativeNow?: Date;
  firestore?: typeof db;
}): Promise<BackfillSummary> {
  const firestore = params?.firestore ?? db;
  const authoritativeNow = params?.authoritativeNow ?? new Date();
  const dryRun = params?.dryRun === true;
  const limit = coerceBackfillLimit(params?.limit);
  const cursor = asTrimmedString(params?.cursor);
  let query = firestore
    .collection("socialPosts")
    .orderBy(FieldPath.documentId())
    .limit(limit);
  if (cursor.length > 0) {
    query = query.startAfter(cursor);
  }

  const snapshot = await query.get();
  const summary: BackfillSummary = {
    scanned: 0,
    updated: 0,
    skipped: 0,
    failed: 0,
    privateLocationCreated: 0,
    publicBucketsRemoved: 0,
    alreadyMigrated: 0,
    missingLocation: 0,
    invalidLocation: 0,
    nextCursor: null,
    hasMore: snapshot.size === limit,
    dryRun,
    uniqueAuthorsRead: 0,
    authorCacheHits: 0,
    authorCacheMisses: 0,
    postsProcessed: 0,
    reasonCounts: {
      alreadyCurrent: 0,
      alreadyMigrated: 0,
      updated: 0,
      missingAuthor: 0,
      missingLocation: 0,
      invalidCoordinates: 0,
      publicBucketsRemoved: 0,
      privateLocationCreated: 0,
      failed: 0,
    },
  };
  const batch = dryRun ? null : firestore.batch();
  const authorLocationCache = new Map<string, PrivateLocationSnapshot | null>();

  const loadCachedAuthorLocation = async (authorId: string): Promise<PrivateLocationSnapshot | null> => {
    if (authorLocationCache.has(authorId)) {
      summary.authorCacheHits += 1;
      return authorLocationCache.get(authorId) ?? null;
    }
    summary.authorCacheMisses += 1;
    summary.uniqueAuthorsRead += 1;
    const location = await loadAuthorLocationSnapshot(firestore, authorId);
    if (authorLocationCache.size >= BACKFILL_AUTHOR_CACHE_LIMIT) {
      const oldestKey = authorLocationCache.keys().next().value;
      if (oldestKey) {
        authorLocationCache.delete(oldestKey);
      }
    }
    authorLocationCache.set(authorId, location);
    return location;
  };

  for (const doc of snapshot.docs) {
    summary.scanned += 1;
    summary.postsProcessed += 1;
    try {
      const data = doc.data() ?? {};
      const authorId = asTrimmedString(data.authorId);
      if (authorId.length === 0) {
        summary.failed += 1;
        summary.reasonCounts!.missingAuthor += 1;
        continue;
      }

      const legacyPrivateLocation = readLegacyPublicLocationBuckets(data);
      const privateSnapshot = await firestore
        .collection(SOCIAL_POST_PRIVATE_COLLECTION)
        .doc(doc.id)
        .get();
      const existingPrivateLocation = readPrivatePostLocation(privateSnapshot.data());
      const preferredPrivateLocation = existingPrivateLocation ?? legacyPrivateLocation;
      const authorLocation = preferredPrivateLocation == null ?
        await loadCachedAuthorLocation(authorId) :
        null;
      const nextMetadataResolved = buildFeedMetadata(data, authoritativeNow.getTime(), {
        authorLocation,
        privateLocation: preferredPrivateLocation,
      });
      const nextPrivateLocation =
        preferredPrivateLocation ?? buildPrivatePostLocationMetadata(authorLocation);
      const legacyBucketsPresent = legacyPrivateLocation != null;
      const alreadyMigrated =
        metadataMatchesCurrent(data, nextMetadataResolved) &&
        !legacyBucketsPresent &&
        existingPrivateLocation != null;
      if (alreadyMigrated) {
        summary.skipped += 1;
        summary.reasonCounts!.alreadyCurrent += 1;
        summary.alreadyMigrated += 1;
        summary.reasonCounts!.alreadyMigrated += 1;
        continue;
      }

      if (
        nextPrivateLocation == null &&
        nextMetadataResolved.nearbyEligible !== true
      ) {
        const currentLocation = readStoredNearbyLocation(data);
        if (currentLocation.feedGeohash5.length === 0) {
          summary.reasonCounts!.missingLocation += 1;
          summary.missingLocation += 1;
        } else {
          summary.reasonCounts!.invalidCoordinates += 1;
          summary.invalidLocation += 1;
        }
        summary.skipped += 1;
        continue;
      }

      summary.updated += 1;
      summary.reasonCounts!.updated += 1;
      if (nextPrivateLocation != null && existingPrivateLocation == null) {
        summary.privateLocationCreated += 1;
        summary.reasonCounts!.privateLocationCreated += 1;
      }
      if (legacyBucketsPresent) {
        summary.publicBucketsRemoved += 1;
        summary.reasonCounts!.publicBucketsRemoved += 1;
      }
      if (batch != null) {
        batch.set(
          doc.ref,
          buildPublicNearbyMetadataWrite(nextMetadataResolved),
          {merge: true},
        );
        const privateWrite = buildPrivateNearbyLocationWrite(nextPrivateLocation);
        if (privateWrite != null) {
          batch.set(
            firestore.collection(SOCIAL_POST_PRIVATE_COLLECTION).doc(doc.id),
            privateWrite,
            {merge: true},
          );
        }
      }
    } catch (_) {
      summary.failed += 1;
      summary.reasonCounts!.failed += 1;
    }
  }

  if (batch != null && summary.updated > 0) {
    await batch.commit();
  }

  summary.nextCursor = snapshot.docs[snapshot.docs.length - 1]?.id ?? null;
  return summary;
}

export async function runSocialPostHomeMetadataBackfill(params?: {
  cursor?: string | null;
  limit?: number;
  dryRun?: boolean;
  authoritativeNow?: Date;
  firestore?: typeof db;
}): Promise<HomeBackfillSummary> {
  const firestore = params?.firestore ?? db;
  const authoritativeNow = params?.authoritativeNow ?? new Date();
  const dryRun = params?.dryRun === true;
  const limit = coerceBackfillLimit(params?.limit);
  const cursor = asTrimmedString(params?.cursor);
  let query = firestore
    .collection("socialPosts")
    .orderBy(FieldPath.documentId())
    .limit(limit);
  if (cursor.length > 0) {
    query = query.startAfter(cursor);
  }

  const snapshot = await query.get();
  const summary: HomeBackfillSummary = {
    scanned: 0,
    updated: 0,
    skipped: 0,
    failed: 0,
    nextCursor: null,
    hasMore: snapshot.size === limit,
    dryRun,
    reasonCounts: {
      alreadyCurrent: 0,
      updated: 0,
      failed: 0,
    },
  };
  const batch = dryRun ? null : firestore.batch();

  for (const doc of snapshot.docs) {
    summary.scanned += 1;
    try {
      const data = doc.data() ?? {};
      const nextMetadata = buildFeedMetadata(data, authoritativeNow.getTime(), {
        authorLocation: null,
        privateLocation: null,
      });
      const homeUnchanged =
        asNumber(data.homeScore) === nextMetadata.homeScore &&
        asInteger(data.homeRankVersion) === nextMetadata.homeRankVersion &&
        data.homeEligible === nextMetadata.homeEligible;
      if (homeUnchanged) {
        summary.skipped += 1;
        summary.reasonCounts!.alreadyCurrent += 1;
        continue;
      }

      summary.updated += 1;
      summary.reasonCounts!.updated += 1;
      if (batch != null) {
        batch.set(doc.ref, {
          homeScore: nextMetadata.homeScore,
          homeRankVersion: nextMetadata.homeRankVersion,
          homeEligible: nextMetadata.homeEligible,
          homeScoreUpdatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }
    } catch (_) {
      summary.failed += 1;
      summary.reasonCounts!.failed += 1;
    }
  }

  if (batch != null && summary.updated > 0) {
    await batch.commit();
  }

  summary.nextCursor = snapshot.docs[snapshot.docs.length - 1]?.id ?? null;
  return summary;
}
