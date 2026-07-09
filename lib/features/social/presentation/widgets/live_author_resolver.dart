import 'package:flutter/material.dart';

import '../../../profile/data/repositories/profile_repository.dart';
import '../../../profile/domain/models/user_profile.dart';

class ResolvedAuthorData {
  final String displayName;
  final String username;
  final String imageUrl;

  const ResolvedAuthorData({
    required this.displayName,
    required this.username,
    required this.imageUrl,
  });

  String get initials {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return 'P';
    return trimmed.substring(0, 1).toUpperCase();
  }
}

class LiveAuthorResolver extends StatelessWidget {
  final String authorId;
  final String fallbackName;
  final String fallbackUsername;
  final String fallbackImageUrl;
  final Widget Function(BuildContext context, ResolvedAuthorData author)
  builder;

  const LiveAuthorResolver({
    super.key,
    required this.authorId,
    required this.fallbackName,
    required this.fallbackUsername,
    required this.fallbackImageUrl,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedAuthorId = authorId.trim();
    final fallback = _buildResolvedAuthorData(null);
    if (trimmedAuthorId.isEmpty) {
      return builder(context, fallback);
    }

    return StreamBuilder<UserProfile>(
      initialData: _LiveAuthorProfileCache.latest(trimmedAuthorId),
      stream: _LiveAuthorProfileCache.watch(trimmedAuthorId),
      builder: (context, snapshot) {
        final resolved = _buildResolvedAuthorData(snapshot.data);
        return builder(context, resolved);
      },
    );
  }

  ResolvedAuthorData _buildResolvedAuthorData(UserProfile? profile) {
    final liveName = profile?.name.trim() ?? '';
    final liveUsername = profile?.displayUsername.trim() ?? '';
    final liveImageUrl = profile?.profileImageUrl.trim() ?? '';

    return ResolvedAuthorData(
      displayName: liveName.isEmpty
          ? (fallbackName.trim().isEmpty ? 'Pettxo user' : fallbackName.trim())
          : liveName,
      username: liveUsername.isEmpty ? fallbackUsername.trim() : liveUsername,
      imageUrl: liveImageUrl.isEmpty ? fallbackImageUrl.trim() : liveImageUrl,
    );
  }
}

class _LiveAuthorProfileCache {
  static final ProfileRepository _profileRepository = ProfileRepository();
  static final Map<String, Stream<UserProfile>> _streamCache =
      <String, Stream<UserProfile>>{};
  static final Map<String, UserProfile> _latestProfileCache =
      <String, UserProfile>{};

  static Stream<UserProfile> watch(String authorId) {
    final trimmedAuthorId = authorId.trim();
    return _streamCache.putIfAbsent(trimmedAuthorId, () {
      return _profileRepository.watchUserProfile(trimmedAuthorId).map((
        profile,
      ) {
        _latestProfileCache[trimmedAuthorId] = profile;
        return profile;
      }).asBroadcastStream();
    });
  }

  static UserProfile? latest(String authorId) {
    return _latestProfileCache[authorId.trim()];
  }
}
