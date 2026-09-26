import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/widgets/app_buttons.dart';
import 'package:pettexo/features/bookings/data/repositories/booking_repository.dart';
import 'package:pettexo/features/bookings/domain/models/booking_v3_models.dart';
import 'package:pettexo/features/bookings/domain/models/canonical_booking_request_models.dart';
import 'package:pettexo/features/bookings/presentation/screens/canonical_booking_request_review_screen.dart';

void main() {
  late _PendingBookingRepository repository;
  late CanonicalBookingRequestInput input;

  setUp(() {
    repository = _PendingBookingRepository();
    input = _buildInput();
  });

  Future<void> pumpReviewScreen(
    WidgetTester tester, {
    double textScaleFactor = 1,
    double bottomSafeArea = 0,
  }) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScaleFactor),
            padding: EdgeInsets.only(bottom: bottomSafeArea),
            viewPadding: EdgeInsets.only(bottom: bottomSafeArea),
          ),
          child: child!,
        ),
        home: const Scaffold(body: Text('Previous screen')),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => CanonicalBookingRequestReviewScreen(
          input: input,
          serviceName: 'Daily Dog Walk',
          providerName: 'Pettxo Provider',
          serviceImageUrl: '',
          timezone: 'Asia/Kolkata',
          schedulingMode: 'fixed',
          bookingRepository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'keeps Send request fixed while details scroll and removes bottom Back',
    (tester) async {
      await pumpReviewScreen(tester, textScaleFactor: 1.3, bottomSafeArea: 34);

      final sendRequest = find.byKey(const ValueKey('send-request-cta'));
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.widgetWithText(SecondaryButton, 'Back'), findsNothing);
      expect(sendRequest, findsOneWidget);
      expect(
        tester.getBottomRight(sendRequest).dy,
        lessThanOrEqualTo(640 - 34),
      );

      final initialCtaTop = tester.getTopLeft(sendRequest).dy;
      final bottomMostDetails = find.text(
        'Your Pettxo profile details will stay attached to this request without exposing private contact information.',
      );
      await tester.scrollUntilVisible(
        bottomMostDetails,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(sendRequest).dy, initialCtaTop);
      expect(
        tester.getBottomRight(bottomMostDetails).dy,
        lessThanOrEqualTo(tester.getTopLeft(sendRequest).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Send request uses the existing submission once and stays disabled while loading',
    (tester) async {
      await pumpReviewScreen(tester);

      final sendRequest = find.byKey(const ValueKey('send-request-cta'));
      await tester.tap(sendRequest);
      await tester.pump();

      expect(repository.callCount, 1);
      expect(repository.receivedInput, same(input));
      var button = tester.widget<InkWell>(sendRequest);
      expect(button.onTap, isNull);
      expect(
        find.descendant(
          of: sendRequest,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      await tester.tap(sendRequest);
      await tester.pump();

      expect(repository.callCount, 1);
      button = tester.widget<InkWell>(sendRequest);
      expect(button.onTap, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}

CanonicalBookingRequestInput _buildInput() {
  final startAt = DateTime(2026, 9, 28, 9);
  final endAt = DateTime(2026, 9, 28, 10);
  final slot = BookingSlotSegmentV3(
    slotId: 'slot-1',
    serviceId: 'service-1',
    providerId: 'provider-1',
    timezone: 'Asia/Kolkata',
    dateKey: '2026-09-28',
    serviceDateKey: '2026-09-28',
    startAt: startAt,
    endAt: endAt,
    durationMinutes: 60,
    unitPricePaise: 50000,
    schedulingMode: 'fixed',
  );
  return CanonicalBookingRequestInput(
    requestAttemptId: 'attempt-1',
    serviceId: 'service-1',
    bookingType: BookingV3Type.slot,
    slotRequest: CanonicalSlotRequestInput(
      selection: SlotBookingSelectionV3(
        bookingType: BookingV3Type.slot,
        slots: [slot],
        slotCount: 1,
        scheduledStartAt: startAt,
        scheduledEndAt: endAt,
        totalDurationMinutes: 60,
        serviceDayCount: 1,
      ),
      estimatedSubtotalPaise: 50000,
    ),
  );
}

class _PendingBookingRepository extends BookingRepository {
  final Completer<CanonicalBookingRequestResult> _result =
      Completer<CanonicalBookingRequestResult>();
  int callCount = 0;
  CanonicalBookingRequestInput? receivedInput;

  @override
  Future<CanonicalBookingRequestResult> createBookingRequestV3({
    required CanonicalBookingRequestInput input,
  }) {
    callCount += 1;
    receivedInput = input;
    return _result.future;
  }
}
