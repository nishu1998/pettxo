import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/glass_surface.dart';
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

  const SlotSelectionScreen({
    super.key,
    required this.serviceId,
    required this.serviceName,
    required this.price,
    required this.durationMinutes,
    required this.providerId,
  });

  @override
  State<SlotSelectionScreen> createState() => _SlotSelectionScreenState();
}

class _SlotSelectionScreenState extends State<SlotSelectionScreen> {
  static const Color _screenBackground = Color(0xFFFCF8F5);
  final BookingRepository _bookingRepository = BookingRepository();
  late DateTime _selectedDate;
  ServiceSlotModel? _selectedSlot;
  String? _slotError;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  List<DateTime> get _visibleDates {
    final today = DateTime.now();
    final base = DateTime(today.year, today.month, today.day);
    return List.generate(7, (index) => base.add(Duration(days: index)));
  }

  void _continue() {
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
                child: SizedBox(
                  height: 86,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _visibleDates.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final date = _visibleDates[index];
                      final isSelected = _isSameDay(date, _selectedDate);
                      return _DateChip(
                        date: date,
                        isSelected: isSelected,
                        onTap: () {
                          setState(() {
                            _selectedDate = date;
                            _selectedSlot = null;
                            _slotError = null;
                          });
                        },
                      );
                    },
                  ),
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
                    if (slots.isEmpty) {
                      return const _SlotStateMessage(
                        icon: Icons.event_busy_outlined,
                        title: 'No slots for this date',
                        subtitle:
                            'Try another day from the date selector above.',
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: slots.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 2.35,
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

class _DateChip extends StatelessWidget {
  final DateTime date;
  final bool isSelected;
  final VoidCallback onTap;

  const _DateChip({
    required this.date,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 74,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.brandGradient : null,
          color: isSelected ? null : const Color(0xFFFFF8F2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: isSelected ? 0 : 0.10),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              weekdays[date.weekday - 1],
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textGrey,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${date.day}',
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textDark,
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
        ? 'Starts in under 1 hour'
        : slot.isFull
        ? 'Full'
        : !slot.isOpen
        ? 'Unavailable'
        : '${_formatTime(slot.startAt)} - ${_formatTime(slot.endAt)}';
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
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : isDisabled
                    ? AppColors.textGrey
                    : AppColors.textDark,
                fontWeight: FontWeight.w800,
                fontSize: slot.isTooSoon ? 11.5 : 12.5,
                height: 1.15,
              ),
            ),
            if (helper != null) ...[
              const SizedBox(height: 3),
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
