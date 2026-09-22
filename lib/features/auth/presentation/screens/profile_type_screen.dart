import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/services/analytics_service.dart';
import '../../../../core/widgets/app_feedback.dart';
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
  bool _isNavigating = false;
  String? _accessError;

  Future<void> navigate(BuildContext context, ProfileType type) async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    try {
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
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'ProfileTypeScreen selection resolution failed: '
          '${error.runtimeType}',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      if (!context.mounted) return;
      AppFeedback.show(
        context,
        message: 'We could not continue account setup. Please try again.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isNavigating = false);
      }
    }
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
    if (mounted) {
      setState(() {
        _checkingAccess = true;
        _accessError = null;
      });
    }
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
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'ProfileTypeScreen access resolution failed: ${error.runtimeType}',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      if (mounted) {
        setState(() {
          _accessError =
              'We could not verify your account setup. Please try again.';
        });
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
    if (_accessError != null) {
      return AuthShell(
        title: 'Choose Your Path',
        subtitle: 'Make your experience truly yours.',
        child: Column(
          children: [
            Text(
              _accessError!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _guardScreenAccess,
              child: const Text('Try again'),
            ),
          ],
        ),
      );
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
