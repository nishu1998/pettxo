import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_confirmation_dialog.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../auth/data/services/auth_service.dart';
import '../../../auth/data/services/pending_email_change_service.dart';
import '../../../auth/data/services/recent_login_service.dart';
import '../../../auth/domain/models/email_verification_mode.dart';
import '../../../auth/domain/utils/account_security_utils.dart';
import '../../../auth/presentation/screens/auth_gateway_screen.dart';
import '../../../auth/presentation/screens/email_verification_screen.dart';
import '../../../auth/presentation/widgets/auth_input_field.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../../profile/domain/models/user_profile.dart';
import 'change_password_screen.dart';
import 'change_email_screen.dart';
import 'change_phone_number_screen.dart';
import 'change_username_screen.dart';
import 'link_email_password_screen.dart';

class AccountSecurityScreen extends StatefulWidget {
  final UserProfile initialProfile;

  const AccountSecurityScreen({super.key, required this.initialProfile});

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  final AuthService _authService = AuthService();
  final ProfileRepository _profileRepository = ProfileRepository();
  final PendingEmailChangeService _pendingEmailChangeService =
      const PendingEmailChangeService();
  final RecentLoginService _recentLoginService = RecentLoginService();

  UserProfile? _profile;
  AccountSecurityViewData? _viewData;
  bool _isLoading = true;
  bool _isDeletingAccount = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _profile = widget.initialProfile;
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      await _authService.reloadCurrentUser();
      final currentUser = FirebaseAuth.instance.currentUser;
      final currentUid = currentUser?.uid.trim() ?? '';
      var pendingEmail = currentUid.isEmpty
          ? null
          : await _pendingEmailChangeService.getPendingEmail(currentUid);
      if (pendingEmail != null && currentUser != null) {
        final currentEmail = (currentUser.email ?? '').trim();
        if ((currentEmail == pendingEmail && currentUser.emailVerified) ||
            (currentEmail.isNotEmpty &&
                currentEmail != pendingEmail &&
                currentUser.emailVerified)) {
          await _pendingEmailChangeService.clearPendingEmail(currentUid);
          if (currentEmail == pendingEmail) {
            await _authService.syncTrustedAuthIdentity();
          }
          pendingEmail = null;
        }
      }
      final profile = await _profileRepository.getCurrentUserProfile();
      final trustedAuth = trustedAuthSnapshotFromFirebaseUser(
        FirebaseAuth.instance.currentUser,
      );
      if (!mounted) return;

