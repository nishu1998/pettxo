import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/home/domain/home_feed_refresh_policy.dart';
import 'package:pettexo/features/social/domain/models/social_post_model.dart';
import 'package:pettexo/features/social/domain/social_post_like_state.dart';

void main() {
  group('HomeFeedRefreshPolicy', () {
    test('successful empty refresh produces an empty replacement feed', () {
      expect(
        HomeFeedRefreshPolicy.dedupeReplacementPosts(const <SocialPostModel>[]),
        isEmpty,
      );
    });

    test(
      'replacement dedupe keeps refreshed posts even when ids match prior feed',
      () {
        final replacement = HomeFeedRefreshPolicy.dedupeReplacementPosts(
          <SocialPostModel>[
            _post(id: 'post-1'),
            _post(id: 'post-2'),
            _post(id: 'post-1'),
          ],
        );

        expect(
          replacement.map((post) => post.id).toList(growable: false),
          <String>['post-1', 'post-2'],
        );
      },
    );

    test('replacement preserves newest-first repository order', () {
      final replacement = HomeFeedRefreshPolicy.dedupeReplacementPosts(
        <SocialPostModel>[
          _post(id: 'new-post'),
          _post(id: 'previous-post'),
          _post(id: 'old-post'),
        ],
      );

      expect(replacement.map((post) => post.id), <String>[
        'new-post',
        'previous-post',
        'old-post',
      ]);
    });

    test('append dedupe prevents duplicates after refresh then pagination', () {
      final appended = HomeFeedRefreshPolicy.dedupeAppendedPosts(
        <SocialPostModel>[
          _post(id: 'post-2'),
          _post(id: 'post-3'),
          _post(id: 'post-3'),
        ],
        existingPostIds: const <String>['post-1', 'post-2'],
      );

      expect(appended.map((post) => post.id).toList(growable: false), <String>[
        'post-3',
      ]);
    });

    test(
      'refresh failure retains a usable feed but initial failure does not',
      () {
        expect(
          HomeFeedRefreshPolicy.shouldRetainExistingFeedAfterFailure(
            hadExistingPosts: true,
          ),
          isTrue,
        );
        expect(
          HomeFeedRefreshPolicy.shouldRetainExistingFeedAfterFailure(
            hadExistingPosts: false,
          ),
          isFalse,
        );
      },
    );
  });

  group('HomeFeedRequestTracker', () {
    test('older response cannot overwrite a newer request', () {
      final tracker = HomeFeedRequestTracker();

      final first = tracker.startRequest();
      final second = tracker.startRequest();

      expect(tracker.isCurrent(first), isFalse);
      expect(tracker.isCurrent(second), isTrue);
    });

    test('pagination can capture the active refresh generation', () {
      final tracker = HomeFeedRequestTracker();
      final initial = tracker.startRequest();

      expect(tracker.currentRequestId, initial);

      tracker.startRequest();
      expect(tracker.isCurrent(initial), isFalse);
    });

    test('account change invalidates the active viewer request', () {
      final tracker = HomeFeedRequestTracker();
      final accountARequest = tracker.startRequest();

      tracker.startRequest();

      expect(tracker.isCurrent(accountARequest), isFalse);
    });
  });

  group('Home like reconciliation', () {
    test('refresh cannot overwrite a newer Home card mutation', () {
      final refreshed = applyNewerSocialPostLikeMutations(
        <SocialPostModel>[_post(id: 'post-1', likeCount: 0)],
        mutations: const <String, SocialPostLikeMutation>{
          'post-1': SocialPostLikeMutation(
            isLiked: true,
            likeCount: 1,
            revision: 2,
          ),
        },
        requestStartRevision: 1,
      );

      expect(refreshed.single.likeCount, 1);
    });

    test('later canonical Home refresh replaces a settled local count', () {
      final refreshed = applyNewerSocialPostLikeMutations(
        <SocialPostModel>[_post(id: 'post-1', likeCount: 3)],
        mutations: const <String, SocialPostLikeMutation>{
          'post-1': SocialPostLikeMutation(
            isLiked: true,
            likeCount: 1,
            revision: 2,
          ),
        },
        requestStartRevision: 2,
      );

      expect(refreshed.single.likeCount, 3);
    });

    test('pagination does not replace an existing post mutation', () {
      final existing = <SocialPostModel>[_post(id: 'post-1', likeCount: 1)];
      final appended = HomeFeedRefreshPolicy.dedupeAppendedPosts(
        <SocialPostModel>[
          _post(id: 'post-1', likeCount: 0),
          _post(id: 'post-2', likeCount: 4),
        ],
        existingPostIds: existing.map((post) => post.id),
      );

      expect(existing.single.likeCount, 1);
      expect(appended.map((post) => post.id), <String>['post-2']);
    });
  });

  group('HomeFeedLoadPolicy', () {
    test('requests the next page inside the prefetch threshold', () {
      expect(
        HomeFeedLoadPolicy.shouldRequestNextPage(
          pixels: 680,
          maxScrollExtent: 1000,
          prefetchDistance: 320,
        ),
        isTrue,
      );
      expect(
        HomeFeedLoadPolicy.shouldRequestNextPage(
          pixels: 679,
          maxScrollExtent: 1000,
          prefetchDistance: 320,
        ),
        isFalse,
      );
    });

    test('prevents duplicate pagination and pagination during refresh', () {
      expect(
        HomeFeedLoadPolicy.canLoadMore(
          isInitialLoading: false,
          isRefreshing: false,
          isLoadingMore: false,
          hasMore: true,
        ),
        isTrue,
      );
      expect(
        HomeFeedLoadPolicy.canLoadMore(
          isInitialLoading: false,
          isRefreshing: false,
          isLoadingMore: true,
          hasMore: true,
        ),
        isFalse,
      );
      expect(
        HomeFeedLoadPolicy.canLoadMore(
          isInitialLoading: false,
          isRefreshing: true,
          isLoadingMore: false,
          hasMore: true,
        ),
        isFalse,
      );
    });

    test('caught-up footer appears only after genuine exhaustion', () {
      HomeFeedFooterState state({
        bool loading = false,
        bool refreshing = false,
        bool hasMore = true,
        bool error = false,
      }) => HomeFeedLoadPolicy.footerState(
        hasEntries: true,
        isInitialLoading: false,
        isRefreshing: refreshing,
        isLoadingMore: loading,
        hasMore: hasMore,
        hasLoadMoreError: error,
      );

      expect(state(), HomeFeedFooterState.none);
      expect(state(loading: true), HomeFeedFooterState.loading);
      expect(state(error: true), HomeFeedFooterState.retry);
      expect(state(error: true, hasMore: false), HomeFeedFooterState.retry);
      expect(state(refreshing: true, hasMore: false), HomeFeedFooterState.none);
      expect(state(hasMore: false), HomeFeedFooterState.caughtUp);
    });
  });
}

