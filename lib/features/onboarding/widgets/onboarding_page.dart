import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../core/constants/app_colors.dart';
import '../models/onboarding_model.dart';

class OnboardingPage extends StatelessWidget {
  final OnboardingModel data;

  const OnboardingPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          /// 🔥 Lottie (slight premium sizing)
          Lottie.asset(data.lottie, height: 260, fit: BoxFit.contain),

          const SizedBox(height: 50),

          /// 🔥 Title (strong hierarchy)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              data.title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1.15,
                letterSpacing: -0.6,
                color: AppColors.textDark,
              ),
            ),
          ),

          const SizedBox(height: 18),

          /// 🔥 Subtitle (lighter tone)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              data.subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
