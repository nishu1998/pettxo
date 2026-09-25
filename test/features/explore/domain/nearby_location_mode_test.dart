import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/explore/domain/models/nearby_location_mode.dart';

void main() {
  group('NearbyLocationMode', () {
    test('parses canonical backend modes', () {
      expect(
        NearbyLocationMode.fromResponse(
          value: 'radius',
          usedCityStateFallback: false,
          activeRadiusKm: 50,
        ),
        NearbyLocationMode.radius,
      );
      expect(
        NearbyLocationMode.fromResponse(
          value: 'savedCityState',
          usedCityStateFallback: true,
          activeRadiusKm: null,
        ),
        NearbyLocationMode.savedCityState,
      );
      expect(
        NearbyLocationMode.fromResponse(
          value: 'unavailable',
          usedCityStateFallback: false,
          activeRadiusKm: null,
        ),
        NearbyLocationMode.unavailable,
      );
    });

    test('keeps query strategy and UI copy synchronized', () {
      expect(
        NearbyLocationMode.radius.bannerText(50),
        'Showing posts within 50 km of you.',
      );
      expect(
        NearbyLocationMode.savedCityState.bannerText(null),
        'Showing posts near your saved city/state.',
      );
      expect(NearbyLocationMode.unavailable.bannerText(null), isNull);
    });

    test('supports old callable responses during rolling deployment', () {
      expect(
        NearbyLocationMode.fromResponse(
          value: null,
          usedCityStateFallback: true,
          activeRadiusKm: null,
        ),
        NearbyLocationMode.savedCityState,
      );
      expect(
        NearbyLocationMode.fromResponse(
          value: null,
          usedCityStateFallback: false,
          activeRadiusKm: 50,
        ),
        NearbyLocationMode.radius,
      );
    });

    test('resolves device, saved-location, and unavailable sources', () {
      expect(
        NearbyLocationMode.fromAvailableSources(
          hasStoredCoordinates: true,
          savedCity: '',
          savedState: '',
        ),
        NearbyLocationMode.radius,
      );
      expect(
        NearbyLocationMode.fromAvailableSources(
          hasStoredCoordinates: false,
          savedCity: ' Pune ',
          savedState: 'Maharashtra',
        ),
        NearbyLocationMode.savedCityState,
      );
      expect(
        NearbyLocationMode.fromAvailableSources(
          hasStoredCoordinates: false,
          savedCity: '',
          savedState: '',
        ),
        NearbyLocationMode.unavailable,
      );
    });
  });
}
