import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../data/repositories/profile_content_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../domain/models/profile_service_listing.dart';
import '../../domain/models/user_profile.dart';

class AddServiceScreen extends StatefulWidget {
  const AddServiceScreen({super.key});

  @override
  State<AddServiceScreen> createState() => _AddServiceScreenState();
}

class _AddServiceScreenState extends State<AddServiceScreen> {
  final ProfileRepository _profileRepository = ProfileRepository();
  final ProfileContentRepository _contentRepository =
      const ProfileContentRepository();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  final List<String> _serviceTypes = const [
    'Grooming',
    'Dog Walking',
    'Cat Sitting',
    'Pet Sitting',
    'Boarding',
    'Day Care',
    'Training',
    'Vet Visit Support',
    'Pet Taxi',
    'Home Visit',
    'Medication Support',
    'Puppy Care',
    'Senior Pet Care',
    'Litter Box Care',
    'Nail Trim',
    'Bathing',
    'Deshedding',
    'Other',
  ];
  final List<String> _petSizes = const [
    'Small pets',
    'Medium pets',
    'Large pets',
    'All friendly pets',
  ];
  late Future<UserProfile> _profileFuture;
  String _selectedServiceType = 'Grooming';
  String _selectedPetSize = 'All friendly pets';
  final Set<DateTime> _selectedDates = {};
  final List<String> _timeSlots = [];
  int _selectedDurationHours = 1;
  int _selectedDurationMinutes = 0;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _profileFuture = _profileRepository.getCurrentUserProfile();
  }

  Future<void> _saveService(UserProfile profile) async {
    if (_isSaving) return;

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final location = _locationController.text.trim();
    final price = _priceController.text.trim();
    final duration = _durationController.text.trim();

    if (title.isEmpty ||
        description.isEmpty ||
        location.isEmpty ||
        price.isEmpty ||
        duration.isEmpty ||
        _selectedDates.isEmpty ||
        _timeSlots.isEmpty) {
      AppFeedback.show(
        context,
        message:
            'Please complete service name, details, location, pricing, duration, and availability.',
        tone: AppFeedbackTone.info,
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final service = ProfileServiceListing(
        id: '${profile.uid}_${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        serviceType: _selectedServiceType,
        description: _notesController.text.trim().isEmpty
            ? description
            : '$description ${_notesController.text.trim()}',
        rate: price.startsWith('₹') ? price : '₹$price',
        location: location,
        availability: _availabilitySummary,
        duration: duration,
        petSize: _selectedPetSize,
        rating: 'New',
        distance: location,
        imageUrl: _imageForServiceType(_selectedServiceType),
      );

      await _contentRepository.addServiceForProfile(profile, service);

      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'Service added to your profile.',
        tone: AppFeedbackTone.success,
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      AppFeedback.show(
        context,
        message: 'Sorry, we could not add this service right now.',
        tone: AppFeedbackTone.error,
      );
    }
  }

  String get _availabilitySummary {
    final selectedDates = _selectedDates.toList()..sort();

    return '${selectedDates.map(_formatShortDate).join(', ')} - ${_timeSlots.join(', ')}';
  }

  void _toggleDate(DateTime date) {
    final normalizedDate = _dateOnly(date);

    setState(() {
      if (_selectedDates.contains(normalizedDate)) {
        _selectedDates.remove(normalizedDate);
      } else {
        _selectedDates.add(normalizedDate);
      }
    });
  }

  void _removeTimeSlot(String value) {
    setState(() {
      _timeSlots.remove(value);
    });
  }

  Future<void> _pickAndAddTimeSlot(BuildContext context) async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      initialEntryMode: TimePickerEntryMode.dial,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: AppColors.background,
              onSurface: AppColors.textDark,
            ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: AppColors.background,
              dialBackgroundColor: Colors.white,
              dialHandColor: AppColors.primary,
              dialTextColor: AppColors.textDark,
              dayPeriodColor: AppColors.primary.withValues(alpha: 0.12),
              dayPeriodTextColor: AppColors.textDark,
              entryModeIconColor: AppColors.primary,
              hourMinuteColor: Colors.white,
              hourMinuteTextColor: AppColors.textDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedTime == null || !mounted || !context.mounted) return;

    final formattedTime = pickedTime.format(context);
    if (_timeSlots.contains(formattedTime)) {
      AppFeedback.show(
        context,
        message: 'This time slot is already added.',
        tone: AppFeedbackTone.info,
      );
      return;
    }

    setState(() {
      _timeSlots.add(formattedTime);
    });
  }

  Future<void> _pickDuration(BuildContext context) async {
    var selectedHours = _selectedDurationHours;
    var selectedMinutes = _selectedDurationMinutes;

    final pickedDuration =
        await showModalBottomSheet<({int hours, int minutes})>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (context) {
            return StatefulBuilder(
              builder: (context, setSheetState) {
                return SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Container(
                        margin: const EdgeInsets.all(14),
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight * 0.82,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.14),
                              blurRadius: 28,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Service duration',
                                      style: TextStyle(
                                        color: AppColors.textDark,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Choose how long one booking usually takes.',
                                style: TextStyle(
                                  color: AppColors.textGrey,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'Hours',
                                style: TextStyle(
                                  color: AppColors.textDark,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _DurationChoiceWrap(
                                values: const [0, 1, 2, 3, 4, 5, 6, 7, 8],
                                selected: selectedHours,
                                suffix: 'h',
                                onChanged: (value) {
                                  setSheetState(() => selectedHours = value);
                                },
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'Minutes',
                                style: TextStyle(
                                  color: AppColors.textDark,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _DurationChoiceWrap(
                                values: const [0, 15, 30, 45],
                                selected: selectedMinutes,
                                suffix: 'm',
                                onChanged: (value) {
                                  setSheetState(() => selectedMinutes = value);
                                },
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed:
                                      selectedHours == 0 && selectedMinutes == 0
                                      ? null
                                      : () {
                                          Navigator.pop(context, (
                                            hours: selectedHours,
                                            minutes: selectedMinutes,
                                          ));
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size.fromHeight(54),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  child: const Text(
                                    'Set duration',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        );

    if (pickedDuration == null || !mounted) return;

    setState(() {
      _selectedDurationHours = pickedDuration.hours;
      _selectedDurationMinutes = pickedDuration.minutes;
      _durationController.text = _formatDuration(
        pickedDuration.hours,
        pickedDuration.minutes,
      );
    });
  }

  String _formatDuration(int hours, int minutes) {
    final parts = <String>[];
    if (hours > 0) parts.add(hours == 1 ? '1 hour' : '$hours hours');
    if (minutes > 0) parts.add('$minutes min');
    return parts.join(' ');
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _formatShortDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  String _imageForServiceType(String serviceType) {
    return switch (serviceType) {
      'Dog Walking' =>
        'https://images.unsplash.com/photo-1548199973-03cce0bbc87b?auto=format&fit=crop&w=700&q=80',
      'Cat Sitting' || 'Pet Sitting' || 'Boarding' || 'Day Care' =>
        'https://images.unsplash.com/photo-1519052537078-e6302a4968d4?auto=format&fit=crop&w=700&q=80',
      'Training' =>
        'https://images.unsplash.com/photo-1601758064130-56e02bbadf17?auto=format&fit=crop&w=700&q=80',
      'Vet Visit Support' =>
        'https://images.unsplash.com/photo-1612531386530-97286d97c2d2?auto=format&fit=crop&w=700&q=80',
      _ =>
        'https://images.unsplash.com/photo-1518717758536-85ae29035b6d?auto=format&fit=crop&w=700&q=80',
    };
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _priceController.dispose();
    _durationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FutureBuilder<UserProfile>(
          future: _profileFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final profile = snapshot.data!;

            return Stack(
              children: [
                Positioned(
                  top: -80,
                  right: -60,
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 0.07),
                    ),
                  ),
                ),
                ListView(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                  children: [
                    _HeaderCard(onBack: () => Navigator.pop(context)),
                    const SizedBox(height: 18),
                    _PremiumIntroCard(profile: profile),
                    const SizedBox(height: 18),
                    _SectionCard(
                      title: 'Service details',
                      subtitle:
                          'Make it easy for pet parents to understand what you offer.',
                      children: [
                        _ServiceTypeDropdown(
                          options: _serviceTypes,
                          selected: _selectedServiceType,
                          onChanged: (value) {
                            setState(() => _selectedServiceType = value);
                          },
                        ),
                        const SizedBox(height: 14),
                        _ServiceField(
                          controller: _titleController,
                          label: 'Service name',
                          hintText: 'Example: Calm home grooming',
                        ),
                        const SizedBox(height: 14),
                        _ServiceField(
                          controller: _descriptionController,
                          label: 'What is included?',
                          hintText:
                              'Bath, brushing, nail trim, calm handling...',
                          maxLines: 4,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SectionCard(
                      title: 'Location and pricing',
                      subtitle:
                          'Clear pricing and location build trust before booking.',
                      children: [
                        _ServiceField(
                          controller: _locationController,
                          label: 'Service location',
                          hintText: profile.location.isEmpty
                              ? 'City, area, or service radius'
                              : profile.location,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _ServiceField(
                                controller: _priceController,
                                label: 'Price',
                                hintText: '499 or 499-899',
                                keyboardType: TextInputType.number,
                                prefixText: '₹ ',
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9\-]'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _ServiceField(
                                controller: _durationController,
                                label: 'Duration',
                                hintText: 'Select',
                                readOnly: true,
                                suffixIcon: const Icon(
                                  Icons.timer_outlined,
                                  color: AppColors.textGrey,
                                ),
                                onTap: () => _pickDuration(context),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _PetSizeSelector(
                          options: _petSizes,
                          selected: _selectedPetSize,
                          onChanged: (value) {
                            setState(() => _selectedPetSize = value);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SectionCard(
                      title: 'Availability calendar',
                      subtitle:
                          'Select bookable dates for the next two months and add your own time slots.',
                      children: [
                        _TwoMonthCalendarPicker(
                          selectedDates: _selectedDates,
                          dateOnly: _dateOnly,
                          onToggle: _toggleDate,
                        ),
                        const SizedBox(height: 16),
                        _CustomTimeSlotPicker(
                          slots: _timeSlots,
                          onPickTime: () => _pickAndAddTimeSlot(context),
                          onRemove: _removeTimeSlot,
                        ),
                        const SizedBox(height: 14),
                        _AvailabilityPreview(summary: _availabilitySummary),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SectionCard(
                      title: 'Premium trust notes',
                      subtitle:
                          'Optional details help families book with confidence.',
                      children: [
                        _ServiceField(
                          controller: _notesController,
                          label: 'Safety, cancellation, or requirements',
                          hintText:
                              'Example: pets must be vaccinated, free cancellation up to 24h...',
                          maxLines: 3,
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving
                            ? null
                            : () => _saveService(profile),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: Text(
                          _isSaving ? 'Publishing...' : 'Add service',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final VoidCallback onBack;

  const _HeaderCard({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
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
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add Service',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Create a bookable pet care offer',
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
    );
  }
}

class _PremiumIntroCard extends StatelessWidget {
  final UserProfile profile;

  const _PremiumIntroCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradientDiagonal,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Premium booking setup',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add clear pricing, pet fit, and availability so ${profile.name.isEmpty ? 'pet parents' : profile.name} can receive better booking requests.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.42,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.event_available_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textGrey,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _ServiceField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hintText;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? prefixText;
  final Widget? suffixIcon;
  final bool readOnly;
  final VoidCallback? onTap;

  const _ServiceField({
    required this.controller,
    required this.label,
    required this.hintText,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.prefixText,
    this.suffixIcon,
    this.readOnly = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      readOnly: readOnly,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixText: prefixText,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFFCFBFA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.32),
          ),
        ),
      ),
    );
  }
}

class _ServiceTypeDropdown extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onChanged;

  const _ServiceTypeDropdown({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: selected,
      isExpanded: true,
      borderRadius: BorderRadius.circular(24),
      dropdownColor: const Color(0xFFFFFCFA),
      menuMaxHeight: 360,
      icon: const Icon(
        Icons.keyboard_arrow_down_rounded,
        color: AppColors.primary,
      ),
      style: const TextStyle(
        color: AppColors.textDark,
        fontWeight: FontWeight.w800,
        fontSize: 15,
      ),
      items: options.map((option) {
        return DropdownMenuItem(
          value: option,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(option),
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
      decoration: InputDecoration(
        labelText: 'Service category',
        helperText: 'This will power Explore grouping later.',
        filled: true,
        fillColor: const Color(0xFFFCFBFA),
        prefixIcon: const Icon(
          Icons.category_outlined,
          color: AppColors.primary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.32),
          ),
        ),
      ),
    );
  }
}

class _PetSizeSelector extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onChanged;

  const _PetSizeSelector({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: selected,
      isExpanded: true,
      borderRadius: BorderRadius.circular(24),
      dropdownColor: const Color(0xFFFFFCFA),
      icon: const Icon(
        Icons.keyboard_arrow_down_rounded,
        color: AppColors.primary,
      ),
      style: const TextStyle(
        color: AppColors.textDark,
        fontWeight: FontWeight.w800,
        fontSize: 15,
      ),
      items: options.map((option) {
        return DropdownMenuItem(
          value: option,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(option),
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
      decoration: InputDecoration(
        labelText: 'Accepted pet size',
        filled: true,
        fillColor: const Color(0xFFFCFBFA),
        prefixIcon: const Icon(Icons.pets_rounded, color: AppColors.primary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.32),
          ),
        ),
      ),
    );
  }
}

class _DurationChoiceWrap extends StatelessWidget {
  final List<int> values;
  final int selected;
  final String suffix;
  final ValueChanged<int> onChanged;

  const _DurationChoiceWrap({
    required this.values,
    required this.selected,
    required this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: values.map((value) {
        final isSelected = value == selected;
        return ChoiceChip(
          label: Text('$value$suffix'),
          selected: isSelected,
          onSelected: (_) => onChanged(value),
          selectedColor: AppColors.primary.withValues(alpha: 0.16),
          backgroundColor: Colors.white,
          labelStyle: TextStyle(
            color: isSelected ? AppColors.primary : AppColors.textDark,
            fontWeight: FontWeight.w900,
          ),
          side: BorderSide(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.26)
                : AppColors.primary.withValues(alpha: 0.08),
          ),
        );
      }).toList(),
    );
  }
}

class _TwoMonthCalendarPicker extends StatelessWidget {
  final Set<DateTime> selectedDates;
  final DateTime Function(DateTime date) dateOnly;
  final ValueChanged<DateTime> onToggle;

  const _TwoMonthCalendarPicker({
    required this.selectedDates,
    required this.dateOnly,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final lastDate = today.add(const Duration(days: 60));
    final firstMonth = DateTime(today.year, today.month);
    final secondMonth = DateTime(today.year, today.month + 1);

    return Column(
      children: [
        _CalendarMonth(
          month: firstMonth,
          today: today,
          lastDate: lastDate,
          selectedDates: selectedDates,
          dateOnly: dateOnly,
          onToggle: onToggle,
        ),
        const SizedBox(height: 16),
        _CalendarMonth(
          month: secondMonth,
          today: today,
          lastDate: lastDate,
          selectedDates: selectedDates,
          dateOnly: dateOnly,
          onToggle: onToggle,
        ),
      ],
    );
  }
}

class _CalendarMonth extends StatelessWidget {
  final DateTime month;
  final DateTime today;
  final DateTime lastDate;
  final Set<DateTime> selectedDates;
  final DateTime Function(DateTime date) dateOnly;
  final ValueChanged<DateTime> onToggle;

  const _CalendarMonth({
    required this.month,
    required this.today,
    required this.lastDate,
    required this.selectedDates,
    required this.dateOnly,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final days = _calendarDaysForMonth(month);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCFA),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _monthLabel(month),
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                'Next 60 days',
                style: TextStyle(
                  color: AppColors.primary.withValues(alpha: 0.82),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              _WeekdayLabel('M'),
              _WeekdayLabel('T'),
              _WeekdayLabel('W'),
              _WeekdayLabel('T'),
              _WeekdayLabel('F'),
              _WeekdayLabel('S'),
              _WeekdayLabel('S'),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: days.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              final date = days[index];
              if (date == null) return const SizedBox.shrink();

              final normalizedDate = dateOnly(date);
              final isAvailable =
                  !normalizedDate.isBefore(today) &&
                  !normalizedDate.isAfter(lastDate);
              final isSelected = selectedDates.contains(normalizedDate);

              return GestureDetector(
                onTap: isAvailable ? () => onToggle(normalizedDate) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: isSelected ? AppColors.brandGradient : null,
                    color: isSelected
                        ? null
                        : isAvailable
                        ? Colors.white
                        : AppColors.textGrey.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? Colors.transparent
                          : AppColors.primary.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Text(
                    '${date.day}',
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : isAvailable
                          ? AppColors.textDark
                          : AppColors.textGrey.withValues(alpha: 0.45),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  List<DateTime?> _calendarDaysForMonth(DateTime month) {
    final firstDay = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingEmptyDays = firstDay.weekday - 1;

    return [
      ...List<DateTime?>.filled(leadingEmptyDays, null),
      ...List.generate(daysInMonth, (index) {
        return DateTime(month.year, month.month, index + 1);
      }),
    ];
  }

  String _monthLabel(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}

class _WeekdayLabel extends StatelessWidget {
  final String label;

  const _WeekdayLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.textGrey,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CustomTimeSlotPicker extends StatelessWidget {
  final List<String> slots;
  final VoidCallback onPickTime;
  final ValueChanged<String> onRemove;

  const _CustomTimeSlotPicker({
    required this.slots,
    required this.onPickTime,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onPickTime,
            icon: const Icon(Icons.schedule_rounded),
            label: const Text('Pick time slot'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.textDark,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Select from the clock so every slot is a valid booking time.',
          style: TextStyle(
            color: AppColors.textGrey,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        if (slots.isEmpty)
          const Text(
            'Add at least one custom time slot for this service.',
            style: TextStyle(
              color: AppColors.textGrey,
              fontWeight: FontWeight.w600,
            ),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: slots.map((slot) {
              return InputChip(
                label: Text(slot),
                onDeleted: () => onRemove(slot),
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                deleteIconColor: AppColors.primary,
                labelStyle: const TextStyle(
                  color: AppColors.textDark,
                  fontWeight: FontWeight.w800,
                ),
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.14),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

class _AvailabilityPreview extends StatelessWidget {
  final String summary;

  const _AvailabilityPreview({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_rounded, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              summary,
              style: const TextStyle(
                color: AppColors.textDark,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
