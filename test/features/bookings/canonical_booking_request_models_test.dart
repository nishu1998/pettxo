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

  group('CanonicalSlotRequestInput', () {
    test('serializes additive selectedDays payload when provided', () {
      final request = CanonicalSlotRequestInput(
        selection: SlotBookingSelectionV3(
          bookingType: BookingV3Type.slot,
          slots: <BookingSlotSegmentV3>[],
          slotCount: 0,
          scheduledStartAt: DateTime.utc(2026, 8, 7, 3, 30),
          scheduledEndAt: DateTime.utc(2026, 8, 7, 4, 30),
          totalDurationMinutes: 0,
        ),
        estimatedSubtotalPaise: 0,
        selectedDays: <CanonicalSelectedDaySlotInput>[
          CanonicalSelectedDaySlotInput(
            serviceDateKey: '2026-08-07',
            slotIds: <String>['slot-1'],
          ),
          CanonicalSelectedDaySlotInput(
            serviceDateKey: '2026-08-08',
            slotIds: <String>['slot-2'],
          ),
        ],
      );

      expect(request.toCallableMap(), {
        'selectedDays': [
          {
            'serviceDateKey': '2026-08-07',
            'slotIds': ['slot-1'],
          },
          {
            'serviceDateKey': '2026-08-08',
            'slotIds': ['slot-2'],
          },
        ],
      });
    });
  });
}
