import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/services/offer_service.dart';
import '../../domain/models/available_offer.dart';
import '../widgets/available_offer_card.dart';

class MyOffersScreen extends StatefulWidget {
  final Future<AvailableOffersResult> Function()? loadAvailableOffers;

  const MyOffersScreen({super.key, this.loadAvailableOffers});

  @override
  State<MyOffersScreen> createState() => _MyOffersScreenState();
}

class _MyOffersScreenState extends State<MyOffersScreen> {
  OfferService? _offerService;
  late Future<AvailableOffersResult> _availableOffersFuture;

  @override
  void initState() {
    super.initState();
    _availableOffersFuture = _fetchAvailableOffers();
  }

  Future<AvailableOffersResult> _fetchAvailableOffers() {
    return (widget.loadAvailableOffers ??
        () => (_offerService ??= OfferService()).getAvailableOffers(
          screen: 'myOffers',
        ))();
  }

  Future<void> _refreshOffers() async {
    final future = _fetchAvailableOffers();
    setState(() {
      _availableOffersFuture = future;
    });
    await future;
  }

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
              child: FutureBuilder<AvailableOffersResult>(
                future: _availableOffersFuture,
                builder: (context, availableSnapshot) {
                  final availableOffers =
                      availableSnapshot.data?.offers ??
                      const <AvailableOffer>[];

                  if (availableSnapshot.connectionState ==
                          ConnectionState.waiting &&
                      !availableSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (availableSnapshot.hasError && availableOffers.isEmpty) {
                    return _RefreshableOffersState(
                      onRefresh: _refreshOffers,
                      child: const _OffersState(
                        icon: Icons.local_offer_outlined,
                        title: 'Offers are unavailable',
                        subtitle:
                            'We could not load your available offers right now.',
                      ),
                    );
                  }

                  if (!availableSnapshot.hasError && availableOffers.isEmpty) {
                    return _RefreshableOffersState(
                      onRefresh: _refreshOffers,
                      child: const _OffersState(
                        icon: Icons.redeem_rounded,
                        title: 'No offers available',
                        subtitle:
                            'No offers are available for your account right now.',
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: _refreshOffers,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                      children: [
                        if (availableSnapshot.hasError)
                          const _OfferMessageCard(
                            title: 'Available offers',
                            message:
                                'We could not refresh every offer right now, but the latest available offers are shown below.',
                          ),
                        _AvailableOfferGroup(
                          title: 'Available Offers',
                          offers: availableOffers,
                        ),
                      ],
                    ),
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

class _AvailableOfferGroup extends StatelessWidget {
  final String title;
  final List<AvailableOffer> offers;

  const _AvailableOfferGroup({required this.title, required this.offers});

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
            child: AvailableOfferCard(offer: offer),
          ),
        ),
      ],
    );
  }
}

class _OfferMessageCard extends StatelessWidget {
  final String title;
  final String message;

  const _OfferMessageCard({required this.title, required this.message});

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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.08),
            ),
          ),
          child: Text(
            message,
            style: const TextStyle(
              color: AppColors.textGrey,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _RefreshableOffersState extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;

  const _RefreshableOffersState({required this.onRefresh, required this.child});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: child,
          ),
        ],
      ),
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
