import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../../core/services/firebase_app_scope.dart';
import '../../../core/services/firestore_cache_service.dart';
import '../../social/domain/models/social_post_model.dart';
import '../../social/domain/social_feed_pagination.dart';
import '../domain/models/explore_feed_kind.dart';
import '../domain/models/explore_feed_page.dart';
import '../domain/models/explore_feed_viewer_context.dart';
import '../domain/models/nearby_location_mode.dart';
import 'explore_feed_filter_service.dart';

class ExploreNearbyAuthException implements Exception {
  const ExploreNearbyAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ExploreAuthenticatedUserSession {
  const ExploreAuthenticatedUserSession({
    required this.uid,
    required this.getIdToken,
    required this.reload,
  });

  final String uid;
  final Future<String?> Function({bool forceRefresh}) getIdToken;
  final Future<void> Function() reload;
}

abstract class ExploreNearbyAuthSession {
  ExploreAuthenticatedUserSession? get currentSession;

  Stream<ExploreAuthenticatedUserSession?> authStateChanges();
  Stream<ExploreAuthenticatedUserSession?> idTokenChanges();
}

class FirebaseExploreNearbyAuthSession implements ExploreNearbyAuthSession {
  FirebaseExploreNearbyAuthSession({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAppScope.auth();

  final FirebaseAuth _auth;

  @override
  ExploreAuthenticatedUserSession? get currentSession =>
      _mapUser(_auth.currentUser);

  @override
  Stream<ExploreAuthenticatedUserSession?> authStateChanges() =>
      _auth.authStateChanges().map(_mapUser);

  @override
  Stream<ExploreAuthenticatedUserSession?> idTokenChanges() =>
      _auth.idTokenChanges().map(_mapUser);

  ExploreAuthenticatedUserSession? _mapUser(User? user) {
    final uid = user?.uid.trim() ?? '';
    if (uid.isEmpty || user == null) return null;
    return ExploreAuthenticatedUserSession(
      uid: uid,
      getIdToken: ({bool forceRefresh = false}) =>
          user.getIdToken(forceRefresh),
      reload: user.reload,
    );
  }
}

class ExploreNearbyAuthReadiness {
  ExploreNearbyAuthReadiness({
    ExploreNearbyAuthSession? authSession,
    Duration? timeout,
  }) : _authSession = authSession ?? FirebaseExploreNearbyAuthSession(),
       _timeout = timeout ?? const Duration(seconds: 6);

  final ExploreNearbyAuthSession _authSession;
  final Duration _timeout;

  ExploreAuthenticatedUserSession? get currentSession =>
      _authSession.currentSession;

  Future<ExploreAuthenticatedUserSession> waitForAuthenticatedUser() async {
    final existingSession = _authSession.currentSession;
    if (existingSession != null) {
      return _validateExistingSession(existingSession);
    }

    try {
      final restoredSession = await _waitForRestoredSession();
      return _validateRestoredSession(restoredSession);
    } on TimeoutException {
      throw const ExploreNearbyAuthException(
        'Please sign in again to use Nearby you.',
      );
    }
  }

  Future<ExploreAuthenticatedUserSession>
  refreshAuthenticatedUserToken() async {
    final session = _authSession.currentSession;
    if (session == null) {
      throw const ExploreNearbyAuthException(
        'Please sign in again to use Nearby you.',
      );
    }
    await _ensureToken(
      session,
      forceRefresh: true,
      failureMessage: 'We could not verify your session. Please sign in again.',
    );
    return session;
  }

  Future<ExploreAuthenticatedUserSession> _validateExistingSession(
    ExploreAuthenticatedUserSession session,
  ) async {
    try {
      await _ensureToken(session, forceRefresh: false, failureMessage: '');
      return session;
    } on ExploreNearbyAuthException {
      // Retry after reloading the current Firebase Auth user below.
    }

    try {
      await session.reload();
    } catch (_) {
      // The current auth state is checked immediately after this attempt.
    }

    final reloadedSession = _authSession.currentSession;
    if (reloadedSession == null) {
      throw const ExploreNearbyAuthException(
        'Please sign in again to use Nearby you.',
      );
    }

    await _ensureToken(
      reloadedSession,
      forceRefresh: true,
      failureMessage: 'We could not verify your session. Please sign in again.',
    );
    return reloadedSession;
  }

  Future<ExploreAuthenticatedUserSession> _validateRestoredSession(
    ExploreAuthenticatedUserSession session,
  ) async {
    await _ensureToken(
      session,
      forceRefresh: false,
      failureMessage: 'We could not verify your session. Please sign in again.',
    );
    return session;
  }

  Future<ExploreAuthenticatedUserSession> _waitForRestoredSession() async {
    final completer = Completer<ExploreAuthenticatedUserSession>();
    StreamSubscription<ExploreAuthenticatedUserSession?>? authSubscription;
    StreamSubscription<ExploreAuthenticatedUserSession?>? tokenSubscription;

    void handleEvent(ExploreAuthenticatedUserSession? session) {
      if (session == null || completer.isCompleted) return;
      completer.complete(session);
    }

    authSubscription = _authSession.authStateChanges().listen(
      handleEvent,
      onError: (_) {},
    );
    tokenSubscription = _authSession.idTokenChanges().listen(
      handleEvent,
      onError: (_) {},
    );

    try {
      return await completer.future.timeout(_timeout);
    } finally {
      await authSubscription.cancel();
      await tokenSubscription.cancel();
    }
  }

  Future<void> _ensureToken(
    ExploreAuthenticatedUserSession session, {
    required bool forceRefresh,
    required String failureMessage,
  }) async {
    try {
      final token = await session.getIdToken(forceRefresh: forceRefresh);
      final tokenAvailable = token?.trim().isNotEmpty == true;
      if (!tokenAvailable) {
        throw ExploreNearbyAuthException(failureMessage);
      }
    } catch (_) {
      throw ExploreNearbyAuthException(failureMessage);
    }
  }
}

typedef ExploreNearbyCallableInvoker =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> payload);

@visibleForTesting
class ExploreFeedBatchSlice {
  const ExploreFeedBatchSlice({
    required this.emittedPosts,
    required this.hasOverflowInBatch,
    required this.lastEmittedPostId,
  });

