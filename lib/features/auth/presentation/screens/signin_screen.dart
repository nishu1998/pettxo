import 'package:flutter/material.dart';

import '../../../../core/constants/validators.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../widgets/custom_button.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/user_service.dart';
import '../widgets/auth_input_field.dart';
import '../widgets/auth_shell.dart';
import 'signin_with_phone_screen.dart';

class SigninScreen extends StatefulWidget {
  const SigninScreen({super.key});

  @override
  State<SigninScreen> createState() => _SigninScreenState();
}

class _SigninScreenState extends State<SigninScreen> {
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
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
    final didSend = await showDialog<bool>(
      context: context,
      builder: (_) => ForgotPasswordDialog(
        initialEmail: emailController.text.trim(),
        authService: _authService,
      ),
    );

    if (didSend == true && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppSnackbar.showSuccess(context, "Password reset email sent");
      });
    }
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

    setState(() => isLoading = true);
    await _analytics.logSignInAttempt(method: 'email');

    final result = await _authService.login(email: email, password: password);

    if (!mounted) return;
    setState(() => isLoading = false);

    if (result.isSuccess) {
      await _analytics.logSignInResult(method: 'email', isSuccess: true);
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: "Welcome back",
        tone: AppFeedbackTone.success,
      );
      final route = await _userService.getPostAuthRoute();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, route);
    } else {
      await _analytics.logSignInResult(
        method: 'email',
        isSuccess: false,
        errorCode: result.error,
      );
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: result.error ?? "Login failed",
        tone: AppFeedbackTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: "Welcome Back",
      subtitle:
          "Sign in to continue exploring pets, bookings, and your community.",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AuthInputField(
            controller: emailController,
            focusNode: emailFocus,
            textInputAction: TextInputAction.next,
            labelText: "Email",
            errorText: emailError,
            onChanged: (value) {
              setState(() {
                emailError = Validators.validateEmail(value);
              });
            },
            onSubmitted: (_) {
              FocusScope.of(context).requestFocus(passwordFocus);
            },
          ),
          const SizedBox(height: 16),
          AuthInputField(
            controller: passwordController,
            focusNode: passwordFocus,
            textInputAction: TextInputAction.done,
            labelText: "Password",
            errorText: passwordError,
            obscureText: obscurePassword,
            onChanged: (value) {
              setState(() {
                passwordError = value.isEmpty ? "Password is required" : null;
              });
            },
            onSubmitted: (_) {
              handleSignin();
            },
            suffixIcon: IconButton(
              icon: Icon(
                obscurePassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () {
                setState(() {
                  obscurePassword = !obscurePassword;
                });
              },
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _showForgotPasswordDialog,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFF75927),
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                "Forgot Password?",
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          const SizedBox(height: 12),
          CustomButton(
            text: isLoading ? "Signing in..." : "Sign In",
            onPressed: isLoading ? null : handleSignin,
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SignInWithPhoneScreen(),
                  ),
                );
              },
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              child: const Text(
                'Continue with Phone',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "New to Pettexo?",
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, "/signup");
                },
                child: const Text("Create account"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ForgotPasswordDialog extends StatefulWidget {
  final String initialEmail;
  final AuthService authService;

  const ForgotPasswordDialog({
    super.key,
    required this.initialEmail,
    required this.authService,
  });

  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  late final TextEditingController _controller;
  String? _validationError;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _controller.text.trim();

    if (email.isEmpty) {
      AppSnackbar.showWarning(context, "Enter your email first");
      return;
    }

    final error = Validators.validateEmail(email);
    setState(() {
      _validationError = error;
    });

    if (error != null) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      await widget.authService.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(
        context,
        e.toString().replaceFirst('Exception: ', ''),
      );
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + viewInsets.bottom),
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Enter your email to receive reset link',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF4A4A4A),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _controller,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) {
                        if (_validationError != null) {
                          setState(() {
                            _validationError = null;
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
                          borderSide: const BorderSide(
                            color: Color(0xFFDADADA),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFDADADA),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1.8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: GradientButton(
                        label: _isSubmitting ? 'Sending...' : 'Send Reset Link',
                        onPressed: _isSubmitting ? null : _submit,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
