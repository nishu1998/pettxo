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
    test('invokes trusted sync after verification succeeds', () async {
      var reloaded = false;
      var synced = false;

      final controller = EmailVerificationController(
        reloadCurrentUser: () async {
          reloaded = true;
        },
        isEmailVerified: () => true,
        syncTrustedAuthIdentity: () async {
          synced = true;
        },
      );

      final verified = await controller.refreshVerificationStatus();

      expect(verified, isTrue);
      expect(reloaded, isTrue);
      expect(synced, isTrue);
    });

    test('does not sync when email is still pending', () async {
      var synced = false;

      final controller = EmailVerificationController(
        reloadCurrentUser: () async {},
        isEmailVerified: () => false,
        syncTrustedAuthIdentity: () async {
          synced = true;
        },
      );

      final verified = await controller.refreshVerificationStatus();

      expect(verified, isFalse);
      expect(synced, isFalse);
    });
  });
}
