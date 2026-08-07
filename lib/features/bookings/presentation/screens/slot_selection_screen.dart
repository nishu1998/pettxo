import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/service_duration.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../restrictions/data/services/user_restriction_service.dart';
import '../../data/repositories/booking_repository.dart';
import '../../domain/models/booking_v3_models.dart';
import '../../domain/models/canonical_booking_request_models.dart';
import '../../domain/models/service_slot_model.dart';
import '../../domain/utils/booking_runway.dart';
import '../../domain/utils/booking_request_attempt_id.dart';
import 'canonical_booking_request_review_screen.dart';

class SlotSelectionScreen extends StatefulWidget {
  final String serviceId;
  final String serviceName;
  final int price;
  final int durationMinutes;
  final String schedulingMode;
  final String providerId;
  final DateTime? suggestedSlotStartAt;
  final String providerName;
  final String serviceImageUrl;

  const SlotSelectionScreen({
    super.key,
    required this.serviceId,
    required this.serviceName,
    required this.price,
    required this.durationMinutes,
    required this.schedulingMode,
    required this.providerId,
    this.suggestedSlotStartAt,
    this.providerName = '',
    this.serviceImageUrl = '',
  });

  @override
  State<SlotSelectionScreen> createState() => _SlotSelectionScreenState();
}

