import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/explore/data/explore_feed_filter_service.dart';
import 'package:pettexo/features/explore/data/explore_feed_repository.dart';
import 'package:pettexo/features/explore/domain/models/explore_feed_kind.dart';
import 'package:pettexo/features/explore/domain/models/explore_feed_viewer_context.dart';
import 'package:pettexo/features/social/domain/models/social_post_model.dart';

void main() {
  group('sliceExploreFeedBatch', () {
    test('preserves overflow posts for the next discover page', () {
      final slice = sliceExploreFeedBatch(
        filteredPosts: <SocialPostModel>[_post('p1'), _post('p2'), _post('p3')],
        remainingSlots: 2,
      );

      expect(
        slice.emittedPosts.map((post) => post.id).toList(growable: false),
        <String>['p1', 'p2'],
      );
      expect(slice.hasOverflowInBatch, isTrue);
      expect(slice.lastEmittedPostId, 'p2');
    });

    test('marks batch complete when the filtered posts fit the page', () {
      final slice = sliceExploreFeedBatch(
        filteredPosts: <SocialPostModel>[_post('p1'), _post('p2')],
        remainingSlots: 3,
      );

      expect(
        slice.emittedPosts.map((post) => post.id).toList(growable: false),
        <String>['p1', 'p2'],
      );
      expect(slice.hasOverflowInBatch, isFalse);
      expect(slice.lastEmittedPostId, 'p2');
    });
  });

  group('ExploreNearbyAuthReadiness', () {
    test('uses current session immediately when available', () async {
      final fakeSession = _FakeAuthSession(
        current: _FakeUserSession(uid: 'user-1', token: 'token-1'),
      );
      final readiness = ExploreNearbyAuthReadiness(
        authSession: fakeSession,
        timeout: const Duration(milliseconds: 20),
      );

      final session = await readiness.waitForAuthenticatedUser();

      expect(session.uid, 'user-1');
      expect(fakeSession.currentTokenCalls, 1);
      expect(fakeSession.currentForceRefreshCalls, 0);
    });

    test('waits briefly for a restored session when current is null', () async {
      final fakeSession = _FakeAuthSession();
      final readiness = ExploreNearbyAuthReadiness(
        authSession: fakeSession,
        timeout: const Duration(milliseconds: 50),
      );

      Future<void>.delayed(const Duration(milliseconds: 5), () {
        fakeSession.emit(_FakeUserSession(uid: 'user-2', token: 'token-2'));
      });

      final session = await readiness.waitForAuthenticatedUser();

      expect(session.uid, 'user-2');
      expect(fakeSession.lastEmittedTokenCalls, 1);
    });

    test('times out when auth is not restored', () async {
      final fakeSession = _FakeAuthSession();
      final readiness = ExploreNearbyAuthReadiness(
        authSession: fakeSession,
        timeout: const Duration(milliseconds: 10),
      );

      expect(
        readiness.waitForAuthenticatedUser(),
        throwsA(
          isA<ExploreNearbyAuthException>().having(
            (error) => error.message,
            'message',
            'Please sign in again to use Nearby you.',
          ),
        ),
      );
    });

    test(
      'surfaces token retrieval failure as a controlled exception',
      () async {
        final fakeSession = _FakeAuthSession(
          current: _FakeUserSession(
            uid: 'user-3',
            tokenError: Exception('token failed'),
          ),
        );
        final readiness = ExploreNearbyAuthReadiness(
          authSession: fakeSession,
          timeout: const Duration(milliseconds: 20),
        );

        expect(
          readiness.waitForAuthenticatedUser(),
          throwsA(
            isA<ExploreNearbyAuthException>().having(
              (error) => error.message,
              'message',
              'We could not verify your session. Please sign in again.',
            ),
          ),
        );
      },
    );

    test(
      'reloads and force-refreshes once when current token lookup fails',
      () async {
        final reloadedSession = _FakeUserSession(
          uid: 'user-4',
          token: 'token-4',
        );
        final fakeSession = _FakeAuthSession(
          current: _FakeUserSession(
            uid: 'user-4',
            tokenError: Exception('token failed'),
          ),
          reloadResult: reloadedSession,
        );
        final readiness = ExploreNearbyAuthReadiness(
          authSession: fakeSession,
          timeout: const Duration(milliseconds: 20),
        );

        final session = await readiness.waitForAuthenticatedUser();

        expect(session.uid, 'user-4');
        expect(fakeSession.reloadCalls, 1);
        expect(reloadedSession.forceRefreshCalls, 1);
      },
    );

    test(
      'returns signed-out message when reload clears the current session',
      () async {
        final fakeSession = _FakeAuthSession(
          current: _FakeUserSession(
            uid: 'user-5',
            tokenError: Exception('token failed'),
          ),
          clearSessionOnReload: true,
        );
        final readiness = ExploreNearbyAuthReadiness(
          authSession: fakeSession,
          timeout: const Duration(milliseconds: 20),
        );

        await expectLater(
          readiness.waitForAuthenticatedUser(),
          throwsA(
            isA<ExploreNearbyAuthException>().having(
              (error) => error.message,
              'message',
              'Please sign in again to use Nearby you.',
            ),
          ),
        );
        expect(fakeSession.reloadCalls, 1);
      },
    );
  });

  group('ExploreFeedRepository nearby auth handling', () {
    test(
      'retries one unauthenticated callable failure and then succeeds',
      () async {
        final fakeSession = _FakeAuthSession(
          current: _FakeUserSession(uid: 'viewer', token: 'token-a'),
        );
        final readiness = ExploreNearbyAuthReadiness(
          authSession: fakeSession,
          timeout: const Duration(milliseconds: 20),
        );
        var callCount = 0;
        final repository = ExploreFeedRepository(
          nearbyAuthReadiness: readiness,
          filterService: _PassthroughFilterService(),
          nearbyCallableInvoker: (payload) async {
            callCount += 1;
            if (callCount == 1) {
              throw FirebaseFunctionsException(
                code: 'unauthenticated',
                message: 'Authentication required.',
              );
            }
            return _nearbyResponse();
          },
        );

        final page = await repository.fetchPage(
          kind: ExploreFeedKind.nearby,
          viewerContext: ExploreFeedViewerContext.empty,
        );

        expect(callCount, 2);
        expect(fakeSession.currentForceRefreshCalls, 1);
        expect(page.posts, hasLength(1));
        expect(page.posts.first.id, 'post-1');
      },
    );

    test(
      'returns controlled message when both attempts are unauthenticated',
      () async {
        final fakeSession = _FakeAuthSession(
          current: _FakeUserSession(uid: 'viewer', token: 'token-a'),
        );
        final readiness = ExploreNearbyAuthReadiness(
          authSession: fakeSession,
          timeout: const Duration(milliseconds: 20),
        );
        var callCount = 0;
        final repository = ExploreFeedRepository(
          nearbyAuthReadiness: readiness,
          filterService: _PassthroughFilterService(),
          nearbyCallableInvoker: (payload) async {
            callCount += 1;
            throw FirebaseFunctionsException(
              code: 'unauthenticated',
              message: 'Authentication required.',
            );
          },
        );

        await expectLater(
          repository.fetchPage(
            kind: ExploreFeedKind.nearby,
            viewerContext: ExploreFeedViewerContext.empty,
          ),
          throwsA(
            isA<ExploreNearbyAuthException>().having(
              (error) => error.message,
              'message',
              'We could not verify your session. Please sign in again.',
            ),
          ),
        );
        expect(callCount, 2);
      },
    );

    test('does not retry non-auth callable errors', () async {
      final fakeSession = _FakeAuthSession(
        current: _FakeUserSession(uid: 'viewer', token: 'token-a'),
      );
      final readiness = ExploreNearbyAuthReadiness(
        authSession: fakeSession,
        timeout: const Duration(milliseconds: 20),
      );
      var callCount = 0;
      final repository = ExploreFeedRepository(
        nearbyAuthReadiness: readiness,
        filterService: _PassthroughFilterService(),
        nearbyCallableInvoker: (payload) async {
          callCount += 1;
          throw FirebaseFunctionsException(code: 'internal', message: 'boom');
        },
      );

      await expectLater(
        repository.fetchPage(
          kind: ExploreFeedKind.nearby,
          viewerContext: ExploreFeedViewerContext.empty,
        ),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      expect(callCount, 1);
    });

    test('does not call Nearby when auth restoration times out', () async {
      final fakeSession = _FakeAuthSession();
      final readiness = ExploreNearbyAuthReadiness(
        authSession: fakeSession,
        timeout: const Duration(milliseconds: 10),
      );
      var callCount = 0;
      final repository = ExploreFeedRepository(
        nearbyAuthReadiness: readiness,
        filterService: _PassthroughFilterService(),
        nearbyCallableInvoker: (payload) async {
          callCount += 1;
          return _nearbyResponse();
        },
      );

      await expectLater(
        repository.fetchPage(
          kind: ExploreFeedKind.nearby,
          viewerContext: ExploreFeedViewerContext.empty,
        ),
        throwsA(isA<ExploreNearbyAuthException>()),
      );
      expect(callCount, 0);
    });
  });
}

SocialPostModel _post(String id) {
  return SocialPostModel.fromMap(<String, dynamic>{
    'id': id,
    'authorId': 'author-$id',
    'authorType': 'user',
    'authorDisplayName': 'Author $id',
    'authorUsername': 'author_$id',
    'authorPhotoUrl': '',
    'authorCategoryLabel': '',
    'authorCity': 'Bengaluru',
    'authorState': 'Karnataka',
    'imageUrls': const <String>['https://example.com/image.jpg'],
    'thumbnailUrls': const <String>['https://example.com/thumb.jpg'],
    'imageAspectRatio': 'square',
    'caption': 'caption',
    'hashtags': const <String>['pets'],
    'likeCount': 0,
    'commentCount': 0,
    'shareCount': 0,
    'reportCount': 0,
    'saveCount': 0,
    'visibilityStatus': 'visible',
    'moderationStatus': 'approved',
    'moderationReason': '',
    'moderatedBy': '',
    'isAdminPost': false,
    'adminPriorityBoost': 0,
    'recentEngagementScore': 0,
    'discoverEligible': true,
    'discoverScore': 10,
    'discoverRankVersion': 1,
    'homeEligible': true,
    'homeScore': 10,
    'homeRankVersion': 1,
    'nearbyEligible': false,
    'nearbyDistanceKm': null,
    'nearbyDistanceLabel': '',
    'feedGeohash3': '',
    'feedGeohash4': '',
    'feedGeohash5': '',
    'feedLocationVersion': 0,
    'createdAtEpoch': 1,
    'usesNearbyFallback': false,
  });
}

Map<String, dynamic> _nearbyResponse() {
  return <String, dynamic>{
    'posts': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'post-1',
        'authorId': 'author-1',
        'visibilityStatus': 'visible',
        'moderationStatus': 'approved',
        'nearbyDistanceLabel': '500 m away',
        'imageUrls': const <String>[],
        'thumbnailUrls': const <String>[],
      },
    ],
    'nextCursor': null,
    'hasMore': false,
    'activeRadiusKm': 5,
    'usedCityStateFallback': false,
    'emptyStateReason': null,
  };
}