  final List<SocialPostModel> emittedPosts;
  final bool hasOverflowInBatch;
  final String? lastEmittedPostId;
}

@visibleForTesting
ExploreFeedBatchSlice sliceExploreFeedBatch({
  required List<SocialPostModel> filteredPosts,
  required int remainingSlots,
}) {
  if (filteredPosts.isEmpty || remainingSlots <= 0) {
    return const ExploreFeedBatchSlice(
      emittedPosts: <SocialPostModel>[],
      hasOverflowInBatch: false,
      lastEmittedPostId: null,
    );
  }

  final emittedPosts = filteredPosts
      .take(remainingSlots)
      .toList(growable: false);
  return ExploreFeedBatchSlice(
    emittedPosts: emittedPosts,
    hasOverflowInBatch: filteredPosts.length > emittedPosts.length,
    lastEmittedPostId: emittedPosts.isEmpty
        ? null
        : emittedPosts.last.id.trim(),
  );
}

abstract class ExploreFeedStrategy {
  const ExploreFeedStrategy();

  ExploreFeedKind get kind;

  Query<Map<String, dynamic>> buildQuery(
    FirebaseFirestore firestore,
    ExploreFeedViewerContext viewerContext, {
    required int limit,
    bool useLegacyFallback = false,
  });
}

class DiscoverExploreFeedStrategy extends ExploreFeedStrategy {
  const DiscoverExploreFeedStrategy();

  @override
  ExploreFeedKind get kind => ExploreFeedKind.discover;

