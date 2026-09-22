import 'package:cloud_functions/cloud_functions.dart';
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
      address: '',
      legacyLocation: '',
      usernameReservationMatchesUid: true,
      hasPublicProfile: true,
      hasPrivateProfile: true,
      accountStatus: 'active',
      scheduledDeletionAt: null,
      acceptedTermsAt: null,
      acceptedPrivacyAt: null,
      acceptedProviderAgreementAt: null,
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
      'returns onboardingConsentRequired for linked user without profile',
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
          hasPendingSignupConsent: false,
        );

        expect(resolution.state, AuthOnboardingState.onboardingConsentRequired);
      },
    );

    test(
      'returns roleSelectionRequired after consent when role is missing',
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
            role: '',
            displayName: '',
            username: '',
            usernameLowercase: '',
            state: '',
            city: '',
            address: '',
            legacyLocation: '',
            usernameReservationMatchesUid: false,
            hasPublicProfile: false,
            hasPrivateProfile: true,
            accountStatus: 'active',
            scheduledDeletionAt: null,
            acceptedTermsAt: null,
            acceptedPrivacyAt: null,
            acceptedProviderAgreementAt: null,
          ),
          hasPendingSignupConsent: true,
        );

        expect(resolution.state, AuthOnboardingState.roleSelectionRequired);
      },
    );

    test(
      'returns profileDetailsRequired when role exists but details are incomplete',
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
            displayName: '',
            username: '',
            usernameLowercase: '',
            state: '',
            city: '',
            address: '',
            legacyLocation: '',
            usernameReservationMatchesUid: false,
            hasPublicProfile: true,
            hasPrivateProfile: true,
            accountStatus: 'active',
            scheduledDeletionAt: null,
            acceptedTermsAt: null,
            acceptedPrivacyAt: null,
            acceptedProviderAgreementAt: null,
          ),
          hasPendingSignupConsent: true,
        );

        expect(resolution.state, AuthOnboardingState.profileDetailsRequired);
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
          address: '',
          legacyLocation: '',
          usernameReservationMatchesUid: true,
          hasPublicProfile: true,
          hasPrivateProfile: true,
          accountStatus: 'pendingDeletion',
          scheduledDeletionAt: null,
          acceptedTermsAt: null,
          acceptedPrivacyAt: null,
          acceptedProviderAgreementAt: null,
        ),
      );

      expect(resolution.state, AuthOnboardingState.accountRecoveryRequired);
    });

    test(
      'keeps completed accounts authenticated even when username reservation lookup mismatches',
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
            address: '',
            legacyLocation: '',
            usernameReservationMatchesUid: false,
            hasPublicProfile: true,
            hasPrivateProfile: true,
            accountStatus: 'active',
            scheduledDeletionAt: null,
            acceptedTermsAt: null,
            acceptedPrivacyAt: null,
            acceptedProviderAgreementAt: null,
          ),
        );

        expect(resolution.state, AuthOnboardingState.authenticated);
      },
    );

    test(
      'completed persisted account overrides stale pending signup consent',
      () {
        final resolution = resolveAuthOnboardingState(
          auth: const AuthIdentitySnapshot(
            uid: 'uid_123',
            email: '',
            phoneNumber: '+919999999999',
            emailVerified: false,
            providerIds: ['phone'],
          ),
          profile: completeProfile,
          hasPendingSignupConsent: true,
        );

        expect(resolution.state, AuthOnboardingState.authenticated);
        expect(resolution.persistedAccountComplete, isTrue);
        expect(resolution.ignoredStaleOnboardingState, isTrue);
      },
    );

    test(
      'legacy location fields still count as a completed persisted account',
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
            state: '',
            city: '',
            address: '',
            legacyLocation: 'Mumbai, Maharashtra',
            usernameReservationMatchesUid: true,
            hasPublicProfile: true,
            hasPrivateProfile: true,
            accountStatus: 'active',
            scheduledDeletionAt: null,
            acceptedTermsAt: null,
            acceptedPrivacyAt: null,
            acceptedProviderAgreementAt: null,
          ),
          hasPendingSignupConsent: true,
        );

        expect(resolution.state, AuthOnboardingState.authenticated);
        expect(resolution.persistedAccountComplete, isTrue);
      },
    );
  });

  group('selected-role profile details entry', () {
    const phoneAuth = AuthIdentitySnapshot(
      uid: 'phone_uid',
      email: '',
      phoneNumber: '+919999999999',
      emailVerified: false,
      providerIds: ['phone'],
    );
    const linkedEmailAuth = AuthIdentitySnapshot(
      uid: 'email_uid',
      email: 'new@example.com',
      phoneNumber: '+918888888888',
      emailVerified: true,
      providerIds: ['password', 'phone'],
    );

    for (final entry in <String, AuthIdentitySnapshot>{
      'phone': phoneAuth,
      'email': linkedEmailAuth,
    }.entries) {
      for (final role in <String>['petParent', 'serviceProvider', 'petLover']) {
        test(
          '${entry.key} new user can continue $role details before role persistence',
          () {
            final resolution = resolveAuthOnboardingState(
              auth: entry.value,
              profile: null,
              hasPendingSignupConsent: true,
            );

            expect(resolution.state, AuthOnboardingState.roleSelectionRequired);
            expect(canContinueSelectedProfileDetails(resolution.state), isTrue);
          },
        );
      }
    }

    test('incomplete persisted profile remains a valid details entry', () {
      expect(
        canContinueSelectedProfileDetails(
          AuthOnboardingState.profileDetailsRequired,
        ),
        isTrue,
      );
    });

    test('completed returning account does not re-enter profile details', () {
      expect(
        canContinueSelectedProfileDetails(AuthOnboardingState.authenticated),
        isFalse,
      );
    });
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

    test(
      'maps onboarding permission failure without exposing backend text',
      () {
        final error = mapFunctionsActionException(
          FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'sensitive backend implementation detail',
          ),
        );

        expect(error.code, 'permission-denied');
        expect(error.message, 'Authentication error. Please try again.');
        expect(error.message, isNot(contains('sensitive')));
      },
    );
  });
}
