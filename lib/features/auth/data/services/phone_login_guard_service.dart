import 'package:flutter/foundation.dart';

import '../../domain/utils/auth_onboarding_resolver.dart';
import 'auth_onboarding_service.dart';
import 'auth_service.dart';

class PhoneLoginGuardResult {
  final bool allowAccess;
  final String? message;

  const PhoneLoginGuardResult({required this.allowAccess, this.message});
}

class PhoneLoginGuardService {
  final AuthOnboardingService _onboardingService;
  final AuthService _authService;

  PhoneLoginGuardService({
    AuthOnboardingService? onboardingService,
    AuthService? authService,
  }) : _onboardingService = onboardingService ?? AuthOnboardingService(),
       _authService = authService ?? AuthService();

  Future<PhoneLoginGuardResult> verifyExistingPhoneLoginAccount() async {
    final resolution = await _onboardingService.resolveCurrentState(
      reloadUser: true,
    );
    if (kDebugMode) {
      debugPrint(
        'PhoneLoginGuardService resolutionState=${resolution.state.name}',
      );
    }

    if (resolution.state == AuthOnboardingState.profileCompletionRequired) {
      await _authService.logout();
      return const PhoneLoginGuardResult(
        allowAccess: false,
        message: 'Your registration is incomplete. Please complete sign up.',
      );
    }

    return const PhoneLoginGuardResult(allowAccess: true);
  }
}
