import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/data/repositories/booking_repository.dart';
import 'package:pettexo/features/bookings/domain/models/canonical_booking_request_models.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() {
  group('canonical booking request error mapping', () {
    test('maps invalid timezone details to schedule verification guidance', () {
      final exception = mapCanonicalBookingRequestFunctionsException(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Provider timezone configuration is invalid.',
          details: const <String, dynamic>{
            'code': 'INVALID_TIMEZONE',
            'issues': <String>['INVALID_TIMEZONE:Unsupported timezone'],
          },
        ),
      );

      expect(
        exception.code,
        CanonicalBookingRequestFailureCode.invalidTimezone,
      );
      expect(
        exception.message,
        'We could not verify the provider schedule right now.',
      );
    });

    test('hides raw internal fallback text from customers', () {
      expect(
        canonicalBookingRequestMessage(
          CanonicalBookingRequestFailureCode.unknown,
          'internal',
        ),
        'We could not send your request right now.',
      );
    });
  });

  group('canonical payment callable auth recovery', () {
    test(
      'retries unauthenticated callable once when a Firebase user exists',
      () async {
        var attempts = 0;
        var refreshCount = 0;

        final result =
            await runCanonicalPaymentCallableWithAuthRecovery<String>(
              operationName: 'createBookingQrPaymentV3',
              currentUserProvider: () => _FakeUser(uid: 'customer-1'),
              refreshToken: (user) async {
                refreshCount += 1;
              },
              invoke: () async {
                attempts += 1;
                if (attempts == 1) {
                  throw FirebaseFunctionsException(
                    code: 'unauthenticated',
                    message: 'Auth context missing.',
                  );
                }
                return 'ok';
              },
            );

        expect(result, 'ok');
        expect(attempts, 2);
        expect(refreshCount, 1);
      },
    );

    test(
      'still retries after token refresh failure when user remains signed in',
      () async {
        var attempts = 0;

        final result =
            await runCanonicalPaymentCallableWithAuthRecovery<String>(
              operationName: 'createBookingQrPaymentV3',
              currentUserProvider: () => _FakeUser(uid: 'customer-1'),
              refreshToken: (user) async {
                throw StateError('refresh failed');
              },
              invoke: () async {
                attempts += 1;
                if (attempts == 1) {
                  throw FirebaseFunctionsException(
                    code: 'unauthenticated',
                    message: 'Auth context missing.',
                  );
                }
                return 'ok';
              },
            );

        expect(result, 'ok');
        expect(attempts, 2);
      },
    );

    test(
      'does not retry unauthenticated callable without a Firebase user',
      () async {
        var attempts = 0;

        await expectLater(
          () => runCanonicalPaymentCallableWithAuthRecovery<String>(
            operationName: 'createBookingQrPaymentV3',
            currentUserProvider: () => null,
            invoke: () async {
              attempts += 1;
              throw FirebaseFunctionsException(
                code: 'unauthenticated',
                message: 'Auth context missing.',
              );
            },
          ),
          throwsA(isA<FirebaseFunctionsException>()),
        );

        expect(attempts, 1);
      },
    );
  });
}

class _FakeUser implements User {
  _FakeUser({required this.uid});

  @override
  final String uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
