import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/profile/domain/models/service_location.dart';

void main() {
  test(
    'selected service location preserves canonical geocoder city and state',
    () {
      const location = ServiceLocation(
        latitude: 18.5204,
        longitude: 73.8567,
        displayAddress: 'Shivajinagar, Pune, Maharashtra',
        city: 'Pune',
        state: 'Maharashtra',
      );

      final restored = ServiceLocation.fromMap(location.toMap());

      expect(restored.city, 'Pune');
      expect(restored.state, 'Maharashtra');
      expect(restored.displayAddress, 'Shivajinagar, Pune, Maharashtra');
      expect(restored.latitude, 18.5204);
      expect(restored.longitude, 73.8567);
      expect(restored.hasPublicArea, isTrue);
    },
  );

  test(
    'service location without canonical city or state is not publishable',
    () {
      const location = ServiceLocation(
        latitude: 18.5204,
        longitude: 73.8567,
        displayAddress: 'An exact address that must remain private',
      );

      expect(location.hasPublicArea, isFalse);
    },
  );
}
