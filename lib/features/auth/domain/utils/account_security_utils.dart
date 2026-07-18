import 'package:firebase_auth/firebase_auth.dart';

import '../../../profile/domain/models/user_profile.dart';
import 'auth_onboarding_resolver.dart';

enum AccountSecurityEmailState { notAdded, pendingVerification, verified }

enum AccountSecurityPasswordState { notAdded, enabled }

class TrustedAuthUserSnapshot {
  final String uid;
  final String email;
  final String phoneNumber;
  final bool emailVerified;
  final List<String> providerIds;

  const TrustedAuthUserSnapshot({
    required this.uid,
    required this.email,
    required this.phoneNumber,
    required this.emailVerified,
    required this.providerIds,
  });

  bool get hasPhoneProvider => providerIds.contains('phone');
  bool get hasPasswordProvider => providerIds.contains('password');
}

class AccountSecurityViewData {
  final String usernameDisplay;
  final String usernameHelperText;
  final String phoneDisplay;
  final String phoneStatusLabel;
  final String emailDisplay;
  final String emailStatusLabel;
  final String passwordStatusLabel;
  final List<String> linkedMethodLabels;
  final bool canChangeUsername;
  final bool canChangeEmail;
  final bool canChangePhoneNumber;
  final bool canAddEmailPassword;
  final bool canChangePassword;
  final bool canManagePendingEmailVerification;
  final bool hasPendingEmailChange;
  final String pendingEmailDisplay;
  final AccountSecurityEmailState emailState;
  final AccountSecurityPasswordState passwordState;

  const AccountSecurityViewData({
    required this.usernameDisplay,
    required this.usernameHelperText,
    required this.phoneDisplay,
    required this.phoneStatusLabel,
    required this.emailDisplay,
    required this.emailStatusLabel,
    required this.passwordStatusLabel,
    required this.linkedMethodLabels,
    required this.canChangeUsername,
    required this.canChangeEmail,
    required this.canChangePhoneNumber,
    required this.canAddEmailPassword,
    required this.canChangePassword,
    required this.canManagePendingEmailVerification,
    required this.hasPendingEmailChange,
    required this.pendingEmailDisplay,
    required this.emailState,
    required this.passwordState,
  });

  factory AccountSecurityViewData.fromSnapshot({
    required UserProfile profile,
    required TrustedAuthUserSnapshot auth,
    String pendingEmailChange = '',
  }) {
    final normalizedPendingEmail = pendingEmailChange.trim();
    final hasPendingEmailChange = normalizedPendingEmail.isNotEmpty;
    final emailState = hasPendingEmailChange
        ? AccountSecurityEmailState.pendingVerification
        : auth.email.trim().isEmpty
        ? AccountSecurityEmailState.notAdded
        : auth.emailVerified
        ? AccountSecurityEmailState.verified
        : AccountSecurityEmailState.pendingVerification;
    final passwordState = auth.hasPasswordProvider
        ? AccountSecurityPasswordState.enabled
        : AccountSecurityPasswordState.notAdded;

    return AccountSecurityViewData(
      usernameDisplay: profile.displayUsername.isEmpty
          ? '@username'
          : profile.displayUsername,
      usernameHelperText:
          'Username changes update your live profile going forward.',
      phoneDisplay: auth.phoneNumber.trim().isEmpty
          ? 'Not added'
          : maskPhoneNumber(auth.phoneNumber),
      phoneStatusLabel: auth.phoneNumber.trim().isEmpty
          ? 'Not added'
          : 'Verified',
      emailDisplay: hasPendingEmailChange
          ? maskEmail(normalizedPendingEmail)
          : auth.email.trim().isEmpty
          ? 'Not added'
          : maskEmail(auth.email),
      emailStatusLabel: switch (emailState) {
        AccountSecurityEmailState.notAdded => 'Not added',
        AccountSecurityEmailState.pendingVerification => 'Pending verification',
        AccountSecurityEmailState.verified => 'Verified',
      },
      passwordStatusLabel: switch (passwordState) {
        AccountSecurityPasswordState.notAdded => 'Not added',
        AccountSecurityPasswordState.enabled => 'Enabled',
      },
      linkedMethodLabels: auth.providerIds.map(providerLabelForId).toList(),
      canChangeUsername: profile.username.trim().isNotEmpty,
      canChangeEmail:
          auth.hasPasswordProvider &&
          !hasPendingEmailChange &&
          auth.email.trim().isNotEmpty &&
          auth.emailVerified,
      canChangePhoneNumber: auth.hasPhoneProvider,
      canAddEmailPassword: auth.hasPhoneProvider && !auth.hasPasswordProvider,
      canChangePassword: auth.hasPasswordProvider,
      canManagePendingEmailVerification:
          hasPendingEmailChange ||
          (auth.hasPasswordProvider &&
              auth.email.trim().isNotEmpty &&
              !auth.emailVerified),
      hasPendingEmailChange: hasPendingEmailChange,
      pendingEmailDisplay: normalizedPendingEmail,
      emailState: emailState,
      passwordState: passwordState,
    );
  }
}

TrustedAuthUserSnapshot trustedAuthSnapshotFromFirebaseUser(User? user) {
  if (user == null) {
    return const TrustedAuthUserSnapshot(
      uid: '',
      email: '',
      phoneNumber: '',
      emailVerified: false,
      providerIds: <String>[],
    );
  }

  String email = (user.email ?? '').trim();
  String phoneNumber = (user.phoneNumber ?? '').trim();
  final providerIds = <String>[];

  for (final provider in user.providerData) {
    providerIds.add(provider.providerId);
    if (email.isEmpty) {
      email = (provider.email ?? '').trim();
    }
    if (phoneNumber.isEmpty) {
      phoneNumber = (provider.phoneNumber ?? '').trim();
    }
  }

  return TrustedAuthUserSnapshot(
    uid: user.uid,
    email: email,
    phoneNumber: phoneNumber,
    emailVerified: user.emailVerified,
    providerIds: deriveTrustedProviderIds(providerIds),
  );
}

List<String> deriveTrustedProviderIds(Iterable<String> providerIds) {
  return normalizeProviderIds(providerIds);
}

String providerLabelForId(String providerId) {
  return switch (providerId.trim()) {
    'password' => 'Email & Password',
    'phone' => 'Phone',
    'google.com' => 'Google',
    'apple.com' => 'Apple',
    _ => providerId.trim(),
  };
}

String maskEmail(String email) {
  final trimmed = email.trim();
  final parts = trimmed.split('@');
  if (parts.length != 2 || parts.first.isEmpty) return trimmed;

  final local = parts.first;
  final domain = parts.last;
  final visiblePrefix = local.length <= 2 ? 1 : 2;
  final prefix = local.substring(0, visiblePrefix);
  return '$prefix••••@$domain';
}

String maskPhoneNumber(String phoneNumber) {
  final trimmed = phoneNumber.trim();
  if (trimmed.isEmpty) return 'Not added';

  final digits = trimmed.replaceAll(RegExp(r'\s+'), '');
  if (digits.length <= 4) return digits;

  final suffix = digits.substring(digits.length - 4);
  var prefix = '';
  if (digits.startsWith('+91')) {
    prefix = '+91';
  } else if (digits.startsWith('+')) {
    final remainder = digits.substring(1);
    final countryCodeLength = remainder.length > 10
        ? remainder.length - 10
        : remainder.length.clamp(1, 3);
    prefix = '+${remainder.substring(0, countryCodeLength)}';
  }

  return prefix.isEmpty ? '••••••$suffix' : '$prefix ••••••$suffix';
}
