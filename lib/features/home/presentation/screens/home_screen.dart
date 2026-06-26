import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/navigation/social_app_tab.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../../offers/data/services/offer_service.dart';
import '../../../offers/presentation/screens/offer_wall_screen.dart';
import '../../../offers/presentation/widgets/offer_popup_dialog.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../../../restrictions/data/services/user_restriction_service.dart';
import '../../../social/data/follow_repository.dart';
import '../../../social/data/social_post_repository.dart';
import '../../../social/domain/social_feed_ranker.dart';
import '../../../social/domain/models/social_post_model.dart';
import '../../../social/presentation/widgets/social_post_card.dart';
import '../../../social/presentation/widgets/suggested_users_section.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final OfferService _offerService = OfferService();
  final SocialPostRepository _socialPostRepository = SocialPostRepository();
  final FollowRepository _followRepository = FollowRepository();
  final ProfileRepository _profileRepository = ProfileRepository();
  final ScrollController _scrollController = ScrollController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late int _suggestionSeed;

  bool _checkedOffers = false;
  bool _isLoadingFeed = true;
  bool _isLoadingMore = false;
  bool _hasMorePosts = true;
  String? _feedError;
  DocumentSnapshot<Map<String, dynamic>>? _lastPostDocument;
  final List<SocialPostModel> _posts = <SocialPostModel>[];
  List<UserProfile> _suggestedUsers = const <UserProfile>[];
  List<RankedPost> _rankedPosts = const <RankedPost>[];
  final Set<String> _likedPostIds = <String>{};
  String? _userCity;
  String? _userState;
  final Set<String> _followingIds = <String>{};
  final Set<String> _shownSuggestionIds = <String>{};
  final Set<String> _userInterestTags = <String>{};
  int _suggestionFollowRefreshCounter = 0;

  @override
  void initState() {
    super.initState();
    _suggestionSeed = DateTime.now().millisecondsSinceEpoch;
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showEligibleOffers();
    });
    _primeRankingContext();
    _loadInitialPosts();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _showEligibleOffers() async {
    if (_checkedOffers || !mounted) return;
    _checkedOffers = true;

    try {
      final result = await _offerService.getEligibleOffers(screen: 'home');
      if (!mounted) return;

      final offerWall = result.offerWall;
      if (offerWall != null &&
          await _offerService.shouldShowOffer(offerWall.id)) {
        await _offerService.markOfferShown(offerWall.id);
        if (!mounted) return;
        final claimed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => OfferWallScreen(offer: offerWall)),
        );
        if (!mounted) return;
        if (claimed == true) {
          AppFeedback.show(
            context,
            message: 'Offer claimed successfully.',
            tone: AppFeedbackTone.success,
          );
        } else {
          await _offerService.recordOfferDismissed(offerWall.id);
        }
        return;
      }

      final popup = result.popup;
      if (popup != null && await _offerService.shouldShowOffer(popup.id)) {
        await _offerService.markOfferShown(popup.id);
        if (!mounted) return;
        final claimed = await OfferPopupDialog.show(context, offer: popup);
        if (!mounted) return;
        if (claimed == true) {
          AppFeedback.show(
            context,
            message: 'Offer claimed successfully.',
            tone: AppFeedbackTone.success,
          );
        } else {
          await _offerService.recordOfferDismissed(popup.id);
        }
      }
    } catch (_) {
      // Offer fetch failures should not interrupt the home experience.
    }
  }

  Future<void> _primeRankingContext() async {
    try {
      final currentUserId = _auth.currentUser?.uid ?? '';
      final results = await Future.wait<dynamic>([
        _profileRepository.getCurrentUserProfile(),
        _followRepository.fetchFollowingIds(currentUserId),
      ]);
      final profile = results[0] as UserProfile;
      final followingIds = results[1] as Set<String>;
      if (!mounted) return;
      setState(() {
        _userCity = profile.city;
        _userState = profile.state;
        _followingIds
          ..clear()
          ..addAll(followingIds);
        _rankedPosts = _buildRankedPosts(_posts);
      });
      await _loadSuggestedUsers();
    } catch (_) {
      // Safe fallback: ranking works without profile context.
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
    await _primeRankingContext();
    await _loadInitialPosts();
  }

  Future<void> _loadInitialPosts() async {
    setState(() {
      _isLoadingFeed = true;
      _feedError = null;
      _hasMorePosts = true;
      _lastPostDocument = null;
      _likedPostIds.clear();
    });

    try {
      final page = await _socialPostRepository.fetchVisiblePosts(limit: 10);
      final likedPostIds = await _socialPostRepository
          .fetchCurrentUserLikedPostIds(
            page.posts.map((post) => post.id).toList(growable: false),
          );
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(_dedupePosts(page.posts));
        _likedPostIds
          ..clear()
          ..addAll(likedPostIds);
        _rankedPosts = _rankInitialPosts(_posts);
        _lastPostDocument = page.lastDocument;
        _hasMorePosts = page.hasMore;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _feedError = error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingFeed = false);
      }
    }
  }

  Future<void> _loadMorePosts() async {
    if (_isLoadingFeed || _isLoadingMore || !_hasMorePosts) return;

    setState(() => _isLoadingMore = true);
    try {
      final page = await _socialPostRepository.fetchVisiblePosts(
        startAfter: _lastPostDocument,
        limit: 10,
      );
      final likedPostIds = await _socialPostRepository
          .fetchCurrentUserLikedPostIds(
            page.posts.map((post) => post.id).toList(growable: false),
          );
      final uniqueNewPosts = _dedupePosts(page.posts);
      if (!mounted) return;
      setState(() {
        _posts.addAll(uniqueNewPosts);
        _likedPostIds.addAll(likedPostIds);
        _mergeRankedPosts(uniqueNewPosts);
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
    if (position.pixels >= position.maxScrollExtent - 320) {
      _loadMorePosts();
    }
  }

  List<SocialPostModel> _dedupePosts(List<SocialPostModel> incoming) {
    final existingIds = _posts.map((post) => post.id).toSet();
    final uniqueIncoming = <SocialPostModel>[];

    for (final post in incoming) {
      if (existingIds.add(post.id)) {
        uniqueIncoming.add(post);
      }
    }

    return uniqueIncoming;
  }

  void _handlePostUpdated(SocialPostModel updatedPost) {
    final index = _posts.indexWhere((post) => post.id == updatedPost.id);
    if (index == -1) return;

    setState(() {
      _posts[index] = updatedPost;
      final rankedIndex = _rankedPosts.indexWhere(
        (rankedPost) => rankedPost.post.id == updatedPost.id,
      );
      if (rankedIndex != -1) {
        _rankedPosts[rankedIndex] = _rankedPosts[rankedIndex].copyWith(
          post: updatedPost,
        );
      }
    });
  }

  void _handleLikeChanged(String postId, bool isLiked, int newLikeCount) {
    final index = _posts.indexWhere((post) => post.id == postId);
    if (index == -1) return;

    setState(() {
      _posts[index] = _posts[index].copyWith(likeCount: newLikeCount);
      final rankedIndex = _rankedPosts.indexWhere(
        (rankedPost) => rankedPost.post.id == postId,
      );
      if (rankedIndex != -1) {
        _rankedPosts[rankedIndex] = _rankedPosts[rankedIndex].copyWith(
          post: _posts[index],
        );
      }
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
      final rankedIndex = _rankedPosts.indexWhere(
        (rankedPost) => rankedPost.post.id == postId,
      );
      if (rankedIndex != -1) {
        _rankedPosts[rankedIndex] = _rankedPosts[rankedIndex].copyWith(
          post: _posts[index],
        );
      }
    });
  }

  void _handlePostDeleted(String postId) {
    setState(() {
      _posts.removeWhere((post) => post.id == postId);
      _likedPostIds.remove(postId);
      _rankedPosts = _rankedPosts
          .where((rankedPost) => rankedPost.post.id != postId)
          .toList(growable: false);
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
      _rankedPosts = _buildRankedPosts(_posts);
    });
    if (isFollowing && _suggestionFollowRefreshCounter >= 3) {
      unawaited(_refreshSuggestions(resetSession: true));
    }
  }

  bool get _shouldShowSuggestions =>
      _suggestedUsers.isNotEmpty && _rankedPosts.length >= 3;

  int get _suggestionsInsertIndex => _rankedPosts.length >= 5 ? 4 : 3;

  int get _baseFeedItemCount =>
      _rankedPosts.length + (_shouldShowSuggestions ? 1 : 0);

  int _postIndexForFeedIndex(int feedIndex) {
    if (!_shouldShowSuggestions || feedIndex < _suggestionsInsertIndex) {
      return feedIndex;
    }
    return feedIndex - 1;
  }

  List<RankedPost> _rankInitialPosts(List<SocialPostModel> posts) {
    return rankPosts(
      posts: List<SocialPostModel>.from(posts),
      currentUserId: _auth.currentUser?.uid,
      userCity: _userCity,
      userState: _userState,
      followingIds: _followingIds,
      userInterestTags: _userInterestTags,
    );
  }

  void _mergeRankedPosts(List<SocialPostModel> newPosts) {
    if (newPosts.isEmpty) return;

    final decayedExisting = _rankedPosts
        .map(
          (rankedPost) => rankedPost.copyWith(score: rankedPost.score * 0.98),
        )
        .toList(growable: true);

    final newRankedPosts = rankPosts(
      posts: List<SocialPostModel>.from(newPosts),
      currentUserId: _auth.currentUser?.uid,
      userCity: _userCity,
      userState: _userState,
      followingIds: _followingIds,
      userInterestTags: _userInterestTags,
    );

    decayedExisting.addAll(newRankedPosts);
    sortRankedPostsInPlace(decayedExisting);
    _rankedPosts = decayedExisting;
  }

  List<RankedPost> _buildRankedPosts(List<SocialPostModel> posts) {
    return rankPosts(
      posts: List<SocialPostModel>.from(posts),
      currentUserId: _auth.currentUser?.uid,
      userCity: _userCity,
      userState: _userState,
      followingIds: _followingIds,
      userInterestTags: _userInterestTags,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _auth.currentUser?.uid ?? '';
    final topInset = MediaQuery.paddingOf(context).top;
    const topBarHeight = 76.0;
    final topContentPadding = topInset + topBarHeight + 24;
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
                if (_rankedPosts.isEmpty) {
                  return const _FeedStatusCard(
                    title: 'No posts yet',
                    message:
                        'The home feed will start filling up once the first Pettxo posts are published.',
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
                final rankedPost = _rankedPosts[_postIndexForFeedIndex(index)];
                return SocialPostCard(
                  key: ValueKey(rankedPost.post.id),
                  post: rankedPost.post,
                  rankingReason: rankedPost.reason,
                  currentUserId: currentUserId,
                  initiallyLiked: _likedPostIds.contains(rankedPost.post.id),
                  initiallyFollowing: _followingIds.contains(
                    rankedPost.post.authorId,
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
            top: topInset + 10,
            child: Align(
              child: FractionallySizedBox(
                widthFactor: 0.85,
                child: GlassSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
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
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFE9DD), Color(0xFFFFF3EC)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: IconButton(
                          onPressed: () async {
                            if (!UserRestrictionService.instance
                                .ensureCanUseSocialFeatures(context)) {
                              return;
                            }
                            final created = await Navigator.pushNamed(
                              context,
                              "/create",
                            );
                            if (!context.mounted) return;
                            if (created is SocialPostModel) {
                              await _loadInitialPosts();
                              if (!context.mounted) return;
                              AppFeedback.show(
                                context,
                                message: 'Post published successfully.',
                                tone: AppFeedbackTone.success,
                              );
                            }
                          },
                          icon: const Icon(
                            Icons.add_rounded,
                            color: AppColors.primary,
                            size: 24,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: SvgPicture.asset(
                              'assets/brand/pettxo_logo.svg',
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            "Pettxo",
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.56),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const _NotificationsBellButton(),
                      ),
                    ],
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
    if (_isLoadingFeed || _feedError != null || _rankedPosts.isEmpty) {
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
