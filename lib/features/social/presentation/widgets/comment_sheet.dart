import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../restrictions/data/services/user_restriction_service.dart';
import '../../data/social_post_repository.dart';
import '../../domain/models/comment_model.dart';
import '../../domain/models/social_post_model.dart';

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
      final page = await widget.repository.fetchComments(postId: widget.post.id);
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
                if (isOwnComment)
                  _CommentMenuTile(
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete comment',
                    isDestructive: true,
                    onTap: () => Navigator.pop(
                      context,
                      _CommentMenuAction.deleteComment,
                    ),
                  )
                else
                  _CommentMenuTile(
                    icon: Icons.flag_outlined,
                    label: 'Report comment',
                    onTap: () => Navigator.pop(
                      context,
                      _CommentMenuAction.reportComment,
                    ),
                  ),
                _CommentMenuTile(
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
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete comment?'),
          content: const Text('This will remove your comment from the post.'),
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
              children: _commentReportReasons.map((reason) {
                return _CommentMenuTile(
                  icon: Icons.outlined_flag_rounded,
                  label: reason,
                  onTap: () => Navigator.pop(context, reason),
                );
              }).toList(growable: false),
            ),
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
    final sheetHeight = math.min(
      screenSize.height * 0.82,
      screenSize.height - viewInsets.bottom - 24,
    ).clamp(320.0, screenSize.height);

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: Container(
          height: sheetHeight,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFCF8F5),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.textGrey.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Comments',
                        style: TextStyle(
                          color: AppColors.textDark,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _buildCommentsList(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 500,
                        decoration: InputDecoration(
                          hintText: 'Write a comment...',
                          counterText: '',
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _commentController.text.trim().isEmpty || _isSending
                            ? null
                            : _sendComment,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
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
                            : const Icon(Icons.send_rounded),
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      itemCount: _comments.length + (_hasMore || _isLoadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
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
          child: _CommentTile(comment: comment),
        );
      },
    );
  }
}

class _CommentTile extends StatelessWidget {
  final CommentModel comment;

  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) {
    final createdAt = comment.createdAt?.toDate();
    final timestamp = createdAt == null ? '' : _formatRelativeTime(createdAt);
    final initials = comment.authorDisplayName.trim().isEmpty
        ? 'P'
        : comment.authorDisplayName.trim()[0].toUpperCase();
    final isUnderReview = comment.moderationStatus == 'pending';
    final isRemoved = comment.visibilityStatus == 'deleted';
    final bodyText = isUnderReview
        ? 'This content is under review.'
        : (isRemoved ? 'Comment removed.' : comment.text);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommentAvatar(
            imageUrl: comment.authorPhotoUrl,
            initials: initials,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      comment.authorDisplayName,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (comment.authorUsername.isNotEmpty)
                      Text(
                        comment.authorUsername,
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (timestamp.isNotEmpty)
                      Text(
                        timestamp,
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  bodyText,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentAvatar extends StatelessWidget {
  final String imageUrl;
  final String initials;

  const _CommentAvatar({
    required this.imageUrl,
    required this.initials,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isNotEmpty) {
      return ClipOval(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            errorWidget: (context, imageUrl, error) => _fallbackAvatar(),
            placeholder: (context, imageUrl) => _fallbackAvatar(),
          ),
        ),
      );
    }

    return _fallbackAvatar();
  }

  Widget _fallbackAvatar() {
    return CircleAvatar(
      radius: 18,
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
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
        ),
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
