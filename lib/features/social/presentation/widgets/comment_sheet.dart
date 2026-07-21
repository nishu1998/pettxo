import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_confirmation_dialog.dart';
import '../../../../core/widgets/app_user_avatar.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_glass_overlay.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../restrictions/data/services/user_restriction_service.dart';
import '../../data/social_post_repository.dart';
import '../../domain/models/comment_model.dart';
import '../../domain/models/social_post_model.dart';
import 'live_author_resolver.dart';

class CommentSheet extends StatefulWidget {
  final SocialPostModel post;
  final String currentUserId;
  final SocialPostRepository repository;
  final ValueChanged<int>? onCommentCountChanged;

  const CommentSheet({
    super.key,
    required this.post,
    required this.currentUserId,
    required this.repository,
    this.onCommentCountChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required SocialPostModel post,
    required String currentUserId,
    required SocialPostRepository repository,
    ValueChanged<int>? onCommentCountChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return CommentSheet(
          post: post,
          currentUserId: currentUserId,
          repository: repository,
          onCommentCountChanged: onCommentCountChanged,
        );
      },
    );
  }

  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<CommentModel> _comments = <CommentModel>[];

  late int _commentCount;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isSending = false;
  bool _isMutatingComment = false;
  String? _error;
  DocumentSnapshot<Map<String, dynamic>>? _lastDocument;

  @override
  void initState() {
    super.initState();
    _commentCount = widget.post.commentCount;
    _commentController.addListener(_handleComposerChanged);
    _scrollController.addListener(_handleScroll);
    _loadInitialComments();
  }

  @override
  void dispose() {
    _commentController.removeListener(_handleComposerChanged);
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleComposerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadInitialComments() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _hasMore = true;
      _lastDocument = null;
    });

    try {
      final page = await widget.repository.fetchComments(
        postId: widget.post.id,
      );
      if (!mounted) return;
      setState(() {
        _comments
          ..clear()
          ..addAll(page.comments);
        _lastDocument = page.lastDocument;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMoreComments() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    try {
      final page = await widget.repository.fetchComments(
        postId: widget.post.id,
        startAfter: _lastDocument,
      );
      if (!mounted) return;
      setState(() {
        _comments.addAll(page.comments);
        _lastDocument = page.lastDocument;
        _hasMore = page.hasMore && page.comments.isNotEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'We could not load more comments right now.',
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
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadMoreComments();
    }
  }

  Future<void> _sendComment() async {
    if (_isSending) return;
    if (!UserRestrictionService.instance.ensureCanUseSocialFeatures(context)) {
      return;
    }
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    try {
      final comment = await widget.repository.addComment(
        postId: widget.post.id,
        currentUserId: widget.currentUserId,
        text: text,
      );
      if (!mounted) return;
      setState(() {
        _comments.insert(0, comment);
        _commentCount += 1;
        _commentController.clear();
      });
      widget.onCommentCountChanged?.call(_commentCount);
    } catch (error) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: error.toString().replaceFirst('Exception: ', ''),
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _showCommentActions(CommentModel comment) async {
    if (_isMutatingComment) return;
    final isOwnComment = comment.authorId == widget.currentUserId;
    final action = await showModalBottomSheet<_CommentMenuAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AppGlassBottomSheetFrame(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isOwnComment)
                _CommentMenuTile(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete comment',
                  isDestructive: true,
                  onTap: () =>
                      Navigator.pop(context, _CommentMenuAction.deleteComment),
                )
              else
                _CommentMenuTile(
                  icon: Icons.flag_outlined,
                  label: 'Report comment',
                  onTap: () =>
                      Navigator.pop(context, _CommentMenuAction.reportComment),
                ),
              _CommentMenuTile(
                icon: Icons.close_rounded,
                label: 'Cancel',
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    switch (action) {
      case _CommentMenuAction.deleteComment:
        await _deleteComment(comment);
        break;
      case _CommentMenuAction.reportComment:
        await _reportComment(comment);
        break;
    }
  }

  Future<void> _deleteComment(CommentModel comment) async {
    if (_isMutatingComment) return;
    if (!UserRestrictionService.instance.canPerformSocialAction(
      context,
      allowWhenSocialRestricted: true,
    )) {
      return;
    }
    final shouldDelete = await AppConfirmationDialog.show(
      context: context,
      title: 'Delete comment?',
      message: 'This will remove your comment from the post.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (shouldDelete != true || !mounted) return;

    setState(() => _isMutatingComment = true);
    try {
      await widget.repository.softDeleteComment(
        postId: widget.post.id,
        commentId: comment.id,
        currentUserId: widget.currentUserId,
      );
      if (!mounted) return;
      setState(() {
        _comments.removeWhere((entry) => entry.id == comment.id);
        _commentCount = (_commentCount - 1).clamp(0, 1 << 31).toInt();
      });
      widget.onCommentCountChanged?.call(_commentCount);
      AppFeedback.show(
        context,
        message: 'Comment deleted.',
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
        setState(() => _isMutatingComment = false);
      }
    }
  }

  Future<void> _reportComment(CommentModel comment) async {
    if (_isMutatingComment) return;
    if (!UserRestrictionService.instance.ensureCanUseSocialFeatures(context)) {
      return;
    }
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AppGlassBottomSheetFrame(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _commentReportReasons
                .map((reason) {
                  return _CommentMenuTile(
                    icon: Icons.outlined_flag_rounded,
                    label: reason,
                    onTap: () => Navigator.pop(context, reason),
                  );
                })
                .toList(growable: false),
          ),
        );
      },
    );
    if (!mounted || reason == null) return;

    setState(() => _isMutatingComment = true);
    try {
      final movedToPending = await widget.repository.reportComment(
        postId: widget.post.id,
        commentId: comment.id,
        currentUserId: widget.currentUserId,
        reason: reason,
      );
      if (!mounted) return;
      if (movedToPending) {
        setState(() {
          final index = _comments.indexWhere((entry) => entry.id == comment.id);
          if (index != -1) {
            _comments[index] = _comments[index].copyWith(
              reportCount: _comments[index].reportCount + 1,
              moderationStatus: 'pending',
              lastReportedAt: Timestamp.now(),
            );
          }
        });
      }
      AppFeedback.show(
        context,
        message: movedToPending
            ? 'This content is under review.'
            : 'Comment reported successfully.',
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
        setState(() => _isMutatingComment = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sheetSurface = isDark
        ? theme.colorScheme.surface.withValues(alpha: 0.66)
        : Colors.white.withValues(alpha: 0.7);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.72);
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.28)
        : Colors.black.withValues(alpha: 0.1);
    final foregroundColor = theme.colorScheme.onSurface;
    final mutedColor = foregroundColor.withValues(alpha: 0.58);
    final sheetHeight = math
        .min(
          screenSize.height * 0.82,
          screenSize.height - viewInsets.bottom - 24,
        )
        .clamp(320.0, screenSize.height);

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 34,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: sheetHeight,
                  decoration: BoxDecoration(
                    color: sheetSurface,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: mutedColor.withValues(alpha: 0.32),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 18, 18, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Comments',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: foregroundColor,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            Semantics(
                              button: true,
                              label: 'Close comments',
                              child: Material(
                                color: Colors.white.withValues(
                                  alpha: isDark ? 0.08 : 0.36,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => Navigator.pop(context),
                                  child: SizedBox(
                                    width: 42,
                                    height: 42,
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: foregroundColor.withValues(
                                        alpha: 0.76,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(child: _buildCommentsList()),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _commentController,
                                minLines: 1,
                                maxLines: 5,
                                maxLength: 500,
                                style: TextStyle(
                                  color: foregroundColor,
                                  fontWeight: FontWeight.w500,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Write a comment...',
                                  hintStyle: TextStyle(color: mutedColor),
                                  counterText: '',
                                  filled: true,
                                  fillColor: isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.white.withValues(alpha: 0.48),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 14,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.72,
                                      ),
                                      width: 1.4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 50,
                              height: 50,
                              child: FilledButton(
                                onPressed:
                                    _commentController.text.trim().isEmpty ||
                                        _isSending
                                    ? null
                                    : _sendComment,
                                style: FilledButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  backgroundColor: AppColors.primary,
                                  disabledBackgroundColor: isDark
                                      ? Colors.white.withValues(alpha: 0.1)
                                      : Colors.black.withValues(alpha: 0.08),
                                  foregroundColor: Colors.white,
                                  disabledForegroundColor: mutedColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(17),
                                  ),
                                ),
                                child: _isSending
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.send_rounded, size: 21),
                              ),
                            ),
                          ],
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
    );
  }

  Widget _buildCommentsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 220),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _loadInitialComments,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_comments.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No comments yet. Be the first to comment.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textGrey,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
      itemCount: _comments.length + (_hasMore || _isLoadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 20),
      itemBuilder: (context, index) {
        if (index >= _comments.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: _isLoadingMore
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      onPressed: _loadMoreComments,
                      child: const Text('Load more comments'),
                    ),
            ),
          );
        }
        final comment = _comments[index];
        return GestureDetector(
          onLongPress: () => _showCommentActions(comment),
          child: _CommentTile(
            comment: comment,
            currentUserId: widget.currentUserId,
          ),
        );
      },
    );
  }
}

