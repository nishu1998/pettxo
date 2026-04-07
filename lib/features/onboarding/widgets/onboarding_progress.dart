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
          return Container(
            height: 8,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: ColoredBox(color: Colors.grey.shade200),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: value,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
