import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../data/services/offer_service.dart';
import '../../domain/models/mobile_offer_campaign.dart';

class OfferWallScreen extends StatefulWidget {
  final MobileOfferCampaign offer;

  const OfferWallScreen({super.key, required this.offer});

  @override
  State<OfferWallScreen> createState() => _OfferWallScreenState();
}

class _OfferWallScreenState extends State<OfferWallScreen> {
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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: -70,
              right: -40,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.08),
                ),
              ),
            ),
            Positioned(
              bottom: 160,
              left: -30,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.gradientSoft.withValues(alpha: 0.11),
                ),
              ),
            ),
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Row(
                  children: [
                    const Spacer(),
                    IconButton(
                      onPressed:
                          _isClaiming ? null : () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Special for you',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  offer.title,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  offer.description,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 15.5,
                    height: 1.55,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),
                _OfferHero(offer: offer),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.98),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Coupon code',
                        style: TextStyle(
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        offer.couponCode,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _MetaPill(
                            icon: Icons.local_offer_outlined,
                            label: offer.discountSummary,
                          ),
                          _MetaPill(
                            icon: Icons.repeat_rounded,
                            label:
                                '${offer.usageLimitPerUser} use${offer.usageLimitPerUser == 1 ? '' : 's'}',
                          ),
                          _MetaPill(
                            icon: Icons.schedule_rounded,
                            label: offer.validitySummary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                GradientButton(
                  label: _isClaiming ? 'Claiming...' : 'Claim Offer',
                  icon: Icons.redeem_rounded,
                  onPressed: _isClaiming ? null : _claim,
                ),
                const SizedBox(height: 12),
                SecondaryButton(
                  label: 'Maybe Later',
                  onPressed:
                      _isClaiming ? null : () => Navigator.pop(context, false),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferHero extends StatelessWidget {
  final MobileOfferCampaign offer;

  const _OfferHero({required this.offer});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: AppColors.brandGradientDiagonal,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.2),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (offer.imageUrl.isNotEmpty)
              Image.network(
                offer.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.12),
                    Colors.black.withValues(alpha: 0.45),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Text(
                    offer.discountSummary,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    offer.couponCode,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4EC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.primary, size: 16),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
