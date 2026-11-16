import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/blocking/data/blocked_relationship_repository.dart';

void main() {
  group('BlockedRelationshipRepository callables', () {
    test('reads the complete authoritative relationship state', () async {
      final functions = _FakeFunctions(<String, dynamic>{
        'relationshipBlocked': true,
        'blockedByCaller': false,
        'canBlock': false,
        'reasonCode': 'PROTECTED_BOOKING_EXISTS',
        'acceptedUnpaidBookingCount': 2,
      });
      final repository = _repository(functions);

      final state = await repository.getRelationshipState(' target-1 ');

      expect(functions.callableName, 'getUserRelationshipStateV1');
      expect(functions.parameters, <String, dynamic>{'targetUid': 'target-1'});
      expect(state.relationshipBlocked, isTrue);
      expect(state.blockedByOther, isTrue);
      expect(state.canBlock, isFalse);
      expect(state.reasonCode, 'PROTECTED_BOOKING_EXISTS');
      expect(state.acceptedUnpaidBookingCount, 2);
    });

    test(
      'block sends no client-owned authority and returns cancellation count',
      () async {
        final functions = _FakeFunctions(<String, dynamic>{
          'relationshipBlocked': true,
          'blockedByCaller': true,
          'cancelledBookingIds': <String>['booking-a', 'booking-b'],
          'idempotentReplay': false,
        });

        final result = await _repository(functions).blockUser('target-1');

        expect(functions.callableName, 'blockUserV1');
        expect(functions.parameters, <String, dynamic>{
          'targetUid': 'target-1',
        });
        expect(result.cancelledBookingCount, 2);
        expect(result.blockedByCaller, isTrue);
      },
    );

    test('unblock preserves an independent reciprocal block', () async {
      final functions = _FakeFunctions(<String, dynamic>{
        'relationshipBlocked': true,
        'blockedByCaller': false,
        'idempotentReplay': false,
      });

      final result = await _repository(functions).unblockUser('target-1');

      expect(functions.callableName, 'unblockUserV1');
      expect(result.relationshipBlocked, isTrue);
      expect(result.blockedByCaller, isFalse);
    });

    test('maps protected and reconciliation backend details safely', () async {
      for (final entry in <String, BlockingFailureKind>{
        'PROTECTED_BOOKING_EXISTS': BlockingFailureKind.protectedBooking,
        'PAYMENT_RECONCILIATION_REQUIRED':
            BlockingFailureKind.paymentReconciliation,
        'PAIR_BOOKING_LIMIT_EXCEEDED': BlockingFailureKind.supportRequired,
        'USER_BLOCKING_DISABLED': BlockingFailureKind.blockingDisabled,
        'RELATIONSHIP_MIGRATION_NOT_VERIFIED':
            BlockingFailureKind.blockingDisabled,
        'BLOCKING_ACTIVATION_NOT_AUDITED': BlockingFailureKind.blockingDisabled,
      }.entries) {
        final functions = _FakeFunctions(
          const <String, dynamic>{},
          error: FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'private booking detail',
            details: <String, dynamic>{'code': entry.key},
          ),
        );
        await expectLater(
          _repository(functions).blockUser('target-1'),
          throwsA(
            isA<BlockingException>().having(
              (error) => error.kind,
              'kind',
              entry.value,
            ),
          ),
        );
      }
    });

    test('signed-out state fails before invoking a callable', () async {
      final functions = _FakeFunctions(const <String, dynamic>{});
      final repository = BlockedRelationshipRepository(
        functions: functions,
        currentUidOverride: () => '',
      );

      await expectLater(
        repository.blockUser('target-1'),
        throwsA(
          isA<BlockingException>().having(
            (error) => error.kind,
            'kind',
            BlockingFailureKind.unauthenticated,
          ),
        ),
      );
      expect(functions.callCount, 0);
    });

    test(
      'overlapping calls remain server-authoritative and independently complete',
      () async {
        final functions = _PendingFunctions();
        final repository = _repository(functions);

        final first = repository.blockUser('target-1');
        final second = repository.blockUser('target-1');
        expect(functions.callCount, 2);

        functions.complete();
        expect((await first).blockedByCaller, isTrue);
        expect((await second).blockedByCaller, isTrue);
      },
    );
  });
}

BlockedRelationshipRepository _repository(FirebaseFunctions functions) {
  return BlockedRelationshipRepository(
    functions: functions,
    currentUidOverride: () => 'caller-1',
  );
}

class _FakeFunctions implements FirebaseFunctions {
  _FakeFunctions(this.response, {this.error});

  final Map<String, dynamic> response;
  final Object? error;
  String? callableName;
  dynamic parameters;
  int callCount = 0;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    callableName = name;
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
    functions.callCount += 1;
    functions.parameters = parameters;
    if (functions.error case final error?) throw error;
    return _FakeResult<T>(functions.response as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingFunctions implements FirebaseFunctions {
  final Completer<Map<String, dynamic>> _response =
      Completer<Map<String, dynamic>>();
  int callCount = 0;

  void complete() => _response.complete(<String, dynamic>{
    'relationshipBlocked': true,
    'blockedByCaller': true,
    'cancelledBookingIds': <String>[],
    'idempotentReplay': false,
  });

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    return _PendingCallable(this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingCallable implements HttpsCallable {
  const _PendingCallable(this.functions);

  final _PendingFunctions functions;

  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    functions.callCount += 1;
    final response = await functions._response.future;
    return _FakeResult<T>(response as T);
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
