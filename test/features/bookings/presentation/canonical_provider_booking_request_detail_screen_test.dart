import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/data/repositories/booking_repository.dart';
import 'package:pettexo/features/bookings/domain/models/booking_read_model.dart';
import 'package:pettexo/features/bookings/domain/models/booking_v3_models.dart';
import 'package:pettexo/features/bookings/domain/models/canonical_booking_request_models.dart';
import 'package:pettexo/features/bookings/domain/models/canonical_provider_booking_request_view.dart';
import 'package:pettexo/features/bookings/presentation/screens/canonical_provider_booking_request_detail_screen.dart';
import 'package:pettexo/features/bookings/presentation/widgets/canonical_provider_request_card.dart';

void main() {
  CanonicalProviderBookingRequestView buildRequest({
    required CanonicalBookingStateV3 state,
    int? estimatedProviderPayoutPaise = 20000,
    DateTime? payDeadlineAt,
  }) {
    final now = DateTime.now().toUtc();
    final timerStartsAt = now.add(const Duration(minutes: 15));
    final acceptDeadlineAt = timerStartsAt.add(const Duration(hours: 1));
    final scheduledStartAt = now.add(const Duration(days: 1, hours: 2));
    final scheduledEndAt = scheduledStartAt.add(const Duration(hours: 1));
    return CanonicalProviderBookingRequestView(
      bookingId: 'booking-1',
      bookingType: BookingV3Type.slot,
      state: state,
      serviceTitle: 'Dog Walking',
      animalType: 'Dog',
      serviceCategory: 'Walking',
      maskedParentDisplayName: 'Nisha G.',
      parentRating: 4.8,
      completedBookingCount: 4,
      scheduledStartAt: scheduledStartAt,
      scheduledEndAt: scheduledEndAt,
      slotCount: 1,
      totalDurationMinutes: 60,
      timerStartsAt: timerStartsAt,
      acceptDeadlineAt: acceptDeadlineAt,
      payDeadlineAt: payDeadlineAt ?? now.add(const Duration(minutes: 45)),
      timezone: 'Asia/Kolkata',
      estimatedProviderPayoutPaise: estimatedProviderPayoutPaise,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required CanonicalProviderBookingRequestView request,
    double textScaleFactor = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScaleFactor)),
          child: CanonicalProviderBookingRequestDetailScreen(
            initialRequest: request,
            bookingRepository: _FakeBookingRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'queued outside-hours detail copy no longer says actions are locked',
    (tester) async {
      await pumpScreen(
        tester,
        request: buildRequest(state: CanonicalBookingStateV3.requested),
      );

      expect(
        find.textContaining('actions stay locked', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining(
          'You can still accept or decline it now',
          findRichText: true,
        ),
        findsWidgets,
      );
    },
  );

  testWidgets('accepted request no longer shows queued-actionable copy', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      request: buildRequest(
        state: CanonicalBookingStateV3.acceptedAwaitingPayment,
      ),
    );

    expect(
      find.textContaining('The customer can pay now', findRichText: true),
      findsNothing,
    );
    expect(find.text('Accepted, awaiting payment'), findsWidgets);
    expect(find.text('Time remaining'), findsOneWidget);
  });

  testWidgets('expired accepted request shows expired provider messaging', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      request: buildRequest(
        state: CanonicalBookingStateV3.acceptedAwaitingPayment,
        payDeadlineAt: DateTime.now().toUtc().subtract(
          const Duration(minutes: 5),
        ),
      ),
    );

    expect(find.text('Expired'), findsWidgets);
    expect(find.text('Waiting for customer payment'), findsNothing);
    expect(find.text('Time remaining'), findsNothing);
    expect(
      find.textContaining(
        'did not complete payment within the allowed time',
        findRichText: true,
      ),
      findsWidgets,
    );
  });

  testWidgets(
    'queued provider request card keeps accept and decline controls visible',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CanonicalProviderRequestCard(
              request: buildRequest(state: CanonicalBookingStateV3.requested),
              onAccept: () {},
              onDecline: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(
        find.textContaining(
          'You can accept or decline it now',
          findRichText: true,
        ),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'request hero payout copy wraps safely on narrow screens with larger text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await pumpScreen(
        tester,
        request: buildRequest(
          state: CanonicalBookingStateV3.pendingProvider,
          estimatedProviderPayoutPaise: null,
        ),
        textScaleFactor: 1.3,
      );

      expect(
        find.text('Payout shown after payment flow activation'),
        findsOneWidget,
      );
      expect(
        find.byIcon(Icons.account_balance_wallet_outlined),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _FakeBookingRepository extends BookingRepository {
  @override
  Stream<BookingReadModel?> watchCanonicalBooking(String bookingId) =>
      Stream.value(null);

  @override
  Future<CanonicalBookingCommandResult> markBookingViewedByProviderV3({
    required String bookingId,
  }) async {
    return CanonicalBookingCommandResult(
      bookingId: bookingId,
      state: CanonicalBookingStateV3.requested,
      respondedAt: null,
      payDeadlineAt: null,
      cancelledAt: null,
      viewedByProviderAt: DateTime.utc(2026, 7, 26, 13),
      idempotentReplay: false,
    );
  }
}
