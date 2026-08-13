import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/offers/domain/models/available_offer.dart';
import 'package:pettexo/features/offers/domain/models/offer_types.dart';
import 'package:pettexo/features/offers/presentation/screens/my_offers_screen.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required Future<AvailableOffersResult> Function() loadAvailableOffers,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MyOffersScreen(loadAvailableOffers: loadAvailableOffers),
      ),
    );
  }

  testWidgets('shows automatic available offers without claim history UI', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      loadAvailableOffers: () async => AvailableOffersResult(
        offerWall: null,
        popup: null,
        offers: const [
          AvailableOffer(
            id: 'available-1',
            title: 'Provider Welcome Offer',
            description: 'This role-targeted campaign already reached you.',
            couponCode: 'PROSAVE',
            displayType: OfferDisplayType.offerWall,
            campaignType: OfferCampaignType.general,
            discountType: OfferDiscountType.percent,
            discountValue: 20,
            maxDiscountAmount: null,
            minBookingAmount: 100,
            usageLimitPerUser: 1,
            priority: 5,
            startAt: null,
            endAt: null,
          ),
        ],
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Available Offers'), findsOneWidget);
    expect(find.text('Provider Welcome Offer'), findsOneWidget);
    expect(find.text('PROSAVE'), findsOneWidget);
    expect(find.text('Claim Offer'), findsNothing);
    expect(find.text('Used'), findsNothing);
    expect(find.text('Expired'), findsNothing);
  });

  testWidgets('shows the new empty state when no offers are available', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      loadAvailableOffers: () async => AvailableOffersResult.empty,
    );

    await tester.pumpAndSettle();

    expect(find.text('No offers available'), findsOneWidget);
    expect(
      find.text('No offers are available for your account right now.'),
      findsOneWidget,
    );
  });

  test('AvailableOffer parses cleanly without imageUrl in the payload', () {
    final offer = AvailableOffer.fromMap({
      'id': 'available-2',
      'title': 'Weekend Offer',
      'description': 'Business-data only coupon payload.',
      'couponCode': 'WEEKEND',
      'displayType': 'offerWall',
      'campaignType': 'general',
      'discountType': 'flat',
      'discountValue': 50,
      'maxDiscountAmount': 100,
      'minBookingAmount': 0,
      'usageLimitPerUser': 1,
      'priority': 3,
    });

    expect(offer.id, 'available-2');
    expect(offer.couponCode, 'WEEKEND');
    expect(offer.displayTitle, 'Weekend Offer');
  });
}
