import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/widgets/app_feedback.dart';
import '../../../../widgets/custom_button.dart';
import '../../../auth/data/services/auth_service.dart';
import '../../../auth/data/services/recent_login_service.dart';
import '../../../auth/presentation/widgets/auth_input_field.dart';
import '../../../auth/presentation/widgets/auth_shell.dart';
import '../../../auth/presentation/widgets/common_phone_field.dart';

enum _PhoneChangeStep {
  reauthenticateCurrentPhone,
  verifyCurrentPhoneOtp,
  enterNewPhone,
  verifyNewPhoneOtp,
}

class ChangePhoneNumberScreen extends StatefulWidget {
  const ChangePhoneNumberScreen({super.key});

  @override
  State<ChangePhoneNumberScreen> createState() =>
      _ChangePhoneNumberScreenState();
}

class _ChangePhoneNumberScreenState extends State<ChangePhoneNumberScreen> {
  final AuthService _authService = AuthService();
  final RecentLoginService _recentLoginService = RecentLoginService();
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _currentOtpController = TextEditingController();
  final TextEditingController _newOtpController = TextEditingController();

  bool _isBusy = false;
  bool _obscurePassword = true;
  bool _currentPhoneReauthenticated = false;
  String? _currentPasswordError;
  String? _newPhoneError;
  String? _currentOtpError;
  String? _newOtpError;
  String _newPhoneNumber = '';
  String? _currentPhoneVerificationId;
  String? _newPhoneVerificationId;
  int? _currentPhoneResendToken;
  int? _newPhoneResendToken;

  bool get _hasPasswordProvider {
    final providerIds = {
      for (final provider
          in _authService.currentUser?.providerData ?? const <UserInfo>[])
        provider.providerId.trim(),
    };
    return providerIds.contains('password');
  }

  _PhoneChangeStep get _step {
    if (!_hasPasswordProvider &&
        !_currentPhoneReauthenticated &&
        _currentPhoneVerificationId == null) {
      return _PhoneChangeStep.reauthenticateCurrentPhone;
    }
    if (!_hasPasswordProvider &&
        !_currentPhoneReauthenticated &&
        _currentPhoneVerificationId != null) {
      return _PhoneChangeStep.verifyCurrentPhoneOtp;
    }
    if (_newPhoneVerificationId == null) {
      return _PhoneChangeStep.enterNewPhone;
    }
    return _PhoneChangeStep.verifyNewPhoneOtp;
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _currentOtpController.dispose();
    _newOtpController.dispose();
    super.dispose();
  }

  String? _validateNewPhone(String phoneNumber) {
    final trimmed = phoneNumber.trim();
    if (trimmed.isEmpty) {
      return 'Phone number is required';
    }
    if (!RegExp(r'^\+\d{10,15}$').hasMatch(trimmed)) {
      return 'Enter a valid phone number';
    }
    final currentPhone = (_authService.currentUser?.phoneNumber ?? '').trim();
    if (trimmed == currentPhone) {
      return 'Choose a different phone number';
    }
    return null;
  }

  String? _initialPhoneNumber(String phoneNumber) {
    final trimmed = phoneNumber.trim();
    if (trimmed.startsWith('+91') && trimmed.length > 3) {
      return trimmed.substring(3);
    }
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _sendCurrentPhoneCode() async {
    final currentPhone = _recentLoginService.requireCurrentUserPhoneNumber();
    setState(() => _isBusy = true);
    await _recentLoginService.sendPhoneReauthenticationCode(
      phoneNumber: currentPhone,
      forceResendingToken: _currentPhoneResendToken,
      codeSent: (verificationId, resendToken) async {
        if (!mounted) return;
        setState(() {
          _currentPhoneVerificationId = verificationId;
          _currentPhoneResendToken = resendToken;
          _isBusy = false;
        });
        AppFeedback.show(
          context,
          message: 'OTP sent to your current phone number.',
          tone: AppFeedbackTone.success,
        );
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
          await _authService.reauthenticateCurrentUserWithPhoneAuthCredential(
            credential,
          );
          if (!mounted) return;
          setState(() {
            _currentPhoneReauthenticated = true;
            _currentPhoneVerificationId = null;
            _isBusy = false;
          });
        } catch (_) {
          if (mounted) {
            setState(() => _isBusy = false);
          }
        }
      },
    );
  }

