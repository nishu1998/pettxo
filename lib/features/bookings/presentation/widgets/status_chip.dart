import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../domain/models/booking_flow_models.dart';

class StatusChip extends StatelessWidget {
  final String label;
  final BookingStatusTone tone;

  const StatusChip({super.key, required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      BookingStatusTone.confirmed => (
        const Color(0xFFDCFCE7),
        const Color(0xFF15803D),
      ),
      BookingStatusTone.awaiting => (
        const Color(0xFFFEF3C7),
        const Color(0xFF92400E),
      ),
      BookingStatusTone.cancelled => (
        const Color(0xFFFEE2E2),
        const Color(0xFFB91C1C),
      ),
      BookingStatusTone.completed => (
        const Color(0xFFDCFCE7),
        const Color(0xFF15803D),
      ),
      BookingStatusTone.request => (
        const Color(0xFFEFF6FF),
        const Color(0xFF1D4ED8),
      ),
      BookingStatusTone.highlighted => (
        AppColors.primary.withValues(alpha: 0.12),
        AppColors.primary,
      ),
      BookingStatusTone.noShow => (
        const Color(0xFFF3F4F6),
        const Color(0xFF6B7280),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
