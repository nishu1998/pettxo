const test = require("node:test");
const assert = require("node:assert/strict");
const {FieldPath, Timestamp} = require("firebase-admin/firestore");

const {
  buildFeedMetadata,
  buildRankingInputs,
  calculateDistanceKm,
  computeDiscoverScoreBreakdown,
  computeHomeScoreBreakdown,
  computeNearbyScoreBreakdown,
  decodeGeohashBounds,
  encodeGeohash,
  formatNearbyDistanceLabel,
  geohashPrefixesAround,
  metadataMatchesCurrent,
  rankingInputsEqual,
  resolvePostSpecificLocationMetadata,
  runNearbyFeedQuery,
  runRefreshSocialPostDiscoverScores,
  runSocialPostFeedMetadataBackfill,
  runSocialPostHomeMetadataBackfill,
} = require("../lib/social/socialFeedFunctions.js");

class FakeDocSnapshot {
  constructor(ref, data) {
    this.ref = ref;
    this.id = ref.id;
    this._data = data;
    this.exists = data !== undefined;
  }

  data() {
    return this._data;
  }
}

class FakeDocRef {
  constructor(firestore, path) {
    this.firestore = firestore;
    this.path = path;
    this.id = path.split("/").pop();
  }

  async get() {
    return new FakeDocSnapshot(this, this.firestore.store.get(this.path));
  }

  async set(data, options) {
    this.firestore._set(this.path, data, options);
  }
}

class FakeQuerySnapshot {
  constructor(docs) {
    this.docs = docs;
    this.size = docs.length;
    this.empty = docs.length === 0;
  }
}

class FakeBatch {
  constructor(firestore) {
    this.firestore = firestore;
    this.operations = [];
  }

  set(ref, data, options) {
    this.operations.push({ref, data, options});
  }

  async commit() {
    for (const operation of this.operations) {
      this.firestore._set(operation.ref.path, operation.data, operation.options);
    }
  }
}

class FakeQuery {
  constructor(
    firestore,
    path,
    filters = [],
    orderBys = [],
    limitCount = null,
    startAfterValue = null,
  ) {
    this.firestore = firestore;
    this.path = path;
    this.filters = filters;
    this.orderBys = orderBys;
    this.limitCount = limitCount;
    this.startAfterValue = startAfterValue;
  }

  where(field, operator, value) {
    return new FakeQuery(
      this.firestore,
      this.path,
      [...this.filters, {field, operator, value}],
      this.orderBys,
      this.limitCount,
      this.startAfterValue,
    );
  }

  orderBy(field, direction = "asc") {
    return new FakeQuery(
      this.firestore,
      this.path,
      this.filters,
      [...this.orderBys, {field, direction}],
      this.limitCount,
      this.startAfterValue,
    );
  }

  limit(count) {
    return new FakeQuery(
      this.firestore,
      this.path,
      this.filters,
      this.orderBys,
      count,
      this.startAfterValue,
    );
  }

  startAfter(value) {
    return new FakeQuery(
      this.firestore,
      this.path,
      this.filters,
      this.orderBys,
      this.limitCount,
      value,
    );
  }

  async get() {
    const prefix = `${this.path}/`;
    let docs = Array.from(this.firestore.store.entries())
      .filter(([path]) => path.startsWith(prefix))
      .filter(([path]) => !path.slice(prefix.length).includes("/"))
      .map(([path, data]) => new FakeDocSnapshot(new FakeDocRef(this.firestore, path), data));

    for (const filter of this.filters) {
      docs = docs.filter((doc) => {
        const fieldValue = doc.data()?.[filter.field];
        if (filter.operator === "==") {
          return fieldValue === filter.value;
        }
        if (filter.operator === "in") {
          return Array.isArray(filter.value) && filter.value.includes(fieldValue);
        }
        throw new Error(`Unsupported operator ${filter.operator}`);
      });
    }

    if (this.orderBys.length > 0) {
      docs.sort((left, right) => {
        for (const orderBy of this.orderBys) {
          const leftValue = orderBy.field instanceof FieldPath ?
            left.id :
            left.data()?.[orderBy.field];
          const rightValue = orderBy.field instanceof FieldPath ?
            right.id :
            right.data()?.[orderBy.field];
          const modifier = orderBy.direction === "desc" ? -1 : 1;
          if (leftValue === rightValue) continue;
          if (typeof leftValue === "number" && typeof rightValue === "number") {
            return (leftValue - rightValue) * modifier;
          }
          return String(leftValue ?? "").localeCompare(String(rightValue ?? "")) * modifier;
        }
        return 0;
      });
    }

    if (this.startAfterValue != null) {
      docs = docs.filter((doc) => doc.id > this.startAfterValue);
    }

    if (this.limitCount != null) {
      docs = docs.slice(0, this.limitCount);
    }

    return new FakeQuerySnapshot(docs);
  }
}

class FakeCollectionRef {
  constructor(firestore, path) {
    this.firestore = firestore;
    this.path = path;
  }

  doc(id) {
    return new FakeDocRef(this.firestore, `${this.path}/${id}`);
  }

  where(field, operator, value) {
    return new FakeQuery(this.firestore, this.path, [{field, operator, value}]);
  }

  orderBy(field, direction) {
    return new FakeQuery(this.firestore, this.path, [], [{field, direction}]);
  }
}

class FakeFirestore {
  constructor(seed = {}) {
    this.store = new Map(Object.entries(seed));
  }

  collection(path) {
    return new FakeCollectionRef(this, path);
  }

  doc(path) {
    return new FakeDocRef(this, path);
  }

  batch() {
    return new FakeBatch(this);
  }

  _set(path, data, options = {}) {
    const existing = this.store.get(path) ?? {};
    this.store.set(path, options.merge ? deepMerge(existing, data) : deepMerge({}, data));
  }
}

function isPlainObject(value) {
  return value != null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype;
}

function isDeleteTransform(value) {
  return value != null && value.constructor?.name === "DeleteTransform";
}

