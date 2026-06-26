import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../restrictions/data/services/user_restriction_service.dart';
import '../../data/follow_repository.dart';
import '../../data/social_post_repository.dart';
import '../../domain/models/social_post_model.dart';
import 'comment_sheet.dart';
import 'post_image_carousel.dart';

class SocialPostCard extends StatefulWidget {
  final SocialPostModel post;
  final String? rankingReason;
  final String currentUserId;
  final bool initiallyLiked;
  final bool initiallyFollowing;
  final SocialPostRepository repository;
  final FollowRepository followRepository;
  final ValueChanged<SocialPostModel>? onPostUpdated;
  final ValueChanged<String>? onPostDeleted;
  final void Function(String postId, bool isLiked, int newLikeCount)?
  onLikeChanged;
  final void Function(String postId, int newCommentCount)?
  onCommentCountChanged;
  final void Function(String authorId, bool isFollowing)? onFollowChanged;

  const SocialPostCard({
    super.key,
    required this.post,
    this.rankingReason,
    required this.currentUserId,
    required this.initiallyLiked,
    required this.initiallyFollowing,
    required this.repository,
    required this.followRepository,
    this.onPostUpdated,
    this.onPostDeleted,
    this.onLikeChanged,
    this.onCommentCountChanged,
    this.onFollowChanged,
  });

  @override
  State<SocialPostCard> createState() => _SocialPostCardState();
}

class _SocialPostCardState extends State<SocialPostCard> {
  late SocialPostModel _post;
  late bool _isLiked;
  late bool _isFollowing;
  bool _isLiking = false;
  bool _isReporting = false;
  bool _isDeleting = false;
  bool _isFollowActionRunning = false;

