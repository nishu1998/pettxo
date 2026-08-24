import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/home/data/home_feed_repository.dart';
import 'package:pettexo/features/home/domain/home_feed_session.dart';
import 'package:pettexo/features/social/domain/models/social_post_model.dart';

void main() {
  group('HomeFeedSession', () {
    test(
      'keeps backend order stable while avoiding immediate same-author repeats',
      () {
        final session = HomeFeedSession();
        const viewerContext = HomeFeedViewerContext(
          currentUserId: 'viewer',
          city: 'Bengaluru',
          state: 'Karnataka',
          followingIds: <String>{},
          blockedUserIds: <String>{},
          mutedUserIds: <String>{},
          creatorsWhoBlockedViewerIds: <String>{},
        );

        session.reset(
          candidates: <SocialPostModel>[
            _post(id: 'a1', authorId: 'author-a', homeScore: 9.5),
            _post(id: 'a2', authorId: 'author-a', homeScore: 9.4),
            _post(id: 'b1', authorId: 'author-b', homeScore: 9.3),
            _post(id: 'c1', authorId: 'author-c', homeScore: 9.2),
          ],
          viewerContext: viewerContext,
          initialEntryCount: 4,
          preserveSeenPosts: false,
        );

        expect(
          session.entries.map((entry) => entry.post.id).toList(growable: false),
          <String>['a1', 'b1', 'a2', 'c1'],
        );
      },
    );

    test('prefers followed creators within the look-ahead window', () {
      final session = HomeFeedSession();
      const viewerContext = HomeFeedViewerContext(
        currentUserId: 'viewer',
        city: '',
        state: '',
        followingIds: <String>{'followed-author'},
        blockedUserIds: <String>{},
        mutedUserIds: <String>{},
        creatorsWhoBlockedViewerIds: <String>{},
      );

      session.reset(
        candidates: <SocialPostModel>[
          _post(id: 'p1', authorId: 'author-a', homeScore: 9.9),
          _post(id: 'p2', authorId: 'followed-author', homeScore: 9.8),
          _post(id: 'p3', authorId: 'author-c', homeScore: 9.7),
        ],
        viewerContext: viewerContext,
        initialEntryCount: 3,
        preserveSeenPosts: false,
      );

      expect(
        session.entries.map((entry) => entry.post.id).toList(growable: false),
        <String>['p2', 'p1', 'p3'],
      );
      expect(session.entries.first.rankingReason, 'Following');
    });

    test('demotes already-seen posts on refresh inside the same session', () {
      final session = HomeFeedSession();
      const viewerContext = HomeFeedViewerContext(
        currentUserId: 'viewer',
        city: '',
        state: '',
        followingIds: <String>{},
        blockedUserIds: <String>{},
        mutedUserIds: <String>{},
        creatorsWhoBlockedViewerIds: <String>{},
      );

      session.reset(
        candidates: <SocialPostModel>[
          _post(id: 'p1', authorId: 'author-a', homeScore: 10),
          _post(id: 'p2', authorId: 'author-b', homeScore: 9.9),
        ],
        viewerContext: viewerContext,
        initialEntryCount: 2,
        preserveSeenPosts: false,
      );

      session.reset(
        candidates: <SocialPostModel>[
          _post(id: 'p1', authorId: 'author-a', homeScore: 10),
          _post(id: 'p2', authorId: 'author-b', homeScore: 9.9),
          _post(id: 'p3', authorId: 'author-c', homeScore: 9.8),
        ],
        viewerContext: viewerContext,
        initialEntryCount: 3,
        preserveSeenPosts: true,
      );

      expect(
        session.entries.map((entry) => entry.post.id).toList(growable: false),
        <String>['p3', 'p1', 'p2'],
      );
    });

    test('emits buffered ranked candidates in later pagination steps', () {
      final session = HomeFeedSession();
      const viewerContext = HomeFeedViewerContext(
        currentUserId: 'viewer',
        city: '',
        state: '',
        followingIds: <String>{},
        blockedUserIds: <String>{},
        mutedUserIds: <String>{},
        creatorsWhoBlockedViewerIds: <String>{},
      );

      session.reset(
        candidates: <SocialPostModel>[
          _post(id: 'p1', authorId: 'author-a', homeScore: 10),
          _post(id: 'p2', authorId: 'author-b', homeScore: 9.9),
          _post(id: 'p3', authorId: 'author-c', homeScore: 9.8),
          _post(id: 'p4', authorId: 'author-d', homeScore: 9.7),
        ],
        viewerContext: viewerContext,
        initialEntryCount: 2,
        preserveSeenPosts: false,
      );

      expect(session.hasPendingCandidates, isTrue);
      expect(
        session.entries.map((entry) => entry.post.id).toList(growable: false),
        <String>['p1', 'p2'],
      );

      session.emitMoreEntries(viewerContext: viewerContext, count: 2);

      expect(session.hasPendingCandidates, isFalse);
      expect(
        session.entries.map((entry) => entry.post.id).toList(growable: false),
        <String>['p1', 'p2', 'p3', 'p4'],
      );
    });
  });
}

SocialPostModel _post({
  required String id,
  required String authorId,
  required double homeScore,
}) {
  return SocialPostModel(
    id: id,
    authorId: authorId,
    authorType: 'user',
    authorDisplayName: authorId,
    authorUsername: authorId,
    authorPhotoUrl: '',
    authorCategoryLabel: '',
    authorCity: 'Bengaluru',
    authorState: 'Karnataka',
    imageUrls: const <String>['https://example.com/image.jpg'],
    thumbnailUrls: const <String>['https://example.com/thumb.jpg'],
    imageAspectRatio: SocialPostAspectRatio.square,
    caption: 'caption',
    hashtags: const <String>['pets'],
    likeCount: 1,
    commentCount: 0,
    shareCount: 0,
    reportCount: 0,
    saveCount: 0,
    visibilityStatus: 'visible',
    moderationStatus: 'approved',
    moderationReason: '',
    moderatedBy: '',
    moderatedAt: null,
    lastReportedAt: null,
    isAdminPost: false,
    adminPriorityBoost: 0,
    recentEngagementScore: 0,
    homeEligible: true,
    homeScore: homeScore,
    homeRankVersion: 1,
    homeScoreUpdatedAt: null,
    nearbyEligible: false,
    nearbyDistanceKm: null,
    nearbyDistanceLabel: '',
    feedGeohash3: '',
    feedGeohash4: '',
    feedGeohash5: '',
    feedLocationVersion: 0,
    feedLocationUpdatedAt: null,
    createdAtEpoch: 1,
    createdAt: null,
    updatedAt: null,
    usesNearbyFallback: false,
  );
}
