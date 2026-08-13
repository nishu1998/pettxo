import 'package:flutter/foundation.dart';

import '../../domain/utils/auth_onboarding_resolver.dart';
import 'auth_onboarding_service.dart';

class PhoneLoginGuardResult {
  final bool allowAccess;
  final String? message;

  const PhoneLoginGuardResult({required this.allowAccess, this.message});
}

class PhoneLoginGuardService {
  final AuthOnboardingService _onboardingService;

  PhoneLoginGuardService({AuthOnboardingService? onboardingService})
    : _onboardingService = onboardingService ?? AuthOnboardingService();

  Future<PhoneLoginGuardResult> verifyExistingPhoneLoginAccount() async {
    final resolution = await _onboardingService.resolveCurrentState(
      reloadUser: true,
    );
    if (kDebugMode) {
      debugPrint(
        'PhoneLoginGuardService resolutionState=${resolution.state.name}',
      );
    }

    if (resolution.state == AuthOnboardingState.signedOut) {
      return const PhoneLoginGuardResult(
        allowAccess: false,
        message: 'We could not restore your Pettxo account right now.',
      );
    }

    return const PhoneLoginGuardResult(allowAccess: true);
  }
}
