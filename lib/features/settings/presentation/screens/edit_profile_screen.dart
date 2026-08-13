import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/image_crop_service.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_user_avatar.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../auth/domain/models/profile_type.dart';
import '../../../auth/presentation/widgets/profile_type_selector_dialog.dart';
import '../../../auth/presentation/widgets/searchable_selection_field.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../../profile/domain/models/user_profile.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const int _bioCharacterLimit = 160;

  final ProfileRepository _profileRepository = ProfileRepository();
  final ImagePicker _imagePicker = ImagePicker();
  final ImageCropService _imageCropService = ImageCropService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  bool _isLoading = true;
  bool _isLocationLoading = true;
  bool _isSaving = false;
  String? _loadError;
  String? _nameError;
  String? _stateError;
  String? _cityError;
  ProfileType _selectedProfileType = ProfileType.petParent;
  File? _selectedImage;
  UserProfile? _initialProfile;
  List<String> _states = const [];
  List<String> _cities = const [];
  String? _selectedState;
  String? _selectedCity;
  bool _hasUnmappedLegacyLocation = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      await LocationService.instance.load();
      final profile = await _profileRepository.getCurrentUserProfile();
      if (!mounted) return;

      _initialProfile = profile;
      _nameController.text = profile.name;
      _bioController.text = profile.bio;
      _selectedProfileType = profileTypeFromStoredValue(profile.role);
      _states = LocationService.instance.getStates();

      final resolvedLocation = LocationService.instance
          .resolveStoredProfileLocation(
            state: profile.state,
            city: profile.city,
            legacyLocation: profile.legacyLocation,
          );
      if (resolvedLocation != null) {
        _selectedState = resolvedLocation.state;
        _cities = LocationService.instance.getCities(resolvedLocation.state);
        _selectedCity = resolvedLocation.city;
        _hasUnmappedLegacyLocation = false;
      } else {
        _selectedState = null;
        _selectedCity = null;
        _cities = const [];
        _hasUnmappedLegacyLocation = profile.location.trim().isNotEmpty;
      }

      setState(() {
        _isLoading = false;
        _isLocationLoading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('EditProfile load -> failed stage=load-profile error=$error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLocationLoading = false;
        _loadError = 'We could not load your profile right now.';
      });
      AppFeedback.show(
        context,
        message: 'Unable to load your profile right now.',
        tone: AppFeedbackTone.error,
      );
    }
  }

  Future<void> _pickProfileImage() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );

    if (image == null || !mounted) return;

    final croppedImage = await _imageCropService.cropImage(
      source: image,
      context: ImageCropContext.profile,
      ratio: ImageCropRatio.square,
    );
    if (!mounted) return;
    if (croppedImage == null) {
      AppFeedback.show(
        context,
        message: _imageCropService.hadLastError
            ? 'Image crop failed. Please try again.'
            : 'Profile photo update cancelled.',
        tone: AppFeedbackTone.info,
      );
      return;
    }

    setState(() {
      _selectedImage = croppedImage;
    });
  }

  Future<void> _saveProfile() async {
    final profile = _initialProfile;
    if (profile == null || _isSaving) return;

    final name = _nameController.text.trim();
    final bio = _bioController.text.trim();
    final selectedState = (_selectedState ?? '').trim();
    final selectedCity = (_selectedCity ?? '').trim();
    final resolvedInitialLocation = LocationService.instance
        .resolveStoredProfileLocation(
          state: profile.state,
          city: profile.city,
          legacyLocation: profile.legacyLocation,
        );
    final hadInitialCanonicalLocation = resolvedInitialLocation != null;
    final hasSelectedCanonicalLocation =
        selectedState.isNotEmpty && selectedCity.isNotEmpty;
    final attemptedCanonicalLocationSelection =
        selectedState.isNotEmpty || selectedCity.isNotEmpty;
    final locationChanged = hadInitialCanonicalLocation
        ? resolvedInitialLocation.state != selectedState ||
              resolvedInitialLocation.city != selectedCity
        : attemptedCanonicalLocationSelection;
    final shouldUpdateLocation =
        hasSelectedCanonicalLocation &&
        (!hadInitialCanonicalLocation || locationChanged);

    setState(() {
      _nameError = name.isEmpty ? 'Name is required' : null;
      _stateError = !_hasUnmappedLegacyLocation && selectedState.isEmpty
          ? 'State is required'
          : null;
      _cityError = !_hasUnmappedLegacyLocation && selectedCity.isEmpty
          ? 'City is required'
          : null;
    });

    if (_nameError != null || _stateError != null || _cityError != null) {
      return;
    }

    if (locationChanged && !hasSelectedCanonicalLocation) {
      setState(() {
        _stateError = selectedState.isEmpty ? 'State is required' : null;
        _cityError = selectedCity.isEmpty ? 'City is required' : null;
      });
      return;
    }

    if (bio.length > _bioCharacterLimit) {
      AppFeedback.show(
        context,
        message: 'Sorry, your bio should stay within 160 characters.',
        tone: AppFeedbackTone.info,
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      debugPrint('EditProfile save -> validation passed');
      String? uploadedImageUrl;
      if (_selectedImage != null) {
        debugPrint('EditProfile save -> profile image upload starting');
        uploadedImageUrl = await _profileRepository.uploadProfileImage(
          _selectedImage!,
        );
        debugPrint('EditProfile save -> profile image upload completed');
      }

      final updateResult = await _profileRepository.updateCurrentUserProfile(
        name: name,
        bio: bio,
        state: shouldUpdateLocation ? selectedState : profile.state,
        city: shouldUpdateLocation ? selectedCity : profile.city,
        updateLocation: shouldUpdateLocation,
        role: _selectedProfileType.storedValue,
        profileImageUrl: uploadedImageUrl,
      );
      debugPrint('EditProfile save -> profile write committed');
      if (updateResult.hasSecondaryFailure) {
        debugPrint(
          'EditProfile save -> secondary failure preserved after commit error=${updateResult.secondaryFailure}',
        );
        if (updateResult.secondaryFailureStackTrace != null) {
          debugPrintStack(stackTrace: updateResult.secondaryFailureStackTrace!);
        }
      }

      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'Profile updated successfully.',
        tone: AppFeedbackTone.success,
      );
      Navigator.pop(context, true);
    } catch (error, stackTrace) {
      debugPrint(
        'EditProfile save -> failed stage=authoritative-write error=$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _isSaving = false);
      AppFeedback.show(
        context,
        message: _friendlySaveError(error),
        tone: AppFeedbackTone.error,
      );
      return;
    }
  }

  String _friendlySaveError(Object error) {
    final message = error.toString().toLowerCase();

    if (message.contains('permission')) {
      return 'Sorry, we could not update your profile because permission was denied. Please check your Firebase rules and try again.';
    }

    if (message.contains('storage')) {
      return 'Sorry, profile photo upload is not available yet. Please save without changing the photo for now.';
    }

    return 'Sorry, we could not update your profile right now. Please try again in a moment.';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _initialProfile;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null || profile == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.person_off_outlined,
                        size: 40,
                        color: AppColors.textGrey,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _loadError ?? 'Profile details are unavailable.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _loadError = null;
                          });
                          _loadProfile();
                        },
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Edit Profile',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.97),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.08),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _pickProfileImage,
                          child: Stack(
                            children: [
                              _ProfileAvatar(
                                imageUrl: profile.profileImageUrl,
                                fallbackInitials: profile.initials,
                                selectedImage: _selectedImage,
                                radius: 46,
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    gradient: AppColors.brandGradient,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt_outlined,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _pickProfileImage,
                          child: const Text('Change photo'),
                        ),
                        const SizedBox(height: 12),
                        _ProfileTextField(
                          controller: _nameController,
                          label: 'Name',
                          errorText: _nameError,
                          onChanged: (_) {
                            if (_nameError == null) return;
                            setState(() => _nameError = null);
                          },
                        ),
                        const SizedBox(height: 14),
                        if (_isLocationLoading)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 14),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        SearchableSelectionField(
                          labelText: 'State',
                          hintText: 'Select your state',
                          value: _selectedState,
                          errorText: _stateError,
                          options: _states,
                          enabled: !_isSaving && !_isLocationLoading,
                          onSelected: (value) {
                            setState(() {
                              _selectedState = value;
                              _cities = LocationService.instance.getCities(
                                value,
                              );
                              if (!_cities.contains(_selectedCity)) {
                                _selectedCity = null;
                              }
                              _stateError = null;
                              _cityError = null;
                              _hasUnmappedLegacyLocation = false;
                            });
                          },
                          compactLabel: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SearchableSelectionField(
                          labelText: 'City',
                          hintText: _selectedState == null
                              ? 'Select state first'
                              : 'Select your city',
                          value: _selectedCity,
                          errorText: _cityError,
                          options: _cities,
                          enabled:
                              !_isSaving &&
                              !_isLocationLoading &&
                              _selectedState != null,
                          onSelected: (value) {
                            setState(() {
                              _selectedCity = value;
                              _cityError = null;
                              _hasUnmappedLegacyLocation = false;
                            });
                          },
                          compactLabel: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                        if (_hasUnmappedLegacyLocation) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Your existing location could not be matched to Pettxo’s state/city list. You can keep it as-is, or select a valid state and city to replace it.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.textGrey),
                          ),
                        ],
                        const SizedBox(height: 14),
                        _ProfileSelectionField(
                          label: 'Account Type',
                          value: _selectedProfileType.label,
                          onTap: _isSaving
                              ? null
                              : () async {
                                  final selected =
                                      await ProfileTypeSelectorDialog.show(
                                        context,
                                        selectedType: _selectedProfileType,
                                      );
                                  if (selected == null || !mounted) return;
                                  setState(() {
                                    _selectedProfileType = selected;
                                  });
                                },
                        ),
                        const SizedBox(height: 14),
                        _ProfileTextField(
                          controller: _bioController,
                          label: 'Bio',
                          maxLines: 4,
                          helperText: 'Keep it short, warm, and trustworthy.',
                          maxLength: _bioCharacterLimit,
                          counterText:
                              '${_bioController.text.length}/$_bioCharacterLimit',
                          onChanged: (_) {
                            setState(() {});
                          },
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          child: GradientButton(
                            label: _isSaving ? 'Saving...' : 'Save changes',
                            onPressed: _isSaving ? null : _saveProfile,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ProfileTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? errorText;
  final String? helperText;
  final String? counterText;
  final ValueChanged<String>? onChanged;
  final int? maxLength;
  final int maxLines;

  const _ProfileTextField({
    required this.controller,
    required this.label,
    this.errorText,
    this.helperText,
    this.counterText,
    this.onChanged,
    this.maxLength,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        helperText: helperText,
        counterText: counterText,
        filled: true,
        fillColor: const Color(0xFFFCFBFA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.28),
          ),
        ),
      ),
    );
  }
}

class _ProfileSelectionField extends StatelessWidget {
  const _ProfileSelectionField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: const Color(0xFFFCFBFA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.28),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.textGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String imageUrl;
  final String fallbackInitials;
  final File? selectedImage;
  final double radius;

  const _ProfileAvatar({
    required this.imageUrl,
    required this.fallbackInitials,
    required this.selectedImage,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;

    Widget fallback() {
      return AppUserAvatarFallback(
        initials: fallbackInitials,
        gradient: AppColors.brandGradientDiagonal,
        textStyle: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w800,
        ),
      );
    }

    return AppUserAvatar(
      size: size,
      imageFile: selectedImage,
      imageUrl: imageUrl,
      useCachedImage: false,
      fallback: fallback(),
    );
  }
}
