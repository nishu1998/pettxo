import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../profile/domain/models/user_profile.dart';

class AccountInfoScreen extends StatelessWidget {
  final UserProfile profile;

  const AccountInfoScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final accountInfo = AccountInfoViewData.fromUser(
      profile: profile,
      user: FirebaseAuth.instance.currentUser,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFFBF6EF),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Account Info',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.08),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'These details are linked to your Pettxo account and are read-only here.',
                    style: TextStyle(
                      color: AppColors.textGrey,
                      height: 1.45,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _ReadOnlyField(
                    icon: Icons.person_outline_rounded,
                    label: 'Name',
                    value: accountInfo.name,
                  ),
                  const SizedBox(height: 14),
                  _ReadOnlyField(
                    icon: Icons.alternate_email_rounded,
                    label: 'Username',
                    value: accountInfo.username,
                  ),
                  if (accountInfo.hasAnyContactInfo) ...[
                    if (accountInfo.hasEmail) ...[
                      const SizedBox(height: 14),
                      _ReadOnlyField(
                        icon: Icons.email_outlined,
                        label: 'Email',
                        value: accountInfo.email,
                      ),
                    ],
                    if (accountInfo.hasPhoneNumber) ...[
                      const SizedBox(height: 14),
                      _ReadOnlyField(
                        icon: Icons.phone_outlined,
                        label: 'Phone number',
                        value: accountInfo.phoneNumber,
                      ),
                    ],
                  ] else ...[
                    const SizedBox(height: 14),
                    _AccountInfoEmptyState(
                      message: 'No account contact information is available.',
                    ),
                  ],
                  const SizedBox(height: 14),
                  _ReadOnlyField(
                    icon: Icons.verified_user_outlined,
                    label: 'Sign-in provider',
                    value: accountInfo.providersLabel,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AccountInfoViewData {
  final String name;
  final String username;
  final String email;
  final String phoneNumber;
  final String providersLabel;

  const AccountInfoViewData({
    required this.name,
    required this.username,
    required this.email,
    required this.phoneNumber,
    required this.providersLabel,
  });

  bool get hasEmail => hasValue(email);
  bool get hasPhoneNumber => hasValue(phoneNumber);
  bool get hasAnyContactInfo => hasEmail || hasPhoneNumber;

  factory AccountInfoViewData.fromUser({
    required UserProfile profile,
    required User? user,
  }) {
    final providerIds = <String>{};
    String email = _cleanValue(user?.email);
    String phoneNumber = _cleanValue(user?.phoneNumber);

    for (final provider in user?.providerData ?? const <UserInfo>[]) {
      final providerId = provider.providerId.trim();
      if (providerId.isNotEmpty) {
        providerIds.add(providerId);
      }
      if (email.isEmpty) {
        email = _cleanValue(provider.email);
      }
      if (phoneNumber.isEmpty) {
        phoneNumber = _cleanValue(provider.phoneNumber);
      }
    }

    if (email.isEmpty) {
      email = _cleanValue(profile.email);
    }
    if (phoneNumber.isEmpty) {
      phoneNumber = _cleanValue(profile.phone);
    }

    return AccountInfoViewData(
      name: profile.name.isEmpty ? 'Name unavailable' : profile.name,
      username: profile.displayUsername.isEmpty
          ? 'Username unavailable'
          : profile.displayUsername,
      email: email,
      phoneNumber: phoneNumber,
      providersLabel: providerIds.isEmpty
          ? 'Account provider unavailable'
          : providerIds.map(_providerLabel).join(', '),
    );
  }

  static bool hasValue(String? value) {
    return value != null && value.trim().isNotEmpty;
  }

  static String _cleanValue(String? value) => value?.trim() ?? '';

  static String _providerLabel(String providerId) {
    return switch (providerId) {
      'password' => 'Email/Password',
      'phone' => 'Phone',
      'google.com' => 'Google',
      'apple.com' => 'Apple',
      _ => providerId,
    };
  }
}

class _AccountInfoEmptyState extends StatelessWidget {
  final String message;

  const _AccountInfoEmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFBFA),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AppColors.textGrey,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.45,
        ),
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ReadOnlyField({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFBFA),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF2EA),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
