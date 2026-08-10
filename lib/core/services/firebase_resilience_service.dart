import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'network_status_service.dart';

typedef FirebaseRetryDelayStrategy = List<Duration>;
typedef FirebaseRetryPredicate = bool Function(Object error);

class FirebaseResilienceService {
  const FirebaseResilienceService._();

  static const FirebaseRetryDelayStrategy defaultBackoff = <Duration>[
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  static Future<T> retryTransient<T>({
    required String operationName,
    required Future<T> Function() operation,
    FirebaseRetryDelayStrategy delays = defaultBackoff,
    FirebaseRetryPredicate retryIf = isRetryableFirebaseError,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 0; attempt <= delays.length; attempt++) {
      final attemptNumber = attempt + 1;
      try {
        final result = await operation();
        _log(
          operationName: operationName,
          phase: 'success',
          attempt: attemptNumber,
          recoveredAfterRetry: attempt > 0,
        );
        return result;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        final retryable = retryIf(error);
        if (!retryable || attempt == delays.length) {
          _log(
            operationName: operationName,
            phase: 'failed',
            attempt: attemptNumber,
            error: error,
            retryable: retryable,
          );
          Error.throwWithStackTrace(error, stackTrace);
        }

        final delay = delays[attempt];
        _log(
          operationName: operationName,
          phase: 'retry_scheduled',
          attempt: attemptNumber,
          error: error,
          retryable: true,
          retryDelay: delay,
        );
        await Future<void>.delayed(delay);
      }
    }

    Error.throwWithStackTrace(
      lastError ?? StateError('Unknown retry failure.'),
      lastStackTrace ?? StackTrace.current,
    );
  }

  static Stream<T> retryTransientStream<T>({
    required String operationName,
    required Stream<T> Function() streamFactory,
    FirebaseRetryDelayStrategy delays = defaultBackoff,
    FirebaseRetryPredicate retryIf = isRetryableFirebaseError,
  }) async* {
    var attempt = 0;

    while (true) {
      try {
        await for (final value in streamFactory()) {
          if (attempt > 0) {
            _log(
              operationName: operationName,
              phase: 'stream_recovered',
              attempt: attempt + 1,
              recoveredAfterRetry: true,
            );
            attempt = 0;
          }
          yield value;
        }
        return;
      } catch (error, stackTrace) {
        final retryable = retryIf(error);
        if (!retryable || attempt >= delays.length) {
          _log(
            operationName: operationName,
            phase: 'stream_failed',
            attempt: attempt + 1,
            error: error,
            retryable: retryable,
          );
          Error.throwWithStackTrace(error, stackTrace);
        }

        final delay = delays[attempt];
        _log(
          operationName: operationName,
          phase: 'stream_retry_scheduled',
          attempt: attempt + 1,
          error: error,
          retryable: true,
          retryDelay: delay,
        );
        attempt += 1;
        await Future<void>.delayed(delay);
      }
    }
  }

  static bool isRetryableFirebaseError(Object error) {
    if (error is TimeoutException) return true;
    if (error is FirebaseException) {
      switch (error.code.trim().toLowerCase()) {
        case 'unavailable':
        case 'deadline-exceeded':
        case 'network-request-failed':
        case 'aborted':
          return true;
      }
    }
    return false;
  }

  static void logImageFailure({
    required String operationName,
    required Object error,
    String? imageUrl,
  }) {
    _log(
      operationName: operationName,
      phase: 'image_failed',
      attempt: 1,
      error: error,
      extra: {
        if (imageUrl != null && imageUrl.trim().isNotEmpty)
          'imageHost': Uri.tryParse(imageUrl)?.host ?? '',
      },
    );
  }

  static void _log({
    required String operationName,
    required String phase,
    required int attempt,
    Object? error,
    bool? retryable,
    Duration? retryDelay,
    bool recoveredAfterRetry = false,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    if (!kDebugMode) return;

    final exception = error is FirebaseException ? error : null;
    final apps = Firebase.apps;
    var currentUserId = '';
    if (apps.isNotEmpty) {
      currentUserId = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    }
    final messageParts = <String>[
      '[FirebaseResilience]',
      'timestamp=${DateTime.now().toIso8601String()}',
      'operation=$operationName',
      'phase=$phase',
      'attempt=$attempt',
      'firebaseInitialized=${apps.isNotEmpty}',
      'projectId=${apps.isNotEmpty ? apps.first.options.projectId : ''}',
      'currentUserPresent=${currentUserId.isNotEmpty}',
      'currentUserId=$currentUserId',
      'networkOnline=${NetworkStatusService.instance.isOnline}',
      'recoveredAfterRetry=$recoveredAfterRetry',
      if (exception != null) 'plugin=${exception.plugin}',
      if (exception != null) 'code=${exception.code}',
      if (exception != null) 'message=${(exception.message ?? '').trim()}',
      if (error is TimeoutException) 'code=timeout',
      if (error is TimeoutException)
        'message=${error.message?.trim().isNotEmpty == true ? error.message!.trim() : 'Operation timed out.'}',
      if (retryable != null) 'retryable=$retryable',
      if (retryDelay != null) 'retryDelayMs=${retryDelay.inMilliseconds}',
      ...extra.entries.map((entry) => '${entry.key}=${entry.value ?? ''}'),
    ];
    debugPrint(messageParts.join(' '));
  }
}
