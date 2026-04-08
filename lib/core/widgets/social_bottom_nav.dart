import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../navigation/social_app_tab.dart';

class SocialBottomNav extends StatelessWidget {
  final SocialAppTab activeTab;

  const SocialBottomNav({super.key, required this.activeTab});

  @override
  Widget build(BuildContext context) {
    Widget navItem({
      required IconData icon,
      required String label,
      required bool isActive,
      required VoidCallback onTap,
    }) {
      final color = isActive ? AppColors.primary : AppColors.textGrey;

      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    void navigateTo(SocialAppTab tab) {
      if (tab == activeTab) return;

      final route = switch (tab) {
        SocialAppTab.home => "/home",
        SocialAppTab.explore => "/explore",
        SocialAppTab.create => "/create",
        SocialAppTab.messages => "/messages",
        SocialAppTab.profile => "/profile",
      };

      Navigator.pushReplacementNamed(context, route);
    }

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            navItem(
              icon: Icons.home_rounded,
              label: "Home",
              isActive: activeTab == SocialAppTab.home,
              onTap: () => navigateTo(SocialAppTab.home),
            ),
            navItem(
              icon: Icons.search_rounded,
              label: "Explore",
              isActive: activeTab == SocialAppTab.explore,
              onTap: () => navigateTo(SocialAppTab.explore),
            ),
            navItem(
              icon: Icons.add_box_outlined,
              label: "Create",
              isActive: activeTab == SocialAppTab.create,
              onTap: () => navigateTo(SocialAppTab.create),
            ),
            navItem(
              icon: Icons.chat_bubble_outline_rounded,
              label: "Messages",
              isActive: activeTab == SocialAppTab.messages,
              onTap: () => navigateTo(SocialAppTab.messages),
            ),
            navItem(
              icon: Icons.person_outline_rounded,
              label: "Profile",
              isActive: activeTab == SocialAppTab.profile,
              onTap: () => navigateTo(SocialAppTab.profile),
            ),
          ],
        ),
      ),
    );
  }
}
