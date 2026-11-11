import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/widgets/app_buttons.dart';
import 'package:pettexo/features/moderation/data/repositories/report_repository.dart';
import 'package:pettexo/features/moderation/presentation/widgets/report_sheet.dart';

void main() {
  tearDown(() async {
    // Let any snackbar overlay timers and animations finish between tests.
    await Future<void>.delayed(Duration.zero);
  });

  testWidgets('service report sheet prevents repeat submission while loading', (
    tester,
  ) async {
    final functions = _PendingFunctions();
    await _pumpLauncher(
      tester,
      repository: ReportRepository(functions: functions),
      type: 'service',
      targetId: 'service-1',
    );

    await tester.tap(find.text('Open report'));
    await tester.pumpAndSettle();
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Inappropriate content'), findsOneWidget);

    await tester.tap(find.text('Spam'));
    await tester.ensureVisible(find.text('Submit Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit Report'));
    await tester.pump();

    expect(find.text('Submitting...'), findsOneWidget);
    expect(functions.callCount, 1);
    final submittingButton = tester.widget<GradientButton>(
      find.widgetWithText(GradientButton, 'Submitting...'),
    );
    expect(submittingButton.onPressed, isNull);

    functions.complete(duplicate: false);
    await tester.pumpAndSettle();
    expect(
      find.text('Report submitted. Our team will review it.'),
      findsOneWidget,
    );
  });

  testWidgets('review report sends contextId and shows duplicate feedback', (
    tester,
  ) async {
    final functions = _PendingFunctions();
    await _pumpLauncher(
      tester,
      repository: ReportRepository(functions: functions),
      type: 'review',
      targetId: 'review-1',
      contextId: 'service-1',
    );

    await tester.tap(find.text('Open report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other'));
    await tester.ensureVisible(find.text('Submit Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit Report'));
    await tester.pump();

    expect(functions.parameters, <String, dynamic>{
      'type': 'review',
      'targetId': 'review-1',
      'contextId': 'service-1',
      'reason': 'other',
    });

    functions.complete(duplicate: true);
    await tester.pumpAndSettle();
    expect(find.text("You've already reported this."), findsOneWidget);
    expect(
      find.text('Report submitted. Our team will review it.'),
      findsNothing,
    );
  });
}

Future<void> _pumpLauncher(
  WidgetTester tester, {
  required ReportRepository repository,
  required String type,
  required String targetId,
  String? contextId,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ReportSheet.show(
              context: context,
              type: type,
              targetId: targetId,
              contextId: contextId,
              repository: repository,
              isAuthenticated: true,
            ),
            child: const Text('Open report'),
          ),
        ),
      ),
    ),
  );
}

class _PendingFunctions implements FirebaseFunctions {
  final Completer<Map<String, dynamic>> _completer =
      Completer<Map<String, dynamic>>();
  dynamic parameters;
  int callCount = 0;

  void complete({required bool duplicate}) {
    _completer.complete(<String, dynamic>{
      'reportId': 'report_123',
      'status': 'pending',
      'duplicate': duplicate,
    });
  }

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    expect(name, 'submitReport');
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
    functions.parameters = parameters;
    final response = await functions._completer.future;
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
