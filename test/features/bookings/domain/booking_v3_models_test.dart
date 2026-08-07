import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/domain/models/booking_v3_models.dart';

void main() {
  group('validateSlotBookingSelectionV3', () {
    BookingSlotSegmentV3 buildSlot({
      required String slotId,
      required int startHour,
      required int endHour,
      String serviceId = 'service-1',
      String providerId = 'provider-1',
      String timezone = 'Asia/Kolkata',
      String dateKey = '2026-07-22',
    }) {
      final startAt = DateTime.utc(2026, 7, 22, startHour);
      final endAt = DateTime.utc(2026, 7, 22, endHour);
      return BookingSlotSegmentV3(
        slotId: slotId,
        serviceId: serviceId,
        providerId: providerId,
        timezone: timezone,
        dateKey: dateKey,
        startAt: startAt,
        endAt: endAt,
        durationMinutes: endAt.difference(startAt).inMinutes,
        unitPricePaise: 10000,
      );
    }

    test('accepts multiple continuous slots and normalizes sort order', () {
      final later = buildSlot(slotId: 'slot-2', startHour: 11, endHour: 12);
      final earlier = buildSlot(slotId: 'slot-1', startHour: 10, endHour: 11);
      final result = validateSlotBookingSelectionV3(
        SlotBookingSelectionV3(
          bookingType: BookingV3Type.slot,
          slots: [later, earlier],
          slotCount: 2,
          scheduledStartAt: earlier.startAt,
          scheduledEndAt: later.endAt,
          totalDurationMinutes: 120,
        ),
      );

      expect(result.ok, isTrue);
      expect(result.normalizedSelection?.slots.first.slotId, 'slot-1');
      expect(result.normalizedSelection?.slotCount, 2);
      expect(result.normalizedSelection?.totalDurationMinutes, 120);
      expect(result.normalizedSelection?.segmentCount, 1);
    });

    test('rejects gap between slots', () {
      final first = buildSlot(slotId: 'slot-1', startHour: 10, endHour: 11);
      final second = buildSlot(slotId: 'slot-2', startHour: 12, endHour: 13);
      final result = validateSlotBookingSelectionV3(
        SlotBookingSelectionV3(
          bookingType: BookingV3Type.slot,
          slots: [first, second],
          slotCount: 2,
          scheduledStartAt: first.startAt,
          scheduledEndAt: second.endAt,
          totalDurationMinutes: 120,
        ),
      );

      expect(result.ok, isFalse);
      expect(
        result.issues.any(
          (issue) =>
              issue.code == SlotBookingValidationCode.nonContiguousDailySlots,
        ),
        isTrue,
      );
    });

    test('rejects overlap, duplicate slot, and mixed provider/service', () {
      final first = buildSlot(slotId: 'slot-1', startHour: 10, endHour: 11);
      final overlap = buildSlot(
        slotId: 'slot-1',
        startHour: 10,
        endHour: 12,
        serviceId: 'service-2',
        providerId: 'provider-2',
      );
      final result = validateSlotBookingSelectionV3(
        SlotBookingSelectionV3(
          bookingType: BookingV3Type.slot,
          slots: [first, overlap],
          slotCount: 2,
          scheduledStartAt: first.startAt,
          scheduledEndAt: overlap.endAt,
          totalDurationMinutes: 180,
        ),
      );

      expect(result.ok, isFalse);
      expect(
        result.issues.any(
          (issue) =>
              issue.code == SlotBookingValidationCode.duplicateSlotSelection,
        ),
        isTrue,
      );
      expect(
        result.issues.any(
          (issue) =>
              issue.code ==
              SlotBookingValidationCode.overlappingBookingSegments,
        ),
        isTrue,
      );
      expect(
        result.issues.any(
          (issue) =>
              issue.code ==
              SlotBookingValidationCode.mixedProviderSlotSelection,
        ),
        isTrue,
      );
      expect(
        result.issues.any(
          (issue) =>
              issue.code == SlotBookingValidationCode.mixedServiceSlotSelection,
        ),
        isTrue,
      );
    });

    test('normalizes consecutive service dates into multiple segments', () {
      BookingSlotSegmentV3 buildDatedSlot({
        required String slotId,
        required DateTime startAt,
        required DateTime endAt,
        required String dateKey,
      }) {
        return BookingSlotSegmentV3(
          slotId: slotId,
          serviceId: 'service-1',
          providerId: 'provider-1',
          timezone: 'Asia/Kolkata',
          dateKey: dateKey,
          serviceDateKey: dateKey,
          startAt: startAt,
          endAt: endAt,
          durationMinutes: endAt.difference(startAt).inMinutes,
          unitPricePaise: 10000,
          schedulingMode: 'fixedDuration',
        );
      }

      final result = validateSlotBookingSelectionV3(
        SlotBookingSelectionV3(
          bookingType: BookingV3Type.slot,
          slots: [
            buildDatedSlot(
              slotId: 'slot-1',
              dateKey: '2026-08-07',
              startAt: DateTime.utc(2026, 8, 7, 3, 30),
              endAt: DateTime.utc(2026, 8, 7, 4, 30),
            ),
            buildDatedSlot(
              slotId: 'slot-2',
              dateKey: '2026-08-08',
              startAt: DateTime.utc(2026, 8, 8, 8, 30),
              endAt: DateTime.utc(2026, 8, 8, 9, 30),
            ),
            buildDatedSlot(
              slotId: 'slot-3',
              dateKey: '2026-08-09',
              startAt: DateTime.utc(2026, 8, 9, 5, 30),
              endAt: DateTime.utc(2026, 8, 9, 6, 30),
            ),
          ],
          slotCount: 3,
          scheduledStartAt: DateTime.utc(2026, 8, 7, 3, 30),
          scheduledEndAt: DateTime.utc(2026, 8, 9, 6, 30),
          totalDurationMinutes: 180,
        ),
      );

      expect(result.ok, isTrue);
      expect(result.normalizedSelection?.serviceDayCount, 3);
      expect(result.normalizedSelection?.segments?.length, 3);
    });
  });

  group('BookingFinancialSnapshotV3 parsing', () {
    const validMap = <String, dynamic>{
      'currency': 'INR',
      'serviceSubtotalPaise': 100000,
      'couponDiscountPaise': 30000,
      'customerPaidPaise': 70000,
      'platformCommissionRateBasisPoints': 1500,
      'platformCommissionPaise': 15000,
      'providerPayoutPaise': 85000,
      'pettxoCouponFundingPaise': 30000,
      'gatewayFeeSunkPaise': 0,
      'providerFaultCostPaise': 0,
      'refundAmountPaise': 52500,
      'pettxoNetBeforeGatewayPaise': -15000,
      'pricingVersion': 1,
    };

    test('parses valid integer paise snapshot without loss', () {
      final parsed = BookingFinancialSnapshotV3.fromMap(validMap);
      expect(parsed.serviceSubtotalPaise, 100000);
      expect(parsed.customerPaidPaise, 70000);
      expect(parsed.providerPayoutPaise, 85000);
      expect(parsed.pettxoNetBeforeGatewayPaise, -15000);
    });

    test('returns null safely for malformed values', () {
      final malformed = {...validMap, 'serviceSubtotalPaise': 100000.5};
      expect(BookingFinancialSnapshotV3.tryParse(malformed), isNull);
    });

    test('throws format exception for malformed strict parse', () {
      final malformed = {...validMap, 'currency': ''};
      expect(
        () => BookingFinancialSnapshotV3.fromMap(malformed),
        throwsFormatException,
      );
    });
  });
}
