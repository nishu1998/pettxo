import 'package:flutter/foundation.dart';

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
    String? diagnosticsLabel,
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
          bool exclude(String reason) {
            _logDecision(diagnosticsLabel, postId, authorId, false, reason);
            return false;
          }

          if (postId.isEmpty) return exclude('MISSING_POST_ID');
          if (authorId.isEmpty) return exclude('MISSING_AUTHOR');
          if (seenPostIds.contains(postId)) return exclude('DUPLICATE');
          if (post.visibilityStatus != 'visible') return exclude('NOT_VISIBLE');
          if (post.moderationStatus != 'approved') {
            return exclude('NOT_APPROVED');
          }
          if ((_authorVisibilityCache[authorId] ?? false) == false) {
            return exclude('ACCOUNT_INELIGIBLE');
          }
          if (viewerContext.blockedUserIds.contains(authorId)) {
            return exclude('AUTHOR_BLOCKED');
          }
          if (viewerContext.mutedUserIds.contains(authorId)) {
            return exclude('AUTHOR_MUTED');
          }
          seenPostIds.add(postId);
          _logDecision(diagnosticsLabel, postId, authorId, true, 'INCLUDED');
          return true;
        })
        .toList(growable: false);
  }

  void _logDecision(
    String? label,
    String postId,
    String authorId,
    bool included,
    String reason,
  ) {
    if (!kDebugMode || label != 'nearby') return;
    debugPrint(
      '[NearbyDiag] client-filter postId=$postId authorId=$authorId '
      'included=$included reason=$reason',
    );
  }
}
