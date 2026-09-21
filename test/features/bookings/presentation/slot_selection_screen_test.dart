import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/data/repositories/booking_repository.dart';
import 'package:pettexo/features/bookings/domain/models/service_slot_model.dart';
import 'package:pettexo/features/bookings/presentation/screens/slot_selection_screen.dart';

class _Repository implements BookingRepository {
  final changes = StreamController<List<ServiceSlotModel>>.broadcast();
  DateTime? selectedDate;
  @override
  Stream<List<ServiceSlotModel>> watchServiceSlotsForDate({
    required String serviceId,
    required DateTime date,
  }) {
    selectedDate = date;
    return changes.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Repository repository;
  final now = DateTime.parse('2026-09-13T18:30:00Z');
  setUp(() => repository = _Repository());
  tearDown(() async => repository.changes.close());
  Future<void> pump(WidgetTester tester, {DateTime? suggested}) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SlotSelectionScreen(
          serviceId: 'service',
          serviceName: 'Walking',
          price: 100,
          durationMinutes: 90,
          schedulingMode: 'fixedDuration',
          providerId: 'provider',
          bookingRepository: repository,
          nowOverride: () => now,
          bookingAccessCheckOverride: (_) => true,
          suggestedSlotStartAt: suggested,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('slot query uses IST date and shows an honest empty state', (
    tester,
  ) async {
    await pump(tester);
    expect(repository.selectedDate, DateTime(2026, 9, 14));
    repository.changes.add([]);
    await tester.pump();
    expect(find.text('No slots for this date'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'query failures remain errors rather than an empty availability list',
    (tester) async {
      await pump(tester);
      repository.changes.addError(StateError('query failed'));
      await tester.pump();
      expect(find.text('Could not load slots'), findsOneWidget);
      expect(find.text('No slots for this date'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'fetched full slots remain disabled while available slots are displayed',
    (tester) async {
      await pump(tester);
      ServiceSlotModel slot(String id, int acceptedCount) => ServiceSlotModel(
        id: id,
        serviceId: 'service',
        serviceOwnerId: 'provider',
        startAt: now.add(const Duration(hours: 9)),
        endAt: now.add(const Duration(hours: 10, minutes: 30)),
        dateKey: '2026-09-14',
        capacity: 2,
        acceptedCount: acceptedCount,
        isBookable: true,
        status: 'open',
      );
      repository.changes.add([slot('full', 2), slot('open', 0)]);
      await tester.pumpAndSettle();
      expect(find.text('Fully booked'), findsOneWidget);
      expect(find.text('2 spots left'), findsOneWidget);
      final fullTile = find
          .ancestor(
            of: find.text('Fully booked'),
            matching: find.byType(GestureDetector),
          )
          .first;
      expect(tester.widget<GestureDetector>(fullTile).onTap, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'a slot becomes unavailable on the next slot snapshot after confirmation',
    (tester) async {
      await pump(tester);
      ServiceSlotModel slot(int acceptedCount) => ServiceSlotModel(
        id: 'last',
        serviceId: 'service',
        serviceOwnerId: 'provider',
        startAt: now.add(const Duration(hours: 9)),
        endAt: now.add(const Duration(hours: 10, minutes: 30)),
        dateKey: '2026-09-14',
        capacity: 1,
        acceptedCount: acceptedCount,
        isBookable: true,
        status: 'open',
      );
      repository.changes.add([slot(0)]);
      await tester.pumpAndSettle();
      expect(find.text('1 spot left'), findsOneWidget);
      repository.changes.add([slot(1)]);
      await tester.pumpAndSettle();
      expect(find.text('Fully booked'), findsOneWidget);
      final tile = find
          .ancestor(
            of: find.text('Fully booked'),
            matching: find.byType(GestureDetector),
          )
          .first;
      expect(tester.widget<GestureDetector>(tile).onTap, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'suggested day 30 is selectable but day 31 is outside the customer horizon',
    (tester) async {
      await pump(
        tester,
        suggested: now.add(const Duration(days: 30, hours: 9)),
      );
      expect(repository.selectedDate, DateTime(2026, 10, 14));
      await tester.pumpWidget(const SizedBox());
      await pump(
        tester,
        suggested: now.add(const Duration(days: 31, hours: 9)),
      );
      expect(repository.selectedDate, DateTime(2026, 9, 14));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
