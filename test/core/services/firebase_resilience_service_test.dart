import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/services/firebase_resilience_service.dart';

void main() {
  test('retryTransient retries retryable failures until success', () async {
    var attempts = 0;

    final result = await FirebaseResilienceService.retryTransient<String>(
      operationName: 'test.future.success',
      delays: const <Duration>[Duration.zero, Duration.zero],
      retryIf: (error) => error is TimeoutException,
      operation: () async {
        attempts += 1;
        if (attempts < 3) {
          throw TimeoutException('temporary');
        }
        return 'ok';
      },
    );

    expect(result, 'ok');
    expect(attempts, 3);
  });

  test('retryTransient rethrows non-retryable failures immediately', () async {
    var attempts = 0;

    await expectLater(
      FirebaseResilienceService.retryTransient<void>(
        operationName: 'test.future.failure',
        delays: const <Duration>[Duration.zero, Duration.zero],
        retryIf: (error) => error is TimeoutException,
        operation: () async {
          attempts += 1;
          throw StateError('permanent');
        },
      ),
      throwsA(isA<StateError>()),
    );

    expect(attempts, 1);
  });

  test(
    'retryTransientStream resubscribes after a retryable stream failure',
    () async {
      var subscriptions = 0;

      final values = await FirebaseResilienceService.retryTransientStream<int>(
        operationName: 'test.stream.recovery',
        delays: const <Duration>[Duration.zero, Duration.zero],
        retryIf: (error) => error is TimeoutException,
        streamFactory: () {
          subscriptions += 1;
          if (subscriptions == 1) {
            return Stream<int>.error(TimeoutException('temporary'));
          }
          return Stream<int>.fromIterable(const <int>[1, 2, 3]);
        },
      ).toList();

      expect(values, const <int>[1, 2, 3]);
      expect(subscriptions, 2);
    },
  );
}
