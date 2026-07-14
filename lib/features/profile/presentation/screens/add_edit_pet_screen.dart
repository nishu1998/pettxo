import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/image_crop_service.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../data/repositories/pet_repository.dart';
import '../../domain/models/pet_profile.dart';

class AddEditPetScreen extends StatefulWidget {
  final String ownerId;
  final String? petId;
  final PetProfile? initialPet;

  const AddEditPetScreen({
    super.key,
    required this.ownerId,
    this.petId,
    this.initialPet,
  });

  bool get isEditMode => petId != null || initialPet != null;

  @override
  State<AddEditPetScreen> createState() => _AddEditPetScreenState();
}

class _AddEditPetScreenState extends State<AddEditPetScreen> {
  static const List<String> _animalOptions = <String>[
    'Dog',
    'Cat',
    'Bird',
    'Rabbit',
    'Fish',
    'Hamster',
    'Guinea Pig',
    'Turtle',
    'Other',
  ];
  static const List<String> _sexOptions = <String>['Male', 'Female', 'Unknown'];

  final PetRepository _repository = PetRepository();
  final ImagePicker _imagePicker = ImagePicker();
  final ImageCropService _imageCropService = ImageCropService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _breedController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _allergiesController = TextEditingController();
  final TextEditingController _vetController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  String? _animalType;
  String? _sex;
  DateTime? _dateOfBirth;
  DateTime? _vaccinationDate;
  DateTime? _dewormingDate;
  bool _isVaccinated = false;
  bool _isDewormed = false;
  bool _isSaving = false;
  File? _selectedPhoto;
  PetProfile? _loadedPet;

  String? _nameError;
  String? _animalError;
  String? _sexError;
  String? _weightError;

  @override
  void initState() {
    super.initState();
    _applyPet(widget.initialPet);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _breedController.dispose();
    _weightController.dispose();
    _allergiesController.dispose();
    _vetController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _applyPet(PetProfile? pet) {
    if (pet == null) return;
    _loadedPet = pet;
    _nameController.text = pet.name;
    _animalType = pet.animalType.isEmpty ? null : pet.animalType;
    _sex = pet.sex.isEmpty ? null : pet.sex;
    _breedController.text = pet.breed;
    _dateOfBirth = pet.dateOfBirth;
    _weightController.text = pet.weightKg == null
        ? ''
        : _formatWeight(pet.weightKg!);
    _isVaccinated = pet.isVaccinated;
    _vaccinationDate = pet.vaccinationDate;
    _isDewormed = pet.isDewormed;
    _dewormingDate = pet.dewormingDate;
    _allergiesController.text = pet.knownAllergies;
    _vetController.text = pet.regularVet;
    _bioController.text = pet.bio;
  }

  Future<void> _pickPhoto() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1600,
    );
    if (image == null || !mounted) return;

    final croppedImage = await _imageCropService.cropImage(
      source: image,
      context: ImageCropContext.profile,
      ratio: ImageCropRatio.square,
    );
    if (!mounted) return;
    if (croppedImage == null) {
      if (_imageCropService.hadLastError) {
        AppFeedback.show(
          context,
          message: 'Image crop failed. Please try again.',
          tone: AppFeedbackTone.error,
        );
      }
      return;
    }

