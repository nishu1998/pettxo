/// Full-history earned entitlement. This is not a wallet or unpaid balance.
class ProviderEarningsSummary {
  const ProviderEarningsSummary({
    required this.providerId,
    required this.lifetimeEarnedPaise,
    required this.finalizedRecordCount,
    required this.provisionalRecordCount,
    required this.asOf,
  });

  final String providerId;
  final int lifetimeEarnedPaise;
  final int finalizedRecordCount;
  final int provisionalRecordCount;
  final DateTime asOf;

  factory ProviderEarningsSummary.fromMap(Map<String, dynamic> data) {
    int integer(String key) {
      final value = data[key];
      if (value is! num ||
          !value.isFinite ||
          value < 0 ||
          value > 9007199254740991 ||
          value != value.truncateToDouble()) {
        throw FormatException('Invalid earnings summary field: $key');
      }
      return value.toInt();
    }

    final providerId = data['providerId'];
    final asOfValue = data['asOf'];
    final asOf = asOfValue is String ? DateTime.tryParse(asOfValue) : null;
    if (providerId is! String ||
        providerId.trim().isEmpty ||
        data['projectionVersion'] != 1 ||
        data['currency'] != 'INR' ||
        asOf == null) {
      throw const FormatException('Invalid provider earnings summary');
    }
    return ProviderEarningsSummary(
      providerId: providerId,
      lifetimeEarnedPaise: integer('lifetimeEarnedPaise'),
      finalizedRecordCount: integer('finalizedRecordCount'),
      provisionalRecordCount: integer('provisionalRecordCount'),
      asOf: asOf,
    );
  }
}
