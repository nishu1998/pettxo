import 'package:flutter/material.dart';

import '../../../../core/constants/validators.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../widgets/custom_button.dart';
import '../../../auth/data/services/auth_service.dart';
import '../../../auth/data/services/pending_email_change_service.dart';
import '../../../auth/data/services/recent_login_service.dart';
import '../../../auth/domain/models/email_verification_mode.dart';
import '../../../auth/presentation/screens/email_verification_screen.dart';
import '../../../auth/presentation/widgets/auth_input_field.dart';
import '../../../auth/presentation/widgets/auth_shell.dart';

class ChangeEmailScreen extends StatefulWidget {
  const ChangeEmailScreen({super.key});

  @override
  State<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends State<ChangeEmailScreen> {
  final AuthService _authService = AuthService();
  final RecentLoginService _recentLoginService = RecentLoginService();
  final PendingEmailChangeService _pendingEmailChangeService =
      const PendingEmailChangeService();
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  String? _currentPasswordError;
  String? _emailError;
  bool _isSubmitting = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final currentPassword = _currentPasswordController.text;
    final newEmail = _emailController.text.trim();
    final currentEmail = (_authService.currentUser?.email ?? '').trim();

    setState(() {
      _currentPasswordError = currentPassword.trim().isEmpty
          ? 'Current password is required'
          : null;
      _emailError = Validators.validateEmail(newEmail);
      if (_emailError == null && newEmail == currentEmail) {
        _emailError = 'Choose a different email address';
      }
    });

    if (_currentPasswordError != null || _emailError != null) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _recentLoginService.reauthenticateWithPassword(
        currentPassword: currentPassword,
      );
      await _authService.beginCurrentUserEmailChange(newEmail: newEmail);
      final uid = _authService.currentUser?.uid.trim() ?? '';
      if (uid.isNotEmpty) {
        await _pendingEmailChangeService.savePendingEmail(
          uid: uid,
          email: newEmail,
        );
      }
      _currentPasswordController.clear();
      _emailController.clear();
      if (!mounted) return;
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => EmailVerificationScreen(
            mode: EmailVerificationMode.nonBlockingLinkedEmail,
            displayEmailOverride: newEmail,
            expectedVerifiedEmail: newEmail,
          ),
        ),
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
    return AuthShell(
      title: 'Change Email',
      subtitle:
          'Re-enter your current password first. Pettxo will wait for the new email verification before trusting the change.',
      child: Column(
        children: [
          AuthInputField(
            controller: _currentPasswordController,
            labelText: 'Current Password',
            errorText: _currentPasswordError,
            obscureText: _obscurePassword,
            onChanged: (_) {
              if (_currentPasswordError != null) {
                setState(() => _currentPasswordError = null);
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
          const SizedBox(height: 16),
          AuthInputField(
            controller: _emailController,
            labelText: 'New Email',
            errorText: _emailError,
            onChanged: (_) {
              if (_emailError != null) {
                setState(() => _emailError = null);
              }
            },
          ),
          const SizedBox(height: 20),
          CustomButton(
            text: _isSubmitting ? 'Sending...' : 'Send Verification Link',
            onPressed: _isSubmitting ? null : _submit,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
