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
            icon: ProfileType.petParent.icon,
            badge: ProfileType.petParent.badge,
            title: ProfileType.petParent.label,
            description: ProfileType.petParent.description,
            onTap: () => navigate(context, ProfileType.petParent),
          ),
          const SizedBox(height: 10),
          ProfileTypeCard(
            icon: ProfileType.serviceProvider.icon,
            badge: ProfileType.serviceProvider.badge,
            title: ProfileType.serviceProvider.label,
            description: ProfileType.serviceProvider.description,
            onTap: () => navigate(context, ProfileType.serviceProvider),
          ),
          const SizedBox(height: 10),
          ProfileTypeCard(
            icon: ProfileType.petLover.icon,
            badge: ProfileType.petLover.badge,
            title: ProfileType.petLover.label,
            description: ProfileType.petLover.description,
            onTap: () => navigate(context, ProfileType.petLover),
          ),
        ],
      ),
    );
  }
}
