import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../core/constants/app_colors.dart';
import '../models/onboarding_model.dart';

class OnboardingPage extends StatelessWidget {
  final OnboardingModel data;

  const OnboardingPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: 30,
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.secondary.withValues(alpha: 0.22),
                          AppColors.secondary.withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.84),
                    borderRadius: BorderRadius.circular(34),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.07),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 26,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Lottie.asset(
                    data.lottie,
                    height: 250,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4EE),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: ShaderMask(
                    shaderCallback: (bounds) =>
                        AppColors.brandGradient.createShader(bounds),
                    child: const Text(
                      'Premium pet experience',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  data.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1.12,
                    letterSpacing: -0.8,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  data.subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.6),
                ),
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
