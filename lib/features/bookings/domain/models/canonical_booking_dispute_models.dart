import 'package:cloud_firestore/cloud_firestore.dart';

class CanonicalBookingDisputeRecord {
  final String disputeId;
  final String bookingId;
  final String status;
  final DateTime? createdAt;
  final DateTime? resolvedAt;
  final String resolutionType;
  final int customerRefundPaise;
  final int providerFinalEntitlementPaise;
  final String publicResolutionMessage;

  const CanonicalBookingDisputeRecord({
    required this.disputeId,
    required this.bookingId,
    required this.status,
    required this.createdAt,
    required this.resolvedAt,
    required this.resolutionType,
    required this.customerRefundPaise,
    required this.providerFinalEntitlementPaise,
    required this.publicResolutionMessage,
  });

  factory CanonicalBookingDisputeRecord.fromMap(Map<String, dynamic> data) {
    final resolution = _readMap(data['resolution']);
    return CanonicalBookingDisputeRecord(
      disputeId: (data['disputeId'] as String? ?? '').trim(),
      bookingId: (data['bookingId'] as String? ?? '').trim(),
      status: (data['status'] as String? ?? '').trim(),
      createdAt: _readDate(data['createdAt']),
      resolvedAt: _readDate(data['resolvedAt']),
      resolutionType:
          (resolution['type'] as String? ?? data['resolution'] as String? ?? '')
              .trim(),
      customerRefundPaise:
          (resolution['customerRefundPaise'] as num?)?.round() ??
          (data['customerRefundPaise'] as num?)?.round() ??
          0,
      providerFinalEntitlementPaise:
          (resolution['providerFinalEntitlementPaise'] as num?)?.round() ??
          (data['providerReleasePaise'] as num?)?.round() ??
          0,
      publicResolutionMessage:
          (resolution['publicMessage'] as String? ??
                  data['publicResolutionMessage'] as String? ??
                  '')
              .trim(),
    );
  }
}

Map<String, dynamic> _readMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const <String, dynamic>{};
}

DateTime? _readDate(Object? raw) {
  if (raw == null) return null;
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is String) return DateTime.tryParse(raw);
  return null;
}
