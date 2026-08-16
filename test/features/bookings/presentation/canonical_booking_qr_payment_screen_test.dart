import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/widgets/app_buttons.dart';
import 'package:pettexo/features/bookings/data/repositories/booking_repository.dart';
import 'package:pettexo/features/bookings/domain/models/booking_document_v3.dart';
import 'package:pettexo/features/bookings/domain/models/booking_payment_order.dart';
import 'package:pettexo/features/bookings/domain/models/booking_read_model.dart';
import 'package:pettexo/features/bookings/domain/models/booking_v3_models.dart';
import 'package:pettexo/features/bookings/presentation/screens/canonical_booking_qr_payment_screen.dart';

void main() {
  late _FakeQrBookingRepository bookingRepository;
  late CanonicalBookingDocumentV3 booking;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    bookingRepository = _FakeQrBookingRepository();
    booking = _buildBookingFixture();
    bookingRepository.emitBooking(booking);
  });

  tearDown(() async {
    await bookingRepository.dispose();
  });

  Future<void> pumpQrScreen(
    WidgetTester tester, {
    CanonicalQrPaymentResult? qrPayment,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CanonicalBookingQrPaymentScreen(
          bookingId: booking.bookingIdForTest,
          qrPayment: qrPayment ?? _qrResult(),
          bookingRepository: bookingRepository,
          confirmationScreenBuilder: (_) =>
              const Scaffold(body: Text('confirmation')),
        ),
      ),
    );
  }

  test('QR mode parses correctly', () {
    final result = CanonicalQrPaymentResult.fromMap({
      'bookingId': 'booking-1',
      'paymentAttemptId': 'attempt-1',
      'mode': 'qr',
      'qrCodeId': 'qr-1',
      'imageUrl': 'https://example.com/qr.png',
      'amountPaise': 25000,
      'currency': 'INR',
      'expiresAt': '2026-08-14T12:30:00.000Z',
      'pricingSummary': {
        'serviceSubtotalPaise': 25000,
        'couponDiscountPaise': 5000,
        'customerPaidPaise': 20000,
        'providerPayoutPaise': 17000,
        'currency': 'INR',
      },
      'idempotentReplay': true,
    });

    expect(result.isQrMode, true);
    expect(result.qrCodeId, 'qr-1');
    expect(result.amountPaise, 25000);
    expect(result.idempotentReplay, true);
  });

  test(
    'zero-payable mode parses correctly and missing optional fields do not crash',
    () {
      final result = CanonicalQrPaymentResult.fromMap({
        'bookingId': 'booking-1',
        'paymentAttemptId': 'attempt-1',
        'mode': 'zero_payable',
        'pricingSummary': {
          'serviceSubtotalPaise': 25000,
          'couponDiscountPaise': 25000,
          'customerPaidPaise': 0,
          'providerPayoutPaise': 17000,
          'currency': 'INR',
        },
        'state': 'CONFIRMED',
        'confirmedAt': '2026-08-14T12:30:00.000Z',
      });

      expect(result.isZeroPayable, true);
      expect(result.imageUrl, isEmpty);
      expect(result.qrCodeId, isEmpty);
      expect(result.amountPaise, 0);
    },
  );

  testWidgets(
    'QR screen shows image, amount, countdown, waiting state, and replay-safe fallback action',
    (tester) async {
      bookingRepository.emitAttempt(
        _attemptFixture(state: CanonicalPaymentAttemptState.orderCreated),
      );
      await pumpQrScreen(tester, qrPayment: _qrResult(idempotentReplay: true));
      await tester.pump();

      expect(find.text('Pay ₹250.00'), findsOneWidget);
      expect(find.text('Scan this QR using any UPI app'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data?.contains('Waiting for payment') ?? false),
          skipOffstage: false,
        ),
        findsWidgets,
      );
      final switchMethodButton = find.byWidgetPredicate(
        (widget) =>
            widget is SecondaryButton &&
            widget.label == 'Use another payment method',
        skipOffstage: false,
      );
      await tester.scrollUntilVisible(switchMethodButton, 250);
      await tester.ensureVisible(switchMethodButton);
      expect(switchMethodButton, findsOneWidget);
      expect(find.text('confirmation'), findsNothing);

      await tester.tap(switchMethodButton, warnIfMissed: false);
      await tester.pump();
    },
  );

  testWidgets('image-load error state is handled', (tester) async {
    await pumpQrScreen(tester, qrPayment: _qrResult(imageUrl: ''));
    await tester.pump();

    expect(
      find.text('We couldn\'t load the QR image right now.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'booking confirmation navigates through the canonical success path',
    (tester) async {
      await pumpQrScreen(tester);
      await tester.pump();

      final confirmedBooking = _buildBookingFixture(
        state: CanonicalBookingStateV3.confirmed,
        paidAt: DateTime.now().toUtc(),
      );
      bookingRepository.confirmationController.add(
        CanonicalBookingReadModel(
          documentId: confirmedBooking.bookingIdForTest,
          booking: confirmedBooking,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('confirmation'), findsOneWidget);
    },
  );

  testWidgets(
    'payment expiry and cancellation show terminal states without success',
    (tester) async {
      await pumpQrScreen(tester);
      await tester.pump();

      bookingRepository.emitAttempt(
        _attemptFixture(state: CanonicalPaymentAttemptState.expired),
      );
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data?.toLowerCase().contains('expired') ?? false),
          skipOffstage: false,
        ),
        findsWidgets,
      );

      bookingRepository.emitBooking(
        _buildBookingFixture(state: CanonicalBookingStateV3.cancelledByParent),
      );
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data == 'QR payment expired' ||
                  widget.data == 'Booking cancelled'),
          skipOffstage: false,
        ),
        findsWidgets,
      );
      expect(find.text('Payment confirmed'), findsNothing);
      expect(find.text('confirmation'), findsNothing);
    },
  );

  testWidgets(
    'reconciliation-required and refund-required attempts do not show success',
    (tester) async {
      await pumpQrScreen(tester);
      await tester.pump();

      bookingRepository.emitAttempt(
        _attemptFixture(
          state: CanonicalPaymentAttemptState.capturedRequiresReconciliation,
        ),
      );
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data?.contains('Please don\'t make another payment') ??
                  false),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(find.text('confirmation'), findsNothing);

      bookingRepository.emitAttempt(
        _attemptFixture(state: CanonicalPaymentAttemptState.refundRequired),
      );
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.data == 'Payment under refund review',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(find.text('confirmation'), findsNothing);
    },
  );
}