function isServerTimestampTransform(value) {
  return value != null && value.constructor?.name === "ServerTimestampTransform";
}

function deepMerge(existing, next) {
  const result = isPlainObject(existing) ? {...existing} : {};
  for (const [key, value] of Object.entries(next)) {
    if (isDeleteTransform(value)) {
      delete result[key];
      continue;
    }
    if (isServerTimestampTransform(value)) {
      result[key] = Timestamp.fromDate(new Date("2026-07-31T12:00:00.000Z"));
      continue;
    }
    if (isPlainObject(value) && isPlainObject(result[key])) {
      result[key] = deepMerge(result[key], value);
      continue;
    }
    result[key] = value;
  }
  return result;
}

function buildPost(overrides = {}) {
  const now = new Date("2026-07-31T12:00:00.000Z");
  return {
    id: "post-default",
    authorId: "author-1",
    authorCity: "Balaghat",
    authorState: "Madhya Pradesh",
    likeCount: 0,
    commentCount: 0,
    shareCount: 0,
    reportCount: 0,
    visibilityStatus: "visible",
    moderationStatus: "approved",
    createdAtEpoch: now.getTime(),
    createdAt: Timestamp.fromDate(now),
    homeScore: 0,
    homeRankVersion: 0,
    homeEligible: false,
    discoverScore: 0,
    discoverRankVersion: 0,
    discoverEligible: false,
    nearbyEligible: false,
    feedGeohash3: "",
    feedGeohash4: "",
    feedGeohash5: "",
    feedLatitudeBucket: 0,
    feedLongitudeBucket: 0,
    feedLocationVersion: 0,
    feedCityKey: "",
    feedStateKey: "",
    ...overrides,
  };
}

function buildPrivatePostLocation(overrides = {}) {
  return {
    feedLocation: {
      latitudeBucket: 21.81,
      longitudeBucket: 80.18,
      feedLocationVersion: 2,
      ...overrides,
    },
    updatedAt: Timestamp.fromDate(new Date("2026-07-31T12:00:00.000Z")),
  };
}

function buildUser(overrides = {}) {
  return {
    uid: "author-1",
    isActive: true,
    isDeleted: false,
    deletionRequested: false,
    accountStatus: "active",
    profileVisibility: "public",
    name: "Author One",
    username: "authorone",
    usernameLowercase: "authorone",
    ...overrides,
  };
}

const noopLogger = {
  info() {},
  error() {},
};

test("zero-engagement new post receives the baseline discover score", () => {
  const now = new Date("2026-07-31T12:00:00.000Z");
  const breakdown = computeDiscoverScoreBreakdown(buildPost(), now.getTime());
  assert.equal(breakdown.discoverEligible, true);
  assert.equal(breakdown.weightedEngagement, 0);
  assert.equal(breakdown.discoverScore, 1.25);
});

test("comments and shares carry higher weight than likes for the same count", () => {
  const nowMs = new Date("2026-07-31T12:00:00.000Z").getTime();
  const likes = computeDiscoverScoreBreakdown(buildPost({likeCount: 3}), nowMs);
  const comments = computeDiscoverScoreBreakdown(buildPost({commentCount: 3}), nowMs);
  const shares = computeDiscoverScoreBreakdown(buildPost({shareCount: 3}), nowMs);

  assert.ok(comments.discoverScore > likes.discoverScore);
  assert.ok(shares.discoverScore > comments.discoverScore);
});

test("home scoring applies freshness, admin boost, and report penalties", () => {
  const nowMs = new Date("2026-07-31T12:00:00.000Z").getTime();
  const freshPopular = computeHomeScoreBreakdown(
    buildPost({
      likeCount: 8,
      commentCount: 3,
      shareCount: 2,
      recentEngagementScore: 4,
      adminPriorityBoost: 8,
    }),
    nowMs,
  );
  const olderReported = computeHomeScoreBreakdown(
    buildPost({
      likeCount: 8,
      commentCount: 3,
      shareCount: 2,
      recentEngagementScore: 4,
      createdAtEpoch: nowMs - (72 * 60 * 60 * 1000),
      createdAt: Timestamp.fromMillis(nowMs - (72 * 60 * 60 * 1000)),
      reportCount: 4,
    }),
    nowMs,
  );

  assert.equal(freshPopular.homeEligible, true);
  assert.ok(freshPopular.homeScore > olderReported.homeScore);
  assert.ok(freshPopular.adminBoost > 0);
  assert.ok(olderReported.reportPenalty > 0);
});

test("home scoring excludes non-visible or unapproved posts", () => {
  const hidden = computeHomeScoreBreakdown(
    buildPost({visibilityStatus: "hidden"}),
    new Date("2026-07-31T12:00:00.000Z").getTime(),
  );
  const pending = computeHomeScoreBreakdown(
    buildPost({moderationStatus: "pending"}),
    new Date("2026-07-31T12:00:00.000Z").getTime(),
  );

  assert.equal(hidden.homeEligible, false);
  assert.equal(hidden.homeScore, 0);
  assert.equal(pending.homeEligible, false);
  assert.equal(pending.homeScore, 0);
});

test("privacy-safe feed metadata keeps precise location private and only returns public geohash metadata", () => {
  const metadata = buildFeedMetadata(buildPost(), Date.now(), {
    creationLocation: {
      latitude: 21.81341,
      longitude: 80.18324,
      city: "Balaghat",
      state: "Madhya Pradesh",
      country: "India",
      geohash3: "te7",
      geohash4: "te7g",
      geohash5: "te7g4",
    },
  });

  assert.equal(metadata.nearbyEligible, true);
  assert.equal(metadata.feedLocationVersion, 2);
  assert.equal(metadata.feedGeohash5, "te7g4");
  assert.equal(metadata.feedCityKey, "balaghat");
  assert.equal(metadata.feedStateKey, "madhya pradesh");
  assert.equal("feedLatitudeBucket" in metadata, false);
  assert.equal("feedLongitudeBucket" in metadata, false);
});

