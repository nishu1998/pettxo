import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/validators.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/legal_acceptance_session_service.dart';
import '../../../../core/services/policy_link_service.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../data/services/auth_service.dart';
import 'email_verification_screen.dart';
import 'signin_screen.dart';
import 'signup_with_phone_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final AuthService _authService = AuthService();
  final AnalyticsService _analytics = AnalyticsService.instance;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final emailFocus = FocusNode();
  final passwordFocus = FocusNode();

  String? emailError;
  String? passwordError;
  String? _consentError;

  bool isLoading = false;
  bool obscurePassword = true;
  bool _acceptedConsent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _analytics.logSignUpViewed();
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

  Future<void> handleSignup() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    setState(() {
      emailError = Validators.validateEmail(email);
      passwordError = Validators.validatePassword(password);
      _consentError = _acceptedConsent
          ? null
          : 'You must agree before creating your account.';
    });

    if (emailError != null || passwordError != null || !_acceptedConsent) {
      return;
    }

    setState(() => isLoading = true);
    await _analytics.logSignUpAttempt(method: 'email');

    final result = await _authService.signUp(email: email, password: password);

    if (!mounted) return;
    setState(() => isLoading = false);

    if (result.isSuccess) {
      LegalAcceptanceSessionService.instance.markSignupConsentAccepted();
      await _analytics.logSignUpResult(method: 'email', isSuccess: true);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const EmailVerificationScreen()),
      );
    } else {
      await _analytics.logSignUpResult(
        method: 'email',
        isSuccess: false,
        errorCode: result.error,
      );
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: result.error ?? "Signup failed",
        tone: AppFeedbackTone.error,
      );
    }
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
                      SizedBox(height: compact ? 8 : 14),
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
                        'Create your account',
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
                          'Pet parents, pet lovers and service providers\none trusted space.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF958E88),
                            fontSize: compact ? 15 : 16,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 28 : 32),
                      _SignupField(
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
                      _SignupField(
                        controller: passwordController,
                        focusNode: passwordFocus,
                        textInputAction: TextInputAction.done,
                        hintText: 'Password',
                        errorText: passwordError,
                        obscureText: obscurePassword,
                        onChanged: (value) {
                          setState(() {
                            passwordError = Validators.validatePassword(value);
                          });
                        },
                        onSubmitted: (_) => handleSignup(),
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
                      SizedBox(height: compact ? 18 : 20),
                      _SignupConsentRow(
                        value: _acceptedConsent,
                        errorText: _consentError,
                        onChanged: (value) {
                          setState(() {
                            _acceptedConsent = value ?? false;
                            if (_acceptedConsent) {
                              _consentError = null;
                            }
                          });
                        },
                      ),
                      SizedBox(height: compact ? 16 : 18),
                      _SignupPrimaryButton(
                        label: isLoading
                            ? 'Creating account...'
                            : 'Create account',
                        isLoading: isLoading,
                        onPressed: isLoading ? null : handleSignup,
                        compact: compact,
                      ),
                      SizedBox(height: compact ? 10 : 12),
                      _SignupSecondaryButton(
                        label: 'Continue with phone',
                        compact: compact,
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SignUpWithPhoneScreen(),
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
                              'Already have an account? ',
                              style: TextStyle(
                                color: Color(0xFF958E88),
                                fontSize: compact ? 15 : 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const SigninScreen(),
                                  ),
                                );
                              },
                              child: Text(
                                'Log in',
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

class _SignupField extends StatefulWidget {
  const _SignupField({
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
  State<_SignupField> createState() => _SignupFieldState();
}

class _SignupFieldState extends State<_SignupField> {
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

class _SignupConsentRow extends StatelessWidget {
  const _SignupConsentRow({
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  final bool value;
  final ValueChanged<bool?> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final baseStyle = const TextStyle(
      color: AppColors.textDark,
      fontSize: 15,
      height: 1.35,
      fontWeight: FontWeight.w500,
    );
    final linkStyle = baseStyle.copyWith(
      color: AppColors.primary,
      fontWeight: FontWeight.w800,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 26,
                height: 26,
                child: Checkbox(
                  value: value,
                  onChanged: onChanged,
                  activeColor: AppColors.primary,
                  side: const BorderSide(color: Color(0xFFE2DDD7), width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: RichText(
                  text: TextSpan(
                    style: baseStyle,
                    children: [
                      const TextSpan(text: 'I agree to the '),
                      TextSpan(
                        text: 'Terms of Service',
                        style: linkStyle,
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            PolicyLinkService.openExternalPolicyUrlWithFeedback(
                              context,
                              PolicyLinkService.termsConditionsKey,
                            );
                          },
                      ),
                      const TextSpan(text: ', '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: linkStyle,
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            PolicyLinkService.openExternalPolicyUrlWithFeedback(
                              context,
                              PolicyLinkService.privacyPolicyKey,
                            );
                          },
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(text: 'Community Guidelines.', style: linkStyle),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              errorText!,
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

class _SignupPrimaryButton extends StatelessWidget {
  const _SignupPrimaryButton({
    required this.label,
    required this.onPressed,
    required this.isLoading,
    required this.compact,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool compact;

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
                      width: 26,
                      height: 26,
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

class _SignupSecondaryButton extends StatelessWidget {
  const _SignupSecondaryButton({
    required this.label,
    required this.onPressed,
    required this.compact,
  });

  final String label;
  final VoidCallback onPressed;
  final bool compact;

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
