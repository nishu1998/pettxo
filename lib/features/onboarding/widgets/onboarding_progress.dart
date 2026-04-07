import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class OnboardingProgress extends StatelessWidget {
  final int index;

  const OnboardingProgress({super.key, required this.index});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 400),
        tween: Tween(begin: 0, end: (index + 1) / 3),
        builder: (context, value, _) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation(AppColors.primary),
            ),
          );
        },
      ),
    );
  }
}