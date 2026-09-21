import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:pettexo/features/bookings/data/provider_earnings_diagnostics.dart';
import 'package:pettexo/features/bookings/domain/models/provider_earning_record.dart';

void main() {
  test(
    'legacy projection identifies fields without leaking raw financial data',
    () {
      expect(
        () => ProviderEarningRecord.fromMap('legacy-1', {
          'providerId': 'provider-a',
          'bookingId': 'booking-1',
          'amount': 1.90,
          'bankDetails': 'SECRET',
        }),
        throwsA(
          isA<ProviderEarningFormatException>()
              .having((e) => e.documentId, 'document ID', 'legacy-1')
              .having(
                (e) => e.invalidFields,
                'invalid fields',
                containsAll([
                  'earningsSchemaVersion',
                  'earningsStatus',
                  'providerFinalEntitlementPaise',
                ]),
              )
              .having(
                (e) => e.toString(),
                'safe error',
                isNot(contains('SECRET')),
              ),
        ),
      );
    },
  );
  test(
    'malformed canonical entitlement is still rejected without rounding',
    () {
      for (final value in ['85', -1, 1.5, double.nan]) {
        expect(
          () => ProviderEarningRecord.fromMap('canonical-1', {
            'providerId': 'provider-a',
            'bookingId': 'booking-1',
            'earningsSchemaVersion': 1,
            'earningsStatus': 'FINALIZED',
            'providerFinalEntitlementPaise': value,
          }),
          throwsA(
            isA<ProviderEarningFormatException>().having(
              (e) => e.invalidFields,
              'field',
              ['providerFinalEntitlementPaise'],
            ),
          ),
        );
      }
    },
  );
  test(
    'callable diagnostics expose only allowlisted reason, never raw details',
    () {
      final diagnostic = providerEarningsErrorDiagnostic(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'SECRET bank details',
          details: {
            'code': 'EARNINGS_RECONCILIATION_REQUIRED',
            'token': 'SECRET',
          },
        ),
      );
      expect(diagnostic['firebaseCode'], 'failed-precondition');
      expect(diagnostic['reasonCode'], 'EARNINGS_RECONCILIATION_REQUIRED');
      expect(diagnostic.toString(), isNot(contains('SECRET')));
      expect(
        providerEarningsErrorDiagnostic(Exception('SECRET')).toString(),
        isNot(contains('SECRET')),
      );
    },
  );
}
