import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/location_service.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/legal_acceptance_session_service.dart';
import '../../../../core/services/policy_link_service.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/legal_consent_checkbox.dart';
import '../../../../widgets/custom_button.dart';
import '../../data/services/user_service.dart';
import '../../domain/models/profile_type.dart';
import '../widgets/auth_input_field.dart';
import '../widgets/auth_shell.dart';
import '../widgets/common_phone_field.dart';
import '../widgets/searchable_selection_field.dart';

class ProfileDetailsScreen extends StatefulWidget {
  final ProfileType type;

  const ProfileDetailsScreen({super.key, required this.type});

  @override
  State<ProfileDetailsScreen> createState() => _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends State<ProfileDetailsScreen> {
  static final RegExp _usernamePattern = RegExp(r'^[a-z0-9_]{3,20}$');
  static final RegExp _phonePattern = RegExp(r'^\+\d{10,15}$');

  final nameController = TextEditingController();
  final usernameController = TextEditingController();
  final nameFocus = FocusNode();
  final usernameFocus = FocusNode();
  final phoneFocus = FocusNode();
  final UserService _userService = UserService();
  final AnalyticsService _analytics = AnalyticsService.instance;
  bool isLoading = false;
  bool isLocationLoading = true;
  bool _acceptedProviderAgreement = false;
  String? usernameError;
  String? phoneError;
  String? stateError;
  String? cityError;
  String? _providerConsentError;
  String? _selectedState;
  String? _selectedCity;
  String _fullPhoneNumber = '';
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

  String get profileTypeName => widget.type.name;

  @override
  void initState() {
    super.initState();
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

    final normalizedUsername = _normalizeUsername(usernameController.text);
    final usernameValidationError = _validateUsername(normalizedUsername);
    final phoneValidationError = _validatePhoneNumber(_fullPhoneNumber);
    final stateValidationError = _selectedState == null
        ? 'State is required'
        : null;
    final cityValidationError = _selectedCity == null
        ? 'City is required'
        : null;

    if (nameController.text.isEmpty ||
        _fullPhoneNumber.isEmpty ||
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
      phoneError = phoneValidationError;
      stateError = stateValidationError;
      cityError = cityValidationError;
      _providerConsentError =
          widget.type == ProfileType.serviceProvider && !_acceptedProviderAgreement
          ? 'You must agree to the Service Provider Agreement.'
          : null;
    });

    if (usernameValidationError != null ||
        phoneValidationError != null ||
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

      await _userService.createUserProfile(
        role: profileTypeName,
        name: nameController.text.trim(),
        username: normalizedUsername,
        phone: _fullPhoneNumber,
        state: _selectedState!,
        city: _selectedCity!,
        acceptedTerms:
            LegalAcceptanceSessionService.instance.hasPendingSignupConsent,
        acceptedPrivacy:
            LegalAcceptanceSessionService.instance.hasPendingSignupConsent,
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
      Navigator.pushReplacementNamed(context, "/home");
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
    phoneFocus.dispose();
    super.dispose();
  }

  String _normalizeUsername(String value) {
    return value.trim().replaceAll('@', '').toLowerCase();
  }

  String? _validateUsername(String username) {
    if (username.isEmpty) {
      return 'Username is required';
    }

    if (!_usernamePattern.hasMatch(username)) {
      return 'Use 3-20 lowercase letters, numbers, or underscores';
    }

    return null;
  }

  String? _validatePhoneNumber(String phoneNumber) {
    if (phoneNumber.isEmpty) {
      return 'Phone number is required';
    }

    if (!_phonePattern.hasMatch(phoneNumber)) {
      return 'Enter a valid phone number';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: getTitle(),
      subtitle:
          "A few details help us shape your profile, recommendations, and booking experience.",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLocationLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          AuthInputField(
            controller: nameController,
            focusNode: nameFocus,
            textInputAction: TextInputAction.next,
            labelText: getNameLabel(),
            onSubmitted: (_) {
              FocusScope.of(context).requestFocus(usernameFocus);
            },
          ),
          const SizedBox(height: 16),
          AuthInputField(
            controller: usernameController,
            focusNode: usernameFocus,
            textInputAction: TextInputAction.next,
            labelText: "Username",
            prefixText: "@",
            helperText: "3-20 lowercase letters, numbers, or underscores",
            errorText: usernameError,
            maxLength: 20,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
            ],
            onChanged: (value) {
              final normalized = _normalizeUsername(value);
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
              FocusScope.of(context).requestFocus(phoneFocus);
            },
          ),
          const SizedBox(height: 16),
          CommonPhoneField(
            focusNode: phoneFocus,
            textInputAction: TextInputAction.next,
            labelText: "Phone Number",
            errorText: phoneError,
            onChanged: (value) {
              setState(() {
                _fullPhoneNumber = value.trim();
                phoneError = _validatePhoneNumber(_fullPhoneNumber);
              });
            },
            onSubmitted: (_) {
              FocusScope.of(context).unfocus();
            },
          ),
          const SizedBox(height: 16),
          SearchableSelectionField(
            labelText: 'State',
            hintText: 'Select your state',
            options: _states,
            value: _selectedState,
            errorText: stateError,
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
          const SizedBox(height: 16),
          SearchableSelectionField(
            labelText: 'City',
            hintText: _selectedState == null
                ? 'Select state first'
                : 'Select your city',
            options: _cities,
            value: _selectedCity,
            errorText: cityError,
            enabled: _selectedState != null && !isLocationLoading,
            onSelected: (value) {
              setState(() {
                _selectedCity = value;
                cityError = null;
              });
            },
          ),
          const SizedBox(height: 24),
          if (widget.type == ProfileType.serviceProvider) ...[
            LegalConsentCheckbox(
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
            const SizedBox(height: 12),
          ],
          CustomButton(
            text: isLoading ? "Saving..." : "Continue",
            onPressed: isLoading ? null : () => saveProfile(),
          ),
        ],
      ),
    );
  }
}
