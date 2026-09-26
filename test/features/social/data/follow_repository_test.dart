import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/social/data/follow_repository.dart';

class _FollowBackend {
  bool relationshipExists = false;
  bool failNext = false;
  int changedMutations = 0;

  Future<Map<String, dynamic>> call(
    String functionName,
    Map<String, dynamic> payload,
  ) async {
    if (failNext) {
      failNext = false;
      throw Exception('backend unavailable');
    }
    if (functionName == 'getFollowState') {
      return {'isFollowing': relationshipExists};
    }
    if (functionName != 'setFollowState') {
      throw StateError('Unexpected function $functionName');
    }
    final desired = payload['desiredFollowing'] == true;
    final changed = relationshipExists != desired;
    if (changed) changedMutations += 1;
    relationshipExists = desired;
    return {'changed': changed, 'isFollowing': relationshipExists};
  }
}

void main() {
  test(
    'successful follow and unfollow return canonical backend state',
    () async {
      final backend = _FollowBackend();
      final repository = FollowRepository(callableInvoker: backend.call);

      expect(
        await repository.toggleFollow(
          followerId: 'viewer',
          followeeId: 'creator',
          currentlyFollowing: false,
        ),
        isTrue,
      );
      expect(
        await repository.toggleFollow(
          followerId: 'viewer',
          followeeId: 'creator',
          currentlyFollowing: true,
        ),
        isFalse,
      );
      expect(backend.changedMutations, 2);
    },
  );

  test('duplicate desired state is idempotent', () async {
    final backend = _FollowBackend()..relationshipExists = true;
    final repository = FollowRepository(callableInvoker: backend.call);

    await repository.followUser(followerId: 'viewer', followeeId: 'creator');
    await repository.followUser(followerId: 'viewer', followeeId: 'creator');

    expect(backend.relationshipExists, isTrue);
    expect(backend.changedMutations, 0);
  });

  test(
    'rapid repeated requests converge to the last committed state',
    () async {
      final backend = _FollowBackend();
      final repository = FollowRepository(callableInvoker: backend.call);

      await repository.followUser(followerId: 'viewer', followeeId: 'creator');
      await repository.unfollowUser(
        followerId: 'viewer',
        followeeId: 'creator',
      );
      await repository.followUser(followerId: 'viewer', followeeId: 'creator');

      expect(backend.relationshipExists, isTrue);
      expect(backend.changedMutations, 3);
    },
  );

  test('backend failure does not return a false success state', () async {
    final backend = _FollowBackend()..failNext = true;
    final repository = FollowRepository(callableInvoker: backend.call);

    await expectLater(
      repository.toggleFollow(
        followerId: 'viewer',
        followeeId: 'creator',
        currentlyFollowing: false,
      ),
      throwsA(isA<Exception>()),
    );
    expect(backend.relationshipExists, isFalse);
  });

  test('canonical state persists across repository recreation', () async {
    final backend = _FollowBackend();
    await FollowRepository(
      callableInvoker: backend.call,
    ).followUser(followerId: 'viewer', followeeId: 'creator');

    final reopened = FollowRepository(callableInvoker: backend.call);
    expect(
      await reopened.isFollowing(followerId: 'viewer', followeeId: 'creator'),
      isTrue,
    );
  });
}
