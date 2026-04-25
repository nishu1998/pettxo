import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../widgets/custom_button.dart';
import '../../data/services/auth_service.dart';
import '../../domain/models/phone_auth_flow.dart';
import '../widgets/auth_shell.dart';
import '../widgets/common_phone_field.dart';
import 'otp_verification_screen.dart';

class SignUpWithPhoneScreen extends StatefulWidget {
  const SignUpWithPhoneScreen({super.key});

  @override
  State<SignUpWithPhoneScreen> createState() => _SignUpWithPhoneScreenState();
}

class _SignUpWithPhoneScreenState extends State<SignUpWithPhoneScreen> {
  final AuthService _authService = AuthService();
  final FocusNode _phoneFocus = FocusNode();

  String? _phoneError;
  String _fullPhoneNumber = '';
  bool _isLoading = false;
  bool _didNavigate = false;

  @override
  void dispose() {
    _phoneFocus.dispose();
    super.dispose();
  }

  String? _validatePhone(String value) {
    if (value.trim().isEmpty) {
      return 'Phone number is required';
    }
    if (!RegExp(r'^\+\d{10,15}$').hasMatch(value.trim())) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  Future<void> _continueWithPhone() async {
    final error = _validatePhone(_fullPhoneNumber);
    setState(() {
      _phoneError = error;
    });

    if (error != null) return;

    setState(() {
      _isLoading = true;
      _didNavigate = false;
    });

    await _authService.verifyPhoneNumber(
      phoneNumber: _fullPhoneNumber,
      verificationCompleted: (credential) async {
        if (_didNavigate) return;
        _didNavigate = true;
        await _authService.signInWithCredential(credential);
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/profile-type',
          (route) => false,
        );
      },
      codeSent: (verificationId, resendToken) async {
        if (_didNavigate || !mounted) return;
        _didNavigate = true;
        setState(() {
          _isLoading = false;
        });
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpVerificationScreen(
              phoneNumber: _fullPhoneNumber,
              verificationId: verificationId,
              resendToken: resendToken,
              flow: PhoneAuthFlow.signUp,
            ),
          ),
        );
      },
      verificationFailed: (message) async {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
        AppSnackbar.showError(context, message);
      },
    );

    if (mounted && !_didNavigate) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Create Account',
      subtitle: 'Sign up with your phone number to join the Pettexo community.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommonPhoneField(
            focusNode: _phoneFocus,
            textInputAction: TextInputAction.done,
            labelText: 'Phone Number',
            errorText: _phoneError,
            onChanged: (value) {
              setState(() {
                _fullPhoneNumber = value.trim();
                _phoneError = _validatePhone(_fullPhoneNumber);
              });
            },
            onSubmitted: (_) => _continueWithPhone(),
          ),
          const SizedBox(height: 20),
          CustomButton(
            text: _isLoading ? 'Please wait...' : 'Continue',
            onPressed: _isLoading ? null : _continueWithPhone,
          ),
          const SizedBox(height: 18),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFF75927),
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Back to Sign Up',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: RichText(
              textAlign: TextAlign.center,
              text: const TextSpan(
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 13,
                  height: 1.6,
                ),
                children: [
                  TextSpan(
                    text: 'By signing up with Pettexo, you agree to our ',
                  ),
                  TextSpan(
                    text: 'Terms',
                    style: TextStyle(
                      color: AppColors.textDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: ' & '),
                  TextSpan(
                    text: 'Privacy Statement',
                    style: TextStyle(
                      color: AppColors.textDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
