import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/analytics_service.dart';
import '../../models/profile_type.dart';
import '../../widgets/profile_type_card.dart';
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
    return Scaffold(
      backgroundColor: AppColors.background,

      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),

          child: Container(
            padding: const EdgeInsets.all(28),

            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(20),
            ),

            child: Column(
              children: [
                const Text(
                  "Choose Your Profile Type",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 10),

                Text(
                  "How do you want to use Pettexo?",
                  style: TextStyle(color: AppColors.textGrey),
                ),

                const SizedBox(height: 30),

                ProfileTypeCard(
                  icon: Icons.pets,
                  title: "Pet Parent",
                  description: "Share your pet's journey and discover services",
                  onTap: () => navigate(context, ProfileType.petParent),
                ),

                const SizedBox(height: 16),

                ProfileTypeCard(
                  icon: Icons.work,
                  title: "Service Provider",
                  description: "Offer pet services and grow your business",
                  onTap: () => navigate(context, ProfileType.serviceProvider),
                ),

                const SizedBox(height: 16),

                ProfileTypeCard(
                  icon: Icons.favorite_border,
                  title: "Pet Lover",
                  description: "Enjoy and engage with pet content",
                  onTap: () => navigate(context, ProfileType.petLover),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
