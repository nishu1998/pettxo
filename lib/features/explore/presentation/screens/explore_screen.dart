import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/navigation/social_app_tab.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../profile/presentation/screens/service_detail_screen.dart';
import '../../../services/data/repositories/services_repository.dart';
import '../../../services/domain/models/service_model.dart';
import '../../../social/data/follow_repository.dart';
import '../../../social/data/social_post_repository.dart';
import '../../../social/domain/models/social_post_model.dart';
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
  final ServicesRepository _servicesRepository = ServicesRepository();
  final FollowRepository _followRepository = FollowRepository();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  Timer? _searchDebounce;
  bool _isLoadingSections = true;
  bool _isSearching = false;
  String? _sectionsError;
  String? _searchError;
  String _searchQuery = '';

  UserProfile? _viewerProfile;
  List<SocialPostModel> _recentPostsCache = const <SocialPostModel>[];
  List<SocialPostModel> _trendingPosts = const <SocialPostModel>[];
  List<SocialPostModel> _prefetchedTrendingPosts = const <SocialPostModel>[];
  List<SocialPostModel> _popularPosts = const <SocialPostModel>[];
  List<SocialPostModel> _prefetchedPopularPosts = const <SocialPostModel>[];
  List<ServiceModel> _nearbyServices = const <ServiceModel>[];
  List<ExploreHashtagSummary> _trendingHashtags =
      const <ExploreHashtagSummary>[];
  List<UserProfile> _profileResults = const <UserProfile>[];
  List<ExploreHashtagSummary> _hashtagSuggestions =
      const <ExploreHashtagSummary>[];
  List<SocialPostModel> _hashtagResults = const <SocialPostModel>[];
  Set<String> _followingIds = <String>{};

  String get _currentUserId => _auth.currentUser?.uid.trim() ?? '';
  bool get _isSearchMode => _searchQuery.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
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
    _nearbyServices = cache.nearbyServices;
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
      nearbyServices: List<ServiceModel>.from(_nearbyServices),
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
      final nearbyServices = await _loadNearbyServices(currentProfile);
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
        _nearbyServices = nearbyServices;
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
        final nearbyServices = await _loadNearbyServices(currentProfile);
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
          _nearbyServices = nearbyServices;
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

  Future<List<ServiceModel>> _loadNearbyServices(UserProfile? profile) async {
    try {
      final city = profile?.city.trim() ?? '';
      final page = await _servicesRepository.fetchActiveServicesPage(
        limit: 20,
        city: city.isEmpty ? null : city,
      );

      final state = profile?.state.trim().toLowerCase() ?? '';
      final ranked = page.services.toList(growable: false)
        ..sort((a, b) {
          final aSameCity =
              city.isNotEmpty &&
              a.city.trim().toLowerCase() == city.toLowerCase();
          final bSameCity =
              city.isNotEmpty &&
              b.city.trim().toLowerCase() == city.toLowerCase();
          if (aSameCity != bSameCity) return aSameCity ? -1 : 1;

          final aSameState =
              state.isNotEmpty && a.state.trim().toLowerCase() == state;
          final bSameState =
              state.isNotEmpty && b.state.trim().toLowerCase() == state;
          if (aSameState != bSameState) return aSameState ? -1 : 1;

          final ratingCompare = b.ratingAverage.compareTo(a.ratingAverage);
          if (ratingCompare != 0) return ratingCompare;

          final completedCompare = b.completedBookingCount.compareTo(
            a.completedBookingCount,
          );
          if (completedCompare != 0) return completedCompare;

          return b.trustScore.compareTo(a.trustScore);
        });

      return ranked.take(10).toList(growable: false);
    } catch (_) {
      // TODO(nishant): Promote nearby service ranking to geo-aware queries once
      // the service location index and user city accuracy are production-ready.
      return const <ServiceModel>[];
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

  void _appendPrefetchedPopularPosts() {
    if (_prefetchedPopularPosts.isEmpty) return;

    setState(() {
      _popularPosts = <SocialPostModel>[
        ..._popularPosts,
        ..._prefetchedPopularPosts,
      ];
      _prefetchedPopularPosts = const <SocialPostModel>[];
    });
    _saveCache();
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

  void _openPostSeeAll({
    required String title,
    required String subtitle,
    required List<SocialPostModel> posts,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ExploreListScreen(
          title: title,
          subtitle: subtitle,
          postItems: posts,
          currentUserId: _currentUserId,
          followingIds: _followingIds,
          onOpenPost: _openPostDetail,
        ),
      ),
    );
  }

  void _openServiceSeeAll() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ExploreListScreen(
          title: 'Popular Services Nearby',
          subtitle:
              'Strong local options ranked by trust, reviews, and demand.',
          serviceItems: _nearbyServices,
          onOpenService: _openService,
        ),
      ),
    );
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

  void _openService(ServiceModel service) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ServiceDetailScreen(service: service.toProfileListing()),
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
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: RefreshIndicator(
        onRefresh: _refreshExploreSections,
        child: CustomScrollView(
          cacheExtent: 1200,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              toolbarHeight: 92,
              automaticallyImplyLeading: false,
              flexibleSpace: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: GlassSurface(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    backgroundColor: Colors.white.withValues(alpha: 0.72),
                    blurSigma: 20,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.62),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.56),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: IconButton(
                            onPressed: () => Navigator.pushReplacementNamed(
                              context,
                              '/home',
                            ),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Explore',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedSearchHeaderDelegate(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: _SearchBar(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    isSearching: _isSearching,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
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
      bottomNavigationBar: const SocialBottomNav(
        activeTab: SocialAppTab.explore,
      ),
    );
  }

  Widget _buildDiscoveryContent() {
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
              title: 'Trending Hashtags',
              subtitle: 'Topics pet parents are using right now.',
              hashtags: _trendingHashtags,
              onTapHashtag: _applyHashtagSearch,
            ),
          ),
          const SizedBox(height: 18),
        ],
        _FadeInSection(
          delay: const Duration(milliseconds: 40),
          child: _PostSection(
            title: 'Trending Posts',
            subtitle: 'Fresh conversations getting attention right now.',
            posts: _trendingPosts,
            onOpenPost: _openPostDetail,
            onReachedEnd: _prefetchedTrendingPosts.isNotEmpty
                ? _appendPrefetchedTrendingPosts
                : null,
            onSeeAll: _trendingPosts.isNotEmpty
                ? () => _openPostSeeAll(
                    title: 'Trending Posts',
                    subtitle:
                        'Fresh conversations getting attention right now.',
                    posts: _trendingPosts,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 18),
        _FadeInSection(
          delay: const Duration(milliseconds: 80),
          child: _PostSection(
            title: 'Popular Posts',
            subtitle: 'Community favorites based on likes and conversation.',
            posts: _popularPosts,
            onOpenPost: _openPostDetail,
            onReachedEnd: _prefetchedPopularPosts.isNotEmpty
                ? _appendPrefetchedPopularPosts
                : null,
            onSeeAll: _popularPosts.isNotEmpty
                ? () => _openPostSeeAll(
                    title: 'Popular Posts',
                    subtitle:
                        'Community favorites based on likes and conversation.',
                    posts: _popularPosts,
                  )
                : null,
          ),
        ),
        if (_nearbyServices.isNotEmpty) ...[
          const SizedBox(height: 18),
          _FadeInSection(
            delay: const Duration(milliseconds: 120),
            child: _ServiceSection(
              title: 'Popular Services Nearby',
              subtitle:
                  'Strong local options ranked by trust, reviews, and demand.',
              services: _nearbyServices,
              onOpenService: _openService,
              onSeeAll: _nearbyServices.isNotEmpty ? _openServiceSeeAll : null,
            ),
          ),
        ],
        if (_trendingPosts.isEmpty &&
            _popularPosts.isEmpty &&
            _nearbyServices.isEmpty)
          const _ExploreEmptyState(
            title: 'Nothing to explore yet',
            message:
                'Follow more pet parents and try again later. Trending posts, nearby services, and hashtags will show up here as Pettxo activity grows.',
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
  final List<ServiceModel> nearbyServices;
  final List<ExploreHashtagSummary> trendingHashtags;
  final Set<String> followingIds;

  const _ExploreCache({
    required this.viewerProfile,
    required this.recentPosts,
    required this.trendingPosts,
    required this.prefetchedTrendingPosts,
    required this.popularPosts,
    required this.prefetchedPopularPosts,
    required this.nearbyServices,
    required this.trendingHashtags,
    required this.followingIds,
  });

  bool get hasDiscoveryData =>
      trendingPosts.isNotEmpty ||
      popularPosts.isNotEmpty ||
      nearbyServices.isNotEmpty ||
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

class _PinnedSearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  const _PinnedSearchHeaderDelegate({required this.child});

  @override
  double get minExtent => 76;

  @override
  double get maxExtent => 76;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(color: AppColors.background, child: child);
  }

  @override
  bool shouldRebuild(covariant _PinnedSearchHeaderDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
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

class _ExploreListScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<SocialPostModel> postItems;
  final List<ServiceModel> serviceItems;
  final String currentUserId;
  final Set<String> followingIds;
  final ValueChanged<SocialPostModel>? onOpenPost;
  final ValueChanged<ServiceModel>? onOpenService;

  const _ExploreListScreen({
    required this.title,
    required this.subtitle,
    this.postItems = const <SocialPostModel>[],
    this.serviceItems = const <ServiceModel>[],
    this.currentUserId = '',
    this.followingIds = const <String>{},
    this.onOpenPost,
    this.onOpenService,
  });

  bool get _showsPosts => postItems.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final items = _showsPosts ? postItems.length : serviceItems.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppColors.textDark,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textGrey,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: items == 0
                  ? const _ExploreEmptyState(
                      title: 'Nothing here yet',
                      message:
                          'This section will fill up as more posts and services become available.',
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final maxCrossAxisExtent = constraints.maxWidth < 420
                            ? 220.0
                            : 240.0;
                        final mainAxisExtent = _showsPosts ? 292.0 : 318.0;

                        return GridView.builder(
                          cacheExtent: 900,
                          gridDelegate:
                              SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: maxCrossAxisExtent,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                mainAxisExtent: mainAxisExtent,
                              ),
                          itemCount: items,
                          itemBuilder: (context, index) {
                            if (_showsPosts) {
                              final post = postItems[index];
                              return _CompactPostCard(
                                post: post,
                                onTap: () => onOpenPost?.call(post),
                                expandToAvailableWidth: true,
                              );
                            }

                            final service = serviceItems[index];
                            return _CompactServiceCard(
                              service: service,
                              onTap: () => onOpenService?.call(service),
                              expandToAvailableWidth: true,
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
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
  final String subtitle;
  final List<ExploreHashtagSummary> hashtags;
  final ValueChanged<String> onTapHashtag;

  const _HashtagSection({
    required this.title,
    required this.subtitle,
    required this.hashtags,
    required this.onTapHashtag,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
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
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final pills = hashtags
                  .map(
                    (hashtag) => _HashtagPill(
                      label: '#${hashtag.tag}',
                      countLabel: '${hashtag.postCount} posts',
                      onTap: () => onTapHashtag(hashtag.tag),
                    ),
                  )
                  .toList(growable: false);

              if (constraints.maxWidth < 360) {
                return Wrap(spacing: 10, runSpacing: 10, children: pills);
              }

              return SizedBox(
                height: 60,
                child: ListView.separated(
                  cacheExtent: 360,
                  scrollDirection: Axis.horizontal,
                  itemCount: pills.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) => pills[index],
                ),
              );
            },
          ),
        ],
      ),
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
              countLabel: '${hashtag.postCount} posts',
              onTap: () => onTapHashtag(hashtag.tag),
            );
          })
          .toList(growable: false),
    );
  }
}

