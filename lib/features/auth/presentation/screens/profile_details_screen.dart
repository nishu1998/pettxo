import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/identity/username_utils.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/legal_acceptance_session_service.dart';
import '../../../../core/services/policy_link_service.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/legal_consent_checkbox.dart';
import '../../../../widgets/custom_button.dart';
import '../../data/services/user_service.dart';
import '../../domain/models/profile_type.dart';
import '../widgets/auth_input_field.dart';
import '../widgets/auth_shell.dart';
import '../widgets/searchable_selection_field.dart';

class ProfileDetailsScreen extends StatefulWidget {
  final ProfileType type;

  const ProfileDetailsScreen({super.key, required this.type});

  @override
  State<ProfileDetailsScreen> createState() => _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends State<ProfileDetailsScreen> {
  final nameController = TextEditingController();
  final usernameController = TextEditingController();
  final nameFocus = FocusNode();
  final usernameFocus = FocusNode();
  final UserService _userService = UserService();
  final AnalyticsService _analytics = AnalyticsService.instance;
  bool isLoading = false;
  bool isLocationLoading = true;
  bool _acceptedProviderAgreement = false;
  String? usernameError;
  String? stateError;
  String? cityError;
  String? _providerConsentError;
  String? _selectedState;
  String? _selectedCity;
  String _fullPhoneNumber = '';
  String _authPhoneNumber = '';
  List<String> _states = const [];
  List<String> _cities = const [];

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

  String getSubtitle() {
    switch (widget.type) {
      case ProfileType.petParent:
        return 'Set up your profile for bookings and personalized pet care.';
      case ProfileType.petLover:
        return 'Set up a simple profile so Pettxo can personalize your community experience.';
      case ProfileType.serviceProvider:
        return 'Complete your public profile so customers can discover and trust your services.';
    }
  }

  String get _verifiedPhoneCaption {
    switch (widget.type) {
      case ProfileType.petParent:
        return 'Used for bookings and recovery.';
      case ProfileType.petLover:
        return 'Linked to your account and recovery.';
      case ProfileType.serviceProvider:
        return 'Used for account access and support.';
    }
  }

  String get profileTypeName => widget.type.name;

  @override
  void initState() {
    super.initState();
    _authPhoneNumber =
        FirebaseAuth.instance.currentUser?.phoneNumber?.trim() ?? '';
    _fullPhoneNumber = _authPhoneNumber;
    _loadLocations();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _analytics.logProfileDetailsView(profileType: profileTypeName);
    });
  }

  Future<void> _loadLocations() async {
    await LocationService.instance.load();
    if (!mounted) return;
    setState(() {
      _states = LocationService.instance.getStates();
      isLocationLoading = false;
    });
  }

  Future<void> saveProfile() async {
    FocusScope.of(context).unfocus();

    final usernameResult = normalizeAndValidateUsername(
      usernameController.text,
    );
    final normalizedUsername = usernameResult.normalized;
    final usernameValidationError = usernameResult.error;
    final stateValidationError = _selectedState == null
        ? 'State is required'
        : null;
    final cityValidationError = _selectedCity == null
        ? 'City is required'
        : null;

    if (nameController.text.isEmpty ||
        _selectedState == null ||
        _selectedCity == null) {
      AppFeedback.show(
        context,
        message: "Please fill all fields",
        tone: AppFeedbackTone.info,
      );
      return;
    }

    setState(() {
      usernameError = usernameValidationError;
      stateError = stateValidationError;
      cityError = cityValidationError;
      _providerConsentError =
          widget.type == ProfileType.serviceProvider &&
              !_acceptedProviderAgreement
          ? 'You must agree to the Service Provider Agreement.'
          : null;
    });

    if (usernameValidationError != null ||
        stateValidationError != null ||
        cityValidationError != null ||
        (widget.type == ProfileType.serviceProvider &&
            !_acceptedProviderAgreement)) {
      return;
    }

    try {
      setState(() {
        isLoading = true;
      });
      final hasSignupConsent = await LegalAcceptanceSessionService.instance
          .readPendingSignupConsent();
      if (!hasSignupConsent) {
        throw Exception('Please accept the required Pettxo terms to continue.');
      }

      await _userService.createUserProfile(
        role: profileTypeName,
        name: nameController.text.trim(),
        username: normalizedUsername,
        state: _selectedState!,
        city: _selectedCity!,
        acceptedTerms: hasSignupConsent,
        acceptedPrivacy: hasSignupConsent,
        acceptedProviderAgreement:
            widget.type == ProfileType.serviceProvider &&
            _acceptedProviderAgreement,
      );
      LegalAcceptanceSessionService.instance.clearSignupConsent();
      await _analytics.logProfileCompleted(profileType: profileTypeName);

      if (!mounted) return;

      AppFeedback.show(
        context,
        message: "Account created successfully",
        tone: AppFeedbackTone.success,
      );
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/auth-gate',
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: e.toString(),
        tone: AppFeedbackTone.error,
      );
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
    nameFocus.dispose();
    usernameFocus.dispose();
    super.dispose();
  }

  String? _validateUsername(String username) {
    return validateNormalizedUsername(username);
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 380;
    final isPetParent = widget.type == ProfileType.petParent;
    final denseLayout = isPetParent || compact;
    final fieldPadding = EdgeInsets.symmetric(
      horizontal: 16,
      vertical: denseLayout ? 14 : 17,
    );

    return AuthShell(
      title: getTitle(),
      subtitle: getSubtitle(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLocationLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          AuthInputField(
            controller: nameController,
            focusNode: nameFocus,
            textInputAction: TextInputAction.next,
            labelText: getNameLabel(),
            contentPadding: fieldPadding,
            onSubmitted: (_) {
              FocusScope.of(context).requestFocus(usernameFocus);
            },
          ),
          SizedBox(height: denseLayout ? 10 : 14),
          AuthInputField(
            controller: usernameController,
            focusNode: usernameFocus,
            textInputAction: TextInputAction.next,
            labelText: "Username",
            prefixText: "@",
            helperText: "3-20 lowercase letters, numbers, dots or underscores",
            errorText: usernameError,
            maxLength: 20,
            contentPadding: fieldPadding,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._]')),
            ],
            onChanged: (value) {
              final normalized = normalizeUsername(value);
              if (normalized != value) {
                usernameController.value = TextEditingValue(
                  text: normalized,
                  selection: TextSelection.collapsed(offset: normalized.length),
                );
              }

              setState(() {
                usernameError = _validateUsername(normalized);
              });
            },
            onSubmitted: (_) {
              FocusScope.of(context).unfocus();
            },
          ),
          SizedBox(height: denseLayout ? 10 : 14),
          _VerifiedPhoneCard(
            phoneNumber: _fullPhoneNumber,
            caption: _verifiedPhoneCaption,
            compact: denseLayout,
          ),
          SizedBox(height: denseLayout ? 10 : 14),
          SearchableSelectionField(
            labelText: 'State',
            hintText: 'Select your state',
            options: _states,
            value: _selectedState,
            errorText: stateError,
            compactLabel: denseLayout,
            contentPadding: fieldPadding,
            enabled: !isLocationLoading,
            onSelected: (value) {
              setState(() {
                _selectedState = value;
                _selectedCity = null;
                _cities = LocationService.instance.getCities(value);
                stateError = null;
                cityError = null;
              });
            },
          ),
          SizedBox(height: denseLayout ? 10 : 14),
          SearchableSelectionField(
            labelText: 'City',
            hintText: _selectedState == null
                ? 'Select state first'
                : 'Select your city',
            options: _cities,
            value: _selectedCity,
            errorText: cityError,
            compactLabel: denseLayout,
            contentPadding: fieldPadding,
            enabled: _selectedState != null && !isLocationLoading,
            onSelected: (value) {
              setState(() {
                _selectedCity = value;
                cityError = null;
              });
            },
          ),
          SizedBox(height: denseLayout ? 16 : 22),
          if (widget.type == ProfileType.serviceProvider) ...[
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(denseLayout ? 13 : 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.08),
                ),
              ),
              child: LegalConsentCheckbox(
                value: _acceptedProviderAgreement,
                onChanged: (value) {
                  setState(() {
                    _acceptedProviderAgreement = value ?? false;
                    if (_acceptedProviderAgreement) {
                      _providerConsentError = null;
                    }
                  });
                },
                errorText: _providerConsentError,
                segments: [
                  const LegalConsentSegment(text: 'I agree to the '),
                  LegalConsentSegment(
                    text: 'Service Provider Agreement',
                    onTap: () =>
                        PolicyLinkService.openExternalPolicyUrlWithFeedback(
                          context,
                          PolicyLinkService.providerPolicyKey,
                        ),
                  ),
                  const LegalConsentSegment(text: '.'),
                ],
              ),
            ),
            SizedBox(height: denseLayout ? 8 : 12),
          ],
          CustomButton(
            text: isLoading ? "Saving..." : "Continue",
            size: denseLayout ? AppButtonSize.compact : AppButtonSize.regular,
            labelFontSize: denseLayout ? 14.5 : null,
            onPressed: isLoading ? null : () => saveProfile(),
          ),
        ],
      ),
    );
  }
}

