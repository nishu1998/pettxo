import '../../social/domain/models/social_post_model.dart';

class HomeFeedRefreshPolicy {
  const HomeFeedRefreshPolicy._();

  static bool shouldReplaceVisibleFeed({
    required bool hadExistingPosts,
    required List<SocialPostModel> refreshedPosts,
  }) {
    if (!hadExistingPosts) return true;
    return refreshedPosts.isNotEmpty;
  }

  static List<SocialPostModel> dedupeReplacementPosts(
    List<SocialPostModel> incoming,
  ) {
    final seenIds = <String>{};
    final uniqueIncoming = <SocialPostModel>[];

    for (final post in incoming) {
      final postId = post.id.trim();
      if (postId.isEmpty || !seenIds.add(postId)) continue;
      uniqueIncoming.add(post);
    }

    return uniqueIncoming;
  }

  static List<SocialPostModel> dedupeAppendedPosts(
    List<SocialPostModel> incoming, {
    required Iterable<String> existingPostIds,
  }) {
    final seenIds = existingPostIds.map((id) => id.trim()).toSet();
    final uniqueIncoming = <SocialPostModel>[];

    for (final post in incoming) {
      final postId = post.id.trim();
      if (postId.isEmpty || !seenIds.add(postId)) continue;
      uniqueIncoming.add(post);
    }

    return uniqueIncoming;
  }
}

class HomeFeedRequestTracker {
  int _latestRequestId = 0;

  int startRequest() => ++_latestRequestId;

  bool isCurrent(int requestId) => requestId == _latestRequestId;
}
