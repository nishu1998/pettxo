import 'package:flutter/material.dart';

import '../../../../core/widgets/live_user_identity_resolver.dart';

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
    return LiveUserIdentityResolver(
      userId: authorId,
      fallbackName: fallbackName,
      fallbackUsername: fallbackUsername,
      fallbackImageUrl: fallbackImageUrl,
      builder: (context, snapshot) {
        return builder(
          context,
          ResolvedAuthorData(
            displayName: snapshot.displayName,
            username: snapshot.username,
            imageUrl: snapshot.imageUrl,
          ),
        );
      },
    );
  }
}
