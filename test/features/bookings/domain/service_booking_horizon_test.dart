import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/domain/utils/service_booking_horizon.dart';

void main() {
  test('selectable range includes today through day 30', () {
    final now = DateTime.parse('2026-09-13T18:30:00Z');
    expect(serviceBookingDate(now), DateTime(2026, 9, 14));
    expect(lastServiceBookingDate(now), DateTime(2026, 10, 14));
    expect(serviceBookingHorizonDays, 30);
  });
  test('service calendar rolls at IST midnight', () {
    expect(
      serviceBookingDate(DateTime.parse('2026-09-13T18:29:59Z')),
      DateTime(2026, 9, 13),
    );
    expect(
      serviceBookingDate(DateTime.parse('2026-09-13T18:30:00Z')),
      DateTime(2026, 9, 14),
    );
  });
  test('equivalent instants use the same date regardless of input offset', () {
    expect(
      serviceBookingDate(DateTime.parse('2026-09-14T00:00:00+05:30')),
      serviceBookingDate(DateTime.parse('2026-09-13T11:30:00-07:00')),
    );
  });
  test('calendar bounds cross year and leap-month boundaries', () {
    expect(
      lastServiceBookingDate(DateTime.parse('2026-12-20T00:00:00Z')),
      DateTime(2027, 1, 19),
    );
    expect(
      lastServiceBookingDate(DateTime.parse('2028-02-01T00:00:00Z')),
      DateTime(2028, 3, 2),
    );
  });
}
