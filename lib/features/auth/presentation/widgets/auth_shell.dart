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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: -70,
              left: -40,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.08),
                ),
              ),
            ),
            Positioned(
              top: 90,
              right: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.06),
                ),
              ),
            ),
            Center(
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                tween: Tween(begin: 0, end: 1),
                builder: (context, value, _) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    child: Column(
                      children: [
                        Transform.translate(
                          offset: Offset(0, 22 * (1 - value)),
                          child: Opacity(
                            opacity: value,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                26,
                                24,
                                24,
                              ),
                              decoration: BoxDecoration(
                                gradient: AppColors.brandGradientDiagonal,
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.18,
                                    ),
                                    blurRadius: 30,
                                    offset: const Offset(0, 14),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.16,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.14,
                                            ),
                                          ),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: Transform.scale(
                                          scale: 1.18,
                                          child: SvgPicture.asset(
                                            'assets/brand/pettxo_logo.svg',
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        eyebrow,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    title,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 29,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                      height: 1.08,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    subtitle,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.86,
                                      ),
                                      fontSize: 14,
                                      height: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Container(
                                    width: 72,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.28,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Transform.translate(
                          offset: Offset(0, 34 * (1 - value)),
                          child: Opacity(
                            opacity: Curves.easeOut.transform(value),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(28),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.08,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 25,
                                    spreadRadius: 1,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
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
          ],
        ),
      ),
    );
  }
}
