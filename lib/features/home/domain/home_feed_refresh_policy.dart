import '../../social/domain/models/social_post_model.dart';

class HomeFeedRefreshPolicy {
  const HomeFeedRefreshPolicy._();

  static bool shouldRetainExistingFeedAfterFailure({
    required bool hadExistingPosts,
  }) {
    return hadExistingPosts;
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

  int get currentRequestId => _latestRequestId;

  int startRequest() => ++_latestRequestId;

  bool isCurrent(int requestId) => requestId == _latestRequestId;
}

enum HomeFeedFooterState { none, loading, retry, caughtUp }

class HomeFeedLoadPolicy {
  const HomeFeedLoadPolicy._();

  static bool canLoadMore({
    required bool isInitialLoading,
    required bool isRefreshing,
    required bool isLoadingMore,
    required bool hasMore,
  }) {
    return !isInitialLoading && !isRefreshing && !isLoadingMore && hasMore;
  }

  static bool shouldRequestNextPage({
    required double pixels,
    required double maxScrollExtent,
    required double prefetchDistance,
  }) {
    return pixels >= maxScrollExtent - prefetchDistance;
  }

  static HomeFeedFooterState footerState({
    required bool hasEntries,
    required bool isInitialLoading,
    required bool isRefreshing,
    required bool isLoadingMore,
    required bool hasMore,
    required bool hasLoadMoreError,
  }) {
    if (!hasEntries || isInitialLoading || isRefreshing) {
      return HomeFeedFooterState.none;
    }
    if (hasLoadMoreError) return HomeFeedFooterState.retry;
    if (isLoadingMore) return HomeFeedFooterState.loading;
    if (!hasMore) return HomeFeedFooterState.caughtUp;
    return HomeFeedFooterState.none;
  }
}
