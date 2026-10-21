import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/domain/models/service_slot_model.dart';

void main() {
  test(
    'callable UTC timestamps retain the provider-facing local wall time',
    () {
      final slot = ServiceSlotModel.fromCallableMap(<String, dynamic>{
        'id': '2026-10-21_0060',
        'serviceId': 'service-1',
        'serviceOwnerId': 'provider-1',
        'startAt': '2026-10-20T19:30:00.000Z',
        'endAt': '2026-10-20T20:30:00.000Z',
        'dateKey': '2026-10-21',
        'capacity': 1,
        'confirmedUnits': 0,
        'isBookable': true,
        'status': 'open',
      });

      expect(
        slot.startAt,
        DateTime.parse('2026-10-20T19:30:00.000Z').toLocal(),
      );
      expect(slot.endAt, DateTime.parse('2026-10-20T20:30:00.000Z').toLocal());
      expect(slot.startAt.isUtc, isFalse);
    },
  );

  test('capacity-one slot uses canonical confirmed occupancy', () {
    final start = DateTime.utc(2026, 9, 22, 10);
    ServiceSlotModel slot(int confirmedUnits) => ServiceSlotModel(
      id: 'slot-1',
      serviceId: 'service-1',
      serviceOwnerId: 'provider-1',
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
      dateKey: '2026-09-22',
      capacity: 1,
      confirmedUnits: confirmedUnits,
      isBookable: true,
      status: 'open',
    );

    final available = slot(0);
    expect(available.isFull, isFalse);
    expect(available.canRequest, isTrue);
    expect(available.remainingCapacity, 1);

    final occupied = slot(1);
    expect(occupied.isFull, isTrue);
    expect(occupied.canRequest, isFalse);
    expect(occupied.remainingCapacity, 0);
  });
}
