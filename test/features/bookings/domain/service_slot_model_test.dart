import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/domain/models/service_slot_model.dart';

void main() {
  test(
    'capacity-one slot becomes unavailable after acceptedCount reaches one',
    () {
      final start = DateTime.utc(2026, 9, 22, 10);
      ServiceSlotModel slot(int acceptedCount) => ServiceSlotModel(
        id: 'slot-1',
        serviceId: 'service-1',
        serviceOwnerId: 'provider-1',
        startAt: start,
        endAt: start.add(const Duration(hours: 1)),
        dateKey: '2026-09-22',
        capacity: 1,
        acceptedCount: acceptedCount,
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
    },
  );
}
