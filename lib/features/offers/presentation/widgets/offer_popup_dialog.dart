import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../data/services/offer_service.dart';
import '../../domain/models/mobile_offer_campaign.dart';

class OfferPopupDialog extends StatefulWidget {
  final MobileOfferCampaign offer;

  const OfferPopupDialog({super.key, required this.offer});

  static Future<bool?> show(
    BuildContext context, {
    required MobileOfferCampaign offer,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: OfferPopupDialog(offer: offer),
      ),
    );
  }

  @override
  State<OfferPopupDialog> createState() => _OfferPopupDialogState();
}

class _OfferPopupDialogState extends State<OfferPopupDialog> {
  final OfferService _offerService = OfferService();
  bool _isClaiming = false;

  Future<void> _claim() async {
    if (_isClaiming) return;
    setState(() => _isClaiming = true);

    try {
      await _offerService.claimOffer(
        campaignId: widget.offer.id,
        sourceDisplayType: widget.offer.displayType,
      );
      await _offerService.resetOfferDismissal(widget.offer.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'We could not claim this offer right now.',
        tone: AppFeedbackTone.error,
      );
      setState(() => _isClaiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFFCF8F5),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Limited offer',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            offer.title,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            offer.description,
            style: const TextStyle(
              color: AppColors.textGrey,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offer.couponCode,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  offer.discountSummary,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          GradientButton(
            label: _isClaiming ? 'Claiming...' : 'Claim Offer',
            onPressed: _isClaiming ? null : _claim,
            icon: Icons.redeem_rounded,
          ),
          const SizedBox(height: 12),
          SecondaryButton(
            label: 'Later',
            onPressed: _isClaiming ? null : () => Navigator.pop(context, false),
          ),
        ],
      ),
    );
  }
}
