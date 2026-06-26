import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
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
        message: 'Unable to request account deletion right now. Please try again.',
        tone: AppFeedbackTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;

    return Scaffold(
      backgroundColor: AppColors.background,
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
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
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
                            'Settings',
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
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.08),
                          Colors.white,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        _SettingsAvatar(profile: profile),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.name.isEmpty
                                    ? 'Your Name'
                                    : profile.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                profile.displayUsername.isEmpty
                                    ? '@username'
                                    : profile.displayUsername,
                                style: const TextStyle(
                                  color: AppColors.textGrey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                profile.roleLabel,
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SettingsSection(
                    title: 'Social',
                    child: Column(
                      children: [
                        _SwitchTile(
                          icon: Icons.notifications_none_rounded,
                          title: 'Social notifications',
                          subtitle:
                              'Likes, comments, follows, and community activity',
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
                          subtitle: 'Show a quick preview in your inbox',
                          value: _settings.messagePreviewsEnabled,
                          onChanged: (value) {
                            _updateSettings(
                              _settings.copyWith(messagePreviewsEnabled: value),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SettingsSection(
                    title: 'Booking & Services',
                    child: Column(
                      children: [
                        _SwitchTile(
                          icon: Icons.event_available_outlined,
                          title: 'Booking notifications',
                          subtitle:
                              'Appointments, confirmations, and booking changes',
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
                  _SettingsSection(
                    title: 'Provider',
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFFFF2EA),
                            child: Icon(
                              Icons.account_balance_wallet_outlined,
                              color: AppColors.primary,
                            ),
                          ),
                          title: const Text(
                            'Provider Earnings',
                            style: TextStyle(
                              color: AppColors.textDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: const Text(
                            'Track pending, payout-eligible, paid, and disputed earnings',
                            style: TextStyle(
                              color: AppColors.textGrey,
                              height: 1.4,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.primary,
                          ),
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/settings/provider-earnings',
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFFFF2EA),
                            child: Icon(
                              Icons.verified_user_outlined,
                              color: AppColors.primary,
                            ),
                          ),
                          title: const Text(
                            'Provider Verification Status',
                            style: TextStyle(
                              color: AppColors.textDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            _verificationSubtitle(_providerOnboarding),
                            style: const TextStyle(
                              color: AppColors.textGrey,
                              height: 1.4,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.primary,
                          ),
                          onTap: _openProviderVerificationHub,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFFFF2EA),
                            child: Icon(
                              Icons.account_balance_outlined,
                              color: AppColors.primary,
                            ),
                          ),
                          title: const Text(
                            'Bank Details',
                            style: TextStyle(
                              color: AppColors.textDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            _bankDetailsSubtitle(_providerOnboarding),
                            style: const TextStyle(
                              color: AppColors.textGrey,
                              height: 1.4,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.primary,
                          ),
                          onTap: _openProviderBankDetails,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SettingsSection(
                    title: 'Offers',
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFFFF2EA),
                            child: Icon(
                              Icons.local_offer_outlined,
                              color: AppColors.primary,
                            ),
                          ),
                          title: const Text(
                            'My Offers',
                            style: TextStyle(
                              color: AppColors.textDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: const Text(
                            'View available, used, and expired claimed offers',
                            style: TextStyle(
                              color: AppColors.textGrey,
                              height: 1.4,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.primary,
                          ),
                          onTap: () =>
                              Navigator.pushNamed(context, '/settings/offers'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SettingsSection(
                    title: 'Legal & Policies',
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFFFF2EA),
                            child: Icon(
                              Icons.gavel_rounded,
                              color: AppColors.primary,
                            ),
                          ),
                          title: const Text(
                            'Legal & Policies',
                            style: TextStyle(
                              color: AppColors.textDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: const Text(
                            'Cancellation, refund, privacy, provider, and terms documents',
                            style: TextStyle(
                              color: AppColors.textGrey,
                              height: 1.4,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.primary,
                          ),
                          onTap: () =>
                              Navigator.pushNamed(context, '/settings/legal'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SettingsSection(
                    title: 'Account',
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFFFF1EF),
                            child: Icon(
                              Icons.delete_outline_rounded,
                              color: Color(0xFFE15656),
                            ),
                          ),
                          title: const Text(
                            'Delete account',
                            style: TextStyle(
                              color: Color(0xFFE15656),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: const Text(
                            'Request account deletion while retained legal and payment records stay protected.',
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
                          onTap: _isDeletingAccount ? null : _requestAccountDeletion,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(26),
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
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFFFF1EF),
                        child: Icon(
                          Icons.logout_rounded,
                          color: Color(0xFFE15656),
                        ),
                      ),
                      title: Text(
                        _isSigningOut ? 'Signing out...' : 'Sign out',
                        style: const TextStyle(
                          color: Color(0xFFE15656),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: const Text(
                        'You will need to sign in again to access your account.',
                        style: TextStyle(
                          color: AppColors.textGrey,
                          height: 1.4,
                        ),
                      ),
                      trailing: _isSigningOut
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFFE15656),
                            ),
                      onTap: _isSigningOut ? null : _signOut,
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
      return 'Rejected. Open to review the reason and resubmit documents.';
    }
    if (verification.isPending) {
      return verification.graceExpired
          ? 'Pending. Your services are paused until verification is approved.'
          : 'Pending review. Open to check your current verification status.';
    }
    return 'Not submitted yet. Open to start provider verification.';
  }

  String _bankDetailsSubtitle(ProviderOnboardingSnapshot? onboarding) {
    final bankDetails = onboarding?.bankDetails;
    if (bankDetails == null) {
      return 'View and update the payout account used for provider earnings';
    }
    if (bankDetails.isSubmitted) {
      final bankName = bankDetails.bankName.isEmpty
          ? 'Bank account on file'
          : bankDetails.bankName;
      final maskedAccount = bankDetails.accountNumberMasked;
      final suffix = maskedAccount.isEmpty ? '' : ' • $maskedAccount';
      return '$bankName$suffix';
    }
    return 'No bank details saved yet. Open to add or update payout details.';
  }
}

class _SettingsAvatar extends StatelessWidget {
  final UserProfile profile;

  const _SettingsAvatar({required this.profile});

  @override
  Widget build(BuildContext context) {
    if (profile.profileImageUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          profile.profileImageUrl,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallback(),
        ),
      );
    }

    return _fallback();
  }

  Widget _fallback() {
    return Container(
      width: 60,
      height: 60,
      decoration: const BoxDecoration(
        gradient: AppColors.brandGradientDiagonal,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        profile.initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _SettingsSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
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
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFFFF2EA),
        child: Icon(icon, color: AppColors.primary),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.textDark,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppColors.textGrey, height: 1.4),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: AppColors.primary,
        activeThumbColor: Colors.white,
      ),
    );
  }
}
