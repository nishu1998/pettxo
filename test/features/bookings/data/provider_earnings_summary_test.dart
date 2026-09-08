import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/domain/models/provider_earnings_summary.dart';
import 'package:pettexo/features/bookings/data/repositories/booking_repository.dart';

Map<String, dynamic> payload() => {
  'providerId': 'provider',
  'lifetimeEarnedPaise': 170000,
  'finalizedRecordCount': 3,
  'provisionalRecordCount': 1,
  'projectionVersion': 1,
  'currency': 'INR',
  'asOf': '2026-09-08T00:00:00Z',
};

void main() {
  test('summary parses full-history integer paise independently from rows', () {
    final result = ProviderEarningsSummary.fromMap(payload());
    expect(result.lifetimeEarnedPaise, 170000);
    expect(result.providerId, 'provider');
    expect(result.finalizedRecordCount, 3);
    expect(result.provisionalRecordCount, 1);
  });
  for (final value in [-1, 0.5, double.nan, double.infinity, '850', null]) {
    test('rejects malformed total $value rather than returning zero', () {
      expect(
        () => ProviderEarningsSummary.fromMap({
          ...payload(),
          'lifetimeEarnedPaise': value,
        }),
        throwsFormatException,
      );
    });
  }
  test('rejects incompatible schema and missing timestamp', () {
    expect(
      () => ProviderEarningsSummary.fromMap({
        ...payload(),
        'projectionVersion': 2,
      }),
      throwsFormatException,
    );
    expect(
      () => ProviderEarningsSummary.fromMap({...payload(), 'asOf': null}),
      throwsFormatException,
    );
  });
  test(
    'repository uses its separate lifetime callable without a row query',
    () async {
      final functions = FakeFunctions();
      final repository = BookingRepository(functions: functions);
      expect(
        (await repository.getProviderEarningsSummary()).lifetimeEarnedPaise,
        170000,
      );
      expect(functions.name, 'getProviderLifetimeEarningsV3');
      expect(functions.parameters, null);
    },
  );
  test(
    'repository propagates reconciliation errors without a local total fallback',
    () async {
      final functions = FakeFunctions()
        ..error = FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Reconcile',
        );
      await expectLater(
        BookingRepository(functions: functions).getProviderEarningsSummary(),
        throwsA(isA<FirebaseFunctionsException>()),
      );
    },
  );
}

class FakeFunctions implements FirebaseFunctions {
  String? name;
  dynamic parameters;
  Exception? error;
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    this.name = name;
    return FakeCallable(this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCallable implements HttpsCallable {
  FakeCallable(this.functions);
  final FakeFunctions functions;
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    functions.parameters = parameters;
    if (functions.error != null) throw functions.error!;
    return FakeResult<T>(payload() as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeResult<T> implements HttpsCallableResult<T> {
  FakeResult(this.data);
  @override
  final T data;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
