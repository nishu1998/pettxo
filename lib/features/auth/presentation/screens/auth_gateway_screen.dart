import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/remote_config_service.dart';
import '../../../home/presentation/screens/home_screen.dart';
import '../../../onboarding/data/services/onboarding_state_service.dart';
import '../../../onboarding/screens/onboarding_screen.dart';
import '../../data/services/auth_onboarding_service.dart';
import '../../domain/utils/auth_onboarding_resolver.dart';
import 'account_recovery_screen.dart';
import 'email_verification_screen.dart';
import 'link_phone_screen.dart';
import 'profile_type_screen.dart';
import 'signin_screen.dart';

class AuthGatewayScreen extends StatefulWidget {
  final bool allowOnboardingWhenSignedOut;
  final bool reloadUserBeforeResolve;

  const AuthGatewayScreen({
    super.key,
    this.allowOnboardingWhenSignedOut = false,
    this.reloadUserBeforeResolve = false,
  });

  @override
  State<AuthGatewayScreen> createState() => _AuthGatewayScreenState();
}

class _AuthGatewayScreenState extends State<AuthGatewayScreen> {
  final AuthOnboardingService _onboardingService = AuthOnboardingService();
  final OnboardingStateService _onboardingStateService =
      OnboardingStateService();
  final RemoteConfigService _remoteConfigService = RemoteConfigService();
  final AnalyticsService _analytics = AnalyticsService.instance;
  bool _isResolving = true;
  String? _resolverError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveAndNavigate();
    });
  }

  Future<void> _resolveAndNavigate() async {
    if (mounted) {
      setState(() {
        _isResolving = true;
        _resolverError = null;
      });
    }
    try {
      final resolution = await _onboardingService.resolveCurrentState(
        reloadUser: widget.reloadUserBeforeResolve,
      );
      if (!mounted) return;

      switch (resolution.state) {
        case AuthOnboardingState.signedOut:
          await _navigateSignedOut();
          return;
        case AuthOnboardingState.accountRecoveryRequired:
          _replaceWith(
            AccountRecoveryScreen(
              accountStatus:
                  resolution.profile?.accountStatus ?? 'pendingDeletion',
              scheduledDeletionAt: resolution.profile?.scheduledDeletionAt,
            ),
          );
          return;
        case AuthOnboardingState.emailVerificationRequired:
          _replaceWith(const EmailVerificationScreen());
          return;
        case AuthOnboardingState.phoneLinkRequired:
          _replaceWith(const LinkPhoneScreen());
          return;
        case AuthOnboardingState.profileCompletionRequired:
          _replaceWith(const ProfileTypeScreen());
          return;
        case AuthOnboardingState.authenticated:
          _replaceWith(const HomeScreen());
          return;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isResolving = false;
        _resolverError =
            'We could not verify your authentication state right now.';
      });
    }
  }

  Future<void> _navigateSignedOut() async {
    if (!widget.allowOnboardingWhenSignedOut) {
      _replaceWith(const SigninScreen());
      return;
    }

    try {
      await _remoteConfigService.init();
      await _analytics.setOnboardingExperiment(
        experimentId: _remoteConfigService.onboardingExperimentId,
        variantId: _remoteConfigService.onboardingVariantId,
      );
    } catch (_) {
      // Best effort only.
    }

    final shouldShowOnboarding = await _onboardingStateService
        .shouldShowOnboarding(
          currentVersion: _remoteConfigService.onboardingDisplayVersion,
          forceShow: _remoteConfigService.onboardingForceShow,
        )
        .catchError((_) => false);
    if (!mounted) return;

    _replaceWith(
      shouldShowOnboarding ? const OnboardingScreen() : const SigninScreen(),
    );
  }

  void _replaceWith(Widget screen) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => screen),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: _isResolving
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      color: AppColors.textGrey,
                      size: 38,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _resolverError ??
                          'We could not verify your authentication state right now.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _resolveAndNavigate,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
