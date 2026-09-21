import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/data/repositories/booking_repository.dart';
import 'package:pettexo/features/bookings/domain/models/provider_earning_record.dart';
import 'package:pettexo/features/bookings/domain/models/provider_earnings_summary.dart';
import 'package:pettexo/features/bookings/presentation/screens/provider_earnings_screen.dart';
import 'package:pettexo/features/bookings/presentation/utils/provider_earnings_presentation.dart';

ProviderEarningRecord record({
  int? amount = 85000,
  String phase = 'FINALIZED',
  String outcome = 'NORMAL_COMPLETION',
  String status = 'READY',
  String id = 'booking-1',
}) => ProviderEarningRecord.fromMap(id, {
  'bookingId': id,
  'providerId': 'provider',
  'earningsSchemaVersion': 1,
  'providerFinalEntitlementPaise': amount,
  'amountPaise': 999999,
  'earningsStatus': phase,
  'earningsOutcome': outcome,
  'status': status,
  'createdAt': '2026-01-01',
  'updatedAt': '2026-09-08',
  'earningsOutcomeAt': '2026-09-07',
});
ProviderEarningsSummary summary(int amount, {String uid = 'provider'}) =>
    ProviderEarningsSummary(
      providerId: uid,
      lifetimeEarnedPaise: amount,
      finalizedRecordCount: 1000,
      provisionalRecordCount: 0,
      asOf: DateTime(2026, 9, 9),
    );

class FakeRepo implements BookingRepository {
  final history = StreamController<List<ProviderEarningRecord>>.broadcast();
  Future<ProviderEarningsSummary> Function() load = () async =>
      summary(1000000);
  int calls = 0;
  int watches = 0;
  final uids = <String>[];
  @override
  Future<ProviderEarningsSummary> getProviderEarningsSummary() {
    calls++;
    return load();
  }

