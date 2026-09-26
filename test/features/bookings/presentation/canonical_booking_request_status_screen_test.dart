import 'package:pettexo/features/services/data/repositories/services_repository.dart';
import 'package:pettexo/features/services/domain/models/service_model.dart';
import 'package:pettexo/features/bookings/domain/models/canonical_booking_cancellation_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/data/repositories/booking_repository.dart';
import 'package:pettexo/features/bookings/domain/models/booking_document_v3.dart';
import 'package:pettexo/features/bookings/domain/models/booking_read_model.dart';
import 'package:pettexo/features/bookings/domain/models/booking_v3_models.dart';
import 'package:pettexo/features/bookings/domain/models/canonical_booking_request_models.dart';
import 'package:pettexo/features/bookings/presentation/screens/canonical_booking_request_status_screen.dart';

void main() {
  testWidgets(
    'payment-expired terminal screen uses shared booking details template and hides payment controls',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() async {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repository = _FakeBookingRepository(
        _buildExpiredAwaitingPaymentBooking(),
      );
      final servicesRepository = _FakeServicesRepository(
        loader: (_, callCount) => callCount == 1 ? _buildActiveService() : null,
      );

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
              padding: const EdgeInsets.only(bottom: 34),
              viewPadding: const EdgeInsets.only(bottom: 34),
            ),
            child: child!,
          ),
          home: CanonicalBookingRequestStatusScreen(
            bookingId: 'booking-1',
            initialResult: CanonicalBookingRequestResult(
              bookingId: 'booking-1',
              source: 'canonical_v3',
              schemaVersion: canonicalBookingSchemaVersion,
              bookingModelVersion: canonicalBookingModelVersion,
              state: CanonicalBookingStateV3.acceptedAwaitingPayment,
              bookingType: BookingV3Type.slot,
              requestedAt: DateTime.utc(2026, 7, 28, 8),
              timerStartsAt: DateTime.utc(2026, 7, 28, 8),
              acceptDeadlineAt: DateTime.utc(2026, 7, 28, 9),
              wasQueuedOutsideWorkingHours: false,
              idempotentReplay: false,
            ),
            serviceName: 'Daily Dog Walk',
            providerName: 'Nishant Gautam',
            serviceImageUrl: '',
            bookingRepository: repository,
            servicesRepository: servicesRepository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bookAgain = find.byKey(const ValueKey('book-again-cta'));
      expect(find.text('Booking Details'), findsOneWidget);
      expect(find.text('BOOKING SUMMARY'), findsOneWidget);
      expect(bookAgain, findsOneWidget);
      expect(find.text('Book Again'), findsOneWidget);
      expect(find.text('PRIMARY ACTIONS'), findsNothing);
      expect(tester.getBottomRight(bookAgain).dy, lessThanOrEqualTo(640 - 34));
      final initialBookAgainTop = tester.getTopLeft(bookAgain).dy;
      await tester.scrollUntilVisible(
        find.text('BOOKING STATUS'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('BOOKING STATUS'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('BOOKING TIMELINE'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('BOOKING TIMELINE'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('FINANCIAL SUMMARY'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('FINANCIAL SUMMARY'), findsOneWidget);
      final bottomMostDetails = find.text(
        'The payment window ended before checkout completed. No active payment action remains on this booking.',
      );
      await tester.scrollUntilVisible(
        bottomMostDetails,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final detailsScroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      detailsScroll.position.jumpTo(detailsScroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(bookAgain).dy, initialBookAgainTop);
      expect(
        tester.getBottomRight(bottomMostDetails).dy,
        lessThanOrEqualTo(tester.getTopLeft(bookAgain).dy),
      );
      expect(find.text('Pay now'), findsNothing);
      expect(find.text('Resume payment'), findsNothing);
      expect(find.text('Latest payment attempt'), findsNothing);
      expect(find.text('Cancellation Policy'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(bookAgain);
      await tester.pumpAndSettle();
      expect(servicesRepository.requestedServiceIds, [
        'service-1',
        'service-1',
      ]);
    },
  );

  testWidgets(
    'customer cancellation shows only canonical customer financial outcome',
    (tester) async {
      final repository = _FakeBookingRepository(
        _buildProviderCancelledAfterPaymentBooking(actor: 'parent'),
      );

      await tester.pumpWidget(
        MaterialApp(
          routes: {'/settings': (_) => const Scaffold(body: Text('Settings'))},
          home: CanonicalBookingRequestStatusScreen(
            bookingId: 'booking-2',
            initialResult: CanonicalBookingRequestResult(
              bookingId: 'booking-2',
              source: 'canonical_v3',
              schemaVersion: canonicalBookingSchemaVersion,
              bookingModelVersion: canonicalBookingModelVersion,
              state: CanonicalBookingStateV3.cancelled,
              bookingType: BookingV3Type.slot,
              requestedAt: DateTime.utc(2026, 7, 28, 8),
              timerStartsAt: DateTime.utc(2026, 7, 28, 8),
              acceptDeadlineAt: DateTime.utc(2026, 7, 28, 9),
              wasQueuedOutsideWorkingHours: false,
              idempotentReplay: false,
            ),
            serviceName: 'Daily Dog Walk',
            providerName: 'Nishant Gautam',
            serviceImageUrl: '',
            bookingRepository: repository,
            servicesRepository: _FakeServicesRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('You paid'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('₹1.00'), findsOneWidget);
      expect(find.text('₹0.25'), findsOneWidget);
      expect(find.text('Refund required'), findsOneWidget);
      expect(find.text('₹0.60'), findsNothing);
      expect(find.text('Payout status'), findsNothing);
      expect(find.text('IMPORTANT INFORMATION'), findsNothing);
      expect(find.byKey(const ValueKey('book-again-cta')), findsOneWidget);
    },
  );

  testWidgets(
    'provider-cancelled-after-payment terminal screen shows refund-aware actions and no payment controls',
    (tester) async {
      final repository = _FakeBookingRepository(
        _buildProviderCancelledAfterPaymentBooking(),
      );

      await tester.pumpWidget(
        MaterialApp(
          routes: {'/settings': (_) => const Scaffold(body: Text('Settings'))},
          home: CanonicalBookingRequestStatusScreen(
            bookingId: 'booking-2',
            initialResult: CanonicalBookingRequestResult(
              bookingId: 'booking-2',
              source: 'canonical_v3',
              schemaVersion: canonicalBookingSchemaVersion,
              bookingModelVersion: canonicalBookingModelVersion,
              state: CanonicalBookingStateV3.cancelled,
              bookingType: BookingV3Type.slot,
              requestedAt: DateTime.utc(2026, 7, 28, 8),
              timerStartsAt: DateTime.utc(2026, 7, 28, 8),
              acceptDeadlineAt: DateTime.utc(2026, 7, 28, 9),
              wasQueuedOutsideWorkingHours: false,
              idempotentReplay: false,
            ),
            serviceName: 'Daily Dog Walk',
            providerName: 'Nishant Gautam',
            serviceImageUrl: '',
            bookingRepository: repository,
            servicesRepository: _FakeServicesRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Cancelled by Provider'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Cancelled by Provider'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('View Refund Status'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('View Refund Status'), findsOneWidget);
      expect(find.text('Contact Support'), findsOneWidget);
      expect(find.text('Refund Status'), findsOneWidget);
      expect(find.byKey(const ValueKey('book-again-cta')), findsOneWidget);
      expect(find.text('Pay now'), findsNothing);
      expect(find.text('Resume payment'), findsNothing);
    },
  );

  testWidgets(
    'eligible terminal request hides Book Again for missing service',
    (tester) async {
      final repository = _FakeBookingRepository(
        _buildExpiredAwaitingPaymentBooking(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CanonicalBookingRequestStatusScreen(
            bookingId: 'booking-1',
            initialResult: CanonicalBookingRequestResult(
              bookingId: 'booking-1',
              source: 'canonical_v3',
              schemaVersion: canonicalBookingSchemaVersion,
              bookingModelVersion: canonicalBookingModelVersion,
              state: CanonicalBookingStateV3.paymentExpired,
              bookingType: BookingV3Type.slot,
              requestedAt: DateTime.utc(2026, 7, 28, 8),
              timerStartsAt: DateTime.utc(2026, 7, 28, 8),
              acceptDeadlineAt: DateTime.utc(2026, 7, 28, 9),
              wasQueuedOutsideWorkingHours: false,
              idempotentReplay: false,
            ),
            serviceName: 'Daily Dog Walk',
            providerName: 'Nishant Gautam',
            serviceImageUrl: '',
            bookingRepository: repository,
            servicesRepository: _FakeServicesRepository(missing: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('book-again-cta')), findsNothing);
      expect(find.text('PRIMARY ACTIONS'), findsNothing);
    },
  );

  testWidgets(
    'pending-provider request uses shared booking details layout and keeps request actions',
    (tester) async {
      final repository = _FakeBookingRepository(_buildPendingProviderBooking());

      await tester.pumpWidget(
        MaterialApp(
          home: CanonicalBookingRequestStatusScreen(
            bookingId: 'booking-pending',
            initialResult: CanonicalBookingRequestResult(
              bookingId: 'booking-pending',
              source: 'canonical_v3',
              schemaVersion: canonicalBookingSchemaVersion,
              bookingModelVersion: canonicalBookingModelVersion,
              state: CanonicalBookingStateV3.pendingProvider,
              bookingType: BookingV3Type.slot,
              requestedAt: DateTime.utc(2026, 7, 29, 8),
              timerStartsAt: DateTime.utc(2026, 7, 29, 8),
              acceptDeadlineAt: DateTime.utc(2026, 7, 29, 9),
              wasQueuedOutsideWorkingHours: false,
              idempotentReplay: false,
            ),
            serviceName: 'Daily Dog Walk',
            providerName: 'Nishant Gautam',
            serviceImageUrl: '',
            bookingRepository: repository,
            servicesRepository: _FakeServicesRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Booking Details'), findsOneWidget);
      expect(find.text('BOOKING SUMMARY'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('BOOKING STATUS'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('BOOKING STATUS'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Waiting for Provider Response'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Waiting for Provider Response'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('RESPONSE WINDOW'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('RESPONSE WINDOW'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Cancel Request'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Cancel Request'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Pay Now'), findsNothing);
      expect(find.text('Resume Payment'), findsNothing);
      expect(find.byKey(const ValueKey('book-again-cta')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _FakeBookingRepository extends BookingRepository {
  _FakeBookingRepository(this.booking);

  final CanonicalBookingDocumentV3 booking;

  @override
  Stream<CanonicalBookingCancellationRecord?> watchCanonicalBookingCancellation(
    String bookingId,
  ) => Stream.value(
    CanonicalBookingCancellationRecord.fromMap({
      'bookingId': bookingId,
      'actorType': 'CUSTOMER',
      'customerPaidPaise': 100,
      'refundAmountPaise': 25,
      'refundStatus': 'REFUND_REQUIRED',
      'providerCompensationPaise': 60,
    }),
  );

  @override
  Stream<BookingReadModel?> watchCanonicalBooking(String bookingId) {
    return Stream.value(
      CanonicalBookingReadModel(documentId: bookingId, booking: booking),
    );
  }
}

CanonicalBookingDocumentV3 _buildExpiredAwaitingPaymentBooking() {
  final now = DateTime.now().toUtc();
  final requestedAt = now.subtract(const Duration(hours: 2));
  final respondedAt = now.subtract(const Duration(hours: 1, minutes: 40));
  final acceptDeadlineAt = now.subtract(const Duration(hours: 1));
  final payDeadlineAt = now.subtract(const Duration(minutes: 5));
  final scheduledStartAt = now.add(const Duration(days: 1));
  final scheduledEndAt = scheduledStartAt.add(const Duration(hours: 1));
  final dateKey =
      '${scheduledStartAt.year.toString().padLeft(4, '0')}-'
      '${scheduledStartAt.month.toString().padLeft(2, '0')}-'
      '${scheduledStartAt.day.toString().padLeft(2, '0')}';

  final result = parseCanonicalBookingDocumentV3({
    'schemaVersion': canonicalBookingSchemaVersion,
    'bookingModelVersion': canonicalBookingModelVersion,
    'documentFormat': canonicalBookingDocumentFormat,
    'bookingType': 'SLOT',
    'state': 'ACCEPTED_AWAITING_PAYMENT',
    'participants': {
      'parent': {
        'parentId': 'parent-1',
        'displayFirstName': 'Nisha',
        'lastInitial': 'G',
        'photoUrl': '',
        'completedBookingCount': 3,
        'rating': 4.8,
      },
      'provider': {
        'providerId': 'provider-1',
        'displayName': 'Nishant Gautam',
        'username': 'nishant',
        'photoUrl': '',
        'completedBookingCount': 10,
        'rating': 4.9,
      },
    },
    'service': {
      'serviceId': 'service-1',
      'providerId': 'provider-1',
      'serviceTitle': 'Daily Dog Walk',
      'animalType': 'Dog',
      'category': 'Walking',
      'bookingType': 'SLOT',
      'timezone': 'Asia/Kolkata',
      'serviceUnitPricePaise': 10000,
      'durationMinutes': 60,
      'selectedSlotCount': 1,
      'totalDurationMinutes': 60,
      'capacitySnapshot': 1,
      'serviceLocationType': 'provider_location',
      'currency': 'INR',
      'snapshotVersion': 1,
      'checkInDateTime': null,
    },
    'schedule': {
      'bookingType': 'SLOT',
      'slots': [
        {
          'slotId': 'slot-1',
          'dateKey': dateKey,
          'startAt': scheduledStartAt,
          'endAt': scheduledEndAt,
          'durationMinutes': 60,
          'unitPricePaise': 10000,
          'serviceId': 'service-1',
          'providerId': 'provider-1',
          'timezone': 'Asia/Kolkata',
        },
      ],
      'slotCount': 1,
      'scheduledStartAt': scheduledStartAt,
      'scheduledEndAt': scheduledEndAt,
      'totalDurationMinutes': 60,
      'timezone': 'Asia/Kolkata',
      'serviceAnchorAt': scheduledStartAt,
    },
    'lifecycle': {
      'requestedAt': requestedAt,
      'timerStartsAt': requestedAt,
      'wasQueuedOutsideWorkingHours': false,
      'notifiedAt': requestedAt,
      'acceptDeadlineAt': acceptDeadlineAt,
      'viewedByProviderAt': respondedAt,
      'respondedAt': respondedAt,
      'providerResponseType': 'accept',
      'responseSeconds': 1200,
      'payDeadlineAt': payDeadlineAt,
      'paymentStartedAt': null,
      'paidAt': null,
      'paymentSeconds': null,
      'otpGeneratedAt': null,
      'otpEnteredAt': null,
      'serviceEndedAt': null,
      'noShowAt': null,
      'disputeDeadlineAt': null,
      'completedAt': null,
      'cancelledAt': null,
    },
    'payment': {
      'status': 'not_started',
      'razorpayOrderId': '',
      'razorpayPaymentId': '',
      'razorpayRefundId': '',
      'paymentAttemptId': '',
      'orderCreatedAt': null,
      'paymentStartedAt': null,
      'capturedAt': null,
      'verifiedAt': null,
      'verificationSource': '',
      'webhookEventIds': <String>[],
      'failureCode': '',
      'failureMessage': '',
    },
    'financials': {
      'currency': 'INR',
      'serviceSubtotalPaise': 10000,
      'couponDiscountPaise': 0,
      'customerPaidPaise': 0,
      'platformCommissionRateBasisPoints': 1500,
      'platformCommissionPaise': 1500,
      'providerPayoutPaise': 8500,
      'pettxoCouponFundingPaise': 0,
      'gatewayFeeSunkPaise': 0,
      'providerFaultCostPaise': 0,
      'refundAmountPaise': 0,
      'pettxoNetBeforeGatewayPaise': 1500,
      'pricingVersion': 1,
    },
    'privacy': {
      'isPaidContactUnlocked': false,
      'contactUnlockedAt': null,
      'chatUnlockedAt': null,
      'otpVisibleToParent': false,
      'exactAddressUnlocked': false,
      'privacyVersion': 1,
      'privateParticipantsRefPath': 'bookingPrivateParticipants/booking-1',
    },
    'cancellation': {
      'cancelledAt': null,
      'cancelledBy': null,
      'cancelReasonCode': '',
      'cancelReasonText': '',
      'hoursBeforeServiceAtCancel': null,
      'refundBand': '',
      'refundBasisPoints': null,
      'refundAmountPaise': 0,
      'providerCompensationPaise': 0,
      'pettxoRetainedPaise': 0,
      'cancellationType': null,
    },
    'dispute': {
      'status': 'none',
      'raisedAt': null,
      'raisedBy': null,
      'reasonCode': '',
      'description': '',
      'evidenceRefs': <String>[],
      'resolvedAt': null,
      'resolvedBy': null,
      'resolution': '',
      'customerRefundPaise': 0,
      'providerReleasePaise': 0,
    },
    'payout': {
      'status': 'not_eligible',
      'eligibleAt': null,
      'releasedAt': null,
      'providerPayoutPaise': 0,
      'payoutReference': '',
      'failureCode': '',
      'retryCount': 0,
    },
    'statistics': {
      'selectedSlotCount': 1,
      'totalDurationMinutes': 60,
      'nights': null,
    },
    'audit': {
      'createdBy': 'system',
      'lastUpdatedBy': 'system',
      'source': 'test',
    },
    'parentId': 'parent-1',
    'providerId': 'provider-1',
    'serviceId': 'service-1',
    'stateQueryValue': 'ACCEPTED_AWAITING_PAYMENT',
    'bookingTypeQueryValue': 'SLOT',
    'serviceAnchorAt': scheduledStartAt,
    'scheduledStartAt': scheduledStartAt,
    'checkInDateTime': null,
    'acceptDeadlineAt': acceptDeadlineAt,
    'payDeadlineAt': payDeadlineAt,
    'completedAt': null,
    'customerId': 'parent-1',
    'serviceOwnerId': 'provider-1',
    'createdAt': requestedAt,
    'updatedAt': now,
  });

  expect(result.isValid, isTrue);
  return result.booking!;
}

CanonicalBookingDocumentV3 _buildPendingProviderBooking() {
  final now = DateTime.now().toUtc();
  final requestedAt = now.subtract(const Duration(minutes: 10));
  final acceptDeadlineAt = now.add(const Duration(minutes: 50));
  final scheduledStartAt = now.add(const Duration(days: 1));
  final scheduledEndAt = scheduledStartAt.add(const Duration(hours: 1));
  return CanonicalBookingDocumentV3(
    schemaVersion: canonicalBookingSchemaVersion,
    bookingModelVersion: canonicalBookingModelVersion,
    documentFormat: canonicalBookingDocumentFormat,
    bookingType: BookingV3Type.slot,
    state: CanonicalBookingStateV3.pendingProvider,
    participants: const CanonicalBookingParticipantsV3(
      parent: CanonicalPublicParentParticipantV3(
        parentId: 'parent-1',
        displayFirstName: 'Nisha',
        lastInitial: 'G',
        photoUrl: '',
        completedBookingCount: 3,
        rating: 4.8,
      ),
      provider: CanonicalPublicProviderParticipantV3(
        providerId: 'provider-1',
        displayName: 'Nishant Gautam',
        username: 'nishant',
        photoUrl: '',
        completedBookingCount: 10,
        rating: 4.9,
      ),
    ),
    service: BookingServiceSnapshotV3(
      serviceId: 'service-1',
      providerId: 'provider-1',
      serviceTitle: 'Daily Dog Walk',
      animalType: 'Dog',
      category: 'Walking',
      bookingType: BookingV3Type.slot,
      timezone: 'Asia/Kolkata',
      serviceUnitPricePaise: 10000,
      durationMinutes: 60,
      pricePerNightPaise: null,
      selectedSlotCount: 1,
      totalDurationMinutes: 60,
      checkInDateTime: null,
      checkOutDateTime: null,
      capacitySnapshot: 1,
      serviceLocationType: 'provider_location',
      currency: 'INR',
      schedulingMode: 'fixedDuration',
      snapshotVersion: 1,
    ),
    schedule: CanonicalSlotBookingScheduleV3(
      serviceAnchorAt: scheduledStartAt,
      timezone: 'Asia/Kolkata',
      slots: [
        CanonicalBookingSlotSegmentV3(
          slotId: 'slot-1',
          dateKey:
              '${scheduledStartAt.year.toString().padLeft(4, '0')}-'
              '${scheduledStartAt.month.toString().padLeft(2, '0')}-'
              '${scheduledStartAt.day.toString().padLeft(2, '0')}',
          startAt: scheduledStartAt,
          endAt: scheduledEndAt,
          durationMinutes: 60,
          unitPricePaise: 10000,
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
      requestedAt: requestedAt,
      timerStartsAt: requestedAt,
      wasQueuedOutsideWorkingHours: false,
      notifiedAt: requestedAt,
      acceptDeadlineAt: acceptDeadlineAt,
      viewedByProviderAt: null,
      respondedAt: null,
      providerResponseType: null,
      responseSeconds: null,
      payDeadlineAt: null,
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
    payment: const CanonicalBookingPaymentV3(
      status: 'not_started',
      razorpayOrderId: '',
      razorpayPaymentId: '',
      razorpayRefundId: '',
      paymentAttemptId: '',
      orderCreatedAt: null,
      paymentStartedAt: null,
      capturedAt: null,
      verifiedAt: null,
      verificationSource: '',
      webhookEventIds: [],
      failureCode: '',
      failureMessage: '',
    ),
    financials: BookingFinancialSnapshotV3(
      currency: 'INR',
      serviceSubtotalPaise: 10000,
      couponDiscountPaise: 0,
      customerPaidPaise: 0,
      platformCommissionRateBasisPoints: 0,
      platformCommissionPaise: 0,
      providerPayoutPaise: 0,
      pettxoCouponFundingPaise: 0,
      gatewayFeeSunkPaise: 0,
      providerFaultCostPaise: 0,
      refundAmountPaise: 0,
      pettxoNetBeforeGatewayPaise: 0,
      pricingVersion: 1,
    ),
    privacy: const CanonicalBookingPrivacyV3(
      isPaidContactUnlocked: false,
      contactUnlockedAt: null,
      chatUnlockedAt: null,
      otpVisibleToParent: false,
      exactAddressUnlocked: false,
      privacyVersion: canonicalBookingPrivacyVersion,
      privateParticipantsRefPath: '',
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
      status: '',
      raisedAt: null,
      raisedBy: null,
      reasonCode: '',
      description: '',
      evidenceRefs: [],
      resolvedAt: null,
      resolvedBy: null,
      resolution: '',
      resolutionVersion: 0,
      financialAdjustmentId: '',
      refundInstructionId: '',
      customerRefundPaise: 0,
      providerReleasePaise: 0,
      publicResolutionMessage: '',
    ),
    payout: const CanonicalBookingPayoutV3(
      status: '',
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
      createdBy: BookingActorV3.parent,
      lastUpdatedBy: BookingActorV3.system,
      source: 'test',
    ),
    parentId: 'parent-1',
    providerId: 'provider-1',
    serviceId: 'service-1',
    stateQueryValue: CanonicalBookingStateV3.pendingProvider,
    bookingTypeQueryValue: BookingV3Type.slot,
    serviceAnchorAt: scheduledStartAt,
    scheduledStartAt: scheduledStartAt,
    checkInDateTime: null,
    acceptDeadlineAt: acceptDeadlineAt,
    payDeadlineAt: null,
    completedAt: null,
    customerId: 'parent-1',
    serviceOwnerId: 'provider-1',
    createdAt: requestedAt,
    updatedAt: requestedAt,
  );
}

CanonicalBookingDocumentV3 _buildProviderCancelledAfterPaymentBooking({
  String actor = 'provider',
}) {
  final now = DateTime.now().toUtc();
  final requestedAt = now.subtract(const Duration(days: 1, hours: 3));
  final respondedAt = requestedAt.add(const Duration(minutes: 10));
  final paidAt = respondedAt.add(const Duration(minutes: 6));
  final cancelledAt = paidAt.add(const Duration(hours: 1));
  final scheduledStartAt = now.add(const Duration(days: 1));
  final scheduledEndAt = scheduledStartAt.add(const Duration(hours: 1));
  final dateKey =
      '${scheduledStartAt.year.toString().padLeft(4, '0')}-'
      '${scheduledStartAt.month.toString().padLeft(2, '0')}-'
      '${scheduledStartAt.day.toString().padLeft(2, '0')}';

  final result = parseCanonicalBookingDocumentV3({
    'schemaVersion': canonicalBookingSchemaVersion,
    'bookingModelVersion': canonicalBookingModelVersion,
    'documentFormat': canonicalBookingDocumentFormat,
    'bookingType': 'SLOT',
    'state': 'CANCELLED',
    'participants': {
      'parent': {
        'parentId': 'parent-1',
        'displayFirstName': 'Nisha',
        'lastInitial': 'G',
        'photoUrl': '',
        'completedBookingCount': 3,
        'rating': 4.8,
      },
      'provider': {
        'providerId': 'provider-1',
        'displayName': 'Nishant Gautam',
        'username': 'nishant',
        'photoUrl': '',
        'completedBookingCount': 10,
        'rating': 4.9,
      },
    },
    'service': {
      'serviceId': 'service-1',
      'providerId': 'provider-1',
      'serviceTitle': 'Daily Dog Walk',
      'animalType': 'Dog',
      'category': 'Walking',
      'bookingType': 'SLOT',
      'timezone': 'Asia/Kolkata',
      'serviceUnitPricePaise': 10000,
      'durationMinutes': 60,
      'selectedSlotCount': 1,
      'totalDurationMinutes': 60,
      'capacitySnapshot': 1,
      'serviceLocationType': 'provider_location',
      'currency': 'INR',
      'snapshotVersion': 1,
      'checkInDateTime': null,
    },
    'schedule': {
      'bookingType': 'SLOT',
      'slots': [
        {
          'slotId': 'slot-1',
          'dateKey': dateKey,
          'startAt': scheduledStartAt,
          'endAt': scheduledEndAt,
          'durationMinutes': 60,
          'unitPricePaise': 10000,
          'serviceId': 'service-1',
          'providerId': 'provider-1',
          'timezone': 'Asia/Kolkata',
        },
      ],
      'slotCount': 1,
      'scheduledStartAt': scheduledStartAt,
      'scheduledEndAt': scheduledEndAt,
      'totalDurationMinutes': 60,
      'timezone': 'Asia/Kolkata',
      'serviceAnchorAt': scheduledStartAt,
    },
    'lifecycle': {
      'requestedAt': requestedAt,
      'timerStartsAt': requestedAt,
      'wasQueuedOutsideWorkingHours': false,
      'notifiedAt': requestedAt,
      'acceptDeadlineAt': requestedAt.add(const Duration(hours: 1)),
      'viewedByProviderAt': respondedAt,
      'respondedAt': respondedAt,
      'providerResponseType': 'accept',
      'responseSeconds': 600,
      'payDeadlineAt': requestedAt.add(const Duration(hours: 2)),
      'paymentStartedAt': respondedAt.add(const Duration(minutes: 2)),
      'paidAt': paidAt,
      'paymentSeconds': 360,
      'otpGeneratedAt': null,
      'otpEnteredAt': null,
      'serviceEndedAt': null,
      'noShowAt': null,
      'disputeDeadlineAt': null,
      'completedAt': null,
      'cancelledAt': cancelledAt,
    },
    'payment': {
      'status': 'refunded',
      'razorpayOrderId': 'order_1',
      'razorpayPaymentId': 'pay_1',
      'razorpayRefundId': 'rfnd_1',
      'paymentAttemptId': 'attempt_1',
      'orderCreatedAt': requestedAt,
      'paymentStartedAt': respondedAt.add(const Duration(minutes: 2)),
      'capturedAt': paidAt,
      'verifiedAt': paidAt,
      'verificationSource': 'test',
      'webhookEventIds': <String>[],
      'failureCode': '',
      'failureMessage': '',
    },
    'financials': {
      'currency': 'INR',
      'serviceSubtotalPaise': 10000,
      'couponDiscountPaise': 0,
      'customerPaidPaise': 10000,
      'platformCommissionRateBasisPoints': 1500,
      'platformCommissionPaise': 1500,
      'providerPayoutPaise': 8500,
      'pettxoCouponFundingPaise': 0,
      'gatewayFeeSunkPaise': 0,
      'providerFaultCostPaise': 0,
      'refundAmountPaise': 10000,
      'pettxoNetBeforeGatewayPaise': 1500,
      'pricingVersion': 1,
    },
    'privacy': {
      'isPaidContactUnlocked': false,
      'contactUnlockedAt': null,
      'chatUnlockedAt': null,
      'otpVisibleToParent': false,
      'exactAddressUnlocked': false,
      'privacyVersion': 1,
      'privateParticipantsRefPath': 'bookingPrivateParticipants/booking-2',
    },
    'cancellation': {
      'cancelledAt': cancelledAt,
      'cancelledBy': actor,
      'cancelReasonCode': 'provider_unavailable',
      'cancelReasonText': 'Provider unavailable.',
      'hoursBeforeServiceAtCancel': 12,
      'refundBand': 'FULL',
      'refundBasisPoints': 10000,
      'refundAmountPaise': 10000,
      'providerCompensationPaise': 0,
      'pettxoRetainedPaise': 0,
      'cancellationType': 'provider_cancelled_after_payment',
    },
    'dispute': {
      'status': 'none',
      'raisedAt': null,
      'raisedBy': null,
      'reasonCode': '',
      'description': '',
      'evidenceRefs': <String>[],
      'resolvedAt': null,
      'resolvedBy': null,
      'resolution': '',
      'customerRefundPaise': 0,
      'providerReleasePaise': 0,
    },
    'payout': {
      'status': 'not_eligible',
      'eligibleAt': null,
      'releasedAt': null,
      'providerPayoutPaise': 0,
      'payoutReference': '',
      'failureCode': '',
      'retryCount': 0,
    },
    'statistics': {
      'selectedSlotCount': 1,
      'totalDurationMinutes': 60,
      'nights': null,
    },
    'audit': {
      'createdBy': 'system',
      'lastUpdatedBy': 'system',
      'source': 'test',
    },
    'parentId': 'parent-1',
    'providerId': 'provider-1',
    'serviceId': 'service-1',
    'stateQueryValue': 'CANCELLED',
    'bookingTypeQueryValue': 'SLOT',
    'serviceAnchorAt': scheduledStartAt,
    'scheduledStartAt': scheduledStartAt,
    'checkInDateTime': null,
    'acceptDeadlineAt': requestedAt.add(const Duration(hours: 1)),
    'payDeadlineAt': requestedAt.add(const Duration(hours: 2)),
    'completedAt': null,
    'customerId': 'parent-1',
    'serviceOwnerId': 'provider-1',
    'createdAt': requestedAt,
    'updatedAt': now,
  });

  expect(result.isValid, isTrue);
  return result.booking!;
}

class _FakeServicesRepository implements ServicesRepository {
  _FakeServicesRepository({
    ServiceModel? service,
    bool missing = false,
    this.loader,
  }) : service = missing ? null : service ?? _buildActiveService();

  final ServiceModel? service;
  final ServiceModel? Function(String serviceId, int callCount)? loader;
  final List<String> requestedServiceIds = <String>[];

  @override
  Future<ServiceModel?> fetchServiceById(String serviceId) async {
    requestedServiceIds.add(serviceId);
    if (loader != null) {
      return loader!(serviceId, requestedServiceIds.length);
    }
    return service;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ServiceModel _buildActiveService() {
  return ServiceModel.fromMap('service-1', {
    'ownerUserId': 'provider-1',
    'title': 'Daily Dog Walk',
    'status': 'active',
    'isActive': true,
    'isDeleted': false,
    'isPaused': false,
    'isVisibleToMarketplace': true,
    'providerVerificationStatus': 'approved',
  });
}
