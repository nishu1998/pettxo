import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/moderation/data/repositories/report_repository.dart';

void main() {
  group('ReportRepository', () {
    test(
      'submits the canonical service payload without client-owned fields',
      () async {
        final functions = _FakeFunctions();

        final result = await ReportRepository(functions: functions)
            .createReport(
              type: ' service ',
              targetId: ' service-1 ',
              reason: 'Inappropriate content',
              description: '  Misleading photos  ',
            );

        expect(functions.callableName, 'submitReport');
        expect(functions.parameters, <String, dynamic>{
          'type': 'service',
          'targetId': 'service-1',
          'reason': 'inappropriate_content',
          'description': 'Misleading photos',
        });
        expect(result.duplicate, isFalse);
        expect(result.status, 'pending');
      },
    );

    test('submits review payload with its parent service context', () async {
      final functions = _FakeFunctions();

      await ReportRepository(functions: functions).createReport(
        type: 'review',
        targetId: ' review-1 ',
        contextId: ' service-1 ',
        reason: 'Spam',
      );

      expect(functions.parameters, <String, dynamic>{
        'type': 'review',
        'targetId': 'review-1',
        'contextId': 'service-1',
        'reason': 'spam',
      });
    });

    test('maps every required display label to a canonical reason code', () {
      expect(ReportRepository.reasonCodeForLabel('Spam'), 'spam');
      expect(
        ReportRepository.reasonCodeForLabel('Inappropriate content'),
        'inappropriate_content',
      );
      expect(
        ReportRepository.reasonCodeForLabel('Harassment'),
        'abusive_or_harmful',
      );
      expect(ReportRepository.reasonCodeForLabel('Other'), 'other');
    });

    test(
      'preserves a duplicate response for authoritative UI handling',
      () async {
        final functions = _FakeFunctions(
          response: <String, dynamic>{
            'reportId': 'report_duplicate',
            'status': 'pending',
            'duplicate': true,
          },
        );

        final result = await ReportRepository(
          functions: functions,
        ).createReport(type: 'service', targetId: 'service-1', reason: 'Other');

        expect(result.duplicate, isTrue);
      },
    );

    test('maps unauthenticated callable errors to a safe failure', () async {
      final functions = _FakeFunctions(
        error: FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'internal auth detail',
        ),
      );

      await expectLater(
        ReportRepository(
          functions: functions,
        ).createReport(type: 'service', targetId: 'service-1', reason: 'Spam'),
        throwsA(
          isA<ReportSubmissionException>()
              .having(
                (error) => error.kind,
                'kind',
                ReportSubmissionFailureKind.unauthenticated,
              )
              .having(
                (error) => error.userMessage,
                'safe message',
                'Please sign in to submit a report.',
              ),
        ),
      );
    });

    test('maps network failures without exposing Firebase details', () async {
      final functions = _FakeFunctions(
        error: FirebaseFunctionsException(
          code: 'unavailable',
          message: 'upstream host and internal request id',
        ),
      );

      await expectLater(
        ReportRepository(
          functions: functions,
        ).createReport(type: 'service', targetId: 'service-1', reason: 'Spam'),
        throwsA(
          isA<ReportSubmissionException>()
              .having(
                (error) => error.kind,
                'kind',
                ReportSubmissionFailureKind.unavailable,
              )
              .having(
                (error) => error.userMessage,
                'safe message',
                'Check your connection and try again.',
              ),
        ),
      );
    });

    test(
      'requires contextId for review reports before calling Firebase',
      () async {
        final functions = _FakeFunctions();

        await expectLater(
          ReportRepository(
            functions: functions,
          ).createReport(type: 'review', targetId: 'review-1', reason: 'Spam'),
          throwsA(
            isA<ReportSubmissionException>().having(
              (error) => error.kind,
              'kind',
              ReportSubmissionFailureKind.invalidArgument,
            ),
          ),
        );
        expect(functions.callCount, 0);
      },
    );

    test('contains no direct Firestore report write', () {
      final source = File(
        'lib/features/moderation/data/repositories/report_repository.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('cloud_firestore')));
      expect(source, isNot(contains("collection('reports')")));
      expect(source, isNot(contains('.set(')));
      expect(source, contains("httpsCallable('submitReport')"));
    });
  });
}

class _FakeFunctions implements FirebaseFunctions {
  _FakeFunctions({Map<String, dynamic>? response, this.error})
    : response =
          response ??
          <String, dynamic>{
            'reportId': 'report_123',
            'status': 'pending',
            'duplicate': false,
          };

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
    final error = functions.error;
    if (error != null) throw error;
    return _FakeResult<T>(functions.response as T);
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
