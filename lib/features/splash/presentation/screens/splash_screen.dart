import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/remote_config_service.dart';
import '../../../auth/data/services/user_service.dart';
import '../../../auth/presentation/screens/profile_type_screen.dart';
import '../../../auth/presentation/screens/signin_screen.dart';
import '../../../home/presentation/screens/home_screen.dart';
import '../../../onboarding/data/services/onboarding_state_service.dart';
import '../../../onboarding/screens/onboarding_screen.dart';

class CinematicSplash extends StatefulWidget {
  const CinematicSplash({super.key});

  @override
  State<CinematicSplash> createState() => _CinematicSplashState();
}

class _CinematicSplashState extends State<CinematicSplash>
    with TickerProviderStateMixin {
  final AnalyticsService analytics = AnalyticsService.instance;
  final RemoteConfigService remote = RemoteConfigService();
  final OnboardingStateService onboardingState = OnboardingStateService();
  final UserService userService = UserService();

  late AnimationController _controller;
  late Animation<double> logoScale;
  late Animation<double> logoOpacity;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    logoScale = Tween(
      begin: 0.96,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    logoOpacity = Tween(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _start();
  }

  Future<void> _start() async {
    await _controller.forward();
    await Future.delayed(const Duration(milliseconds: 250));

    if (!mounted) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      final hasProfile = await userService.hasUserProfile();
      if (!mounted) return;
      if (hasProfile) {
        _goToHome();
      } else {
        _goToProfileType();
      }
      return;
    }

    await remote.init();
    await analytics.setOnboardingExperiment(
      experimentId: remote.onboardingExperimentId,
      variantId: remote.onboardingVariantId,
    );

    final shouldShowOnboarding = await onboardingState.shouldShowOnboarding(
      currentVersion: remote.onboardingDisplayVersion,
      forceShow: remote.onboardingForceShow,
    );

    if (!mounted) return;
    _goNext(shouldShowOnboarding: shouldShowOnboarding);
  }

  void _goNext({required bool shouldShowOnboarding}) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => shouldShowOnboarding
            ? const OnboardingScreen()
            : const SigninScreen(),
      ),
    );
  }

  void _goToHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _goToProfileType() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ProfileTypeScreen()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final logoSize = math.min(size.width * 0.36, 144.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Center(
            child: Opacity(
              opacity: logoOpacity.value,
              child: Transform.scale(
                scale: logoScale.value,
                child: Image.asset(
                  'assets/logo1024.png',
                  width: logoSize,
                  height: logoSize,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
