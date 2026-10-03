import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/auth/domain/models/email_verification_mode.dart';
import 'package:pettexo/features/auth/domain/utils/email_verification_controller.dart';

void main() {
  group('EmailVerificationMode', () {
    test('distinguishes blocking and non-blocking flows', () {
      expect(EmailVerificationMode.blockingOnboarding.blocksAppAccess, isTrue);
      expect(
        EmailVerificationMode.nonBlockingLinkedEmail.blocksAppAccess,
        isFalse,
      );
    });
  });

  group('EmailVerificationController', () {
    test('reloads, refreshes token, and syncs a verified identity', () async {
      final calls = <String>[];
      final controller = _controller(
        reload: () async => calls.add('reload'),
        refreshToken: () async => calls.add('token'),
        sync: () async => calls.add('sync'),
      );

      expect(
        await controller.refreshVerificationStatus(),
        EmailVerificationRefreshResult.verified,
      );
      expect(calls, <String>['reload', 'token', 'sync']);
    });

    test('does not refresh or sync when email is still pending', () async {
      var tokenRefreshes = 0;
      var syncs = 0;
      final controller = _controller(
        verified: false,
        refreshToken: () async => tokenRefreshes += 1,
        sync: () async => syncs += 1,
      );

      expect(
        await controller.refreshVerificationStatus(),
        EmailVerificationRefreshResult.pending,
      );
      expect(tokenRefreshes, 0);
      expect(syncs, 0);
    });

    test('requires reauthentication when reload invalidates session', () async {
      final error = _SessionInvalidError();
      final controller = _controller(
        reload: () async => throw error,
        sessionInvalid: (candidate) => identical(candidate, error),
      );

      expect(
        await controller.refreshVerificationStatus(),
        EmailVerificationRefreshResult.reauthenticationRequired,
      );
    });

    test(
      'requires reauthentication when token refresh invalidates session',
      () async {
        final error = _SessionInvalidError();
        var syncs = 0;
        final controller = _controller(
          refreshToken: () async => throw error,
          sync: () async => syncs += 1,
          sessionInvalid: (candidate) => identical(candidate, error),
        );

        expect(
          await controller.refreshVerificationStatus(),
          EmailVerificationRefreshResult.reauthenticationRequired,
        );
        expect(syncs, 0);
      },
    );

    test('requires reauthentication when current user disappears', () async {
      final controller = _controller(uid: '');

      expect(
        await controller.refreshVerificationStatus(),
        EmailVerificationRefreshResult.reauthenticationRequired,
      );
    });

    test('rejects a different UID without syncing the profile', () async {
      var syncs = 0;
      final controller = _controller(
        uid: 'different-uid',
        sync: () async => syncs += 1,
      );

      await expectLater(
        controller.refreshVerificationStatus(),
        throwsA(isA<EmailVerificationIdentityChangedException>()),
      );
      expect(syncs, 0);
    });

    test(
      'surfaces reload and token network failures without syncing',
      () async {
        for (final failReload in <bool>[true, false]) {
          var syncs = 0;
          final controller = _controller(
            reload: () async {
              if (failReload) throw StateError('network unavailable');
            },
            refreshToken: () async {
              if (!failReload) throw StateError('network unavailable');
            },
            sync: () async => syncs += 1,
          );

          await expectLater(
            controller.refreshVerificationStatus(),
            throwsA(isA<StateError>()),
          );
          expect(syncs, 0);
        }
      },
    );
  });
}

EmailVerificationController _controller({
  Future<void> Function()? reload,
  Future<void> Function()? refreshToken,
  Future<void> Function()? sync,
  bool verified = true,
  String uid = 'stable-uid',
  bool Function(Object error)? sessionInvalid,
}) {
  return EmailVerificationController(
    reloadCurrentUser: reload ?? () async {},
    refreshIdToken: refreshToken ?? () async {},
    currentUid: () => uid,
    isEmailVerified: () => verified,
    syncTrustedAuthIdentity: sync ?? () async {},
    isSessionInvalidError: sessionInvalid ?? (_) => false,
    expectedUid: 'stable-uid',
  );
}

class _SessionInvalidError implements Exception {}
