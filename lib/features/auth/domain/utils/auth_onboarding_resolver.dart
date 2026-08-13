import '../../../../core/identity/username_utils.dart';

enum AuthOnboardingState {
  signedOut,
  accountRecoveryRequired,
  emailVerificationRequired,
  phoneLinkRequired,
  onboardingConsentRequired,
  roleSelectionRequired,
  profileDetailsRequired,
  authenticated,
}

class AuthIdentitySnapshot {
  final String uid;
  final String email;
  final String phoneNumber;
  final bool emailVerified;
  final List<String> providerIds;

  const AuthIdentitySnapshot({
    required this.uid,
    required this.email,
    required this.phoneNumber,
    required this.emailVerified,
    required this.providerIds,
  });

  bool get hasPasswordProvider => providerIds.contains('password');
  bool get hasPhoneProvider => providerIds.contains('phone');
}

class ProfileCompletionSnapshot {
  final String uid;
  final String role;
  final String displayName;
  final String username;
  final String usernameLowercase;
  final String state;
  final String city;
  final String address;
  final String legacyLocation;
  final bool usernameReservationMatchesUid;
  final bool hasPublicProfile;
  final bool hasPrivateProfile;
  final String accountStatus;
  final DateTime? scheduledDeletionAt;
  final DateTime? acceptedTermsAt;
  final DateTime? acceptedPrivacyAt;
  final DateTime? acceptedProviderAgreementAt;

  const ProfileCompletionSnapshot({
    required this.uid,
    required this.role,
    required this.displayName,
    required this.username,
    required this.usernameLowercase,
    required this.state,
    required this.city,
    required this.address,
    required this.legacyLocation,
    required this.usernameReservationMatchesUid,
    required this.hasPublicProfile,
    required this.hasPrivateProfile,
    required this.accountStatus,
    required this.scheduledDeletionAt,
    required this.acceptedTermsAt,
    required this.acceptedPrivacyAt,
    required this.acceptedProviderAgreementAt,
  });

  bool get hasPersistedLegalAcceptance =>
      acceptedTermsAt != null && acceptedPrivacyAt != null;
}

class AuthOnboardingResolution {
  final AuthOnboardingState state;
  final AuthIdentitySnapshot? auth;
  final ProfileCompletionSnapshot? profile;
  final bool hasPendingSignupConsent;
  final bool persistedAccountComplete;
  final bool ignoredStaleOnboardingState;
  final String reason;

  const AuthOnboardingResolution({
    required this.state,
    required this.auth,
    required this.profile,
    this.hasPendingSignupConsent = false,
    this.persistedAccountComplete = false,
    this.ignoredStaleOnboardingState = false,
    this.reason = '',
  });
}

List<String> normalizeProviderIds(Iterable<String> providerIds) {
  final normalized = providerIds
      .map((providerId) => providerId.trim())
      .where((providerId) => providerId.isNotEmpty)
      .toSet()
      .toList(growable: false);
  normalized.sort();
  return normalized;
}

bool linkedUidRemainsUnchanged({
  required String expectedUid,
  required String actualUid,
}) {
  return expectedUid.trim().isNotEmpty &&
      expectedUid.trim() == actualUid.trim();
}

bool profileHasAnyPersistedLocation(ProfileCompletionSnapshot? profile) {
  if (profile == null) return false;
  if (profile.state.trim().isNotEmpty && profile.city.trim().isNotEmpty) {
    return true;
  }
  if (profile.address.trim().isNotEmpty) return true;
  if (profile.legacyLocation.trim().isNotEmpty) return true;
  return false;
}

bool isPersistedAccountComplete(ProfileCompletionSnapshot? profile) {
  if (profile == null) return false;
  if (!profile.hasPublicProfile) return false;
  if (profile.displayName.trim().isEmpty) return false;
  if (profile.role.trim().isEmpty) return false;
  if (!profileHasAnyPersistedLocation(profile)) return false;

  final normalizedUsername = normalizeUsername(
    profile.usernameLowercase.isNotEmpty
        ? profile.usernameLowercase
        : profile.username,
  );
  if (validateNormalizedUsername(normalizedUsername) != null) {
    return false;
  }

  return true;
}

bool isProfileComplete({
  required AuthIdentitySnapshot auth,
  required ProfileCompletionSnapshot? profile,
}) {
  if (profile == null) return false;
  if (profile.uid.trim() != auth.uid.trim()) return false;
  return isPersistedAccountComplete(profile);
}

bool profileHasPersistedRole(ProfileCompletionSnapshot? profile) {
  return profile != null && profile.role.trim().isNotEmpty;
}

