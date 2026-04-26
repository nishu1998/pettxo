import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../domain/models/booking_flow_models.dart';
import 'status_chip.dart';

class BookingCard extends StatelessWidget {
  final BookingRecord booking;
  final String? countdownText;
  final String? loadingActionLabel;
  final VoidCallback? onTap;
  final void Function(BookingActionData action)? onActionTap;

  const BookingCard({
    super.key,
    required this.booking,
    this.countdownText,
    this.loadingActionLabel,
    this.onTap,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: booking.isRequestHighlighted
              ? AppColors.primary.withValues(alpha: 0.22)
              : AppColors.primary.withValues(alpha: 0.08),
          width: booking.isRequestHighlighted ? 1.2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Container(
        decoration: booking.isRequestHighlighted
            ? const BoxDecoration(
                border: Border(
                  left: BorderSide(color: AppColors.primary, width: 3),
                ),
              )
            : null,
        padding: const EdgeInsets.all(16),
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
                        booking.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        booking.subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (countdownText != null)
                  _TimerPill(text: countdownText!)
                else
                  StatusChip(
                    label: booking.statusLabel,
                    tone: booking.statusTone,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              booking.meta,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textGrey,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (booking.reviewSummary.isNotEmpty ||
                booking.statusTone == BookingStatusTone.completed) ...[
              const SizedBox(height: 8),
              _BookingReviewSummaryLine(booking: booking),
            ],
            if (countdownText != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 12,
                      height: 1.4,
                    ),
                    children: [
                      const TextSpan(
                        text: 'Waiting for provider',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text:
                            ' · Response window ends in $countdownText',
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (booking.actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: booking.actions.map((action) {
                  final isLast = action == booking.actions.last;
                  final isLoading = loadingActionLabel == action.label;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: isLast ? 0 : 10),
                      child: _ActionButton(
                        action: action,
                        isLoading: isLoading,
                        onTap: loadingActionLabel == null
                            ? () => onActionTap?.call(action)
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );

    if (onTap == null) return card;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: card,
    );
  }
}

class _BookingReviewSummaryLine extends StatelessWidget {
  final BookingRecord booking;

  const _BookingReviewSummaryLine({required this.booking});

  @override
  Widget build(BuildContext context) {
    if (booking.reviewSummary.isNotEmpty) {
      return _ReviewSummaryText(text: booking.reviewSummary);
    }

    final providerUserId = booking.providerUserId.trim();
    if (providerUserId.isEmpty) {
      return const _ReviewSummaryText(text: 'New provider');
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(providerUserId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? const <String, dynamic>{};
        final ratingAverage = (data['ratingAverage'] as num?)?.toDouble() ?? 0;
        final ratingCount = (data['ratingCount'] as num?)?.toInt() ?? 0;
        final text = ratingCount > 0
            ? '⭐ ${ratingAverage.toStringAsFixed(1)} · $ratingCount ${ratingCount == 1 ? 'review' : 'reviews'}'
            : 'New provider';
        return _ReviewSummaryText(text: text);
      },
    );
  }
}

class _ReviewSummaryText extends StatelessWidget {
  final String text;

  const _ReviewSummaryText({required this.text});

  @override
  Widget build(BuildContext context) {
    final highlighted = text.startsWith('⭐');
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12.5,
        color: highlighted ? const Color(0xFF9A3412) : AppColors.textGrey,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _TimerPill extends StatelessWidget {
  final String text;

  const _TimerPill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF92400E),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF92400E),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final BookingActionData action;
  final bool isLoading;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.action,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = isLoading ? '${action.label}...' : action.label;
    if (action.style == BookingActionStyle.primary) {
      return GradientButton(label: label, onPressed: onTap);
    }

    return SecondaryButton(label: label, onPressed: onTap);
  }
}
