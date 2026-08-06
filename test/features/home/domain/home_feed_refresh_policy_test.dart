import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/home/domain/home_feed_refresh_policy.dart';
import 'package:pettexo/features/social/domain/models/social_post_model.dart';

void main() {
  group('HomeFeedRefreshPolicy', () {
    test(
      'non-empty feed plus refresh posts still replaces the visible list',
      () {
        final refreshedPosts = <SocialPostModel>[
          _post(id: 'post-1'),
          _post(id: 'post-2'),
        ];

        expect(
          HomeFeedRefreshPolicy.shouldReplaceVisibleFeed(
            hadExistingPosts: true,
            refreshedPosts: refreshedPosts,
          ),
          isTrue,
        );
      },
    );

    test(
      'non-empty feed plus temporary empty refresh retains existing list',
      () {
        expect(
          HomeFeedRefreshPolicy.shouldReplaceVisibleFeed(
            hadExistingPosts: true,
            refreshedPosts: const <SocialPostModel>[],
          ),
          isFalse,
        );
      },
    );

    test('initial load genuinely empty still allows empty state', () {
      expect(
        HomeFeedRefreshPolicy.shouldReplaceVisibleFeed(
          hadExistingPosts: false,
          refreshedPosts: const <SocialPostModel>[],
        ),
        isTrue,
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
  });

  group('HomeFeedRequestTracker', () {
    test('older response cannot overwrite a newer request', () {
      final tracker = HomeFeedRequestTracker();

      final first = tracker.startRequest();
      final second = tracker.startRequest();

      expect(tracker.isCurrent(first), isFalse);
      expect(tracker.isCurrent(second), isTrue);
    });
  });
}

SocialPostModel _post({required String id}) {
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
    likeCount: 0,
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
