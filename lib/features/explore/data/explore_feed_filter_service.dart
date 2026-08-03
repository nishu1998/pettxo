import '../../profile/data/repositories/profile_repository.dart';
import '../../social/domain/models/social_post_model.dart';
import '../domain/models/explore_feed_viewer_context.dart';

class ExploreFeedFilterService {
  ExploreFeedFilterService({ProfileRepository? profileRepository})
    : _profileRepository = profileRepository;

  final ProfileRepository? _profileRepository;
  final Map<String, bool> _authorVisibilityCache = <String, bool>{};

  ProfileRepository get _resolvedProfileRepository =>
      _profileRepository ?? ProfileRepository();

  Future<List<SocialPostModel>> apply({
    required List<SocialPostModel> posts,
    required ExploreFeedViewerContext viewerContext,
    required Set<String> seenPostIds,
  }) async {
    if (posts.isEmpty) return const <SocialPostModel>[];

    final missingAuthorIds = posts
        .map((post) => post.authorId.trim())
        .where((authorId) => authorId.isNotEmpty)
        .where((authorId) => !_authorVisibilityCache.containsKey(authorId))
        .toSet()
        .toList(growable: false);

    if (missingAuthorIds.isNotEmpty) {
      final fetchedVisibility = await _resolvedProfileRepository
          .fetchPublicVisibilityByIds(missingAuthorIds);
      _authorVisibilityCache.addAll(fetchedVisibility);
    }

    return posts
        .where((post) {
          final postId = post.id.trim();
          final authorId = post.authorId.trim();
          if (postId.isEmpty || authorId.isEmpty) return false;
          if (seenPostIds.contains(postId)) return false;
          if (post.visibilityStatus != 'visible') return false;
          if (post.moderationStatus != 'approved') return false;
          if ((_authorVisibilityCache[authorId] ?? false) == false) {
            return false;
          }
          if (viewerContext.blockedUserIds.contains(authorId)) return false;
          if (viewerContext.mutedUserIds.contains(authorId)) return false;
          seenPostIds.add(postId);
          return true;
        })
        .toList(growable: false);
  }
}
