import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_user_avatar.dart';
import '../../../../core/widgets/pettxo_loading_animation.dart';
import '../../application/blocking_change_coordinator.dart';
import '../../data/blocked_relationship_repository.dart';
import '../user_safety_dialogs.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({
    super.key,
    BlockedRelationshipRepository? repository,
  }) : _repository = repository;

  final BlockedRelationshipRepository? _repository;

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen>
    with WidgetsBindingObserver {
  late final BlockedRelationshipRepository _repository =
      widget._repository ?? BlockedRelationshipRepository();
  final List<BlockedUserSummary> _users = <BlockedUserSummary>[];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  String _unblockingUid = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load(reset: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if ((reset && _loading && _users.isNotEmpty) || (!reset && _loadingMore)) {
      return;
    }
    setState(() {
      if (reset) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final page = await _repository.loadOutgoingBlockedUsers(
        startAfter: reset ? null : _cursor,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _users.clear();
        final existing = _users.map((user) => user.uid).toSet();
        _users.addAll(page.users.where((user) => existing.add(user.uid)));
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _error = null;
      });
    } on BlockingException catch (error) {
      if (!mounted) return;
      setState(() => _error = blockingFailureMessage(error.kind));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Unable to load blocked users right now.');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _unblock(BlockedUserSummary user) async {
    if (_unblockingUid.isNotEmpty ||
        !await showUnblockConfirmation(context) ||
        !mounted) {
      return;
    }
    setState(() => _unblockingUid = user.uid);
    try {
      final result = await _repository.unblockUser(user.uid);
      if (!mounted) return;
      setState(() => _users.removeWhere((entry) => entry.uid == user.uid));
      BlockingChangeCoordinator.instance.publish(
        BlockingChange(
          targetUid: user.uid,
          relationshipBlocked: result.relationshipBlocked,
          blockedByCaller: result.blockedByCaller,
        ),
      );
      AppFeedback.show(
        context,
        message: result.relationshipBlocked
            ? 'Your block was removed. Some restrictions remain.'
            : 'User unblocked successfully.',
        tone: AppFeedbackTone.success,
      );
    } on BlockingException catch (error) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: blockingFailureMessage(error.kind),
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) setState(() => _unblockingUid = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textDark,
        title: const Text('Blocked Users'),
      ),
      body: _loading && _users.isEmpty
          ? const Center(
              child: PettxoLoader(semanticLabel: 'Loading blocked users'),
            )
          : RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                children: [
                  if (_error != null && _users.isEmpty)
                    _MessageState(
                      icon: Icons.cloud_off_outlined,
                      title: _error!,
                      actionLabel: 'Try again',
                      onAction: () => _load(reset: true),
                    )
                  else if (_users.isEmpty)
                    const _MessageState(
                      icon: Icons.person_off_outlined,
                      title: "You haven't blocked anyone.",
                    )
                  else ...[
                    const Text(
                      'People you blocked cannot message or interact with you. Unblocking does not restore previous follows or conversations.',
                      style: TextStyle(color: AppColors.textGrey, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    ..._users.map(
                      (user) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _BlockedUserTile(
                          user: user,
                          busy: _unblockingUid == user.uid,
                          onUnblock: () => _unblock(user),
                        ),
                      ),
                    ),
                    if (_hasMore)
                      Center(
                        child: TextButton(
                          onPressed: _loadingMore
                              ? null
                              : () => _load(reset: false),
                          child: Text(
                            _loadingMore ? 'Loading...' : 'Load more',
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _BlockedUserTile extends StatelessWidget {
  const _BlockedUserTile({
    required this.user,
    required this.busy,
    required this.onUnblock,
  });

  final BlockedUserSummary user;
  final bool busy;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final initial = user.displayName.trim().isEmpty
        ? 'P'
        : user.displayName.trim()[0].toUpperCase();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          AppUserAvatar(
            size: 48,
            imageUrl: user.photoUrl,
            fallback: AppUserAvatarFallback(
              initials: initial,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              textStyle: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (user.username.isNotEmpty)
                  Text(
                    '@${user.username.replaceFirst('@', '')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textGrey),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: busy ? null : onUnblock,
            child: Text(busy ? 'Unblocking...' : 'Unblock'),
          ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AppColors.textGrey),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 10),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
