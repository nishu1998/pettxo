import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../auth/data/services/auth_service.dart';
import '../../data/services/settings_service.dart';
import '../../domain/models/app_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();
  final SettingsService _settingsService = SettingsService();
  AppSettings _settings = const AppSettings.defaults();
  bool _isLoading = true;
  bool _isSigningOut = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.loadSettings();
    if (!mounted) return;

    setState(() {
      _settings = settings;
      _isLoading = false;
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Settings',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textDark,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Profile, social preferences, and booking controls',
                                style: TextStyle(
                                  color: AppColors.textGrey,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
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
                    title: 'Profile',
                    child: Column(
                      children: [
                        _SettingsTile(
                          icon: Icons.person_outline_rounded,
                          title: 'Profile details',
                          subtitle:
                              'Keep profile edits and account basics inside settings.',
                          onTap: () {
                            AppFeedback.show(
                              context,
                              message:
                                  'Profile editing can be connected here next without crowding the profile screen.',
                              tone: AppFeedbackTone.info,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
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
                        const Divider(height: 1),
                        _SwitchTile(
                          icon: Icons.storefront_outlined,
                          title: 'I have listed services',
                          subtitle:
                              'Use this when your profile should expose service controls',
                          value: _settings.hasListedServices,
                          onChanged: (value) {
                            _updateSettings(
                              _settings.copyWith(
                                hasListedServices: value,
                                showManageServicesOnProfile: value
                                    ? _settings.showManageServicesOnProfile
                                    : false,
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        _SwitchTile(
                          icon: Icons.build_circle_outlined,
                          title: 'Show Manage Services on profile',
                          subtitle:
                              'Only enable this when you want that single CTA visible',
                          value: _settings.showManageServicesOnProfile,
                          enabled: _settings.hasListedServices,
                          onChanged: (value) {
                            _updateSettings(
                              _settings.copyWith(
                                showManageServicesOnProfile: value,
                              ),
                            );
                          },
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

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
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
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: ListTile(
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
          onChanged: enabled ? onChanged : null,
          activeTrackColor: AppColors.primary,
          activeThumbColor: Colors.white,
        ),
      ),
    );
  }
}
