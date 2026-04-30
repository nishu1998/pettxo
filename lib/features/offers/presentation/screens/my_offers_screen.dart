import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/services/offer_service.dart';
import '../../domain/models/claimed_offer.dart';
import '../widgets/claimed_offer_card.dart';

class MyOffersScreen extends StatelessWidget {
  MyOffersScreen({super.key});

  final OfferService _offerService = OfferService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.background,
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
                      'My Offers',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<ClaimedOffer>>(
                stream: _offerService.watchClaimedOffers(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return const _OffersState(
                      icon: Icons.local_offer_outlined,
                      title: 'Offers are unavailable',
                      subtitle:
                          'We could not load your claimed offers right now.',
                    );
                  }

                  final offers = snapshot.data ?? const <ClaimedOffer>[];
                  if (offers.isEmpty) {
                    return const _OffersState(
                      icon: Icons.redeem_rounded,
                      title: 'No offers yet',
                      subtitle:
                          'Claim offers when they appear and they will show up here.',
                    );
                  }

                  final available = offers.where((offer) => offer.isAvailable).toList();
                  final used = offers.where((offer) => offer.isUsed).toList();
                  final expired = offers
                      .where((offer) => !offer.isUsed && offer.isExpired)
                      .toList();

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                    children: [
                      if (available.isNotEmpty)
                        _OfferGroup(title: 'Available', offers: available),
                      if (used.isNotEmpty) ...[
                        if (available.isNotEmpty) const SizedBox(height: 18),
                        _OfferGroup(title: 'Used', offers: used),
                      ],
                      if (expired.isNotEmpty) ...[
                        if (available.isNotEmpty || used.isNotEmpty)
                          const SizedBox(height: 18),
                        _OfferGroup(title: 'Expired', offers: expired),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferGroup extends StatelessWidget {
  final String title;
  final List<ClaimedOffer> offers;

  const _OfferGroup({required this.title, required this.offers});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        ...offers.map(
          (offer) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ClaimedOfferCard(offer: offer),
          ),
        ),
      ],
    );
  }
}

class _OffersState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _OffersState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: const Color(0xFFFFF2EA),
              child: Icon(icon, color: AppColors.primary, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textGrey,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
