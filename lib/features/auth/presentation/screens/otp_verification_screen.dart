import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../widgets/custom_button.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/user_service.dart';
import '../../domain/models/phone_auth_flow.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;
  final int? resendToken;
  final PhoneAuthFlow flow;

  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    required this.flow,
    this.resendToken,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  static const int _otpLength = 6;
  static const int _resendDelay = 30;

  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  final List<TextEditingController> _controllers = List.generate(
    _otpLength,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    _otpLength,
    (_) => FocusNode(),
  );

  late String _verificationId;
  int? _resendToken;
  int _secondsLeft = _resendDelay;
  bool _isSubmitting = false;
  bool _didNavigate = false;
  Timer? _timer;

  bool get _isOtpComplete =>
      _controllers.every((controller) => controller.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNodes.first.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsLeft = _resendDelay;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _secondsLeft = 0;
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _secondsLeft -= 1;
        });
      }
    });
  }

  Future<void> _handleVerifiedUser() async {
    if (_didNavigate || !mounted) return;
    _didNavigate = true;

    if (widget.flow == PhoneAuthFlow.signUp) {
      Navigator.pushNamedAndRemoveUntil(context, '/profile-type', (r) => false);
      return;
    }

    final route = await _userService.getPostAuthRoute();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, route, (r) => false);
  }

  Future<void> _submitOtp() async {
    if (!_isOtpComplete || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final smsCode = _controllers.map((controller) => controller.text).join();
      await _authService.signInWithPhoneCredential(
        verificationId: _verificationId,
        smsCode: smsCode,
      );
      await _handleVerifiedUser();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _resendCode() async {
    if (_secondsLeft > 0) return;

    await _authService.verifyPhoneNumber(
      phoneNumber: widget.phoneNumber,
      forceResendingToken: _resendToken,
      verificationCompleted: (credential) async {
        if (_didNavigate) return;
        await _authService.signInWithCredential(credential);
        await _handleVerifiedUser();
      },
      codeSent: (verificationId, resendToken) async {
        if (!mounted) return;
        _verificationId = verificationId;
        _resendToken = resendToken;
        _startTimer();
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OTP resent successfully')),
        );
      },
      verificationFailed: (message) async {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      },
    );
  }

  String _formatPhoneNumber(String phone) {
    if (!phone.startsWith('+91')) {
      return phone;
    }
    final digits = phone.substring(3);
    if (digits.length != 10) {
      return phone;
    }
    return '+91 ${digits.substring(0, 5)} ${digits.substring(5)}';
  }

  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      final chars = value.split('');
      for (var i = 0; i < chars.length && index + i < _otpLength; i++) {
        _controllers[index + i].text = chars[i];
      }
      final nextIndex = (index + chars.length).clamp(0, _otpLength - 1);
      _focusNodes[nextIndex].requestFocus();
    } else if (value.isNotEmpty && index < _otpLength - 1) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final formattedSeconds = _secondsLeft.toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(36, 36),
                ),
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
              ),
              const SizedBox(height: 28),
              const Text(
                'We just sent an OTP to',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _formatPhoneNumber(widget.phoneNumber),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Edit Number',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: List.generate(_otpLength, (index) {
                  final isFocused = _focusNodes[index].hasFocus;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: index == _otpLength - 1 ? 0 : 10,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isFocused
                                ? AppColors.primary
                                : const Color(0xFFDADADA),
                            width: isFocused ? 1.8 : 1,
                          ),
                          boxShadow: isFocused
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    blurRadius: 16,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : const [],
                        ),
                        child: TextField(
                          controller: _controllers[index],
                          focusNode: _focusNodes[index],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 1,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (value) => _onDigitChanged(index, value),
                          decoration: const InputDecoration(
                            counterText: '',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 18),
                          ),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              _secondsLeft > 0
                  ? RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 15,
                        ),
                        children: [
                          const TextSpan(text: 'Resend code in '),
                          TextSpan(
                            text: '00:$formattedSeconds',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    )
                  : TextButton(
                      onPressed: _resendCode,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text(
                        'Resend code',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
              const Spacer(),
              Opacity(
                opacity: _isOtpComplete ? 1 : 0.45,
                child: IgnorePointer(
                  ignoring: !_isOtpComplete || _isSubmitting,
                  child: CustomButton(
                    text: _isSubmitting ? 'Submitting...' : 'Submit OTP',
                    onPressed: _submitOtp,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