  bool get _isOwnPost => widget.currentUserId == _post.authorId;
  bool get _isAdminPost => _post.isAdminPost || _post.authorType == 'admin';

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _isLiked = widget.initiallyLiked;
    _isFollowing = widget.initiallyFollowing;
  }

  @override
  void didUpdateWidget(covariant SocialPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post != widget.post) {
      _post = widget.post;
    }
    if (oldWidget.initiallyLiked != widget.initiallyLiked) {
      _isLiked = widget.initiallyLiked;
    }
    if (oldWidget.initiallyFollowing != widget.initiallyFollowing) {
      _isFollowing = widget.initiallyFollowing;
    }
  }

  Future<void> _handleLikeTap() async {
    if (_isLiking) return;
    if (!UserRestrictionService.instance.ensureCanUseSocialFeatures(context)) {
      return;
    }

    final nextLiked = !_isLiked;
    final nextCount = nextLiked
        ? _post.likeCount + 1
        : (_post.likeCount - 1).clamp(0, 1 << 31).toInt();

    setState(() {
      _isLiking = true;
      _isLiked = nextLiked;
      _post = _post.copyWith(likeCount: nextCount);
    });
    widget.onLikeChanged?.call(_post.id, nextLiked, nextCount);

    try {
      await widget.repository.toggleLike(
        postId: _post.id,
        currentUserId: widget.currentUserId,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLiked = !nextLiked;
        _post = _post.copyWith(likeCount: widget.post.likeCount);
      });
      widget.onLikeChanged?.call(_post.id, !nextLiked, widget.post.likeCount);
      AppFeedback.show(
        context,
        message: 'We could not update your like right now.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isLiking = false);
      }
    }
  }

  Future<void> _showPostMenu() async {
    if (_isDeleting || _isReporting || _isFollowActionRunning) return;
    final action = await showModalBottomSheet<_PostMenuAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isOwnPost)
                  _MenuTile(
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete post',
                    isDestructive: true,
                    enabled: !_isDeleting,
                    onTap: () =>
                        Navigator.pop(context, _PostMenuAction.deletePost),
                  )
                else ...[
                  _MenuTile(
                    icon: Icons.flag_outlined,
                    label: 'Report post',
                    enabled: !_isReporting,
                    onTap: () =>
                        Navigator.pop(context, _PostMenuAction.reportPost),
                  ),
                  if (!_isAdminPost)
                    _MenuTile(
                      icon: _isFollowing
                          ? Icons.person_remove_outlined
                          : Icons.person_add_alt_1_outlined,
                      label: _isFollowing ? 'Unfollow' : 'Follow',
                      enabled: !_isFollowActionRunning,
                      onTap: () =>
                          Navigator.pop(context, _PostMenuAction.toggleFollow),
                    ),
                ],
                _MenuTile(
                  icon: Icons.close_rounded,
                  label: 'Cancel',
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _PostMenuAction.deletePost:
        await _handleDeletePost();
        break;
      case _PostMenuAction.reportPost:
        await _handleReportPost();
        break;
      case _PostMenuAction.toggleFollow:
        await _handleFollowToggle();
        break;
    }
  }

  Future<void> _handleFollowToggle() async {
    if (_isAdminPost || _isOwnPost || _isFollowActionRunning) return;
    if (!UserRestrictionService.instance.ensureCanUseSocialFeatures(context)) {
      return;
    }

    setState(() => _isFollowActionRunning = true);

    try {
      final nextFollowing = await widget.followRepository.toggleFollow(
        followerId: widget.currentUserId,
        followeeId: _post.authorId,
        currentlyFollowing: _isFollowing,
      );

      if (!mounted) return;
      setState(() => _isFollowing = nextFollowing);
      widget.onFollowChanged?.call(_post.authorId, nextFollowing);
      AppFeedback.show(
        context,
        message: nextFollowing ? 'Followed user.' : 'Unfollowed user.',
        tone: AppFeedbackTone.success,
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: error.toString().replaceFirst('Exception: ', ''),
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isFollowActionRunning = false);
      }
    }
  }

  Future<void> _handleDeletePost() async {
    if (_isDeleting) return;
    if (!UserRestrictionService.instance.canPerformSocialAction(
      context,
      allowWhenSocialRestricted: true,
    )) {
      return;
    }
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete post?'),
          content: const Text('This will remove the post from the feed.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Color(0xFFD64B4B)),
              ),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await widget.repository.softDeletePost(
        postId: _post.id,
        currentUserId: widget.currentUserId,
      );
      widget.onPostDeleted?.call(_post.id);
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'Post deleted.',
        tone: AppFeedbackTone.success,
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: error.toString().replaceFirst('Exception: ', ''),
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  Future<void> _handleReportPost() async {
    if (_isReporting) return;
    if (!UserRestrictionService.instance.ensureCanUseSocialFeatures(context)) {
      return;
    }
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _reportReasons
                  .map((reason) {
                    return _MenuTile(
                      icon: Icons.outlined_flag_rounded,
                      label: reason,
                      enabled: !_isReporting,
                      onTap: () => Navigator.pop(context, reason),
                    );
                  })
                  .toList(growable: false),
            ),
          ),
        );
      },
    );

    if (!mounted || reason == null) return;
    setState(() => _isReporting = true);

    try {
      final movedToPending = await widget.repository.reportPost(
        postId: _post.id,
        currentUserId: widget.currentUserId,
        reason: reason,
      );
      setState(() {
        _post = _post.copyWith(
          reportCount: _post.reportCount + 1,
          lastReportedAt: Timestamp.now(),
          moderationStatus: movedToPending ? 'pending' : _post.moderationStatus,
        );
      });
      widget.onPostUpdated?.call(_post);
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: movedToPending
            ? 'This content is under review.'
            : 'Post reported successfully.',
        tone: AppFeedbackTone.success,
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: error.toString().replaceFirst('Exception: ', ''),
        tone: error.toString().contains('already reported')
            ? AppFeedbackTone.info
            : AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isReporting = false);
      }
    }
  }

  Future<void> _handleShareTap() async {
    final shareText = _buildShareText();
    final box = context.findRenderObject() as RenderBox?;

    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          title: 'Pettxo post',
          subject: 'Check out this Pettxo post',
          text: shareText,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );

      if (!mounted || result.status != ShareResultStatus.success) return;

      final previousShareCount = _post.shareCount;
      final nextShareCount = previousShareCount + 1;

      setState(() {
        _post = _post.copyWith(shareCount: nextShareCount);
      });
      widget.onPostUpdated?.call(_post);

      try {
        final persistedShareCount = await widget.repository.incrementShareCount(
          postId: _post.id,
        );
        if (!mounted) return;
        setState(() {
          _post = _post.copyWith(shareCount: persistedShareCount);
        });
        widget.onPostUpdated?.call(_post);
      } catch (_) {
        // Sharing itself already succeeded, so do not interrupt the user flow
        // if analytics/counter persistence is unavailable.
      }
    } catch (error) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: error.toString().replaceFirst('Exception: ', ''),
        tone: AppFeedbackTone.error,
      );
    }
  }

  String _buildShareText() {
    final lines = <String>[
      'Check out this post on Pettxo',
      if (_post.authorDisplayName.trim().isNotEmpty)
        'By ${_post.authorDisplayName.trim()}',
    ];

    final caption = _post.caption.trim();
    if (caption.isNotEmpty) {
      lines.add('');
      lines.add(caption);
    }

    if (_post.hashtags.isNotEmpty) {
      lines.add('');
      lines.add(_post.hashtags.map((tag) => '#$tag').join(' '));
    }

    final leadImageUrl = _post.imageUrls.isEmpty ? '' : _post.imageUrls.first;
    if (leadImageUrl.isNotEmpty) {
      lines.add('');
      lines.add(leadImageUrl);
    }

    return lines.join('\n');
  }

  Future<void> _openComments() async {
    await CommentSheet.show(
      context,
      post: _post,
      currentUserId: widget.currentUserId,
      repository: widget.repository,
      onCommentCountChanged: (newCommentCount) {
        if (!mounted) return;
        setState(() {
          _post = _post.copyWith(commentCount: newCommentCount);
        });
        widget.onCommentCountChanged?.call(_post.id, newCommentCount);
        widget.onPostUpdated?.call(_post);
      },
    );
  }

  Future<void> _openAuthorProfile() async {
    final authorId = _post.authorId.trim();
    if (authorId.isEmpty || _isAdminPost) return;

    if (authorId == widget.currentUserId) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfileScreen(userId: authorId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initials = _post.authorDisplayName.trim().isEmpty
        ? 'P'
        : _post.authorDisplayName.trim()[0].toUpperCase();
    final hasUsername = _post.authorUsername.isNotEmpty;
    final hasLocation = _post.locationLabel.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _openAuthorProfile,
                    borderRadius: BorderRadius.circular(22),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          _ProfileAvatar(
                            imageUrl: _post.authorPhotoUrl,
                            initials: initials,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _isAdminPost
                                            ? (_post.authorDisplayName.isEmpty
                                                  ? 'Pettxo'
                                                  : _post.authorDisplayName)
                                            : _post.authorDisplayName,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textDark,
                                        ),
                                      ),
                                    ),
                                    if (_post.authorCategoryLabel.isNotEmpty)
                                      Container(
                                        margin: const EdgeInsets.only(left: 8),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF2EA),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          _isAdminPost
                                              ? 'Verified'
                                              : _post.authorCategoryLabel,
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    if (_isAdminPost) ...[
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.verified_rounded,
                                        size: 18,
                                        color: AppColors.primary,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (hasUsername)
                                      Text(
                                        _post.authorUsername,
                                        style: const TextStyle(
                                          color: AppColors.textGrey,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    if (hasUsername && hasLocation)
                                      const Text(
                                        '•',
                                        style: TextStyle(
                                          color: AppColors.textGrey,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    if (hasLocation)
                                      Text(
                                        _post.locationLabel,
                                        style: const TextStyle(
                                          color: AppColors.textGrey,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _showPostMenu,
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ],
            ),
          ),
          PostImageCarousel(
            imageUrls: _post.imageUrls,
            thumbnailUrls: _post.thumbnailUrls,
            aspectRatio: _post.aspectRatioValue,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                _ActionPill(
                  icon: _isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  iconColor: _isLiked
                      ? const Color(0xFFE45858)
                      : AppColors.textDark,
                  label: '${_post.likeCount}',
                  onTap: _isLiking ? null : _handleLikeTap,
                  enabled: !_isLiking,
                ),
                const SizedBox(width: 12),
                _ActionPill(
                  icon: Icons.mode_comment_outlined,
                  label: '${_post.commentCount}',
                  onTap: _openComments,
                ),
                const SizedBox(width: 12),
                _ActionPill(
                  icon: Icons.share_outlined,
                  label: '${_post.shareCount}',
                  onTap: _handleShareTap,
                ),
              ],
            ),
          ),
          if (_post.hashtags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _post.hashtags
                    .map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7F1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '#$tag',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
          if (_post.moderationStatus == 'pending')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'This content is under review.',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          if (_post.caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 15,
                    height: 1.45,
                  ),
                  children: [
                    if (_post.authorUsername.isNotEmpty)
                      TextSpan(
                        text: '${_post.authorUsername} ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    TextSpan(text: _post.caption),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
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
          width: 40,
          height: 40,
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (context, imageUrl) => const CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.background,
            ),
            errorWidget: (context, imageUrl, error) => CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.background,
              child: Text(
                initials,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 20,
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

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  const _ActionPill({
    required this.icon,
    required this.label,
    this.iconColor,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFFFFF8F3) : const Color(0xFFF3EFEB),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: enabled
                  ? (iconColor ?? AppColors.textDark)
                  : AppColors.textGrey,
              size: 19,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: enabled ? AppColors.textDark : AppColors.textGrey,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDestructive;
  final bool enabled;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = isDestructive
        ? const Color(0xFFD64B4B)
        : AppColors.textDark;
    final color = enabled ? activeColor : AppColors.textGrey;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
      onTap: enabled ? onTap : null,
    );
  }
}

enum _PostMenuAction { deletePost, reportPost, toggleFollow }

const List<String> _reportReasons = <String>[
  'Spam',
  'Inappropriate content',
  'Harassment',
  'Other',
];