class _FakeAuthSession implements ExploreNearbyAuthSession {
  _FakeAuthSession({
    this.current,
    this.reloadResult,
    this.clearSessionOnReload = false,
  });

  ExploreAuthenticatedUserSession? current;
  ExploreAuthenticatedUserSession? reloadResult;
  final bool clearSessionOnReload;
  final StreamController<ExploreAuthenticatedUserSession?> _controller =
      StreamController<ExploreAuthenticatedUserSession?>();
  final StreamController<ExploreAuthenticatedUserSession?> _authController =
      StreamController<ExploreAuthenticatedUserSession?>();
  int reloadCalls = 0;

  @override
  ExploreAuthenticatedUserSession? get currentSession => _decorate(current);

  int get currentTokenCalls => current is _FakeUserSession
      ? (current as _FakeUserSession).tokenCalls
      : 0;

  int get currentForceRefreshCalls => current is _FakeUserSession
      ? (current as _FakeUserSession).forceRefreshCalls
      : 0;

  int get lastEmittedTokenCalls => _lastEmitted?.tokenCalls ?? 0;
  _FakeUserSession? _lastEmitted;

  @override
  Stream<ExploreAuthenticatedUserSession?> authStateChanges() =>
      _authController.stream.map(_decorate);

  @override
  Stream<ExploreAuthenticatedUserSession?> idTokenChanges() =>
      _controller.stream.map(_decorate);

