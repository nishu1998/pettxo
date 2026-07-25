import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/domain/models/booking_v3_models.dart';
import 'package:pettexo/features/bookings/domain/models/canonical_booking_request_models.dart';
import 'package:pettexo/features/bookings/domain/utils/booking_request_attempt_id.dart';

void main() {
  group('BookingRequestAttemptIdController', () {
    test('reuses the same id for the same payload key', () {
      final controller = BookingRequestAttemptIdController();

      final first = controller.idForPayload('service_a|slot_1');
      final second = controller.idForPayload('service_a|slot_1');

      expect(second, first);
    });

    test('creates a new id when the payload key changes', () {
      final controller = BookingRequestAttemptIdController();

      final first = controller.idForPayload('service_a|slot_1');
      final second = controller.idForPayload('service_a|slot_1,slot_2');

      expect(second, isNot(first));
    });
  });

  group('CanonicalBookingRequestResult', () {
    test('parses canonical response fields safely', () {
      final result = CanonicalBookingRequestResult.fromMap({
        'bookingId': 'booking_123',
        'source': 'canonical_v3',
        'schemaVersion': 3,
        'bookingModelVersion': '3.2',
        'state': 'PENDING_PROVIDER',
        'bookingType': 'SLOT',
        'requestedAt': '2026-07-22T10:00:00.000Z',
        'timerStartsAt': '2026-07-22T10:00:00.000Z',
        'acceptDeadlineAt': '2026-07-22T11:00:00.000Z',
        'wasQueuedOutsideWorkingHours': false,
        'idempotentReplay': true,
      });

      expect(result.bookingId, 'booking_123');
      expect(result.bookingType, BookingV3Type.slot);
      expect(result.state, CanonicalBookingStateV3.pendingProvider);
      expect(result.idempotentReplay, isTrue);
      expect(result.acceptDeadlineAt, isNotNull);
    });
  });
}
