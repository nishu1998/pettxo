import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class OnboardingProgress extends StatelessWidget {
  final int index;

  const OnboardingProgress({super.key, required this.index});

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(
      value: (index + 1) / 3,
      color: AppColors.primary,
      backgroundColor: Colors.grey.shade300,
    );
  }
}