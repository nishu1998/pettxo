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

class SocialTabBackScope extends StatelessWidget {
  final SocialAppTab activeTab;
  final Widget child;
  final bool enabled;

  const SocialTabBackScope({
    super.key,
    required this.activeTab,
    required this.child,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled || activeTab == SocialAppTab.home) {
      return child;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !context.mounted) return;
        Navigator.pushReplacementNamed(context, '/home');
      },
      child: child,
    );
  }
}

class _SocialBottomNavState extends State<SocialBottomNav> {
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
    final centerWrapperWidth = compact ? 88.0 : 96.0;
    final centerWrapperHeight = compact ? 84.0 : 92.0;
    final labelFontSize = compact ? 10.5 : 11.5;
    final centerLabelFontSize = compact ? 10.5 : 11.5;
    final iconSize = compact ? 20.0 : 21.0;
    final activeIndicatorBottomMargin = compact ? 6.0 : 8.0;
    final itemLabelSpacing = compact ? 5.0 : 6.0;

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
                child: SizedBox(
                  width: centerWrapperWidth,
                  height: centerWrapperHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topCenter,
                    children: [
                      Positioned(
                        top: 0,
                        child: Container(
                          width: centerButtonSize,
                          height: centerButtonSize,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Transform.scale(
                              scale: 1.22,
                              child: Image.asset(
                                'assets/brand/service_nav_button.png',
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
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
                                color: widget.activeTab == SocialAppTab.services
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
