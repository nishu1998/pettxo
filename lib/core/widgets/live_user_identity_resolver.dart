import 'package:flutter/material.dart';

import '../../features/profile/data/repositories/profile_repository.dart';
import '../../features/profile/domain/models/user_profile.dart';

class ResolvedUserIdentity {
  final String displayName;
  final String username;
  final String imageUrl;
  final String roleLabel;

  const ResolvedUserIdentity({
    required this.displayName,
    required this.username,
    required this.imageUrl,
    required this.roleLabel,
  });

  String get initials {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return 'P';
    return trimmed.substring(0, 1).toUpperCase();
  }
}

class LiveUserIdentityResolver extends StatelessWidget {
  final String userId;
  final String fallbackName;
  final String fallbackUsername;
  final String fallbackImageUrl;
  final String fallbackRoleLabel;
  final String placeholderName;
  final Widget Function(BuildContext context, ResolvedUserIdentity identity)
  builder;

  const LiveUserIdentityResolver({
    super.key,
    required this.userId,
    required this.fallbackName,
    required this.fallbackUsername,
    required this.fallbackImageUrl,
    this.fallbackRoleLabel = '',
    required this.builder,
    this.placeholderName = 'Pettxo user',
  });

  @override
  Widget build(BuildContext context) {
    final trimmedUserId = userId.trim();
    final fallback = _resolveIdentity(null);
    if (trimmedUserId.isEmpty) {
      return builder(context, fallback);
    }

    return StreamBuilder<UserProfile>(
      initialData: _LiveUserIdentityCache.latest(trimmedUserId),
      stream: _LiveUserIdentityCache.watch(trimmedUserId),
      builder: (context, snapshot) {
        return builder(context, _resolveIdentity(snapshot.data));
      },
    );
  }

  ResolvedUserIdentity _resolveIdentity(UserProfile? profile) {
    final liveName = profile?.name.trim() ?? '';
    final liveUsername = profile?.username.trim() ?? '';
    final liveImageUrl = profile?.profileImageUrl.trim() ?? '';
    final liveRoleLabel = profile?.roleLabel.trim() ?? '';
    final normalizedFallbackName = fallbackName.trim();
    final normalizedFallbackUsername = fallbackUsername.trim().replaceFirst(
      '@',
      '',
    );

    return ResolvedUserIdentity(
      displayName: liveName.isNotEmpty
          ? liveName
          : (normalizedFallbackName.isNotEmpty
                ? normalizedFallbackName
                : placeholderName),
      username: liveUsername.isNotEmpty
          ? liveUsername
          : normalizedFallbackUsername,
      imageUrl: liveImageUrl.isNotEmpty
          ? liveImageUrl
          : fallbackImageUrl.trim(),
      roleLabel: liveRoleLabel.isNotEmpty ? liveRoleLabel : fallbackRoleLabel,
    );
  }
}

class _LiveUserIdentityCache {
  static final ProfileRepository _profileRepository = ProfileRepository();
  static final Map<String, Stream<UserProfile>> _streamCache =
      <String, Stream<UserProfile>>{};
  static final Map<String, UserProfile> _latestProfileCache =
      <String, UserProfile>{};

  static Stream<UserProfile> watch(String userId) {
    final trimmedUserId = userId.trim();
    return _streamCache.putIfAbsent(trimmedUserId, () {
      return _profileRepository.watchUserProfile(trimmedUserId).map((profile) {
        _latestProfileCache[trimmedUserId] = profile;
        return profile;
      }).asBroadcastStream();
    });
  }

  static UserProfile? latest(String userId) {
    return _latestProfileCache[userId.trim()];
  }
}
