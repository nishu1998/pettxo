import 'package:flutter/material.dart';

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
      subtitle: "Make your experience truly yours.",
      child: Column(
        children: [
          ProfileTypeCard(
            icon: Icons.pets_rounded,
            badge: "For pet owners",
            title: "Pet Parent",
            description:
                "Manage care, book services and track your pet’s journey.",
            onTap: () => navigate(context, ProfileType.petParent),
          ),
          const SizedBox(height: 14),
          ProfileTypeCard(
            icon: Icons.work_outline_rounded,
            badge: "For professionals",
            title: "Service Provider",
            description: "List services, get bookings and grow your business.",
            onTap: () => navigate(context, ProfileType.serviceProvider),
          ),
          const SizedBox(height: 14),
          ProfileTypeCard(
            icon: Icons.favorite_border_rounded,
            badge: "For community",
            title: "Pet Lover",
            description: "Explore pet stories and connect with the community.",
            onTap: () => navigate(context, ProfileType.petLover),
          ),
        ],
      ),
    );
  }
}
