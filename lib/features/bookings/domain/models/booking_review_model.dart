import 'package:cloud_firestore/cloud_firestore.dart';

class BookingReviewModel {
  final String id;
  final String bookingId;
  final String serviceId;
  final String providerUserId;
  final String reviewerUserId;
  final String reviewerName;
  final String reviewerPhotoUrl;
  final int rating;
  final String comment;
  final List<String> tags;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isEdited;
  final String moderationStatus;

  const BookingReviewModel({
    required this.id,
    required this.bookingId,
    required this.serviceId,
    required this.providerUserId,
    required this.reviewerUserId,
    required this.reviewerName,
    required this.reviewerPhotoUrl,
    required this.rating,
    required this.comment,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    required this.isEdited,
    required this.moderationStatus,
  });

  factory BookingReviewModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return BookingReviewModel.fromMap(snapshot.id, snapshot.data() ?? const {});
  }

  factory BookingReviewModel.fromMap(String id, Map<String, dynamic> data) {
    return BookingReviewModel(
      id: id.trim(),
      bookingId: _string(data['bookingId']),
      serviceId: _string(data['serviceId']),
      providerUserId: _firstString([
        data['providerUserId'],
        data['providerId'],
      ]),
      reviewerUserId: _firstString([
        data['reviewerUserId'],
        data['reviewerId'],
      ]),
      reviewerName: _string(data['reviewerName']),
      reviewerPhotoUrl: _string(data['reviewerPhotoUrl']),
      rating: _int(data['rating']),
      comment: _string(data['comment']),
      tags: (data['tags'] as List<dynamic>? ?? const [])
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      createdAt: _dateTime(data['createdAt']),
      updatedAt: _dateTime(data['updatedAt']),
      isEdited: data['isEdited'] as bool? ?? false,
      moderationStatus: _string(data['moderationStatus']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bookingId': bookingId,
      'serviceId': serviceId,
      'providerUserId': providerUserId,
      'reviewerUserId': reviewerUserId,
      'reviewerName': reviewerName,
      'reviewerPhotoUrl': reviewerPhotoUrl,
      'rating': rating,
      'comment': comment,
      'tags': tags,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'isEdited': isEdited,
      'moderationStatus': moderationStatus,
    };
  }

  Map<String, dynamic> toCreateMap() {
    return {
      'bookingId': bookingId,
      'serviceId': serviceId,
      'providerUserId': providerUserId,
      'reviewerUserId': reviewerUserId,
      'reviewerName': reviewerName,
      'reviewerPhotoUrl': reviewerPhotoUrl,
      'rating': rating,
      'comment': comment.trim(),
      'tags': tags,
      'isEdited': isEdited,
      'moderationStatus': moderationStatus,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  BookingReviewModel copyWith({
    String? id,
    String? bookingId,
    String? serviceId,
    String? providerUserId,
    String? reviewerUserId,
    String? reviewerName,
    String? reviewerPhotoUrl,
    int? rating,
    String? comment,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isEdited,
    String? moderationStatus,
  }) {
    return BookingReviewModel(
      id: id ?? this.id,
      bookingId: bookingId ?? this.bookingId,
      serviceId: serviceId ?? this.serviceId,
      providerUserId: providerUserId ?? this.providerUserId,
      reviewerUserId: reviewerUserId ?? this.reviewerUserId,
      reviewerName: reviewerName ?? this.reviewerName,
      reviewerPhotoUrl: reviewerPhotoUrl ?? this.reviewerPhotoUrl,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isEdited: isEdited ?? this.isEdited,
      moderationStatus: moderationStatus ?? this.moderationStatus,
    );
  }

  static String _firstString(List<Object?> values, {String fallback = ''}) {
    for (final value in values) {
      final text = _string(value);
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }

  static String _string(Object? value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static int _int(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static DateTime? _dateTime(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String get reviewerFirstName {
    final trimmed = reviewerName.trim();
    if (trimmed.isEmpty) return '';
    final parts = trimmed.split(RegExp(r'\s+'));
    return parts.isEmpty ? '' : parts.first;
  }

  bool get isApprovedForPublicDisplay {
    final normalized = moderationStatus.trim().toLowerCase();
    return normalized.isEmpty || normalized == 'approved';
  }
}