test("post location stays immutable when an author moves and new posts use the new creation location", () => {
  const locationA = {
    latitude: 21.8134,
    longitude: 80.1832,
    city: "Balaghat",
    state: "Madhya Pradesh",
    country: "India",
    geohash3: encodeGeohash(21.8134, 80.1832, 3),
    geohash4: encodeGeohash(21.8134, 80.1832, 4),
    geohash5: encodeGeohash(21.8134, 80.1832, 5),
  };
  const locationB = {
    latitude: 18.5204,
    longitude: 73.8567,
    city: "Pune",
    state: "Maharashtra",
    country: "India",
    geohash3: encodeGeohash(18.5204, 73.8567, 3),
    geohash4: encodeGeohash(18.5204, 73.8567, 4),
    geohash5: encodeGeohash(18.5204, 73.8567, 5),
  };
  const oldPostMetadata = buildFeedMetadata(buildPost({id: "A1"}), Date.now(), {
    creationLocation: locationA,
  });
  const oldPostAfterMove = buildFeedMetadata(
    {...buildPost({id: "A1"}), ...oldPostMetadata},
    Date.now(),
    {creationLocation: locationB},
  );
  const newPostMetadata = buildFeedMetadata(buildPost({id: "B1"}), Date.now(), {
    creationLocation: locationB,
  });

  assert.equal(oldPostAfterMove.feedGeohash5, locationA.geohash5);
  assert.equal(newPostMetadata.feedGeohash5, locationB.geohash5);
  assert.notEqual(oldPostAfterMove.feedGeohash5, newPostMetadata.feedGeohash5);
});

test("post-specific creation intent wins without consulting stale author location", () => {
  const resolved = resolvePostSpecificLocationMetadata({
    postData: buildPost({id: "B1", authorId: "viewer"}),
    privateData: undefined,
    intentData: {
      ownerUid: "viewer",
      source: "freshDeviceAtPublish",
      location: {
        latitude: 18.5204,
        longitude: 73.8567,
        city: "Pune",
        state: "Maharashtra",
        country: "India",
      },
      capturedAt: Timestamp.fromDate(new Date("2026-09-25T12:00:00.000Z")),
    },
    authorId: "viewer",
  });

  assert.equal(resolved.intent.ownerUid, "viewer");
  assert.equal(resolved.privateLocation.latitudeBucket, 18.52);
  assert.equal(resolved.privateLocation.longitudeBucket, 73.86);
  assert.equal(resolved.metadata.feedGeohash5, encodeGeohash(18.52, 73.86, 5));
  assert.equal(resolved.metadata.feedCityKey, "pune");
  assert.equal(resolved.metadata.feedStateKey, "maharashtra");
});

test("post intent public GeoHash is derived from the persisted private bucket", () => {
  const resolved = resolvePostSpecificLocationMetadata({
    postData: buildPost({id: "boundary", authorId: "viewer"}),
    intentData: {
      ownerUid: "viewer",
      source: "freshDeviceAtPublish",
      location: {
        latitude: 23.293169,
        longitude: 77.420000,
        city: "Bhopal",
        state: "Madhya Pradesh",
        country: "India",
      },
      capturedAt: Timestamp.fromDate(new Date("2026-09-25T12:00:00.000Z")),
    },
    authorId: "viewer",
  });

  const expected = encodeGeohash(
    resolved.privateLocation.latitudeBucket,
    resolved.privateLocation.longitudeBucket,
    5,
  );
  assert.notEqual(expected, encodeGeohash(23.293169, 77.420000, 5));
  assert.equal(resolved.metadata.feedGeohash5, expected);
});

test("ranking input guard ignores metadata-only changes and metadata match prevents duplicate writes", () => {
  const nowMs = new Date("2026-07-31T12:00:00.000Z").getTime();
  const before = buildPost();
  const expectedMetadata = buildFeedMetadata(before, nowMs);
  const after = {...before, ...expectedMetadata};

  assert.equal(rankingInputsEqual(buildRankingInputs(before), buildRankingInputs(after)), true);
  assert.equal(metadataMatchesCurrent(after, buildFeedMetadata(after, nowMs)), true);
});

test("feed metadata includes backend-owned home ranking fields", () => {
  const metadata = buildFeedMetadata(buildPost({likeCount: 5}), Date.now());

  assert.equal(typeof metadata.homeScore, "number");
  assert.equal(metadata.homeEligible, true);
  assert.equal(metadata.homeRankVersion > 0, true);
});

test("scheduled refresh updates scores after the post crosses an age bucket", async () => {
  const start = new Date("2026-07-31T12:00:00.000Z");
  const createdAt = new Date(start.getTime() - (5 * 60 * 60 * 1000));
  const firestore = new FakeFirestore({
    "socialPosts/postA": buildPost({
      id: "postA",
      likeCount: 5,
      createdAtEpoch: createdAt.getTime(),
      createdAt: Timestamp.fromDate(createdAt),
      discoverScore: 0,
      discoverRankVersion: 0,
      discoverEligible: false,
    }),
  });

  const beforeScore = firestore.store.get("socialPosts/postA").discoverScore;
  const summary = await runRefreshSocialPostDiscoverScores({
    authoritativeNow: new Date("2026-08-01T04:30:00.000Z"),
    firestore,
    schedulerLogger: noopLogger,
    skipLease: true,
  });
  const after = firestore.store.get("socialPosts/postA");

  assert.equal(summary.updated, 1);
  assert.ok(after.discoverScore > 0);
  assert.notEqual(after.discoverScore, beforeScore);
  assert.ok(after.homeScore > 0);
});

