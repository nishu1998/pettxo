import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../domain/models/claimed_offer.dart';

class ClaimedOfferCard extends StatelessWidget {
  final ClaimedOffer offer;

  const ClaimedOfferCard({super.key, required this.offer});

  @override
  Widget build(BuildContext context) {
    final status = offer.effectiveStatusLabel;
    final statusColor = switch (status) {
      'Used' => const Color(0xFF0F766E),
      'Expired' => const Color(0xFF9A3412),
      _ => AppColors.primary,
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
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
                      offer.title.isEmpty ? 'Offer' : offer.title,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      offer.couponCode,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          if (offer.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              offer.description,
              style: const TextStyle(
                color: AppColors.textGrey,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _OfferMetaPill(
                icon: Icons.local_offer_outlined,
                label: offer.discountSummary,
              ),
              _OfferMetaPill(
                icon: Icons.repeat_rounded,
                label: '${offer.remainingUses} use${offer.remainingUses == 1 ? '' : 's'} left',
              ),
              _OfferMetaPill(
                icon: Icons.schedule_rounded,
                label: offer.validUntil == null
                    ? 'No expiry'
                    : _formatDate(offer.validUntil!),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
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
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

class _OfferMetaPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _OfferMetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5EF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.primary, size: 16),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
