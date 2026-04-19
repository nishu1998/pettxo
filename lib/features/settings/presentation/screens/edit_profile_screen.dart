import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
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

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;
  String? _nameError;
  String? _locationError;
  File? _selectedImage;
  UserProfile? _initialProfile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _profileRepository.getCurrentUserProfile();
      if (!mounted) return;

      _initialProfile = profile;
      _nameController.text = profile.name;
      _locationController.text = profile.location;
      _bioController.text = profile.bio;

      setState(() => _isLoading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
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

    setState(() {
      _selectedImage = File(image.path);
    });
  }

  Future<void> _saveProfile() async {
    final profile = _initialProfile;
    if (profile == null || _isSaving) return;

    final name = _nameController.text.trim();
    final location = _locationController.text.trim();
    final bio = _bioController.text.trim();

    setState(() {
      _nameError = name.isEmpty ? 'Name is required' : null;
      _locationError = location.isEmpty ? 'Location is required' : null;
    });

    if (_nameError != null || _locationError != null) {
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
      String? uploadedImageUrl;
      if (_selectedImage != null) {
        uploadedImageUrl = await _profileRepository.uploadProfileImage(
          _selectedImage!,
        );
      }

      await _profileRepository.updateCurrentUserProfile(
        name: name,
        location: location,
        bio: bio,
        profileImageUrl: uploadedImageUrl,
      );

      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'Profile updated successfully.',
        tone: AppFeedbackTone.success,
      );
      Navigator.pop(context, true);
    } catch (error) {
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
    _locationController.dispose();
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Edit Profile',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textDark,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Update your identity, bio, avatar, and public details',
                                style: TextStyle(
                                  color: AppColors.textGrey,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
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
                        _ProfileTextField(
                          controller: _locationController,
                          label: 'Location',
                          errorText: _locationError,
                          onChanged: (_) {
                            if (_locationError == null) return;
                            setState(() => _locationError = null);
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
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: AppColors.brandGradientDiagonal,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          fallbackInitials,
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.8,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    if (selectedImage != null) {
      return ClipOval(
        child: Image.file(
          selectedImage!,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }

    if (imageUrl.isEmpty) {
      return fallback();
    }

    return ClipOval(
      child: Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback(),
      ),
    );
  }
}
