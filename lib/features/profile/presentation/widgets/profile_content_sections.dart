import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../domain/models/profile_service_listing.dart';
import '../screens/service_detail_screen.dart';
import '../../../social/data/follow_repository.dart';
import '../../../social/data/social_post_repository.dart';
import '../../../social/domain/models/social_post_model.dart';
import '../../../social/presentation/widgets/social_post_card.dart';

class ProfileSectionTabs extends StatelessWidget {
  final int selectedIndex;
  final bool showServices;
  final int serviceCount;
  final ValueChanged<int> onChanged;

  const ProfileSectionTabs({
    super.key,
    required this.selectedIndex,
    required this.showServices,
    required this.serviceCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ProfileTabButton(
              label: 'Posts',
              isActive: selectedIndex == 0,
              onTap: () => onChanged(0),
            ),
          ),
          if (showServices)
            Expanded(
              child: _ProfileTabButton(
                label: 'Services ($serviceCount)',
                isActive: selectedIndex == 1,
                onTap: () => onChanged(1),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileTabButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ProfileTabButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isActive ? AppColors.textDark : AppColors.textGrey,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class ProfilePostsSection extends StatelessWidget {
  final List<SocialPostModel> posts;
  final bool canCreatePost;
  final String currentUserId;

  const ProfilePostsSection({
    super.key,
    required this.posts,
    required this.canCreatePost,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty && !canCreatePost) {
      return const EmptyProfileSection(
        icon: Icons.grid_view_rounded,
        title: 'No posts yet',
        message:
            'Share your first pet story, service update, or happy moment so followers have something to discover here.',
      );
    }

    final itemCount = posts.length + (canCreatePost ? 1 : 0);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.96,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        const createTileIndex = 0;
        if (canCreatePost && index == createTileIndex) {
          return const _ProfileNewPostTile();
        }

        final postIndex = canCreatePost && index > createTileIndex
            ? index - 1
            : index;
        final post = posts[postIndex];
        return _ProfilePostGridItem(
          post: post,
          posts: posts,
          currentUserId: currentUserId,
        );
      },
    );
  }
}

class _ProfilePostGridItem extends StatelessWidget {
  final SocialPostModel post;
  final List<SocialPostModel> posts;
  final String currentUserId;

  const _ProfilePostGridItem({
    required this.post,
    required this.posts,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final initialIndex = posts.indexWhere((item) => item.id == post.id);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _ProfilePostDetailScreen(
                posts: posts,
                initialIndex: initialIndex < 0 ? 0 : initialIndex,
                currentUserId: currentUserId,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(26),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(26),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (post.imageUrls.isEmpty)
                        Container(
                          decoration: const BoxDecoration(
                            gradient: AppColors.brandGradientDiagonal,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.pets_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        )
                      else
                        Image.network(
                          post.imageUrls.first,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              decoration: const BoxDecoration(
                                gradient: AppColors.brandGradientDiagonal,
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.pets_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                            );
                          },
                        ),
                      if (post.likeCount > 0)
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.44),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.favorite_rounded,
                                  color: Colors.white,
                                  size: 13,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${post.likeCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                child: Row(
                  children: [
                    const Spacer(),
                    Text(
                      _formatPostAge(post.createdAtEpoch),
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
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

class _ProfileNewPostTile extends StatelessWidget {
  const _ProfileNewPostTile();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, '/create'),
        borderRadius: BorderRadius.circular(26),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(26),
          ),
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: Colors.black.withValues(alpha: 0.35),
              radius: 26,
            ),
            child: const Center(
              child: Text(
                'New post',
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfilePostDetailScreen extends StatelessWidget {
  final List<SocialPostModel> posts;
  final int initialIndex;
  final String currentUserId;

  const _ProfilePostDetailScreen({
    required this.posts,
    required this.initialIndex,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    return _ProfilePostFeedScreen(
      posts: posts,
      initialIndex: initialIndex,
      currentUserId: currentUserId,
    );
  }
}

class _ProfilePostFeedScreen extends StatefulWidget {
  final List<SocialPostModel> posts;
  final int initialIndex;
  final String currentUserId;

  const _ProfilePostFeedScreen({
    required this.posts,
    required this.initialIndex,
    required this.currentUserId,
  });

  @override
  State<_ProfilePostFeedScreen> createState() => _ProfilePostFeedScreenState();
}

class _ProfilePostFeedScreenState extends State<_ProfilePostFeedScreen> {
  final SocialPostRepository _socialPostRepository = SocialPostRepository();
  final FollowRepository _followRepository = FollowRepository();
  late final ScrollController _scrollController;
  late List<SocialPostModel> _posts;
  final Map<String, GlobalKey> _postKeys = <String, GlobalKey>{};
  Set<String> _likedPostIds = <String>{};
  bool _isFollowingAuthor = false;

  @override
  void initState() {
    super.initState();
    _posts = List<SocialPostModel>.from(widget.posts);
    _scrollController = ScrollController();
    _loadPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToInitialPost();
    });
  }

  Future<void> _loadPreferences() async {
    final currentUserId = widget.currentUserId.trim();
    if (currentUserId.isEmpty || _posts.isEmpty) {
      return;
    }

    try {
      final postIds = _posts.map((post) => post.id).toList(growable: false);
      final authorId = _posts.first.authorId;
      final results = await Future.wait<dynamic>([
        _socialPostRepository.fetchCurrentUserLikedPostIds(postIds),
        if (authorId.isNotEmpty && authorId != currentUserId)
          _followRepository.isFollowing(
            followerId: currentUserId,
            followeeId: authorId,
          )
        else
          Future<bool>.value(false),
      ]);
      if (!mounted) return;
      setState(() {
        _likedPostIds = results[0] as Set<String>;
        _isFollowingAuthor = results[1] as bool;
      });
    } catch (_) {}
  }

  void _scrollToInitialPost() {
    if (_posts.isEmpty ||
        widget.initialIndex < 0 ||
        widget.initialIndex >= _posts.length) {
      return;
    }
    final targetPost = _posts[widget.initialIndex];
    final targetKey = _postKeys[targetPost.id];
    final targetContext = targetKey?.currentContext;
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.08,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  void _handlePostUpdated(SocialPostModel updatedPost) {
    final index = _posts.indexWhere((post) => post.id == updatedPost.id);
    if (index < 0) return;
    setState(() {
      _posts[index] = updatedPost;
    });
  }

  void _handlePostDeleted(String postId) {
    final nextPosts = _posts
        .where((post) => post.id != postId)
        .toList(growable: false);
    if (!mounted) return;
    if (nextPosts.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _posts = nextPosts;
      _likedPostIds.remove(postId);
      _postKeys.remove(postId);
    });
  }

  void _handleLikeChanged(String postId, bool isLiked, int newLikeCount) {
    final index = _posts.indexWhere((post) => post.id == postId);
    if (index < 0) return;
    setState(() {
      if (isLiked) {
        _likedPostIds.add(postId);
      } else {
        _likedPostIds.remove(postId);
      }
      _posts[index] = _posts[index].copyWith(likeCount: newLikeCount);
    });
  }

  void _handleCommentCountChanged(String postId, int newCommentCount) {
    final index = _posts.indexWhere((post) => post.id == postId);
    if (index < 0) return;
    setState(() {
      _posts[index] = _posts[index].copyWith(commentCount: newCommentCount);
    });
  }

  void _handleFollowChanged(String authorId, bool isFollowing) {
    if (_posts.isEmpty || _posts.first.authorId != authorId) return;
    setState(() => _isFollowingAuthor = isFollowing);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textDark,
      ),
      body: _posts.isEmpty
          ? const SizedBox.shrink()
          : ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              itemCount: _posts.length,
              separatorBuilder: (context, index) => const SizedBox(height: 18),
              itemBuilder: (context, index) {
                final post = _posts[index];
                final key = _postKeys.putIfAbsent(post.id, GlobalKey.new);
                return KeyedSubtree(
                  key: key,
                  child: SocialPostCard(
                    key: ValueKey(post.id),
                    post: post,
                    currentUserId: widget.currentUserId,
                    initiallyLiked: _likedPostIds.contains(post.id),
                    initiallyFollowing: _isFollowingAuthor,
                    repository: _socialPostRepository,
                    followRepository: _followRepository,
                    onPostUpdated: _handlePostUpdated,
                    onPostDeleted: _handlePostDeleted,
                    onLikeChanged: _handleLikeChanged,
                    onCommentCountChanged: _handleCommentCountChanged,
                    onFollowChanged: _handleFollowChanged,
                  ),
                );
              },
            ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    const dashWidth = 14.0;
    const dashGap = 10.0;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final nextDistance = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, nextDistance.clamp(0, metric.length)),
          paint,
        );
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}

String _formatPostAge(int createdAtEpoch) {
  if (createdAtEpoch <= 0) return 'Now';

  final createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtEpoch);
  final difference = DateTime.now().difference(createdAt);

  if (difference.inMinutes < 1) return 'Now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';

  final weeks = (difference.inDays / 7).floor();
  if (weeks < 5) return '${weeks}w ago';

  final months = (difference.inDays / 30).floor();
  if (months < 12) return '${months}mo ago';

  final years = (difference.inDays / 365).floor();
  return '${years}y ago';
}

class ProfileServicesSection extends StatelessWidget {
  final List<ProfileServiceListing> services;
  final bool canManage;
  final VoidCallback onAdd;
  final VoidCallback onManage;

  const ProfileServicesSection({
    super.key,
    required this.services,
    required this.canManage,
    required this.onAdd,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canManage) ...[
          Row(
            children: [
              Expanded(
                child: GradientButton(
                  label: 'Add Service',
                  icon: Icons.add_rounded,
                  onPressed: onAdd,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SecondaryButton(
                  label: 'Manage',
                  icon: Icons.tune_rounded,
                  onPressed: onManage,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (services.isEmpty)
          const EmptyProfileSection(
            icon: Icons.design_services_outlined,
            title: 'No services listed',
            message:
                'Add your first service to start showing visitors what you offer and encourage bookings from your profile.',
          )
        else
          ...services.map((service) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _ProfileServiceCard(service: service),
            );
          }),
      ],
    );
  }
}

class _ProfileServiceCard extends StatelessWidget {
  final ProfileServiceListing service;

  const _ProfileServiceCard({required this.service});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ServiceDetailScreen(service: service),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(26),
                ),
                child: SizedBox(
                  width: 116,
                  height: 158,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (service.imageUrl.isEmpty)
                        _ServiceImageFallback(service: service)
                      else if (service.imageUrl.startsWith('http'))
                        Image.network(
                          service.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _ServiceImageFallback(service: service);
                          },
                        )
                      else
                        Image.file(
                          File(service.imageUrl),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _ServiceImageFallback(service: service);
                          },
                        ),
                      if (service.isPaused)
                        Container(color: Colors.black.withValues(alpha: 0.36)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              service.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textDark,
                              ),
                            ),
                          ),
                          if (service.isSponsorActive) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF2EA),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Sponsored',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                          if (service.isPaused) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.textGrey.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Paused',
                                style: TextStyle(
                                  color: AppColors.textGrey,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        service.serviceType,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        service.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          height: 1.35,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        service.reviewSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: service.hasReviews
                              ? const Color(0xFF9A3412)
                              : AppColors.textGrey,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          service.rate,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.textDark,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            color: AppColors.primary,
                            size: 16,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: GestureDetector(
                              onTap:
                                  service.latitude == 0 &&
                                      service.longitude == 0
                                  ? null
                                  : () async {
                                      final uri = Uri.parse(
                                        'https://www.google.com/maps/search/?api=1&query=${service.latitude},${service.longitude}',
                                      );
                                      await launchUrl(
                                        uri,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    },
                              child: Text(
                                service.location.isEmpty
                                    ? 'Location shared after booking'
                                    : service.location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.open_in_new_rounded,
                            color: AppColors.primary,
                            size: 14,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            color: AppColors.textGrey,
                            size: 16,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              service.duration.isEmpty
                                  ? service.availability
                                  : '${service.duration} - ${service.petSize}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textGrey,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceImageFallback extends StatelessWidget {
  final ProfileServiceListing service;

  const _ServiceImageFallback({required this.service});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.brandGradientDiagonal,
      ),
      child: Center(
        child: service.photoPaths.isNotEmpty
            ? const Icon(
                Icons.photo_library_rounded,
                color: Colors.white,
                size: 36,
              )
            : const Icon(Icons.pets_rounded, color: Colors.white, size: 36),
      ),
    );
  }
}

class ManageServiceTile extends StatelessWidget {
  final ProfileServiceListing service;
  final VoidCallback onPause;
  final VoidCallback onDelete;

  const ManageServiceTile({
    super.key,
    required this.service,
    required this.onPause,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCFA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  service.isPaused ? 'Paused' : 'Active',
                  style: TextStyle(
                    color: service.isPaused
                        ? AppColors.textGrey
                        : AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onPause,
            child: Text(service.isPaused ? 'Resume' : 'Pause'),
          ),
          IconButton(
            onPressed: onDelete,
            color: Colors.redAccent,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class EmptyProfileSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const EmptyProfileSection({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary, size: 34),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textGrey,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
