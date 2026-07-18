import 'package:flutter/material.dart';

import '../../../../core/widgets/app_feedback.dart';
import '../../../../widgets/custom_button.dart';
import '../../data/services/auth_service.dart';
import '../../domain/models/phone_auth_flow.dart';
import '../widgets/auth_shell.dart';
import '../widgets/common_phone_field.dart';
import '../widgets/phone_auth_verification_overlay.dart';
import 'auth_gateway_screen.dart';
import 'otp_verification_screen.dart';

class LinkPhoneScreen extends StatefulWidget {
  const LinkPhoneScreen({super.key});

  @override
  State<LinkPhoneScreen> createState() => _LinkPhoneScreenState();
}

class _LinkPhoneScreenState extends State<LinkPhoneScreen> {
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

  Future<void> _continueToPhoneLink() async {
    if (_isLoading) return;
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
        await _authService.linkCurrentUserWithCredential(credential);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) =>
                const AuthGatewayScreen(reloadUserBeforeResolve: true),
          ),
          (route) => false,
        );
      },
      codeSent: (verificationId, resendToken) async {
        if (_didNavigate || !mounted) return;
        _didNavigate = true;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpVerificationScreen(
              phoneNumber: _fullPhoneNumber,
              verificationId: verificationId,
              resendToken: resendToken,
              flow: PhoneAuthFlow.linkPhone,
            ),
          ),
        );
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _didNavigate = false;
        });
      },
      verificationFailed: (message) async {
        if (!mounted) return;
        setState(() => _isLoading = false);
        AppFeedback.show(
          context,
          message: message,
          tone: AppFeedbackTone.error,
        );
      },
    );

    if (mounted && !_didNavigate) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AuthShell(
          title: 'Verify Your Phone',
          subtitle:
              'Link a phone number to this email account before creating your Pettxo profile.',
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
                onSubmitted: (_) => _continueToPhoneLink(),
              ),
              const SizedBox(height: 18),
              CustomButton(
                text: _isLoading ? 'Please wait...' : 'Send OTP',
                onPressed: _isLoading ? null : _continueToPhoneLink,
              ),
            ],
          ),
        ),
        if (_isLoading)
          const PhoneAuthVerificationOverlay(
            message: 'Verifying your number securely...',
          ),
      ],
    );
  }
}