test("home metadata backfill updates stale home ranking fields only", async () => {
  const firestore = new FakeFirestore({
    "socialPosts/postA": buildPost({
      id: "postA",
      likeCount: 10,
      homeScore: 0,
      homeRankVersion: 0,
      homeEligible: false,
    }),
    "socialPosts/postB": buildPost({
      id: "postB",
      moderationStatus: "pending",
      homeScore: 0,
      homeRankVersion: 0,
      homeEligible: false,
    }),
  });

  const dryRun = await runSocialPostHomeMetadataBackfill({
    firestore,
    dryRun: true,
    limit: 10,
  });
  assert.equal(dryRun.scanned, 2);
  assert.equal(dryRun.updated, 2);

  const summary = await runSocialPostHomeMetadataBackfill({
    firestore,
    dryRun: false,
    limit: 10,
  });
  const updatedA = firestore.store.get("socialPosts/postA");
  const updatedB = firestore.store.get("socialPosts/postB");

  assert.equal(summary.updated, 2);
  assert.ok(updatedA.homeScore > 0);
  assert.equal(updatedA.homeEligible, true);
  assert.equal(updatedA.homeRankVersion > 0, true);
  assert.equal(updatedB.homeEligible, false);
  assert.equal(updatedB.homeRankVersion > 0, true);
});

test("distance calculation and formatting support metre and kilometre labels", () => {
  const shortDistance = calculateDistanceKm(21.8134, 80.1832, 21.814, 80.1832);
  const longerDistance = calculateDistanceKm(21.8134, 80.1832, 21.9134, 80.1832);

  assert.ok(shortDistance > 0 && shortDistance < 1);
  assert.match(formatNearbyDistanceLabel(shortDistance), /m away$/);
  assert.ok(longerDistance > 10);
  assert.match(formatNearbyDistanceLabel(longerDistance), /km away$/);
});

test("nearby scoring favors closer fresher posts and excludes posts outside 50 km", () => {
  const now = new Date("2026-07-31T12:00:00.000Z");
  const closeFresh = computeNearbyScoreBreakdown(
    buildPost({nearbyEligible: true, likeCount: 1, commentCount: 1}),
    21.81,
    80.18,
    now.getTime(),
    {latitudeBucket: 21.81, longitudeBucket: 80.18, feedLocationVersion: 2},
  );
  const farOld = computeNearbyScoreBreakdown(
    buildPost({
      nearbyEligible: true,
      likeCount: 20,
      commentCount: 4,
      createdAtEpoch: now.getTime() - (500 * 60 * 60 * 1000),
      createdAt: Timestamp.fromDate(new Date(now.getTime() - (500 * 60 * 60 * 1000))),
    }),
    21.81,
    80.18,
    now.getTime(),
    {latitudeBucket: 22.25, longitudeBucket: 80.18, feedLocationVersion: 2},
  );

  assert.equal(closeFresh.nearbyEligible, true);
  assert.ok(closeFresh.nearbyScore > farOld.nearbyScore);

  const outside = computeNearbyScoreBreakdown(
    buildPost({nearbyEligible: true}),
    21.81,
    80.18,
    now.getTime(),
    {latitudeBucket: 23.0, longitudeBucket: 80.18, feedLocationVersion: 2},
  );
  assert.equal(outside.nearbyEligible, false);
});

test("nearby applies the 50 km radius at the distance boundary", () => {
  const latitude = 21.8134;
  const insideLatitude = latitude + (49.9 / 111.195);
  const outsideLatitude = latitude + (50.1 / 111.195);
  const inside = computeNearbyScoreBreakdown(
    buildPost({nearbyEligible: true}),
    latitude,
    80.1832,
    Date.now(),
    {latitudeBucket: insideLatitude, longitudeBucket: 80.1832, feedLocationVersion: 2},
  );
  const outside = computeNearbyScoreBreakdown(
    buildPost({nearbyEligible: true}),
    latitude,
    80.1832,
    Date.now(),
    {latitudeBucket: outsideLatitude, longitudeBucket: 80.1832, feedLocationVersion: 2},
  );

  assert.equal(inside.nearbyEligible, true);
  assert.equal(outside.nearbyEligible, false);
});

test("nearby GeoHash candidates include the adjacent cell across a boundary", () => {
  const originalHash = encodeGeohash(21.8134, 80.1832, 3);
  const bounds = decodeGeohashBounds(originalHash);
  assert.ok(bounds);
  const latitude = (bounds.minLat + bounds.maxLat) / 2;
  const viewerHash = encodeGeohash(latitude, bounds.maxLon - 0.001, 3);
  const adjacentHash = encodeGeohash(latitude, bounds.maxLon + 0.001, 3);

  assert.notEqual(viewerHash, adjacentHash);
  assert.ok(geohashPrefixesAround(viewerHash).includes(adjacentHash));
});

