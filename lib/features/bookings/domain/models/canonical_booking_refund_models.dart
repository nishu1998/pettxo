import 'package:cloud_firestore/cloud_firestore.dart';

class CanonicalBookingRefundRecord {
  final String bookingId;
  final String state;
  final int refundAmountPaise;
  final String refundInstructionId;
  final String razorpayRefundId;
  final DateTime? createdAt;
  final DateTime? submittedAt;
  final DateTime? confirmedAt;
  final DateTime? updatedAt;

  const CanonicalBookingRefundRecord({
    required this.bookingId,
    required this.state,
    required this.refundAmountPaise,
    required this.refundInstructionId,
    required this.razorpayRefundId,
    required this.createdAt,
    required this.submittedAt,
    required this.confirmedAt,
    required this.updatedAt,
  });

  factory CanonicalBookingRefundRecord.fromMap(Map<String, dynamic> data) {
    return CanonicalBookingRefundRecord(
      bookingId: (data['bookingId'] as String? ?? '').trim(),
      state: (data['state'] as String? ?? '').trim(),
      refundAmountPaise: (data['refundAmountPaise'] as num?)?.round() ?? 0,
      refundInstructionId: (data['refundInstructionId'] as String? ?? '')
          .trim(),
      razorpayRefundId: (data['razorpayRefundId'] as String? ?? '').trim(),
      createdAt: _readDate(data['createdAt']),
      submittedAt: _readDate(data['submittedAt']),
      confirmedAt: _readDate(data['confirmedAt']),
      updatedAt: _readDate(data['updatedAt']),
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
