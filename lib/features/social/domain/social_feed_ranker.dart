import 'dart:math' as math;

import 'models/social_post_model.dart';

class RankedPost {
  final SocialPostModel post;
  final double score;
  final String? reason;

  const RankedPost({
    required this.post,
    required this.score,
    required this.reason,
  });

  RankedPost copyWith({
    SocialPostModel? post,
    double? score,
    String? reason,
  }) {
    return RankedPost(
      post: post ?? this.post,
      score: score ?? this.score,
      reason: reason ?? this.reason,
    );
  }
}

List<RankedPost> rankPosts({
  required List<SocialPostModel> posts,
  required String? currentUserId,
  required String? userCity,
  required String? userState,
  required Set<String> followingIds,
  required Set<String> userInterestTags,
}) {
  final normalizedUserCity = (userCity ?? '').trim().toLowerCase();
  final normalizedUserState = (userState ?? '').trim().toLowerCase();
  final normalizedFollowingIds = Set<String>.from(followingIds);
  final normalizedInterestTags = userInterestTags
      .map((tag) => tag.trim().toLowerCase())
      .where((tag) => tag.isNotEmpty)
      .toSet();
  final nowEpoch = DateTime.now().millisecondsSinceEpoch;

  final ranked = posts.map((post) {
    return scorePost(
      post: post,
      nowEpoch: nowEpoch,
      userCity: normalizedUserCity,
      userState: normalizedUserState,
      followingIds: normalizedFollowingIds,
      userInterestTags: normalizedInterestTags,
    );
  }).toList(growable: false);

  sortRankedPostsInPlace(ranked);

  return ranked;
}

RankedPost scorePost({
  required SocialPostModel post,
  required int nowEpoch,
  required String userCity,
  required String userState,
  required Set<String> followingIds,
  required Set<String> userInterestTags,
}) {
  var score = 0.0;
  String? reason;
  var bestReasonScore = double.negativeInfinity;

  void registerReason(String label, double reasonScore) {
    if (reasonScore > bestReasonScore) {
      bestReasonScore = reasonScore;
      reason = label;
    }
  }

  if (followingIds.contains(post.authorId)) {
    score += 40;
    registerReason('Following', 40);
  }

  final postCity = post.authorCity.trim().toLowerCase();
  final postState = post.authorState.trim().toLowerCase();
  if (userCity.isNotEmpty && postCity == userCity) {
    score += 25;
    registerReason('Near you', 25);
  } else if (userState.isNotEmpty && postState == userState) {
    score += 10;
    registerReason('Near you', 10);
  }

  if (userInterestTags.isNotEmpty) {
    final normalizedTags = post.hashtags
        .map((tag) => tag.trim().toLowerCase())
        .where((tag) => tag.isNotEmpty)
        .toSet();
    final matches = normalizedTags.intersection(userInterestTags).length;
    final hashtagBoost = math.min(20, matches * 5).toDouble();
    score += hashtagBoost;
    if (hashtagBoost > 0) {
      registerReason('For you', hashtagBoost);
    }
  }

  if (post.createdAtEpoch > 0) {
    final ageHours = (nowEpoch - post.createdAtEpoch) / (1000 * 60 * 60);
    if (ageHours < 1) {
      score += 30;
      registerReason('Fresh', 30);
    } else if (ageHours < 6) {
      score += 20;
      registerReason('Fresh', 20);
    } else if (ageHours < 24) {
      score += 10;
      registerReason('Fresh', 10);
    }
  }

  final engagementBoost = math.min(
    25,
    (post.likeCount * 0.4) +
        (post.commentCount * 1.0) +
        post.recentEngagementScore,
  );
  score += engagementBoost;
  if (engagementBoost >= 15) {
    registerReason('Popular', engagementBoost.toDouble());
  }

  final adminBoost = math.min(30, post.adminPriorityBoost).toDouble();
  score += adminBoost;
  if (adminBoost > 0 || post.isAdminPost || post.authorType == 'admin') {
    registerReason('Pettxo update', adminBoost > 0 ? adminBoost : 12);
  }

  if (post.reportCount > 3) {
    score -= 20;
  }

  reason ??= 'For you';
  return RankedPost(post: post, score: score, reason: reason);
}

void sortRankedPostsInPlace(List<RankedPost> rankedPosts) {
  rankedPosts.sort((a, b) {
    final scoreCompare = b.score.compareTo(a.score);
    if (scoreCompare != 0) return scoreCompare;

    final timeCompare = b.post.createdAtEpoch.compareTo(a.post.createdAtEpoch);
    if (timeCompare != 0) return timeCompare;

    return a.post.id.compareTo(b.post.id);
  });
}