SocialPostModel _post({required String id, int likeCount = 0}) {
  return SocialPostModel(
    id: id,
    authorId: 'author-$id',
    authorType: 'user',
    authorDisplayName: 'Author $id',
    authorUsername: 'author_$id',
    authorPhotoUrl: '',
    authorCategoryLabel: '',
    authorCity: 'Bengaluru',
    authorState: 'Karnataka',
    nearbyEligible: false,
    feedGeohash3: '',
    feedGeohash4: '',
    feedGeohash5: '',
    feedLocationVersion: 0,
    feedLocationUpdatedAt: null,
    nearbyDistanceKm: null,
    nearbyDistanceLabel: '',
    usesNearbyFallback: false,
    isAdminPost: false,
    adminPriorityBoost: 0,
    recentEngagementScore: 0,
    homeEligible: true,
    homeScore: 5,
    homeRankVersion: 1,
    homeScoreUpdatedAt: null,
    imageUrls: const <String>['https://example.com/image.jpg'],
    thumbnailUrls: const <String>['https://example.com/thumb.jpg'],
    imageAspectRatio: SocialPostAspectRatio.square,
    caption: 'caption',
    hashtags: const <String>['pets'],
    likeCount: likeCount,
    commentCount: 0,
    shareCount: 0,
    saveCount: 0,
    reportCount: 0,
    visibilityStatus: 'visible',
    moderationStatus: 'approved',
    moderationReason: '',
    moderatedBy: '',
    moderatedAt: null,
    lastReportedAt: null,
    createdAtEpoch: 1,
    createdAt: null,
    updatedAt: null,
  );
}
