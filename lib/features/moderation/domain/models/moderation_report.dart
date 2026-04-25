import 'package:cloud_firestore/cloud_firestore.dart';

class ModerationReport {
  final String id;
  final String reporterId;
  final String targetType;
  final String targetId;
  final String targetOwnerId;
  final String reason;
  final String description;
  final List<String> evidenceUrls;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ModerationReport({
    required this.id,
    required this.reporterId,
    required this.targetType,
    required this.targetId,
    required this.targetOwnerId,
    required this.reason,
    required this.description,
    required this.evidenceUrls,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toCreateMap() {
    return {
      'reporterId': reporterId,
      'targetType': targetType,
      'targetId': targetId,
      'targetOwnerId': targetOwnerId,
      'reason': reason,
      'description': description,
      'evidenceUrls': evidenceUrls,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
