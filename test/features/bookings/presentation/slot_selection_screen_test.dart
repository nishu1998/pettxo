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
    'full slots are hidden while partially available slots are displayed',
    (tester) async {
      await pump(tester);
      ServiceSlotModel slot(String id, int confirmedUnits) => ServiceSlotModel(
        id: id,
        serviceId: 'service',
        serviceOwnerId: 'provider',
        startAt: now.add(const Duration(hours: 9)),
        endAt: now.add(const Duration(hours: 10, minutes: 30)),
        dateKey: '2026-09-14',
        capacity: 2,
        confirmedUnits: confirmedUnits,
        isBookable: true,
        status: 'open',
      );
      repository.changes.add([slot('full', 2), slot('open', 0)]);
      await tester.pumpAndSettle();
      expect(find.text('Fully booked'), findsNothing);
      expect(find.text('2 spots left'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'confirmation hides a slot and cancellation makes it visible after reload',
    (tester) async {
      await pump(tester);
      ServiceSlotModel slot(int confirmedUnits) => ServiceSlotModel(
        id: 'last',
        serviceId: 'service',
        serviceOwnerId: 'provider',
        startAt: now.add(const Duration(hours: 9)),
        endAt: now.add(const Duration(hours: 10, minutes: 30)),
        dateKey: '2026-09-14',
        capacity: 1,
        confirmedUnits: confirmedUnits,
        isBookable: true,
        status: 'open',
      );
      repository.changes.add([slot(0)]);
      await tester.pumpAndSettle();
      expect(find.text('1 spot left'), findsOneWidget);
      repository.changes.add([slot(1)]);
      await tester.pumpAndSettle();
      expect(find.text('1 spot left'), findsNothing);
      expect(find.text('No slots for this date'), findsOneWidget);
      repository.changes.add([slot(0)]);
      await tester.pumpAndSettle();
      expect(find.text('1 spot left'), findsOneWidget);
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

  testWidgets(
    'callable slots render the complete 01:00-23:00 IST window chronologically',
    (tester) async {
      await pump(tester);
      final firstStart = DateTime.parse('2026-10-20T19:30:00.000Z');
      final slots = List<ServiceSlotModel>.generate(22, (index) {
        final start = firstStart.add(Duration(hours: index));
        final end = start.add(const Duration(hours: 1));
        return ServiceSlotModel.fromCallableMap(<String, dynamic>{
          'id': '2026-10-21_${(60 + index * 60).toString().padLeft(4, '0')}',
          'serviceId': 'service',
          'serviceOwnerId': 'provider',
          'startAt': start.toIso8601String(),
          'endAt': end.toIso8601String(),
          'dateKey': '2026-10-21',
          'capacity': 1,
          'confirmedUnits': 0,
          'isBookable': true,
          'status': 'open',
        });
      });

      repository.changes.add(slots);
      await tester.pumpAndSettle();
      expect(find.text('1:00 AM - 2:00 AM'), findsOneWidget);
      expect(find.text('11:30 AM - 12:30 PM'), findsNothing);

      await tester.drag(find.byType(ListView).last, const Offset(-5000, 0));
      await tester.pumpAndSettle();
      expect(find.text('10:00 PM - 11:00 PM'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