    setState(() => _selectedPhoto = croppedImage);
  }

  Future<void> _pickDate({
    required DateTime? initialDate,
    required ValueChanged<DateTime?> onChanged,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate ?? now,
      firstDate: DateTime(now.year - 40),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.textDark,
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: Colors.white,
              headerBackgroundColor: AppColors.primary,
              headerForegroundColor: Colors.white,
              dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return AppColors.textDark;
              }),
              dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppColors.primary;
                }
                return null;
              }),
              todayForegroundColor: const WidgetStatePropertyAll(
                AppColors.primary,
              ),
              todayBorder: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (!mounted || picked == null) return;
    setState(() => onChanged(picked));
  }

  Future<void> _savePet() async {
    if (_isSaving) return;

    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid != widget.ownerId) {
      AppFeedback.show(
        context,
        message: 'Only the pet owner can save this pet.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    final name = _nameController.text.trim();
    final animal = _animalType?.trim() ?? '';
    final sex = _sex?.trim() ?? '';
    final weightText = _weightController.text.trim();
    final weight = weightText.isEmpty ? null : double.tryParse(weightText);

    setState(() {
      _nameError = name.isEmpty ? 'Pet name is required' : null;
      _animalError = animal.isEmpty ? 'Animal is required' : null;
      _sexError = sex.isEmpty ? 'Sex is required' : null;
      _weightError = weightText.isNotEmpty && (weight == null || weight <= 0)
          ? 'Enter a valid weight'
          : null;
    });

    if (_nameError != null ||
        _animalError != null ||
        _sexError != null ||
        _weightError != null) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final existing = _loadedPet ?? widget.initialPet;
      final pet = PetProfile(
        id: existing?.id ?? '',
        ownerId: widget.ownerId,
        name: name,
        animalType: animal,
        sex: sex,
        breed: _breedController.text.trim(),
        dateOfBirth: _dateOfBirth,
        weightKg: weight,
        photoUrl: existing?.photoUrl ?? '',
        bio: _bioController.text.trim(),
        isVaccinated: _isVaccinated,
        vaccinationDate: _isVaccinated ? _vaccinationDate : null,
        isDewormed: _isDewormed,
        dewormingDate: _isDewormed ? _dewormingDate : null,
        knownAllergies: _allergiesController.text.trim(),
        regularVet: _vetController.text.trim(),
        createdAt: existing?.createdAt,
        updatedAt: existing?.updatedAt,
        isDeleted: false,
      );

      if (widget.isEditMode && pet.id.isNotEmpty) {
        await _repository.updatePet(pet: pet, photoFile: _selectedPhoto);
      } else {
        await _repository.createPet(pet: pet, photoFile: _selectedPhoto);
      }

      if (!mounted) return;
      AppFeedback.show(
        context,
        message: widget.isEditMode ? 'Pet profile saved.' : 'Pet added.',
        tone: AppFeedbackTone.success,
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'Unable to save pet right now.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialPet = widget.initialPet;
    if (widget.isEditMode && initialPet == null) {
      return StreamBuilder<PetProfile?>(
        stream: _repository.watchPet(
          ownerId: widget.ownerId,
          petId: widget.petId ?? '',
        ),
        builder: (context, snapshot) {
          final pet = snapshot.data;
          if (snapshot.connectionState == ConnectionState.waiting &&
              _loadedPet == null) {
            return const Scaffold(
              backgroundColor: AppColors.background,
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (pet == null && _loadedPet == null) {
            return const _PetFormMissingState();
          }
          if (pet != null && _loadedPet?.id != pet.id) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _loadedPet?.id != pet.id) {
                setState(() => _applyPet(pet));
              }
            });
          }
          return _buildForm();
        },
      );
    }

    return _buildForm();
  }

  Widget _buildForm() {
    final existingPhotoUrl =
        _loadedPet?.photoUrl ?? widget.initialPet?.photoUrl ?? '';
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _PetFormHeader(title: widget.isEditMode ? 'Edit pet' : 'Add pet'),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(18, 10, 18, 24 + bottomInset),
                children: [
                  _PetPhotoPicker(
                    imageFile: _selectedPhoto,
                    imageUrl: existingPhotoUrl,
                    label: widget.isEditMode ? 'Change photo' : 'Add photo',
                    onTap: _pickPhoto,
                  ),
                  const SizedBox(height: 16),
                  _PetTextField(
                    controller: _nameController,
                    label: 'Pet name',
                    errorText: _nameError,
                  ),
                  const SizedBox(height: 12),
                  _PetDropdownField(
                    label: 'Animal',
                    value: _animalType,
                    options: _animalOptions,
                    errorText: _animalError,
                    onChanged: (value) => setState(() {
                      _animalType = value;
                      _animalError = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  _PetDropdownField(
                    label: 'Sex',
                    value: _sex,
                    options: _sexOptions,
                    errorText: _sexError,
                    onChanged: (value) => setState(() {
                      _sex = value;
                      _sexError = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  _PetTextField(controller: _breedController, label: 'Breed'),
                  const SizedBox(height: 12),
                  _PetDateField(
                    label: 'Date of birth',
                    value: _dateOfBirth,
                    onTap: () => _pickDate(
                      initialDate: _dateOfBirth,
                      onChanged: (date) => _dateOfBirth = date,
                    ),
                    onClear: _dateOfBirth == null
                        ? null
                        : () => setState(() => _dateOfBirth = null),
                  ),
                  const SizedBox(height: 12),
                  _PetTextField(
                    controller: _weightController,
                    label: 'Weight in kilograms',
                    errorText: _weightError,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _PetSwitchTile(
                    label: 'Vaccinated',
                    helperText: 'Providers see this before accepting',
                    value: _isVaccinated,
                    onChanged: (value) => setState(() {
                      _isVaccinated = value;
                      if (!value) _vaccinationDate = null;
                    }),
                  ),
                  if (_isVaccinated) ...[
                    const SizedBox(height: 12),
                    _PetDateField(
                      label: 'Vaccination date',
                      value: _vaccinationDate,
                      onTap: () => _pickDate(
                        initialDate: _vaccinationDate,
                        onChanged: (date) => _vaccinationDate = date,
                      ),
                      onClear: _vaccinationDate == null
                          ? null
                          : () => setState(() => _vaccinationDate = null),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _PetSwitchTile(
                    label: 'Dewormed',
                    helperText: 'Last dose is shown on the pet card',
                    value: _isDewormed,
                    onChanged: (value) => setState(() {
                      _isDewormed = value;
                      if (!value) _dewormingDate = null;
                    }),
                  ),
                  if (_isDewormed) ...[
                    const SizedBox(height: 12),
                    _PetDateField(
                      label: 'Deworming date',
                      value: _dewormingDate,
                      onTap: () => _pickDate(
                        initialDate: _dewormingDate,
                        onChanged: (date) => _dewormingDate = date,
                      ),
                      onClear: _dewormingDate == null
                          ? null
                          : () => setState(() => _dewormingDate = null),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _PetTextField(
                    controller: _allergiesController,
                    label: 'Known allergies',
                  ),
                  const SizedBox(height: 12),
                  _PetTextField(
                    controller: _vetController,
                    label: 'Regular vet',
                  ),
                  const SizedBox(height: 12),
                  _PetTextField(
                    controller: _bioController,
                    label: 'Bio',
                    maxLines: 4,
                  ),
                  const SizedBox(height: 22),
                  GradientButton(
                    label: _isSaving
                        ? 'Saving...'
                        : widget.isEditMode
                        ? 'Save pet'
                        : 'Add pet',
                    onPressed: _isSaving ? null : _savePet,
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

class _PetFormHeader extends StatelessWidget {
  final String title;

  const _PetFormHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PetPhotoPicker extends StatelessWidget {
  final File? imageFile;
  final String imageUrl;
  final String label;
  final VoidCallback onTap;

  const _PetPhotoPicker({
    required this.imageFile,
    required this.imageUrl,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: SizedBox(
                    width: 178,
                    height: 178,
                    child: _PetImage(
                      file: imageFile,
                      imageUrl: imageUrl,
                      size: 178,
                    ),
                  ),
                ),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: const Icon(
                    Icons.photo_camera_rounded,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PetTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? errorText;
  final int maxLines;
  final TextInputType? keyboardType;

  const _PetTextField({
    required this.controller,
    required this.label,
    this.errorText,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: _petInputDecoration(label: label, errorText: errorText),
    );
  }
}

class _PetDropdownField extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> options;
  final String? errorText;
  final ValueChanged<String?> onChanged;

  const _PetDropdownField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.errorText,
  });

  Future<void> _openOptions(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.98),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: options.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: AppColors.primary.withValues(alpha: 0.06),
                      ),
                      itemBuilder: (context, index) {
                        final option = options[index];
                        final isSelected = option == value;
                        return ListTile(
                          minVerticalPadding: 14,
                          title: Text(
                            option,
                            style: TextStyle(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textDark,
                              fontWeight: isSelected
                                  ? FontWeight.w900
                                  : FontWeight.w700,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.primary,
                                )
                              : null,
                          onTap: () => Navigator.pop(sheetContext, option),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final selectedValue = value != null && options.contains(value)
        ? value!
        : 'Select $label';

    return InkWell(
      onTap: () => _openOptions(context),
      borderRadius: BorderRadius.circular(18),
      child: InputDecorator(
        decoration: _petInputDecoration(label: label, errorText: errorText),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selectedValue,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: value == null
                      ? AppColors.textGrey
                      : AppColors.textDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _PetDateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _PetDateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: InputDecorator(
        decoration: _petInputDecoration(label: label),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value == null ? 'Select date' : _formatDate(value!),
                style: TextStyle(
                  color: value == null
                      ? AppColors.textGrey
                      : AppColors.textDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (onClear != null)
              IconButton(
                tooltip: 'Clear $label',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, color: AppColors.primary),
              )
            else
              const Icon(
                Icons.calendar_month_rounded,
                color: AppColors.primary,
              ),
          ],
        ),
      ),
    );
  }
}

class _PetSwitchTile extends StatelessWidget {
  final String label;
  final String helperText;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PetSwitchTile({
    required this.label,
    required this.helperText,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  helperText,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: AppColors.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _PetImage extends StatelessWidget {
  final File? file;
  final String imageUrl;
  final double size;

  const _PetImage({
    required this.file,
    required this.imageUrl,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (file != null) {
      return Image.file(file!, fit: BoxFit.cover);
    }
    if (imageUrl.trim().isNotEmpty) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _PetPlaceholder(size: size),
      );
    }
    return _PetPlaceholder(size: size);
  }
}

class _PetPlaceholder extends StatelessWidget {
  final double size;

  const _PetPlaceholder({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: AppColors.brandGradientDiagonal,
      ),
      child: const Icon(Icons.pets_rounded, color: Colors.white, size: 54),
    );
  }
}

class _PetFormMissingState extends StatelessWidget {
  const _PetFormMissingState();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.pets_rounded,
                  color: AppColors.primary,
                  size: 48,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Pet not found',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This pet may have been removed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textGrey),
                ),
                const SizedBox(height: 18),
                SecondaryButton(
                  label: 'Go back',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration _petInputDecoration({
  required String label,
  String? errorText,
}) {
  return InputDecoration(
    labelText: label,
    errorText: errorText,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.08)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
    ),
  );
}

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String _formatWeight(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}
