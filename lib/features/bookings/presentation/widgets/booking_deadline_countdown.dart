import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

enum BookingDeadlineCountdownTone { normal, warning, critical }

class BookingDeadlineCountdown extends StatelessWidget {
  const BookingDeadlineCountdown({
    super.key,
    required this.deadline,
    this.label = 'Time remaining',
    this.valueFontSize = 28,
    this.labelFontSize = 13,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.textAlign = TextAlign.start,
    this.centerLabelRow = false,
    this.showSideDividers = false,
  });

  final DateTime? deadline;
  final String label;
  final double valueFontSize;
  final double labelFontSize;
  final CrossAxisAlignment crossAxisAlignment;
  final TextAlign textAlign;
  final bool centerLabelRow;
  final bool showSideDividers;

  static int remainingSeconds(DateTime? deadline, {DateTime? now}) {
    if (deadline == null) return 0;
    final seconds = deadline.difference(now ?? DateTime.now()).inSeconds;
    return seconds > 0 ? seconds : 0;
  }

  static BookingDeadlineCountdownTone toneFor(
    DateTime? deadline, {
    DateTime? now,
  }) {
    final remaining = remainingSeconds(deadline, now: now);
    if (remaining <= 60) return BookingDeadlineCountdownTone.critical;
    if (remaining <= 600) return BookingDeadlineCountdownTone.warning;
    return BookingDeadlineCountdownTone.normal;
  }

  static Color colorFor(DateTime? deadline, {DateTime? now}) {
    return switch (toneFor(deadline, now: now)) {
      BookingDeadlineCountdownTone.normal => AppColors.primary,
      BookingDeadlineCountdownTone.warning => const Color(0xFFF59E0B),
      BookingDeadlineCountdownTone.critical => const Color(0xFFDC2626),
    };
  }

  static String formatRemaining(DateTime? deadline, {DateTime? now}) {
    final remaining = remainingSeconds(deadline, now: now);
    final hours = remaining ~/ 3600;
    final minutes = (remaining % 3600) ~/ 60;
    final seconds = remaining % 60;
    if (hours > 0) {
      return '$hours'
          'h ${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s';
    }
    if (minutes > 0) {
      return '$minutes'
          'm ${seconds.toString().padLeft(2, '0')}s';
    }
    return '00:${seconds.toString().padLeft(2, '0')}';
  }

  static String formatClock(DateTime? deadline, {DateTime? now}) {
    final remaining = remainingSeconds(deadline, now: now);
    final hours = remaining ~/ 3600;
    final minutes = (remaining % 3600) ~/ 60;
    final seconds = remaining % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = colorFor(deadline);
    final labelRow = Row(
      mainAxisSize: centerLabelRow ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: centerLabelRow && !showSideDividers
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        if (showSideDividers)
          Expanded(
            child: Container(height: 1, color: accent.withValues(alpha: 0.22)),
          ),
        if (showSideDividers) const SizedBox(width: 14),
        Icon(Icons.timer_outlined, size: 16, color: accent),
        const SizedBox(width: 6),
        Text(
          label,
          textAlign: textAlign,
          style: TextStyle(
            color: accent,
            fontSize: labelFontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.1,
          ),
        ),
        if (showSideDividers) const SizedBox(width: 14),
        if (showSideDividers)
          Expanded(
            child: Container(height: 1, color: accent.withValues(alpha: 0.22)),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        labelRow,
        const SizedBox(height: 6),
        Text(
          formatRemaining(deadline),
          textAlign: textAlign,
          style: TextStyle(
            color: accent,
            fontSize: valueFontSize,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ],
    );
  }
}
