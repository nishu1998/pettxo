import 'package:flutter/material.dart';

import '../../../../core/widgets/app_feedback.dart';
import '../../../../widgets/custom_button.dart';
import '../../../auth/data/services/auth_service.dart';
import '../../../auth/domain/utils/password_validation.dart';
import '../../../auth/presentation/widgets/auth_input_field.dart';
import '../../../auth/presentation/widgets/auth_shell.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  String? _currentPasswordError;
  String? _newPasswordError;
  String? _confirmPasswordError;
  bool _isSubmitting = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text.trim();
    final confirmation = _confirmPasswordController.text.trim();

    setState(() {
      _currentPasswordError = currentPassword.trim().isEmpty
          ? 'Current password is required'
          : null;
      _newPasswordError = validateAccountSecurityPassword(newPassword);
      _confirmPasswordError = validatePasswordConfirmation(
        password: newPassword,
        confirmation: confirmation,
      );
      if (_newPasswordError == null && currentPassword == newPassword) {
        _newPasswordError =
            'Choose a new password instead of reusing the current one';
      }
    });

    if (_currentPasswordError != null ||
        _newPasswordError != null ||
        _confirmPasswordError != null) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _authService.changeCurrentUserPassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'Your password has been updated.',
        tone: AppFeedbackTone.success,
      );
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
      title: 'Change Password',
      subtitle:
          'Re-enter your current password before saving a new one for this Pettxo account.',
      child: Column(
        children: [
          AuthInputField(
            controller: _currentPasswordController,
            labelText: 'Current Password',
            errorText: _currentPasswordError,
            obscureText: _obscureCurrentPassword,
            onChanged: (_) {
              if (_currentPasswordError != null) {
                setState(() => _currentPasswordError = null);
              }
            },
            suffixIcon: IconButton(
              icon: Icon(
                _obscureCurrentPassword
                    ? Icons.visibility_off
                    : Icons.visibility,
              ),
              onPressed: () {
                setState(
                  () => _obscureCurrentPassword = !_obscureCurrentPassword,
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          AuthInputField(
            controller: _newPasswordController,
            labelText: 'New Password',
            errorText: _newPasswordError,
            helperText: 'Use at least 6 characters with no spaces.',
            obscureText: _obscureNewPassword,
            onChanged: (_) {
              if (_newPasswordError != null) {
                setState(() => _newPasswordError = null);
              }
            },
            suffixIcon: IconButton(
              icon: Icon(
                _obscureNewPassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () {
                setState(() => _obscureNewPassword = !_obscureNewPassword);
              },
            ),
          ),
          const SizedBox(height: 16),
          AuthInputField(
            controller: _confirmPasswordController,
            labelText: 'Confirm New Password',
            errorText: _confirmPasswordError,
            obscureText: _obscureConfirmPassword,
            onChanged: (_) {
              if (_confirmPasswordError != null) {
                setState(() => _confirmPasswordError = null);
              }
            },
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_off
                    : Icons.visibility,
              ),
              onPressed: () {
                setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword,
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          CustomButton(
            text: _isSubmitting ? 'Updating...' : 'Update Password',
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
