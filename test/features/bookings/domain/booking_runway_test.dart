import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/domain/utils/booking_runway.dart';

void main() {
  test('runway ends 150 minutes after authoritative now', () {
    final authoritativeNow = DateTime.utc(2026, 7, 27, 10, 0);

    final runwayEndsAt = computeCanonicalBookingRunwayEndsAt(authoritativeNow);

    expect(runwayEndsAt, DateTime.utc(2026, 7, 27, 12, 30));
  });

  test('slot starting less than 150 minutes from now is not bookable', () {
    final authoritativeNow = DateTime.utc(2026, 7, 27, 10, 0);
    final anchorAt = DateTime.utc(2026, 7, 27, 12, 29);

    final isBookable = isCanonicalBookingAnchorBookable(
      anchorAt: anchorAt,
      authoritativeNow: authoritativeNow,
    );

    expect(isBookable, isFalse);
  });

  test('slot starting exactly 150 minutes from now remains bookable', () {
    final authoritativeNow = DateTime.utc(2026, 7, 27, 10, 0);
    final anchorAt = DateTime.utc(2026, 7, 27, 12, 30);

    final isBookable = isCanonicalBookingAnchorBookable(
      anchorAt: anchorAt,
      authoritativeNow: authoritativeNow,
    );

    expect(isBookable, isTrue);
  });
}