class _HashtagPill extends StatelessWidget {
  final String label;
  final String countLabel;
  final VoidCallback onTap;

  const _HashtagPill({
    required this.label,
    required this.countLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF6F0),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.10),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                countLabel,
                maxLines: 1,
                style: const TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<SocialPostModel> posts;
  final ValueChanged<SocialPostModel> onOpenPost;
  final VoidCallback? onReachedEnd;
  final VoidCallback? onSeeAll;

  const _PostSection({
    required this.title,
    required this.subtitle,
    required this.posts,
    required this.onOpenPost,
    this.onReachedEnd,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (onSeeAll != null)
                TextButton(onPressed: onSeeAll, child: const Text('See All')),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          if (posts.isEmpty)
            const _InlineEmptyState(message: 'No posts available right now.')
          else
            SizedBox(
              height: 286,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  final metrics = notification.metrics;
                  if (onReachedEnd == null ||
                      metrics.axis != Axis.horizontal ||
                      metrics.maxScrollExtent <= 0) {
                    return false;
                  }

                  if (metrics.pixels >= metrics.maxScrollExtent - 140) {
                    onReachedEnd?.call();
                  }
                  return false;
                },
                child: ListView.separated(
                  cacheExtent: 600,
                  scrollDirection: Axis.horizontal,
                  itemCount: posts.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    return _CompactPostCard(
                      post: posts[index],
                      onTap: () => onOpenPost(posts[index]),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ServiceSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<ServiceModel> services;
  final ValueChanged<ServiceModel> onOpenService;
  final VoidCallback? onSeeAll;

  const _ServiceSection({
    required this.title,
    required this.subtitle,
    required this.services,
    required this.onOpenService,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (onSeeAll != null)
                TextButton(onPressed: onSeeAll, child: const Text('See All')),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 312,
            child: ListView.separated(
              cacheExtent: 600,
              scrollDirection: Axis.horizontal,
              itemCount: services.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final service = services[index];
                return _CompactServiceCard(
                  service: service,
                  onTap: () => onOpenService(service),
                );
              },
            ),
          ),
        ],
      ),
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
                      post.authorDisplayName.isEmpty
                          ? 'Pettxo user'
                          : post.authorDisplayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      post.authorUsername,
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
  }
}

class _CompactPostCard extends StatelessWidget {
  final SocialPostModel post;
  final VoidCallback onTap;
  final bool expandToAvailableWidth;

