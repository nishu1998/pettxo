import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../models/onboarding_model.dart';

class OnboardingPage extends StatelessWidget {
  final OnboardingModel data;

  const OnboardingPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [

        /// 🔥 Lottie Animation
        Lottie.asset(
          data.lottie,
          height: 250,
        ),

        const SizedBox(height: 40),

        /// 🔥 Title
        Text(
          data.title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),

        const SizedBox(height: 16),

        /// 🔥 Subtitle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            data.subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}