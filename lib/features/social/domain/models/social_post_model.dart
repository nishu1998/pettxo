import 'package:cloud_firestore/cloud_firestore.dart';

enum SocialPostAspectRatio { square, portrait, landscape }

class SocialPostModel {
  final String id;
  final String authorId;
  final String authorType;
  final String authorDisplayName;
  final String authorUsername;
  final String authorPhotoUrl;
  final String authorCategoryLabel;
  final String authorCity;
  final String authorState;
  final bool isAdminPost;
  final int adminPriorityBoost;
  final double recentEngagementScore;
  final List<String> imageUrls;
  final List<String> thumbnailUrls;
  final SocialPostAspectRatio imageAspectRatio;
  final String caption;
  final List<String> hashtags;
  final int likeCount;
  final int commentCount;
  final int shareCount;
  final int saveCount;
  final int reportCount;
  final String visibilityStatus;
  final String moderationStatus;
  final String moderationReason;
  final String moderatedBy;
  final Timestamp? moderatedAt;
  final Timestamp? lastReportedAt;
  final int createdAtEpoch;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  const SocialPostModel({
    required this.id,
    required this.authorId,
    required this.authorType,
    required this.authorDisplayName,
    required this.authorUsername,
    required this.authorPhotoUrl,
    required this.authorCategoryLabel,
    required this.authorCity,
    required this.authorState,
    required this.isAdminPost,
    required this.adminPriorityBoost,
    required this.recentEngagementScore,
    required this.imageUrls,
    required this.thumbnailUrls,
    required this.imageAspectRatio,
    required this.caption,
    required this.hashtags,
    required this.likeCount,
    required this.commentCount,
    required this.shareCount,
    required this.saveCount,
    required this.reportCount,
    required this.visibilityStatus,
    required this.moderationStatus,
    required this.moderationReason,
    required this.moderatedBy,
    required this.moderatedAt,
    required this.lastReportedAt,
    required this.createdAtEpoch,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SocialPostModel.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return SocialPostModel.fromMap(data, fallbackId: doc.id);
  }

  factory SocialPostModel.fromMap(
    Map<String, dynamic> data, {
    String fallbackId = '',
  }) {
    return SocialPostModel(
      id: (data['id'] as String? ?? fallbackId).trim(),
      authorId: (data['authorId'] as String? ?? '').trim(),
      authorType: (data['authorType'] as String? ?? 'user').trim(),
      authorDisplayName: (data['authorDisplayName'] as String? ?? '').trim(),
      authorUsername: (data['authorUsername'] as String? ?? '').trim(),
      authorPhotoUrl: (data['authorPhotoUrl'] as String? ?? '').trim(),
      authorCategoryLabel: (data['authorCategoryLabel'] as String? ?? '').trim(),
      authorCity: (data['authorCity'] as String? ?? '').trim(),
      authorState: (data['authorState'] as String? ?? '').trim(),
      isAdminPost: data['isAdminPost'] == true,
      adminPriorityBoost: (data['adminPriorityBoost'] as num?)?.toInt() ?? 0,
      recentEngagementScore:
          (data['recentEngagementScore'] as num?)?.toDouble() ?? 0,
      imageUrls: _readStringList(data['imageUrls']),
      thumbnailUrls: _readStringList(data['thumbnailUrls']),
      imageAspectRatio: socialPostAspectRatioFromValue(
        (data['imageAspectRatio'] as String? ?? 'square').trim(),
      ),
      caption: (data['caption'] as String? ?? '').trim(),
      hashtags: _readStringList(data['hashtags']),
      likeCount: (data['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (data['commentCount'] as num?)?.toInt() ?? 0,
      shareCount: (data['shareCount'] as num?)?.toInt() ?? 0,
      saveCount: (data['saveCount'] as num?)?.toInt() ?? 0,
      reportCount: (data['reportCount'] as num?)?.toInt() ?? 0,
      visibilityStatus: (data['visibilityStatus'] as String? ?? 'visible').trim(),
      moderationStatus: (data['moderationStatus'] as String? ?? 'approved').trim(),
      moderationReason: (data['moderationReason'] as String? ?? '').trim(),
      moderatedBy: (data['moderatedBy'] as String? ?? '').trim(),
      moderatedAt: data['moderatedAt'] as Timestamp?,
      lastReportedAt: data['lastReportedAt'] as Timestamp?,
      createdAtEpoch: (data['createdAtEpoch'] as num?)?.toInt() ??
          (data['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
          0,
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'authorId': authorId,
      'authorType': authorType,
      'authorDisplayName': authorDisplayName,
      'authorUsername': authorUsername,
      'authorPhotoUrl': authorPhotoUrl,
      'authorCategoryLabel': authorCategoryLabel,
      'authorCity': authorCity,
      'authorState': authorState,
      'isAdminPost': isAdminPost,
      'adminPriorityBoost': adminPriorityBoost,
      'recentEngagementScore': recentEngagementScore,
      'imageUrls': imageUrls,
      'thumbnailUrls': thumbnailUrls,
      'imageAspectRatio': imageAspectRatio.value,
      'caption': caption,
      'hashtags': hashtags,
      'likeCount': likeCount,
      'commentCount': commentCount,
      'shareCount': shareCount,
      'saveCount': saveCount,
      'reportCount': reportCount,
      'visibilityStatus': visibilityStatus,
      'moderationStatus': moderationStatus,
      'moderationReason': moderationReason,
      'moderatedBy': moderatedBy,
      'moderatedAt': moderatedAt,
      'lastReportedAt': lastReportedAt,
      'createdAtEpoch': createdAtEpoch,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  SocialPostModel copyWith({
    String? id,
    String? authorId,
    String? authorType,
    String? authorDisplayName,
    String? authorUsername,
    String? authorPhotoUrl,
    String? authorCategoryLabel,
    String? authorCity,
    String? authorState,
    bool? isAdminPost,
    int? adminPriorityBoost,
    double? recentEngagementScore,
    List<String>? imageUrls,
    List<String>? thumbnailUrls,
    SocialPostAspectRatio? imageAspectRatio,
    String? caption,
    List<String>? hashtags,
    int? likeCount,
    int? commentCount,
    int? shareCount,
    int? saveCount,
    int? reportCount,
    String? visibilityStatus,
    String? moderationStatus,
    String? moderationReason,
    String? moderatedBy,
    Timestamp? moderatedAt,
    Timestamp? lastReportedAt,
    int? createdAtEpoch,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return SocialPostModel(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      authorType: authorType ?? this.authorType,
      authorDisplayName: authorDisplayName ?? this.authorDisplayName,
      authorUsername: authorUsername ?? this.authorUsername,
      authorPhotoUrl: authorPhotoUrl ?? this.authorPhotoUrl,
      authorCategoryLabel: authorCategoryLabel ?? this.authorCategoryLabel,
      authorCity: authorCity ?? this.authorCity,
      authorState: authorState ?? this.authorState,
      isAdminPost: isAdminPost ?? this.isAdminPost,
      adminPriorityBoost: adminPriorityBoost ?? this.adminPriorityBoost,
      recentEngagementScore:
          recentEngagementScore ?? this.recentEngagementScore,
      imageUrls: imageUrls ?? this.imageUrls,
      thumbnailUrls: thumbnailUrls ?? this.thumbnailUrls,
      imageAspectRatio: imageAspectRatio ?? this.imageAspectRatio,
      caption: caption ?? this.caption,
      hashtags: hashtags ?? this.hashtags,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      shareCount: shareCount ?? this.shareCount,
      saveCount: saveCount ?? this.saveCount,
      reportCount: reportCount ?? this.reportCount,
      visibilityStatus: visibilityStatus ?? this.visibilityStatus,
      moderationStatus: moderationStatus ?? this.moderationStatus,
      moderationReason: moderationReason ?? this.moderationReason,
      moderatedBy: moderatedBy ?? this.moderatedBy,
      moderatedAt: moderatedAt ?? this.moderatedAt,
      lastReportedAt: lastReportedAt ?? this.lastReportedAt,
      createdAtEpoch: createdAtEpoch ?? this.createdAtEpoch,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get locationLabel {
    if (authorCity.isNotEmpty && authorState.isNotEmpty) {
      return '$authorCity, $authorState';
    }
    if (authorCity.isNotEmpty) return authorCity;
    if (authorState.isNotEmpty) return authorState;
    return '';
  }

  double get aspectRatioValue {
    switch (imageAspectRatio) {
      case SocialPostAspectRatio.square:
        return 1;
      case SocialPostAspectRatio.portrait:
        return 4 / 5;
      case SocialPostAspectRatio.landscape:
        return 1.91 / 1;
    }
  }

  static List<String> _readStringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}

SocialPostAspectRatio socialPostAspectRatioFromValue(String value) {
  switch (value) {
    case 'portrait':
      return SocialPostAspectRatio.portrait;
    case 'landscape':
      return SocialPostAspectRatio.landscape;
    case 'square':
    default:
      return SocialPostAspectRatio.square;
  }
}

extension SocialPostAspectRatioValue on SocialPostAspectRatio {
  String get value {
    switch (this) {
      case SocialPostAspectRatio.square:
        return 'square';
      case SocialPostAspectRatio.portrait:
        return 'portrait';
      case SocialPostAspectRatio.landscape:
        return 'landscape';
    }
  }

  String get label {
    switch (this) {
      case SocialPostAspectRatio.square:
        return 'Square';
      case SocialPostAspectRatio.portrait:
        return 'Portrait';
      case SocialPostAspectRatio.landscape:
        return 'Landscape';
    }
  }
}
