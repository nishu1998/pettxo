import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/auth/domain/utils/account_security_utils.dart';
import 'package:pettexo/features/profile/domain/models/user_profile.dart';
import 'package:pettexo/features/restrictions/domain/models/user_restriction_state.dart';

void main() {
  group('AccountSecurityViewData', () {
    test('builds phone-only account state', () {
      final viewData = AccountSecurityViewData.fromSnapshot(
        profile: _profile(),
        auth: const TrustedAuthUserSnapshot(
          uid: 'uid_123',
          email: '',
          phoneNumber: '+919876541234',
          emailVerified: false,
          providerIds: ['phone'],
        ),
      );

      expect(viewData.phoneStatusLabel, 'Verified');
      expect(viewData.emailStatusLabel, 'Not added');
      expect(viewData.passwordStatusLabel, 'Not added');
      expect(viewData.canAddEmailPassword, isTrue);
      expect(viewData.canChangePassword, isFalse);
      expect(viewData.canChangePhoneNumber, isTrue);
      expect(viewData.canChangeUsername, isTrue);
      expect(viewData.canManagePendingEmailVerification, isFalse);
    });

    test('builds email and phone account state', () {
      final viewData = AccountSecurityViewData.fromSnapshot(
        profile: _profile(),
        auth: const TrustedAuthUserSnapshot(
          uid: 'uid_123',
          email: 'nishant@gmail.com',
          phoneNumber: '+919876541234',
          emailVerified: true,
          providerIds: ['password', 'phone'],
        ),
      );

      expect(viewData.emailStatusLabel, 'Verified');
      expect(viewData.passwordStatusLabel, 'Enabled');
      expect(viewData.canAddEmailPassword, isFalse);
      expect(viewData.canChangePassword, isTrue);
      expect(viewData.canChangeEmail, isTrue);
      expect(viewData.canChangePhoneNumber, isTrue);
      expect(viewData.canManagePendingEmailVerification, isFalse);
    });

    test('builds pending linked-email state', () {
      final viewData = AccountSecurityViewData.fromSnapshot(
        profile: _profile(),
        auth: const TrustedAuthUserSnapshot(
          uid: 'uid_123',
          email: 'nishant@gmail.com',
          phoneNumber: '+919876541234',
          emailVerified: false,
          providerIds: ['password', 'phone'],
        ),
      );

      expect(
        viewData.emailState,
        AccountSecurityEmailState.pendingVerification,
      );
      expect(viewData.emailStatusLabel, 'Pending verification');
      expect(viewData.passwordStatusLabel, 'Enabled');
      expect(viewData.canManagePendingEmailVerification, isTrue);
    });

    test('builds pending changed-email state', () {
      final viewData = AccountSecurityViewData.fromSnapshot(
        profile: _profile(),
        auth: const TrustedAuthUserSnapshot(
          uid: 'uid_123',
          email: 'old@gmail.com',
          phoneNumber: '+919876541234',
          emailVerified: true,
          providerIds: ['password', 'phone'],
        ),
        pendingEmailChange: 'new@gmail.com',
      );

      expect(viewData.emailDisplay, 'ne••••@gmail.com');
      expect(viewData.emailStatusLabel, 'Pending verification');
      expect(viewData.hasPendingEmailChange, isTrue);
      expect(viewData.canChangeEmail, isFalse);
      expect(viewData.canManagePendingEmailVerification, isTrue);
    });
  });

  group('account security helpers', () {
    test('derives trusted providers uniquely and in order', () {
      expect(deriveTrustedProviderIds(['phone', 'password', 'phone', '']), [
        'password',
        'phone',
      ]);
    });

    test('masks email and phone values for display', () {
      expect(maskEmail('nishant@gmail.com'), 'ni••••@gmail.com');
      expect(maskPhoneNumber('+919876541234'), '+91 ••••••1234');
    });
  });
}

UserProfile _profile() {
  return const UserProfile(
    uid: 'uid_123',
    displayName: 'Nishant',
    photoUrl: '',
    email: '',
    emailVerified: false,
    role: 'petParent',
    name: 'Nishant',
    username: 'nishant.pet',
    usernameLowercase: 'nishant.pet',
    phoneNumber: '+919876541234',
    phoneVerified: true,
    providers: ['phone'],
    phone: '+919876541234',
    country: '',
    state: 'Maharashtra',
    city: 'Mumbai',
    address: '',
    legacyLocation: '',
    bio: '',
    profileImageUrl: '',
    ratingAverage: 0,
    ratingCount: 0,
    followingCount: 0,
    followerCount: 0,
    hasFollowCounts: false,
    accountStatus: 'active',
    isDeleted: false,
    isActive: true,
    deletionRequested: false,
    profileVisibility: 'public',
    restrictionState: UserRestrictionState.unrestricted,
    createdAt: null,
    updatedAt: null,
    acceptedTermsAt: null,
    acceptedPrivacyAt: null,
    acceptedProviderAgreementAt: null,
  );
}
