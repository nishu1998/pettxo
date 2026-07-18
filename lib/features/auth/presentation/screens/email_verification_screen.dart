import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../widgets/custom_button.dart';
import '../../domain/models/email_verification_mode.dart';
import '../../domain/utils/email_verification_controller.dart';
import '../../data/services/auth_onboarding_service.dart';
import '../../data/services/auth_service.dart';
import '../../domain/utils/auth_onboarding_resolver.dart';
import '../widgets/auth_shell.dart';
import 'auth_gateway_screen.dart';
import 'signup_screen.dart';

class EmailVerificationScreen extends StatefulWidget {
  final EmailVerificationMode mode;
  final String? displayEmailOverride;
  final String? expectedVerifiedEmail;

  const EmailVerificationScreen({
    super.key,
    this.mode = EmailVerificationMode.blockingOnboarding,
    this.displayEmailOverride,
    this.expectedVerifiedEmail,
  });

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  static const int _cooldownSeconds = 30;

  final AuthService _authService = AuthService();
  final AuthOnboardingService _onboardingService = AuthOnboardingService();
  late final EmailVerificationController _verificationController;

  Timer? _timer;
  int _secondsLeft = 0;
  bool _isChecking = false;
  bool _isResending = false;
  bool _isRestarting = false;

  String get _maskedEmail {
    final email =
        (widget.displayEmailOverride ?? _authService.currentUser?.email ?? '')
            .trim();
    final parts = email.split('@');
    if (parts.length != 2 || parts.first.isEmpty) return email;
    final local = parts.first;
    final maskedLocal = local.length <= 2
        ? '${local[0]}*'
        : '${local.substring(0, 2)}***';
    return '$maskedLocal@${parts.last}';
  }

  @override
  void initState() {
    super.initState();
    _verificationController = EmailVerificationController(
      reloadCurrentUser: () async {
        await _authService.reloadCurrentUser();
      },
      isEmailVerified: () {
        final currentUser = _authService.currentUser;
        final expectedEmail = (widget.expectedVerifiedEmail ?? '').trim();
        if (expectedEmail.isNotEmpty) {
          return (currentUser?.email ?? '').trim() == expectedEmail &&
              (currentUser?.emailVerified ?? false);
        }
        return currentUser?.emailVerified ?? false;
      },
      syncTrustedAuthIdentity: _authService.syncTrustedAuthIdentity,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkVerificationStatus() async {
    if (_isChecking) return;
    setState(() => _isChecking = true);

    try {
      final isVerified = await _verificationController
          .refreshVerificationStatus();
      if (!mounted) return;

      if (!isVerified) {
        AppFeedback.show(
          context,
          message: 'Your email is still unverified. Please check your inbox.',
          tone: AppFeedbackTone.info,
        );
      } else {
        if (widget.mode.blocksAppAccess) {
          final resolution = await _onboardingService.resolveCurrentState();
          if (!mounted) return;
          if (resolution.state ==
              AuthOnboardingState.emailVerificationRequired) {
            AppFeedback.show(
              context,
              message:
                  'Your email is verified, but Pettxo still needs a quick refresh. Please try again.',
              tone: AppFeedbackTone.info,
            );
          } else {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) =>
                    const AuthGatewayScreen(reloadUserBeforeResolve: true),
              ),
              (route) => false,
            );
          }
        } else {
          AppFeedback.show(
            context,
            message: 'Your linked email is now verified.',
            tone: AppFeedbackTone.success,
          );
          Navigator.of(context).pop(true);
        }
      }
    } catch (error) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: error.toString().replaceFirst('Exception: ', ''),
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  Future<void> _resendVerificationEmail() async {
    if (_isResending || _secondsLeft > 0) return;
    setState(() => _isResending = true);

    try {
      await _authService.sendCurrentUserEmailVerification();
      _startCooldown();
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'Verification email sent again.',
        tone: AppFeedbackTone.success,
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: error.toString().replaceFirst('Exception: ', ''),
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  Future<void> _restartSignup() async {
    if (_isRestarting) return;
    setState(() => _isRestarting = true);
    try {
      await _authService.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SignupScreen()),
        (route) => false,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isRestarting = false);
      AppFeedback.show(
        context,
        message: 'Unable to restart signup right now.',
        tone: AppFeedbackTone.error,
      );
    }
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _secondsLeft = _cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() => _secondsLeft = 0);
        }
        return;
      }
      if (mounted) {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final resendLabel = _secondsLeft > 0
        ? 'Resend in ${_secondsLeft.toString().padLeft(2, '0')}s'
        : 'Resend verification email';

    return AuthShell(
      title: widget.mode.title,
      subtitle: widget.mode.subtitle(_maskedEmail),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.14),
              ),
            ),
            child: Text(
              widget.mode.blocksAppAccess
                  ? 'We use Firebase email verification for this step. After you verify, come back here and tap “I have verified”.'
                  : 'Your phone sign-in stays active while this linked email is pending. After you verify it, come back here and tap “I have verified”.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 20),
          CustomButton(
            text: _isChecking ? 'Checking...' : 'I have verified',
            onPressed: _isChecking ? null : _checkVerificationStatus,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: (_isResending || _secondsLeft > 0)
                ? null
                : _resendVerificationEmail,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
            ),
            child: Text(_isResending ? 'Sending...' : resendLabel),
          ),
          const SizedBox(height: 12),
          if (widget.mode.blocksAppAccess)
            TextButton(
              onPressed: _isRestarting ? null : _restartSignup,
              child: Text(
                _isRestarting ? 'Please wait...' : 'Use a different email',
              ),
            )
          else
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Back to Account & Security'),
            ),
        ],
      ),
    );
  }
}
