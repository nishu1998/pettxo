import 'package:flutter/material.dart';

import '../../../../core/services/legal_acceptance_session_service.dart';
import '../../../../core/services/policy_link_service.dart';
import '../../../../core/widgets/legal_consent_checkbox.dart';
import '../../../settings/presentation/screens/legal_policies_screen.dart';
import '../../../../widgets/custom_button.dart';
import '../../data/services/auth_onboarding_service.dart';
import '../../domain/models/profile_type.dart';
import '../../domain/utils/auth_onboarding_resolver.dart';
import '../widgets/auth_shell.dart';
import 'profile_details_screen.dart';
import 'profile_type_screen.dart';

class OnboardingConsentScreen extends StatefulWidget {
  const OnboardingConsentScreen({
    super.key,
    this.existingRole,
    this.onboardingService,
  });

  final String? existingRole;
  final AuthOnboardingService? onboardingService;

  @override
  State<OnboardingConsentScreen> createState() =>
      _OnboardingConsentScreenState();
}

class _OnboardingConsentScreenState extends State<OnboardingConsentScreen> {
  late final AuthOnboardingService _onboardingService =
      widget.onboardingService ?? AuthOnboardingService();
  bool _acceptedConsent = false;
  bool _isCheckingAccess = true;
  bool _isSaving = false;
  String? _consentError;

  @override
  void initState() {
    super.initState();
    _guardScreenAccess();
  }

  Future<void> _guardScreenAccess() async {
    try {
      final resolution = await _onboardingService.resolveCurrentState();
      if (!mounted) return;
      switch (resolution.state) {
        case AuthOnboardingState.onboardingConsentRequired:
          break;
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
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ProfileTypeScreen()),
          );
          return;
        case AuthOnboardingState.roleSelectionRequired:
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ProfileTypeScreen()),
          );
          return;
        case AuthOnboardingState.authenticated:
        case AuthOnboardingState.accountRecoveryRequired:
        case AuthOnboardingState.emailVerificationRequired:
        case AuthOnboardingState.phoneLinkRequired:
        case AuthOnboardingState.signedOut:
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/auth-gate', (route) => false);
          return;
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingAccess = false;
        });
      }
    }
  }

  Future<void> _continue() async {
    if (_isSaving) return;
    if (!_acceptedConsent) {
      setState(() {
        _consentError = 'You must agree before continuing.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _consentError = null;
    });

    final resolution = await _onboardingService.resolveCurrentState();
    if (!mounted) return;
    switch (resolution.state) {
      case AuthOnboardingState.authenticated:
      case AuthOnboardingState.accountRecoveryRequired:
      case AuthOnboardingState.emailVerificationRequired:
      case AuthOnboardingState.phoneLinkRequired:
      case AuthOnboardingState.signedOut:
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/auth-gate', (route) => false);
        return;
      case AuthOnboardingState.roleSelectionRequired:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ProfileTypeScreen()),
        );
        return;
      case AuthOnboardingState.profileDetailsRequired:
        final role = (resolution.profile?.role ?? '').trim();
        if (role.isNotEmpty) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) =>
                  ProfileDetailsScreen(type: profileTypeFromStoredValue(role)),
            ),
          );
          return;
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ProfileTypeScreen()),
        );
        return;
      case AuthOnboardingState.onboardingConsentRequired:
        break;
    }

    LegalAcceptanceSessionService.instance.markSignupConsentAccepted();
    if (!mounted) return;

    final normalizedRole = (widget.existingRole ?? '').trim();
    if (normalizedRole.isNotEmpty) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ProfileDetailsScreen(
            type: profileTypeFromStoredValue(normalizedRole),
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ProfileTypeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingAccess) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return AuthShell(
      title: 'Before You Continue',
      subtitle:
          'Please review and accept the Pettxo terms and privacy requirements to continue setting up your account.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF3D9C8)),
            ),
            child: LegalConsentCheckbox(
              value: _acceptedConsent,
              onChanged: (value) {
                setState(() {
                  _acceptedConsent = value ?? false;
                  if (_acceptedConsent) {
                    _consentError = null;
                  }
                });
              },
              errorText: _consentError,
              segments: [
                const LegalConsentSegment(text: 'I agree to Pettxo’s '),
                LegalConsentSegment(
                  text: 'Terms of Service',
                  onTap: () => PolicyLinkService.openPolicy(
                    context,
                    webUrl: PolicyLinkService.urlForKey(
                      PolicyLinkService.termsConditionsKey,
                    ),
                    fallbackRoute:
                        LegalPoliciesCatalog.termsAndConditions.routeName,
                  ),
                ),
                const LegalConsentSegment(text: ' and '),
                LegalConsentSegment(
                  text: 'Privacy Policy',
                  onTap: () => PolicyLinkService.openPolicy(
                    context,
                    webUrl: PolicyLinkService.urlForKey(
                      PolicyLinkService.privacyPolicyKey,
                    ),
                    fallbackRoute: LegalPoliciesCatalog.privacyPolicy.routeName,
                  ),
                ),
                const LegalConsentSegment(text: '.'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          CustomButton(
            text: _isSaving ? 'Please wait...' : 'Continue',
            onPressed: _isSaving ? null : _continue,
          ),
          const SizedBox(height: 12),
          Text(
            'This only restores the consent required to finish your incomplete signup. Completed Pettxo accounts are not asked to re-enter onboarding.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
