import 'models/social_post_model.dart';

class SocialPostLikeMutation {
  final bool isLiked;
  final int likeCount;
  final int revision;
  final bool isPending;

  const SocialPostLikeMutation({
    required this.isLiked,
    required this.likeCount,
    required this.revision,
    this.isPending = false,
  });
}

List<SocialPostModel> updateSocialPostLikeState(
  List<SocialPostModel> posts, {
  required String postId,
  required int likeCount,
}) {
  return posts
      .map(
        (post) =>
            post.id == postId ? post.copyWith(likeCount: likeCount) : post,
      )
      .toList(growable: false);
}

List<SocialPostModel> applyNewerSocialPostLikeMutations(
  List<SocialPostModel> posts, {
  required Map<String, SocialPostLikeMutation> mutations,
  required int requestStartRevision,
}) {
  return posts
      .map((post) {
        final mutation = mutations[post.id];
        if (mutation == null ||
            (!mutation.isPending &&
                mutation.revision <= requestStartRevision)) {
          return post;
        }
        return post.copyWith(likeCount: mutation.likeCount);
      })
      .toList(growable: false);
}

Set<String> applyNewerViewerLikeMutations(
  Set<String> canonicalLikedPostIds, {
  required Map<String, SocialPostLikeMutation> mutations,
  required int requestStartRevision,
}) {
  final reconciled = Set<String>.from(canonicalLikedPostIds);
  for (final entry in mutations.entries) {
    final mutation = entry.value;
    if (!mutation.isPending && mutation.revision <= requestStartRevision) {
      continue;
    }
    if (mutation.isLiked) {
      reconciled.add(entry.key);
    } else {
      reconciled.remove(entry.key);
    }
  }
  return reconciled;
}
