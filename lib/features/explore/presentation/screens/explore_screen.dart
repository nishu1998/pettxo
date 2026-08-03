import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/navigation/social_app_tab.dart';
import '../../../../core/widgets/app_user_avatar.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../data/explore_feed_repository.dart';
import '../../data/explore_location_repository.dart';
import '../../data/explore_viewer_context_repository.dart';
import '../../domain/models/explore_feed_kind.dart';
import '../../domain/models/explore_feed_viewer_context.dart';
import '../../domain/utils/nearby_error_message.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../social/data/follow_repository.dart';
import '../../../social/data/social_post_repository.dart';
import '../../../social/domain/models/social_post_model.dart';
import '../../../social/presentation/widgets/live_author_resolver.dart';
import '../../../social/presentation/widgets/social_post_card.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  static _ExploreCache? _memoryCache;

  final ExploreFeedRepository _exploreFeedRepository = ExploreFeedRepository();
  final ExploreLocationRepository _exploreLocationRepository =
      ExploreLocationRepository();
  final ExploreViewerContextRepository _viewerContextRepository =
      ExploreViewerContextRepository();
  final SocialPostRepository _socialPostRepository = SocialPostRepository();
  final ProfileRepository _profileRepository = ProfileRepository();
  final FollowRepository _followRepository = FollowRepository();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  Timer? _searchDebounce;
  StreamSubscription<User?>? _authStateSubscription;
  bool _isLoadingSections = true;
  bool _isLoadingMoreDiscoverPosts = false;
  bool _isLoadingNearbyPosts = false;
  bool _isLoadingMoreNearbyPosts = false;
  bool _isSearching = false;
  bool _isSearchBarVisible = true;
  String? _sectionsError;
  String? _nearbyError;
  String? _searchError;
  String _searchQuery = '';
  ExploreFeedKind _activeFeedKind = ExploreFeedKind.discover;
  ExploreLocationAvailability _nearbyAvailability =
      ExploreLocationAvailability.permissionNotRequested;

  ExploreFeedViewerContext _viewerContext = ExploreFeedViewerContext.empty;
  List<SocialPostModel> _discoverPosts = const <SocialPostModel>[];
  List<SocialPostModel> _nearbyPosts = const <SocialPostModel>[];
  DocumentSnapshot<Map<String, dynamic>>? _discoverLastDocument;
  Map<String, dynamic>? _nearbyCursor;
  bool _hasMoreDiscoverPosts = true;
  bool _hasMoreNearbyPosts = true;
  double? _nearbyRadiusKm;
  bool _nearbyUsedFallback = false;
  String? _nearbyEmptyReason;
  List<ExploreHashtagSummary> _trendingHashtags =
      const <ExploreHashtagSummary>[];
  List<UserProfile> _profileResults = const <UserProfile>[];
  List<ExploreHashtagSummary> _hashtagSuggestions =
      const <ExploreHashtagSummary>[];
  List<SocialPostModel> _hashtagResults = const <SocialPostModel>[];
  double _lastScrollOffset = 0;
  double _scrollDeltaAccumulator = 0;
  double _discoverScrollOffset = 0;
  double _nearbyScrollOffset = 0;
  String _authGenerationUid = '';
  int _nearbyRequestGeneration = 0;

  static const double _topBarTopResetOffset = 12;
  static const double _topBarHideThreshold = 32;
  static const double _topBarShowThreshold = 14;

  String get _currentUserId => _auth.currentUser?.uid.trim() ?? '';
  bool get _isSearchMode => _searchQuery.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    unawaited(_logExploreAuthSnapshot());
    _authGenerationUid = _currentUserId;
    _authStateSubscription = _auth.authStateChanges().listen(
      _handleAuthChanged,
    );
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

  Future<void> _logExploreAuthSnapshot() async {
    if (!kDebugMode) return;
    final user = _auth.currentUser;
    var tokenSuccess = false;
    try {
      final token = await user?.getIdToken(false);
      tokenSuccess = token?.trim().isNotEmpty == true;
    } catch (_) {
      tokenSuccess = false;
    }
    debugPrint(
      'Explore screen debug -> currentUserId=${user?.uid ?? ''}, tokenSuccess=$tokenSuccess',
    );
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleAuthChanged(User? user) {
    final nextUid = user?.uid.trim() ?? '';
    if (nextUid == _authGenerationUid) {
      return;
    }
    _authGenerationUid = nextUid;
    _nearbyRequestGeneration += 1;
    if (!mounted) return;
    setState(() {
      _nearbyPosts = const <SocialPostModel>[];
      _nearbyCursor = null;
      _nearbyError = null;
      _nearbyRadiusKm = null;
      _nearbyUsedFallback = false;
      _nearbyEmptyReason = null;
      _hasMoreNearbyPosts = true;
      _isLoadingNearbyPosts = false;
      _isLoadingMoreNearbyPosts = false;
    });
    _saveCache();
    debugPrint(
      'Explore screen auth debug -> uidChanged nextUid=$nextUid requestGeneration=$_nearbyRequestGeneration',
    );
    if (_activeFeedKind == ExploreFeedKind.nearby && nextUid.isNotEmpty) {
      unawaited(_loadNearbyPosts(forceRefresh: true, refreshLocation: true));
    }
  }

  void _applyCache(_ExploreCache cache) {
    _viewerContext = cache.viewerContext;
    _activeFeedKind = cache.activeFeedKind;
    _discoverPosts = cache.discoverPosts;
    _nearbyPosts = cache.nearbyPosts;
    _discoverLastDocument = cache.lastDiscoverDocument;
    _nearbyCursor = cache.nearbyCursor;
    _hasMoreDiscoverPosts = cache.hasMoreDiscoverPosts;
    _hasMoreNearbyPosts = cache.hasMoreNearbyPosts;
    _nearbyRadiusKm = cache.nearbyRadiusKm;
    _nearbyUsedFallback = cache.nearbyUsedFallback;
    _nearbyAvailability = cache.nearbyAvailability;
    _nearbyEmptyReason = cache.nearbyEmptyReason;
    _trendingHashtags = cache.trendingHashtags;
    _discoverScrollOffset = cache.discoverScrollOffset;
    _nearbyScrollOffset = cache.nearbyScrollOffset;
    _sectionsError = null;
    _nearbyError = null;
  }

  void _saveCache() {
    _memoryCache = _ExploreCache(
      viewerContext: _viewerContext,
      activeFeedKind: _activeFeedKind,
      discoverPosts: List<SocialPostModel>.from(_discoverPosts),
      nearbyPosts: List<SocialPostModel>.from(_nearbyPosts),
      lastDiscoverDocument: _discoverLastDocument,
      nearbyCursor: _nearbyCursor == null
          ? null
          : Map<String, dynamic>.from(_nearbyCursor!),
      hasMoreDiscoverPosts: _hasMoreDiscoverPosts,
      hasMoreNearbyPosts: _hasMoreNearbyPosts,
      nearbyRadiusKm: _nearbyRadiusKm,
      nearbyUsedFallback: _nearbyUsedFallback,
      nearbyAvailability: _nearbyAvailability,
      nearbyEmptyReason: _nearbyEmptyReason,
      trendingHashtags: List<ExploreHashtagSummary>.from(_trendingHashtags),
      discoverScrollOffset: _discoverScrollOffset,
      nearbyScrollOffset: _nearbyScrollOffset,
    );
  }

  Future<void> _refreshExploreSections() async {
    _memoryCache = null;
    await _loadExploreSections(forceRefresh: true);
    if (_activeFeedKind == ExploreFeedKind.nearby) {
      await _loadNearbyPosts(forceRefresh: true, refreshLocation: true);
    }
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
      final viewerContextFuture = _viewerContextRepository.load();
      final trendingHashtagsFuture = _socialPostRepository
          .fetchTrendingHashtags(limit: 10);

      final results = await Future.wait<dynamic>([
        viewerContextFuture,
        trendingHashtagsFuture,
      ]);

      final viewerContext = results[0] as ExploreFeedViewerContext;
      final trendingHashtags = results[1] as List<ExploreHashtagSummary>;
      final feedPage = await _exploreFeedRepository.fetchPage(
        kind: ExploreFeedKind.discover,
        viewerContext: viewerContext,
        limit: 10,
      );

      if (!mounted) return;
      setState(() {
        _viewerContext = viewerContext;
        _discoverPosts = feedPage.posts;
        _discoverLastDocument = feedPage.lastDocument;
        _hasMoreDiscoverPosts = feedPage.hasMore;
        _trendingHashtags = trendingHashtags;
      });
      _saveCache();

      if (_activeFeedKind == ExploreFeedKind.nearby &&
          _nearbyPosts.isEmpty &&
          _nearbyError == null) {
        unawaited(_loadNearbyPosts());
      }

      if (_isSearchMode) {
        await _runSearch(_searchQuery);
      }
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _sectionsError = error.message ?? error.toString();
      });
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

  Future<void> _loadMoreDiscoverPosts() async {
    if (_isLoadingMoreDiscoverPosts || !_hasMoreDiscoverPosts) return;

    setState(() => _isLoadingMoreDiscoverPosts = true);
    try {
      final page = await _exploreFeedRepository.fetchPage(
        kind: ExploreFeedKind.discover,
        viewerContext: _viewerContext,
        startAfter: _discoverLastDocument,
        excludePostIds: _discoverPosts
            .map((post) => post.id.trim())
            .where((id) => id.isNotEmpty)
            .toSet(),
        limit: 10,
      );
      if (!mounted) return;
      setState(() {
        _discoverPosts = <SocialPostModel>[..._discoverPosts, ...page.posts];
        _discoverLastDocument = page.lastDocument;
        _hasMoreDiscoverPosts = page.hasMore && page.posts.isNotEmpty;
      });
      _saveCache();
    } catch (_) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'We could not load more posts right now.',
        tone: AppFeedbackTone.warning,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingMoreDiscoverPosts = false);
      }
    }
  }

  Future<void> _loadNearbyPosts({
    bool forceRefresh = false,
    bool requestPermission = false,
    bool refreshLocation = false,
  }) async {
    if ((_isLoadingNearbyPosts || _isLoadingMoreNearbyPosts) && !forceRefresh) {
      return;
    }

    final hasExistingPosts = _nearbyPosts.isNotEmpty && !forceRefresh;
    setState(() {
      if (forceRefresh || !hasExistingPosts) {
        _isLoadingNearbyPosts = true;
      } else {
        _isLoadingMoreNearbyPosts = true;
      }
      _nearbyError = null;
      if (forceRefresh) {
        _nearbyCursor = null;
        _hasMoreNearbyPosts = true;
        _nearbyEmptyReason = null;
        _nearbyRadiusKm = null;
        _nearbyUsedFallback = false;
      }
    });

    final requestGeneration = ++_nearbyRequestGeneration;
    final requestUid = _authGenerationUid;
    try {
      final locationState = await _exploreLocationRepository.ensureLocation(
        requestPermission: requestPermission,
        refreshDeviceLocation: refreshLocation || forceRefresh,
      );
      final nextViewerContext = _viewerContext.copyWith(
        locationSnapshot: locationState.snapshot,
        city: locationState.snapshot.city.isNotEmpty
            ? locationState.snapshot.city
            : _viewerContext.city,
        state: locationState.snapshot.state.isNotEmpty
            ? locationState.snapshot.state
            : _viewerContext.state,
      );

      if (!mounted ||
          requestGeneration != _nearbyRequestGeneration ||
          requestUid != _authGenerationUid) {
        return;
      }
      setState(() {
        _viewerContext = nextViewerContext;
        _nearbyAvailability = locationState.availability;
      });

      final canLoadNearby =
          locationState.availability == ExploreLocationAvailability.ready ||
          nextViewerContext.normalizedCity.isNotEmpty ||
          nextViewerContext.normalizedState.isNotEmpty;
      if (!canLoadNearby) {
        setState(() {
          if (forceRefresh) {
            _nearbyPosts = const <SocialPostModel>[];
          }
          _hasMoreNearbyPosts = false;
        });
        _saveCache();
        return;
      }

      final page = await _exploreFeedRepository.fetchPage(
        kind: ExploreFeedKind.nearby,
        viewerContext: nextViewerContext,
        cursor: forceRefresh ? null : _nearbyCursor,
        excludePostIds: forceRefresh
            ? const <String>{}
            : _nearbyPosts
                  .map((post) => post.id.trim())
                  .where((id) => id.isNotEmpty)
                  .toSet(),
        limit: 10,
      );

      if (!mounted ||
          requestGeneration != _nearbyRequestGeneration ||
          requestUid != _authGenerationUid) {
        return;
      }
      setState(() {
        _nearbyPosts = forceRefresh
            ? page.posts
            : <SocialPostModel>[..._nearbyPosts, ...page.posts];
        _nearbyCursor = page.nextCursor;
        _hasMoreNearbyPosts = page.hasMore && page.nextCursor != null;
        _nearbyRadiusKm = page.activeRadiusKm;
        _nearbyUsedFallback = page.usedLocationFallback;
        _nearbyEmptyReason = page.emptyStateReason;
      });
      _saveCache();
    } on FirebaseFunctionsException catch (error) {
      if (!mounted ||
          requestGeneration != _nearbyRequestGeneration ||
          requestUid != _authGenerationUid) {
        return;
      }
      setState(() {
        _nearbyError =
            error.message ?? 'We could not load nearby posts right now.';
      });
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Explore nearby parse debug -> error=$error');
      }
      if (!mounted ||
          requestGeneration != _nearbyRequestGeneration ||
          requestUid != _authGenerationUid) {
        return;
      }
      setState(() {
        _nearbyError = nearbyLoadErrorMessage(error);
      });
    } finally {
      if (mounted &&
          requestGeneration == _nearbyRequestGeneration &&
          requestUid == _authGenerationUid) {
        setState(() {
          _isLoadingNearbyPosts = false;
          _isLoadingMoreNearbyPosts = false;
        });
      }
    }
  }

  void _handleFeedChanged(ExploreFeedKind kind) {
    if (_activeFeedKind == kind) return;
    setState(() {
      _activeFeedKind = kind;
    });
    _saveCache();

    if (kind == ExploreFeedKind.nearby &&
        _nearbyPosts.isEmpty &&
        !_isLoadingNearbyPosts) {
      unawaited(_loadNearbyPosts());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final targetOffset = kind == ExploreFeedKind.discover
          ? _discoverScrollOffset
          : _nearbyScrollOffset;
      _scrollController.jumpTo(
        targetOffset.clamp(0, _scrollController.position.maxScrollExtent),
      );
    });
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final direction = position.userScrollDirection;
    final pixels = position.pixels;
    if (_activeFeedKind == ExploreFeedKind.discover) {
      _discoverScrollOffset = pixels;
    } else {
      _nearbyScrollOffset = pixels;
    }
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
                initiallyFollowing: _viewerContext.followingIds.contains(
                  post.authorId,
                ),
                repository: _socialPostRepository,
                followRepository: _followRepository,
                onFollowChanged: (authorId, isFollowing) {
                  setState(() {
                    final nextFollowingIds = Set<String>.from(
                      _viewerContext.followingIds,
                    );
                    if (isFollowing) {
                      nextFollowingIds.add(authorId);
                    } else {
                      nextFollowingIds.remove(authorId);
                    }
                    _viewerContext = _viewerContext.copyWith(
                      followingIds: nextFollowingIds,
                    );
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
        currentlyFollowing: _viewerContext.followingIds.contains(userId),
      );
      if (!mounted) return;
      setState(() {
        final nextFollowingIds = Set<String>.from(_viewerContext.followingIds);
        if (isFollowing) {
          nextFollowingIds.add(userId);
        } else {
          nextFollowingIds.remove(userId);
        }
        _viewerContext = _viewerContext.copyWith(
          followingIds: nextFollowingIds,
        );
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
                      metrics.axis != Axis.vertical ||
                      metrics.maxScrollExtent <= 0) {
                    return false;
                  }

                  if (metrics.pixels >= metrics.maxScrollExtent - 320) {
                    if (_activeFeedKind == ExploreFeedKind.discover) {
                      if (_hasMoreDiscoverPosts &&
                          !_isLoadingMoreDiscoverPosts) {
                        _loadMoreDiscoverPosts();
                      }
                    } else if (_hasMoreNearbyPosts &&
                        !_isLoadingNearbyPosts &&
                        !_isLoadingMoreNearbyPosts) {
                      _loadNearbyPosts();
                    }
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
    final discoverPosts = _discoverPosts;

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
        _FadeInSection(
          child: _ExploreFeedSwitcher(
            activeKind: _activeFeedKind,
            onChanged: _handleFeedChanged,
          ),
        ),
        const SizedBox(height: 16),
        if (_activeFeedKind == ExploreFeedKind.discover) ...[
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
        ] else
          _buildNearbyContent(),
      ],
    );
  }

  Widget _buildNearbyContent() {
    if (_isLoadingNearbyPosts && _nearbyPosts.isEmpty) {
      return const _ExploreLoadingState();
    }

    if (_nearbyError != null) {
      return _ExploreErrorState(
        message: _nearbyError!,
        onRetry: () =>
            _loadNearbyPosts(forceRefresh: true, refreshLocation: true),
      );
    }

    if (_nearbyAvailability == ExploreLocationAvailability.serviceDisabled &&
        _nearbyPosts.isEmpty) {
      return _NearbyLocationStateCard(
        title: 'Turn on location services',
        message:
            'Nearby uses your location to find posts close to you. Enable device location services to continue.',
        actionLabel: 'Enable location services',
        onAction: () async {
          await _exploreLocationRepository.openLocationSettings();
        },
      );
    }

    if (_nearbyAvailability ==
            ExploreLocationAvailability.permissionPermanentlyDenied &&
        _nearbyPosts.isEmpty) {
      return _NearbyLocationStateCard(
        title: 'Location permission is off',
        message:
            'Nearby needs your location to rank posts by distance. Open app settings to allow location access.',
        actionLabel: 'Open settings',
        onAction: () async {
          await _exploreLocationRepository.openAppSettings();
        },
      );
    }

    if ((_nearbyAvailability ==
                ExploreLocationAvailability.permissionNotRequested ||
            _nearbyAvailability ==
                ExploreLocationAvailability.permissionDenied) &&
        _nearbyPosts.isEmpty &&
        _viewerContext.normalizedCity.isEmpty &&
        _viewerContext.normalizedState.isEmpty) {
      return _NearbyLocationStateCard(
        title: 'Enable location for Nearby',
        message:
            'Nearby you uses your location to find posts around you. Discover continues working without location permission.',
        actionLabel: 'Enable location',
        onAction: () => _loadNearbyPosts(
          forceRefresh: true,
          requestPermission: true,
          refreshLocation: true,
        ),
      );
    }

    if (_nearbyPosts.isEmpty) {
      final radiusText = _nearbyRadiusKm == null
          ? ''
          : ' within ${_nearbyRadiusKm!.toStringAsFixed(0)} km';
      return _ExploreEmptyState(
        title: _nearbyUsedFallback
            ? 'No posts in your area yet'
            : 'No nearby posts yet',
        message: _nearbyUsedFallback
            ? 'Nearby is using your saved city/state right now, but we still could not find public posts near you.'
            : _nearbyEmptyReason == 'missingLocation'
            ? 'Enable location to see nearby posts.'
            : 'There are no nearby posts$radiusText yet. Try again after more pet parents post nearby.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_nearbyUsedFallback || _nearbyRadiusKm != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _nearbyUsedFallback
                  ? 'Showing posts near your saved city/state.'
                  : 'Showing posts within ${_nearbyRadiusKm!.toStringAsFixed(0)} km of you.',
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        _FadeInSection(
          child: _DiscoverSection(
            title: 'Nearby you',
            posts: _nearbyPosts,
            onOpenPost: _openPostDetail,
            showLocationLabel: true,
          ),
        ),
        if (_isLoadingMoreNearbyPosts)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
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
            final isFollowing = _viewerContext.followingIds.contains(
              profile.uid,
            );
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
  final ExploreFeedViewerContext viewerContext;
  final ExploreFeedKind activeFeedKind;
  final List<SocialPostModel> discoverPosts;
  final List<SocialPostModel> nearbyPosts;
  final DocumentSnapshot<Map<String, dynamic>>? lastDiscoverDocument;
  final Map<String, dynamic>? nearbyCursor;
  final bool hasMoreDiscoverPosts;
  final bool hasMoreNearbyPosts;
  final double? nearbyRadiusKm;
  final bool nearbyUsedFallback;
  final ExploreLocationAvailability nearbyAvailability;
  final String? nearbyEmptyReason;
  final List<ExploreHashtagSummary> trendingHashtags;
  final double discoverScrollOffset;
  final double nearbyScrollOffset;

  const _ExploreCache({
    required this.viewerContext,
    required this.activeFeedKind,
    required this.discoverPosts,
    required this.nearbyPosts,
    required this.lastDiscoverDocument,
    required this.nearbyCursor,
    required this.hasMoreDiscoverPosts,
    required this.hasMoreNearbyPosts,
    required this.nearbyRadiusKm,
    required this.nearbyUsedFallback,
    required this.nearbyAvailability,
    required this.nearbyEmptyReason,
    required this.trendingHashtags,
    required this.discoverScrollOffset,
    required this.nearbyScrollOffset,
  });

  bool get hasDiscoveryData =>
      discoverPosts.isNotEmpty ||
      nearbyPosts.isNotEmpty ||
      trendingHashtags.isNotEmpty;
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

class _ExploreFeedSwitcher extends StatelessWidget {
  final ExploreFeedKind activeKind;
  final ValueChanged<ExploreFeedKind> onChanged;

  const _ExploreFeedSwitcher({
    required this.activeKind,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
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
          Expanded(
            child: _ExploreFeedPill(
              label: 'Discover',
              selected: activeKind == ExploreFeedKind.discover,
              onTap: () => onChanged(ExploreFeedKind.discover),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ExploreFeedPill(
              label: 'Nearby you',
              selected: activeKind == ExploreFeedKind.nearby,
              onTap: () => onChanged(ExploreFeedKind.nearby),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExploreFeedPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ExploreFeedPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFFFF6B2C), Color(0xFFFF8B57)],
                )
              : null,
          color: selected ? null : const Color(0xFFF7F3EF),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textDark,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _NearbyLocationStateCard extends StatelessWidget {
  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;

  const _NearbyLocationStateCard({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.near_me_rounded, color: AppColors.primary, size: 28),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => unawaited(onAction()),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: Text(actionLabel),
          ),
        ],
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
  final bool showLocationLabel;

  const _DiscoverSection({
    required this.title,
    required this.posts,
    required this.onOpenPost,
    this.showLocationLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const crossAxisCount = 2;
        const crossAxisSpacing = 12.0;
        const mainAxisSpacing = 12.0;
        final availableWidth = constraints.maxWidth;
        final cardWidth =
            (availableWidth - crossAxisSpacing * (crossAxisCount - 1)) /
            crossAxisCount;
        final compactCard = cardWidth < 170;
        final imageHeight = showLocationLabel
            ? (compactCard ? 176.0 : 188.0)
            : (compactCard ? 168.0 : 180.0);
        final cardHeight = showLocationLabel
            ? (compactCard ? 324.0 : 332.0)
            : (compactCard ? 300.0 : 312.0);

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
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: mainAxisSpacing,
                  crossAxisSpacing: crossAxisSpacing,
                  mainAxisExtent: cardHeight,
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
                    showLocationLabel: showLocationLabel,
                    imageHeightOverride: imageHeight,
                  );
                },
              ),
          ],
        );
      },
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
  final bool showLocationLabel;
  final double? imageHeightOverride;

  const _CompactPostCard({
    required this.post,
    required this.onTap,
    this.expandToAvailableWidth = false,
    this.showUsername = true,
    this.showShareStat = true,
    this.showLocationLabel = false,
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
                            if (showLocationLabel &&
                                post.locationLabel.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF4EC),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  post.locationLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: compact ? 11.5 : 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
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
