import '../../domain/models/provider_earning_record.dart';

/// Keep stored paise integer throughout formatting, including on the web.
String formatEarningsPaise(int paise) {
  final whole = (paise ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '₹$whole.${(paise % 100).toString().padLeft(2, '0')}';
}

String earningsStatusLabel(ProviderEarningRecord record) {
  if (record.earningsStatus == 'HELD' || record.status == 'HELD') {
    return 'On Hold';
  }
  if (record.isProvisional) return 'Not final yet';
  if (record.status == 'PAID') return 'Paid';
  return 'Earned';
}

String earningsOutcomeLabel(ProviderEarningRecord record) =>
    switch (record.earningsOutcome) {
      'CUSTOMER_CANCELLATION' => 'Cancellation compensation',
      'PROVIDER_CANCELLATION' => 'Cancelled',
      'NO_SHOW' => 'No-show earning',
      'DISPUTE_RESOLUTION' => 'Dispute resolved',
      'OPEN_DISPUTE' => 'Under review',
      'CANONICAL_REFUND_REVIEW' => 'Under review',
      'PAYMENT_CONFIRMED' => 'Booking confirmed',
      'COMPLETION_REVIEW' => 'Completion under review',
      _ => 'Service earning',
    };

String formatEarningsDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}
