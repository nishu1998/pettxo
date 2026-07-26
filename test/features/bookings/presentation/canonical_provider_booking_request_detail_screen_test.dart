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
  }) {
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
      scheduledStartAt: DateTime.utc(2026, 7, 27, 6, 30),
      scheduledEndAt: DateTime.utc(2026, 7, 27, 7, 30),
      slotCount: 1,
      totalDurationMinutes: 60,
      timerStartsAt: DateTime.utc(2026, 7, 27, 3, 30),
      acceptDeadlineAt: DateTime.utc(2026, 7, 27, 4, 30),
      timezone: 'Asia/Kolkata',
      estimatedProviderPayoutPaise: 20000,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required CanonicalProviderBookingRequestView request,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CanonicalProviderBookingRequestDetailScreen(
          initialRequest: request,
          bookingRepository: _FakeBookingRepository(),
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
          'You can accept or decline it now',
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
      findsWidgets,
    );
    expect(
      find.textContaining('actions stay locked', findRichText: true),
      findsNothing,
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