  @override
  Query<Map<String, dynamic>> buildQuery(
    FirebaseFirestore firestore,
    ExploreFeedViewerContext viewerContext, {
    required int limit,
    bool useLegacyFallback = false,
  }) {
    final base = firestore
        .collection('socialPosts')
        .where('visibilityStatus', isEqualTo: 'visible')
        .where('moderationStatus', isEqualTo: 'approved')
        .where('discoverEligible', isEqualTo: true);

    if (useLegacyFallback) {
      return base.orderBy('createdAt', descending: true).limit(limit);
    }

    return base
        .orderBy('discoverScore', descending: true)
        .orderBy('createdAtEpoch', descending: true)
        .limit(limit);
  }
}

class NearbyExploreFeedStrategy extends ExploreFeedStrategy {
  const NearbyExploreFeedStrategy();

  @override
  ExploreFeedKind get kind => ExploreFeedKind.nearby;

  @override
  Query<Map<String, dynamic>> buildQuery(
    FirebaseFirestore firestore,
    ExploreFeedViewerContext viewerContext, {
    required int limit,
    bool useLegacyFallback = false,
  }) {
    final normalizedCity = viewerContext.normalizedCity;
    final normalizedState = viewerContext.normalizedState;

    Query<Map<String, dynamic>> base = firestore
        .collection('socialPosts')
        .where('visibilityStatus', isEqualTo: 'visible')
        .where('moderationStatus', isEqualTo: 'approved')
        .where('discoverEligible', isEqualTo: true);

    if (normalizedCity.isNotEmpty) {
      base = base.where('feedCityKey', isEqualTo: normalizedCity);
    } else if (normalizedState.isNotEmpty) {
      base = base.where('feedStateKey', isEqualTo: normalizedState);
    }

    if (useLegacyFallback) {
      return base.orderBy('createdAt', descending: true).limit(limit);
    }

    return base
        .orderBy('discoverScore', descending: true)
        .orderBy('createdAtEpoch', descending: true)
        .limit(limit);
  }
}

class ExploreFeedRepository {
  ExploreFeedRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseApp? app,
    ExploreNearbyAuthReadiness? nearbyAuthReadiness,
    ExploreNearbyCallableInvoker? nearbyCallableInvoker,
    ExploreFeedFilterService? filterService,
    List<ExploreFeedStrategy>? strategies,
  }) : _firestore = firestore,
       _nearbyAuthReadiness =
           nearbyAuthReadiness ?? ExploreNearbyAuthReadiness(),
       _nearbyCallableInvoker =
           nearbyCallableInvoker ??
           ((payload) =>
               (functions ??
                       FirebaseFunctions.instanceFor(
                         app: app ?? FirebaseAppScope.app,
                         region: 'asia-south1',
                       ))
                   .httpsCallable('getNearbySocialPosts')
                   .call(payload)
                   .then(
                     (response) => Map<String, dynamic>.from(
                       response.data as Map<dynamic, dynamic>,
                     ),
                   )),
       _filterService = filterService ?? ExploreFeedFilterService(),
       _strategies = <ExploreFeedKind, ExploreFeedStrategy>{
         for (final strategy
             in strategies ??
                 const <ExploreFeedStrategy>[
                   DiscoverExploreFeedStrategy(),
                   NearbyExploreFeedStrategy(),
                 ])
           strategy.kind: strategy,
       };

  final FirebaseFirestore? _firestore;
  final ExploreNearbyAuthReadiness _nearbyAuthReadiness;
  final ExploreNearbyCallableInvoker _nearbyCallableInvoker;
  final ExploreFeedFilterService _filterService;
  final Map<ExploreFeedKind, ExploreFeedStrategy> _strategies;

  FirebaseFirestore get _resolvedFirestore =>
      _firestore ?? FirebaseFirestore.instance;