test("nearby query ranks by distance, paginates via sessions, and omits public buckets", async () => {
  const firestore = new FakeFirestore({
    "userPrivate/viewer": {
      exploreLocation: {
        latitude: 21.8134,
        longitude: 80.1832,
        city: "Balaghat",
        state: "Madhya Pradesh",
        geohash3: "te7",
        geohash4: "te7g",
        geohash5: "te7g4",
      },
    },
    "users/viewer": {city: "Balaghat", state: "Madhya Pradesh"},
    "users/author-1": buildUser({uid: "author-1"}),
    "users/author-2": buildUser({uid: "author-2", username: "author2", usernameLowercase: "author2"}),
    "users/author-3": buildUser({uid: "author-3", username: "author3", usernameLowercase: "author3"}),
    "socialPosts/closeFresh": buildPost({
      id: "closeFresh",
      authorId: "author-1",
      nearbyEligible: true,
      feedGeohash3: "te7",
      feedGeohash4: "te7g",
      feedGeohash5: "te7g4",
      likeCount: 1,
      createdAtEpoch: new Date("2026-07-31T11:30:00.000Z").getTime(),
    }),
    "socialPostPrivate/closeFresh": buildPrivatePostLocation(),
    "socialPosts/midEngaged": buildPost({
      id: "midEngaged",
      authorId: "author-2",
      nearbyEligible: true,
      feedGeohash3: "te7",
      feedGeohash4: "te7g",
      feedGeohash5: "te7g5",
      likeCount: 12,
      commentCount: 4,
      createdAtEpoch: new Date("2026-07-31T10:00:00.000Z").getTime(),
    }),
    "socialPostPrivate/midEngaged": buildPrivatePostLocation({
      latitudeBucket: 21.88,
      longitudeBucket: 80.18,
    }),
    "socialPosts/farButEligible": buildPost({
      id: "farButEligible",
      authorId: "author-3",
      nearbyEligible: true,
      feedGeohash3: "te7",
      feedGeohash4: "te7h",
      feedGeohash5: "te7h1",
      likeCount: 3,
      createdAtEpoch: new Date("2026-07-31T11:00:00.000Z").getTime(),
    }),
    "socialPostPrivate/farButEligible": buildPrivatePostLocation({
      latitudeBucket: 21.98,
      longitudeBucket: 80.18,
    }),
  });

  const firstPage = await runNearbyFeedQuery({
    uid: "viewer",
    limit: 1,
    firestore,
    authoritativeNow: new Date("2026-07-31T12:00:00.000Z"),
  });

  assert.equal(firstPage.posts.length, 1);
  assert.ok(["closeFresh", "midEngaged", "farButEligible"].includes(firstPage.posts[0].id));
  assert.equal(firstPage.posts[0].usesNearbyFallback, false);
  assert.match(firstPage.posts[0].nearbyDistanceLabel, /(m|km) away$/);
  assert.equal("feedLatitudeBucket" in firstPage.posts[0], false);
  assert.equal("feedLongitudeBucket" in firstPage.posts[0], false);
  assert.ok(firstPage.nextCursor.sessionId);

  const secondPage = await runNearbyFeedQuery({
    uid: "viewer",
    limit: 1,
    cursor: firstPage.nextCursor,
    firestore,
    authoritativeNow: new Date("2026-07-31T12:00:00.000Z"),
  });

  assert.equal(secondPage.posts.length, 1);
  assert.notEqual(secondPage.posts[0].id, firstPage.posts[0].id);
});

test("nearby query falls back to city/state when precise coordinates are unavailable", async () => {
  const firestore = new FakeFirestore({
    "users/viewer": {city: "Balaghat", state: "Madhya Pradesh"},
    "users/author-1": buildUser({uid: "author-1"}),
    "socialPosts/cityPost": buildPost({
      id: "cityPost",
      authorId: "author-1",
      feedCityKey: "balaghat",
      feedStateKey: "madhya pradesh",
      discoverScore: 3.2,
    }),
  });

  const response = await runNearbyFeedQuery({
    uid: "viewer",
    limit: 10,
    firestore,
  });

  assert.equal(response.usedCityStateFallback, true);
  assert.equal(response.locationMode, "savedCityState");
  assert.equal(response.posts.length, 1);
  assert.equal(response.posts[0].nearbyDistanceLabel, "Near your city");
  assert.equal(response.posts[0].usesNearbyFallback, true);
});

test("nearby includes the viewer's and other users' eligible posts within 50 km", async () => {
  const firestore = new FakeFirestore({
    "userPrivate/viewer": {
      exploreLocation: {
        latitude: 21.8134,
        longitude: 80.1832,
        city: "Balaghat",
        state: "Madhya Pradesh",
        geohash3: "te7",
        geohash4: "te7g",
        geohash5: "te7g4",
      },
    },
    "users/viewer": buildUser({uid: "viewer", username: "viewer", usernameLowercase: "viewer"}),
    "users/user-b": buildUser({uid: "user-b", username: "userb", usernameLowercase: "userb"}),
  });
  const posts = [
    ["a1", "viewer", 21.8224],
    ["a2", "viewer", 21.9934],
    ["b1", "user-b", 21.8314],
    ["b2", "user-b", 22.0834],
    ["outside", "user-b", 22.3534],
  ];
  for (const [id, authorId, latitudeBucket] of posts) {
    firestore.store.set(`socialPosts/${id}`, buildPost({
      id,
      authorId,
      nearbyEligible: true,
      feedGeohash3: "te7",
      feedGeohash4: "te7g",
      feedGeohash5: "te7g4",
    }));
    firestore.store.set(
      `socialPostPrivate/${id}`,
      buildPrivatePostLocation({latitudeBucket, longitudeBucket: 80.1832}),
    );
  }

  const response = await runNearbyFeedQuery({
    uid: "viewer",
    limit: 10,
    firestore,
    authoritativeNow: new Date("2026-07-31T12:00:00.000Z"),
  });

  assert.deepStrictEqual(
    new Set(response.posts.map((post) => post.id)),
    new Set(["a1", "a2", "b1", "b2"]),
  );
  assert.equal(response.locationMode, "radius");
  assert.equal(response.activeRadiusKm, 50);
});

test("nearby candidate collection is not truncated at the former 40-post pool limit", async () => {
  const seed = {
    "userPrivate/viewer": {
      exploreLocation: {
        latitude: 21.8134,
        longitude: 80.1832,
        city: "Balaghat",
        state: "Madhya Pradesh",
        geohash3: "te7",
        geohash4: "te7g",
        geohash5: "te7g4",
      },
    },
    "users/viewer": buildUser({uid: "viewer", username: "viewer", usernameLowercase: "viewer"}),
    "users/user-b": buildUser({uid: "user-b", username: "userb", usernameLowercase: "userb"}),
  };
  for (let index = 0; index < 70; index += 1) {
    const id = `dense-${String(index).padStart(2, "0")}`;
    const authorId = index % 2 === 0 ? "viewer" : "user-b";
    seed[`socialPosts/${id}`] = buildPost({
      id,
      authorId,
      nearbyEligible: true,
      feedGeohash3: "te7",
      feedGeohash4: "te7g",
      feedGeohash5: "te7g4",
      createdAtEpoch: new Date("2026-07-31T12:00:00.000Z").getTime() - index,
    });
    seed[`socialPostPrivate/${id}`] = buildPrivatePostLocation();
  }
  const firestore = new FakeFirestore(seed);
  const received = [];
  let cursor = null;
  do {
    const page = await runNearbyFeedQuery({
      uid: "viewer",
      limit: 20,
      cursor,
      firestore,
      authoritativeNow: new Date("2026-07-31T12:00:00.000Z"),
    });
    received.push(...page.posts.map((post) => post.id));
    cursor = page.nextCursor;
  } while (cursor != null);

  assert.equal(received.length, 70);
  assert.equal(new Set(received).size, 70);
  assert.ok(received.some((id) => id === "dense-00"));
  assert.ok(received.some((id) => id === "dense-69"));
});

