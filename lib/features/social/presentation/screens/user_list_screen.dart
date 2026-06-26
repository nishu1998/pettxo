import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../../../restrictions/data/services/user_restriction_service.dart';
import '../../data/follow_repository.dart';

typedef FollowIdsPageLoader =
    Future<FollowIdsPage> Function(DocumentSnapshot<Map<String, dynamic>>? lastDoc);

enum UserListKind { followers, following }

class UserListScreen extends StatefulWidget {
  final String title;
  final String emptyMessage;
  final UserListKind listKind;
  final FollowIdsPageLoader loader;

  const UserListScreen({
    super.key,
    required this.title,
    required this.emptyMessage,
    required this.listKind,
    required this.loader,
  });

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  final ProfileRepository _profileRepository = ProfileRepository();
  final FollowRepository _followRepository = FollowRepository();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final List<String> _userIds = <String>[];
  final Map<String, UserProfile> _profileCache = <String, UserProfile>{};
  final Set<String> _followingIds = <String>{};

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isRefreshingFollowState = true;
  bool _hasMore = true;
  String? _error;
  DocumentSnapshot<Map<String, dynamic>>? _lastDocument;

  String get _currentUserId => _auth.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _primeFollowingState();
    _loadInitialPage();
  }

  Future<void> _primeFollowingState() async {
    try {
      final followingIds = await _followRepository.fetchFollowingIds(
        _currentUserId,
      );
      if (!mounted) return;
      setState(() {
        _followingIds
          ..clear()
          ..addAll(followingIds);
      });
    } finally {
      if (mounted) {
        setState(() => _isRefreshingFollowState = false);
      }
    }
  }

  Future<void> _loadInitialPage() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _hasMore = true;
      _lastDocument = null;
      _userIds.clear();
      _profileCache.clear();
    });

    try {
      final page = await widget.loader(null);
      await _applyPage(page, replace: true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    try {
      final page = await widget.loader(_lastDocument);
      await _applyPage(page, replace: false);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'We could not load more users right now.',
        tone: AppFeedbackTone.warning,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _applyPage(
    FollowIdsPage page, {
    required bool replace,
  }) async {
    final uniqueIds = replace
        ? page.userIds
        : page.userIds.where((id) => !_userIds.contains(id)).toList();
    final uncachedIds = uniqueIds
        .where((id) => !_profileCache.containsKey(id))
        .toList(growable: false);
    final fetchedProfiles = await _profileRepository.fetchUserProfilesByIds(
      uncachedIds,
    );

    if (!mounted) return;
    setState(() {
      if (replace) {
        _userIds
          ..clear()
          ..addAll(uniqueIds);
      } else {
        _userIds.addAll(uniqueIds);
      }
      _profileCache.addAll(fetchedProfiles);
      _lastDocument = page.lastDocument;
      _hasMore = page.hasMore;
    });
  }

  void _handleFollowChanged(String userId, bool isFollowing) {
    setState(() {
      if (isFollowing) {
        _followingIds.add(userId);
      } else {
        _followingIds.remove(userId);
        if (widget.listKind == UserListKind.following) {
          _userIds.remove(userId);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textDark,
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
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
                onPressed: _loadInitialPage,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_userIds.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            widget.emptyMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textGrey,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: _userIds.length + (_hasMore || _isLoadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index >= _userIds.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: _isLoadingMore
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      onPressed: _loadMore,
                      child: const Text('Load more'),
                    ),
            ),
          );
        }

        final userId = _userIds[index];
        final profile = _profileCache[userId];
        if (profile == null) {
          return const _UserRowPlaceholder();
        }

        return _UserListRow(
          profile: profile,
          currentUserId: _currentUserId,
          initiallyFollowing: _followingIds.contains(userId),
          isFollowStateLoading: _isRefreshingFollowState,
          followRepository: _followRepository,
          onFollowChanged: _handleFollowChanged,
        );
      },
    );
  }
}

class _UserListRow extends StatefulWidget {
  final UserProfile profile;
  final String currentUserId;
  final bool initiallyFollowing;
  final bool isFollowStateLoading;
  final FollowRepository followRepository;
  final void Function(String userId, bool isFollowing) onFollowChanged;

  const _UserListRow({
    required this.profile,
    required this.currentUserId,
    required this.initiallyFollowing,
    required this.isFollowStateLoading,
    required this.followRepository,
    required this.onFollowChanged,
  });

  @override
  State<_UserListRow> createState() => _UserListRowState();
}

class _UserListRowState extends State<_UserListRow> {
  late bool _isFollowing;
  bool _isFollowActionRunning = false;

  bool get _isOwnProfile => widget.profile.uid == widget.currentUserId;

  @override
  void initState() {
    super.initState();
    _isFollowing = widget.initiallyFollowing;
  }

  @override
  void didUpdateWidget(covariant _UserListRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initiallyFollowing != widget.initiallyFollowing) {
      _isFollowing = widget.initiallyFollowing;
    }
  }

  Future<void> _toggleFollow() async {
    if (_isOwnProfile || _isFollowActionRunning || widget.isFollowStateLoading) {
      return;
    }
    if (!UserRestrictionService.instance.ensureCanUseSocialFeatures(context)) {
      return;
    }

    final previous = _isFollowing;
    final next = !previous;
    setState(() {
      _isFollowActionRunning = true;
      _isFollowing = next;
    });

    try {
      final resolved = await widget.followRepository.toggleFollow(
        followerId: widget.currentUserId,
        followeeId: widget.profile.uid,
        currentlyFollowing: previous,
      );
      if (!mounted) return;
      setState(() => _isFollowing = resolved);
      widget.onFollowChanged(widget.profile.uid, resolved);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isFollowing = previous);
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          _UserAvatar(
            imageUrl: widget.profile.profileImageUrl,
            initials: widget.profile.initials,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.profile.name.isEmpty ? 'Pettxo user' : widget.profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.profile.displayUsername.isEmpty
                      ? '@username'
                      : widget.profile.displayUsername,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (!_isOwnProfile)
            FilledButton(
              onPressed: (_isFollowActionRunning || widget.isFollowStateLoading)
                  ? null
                  : _toggleFollow,
              style: FilledButton.styleFrom(
                backgroundColor: _isFollowing ? Colors.white : AppColors.primary,
                foregroundColor: _isFollowing ? AppColors.textDark : Colors.white,
                side: _isFollowing
                    ? BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.22),
                      )
                    : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isFollowActionRunning
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _isFollowing ? AppColors.textDark : Colors.white,
                      ),
                    )
                  : Text(_isFollowing ? 'Following' : 'Follow'),
            ),
        ],
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  final String imageUrl;
  final String initials;

  const _UserAvatar({
    required this.imageUrl,
    required this.initials,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isNotEmpty) {
      return ClipOval(
        child: SizedBox(
          width: 44,
          height: 44,
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            placeholder: (context, imageUrl) => _fallbackAvatar(),
            errorWidget: (context, imageUrl, error) => _fallbackAvatar(),
          ),
        ),
      );
    }

    return _fallbackAvatar();
  }

  Widget _fallbackAvatar() {
    return CircleAvatar(
      radius: 22,
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

class _UserRowPlaceholder extends StatelessWidget {
  const _UserRowPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
