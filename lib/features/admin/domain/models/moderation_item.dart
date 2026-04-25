import 'package:cloud_firestore/cloud_firestore.dart';

class ModerationItem {
  final String id;
  final String targetType;
  final String targetId;
  final String targetOwnerId;
  final String source;
  final String reportId;
  final String severity;
  final String status;
  final String reason;
  final String assignedAdminId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? resolvedAt;

  const ModerationItem({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.targetOwnerId,
    required this.source,
    required this.reportId,
    required this.severity,
    required this.status,
    required this.reason,
    required this.assignedAdminId,
    required this.createdAt,
    required this.updatedAt,
    required this.resolvedAt,
  });

  factory ModerationItem.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};

    return ModerationItem(
      id: doc.id,
      targetType: (data['targetType'] as String? ?? '').trim(),
      targetId: (data['targetId'] as String? ?? '').trim(),
      targetOwnerId: (data['targetOwnerId'] as String? ?? '').trim(),
      source: (data['source'] as String? ?? 'system').trim(),
      reportId: (data['reportId'] as String? ?? '').trim(),
      severity: (data['severity'] as String? ?? 'low').trim(),
      status: (data['status'] as String? ?? 'pending').trim(),
      reason: (data['reason'] as String? ?? '').trim(),
      assignedAdminId: (data['assignedAdminId'] as String? ?? '').trim(),
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
      resolvedAt: _readDate(data['resolvedAt']),
    );
  }

  static DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