  Future<void> _confirmCurrentPhoneOtp() async {
    final verificationId = _currentPhoneVerificationId;
    final smsCode = _currentOtpController.text.trim();
    setState(() {
      _currentOtpError = smsCode.isEmpty ? 'Enter the OTP' : null;
    });
    if (verificationId == null || _currentOtpError != null) return;

    setState(() => _isBusy = true);
    try {
      await _recentLoginService.reauthenticateWithPhoneOtp(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      _currentOtpController.clear();
      if (!mounted) return;
      setState(() {
        _currentPhoneVerificationId = null;
        _currentPhoneReauthenticated = true;
        _isBusy = false;
      });
      AppFeedback.show(
        context,
        message: 'Current phone number confirmed.',
        tone: AppFeedbackTone.success,
      );
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

  Future<void> _sendNewPhoneCode() async {
    final validationError = _validateNewPhone(_newPhoneNumber);
    setState(() => _newPhoneError = validationError);
    if (validationError != null) return;

    if (_hasPasswordProvider) {
      final password = _currentPasswordController.text;
      setState(() {
        _currentPasswordError = password.trim().isEmpty
            ? 'Current password is required'
            : null;
      });
      if (_currentPasswordError != null) return;
    }

    setState(() => _isBusy = true);
    try {
      if (_hasPasswordProvider) {
        await _recentLoginService.reauthenticateWithPassword(
          currentPassword: _currentPasswordController.text,
        );
      }
      await _recentLoginService.sendPhoneReauthenticationCode(
        phoneNumber: _newPhoneNumber,
        forceResendingToken: _newPhoneResendToken,
        codeSent: (verificationId, resendToken) async {
          if (!mounted) return;
          setState(() {
            _newPhoneVerificationId = verificationId;
            _newPhoneResendToken = resendToken;
            _isBusy = false;
          });
          AppFeedback.show(
            context,
            message: 'OTP sent to your new phone number.',
            tone: AppFeedbackTone.success,
          );
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
          setState(() => _isBusy = true);
          try {
            await _authService.updateCurrentUserPhoneNumberWithCredential(
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

  Future<void> _confirmNewPhoneOtp() async {
    final verificationId = _newPhoneVerificationId;
    final smsCode = _newOtpController.text.trim();
    setState(() {
      _newOtpError = smsCode.isEmpty ? 'Enter the OTP' : null;
    });
    if (verificationId == null || _newOtpError != null) return;

    setState(() => _isBusy = true);
    try {
      await _authService.updateCurrentUserPhoneNumber(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      _newOtpController.clear();
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'Your phone number has been updated.',
        tone: AppFeedbackTone.success,
      );
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
    final currentPhone = (_authService.currentUser?.phoneNumber ?? '').trim();

    return AuthShell(
      title: 'Change Phone Number',
      subtitle:
          'Pettxo keeps the same Firebase UID. First confirm the current account, then verify the new phone number.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_hasPasswordProvider &&
              _step == _PhoneChangeStep.reauthenticateCurrentPhone) ...[
            Text(
              'We will send an OTP to ${currentPhone.isEmpty ? 'your current phone number' : currentPhone}.',
            ),
            const SizedBox(height: 20),
            CustomButton(
              text: _isBusy ? 'Sending...' : 'Send Code To Current Phone',
              onPressed: _isBusy ? null : _sendCurrentPhoneCode,
            ),
          ] else if (!_hasPasswordProvider &&
              _step == _PhoneChangeStep.verifyCurrentPhoneOtp) ...[
            AuthInputField(
              controller: _currentOtpController,
              labelText: 'Current Phone OTP',
              errorText: _currentOtpError,
              onChanged: (_) {
                if (_currentOtpError != null) {
                  setState(() => _currentOtpError = null);
                }
              },
            ),
            const SizedBox(height: 20),
            CustomButton(
              text: _isBusy ? 'Verifying...' : 'Confirm Current Phone',
              onPressed: _isBusy ? null : _confirmCurrentPhoneOtp,
            ),
          ] else ...[
            if (_hasPasswordProvider) ...[
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
            ],
            if (_step == _PhoneChangeStep.enterNewPhone) ...[
              CommonPhoneField(
                initialNumber: _initialPhoneNumber(_newPhoneNumber),
                labelText: 'New Phone Number',
                errorText: _newPhoneError,
                onChanged: (value) {
                  setState(() {
                    _newPhoneNumber = value.trim();
                    _newPhoneError = _validateNewPhone(_newPhoneNumber);
                  });
                },
              ),
              const SizedBox(height: 20),
              CustomButton(
                text: _isBusy ? 'Sending...' : 'Send OTP To New Phone',
                onPressed: _isBusy ? null : _sendNewPhoneCode,
              ),
            ] else ...[
              CommonPhoneField(
                initialNumber: _initialPhoneNumber(_newPhoneNumber),
                labelText: 'New Phone Number',
                errorText: _newPhoneError,
                enabled: false,
                onChanged: (_) {},
              ),
              const SizedBox(height: 16),
              AuthInputField(
                controller: _newOtpController,
                labelText: 'New Phone OTP',
                errorText: _newOtpError,
                onChanged: (_) {
                  if (_newOtpError != null) {
                    setState(() => _newOtpError = null);
                  }
                },
              ),
              const SizedBox(height: 20),
              CustomButton(
                text: _isBusy ? 'Updating...' : 'Verify And Update Phone',
                onPressed: _isBusy ? null : _confirmNewPhoneOtp,
              ),
            ],
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
