import '../../../../core/identity/username_utils.dart';

enum AuthOnboardingState {
  signedOut,
  accountRecoveryRequired,
  emailVerificationRequired,
  phoneLinkRequired,
  profileCompletionRequired,
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
  final bool usernameReservationMatchesUid;
  final String accountStatus;
  final DateTime? scheduledDeletionAt;

  const ProfileCompletionSnapshot({
    required this.uid,
    required this.role,
    required this.displayName,
    required this.username,
    required this.usernameLowercase,
    required this.state,
    required this.city,
    required this.usernameReservationMatchesUid,
    required this.accountStatus,
    required this.scheduledDeletionAt,
  });
}

class AuthOnboardingResolution {
  final AuthOnboardingState state;
  final AuthIdentitySnapshot? auth;
  final ProfileCompletionSnapshot? profile;

  const AuthOnboardingResolution({
    required this.state,
    required this.auth,
    required this.profile,
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

bool isProfileComplete({
  required AuthIdentitySnapshot auth,
  required ProfileCompletionSnapshot? profile,
}) {
  if (profile == null) return false;
  if (profile.uid.trim() != auth.uid.trim()) return false;
  if (profile.displayName.trim().isEmpty) return false;
  if (profile.role.trim().isEmpty) return false;
  if (profile.state.trim().isEmpty) return false;
  if (profile.city.trim().isEmpty) return false;

  final normalizedUsername = normalizeUsername(
    profile.usernameLowercase.isNotEmpty
        ? profile.usernameLowercase
        : profile.username,
  );
  if (validateNormalizedUsername(normalizedUsername) != null) {
    return false;
  }

  return profile.usernameReservationMatchesUid;
}

AuthOnboardingResolution resolveAuthOnboardingState({
  required AuthIdentitySnapshot? auth,
  required ProfileCompletionSnapshot? profile,
}) {
  if (auth == null) {
    return const AuthOnboardingResolution(
      state: AuthOnboardingState.signedOut,
      auth: null,
      profile: null,
    );
  }

  final accountStatus = profile?.accountStatus.trim();
  if (accountStatus == 'pendingDeletion' ||
      accountStatus == 'deletionInProgress') {
    return AuthOnboardingResolution(
      state: AuthOnboardingState.accountRecoveryRequired,
      auth: auth,
      profile: profile,
    );
  }

  if (auth.hasPasswordProvider &&
      auth.email.trim().isNotEmpty &&
      !auth.emailVerified) {
    return AuthOnboardingResolution(
      state: AuthOnboardingState.emailVerificationRequired,
      auth: auth,
      profile: profile,
    );
  }

  if (!auth.hasPhoneProvider || auth.phoneNumber.trim().isEmpty) {
    return AuthOnboardingResolution(
      state: AuthOnboardingState.phoneLinkRequired,
      auth: auth,
      profile: profile,
    );
  }

  if (!isProfileComplete(auth: auth, profile: profile)) {
    return AuthOnboardingResolution(
      state: AuthOnboardingState.profileCompletionRequired,
      auth: auth,
      profile: profile,
    );
  }

  return AuthOnboardingResolution(
    state: AuthOnboardingState.authenticated,
    auth: auth,
    profile: profile,
  );
}