  @override
  Stream<List<ProviderEarningRecord>> watchProviderEarnings(
    String currentUserId, {
    int limit = 120,
  }) {
    expect(limit, 120);
    watches++;
    uids.add(currentUserId);
    return history.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUser implements User {
  FakeUser(this.uid);
  @override
  final String uid;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuth implements FirebaseAuth {
  final changes = StreamController<User?>.broadcast();
  @override
  User? currentUser = FakeUser('provider');
  @override
  Stream<User?> authStateChanges() => changes.stream;
  void change(String? uid) {
    currentUser = uid == null ? null : FakeUser(uid);
    changes.add(currentUser);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeRepo repo;
  late FakeAuth auth;
  setUp(() {
    repo = FakeRepo();
    auth = FakeAuth();
  });
  tearDown(() async {
    await repo.history.close();
    await auth.changes.close();
  });
  Future<void> mount(
    WidgetTester tester, {
    ThemeMode mode = ThemeMode.light,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(),
        darkTheme: ThemeData.dark(),
        themeMode: mode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ProviderEarningsScreen(repository: repo, auth: auth),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'lifetime uses summary 10000 rather than two history rows totaling 1350',
    (tester) async {
      await mount(tester);
      repo.history.add([record(), record(amount: 50000, id: 'booking-2')]);
      await tester.pump();
      expect(find.text('₹10,000.00'), findsOneWidget);
      expect(find.text('₹1,350.00'), findsNothing);
      expect(find.text('₹850.00'), findsOneWidget);
      expect(find.text('Recent records · Up to 120 bookings'), findsOneWidget);
      expect(repo.uids, ['provider']);
    },
  );
  testWidgets('120 visible records cannot cap the lifetime total', (
    tester,
  ) async {
    repo.load = () async => summary(85000000);
    await mount(tester);
    repo.history.add(List.generate(120, (i) => record(id: 'booking-$i')));
    await tester.pump();
    expect(find.text('₹850,000.00'), findsOneWidget);
    expect(find.text('₹102,000.00'), findsNothing);
  });
  testWidgets(
    'loading shows no false zero and history can load independently',
    (tester) async {
      final pending = Completer<ProviderEarningsSummary>();
      repo.load = () => pending.future;
      await mount(tester);
      repo.history.add([record()]);
      await tester.pump();
      expect(find.byKey(const Key('lifetime-total')), findsNothing);
      expect(find.text('₹0.00'), findsNothing);
      expect(find.text('₹850.00'), findsOneWidget);
      pending.complete(summary(85000));
      await tester.pump();
    },
  );
  testWidgets('confirmed zero and empty history show genuine empty state', (
    tester,
  ) async {
    repo.load = () async => summary(0);
    await mount(tester);
    repo.history.add([]);
    await tester.pump();
    expect(find.text('₹0.00'), findsOneWidget);
    expect(find.text('No earnings yet'), findsOneWidget);
  });
  testWidgets('summary errors have safe retry and do not hide history', (
    tester,
  ) async {
    repo.load = () async => throw Exception('SECRET FIREBASE ERROR');
    await mount(tester);
    repo.history.add([record()]);
    await tester.pump();
    expect(
      find.text('We couldn’t load your lifetime earnings.'),
      findsOneWidget,
    );
    expect(find.textContaining('SECRET'), findsNothing);
    expect(find.text('₹850.00'), findsOneWidget);
    repo.load = () async => summary(85000);
    await tester.tap(find.text('Retry total'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('lifetime-total')), findsOneWidget);
    expect(repo.watches, 1);
  });
  testWidgets('retry total leaves failing history independent', (tester) async {
    repo.load = () async => throw Exception('private total error');
    await mount(tester);
    repo.history.addError(Exception('private history error'));
    await tester.pump();
    repo.load = () async => summary(85000);
    await tester.tap(find.text('Retry total'));
    await tester.pump();
    await tester.pump();
    expect(repo.calls, 2);
    expect(repo.watches, 1);
    expect(
      find.text('We couldn’t load your earnings history.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('lifetime-total')), findsOneWidget);
  });

  testWidgets('history errors are not empty and retry replaces subscription', (
    tester,
  ) async {
    await mount(tester);
    repo.history.addError(Exception('private'));
    await tester.pump();
    expect(
      find.text('We couldn’t load your earnings history.'),
      findsOneWidget,
    );
    expect(find.text('No earnings yet'), findsNothing);
    await tester.tap(find.text('Retry history'));
    await tester.pump();
    await tester.pump();
    // The controller is created by setUp outside the widget fake-async zone.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(repo.calls, 1);
    expect(repo.watches, 2);
    repo.history.add([record()]);
    await tester.pump();
    await tester.pump();
    expect(find.text('₹850.00'), findsOneWidget);
  });
  testWidgets(
    'cancellation uses 350 canonical compensation with outcome date',
    (tester) async {
      await mount(tester);
      repo.history.add([
        record(amount: 35000, outcome: 'CUSTOMER_CANCELLATION'),
      ]);
      await tester.pump();
      expect(find.text('₹350.00'), findsOneWidget);
      expect(find.text('Cancellation compensation'), findsOneWidget);
      expect(find.text('Outcome date 07/09/2026'), findsOneWidget);
      expect(find.text('₹850.00'), findsNothing);
    },
  );
  testWidgets(
    'held provisional dispute never presents expected money as earned',
    (tester) async {
      await mount(tester);
      repo.history.add([
        record(amount: null, phase: 'HELD', outcome: 'OPEN_DISPUTE'),
      ]);
      await tester.pump();
      expect(find.text('Earning pending finalization'), findsOneWidget);
      expect(find.textContaining('Payout:'), findsNothing);
      expect(find.text('Amount not final yet'), findsOneWidget);
      expect(find.text('Not included in Total Earned yet.'), findsOneWidget);
    },
  );
  testWidgets('held final entitlement remains a definitive earning', (
    tester,
  ) async {
    await mount(tester);
    repo.history.add([record(phase: 'HELD', status: 'HELD')]);
    await tester.pump();
    expect(find.text('Earned'), findsOneWidget);
    expect(find.text('Payout: On hold'), findsOneWidget);
    expect(find.text('₹850.00'), findsOneWidget);
    expect(find.text('Amount not final yet'), findsNothing);
  });
  testWidgets('paid earning stays visible and summary remains full lifetime', (
    tester,
  ) async {
    await mount(tester);
    repo.history.add([record(status: 'PAID')]);
    await tester.pump();
    expect(find.text('Earned'), findsOneWidget);
    expect(find.text('Payout: Paid'), findsOneWidget);
    expect(find.text('₹850.00'), findsOneWidget);
    expect(find.text('₹10,000.00'), findsOneWidget);
  });
  testWidgets(
    'zero final cancellation is hidden without hiding provisional records',
    (tester) async {
      await mount(tester);
      repo.history.add([record(amount: 0, outcome: 'PROVIDER_CANCELLATION')]);
      await tester.pump();
      expect(find.text('Cancelled'), findsNothing);
      expect(find.text('₹0.00'), findsNothing);
      expect(find.text('No recent earnings to show'), findsOneWidget);
    },
  );
  testWidgets('rebuild and refresh keep one live history subscription', (
    tester,
  ) async {
    await mount(tester);
    repo.history.add([record()]);
    await tester.pump();
    await mount(tester, mode: ThemeMode.dark);
    expect(repo.calls, 1);
    expect(repo.watches, 1);
    await tester.tap(find.byTooltip('Refresh earnings'));
    await tester.pump();
    await tester.pump();
    expect(repo.calls, 2);
    expect(repo.watches, 1);
  });
  testWidgets('signed-out screen performs no financial requests', (
    tester,
  ) async {
    auth.currentUser = null;
    await mount(tester);
    expect(find.text('Sign in to view your earnings.'), findsOneWidget);
    expect(repo.calls, 0);
    expect(repo.watches, 0);
  });
  testWidgets('sign-out clears data and ignores late summary completion', (
    tester,
  ) async {
    final pending = Completer<ProviderEarningsSummary>();
    repo.load = () => pending.future;
    await mount(tester);
    auth.change(null);
    await tester.pump();
    pending.complete(summary(85000));
    await tester.pump();
    expect(find.text('₹850.00'), findsNothing);
    expect(find.text('Sign in to view your earnings.'), findsOneWidget);
    expect(repo.history.hasListener, false);
  });
  testWidgets('cross-account summary is rejected', (tester) async {
    repo.load = () async => summary(85000, uid: 'other');
    await mount(tester);
    expect(
      find.text('We couldn’t load your lifetime earnings.'),
      findsOneWidget,
    );
    expect(find.text('₹850.00'), findsNothing);
  });
  testWidgets(
    'large amount, long booking ID, small phone and scaled dark theme do not overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      repo.load = () async => summary(1234567890);
      await mount(tester, mode: ThemeMode.dark, scale: 2);
      repo.history.add([
        record(id: 'very-long-booking-reference-12345678901234567890'),
      ]);
      await tester.pump();
      expect(find.text('₹12,345,678.90'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pull-to-refresh updates lifetime without resubscribing to history',
    (tester) async {
      await mount(tester);
      repo.history.add([]);
      await tester.pump();
      repo.load = () async => summary(170000);
      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.text('₹1,700.00'), findsOneWidget);
      expect(repo.calls, 2);
      expect(repo.watches, 1);
    },
  );
  testWidgets(
    'account switch discards previous earnings and scopes new history',
    (tester) async {
      await mount(tester);
      repo.history.add([record()]);
      await tester.pump();
      repo.load = () async => summary(0, uid: 'next-provider');
      auth.change('next-provider');
      await tester.pump();
      await tester.pump();
      expect(repo.uids, ['provider', 'next-provider']);
      expect(find.text('₹10,000.00'), findsNothing);
      expect(find.text('₹850.00'), findsNothing);
      repo.history.add([record()]);
      await tester.pump();
      expect(
        find.text('We couldn’t load your earnings history.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('no-show and dispute resolution render final allocated amounts', (
    tester,
  ) async {
    await mount(tester);
    repo.history.add([
      record(amount: 42000, outcome: 'NO_SHOW'),
      record(
        amount: 50000,
        phase: 'ADJUSTED',
        outcome: 'DISPUTE_RESOLUTION',
        id: 'booking-2',
      ),
    ]);
    await tester.pump();
    expect(find.text('No-show earning'), findsOneWidget);
    expect(find.text('₹420.00'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pump();
    expect(find.text('Dispute resolved'), findsOneWidget);
    expect(find.text('₹500.00'), findsOneWidget);
  });
  testWidgets('current canonical records form an earnings statement', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    repo.load = () async => summary(170);
    await mount(tester);
    repo.history.add([
      record(id: 'DGKy', amount: 170, outcome: 'NO_SHOW', status: 'HELD'),
      record(
        id: 'FCxs',
        amount: null,
        phase: 'PROVISIONAL',
        outcome: 'PAYMENT_CONFIRMED',
        status: 'HELD',
      ),
      record(
        id: 'MrvT',
        amount: null,
        phase: 'PROVISIONAL',
        outcome: 'PAYMENT_CONFIRMED',
        status: 'HELD',
      ),
      record(
        id: 'YMId',
        amount: 0,
        outcome: 'PROVIDER_CANCELLATION',
        status: 'CANCELLED',
      ),
    ]);
    await tester.pump();
    expect(find.text('₹1.70'), findsNWidgets(2));
    expect(find.text('No-show earning'), findsOneWidget);
    expect(find.text('Earned'), findsOneWidget);
    expect(find.text('Payout: On hold'), findsOneWidget);
    expect(find.text('Earning pending finalization'), findsNWidgets(2));
    expect(find.text('Amount not final yet'), findsNWidgets(2));
    expect(find.text('₹0.00'), findsNothing);
    expect(find.text('Cancelled'), findsNothing);
    expect(find.textContaining('Source:'), findsNothing);
    expect(find.textContaining('paidBookingCanonical'), findsNothing);
    expect(find.textContaining('Booking DGKy'), findsNothing);
    for (final label in ['Pending', 'Eligible', 'Paid', 'On Hold']) {
      expect(find.text(label), findsNothing);
    }
  });
  test(
    'payout mapping cannot replace earnings status or expose provisional payouts',
    () {
      const labels = {
        'HELD': 'Payout: On hold',
        'READY': 'Payout: Eligible',
        'PAID': 'Payout: Paid',
        'PROCESSING': 'Payout: Processing',
        'FAILED': 'Payout: Failed',
        'CANCELLED': 'Payout: Cancelled',
      };
      for (final entry in labels.entries) {
        expect(earningsStatusLabel(record(status: entry.key)), 'Earned');
        expect(earningsPayoutLabel(record(status: entry.key)), entry.value);
        final provisional = record(
          amount: null,
          phase: 'PROVISIONAL',
          status: entry.key,
        );
        expect(
          earningsStatusLabel(provisional),
          'Earning pending finalization',
        );
        expect(earningsPayoutLabel(provisional), isNull);
      }
      expect(earningsPayoutLabel(record(status: 'unknown')), isNull);
      expect(
        earningsPayoutLabel(record(amount: 0, status: 'CANCELLED')),
        isNull,
      );
      expect(
        earningsOutcomeLabel(record(outcome: 'unknown')),
        'Booking earning',
      );
    },
  );
  test('paise formatter uses grouping and exactly two decimals', () {
    expect(formatEarningsPaise(85000), '₹850.00');
    expect(formatEarningsPaise(123456789), '₹1,234,567.89');
    expect(formatEarningsPaise(0), '₹0.00');
    expect(formatEarningsPaise(9007199254740991), '₹90,071,992,547,409.91');
  });
  test('no-show and resolved dispute have neutral friendly labels', () {
    expect(earningsOutcomeLabel(record(outcome: 'NO_SHOW')), 'No-show earning');
    expect(
      earningsOutcomeLabel(record(outcome: 'DISPUTE_RESOLUTION')),
      'Dispute resolved',
    );
    expect(earningsStatusLabel(record(status: 'PROCESSING')), 'Earned');
  });
  test(
    'legacy/malformed amounts cannot be rounded or converted into earnings',
    () {
      for (final amount in [
        -1,
        0.5,
        double.nan,
        double.infinity,
        '850',
        9007199254740992,
      ]) {
        expect(
          () => ProviderEarningRecord.fromMap('b', {
            'bookingId': 'b',
            'providerId': 'provider',
            'earningsSchemaVersion': 1,
            'earningsStatus': 'FINALIZED',
            'providerFinalEntitlementPaise': amount,
          }),
          throwsFormatException,
        );
      }
      expect(
        () => ProviderEarningRecord.fromMap('b', {'amount': 850}),
        throwsFormatException,
      );
    },
  );
  test('duplicate refund metadata cannot change canonical earning', () {
    final result = ProviderEarningRecord.fromMap('b', {
      'bookingId': 'b',
      'providerId': 'provider',
      'earningsSchemaVersion': 1,
      'earningsStatus': 'FINALIZED',
      'providerFinalEntitlementPaise': 85000,
      'refundKind': 'DUPLICATE_PAYMENT',
      'refundAmountPaise': 100000,
      'amount': 0,
      'amountPaise': 0,
    });
    expect(result.finalEntitlementPaise, 85000);
  });
  test(
    'date fallback is explicitly updated or recorded, never falsely finalized',
    () {
      const row = ProviderEarningRecord(
        id: 'b',
        bookingId: 'b',
        providerId: 'provider',
        finalEntitlementPaise: 85000,
        earningsStatus: 'FINALIZED',
        earningsOutcome: '',
        status: 'READY',
      );
      expect(row.displayDate, isNull);
      final updated = ProviderEarningRecord.fromMap('b', {
        'bookingId': 'b',
        'providerId': 'provider',
        'earningsSchemaVersion': 1,
        'earningsStatus': 'FINALIZED',
        'providerFinalEntitlementPaise': 85000,
        'createdAt': '2026-01-01',
        'updatedAt': '2026-09-08',
      });
      expect(updated.dateLabel, 'Updated');
      expect(updated.displayDate, DateTime(2026, 9, 8));
    },
  );
}
