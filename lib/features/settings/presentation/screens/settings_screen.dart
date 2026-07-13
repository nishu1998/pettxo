import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_user_avatar.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../auth/data/services/auth_service.dart';
import '../../../provider/data/repositories/provider_onboarding_repository.dart';
import '../../../provider/domain/models/provider_onboarding_models.dart';
import '../../../provider/presentation/screens/provider_bank_details_screen.dart';
import '../../../provider/presentation/screens/provider_verification_hub_screen.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../data/services/settings_service.dart';
import '../../domain/models/app_settings.dart';
import 'account_info_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();
  final ProfileRepository _profileRepository = ProfileRepository();
  final ProviderOnboardingRepository _providerOnboardingRepository =
      ProviderOnboardingRepository();
  final SettingsService _settingsService = SettingsService();
  AppSettings _settings = const AppSettings.defaults();
  UserProfile? _profile;
  ProviderOnboardingSnapshot? _providerOnboarding;
  bool _isLoading = true;
  bool _isSigningOut = false;
  bool _isDeletingAccount = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _settingsService.loadSettings();
      final profile = await _profileRepository.getCurrentUserProfile();
      ProviderOnboardingSnapshot? providerOnboarding;
      try {
        providerOnboarding = await _providerOnboardingRepository
            .fetchCurrentOnboarding();
      } catch (_) {
        providerOnboarding = null;
      }
      if (!mounted) return;

      setState(() {
        _settings = settings;
        _profile = profile;
        _providerOnboarding = providerOnboarding;
        _loadError = null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loadError = 'We could not load your settings right now.';
        _isLoading = false;
      });
    }
  }

  Future<void> _openProviderVerificationHub() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProviderVerificationHubScreen()),
    );
    if (!mounted) return;
    setState(() => _isLoading = true);
    await _loadSettings();
  }

  Future<void> _openProviderBankDetails() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProviderBankDetailsScreen()),
    );
    if (!mounted) return;
    setState(() => _isLoading = true);
    await _loadSettings();
  }

  Future<void> _updateSettings(AppSettings settings) async {
    setState(() => _settings = settings);
    await _settingsService.saveSettings(settings);
  }

  Future<void> _signOut() async {
    if (_isSigningOut) return;

    setState(() => _isSigningOut = true);

    try {
      await _authService.logout();
      if (!mounted) return;

      Navigator.pushNamedAndRemoveUntil(context, "/signin", (route) => false);
    } catch (_) {
      if (!mounted) return;

      setState(() => _isSigningOut = false);
      AppFeedback.show(
        context,
        message: 'Unable to sign out right now. Please try again.',
        tone: AppFeedbackTone.error,
      );
    }
  }

  Future<void> _requestAccountDeletion() async {
    if (_isDeletingAccount || _isSigningOut) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete account?'),
          content: const Text(
            'This submits an account deletion request. Pettxo will restrict your profile, services, bookings, and chats while payment, booking, KYC, and dispute records required for legal retention are preserved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'Delete account',
                style: TextStyle(color: Color(0xFFE15656)),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingAccount = true);
    try {
      final message = await _authService.requestAccountDeletion();
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: message,
        tone: AppFeedbackTone.success,
      );
      await _authService.logout();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, "/signin", (route) => false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDeletingAccount = false);
      AppFeedback.show(
        context,
        message:
            'Unable to request account deletion right now. Please try again.',
        tone: AppFeedbackTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;

    return Scaffold(
      backgroundColor: const Color(0xFFFBF6EF),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null || profile == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.settings_suggest_outlined,
                        size: 38,
                        color: AppColors.textGrey,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _loadError ?? 'Settings are unavailable right now.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () {
                          setState(() => _isLoading = true);
                          _loadSettings();
                        },
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 28),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Text(
                            'Settings',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          _SettingsAvatar(profile: profile),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  profile.name.isEmpty
                                      ? 'Your Name'
                                      : profile.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${profile.displayUsername.isEmpty ? '@username' : profile.displayUsername} · ${profile.roleLabel}',
                                  style: const TextStyle(
                                    color: AppColors.textGrey,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SectionLabel(title: 'NOTIFICATIONS'),
                  _SettingsCard(
                    child: Column(
                      children: [
                        _SwitchTile(
                          icon: Icons.notifications_none_rounded,
                          title: 'Social activity',
                          subtitle: 'Likes, comments, follows',
                          value: _settings.socialNotificationsEnabled,
                          onChanged: (value) {
                            _updateSettings(
                              _settings.copyWith(
                                socialNotificationsEnabled: value,
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        _SwitchTile(
                          icon: Icons.mark_chat_unread_outlined,
                          title: 'Message previews',
                          subtitle: 'Quick preview in your inbox',
                          value: _settings.messagePreviewsEnabled,
                          onChanged: (value) {
                            _updateSettings(
                              _settings.copyWith(messagePreviewsEnabled: value),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        _SwitchTile(
                          icon: Icons.event_available_outlined,
                          title: 'Bookings',
                          subtitle: 'Appointments and confirmations',
                          value: _settings.bookingNotificationsEnabled,
                          onChanged: (value) {
                            _updateSettings(
                              _settings.copyWith(
                                bookingNotificationsEnabled: value,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionLabel(title: 'PROVIDER'),
                  _SettingsCard(
                    child: Column(
                      children: [
                        _NavTile(
                          icon: Icons.account_balance_wallet_outlined,
                          title: 'Provider earnings',
                          subtitle: const Text(
                            'Pending, payout-eligible, paid',
                            style: TextStyle(
                              color: AppColors.textGrey,
                              height: 1.4,
                            ),
                          ),
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/settings/provider-earnings',
                          ),
                        ),
                        const Divider(height: 1),
                        _NavTile(
                          icon: Icons.verified_user_outlined,
                          title: 'Verification status',
                          subtitle: Text(
                            _verificationSubtitle(_providerOnboarding),
                            style: const TextStyle(
                              color: AppColors.textGrey,
                              height: 1.4,
                            ),
                          ),
                          onTap: _openProviderVerificationHub,
                        ),
                        const Divider(height: 1),
                        _NavTile(
                          icon: Icons.account_balance_outlined,
                          title: 'Bank details',
                          subtitle: Text(
                            _bankDetailsSubtitle(_providerOnboarding),
                            style: const TextStyle(
                              color: AppColors.textGrey,
                              height: 1.4,
                            ),
                          ),
                          onTap: _openProviderBankDetails,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionLabel(title: 'ACCOUNT INFO'),
                  _SettingsCard(
                    child: Column(
                      children: [
                        _NavTile(
                          icon: Icons.manage_accounts_outlined,
                          title: 'View account info',
                          subtitle: const Text(
                            'Name, username, email, phone and sign-in provider',
                            style: TextStyle(
                              color: AppColors.textGrey,
                              height: 1.4,
                            ),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    AccountInfoScreen(profile: profile),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionLabel(title: 'MORE'),
                  _SettingsCard(
                    child: Column(
                      children: [
                        _NavTile(
                          icon: Icons.local_offer_outlined,
                          title: 'My offers',
                          subtitle: const Text(
                            'Available, used and expired',
                            style: TextStyle(
                              color: AppColors.textGrey,
                              height: 1.4,
                            ),
                          ),
                          onTap: () =>
                              Navigator.pushNamed(context, '/settings/offers'),
                        ),
                        const Divider(height: 1),
                        _NavTile(
                          icon: Icons.gavel_rounded,
                          title: 'Legal and policies',
                          subtitle: const Text(
                            'Terms, privacy, refunds',
                            style: TextStyle(
                              color: AppColors.textGrey,
                              height: 1.4,
                            ),
                          ),
                          onTap: () =>
                              Navigator.pushNamed(context, '/settings/legal'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionLabel(title: 'ACCOUNT'),
                  _SettingsCard(
                    child: Column(
                      children: [
                        _NavTile(
                          icon: Icons.delete_outline_rounded,
                          title: 'Delete account',
                          titleColor: const Color(0xFFE15656),
                          iconColor: const Color(0xFFE15656),
                          iconBackgroundColor: const Color(0xFFFFF1EF),
                          subtitle: const Text(
                            'Legal and payment records stay protected',
                            style: TextStyle(
                              color: AppColors.textGrey,
                              height: 1.4,
                            ),
                          ),
                          trailing: _isDeletingAccount
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Color(0xFFE15656),
                                ),
                          onTap: _isDeletingAccount
                              ? null
                              : _requestAccountDeletion,
                        ),
                        const Divider(height: 1),
                        _NavTile(
                          icon: Icons.logout_rounded,
                          title: _isSigningOut ? 'Signing out...' : 'Sign out',
                          titleColor: const Color(0xFFE15656),
                          iconColor: const Color(0xFFE15656),
                          iconBackgroundColor: const Color(0xFFFFF1EF),
                          subtitle: null,
                          trailing: _isSigningOut
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Color(0xFFE15656),
                                ),
                          onTap: _isSigningOut ? null : _signOut,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  String _verificationSubtitle(ProviderOnboardingSnapshot? onboarding) {
    final verification = onboarding?.verification;
    if (verification == null) {
      return 'Check your verification progress and resubmit documents if needed';
    }
    if (verification.isApproved) {
      return 'Approved. Your provider verification is complete.';
    }
    if (verification.isRejected) {
      return 'Rejected';
    }
    if (verification.isPending) {
      return 'Pending review';
    }
    return 'Not submitted';
  }

  String _bankDetailsSubtitle(ProviderOnboardingSnapshot? onboarding) {
    final bankDetails = onboarding?.bankDetails;
    if (bankDetails == null) {
      return 'Add payout account';
    }
    if (bankDetails.isSubmitted) {
      final bankName = bankDetails.bankName.isEmpty
          ? 'Bank account on file'
          : bankDetails.bankName;
      final maskedAccount = bankDetails.accountNumberMasked;
      final suffix = maskedAccount.isEmpty ? '' : ' • $maskedAccount';
      return '$bankName$suffix';
    }
    return 'Add payout account';
  }
}

class _SettingsAvatar extends StatelessWidget {
  final UserProfile profile;

  const _SettingsAvatar({required this.profile});

  @override
  Widget build(BuildContext context) {
    return AppUserAvatar(
      size: 60,
      imageUrl: profile.profileImageUrl,
      useCachedImage: false,
      fallback: _fallback(),
    );
  }

  Widget _fallback() {
    return AppUserAvatarFallback(
      initials: profile.initials,
      gradient: AppColors.brandGradientDiagonal,
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;

  const _SectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: Color(0xFF8E8479),
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final Widget child;

  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF2EA),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: AppColors.primary, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    height: 1.4,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.primary,
            activeThumbColor: Colors.white,
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color titleColor;
  final Color iconColor;
  final Color iconBackgroundColor;

  const _NavTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.titleColor = AppColors.textDark,
    this.iconColor = AppColors.primary,
    this.iconBackgroundColor = const Color(0xFFFFF2EA),
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: iconBackgroundColor,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    subtitle!,
                  ],
                ],
              ),
            ),
            trailing ??
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFC8BEB3),
                ),
          ],
        ),
      ),
    );
  }
}
