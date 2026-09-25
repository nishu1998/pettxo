import '../../../profile/domain/models/user_profile.dart';
import '../../../social/data/social_post_repository.dart';
import '../../../social/domain/hashtag_normalizer.dart';
import '../../../social/domain/models/social_post_model.dart';

class ExploreSearchQuery {
  const ExploreSearchQuery({
    required this.raw,
    required this.hashtag,
    required this.isHashtagOnly,
  });

  factory ExploreSearchQuery.parse(String input) {
    final raw = input.trim();
    return ExploreSearchQuery(
      raw: raw,
      hashtag: normalizeHashtag(raw),
      isHashtagOnly: raw.startsWith('#'),
    );
  }

  final String raw;
  final String hashtag;
  final bool isHashtagOnly;

  bool get isEmpty => raw.isEmpty;
}

class ExploreSearchRequestTracker {
  int _generation = 0;

  int startRequest() => ++_generation;

  void invalidate() => _generation += 1;

  bool isCurrent(int requestGeneration) => requestGeneration == _generation;
}

List<UserProfile> filterSearchProfilesForViewer(
  Iterable<UserProfile> profiles, {
  required String currentUserId,
  required Set<String> blockedUserIds,
  required Set<String> mutedUserIds,
}) {
  final excluded = <String>{
    currentUserId.trim(),
    ...blockedUserIds,
    ...mutedUserIds,
  }..remove('');
  return profiles
      .where((profile) => profile.uid.trim().isNotEmpty)
      .where((profile) => profile.isPubliclyVisible)
      .where((profile) => !excluded.contains(profile.uid.trim()))
      .toList(growable: false);
}

List<SocialPostModel> filterSearchPostsForViewer(
  Iterable<SocialPostModel> posts, {
  required Set<String> blockedUserIds,
  required Set<String> mutedUserIds,
}) {
  final excluded = <String>{...blockedUserIds, ...mutedUserIds};
  return posts
      .where((post) => post.visibilityStatus == 'visible')
      .where((post) => post.moderationStatus == 'approved')
      .where((post) => !excluded.contains(post.authorId.trim()))
      .toList(growable: false);
}

List<ExploreHashtagSummary> reconcileExactHashtagSummary({
  required String normalizedHashtag,
  required List<ExploreHashtagSummary> suggestions,
  required List<SocialPostModel> exactPosts,
}) {
  if (normalizedHashtag.isEmpty || exactPosts.isEmpty) return suggestions;

  final exactIndex = suggestions.indexWhere(
    (summary) => summary.tag == normalizedHashtag,
  );
  final postIds = exactPosts.map((post) => post.id).toList(growable: false);
  final existing = exactIndex < 0 ? null : suggestions[exactIndex];
  final reconciled = ExploreHashtagSummary(
    tag: normalizedHashtag,
    postCount: existing == null
        ? exactPosts.length
        : existing.postCount < exactPosts.length
        ? exactPosts.length
        : existing.postCount,
    recentPostIds: postIds,
    lastUsedAt: existing?.lastUsedAt,
  );
  if (exactIndex < 0) {
    return <ExploreHashtagSummary>[reconciled, ...suggestions];
  }
  final result = List<ExploreHashtagSummary>.from(suggestions);
  result[exactIndex] = reconciled;
  return result;
}
