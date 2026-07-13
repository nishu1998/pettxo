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

enum _SplashDestination { home, profileType, onboarding, signin }

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

  static const Duration _startupTimeout = Duration(seconds: 4);

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
    final destination = await _resolveStartupDestination().timeout(
      _startupTimeout,
      onTimeout: () {
        debugPrint('Splash startup debug -> timeout fallback activated');
        return FirebaseAuth.instance.currentUser != null
            ? _SplashDestination.home
            : _SplashDestination.signin;
      },
    );
    if (!mounted) return;
    _navigateTo(destination);
  }

  Future<_SplashDestination> _resolveStartupDestination() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      final hasProfile = await userService.hasUserProfileCacheFirst().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          debugPrint(
            'Splash startup debug -> user profile lookup timed out, using cached auth session for uid=${currentUser.uid}',
          );
          return null;
        },
      );
      debugPrint(
        'Splash startup debug -> authenticated launch resolved from ${hasProfile == null ? 'fallback' : 'cache/server'} for uid=${currentUser.uid}',
      );
      if (hasProfile == false) {
        return _SplashDestination.profileType;
      }
      return _SplashDestination.home;
    }

    unawaited(_warmRemoteConfigAndAnalytics());

    final shouldShowOnboarding = await onboardingState
        .shouldShowOnboarding(
          currentVersion: remote.onboardingDisplayVersion,
          forceShow: remote.onboardingForceShow,
        )
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            debugPrint('Splash startup debug -> onboarding state timed out');
            return false;
          },
        );
    debugPrint(
      'Splash startup debug -> unauthenticated launch resolved from local state, showOnboarding=$shouldShowOnboarding',
    );
    return shouldShowOnboarding
        ? _SplashDestination.onboarding
        : _SplashDestination.signin;
  }

  Future<void> _warmRemoteConfigAndAnalytics() async {
    try {
      await remote.init().timeout(const Duration(seconds: 2));
      debugPrint('Splash startup debug -> remote config warmup completed');
    } catch (error) {
      debugPrint(
        'Splash startup debug -> remote config warmup skipped: $error',
      );
    }

    try {
      await analytics.setOnboardingExperiment(
        experimentId: remote.onboardingExperimentId,
        variantId: remote.onboardingVariantId,
      );
    } catch (error) {
      debugPrint('Splash startup debug -> analytics warmup skipped: $error');
    }
  }

  void _navigateTo(_SplashDestination destination) {
    switch (destination) {
      case _SplashDestination.home:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
        return;
      case _SplashDestination.profileType:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ProfileTypeScreen()),
        );
        return;
      case _SplashDestination.onboarding:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        );
        return;
      case _SplashDestination.signin:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const SigninScreen()),
        );
        return;
    }
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