test("nearby refresh is deterministic and includes a newly eligible post", async () => {
  const firestore = new FakeFirestore({
    "userPrivate/viewer": {
      exploreLocation: {
        latitude: 21.8134,
        longitude: 80.1832,
        city: "Balaghat",
        state: "Madhya Pradesh",
        geohash3: "te7",
        geohash4: "te7g",
        geohash5: "te7g4",
      },
    },
    "users/viewer": buildUser({uid: "viewer", username: "viewer", usernameLowercase: "viewer"}),
    "users/user-b": buildUser({uid: "user-b", username: "userb", usernameLowercase: "userb"}),
    "socialPosts/own": buildPost({id: "own", authorId: "viewer", nearbyEligible: true, feedGeohash3: "te7", feedGeohash4: "te7g", feedGeohash5: "te7g4"}),
    "socialPostPrivate/own": buildPrivatePostLocation(),
    "socialPosts/other": buildPost({id: "other", authorId: "user-b", nearbyEligible: true, feedGeohash3: "te7", feedGeohash4: "te7g", feedGeohash5: "te7g4"}),
    "socialPostPrivate/other": buildPrivatePostLocation({latitudeBucket: 21.82}),
  });

  const first = await runNearbyFeedQuery({uid: "viewer", limit: 20, firestore});
  const refreshed = await runNearbyFeedQuery({uid: "viewer", limit: 20, firestore});
  assert.deepStrictEqual(
    refreshed.posts.map((post) => post.id),
    first.posts.map((post) => post.id),
  );

  firestore.store.set("socialPosts/new-own", buildPost({
    id: "new-own",
    authorId: "viewer",
    nearbyEligible: true,
    feedGeohash3: "te7",
    feedGeohash4: "te7g",
    feedGeohash5: "te7g4",
    createdAtEpoch: Date.now() + 1,
  }));
  firestore.store.set("socialPostPrivate/new-own", buildPrivatePostLocation());
  const afterCreate = await runNearbyFeedQuery({uid: "viewer", limit: 20, firestore});
  assert.ok(afterCreate.posts.some((post) => post.id === "new-own"));
  assert.ok(afterCreate.posts.some((post) => post.id === "own"));
  assert.ok(afterCreate.posts.some((post) => post.id === "other"));
});

test("nearby excludes an own post stored far away while returning multiple nearby authors", async () => {
  const firestore = new FakeFirestore({
    "userPrivate/viewer": {
      exploreLocation: {
        latitude: 21.8134,
        longitude: 80.1832,
        city: "Balaghat",
        state: "Madhya Pradesh",
        geohash3: "te7",
        geohash4: "te7g",
        geohash5: "te7g4",
      },
    },
    "users/viewer": buildUser({uid: "viewer", username: "viewer", usernameLowercase: "viewer"}),
    "users/user-b": buildUser({uid: "user-b", username: "userb", usernameLowercase: "userb"}),
    "users/user-c": buildUser({uid: "user-c", username: "userc", usernameLowercase: "userc"}),
    "socialPosts/own-far": buildPost({
      id: "own-far",
      authorId: "viewer",
      nearbyEligible: true,
      feedGeohash3: "ttn",
      feedGeohash4: "ttnf",
      feedGeohash5: "ttnfv",
    }),
    "socialPostPrivate/own-far": buildPrivatePostLocation({
      latitudeBucket: 28.61,
      longitudeBucket: 77.21,
    }),
    "socialPosts/nearby-own": buildPost({id: "nearby-own", authorId: "viewer", nearbyEligible: true, feedGeohash3: "te7", feedGeohash4: "te7g", feedGeohash5: "te7g4"}),
    "socialPostPrivate/nearby-own": buildPrivatePostLocation(),
    "socialPosts/nearby-b": buildPost({id: "nearby-b", authorId: "user-b", nearbyEligible: true, feedGeohash3: "te7", feedGeohash4: "te7g", feedGeohash5: "te7g4"}),
    "socialPostPrivate/nearby-b": buildPrivatePostLocation({latitudeBucket: 21.82}),
    "socialPosts/nearby-c": buildPost({id: "nearby-c", authorId: "user-c", nearbyEligible: true, feedGeohash3: "te7", feedGeohash4: "te7g", feedGeohash5: "te7g4"}),
    "socialPostPrivate/nearby-c": buildPrivatePostLocation({longitudeBucket: 80.19}),
  });

  const response = await runNearbyFeedQuery({
    uid: "viewer",
    limit: 20,
    firestore,
    debugDiagnostics: true,
  });
  const ids = response.posts.map((post) => post.id);

  assert.equal(ids.includes("own-far"), false);
  assert.deepStrictEqual(new Set(ids), new Set(["nearby-own", "nearby-b", "nearby-c"]));
});

test("nearby handles missing post location without crashing or broadening results", async () => {
  const firestore = new FakeFirestore({
    "userPrivate/viewer": {
      exploreLocation: {
        latitude: 21.8134,
        longitude: 80.1832,
        city: "Balaghat",
        state: "Madhya Pradesh",
        geohash3: "te7",
        geohash4: "te7g",
        geohash5: "te7g4",
      },
    },
    "users/viewer": buildUser({uid: "viewer", username: "viewer", usernameLowercase: "viewer"}),
    "socialPosts/malformed": buildPost({
      id: "malformed",
      authorId: "viewer",
      nearbyEligible: true,
      feedGeohash3: "te7",
      feedGeohash4: "te7g",
      feedGeohash5: "te7g4",
    }),
  });

  const response = await runNearbyFeedQuery({uid: "viewer", limit: 20, firestore});
  assert.deepStrictEqual(response.posts, []);
});

