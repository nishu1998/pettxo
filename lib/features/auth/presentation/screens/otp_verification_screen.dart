import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sms_autofill/sms_autofill.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_snackbar.dart';
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

class _OtpVerificationScreenState extends State<OtpVerificationScreen>
    with CodeAutoFill {
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
  String? _lastAutoSubmittedCode;

  bool get _isOtpComplete =>
      _controllers.every((controller) => controller.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
    _startTimer();
    _startOtpListener();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNodes.first.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    cancel();
    SmsAutoFill().unregisterListener();
    _timer?.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _startOtpListener() async {
    try {
      await SmsAutoFill().listenForCode();
    } catch (_) {
      // Best-effort only. Manual OTP entry remains available.
    }
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
      final smsCode = _currentOtpCode;
      await _authService.signInWithPhoneCredential(
        verificationId: _verificationId,
        smsCode: smsCode,
      );
      await _handleVerifiedUser();
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(
        context,
        e.toString().replaceFirst('Exception: ', ''),
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
        _lastAutoSubmittedCode = null;
        _clearOtpFields();
        await _startOtpListener();
        if (!mounted) return;
        _startTimer();
        setState(() {});
        AppSnackbar.showSuccess(context, 'OTP resent successfully');
      },
      verificationFailed: (message) async {
        if (!mounted) return;
        AppSnackbar.showError(context, message);
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

  String get _currentOtpCode =>
      _controllers.map((controller) => controller.text.trim()).join();

  void _clearOtpFields() {
    for (final controller in _controllers) {
      controller.clear();
    }
  }

  String _sanitizeOtp(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
  }

  Future<void> _applyOtpCode(
    String rawValue, {
    bool shouldAutoSubmit = false,
  }) async {
    final sanitized = _sanitizeOtp(rawValue);
    if (sanitized.isEmpty) return;

    final limited = sanitized.length > _otpLength
        ? sanitized.substring(0, _otpLength)
        : sanitized;

    for (var i = 0; i < _otpLength; i++) {
      _controllers[i].text = i < limited.length ? limited[i] : '';
    }

    final nextFocusIndex = limited.length == _otpLength
        ? _otpLength - 1
        : limited.length.clamp(0, _otpLength - 1);
    if (mounted) {
      _focusNodes[nextFocusIndex].requestFocus();
      setState(() {});
    }

    if (shouldAutoSubmit && limited.length == _otpLength) {
      await _maybeAutoSubmitOtp(limited);
    }
  }

  Future<void> _maybeAutoSubmitOtp(String otp) async {
    if (_isSubmitting || otp.length != _otpLength) return;
    if (_lastAutoSubmittedCode == otp) return;

    _lastAutoSubmittedCode = otp;
    await _submitOtp();
  }

  void _onDigitChanged(int index, String value) {
    final sanitized = _sanitizeOtp(value);
    if (sanitized.length > 1) {
      unawaited(_handleOtpDetected(sanitized, autoSubmit: true));
      return;
    } else if (value.isNotEmpty && index < _otpLength - 1) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    setState(() {});
  }

  Future<void> _handleOtpDetected(
    String code, {
    required bool autoSubmit,
  }) async {
    await _applyOtpCode(code, shouldAutoSubmit: autoSubmit);
  }

  @override
  void codeUpdated() {
    final detectedCode = code;
    if (detectedCode == null || detectedCode.isEmpty) return;
    unawaited(_handleOtpDetected(detectedCode, autoSubmit: true));
  }

  @override
  Widget build(BuildContext context) {
    final formattedSeconds = _secondsLeft.toString().padLeft(2, '0');
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isKeyboardOpen = viewInsets.bottom > 0;
            final otpSpacing = constraints.maxWidth < 360 ? 8.0 : 10.0;
            final titleGap = isKeyboardOpen ? 18.0 : 28.0;
            final sectionGap = isKeyboardOpen ? 20.0 : 28.0;

            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + viewInsets.bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 40,
                ),
                child: IntrinsicHeight(
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
                      SizedBox(height: titleGap),
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
                      SizedBox(height: sectionGap),
                      AutofillGroup(
                        child: Row(
                          children: List.generate(_otpLength, (index) {
                            final isFocused = _focusNodes[index].hasFocus;
                            return Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: index == _otpLength - 1
                                      ? 0
                                      : otpSpacing,
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
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.12),
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
                                    textInputAction: index == _otpLength - 1
                                        ? TextInputAction.done
                                        : TextInputAction.next,
                                    autofillHints: index == 0
                                        ? const [AutofillHints.oneTimeCode]
                                        : null,
                                    textAlign: TextAlign.center,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(
                                        _otpLength,
                                      ),
                                    ],
                                    onChanged: (value) =>
                                        _onDigitChanged(index, value),
                                    onSubmitted: (_) {
                                      if (_isOtpComplete) {
                                        unawaited(_submitOtp());
                                      }
                                    },
                                    decoration: const InputDecoration(
                                      counterText: '',
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(
                                        vertical: 18,
                                      ),
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
                      SizedBox(height: isKeyboardOpen ? 24 : 0),
                      const Spacer(),
                      const SizedBox(height: 20),
                      Opacity(
                        opacity: _isOtpComplete ? 1 : 0.45,
                        child: IgnorePointer(
                          ignoring: !_isOtpComplete || _isSubmitting,
                          child: CustomButton(
                            text: _isSubmitting
                                ? 'Submitting...'
                                : 'Submit OTP',
                            onPressed: _submitOtp,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
