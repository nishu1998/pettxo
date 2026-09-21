import 'package:cloud_firestore/cloud_firestore.dart';

/// Identifies invalid field names without retaining their values or documents.
class ProviderEarningFormatException extends FormatException {
  ProviderEarningFormatException(this.documentId, List<String> fields)
    : invalidFields = List.unmodifiable(fields),
      super('Earnings record requires reconciliation');
  final String documentId;
  final List<String> invalidFields;
}

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
    final invalid = <String>[
      if (data['earningsSchemaVersion'] != 1) 'earningsSchemaVersion',
      if (!const {
        'PROVISIONAL',
        'HELD',
        'FINALIZED',
        'ADJUSTED',
      }.contains(phase))
        'earningsStatus',
      if (!data.containsKey('providerFinalEntitlementPaise') ||
          (amount != null &&
              (amount is! num ||
                  !amount.isFinite ||
                  amount < 0 ||
                  amount > 9007199254740991 ||
                  amount != amount.truncateToDouble())) ||
          (const {'FINALIZED', 'ADJUSTED'}.contains(phase) && amount == null))
        'providerFinalEntitlementPaise',
      if (bookingId is! String ||
          bookingId.trim().isEmpty ||
          bookingId.contains('/'))
        'bookingId',
      if (providerId is! String || providerId.trim().isEmpty) 'providerId',
    ];
    if (invalid.isNotEmpty) throw ProviderEarningFormatException(id, invalid);
    return ProviderEarningRecord(
      id: id,
      bookingId: (bookingId as String).trim(),
      providerId: (providerId as String).trim(),
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
