import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../social/domain/models/social_post_model.dart';

class ExploreFeedPage {
  final List<SocialPostModel> posts;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final Map<String, dynamic>? nextCursor;
  final bool hasMore;
  final bool usedLegacyFallback;
  final double? activeRadiusKm;
  final bool usedLocationFallback;
  final String? emptyStateReason;

  const ExploreFeedPage({
    required this.posts,
    required this.lastDocument,
    this.nextCursor,
    required this.hasMore,
    this.usedLegacyFallback = false,
    this.activeRadiusKm,
    this.usedLocationFallback = false,
    this.emptyStateReason,
  });
}
