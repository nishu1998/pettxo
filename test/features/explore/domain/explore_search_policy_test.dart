import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/explore/domain/utils/explore_search_policy.dart';
import 'package:pettexo/features/profile/domain/models/user_profile.dart';
import 'package:pettexo/features/social/data/social_post_repository.dart';
import 'package:pettexo/features/social/domain/hashtag_normalizer.dart';
import 'package:pettexo/features/social/domain/models/social_post_model.dart';

void main() {
  group('canonical hashtag normalization', () {
    test('plain, hash-prefixed, case, and whitespace forms agree', () {
      for (final input in <String>[
        'rabbit',
        '#rabbit',
        'Rabbit',
        '#Rabbit',
        'RABBIT',
        '#RABBIT',
        '  #rabbit  ',
      ]) {
        expect(normalizeHashtag(input), 'rabbit');
      }
      for (final input in <String>[
        'adoption',
        '#adoption',
        'Adoption',
        '#Adoption',
        'ADOPTION',
        ' adoption ',
      ]) {
        expect(normalizeHashtag(input), 'adoption');
      }
      expect(normalizeHashtag('cat'), 'cat');
      expect(normalizeHashtag('#cat'), 'cat');
    });

    test(
      'only one leading hash is removed and invalid whitespace is rejected',
      () {
        expect(normalizeHashtag('##rabbit'), '#rabbit');
        expect(normalizeHashtag('rabbit#cat'), 'rabbit#cat');
        expect(normalizeHashtag('rabbit cat'), isEmpty);
      },
    );

    test(
      'post writer normalization deduplicates canonical hashtag identity',
      () {
        expect(
          normalizeHashtags(<String>['#Adoption', ' adoption ', 'ADOPTION']),
          <String>['adoption'],
        );
      },
    );

    test('typed and tapped hashtag queries share the canonical token', () {
      expect(ExploreSearchQuery.parse('adoption').hashtag, 'adoption');
      expect(ExploreSearchQuery.parse('#adoption').hashtag, 'adoption');
      expect(ExploreSearchQuery.parse(' #Adoption ').hashtag, 'adoption');
      expect(ExploreSearchQuery.parse('#adoption').isHashtagOnly, isTrue);
      expect(ExploreSearchQuery.parse('adoption').isHashtagOnly, isFalse);
    });
  });

  group('hashtag result reconciliation', () {
    test('missing adoption metadata is synthesized from canonical posts', () {
      final posts = <SocialPostModel>[
        _post('post-a', 'author-a', hashtags: const ['adoption']),
        _post('post-b', 'author-b', hashtags: const ['adoption']),
      ];

      final summaries = reconcileExactHashtagSummary(
        normalizedHashtag: 'adoption',
        suggestions: const <ExploreHashtagSummary>[],
        exactPosts: posts,
      );

      expect(summaries.single.tag, 'adoption');
      expect(summaries.single.postCount, 2);
      expect(summaries.single.recentPostIds, <String>['post-a', 'post-b']);
    });

    test('stale rabbit metadata is reconciled with all returned posts', () {
      final posts = <SocialPostModel>[
        _post('new-rabbit', 'author-a', hashtags: const ['rabbit']),
        _post('old-rabbit', 'author-b', hashtags: const ['rabbit']),
      ];
      const stale = ExploreHashtagSummary(
        tag: 'rabbit',
        postCount: 1,
        recentPostIds: <String>['old-rabbit'],
        lastUsedAt: null,
      );

      final summaries = reconcileExactHashtagSummary(
        normalizedHashtag: 'rabbit',
        suggestions: const <ExploreHashtagSummary>[stale],
        exactPosts: posts,
      );

      expect(summaries.single.postCount, 2);
      expect(summaries.single.recentPostIds, <String>[
        'new-rabbit',
        'old-rabbit',
      ]);
    });
  });

  group('search request identity', () {
    test('an older response cannot replace a newer query', () {
      final tracker = ExploreSearchRequestTracker();
      final adoptionRequest = tracker.startRequest();
      final rabbitRequest = tracker.startRequest();

      expect(tracker.isCurrent(adoptionRequest), isFalse);
      expect(tracker.isCurrent(rabbitRequest), isTrue);
    });

    test('clear search invalidates an in-flight response', () {
      final tracker = ExploreSearchRequestTracker();
      final request = tracker.startRequest();

      tracker.invalidate();

      expect(tracker.isCurrent(request), isFalse);
    });
  });

  group('search visibility', () {
    test('profiles respect current-user, block, and mute state', () {
      final visible = filterSearchProfilesForViewer(
        <UserProfile>[
          _profile('viewer'),
          _profile('allowed'),
          _profile('blocked'),
          _profile('muted'),
          _profile('deleted', isDeleted: true),
        ],
        currentUserId: 'viewer',
        blockedUserIds: const <String>{'blocked'},
        mutedUserIds: const <String>{'muted'},
      );

      expect(visible.map((profile) => profile.uid), <String>['allowed']);
    });

    test('hidden, unapproved, blocked, and muted posts are excluded', () {
      final visible = filterSearchPostsForViewer(
        <SocialPostModel>[
          _post('allowed', 'author-a'),
          _post('hidden', 'author-b', visibility: 'hidden'),
          _post('pending', 'author-c', moderation: 'pending'),
          _post('blocked', 'author-blocked'),
          _post('muted', 'author-muted'),
        ],
        blockedUserIds: const <String>{'author-blocked'},
        mutedUserIds: const <String>{'author-muted'},
      );

      expect(visible.map((post) => post.id), <String>['allowed']);
    });
  });
}

SocialPostModel _post(
  String id,
  String authorId, {
  List<String> hashtags = const <String>['pets'],
  String visibility = 'visible',
  String moderation = 'approved',
}) {
  return SocialPostModel.fromMap(<String, dynamic>{
    'id': id,
    'authorId': authorId,
    'hashtags': hashtags,
    'visibilityStatus': visibility,
    'moderationStatus': moderation,
  });
}

UserProfile _profile(String uid, {bool isDeleted = false}) {
  return UserProfile.fromMap(<String, dynamic>{
    'uid': uid,
    'displayName': 'Name $uid',
    'name': 'Name $uid',
    'username': uid,
    'usernameLowercase': uid,
    'accountStatus': 'active',
    'isActive': true,
    'isDeleted': isDeleted,
    'profileVisibility': 'public',
  });
}