  void emit(_FakeUserSession session) {
    _lastEmitted = session;
    current = session;
    _authController.add(session);
    _controller.add(session);
  }

  Future<void> reloadCurrentSession() async {
    reloadCalls += 1;
    if (clearSessionOnReload) {
      current = null;
      _authController.add(null);
      _controller.add(null);
      return;
    }
    if (reloadResult != null) {
      current = reloadResult;
    }
  }

  ExploreAuthenticatedUserSession? _decorate(
    ExploreAuthenticatedUserSession? session,
  ) {
    if (session == null) return null;
    return ExploreAuthenticatedUserSession(
      uid: session.uid,
      getIdToken: session.getIdToken,
      reload: reloadCurrentSession,
      providerIds: session.providerIds,
    );
  }
}

class _FakeUserSession extends ExploreAuthenticatedUserSession {
  _FakeUserSession({
    required super.uid,
    this.token,
    this.tokenError,
    Future<void> Function()? reload,
  }) : super(
         getIdToken: ({bool forceRefresh = false}) async {
           throw UnimplementedError();
         },
         reload: reload ?? _noopReload,
         providerIds: const <String>['phone'],
       );

  final String? token;
  final Object? tokenError;
  int tokenCalls = 0;
  int forceRefreshCalls = 0;

  @override
  Future<String?> Function({bool forceRefresh}) get getIdToken =>
      ({bool forceRefresh = false}) async {
        tokenCalls += 1;
        if (forceRefresh) {
          forceRefreshCalls += 1;
        }
        if (tokenError != null) {
          throw tokenError!;
        }
        return token;
      };

  static Future<void> _noopReload() async {}
}

class _PassthroughFilterService extends ExploreFeedFilterService {
  _PassthroughFilterService();

  @override
  Future<List<SocialPostModel>> apply({
    required List<SocialPostModel> posts,
    required ExploreFeedViewerContext viewerContext,
    required Set<String> seenPostIds,
  }) async {
    return posts
        .where((post) => seenPostIds.add(post.id))
        .toList(growable: false);
  }
}
