import 'package:cloud_firestore/cloud_firestore.dart';

class CommentModel {
  final String id;
  final String postId;
  final String authorId;
  final String authorDisplayName;
  final String authorUsername;
  final String authorPhotoUrl;
  final String parentPostAuthorId;
  final String parentPostPreview;
  final String text;
  final int likeCount;
  final int reportCount;
  final String visibilityStatus;
  final String moderationStatus;
  final String moderationReason;
  final String moderatedBy;
  final Timestamp? moderatedAt;
  final Timestamp? lastReportedAt;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  const CommentModel({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorDisplayName,
    required this.authorUsername,
    required this.authorPhotoUrl,
    required this.parentPostAuthorId,
    required this.parentPostPreview,
    required this.text,
    required this.likeCount,
    required this.reportCount,
    required this.visibilityStatus,
    required this.moderationStatus,
    required this.moderationReason,
    required this.moderatedBy,
    required this.moderatedAt,
    required this.lastReportedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CommentModel.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return CommentModel(
      id: (data['id'] as String? ?? doc.id).trim(),
      postId: (data['postId'] as String? ?? '').trim(),
      authorId: (data['authorId'] as String? ?? '').trim(),
      authorDisplayName: (data['authorDisplayName'] as String? ?? '').trim(),
      authorUsername: (data['authorUsername'] as String? ?? '').trim(),
      authorPhotoUrl: (data['authorPhotoUrl'] as String? ?? '').trim(),
      parentPostAuthorId: (data['parentPostAuthorId'] as String? ?? '').trim(),
      parentPostPreview: (data['parentPostPreview'] as String? ?? '').trim(),
      text: (data['text'] as String? ?? '').trim(),
      likeCount: (data['likeCount'] as num?)?.toInt() ?? 0,
      reportCount: (data['reportCount'] as num?)?.toInt() ?? 0,
      visibilityStatus: (data['visibilityStatus'] as String? ?? 'visible').trim(),
      moderationStatus: (data['moderationStatus'] as String? ?? 'approved').trim(),
      moderationReason: (data['moderationReason'] as String? ?? '').trim(),
      moderatedBy: (data['moderatedBy'] as String? ?? '').trim(),
      moderatedAt: data['moderatedAt'] as Timestamp?,
      lastReportedAt: data['lastReportedAt'] as Timestamp?,
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'postId': postId,
      'authorId': authorId,
      'authorDisplayName': authorDisplayName,
      'authorUsername': authorUsername,
      'authorPhotoUrl': authorPhotoUrl,
      'parentPostAuthorId': parentPostAuthorId,
      'parentPostPreview': parentPostPreview,
      'text': text,
      'likeCount': likeCount,
      'reportCount': reportCount,
      'visibilityStatus': visibilityStatus,
      'moderationStatus': moderationStatus,
      'moderationReason': moderationReason,
      'moderatedBy': moderatedBy,
      'moderatedAt': moderatedAt,
      'lastReportedAt': lastReportedAt,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  CommentModel copyWith({
    String? id,
    String? postId,
    String? authorId,
    String? authorDisplayName,
    String? authorUsername,
    String? authorPhotoUrl,
    String? parentPostAuthorId,
    String? parentPostPreview,
    String? text,
    int? likeCount,
    int? reportCount,
    String? visibilityStatus,
    String? moderationStatus,
    String? moderationReason,
    String? moderatedBy,
    Timestamp? moderatedAt,
    Timestamp? lastReportedAt,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return CommentModel(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      authorId: authorId ?? this.authorId,
      authorDisplayName: authorDisplayName ?? this.authorDisplayName,
      authorUsername: authorUsername ?? this.authorUsername,
      authorPhotoUrl: authorPhotoUrl ?? this.authorPhotoUrl,
      parentPostAuthorId: parentPostAuthorId ?? this.parentPostAuthorId,
      parentPostPreview: parentPostPreview ?? this.parentPostPreview,
      text: text ?? this.text,
      likeCount: likeCount ?? this.likeCount,
      reportCount: reportCount ?? this.reportCount,
      visibilityStatus: visibilityStatus ?? this.visibilityStatus,
      moderationStatus: moderationStatus ?? this.moderationStatus,
      moderationReason: moderationReason ?? this.moderationReason,
      moderatedBy: moderatedBy ?? this.moderatedBy,
      moderatedAt: moderatedAt ?? this.moderatedAt,
      lastReportedAt: lastReportedAt ?? this.lastReportedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
