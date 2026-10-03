import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/data/repositories/booking_repository.dart';

void main() {
  test(
    'repository requests sanitized canonical availability for one date',
    () async {
      final functions = _FakeFunctions();
      final slots = await BookingRepository(functions: functions)
          .watchServiceSlotsForDate(
            serviceId: ' service-1 ',
            date: DateTime(2026, 9, 14),
          )
          .first;

      expect(functions.name, 'listBookableServiceSlotsV3');
      expect(functions.parameters, <String, dynamic>{
        'serviceId': 'service-1',
        'dateKey': '2026-09-14',
      });
      expect(slots, hasLength(1));
      expect(slots.single.confirmedUnits, 1);
      expect(slots.single.remainingCapacity, 1);
    },
  );

  test('repository rejects a response without a sanitized slots list', () {
    final functions = _FakeFunctions()..payload = <String, dynamic>{};
    expect(
      BookingRepository(functions: functions)
          .watchServiceSlotsForDate(
            serviceId: 'service-1',
            date: DateTime(2026, 9, 14),
          )
          .first,
      throwsFormatException,
    );
  });
}

class _FakeFunctions implements FirebaseFunctions {
  String? name;
  dynamic parameters;
  Map<String, dynamic> payload = <String, dynamic>{
    'serviceId': 'service-1',
    'dateKey': '2026-09-14',
    'slots': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': '2026-09-14_0900',
        'serviceId': 'service-1',
        'serviceOwnerId': 'provider-1',
        'startAt': '2026-09-14T03:30:00.000Z',
        'endAt': '2026-09-14T04:30:00.000Z',
        'dateKey': '2026-09-14',
        'capacity': 2,
        'confirmedUnits': 1,
        'isBookable': true,
        'status': 'open',
      },
    ],
  };

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    this.name = name;
    return _FakeCallable(this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCallable implements HttpsCallable {
  const _FakeCallable(this.functions);

  final _FakeFunctions functions;

  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    functions.parameters = parameters;
    return _FakeResult<T>(functions.payload as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResult<T> implements HttpsCallableResult<T> {
  const _FakeResult(this.data);

  @override
  final T data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