class _CommentTile extends StatelessWidget {
  final CommentModel comment;
  final String currentUserId;

  const _CommentTile({required this.comment, required this.currentUserId});

  void _openAuthorProfile(BuildContext context) {
    final authorId = comment.authorId.trim();
    if (authorId.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => authorId == currentUserId.trim()
            ? const ProfileScreen()
            : ProfileScreen(userId: authorId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final createdAt = comment.createdAt?.toDate();
    final timestamp = createdAt == null ? '' : _formatRelativeTime(createdAt);
    final isUnderReview = comment.moderationStatus == 'pending';
    final isRemoved = comment.visibilityStatus == 'deleted';
    final bodyText = isUnderReview
        ? 'This content is under review.'
        : (isRemoved ? 'Comment removed.' : comment.text);

    return LiveAuthorResolver(
      authorId: comment.authorId,
      fallbackName: comment.authorDisplayName,
      fallbackUsername: comment.authorUsername,
      fallbackImageUrl: comment.authorPhotoUrl,
      builder: (context, author) {
        final theme = Theme.of(context);
        final foregroundColor = theme.colorScheme.onSurface;
        final mutedColor = foregroundColor.withValues(alpha: 0.58);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _openAuthorProfile(context),
              child: _CommentAvatar(
                imageUrl: author.imageUrl,
                initials: author.initials,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => _openAuthorProfile(context),
                      child: Text(
                        author.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: foregroundColor,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                    ),
                    if (author.username.isNotEmpty || timestamp.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          if (author.username.isNotEmpty)
                            Text(
                              author.username,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: mutedColor,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                            ),
                          if (timestamp.isNotEmpty)
                            Text(
                              timestamp,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: mutedColor,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 7),
                    Text(
                      bodyText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: foregroundColor.withValues(alpha: 0.88),
                        height: 1.38,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CommentAvatar extends StatelessWidget {
  final String imageUrl;
  final String initials;

  const _CommentAvatar({required this.imageUrl, required this.initials});

  @override
  Widget build(BuildContext context) {
    return AppUserAvatar(
      size: 44,
      imageUrl: imageUrl,
      fallback: _fallbackAvatar(context),
    );
  }

  Widget _fallbackAvatar(BuildContext context) {
    final theme = Theme.of(context);
    return AppUserAvatarFallback(
      initials: initials,
      backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.72),
      textStyle: TextStyle(
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _CommentMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _CommentMenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? const Color(0xFFD64B4B) : AppColors.textDark;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
      onTap: onTap,
    );
  }
}

String _formatRelativeTime(DateTime time) {
  final now = DateTime.now();
  final difference = now.difference(time);
  if (difference.inMinutes < 1) return 'now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m';
  if (difference.inHours < 24) return '${difference.inHours}h';
  if (difference.inDays < 7) return '${difference.inDays}d';
  return '${time.day}/${time.month}/${time.year}';
}

enum _CommentMenuAction { deleteComment, reportComment }

const List<String> _commentReportReasons = <String>[
  'Spam',
  'Inappropriate content',
  'Harassment',
  'Other',
];
