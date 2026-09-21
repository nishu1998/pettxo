import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/domain/models/provider_earning_record.dart';
import 'package:pettexo/features/bookings/presentation/utils/provider_earnings_presentation.dart';

void main() {
  for (final entry in {
    'READY': 'Eligible',
    'HELD': 'On hold',
    'hold': 'On hold',
    'PROCESSING': 'Processing',
    'COMPLETED': 'Paid',
    'NEEDS_ATTENTION': 'Needs attention',
  }.entries) {
    test('final no-show entitlement remains earned during ${entry.key}', () {
      final record = ProviderEarningRecord.fromMap('booking', {
        'bookingId': 'booking',
        'providerId': 'provider',
        'earningsSchemaVersion': 1,
        'earningsStatus': 'FINALIZED',
        'earningsOutcome': 'NO_SHOW',
        'providerFinalEntitlementPaise': 85000,
        'status': entry.key,
        'customerPaidPaise': 90000,
        'serviceSubtotalPaise': 100000,
      });
      expect(earningsStatusLabel(record), 'Earned');
      expect(formatEarningsPaise(record.finalEntitlementPaise!), '₹850.00');
      expect(earningsPayoutLabel(record), 'Payout: ${entry.value}');
    });
  }
}