      setState(() {
        _profile = profile;
        _viewData = AccountSecurityViewData.fromSnapshot(
          profile: profile,
          auth: trustedAuth,
          pendingEmailChange: pendingEmail ?? '',
        );
        _isLoading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profile = widget.initialProfile;
        final trustedAuth = trustedAuthSnapshotFromFirebaseUser(
          FirebaseAuth.instance.currentUser,
        );
        _viewData = AccountSecurityViewData.fromSnapshot(
          profile: widget.initialProfile,
          auth: trustedAuth,
          pendingEmailChange: '',
        );
        _isLoading = false;
        _loadError = 'We could not refresh your account details right now.';
      });
    }
  }

  Future<void> _openLinkEmailPassword() async {
    final didUpdate = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LinkEmailPasswordScreen()),
    );
    if (didUpdate == true && mounted) {
      setState(() => _isLoading = true);
      await _refresh();
    }
  }

  Future<void> _openChangePassword() async {
    final didUpdate = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
    );
    if (didUpdate == true && mounted) {
      setState(() => _isLoading = true);
      await _refresh();
    }
  }

  Future<void> _openChangeUsername() async {
    final profile = _profile;
    if (profile == null) return;
    final didUpdate = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChangeUsernameScreen(currentUsername: profile.username),
      ),
    );
    if (didUpdate == true && mounted) {
      setState(() => _isLoading = true);
      await _refresh();
    }
  }

  Future<void> _openChangeEmail() async {
    final didUpdate = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const ChangeEmailScreen()));
    if (didUpdate == true && mounted) {
      setState(() => _isLoading = true);
      await _refresh();
    }
  }

  Future<void> _openChangePhoneNumber() async {
    final didUpdate = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ChangePhoneNumberScreen()),
    );
    if (didUpdate == true && mounted) {
      setState(() => _isLoading = true);
      await _refresh();
    }
  }

  Future<void> _openEmailVerificationManager() async {
    final expectedEmail = _viewData?.hasPendingEmailChange == true
        ? _viewData?.pendingEmailDisplay
        : null;
    final didUpdate = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EmailVerificationScreen(
          mode: EmailVerificationMode.nonBlockingLinkedEmail,
          displayEmailOverride: expectedEmail,
          expectedVerifiedEmail: expectedEmail,
        ),
      ),
    );
    if (didUpdate == true && mounted) {
      setState(() => _isLoading = true);
      await _refresh();
    }
  }

  Future<void> _requestAccountDeletion() async {
    if (_isDeletingAccount) return;

    final confirmed = await AppConfirmationDialog.showPhraseConfirmation(
      context: context,
      title: 'Schedule account deletion?',
      message:
          'Your access will stop immediately, and your Pettxo account will be permanently deleted after 30 days unless you sign in and restore it before then.',
      helperMessage:
          'During the recovery window, your UID, email or phone sign-in, and username stay reserved for this account.',
      confirmationPhrase: 'DELETE',
      inputLabel: 'Type DELETE to confirm',
      cancelLabel: 'Cancel',
      confirmLabel: 'Schedule deletion',
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;

    final didReauthenticate = await _reauthenticateForDeletion();
    if (didReauthenticate != true || !mounted) return;

    setState(() => _isDeletingAccount = true);
    try {
      final result = await _authService.requestAccountDeletion();
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: result.scheduledDeletionAt == null
            ? 'Account deletion has been scheduled.'
            : 'Account deletion has been scheduled for ${_formatDeletionDate(result.scheduledDeletionAt!)}.',
        tone: AppFeedbackTone.success,
      );
      await _authService.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGatewayScreen()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isDeletingAccount = false);
      AppFeedback.show(
        context,
        message: error.toString().replaceFirst('Exception: ', ''),
        tone: AppFeedbackTone.error,
      );
    }
  }

  String _formatDeletionDate(DateTime value) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  Future<bool?> _reauthenticateForDeletion() async {
    final providerIds = {
      for (final provider
          in FirebaseAuth.instance.currentUser?.providerData ??
              const <UserInfo>[])
        provider.providerId.trim(),
    };
    if (providerIds.contains('password')) {
      return showDialog<bool>(
        context: context,
        builder: (_) =>
            _PasswordReauthDialog(recentLoginService: _recentLoginService),
      );
    }

    return showDialog<bool>(
      context: context,
      builder: (_) =>
          _PhoneReauthDialog(recentLoginService: _recentLoginService),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final viewData = _viewData;

    return Scaffold(
      backgroundColor: const Color(0xFFFBF6EF),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : profile == null || viewData == null
            ? _AccountSecurityErrorState(
                message: _loadError ?? 'Account details are unavailable.',
                onRetry: () {
                  setState(() => _isLoading = true);
                  _refresh();
                },
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                children: [
                  _AccountSecurityHeader(
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 18),
                  if (_loadError != null) ...[
                    _InlineNotice(message: _loadError!),
                    const SizedBox(height: 18),
                  ],
                  _AccountSecurityCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Trusted sign-in state',
                          style: TextStyle(
                            color: AppColors.textDark,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'These details come from your current Firebase Authentication account, not editable profile text.',
                          style: TextStyle(
                            color: AppColors.textGrey,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _InfoRow(
                          icon: Icons.link_rounded,
                          title: 'Linked sign-in methods',
                          value: viewData.linkedMethodLabels.isEmpty
                              ? 'Unavailable'
                              : viewData.linkedMethodLabels.join(', '),
                          status: null,
                        ),
                        const SizedBox(height: 14),
                        _InfoRow(
                          icon: Icons.phone_outlined,
                          title: 'Phone',
                          value: viewData.phoneDisplay,
                          status: viewData.phoneStatusLabel,
                        ),
                        const SizedBox(height: 14),
                        _InfoRow(
                          icon: Icons.email_outlined,
                          title: 'Email',
                          value: viewData.emailDisplay,
                          status: viewData.emailStatusLabel,
                        ),
                        const SizedBox(height: 14),
                        _InfoRow(
                          icon: Icons.lock_outline_rounded,
                          title: 'Password',
                          value: viewData.passwordStatusLabel,
                          status: null,
                        ),
                        const SizedBox(height: 14),
                        _InfoRow(
                          icon: Icons.alternate_email_rounded,
                          title: 'Username',
                          value: viewData.usernameDisplay,
                          status: null,
                          helperText: viewData.usernameHelperText,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _AccountSecurityCard(
                    child: Column(
                      children: [
                        if (viewData.canChangeUsername)
                          _ActionTile(
                            icon: Icons.alternate_email_rounded,
                            title: 'Change Username',
                            subtitle:
                                'Reserve a new username without changing your Pettxo UID.',
                            onTap: _openChangeUsername,
                          ),
                        if (viewData.canChangeUsername &&
                            (viewData.canAddEmailPassword ||
                                viewData.canManagePendingEmailVerification ||
                                viewData.canChangeEmail ||
                                viewData.canChangePhoneNumber ||
                                viewData.canChangePassword))
                          const Divider(height: 1),
                        if (viewData.canAddEmailPassword)
                          _ActionTile(
                            icon: Icons.add_link_rounded,
                            title: 'Add Email & Password',
                            subtitle:
                                'Keep this same Pettxo UID and add email sign-in securely.',
                            onTap: _openLinkEmailPassword,
                          ),
                        if (viewData.canAddEmailPassword &&
                            viewData.canManagePendingEmailVerification)
                          const Divider(height: 1),
                        if (viewData.canManagePendingEmailVerification)
                          _ActionTile(
                            icon: Icons.mark_email_unread_outlined,
                            title: 'Manage Email Verification',
                            subtitle:
                                'Resend the email or refresh verification status.',
                            onTap: _openEmailVerificationManager,
                          ),
                        if (viewData.canChangeEmail) ...[
                          if (viewData.canAddEmailPassword ||
                              viewData.canManagePendingEmailVerification)
                            const Divider(height: 1),
                          _ActionTile(
                            icon: Icons.alternate_email_outlined,
                            title: 'Change Email',
                            subtitle:
                                'Re-authenticate with your password before sending a verification link.',
                            onTap: _openChangeEmail,
                          ),
                        ],
                        if (viewData.canChangePhoneNumber) ...[
                          if (viewData.canAddEmailPassword ||
                              viewData.canManagePendingEmailVerification ||
                              viewData.canChangeEmail)
                            const Divider(height: 1),
                          _ActionTile(
                            icon: Icons.phone_android_outlined,
                            title: 'Change Phone Number',
                            subtitle:
                                'Confirm your current account first, then verify the new number with OTP.',
                            onTap: _openChangePhoneNumber,
                          ),
                        ],
                        if (viewData.canChangePassword) ...[
                          if (viewData.canManagePendingEmailVerification ||
                              viewData.canChangeEmail ||
                              viewData.canChangePhoneNumber)
                            const Divider(height: 1),
                          _ActionTile(
                            icon: Icons.password_rounded,
                            title: 'Change Password',
                            subtitle:
                                'Re-enter your current password before saving a new one.',
                            onTap: _openChangePassword,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _AccountSecurityCard(
                    child: _ActionTile(
                      icon: Icons.delete_outline_rounded,
                      title: _isDeletingAccount
                          ? 'Deleting account...'
                          : 'Delete Account',
                      subtitle:
                          'This action is permanent and signs you out after Pettxo accepts the request.',
                      onTap: _isDeletingAccount
                          ? null
                          : _requestAccountDeletion,
                      titleColor: const Color(0xFFE15656),
                      iconColor: const Color(0xFFE15656),
                      iconBackgroundColor: const Color(0xFFFFF1EF),
                      trailing: _isDeletingAccount
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _PasswordReauthDialog extends StatefulWidget {
  final RecentLoginService recentLoginService;

  const _PasswordReauthDialog({required this.recentLoginService});

  @override
  State<_PasswordReauthDialog> createState() => _PasswordReauthDialogState();
}

class _PasswordReauthDialogState extends State<_PasswordReauthDialog> {
  final TextEditingController _passwordController = TextEditingController();
  String? _passwordError;
  bool _isSubmitting = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    setState(() {
      _passwordError = password.trim().isEmpty
          ? 'Current password is required'
          : null;
    });
    if (_passwordError != null) return;

    setState(() => _isSubmitting = true);
    try {
      await widget.recentLoginService.reauthenticateWithPassword(
        currentPassword: password,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      AppFeedback.show(
        context,
        message: error.toString().replaceFirst('Exception: ', ''),
        tone: AppFeedbackTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm your password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthInputField(
            controller: _passwordController,
            labelText: 'Current Password',
            errorText: _passwordError,
            obscureText: _obscurePassword,
            onChanged: (_) {
              if (_passwordError != null) {
                setState(() => _passwordError = null);
              }
            },
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isSubmitting ? null : _submit,
          child: Text(_isSubmitting ? 'Checking...' : 'Continue'),
        ),
      ],
    );
  }
}

class _PhoneReauthDialog extends StatefulWidget {
  final RecentLoginService recentLoginService;

  const _PhoneReauthDialog({required this.recentLoginService});

  @override
  State<_PhoneReauthDialog> createState() => _PhoneReauthDialogState();
}

class _PhoneReauthDialogState extends State<_PhoneReauthDialog> {
  final TextEditingController _otpController = TextEditingController();
  String? _otpError;
  bool _isBusy = false;
  String? _verificationId;
  int? _resendToken;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phoneNumber = widget.recentLoginService
        .requireCurrentUserPhoneNumber();
    setState(() => _isBusy = true);
    await widget.recentLoginService.sendPhoneReauthenticationCode(
      phoneNumber: phoneNumber,
      forceResendingToken: _resendToken,
      codeSent: (verificationId, resendToken) async {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _resendToken = resendToken;
          _isBusy = false;
        });
      },
      verificationFailed: (message) async {
        if (!mounted) return;
        setState(() => _isBusy = false);
        AppFeedback.show(
          context,
          message: message,
          tone: AppFeedbackTone.error,
        );
      },
      verificationCompleted: (credential) async {
        try {
          await AuthService().reauthenticateCurrentUserWithPhoneAuthCredential(
            credential,
          );
          if (!mounted) return;
          Navigator.of(context).pop(true);
        } catch (error) {
          if (!mounted) return;
          setState(() => _isBusy = false);
          AppFeedback.show(
            context,
            message: error.toString().replaceFirst('Exception: ', ''),
            tone: AppFeedbackTone.error,
          );
        }
      },
    );
  }

  Future<void> _verifyCode() async {
    final smsCode = _otpController.text.trim();
    setState(() {
      _otpError = smsCode.isEmpty ? 'Enter the OTP' : null;
    });
    if (_verificationId == null || _otpError != null) return;

    setState(() => _isBusy = true);
    try {
      await widget.recentLoginService.reauthenticateWithPhoneOtp(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      AppFeedback.show(
        context,
        message: error.toString().replaceFirst('Exception: ', ''),
        tone: AppFeedbackTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm your phone'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_verificationId == null)
            const Text(
              'We will send an OTP to your current verified phone number before deletion continues.',
            )
          else
            AuthInputField(
              controller: _otpController,
              labelText: 'Current Phone OTP',
              errorText: _otpError,
              onChanged: (_) {
                if (_otpError != null) {
                  setState(() => _otpError = null);
                }
              },
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isBusy
              ? null
              : _verificationId == null
              ? _sendCode
              : _verifyCode,
          child: Text(
            _isBusy
                ? 'Please wait...'
                : _verificationId == null
                ? 'Send OTP'
                : 'Continue',
          ),
        ),
      ],
    );
  }
}

class _AccountSecurityHeader extends StatelessWidget {
  final VoidCallback onBack;

  const _AccountSecurityHeader({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
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
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Account & Security',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountSecurityCard extends StatelessWidget {
  final Widget child;

  const _AccountSecurityCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String? status;
  final String? helperText;

  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.status,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFBFA),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF2EA),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (helperText != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    helperText!,
                    style: const TextStyle(
                      color: AppColors.textGrey,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (status != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _statusBackground(status!),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                status!,
                style: TextStyle(
                  color: _statusColor(status!),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Color _statusBackground(String status) {
    return switch (status) {
      'Verified' || 'Enabled' => const Color(0xFFE9F8EF),
      'Pending verification' => const Color(0xFFFFF4E6),
      _ => const Color(0xFFF3EFEB),
    };
  }

  static Color _statusColor(String status) {
    return switch (status) {
      'Verified' || 'Enabled' => const Color(0xFF1F8A4C),
      'Pending verification' => const Color(0xFFB86A07),
      _ => AppColors.textGrey,
    };
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color titleColor;
  final Color iconColor;
  final Color iconBackgroundColor;
  final Widget? trailing;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.titleColor = AppColors.textDark,
    this.iconColor = AppColors.primary,
    this.iconBackgroundColor = const Color(0xFFFFF2EA),
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
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
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textGrey,
                      height: 1.4,
                    ),
                  ),
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

class _AccountSecurityErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _AccountSecurityErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.security_outlined,
              size: 38,
              color: AppColors.textGrey,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  final String message;

  const _InlineNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.textDark, height: 1.4),
      ),
    );
  }
}