  Future<ExploreFeedPage> fetchPage({
    required ExploreFeedKind kind,
    required ExploreFeedViewerContext viewerContext,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    Map<String, dynamic>? cursor,
    Set<String> excludePostIds = const <String>{},
    int limit = socialFeedPageSize,
  }) async {
    if (kind == ExploreFeedKind.nearby) {
      return _fetchNearbyPage(
        viewerContext: viewerContext,
        cursor: cursor,
        excludePostIds: excludePostIds,
        limit: limit,
      );
    }

    final strategy = _strategies[kind];
    if (strategy == null) {
      throw Exception('Explore feed strategy for $kind is not configured.');
    }

    try {
      final page = await _loadPage(
        strategy: strategy,
        viewerContext: viewerContext,
        startAfter: startAfter,
        excludePostIds: excludePostIds,
        limit: limit,
      );
      if (startAfter == null && page.posts.isEmpty) {
        return _loadPage(
          strategy: strategy,
          viewerContext: viewerContext,
          startAfter: startAfter,
          excludePostIds: excludePostIds,
          limit: limit,
          useLegacyFallback: true,
        );
      }
      return page;
    } on FirebaseException catch (error) {
      if (error.code != 'failed-precondition') rethrow;
      return _loadPage(
        strategy: strategy,
        viewerContext: viewerContext,
        startAfter: startAfter,
        excludePostIds: excludePostIds,
        limit: limit,
        useLegacyFallback: true,
      );
    }
  }

  Future<ExploreFeedPage> _loadPage({
    required ExploreFeedStrategy strategy,
    required ExploreFeedViewerContext viewerContext,
    required Set<String> excludePostIds,
    required int limit,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    bool useLegacyFallback = false,
  }) async {
    final posts = <SocialPostModel>[];
    final seenPostIds = Set<String>.from(excludePostIds);
    DocumentSnapshot<Map<String, dynamic>>? cursor = startAfter;
    var hasMore = true;
    final pageSize = math.max(limit * 2, 20);

    while (posts.length < limit && hasMore) {
      Query<Map<String, dynamic>> query = strategy.buildQuery(
        _resolvedFirestore,
        viewerContext,
        limit: pageSize,
        useLegacyFallback: useLegacyFallback,
      );
      if (cursor != null) {
        query = query.startAfterDocument(cursor);
      }

      final snapshot = cursor == null
          ? await FirestoreCacheService.getCollectionCacheFirst(query)
          : await query.get();
      if (snapshot.docs.isEmpty) {
        hasMore = false;
        break;
      }

      final filteredPosts = await _filterService.apply(
        posts: snapshot.docs
            .map(SocialPostModel.fromDocument)
            .toList(growable: false),
        viewerContext: viewerContext,
        seenPostIds: seenPostIds,
      );
      final batchSlice = sliceExploreFeedBatch(
        filteredPosts: filteredPosts,
        remainingSlots: math.max(0, limit - posts.length),
      );
      posts.addAll(batchSlice.emittedPosts);

      if (batchSlice.hasOverflowInBatch) {
        cursor = _findBatchCursorForEmittedPost(
          snapshot.docs,
          fallback: snapshot.docs.last,
          lastEmittedPostId: batchSlice.lastEmittedPostId,
        );
        hasMore = true;
        break;
      }

      cursor = snapshot.docs.last;
      hasMore = snapshot.docs.length == pageSize;
    }

    return ExploreFeedPage(
      posts: posts.take(limit).toList(growable: false),
      lastDocument: cursor ?? startAfter,
      hasMore: hasMore,
      usedLegacyFallback: useLegacyFallback,
    );
  }

