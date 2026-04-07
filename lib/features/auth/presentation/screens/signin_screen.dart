import 'package:flutter/material.dart';

import '../../../../core/constants/validators.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../widgets/custom_button.dart';
import '../../data/services/auth_service.dart';
import '../widgets/auth_input_field.dart';
import '../widgets/auth_shell.dart';

class SigninScreen extends StatefulWidget {
  const SigninScreen({super.key});

  @override
  State<SigninScreen> createState() => _SigninScreenState();
}

class _SigninScreenState extends State<SigninScreen> {
  final AuthService _authService = AuthService();
  final AnalyticsService _analytics = AnalyticsService.instance;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final emailFocus = FocusNode();
  final passwordFocus = FocusNode();

  String? emailError;
  String? passwordError;

  bool isLoading = false;
  bool obscurePassword = true;

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
      Navigator.pushReplacementNamed(context, "/home");
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
              onPressed: () {
                AppFeedback.show(
                  context,
                  message: "Forgot password will be added next.",
                  tone: AppFeedbackTone.info,
                );
              },
              child: const Text("Forgot password?"),
            ),
          ),
          const SizedBox(height: 12),
          CustomButton(
            text: isLoading ? "Signing in..." : "Sign In",
            onPressed: isLoading ? null : handleSignin,
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
