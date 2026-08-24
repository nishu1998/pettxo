import '../../social/domain/models/social_post_model.dart';
import '../data/home_feed_repository.dart';

class HomeFeedEntry {
  static const Object _sentinel = Object();

  final SocialPostModel post;
  final String? rankingReason;

  const HomeFeedEntry({required this.post, required this.rankingReason});

  HomeFeedEntry copyWith({
    SocialPostModel? post,
    Object? rankingReason = _sentinel,
  }) {
    return HomeFeedEntry(
      post: post ?? this.post,
      rankingReason: identical(rankingReason, _sentinel)
          ? this.rankingReason
          : rankingReason as String?,
    );
  }
}

class HomeFeedSession {
  HomeFeedSession({this.lookAheadWindow = 12});
  final int lookAheadWindow;

  final List<SocialPostModel> _candidateBuffer = <SocialPostModel>[];
  final List<HomeFeedEntry> _emittedEntries = <HomeFeedEntry>[];
  final Set<String> _knownPostIds = <String>{};
  final Set<String> _emittedPostIds = <String>{};
  final Set<String> _seenPostIds = <String>{};
  final List<String> _recentAuthorIds = <String>[];

  List<HomeFeedEntry> get entries =>
      List<HomeFeedEntry>.unmodifiable(_emittedEntries);

  Set<String> get emittedPostIds => Set<String>.unmodifiable(_emittedPostIds);

  bool get hasPendingCandidates => _candidateBuffer.isNotEmpty;

  void reset({
    required List<SocialPostModel> candidates,
    required HomeFeedViewerContext viewerContext,
    required int initialEntryCount,
    bool preserveSeenPosts = true,
  }) {
    final preservedSeen = preserveSeenPosts
        ? Set<String>.from(_seenPostIds)
        : <String>{};
    _candidateBuffer
      ..clear()
      ..addAll(candidates.where((post) => post.id.trim().isNotEmpty));
    _emittedEntries.clear();
    _knownPostIds
      ..clear()
      ..addAll(_candidateBuffer.map((post) => post.id.trim()));
    _emittedPostIds.clear();
    _recentAuthorIds.clear();
    _seenPostIds
      ..clear()
      ..addAll(preservedSeen);

    _appendNextEntries(count: initialEntryCount, viewerContext: viewerContext);
  }

  void appendCandidates({
    required List<SocialPostModel> candidates,
    required HomeFeedViewerContext viewerContext,
    required int count,
  }) {
    for (final post in candidates) {
      final postId = post.id.trim();
      if (postId.isEmpty) continue;
      if (_knownPostIds.add(postId)) {
        _candidateBuffer.add(post);
      }
    }

    _appendNextEntries(count: count, viewerContext: viewerContext);
  }

  void emitMoreEntries({
    required HomeFeedViewerContext viewerContext,
    required int count,
  }) {
    _appendNextEntries(count: count, viewerContext: viewerContext);
  }

  void replacePost(SocialPostModel post) {
    final postId = post.id.trim();
    if (postId.isEmpty) return;

    for (var index = 0; index < _candidateBuffer.length; index += 1) {
      if (_candidateBuffer[index].id == postId) {
        _candidateBuffer[index] = post;
      }
    }
    for (var index = 0; index < _emittedEntries.length; index += 1) {
      if (_emittedEntries[index].post.id == postId) {
        _emittedEntries[index] = _emittedEntries[index].copyWith(post: post);
      }
    }
  }

  void removePost(String postId) {
    final trimmedPostId = postId.trim();
    if (trimmedPostId.isEmpty) return;

    _candidateBuffer.removeWhere((post) => post.id == trimmedPostId);
    _emittedEntries.removeWhere((entry) => entry.post.id == trimmedPostId);
    _knownPostIds.remove(trimmedPostId);
    _emittedPostIds.remove(trimmedPostId);
    _seenPostIds.remove(trimmedPostId);
    _rebuildRecentAuthors();
  }

  void _appendNextEntries({
    required int count,
    required HomeFeedViewerContext viewerContext,
  }) {
    while (_candidateBuffer.isNotEmpty && count > 0) {
      final candidateIndex = _chooseNextIndex(viewerContext);
      final nextPost = _candidateBuffer.removeAt(candidateIndex);
      final postId = nextPost.id.trim();
      if (_emittedPostIds.contains(postId)) {
        continue;
      }

      _emittedEntries.add(
        HomeFeedEntry(
          post: nextPost,
          rankingReason: _buildRankingReason(nextPost, viewerContext),
        ),
      );
      _emittedPostIds.add(postId);
      _seenPostIds.add(postId);

      final authorId = nextPost.authorId.trim();
      if (authorId.isNotEmpty) {
        _recentAuthorIds.insert(0, authorId);
        if (_recentAuthorIds.length > 3) {
          _recentAuthorIds.removeLast();
        }
      }
      count -= 1;
    }
  }

  int _chooseNextIndex(HomeFeedViewerContext viewerContext) {
    final maxIndex = _candidateBuffer.length < lookAheadWindow
        ? _candidateBuffer.length
        : lookAheadWindow;
    var bestIndex = 0;
    var bestScore = double.infinity;

    for (var index = 0; index < maxIndex; index += 1) {
      final post = _candidateBuffer[index];
      final adjustedScore = _adjustedPriority(
        post,
        viewerContext: viewerContext,
        canonicalIndex: index,
      );
      if (adjustedScore < bestScore) {
        bestIndex = index;
        bestScore = adjustedScore;
      }
    }

    return bestIndex;
  }

  double _adjustedPriority(
    SocialPostModel post, {
    required HomeFeedViewerContext viewerContext,
    required int canonicalIndex,
  }) {
    final authorId = post.authorId.trim();
    var score = canonicalIndex.toDouble();

    if (viewerContext.followingIds.contains(authorId)) {
      score -= 1.25;
    }
    if (_seenPostIds.contains(post.id.trim())) {
      score += 3.5;
    }
    if (_recentAuthorIds.isNotEmpty && _recentAuthorIds.first == authorId) {
      score += 2.2;
    } else if (_recentAuthorIds.skip(1).contains(authorId)) {
      score += 0.75;
    }

    return score;
  }

  String? _buildRankingReason(
    SocialPostModel post,
    HomeFeedViewerContext viewerContext,
  ) {
    if (post.isAdminPost || post.authorType.trim().toLowerCase() == 'admin') {
      return 'Pettxo update';
    }

    if (viewerContext.followingIds.contains(post.authorId.trim())) {
      return 'Following';
    }

    final postCity = post.authorCity.trim().toLowerCase();
    final postState = post.authorState.trim().toLowerCase();
    final viewerCity = viewerContext.city.trim().toLowerCase();
    final viewerState = viewerContext.state.trim().toLowerCase();
    if (viewerCity.isNotEmpty &&
        viewerState.isNotEmpty &&
        postCity == viewerCity &&
        postState == viewerState) {
      return 'Near you';
    }

    final weightedEngagement =
        post.likeCount + (post.commentCount * 3) + (post.shareCount * 5);
    if (weightedEngagement >= 12 || post.homeScore >= 4.5) {
      return 'Popular';
    }

    return 'Fresh';
  }

  void _rebuildRecentAuthors() {
    _recentAuthorIds
      ..clear()
      ..addAll(
        _emittedEntries.reversed
            .map((entry) => entry.post.authorId.trim())
            .where((authorId) => authorId.isNotEmpty)
            .take(3)
            .toList(growable: false)
            .reversed,
      );
  }
}
