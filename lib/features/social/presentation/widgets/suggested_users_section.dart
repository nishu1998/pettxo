import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../../../restrictions/data/services/user_restriction_service.dart';
import '../../data/follow_repository.dart';

class SuggestedUsersSection extends StatelessWidget {
  final List<UserProfile> users;
  final String currentUserId;
  final FollowRepository followRepository;
  final void Function(String userId) onFollowed;

  const SuggestedUsersSection({
    super.key,
    required this.users,
    required this.currentUserId,
    required this.followRepository,
    required this.onFollowed,
  });

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
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
          const Text(
            'Suggested for you',
            style: TextStyle(
              color: AppColors.textDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Discover more pet parents and providers around you.',
            style: TextStyle(
              color: AppColors.textGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 228,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: users.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final user = users[index];
                return _SuggestedUserCard(
                  profile: user,
                  currentUserId: currentUserId,
                  followRepository: followRepository,
                  onFollowed: onFollowed,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestedUserCard extends StatefulWidget {
  final UserProfile profile;
  final String currentUserId;
  final FollowRepository followRepository;
  final void Function(String userId) onFollowed;

  const _SuggestedUserCard({
    required this.profile,
    required this.currentUserId,
    required this.followRepository,
    required this.onFollowed,
  });

  @override
  State<_SuggestedUserCard> createState() => _SuggestedUserCardState();
}

class _SuggestedUserCardState extends State<_SuggestedUserCard> {
  bool _isFollowActionRunning = false;

  Future<void> _handleFollow() async {
    if (_isFollowActionRunning) return;
    if (!UserRestrictionService.instance.ensureCanUseSocialFeatures(context)) {
      return;
    }

    setState(() => _isFollowActionRunning = true);
    try {
      final isFollowing = await widget.followRepository.toggleFollow(
        followerId: widget.currentUserId,
        followeeId: widget.profile.uid,
        currentlyFollowing: false,
      );
      if (!mounted) return;
      if (isFollowing) {
        widget.onFollowed(widget.profile.uid);
        AppFeedback.show(
          context,
          message: 'Followed user.',
          tone: AppFeedbackTone.success,
        );
      }
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

  @override
  Widget build(BuildContext context) {
    final location = widget.profile.location;

    return Container(
      width: 156,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF8),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SuggestedUserAvatar(
            imageUrl: widget.profile.profileImageUrl,
            initials: widget.profile.initials,
          ),
          const SizedBox(height: 8),
          Text(
            widget.profile.name.isEmpty ? 'Pettxo user' : widget.profile.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            widget.profile.displayUsername.isEmpty
                ? '@username'
                : widget.profile.displayUsername,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            location.isEmpty ? 'Pettxo community' : location,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isFollowActionRunning ? null : _handleFollow,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(40),
                padding: const EdgeInsets.symmetric(vertical: 10),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isFollowActionRunning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Follow'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestedUserAvatar extends StatelessWidget {
  final String imageUrl;
  final String initials;

  const _SuggestedUserAvatar({
    required this.imageUrl,
    required this.initials,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isNotEmpty) {
      return ClipOval(
        child: SizedBox(
          width: 48,
          height: 48,
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
      radius: 24,
      backgroundColor: AppColors.background,
      child: Text(
        initials,
        style: const TextStyle(
          color: AppColors.textDark,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
