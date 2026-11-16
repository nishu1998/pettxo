import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/blocking/data/blocked_relationship_repository.dart';
import 'package:pettexo/features/blocking/presentation/user_safety_dialogs.dart';

void main() {
  testWidgets('ordinary block confirmation uses the required warning', (
    tester,
  ) async {
    await _pumpLauncher(
      tester,
      onPressed: (context) => showBlockConfirmation(
        context,
        const UserRelationshipState(
          relationshipBlocked: false,
          blockedByCaller: false,
          canBlock: true,
          reasonCode: '',
          acceptedUnpaidBookingCount: 0,
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Block this user?'), findsOneWidget);
    expect(find.text('Block User'), findsOneWidget);
    expect(find.textContaining("won't be able to message"), findsOneWidget);
  });

  testWidgets('accepted-unpaid state uses destructive cancellation warning', (
    tester,
  ) async {
    await _pumpLauncher(
      tester,
      onPressed: (context) => showBlockConfirmation(
        context,
        const UserRelationshipState(
          relationshipBlocked: false,
          blockedByCaller: false,
          canBlock: true,
          reasonCode: '',
          acceptedUnpaidBookingCount: 1,
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Block user and cancel unpaid bookings?'), findsOneWidget);
    expect(find.text('Keep Bookings'), findsOneWidget);
    expect(find.text('Block and Cancel'), findsOneWidget);
  });

  testWidgets('protected booking keeps reporting and support available', (
    tester,
  ) async {
    await _pumpLauncher(
      tester,
      onPressed: (context) => showBlockingUnavailable(
        context,
        reasonCode: 'PROTECTED_BOOKING_EXISTS',
        reportTargetUid: 'target-user',
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Blocking temporarily unavailable'), findsOneWidget);
    expect(find.textContaining('active paid booking'), findsOneWidget);
    expect(find.text('Report User'), findsOneWidget);
  });

  testWidgets('payment reconciliation has distinct safe messaging', (
    tester,
  ) async {
    await _pumpLauncher(
      tester,
      onPressed: (context) => showBlockingUnavailable(
        context,
        reasonCode: 'PAYMENT_RECONCILIATION_REQUIRED',
        reportTargetUid: 'target-user',
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('payment needs verification'), findsOneWidget);
    expect(find.textContaining('booking-'), findsNothing);
  });

  test('error mapping never exposes Firebase or booking identifiers', () {
    expect(
      blockingFailureMessage(BlockingFailureKind.paymentReconciliation),
      contains('Contact Pettxo Support'),
    );
    expect(
      blockingFailureMessage(BlockingFailureKind.protectedBooking),
      isNot(contains('bookingId')),
    );
    expect(
      blockingFailureMessage(BlockingFailureKind.unavailable),
      'Check your connection and try again.',
    );
  });
}

Future<void> _pumpLauncher(
  WidgetTester tester, {
  required Future<dynamic> Function(BuildContext context) onPressed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => onPressed(context),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}
