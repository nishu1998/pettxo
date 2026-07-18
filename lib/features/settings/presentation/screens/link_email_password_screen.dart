import 'package:flutter/material.dart';

import '../../../../core/constants/validators.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../auth/data/services/auth_service.dart';
import '../../../auth/domain/models/email_verification_mode.dart';
import '../../../auth/domain/utils/password_validation.dart';
import '../../../auth/presentation/screens/email_verification_screen.dart';
import '../../../auth/presentation/widgets/auth_input_field.dart';
import '../../../auth/presentation/widgets/auth_shell.dart';
import '../../../../widgets/custom_button.dart';

class LinkEmailPasswordScreen extends StatefulWidget {
  const LinkEmailPasswordScreen({super.key});

  @override
  State<LinkEmailPasswordScreen> createState() =>
      _LinkEmailPasswordScreenState();
}

class _LinkEmailPasswordScreenState extends State<LinkEmailPasswordScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmation = _confirmController.text.trim();

    setState(() {
      _emailError = Validators.validateEmail(email);
      _passwordError = validateAccountSecurityPassword(password);
      _confirmError = validatePasswordConfirmation(
        password: password,
        confirmation: confirmation,
      );
    });

    if (_emailError != null ||
        _passwordError != null ||
        _confirmError != null) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _authService.linkCurrentUserWithEmailPassword(
        email: email,
        password: password,
      );
      if (!mounted) return;
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const EmailVerificationScreen(
            mode: EmailVerificationMode.nonBlockingLinkedEmail,
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
      title: 'Add Email & Password',
      subtitle:
          'Link email sign-in to this same Pettxo account. Your phone-authenticated UID stays unchanged.',
      child: Column(
        children: [
          AuthInputField(
            controller: _emailController,
            labelText: 'Email',
            errorText: _emailError,
            onChanged: (_) {
              if (_emailError != null) {
                setState(() => _emailError = null);
              }
            },
          ),
          const SizedBox(height: 16),
          AuthInputField(
            controller: _passwordController,
            labelText: 'Password',
            errorText: _passwordError,
            obscureText: _obscurePassword,
            helperText: 'Use at least 6 characters with no spaces.',
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
          const SizedBox(height: 16),
          AuthInputField(
            controller: _confirmController,
            labelText: 'Confirm Password',
            errorText: _confirmError,
            obscureText: _obscureConfirmPassword,
            onChanged: (_) {
              if (_confirmError != null) {
                setState(() => _confirmError = null);
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
            text: _isSubmitting ? 'Linking...' : 'Link Email & Password',
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
