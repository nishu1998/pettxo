import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/constants/validators.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/email_sign_in_lockout_service.dart';
import '../../domain/models/password_reset_request_result.dart';
import 'auth_gateway_screen.dart';
import 'signin_with_phone_screen.dart';
import 'signup_screen.dart';

class SigninScreen extends StatefulWidget {
  const SigninScreen({super.key});

  @override
  State<SigninScreen> createState() => _SigninScreenState();
}

class _SigninScreenState extends State<SigninScreen> {
  final AuthService _authService = AuthService();
  final EmailSignInLockoutService _emailSignInLockoutService =
      EmailSignInLockoutService();
  final AnalyticsService _analytics = AnalyticsService.instance;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final emailFocus = FocusNode();
  final passwordFocus = FocusNode();

  String? emailError;
  String? passwordError;

  bool isLoading = false;
  bool obscurePassword = true;

  Future<void> _showForgotPasswordDialog() async {
    await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (_) => ForgotPasswordDialog(
        initialEmail: emailController.text.trim(),
        authService: _authService,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _analytics.logSignInViewed();
    });
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    emailFocus.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  Future<void> handleSignin() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    setState(() {
      emailError = Validators.validateEmail(email);
      passwordError = password.isEmpty ? "Password is required" : null;
    });

    if (emailError != null || passwordError != null) return;

    final lockoutState = await _emailSignInLockoutService.getState(email);
    if (!mounted) return;
    if (lockoutState.isLocked) {
      AppSnackbar.showError(
        context,
        _buildLockoutMessage(lockoutState),
        title: 'Too Many Attempts',
        duration: const Duration(seconds: 5),
      );
      return;
    }

    setState(() => isLoading = true);
    await _analytics.logSignInAttempt(method: 'email');

    final result = await _authService.login(email: email, password: password);

    if (!mounted) return;
    setState(() => isLoading = false);