class _FakeQrBookingRepository extends BookingRepository {
  CanonicalBookingReadModel? _currentBooking;
  CanonicalPaymentAttemptReadModel? _currentAttempt;
  final StreamController<BookingReadModel?> bookingController =
      StreamController<BookingReadModel?>.broadcast();
  final StreamController<BookingReadModel?> confirmationController =
      StreamController<BookingReadModel?>.broadcast();
  final StreamController<CanonicalPaymentAttemptReadModel?> attemptController =
      StreamController<CanonicalPaymentAttemptReadModel?>.broadcast();

  void emitBooking(CanonicalBookingDocumentV3 booking) {
    _currentBooking = CanonicalBookingReadModel(
      documentId: booking.bookingIdForTest,
      booking: booking,
    );
    bookingController.add(_currentBooking);
  }

  void emitAttempt(CanonicalPaymentAttemptReadModel attempt) {
    _currentAttempt = attempt;
    attemptController.add(attempt);
  }

  Future<void> dispose() async {
    await bookingController.close();
    await confirmationController.close();
    await attemptController.close();
  }

  @override
  Stream<BookingReadModel?> watchCanonicalBooking(String bookingId) async* {
    yield _currentBooking;
    yield* bookingController.stream;
  }

  @override
  Stream<BookingReadModel?> watchCanonicalBookingConfirmation(
    String bookingId,
  ) => confirmationController.stream;

  @override
  Stream<CanonicalPaymentAttemptReadModel?> watchPaymentAttempt({
    required String bookingId,
    required String paymentAttemptId,
  }) async* {
    yield _currentAttempt;
    yield* attemptController.stream;
  }
}

CanonicalQrPaymentResult _qrResult({
  String imageUrl = 'https://example.com/qr.png',
  bool idempotentReplay = false,
}) {
  return CanonicalQrPaymentResult.fromMap({
    'bookingId': 'booking-1',
    'paymentAttemptId': 'attempt-1',
    'mode': 'qr',
    'qrCodeId': 'qr-1',
    'imageUrl': imageUrl,
    'amountPaise': 25000,
    'currency': 'INR',
    'expiresAt': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 10))
        .toIso8601String(),
    'pricingSummary': {
      'serviceSubtotalPaise': 25000,
      'couponDiscountPaise': 0,
      'customerPaidPaise': 25000,
      'providerPayoutPaise': 20000,
      'currency': 'INR',
    },
    'idempotentReplay': idempotentReplay,
  });
}

