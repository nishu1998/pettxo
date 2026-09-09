import 'package:cloud_firestore/cloud_firestore.dart';

/// Canonical earned entitlement, independent of payment to the provider.
class ProviderEarningRecord {
  const ProviderEarningRecord({
    required this.id,
    required this.bookingId,
    required this.providerId,
    required this.finalEntitlementPaise,
    required this.earningsStatus,
    required this.earningsOutcome,
    required this.status,
    this.earningsOutcomeAt,
    this.updatedAt,
    this.createdAt,
  });

  final String id;
  final String bookingId;
  final String providerId;
  final int? finalEntitlementPaise;
  final String earningsStatus;
  final String earningsOutcome;
  final String status;
  final DateTime? earningsOutcomeAt;
  final DateTime? updatedAt;
  final DateTime? createdAt;

  bool get isProvisional => finalEntitlementPaise == null;
  bool get isVisible =>
      earningsOutcome != 'NO_EARNING_RECORD_REQUIRED' &&
      finalEntitlementPaise != 0;
  DateTime? get displayDate => earningsOutcomeAt ?? updatedAt ?? createdAt;
  String get dateLabel => earningsOutcomeAt != null
      ? 'Outcome date'
      : updatedAt != null
      ? 'Updated'
      : 'Recorded';

  factory ProviderEarningRecord.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => ProviderEarningRecord.fromMap(snapshot.id, snapshot.data() ?? {});

  factory ProviderEarningRecord.fromMap(String id, Map<String, dynamic> data) {
    final amount = data['providerFinalEntitlementPaise'];
    final phase = data['earningsStatus'];
    final bookingId = data['bookingId'];
    final providerId = data['providerId'];
    if (data['earningsSchemaVersion'] != 1 ||
        !data.containsKey('providerFinalEntitlementPaise') ||
        !const {
          'PROVISIONAL',
          'HELD',
          'FINALIZED',
          'ADJUSTED',
        }.contains(phase) ||
        (amount != null &&
            (amount is! num ||
                !amount.isFinite ||
                amount < 0 ||
                amount > 9007199254740991 ||
                amount != amount.truncateToDouble())) ||
        (const {'FINALIZED', 'ADJUSTED'}.contains(phase) && amount == null) ||
        bookingId is! String ||
        bookingId.trim().isEmpty ||
        bookingId.contains('/') ||
        providerId is! String ||
        providerId.trim().isEmpty) {
      throw const FormatException('Earnings record requires reconciliation');
    }
    return ProviderEarningRecord(
      id: id,
      bookingId: bookingId.trim(),
      providerId: providerId.trim(),
      finalEntitlementPaise: (amount as num?)?.toInt(),
      earningsStatus: phase as String,
      earningsOutcome: data['earningsOutcome'] is String
          ? data['earningsOutcome'] as String
          : '',
      status: data['status'] is String
          ? (data['status'] as String).toUpperCase()
          : '',
      earningsOutcomeAt: _dateTime(data['earningsOutcomeAt']),
      updatedAt: _dateTime(data['updatedAt']),
      createdAt: _dateTime(data['createdAt']),
    );
  }

  static DateTime? _dateTime(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