  DocumentSnapshot<Map<String, dynamic>> _findBatchCursorForEmittedPost(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required DocumentSnapshot<Map<String, dynamic>> fallback,
    required String? lastEmittedPostId,
  }) {
    final targetId = lastEmittedPostId?.trim() ?? '';
    if (targetId.isEmpty) {
      return fallback;
    }
    for (final doc in docs) {
      if (doc.id.trim() == targetId) {
        return doc;
      }
    }
    return fallback;
  }

  Future<ExploreFeedPage> _fetchNearbyPage({
    required ExploreFeedViewerContext viewerContext,
    required Set<String> excludePostIds,
    required int limit,
    Map<String, dynamic>? cursor,
  }) async {
    await _nearbyAuthReadiness.waitForAuthenticatedUser();
    const maxRefillAttempts = 240;
    final posts = <SocialPostModel>[];
    final seenPostIds = Set<String>.from(excludePostIds);
    Map<String, dynamic>? nextCursor = cursor;
    bool hasMore = true;
    double? activeRadiusKm;
    bool usedLocationFallback = false;
    NearbyLocationMode nearbyLocationMode = NearbyLocationMode.unavailable;
    String? emptyStateReason;
    var attempts = 0;
    var restartedExpiredSession = false;

    while (posts.length < limit && hasMore && attempts < maxRefillAttempts) {
      attempts += 1;
      final remaining = math.max(1, limit - posts.length);
      final payload = <String, dynamic>{
        'limit': math.min(math.max(remaining, limit), 20),
        if (kDebugMode) 'debugDiagnostics': true,
      };
      if (nextCursor != null) {
        payload['cursor'] = nextCursor;
      }
      Map<String, dynamic> data;
      try {
        data = await _callNearbyCallable(payload);
      } on FirebaseFunctionsException catch (error) {
        final shouldRestartSession =
            nextCursor != null &&
            !restartedExpiredSession &&
            (error.code == 'deadline-exceeded' ||
                error.code == 'invalid-argument');
        if (!shouldRestartSession) {
          if (error.code == 'unauthenticated') {
            data = await _retryUnauthenticatedNearby(payload);
          } else {
            rethrow;
          }
        } else {
          restartedExpiredSession = true;
          nextCursor = null;
          hasMore = true;
          continue;
        }
      }

      final rawItems = data['posts'] as List<dynamic>? ?? const <dynamic>[];
      final rawMaps = rawItems.whereType<Map>().toList(growable: false);

      final rawPosts = <SocialPostModel>[];
      for (final item in rawMaps) {
        rawPosts.add(
          SocialPostModel.fromMap(
            Map<String, dynamic>.from(item.cast<dynamic, dynamic>()),
          ),
        );
      }

      final filteredPosts = await _filterService.apply(
        posts: rawPosts,
        viewerContext: viewerContext,
        seenPostIds: seenPostIds,
      );
      posts.addAll(filteredPosts);

      final rawNextCursor = data['nextCursor'];
      nextCursor = rawNextCursor is Map
          ? Map<String, dynamic>.from(rawNextCursor.cast<dynamic, dynamic>())
          : null;
      hasMore = data['hasMore'] == true && nextCursor != null;
      activeRadiusKm = (data['activeRadiusKm'] as num?)?.toDouble();
      usedLocationFallback = data['usedCityStateFallback'] == true;
      nearbyLocationMode = NearbyLocationMode.fromResponse(
        value: data['locationMode'],
        usedCityStateFallback: usedLocationFallback,
        activeRadiusKm: activeRadiusKm,
      );
      emptyStateReason =
          (data['emptyStateReason'] as String?)?.trim().isNotEmpty == true
          ? (data['emptyStateReason'] as String).trim()
          : null;

      if (nextCursor == null) {
        hasMore = false;
      }
    }

    return ExploreFeedPage(
      posts: posts.take(limit).toList(growable: false),
      lastDocument: null,
      nextCursor: nextCursor,
      hasMore: hasMore,
      activeRadiusKm: activeRadiusKm,
      usedLocationFallback: usedLocationFallback,
      nearbyLocationMode: nearbyLocationMode,
      emptyStateReason: emptyStateReason,
    );
  }

  Future<Map<String, dynamic>> _callNearbyCallable(
    Map<String, dynamic> payload,
  ) => _nearbyCallableInvoker(payload);

  Future<Map<String, dynamic>> _retryUnauthenticatedNearby(
    Map<String, dynamic> payload,
  ) async {
    try {
      await _nearbyAuthReadiness.refreshAuthenticatedUserToken();
      return await _callNearbyCallable(payload);
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'unauthenticated') {
        throw ExploreNearbyAuthException(
          _nearbyAuthReadiness.currentSession == null
              ? 'Please sign in again to use Nearby you.'
              : 'We could not verify your session. Please sign in again.',
        );
      }
      rethrow;
    } on ExploreNearbyAuthException {
      rethrow;
    } catch (_) {
      throw const ExploreNearbyAuthException(
        'We could not verify your session. Please sign in again.',
      );
    }
  }
}
