import 'package:flutter/material.dart';

import '../../../../core/constants/validators.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../widgets/custom_button.dart';
import '../../data/services/auth_service.dart';
import 'profile_type_screen.dart';
import 'signin_screen.dart';
import '../widgets/auth_input_field.dart';
import '../widgets/auth_shell.dart';

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

  bool isLoading = false;
  bool obscurePassword = true;

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
    });

    if (emailError != null || passwordError != null) return;

    setState(() => isLoading = true);
    await _analytics.logSignUpAttempt(method: 'email');

    final result = await _authService.signUp(email: email, password: password);

    if (!mounted) return;
    setState(() => isLoading = false);

    if (result.isSuccess) {
      await _analytics.logSignUpResult(method: 'email', isSuccess: true);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ProfileTypeScreen()),
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
    return AuthShell(
      title: "Create Your Account",
      subtitle:
          "Join pet parents, service providers, and animal lovers in one trusted space.",
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
                passwordError = Validators.validatePassword(value);
              });
            },
            onSubmitted: (_) {
              handleSignup();
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
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4EE),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              children: [
                Icon(Icons.smartphone_rounded, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Phone sign up is coming next.",
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          CustomButton(
            text: isLoading ? "Creating account..." : "Sign Up with Email",
            onPressed: isLoading ? () {} : handleSignup,
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Already have an account?",
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const SigninScreen()),
                  );
                },
                child: const Text(
                  "Login",
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
