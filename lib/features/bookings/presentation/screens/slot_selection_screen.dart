import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../restrictions/data/services/user_restriction_service.dart';
import '../../data/repositories/booking_repository.dart';
import '../../domain/models/booking_checkout_draft.dart';
import '../../domain/models/service_slot_model.dart';
import 'payment_review_screen.dart';

class SlotSelectionScreen extends StatefulWidget {
  final String serviceId;
  final String serviceName;
  final int price;
  final int durationMinutes;
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
  final BookingRepository _bookingRepository = BookingRepository();
  late DateTime _selectedDate;
  late DateTime _focusedMonth;
  ServiceSlotModel? _selectedSlot;
  String? _slotError;

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
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _lastSelectableDate => _today.add(const Duration(days: 30));

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
      _selectedSlot = null;
      _slotError = null;
    });
  }

  void _continue() {
    if (!UserRestrictionService.instance.ensureCanUseBookingFeatures(context)) {
      return;
    }
    final selectedSlot = _selectedSlot;
    if (selectedSlot == null) {
      setState(() => _slotError = 'Choose an available slot to continue.');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentReviewScreen(
          draft: BookingCheckoutDraft(
            serviceId: widget.serviceId,
            serviceName: widget.serviceName,
            price: widget.price,
            durationMinutes: widget.durationMinutes,
            providerId: widget.providerId,
            slotId: selectedSlot.id,
            selectedSlot: selectedSlot.startAt,
            selectedSlotEnd: selectedSlot.endAt,
          ),
        ),
      ),
    );
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
                durationLabel: _formatDuration(widget.durationMinutes),
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
                    _selectedSlot = null;
                    _slotError = null;
                  });
                },
                isSelectable: _isSelectableDate,
                isSameDay: _isSameDay,
              ),
              const SizedBox(height: 22),
              const Text(
                'Available slots',
                style: TextStyle(
                  color: AppColors.textDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              StreamBuilder<List<ServiceSlotModel>>(
                stream: _bookingRepository.watchServiceSlotsForDate(
                  serviceId: widget.serviceId,
                  date: _selectedDate,
                ),
                builder: (context, snapshot) =>
                    _buildSlotSelector(context, snapshot),
              ),
              const SizedBox(height: 14),
              const _CancellationInfoBanner(),
            ],
          ),
          _SlotTopBar(topInset: topInset, onBack: () => Navigator.pop(context)),
          _SlotBottomBar(
            bottomInset: bottomInset,
            isReady: _selectedSlot != null,
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
          selectedSlotId: _selectedSlot?.id,
          onSlotSelected: (slot) {
            setState(() {
              _selectedSlot = slot;
              _slotError = null;
            });
          },
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
    if (_selectedSlot != null ||
        widget.suggestedSlotStartAt == null ||
        !_isSameDay(widget.suggestedSlotStartAt!, _selectedDate)) {
      return;
    }

    final suggestedLocal = widget.suggestedSlotStartAt!.toLocal();
    final suggestedSlot = slots
        .where((slot) {
          final slotLocal = slot.startAt.toLocal();
          return slot.canRequest &&
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
      if (!mounted || _selectedSlot?.id == suggestedSlot.id) return;
      setState(() {
        _selectedSlot = suggestedSlot;
        _slotError = null;
      });
    });
  }

  String _formatDuration(int minutes) {
    if (minutes <= 0) return 'Duration varies';
    if (minutes % 60 == 0 && minutes >= 60) {
      final hours = minutes ~/ 60;
      return '$hours hr${hours == 1 ? '' : 's'}';
    }
    return '$minutes min';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _SlotTopBar extends StatelessWidget {
  final double topInset;
  final VoidCallback onBack;

  const _SlotTopBar({required this.topInset, required this.onBack});

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
            const Expanded(
              child: Text(
                'Choose a slot',
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
  final ValueChanged<ServiceSlotModel> onSlotSelected;

  const _SlotRail({
    required this.slots,
    required this.selectedSlotId,
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
              isSelected: widget.selectedSlotId == slot.id,
              onTap: slot.canRequest ? () => widget.onSlotSelected(slot) : null,
            ),
          );
        },
      ),
    );
  }

  void _jumpToNextAvailable() {
    if (!_controller.hasClients || widget.slots.isEmpty) return;
    final preferredIndex = widget.selectedSlotId == null
        ? widget.slots.indexWhere((slot) => slot.canRequest)
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
  final bool isSelected;
  final VoidCallback? onTap;

  const _SlotTile({
    required this.slot,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    final label = slot.isTooSoon
        ? 'Starts in under 1 hour'
        : slot.isFull
        ? '${_formatTime(slot.startAt)} - ${_formatTime(slot.endAt)}'
        : !slot.isOpen
        ? '${_formatTime(slot.startAt)} - ${_formatTime(slot.endAt)}'
        : '${_formatTime(slot.startAt)} - ${_formatTime(slot.endAt)}';
    final helper = slot.canRequest
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

class _CancellationInfoBanner extends StatelessWidget {
  const _CancellationInfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFE4EEFF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF1E5ED8), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Cancellation charges apply based on timing. You will see the exact refund window before you pay.',
              style: TextStyle(
                color: Color(0xFF1E5ED8),
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

class _SlotBottomBar extends StatelessWidget {
  final double bottomInset;
  final bool isReady;
  final VoidCallback onContinue;

  const _SlotBottomBar({
    required this.bottomInset,
    required this.isReady,
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
                child: const Center(
                  child: Text(
                    'Continue',
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
