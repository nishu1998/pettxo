import 'package:flutter/material.dart';
import 'dart:async';

import '../../core/services/remote_config_service.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';


class CinematicSplash extends StatefulWidget {
  const CinematicSplash({super.key});

  @override
  State<CinematicSplash> createState() => _CinematicSplashState();
}

class _CinematicSplashState extends State<CinematicSplash>
    with TickerProviderStateMixin {

  late AnimationController _controller;
  late Animation<double> logoScale;
  late Animation<double> textOpacity;
  late Animation<Offset> textSlide;

  final RemoteConfigService remote = RemoteConfigService(); // ✅ Added

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    logoScale = Tween(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    textOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 1.0)),
    );

    textSlide = Tween(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _start();
  }

  Future<void> _start() async {
    await _controller.forward();

    // 🔥 Initialize Remote Config during splash
    await remote.init();

    await Future.delayed(const Duration(milliseconds: 400));

    _goNext();
  }

  void _goNext() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => OnboardingScreen(),
      ),
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

    final logoSize = size.width * 0.7;

    return Scaffold(
      backgroundColor: Colors.white,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            children: [

              /// 🌄 Background
              Opacity(
                opacity: _controller.value * 0.8,
                child: Image.asset(
                  'assets/splash_bg.png',
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),

              /// 🔥 LOGO (center)
              Center(
                child: Transform.scale(
                  scale: logoScale.value,
                  child: Image.asset(
                    'assets/logo1024.png',
                    width: logoSize,
                  ),
                ),
              ),

              /// 🔥 TEXT
              Positioned(
                top: size.height * 0.65,
                left: 0,
                right: 0,
                child: Opacity(
                  opacity: textOpacity.value,
                  child: SlideTransition(
                    position: textSlide,
                    child: Center(
                      child: Text(
                        "PETTXO",
                        style: TextStyle(
                          fontSize: size.width * 0.07,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                          color: const Color(0xFFF75927),
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