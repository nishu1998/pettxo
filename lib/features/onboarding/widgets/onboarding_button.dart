import 'package:flutter/material.dart';
import '../../../../core/widgets/app_buttons.dart';

class OnboardingButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const OnboardingButton({super.key, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GradientButton(label: text, onPressed: onTap);
  }
}
