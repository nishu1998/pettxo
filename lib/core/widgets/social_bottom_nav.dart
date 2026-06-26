import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../navigation/social_app_tab.dart';
import 'glass_surface.dart';

class SocialBottomNav extends StatefulWidget {
  final SocialAppTab? activeTab;

  const SocialBottomNav({super.key, required this.activeTab});

  /// Keeps trailing content reachable while still allowing the body to paint
  /// behind the floating bottom bar.
  static double contentBottomPadding(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final compact = MediaQuery.sizeOf(context).width < 380;
    return (compact ? 124.0 : 132.0) + bottomInset;
  }

  @override
  State<SocialBottomNav> createState() => _SocialBottomNavState();
}

class _SocialBottomNavState extends State<SocialBottomNav>
    with SingleTickerProviderStateMixin {
  late final AnimationController _orbitController;

  @override
  void initState() {
    super.initState();
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 7600),
    )..repeat();
  }

  @override
  void dispose() {
    _orbitController.dispose();
    super.dispose();
  }

  void _navigateTo(BuildContext context, SocialAppTab tab) {
    if (tab == widget.activeTab) return;

    final route = switch (tab) {
      SocialAppTab.home => "/home",
      SocialAppTab.explore => "/explore",
      SocialAppTab.services => "/services",
      SocialAppTab.messages => "/messages",
      SocialAppTab.profile => "/profile",
    };

    Navigator.pushReplacementNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final compact = screenWidth < 380;
    final navHeight = compact ? 98.0 : 104.0;
    final navBottom = compact ? 10.0 : 12.0;
    final navHorizontalPadding = compact ? 10.0 : 14.0;
    final navVerticalPadding = compact ? 8.0 : 10.0;
    final centerGap = compact ? 72.0 : 82.0;
    final centerButtonSize = compact ? 56.0 : 62.0;
    final centerOrbitSize = centerButtonSize + (compact ? 12.0 : 14.0);
    final centerWrapperWidth = compact ? 88.0 : 96.0;
    final centerWrapperHeight = compact ? 84.0 : 92.0;
    final labelFontSize = compact ? 10.5 : 11.5;
    final centerLabelFontSize = compact ? 10.5 : 11.5;
    final iconSize = compact ? 20.0 : 21.0;
    final activeIndicatorBottomMargin = compact ? 6.0 : 8.0;
    final itemLabelSpacing = compact ? 5.0 : 6.0;
    final tau = math.pi * 2;
    final baseAngle = _orbitController.value * tau;
    final orbitAngles = [
      baseAngle + math.sin(baseAngle * 0.78) * 0.34,
      baseAngle + 1.95 + math.sin(baseAngle * 1.11 + 0.8) * 0.26,
      baseAngle + 4.02 + math.sin(baseAngle * 0.63 + 1.7) * 0.42,
    ];

    Widget navItem({
      required IconData icon,
      required String label,
      required bool isActive,
      required VoidCallback onTap,
    }) {
      final color = isActive ? AppColors.primary : const Color(0xFF9A948E);

      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: compact ? 2 : 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  width: 18,
                  height: 3,
                  margin: EdgeInsets.only(bottom: activeIndicatorBottomMargin),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Icon(icon, color: color, size: iconSize),
                SizedBox(height: itemLabelSpacing),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        color: color,
                        fontSize: labelFontSize,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: SizedBox(
        height: navHeight,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 16,
              right: 16,
              bottom: navBottom,
              child: GlassSurface(
                padding: EdgeInsets.fromLTRB(
                  navHorizontalPadding,
                  navVerticalPadding,
                  navHorizontalPadding,
                  navVerticalPadding,
                ),
                borderRadius: BorderRadius.circular(26),
                backgroundColor: Colors.white.withValues(alpha: 0.72),
                blurSigma: 20,
                border: Border.all(color: Colors.white.withValues(alpha: 0.62)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.07),
                    blurRadius: 28,
                    spreadRadius: 2,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
                child: Row(
                  children: [
                    navItem(
                      icon: Icons.home_rounded,
                      label: "Home",
                      isActive: widget.activeTab == SocialAppTab.home,
                      onTap: () => _navigateTo(context, SocialAppTab.home),
                    ),
                    navItem(
                      icon: Icons.travel_explore_rounded,
                      label: "Explore",
                      isActive: widget.activeTab == SocialAppTab.explore,
                      onTap: () => _navigateTo(context, SocialAppTab.explore),
                    ),
                    SizedBox(width: centerGap),
                    navItem(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: "Messages",
                      isActive: widget.activeTab == SocialAppTab.messages,
                      onTap: () => _navigateTo(context, SocialAppTab.messages),
                    ),
                    navItem(
                      icon: Icons.person_outline_rounded,
                      label: "Profile",
                      isActive: widget.activeTab == SocialAppTab.profile,
                      onTap: () => _navigateTo(context, SocialAppTab.profile),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: navBottom + (compact ? 4 : 6),
              child: GestureDetector(
                onTap: () => _navigateTo(context, SocialAppTab.services),
                child: AnimatedBuilder(
                  animation: _orbitController,
                  builder: (context, child) {
                    return SizedBox(
                      width: centerWrapperWidth,
                      height: centerWrapperHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.topCenter,
                        children: [
                          Positioned(
                            top: 0,
                            child: SizedBox(
                              width: centerOrbitSize,
                              height: centerOrbitSize,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  IgnorePointer(
                                    child: Transform.rotate(
                                      angle:
                                          _orbitController.value *
                                          6.28318530718,
                                      child: SizedBox(
                                        width: centerOrbitSize,
                                        height: centerOrbitSize,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Container(
                                              width: centerOrbitSize,
                                              height: centerOrbitSize,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: AppColors.primary
                                                      .withValues(alpha: 0.18),
                                                  width: 1.2,
                                                ),
                                              ),
                                            ),
                                            _OrbitDot(
                                              angle: orbitAngles[0],
                                              orbitSize: centerOrbitSize,
                                              dotSize: compact ? 8 : 9,
                                              child: Container(
                                                width: compact ? 8 : 9,
                                                height: compact ? 8 : 9,
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: AppColors.primary
                                                        .withValues(
                                                          alpha: 0.34,
                                                        ),
                                                    width: 1,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            _OrbitDot(
                                              angle: orbitAngles[1],
                                              orbitSize: centerOrbitSize,
                                              dotSize: compact ? 6 : 7,
                                              child: Container(
                                                width: compact ? 6 : 7,
                                                height: compact ? 6 : 7,
                                                decoration: BoxDecoration(
                                                  color: AppColors.secondary
                                                      .withValues(alpha: 0.9),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            ),
                                            _OrbitDot(
                                              angle: orbitAngles[2],
                                              orbitSize: centerOrbitSize,
                                              dotSize: compact ? 7 : 8,
                                              child: Container(
                                                width: compact ? 7 : 8,
                                                height: compact ? 7 : 8,
                                                decoration: BoxDecoration(
                                                  color: AppColors.primary
                                                      .withValues(alpha: 0.88),
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: Colors.white
                                                        .withValues(
                                                          alpha: 0.92,
                                                        ),
                                                    width: 0.8,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: centerButtonSize,
                                    height: centerButtonSize,
                                    decoration: BoxDecoration(
                                      gradient: AppColors.brandGradientDiagonal,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.98,
                                        ),
                                        width: 4,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.18,
                                          ),
                                          blurRadius: 18,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.auto_awesome_rounded,
                                      color: Colors.white,
                                      size: compact ? 25 : 28,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: compact ? 2 : 3,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  "Services",
                                  maxLines: 1,
                                  style: TextStyle(
                                    color:
                                        widget.activeTab ==
                                            SocialAppTab.services
                                        ? AppColors.primary
                                        : const Color(0xFF9A948E),
                                    fontSize: centerLabelFontSize,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
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
          ],
        ),
      ),
    );
  }
}

class _OrbitDot extends StatelessWidget {
  final double angle;
  final double orbitSize;
  final double dotSize;
  final Widget child;

  const _OrbitDot({
    required this.angle,
    required this.orbitSize,
    required this.dotSize,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final radius = orbitSize / 2;
    final center = radius - (dotSize / 2);
    final dx = center + math.cos(angle - (math.pi / 2)) * radius;
    final dy = center + math.sin(angle - (math.pi / 2)) * radius;

    return Positioned(left: dx, top: dy, child: child);
  }
}