bool profileNeedsDetails(ProfileCompletionSnapshot? profile) {
  if (profile == null) return false;
  if (!profile.hasPublicProfile) return false;
  if (profile.role.trim().isEmpty) return false;
  if (profile.displayName.trim().isEmpty) return true;
  if (!profileHasAnyPersistedLocation(profile)) return true;

  final normalizedUsername = normalizeUsername(
    profile.usernameLowercase.isNotEmpty
        ? profile.usernameLowercase
        : profile.username,
  );
  return validateNormalizedUsername(normalizedUsername) != null;
}

AuthOnboardingResolution resolveAuthOnboardingState({
  required AuthIdentitySnapshot? auth,
  required ProfileCompletionSnapshot? profile,
  bool hasPendingSignupConsent = false,
}) {
  if (auth == null) {
    return const AuthOnboardingResolution(
      state: AuthOnboardingState.signedOut,
      auth: null,
      profile: null,
      reason: 'signed-out',
    );
  }

  final persistedAccountComplete =
      profile != null &&
      profile.uid.trim() == auth.uid.trim() &&
      isPersistedAccountComplete(profile);
  final ignoredStaleOnboardingState =
      persistedAccountComplete && hasPendingSignupConsent;

  final accountStatus = profile?.accountStatus.trim();
  if (accountStatus == 'pendingDeletion' ||
      accountStatus == 'deletionInProgress') {
    return AuthOnboardingResolution(
      state: AuthOnboardingState.accountRecoveryRequired,
      auth: auth,
      profile: profile,
      hasPendingSignupConsent: hasPendingSignupConsent,
      persistedAccountComplete: persistedAccountComplete,
      ignoredStaleOnboardingState: ignoredStaleOnboardingState,
      reason: 'account-recovery-required',
    );
  }

  if (auth.hasPasswordProvider &&
      auth.email.trim().isNotEmpty &&
      !auth.emailVerified) {
    return AuthOnboardingResolution(
      state: AuthOnboardingState.emailVerificationRequired,
      auth: auth,
      profile: profile,
      hasPendingSignupConsent: hasPendingSignupConsent,
      persistedAccountComplete: persistedAccountComplete,
      ignoredStaleOnboardingState: ignoredStaleOnboardingState,
      reason: 'email-verification-required',
    );
  }

  if (!auth.hasPhoneProvider || auth.phoneNumber.trim().isEmpty) {
    return AuthOnboardingResolution(
      state: AuthOnboardingState.phoneLinkRequired,
      auth: auth,
      profile: profile,
      hasPendingSignupConsent: hasPendingSignupConsent,
      persistedAccountComplete: persistedAccountComplete,
      ignoredStaleOnboardingState: ignoredStaleOnboardingState,
      reason: 'phone-link-required',
    );
  }

  if (persistedAccountComplete) {
    return AuthOnboardingResolution(
      state: AuthOnboardingState.authenticated,
      auth: auth,
      profile: profile,
      hasPendingSignupConsent: hasPendingSignupConsent,
      persistedAccountComplete: true,
      ignoredStaleOnboardingState: ignoredStaleOnboardingState,
      reason: ignoredStaleOnboardingState
          ? 'authenticated-persisted-account'
          : 'authenticated',
    );
  }

  final hasPersistedLegalAcceptance =
      profile?.hasPersistedLegalAcceptance == true;
  if (!hasPersistedLegalAcceptance && !hasPendingSignupConsent) {
    return AuthOnboardingResolution(
      state: AuthOnboardingState.onboardingConsentRequired,
      auth: auth,
      profile: profile,
      hasPendingSignupConsent: false,
      persistedAccountComplete: false,
      ignoredStaleOnboardingState: false,
      reason: 'signup-consent-required',
    );
  }

  if (!profileHasPersistedRole(profile)) {
    return AuthOnboardingResolution(
      state: AuthOnboardingState.roleSelectionRequired,
      auth: auth,
      profile: profile,
      hasPendingSignupConsent: hasPendingSignupConsent,
      persistedAccountComplete: false,
      ignoredStaleOnboardingState: false,
      reason: 'role-selection-required',
    );
  }

  if (profileNeedsDetails(profile) || profile == null) {
    return AuthOnboardingResolution(
      state: AuthOnboardingState.profileDetailsRequired,
      auth: auth,
      profile: profile,
      hasPendingSignupConsent: hasPendingSignupConsent,
      persistedAccountComplete: false,
      ignoredStaleOnboardingState: false,
      reason: 'profile-details-required',
    );
  }

  return AuthOnboardingResolution(
    state: AuthOnboardingState.authenticated,
    auth: auth,
    profile: profile,
    hasPendingSignupConsent: hasPendingSignupConsent,
    persistedAccountComplete: persistedAccountComplete,
    ignoredStaleOnboardingState: ignoredStaleOnboardingState,
    reason: 'authenticated-fallback',
  );
}
