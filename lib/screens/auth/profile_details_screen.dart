import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/analytics_service.dart';
import '../../models/profile_type.dart';
import '../../widgets/custom_button.dart';
import '../../services/user_service.dart';

class ProfileDetailsScreen extends StatefulWidget {
  final ProfileType type;

  const ProfileDetailsScreen({super.key, required this.type});

  @override
  State<ProfileDetailsScreen> createState() => _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends State<ProfileDetailsScreen> {
  final nameController = TextEditingController();
  final usernameController = TextEditingController();
  final locationController = TextEditingController();
  final UserService _userService = UserService();
  final AnalyticsService _analytics = AnalyticsService.instance;
  bool isLoading = false;

  String getTitle() {
    switch (widget.type) {
      case ProfileType.petParent:
        return "Pet Parent Information";

      case ProfileType.petLover:
        return "Pet Lover Information";

      case ProfileType.serviceProvider:
        return "Service Provider Information";
    }
  }

  String getNameLabel() {
    if (widget.type == ProfileType.serviceProvider) {
      return "Business Name";
    }

    return "Full Name";
  }

  String get profileTypeName => widget.type.name;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _analytics.logProfileDetailsView(profileType: profileTypeName);
    });
  }

  Future<void> saveProfile() async {
    FocusScope.of(context).unfocus();

    if (nameController.text.isEmpty ||
        usernameController.text.isEmpty ||
        locationController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please fill all fields")));
      return;
    }

    try {
      setState(() {
        isLoading = true;
      });

      await _userService.createUserProfile(
        role: profileTypeName,
        name: nameController.text.trim(),
        username: usernameController.text.trim(),
        location: locationController.text.trim(),
      );
      await _analytics.logProfileCompleted(profileType: profileTypeName);

      if (!mounted) return;

      Navigator.pushReplacementNamed(context, "/home");
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    usernameController.dispose();
    locationController.dispose();
    super.dispose();
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),

                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const Text("Back"),
                  ],
                ),

                const SizedBox(height: 20),

                Text(
                  getTitle(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  "Tell us about yourself",
                  style: TextStyle(color: AppColors.textGrey),
                ),

                const SizedBox(height: 30),

                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: getNameLabel(),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                  ),
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: usernameController,
                  decoration: InputDecoration(
                    labelText: "Username",
                    filled: true,
                    fillColor: Colors.grey.shade100,
                  ),
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: locationController,
                  decoration: InputDecoration(
                    labelText: "Location",
                    filled: true,
                    fillColor: Colors.grey.shade100,
                  ),
                ),

                const SizedBox(height: 30),

                CustomButton(
                  text: isLoading ? "Saving..." : "Continue",
                  onPressed: isLoading ? null : () => saveProfile(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
