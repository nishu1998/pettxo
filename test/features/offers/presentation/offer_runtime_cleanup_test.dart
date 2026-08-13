import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home no longer contains coupon promotion runtime', () {
    final source = File(
      'lib/features/home/presentation/screens/home_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('OfferPopupDialog')));
    expect(source, isNot(contains('OfferWallScreen')));
    expect(source, isNot(contains('getAvailableOffers(screen: \'home\')')));
    expect(source, isNot(contains('getEligibleOffers(screen: \'home\')')));
    expect(source, isNot(contains('_showEligibleOffers')));
    expect(source, isNot(contains('MyOffersScreen')));
  });

  test(
    'offer service no longer contains popup dismissal throttling helpers',
    () {
      final source = File(
        'lib/features/offers/data/services/offer_service.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('SharedPreferences')));
      expect(source, isNot(contains('shouldShowOffer')));
      expect(source, isNot(contains('markOfferShown')));
      expect(source, isNot(contains('recordOfferDismissed')));
      expect(source, isNot(contains('resetOfferDismissal')));
      expect(source, contains('getAvailableOffers'));
      expect(source, isNot(contains('getEligibleOffers')));
      expect(source, isNot(contains('claimOffer')));
      expect(source, isNot(contains('watchClaimedOffers')));
    },
  );

  test(
    'automatic settings availability still depends on getAvailableOffers',
    () {
      final source = File(
        'lib/features/offers/presentation/screens/my_offers_screen.dart',
      ).readAsStringSync();

      expect(source, contains('getAvailableOffers'));
      expect(source, isNot(contains('Claim Offer')));
    },
  );

  test('deleted coupon promotion runtime files do not remain in the app', () {
    expect(
      File(
        'lib/features/offers/presentation/widgets/offer_popup_dialog.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/features/offers/presentation/screens/offer_wall_screen.dart',
      ).existsSync(),
      isFalse,
    );
  });

  test('checkout now uses direct offer campaign validation for pricing', () {
    final source = File(
      'lib/features/bookings/presentation/screens/canonical_booking_payment_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('watchClaimedOffers()')));
    expect(source, contains('loadAvailableOffers'));
    expect(source, contains('offerCampaignId'));
    expect(source, isNot(contains('claimedOfferId')));
  });

  test('claimed offer runtime files no longer remain in the app', () {
    expect(
      File('lib/features/offers/domain/models/claimed_offer.dart').existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/features/offers/presentation/widgets/claimed_offer_card.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/features/offers/domain/models/mobile_offer_campaign.dart',
      ).existsSync(),
      isFalse,
    );
  });
}
