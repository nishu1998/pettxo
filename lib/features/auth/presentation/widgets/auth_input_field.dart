import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

class AuthInputField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final String labelText;
  final String? errorText;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffixIcon;

  const AuthInputField({
    super.key,
    required this.controller,
    required this.labelText,
    this.focusNode,
    this.textInputAction,
    this.errorText,
    this.obscureText = false,
    this.onChanged,
    this.onSubmitted,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      textInputAction: textInputAction,
      obscureText: obscureText,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: labelText,
        errorText: errorText,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
        ),
        labelStyle: const TextStyle(
          color: AppColors.textGrey,
          fontWeight: FontWeight.w500,
        ),
        suffixIcon: suffixIcon,
      ),
    );
  }
}