test("nearby session paging refills past posts hidden after session creation", async () => {
  const firestore = new FakeFirestore({
    "userPrivate/viewer": {
      exploreLocation: {
        latitude: 21.8134,
        longitude: 80.1832,
        city: "Balaghat",
        state: "Madhya Pradesh",
        geohash3: "te7",
        geohash4: "te7g",
        geohash5: "te7g4",
      },
    },
    "users/viewer": buildUser({uid: "viewer", username: "viewer", usernameLowercase: "viewer"}),
    "socialPosts/p1": buildPost({id: "p1", authorId: "viewer", nearbyEligible: true, feedGeohash3: "te7", feedGeohash4: "te7g", feedGeohash5: "te7g4", createdAtEpoch: 3}),
    "socialPosts/p2": buildPost({id: "p2", authorId: "viewer", nearbyEligible: true, feedGeohash3: "te7", feedGeohash4: "te7g", feedGeohash5: "te7g4", createdAtEpoch: 2}),
    "socialPosts/p3": buildPost({id: "p3", authorId: "viewer", nearbyEligible: true, feedGeohash3: "te7", feedGeohash4: "te7g", feedGeohash5: "te7g4", createdAtEpoch: 1}),
    "socialPostPrivate/p1": buildPrivatePostLocation(),
    "socialPostPrivate/p2": buildPrivatePostLocation(),
    "socialPostPrivate/p3": buildPrivatePostLocation(),
  });
  const first = await runNearbyFeedQuery({uid: "viewer", limit: 1, firestore});
  const sessionPath = `nearbyFeedSessions/${first.nextCursor.sessionId}`;
  const ordered = firestore.store.get(sessionPath).orderedPosts;
  const hiddenId = ordered[1].id;
  firestore.store.set(`socialPosts/${hiddenId}`, {
    ...firestore.store.get(`socialPosts/${hiddenId}`),
    visibilityStatus: "hidden",
  });

  const second = await runNearbyFeedQuery({
    uid: "viewer",
    limit: 1,
    cursor: first.nextCursor,
    firestore,
  });

  assert.equal(second.posts.length, 1);
  assert.notEqual(second.posts[0].id, hiddenId);
  assert.notEqual(second.posts[0].id, first.posts[0].id);
});

test("nearby sessions keep paging stable when engagement changes between pages", async () => {
  const firestore = new FakeFirestore({
    "userPrivate/viewer": {
      exploreLocation: {
        latitude: 21.8134,
        longitude: 80.1832,
        city: "Balaghat",
        state: "Madhya Pradesh",
        geohash3: "te7",
        geohash4: "te7g",
        geohash5: "te7g4",
      },
    },
    "users/viewer": {city: "Balaghat", state: "Madhya Pradesh"},
    "users/author-1": buildUser({uid: "author-1"}),
    "users/author-2": buildUser({uid: "author-2", username: "author2", usernameLowercase: "author2"}),
    "socialPosts/postA": buildPost({
      id: "postA",
      authorId: "author-1",
      nearbyEligible: true,
      feedGeohash3: "te7",
      feedGeohash4: "te7g",
      feedGeohash5: "te7g4",
      likeCount: 1,
      createdAtEpoch: new Date("2026-07-31T11:50:00.000Z").getTime(),
    }),
    "socialPostPrivate/postA": buildPrivatePostLocation(),
    "socialPosts/postB": buildPost({
      id: "postB",
      authorId: "author-2",
      nearbyEligible: true,
      feedGeohash3: "te7",
      feedGeohash4: "te7g",
      feedGeohash5: "te7g5",
      likeCount: 1,
      createdAtEpoch: new Date("2026-07-31T11:40:00.000Z").getTime(),
    }),
    "socialPostPrivate/postB": buildPrivatePostLocation({
      latitudeBucket: 21.84,
      longitudeBucket: 80.18,
    }),
  });

  const firstPage = await runNearbyFeedQuery({
    uid: "viewer",
    limit: 1,
    firestore,
    authoritativeNow: new Date("2026-07-31T12:00:00.000Z"),
  });

  firestore.store.set("socialPosts/postB", {
    ...firestore.store.get("socialPosts/postB"),
    likeCount: 200,
    commentCount: 40,
    discoverScore: 100,
  });

  const secondPage = await runNearbyFeedQuery({
    uid: "viewer",
    limit: 1,
    cursor: firstPage.nextCursor,
    firestore,
    authoritativeNow: new Date("2026-07-31T12:10:00.000Z"),
  });

  assert.equal(firstPage.posts.length, 1);
  assert.equal(secondPage.posts.length, 1);
  assert.notEqual(secondPage.posts[0].id, firstPage.posts[0].id);
});

test("engaged older candidates still have a bounded path into nearby results", async () => {
  const firestore = new FakeFirestore({
    "userPrivate/viewer": {
      exploreLocation: {
        latitude: 21.8134,
        longitude: 80.1832,
        city: "Balaghat",
        state: "Madhya Pradesh",
        geohash3: "te7",
        geohash4: "te7g",
        geohash5: "te7g4",
      },
    },
    "users/viewer": {city: "Balaghat", state: "Madhya Pradesh"},
    "users/author-1": buildUser({uid: "author-1"}),
    "users/author-2": buildUser({uid: "author-2", username: "author2", usernameLowercase: "author2"}),
    "socialPosts/freshLow": buildPost({
      id: "freshLow",
      authorId: "author-1",
      nearbyEligible: true,
      feedGeohash3: "te7",
      feedGeohash4: "te7g",
      feedGeohash5: "te7g4",
      likeCount: 0,
      createdAtEpoch: new Date("2026-07-31T11:58:00.000Z").getTime(),
    }),
    "socialPostPrivate/freshLow": buildPrivatePostLocation(),
    "socialPosts/olderHigh": buildPost({
      id: "olderHigh",
      authorId: "author-2",
      nearbyEligible: true,
      feedGeohash3: "te7",
      feedGeohash4: "te7g",
      feedGeohash5: "te7g4",
      likeCount: 50,
      commentCount: 12,
      shareCount: 5,
      createdAtEpoch: new Date("2026-07-29T12:00:00.000Z").getTime(),
    }),
    "socialPostPrivate/olderHigh": buildPrivatePostLocation({
      latitudeBucket: 21.82,
      longitudeBucket: 80.18,
    }),
  });

  const response = await runNearbyFeedQuery({
    uid: "viewer",
    limit: 5,
    firestore,
    authoritativeNow: new Date("2026-07-31T12:00:00.000Z"),
  });

  assert.ok(response.posts.some((post) => post.id === "olderHigh"));
});

