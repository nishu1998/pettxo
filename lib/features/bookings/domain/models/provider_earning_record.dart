import 'package:cloud_firestore/cloud_firestore.dart';

class ProviderEarningRecord {
  final String id;
  final String bookingId;
  final String providerId;
  final String userId;
  final String serviceId;
  final int amount;
  final int amountPaise;
  final int pettxoCommissionAmount;
  final int pettxoCommissionAmountPaise;
  final int totalAmount;
  final int totalAmountPaise;
  final String source;
  final String status;
  final DateTime? eligibleAt;
  final DateTime? paidAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ProviderEarningRecord({
    required this.id,
    required this.bookingId,
    required this.providerId,
    required this.userId,
    required this.serviceId,
    required this.amount,
    required this.amountPaise,
    required this.pettxoCommissionAmount,
    required this.pettxoCommissionAmountPaise,
    required this.totalAmount,
    required this.totalAmountPaise,
    required this.source,
    required this.status,
    this.eligibleAt,
    this.paidAt,
    this.createdAt,
    this.updatedAt,
  });

  factory ProviderEarningRecord.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return ProviderEarningRecord(
      id: snapshot.id,
      bookingId: (data['bookingId'] as String? ?? '').trim(),
      providerId: (data['providerId'] as String? ?? '').trim(),
      userId: (data['userId'] as String? ?? '').trim(),
      serviceId: (data['serviceId'] as String? ?? '').trim(),
      amount: (data['amount'] as num?)?.round() ?? 0,
      amountPaise:
          (data['amountPaise'] as num?)?.round() ??
          ((data['amount'] as num?)?.round() ?? 0) * 100,
      pettxoCommissionAmount:
          (data['pettxoCommissionAmount'] as num?)?.round() ?? 0,
      pettxoCommissionAmountPaise:
          (data['pettxoCommissionAmountPaise'] as num?)?.round() ??
          ((data['pettxoCommissionAmount'] as num?)?.round() ?? 0) * 100,
      totalAmount: (data['totalAmount'] as num?)?.round() ?? 0,
      totalAmountPaise:
          (data['totalAmountPaise'] as num?)?.round() ??
          ((data['totalAmount'] as num?)?.round() ?? 0) * 100,
      source: (data['source'] as String? ?? '').trim(),
      status: (data['status'] as String? ?? '').trim(),
      eligibleAt: _dateTime(data['eligibleAt']),
      paidAt: _dateTime(data['paidAt']),
      createdAt: _dateTime(data['createdAt']),
      updatedAt: _dateTime(data['updatedAt']),
    );
  }

  static DateTime? _dateTime(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
