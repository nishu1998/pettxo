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
  if (record.isProvisional) return 'Earning pending finalization';
  return 'Earned';
}

/// Payout metadata never determines whether the entitlement is final.
String? earningsPayoutLabel(ProviderEarningRecord record) {
  if (record.isProvisional || record.finalEntitlementPaise == 0) return null;
  return switch (record.status) {
    'HOLD' || 'HELD' => 'Payout: On hold',
    'READY' => 'Payout: Eligible',
    'PAID' || 'COMPLETED' => 'Payout: Paid',
    'PROCESSING' => 'Payout: Processing',
    'NEEDS_ATTENTION' => 'Payout: Needs attention',
    'FAILED' => 'Payout: Failed',
    'CANCELLED' => 'Payout: Cancelled',
    _ => null,
  };
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
      _ => 'Booking earning',
    };

String formatEarningsDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}
