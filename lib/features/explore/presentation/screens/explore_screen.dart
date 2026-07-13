import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/navigation/social_app_tab.dart';
import '../../../../core/widgets/app_user_avatar.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../social/data/follow_repository.dart';
import '../../../social/data/social_post_repository.dart';
import '../../../social/domain/models/social_post_model.dart';
import '../../../social/presentation/widgets/live_author_resolver.dart';
import '../../../social/presentation/widgets/social_post_card.dart';

const bool _debugExploreRanking = false;

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  static _ExploreCache? _memoryCache;

  final SocialPostRepository _socialPostRepository = SocialPostRepository();
  final ProfileRepository _profileRepository = ProfileRepository();
  final FollowRepository _followRepository = FollowRepository();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  Timer? _searchDebounce;
  bool _isLoadingSections = true;
  bool _isSearching = false;
  bool _isSearchBarVisible = true;
  String? _sectionsError;
  String? _searchError;
  String _searchQuery = '';

  UserProfile? _viewerProfile;
  List<SocialPostModel> _recentPostsCache = const <SocialPostModel>[];
  List<SocialPostModel> _trendingPosts = const <SocialPostModel>[];
  List<SocialPostModel> _prefetchedTrendingPosts = const <SocialPostModel>[];
  List<SocialPostModel> _popularPosts = const <SocialPostModel>[];
  List<SocialPostModel> _prefetchedPopularPosts = const <SocialPostModel>[];
  List<ExploreHashtagSummary> _trendingHashtags =
      const <ExploreHashtagSummary>[];
  List<UserProfile> _profileResults = const <UserProfile>[];
  List<ExploreHashtagSummary> _hashtagSuggestions =
      const <ExploreHashtagSummary>[];
  List<SocialPostModel> _hashtagResults = const <SocialPostModel>[];
  Set<String> _followingIds = <String>{};
  double _lastScrollOffset = 0;
  double _scrollDeltaAccumulator = 0;

  static const double _topBarTopResetOffset = 12;
  static const double _topBarHideThreshold = 32;
  static const double _topBarShowThreshold = 14;

  String get _currentUserId => _auth.currentUser?.uid.trim() ?? '';
  bool get _isSearchMode => _searchQuery.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _searchController.addListener(_handleSearchChanged);
    final cache = _memoryCache;
    if (cache != null && cache.hasDiscoveryData) {
      _applyCache(cache);
      _isLoadingSections = false;
    } else {
      _loadExploreSections();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _applyCache(_ExploreCache cache) {
    _viewerProfile = cache.viewerProfile;
    _recentPostsCache = cache.recentPosts;
    _trendingPosts = cache.trendingPosts;
    _prefetchedTrendingPosts = cache.prefetchedTrendingPosts;
    _popularPosts = cache.popularPosts;
    _prefetchedPopularPosts = cache.prefetchedPopularPosts;
    _trendingHashtags = cache.trendingHashtags;
    _followingIds = cache.followingIds;
    _sectionsError = null;
  }

  void _saveCache() {
    _memoryCache = _ExploreCache(
      viewerProfile: _viewerProfile,
      recentPosts: List<SocialPostModel>.from(_recentPostsCache),
      trendingPosts: List<SocialPostModel>.from(_trendingPosts),
      prefetchedTrendingPosts: List<SocialPostModel>.from(
        _prefetchedTrendingPosts,
      ),
      popularPosts: List<SocialPostModel>.from(_popularPosts),
      prefetchedPopularPosts: List<SocialPostModel>.from(
        _prefetchedPopularPosts,
      ),
      trendingHashtags: List<ExploreHashtagSummary>.from(_trendingHashtags),
      followingIds: Set<String>.from(_followingIds),
    );
  }

  Future<void> _refreshExploreSections() async {
    _memoryCache = null;
    await _loadExploreSections(forceRefresh: true);
  }

  Future<void> _loadExploreSections({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cache = _memoryCache;
      if (cache != null && cache.hasDiscoveryData) {
        if (mounted) {
          setState(() {
            _applyCache(cache);
            _isLoadingSections = false;
          });
        }
        return;
      }
    }

    setState(() {
      _isLoadingSections = true;
      _sectionsError = null;
    });

    try {
      final currentUserId = _currentUserId;
      final profileFuture = currentUserId.isEmpty
          ? Future<UserProfile?>.value(null)
          : _profileRepository.getCurrentUserProfile();
      final followingFuture = currentUserId.isEmpty
          ? Future<Set<String>>.value(<String>{})
          : _followRepository.fetchFollowingIds(currentUserId);
      final recentPostsFuture = _socialPostRepository.fetchRecentVisiblePosts(
        limit: 40,
      );
      final popularPostsFuture = _socialPostRepository.fetchPopularPosts(
        limit: 20,
        allowLocalFallback: false,
      );
      final trendingHashtagsFuture = _socialPostRepository
          .fetchTrendingHashtags(limit: 10);

      final results = await Future.wait<dynamic>([
        profileFuture,
        followingFuture,
        recentPostsFuture,
        popularPostsFuture,
        trendingHashtagsFuture,
      ]);

      final currentProfile = results[0] as UserProfile?;
      final followingIds = results[1] as Set<String>;
      final recentPosts = results[2] as List<SocialPostModel>;
      var popularPosts = results[3] as List<SocialPostModel>;
      final trendingHashtags = results[4] as List<ExploreHashtagSummary>;
      final rankingContext = _ExploreRankingContext(
        followingIds: followingIds,
        userCity: currentProfile?.city ?? '',
        userState: currentProfile?.state ?? '',
      );
      final rankedTrending = _rankPostsForExplore(
        recentPosts,
        rankingContext,
        limit: 20,
        debugLabel: 'trending',
      );

      if (!mounted) return;
      setState(() {
        _viewerProfile = currentProfile;
        _followingIds = followingIds;
        _recentPostsCache = recentPosts;
        _trendingPosts = rankedTrending.take(10).toList(growable: false);
        _prefetchedTrendingPosts = rankedTrending
            .skip(10)
            .take(10)
            .toList(growable: false);
        _popularPosts = popularPosts.take(10).toList(growable: false);
        _prefetchedPopularPosts = popularPosts
            .skip(10)
            .take(10)
            .toList(growable: false);
        _trendingHashtags = trendingHashtags;
      });
      _saveCache();

      if (_isSearchMode) {
        await _runSearch(_searchQuery);
      }
    } on FirebaseException catch (error) {
      if (!mounted) return;
      if (error.code != 'failed-precondition') {
        setState(() {
          _sectionsError = error.message ?? error.toString();
        });
        return;
      }

      try {
        final currentUserId = _currentUserId;
        final profileFuture = currentUserId.isEmpty
            ? Future<UserProfile?>.value(null)
            : _profileRepository.getCurrentUserProfile();
        final followingFuture = currentUserId.isEmpty
            ? Future<Set<String>>.value(<String>{})
            : _followRepository.fetchFollowingIds(currentUserId);
        final recentPostsFuture = _socialPostRepository.fetchRecentVisiblePosts(
          limit: 40,
        );
        final trendingHashtagsFuture = _socialPostRepository
            .fetchTrendingHashtags(limit: 10);

        final fallbackResults = await Future.wait<dynamic>([
          profileFuture,
          followingFuture,
          recentPostsFuture,
          trendingHashtagsFuture,
        ]);

        final currentProfile = fallbackResults[0] as UserProfile?;
        final followingIds = fallbackResults[1] as Set<String>;
        final recentPosts = fallbackResults[2] as List<SocialPostModel>;
        final trendingHashtags =
            fallbackResults[3] as List<ExploreHashtagSummary>;
        final rankingContext = _ExploreRankingContext(
          followingIds: followingIds,
          userCity: currentProfile?.city ?? '',
          userState: currentProfile?.state ?? '',
        );
        final rankedTrending = _rankPostsForExplore(
          recentPosts,
          rankingContext,
          limit: 20,
          debugLabel: 'trending-fallback',
        );
        final fallbackPopularPosts = _rankPostsForExplore(
          recentPosts,
          rankingContext,
          limit: 20,
          debugLabel: 'popular-fallback',
        );

        if (!mounted) return;
        setState(() {
          _viewerProfile = currentProfile;
          _followingIds = followingIds;
          _recentPostsCache = recentPosts;
          _trendingPosts = rankedTrending.take(10).toList(growable: false);
          _prefetchedTrendingPosts = rankedTrending
              .skip(10)
              .take(10)
              .toList(growable: false);
          _popularPosts = fallbackPopularPosts.take(10).toList(growable: false);
          _prefetchedPopularPosts = fallbackPopularPosts
              .skip(10)
              .take(10)
              .toList(growable: false);
          _trendingHashtags = trendingHashtags;
          _sectionsError = null;
        });
        _saveCache();

        if (_isSearchMode) {
          await _runSearch(_searchQuery);
        }
      } catch (fallbackError) {
        if (!mounted) return;
        setState(() {
          _sectionsError = fallbackError.toString().replaceFirst(
            'Exception: ',
            '',
          );
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sectionsError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingSections = false);
      }
    }
  }

  List<SocialPostModel> _rankPostsForExplore(
    List<SocialPostModel> posts,
    _ExploreRankingContext context, {
    int limit = 10,
    String debugLabel = 'explore',
  }) {
    final candidatePool = posts.take(40).toList(growable: false);
    final normalizedCity = context.userCity.trim().toLowerCase();
    final normalizedState = context.userState.trim().toLowerCase();
    final rankedEntries = <_RankedExplorePost>[];
    final authorCounts = <String, int>{};

    for (final post in candidatePool) {
      final authorCity = post.authorCity.trim().toLowerCase();
      final authorState = post.authorState.trim().toLowerCase();
      final ageHours = _ageHoursFor(post.createdAtEpoch);
      final baseScore =
          (post.likeCount * 1.0) +
          (post.commentCount * 2.0) +
          post.recentEngagementScore;
      final freshnessFactor = _freshnessFactorFor(post.createdAtEpoch);

      var finalScore = baseScore * freshnessFactor;
      var recencyBoost = 0.0;
      var diversityPenaltyApplied = false;

      if (context.followingIds.contains(post.authorId)) {
        finalScore += 20;
      }
      if (normalizedCity.isNotEmpty && authorCity == normalizedCity) {
        finalScore += 10;
      } else if (normalizedState.isNotEmpty && authorState == normalizedState) {
        finalScore += 5;
      }
      if (ageHours <= 2) {
        recencyBoost += 5;
      }
      if (ageHours <= 1) {
        recencyBoost += 3;
      }
      finalScore += recencyBoost;

      final authorId = post.authorId;
      final authorCount = authorCounts[authorId] ?? 0;
      if (authorCount >= 2) {
        finalScore *= 0.7;
        diversityPenaltyApplied = true;
      }
      authorCounts[authorId] = authorCount + 1;

      rankedEntries.add(
        _RankedExplorePost(
          post: post,
          finalScore: finalScore,
          baseScore: baseScore,
          freshnessFactor: freshnessFactor,
          recencyBoost: recencyBoost,
          diversityPenaltyApplied: diversityPenaltyApplied,
        ),
      );
    }

    rankedEntries.sort((a, b) {
      final scoreCompare = b.finalScore.compareTo(a.finalScore);
      if (scoreCompare != 0) return scoreCompare;

      final createdCompare = b.post.createdAtEpoch.compareTo(
        a.post.createdAtEpoch,
      );
      if (createdCompare != 0) return createdCompare;

      return a.post.id.compareTo(b.post.id);
    });
    final selected = rankedEntries.take(limit).toList(growable: false);

    if (_debugExploreRanking) {
      for (final entry in selected.take(5)) {
        debugPrint(
          '[ExploreRanking:$debugLabel] '
          'post=${entry.post.id} '
          'score=${entry.finalScore.toStringAsFixed(2)} '
          'base=${entry.baseScore.toStringAsFixed(2)} '
          'freshness=${entry.freshnessFactor.toStringAsFixed(1)} '
          'recencyBoost=${entry.recencyBoost.toStringAsFixed(1)} '
          'diversityPenalty=${entry.diversityPenaltyApplied} '
          'likes=${entry.post.likeCount} '
          'comments=${entry.post.commentCount} '
          'recent=${entry.post.recentEngagementScore.toStringAsFixed(1)}',
        );
      }
    }

    return selected.map((entry) => entry.post).toList(growable: false);
  }

  double _freshnessFactorFor(int createdAtEpoch) {
    if (createdAtEpoch <= 0) return 0.2;

    final ageHours = _ageHoursFor(createdAtEpoch);

    if (ageHours <= 6) return 1.0;
    if (ageHours <= 24) return 0.8;
    if (ageHours <= 72) return 0.6;
    if (ageHours <= 168) return 0.4;
    return 0.2;
  }

  double _ageHoursFor(int createdAtEpoch) {
    if (createdAtEpoch <= 0) return 9999;
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(createdAtEpoch),
    );
    return age.inMinutes / 60;
  }

  void _appendPrefetchedTrendingPosts() {
    if (_prefetchedTrendingPosts.isEmpty) return;

    setState(() {
      _trendingPosts = <SocialPostModel>[
        ..._trendingPosts,
        ..._prefetchedTrendingPosts,
      ];
      _prefetchedTrendingPosts = const <SocialPostModel>[];
    });
    _saveCache();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final direction = position.userScrollDirection;
    final pixels = position.pixels;
    final delta = pixels - _lastScrollOffset;
    _lastScrollOffset = pixels;

    if (pixels <= _topBarTopResetOffset) {
      _scrollDeltaAccumulator = 0;
      if (!_isSearchBarVisible && mounted) {
        setState(() => _isSearchBarVisible = true);
      }
    } else if (direction == ScrollDirection.reverse && delta > 0) {
      _scrollDeltaAccumulator = (_scrollDeltaAccumulator + delta).clamp(
        0.0,
        _topBarHideThreshold,
      );
      if (_isSearchBarVisible &&
          _scrollDeltaAccumulator >= _topBarHideThreshold &&
          mounted) {
        _scrollDeltaAccumulator = 0;
        setState(() => _isSearchBarVisible = false);
      }
    } else if (direction == ScrollDirection.forward && delta < 0) {
      _scrollDeltaAccumulator = (_scrollDeltaAccumulator + delta).clamp(
        -_topBarShowThreshold,
        0.0,
      );
      if (!_isSearchBarVisible &&
          _scrollDeltaAccumulator <= -_topBarShowThreshold &&
          mounted) {
        _scrollDeltaAccumulator = 0;
        setState(() => _isSearchBarVisible = true);
      }
    } else if (direction == ScrollDirection.idle) {
      _scrollDeltaAccumulator = 0;
    }
  }

  void _handleSearchChanged() {
    final nextQuery = _searchController.text.trim();
    if (nextQuery == _searchQuery) return;

    setState(() {
      _searchQuery = nextQuery;
      _searchError = null;
      if (nextQuery.isEmpty) {
        _profileResults = const <UserProfile>[];
        _hashtagSuggestions = const <ExploreHashtagSummary>[];
        _hashtagResults = const <SocialPostModel>[];
        _isSearching = false;
      }
    });

    _searchDebounce?.cancel();
    if (nextQuery.isEmpty) return;

    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _runSearch(nextQuery);
    });
  }

  Future<void> _runSearch(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final currentUserId = _currentUserId;
      final hashtagFuture = _socialPostRepository.searchHashtags(
        query,
        limit: 8,
      );

      if (query.startsWith('#')) {
        final results = await Future.wait<dynamic>([
          hashtagFuture,
          _socialPostRepository.searchPostsByHashtag(query, limit: 12),
        ]);

        if (!mounted || query != _searchQuery.trim()) return;
        setState(() {
          _profileResults = const <UserProfile>[];
          _hashtagSuggestions = results[0] as List<ExploreHashtagSummary>;
          _hashtagResults = results[1] as List<SocialPostModel>;
        });
      } else {
        final results = await Future.wait<dynamic>([
          _profileRepository.searchProfiles(
            query,
            excludeUserId: currentUserId,
            limit: 10,
          ),
          hashtagFuture,
        ]);

        final profiles = results[0] as List<UserProfile>;
        final hashtagSuggestions = results[1] as List<ExploreHashtagSummary>;
        List<SocialPostModel> hashtagPosts = const <SocialPostModel>[];
        if (hashtagSuggestions.isNotEmpty) {
          final exactTag = _findBestHashtagMatch(hashtagSuggestions, query);
          hashtagPosts = await _socialPostRepository.fetchPostsByIds(
            exactTag.recentPostIds,
            limit: 6,
          );
        }

        if (!mounted || query != _searchQuery.trim()) return;
        setState(() {
          _profileResults = profiles;
          _hashtagSuggestions = hashtagSuggestions;
          _hashtagResults = hashtagPosts;
        });
      }
    } catch (error) {
      if (!mounted || query != _searchQuery.trim()) return;
      setState(() {
        _searchError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted && query == _searchQuery.trim()) {
        setState(() => _isSearching = false);
      }
    }
  }

  ExploreHashtagSummary _findBestHashtagMatch(
    List<ExploreHashtagSummary> hashtags,
    String query,
  ) {
    final normalized = _socialPostRepository.normalizeHashtag(query);
    for (final hashtag in hashtags) {
      if (hashtag.tag == normalized) {
        return hashtag;
      }
    }
    return hashtags.first;
  }

  void _applyHashtagSearch(String tag) {
    final normalized = _socialPostRepository.normalizeHashtag(tag);
    if (normalized.isEmpty) return;

    _searchController.value = TextEditingValue(
      text: '#$normalized',
      selection: TextSelection.collapsed(offset: normalized.length + 1),
    );
    _searchFocusNode.requestFocus();
    _searchDebounce?.cancel();
    _runSearch('#$normalized');
  }

  void _openProfile(UserProfile profile) {
    final userId = profile.uid.trim();
    if (userId.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => userId == _currentUserId
            ? const ProfileScreen()
            : ProfileScreen(userId: userId),
      ),
    );
  }

  Future<void> _openPostDetail(SocialPostModel post) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
            child: SingleChildScrollView(
              child: SocialPostCard(
                post: post,
                currentUserId: _currentUserId,
                initiallyLiked: false,
                initiallyFollowing: _followingIds.contains(post.authorId),
                repository: _socialPostRepository,
                followRepository: _followRepository,
                onFollowChanged: (authorId, isFollowing) {
                  setState(() {
                    if (isFollowing) {
                      _followingIds.add(authorId);
                    } else {
                      _followingIds.remove(authorId);
                    }
                  });
                  _saveCache();
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _followProfile(UserProfile profile) async {
    final userId = profile.uid.trim();
    if (userId.isEmpty || userId == _currentUserId) return;

    try {
      final isFollowing = await _followRepository.toggleFollow(
        followerId: _currentUserId,
        followeeId: userId,
        currentlyFollowing: _followingIds.contains(userId),
      );
      if (!mounted) return;
      setState(() {
        if (isFollowing) {
          _followingIds.add(userId);
        } else {
          _followingIds.remove(userId);
        }
      });
      _saveCache();
      AppFeedback.show(
        context,
        message: isFollowing ? 'Followed user.' : 'Unfollowed user.',
        tone: AppFeedbackTone.success,
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: error.toString().replaceFirst('Exception: ', ''),
        tone: AppFeedbackTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    const headerHeight = 72.0;

    return SocialTabBackScope(
      activeTab: SocialAppTab.explore,
      child: Scaffold(
        backgroundColor: AppColors.background,
        extendBody: true,
        body: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _refreshExploreSections,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  final metrics = notification.metrics;
                  if (_isSearchMode ||
                      _prefetchedTrendingPosts.isEmpty ||
                      metrics.axis != Axis.vertical ||
                      metrics.maxScrollExtent <= 0) {
                    return false;
                  }

                  if (metrics.pixels >= metrics.maxScrollExtent - 320) {
                    _appendPrefetchedTrendingPosts();
                  }
                  return false;
                },
                child: CustomScrollView(
                  controller: _scrollController,
                  cacheExtent: 1200,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          topInset + headerHeight,
                          16,
                          SocialBottomNav.contentBottomPadding(context),
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: _isSearchMode
                              ? KeyedSubtree(
                                  key: const ValueKey<String>('search'),
                                  child: _buildSearchContent(),
                                )
                              : KeyedSubtree(
                                  key: const ValueKey<String>('discovery'),
                                  child: _buildDiscoveryContent(),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                ignoring: true,
                child: GlassSurface(
                  padding: EdgeInsets.only(top: topInset),
                  borderRadius: BorderRadius.zero,
                  backgroundColor: AppColors.background.withValues(alpha: 0.72),
                  blurSigma: 24,
                  border: Border.all(color: Colors.transparent, width: 0),
                  boxShadow: const [],
                  child: const SizedBox(height: 4),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: ClipRect(
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topCenter,
                  heightFactor: _isSearchBarVisible ? 1 : 0,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOutCubic,
                    offset: _isSearchBarVisible
                        ? Offset.zero
                        : const Offset(0, -0.22),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeInOutCubic,
                      opacity: _isSearchBarVisible ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !_isSearchBarVisible,
                        child: GlassSurface(
                          padding: EdgeInsets.fromLTRB(16, topInset + 4, 16, 8),
                          borderRadius: BorderRadius.zero,
                          backgroundColor: Colors.white.withValues(alpha: 0.58),
                          blurSigma: 22,
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.white.withValues(alpha: 0.45),
                            ),
                          ),
                          child: _SearchBar(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            isSearching: _isSearching,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: const SocialBottomNav(
          activeTab: SocialAppTab.explore,
        ),
      ),
    );
  }

  Widget _buildDiscoveryContent() {
    final discoverPosts = _popularPosts.isNotEmpty
        ? _popularPosts
        : _trendingPosts;

    if (_isLoadingSections) {
      return const _ExploreLoadingState();
    }

    if (_sectionsError != null) {
      return _ExploreErrorState(
        message: _sectionsError!,
        onRetry: _refreshExploreSections,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_trendingHashtags.isNotEmpty) ...[
          _FadeInSection(
            child: _HashtagSection(
              title: 'Trending tags',
              hashtags: _trendingHashtags,
              onTapHashtag: _applyHashtagSearch,
            ),
          ),
          const SizedBox(height: 10),
        ],
        _FadeInSection(
          delay: const Duration(milliseconds: 40),
          child: _DiscoverSection(
            title: 'Discover',
            posts: discoverPosts,
            onOpenPost: _openPostDetail,
          ),
        ),
        if (discoverPosts.isEmpty && _trendingHashtags.isEmpty)
          const _ExploreEmptyState(
            title: 'Nothing to explore yet',
            message:
                'Follow more pet parents and try again later. Trending posts and hashtags will show up here as Pettxo activity grows.',
          ),
      ],
    );
  }

  Widget _buildSearchContent() {
    if (_isSearching) {
      return const _SearchLoadingState();
    }

    if (_searchError != null) {
      return _ExploreErrorState(
        message: _searchError!,
        onRetry: () => _runSearch(_searchQuery),
      );
    }

    if (_profileResults.isEmpty &&
        _hashtagSuggestions.isEmpty &&
        _hashtagResults.isEmpty) {
      return _ExploreEmptyState(
        title: 'No results found',
        message: _searchQuery.startsWith('#')
            ? 'Try another hashtag or remove the # to search for people and profiles.'
            : 'Try another username or hashtag like #pettxo. Following more people also improves what Explore can suggest.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_profileResults.isNotEmpty) ...[
          _ResultSectionTitle(
            title: 'Profiles',
            subtitle: 'People matching "${_searchQuery.trim()}".',
          ),
          const SizedBox(height: 12),
          ..._profileResults.map((profile) {
            final isCurrentUser = profile.uid == _currentUserId;
            final isFollowing = _followingIds.contains(profile.uid);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ProfileResultCard(
                profile: profile,
                isCurrentUser: isCurrentUser,
                isFollowing: isFollowing,
                onTap: () => _openProfile(profile),
                onFollow: isCurrentUser ? null : () => _followProfile(profile),
              ),
            );
          }),
        ],
        if (_hashtagSuggestions.isNotEmpty) ...[
          if (_profileResults.isNotEmpty) const SizedBox(height: 10),
          _ResultSectionTitle(
            title: 'Hashtags',
            subtitle: _searchQuery.startsWith('#')
                ? 'Tags matching ${_searchQuery.trim()}.'
                : 'Suggested tags related to your search.',
          ),
          const SizedBox(height: 12),
          _HashtagSuggestionWrap(
            hashtags: _hashtagSuggestions,
            onTapHashtag: _applyHashtagSearch,
          ),
        ],
        if (_hashtagResults.isNotEmpty) ...[
          if (_profileResults.isNotEmpty || _hashtagSuggestions.isNotEmpty)
            const SizedBox(height: 18),
          _ResultSectionTitle(
            title: 'Hashtag Posts',
            subtitle: _searchQuery.startsWith('#')
                ? 'Posts matching ${_searchQuery.trim()}.'
                : 'Recent posts linked to related hashtags.',
          ),
          const SizedBox(height: 12),
          ..._hashtagResults.map((post) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SearchPostCard(
                post: post,
                onTap: () => _openPostDetail(post),
              ),
            );
          }),
        ],
      ],
    );
  }
}

class _ExploreCache {
  final UserProfile? viewerProfile;
  final List<SocialPostModel> recentPosts;
  final List<SocialPostModel> trendingPosts;
  final List<SocialPostModel> prefetchedTrendingPosts;
  final List<SocialPostModel> popularPosts;
  final List<SocialPostModel> prefetchedPopularPosts;
  final List<ExploreHashtagSummary> trendingHashtags;
  final Set<String> followingIds;

  const _ExploreCache({
    required this.viewerProfile,
    required this.recentPosts,
    required this.trendingPosts,
    required this.prefetchedTrendingPosts,
    required this.popularPosts,
    required this.prefetchedPopularPosts,
    required this.trendingHashtags,
    required this.followingIds,
  });

  bool get hasDiscoveryData =>
      trendingPosts.isNotEmpty ||
      popularPosts.isNotEmpty ||
      trendingHashtags.isNotEmpty;
}

class _ExploreRankingContext {
  final Set<String> followingIds;
  final String userCity;
  final String userState;

  const _ExploreRankingContext({
    required this.followingIds,
    required this.userCity,
    required this.userState,
  });
}

class _RankedExplorePost {
  final SocialPostModel post;
  final double finalScore;
  final double baseScore;
  final double freshnessFactor;
  final double recencyBoost;
  final bool diversityPenaltyApplied;

  const _RankedExplorePost({
    required this.post,
    required this.finalScore,
    required this.baseScore,
    required this.freshnessFactor,
    required this.recencyBoost,
    required this.diversityPenaltyApplied,
  });
}

class _FadeInSection extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const _FadeInSection({required this.child, this.delay = Duration.zero});

  @override
  State<_FadeInSection> createState() => _FadeInSectionState();
}

class _FadeInSectionState extends State<_FadeInSection> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) {
        setState(() => _visible = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      opacity: _visible ? 1 : 0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        offset: _visible ? Offset.zero : const Offset(0, 0.03),
        child: widget.child,
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSearching;

  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.isSearching,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: AppColors.textGrey),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search profiles or hashtags like #pettxo',
                border: InputBorder.none,
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: isSearching
                ? const SizedBox(
                    key: ValueKey<String>('loader'),
                    width: 22,
                    height: 22,
                    child: Padding(
                      padding: EdgeInsets.all(2),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : controller.text.trim().isNotEmpty
                ? IconButton(
                    key: const ValueKey<String>('clear'),
                    onPressed: controller.clear,
                    icon: const Icon(Icons.close_rounded),
                  )
                : const SizedBox.shrink(key: ValueKey<String>('empty')),
          ),
        ],
      ),
    );
  }
}

