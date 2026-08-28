import 'package:cloud_firestore/cloud_firestore.dart';

class CanonicalBookingPayoutRecord {
  final String payoutId;
  final String bookingId;
  final String status;
  final String holdReason;
  final int providerEntitlementPaise;
  final int priorPaidPaise;
  final int remainingPayablePaise;
  final DateTime? eligibleAt;
  final DateTime? readyAt;
  final DateTime? processingAt;
  final DateTime? paidAt;
  final DateTime? failedAt;
  final String failureCode;

  const CanonicalBookingPayoutRecord({
    required this.payoutId,
    required this.bookingId,
    required this.status,
    required this.holdReason,
    required this.providerEntitlementPaise,
    required this.priorPaidPaise,
    required this.remainingPayablePaise,
    required this.eligibleAt,
    required this.readyAt,
    required this.processingAt,
    required this.paidAt,
    required this.failedAt,
    required this.failureCode,
  });

  factory CanonicalBookingPayoutRecord.fromMap(Map<String, dynamic> data) {
    return CanonicalBookingPayoutRecord(
      payoutId: (data['payoutId'] as String? ?? '').trim(),
      bookingId: (data['bookingId'] as String? ?? '').trim(),
      status: (data['status'] as String? ?? '').trim(),
      holdReason: (data['holdReason'] as String? ?? '').trim(),
      providerEntitlementPaise:
          (data['providerEntitlementPaise'] as num?)?.round() ?? 0,
      priorPaidPaise: (data['priorPaidPaise'] as num?)?.round() ?? 0,
      remainingPayablePaise:
          (data['remainingPayablePaise'] as num?)?.round() ?? 0,
      eligibleAt: _readDate(data['eligibleAt']),
      readyAt: _readDate(data['readyAt']),
      processingAt: _readDate(data['processingAt']),
      paidAt: _readDate(data['paidAt']),
      failedAt: _readDate(data['failedAt']),
      failureCode: (data['failureCode'] as String? ?? '').trim(),
    );
  }
}

DateTime? _readDate(Object? raw) {
  if (raw == null) return null;
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is String) return DateTime.tryParse(raw);
  return null;
}
