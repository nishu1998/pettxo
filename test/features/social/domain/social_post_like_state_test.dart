import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/social/domain/models/social_post_model.dart';
import 'package:pettexo/features/social/domain/social_post_like_state.dart';

void main() {
  test('like updates remain attached to post id across reordering', () {
    final postA = _post('post-a', 'author-a', 'Alice', likeCount: 0);
    final postB = _post('post-b', 'author-b', 'Bob', likeCount: 7);

    final updated = updateSocialPostLikeState(
      <SocialPostModel>[postB, postA],
      postId: 'post-a',
      likeCount: 1,
    );

    expect(updated.map((post) => post.id), <String>['post-b', 'post-a']);
    expect(updated[0].authorId, 'author-b');
    expect(updated[0].authorDisplayName, 'Bob');
    expect(updated[0].likeCount, 7);
    expect(updated[1].authorId, 'author-a');
    expect(updated[1].authorDisplayName, 'Alice');
    expect(updated[1].likeCount, 1);
  });

  test('rapid like unlike like converges without touching another post', () {
    var posts = <SocialPostModel>[
      _post('post-a', 'author-a', 'Alice', likeCount: 0),
      _post('post-b', 'author-b', 'Bob', likeCount: 4),
    ];

    for (final count in <int>[1, 0, 1]) {
      posts = updateSocialPostLikeState(
        posts,
        postId: 'post-a',
        likeCount: count,
      );
    }

    expect(posts.first.likeCount, 1);
    expect(posts.last.likeCount, 4);
  });

  test('newer detail mutation wins over an older refresh response', () {
    final staleResponse = <SocialPostModel>[
      _post('post-a', 'author-a', 'Alice', likeCount: 0),
    ];
    const mutation = SocialPostLikeMutation(
      isLiked: true,
      likeCount: 1,
      revision: 2,
    );

    final reconciled = applyNewerSocialPostLikeMutations(
      staleResponse,
      mutations: const <String, SocialPostLikeMutation>{'post-a': mutation},
      requestStartRevision: 1,
    );

    expect(reconciled.single.likeCount, 1);
  });

  test('a later refresh remains the canonical count source', () {
    final canonicalResponse = <SocialPostModel>[
      _post('post-a', 'author-a', 'Alice', likeCount: 3),
    ];
    const mutation = SocialPostLikeMutation(
      isLiked: true,
      likeCount: 1,
      revision: 2,
    );

    final reconciled = applyNewerSocialPostLikeMutations(
      canonicalResponse,
      mutations: const <String, SocialPostLikeMutation>{'post-a': mutation},
      requestStartRevision: 2,
    );

    expect(reconciled.single.likeCount, 3);
  });

  test('an in-flight mutation is preserved by a newer refresh request', () {
    final staleResponse = <SocialPostModel>[
      _post('post-a', 'author-a', 'Alice', likeCount: 0),
    ];
    const mutation = SocialPostLikeMutation(
      isLiked: true,
      likeCount: 1,
      revision: 2,
      isPending: true,
    );

    final reconciled = applyNewerSocialPostLikeMutations(
      staleResponse,
      mutations: const <String, SocialPostLikeMutation>{'post-a': mutation},
      requestStartRevision: 2,
    );

    expect(reconciled.single.likeCount, 1);
  });

  test('viewer liked state follows only newer or pending mutations', () {
    const settled = SocialPostLikeMutation(
      isLiked: true,
      likeCount: 3,
      revision: 2,
    );
    const pending = SocialPostLikeMutation(
      isLiked: false,
      likeCount: 2,
      revision: 4,
      isPending: true,
    );

    final reconciled = applyNewerViewerLikeMutations(
      <String>{'post-b'},
      mutations: const <String, SocialPostLikeMutation>{
        'post-a': settled,
        'post-b': pending,
      },
      requestStartRevision: 4,
    );

    expect(reconciled, <String>{});
  });
}

SocialPostModel _post(
  String id,
  String authorId,
  String authorName, {
  required int likeCount,
}) {
  return SocialPostModel.fromMap(<String, dynamic>{
    'id': id,
    'authorId': authorId,
    'authorDisplayName': authorName,
    'authorUsername': authorName.toLowerCase(),
    'likeCount': likeCount,
  });
}
