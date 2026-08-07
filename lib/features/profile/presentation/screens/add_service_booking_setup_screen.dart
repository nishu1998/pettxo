import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/service_duration.dart';
import '../../../../core/widgets/app_glass_overlay.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../domain/models/add_service_flow_draft.dart';
import '../../domain/models/service_location.dart';
import '../../domain/models/service_booking_setup_draft.dart';
import '../../domain/models/service_details_draft.dart';
import 'add_service_additional_details_screen.dart';
import 'service_location_picker_screen.dart';
import '../widgets/add_service_flow_header.dart';
import '../widgets/service_location_card.dart';

class AddServiceBookingSetupScreen extends StatefulWidget {
  final ServiceDetailsDraft draft;

  const AddServiceBookingSetupScreen({super.key, required this.draft});

  @override
  State<AddServiceBookingSetupScreen> createState() =>
      _AddServiceBookingSetupScreenState();
}

class _AddServiceBookingSetupScreenState
    extends State<AddServiceBookingSetupScreen> {
  static const Color _screenBackground = Color(0xFFFCF8F5);
  static final List<_DurationOption> _durationOptions = [
    for (final durationMinutes in selectableFixedServiceDurations)
      _DurationOption(
        label: formatServiceDurationLabel(
          durationMinutes: durationMinutes,
          schedulingMode: serviceSchedulingModeFixedDuration,
        ),
        schedulingMode: serviceSchedulingModeFixedDuration,
        durationMinutes: durationMinutes,
      ),
    const _DurationOption(
      label: 'Day care',
      schedulingMode: serviceSchedulingModeDayCare,
    ),
    const _DurationOption(
      label: 'Overnight',
      schedulingMode: serviceSchedulingModeOvernight,
    ),
    const _DurationOption(
      label: '24 hours',
      schedulingMode: serviceSchedulingModeTwentyFourHours,
    ),
  ];

  static const List<String> _days = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static const List<String> _serviceTypeOptions = [
    'At provider location',
    'Home visit available',
  ];

  final GlobalKey _durationFieldKey = GlobalKey();
  final GlobalKey _availabilitySectionKey = GlobalKey();
  final GlobalKey _serviceTypeFieldKey = GlobalKey();
  final GlobalKey _locationFieldKey = GlobalKey();

  _DurationOption? _selectedDurationOption;
  int _capacity = 1;
  final Set<String> _selectedDays = {'Mon', 'Tue', 'Wed', 'Thu', 'Fri'};
  int? _startMinutes = 9 * 60;
  int? _endMinutes = 17 * 60;
  String? _selectedServiceType = _serviceTypeOptions.first;
  ServiceLocation? _selectedLocation;
  bool _isLoadingLocation = true;
  String? _locationStatusMessage;

  String? _durationError;
  String? _availabilityError;
  String? _serviceTypeError;
  String? _locationError;
  _BookingSetupField? _highlightedField;

  // Prepared for future business rules: when confirmed bookings exist, some
  // fields should become immutable to avoid invalidating booked slots.
  final bool _hasConfirmedBookings = false;

  @override
  void initState() {
    super.initState();
    _selectedDurationOption = _durationOptions.firstWhere(
      (option) => option.durationMinutes == 60,
      orElse: () => _durationOptions.first,
    );
    _loadInitialLocation();
  }

  @override
  void dispose() {
    super.dispose();
  }

  bool get _isFormValid {
    final location = _selectedLocation;

    return _selectedDurationOption != null &&
        _capacity >= 1 &&
        _selectedDays.isNotEmpty &&
        _startMinutes != null &&
        _hasValidTimeWindow &&
        _selectedServiceType != null &&
        location != null &&
        location.displayAddress.trim().isNotEmpty;
  }

  String? get _selectedDurationLabel => _selectedDurationOption?.label;

  String? get _selectedSchedulingMode =>
      _selectedDurationOption?.schedulingMode;

  bool get _isOvernightMode =>
      _selectedSchedulingMode == serviceSchedulingModeOvernight;

  bool get _isTwentyFourHourMode =>
      _selectedSchedulingMode == serviceSchedulingModeTwentyFourHours;

  bool get _requiresEndTimePicker => !_isTwentyFourHourMode;

  int? get _storedEndMinutes =>
      _isTwentyFourHourMode ? _startMinutes : _endMinutes;

  bool get _hasValidTimeWindow {
    return validateServiceSchedulingSetup(
      schedulingMode: _selectedSchedulingMode,
      sessionDurationMinutes: _selectedDurationMinutes,
      startMinutes: _startMinutes,
      endMinutes: _storedEndMinutes,
      availableDays: _selectedDays,
    ).isValid;
  }

  int? get _selectedDurationMinutes {
    final option = _selectedDurationOption;
    final start = _startMinutes;
    final end = _storedEndMinutes;
    if (option == null) return null;
    if (option.schedulingMode == serviceSchedulingModeTwentyFourHours) {
      if (start == null) return null;
      return 24 * 60;
    }
    if (option.schedulingMode == serviceSchedulingModeOvernight) {
      if (start == null || end == null) return null;
      final duration = deriveOvernightDurationMinutes(
        startMinutes: start,
        endMinutes: end,
      );
      if (duration == null || duration <= 0 || duration >= 24 * 60) {
        return null;
      }
      return duration;
    }
    if (option.schedulingMode == serviceSchedulingModeDayCare) {
      if (start == null || end == null || end <= start) return null;
      return end - start;
    }
    return option.durationMinutes;
  }

  String get _durationHelperText {
    final schedulingMode = _selectedSchedulingMode;
    if (schedulingMode == null) {
      return 'Choose how booking slots should be created for each available day.';
    }
    return serviceDurationHelperText(schedulingMode: schedulingMode);
  }

  String? get _availabilityValidationMessage {
    if (_startMinutes == null) {
      return _requiresEndTimePicker
          ? 'Start and end time are required'
          : 'Start time is required';
    }
    if (_requiresEndTimePicker && _endMinutes == null) {
      return 'Start and end time are required';
    }
    if (_isTwentyFourHourMode) {
      return null;
    }
    final validation = validateServiceSchedulingSetup(
      schedulingMode: _selectedSchedulingMode,
      sessionDurationMinutes: _selectedDurationMinutes,
      startMinutes: _startMinutes,
      endMinutes: _storedEndMinutes,
      availableDays: _selectedDays,
    );
    if (validation.isValid) return null;
    if (_isOvernightMode) {
      return 'Overnight end time must be on the next day and less than 24 hours after the start time';
    }
    return 'End time must be after start time';
  }

  List<String> get _slotPreview {
    final schedulingMode = _selectedSchedulingMode;
    final duration = _selectedDurationMinutes;
    final start = _startMinutes;
    final end = _storedEndMinutes;
    if (schedulingMode == null || duration == null || start == null) {
      return const [];
    }

    if (schedulingMode == serviceSchedulingModeTwentyFourHours) {
      return ['${_formatTime(start)} - ${_formatTime(start)} next day'];
    }

    if (end == null) return const [];

    if (schedulingMode == serviceSchedulingModeOvernight) {
      final overnightDuration = deriveOvernightDurationMinutes(
        startMinutes: start,
        endMinutes: end,
      );
      if (overnightDuration == null ||
          overnightDuration <= 0 ||
          overnightDuration >= 24 * 60) {
        return const [];
      }
      return ['${_formatTime(start)} - ${_formatTime(end)} next day'];
    }

    if (end <= start) return const [];

    if (schedulingMode == serviceSchedulingModeDayCare) {
      return ['${_formatTime(start)} - ${_formatTime(end)}'];
    }

    final slots = <String>[];
    var cursor = start;

    // Backend booking logic enforces lead-time rules like "slot must
    // start at least 1 hour in the future". For now this preview stays local.
    while (cursor + duration <= end) {
      final slotEnd = cursor + duration;
      slots.add('${_formatTime(cursor)} - ${_formatTime(slotEnd)}');
      cursor = slotEnd;
    }

    return slots;
  }

  bool _validateForm() {
    setState(() {
      _durationError = _selectedDurationOption == null
          ? 'Session duration is required'
          : null;
      _availabilityError = _selectedDays.isEmpty
          ? 'Select at least one available day'
          : _availabilityValidationMessage;
      _serviceTypeError = _selectedServiceType == null
          ? 'Service type is required'
          : null;
      _locationError =
          _selectedLocation == null ||
              _selectedLocation!.displayAddress.trim().isEmpty
          ? 'Location is required'
          : null;
    });

    return _isFormValid;
  }

  Future<void> _loadInitialLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationStatusMessage = 'Fetching your current location...';
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _isLoadingLocation = false;
          _locationStatusMessage =
              'Location access required. Please enable location or select manually.';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _isLoadingLocation = false;
          _locationStatusMessage =
              'Location access required. Please enable location or select manually.';
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final address = await _reverseGeocode(
        position.latitude,
        position.longitude,
      );

      if (!mounted) return;
      setState(() {
        _selectedLocation = ServiceLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          displayAddress: address,
        );
        _locationStatusMessage = null;
        _locationError = null;
        _isLoadingLocation = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingLocation = false;
        _locationStatusMessage =
            'Location access required. Please enable location or select manually.';
      });
    }
  }

  Future<String> _reverseGeocode(double latitude, double longitude) async {
    final placemarks = await placemarkFromCoordinates(latitude, longitude);
    if (placemarks.isEmpty) return 'Selected location';

    final place = placemarks.first;
    final parts = [
      place.name,
      place.street,
      place.subLocality,
      place.locality,
      place.administrativeArea,
    ].where((part) => part != null && part.trim().isNotEmpty).cast<String>();

    return parts.take(4).join(', ');
  }

  Future<void> _changeLocation() async {
    final initialLocation =
        _selectedLocation ??
        const ServiceLocation(
          latitude: 12.9716,
          longitude: 77.5946,
          displayAddress: 'Bangalore, Karnataka',
        );

    final selected = await Navigator.push<ServiceLocation>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ServiceLocationPickerScreen(initialLocation: initialLocation),
      ),
    );

    if (selected == null || !mounted) return;

    setState(() {
      _selectedLocation = selected;
      _locationError = null;
      if (_highlightedField == _BookingSetupField.location) {
        _highlightedField = null;
      }
    });
  }

  Future<void> _editAddress() async {
    final currentLocation = _selectedLocation;
    if (currentLocation == null) return;

    var editedAddress = currentLocation.displayAddress;

    final updatedAddress = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            0,
            12,
            MediaQuery.viewInsetsOf(context).bottom + 12,
          ),
          child: GlassSurface(
            borderRadius: BorderRadius.circular(28),
            backgroundColor: Colors.white.withValues(alpha: 0.92),
            blurSigma: 18,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Edit Address',
                    style: TextStyle(
                      color: AppColors.textDark,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    initialValue: editedAddress,
                    maxLength: 200,
                    maxLines: 3,
                    onChanged: (value) {
                      editedAddress = value;
                    },
                    decoration: InputDecoration(
                      hintText: 'Add apartment, floor, or landmark',
                      filled: true,
                      fillColor: const Color(0xFFFCFBFA),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          label: 'Cancel',
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GradientButton(
                          label: 'Save',
                          onPressed: () =>
                              Navigator.pop(context, editedAddress.trim()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (updatedAddress == null || updatedAddress.isEmpty || !mounted) return;

    setState(() {
      _selectedLocation = currentLocation.copyWith(
        displayAddress: updatedAddress,
      );
      _locationError = null;
      if (_highlightedField == _BookingSetupField.location) {
        _highlightedField = null;
      }
    });
  }

  _BookingFieldIssue? _firstInvalidField() {
    if (_selectedDurationOption == null) {
      return _BookingFieldIssue(
        field: _BookingSetupField.duration,
        key: _durationFieldKey,
        message: 'Select a session duration to continue.',
      );
    }

    if (_selectedDays.isEmpty) {
      return _BookingFieldIssue(
        field: _BookingSetupField.availability,
        key: _availabilitySectionKey,
        message: 'Choose at least one available day.',
      );
    }

    final availabilityMessage = _availabilityValidationMessage;
    if (availabilityMessage != null) {
      return _BookingFieldIssue(
        field: _BookingSetupField.availability,
        key: _availabilitySectionKey,
        message: availabilityMessage,
      );
    }

    if (_selectedServiceType == null) {
      return _BookingFieldIssue(
        field: _BookingSetupField.serviceType,
        key: _serviceTypeFieldKey,
        message: 'Select a service type.',
      );
    }

    if (_selectedLocation == null ||
        _selectedLocation!.displayAddress.trim().isEmpty) {
      return _BookingFieldIssue(
        field: _BookingSetupField.location,
        key: _locationFieldKey,
        message: 'Select a location to continue.',
      );
    }

    return null;
  }

  Future<void> _showFieldGuidance(_BookingFieldIssue issue) async {
    setState(() {
      _highlightedField = issue.field;
    });

    AppFeedback.show(
      context,
      message: issue.message,
      tone: AppFeedbackTone.info,
    );

    final fieldContext = issue.key.currentContext;
    if (fieldContext != null) {
      await Scrollable.ensureVisible(
        fieldContext,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.18,
      );
    }
  }

  Future<void> _handleNextPress() async {
    if (_validateForm()) {
      await _goToNext();
      return;
    }

    final issue = _firstInvalidField();
    if (issue != null) {
      await _showFieldGuidance(issue);
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final currentMinutes = isStart ? _startMinutes : _storedEndMinutes;
    final initialTime = currentMinutes == null
        ? const TimeOfDay(hour: 9, minute: 0)
        : TimeOfDay(hour: currentMinutes ~/ 60, minute: currentMinutes % 60);

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        final theme = Theme.of(context);
        final mediaQuery = MediaQuery.of(context);
        final size = mediaQuery.size;
        final compact = size.width < 390 || size.height < 780;
        return Theme(
          data: theme.copyWith(
            dialogTheme: const DialogThemeData(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
            ),
            colorScheme: theme.colorScheme.copyWith(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.transparent,
              onSurface: AppColors.textDark,
            ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              helpTextStyle: const TextStyle(
                color: AppColors.textDark,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
              hourMinuteTextColor: AppColors.textDark,
              hourMinuteTextStyle: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w700,
              ),
              hourMinuteColor: Colors.white.withValues(alpha: 0.58),
              dayPeriodColor: WidgetStateColor.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppColors.primary.withValues(alpha: 0.18);
                }
                return Colors.white.withValues(alpha: 0.58);
              }),
              dayPeriodTextColor: WidgetStateColor.resolveWith((states) {
                return AppColors.primary;
              }),
              dayPeriodShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.20),
                ),
              ),
              dialBackgroundColor: Colors.white.withValues(alpha: 0.52),
              dialHandColor: AppColors.primary,
              dialTextColor: AppColors.textDark,
              entryModeIconColor: AppColors.textGrey,
              cancelButtonStyle: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              confirmButtonStyle: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          child: MediaQuery(
            data: mediaQuery.copyWith(
              alwaysUse24HourFormat: false,
              textScaler: mediaQuery.textScaler.clamp(
                minScaleFactor: 0.88,
                maxScaleFactor: 1,
              ),
            ),
            child: AppGlassDialogFrame(
              maxWidth: compact ? size.width - 28 : 410,
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(compact ? 24 : 30),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(compact ? 24 : 30),
                child: SizedBox(
                  width: compact ? size.width - 52 : null,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: child!,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (picked == null || !mounted) return;

    final roundedMinutes = _roundToQuarterHour(
      picked.hour * 60 + picked.minute,
    );

    setState(() {
      if (isStart) {
        _startMinutes = roundedMinutes;
        if (_isTwentyFourHourMode) {
          _endMinutes = roundedMinutes;
        }
      } else {
        _endMinutes = roundedMinutes;
      }
      _availabilityError = null;
    });
  }

  int _roundToQuarterHour(int totalMinutes) {
    final remainder = totalMinutes % 15;
    if (remainder == 0) return totalMinutes;
    final rounded = totalMinutes + (15 - remainder);
    return rounded > (23 * 60 + 45) ? 23 * 60 + 45 : rounded;
  }

  String _formatTime(int? totalMinutes) {
    if (totalMinutes == null) return 'Select time';
    final hour = totalMinutes ~/ 60;
    final minute = totalMinutes % 60;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $suffix';
  }

  Future<void> _goToNext() async {
    if (!_validateForm()) return;

    final bookingSetupDraft = ServiceBookingSetupDraft(
      sessionDurationMinutes: _selectedDurationMinutes!,
      schedulingMode: _selectedSchedulingMode!,
      hasConfirmedBookings: _hasConfirmedBookings,
      capacity: _capacity,
      availableDays: _days.where(_selectedDays.contains).toList(),
      startMinutes: _startMinutes!,
      endMinutes: _storedEndMinutes!,
      sameForAllDays: true,
      serviceType: _selectedServiceType!,
      location: _selectedLocation!,
    );

    final flowDraft = AddServiceFlowDraft(
      details: widget.draft,
      bookingSetup: bookingSetupDraft,
    );

    final published = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddServiceAdditionalDetailsScreen(draft: flowDraft),
      ),
    );

    if (published == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final topContentPadding =
        MediaQuery.paddingOf(context).top + AddServiceFlowHeader.contentHeight;

    return Scaffold(
      backgroundColor: _screenBackground,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            ListView(
              padding: EdgeInsets.fromLTRB(
                18,
                topContentPadding,
                18,
                bottomInset + 28,
              ),
              children: [
                const _IntroCard(
                  subtitle:
                      'This information controls availability, capacity, cancellations, and visibility.',
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  title: 'Session Setup',
                  children: [
                    _DropdownField(
                      fieldKey: _durationFieldKey,
                      label: 'Session duration',
                      value: _selectedDurationLabel,
                      options: _durationOptions
                          .map((option) => option.label)
                          .toList(),
                      helperText: _hasConfirmedBookings
                          ? 'Duration cannot be changed while bookings exist.'
                          : _durationHelperText,
                      errorText: _durationError,
                      isHighlighted:
                          _highlightedField == _BookingSetupField.duration,
                      enabled: !_hasConfirmedBookings,
                      onChanged: (value) {
                        setState(() {
                          final nextOption = _durationOptions.firstWhere(
                            (option) => option.label == value,
                            orElse: () => _selectedDurationOption!,
                          );
                          _selectedDurationOption = nextOption;
                          if (nextOption.schedulingMode ==
                              serviceSchedulingModeTwentyFourHours) {
                            _endMinutes = _startMinutes;
                          }
                          _durationError = null;
                          _availabilityError = null;
                          if (_highlightedField ==
                              _BookingSetupField.duration) {
                            _highlightedField = null;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 18),
                    _CapacityStepper(
                      value: _capacity,
                      onDecrement: _capacity > 1
                          ? () => setState(() => _capacity -= 1)
                          : null,
                      onIncrement: () => setState(() => _capacity += 1),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  title: 'Availability',
                  sectionKey: _availabilitySectionKey,
                  errorText: _availabilityError,
                  isHighlighted:
                      _highlightedField == _BookingSetupField.availability,
                  children: [
                    const Text(
                      'Availability',
                      style: TextStyle(
                        color: AppColors.textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _days.map((day) {
                        final selected = _selectedDays.contains(day);
                        return FilterChip(
                          label: Text(day),
                          selected: selected,
                          onSelected: (value) {
                            setState(() {
                              if (value) {
                                _selectedDays.add(day);
                              } else {
                                _selectedDays.remove(day);
                              }
                              _availabilityError = null;
                              if (_highlightedField ==
                                  _BookingSetupField.availability) {
                                _highlightedField = null;
                              }
                            });
                          },
                          backgroundColor: Colors.white,
                          selectedColor: AppColors.primary.withValues(
                            alpha: 0.12,
                          ),
                          checkmarkColor: AppColors.primary,
                          side: BorderSide(
                            color: selected
                                ? AppColors.primary.withValues(alpha: 0.26)
                                : AppColors.primary.withValues(alpha: 0.10),
                          ),
                          labelStyle: TextStyle(
                            color: selected
                                ? AppColors.primary
                                : AppColors.textDark,
                            fontWeight: FontWeight.w600,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _TimePickerField(
                            label: 'Start time',
                            value: _formatTime(_startMinutes),
                            isHighlighted:
                                _highlightedField ==
                                _BookingSetupField.availability,
                            onTap: () async {
                              await _pickTime(isStart: true);
                              if (!mounted) return;
                              if (_highlightedField ==
                                  _BookingSetupField.availability) {
                                setState(() => _highlightedField = null);
                              }
                            },
                          ),
                        ),
                        if (_requiresEndTimePicker) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TimePickerField(
                              label: _isOvernightMode
                                  ? 'End time (next day)'
                                  : 'End time',
                              value: _formatTime(_endMinutes),
                              isHighlighted:
                                  _highlightedField ==
                                  _BookingSetupField.availability,
                              onTap: () async {
                                await _pickTime(isStart: false);
                                if (!mounted) return;
                                if (_highlightedField ==
                                    _BookingSetupField.availability) {
                                  setState(() => _highlightedField = null);
                                }
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_isTwentyFourHourMode) ...[
                      const SizedBox(height: 12),
                      Text(
                        _startMinutes == null
                            ? 'Ends automatically 24 hours after the selected start time.'
                            : 'Ends automatically at ${_formatTime(_startMinutes)} the next day.',
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  title: 'Slot Preview',
                  children: [
                    const Text(
                      'This is a frontend helper preview of how slots will be generated from your duration mode and availability.',
                      style: TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_slotPreview.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFCFBFA),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          'Select a valid duration mode and time window to preview generated slots.',
                          style: TextStyle(
                            color: AppColors.textGrey,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      )
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var i = 0; i < _slotPreview.length; i++) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.10,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  _slotPreview[i],
                                  style: const TextStyle(
                                    color: AppColors.textDark,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (i != _slotPreview.length - 1)
                                const SizedBox(width: 10),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  title: 'Service Type & Location',
                  children: [
                    _RadioGroupField(
                      fieldKey: _serviceTypeFieldKey,
                      label: 'Service type',
                      options: _serviceTypeOptions,
                      value: _selectedServiceType,
                      helperText: _hasConfirmedBookings
                          ? 'Service type cannot be changed while bookings exist.'
                          : null,
                      errorText: _serviceTypeError,
                      isHighlighted:
                          _highlightedField == _BookingSetupField.serviceType,
                      enabled: !_hasConfirmedBookings,
                      onChanged: (value) {
                        setState(() {
                          _selectedServiceType = value;
                          _serviceTypeError = null;
                          if (_highlightedField ==
                              _BookingSetupField.serviceType) {
                            _highlightedField = null;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 18),
                    ServiceLocationCard(
                      key: _locationFieldKey,
                      location: _selectedLocation,
                      isLoading: _isLoadingLocation,
                      statusMessage: _locationStatusMessage,
                      isHighlighted:
                          _highlightedField == _BookingSetupField.location,
                      helperText:
                          'Used for discovery and slot availability. Exact address is shared only after booking is confirmed.',
                      errorText: _locationError,
                      onChangeLocation: _changeLocation,
                      onEditAddress: _editAddress,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Stack(
                  children: [
                    GradientButton(
                      label: 'Next',
                      onPressed: _isFormValid ? _handleNextPress : null,
                    ),
                    if (!_isFormValid)
                      Positioned.fill(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: _handleNextPress,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            AddServiceFlowHeader(
              title: 'Booking Setup',
              onBack: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  final String subtitle;

  const _IntroCard({required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Key? sectionKey;
  final String title;
  final String? errorText;
  final bool isHighlighted;
  final List<Widget> children;

  const _SectionCard({
    this.sectionKey,
    required this.title,
    required this.children,
    this.errorText,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: sectionKey,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: isHighlighted
              ? AppColors.primary
              : AppColors.primary.withValues(alpha: 0.08),
          width: isHighlighted ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              errorText!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  final Key? fieldKey;
  final String label;
  final String? value;
  final List<String> options;
  final String? helperText;
  final String? errorText;
  final bool isHighlighted;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  const _DropdownField({
    this.fieldKey,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.helperText,
    this.errorText,
    this.isHighlighted = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: fieldKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textGrey,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: enabled
              ? () async {
                  FocusManager.instance.primaryFocus?.unfocus();
                  final selected = await showModalBottomSheet<String>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    builder: (context) {
                      return _SelectionSheet(
                        title: label,
                        options: options,
                        selectedValue: value,
                      );
                    },
                  );
                  if (selected != null) {
                    onChanged(selected);
                  }
                }
              : null,
          borderRadius: BorderRadius.circular(18),
          child: InputDecorator(
            decoration: InputDecoration(
              helperText: helperText,
              errorText: errorText,
              filled: true,
              fillColor: enabled
                  ? const Color(0xFFFCFBFA)
                  : Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: isHighlighted
                    ? const BorderSide(color: AppColors.primary, width: 1.6)
                    : BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: isHighlighted
                    ? const BorderSide(color: AppColors.primary, width: 1.6)
                    : BorderSide.none,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value ?? 'Select duration',
                    style: TextStyle(
                      color: value == null
                          ? AppColors.textGrey
                          : AppColors.textDark,
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
      ],
    );
  }
}

class _CapacityStepper extends StatelessWidget {
  final int value;
  final VoidCallback? onDecrement;
  final VoidCallback onIncrement;

  const _CapacityStepper({
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How many bookings can you handle at the same time?',
          style: TextStyle(
            color: AppColors.textGrey,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFCFBFA),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              _StepperButton(icon: Icons.remove_rounded, onTap: onDecrement),
              Expanded(
                child: Center(
                  child: Text(
                    '$value',
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              _StepperButton(icon: Icons.add_rounded, onTap: onIncrement),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Individual service (e.g. home visit) -> 1\nSalon or team -> 3 to 5',
          style: TextStyle(
            color: AppColors.textGrey,
            fontSize: 12.5,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: onTap == null
              ? Colors.grey.shade200
              : AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: onTap == null ? Colors.grey : AppColors.primary,
        ),
      ),
    );
  }
}

class _TimePickerField extends StatelessWidget {
  final String label;
  final String value;
  final bool isHighlighted;
  final VoidCallback onTap;

  const _TimePickerField({
    required this.label,
    required this.value,
    this.isHighlighted = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textGrey,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            onTap();
          },
          borderRadius: BorderRadius.circular(18),
          child: GlassSurface(
            borderRadius: BorderRadius.circular(18),
            blurSigma: 20,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            backgroundColor: Colors.white.withValues(alpha: 0.60),
            border: Border.all(
              color: isHighlighted
                  ? AppColors.primary
                  : Colors.white.withValues(alpha: 0.64),
              width: isHighlighted ? 1.6 : 1,
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
                const Icon(Icons.schedule_rounded, color: AppColors.textGrey),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RadioGroupField extends StatelessWidget {
  final Key? fieldKey;
  final String label;
  final List<String> options;
  final String? value;
  final String? helperText;
  final String? errorText;
  final bool isHighlighted;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  const _RadioGroupField({
    this.fieldKey,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.helperText,
    this.errorText,
    this.isHighlighted = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: fieldKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textGrey,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        ...options.map((option) {
          final isSelected = value == option;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: enabled ? () => onChanged(option) : null,
              borderRadius: BorderRadius.circular(18),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : const Color(0xFFFCFBFA),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isHighlighted
                        ? AppColors.primary
                        : isSelected
                        ? AppColors.primary.withValues(alpha: 0.32)
                        : AppColors.primary.withValues(alpha: 0.08),
                    width: isHighlighted ? 1.4 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    _RadioDot(isSelected: isSelected),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        option,
                        style: TextStyle(
                          color: enabled
                              ? AppColors.textDark
                              : AppColors.textGrey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        if (helperText != null)
          Text(
            helperText!,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              errorText!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _SelectionSheet extends StatelessWidget {
  final String title;
  final List<String> options;
  final String? selectedValue;

  const _SelectionSheet({
    required this.title,
    required this.options,
    required this.selectedValue,
  });

  @override
  Widget build(BuildContext context) {
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.7;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(28),
        backgroundColor: Colors.white.withValues(alpha: 0.92),
        blurSigma: 18,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxSheetHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final option = options[index];
                      final isSelected = option == selectedValue;
                      return InkWell(
                        onTap: () => Navigator.pop(context, option),
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.08)
                                : const Color(0xFFFCFBFA),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary.withValues(alpha: 0.30)
                                  : AppColors.primary.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  option,
                                  style: const TextStyle(
                                    color: AppColors.textDark,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_rounded,
                                  color: AppColors.primary,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  final bool isSelected;

  const _RadioDot({required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.textGrey,
          width: 1.4,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? AppColors.primary : Colors.transparent,
        ),
      ),
    );
  }
}

class _DurationOption {
  final String label;
  final String schedulingMode;
  final int? durationMinutes;

  const _DurationOption({
    required this.label,
    required this.schedulingMode,
    this.durationMinutes,
  });
}

enum _BookingSetupField { duration, availability, serviceType, location }

class _BookingFieldIssue {
  final _BookingSetupField field;
  final GlobalKey key;
  final String message;

  const _BookingFieldIssue({
    required this.field,
    required this.key,
    required this.message,
  });
}
