import 'package:flutter/material.dart';

import '../../../../core/services/analytics_service.dart';
import '../../data/services/auth_onboarding_service.dart';
import '../../domain/models/profile_type.dart';
import '../../domain/utils/auth_onboarding_resolver.dart';
import '../widgets/auth_shell.dart';
import '../widgets/profile_type_card.dart';
import 'onboarding_consent_screen.dart';
import 'profile_details_screen.dart';

class ProfileTypeScreen extends StatefulWidget {
  const ProfileTypeScreen({super.key, this.onboardingService});

  final AuthOnboardingService? onboardingService;

  @override
  State<ProfileTypeScreen> createState() => _ProfileTypeScreenState();
}

class _ProfileTypeScreenState extends State<ProfileTypeScreen> {
  late final AuthOnboardingService _onboardingService =
      widget.onboardingService ?? AuthOnboardingService();
  bool _checkingAccess = true;

  Future<void> navigate(BuildContext context, ProfileType type) async {
    final resolution = await _onboardingService.resolveCurrentState();
    if (!context.mounted) return;
    if (resolution.state != AuthOnboardingState.roleSelectionRequired &&
        resolution.state != AuthOnboardingState.signedOut) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil('/auth-gate', (route) => false);
      return;
    }
    AnalyticsService.instance.logProfileTypeSelected(profileType: type.name);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfileDetailsScreen(type: type)),
    );
  }

  @override
  void initState() {
    super.initState();
    _guardScreenAccess();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AnalyticsService.instance.logProfileTypeView();
    });
  }

  Future<void> _guardScreenAccess() async {
    try {
      final resolution = await _onboardingService.resolveCurrentState();
      if (!mounted) return;
      switch (resolution.state) {
        case AuthOnboardingState.authenticated:
        case AuthOnboardingState.accountRecoveryRequired:
        case AuthOnboardingState.emailVerificationRequired:
        case AuthOnboardingState.phoneLinkRequired:
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/auth-gate', (route) => false);
          return;
        case AuthOnboardingState.onboardingConsentRequired:
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => OnboardingConsentScreen(
                existingRole: resolution.profile?.role,
              ),
            ),
          );
          return;
        case AuthOnboardingState.profileDetailsRequired:
          final role = (resolution.profile?.role ?? '').trim();
          if (role.isNotEmpty) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => ProfileDetailsScreen(
                  type: profileTypeFromStoredValue(role),
                ),
              ),
            );
            return;
          }
          break;
        case AuthOnboardingState.roleSelectionRequired:
        case AuthOnboardingState.signedOut:
          break;
      }
    } finally {
      if (mounted) {
        setState(() {
          _checkingAccess = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAccess) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
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
