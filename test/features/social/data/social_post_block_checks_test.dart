import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/blocking/data/blocked_user_set_cache.dart';
import 'package:pettexo/features/social/data/social_post_repository.dart';

import '../../../helpers/fake_app_services.dart';
import '../../../helpers/in_memory_firestore.dart';

const _me = 'alice';
const _other = 'bob';
const _postId = 'p1';

Map<String, dynamic> _post({String? authorId}) => <String, dynamic>{
  'authorId': ?authorId,
  'caption': 'hello',
  'visibilityStatus': 'visible',
  'moderationStatus': 'approved',
  'likeCount': 0,
  'commentCount': 0,
  'shareCount': 0,
  'reportCount': 0,
  'createdAt': Timestamp.fromMillisecondsSinceEpoch(0),
};

void main() {
  late InMemoryFirestore db;
  late FakeNotificationRepository notifications;
  late SocialPostRepository repository;

  void block(String owner, String blocked) {
    db.seed('userBlocks/${owner}_$blocked', <String, dynamic>{
      'ownerUserId': owner,
      'blockedUserId': blocked,
    });
  }

  setUp(() {
    BlockedUserSetCache.instance.invalidate();
    db = InMemoryFirestore()
      ..seed('socialPosts/$_postId', _post(authorId: _other));
    notifications = FakeNotificationRepository();
    repository = SocialPostRepository(
      firestore: db,
      storage: FakeStorage(),
      auth: FakeAuth(_me),
      profileRepository: FakeProfileRepository(_me),
      notificationRepository: notifications,
    );
  });

  tearDown(() => BlockedUserSetCache.instance.invalidate());

  group('toggleLike', () {
    test(
      'likes and unlikes with no block, without userBlocks point gets',
      () async {
        final liked = await repository.toggleLike(
          postId: _postId,
          currentUserId: _me,
        );
        expect(liked.isLiked, isTrue);
        expect(liked.likeCount, 1);
        expect(db.exists('socialPosts/$_postId/likes/$_me'), isTrue);
        expect(notifications.created, <String>['like:$_other:$_postId']);

        final unliked = await repository.toggleLike(
          postId: _postId,
          currentUserId: _me,
        );
        expect(unliked.isLiked, isFalse);
        expect(db.read('socialPosts/$_postId')!['likeCount'], 0);
        expect(db.pointGetsOn('userBlocks'), isEmpty);
      },
    );

    for (final pair in <List<String>>[
      <String>[_me, _other],
      <String>[_other, _me],
    ]) {
      test(
        'throws the friendly error with block ${pair[0]}_${pair[1]}',
        () async {
          block(pair[0], pair[1]);
          await expectLater(
            repository.toggleLike(postId: _postId, currentUserId: _me),
            throwsA(
              predicate(
                (e) => e.toString().contains(
                  'This post is no longer available for likes.',
                ),
              ),
            ),
          );
          expect(db.exists('socialPosts/$_postId/likes/$_me'), isFalse);
          expect(db.pointGetsOn('userBlocks'), isEmpty);
        },
      );
    }

    test('own post needs no block lookup', () async {
      db.seed('socialPosts/own', _post(authorId: _me));
      await repository.toggleLike(postId: 'own', currentUserId: _me);
      expect(db.queriesOn('userBlocks'), isEmpty);
      expect(db.pointGetsOn('userBlocks'), isEmpty);
    });

    test(
      'a failed block-set load fails the like instead of allowing it',
      () async {
        db.queryErrors['userBlocks'] = FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
        );
        await expectLater(
          repository.toggleLike(postId: _postId, currentUserId: _me),
          throwsA(isA<FirebaseException>()),
        );
        expect(db.exists('socialPosts/$_postId/likes/$_me'), isFalse);
      },
    );
  });

  group('addComment', () {
    test('comments with no block, without userBlocks point gets', () async {
      final comment = await repository.addComment(
        postId: _postId,
        currentUserId: _me,
        text: 'nice',
      );
      expect(comment.text, 'nice');
      expect(comment.authorId, _me);
      expect(db.read('socialPosts/$_postId')!['commentCount'], 1);
      expect(db.pointGetsOn('userBlocks'), isEmpty);
    });

    test('throws the friendly error with a block', () async {
      block(_other, _me);
      await expectLater(
        repository.addComment(postId: _postId, currentUserId: _me, text: 'x'),
        throwsA(
          predicate(
            (e) => e.toString().contains(
              'This post is no longer available for comments.',
            ),
          ),
        ),
      );
      expect(db.read('socialPosts/$_postId')!['commentCount'], 0);
      expect(db.pointGetsOn('userBlocks'), isEmpty);
    });
  });

  group('incrementShareCount', () {
    test('increments with no block, without userBlocks point gets', () async {
      expect(await repository.incrementShareCount(postId: _postId), 1);
      expect(db.read('socialPosts/$_postId')!['shareCount'], 1);
      expect(db.pointGetsOn('userBlocks'), isEmpty);
    });

    test('throws the friendly error with a block', () async {
      block(_me, _other);
      await expectLater(
        repository.incrementShareCount(postId: _postId),
        throwsA(
          predicate(
            (e) => e.toString().contains(
              'This post is no longer available for sharing.',
            ),
          ),
        ),
      );
      expect(db.read('socialPosts/$_postId')!['shareCount'], 0);
      expect(db.pointGetsOn('userBlocks'), isEmpty);
    });
  });

  test('the block set is loaded once across several actions', () async {
    await repository.toggleLike(postId: _postId, currentUserId: _me);
    await repository.addComment(postId: _postId, currentUserId: _me, text: 'a');
    await repository.incrementShareCount(postId: _postId);
    expect(db.queriesOn('userBlocks'), hasLength(2));
  });
}
