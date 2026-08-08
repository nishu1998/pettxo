import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../auth/presentation/screens/auth_gateway_screen.dart';

class CinematicSplash extends StatefulWidget {
  const CinematicSplash({super.key});

  @override
  State<CinematicSplash> createState() => _CinematicSplashState();
}

class _CinematicSplashState extends State<CinematicSplash> {
  static const double _nativeLaunchLogoLogicalSize = 256;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await Future.delayed(const Duration(milliseconds: 1650));

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const AuthGatewayScreen(allowOnboardingWhenSignedOut: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final logoSize = math.max(
      0.0,
      math.min(width - 48, _nativeLaunchLogoLogicalSize),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SizedBox.square(
          dimension: logoSize,
          child: Image.asset('assets/logo1024.png', fit: BoxFit.contain),
        ),
      ),
    );
  }
}