class _ResultSectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _ResultSectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppColors.textGrey,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _HashtagSection extends StatelessWidget {
  final String title;
  final List<ExploreHashtagSummary> hashtags;
  final ValueChanged<String> onTapHashtag;

  const _HashtagSection({
    required this.title,
    required this.hashtags,
    required this.onTapHashtag,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ListView.separated(
            cacheExtent: 420,
            scrollDirection: Axis.horizontal,
            itemCount: hashtags.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final hashtag = hashtags[index];
              return _HashtagPill(
                label: '#${hashtag.tag}',
                onTap: () => onTapHashtag(hashtag.tag),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HashtagSuggestionWrap extends StatelessWidget {
  final List<ExploreHashtagSummary> hashtags;
  final ValueChanged<String> onTapHashtag;

  const _HashtagSuggestionWrap({
    required this.hashtags,
    required this.onTapHashtag,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: hashtags
          .map((hashtag) {
            return _HashtagPill(
              label: '#${hashtag.tag}',
              onTap: () => onTapHashtag(hashtag.tag),
            );
          })
          .toList(growable: false),
    );
  }
}

class _HashtagPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _HashtagPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscoverSection extends StatelessWidget {
  final String title;
  final List<SocialPostModel> posts;
  final ValueChanged<SocialPostModel> onOpenPost;

  const _DiscoverSection({
    required this.title,
    required this.posts,
    required this.onOpenPost,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 14),
        if (posts.isEmpty)
          const _InlineEmptyState(message: 'No posts available right now.')
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 292,
            ),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];
              return _CompactPostCard(
                post: post,
                onTap: () => onOpenPost(post),
                expandToAvailableWidth: true,
                showUsername: false,
                showShareStat: false,
                imageHeightOverride: 196,
              );
            },
          ),
      ],
    );
  }
}