class _VerifiedPhoneCard extends StatelessWidget {
  const _VerifiedPhoneCard({
    required this.phoneNumber,
    required this.caption,
    this.compact = false,
  });

  final String phoneNumber;
  final String caption;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isCompact = compact || MediaQuery.sizeOf(context).width < 380;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isCompact ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: isCompact ? 36 : 42,
            height: isCompact ? 36 : 42,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradientDiagonal,
              borderRadius: BorderRadius.circular(isCompact ? 12 : 13),
            ),
            child: const Icon(
              Icons.verified_rounded,
              color: Colors.white,
              size: 19,
            ),
          ),
          SizedBox(width: isCompact ? 9 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Verified phone number',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontSize: isCompact ? 12.5 : 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: isCompact ? 2 : 3),
                Text(
                  _formatPhoneNumber(phoneNumber),
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: isCompact ? 15 : 16.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: isCompact ? 3 : 5),
                Text(
                  caption,
                  style: TextStyle(
                    color: AppColors.textGrey,
                    fontSize: isCompact ? 11.4 : 12.2,
                    height: 1.28,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatPhoneNumber(String phoneNumber) {
    final trimmed = phoneNumber.trim();
    if (trimmed.isEmpty) return 'Verified on your account';
    if (trimmed.startsWith('+91') && trimmed.length == 13) {
      final digits = trimmed.substring(3);
      return '+91 ${digits.substring(0, 5)} ${digits.substring(5)}';
    }
    return trimmed;
  }
}
