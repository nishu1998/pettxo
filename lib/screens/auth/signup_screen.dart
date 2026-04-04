import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/validators.dart';
import '../../services/auth_service.dart';
import '../../widgets/custom_button.dart';
import '../auth/profile_type_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {

  final AuthService _authService = AuthService();

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final emailFocus = FocusNode();
  final passwordFocus = FocusNode();

  String? emailError;
  String? passwordError;

  bool isLoading = false;
  bool obscurePassword = true;

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

    final result = await _authService.signUp(
      email: email,
      password: password,
    );

    setState(() => isLoading = false);

    if (result.isSuccess) {

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Account created successfully")),
      );
      Navigator.pushReplacement(
      context,
      MaterialPageRoute(
      builder: (_) => ProfileTypeScreen(),
       ),
      );

    } else {

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? "Signup failed")),
      );

    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: AppColors.background,

      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),

          child: Container(
            padding: const EdgeInsets.all(28),

            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.05),
                  blurRadius: 25,
                  spreadRadius: 1,
                  offset: const Offset(0,10),
                )
              ],
            ),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [

                /// LOGO
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.pets, color: AppColors.secondary),
                    const SizedBox(width: 8),
                    Text(
                      "Pettxo",
                      style: TextStyle(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                const Text(
                  "Create Account",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),

                const SizedBox(height: 30),

                /// EMAIL FIELD
                TextField(
                  controller: emailController,
                  focusNode: emailFocus,
                  textInputAction: TextInputAction.next,

                  onChanged: (value) {
                    setState(() {
                      emailError = Validators.validateEmail(value);
                    });
                  },

                  onSubmitted: (_) {
                    FocusScope.of(context).requestFocus(passwordFocus);
                  },

                  decoration: InputDecoration(
                    labelText: "Email",
                    errorText: emailError,
                    filled: true,
                    fillColor: Colors.grey.shade100,

                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                /// PASSWORD FIELD
                TextField(
                  controller: passwordController,
                  focusNode: passwordFocus,
                  obscureText: obscurePassword,
                  textInputAction: TextInputAction.done,

                  onChanged: (value) {
                    setState(() {
                      passwordError = Validators.validatePassword(value);
                    });
                  },

                  onSubmitted: (_) {
                    handleSignup();
                  },

                  decoration: InputDecoration(
                    labelText: "Password",
                    errorText: passwordError,
                    filled: true,
                    fillColor: Colors.grey.shade100,

                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),

                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          obscurePassword = !obscurePassword;
                        });
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 25),

                /// SIGNUP BUTTON
                CustomButton(
                  text: isLoading
                      ? "Creating account..."
                      : "Sign Up with Email",
                  onPressed: isLoading ? () {} : handleSignup,
                ),

                const SizedBox(height: 20),

                Text(
                  "Use Phone instead",
                  style: TextStyle(
                    color: AppColors.textGrey,
                  ),
                ),

                const SizedBox(height: 20),

                const Divider(),

                const SizedBox(height: 10),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Already have an account?",
                      style: TextStyle(color: AppColors.textGrey),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "Login",
                      style: TextStyle(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}