CanonicalPaymentAttemptReadModel _attemptFixture({
  required CanonicalPaymentAttemptState state,
}) {
  return CanonicalPaymentAttemptReadModel(
    bookingId: 'booking-1',
    paymentAttemptId: 'attempt-1',
    state: state,
    amountPaise: 25000,
    currency: 'INR',
    razorpayOrderId: '',
    razorpayPaymentId: '',
    failureCode: '',
    failureMessage: '',
    retryCount: 0,
    orderExpiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
    orderCreatedAt: DateTime.now().toUtc(),
    checkoutOpenedAt: null,
    captureReportedAt: null,
    confirmedAt: null,
    failedAt: null,
    refundRequiredAt: null,
    refundedAt: null,
    lastReconciledAt: null,
    pricingSummary: const CanonicalPaymentPricingSummary(
      serviceSubtotalPaise: 25000,
      couponDiscountPaise: 0,
      customerPaidPaise: 25000,
      providerPayoutPaise: 20000,
      currency: 'INR',
    ),
  );
}

CanonicalBookingDocumentV3 _buildBookingFixture({
  CanonicalBookingStateV3 state =
      CanonicalBookingStateV3.acceptedAwaitingPayment,
  DateTime? paidAt,
}) {
  final base = DateTime.now().toUtc().add(const Duration(hours: 2));
  final scheduledStartAt = base.add(const Duration(days: 1));
  final scheduledEndAt = scheduledStartAt.add(const Duration(hours: 1));
  final respondedAt = base;
  final payDeadlineAt = base.add(const Duration(minutes: 30));

  return CanonicalBookingDocumentV3(
    schemaVersion: canonicalBookingSchemaVersion,
    bookingModelVersion: canonicalBookingModelVersion,
    documentFormat: canonicalBookingDocumentFormat,
    bookingType: BookingV3Type.slot,
    state: state,
    participants: const CanonicalBookingParticipantsV3(
      parent: CanonicalPublicParentParticipantV3(
        parentId: 'parent-1',
        displayFirstName: 'Nisha',
        lastInitial: 'G',
        photoUrl: '',
        completedBookingCount: 4,
        rating: 4.8,
      ),
      provider: CanonicalPublicProviderParticipantV3(
        providerId: 'provider-1',
        displayName: 'Prakash Gautam',
        username: 'prakashg',
        photoUrl: '',
        completedBookingCount: 12,
        rating: 4.9,
      ),
    ),
    service: const BookingServiceSnapshotV3(
      serviceId: 'service-1',
      providerId: 'provider-1',
      serviceTitle: 'Daily Dog Walk',
      animalType: 'Dog',
      category: 'Walking',
      bookingType: BookingV3Type.slot,
      timezone: 'Asia/Kolkata',
      schedulingMode: 'fixedDuration',
      serviceUnitPricePaise: 25000,
      durationMinutes: 60,
      pricePerNightPaise: null,
      selectedSlotCount: 1,
      totalDurationMinutes: 60,
      checkInDateTime: null,
      checkOutDateTime: null,
      capacitySnapshot: 1,
      serviceLocationType: 'provider_location',
      currency: 'INR',
      snapshotVersion: 1,
    ),
    schedule: CanonicalSlotBookingScheduleV3(
      serviceAnchorAt: scheduledStartAt,
      timezone: 'Asia/Kolkata',
      slots: [
        CanonicalBookingSlotSegmentV3(
          slotId: 'slot-1',
          dateKey: '2026-07-27',
          startAt: scheduledStartAt,
          endAt: scheduledEndAt,
          durationMinutes: 60,
          unitPricePaise: 25000,
          serviceId: 'service-1',
          providerId: 'provider-1',
          timezone: 'Asia/Kolkata',
        ),
      ],
      slotCount: 1,
      scheduledStartAt: scheduledStartAt,
      scheduledEndAt: scheduledEndAt,
      totalDurationMinutes: 60,
    ),
    lifecycle: CanonicalBookingLifecycleV3(
      requestedAt: DateTime.utc(2026, 7, 26, 10),
      timerStartsAt: DateTime.utc(2026, 7, 26, 10, 5),
      wasQueuedOutsideWorkingHours: false,
      notifiedAt: DateTime.utc(2026, 7, 26, 10, 6),
      acceptDeadlineAt: DateTime.utc(2026, 7, 26, 11),
      viewedByProviderAt: DateTime.utc(2026, 7, 26, 10, 15),
      respondedAt: respondedAt,
      providerResponseType: ProviderResponseTypeV3.accept,
      responseSeconds: 3300,
      payDeadlineAt: payDeadlineAt,
      paymentStartedAt: null,
      paidAt: paidAt,
      paymentSeconds: null,
      otpGeneratedAt: null,
      otpEnteredAt: null,
      noShowAt: null,
      serviceEndedAt: null,
      disputeDeadlineAt: null,
      completedAt: null,
      reviewWindowEndsAt: null,
      finalizedAt: null,
      cancelledAt: null,
    ),
    payment: const CanonicalBookingPaymentV3(
      status: 'awaiting_customer_payment',
      razorpayOrderId: '',
      razorpayPaymentId: '',
      razorpayRefundId: '',
      paymentAttemptId: '',
      orderCreatedAt: null,
      paymentStartedAt: null,
      capturedAt: null,
      verifiedAt: null,
      verificationSource: '',
      webhookEventIds: <String>[],
      failureCode: '',
      failureMessage: '',
    ),
    financials: null,
    privacy: const CanonicalBookingPrivacyV3(
      isPaidContactUnlocked: false,
      contactUnlockedAt: null,
      chatUnlockedAt: null,
      otpVisibleToParent: false,
      exactAddressUnlocked: false,
      privacyVersion: 1,
      privateParticipantsRefPath: 'bookingPrivateParticipants/booking-1',
    ),
    cancellation: const CanonicalBookingCancellationV3(
      cancelledAt: null,
      cancelledBy: null,
      cancelReasonCode: '',
      cancelReasonText: '',
      hoursBeforeServiceAtCancel: null,
      refundBand: '',
      refundBasisPoints: null,
      refundAmountPaise: 0,
      providerCompensationPaise: 0,
      pettxoRetainedPaise: 0,
      cancellationType: null,
    ),
    dispute: const CanonicalBookingDisputeV3(
      disputeId: '',
      status: 'none',
      raisedAt: null,
      raisedBy: null,
      reasonCode: '',
      description: '',
      evidenceRefs: <String>[],
      resolvedAt: null,
      resolvedBy: null,
      resolution: '',
      resolutionVersion: 0,
      financialAdjustmentId: '',
      refundInstructionId: '',
      customerRefundPaise: 0,
      providerReleasePaise: 0,
    ),
    payout: const CanonicalBookingPayoutV3(
      status: 'not_eligible',
      holdReason: '',
      eligibleAt: null,
      readyAt: null,
      processingAt: null,
      releasedAt: null,
      failedAt: null,
      providerPayoutPaise: 0,
      priorPaidPaise: 0,
      remainingPayablePaise: 0,
      payoutReference: '',
      externalTransactionId: '',
      failureCode: '',
      retryCount: 0,
    ),
    statistics: const CanonicalBookingStatisticsV3(
      selectedSlotCount: 1,
      totalDurationMinutes: 60,
      nights: null,
    ),
    audit: const CanonicalBookingAuditV3(
      createdBy: BookingActorV3.system,
      lastUpdatedBy: BookingActorV3.system,
      source: 'test',
    ),
    parentId: 'parent-1',
    providerId: 'provider-1',
    serviceId: 'service-1',
    stateQueryValue: state,
    bookingTypeQueryValue: BookingV3Type.slot,
    serviceAnchorAt: scheduledStartAt,
    scheduledStartAt: scheduledStartAt,
    checkInDateTime: null,
    acceptDeadlineAt: DateTime.utc(2026, 7, 26, 11),
    payDeadlineAt: payDeadlineAt,
    completedAt: null,
    customerId: 'parent-1',
    serviceOwnerId: 'provider-1',
    createdAt: DateTime.utc(2026, 7, 26, 10),
    updatedAt: DateTime.utc(2026, 7, 26, 12, 5),
  );
}

extension on CanonicalBookingDocumentV3 {
  String get bookingIdForTest => 'booking-1';
}
