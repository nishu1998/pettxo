import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
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

  const SlotSelectionScreen({
    super.key,
    required this.serviceId,
    required this.serviceName,
    required this.price,
    required this.durationMinutes,
    required this.providerId,
    this.suggestedSlotStartAt,
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
    final lastSelectableDate = normalizedToday.add(const Duration(days: 29));
    final canUseSuggestedDate =
        normalizedSuggested != null &&
        !normalizedSuggested.isBefore(normalizedToday) &&
        !normalizedSuggested.isAfter(lastSelectableDate);
    _selectedDate = canUseSuggestedDate ? normalizedSuggested : normalizedToday;
    _focusedMonth = DateTime(_selectedDate.year, _selectedDate.month);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!UserRestrictionService.instance.ensureCanUseBookingFeatures(context)) {
        Navigator.maybePop(context);
      }
    });
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _lastSelectableDate => _today.add(const Duration(days: 29));

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
    final latest = DateTime(_lastSelectableDate.year, _lastSelectableDate.month);
    if (next.isBefore(earliest) || next.isAfter(latest)) return;
    setState(() => _focusedMonth = next);
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
              18,
              topInset + 108,
              18,
              bottomInset + 24,
            ),
            children: [
              _IntroCard(
                title: widget.serviceName,
                subtitle:
                    'Choose a date and time. The provider has up to 24 hours to respond, or until 1 hour before the service starts, whichever comes first.',
              ),
              const SizedBox(height: 18),
              _SectionCard(
                title: 'Select date',
                child: _CalendarMonthSection(
                  focusedMonth: _focusedMonth,
                  selectedDate: _selectedDate,
                  canGoPrevious: _canGoToPreviousMonth,
                  canGoNext: _canGoToNextMonth,
                  onPrevious: () => _moveMonth(-1),
                  onNext: () => _moveMonth(1),
                  onDateSelected: (date) {
                    if (!_isSelectableDate(date)) return;
                    setState(() {
                      _selectedDate = date;
                      _selectedSlot = null;
                      _slotError = null;
                    });
                  },
                  isSelectable: _isSelectableDate,
                  isSameDay: _isSameDay,
                ),
              ),
              const SizedBox(height: 18),
              _SectionCard(
                title: 'Available slots',
                child: StreamBuilder<List<ServiceSlotModel>>(
                  stream: _bookingRepository.watchServiceSlotsForDate(
                    serviceId: widget.serviceId,
                    date: _selectedDate,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _SlotStateMessage(
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
                    if (_selectedSlot == null &&
                        widget.suggestedSlotStartAt != null &&
                        _isSameDay(
                          widget.suggestedSlotStartAt!,
                          _selectedDate,
                        )) {
                      final suggestedSlot = slots
                          .where(
                            (slot) =>
                                slot.canRequest &&
                                slot.startAt.toLocal().year ==
                                    widget.suggestedSlotStartAt!.toLocal().year &&
                                slot.startAt.toLocal().month ==
                                    widget.suggestedSlotStartAt!.toLocal().month &&
                                slot.startAt.toLocal().day ==
                                    widget.suggestedSlotStartAt!.toLocal().day &&
                                slot.startAt.toLocal().hour ==
                                    widget.suggestedSlotStartAt!.toLocal().hour &&
                                slot.startAt.toLocal().minute ==
                                    widget.suggestedSlotStartAt!.toLocal().minute,
                          )
                          .cast<ServiceSlotModel?>()
                          .firstWhere((slot) => slot != null, orElse: () => null);
                      if (suggestedSlot != null) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted || _selectedSlot?.id == suggestedSlot.id) {
                            return;
                          }
                          setState(() {
                            _selectedSlot = suggestedSlot;
                            _slotError = null;
                          });
                        });
                      }
                    }
                    if (slots.isEmpty) {
                      return const _SlotStateMessage(
                        icon: Icons.event_busy_outlined,
                        title: 'No slots for this date',
                        subtitle:
                            'Try another day from the date selector above.',
                      );
                    }

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final crossAxisSpacing = 10.0;
                        final availableWidth = constraints.maxWidth;
                        final tileWidth =
                            (availableWidth - crossAxisSpacing) / 2;
                        final tileHeight = tileWidth < 150 ? 88.0 : 82.0;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: slots.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: crossAxisSpacing,
                                    mainAxisSpacing: 10,
                                    mainAxisExtent: tileHeight,
                                  ),
                              itemBuilder: (context, index) {
                                final slot = slots[index];
                                return _SlotTile(
                                  slot: slot,
                                  isSelected: _selectedSlot?.id == slot.id,
                                  onTap: slot.canRequest
                                      ? () {
                                          setState(() {
                                            _selectedSlot = slot;
                                            _slotError = null;
                                          });
                                        }
                                      : null,
                                );
                              },
                            ),
                            if (_slotError != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                _slotError!,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 22),
              GradientButton(
                label: 'Continue',
                onPressed: _selectedSlot == null ? null : _continue,
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            top: topInset + 10,
            child: GlassSurface(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              borderRadius: BorderRadius.circular(24),
              backgroundColor: Colors.white.withValues(alpha: 0.72),
              blurSigma: 20,
              border: Border.all(color: Colors.white.withValues(alpha: 0.62)),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.56),
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
                      'Select Slot',
                      style: TextStyle(
                        color: AppColors.textDark,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _IntroCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _IntroCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textGrey,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
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
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _CalendarMonthSection extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime selectedDate;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onDateSelected;
  final bool Function(DateTime date) isSelectable;
  final bool Function(DateTime a, DateTime b) isSameDay;

  const _CalendarMonthSection({
    required this.focusedMonth,
    required this.selectedDate,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
    required this.onDateSelected,
    required this.isSelectable,
    required this.isSameDay,
  });

  @override
  Widget build(BuildContext context) {
    const weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final firstDate = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final daysInMonth = DateTime(
      focusedMonth.year,
      focusedMonth.month + 1,
      0,
    ).day;
    final leadingEmptySlots = firstDate.weekday - 1;
    final totalCells = ((leadingEmptySlots + daysInMonth + 6) ~/ 7) * 7;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              _MonthArrowButton(
                icon: Icons.chevron_left_rounded,
                enabled: canGoPrevious,
                onTap: onPrevious,
              ),
              Expanded(
                child: Text(
                  '${_monthLabel(focusedMonth.month)} ${focusedMonth.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _MonthArrowButton(
                icon: Icons.chevron_right_rounded,
                enabled: canGoNext,
                onTap: onNext,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: weekdayLabels.map((label) {
            return Expanded(
              child: Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: totalCells,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 10,
            crossAxisSpacing: 8,
            mainAxisExtent: 72,
          ),
          itemBuilder: (context, index) {
            if (index < leadingEmptySlots) {
              return const SizedBox.shrink();
            }

            final dayNumber = index - leadingEmptySlots + 1;
            if (dayNumber > daysInMonth) {
              return const SizedBox.shrink();
            }
            final date = DateTime(
              focusedMonth.year,
              focusedMonth.month,
              dayNumber,
            );
            return _DateChip(
              date: date,
              isSelected: isSameDay(date, selectedDate),
              isEnabled: isSelectable(date),
              onTap: () => onDateSelected(date),
            );
          },
        ),
      ],
    );
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFFFFF8F2) : const Color(0xFFF4EFEB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: enabled ? 0.10 : 0.04),
          ),
        ),
        child: Icon(
          icon,
          color: enabled ? AppColors.primary : AppColors.textGrey,
          size: 20,
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
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected && isEnabled ? AppColors.brandGradient : null,
          color: isSelected && isEnabled
              ? null
              : isEnabled
              ? const Color(0xFFFFF8F2)
              : const Color(0xFFF5F0EC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.primary.withValues(
              alpha: isSelected && isEnabled ? 0 : isEnabled ? 0.10 : 0.05,
            ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(
                color: isSelected && isEnabled
                    ? Colors.white
                    : isEnabled
                    ? AppColors.textDark
                    : AppColors.textGrey.withValues(alpha: 0.65),
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
          ],
        ),
      ),
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
        ? 'Starts in under\n1 hour'
        : slot.isFull
        ? 'Full'
        : !slot.isOpen
        ? 'Unavailable'
        : '${_formatTime(slot.startAt)} -\n${_formatTime(slot.endAt)}';
    final helper = slot.canRequest
        ? '${slot.remainingCapacity} spot${slot.remainingCapacity == 1 ? '' : 's'} left'
        : null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.brandGradient : null,
          color: isSelected
              ? null
              : isDisabled
              ? const Color(0xFFF1ECE8)
              : const Color(0xFFFFFAF7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : AppColors.primary.withValues(alpha: 0.10),
          ),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              softWrap: true,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : isDisabled
                    ? AppColors.textGrey
                    : AppColors.textDark,
                fontWeight: FontWeight.w800,
                fontSize: slot.isTooSoon ? 11 : 12,
                height: 1.2,
              ),
            ),
            if (helper != null) ...[
              const SizedBox(height: 4),
              Text(
                helper,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.86)
                      : AppColors.textGrey,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
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
