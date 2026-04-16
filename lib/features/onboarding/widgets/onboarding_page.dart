import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../core/constants/app_colors.dart';
import '../models/onboarding_model.dart';

class OnboardingPage extends StatelessWidget {
  final OnboardingModel data;

  const OnboardingPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final illustrationHeight = MediaQuery.sizeOf(context).height * 0.28;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
              child: Center(
                child: Lottie.asset(
                  data.lottie,
                  height: illustrationHeight.clamp(260.0, 320.0),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            child: Column(
              children: [
                Text(
                  data.tagLine,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  data.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    height: 1.12,
                    letterSpacing: -0.6,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  data.subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.6,
                    color: const Color(0xFF4A4A4A),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 26 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
    );
  }
}
