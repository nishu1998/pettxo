import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../widgets/custom_button.dart';
import '../../data/services/user_service.dart';
import '../../domain/models/profile_type.dart';
import '../widgets/auth_input_field.dart';
import '../widgets/auth_shell.dart';

class ProfileDetailsScreen extends StatefulWidget {
  final ProfileType type;

  const ProfileDetailsScreen({super.key, required this.type});

  @override
  State<ProfileDetailsScreen> createState() => _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends State<ProfileDetailsScreen> {
  static final RegExp _usernamePattern = RegExp(r'^[a-z0-9_]{3,20}$');

  final nameController = TextEditingController();
  final usernameController = TextEditingController();
  final locationController = TextEditingController();
  final nameFocus = FocusNode();
  final usernameFocus = FocusNode();
  final locationFocus = FocusNode();
  final UserService _userService = UserService();
  final AnalyticsService _analytics = AnalyticsService.instance;
  bool isLoading = false;
  String? usernameError;

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

    final normalizedUsername = _normalizeUsername(usernameController.text);
    final usernameValidationError = _validateUsername(normalizedUsername);

    if (nameController.text.isEmpty || locationController.text.isEmpty) {
      AppFeedback.show(
        context,
        message: "Please fill all fields",
        tone: AppFeedbackTone.info,
      );
      return;
    }

    setState(() {
      usernameError = usernameValidationError;
    });

    if (usernameValidationError != null) {
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
        location: locationController.text.trim(),
      );
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
    locationController.dispose();
    nameFocus.dispose();
    usernameFocus.dispose();
    locationFocus.dispose();
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

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: getTitle(),
      subtitle:
          "A few details help us shape your profile, recommendations, and booking experience.",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textDark,
              padding: EdgeInsets.zero,
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text(
              "Back",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4EE),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              widget.type == ProfileType.serviceProvider
                  ? "This information will help customers trust your business."
                  : "This helps your profile feel complete and more discoverable.",
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 20),
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
              FocusScope.of(context).requestFocus(locationFocus);
            },
          ),
          const SizedBox(height: 16),
          AuthInputField(
            controller: locationController,
            focusNode: locationFocus,
            textInputAction: TextInputAction.done,
            labelText: "Location",
            onSubmitted: (_) {
              saveProfile();
            },
          ),
          const SizedBox(height: 24),
          CustomButton(
            text: isLoading ? "Saving..." : "Continue",
            onPressed: isLoading ? null : () => saveProfile(),
          ),
        ],
      ),
    );
  }
}