test("backfill migrates private location, removes public buckets, and stays idempotent on retry", async () => {
  const firestore = new FakeFirestore({
    "socialPosts/postA": buildPost({
      id: "postA",
      authorId: "author-1",
      feedLatitudeBucket: 21.81,
      feedLongitudeBucket: 80.18,
      feedLocationVersion: 1,
    }),
    "socialPosts/postB": buildPost({
      id: "postB",
      authorId: "author-1",
      feedLatitudeBucket: 21.81,
      feedLongitudeBucket: 80.18,
      feedLocationVersion: 1,
    }),
    "userPrivate/author-1": {
      exploreLocation: {
        latitude: 24.1234,
        longitude: 81.9876,
        city: "Moved City",
        state: "Moved State",
        geohash3: "zzz",
        geohash4: "zzzz",
        geohash5: "zzzzz",
      },
    },
  });

  const firstRun = await runSocialPostFeedMetadataBackfill({
    firestore,
    authoritativeNow: new Date("2026-07-31T12:00:00.000Z"),
  });
  const secondRun = await runSocialPostFeedMetadataBackfill({
    firestore,
    authoritativeNow: new Date("2026-07-31T12:00:00.000Z"),
  });
  const updated = firestore.store.get("socialPosts/postA");
  const privateLocation = firestore.store.get("socialPostPrivate/postA");

  assert.equal(firstRun.updated, 2);
  assert.equal(firstRun.privateLocationCreated, 2);
  assert.equal(firstRun.publicBucketsRemoved, 2);
  assert.ok(firstRun.authorCacheHits >= 0);
  assert.ok(firstRun.authorCacheMisses >= 0);
  assert.equal(updated.nearbyEligible, true);
  assert.equal(updated.feedLocationVersion, 2);
  assert.notEqual(updated.feedGeohash5, "zzzzz");
  assert.equal("feedLatitudeBucket" in updated, false);
  assert.equal("feedLongitudeBucket" in updated, false);
  assert.equal(privateLocation.feedLocation.latitudeBucket, 21.81);
  assert.equal(secondRun.updated, 0);
  assert.equal(secondRun.alreadyMigrated, 2);
  assert.equal(secondRun.skipped, 2);
});

test("backfill never invents a historical post location from the author's current location", async () => {
  const firestore = new FakeFirestore({
    "socialPosts/legacyMissing": buildPost({
      id: "legacyMissing",
      authorId: "author-1",
      feedLatitudeBucket: 0,
      feedLongitudeBucket: 0,
      feedLocationVersion: 0,
    }),
    "userPrivate/author-1": {
      exploreLocation: {
        latitude: 18.5204,
        longitude: 73.8567,
        city: "Pune",
        state: "Maharashtra",
        geohash3: "tek",
        geohash4: "tek1",
        geohash5: "tek1x",
      },
    },
  });

  const summary = await runSocialPostFeedMetadataBackfill({firestore});

  assert.equal(summary.updated, 0);
  assert.equal(summary.missingLocation, 1);
  assert.equal(firestore.store.has("socialPostPrivate/legacyMissing"), false);
  assert.equal(firestore.store.get("socialPosts/legacyMissing").nearbyEligible, false);
});

test("nearby backend filtering excludes blocked and inactive creators before results are returned", async () => {
  const firestore = new FakeFirestore({
    "userPrivate/viewer": {
      exploreLocation: {
        latitude: 21.8134,
        longitude: 80.1832,
        city: "Balaghat",
        state: "Madhya Pradesh",
        geohash3: "te7",
        geohash4: "te7g",
        geohash5: "te7g4",
      },
    },
    "users/viewer": {city: "Balaghat", state: "Madhya Pradesh"},
    "users/author-visible": buildUser({uid: "author-visible", username: "visible", usernameLowercase: "visible"}),
    "users/author-hidden": buildUser({
      uid: "author-hidden",
      username: "hidden",
      usernameLowercase: "hidden",
      profileVisibility: "hidden",
    }),
    "userBlocks/block1": {ownerUserId: "viewer", blockedUserId: "author-hidden"},
    "socialPosts/visiblePost": buildPost({
      id: "visiblePost",
      authorId: "author-visible",
      nearbyEligible: true,
      feedGeohash3: "te7",
      feedGeohash4: "te7g",
      feedGeohash5: "te7g4",
    }),
    "socialPostPrivate/visiblePost": buildPrivatePostLocation(),
    "socialPosts/blockedPost": buildPost({
      id: "blockedPost",
      authorId: "author-hidden",
      nearbyEligible: true,
      feedGeohash3: "te7",
      feedGeohash4: "te7g",
      feedGeohash5: "te7g4",
    }),
    "socialPostPrivate/blockedPost": buildPrivatePostLocation(),
  });

  const response = await runNearbyFeedQuery({
    uid: "viewer",
    limit: 10,
    firestore,
    authoritativeNow: new Date("2026-07-31T12:00:00.000Z"),
  });

  assert.deepStrictEqual(
    response.posts.map((post) => post.id),
    ["visiblePost"],
  );
});
