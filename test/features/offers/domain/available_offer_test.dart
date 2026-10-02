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

  test('canonical exclusive end derives the preceding inclusive IST date', () {
    final offer = _offerWithEnd('2026-10-10T18:30:00.000Z');

    expect(offer.validThroughBusinessDate?.year, 2026);
    expect(offer.validThroughBusinessDate?.month, 10);
    expect(offer.validThroughBusinessDate?.day, 10);
    expect(offer.availabilitySummary, 'Available until 10 Oct 2026');
  });

  test(
    'canonical valid-through date is independent of represented timezone',
    () {
      final equivalentInstants = [
        '2026-10-11T00:00:00.000+05:30',
        '2026-10-10T18:30:00.000Z',
        '2026-10-11T02:30:00.000+08:00',
        '2026-10-10T20:30:00.000+02:00',
        '2026-10-10T11:30:00.000-07:00',
      ];

      for (final timestamp in equivalentInstants) {
        final offer = _offerWithEnd(timestamp);
        expect(
          offer.availabilitySummary,
          'Available until 10 Oct 2026',
          reason: timestamp,
        );
      }
    },
  );

  test('arbitrary legacy end retains its own IST date', () {
    final offer = _offerWithEnd('2026-08-31T16:43:00.000Z');

    expect(offer.availabilitySummary, 'Available until 31 Aug 2026');
  });

  test('missing end remains available now', () {
    final offer = _offerWithEnd(null);

    expect(offer.validThroughBusinessDate, isNull);
    expect(offer.availabilitySummary, 'Available now');
  });
}

AvailableOffer _offerWithEnd(String? endAt) {
  return AvailableOffer.fromMap({
    'id': 'offer-1',
    'title': 'Offer',
    'couponCode': 'SAVE',
    'displayType': 'offerWall',
    'campaignType': 'general',
    'discountType': 'flat',
    'discountValue': 50,
    'usageLimitPerUser': 1,
    'endAt': endAt,
  });
}
