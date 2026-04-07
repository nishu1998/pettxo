import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/analytics_service.dart';
import '../../domain/models/profile_type.dart';
import '../widgets/auth_shell.dart';
import '../widgets/profile_type_card.dart';
import 'profile_details_screen.dart';

class ProfileTypeScreen extends StatefulWidget {
  const ProfileTypeScreen({super.key});

  @override
  State<ProfileTypeScreen> createState() => _ProfileTypeScreenState();
}

class _ProfileTypeScreenState extends State<ProfileTypeScreen> {
  void navigate(BuildContext context, ProfileType type) {
    AnalyticsService.instance.logProfileTypeSelected(profileType: type.name);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfileDetailsScreen(type: type)),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AnalyticsService.instance.logProfileTypeView();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: "Choose Your Path",
      subtitle:
          "Set up Pettexo around the way you’ll use it, so your feed, bookings, and tools feel personal from day one.",
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4EE),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    "This helps us personalize your experience right away.",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ProfileTypeCard(
            icon: Icons.pets_rounded,
            badge: "For pet owners",
            title: "Pet Parent",
            description:
                "Share your pet's journey, book trusted services, and manage daily care in one place.",
            onTap: () => navigate(context, ProfileType.petParent),
          ),
          const SizedBox(height: 14),
          ProfileTypeCard(
            icon: Icons.work_outline_rounded,
            badge: "For professionals",
            title: "Service Provider",
            description:
                "Showcase services, receive bookings, and build trust with pet families nearby.",
            onTap: () => navigate(context, ProfileType.serviceProvider),
          ),
          const SizedBox(height: 14),
          ProfileTypeCard(
            icon: Icons.favorite_border_rounded,
            badge: "For community",
            title: "Pet Lover",
            description:
                "Follow inspiring pet stories, discover places, and stay connected to the community.",
            onTap: () => navigate(context, ProfileType.petLover),
          ),
        ],
      ),
    );
  }
}