  const _CompactPostCard({
    required this.post,
    required this.onTap,
    this.expandToAvailableWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final previewText = post.caption.trim().isEmpty
        ? post.hashtags.map((tag) => '#$tag').join(' ')
        : post.caption.trim();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isHorizontalSectionCard = !expandToAvailableWidth;
        final compact = constraints.maxWidth < 190;
        final imageHeight = isHorizontalSectionCard
            ? (compact ? 150.0 : 168.0)
            : (compact ? 104.0 : 122.0);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              width: expandToAvailableWidth ? double.infinity : 220,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBF8),
                borderRadius: BorderRadius.circular(22),
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
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 10 : 12,
                      10,
                      compact ? 10 : 12,
                      12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.authorDisplayName.isEmpty
                              ? 'Pettxo user'
                              : post.authorDisplayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textDark,
                            fontSize: compact ? 14 : 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (!isHorizontalSectionCard) ...[
                          const SizedBox(height: 4),
                          Text(
                            post.authorUsername,
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
                            height: 1.35,
                          ),
                        ),
                        if (!isHorizontalSectionCard) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _StatChip(
                                icon: Icons.favorite_border_rounded,
                                value: '${post.likeCount}',
                                compact: compact,
                              ),
                              _StatChip(
                                icon: Icons.mode_comment_outlined,
                                value: '${post.commentCount}',
                                compact: compact,
                              ),
                              _StatChip(
                                icon: Icons.share_outlined,
                                value: '${post.shareCount}',
                                compact: compact,
                              ),
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
  }
}

class _CompactServiceCard extends StatelessWidget {
  final ServiceModel service;
  final VoidCallback onTap;
  final bool expandToAvailableWidth;