class _ProfileResultCard extends StatelessWidget {
  final UserProfile profile;
  final bool isCurrentUser;
  final bool isFollowing;
  final VoidCallback onTap;
  final VoidCallback? onFollow;

  const _ProfileResultCard({
    required this.profile,
    required this.isCurrentUser,
    required this.isFollowing,
    required this.onTap,
    this.onFollow,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              _ProfileAvatar(
                imageUrl: profile.profileImageUrl,
                initials: profile.initials,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name.isEmpty ? 'Pettxo user' : profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.displayUsername.isEmpty
                          ? '@username'
                          : profile.displayUsername,
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isCurrentUser)
                FilledButton(
                  onPressed: onFollow,
                  style: FilledButton.styleFrom(
                    backgroundColor: isFollowing
                        ? AppColors.textGrey
                        : AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  child: Text(isFollowing ? 'Following' : 'Follow'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchPostCard extends StatelessWidget {
  final SocialPostModel post;
  final VoidCallback onTap;

  const _SearchPostCard({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return LiveAuthorResolver(
      authorId: post.authorId,
      fallbackName: post.authorDisplayName,
      fallbackUsername: post.authorUsername,
      fallbackImageUrl: post.authorPhotoUrl,
      builder: (context, author) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.08),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: 90,
                      height: 90,
                      child: _RemoteImage(
                        url: post.thumbnailUrls.isNotEmpty
                            ? post.thumbnailUrls.first
                            : (post.imageUrls.isNotEmpty
                                  ? post.imageUrls.first
                                  : ''),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          author.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textDark,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          author.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textGrey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          post.caption.isEmpty
                              ? post.hashtags.map((tag) => '#$tag').join(' ')
                              : post.caption,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textDark,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CompactPostCard extends StatelessWidget {
  final SocialPostModel post;
  final VoidCallback onTap;
  final bool expandToAvailableWidth;
  final bool showUsername;
  final bool showShareStat;
  final double? imageHeightOverride;

  const _CompactPostCard({
    required this.post,
    required this.onTap,
    this.expandToAvailableWidth = false,
    this.showUsername = true,
    this.showShareStat = true,
    this.imageHeightOverride,
  });

  @override
  Widget build(BuildContext context) {
    final previewText = post.caption.trim().isEmpty
        ? post.hashtags.map((tag) => '#$tag').join(' ')
        : post.caption.trim();

    return LiveAuthorResolver(
      authorId: post.authorId,
      fallbackName: post.authorDisplayName,
      fallbackUsername: post.authorUsername,
      fallbackImageUrl: post.authorPhotoUrl,
      builder: (context, author) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isHorizontalSectionCard = !expandToAvailableWidth;
            final compact = constraints.maxWidth < 190;
            final imageHeight =
                imageHeightOverride ??
                (isHorizontalSectionCard
                    ? (compact ? 150.0 : 168.0)
                    : (compact ? 104.0 : 122.0));

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  width: expandToAvailableWidth ? double.infinity : 220,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.045),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(22),
                        ),
                        child: SizedBox(
                          height: imageHeight,
                          width: double.infinity,
                          child: _RemoteImage(
                            url: post.thumbnailUrls.isNotEmpty
                                ? post.thumbnailUrls.first
                                : (post.imageUrls.isNotEmpty
                                      ? post.imageUrls.first
                                      : ''),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 14 : 18,
                          14,
                          compact ? 14 : 18,
                          8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              author.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textDark,
                                fontSize: compact ? 15 : 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (!isHorizontalSectionCard && showUsername) ...[
                              const SizedBox(height: 4),
                              Text(
                                author.username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.textGrey,
                                  fontSize: compact ? 12 : 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              previewText.isEmpty
                                  ? 'Tap to open post.'
                                  : previewText,
                              maxLines: isHorizontalSectionCard
                                  ? (compact ? 2 : 3)
                                  : (compact ? 1 : 2),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textDark,
                                fontSize: compact ? 13 : 14,
                                height: 1.28,
                              ),
                            ),
                            if (!isHorizontalSectionCard) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _StatChip(
                                    icon: Icons.favorite_border_rounded,
                                    value: '${post.likeCount}',
                                    compact: compact,
                                    minimal: !showShareStat,
                                  ),
                                  const SizedBox(width: 12),
                                  _StatChip(
                                    icon: Icons.mode_comment_outlined,
                                    value: '${post.commentCount}',
                                    compact: compact,
                                    minimal: !showShareStat,
                                  ),
                                  if (showShareStat) ...[
                                    const SizedBox(width: 12),
                                    _StatChip(
                                      icon: Icons.share_outlined,
                                      value: '${post.shareCount}',
                                      compact: compact,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String imageUrl;
  final String initials;

  const _ProfileAvatar({required this.imageUrl, required this.initials});

  @override
  Widget build(BuildContext context) {
    return AppUserAvatar(
      size: 52,
      imageUrl: imageUrl,
      fallback: _fallbackAvatar(),
    );
  }

  Widget _fallbackAvatar() {
    return AppUserAvatarFallback(
      initials: initials,
      backgroundColor: AppColors.background,
      textStyle: const TextStyle(
        color: AppColors.textDark,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _RemoteImage extends StatelessWidget {
  final String url;
  final BoxFit fit;

  const _RemoteImage({required this.url, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const ColoredBox(
        color: Color(0xFFFFF2EA),
        child: Center(
          child: Icon(
            Icons.image_outlined,
            color: AppColors.textGrey,
            size: 36,
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFFFCF8F5),
      child: CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        errorWidget: (_, _, _) => const Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            color: AppColors.textGrey,
            size: 34,
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final bool compact;
  final bool minimal;

  const _StatChip({
    required this.icon,
    required this.value,
    this.compact = false,
    this.minimal = false,
  });

  @override
  Widget build(BuildContext context) {
    if (minimal) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 17 : 18, color: AppColors.textGrey),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              color: AppColors.textGrey,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 14 : 16, color: AppColors.textDark),
          SizedBox(width: compact ? 4 : 6),
          Text(
            value,
            style: TextStyle(
              color: AppColors.textDark,
              fontSize: compact ? 12 : 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExploreLoadingState extends StatelessWidget {
  const _ExploreLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _ExploreSkeletonSection(
          titleWidth: 190,
          subtitleWidth: 250,
          cardCount: 3,
          cardHeight: 286,
        ),
        SizedBox(height: 18),
        _ExploreSkeletonSection(
          titleWidth: 170,
          subtitleWidth: 230,
          cardCount: 3,
          cardHeight: 286,
        ),
        SizedBox(height: 18),
        _ExploreSkeletonSection(
          titleWidth: 220,
          subtitleWidth: 260,
          cardCount: 3,
          cardHeight: 312,
        ),
      ],
    );
  }
}

class _SearchLoadingState extends StatelessWidget {
  const _SearchLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _ProfileSkeletonCard(),
        SizedBox(height: 12),
        _ProfileSkeletonCard(),
        SizedBox(height: 18),
        _HashtagSkeletonWrap(),
        SizedBox(height: 18),
        _SearchPostSkeletonCard(),
      ],
    );
  }
}

class _ExploreSkeletonSection extends StatelessWidget {
  final double titleWidth;
  final double subtitleWidth;
  final int cardCount;
  final double cardHeight;

  const _ExploreSkeletonSection({
    required this.titleWidth,
    required this.subtitleWidth,
    required this.cardCount,
    required this.cardHeight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBox(width: titleWidth, height: 28),
          const SizedBox(height: 10),
          _SkeletonBox(width: subtitleWidth, height: 16),
          const SizedBox(height: 16),
          SizedBox(
            height: cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cardCount,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, _) =>
                  SizedBox(width: 220, child: const _CompactCardSkeleton()),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactCardSkeleton extends StatelessWidget {
  const _CompactCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF8),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          ClipRRect(
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            child: _SkeletonBox(width: double.infinity, height: 122),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBox(width: 120, height: 18),
                SizedBox(height: 8),
                _SkeletonBox(width: 84, height: 14),
                SizedBox(height: 10),
                _SkeletonBox(width: 172, height: 14),
                SizedBox(height: 6),
                _SkeletonBox(width: 138, height: 14),
                SizedBox(height: 12),
                Row(
                  children: [
                    _SkeletonBox(width: 48, height: 30),
                    SizedBox(width: 8),
                    _SkeletonBox(width: 48, height: 30),
                    SizedBox(width: 8),
                    _SkeletonBox(width: 48, height: 30),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSkeletonCard extends StatelessWidget {
  const _ProfileSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: const Row(
        children: [
          _SkeletonCircle(size: 52),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBox(width: 130, height: 18),
                SizedBox(height: 8),
                _SkeletonBox(width: 90, height: 14),
              ],
            ),
          ),
          _SkeletonBox(width: 86, height: 40),
        ],
      ),
    );
  }
}

class _HashtagSkeletonWrap extends StatelessWidget {
  const _HashtagSkeletonWrap();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _SkeletonBox(width: 112, height: 48, radius: 999),
        _SkeletonBox(width: 124, height: 48, radius: 999),
        _SkeletonBox(width: 108, height: 48, radius: 999),
      ],
    );
  }
}

class _SearchPostSkeletonCard extends StatelessWidget {
  const _SearchPostSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBox(width: 90, height: 90, radius: 18),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBox(width: 120, height: 16),
                SizedBox(height: 8),
                _SkeletonBox(width: 84, height: 14),
                SizedBox(height: 10),
                _SkeletonBox(width: 210, height: 14),
                SizedBox(height: 6),
                _SkeletonBox(width: 170, height: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonCircle extends StatelessWidget {
  final double size;

  const _SkeletonCircle({required this.size});

  @override
  Widget build(BuildContext context) {
    return _SkeletonBox(width: size, height: size, radius: size / 2);
  }
}

class _SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _SkeletonBox({
    required this.width,
    required this.height,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.72, end: 1),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeInOut,
      builder: (context, value, _) {
        return Opacity(
          opacity: 0.72 + ((value - 0.72) * 0.25),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: const Color(0xFFF2ECE6),
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
        );
      },
      onEnd: () {},
    );
  }
}

class _ExploreErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ExploreErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.explore_off_rounded,
            size: 38,
            color: AppColors.textGrey,
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textGrey,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _ExploreEmptyState extends StatelessWidget {
  final String title;
  final String message;

  const _ExploreEmptyState({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.travel_explore_rounded,
            size: 40,
            color: AppColors.primary,
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textGrey,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  final String message;

  const _InlineEmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Text(
        message,
        style: const TextStyle(
          color: AppColors.textGrey,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
