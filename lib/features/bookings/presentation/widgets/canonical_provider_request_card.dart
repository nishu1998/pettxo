import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../domain/models/canonical_provider_booking_request_view.dart';

class CanonicalProviderRequestCard extends StatelessWidget {
  final CanonicalProviderBookingRequestView request;
  final String? countdownText;
  final bool isAccepting;
  final bool isDeclining;
  final VoidCallback? onTap;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  const CanonicalProviderRequestCard({
    super.key,
    required this.request,
    this.countdownText,
    this.isAccepting = false,
    this.isDeclining = false,
    this.onTap,
    this.onAccept,
    this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.serviceTitle,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${request.maskedParentDisplayName} · ${request.animalType} · ${request.serviceCategory}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF8E8479),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _StatePill(label: _stateLabel, tint: _stateTint),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _metaLine,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF5F5650),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7F1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _supportingLine(countdownText),
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (request.isActionable) ...[
            const SizedBox(height: 16),
            Text(
              _actionHint,
              style: const TextStyle(
                color: Color(0xFF8E8479),
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: isDeclining ? 'Declining...' : 'Decline',
                    onPressed: isBusy ? null : onDecline,
                    size: AppButtonSize.compact,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GradientButton(
                    label: isAccepting ? 'Accepting...' : 'Accept',
                    onPressed: isBusy ? null : onAccept,
                    size: AppButtonSize.compact,
                    isLoading: isAccepting,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: card,
    );
  }

  bool get isBusy => isAccepting || isDeclining;

  String get _stateLabel {
    if (request.isQueuedRequest) return 'Queued';
    if (request.isPendingProvider) return 'Action required';
    if (request.isAcceptedAwaitingPayment) return 'Accepted';
    return 'Request';
  }

  Color get _stateTint {
    if (request.isQueuedRequest) return const Color(0xFFFFE8D4);
    if (request.isPendingProvider) return const Color(0xFFFFE1D2);
    if (request.isAcceptedAwaitingPayment) return const Color(0xFFDDF7E3);
    return const Color(0xFFF3F4F6);
  }

  String get _metaLine {
    final start = request.scheduledStartAt;
    final end = request.scheduledEndAt;
    if (start == null || end == null) {
      return 'Schedule details are being prepared for this booking type.';
    }
    final duration = request.totalDurationMinutes > 0
        ? ' · ${request.totalDurationMinutes} min'
        : '';
    return '${_dateLabel(start)} · ${_timeLabel(start)} to ${_timeLabel(end)} · ${request.slotCount} slot${request.slotCount == 1 ? '' : 's'}$duration';
  }

  String _supportingLine(String? countdownText) {
    if (request.isQueuedRequest) {
      final timerStartsAt = request.timerStartsAt;
      if (timerStartsAt == null) {
        return 'This request was received outside your working hours. You can accept or decline it now. The official response window will start when your schedule opens.';
      }
      return 'This request was received outside your working hours. You can accept or decline it now. Your official response window starts on ${_dateLabel(timerStartsAt)} at ${_timeLabel(timerStartsAt)}.';
    }
    if (request.isPendingProvider) {
      return countdownText == null
          ? 'The official 60-minute response window is active.'
          : 'The official 60-minute response window is active. $countdownText remaining.';
    }
    return 'Accepted, awaiting payment. The customer can pay now and the booking will confirm as soon as payment succeeds.';
  }

  String get _actionHint {
    if (request.isQueuedRequest) {
      return 'You can respond now even though the official working-hours clock has not started yet.';
    }
    return 'Accepting lets the customer pay now. Availability is confirmed only after payment succeeds.';
  }

  String _dateLabel(DateTime value) {
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
    return '${value.day} ${months[value.month - 1]}';
  }

  String _timeLabel(DateTime value) {
    final hour = value.hour;
    final minute = value.minute;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $suffix';
  }
}

class _StatePill extends StatelessWidget {
  final String label;
  final Color tint;

  const _StatePill({required this.label, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textDark,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