    if (result.isSuccess) {
      await _emailSignInLockoutService.clear(email);
      await _analytics.logSignInResult(method: 'email', isSuccess: true);
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: "Welcome back",
        tone: AppFeedbackTone.success,
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) =>
              const AuthGatewayScreen(reloadUserBeforeResolve: true),
        ),
        (route) => false,
      );
    } else {
      await _analytics.logSignInResult(
        method: 'email',
        isSuccess: false,
        errorCode: result.errorCode ?? result.error,
      );
      if (!mounted) return;
      if (result.errorCode == 'wrong-password' ||
          (result.errorCode == null &&
              (result.error ?? '').toLowerCase().contains(
                'incorrect password',
              ))) {
        final nextState = await _emailSignInLockoutService
            .registerWrongPassword(email);
        if (!mounted) return;
        AppSnackbar.showError(
          context,
          nextState.isLocked
              ? _buildLockoutMessage(nextState)
              : _buildWrongPasswordMessage(nextState),
          title: nextState.isLocked
              ? 'Too Many Attempts'
              : 'Incorrect Password',
          duration: const Duration(seconds: 5),
        );
        return;
      }

      AppFeedback.show(
        context,
        message: result.error ?? "Login failed",
        tone: AppFeedbackTone.error,
      );
    }
  }

  String _buildWrongPasswordMessage(EmailSignInLockoutState state) {
    final remainingAttempts = state.remainingAttemptsBeforeLockout;
    if (remainingAttempts <= 0) {
      return 'Wrong password again. One more failed attempt will lock email sign-in for 30 minutes.';
    }
    final attemptLabel = remainingAttempts == 1 ? 'attempt' : 'attempts';
    return 'The password you entered is incorrect. $remainingAttempts $attemptLabel left before email sign-in is locked for 30 minutes.';
  }

  String _buildLockoutMessage(EmailSignInLockoutState state) {
    final remaining = state.remainingLockoutDuration;
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    if (minutes <= 0) {
      return 'Email sign-in is temporarily locked. Try again in less than a minute.';
    }
    if (seconds == 0) {
      return 'Email sign-in is temporarily locked. Try again in $minutes minutes.';
    }
    return 'Email sign-in is temporarily locked. Try again in $minutes min ${seconds.toString().padLeft(2, '0')} sec.';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 380;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFFFFCF8),
              AppColors.background,
              Color(0xFFFDF4ED),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 16 : 18,
                  vertical: compact ? 12 : 16,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - (compact ? 24 : 32),
                  ),
                  child: Column(
                    children: [
                      SizedBox(height: compact ? 60 : 68),
                      SizedBox(
                        width: compact ? 82 : 92,
                        height: compact ? 70 : 76,
                        child: SvgPicture.asset(
                          'assets/brand/pettxo_logo.svg',
                          fit: BoxFit.contain,
                        ),
                      ),
                      Transform.translate(
                        offset: const Offset(0, -8),
                        child: Text(
                          'Pettxo',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: compact ? 28 : 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 0 : 4),
                      Text(
                        'Welcome back',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textDark,
                          fontSize: compact ? 28 : 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.2,
                          height: 1.02,
                        ),
                      ),
                      SizedBox(height: compact ? 12 : 14),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 6 : 8,
                        ),
                        child: Text(
                          'Log in with your email to continue.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: const Color(0xFF958E88),
                            fontSize: compact ? 15 : 16,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 28 : 32),
                      _SigninField(
                        controller: emailController,
                        focusNode: emailFocus,
                        textInputAction: TextInputAction.next,
                        hintText: 'Email address',
                        errorText: emailError,
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (value) {
                          setState(() {
                            emailError = Validators.validateEmail(value);
                          });
                        },
                        onSubmitted: (_) {
                          FocusScope.of(context).requestFocus(passwordFocus);
                        },
                      ),
                      SizedBox(height: compact ? 14 : 16),
                      _SigninField(
                        controller: passwordController,
                        focusNode: passwordFocus,
                        textInputAction: TextInputAction.done,
                        hintText: 'Password',
                        errorText: passwordError,
                        obscureText: obscurePassword,
                        onChanged: (value) {
                          setState(() {
                            passwordError = value.isEmpty
                                ? 'Password is required'
                                : null;
                          });
                        },
                        onSubmitted: (_) => handleSignin(),
                        suffixIcon: IconButton(
                          splashRadius: 20,
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: const Color(0xFFA9A19A),
                          ),
                          onPressed: () {
                            setState(() {
                              obscurePassword = !obscurePassword;
                            });
                          },
                        ),
                      ),
                      SizedBox(height: compact ? 10 : 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _showForgotPasswordDialog,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Forgot Password?',
                            style: TextStyle(
                              fontSize: compact ? 13 : 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 14 : 16),
                      _SigninPrimaryButton(
                        label: isLoading ? 'Loging in...' : 'Continue',
                        compact: compact,
                        isLoading: isLoading,
                        onPressed: isLoading ? null : handleSignin,
                      ),
                      SizedBox(height: compact ? 10 : 12),
                      _SigninSecondaryButton(
                        label: 'Continue with phone',
                        compact: compact,
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SignInWithPhoneScreen(),
                            ),
                          );
                        },
                      ),
                      SizedBox(height: compact ? 20 : 22),
                      Padding(
                        padding: EdgeInsets.only(bottom: compact ? 6 : 8),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'New to Pettxo? ',
                              style: TextStyle(
                                color: const Color(0xFF958E88),
                                fontSize: compact ? 15 : 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const SignupScreen(),
                                  ),
                                );
                              },
                              child: Text(
                                'Create account',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: compact ? 15 : 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SigninField extends StatefulWidget {
  const _SigninField({
    required this.controller,
    required this.hintText,
    this.focusNode,
    this.textInputAction,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final String hintText;
  final String? errorText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffixIcon;

  @override
  State<_SigninField> createState() => _SigninFieldState();
}

class _SigninFieldState extends State<_SigninField> {
  late final FocusNode _focusNode;
  late final bool _ownsFocusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _isFocused = _focusNode.hasFocus;
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _handleFocusChange() {
    if (_isFocused == _focusNode.hasFocus) return;
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.errorText != null
        ? const Color(0xFFE16A6A)
        : (_isFocused ? AppColors.primary : const Color(0xFFE7E1DB));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: borderColor,
              width: _isFocused ? 1.5 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(
                  alpha: _isFocused ? 0.08 : 0.03,
                ),
                blurRadius: _isFocused ? 24 : 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            textInputAction: widget.textInputAction,
            keyboardType: widget.keyboardType,
            obscureText: widget.obscureText,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: const TextStyle(
                color: Color(0xFFAAA39C),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 22,
                vertical: 16,
              ),
              suffixIcon: widget.suffixIcon,
            ),
          ),
        ),
        if (widget.errorText != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              widget.errorText!,
              style: const TextStyle(
                color: Color(0xFFC94B4B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SigninPrimaryButton extends StatelessWidget {
  const _SigninPrimaryButton({
    required this.label,
    required this.compact,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool compact;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: compact ? 62 : 66,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: AppColors.brandGradient,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.2),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onPressed,
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      label,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 16 : 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SigninSecondaryButton extends StatelessWidget {
  const _SigninSecondaryButton({
    required this.label,
    required this.compact,
    required this.onPressed,
  });

  final String label;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: compact ? 62 : 66,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.primary, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          backgroundColor: Colors.white.withValues(alpha: 0.74),
          padding: EdgeInsets.zero,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: AppColors.primary,
            fontSize: compact ? 16 : 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
      ),
    );
  }
}

class ForgotPasswordDialog extends StatefulWidget {
  final String initialEmail;
  final AuthService? authService;
  final Future<PasswordResetRequestResult> Function(String email)?
  requestPasswordResetOverride;

  const ForgotPasswordDialog({
    super.key,
    required this.initialEmail,
    this.authService,
    this.requestPasswordResetOverride,
  }) : assert(
         authService != null || requestPasswordResetOverride != null,
         'Either authService or requestPasswordResetOverride must be provided.',
       );

  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  static const int _cooldownSeconds = 30;

  late final TextEditingController _controller;
  Timer? _timer;
  int _secondsLeft = 0;
  String? _validationError;
  String? _statusMessage;
  String? _successEmail;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _validationError = null;
      _statusMessage = null;
      _isSubmitting = true;
    });

    final result =
        await (widget.requestPasswordResetOverride?.call(_controller.text) ??
            widget.authService!.requestPasswordReset(_controller.text));
    if (!mounted) return;

    if (result.isSuccess) {
      _startCooldown();
      setState(() {
        _isSubmitting = false;
        _successEmail = _maskEmail(result.normalizedEmail);
        _statusMessage = 'Password reset email sent';
      });
      return;
    }

    setState(() {
      _isSubmitting = false;
      _successEmail = null;
      _statusMessage = result.message;
      if (result.status == PasswordResetRequestStatus.invalidEmail) {
        _validationError = result.message;
      }
    });
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

  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final local = parts.first;
    final domain = parts.last;
    if (local.isEmpty) return email;
    if (local.length == 1) return '${local[0]}***@$domain';
    return '${local[0]}${'*' * (local.length - 2)}${local[local.length - 1]}@$domain';
  }

  bool get _showSuccessState => _successEmail != null;

  Widget _buildStatusBanner({
    required String message,
    required Color borderColor,
    required Color backgroundColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor.withValues(alpha: 0.2)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFF4A4A4A), height: 1.45),
      ),
    );
  }

  Widget _buildEmailField() {
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.done,
      onChanged: (_) {
        if (_validationError != null || _statusMessage != null) {
          setState(() {
            _validationError = null;
            if (!_showSuccessState) {
              _statusMessage = null;
            }
          });
        }
      },
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        hintText: 'Email address',
        errorText: _validationError,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDADADA)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDADADA)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final buttonLabel = _isSubmitting
        ? (_showSuccessState ? 'Sending...' : 'Checking...')
        : _secondsLeft > 0
        ? 'Resend in ${_secondsLeft.toString().padLeft(2, '0')}s'
        : (_showSuccessState ? 'Resend email' : 'Send Reset Link');

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + viewInsets.bottom),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.58),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.78),
                          const Color(0xFFFFF8F2).withValues(alpha: 0.66),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          blurRadius: 32,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Expanded(
                              child: Text(
                                'Reset Password',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            InkWell(
                              onTap: () => Navigator.of(context).pop(),
                              borderRadius: BorderRadius.circular(10),
                              child: Ink(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.75),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 20,
                                  color: Color(0xFF5B5550),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        if (_showSuccessState) ...[
                          Row(
                            children: const [
                              Icon(
                                Icons.mark_email_read_rounded,
                                color: AppColors.primary,
                                size: 28,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Password reset email sent',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _buildStatusBanner(
                            message:
                                'Check your inbox and follow the link to create a new password.',
                            borderColor: AppColors.primary,
                            backgroundColor: const Color(
                              0xFFFFF8EF,
                            ).withValues(alpha: 0.76),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Email: $_successEmail',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF4A4A4A),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ] else ...[
                          const Text(
                            'Enter the email linked to your Pettxo account.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF4A4A4A),
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'We will send a reset link only when password sign-in is enabled for that account.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF4A4A4A),
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 18),
                          if (_statusMessage != null) ...[
                            _buildStatusBanner(
                              message: _statusMessage!,
                              borderColor: const Color(0xFFE16A6A),
                              backgroundColor: const Color(
                                0xFFFFF5F5,
                              ).withValues(alpha: 0.8),
                            ),
                            const SizedBox(height: 18),
                          ],
                          _buildEmailField(),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: GradientButton(
                            label: buttonLabel,
                            onPressed: (_isSubmitting || _secondsLeft > 0)
                                ? null
                                : _submit,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