  const _CompactServiceCard({
    required this.service,
    required this.onTap,
    this.expandToAvailableWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 190;
        final imageHeight = compact ? 104.0 : 122.0;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              width: expandToAvailableWidth ? double.infinity : 220,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBF8),
                borderRadius: BorderRadius.circular(22),
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
                        url: service.primaryPhotoUrl.isNotEmpty
                            ? service.primaryPhotoUrl
                            : (service.photoUrls.isNotEmpty
                                  ? service.photoUrls.first
                                  : ''),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 10 : 12,
                      10,
                      compact ? 10 : 12,
                      12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textDark,
                            fontSize: compact ? 14 : 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          service.ownerName.isEmpty
                              ? 'Pettxo provider'
                              : service.ownerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textGrey,
                            fontSize: compact ? 12 : 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          service.ratingCount > 0
                              ? '⭐ ${service.ratingAverage.toStringAsFixed(1)} · ${service.ratingCount} reviews'
                              : 'New service listing',
                          maxLines: compact ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textDark,
                            fontSize: compact ? 12 : 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          service.displayAddress.isEmpty
                              ? _serviceLocationLabel(service)
                              : service.displayAddress,
                          maxLines: compact ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textGrey,
                            fontSize: compact ? 12 : 12.5,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 8 : 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF2EA),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            '₹${service.pricePerSession}/session',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: compact ? 12 : 13,
                              fontWeight: FontWeight.w700,
                            ),
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

String _serviceLocationLabel(ServiceModel service) {
  final city = service.city.trim();
  final state = service.state.trim();
  if (city.isNotEmpty && state.isNotEmpty) {
    return '$city, $state';
  }
  if (city.isNotEmpty) return city;
  if (state.isNotEmpty) return state;
  return 'Location available on service details';
}

class _ProfileAvatar extends StatelessWidget {
  final String imageUrl;
  final String initials;

  const _ProfileAvatar({required this.imageUrl, required this.initials});

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isNotEmpty) {
      return ClipOval(
        child: SizedBox(
          width: 52,
          height: 52,
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            placeholder: (_, _) => _fallbackAvatar(),
            errorWidget: (_, _, _) => _fallbackAvatar(),
          ),
        ),
      );
    }

    return _fallbackAvatar();
  }

  Widget _fallbackAvatar() {
    return CircleAvatar(
      radius: 26,
      backgroundColor: AppColors.background,
      child: Text(
        initials,
        style: const TextStyle(
          color: AppColors.textDark,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RemoteImage extends StatelessWidget {
  final String url;

  const _RemoteImage({required this.url});

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
        fit: BoxFit.contain,
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

  const _StatChip({
    required this.icon,
    required this.value,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
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
