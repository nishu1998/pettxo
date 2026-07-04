import 'package:flutter/material.dart';

import '../../../../core/widgets/app_snackbar.dart';
import '../../../../widgets/custom_button.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/user_service.dart';
import '../../domain/models/phone_auth_flow.dart';
import '../widgets/auth_shell.dart';
import '../widgets/common_phone_field.dart';
import 'otp_verification_screen.dart';

class SignInWithPhoneScreen extends StatefulWidget {
  const SignInWithPhoneScreen({super.key});

  @override
  State<SignInWithPhoneScreen> createState() => _SignInWithPhoneScreenState();
}

class _SignInWithPhoneScreenState extends State<SignInWithPhoneScreen> {
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
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
        await _authService.signInWithCredential(credential);
        if (!mounted) return;
        final route = await _userService.getPostAuthRoute();
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, route, (route) => false);
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
              flow: PhoneAuthFlow.signIn,
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
      title: 'Welcome Back',
      subtitle:
          'Sign in to continue exploring pets, bookings, and your community.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
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
          const SizedBox(height: 12),
          CustomButton(
            text: _isLoading ? 'Please wait...' : 'Continue',
            onPressed: _isLoading ? null : _continueWithPhone,
          ),
          const SizedBox(height: 24),
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
                'Continue with Email',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'New to Pettxo?',
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/signup');
                },
                child: const Text('Create account'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
