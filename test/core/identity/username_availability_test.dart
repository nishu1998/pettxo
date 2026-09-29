import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/identity/username_availability.dart';

void main() {
  test('parses distinct availability outcomes', () {
    for (final entry in <String, UsernameAvailabilityStatus>{
      'available': UsernameAvailabilityStatus.available,
      'owned': UsernameAvailabilityStatus.owned,
      'taken': UsernameAvailabilityStatus.taken,
      'reserved': UsernameAvailabilityStatus.reserved,
      'staleReservation': UsernameAvailabilityStatus.staleReservation,
      'invalid': UsernameAvailabilityStatus.invalid,
    }.entries) {
      final result = UsernameAvailabilityResult.fromMap({
        'username': 'pettxo',
        'status': entry.key,
      });
      expect(result.status, entry.value);
      expect(
        result.isAvailable,
        entry.value == UsernameAvailabilityStatus.available ||
            entry.value == UsernameAvailabilityStatus.owned,
      );
    }
  });

  test(
    'rejects malformed backend responses instead of reporting unavailable',
    () {
      expect(
        () => UsernameAvailabilityResult.fromMap({
          'username': 'pettxo',
          'status': 'backend-failed',
        }),
        throwsFormatException,
      );
    },
  );
}
