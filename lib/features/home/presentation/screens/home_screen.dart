import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/navigation/social_app_tab.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../../../core/services/network_status_service.dart';
import '../../data/home_feed_repository.dart';
import '../../domain/home_feed_refresh_policy.dart';
import '../../domain/home_feed_session.dart';
import '../../../notifications/domain/notification_visibility.dart';
import '../../../offer_wall/data/services/offer_wall_coordinator.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../../../restrictions/data/services/user_restriction_service.dart';
import '../../../social/data/follow_repository.dart';
import '../../../social/data/services/post_publish_coordinator.dart';
import '../../../social/data/social_post_repository.dart';
import '../../../social/domain/models/social_post_model.dart';
import '../../../social/presentation/widgets/social_post_card.dart';
import '../../../social/presentation/widgets/suggested_users_section.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final HomeFeedRepository _homeFeedRepository = HomeFeedRepository();
  final HomeFeedSession _homeFeedSession = HomeFeedSession();
  final SocialPostRepository _socialPostRepository = SocialPostRepository();
  final FollowRepository _followRepository = FollowRepository();
  final ProfileRepository _profileRepository = ProfileRepository();
  final ScrollController _scrollController = ScrollController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late int _suggestionSeed;

  bool _isLoadingFeed = true;
  bool _isLoadingMore = false;
  bool _isTopBarVisible = true;
  bool _hasMorePosts = true;
  String? _feedError;
  DocumentSnapshot<Map<String, dynamic>>? _lastPostDocument;
  final List<SocialPostModel> _posts = <SocialPostModel>[];
  List<UserProfile> _suggestedUsers = const <UserProfile>[];
  List<HomeFeedEntry> _feedEntries = const <HomeFeedEntry>[];
  final Set<String> _likedPostIds = <String>{};
  HomeFeedViewerContext _viewerContext = HomeFeedViewerContext.empty;
  String? _userCity;
  String? _userState;
  final Set<String> _followingIds = <String>{};
  final Set<String> _shownSuggestionIds = <String>{};
  int _suggestionFollowRefreshCounter = 0;
  double _lastScrollOffset = 0;
  double _scrollDeltaAccumulator = 0;
  late final VoidCallback _networkStatusListener;
  late final VoidCallback _postPublishListener;
  int _lastHandledPublishEventId = 0;
  final HomeFeedRequestTracker _feedRequestTracker = HomeFeedRequestTracker();

  static const double _topBarTopResetOffset = 12;
  static const double _topBarHideThreshold = 32;
  static const double _topBarShowThreshold = 14;

  @override
  void initState() {
    super.initState();
    _suggestionSeed = DateTime.now().millisecondsSinceEpoch;
    _scrollController.addListener(_handleScroll);
    _networkStatusListener = () {
      if (!mounted) return;
      if (NetworkStatusService.instance.isOnline &&
          (_posts.isEmpty || _feedError != null)) {
        debugPrint('HomeScreen startup debug -> refreshing after reconnect');
        unawaited(_refreshHome());
      } else {
        setState(() {});
      }
    };
    NetworkStatusService.instance.isOnlineListenable.addListener(
      _networkStatusListener,
    );
    _postPublishListener = () {
      final state = PostPublishCoordinator.instance.state;
      if (state.phase != PostPublishPhase.success) return;
      if (state.eventId == _lastHandledPublishEventId) return;
      _lastHandledPublishEventId = state.eventId;
      unawaited(_refreshHome());
    };
    PostPublishCoordinator.instance.stateListenable.addListener(
      _postPublishListener,
    );
    _loadInitialPosts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(OfferWallCoordinator.instance.handleAuthenticatedShellReady());
    });
  }

  @override
  void dispose() {
    PostPublishCoordinator.instance.stateListenable.removeListener(
      _postPublishListener,
    );
    NetworkStatusService.instance.isOnlineListenable.removeListener(
      _networkStatusListener,
    );
    _scrollController.dispose();
    super.dispose();
  }

  Future<HomeFeedViewerContext> _loadViewerContextForFeed() async {
    try {
      return await _homeFeedRepository.loadViewerContext();
    } catch (_) {
      // Safe fallback: home feed still works without personalization context.
      return _viewerContext;
    }
  }

  Future<void> _loadSuggestedUsers() async {
    final currentUserId = _auth.currentUser?.uid ?? '';
    if (currentUserId.isEmpty) return;

    try {
      final excludedIds = Set<String>.from(_followingIds)
        ..addAll(_shownSuggestionIds);
      final suggestions = await _profileRepository.fetchSuggestedUsers(
        currentUserId: currentUserId,
        followingIds: excludedIds,
        city: _userCity,
        state: _userState,
        limit: 10,
        seed: _suggestionSeed,
      );
      if (!mounted) return;
      setState(() {
        _suggestedUsers = suggestions;
        _shownSuggestionIds.addAll(
          suggestions
              .map((profile) => profile.uid)
              .where((id) => id.isNotEmpty),
        );
      });
    } catch (_) {
      // Suggestions are non-blocking for the home feed.
    }
  }

  Future<void> _refreshSuggestions({bool resetSession = false}) async {
    if (resetSession) {
      _suggestionSeed = DateTime.now().millisecondsSinceEpoch;
      _shownSuggestionIds.clear();
      _suggestionFollowRefreshCounter = 0;
    }
    await _loadSuggestedUsers();
  }

  Future<void> _refreshHome() async {
    _suggestionSeed = DateTime.now().millisecondsSinceEpoch;
    _shownSuggestionIds.clear();
    _suggestionFollowRefreshCounter = 0;
    await _loadInitialPosts(forceRefresh: true);
  }

  Future<void> _loadInitialPosts({bool forceRefresh = false}) async {
    final requestId = _feedRequestTracker.startRequest();
    final hadExistingPosts = _feedEntries.isNotEmpty;
    if (!mounted) return;

    setState(() {
      _feedError = null;
      if (!hadExistingPosts) {
        _isLoadingFeed = true;
        _hasMorePosts = true;
        _lastPostDocument = null;
        _likedPostIds.clear();
      }
    });

    try {
      final viewerContext = await _loadViewerContextForFeed();
      if (!mounted || !_feedRequestTracker.isCurrent(requestId)) return;

      final page = await _homeFeedRepository.fetchPage(
        viewerContext: viewerContext,
        limit: 10,
        forceRefresh: forceRefresh,
      );
      if (!mounted || !_feedRequestTracker.isCurrent(requestId)) return;

      final likedPostIds = await _socialPostRepository
          .fetchCurrentUserLikedPostIds(
            page.posts.map((post) => post.id).toList(growable: false),
          );
      if (!mounted || !_feedRequestTracker.isCurrent(requestId)) return;

      final replacementPosts = HomeFeedRefreshPolicy.dedupeReplacementPosts(
        page.posts,
      );
      final shouldReplaceVisibleFeed =
          HomeFeedRefreshPolicy.shouldReplaceVisibleFeed(
            hadExistingPosts: hadExistingPosts,
            refreshedPosts: replacementPosts,
          );
      if (!shouldReplaceVisibleFeed) {
        setState(() {
          _viewerContext = viewerContext;
          _userCity = viewerContext.city;
          _userState = viewerContext.state;
          _followingIds
            ..clear()
            ..addAll(viewerContext.followingIds);
        });
        unawaited(_loadSuggestedUsers());
        return;
      }

      _homeFeedSession.reset(
        candidates: replacementPosts,
        viewerContext: viewerContext,
        initialEntryCount: 10,
        preserveSeenPosts: forceRefresh,
      );

      setState(() {
        _viewerContext = viewerContext;
        _userCity = viewerContext.city;
        _userState = viewerContext.state;
        _followingIds
          ..clear()
          ..addAll(viewerContext.followingIds);
        _posts
          ..clear()
          ..addAll(replacementPosts);
        _likedPostIds
          ..clear()
          ..addAll(likedPostIds);
        _feedEntries = _homeFeedSession.entries;
        _lastPostDocument = page.lastDocument;
        _hasMorePosts = page.hasMore;
      });
      unawaited(_loadSuggestedUsers());
    } catch (error) {
      if (!mounted || !_feedRequestTracker.isCurrent(requestId)) return;
      if (hadExistingPosts) {
        AppFeedback.show(
          context,
          message: NetworkStatusService.instance.isOffline
              ? 'You’re offline. Showing the existing home feed.'
              : 'We could not refresh the home feed right now.',
          tone: AppFeedbackTone.warning,
        );
      } else {
        setState(
          () => _feedError = NetworkStatusService.instance.isOffline
              ? 'You’re offline. Connect to the internet to load latest content.'
              : error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted && _feedRequestTracker.isCurrent(requestId)) {
        setState(() => _isLoadingFeed = false);
      }
    }
  }

  Future<void> _loadMorePosts() async {
    if (_isLoadingFeed || _isLoadingMore || !_hasMorePosts) return;

    setState(() => _isLoadingMore = true);
    try {
      final page = await _homeFeedRepository.fetchPage(
        viewerContext: _viewerContext,
        startAfter: _lastPostDocument,
        excludePostIds: _homeFeedSession.emittedPostIds,
        limit: 10,
      );
      final likedPostIds = await _socialPostRepository
          .fetchCurrentUserLikedPostIds(
            page.posts.map((post) => post.id).toList(growable: false),
          );
      final uniqueNewPosts = HomeFeedRefreshPolicy.dedupeAppendedPosts(
        page.posts,
        existingPostIds: _posts.map((post) => post.id),
      );
      _homeFeedSession.appendCandidates(
        candidates: uniqueNewPosts,
        viewerContext: _viewerContext,
        count: 10,
      );
      if (!mounted) return;
      setState(() {
        _posts.addAll(uniqueNewPosts);
        _likedPostIds.addAll(likedPostIds);
        _feedEntries = _homeFeedSession.entries;
        _lastPostDocument = page.lastDocument;
        _hasMorePosts = page.hasMore && page.posts.isNotEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'We could not load more posts right now.',
        tone: AppFeedbackTone.warning,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
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
      if (!_isTopBarVisible && mounted) {
        setState(() => _isTopBarVisible = true);
      }
    } else if (direction == ScrollDirection.reverse && delta > 0) {
      _scrollDeltaAccumulator = (_scrollDeltaAccumulator + delta).clamp(
        0.0,
        _topBarHideThreshold,
      );
      if (_isTopBarVisible &&
          _scrollDeltaAccumulator >= _topBarHideThreshold &&
          mounted) {
        _scrollDeltaAccumulator = 0;
        setState(() => _isTopBarVisible = false);
      }
    } else if (direction == ScrollDirection.forward && delta < 0) {
      _scrollDeltaAccumulator = (_scrollDeltaAccumulator + delta).clamp(
        -_topBarShowThreshold,
        0.0,
      );
      if (!_isTopBarVisible &&
          _scrollDeltaAccumulator <= -_topBarShowThreshold &&
          mounted) {
        _scrollDeltaAccumulator = 0;
        setState(() => _isTopBarVisible = true);
      }
    } else if (direction == ScrollDirection.idle) {
      _scrollDeltaAccumulator = 0;
    }

    if (pixels >= position.maxScrollExtent - 320) {
      _loadMorePosts();
    }
  }

  void _handlePostUpdated(SocialPostModel updatedPost) {
    final index = _posts.indexWhere((post) => post.id == updatedPost.id);
    if (index == -1) return;

    setState(() {
      _posts[index] = updatedPost;
      _homeFeedSession.replacePost(updatedPost);
      _feedEntries = _homeFeedSession.entries;
    });
  }

  void _handleLikeChanged(String postId, bool isLiked, int newLikeCount) {
    final index = _posts.indexWhere((post) => post.id == postId);
    if (index == -1) return;

    setState(() {
      _posts[index] = _posts[index].copyWith(likeCount: newLikeCount);
      _homeFeedSession.replacePost(_posts[index]);
      _feedEntries = _homeFeedSession.entries;
      if (isLiked) {
        _likedPostIds.add(postId);
      } else {
        _likedPostIds.remove(postId);
      }
    });
  }

  void _handleCommentCountChanged(String postId, int newCommentCount) {
    final index = _posts.indexWhere((post) => post.id == postId);
    if (index == -1) return;

    setState(() {
      _posts[index] = _posts[index].copyWith(commentCount: newCommentCount);
      _homeFeedSession.replacePost(_posts[index]);
      _feedEntries = _homeFeedSession.entries;
    });
  }

  void _handlePostDeleted(String postId) {
    setState(() {
      _posts.removeWhere((post) => post.id == postId);
      _likedPostIds.remove(postId);
      _homeFeedSession.removePost(postId);
      _feedEntries = _homeFeedSession.entries;
    });
  }

  void _handleFollowChanged(String authorId, bool isFollowing) {
    setState(() {
      if (isFollowing) {
        _followingIds.add(authorId);
        _suggestedUsers = _suggestedUsers
            .where((profile) => profile.uid != authorId)
            .toList(growable: false);
        _suggestionFollowRefreshCounter += 1;
      } else {
        _followingIds.remove(authorId);
      }
      _viewerContext = HomeFeedViewerContext(
        currentUserId: _viewerContext.currentUserId,
        city: _viewerContext.city,
        state: _viewerContext.state,
        followingIds: Set<String>.from(_followingIds),
        blockedUserIds: _viewerContext.blockedUserIds,
        mutedUserIds: _viewerContext.mutedUserIds,
        creatorsWhoBlockedViewerIds: _viewerContext.creatorsWhoBlockedViewerIds,
      );
      _homeFeedSession.reset(
        candidates: List<SocialPostModel>.from(_posts),
        viewerContext: _viewerContext,
        initialEntryCount: _feedEntries.length,
        preserveSeenPosts: true,
      );
      _feedEntries = _homeFeedSession.entries;
    });
    if (isFollowing && _suggestionFollowRefreshCounter >= 3) {
      unawaited(_refreshSuggestions(resetSession: true));
    }
  }

  bool get _shouldShowSuggestions =>
      _suggestedUsers.isNotEmpty && _feedEntries.length >= 3;

  int get _suggestionsInsertIndex => _feedEntries.length >= 5 ? 4 : 3;

  int get _baseFeedItemCount =>
      _feedEntries.length + (_shouldShowSuggestions ? 1 : 0);

  int _postIndexForFeedIndex(int feedIndex) {
    if (!_shouldShowSuggestions || feedIndex < _suggestionsInsertIndex) {
      return feedIndex;
    }
    return feedIndex - 1;
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _auth.currentUser?.uid ?? '';
    final topInset = MediaQuery.paddingOf(context).top;
    const topBarHeight = 68.0;
    final topContentPadding = topInset + topBarHeight + 8;
    final bottomContentPadding = SocialBottomNav.contentBottomPadding(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: Stack(
        children: [
          // The feed is painted edge-to-edge first so it can scroll behind the
          // floating header and bottom nav overlays.
          RefreshIndicator(
            onRefresh: _refreshHome,
            child: ListView.separated(
              controller: _scrollController,
              cacheExtent: 720,
              padding: EdgeInsets.fromLTRB(
                16,
                topContentPadding,
                16,
                bottomContentPadding,
              ),
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              itemCount: _feedItemCount,
              separatorBuilder: (context, index) => const SizedBox(height: 18),
              itemBuilder: (context, index) {
                if (_isLoadingFeed) {
                  return const _FeedLoadingCard();
                }
                if (_feedError != null) {
                  return _FeedStatusCard(
                    title: 'Could not load the feed',
                    message: _feedError!,
                    actionLabel: 'Try Again',
                    onPressed: _loadInitialPosts,
                  );
                }
                if (_feedEntries.isEmpty) {
                  return _FeedStatusCard(
                    title: NetworkStatusService.instance.isOffline
                        ? 'You’re offline'
                        : 'No posts yet',
                    message: NetworkStatusService.instance.isOffline
                        ? 'Connect to the internet to load latest content.'
                        : 'The home feed will start filling up once the first Pettxo posts are published.',
                  );
                }
                if (_shouldShowSuggestions &&
                    index == _suggestionsInsertIndex) {
                  return SuggestedUsersSection(
                    users: _suggestedUsers,
                    currentUserId: currentUserId,
                    followRepository: _followRepository,
                    onFollowed: (userId) => _handleFollowChanged(userId, true),
                  );
                }
                if (index >= _baseFeedItemCount) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final entry = _feedEntries[_postIndexForFeedIndex(index)];
                return SocialPostCard(
                  key: ValueKey(entry.post.id),
                  post: entry.post,
                  rankingReason: entry.rankingReason,
                  currentUserId: currentUserId,
                  initiallyLiked: _likedPostIds.contains(entry.post.id),
                  initiallyFollowing: _followingIds.contains(
                    entry.post.authorId,
                  ),
                  repository: _socialPostRepository,
                  followRepository: _followRepository,
                  onPostUpdated: _handlePostUpdated,
                  onPostDeleted: _handlePostDeleted,
                  onLikeChanged: _handleLikeChanged,
                  onCommentCountChanged: _handleCommentCountChanged,
                  onFollowChanged: _handleFollowChanged,
                );
              },
            ),
          ),
          // Safe-area spacing is applied to the overlay itself instead of the
          // whole body, which keeps the status bar clear while still letting
          // content pass underneath the bar as the user scrolls.
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
            top: topInset,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              offset: _isTopBarVisible ? Offset.zero : const Offset(0, -1.15),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOutCubic,
                opacity: _isTopBarVisible ? 1 : 0,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  scale: _isTopBarVisible ? 1 : 0.97,
                  child: IgnorePointer(
                    ignoring: !_isTopBarVisible,
                    child: GlassSurface(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      borderRadius: BorderRadius.zero,
                      backgroundColor: AppColors.background.withValues(
                        alpha: 0.56,
                      ),
                      blurSigma: 20,
                      border: Border.all(color: Colors.transparent, width: 0),
                      boxShadow: const [],
                      child: Align(
                        child: FractionallySizedBox(
                          widthFactor: 0.89,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFFFE9DD),
                                          Color(0xFFFFF3EC),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(18),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.04,
                                          ),
                                          blurRadius: 14,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: IconButton(
                                      onPressed: () async {
                                        if (!UserRestrictionService.instance
                                            .ensureCanUseSocialFeatures(
                                              context,
                                            )) {
                                          return;
                                        }
                                        await Navigator.pushNamed(
                                          context,
                                          "/create",
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.add_rounded,
                                        color: AppColors.primary,
                                        size: 24,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.68,
                                      ),
                                      borderRadius: BorderRadius.circular(18),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.04,
                                          ),
                                          blurRadius: 14,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: const _NotificationsBellButton(),
                                  ),
                                ],
                              ),
                              const IgnorePointer(
                                child: Text(
                                  "Pettxo",
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
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
      bottomNavigationBar: const SocialBottomNav(activeTab: SocialAppTab.home),
    );
  }

  int get _feedItemCount {
    if (_isLoadingFeed || _feedError != null || _feedEntries.isEmpty) {
      return 1;
    }
    return _baseFeedItemCount + (_isLoadingMore ? 1 : 0);
  }
}

class _FeedStatusCard extends StatelessWidget {
  final String title;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onPressed;

  const _FeedStatusCard({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onPressed,
  });

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.textGrey,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (actionLabel != null && onPressed != null) ...[
            const SizedBox(height: 16),
            SecondaryButton(
              label: actionLabel!,
              expand: false,
              onPressed: () => onPressed!.call(),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeedLoadingCard extends StatelessWidget {
  const _FeedLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class _NotificationsBellButton extends StatefulWidget {
  const _NotificationsBellButton();

  @override
  State<_NotificationsBellButton> createState() =>
      _NotificationsBellButtonState();
}

class _NotificationsBellButtonState extends State<_NotificationsBellButton>
    with SingleTickerProviderStateMixin {
  static const Duration _ringDuration = Duration(milliseconds: 720);
  static const Duration _ringInterval = Duration(seconds: 8);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _ringDuration,
  );
  late final Animation<double> _rotation = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0,
        end: -0.12,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 1,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: -0.12,
        end: 0.1,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 1,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0.1,
        end: -0.07,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 1,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: -0.07,
        end: 0.05,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 1,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0.05,
        end: 0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 1,
    ),
  ]).animate(_controller);

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _notificationSubscription;
  Timer? _ringTimer;
  bool _hasUnreadNotifications = false;

  @override
  void initState() {
    super.initState();
    _bindNotificationStream(_auth.currentUser);
    _authSubscription = _auth.authStateChanges().listen(
      _bindNotificationStream,
    );
  }

  @override
  void dispose() {
    _ringTimer?.cancel();
    _notificationSubscription?.cancel();
    _authSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _bindNotificationStream(User? user) {
    _notificationSubscription?.cancel();
    _updateUnreadState(false);

    if (user == null) return;

    _notificationSubscription = _firestore
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .limit(50)
        .snapshots()
        .listen((snapshot) {
          final hasUnread = snapshot.docs.any((doc) {
            final data = doc.data();
            if (!NotificationVisibility.isVisibleInApp(data)) return false;
            return data['read'] != true && data['isRead'] != true;
          });
          _updateUnreadState(hasUnread);
        });
  }

  void _updateUnreadState(bool hasUnread) {
    if (_hasUnreadNotifications == hasUnread) return;
    _hasUnreadNotifications = hasUnread;

    if (hasUnread) {
      _startRingLoop();
    } else {
      _stopRingLoop();
    }
  }

  void _startRingLoop() {
    _ringTimer?.cancel();
    _controller.forward(from: 0);
    _ringTimer = Timer.periodic(_ringInterval, (_) {
      if (!_hasUnreadNotifications || _controller.isAnimating) return;
      _controller.forward(from: 0);
    });
  }

  void _stopRingLoop() {
    _ringTimer?.cancel();
    _ringTimer = null;
    if (_controller.isAnimating || _controller.value != 0) {
      _controller.animateTo(0, duration: const Duration(milliseconds: 160));
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        Navigator.pushNamed(context, "/alerts");
      },
      icon: AnimatedBuilder(
        animation: _rotation,
        builder: (context, child) {
          return Transform.rotate(
            angle: _rotation.value,
            alignment: const Alignment(0, -0.65),
            child: Icon(
              Icons.notifications_none_rounded,
              color: _hasUnreadNotifications
                  ? AppColors.primary
                  : AppColors.textDark,
            ),
          );
        },
      ),
    );
  }
}
