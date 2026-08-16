import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/widgets/app_buttons.dart';
import 'package:pettexo/features/bookings/data/repositories/booking_repository.dart';
import 'package:pettexo/features/bookings/domain/models/booking_document_v3.dart';
import 'package:pettexo/features/bookings/domain/models/booking_payment_order.dart';
import 'package:pettexo/features/bookings/domain/models/booking_read_model.dart';
import 'package:pettexo/features/bookings/domain/models/booking_v3_models.dart';
import 'package:pettexo/features/bookings/presentation/screens/canonical_booking_payment_screen.dart';
import 'package:pettexo/features/offers/domain/models/available_offer.dart';
import 'package:pettexo/features/offers/domain/models/offer_types.dart';

void main() {
  late _FakeBookingRepository bookingRepository;
  late CanonicalBookingDocumentV3 booking;
  late List<AvailableOffer> offers;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    bookingRepository = _FakeBookingRepository();
    booking = _buildBookingFixture();
    offers = const <AvailableOffer>[];
    bookingRepository.emitBooking(booking);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CanonicalBookingPaymentScreen(
          bookingId: booking.bookingIdForTest,
          serviceName: booking.service.serviceTitle,
          providerName: booking.participants.provider.displayName,
          serviceImageUrl: '',
          bookingRepository: bookingRepository,
          loadAvailableOffers:
              ({
                required double bookingAmount,
                String? serviceId,
                String? providerId,
                String? category,
              }) async => AvailableOffersResult(
                offerWall: offers.isEmpty ? null : offers.first,
                popup: null,
                offers: offers,
              ),
        ),
      ),
    );
  }

  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
  }

  testWidgets(
    'loads authoritative pricing on open and hides internal allocation rows',
    (tester) async {
      useTallViewport(tester);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      bookingRepository.previewResultsByOfferId[''] = _previewResult(
        serviceSubtotalPaise: 25000,
        couponDiscountPaise: 0,
        customerPaidPaise: 25000,
      );

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      expect(bookingRepository.previewRequests, ['']);
      expect(_textFinder('PRICE DETAILS'), findsOneWidget);
      expect(_textFinder('Price details'), findsOneWidget);
      expect(_textFinder('Service amount'), findsOneWidget);
      expect(_textFinder('Total payable'), findsWidgets);
      expect(_textFinder('₹250.00'), findsWidgets);
      expect(_textFinder('Offer discount'), findsOneWidget);
      expect(_textFinder('Time remaining'), findsOneWidget);
      expect(_textFinder('CHOOSE PAYMENT METHOD'), findsOneWidget);
      expect(_textFinder('Pay with Razorpay'), findsWidgets);
      expect(_textFinder('Pay using QR'), findsWidgets);
      expect(find.textContaining('Provider payout'), findsNothing);
      expect(find.text('Calculating your total...'), findsNothing);
    },
  );

  testWidgets('shows retry state when pricing preview fails', (tester) async {
    bookingRepository.previewErrorByOfferId[''] =
        const CanonicalPaymentException(
          code: CanonicalPaymentFailureCode.bookingNotPayable,
          message: 'Not payable',
        );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(_textFinder('We couldn’t load the payment total.'), findsOneWidget);
    expect(_textFinder('Retry'), findsOneWidget);
  });

  testWidgets(
    'payment stays disabled until cancellation policy consent is checked',
    (tester) async {
      useTallViewport(tester);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      bookingRepository.previewResultsByOfferId[''] = _previewResult(
        serviceSubtotalPaise: 25000,
        couponDiscountPaise: 0,
        customerPaidPaise: 25000,
      );

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      final checkbox = find.byType(Checkbox);

      expect(checkbox, findsOneWidget);
      expect(_gradientButtonFinder('Pay with Razorpay'), findsNothing);
      expect(_secondaryButtonFinder('Payment unavailable'), findsNWidgets(2));

      await tester.tap(checkbox, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(_gradientButtonFinder('Pay with Razorpay'), findsOneWidget);
      expect(_secondaryButtonFinder('Pay using QR'), findsOneWidget);
    },
  );

  testWidgets(
    'payment remains disabled after consent when the payment window is expired',
    (tester) async {
      useTallViewport(tester);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      bookingRepository.previewResultsByOfferId[''] = _previewResult(
        serviceSubtotalPaise: 25000,
        couponDiscountPaise: 0,
        customerPaidPaise: 25000,
        payDeadlineAt: DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        ),
      );

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      final checkbox = find.byType(Checkbox);
      await tester.tap(checkbox, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(_gradientButtonFinder('Pay with Razorpay'), findsNothing);
      expect(
        _secondaryButtonFinder('Payment window expired'),
        findsNWidgets(2),
      );
    },
  );

  testWidgets(
    'payment remains disabled while an earlier captured attempt is awaiting reconciliation',
    (tester) async {
      useTallViewport(tester);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final attempt = _attemptResult(
        state: CanonicalPaymentAttemptState.capturedRequiresReconciliation,
      );
      booking = _buildBookingFixture(paymentAttemptId: attempt.paymentAttemptId);
      bookingRepository.emitBooking(booking);
      bookingRepository.emitAttempt(attempt);
      bookingRepository.previewResultsByOfferId[''] = _previewResult(
        serviceSubtotalPaise: 25000,
        couponDiscountPaise: 0,
        customerPaidPaise: 25000,
      );

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      final checkbox = find.byType(Checkbox);
      await tester.tap(checkbox, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(_gradientButtonFinder('Pay with Razorpay'), findsNothing);
      expect(_secondaryButtonFinder('Payment unavailable'), findsNWidgets(2));
      expect(
        find.text('Payment was captured and is awaiting backend reconciliation.'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'creating QR disables the QR action while the callable is in flight',
    (tester) async {
      useTallViewport(tester);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      bookingRepository.previewResultsByOfferId[''] = _previewResult(
        serviceSubtotalPaise: 25000,
        couponDiscountPaise: 0,
        customerPaidPaise: 25000,
      );
      bookingRepository.pendingQrResult = Completer<CanonicalQrPaymentResult>();

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      final checkbox = find.byType(Checkbox);
      await tester.tap(checkbox, warnIfMissed: false);
      await tester.pumpAndSettle();

      final qrButton = _secondaryButtonFinder('Pay using QR');
      expect(qrButton, findsOneWidget);
      await tester.tap(qrButton, warnIfMissed: false);
      await tester.pump();

      expect(bookingRepository.qrRequests, ['']);
      expect(_secondaryButtonFinder('Pay using QR'), findsNothing);
      expect(_gradientButtonFinder('Creating QR...'), findsOneWidget);
      expect(bookingRepository.qrRequests, ['']);

      bookingRepository.pendingQrResult!.complete(_qrResult());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('successful QR creation opens the QR payment waiting screen', (
    tester,
  ) async {
    useTallViewport(tester);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    bookingRepository.previewResultsByOfferId[''] = _previewResult(
      serviceSubtotalPaise: 25000,
      couponDiscountPaise: 0,
      customerPaidPaise: 25000,
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(
      _secondaryButtonFinder('Pay using QR'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('Use another payment method'), findsOneWidget);
    expect(find.text('Waiting for payment…'), findsWidgets);
  });

  testWidgets(
    'coupon picker shows empty state when no eligible coupons are available',
    (tester) async {
      useTallViewport(tester);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      bookingRepository.previewResultsByOfferId[''] = _previewResult(
        serviceSubtotalPaise: 25000,
        couponDiscountPaise: 0,
        customerPaidPaise: 25000,
      );
      offers = const <AvailableOffer>[];

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      final offersButton = _secondaryButtonFinder('Available offers');
      await tester.scrollUntilVisible(offersButton, 300);
      await tester.ensureVisible(offersButton);
      await tester.tap(offersButton, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
        find.text('No coupons are currently available for this booking.'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'applying a coupon refreshes authoritative pricing and updates coupon state',
    (tester) async {
      useTallViewport(tester);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      const offerCampaignId = 'offer-1';
      bookingRepository.previewResultsByOfferId[''] = _previewResult(
        serviceSubtotalPaise: 25000,
        couponDiscountPaise: 0,
        customerPaidPaise: 25000,
      );
      bookingRepository.previewResultsByOfferId[offerCampaignId] =
          _previewResult(
            serviceSubtotalPaise: 25000,
            couponDiscountPaise: 5000,
            customerPaidPaise: 20000,
            offerCampaignId: offerCampaignId,
          );
      offers = [
        _buildAvailableOffer(
          id: offerCampaignId,
          couponCode: 'SAVE50',
          discountValue: 50,
        ),
      ];

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      final offersButton = _secondaryButtonFinder('Available offers');
      await tester.scrollUntilVisible(offersButton, 300);
      await tester.ensureVisible(offersButton);
      await tester.tap(offersButton, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('SAVE50'), findsOneWidget);
      await tester.tap(find.text('SAVE50'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(bookingRepository.previewRequests, ['', offerCampaignId]);
      expect(find.text('Offer discount'), findsOneWidget);
      expect(find.text('-₹50.00'), findsOneWidget);
      expect(find.text('₹200.00'), findsWidgets);
      expect(find.text('Available offers'), findsWidgets);
      expect(find.text('Remove offer'), findsOneWidget);
    },
  );
}

Finder _secondaryButtonFinder(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is SecondaryButton && widget.label == label,
    skipOffstage: false,
  );
}

Finder _gradientButtonFinder(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is GradientButton && widget.label == label,
    skipOffstage: false,
  );
}

Finder _textFinder(String text) {
  return find.byWidgetPredicate(
    (widget) => widget is Text && widget.data == text,
    skipOffstage: false,
  );
}

class _FakeBookingRepository extends BookingRepository {
  BookingReadModel? _booking;
  CanonicalPaymentAttemptReadModel? _attempt;
  final StreamController<BookingReadModel?> confirmationController =
      StreamController<BookingReadModel?>.broadcast();
  final StreamController<CanonicalPaymentAttemptReadModel?> attemptController =
      StreamController<CanonicalPaymentAttemptReadModel?>.broadcast();
  final Map<String, CanonicalPaymentPricingPreviewResult>
  previewResultsByOfferId = <String, CanonicalPaymentPricingPreviewResult>{};
  final Map<String, Object> previewErrorByOfferId = <String, Object>{};
  final List<String> previewRequests = <String>[];
  final List<String> qrRequests = <String>[];
  Completer<CanonicalQrPaymentResult>? pendingQrResult;

  void emitBooking(CanonicalBookingDocumentV3 booking) {
    _booking = CanonicalBookingReadModel(
      documentId: booking.bookingIdForTest,
      booking: booking,
    );
  }

  void emitAttempt(CanonicalPaymentAttemptReadModel attempt) {
    _attempt = attempt;
    attemptController.add(attempt);
  }

  @override
  Stream<BookingReadModel?> watchCanonicalBooking(String bookingId) =>
      Stream.value(_booking);

  @override
  Stream<BookingReadModel?> watchCanonicalBookingConfirmation(
    String bookingId,
  ) => confirmationController.stream;

  @override
  Stream<CanonicalPaymentAttemptReadModel?> watchPaymentAttempt({
    required String bookingId,
    required String paymentAttemptId,
  }) async* {
    yield _attempt;
    yield* attemptController.stream;
  }

  @override
  Future<CanonicalPaymentPricingPreviewResult> previewPaymentPricingV3({
    required String bookingId,
    String? offerCampaignId,
  }) async {
    final key = offerCampaignId?.trim() ?? '';
    previewRequests.add(key);
    final error = previewErrorByOfferId[key];
    if (error is CanonicalPaymentException) throw error;
    if (error != null) throw error;
    final result = previewResultsByOfferId[key];
    if (result == null) {
      throw StateError('Missing preview result for "$key".');
    }
    return result;
  }

  @override
  Future<CanonicalQrPaymentResult> createQrPaymentV3({
    required String bookingId,
    String? offerCampaignId,
  }) {
    qrRequests.add(offerCampaignId?.trim() ?? '');
    final completer = pendingQrResult;
    if (completer != null) {
      return completer.future;
    }
    return Future<CanonicalQrPaymentResult>.value(_qrResult());
  }
}

CanonicalPaymentAttemptReadModel _attemptResult({
  required CanonicalPaymentAttemptState state,
}) {
  return CanonicalPaymentAttemptReadModel(
    bookingId: 'booking-1',
    paymentAttemptId: 'attempt-1',
    state: state,
    amountPaise: 25000,
    currency: 'INR',
    razorpayOrderId: 'order-1',
    razorpayPaymentId: 'pay-1',
    failureCode: '',
    failureMessage: '',
    retryCount: 0,
    orderExpiresAt: DateTime.now().toUtc().add(const Duration(minutes: 20)),
    orderCreatedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
    checkoutOpenedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
    captureReportedAt: DateTime.now().toUtc().subtract(const Duration(seconds: 30)),
    confirmedAt: null,
    failedAt: null,
    refundRequiredAt: null,
    refundedAt: null,
    lastReconciledAt: DateTime.now().toUtc().subtract(const Duration(seconds: 10)),
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
  String paymentAttemptId = '',
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
    state: CanonicalBookingStateV3.acceptedAwaitingPayment,
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
      paidAt: null,
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
    payment: CanonicalBookingPaymentV3(
      status: 'awaiting_customer_payment',
      razorpayOrderId: '',
      razorpayPaymentId: '',
      razorpayRefundId: '',
      paymentAttemptId: paymentAttemptId,
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
    stateQueryValue: CanonicalBookingStateV3.acceptedAwaitingPayment,
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

CanonicalPaymentPricingPreviewResult _previewResult({
  required int serviceSubtotalPaise,
  required int couponDiscountPaise,
  required int customerPaidPaise,
  String offerCampaignId = '',
  DateTime? payDeadlineAt,
}) {
  return CanonicalPaymentPricingPreviewResult(
    bookingId: 'booking-1',
    pricingSummary: CanonicalPaymentPricingSummary(
      serviceSubtotalPaise: serviceSubtotalPaise,
      couponDiscountPaise: couponDiscountPaise,
      customerPaidPaise: customerPaidPaise,
      providerPayoutPaise: 20000,
      currency: 'INR',
    ),
    payDeadlineAt:
        payDeadlineAt ??
        DateTime.now().toUtc().add(const Duration(minutes: 30)),
    offerCampaignId: offerCampaignId,
    idempotentReplay: false,
  );
}

CanonicalQrPaymentResult _qrResult({String mode = 'qr'}) {
  return CanonicalQrPaymentResult.fromMap({
    'bookingId': 'booking-1',
    'paymentAttemptId': 'attempt-1',
    'mode': mode,
    'qrCodeId': 'qr-1',
    'imageUrl': 'https://example.com/qr.png',
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
    'idempotentReplay': false,
  });
}

AvailableOffer _buildAvailableOffer({
  required String id,
  required String couponCode,
  required double discountValue,
  double? minBookingAmount,
}) {
  return AvailableOffer(
    id: id,
    title: 'Save on this walk',
    description: 'A simple coupon for testing.',
    couponCode: couponCode,
    displayType: OfferDisplayType.offerWall,
    campaignType: OfferCampaignType.general,
    discountType: OfferDiscountType.flat,
    discountValue: discountValue,
    maxDiscountAmount: 50,
    minBookingAmount: minBookingAmount ?? 0,
    usageLimitPerUser: 1,
    priority: 10,
    startAt: DateTime.utc(2026, 7, 26, 11),
    endAt: DateTime.utc(2026, 8, 1),
  );
}

extension on CanonicalBookingDocumentV3 {
  String get bookingIdForTest => 'booking-1';
}
