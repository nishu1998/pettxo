import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/auth/domain/utils/auth_error_utils.dart';
import 'package:pettexo/features/auth/domain/utils/auth_onboarding_resolver.dart';

void main() {
  group('resolveAuthOnboardingState', () {
    const completeProfile = ProfileCompletionSnapshot(
      uid: 'uid_123',
      role: 'petParent',
      displayName: 'Nishant',
      username: 'nishant.pet',
      usernameLowercase: 'nishant.pet',
      state: 'Maharashtra',
      city: 'Mumbai',
      usernameReservationMatchesUid: true,
      accountStatus: 'active',
      scheduledDeletionAt: null,
    );

    test('returns signedOut when auth is missing', () {
      final resolution = resolveAuthOnboardingState(auth: null, profile: null);
      expect(resolution.state, AuthOnboardingState.signedOut);
    });

    test('returns emailVerificationRequired for unverified email user', () {
      final resolution = resolveAuthOnboardingState(
        auth: const AuthIdentitySnapshot(
          uid: 'uid_123',
          email: 'hello@example.com',
          phoneNumber: '',
          emailVerified: false,
          providerIds: ['password'],
        ),
        profile: null,
      );

      expect(resolution.state, AuthOnboardingState.emailVerificationRequired);
    });

    test('returns phoneLinkRequired for verified email user without phone', () {
      final resolution = resolveAuthOnboardingState(
        auth: const AuthIdentitySnapshot(
          uid: 'uid_123',
          email: 'hello@example.com',
          phoneNumber: '',
          emailVerified: true,
          providerIds: ['password'],
        ),
        profile: null,
      );

      expect(resolution.state, AuthOnboardingState.phoneLinkRequired);
    });

    test(
      'returns profileCompletionRequired for fully linked user without profile',
      () {
        final resolution = resolveAuthOnboardingState(
          auth: const AuthIdentitySnapshot(
            uid: 'uid_123',
            email: 'hello@example.com',
            phoneNumber: '+919999999999',
            emailVerified: true,
            providerIds: ['password', 'phone'],
          ),
          profile: null,
        );

        expect(resolution.state, AuthOnboardingState.profileCompletionRequired);
      },
    );

    test('returns authenticated for complete phone-only user', () {
      final resolution = resolveAuthOnboardingState(
        auth: const AuthIdentitySnapshot(
          uid: 'uid_123',
          email: '',
          phoneNumber: '+919999999999',
          emailVerified: false,
          providerIds: ['phone'],
        ),
        profile: completeProfile,
      );

      expect(resolution.state, AuthOnboardingState.authenticated);
    });

    test('returns authenticated for fully linked complete user', () {
      final resolution = resolveAuthOnboardingState(
        auth: const AuthIdentitySnapshot(
          uid: 'uid_123',
          email: 'hello@example.com',
          phoneNumber: '+919999999999',
          emailVerified: true,
          providerIds: ['password', 'phone'],
        ),
        profile: completeProfile,
      );

      expect(resolution.state, AuthOnboardingState.authenticated);
    });

    test('returns accountRecoveryRequired for pending deletion profile', () {
      final resolution = resolveAuthOnboardingState(
        auth: const AuthIdentitySnapshot(
          uid: 'uid_123',
          email: 'hello@example.com',
          phoneNumber: '+919999999999',
          emailVerified: true,
          providerIds: ['password', 'phone'],
        ),
        profile: const ProfileCompletionSnapshot(
          uid: 'uid_123',
          role: 'petParent',
          displayName: 'Nishant',
          username: 'nishant.pet',
          usernameLowercase: 'nishant.pet',
          state: 'Maharashtra',
          city: 'Mumbai',
          usernameReservationMatchesUid: true,
          accountStatus: 'pendingDeletion',
          scheduledDeletionAt: null,
        ),
      );

      expect(resolution.state, AuthOnboardingState.accountRecoveryRequired);
    });

    test(
      'returns profileCompletionRequired for username reservation mismatch',
      () {
        final resolution = resolveAuthOnboardingState(
          auth: const AuthIdentitySnapshot(
            uid: 'uid_123',
            email: '',
            phoneNumber: '+919999999999',
            emailVerified: false,
            providerIds: ['phone'],
          ),
          profile: const ProfileCompletionSnapshot(
            uid: 'uid_123',
            role: 'petParent',
            displayName: 'Nishant',
            username: 'nishant.pet',
            usernameLowercase: 'nishant.pet',
            state: 'Maharashtra',
            city: 'Mumbai',
            usernameReservationMatchesUid: false,
            accountStatus: 'active',
            scheduledDeletionAt: null,
          ),
        );

        expect(resolution.state, AuthOnboardingState.profileCompletionRequired);
      },
    );
  });

  group('auth identity helpers', () {
    test('normalizes provider ids uniquely and in sorted order', () {
      expect(
        normalizeProviderIds(['phone', 'password', 'phone', '', 'google.com']),
        ['google.com', 'password', 'phone'],
      );
    });

    test('linked uid must remain unchanged for email-first phone linking', () {
      expect(
        linkedUidRemainsUnchanged(expectedUid: 'uid_123', actualUid: 'uid_123'),
        isTrue,
      );
      expect(
        linkedUidRemainsUnchanged(
          expectedUid: 'uid_123',
          actualUid: 'uid_other',
        ),
        isFalse,
      );
    });
  });

  group('mapFirebaseAuthErrorCode', () {
    test('maps collision and credential errors clearly', () {
      expect(
        mapFirebaseAuthErrorCode('email-already-in-use'),
        contains('already exists with this email'),
      );
      expect(
        mapFirebaseAuthErrorCode('credential-already-in-use'),
        contains('already linked to another Pettxo account'),
      );
      expect(
        mapFirebaseAuthErrorCode('provider-already-linked'),
        contains('already linked'),
      );
      expect(
        mapFirebaseAuthErrorCode('invalid-credential'),
        contains('invalid or has expired'),
      );
      expect(
        mapFirebaseAuthErrorCode('username-taken'),
        contains('already taken'),
      );
      expect(
        mapFirebaseAuthErrorCode('invalid-username'),
        contains('Choose a valid username'),
      );
      expect(mapFirebaseAuthErrorCode('user-disabled'), contains('disabled'));
    });
  });
}
