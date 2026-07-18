import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/constants/app_colors.dart';

class AuthShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final String eyebrow;

  const AuthShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.eyebrow = 'PETTXO',
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 380;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            tween: Tween(begin: 0, end: 1),
            builder: (context, value, _) {
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 20 : 24,
                  vertical: compact ? 14 : 18,
                ),
                child: Column(
                  children: [
                    Transform.translate(
                      offset: Offset(0, 22 * (1 - value)),
                      child: Opacity(
                        opacity: value,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            0,
                            compact ? 4 : 6,
                            0,
                            compact ? 8 : 10,
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: compact ? 58 : 64,
                                    height: compact ? 58 : 64,
                                    child: Transform.scale(
                                      scale: compact ? 1.24 : 1.28,
                                      child: SvgPicture.asset(
                                        'assets/brand/pettxo_logo.svg',
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: compact ? 8 : 10),
                                  Text(
                                    eyebrow,
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontSize: compact ? 22 : 24,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: compact ? 8 : 10),
                              Text(
                                title,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: compact ? 27 : 29,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  height: 1.08,
                                ),
                              ),
                              SizedBox(height: compact ? 8 : 10),
                              Text(
                                subtitle,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF4A4A4A),
                                  fontSize: compact ? 13.5 : 14,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(0, 34 * (1 - value)),
                      child: Opacity(
                        opacity: Curves.easeOut.transform(value),
                        child: Padding(
                          padding: EdgeInsets.only(top: compact ? 2 : 4),
                          child: child,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