class _SlotSelectionScreenState extends State<SlotSelectionScreen> {
  static const Color _screenBackground = Color(0xFFFCF8F5);
  static const Duration _availabilityRefreshInterval = Duration(minutes: 1);
  static const int _maxSelectedServiceDays = 10;
  late DateTime _selectedDate;
  late DateTime _focusedMonth;
  final Map<String, List<ServiceSlotModel>> _selectedSlotsByDate =
      <String, List<ServiceSlotModel>>{};
  final BookingRequestAttemptIdController _requestAttemptIdController =
      BookingRequestAttemptIdController();
  String? _slotError;
  Timer? _availabilityTicker;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final suggestedDate = widget.suggestedSlotStartAt?.toLocal();
    final normalizedToday = DateTime(now.year, now.month, now.day);
    final normalizedSuggested = suggestedDate == null
        ? null
        : DateTime(suggestedDate.year, suggestedDate.month, suggestedDate.day);
    final lastSelectableDate = normalizedToday.add(const Duration(days: 30));
    final canUseSuggestedDate =
        normalizedSuggested != null &&
        !normalizedSuggested.isBefore(normalizedToday) &&
        !normalizedSuggested.isAfter(lastSelectableDate);
    _selectedDate = canUseSuggestedDate ? normalizedSuggested : normalizedToday;
    _focusedMonth = DateTime(_selectedDate.year, _selectedDate.month);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!UserRestrictionService.instance.ensureCanUseBookingFeatures(
        context,
      )) {
        Navigator.maybePop(context);
      }
    });
    _availabilityTicker = Timer.periodic(_availabilityRefreshInterval, (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  DateTime get _today {
    final now = _authoritativeNow;
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _authoritativeNow => DateTime.now();

  DateTime get _lastSelectableDate => _today.add(const Duration(days: 30));

  String get _effectiveTimezone => 'Asia/Kolkata';

  int get _canonicalUnitPricePaise => widget.price * 100;

  bool get _canGoToPreviousMonth {
    final currentMonth = DateTime(_today.year, _today.month);
    return _focusedMonth.isAfter(currentMonth);
  }

  bool get _canGoToNextMonth {
    final lastMonth = DateTime(
      _lastSelectableDate.year,
      _lastSelectableDate.month,
    );
    return _focusedMonth.isBefore(lastMonth);
  }

  bool _isSelectableDate(DateTime date) {
    return !date.isBefore(_today) && !date.isAfter(_lastSelectableDate);
  }

  void _moveMonth(int delta) {
    final next = DateTime(_focusedMonth.year, _focusedMonth.month + delta);
    final earliest = DateTime(_today.year, _today.month);
    final latest = DateTime(
      _lastSelectableDate.year,
      _lastSelectableDate.month,
    );
    if (next.isBefore(earliest) || next.isAfter(latest)) return;
    var nextSelectedDate = next;
    if (nextSelectedDate.isBefore(_today)) nextSelectedDate = _today;
    if (nextSelectedDate.isAfter(_lastSelectableDate)) {
      nextSelectedDate = _lastSelectableDate;
    }
    setState(() {
      _focusedMonth = next;
      _selectedDate = nextSelectedDate;
      _slotError = null;
    });
  }

  void _continue() {
    if (!UserRestrictionService.instance.ensureCanUseBookingFeatures(context)) {
      return;
    }
    if (!_hasValidSelection) {
      setState(() {
        _slotError = 'Choose at least one available slot.';
      });
      return;
    }
    final normalizedSelection = _normalizedSelection;
    if (normalizedSelection == null || normalizedSelection.slots.isEmpty) {
      setState(() {
        _slotError = 'Choose continuous slots on consecutive service days.';
      });
      return;
    }
    final estimatedSubtotalPaise =
        normalizedSelection.slotCount * _canonicalUnitPricePaise;
    final selectedDays = _buildSelectedDaysPayload(normalizedSelection);
    final requestInput = CanonicalBookingRequestInput(
      requestAttemptId: _requestAttemptIdController.idForPayload(
        _canonicalPayloadKey(normalizedSelection),
      ),
      serviceId: widget.serviceId,
      bookingType: BookingV3Type.slot,
      slotRequest: CanonicalSlotRequestInput(
        selection: normalizedSelection,
        estimatedSubtotalPaise: estimatedSubtotalPaise,
        selectedDays: selectedDays.length > 1 ? selectedDays : null,
      ),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CanonicalBookingRequestReviewScreen(
          input: requestInput,
          serviceName: widget.serviceName,
          providerName: widget.providerName,
          serviceImageUrl: widget.serviceImageUrl,
          timezone: _effectiveTimezone,
          schedulingMode: widget.schedulingMode,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _availabilityTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _screenBackground,
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              topInset + 76,
              16,
              bottomInset + 112,
            ),
            children: [
              _ServiceSummaryCard(
                title: widget.serviceName,
                providerName: widget.providerName,
                durationLabel: formatServiceDurationLabel(
                  durationMinutes: widget.durationMinutes,
                  schedulingMode: widget.schedulingMode,
                ),
                price: widget.price,
                imageUrl: widget.serviceImageUrl,
              ),
              const SizedBox(height: 18),
              _CalendarMonthSection(
                today: _today,
                lastSelectableDate: _lastSelectableDate,
                displayedMonth: _focusedMonth,
                selectedDate: _selectedDate,
                canGoPrevious: _canGoToPreviousMonth,
                canGoNext: _canGoToNextMonth,
                onPrevious: () => _moveMonth(-1),
                onNext: () => _moveMonth(1),
                onMiddleDateChanged: (date) {
                  final month = DateTime(date.year, date.month);
                  if (_focusedMonth == month) return;
                  setState(() => _focusedMonth = month);
                },
                onDateSelected: (date) {
                  if (!_isSelectableDate(date)) return;
                  setState(() {
                    _selectedDate = date;
                    _focusedMonth = DateTime(date.year, date.month);
                    _slotError = null;
                  });
                },
                isSelectable: _isSelectableDate,
                isSameDay: _isSameDay,
              ),
              const SizedBox(height: 22),
              const Text(
                'Choose continuous slots on consecutive days',
                style: TextStyle(
                  color: AppColors.textDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Nothing will be charged now. Pick up to 10 consecutive service days and your selection will stay unreserved until payment succeeds.',
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              StreamBuilder<List<ServiceSlotModel>>(
                stream: BookingRepository().watchServiceSlotsForDate(
                  serviceId: widget.serviceId,
                  date: _selectedDate,
                ),
                builder: (context, snapshot) =>
                    _buildSlotSelector(context, snapshot),
              ),
              const SizedBox(height: 14),
              if (_normalizedSelection != null) ...[
                _CanonicalSelectionSummaryCard(
                  selection: _normalizedSelection!,
                  unitPricePaise: _canonicalUnitPricePaise,
                  schedulingMode: widget.schedulingMode,
                ),
                const SizedBox(height: 14),
              ],
              const _CanonicalRequestInfoBanner(),
            ],
          ),
          _SlotTopBar(
            topInset: topInset,
            title: 'Request slots',
            onBack: () => Navigator.pop(context),
          ),
          _SlotBottomBar(
            bottomInset: bottomInset,
            isReady: _hasValidSelection,
            label: 'Review request',
            onContinue: _continue,
          ),
        ],
      ),
    );
  }

  Widget _buildSlotSelector(
    BuildContext context,
    AsyncSnapshot<List<ServiceSlotModel>> snapshot,
  ) {
    if (snapshot.hasError) {
      return const _SlotStateMessage(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load slots',
        subtitle: 'Please go back and try again in a moment.',
      );
    }

    if (snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData) {
      return const _SlotLoadingState();
    }

    final slots = snapshot.data ?? const <ServiceSlotModel>[];
    _pruneInvalidSelection(slots);
    _selectSuggestedSlotIfNeeded(slots);

    if (slots.isEmpty) {
      return const _SlotStateMessage(
        icon: Icons.event_busy_outlined,
        title: 'No slots for this date',
        subtitle: 'Try another day from the date selector above.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SlotRail(
          slots: slots,
          selectedSlotId: null,
          selectedSlotIds: _selectedSlotsForDate(
            _selectedDateKey,
          ).map((slot) => slot.id).toSet(),
          allowMultiSelect: true,
          isSlotBookable: _isSlotBookable,
          onSlotSelected: _handleSlotTapped,
        ),
        const SizedBox(height: 12),
        const Row(
          children: [
            Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: AppColors.textGrey,
            ),
            SizedBox(width: 7),
            Text(
              'Swipe for more slots',
              style: TextStyle(
                color: AppColors.textGrey,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        if (_slotError != null) ...[
          const SizedBox(height: 10),
          Text(
            _slotError!,
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }

  void _selectSuggestedSlotIfNeeded(List<ServiceSlotModel> slots) {
    if (_allSelectedSlots.isNotEmpty ||
        widget.suggestedSlotStartAt == null ||
        !_isSameDay(widget.suggestedSlotStartAt!, _selectedDate)) {
      return;
    }

    final suggestedLocal = widget.suggestedSlotStartAt!.toLocal();
    final suggestedSlot = slots
        .where((slot) {
          final slotLocal = slot.startAt.toLocal();
          return _isSlotBookable(slot) &&
              slotLocal.year == suggestedLocal.year &&
              slotLocal.month == suggestedLocal.month &&
              slotLocal.day == suggestedLocal.day &&
              slotLocal.hour == suggestedLocal.hour &&
              slotLocal.minute == suggestedLocal.minute;
        })
        .cast<ServiceSlotModel?>()
        .firstWhere((slot) => slot != null, orElse: () => null);
    if (suggestedSlot == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _allSelectedSlots.any((slot) => slot.id == suggestedSlot.id)) {
        return;
      }
      setState(() {
        _selectedSlotsByDate[_selectedDateKey] = <ServiceSlotModel>[
          suggestedSlot,
        ];
        _slotError = null;
      });
    });
  }

  void _handleSlotTapped(ServiceSlotModel slot) {
    if (!_isSlotBookable(slot)) return;
    _toggleCanonicalSlot(slot);
  }

  void _toggleCanonicalSlot(ServiceSlotModel slot) {
    final targetDateKey = _serviceDateKeyForSlot(slot);
    final currentDateSelection = [..._selectedSlotsForDate(targetDateKey)];
    final existingIndex = currentDateSelection.indexWhere(
      (entry) => entry.id == slot.id,
    );
    if (existingIndex >= 0) {
      final removingLastSlotForDate = currentDateSelection.length == 1;
      if (removingLastSlotForDate &&
          _wouldSplitSelectionOnDateRemoval(targetDateKey)) {
        setState(() {
          _slotError =
              'Remove a selection from the first or last chosen day before removing this middle day.';
        });
        return;
      }
      currentDateSelection.removeAt(existingIndex);
      setState(() {
        if (currentDateSelection.isEmpty) {
          _selectedSlotsByDate.remove(targetDateKey);
        } else {
          _selectedSlotsByDate[targetDateKey] = _sortSlots(
            currentDateSelection,
          );
        }
        _slotError = null;
      });
      return;
    }

    final addDecision = _canAddServiceDate(targetDateKey);
    if (!addDecision.allowed) {
      setState(() {
        _slotError = addDecision.message;
      });
      return;
    }
    currentDateSelection.add(slot);
    if (!_isSelectionStillBookable(currentDateSelection)) {
      setState(() {
        _slotError = 'Please choose a slot that is still available to request.';
      });
      return;
    }

    final nextSelectionByDate = _cloneSelectionByDate();
    nextSelectionByDate[targetDateKey] = _sortSlots(currentDateSelection);
    final selection = _buildCanonicalSelection(nextSelectionByDate);
    if (selection == null) {
      setState(() {
        _slotError = 'We could not prepare those slots. Please try again.';
      });
      return;
    }
    final validation = validateSlotBookingSelectionV3(selection);
    if (!validation.ok) {
      setState(() {
        _slotError =
            'Please choose continuous slots on each day without gaps or overlaps.';
      });
      return;
    }

    setState(() {
      _selectedSlotsByDate
        ..clear()
        ..addAll(nextSelectionByDate);
      _slotError = null;
    });
  }

  SlotBookingSelectionV3? _buildCanonicalSelection(
    Map<String, List<ServiceSlotModel>> slotsByDate,
  ) {
    final slots = slotsByDate.values
        .expand((dateSlots) => dateSlots)
        .toList(growable: false);
    if (slots.isEmpty) return null;
    final sorted = _sortSlots(slots);
    final segments = sorted
        .map(
          (slot) => BookingSlotSegmentV3(
            slotId: slot.id,
            serviceId: widget.serviceId,
            providerId: widget.providerId,
            timezone: _effectiveTimezone,
            dateKey: slot.dateKey,
            serviceDateKey: _serviceDateKeyForSlot(slot),
            startAt: slot.startAt,
            endAt: slot.endAt,
            durationMinutes: slot.endAt.difference(slot.startAt).inMinutes,
            unitPricePaise: _canonicalUnitPricePaise,
            schedulingMode: widget.schedulingMode,
          ),
        )
        .toList(growable: false);

    return SlotBookingSelectionV3(
      bookingType: BookingV3Type.slot,
      slots: segments,
      slotCount: segments.length,
      scheduledStartAt: segments.first.startAt,
      scheduledEndAt: segments.last.endAt,
      totalDurationMinutes: segments.fold<int>(
        0,
        (sum, segment) => sum + segment.durationMinutes,
      ),
    );
  }

  String _canonicalPayloadKey(SlotBookingSelectionV3 selection) {
    final segmentKey =
        (selection.segments ?? const <SlotBookingScheduleSegmentV3>[])
            .map(
              (segment) =>
                  '${segment.serviceDateKey}:${segment.slotIds.join("-")}',
            )
            .join('|');
    return '${widget.serviceId}|${widget.providerId}|$segmentKey|${selection.scheduledStartAt.toUtc().toIso8601String()}';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool get _hasValidSelection => _normalizedSelection != null;

  List<ServiceSlotModel> get _allSelectedSlots =>
      _selectedSlotsByDate.values
          .expand((slots) => slots)
          .toList(growable: false)
        ..sort((a, b) => a.startAt.compareTo(b.startAt));

  String get _selectedDateKey => _dateKeyForDate(_selectedDate);

  SlotBookingSelectionV3? get _normalizedSelection {
    if (_selectedSlotsByDate.isEmpty) return null;
    final selection = _buildCanonicalSelection(_selectedSlotsByDate);
    if (selection == null) return null;
    final validation = validateSlotBookingSelectionV3(selection);
    if (!validation.ok) return null;
    return validation.normalizedSelection;
  }

  bool _isSlotBookable(ServiceSlotModel slot) {
    return slot.isOpen &&
        isCanonicalBookingAnchorBookable(
          anchorAt: slot.startAt,
          authoritativeNow: _authoritativeNow,
        );
  }

  bool _isSelectionStillBookable(List<ServiceSlotModel> slots) {
    if (slots.isEmpty) return false;
    final sorted = [...slots]..sort((a, b) => a.startAt.compareTo(b.startAt));
    if (!_isSlotBookable(sorted.first)) {
      return false;
    }
    return sorted.every((slot) => slot.isOpen);
  }

  void _pruneInvalidSelection(List<ServiceSlotModel> availableSlots) {
    final currentDateKey = _selectedDateKey;
    final selectedSlots = _selectedSlotsForDate(currentDateKey);
    if (selectedSlots.isEmpty) return;
    final currentSlotsById = {for (final slot in availableSlots) slot.id: slot};
    final refreshedSelection = selectedSlots
        .map((slot) => currentSlotsById[slot.id])
        .whereType<ServiceSlotModel>()
        .toList(growable: false);
    if (_isSelectionStillBookable(refreshedSelection) &&
        refreshedSelection.length == selectedSlots.length) {
      return;
    }
    final nextSelectionByDate = _cloneSelectionByDate();
    if (refreshedSelection.isEmpty) {
      nextSelectionByDate.remove(currentDateKey);
    } else {
      nextSelectionByDate[currentDateKey] = _sortSlots(refreshedSelection);
    }
    final hasSafeSelectionAfterRefresh =
        nextSelectionByDate.isEmpty ||
        (() {
          final nextSelection = _buildCanonicalSelection(nextSelectionByDate);
          if (nextSelection == null) return false;
          return validateSlotBookingSelectionV3(nextSelection).ok;
        })();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedSlotsByDate
          ..clear()
          ..addAll(
            hasSafeSelectionAfterRefresh ? nextSelectionByDate : const {},
          );
        if (!hasSafeSelectionAfterRefresh) {
          _selectedSlotsByDate.clear();
        }
        _slotError =
            'One or more selected slots are no longer available. Please review your booking.';
      });
    });
  }

  Map<String, List<ServiceSlotModel>> _cloneSelectionByDate() {
    return {
      for (final entry in _selectedSlotsByDate.entries)
        entry.key: [...entry.value]
          ..sort((a, b) => a.startAt.compareTo(b.startAt)),
    };
  }

  List<ServiceSlotModel> _selectedSlotsForDate(String dateKey) {
    return _selectedSlotsByDate[dateKey] ?? const <ServiceSlotModel>[];
  }

  List<ServiceSlotModel> _sortSlots(List<ServiceSlotModel> slots) {
    return [...slots]..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  String _serviceDateKeyForSlot(ServiceSlotModel slot) {
    final key = slot.dateKey.trim();
    if (key.isNotEmpty) return key;
    return _dateKeyForDate(slot.startAt);
  }

  String _dateKeyForDate(DateTime date) {
    final local = date.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  List<String> _sortedSelectedDateKeys() {
    final keys = _selectedSlotsByDate.keys.toList(growable: false);
    keys.sort();
    return keys;
  }

  _DateAddDecision _canAddServiceDate(String dateKey) {
    final selectedDateKeys = _sortedSelectedDateKeys();
    if (selectedDateKeys.isEmpty || selectedDateKeys.contains(dateKey)) {
      return const _DateAddDecision.allowed();
    }
    if (selectedDateKeys.length >= _maxSelectedServiceDays) {
      return const _DateAddDecision.denied(
        'You can choose up to 10 consecutive service days in one booking.',
      );
    }
    final first = DateTime.parse(selectedDateKeys.first);
    final last = DateTime.parse(selectedDateKeys.last);
    final target = DateTime.parse(dateKey);
    final allowedPrevious = first.subtract(const Duration(days: 1));
    final allowedNext = last.add(const Duration(days: 1));
    if (_isSameDay(target, allowedPrevious) ||
        _isSameDay(target, allowedNext)) {
      return const _DateAddDecision.allowed();
    }
    return const _DateAddDecision.denied(
      'Choose the previous or next consecutive service day to extend this booking.',
    );
  }

  bool _wouldSplitSelectionOnDateRemoval(String dateKey) {
    final selectedDateKeys = _sortedSelectedDateKeys();
    if (selectedDateKeys.length <= 2) return false;
    final index = selectedDateKeys.indexOf(dateKey);
    return index > 0 && index < selectedDateKeys.length - 1;
  }

  List<CanonicalSelectedDaySlotInput> _buildSelectedDaysPayload(
    SlotBookingSelectionV3 selection,
  ) {
    final segments =
        selection.segments ?? const <SlotBookingScheduleSegmentV3>[];
    if (segments.isEmpty) {
      final slotIds = selection.slots
          .map((slot) => slot.slotId)
          .toList(growable: false);
      return <CanonicalSelectedDaySlotInput>[
        CanonicalSelectedDaySlotInput(
          serviceDateKey:
              selection.slots.first.serviceDateKey ??
              selection.slots.first.dateKey,
          slotIds: slotIds,
        ),
      ];
    }
    return segments
        .map(
          (segment) => CanonicalSelectedDaySlotInput(
            serviceDateKey: segment.serviceDateKey,
            slotIds: segment.slotIds,
          ),
        )
        .toList(growable: false);
  }
}

class _DateAddDecision {
  final bool allowed;
  final String? message;

  const _DateAddDecision._({required this.allowed, this.message});

  const _DateAddDecision.allowed() : this._(allowed: true);

  const _DateAddDecision.denied(String message)
    : this._(allowed: false, message: message);
}

class _SlotTopBar extends StatelessWidget {
  final double topInset;
  final String title;
  final VoidCallback onBack;

  const _SlotTopBar({
    required this.topInset,
    required this.title,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: GlassSurface(
        padding: EdgeInsets.fromLTRB(20, topInset + 8, 20, 10),
        borderRadius: BorderRadius.zero,
        backgroundColor: const Color(0xFFFCF8F5).withValues(alpha: 0.82),
        blurSigma: 18,
        border: Border(
          bottom: BorderSide(color: AppColors.primary.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 24),
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textDark,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceSummaryCard extends StatelessWidget {
  final String title;
  final String providerName;
  final String durationLabel;
  final int price;
  final String imageUrl;

  const _ServiceSummaryCard({
    required this.title,
    required this.providerName,
    required this.durationLabel,
    required this.price,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final provider = providerName.trim().isEmpty
        ? 'Service provider'
        : providerName.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: SizedBox(
              width: 58,
              height: 58,
              child: imageUrl.trim().isEmpty
                  ? Container(
                      color: const Color(0xFFFFEFE7),
                      child: const Icon(
                        Icons.pets_rounded,
                        color: AppColors.primary,
                        size: 28,
                      ),
                    )
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: const Color(0xFFFFEFE7),
                        child: const Icon(
                          Icons.pets_rounded,
                          color: AppColors.primary,
                          size: 28,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$provider · $durationLabel · ₹$price',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
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

class _CalendarMonthSection extends StatefulWidget {
  final DateTime today;
  final DateTime lastSelectableDate;
  final DateTime displayedMonth;
  final DateTime selectedDate;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onMiddleDateChanged;
  final ValueChanged<DateTime> onDateSelected;
  final bool Function(DateTime date) isSelectable;
  final bool Function(DateTime a, DateTime b) isSameDay;

  const _CalendarMonthSection({
    required this.today,
    required this.lastSelectableDate,
    required this.displayedMonth,
    required this.selectedDate,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
    required this.onMiddleDateChanged,
    required this.onDateSelected,
    required this.isSelectable,
    required this.isSameDay,
  });

  @override
  State<_CalendarMonthSection> createState() => _CalendarMonthSectionState();
}

class _CalendarMonthSectionState extends State<_CalendarMonthSection> {
  static const double _dateChipWidth = 58;
  static const double _dateGap = 9;
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _controller.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToDate(widget.selectedDate);
      _handleScroll();
    });
  }

  @override
  void didUpdateWidget(covariant _CalendarMonthSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isSameDay(oldWidget.selectedDate, widget.selectedDate)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToDate(widget.selectedDate);
        _handleScroll();
      });
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final days = _visibleDates();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                  '${_monthLabel(widget.displayedMonth.month)} ${widget.displayedMonth.year}',
                ),
              ),
              _MonthArrowButton(
                icon: Icons.arrow_back_rounded,
                enabled: widget.canGoPrevious,
                onTap: widget.onPrevious,
              ),
              const SizedBox(width: 8),
              _MonthArrowButton(
                icon: Icons.chevron_right_rounded,
                enabled: widget.canGoNext,
                onTap: widget.onNext,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 70,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: ListView.separated(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                clipBehavior: Clip.hardEdge,
                itemCount: days.length,
                separatorBuilder: (_, _) => const SizedBox(width: _dateGap),
                itemBuilder: (context, index) {
                  final date = days[index];
                  return _DateChip(
                    date: date,
                    isSelected: widget.isSameDay(date, widget.selectedDate),
                    isEnabled: widget.isSelectable(date),
                    onTap: () => widget.onDateSelected(date),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<DateTime> _visibleDates() {
    final dates = <DateTime>[];
    for (
      var date = widget.today;
      !date.isAfter(widget.lastSelectableDate);
      date = date.add(const Duration(days: 1))
    ) {
      dates.add(date);
    }
    return dates;
  }

  void _jumpToDate(DateTime date) {
    if (!_controller.hasClients) return;
    final index = date
        .difference(widget.today)
        .inDays
        .clamp(0, _visibleDates().length - 1);
    final viewport = _controller.position.viewportDimension;
    final target =
        (index * (_dateChipWidth + _dateGap)) - (viewport - _dateChipWidth) / 2;
    _controller.jumpTo(
      target.clamp(0.0, _controller.position.maxScrollExtent).toDouble(),
    );
  }

  void _handleScroll() {
    if (!_controller.hasClients) return;
    final viewport = _controller.position.viewportDimension;
    final centerOffset = _controller.offset + viewport / 2;
    final index = (centerOffset / (_dateChipWidth + _dateGap)).round().clamp(
      0,
      _visibleDates().length - 1,
    );
    widget.onMiddleDateChanged(_visibleDates()[index]);
  }

  String _monthLabel(int month) {
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
    return months[(month - 1).clamp(0, 11)];
  }
}

class _MonthArrowButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _MonthArrowButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEDE8E4), width: 1.4),
        ),
        child: Icon(
          icon,
          color: enabled
              ? AppColors.textDark
              : AppColors.textGrey.withValues(alpha: 0.45),
          size: 21,
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final DateTime date;
  final bool isSelected;
  final bool isEnabled;
  final VoidCallback onTap;

  const _DateChip({
    required this.date,
    required this.isSelected,
    required this.isEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final weekday = _weekdayLabel(date.weekday);

    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Container(
        width: 58,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected && isEnabled ? AppColors.brandGradient : null,
          color: isSelected && isEnabled ? null : Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: isSelected && isEnabled
                ? Colors.transparent
                : const Color(0xFFEDE8E4),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              weekday,
              style: TextStyle(
                color: isSelected && isEnabled
                    ? Colors.white
                    : AppColors.textGrey,
                fontWeight: FontWeight.w900,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${date.day}',
              style: TextStyle(
                color: isSelected && isEnabled
                    ? Colors.white
                    : isEnabled
                    ? AppColors.textDark
                    : AppColors.textGrey.withValues(alpha: 0.65),
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _weekdayLabel(int weekday) {
    const labels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return labels[(weekday - 1).clamp(0, 6)];
  }
}

class _SlotRail extends StatefulWidget {
  final List<ServiceSlotModel> slots;
  final String? selectedSlotId;
  final Set<String> selectedSlotIds;
  final bool allowMultiSelect;
  final bool Function(ServiceSlotModel slot) isSlotBookable;
  final ValueChanged<ServiceSlotModel> onSlotSelected;

  const _SlotRail({
    required this.slots,
    required this.selectedSlotId,
    required this.selectedSlotIds,
    required this.allowMultiSelect,
    required this.isSlotBookable,
    required this.onSlotSelected,
  });

  @override
  State<_SlotRail> createState() => _SlotRailState();
}

class _SlotRailState extends State<_SlotRail> {
  static const double _slotWidth = 164;
  static const double _slotGap = 10;
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToNextAvailable());
  }

  @override
  void didUpdateWidget(covariant _SlotRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slots != widget.slots ||
        oldWidget.selectedSlotId != widget.selectedSlotId) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _jumpToNextAvailable(),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        clipBehavior: Clip.hardEdge,
        itemCount: widget.slots.length,
        separatorBuilder: (_, _) => const SizedBox(width: _slotGap),
        itemBuilder: (context, index) {
          final slot = widget.slots[index];
          return SizedBox(
            width: _slotWidth,
            child: _SlotTile(
              slot: slot,
              isBookable: widget.isSlotBookable(slot),
              isSelected: widget.allowMultiSelect
                  ? widget.selectedSlotIds.contains(slot.id)
                  : widget.selectedSlotId == slot.id,
              isMultiSelect: widget.allowMultiSelect,
              onTap: widget.isSlotBookable(slot)
                  ? () => widget.onSlotSelected(slot)
                  : null,
            ),
          );
        },
      ),
    );
  }

  void _jumpToNextAvailable() {
    if (!_controller.hasClients || widget.slots.isEmpty) return;
    final preferredIndex = widget.selectedSlotId == null
        ? widget.slots.indexWhere((slot) => widget.isSlotBookable(slot))
        : widget.slots.indexWhere((slot) => slot.id == widget.selectedSlotId);
    final index = preferredIndex < 0 ? 0 : preferredIndex;
    final target = index * (_slotWidth + _slotGap);
    _controller.jumpTo(
      target.clamp(0.0, _controller.position.maxScrollExtent).toDouble(),
    );
  }
}

class _SlotTile extends StatelessWidget {
  final ServiceSlotModel slot;
  final bool isBookable;
  final bool isSelected;
  final bool isMultiSelect;
  final VoidCallback? onTap;

  const _SlotTile({
    required this.slot,
    required this.isBookable,
    required this.isSelected,
    required this.isMultiSelect,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    final label = '${_formatTime(slot.startAt)} - ${_formatTime(slot.endAt)}';
    final helper = isBookable
        ? '${slot.remainingCapacity} spot${slot.remainingCapacity == 1 ? '' : 's'} left'
        : slot.isFull
        ? 'Fully booked'
        : 'Unavailable';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.zero,
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.brandGradient : null,
          color: isSelected
              ? null
              : isDisabled
              ? const Color(0xFFF8F1EC)
              : Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : isDisabled
                ? const Color(0xFFECE3DD)
                : const Color(0xFFE8E4E1),
            width: 1.4,
          ),
          boxShadow: isSelected || isDisabled
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.035),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        alignment: Alignment.centerLeft,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : isDisabled
                      ? AppColors.textGrey
                      : AppColors.textDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                helper,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.86)
                      : AppColors.textGrey,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (isSelected && isMultiSelect) ...[
                const SizedBox(height: 6),
                const Icon(Icons.check_rounded, size: 14, color: Colors.white),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final hour = date.hour;
    final minute = date.minute;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $suffix';
  }
}

class _CanonicalRequestInfoBanner extends StatelessWidget {
  const _CanonicalRequestInfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1EA),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule_rounded, color: AppColors.primary, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'If the provider is currently outside working hours, their response timer will start when working hours begin.',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 14.5,
                fontWeight: FontWeight.w900,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CanonicalSelectionSummaryCard extends StatelessWidget {
  final SlotBookingSelectionV3 selection;
  final int unitPricePaise;
  final String schedulingMode;

  const _CanonicalSelectionSummaryCard({
    required this.selection,
    required this.unitPricePaise,
    required this.schedulingMode,
  });

  @override
  Widget build(BuildContext context) {
    final segments =
        selection.segments ?? const <SlotBookingScheduleSegmentV3>[];
    final estimatedSubtotalPaise = selection.slotCount * unitPricePaise;
    final serviceDayCount = selection.serviceDayCount ?? segments.length;
    final visibleSegments = segments.isNotEmpty
        ? segments
        : <SlotBookingScheduleSegmentV3>[
            SlotBookingScheduleSegmentV3(
              serviceDateKey:
                  selection.slots.first.serviceDateKey ??
                  selection.slots.first.dateKey,
              slotIds: selection.slots
                  .map((slot) => slot.slotId)
                  .toList(growable: false),
              startAt: selection.scheduledStartAt,
              endAt: selection.scheduledEndAt,
              durationMinutes: selection.totalDurationMinutes,
              schedulingMode: schedulingMode,
            ),
          ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Booking summary',
            style: TextStyle(
              color: AppColors.textDark,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$serviceDayCount Service Day${serviceDayCount == 1 ? '' : 's'}',
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          ...visibleSegments.map(
            (segment) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatSummaryDate(segment.startAt),
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatSlotTime(segment.startAt)} - ${_formatSlotTime(segment.endAt)}',
                    style: const TextStyle(
                      color: AppColors.textGrey,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Text(
            '${selection.slotCount} slot${selection.slotCount == 1 ? '' : 's'} · ${_formatDuration(selection.totalDurationMinutes, schedulingMode: schedulingMode)} · Total service price ₹${(estimatedSubtotalPaise / 100).toStringAsFixed(0)}',
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatSlotTime(DateTime date) {
  final hour = date.hour;
  final minute = date.minute;
  final suffix = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$displayHour:${minute.toString().padLeft(2, '0')} $suffix';
}

String _formatSummaryDate(DateTime date) {
  const months = <String>[
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
  final local = date.toLocal();
  return '${months[local.month - 1]} ${local.day}';
}

String _formatDuration(int minutes, {String? schedulingMode}) {
  return formatServiceDurationLabel(
    durationMinutes: minutes,
    schedulingMode: schedulingMode,
  );
}

class _SlotBottomBar extends StatelessWidget {
  final double bottomInset;
  final bool isReady;
  final String label;
  final VoidCallback onContinue;

  const _SlotBottomBar({
    required this.bottomInset,
    required this.isReady,
    required this.label,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 20,
      right: 20,
      bottom: bottomInset + 6,
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SizedBox(
          height: 54,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: isReady
                  ? AppColors.brandGradient
                  : const LinearGradient(
                      colors: [Color(0xFFFFB5A5), Color(0xFFFFA895)],
                    ),
              borderRadius: BorderRadius.circular(19),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onContinue,
                borderRadius: BorderRadius.circular(19),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SlotLoadingState extends StatelessWidget {
  const _SlotLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

class _SlotStateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SlotStateMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFFFFF1EA),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textDark,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
