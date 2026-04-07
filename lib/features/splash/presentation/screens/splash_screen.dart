import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/remote_config_service.dart';
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

  late AnimationController _controller;
  late Animation<double> logoScale;
  late Animation<double> textOpacity;
  late Animation<Offset> textSlide;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    logoScale = Tween(
      begin: 1.0,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    textOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 1.0)),
    );

    textSlide = Tween(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _start();
  }

  Future<void> _start() async {
    await _controller.forward();
    await remote.init();
    await analytics.setOnboardingExperiment(
      experimentId: remote.onboardingExperimentId,
      variantId: remote.onboardingVariantId,
    );

    await Future.delayed(const Duration(milliseconds: 400));

    _goNext();
  }

  void _goNext() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
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
    final logoSize = size.width * 0.48;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            children: [
              Opacity(
                opacity: _controller.value * 0.8,
                child: Image.asset(
                  'assets/splash_bg.png',
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.background.withValues(alpha: 0.55),
                      Colors.white.withValues(alpha: 0.25),
                      AppColors.background.withValues(alpha: 0.86),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Positioned(
                top: -40,
                right: -30,
                child: Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Center(
                child: Transform.scale(
                  scale: logoScale.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: logoSize,
                        height: logoSize,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradientDiagonal,
                          borderRadius: BorderRadius.circular(40),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.18),
                              blurRadius: 35,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: SvgPicture.asset(
                          'assets/brand/pettxo_logo.svg',
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 22),
                      ShaderMask(
                        shaderCallback: (bounds) =>
                            AppColors.brandGradient.createShader(bounds),
                        child: Text(
                          'PETTXO',
                          style: TextStyle(
                            fontSize: size.width * 0.078,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: size.height * 0.73,
                left: 0,
                right: 0,
                child: Opacity(
                  opacity: textOpacity.value,
                  child: SlideTransition(
                    position: textSlide,
                    child: Center(
                      child: Text(
                        'For pet people, services, and stories',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: size.width * 0.037,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
