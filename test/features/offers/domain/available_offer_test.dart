import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/offers/domain/models/available_offer.dart';

void main() {
  test('available offers parse callable payloads without claim documents', () {
    final result = AvailableOffersResult.fromMap({
      'ok': true,
      'offerWall': {
        'id': 'wall-1',
        'title': 'Festival Savings',
        'description': 'Save on your next booking.',
        'couponCode': 'FEST50',
        'displayType': 'offerWall',
        'campaignType': 'festival',
        'discountType': 'percent',
        'discountValue': 50,
        'usageLimitPerUser': 1,
        'priority': 10,
        'startAt': '2026-08-10T00:00:00.000Z',
        'endAt': '2026-08-31T23:59:59.000Z',
      },
      'popup': null,
      'offers': [
        {
          'id': 'wall-1',
          'title': 'Festival Savings',
          'description': 'Save on your next booking.',
          'couponCode': 'FEST50',
          'displayType': 'offerWall',
          'campaignType': 'festival',
          'discountType': 'percent',
          'discountValue': 50,
          'usageLimitPerUser': 1,
          'priority': 10,
          'startAt': '2026-08-10T00:00:00.000Z',
          'endAt': '2026-08-31T23:59:59.000Z',
        },
      ],
    });

    expect(result.offerWall, isNotNull);
    expect(result.offerWall!.id, 'wall-1');
    expect(result.offerWall!.couponCode, 'FEST50');
    expect(result.offerWall!.availabilitySummary, contains('Available until'));
    expect(result.offers, hasLength(1));
  });
}
