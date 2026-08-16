import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/data/repositories/booking_repository.dart';
import 'package:pettexo/features/bookings/domain/models/booking_document_v3.dart';
import 'package:pettexo/features/bookings/domain/models/booking_read_model.dart';
import 'package:pettexo/features/bookings/domain/models/booking_v3_models.dart';
import 'package:pettexo/features/bookings/domain/models/canonical_booking_cancellation_models.dart';
import 'package:pettexo/features/bookings/domain/models/canonical_booking_request_models.dart';
import 'package:pettexo/features/bookings/domain/models/canonical_provider_booking_request_view.dart';
import 'package:pettexo/features/bookings/presentation/screens/canonical_provider_booking_request_detail_screen.dart';
import 'package:pettexo/features/bookings/presentation/utils/canonical_booking_schedule_presentation.dart';
import 'package:pettexo/features/bookings/presentation/widgets/canonical_provider_request_card.dart';

void main() {
  CanonicalProviderBookingRequestView buildRequest({
    required CanonicalBookingStateV3 state,
    int? estimatedProviderPayoutPaise = 20000,
    DateTime? payDeadlineAt,
    String maskedParentDisplayName = 'Anita G.',
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
      maskedParentDisplayName: maskedParentDisplayName,
      parentRating: 4.8,
      completedBookingCount: 4,
      scheduledStartAt: scheduledStartAt,
      scheduledEndAt: scheduledEndAt,
      slotCount: 1,
      totalDurationMinutes: 90,
      timerStartsAt: timerStartsAt,
      acceptDeadlineAt: acceptDeadlineAt,
      payDeadlineAt: payDeadlineAt ?? now.add(const Duration(minutes: 45)),
      timezone: 'Asia/Kolkata',
      schedulingMode: 'fixedDuration',
      estimatedProviderPayoutPaise: estimatedProviderPayoutPaise,
      schedulePresentation: CanonicalBookingSchedulePresentation(
        bookingType: BookingV3Type.slot,
        effectiveSegments: const <CanonicalBookingScheduleSegmentV3>[],
        isMultiDayPackage: false,
        hasContinuousServiceWindow: true,
        serviceDayCount: 1,
        segmentCount: 1,
        slotCount: 1,
        firstStartAt: scheduledStartAt,
        firstSegmentEndAt: scheduledEndAt,
        finalEndAt: scheduledEndAt,
        totalDurationMinutes: 90,
        schedulingMode: 'fixedDuration',
        compactDateRangeLabel: 'Tomorrow',
        compactScheduleSummary: 'Tomorrow · 90 min',
        dateLabel: 'Tomorrow',
        timeLabel: 'Flexible',
        durationLabel: '90 min',
        packageLabel: '',
        perSegmentDisplayRows: const <CanonicalBookingScheduleDisplayRow>[],
        cancellationConfirmationMessage: '',
      ),
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required CanonicalProviderBookingRequestView request,
    _FakeBookingRepository? bookingRepository,
    double textScaleFactor = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScaleFactor)),
          child: CanonicalProviderBookingRequestDetailScreen(
            initialRequest: request,
            bookingRepository: bookingRepository ?? _FakeBookingRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'queued provider request uses shared booking details sections and actions',
    (tester) async {
      await pumpScreen(
        tester,
        request: buildRequest(state: CanonicalBookingStateV3.requested),
      );

      expect(find.text('Booking Details'), findsOneWidget);
      expect(find.text('BOOKING SUMMARY'), findsOneWidget);
      await _scrollUntilTextVisible(tester, 'BOOKING STATUS');
      expect(find.text('BOOKING STATUS'), findsOneWidget);
      await _scrollUntilTextVisible(tester, 'Action Required');
      expect(find.text('Action Required'), findsOneWidget);
      await _scrollUntilTextVisible(tester, 'RESPONSE WINDOW');
      expect(find.text('RESPONSE WINDOW'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(find.textContaining('actions stay locked'), findsNothing);
    },
  );

  testWidgets(
    'accepted request shows payment-window layout without provider actions',
    (tester) async {
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
      await _scrollUntilTextVisible(tester, 'Accepted, Awaiting Payment');
      expect(find.text('Accepted, Awaiting Payment'), findsOneWidget);
      await _scrollUntilTextVisible(tester, 'RESPONSE WINDOW');
      expect(find.text('Customer payment window'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Decline'), findsNothing);
    },
  );

  testWidgets(
    'accepted request keeps customer identity redacted during the payment window',
    (tester) async {
      await pumpScreen(
        tester,
        request: buildRequest(
          state: CanonicalBookingStateV3.acceptedAwaitingPayment,
          maskedParentDisplayName: 'Customer',
        ),
      );

      await _scrollUntilTextVisible(tester, 'BOOKING SUMMARY');
      expect(find.text('Customer'), findsWidgets);
      expect(find.text('Anita G.'), findsNothing);
    },
  );

  testWidgets(
    'expired accepted request opens unified provider terminal details and hides active controls',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final expiredDeadline = DateTime.utc(
        2026,
        7,
        29,
        9,
      ).subtract(const Duration(minutes: 5));
      final booking = _buildCanonicalBooking(
        state: CanonicalBookingStateV3.acceptedAwaitingPayment,
        payDeadlineAt: expiredDeadline,
        respondedAt: DateTime.utc(2026, 7, 29, 7, 30),
      );

      await pumpScreen(
        tester,
        request: buildRequest(
          state: CanonicalBookingStateV3.acceptedAwaitingPayment,
          payDeadlineAt: expiredDeadline,
        ),
        bookingRepository: _FakeBookingRepository(booking: booking),
      );

      expect(find.text('Booking Details'), findsOneWidget);
      expect(find.text('BOOKING SUMMARY'), findsOneWidget);
      await _scrollUntilTextVisible(tester, 'BOOKING STATUS');
      expect(find.text('BOOKING STATUS'), findsOneWidget);
      await _scrollUntilTextVisible(tester, 'Payment Window Expired');
      expect(find.text('Payment Window Expired'), findsOneWidget);
      expect(find.text('Expired'), findsOneWidget);
      expect(
        find.textContaining(
          'did not complete payment within the allowed time',
          findRichText: true,
        ),
        findsWidgets,
      );
      await _scrollUntilTextVisible(tester, 'BOOKING TIMELINE');
      expect(find.text('BOOKING TIMELINE'), findsOneWidget);
      await _scrollUntilTextVisible(tester, 'OUTCOME DETAILS');
      expect(find.text('OUTCOME DETAILS'), findsOneWidget);
      await _scrollUntilTextVisible(tester, 'IMPORTANT INFORMATION');
      expect(find.text('IMPORTANT INFORMATION'), findsOneWidget);
      expect(find.text('Time remaining'), findsNothing);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Decline'), findsNothing);
      expect(find.text('Cancel request'), findsNothing);
      expect(find.textContaining('safe read compatibility'), findsNothing);
      expect(
        find.textContaining('latest state has already been applied'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'customer cancelled before payment shows read-only cancelled details with no payout placeholder',
    (tester) async {
      final cancelledAt = DateTime.utc(2026, 7, 29, 8, 45);
      final booking = _buildCanonicalBooking(
        state: CanonicalBookingStateV3.cancelledByParent,
        cancelledAt: cancelledAt,
        cancelledBy: 'PARENT',
        cancelReasonText: 'Changed plans',
      );

      await pumpScreen(
        tester,
        request: buildRequest(state: CanonicalBookingStateV3.cancelledByParent),
        bookingRepository: _FakeBookingRepository(booking: booking),
      );

      await _scrollUntilTextVisible(tester, 'Cancelled by Customer');
      expect(find.text('Cancelled by Customer'), findsWidgets);
      expect(
        find.textContaining('No payment was collected.', findRichText: true),
        findsWidgets,
      );
      await _scrollUntilTextVisible(tester, 'Customer payment');
      expect(find.text('Customer payment'), findsOneWidget);
      expect(find.text('Not collected'), findsOneWidget);
      expect(
        find.text('Payout shown after payment flow activation'),
        findsNothing,
      );
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Decline'), findsNothing);
    },
  );

  testWidgets(
    'customer cancelled after payment shows authoritative refund and settlement rows only when available',
    (tester) async {
      final cancelledAt = DateTime.utc(2026, 7, 29, 11, 15);
      final booking = _buildCanonicalBooking(
        state: CanonicalBookingStateV3.cancelledByParent,
        respondedAt: DateTime.utc(2026, 7, 29, 9, 30),
        paidAt: DateTime.utc(2026, 7, 29, 10),
        cancelledAt: cancelledAt,
        cancelledBy: 'CUSTOMER',
        cancelReasonText: 'Changed plans',
        customerPaidPaise: 89900,
        refundAmountPaise: 89900,
        payoutStatus: 'processing',
      );
      final cancellationRecord = _buildCancellationRecord(
        actorType: 'CUSTOMER',
        cancelledAt: cancelledAt,
        reasonText: 'Changed plans',
        customerPaidPaise: 89900,
        refundAmountPaise: 89900,
        refundStatus: 'processing',
        providerCompensationPaise: 0,
      );

      await pumpScreen(
        tester,
        request: buildRequest(state: CanonicalBookingStateV3.cancelledByParent),
        bookingRepository: _FakeBookingRepository(
          booking: booking,
          cancellationRecord: cancellationRecord,
        ),
      );

      await _scrollUntilTextVisible(tester, 'Cancelled by Customer');
      expect(find.text('Cancelled by Customer'), findsWidgets);
      await _scrollUntilTextVisible(tester, 'Customer paid');
      expect(find.text('Customer paid'), findsOneWidget);
      expect(find.text('₹899'), findsWidgets);
      expect(find.text('Refund status'), findsOneWidget);
      expect(find.text('Processing'), findsWidgets);
      expect(find.text('Provider settlement status'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Decline'), findsNothing);
      expect(find.text('Cancel request'), findsNothing);
      expect(find.text('Time remaining'), findsNothing);
    },
  );

  testWidgets(
    'provider cancelled after payment shows cancelled by you without customer wording',
    (tester) async {
      final cancelledAt = DateTime.utc(2026, 7, 28, 12, 20);
      final booking = _buildCanonicalBooking(
        state: CanonicalBookingStateV3.cancelled,
        respondedAt: DateTime.utc(2026, 7, 28, 10, 15),
        paidAt: DateTime.utc(2026, 7, 28, 10, 45),
        cancelledAt: cancelledAt,
        cancelledBy: 'PROVIDER',
        cancelReasonText: 'Not available',
        customerPaidPaise: 10000,
        refundAmountPaise: 10000,
        payoutStatus: 'cancelled',
      );
      final cancellationRecord = _buildCancellationRecord(
        actorType: 'PROVIDER',
        cancelledAt: cancelledAt,
        reasonText: 'Not available',
        customerPaidPaise: 10000,
        refundAmountPaise: 10000,
        refundStatus: 'completed',
        providerCompensationPaise: 0,
      );

      await pumpScreen(
        tester,
        request: buildRequest(state: CanonicalBookingStateV3.cancelled),
        bookingRepository: _FakeBookingRepository(
          booking: booking,
          cancellationRecord: cancellationRecord,
        ),
      );

      await _scrollUntilTextVisible(tester, 'Cancelled by You');
      expect(find.text('Cancelled by You'), findsWidgets);
      expect(find.text('Cancelled by Customer'), findsNothing);
      await _scrollUntilTextVisible(tester, 'Cancelled by');
      expect(find.text('You'), findsWidgets);
      expect(find.text('Not available'), findsOneWidget);
      expect(find.text('Message customer'), findsNothing);
      expect(find.text('Enter customer OTP'), findsNothing);
    },
  );

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

CanonicalBookingDocumentV3 _buildCanonicalBooking({
  required CanonicalBookingStateV3 state,
  DateTime? respondedAt,
  DateTime? paidAt,
  DateTime? payDeadlineAt,
  DateTime? cancelledAt,
  String? cancelledBy,
  String cancelReasonText = '',
  int customerPaidPaise = 0,
  int refundAmountPaise = 0,
  int providerCompensationPaise = 0,
  String payoutStatus = '',
}) {
  final requestedAt = DateTime.utc(2026, 7, 28, 6, 30);
  final startAt = DateTime.utc(2026, 7, 29, 12, 0);
  final endAt = DateTime.utc(2026, 7, 29, 13, 30);
  final deadline =
      payDeadlineAt ?? respondedAt?.add(const Duration(hours: 1)) ?? startAt;

  return CanonicalBookingDocumentV3(
    schemaVersion: canonicalBookingSchemaVersion,
    bookingModelVersion: canonicalBookingModelVersion,
    documentFormat: canonicalBookingDocumentFormat,
    bookingType: BookingV3Type.slot,
    state: state,
    participants: const CanonicalBookingParticipantsV3(
      parent: CanonicalPublicParentParticipantV3(
        parentId: 'parent-1',
        displayFirstName: 'Anita',
        lastInitial: 'G',
        photoUrl: '',
        completedBookingCount: 0,
        rating: 0,
      ),
      provider: CanonicalPublicProviderParticipantV3(
        providerId: 'provider-1',
        displayName: 'Prakash Gautam',
        username: 'prakash',
        photoUrl: '',
        completedBookingCount: 0,
        rating: 0,
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
      serviceUnitPricePaise: 89900,
      durationMinutes: 90,
      pricePerNightPaise: null,
      selectedSlotCount: 1,
      totalDurationMinutes: 90,
      checkInDateTime: null,
      checkOutDateTime: null,
      capacitySnapshot: 1,
      serviceLocationType: 'provider_location',
      currency: 'INR',
      schedulingMode: 'fixedDuration',
      snapshotVersion: 1,
    ),
    schedule: CanonicalSlotBookingScheduleV3(
      serviceAnchorAt: startAt,
      timezone: 'Asia/Kolkata',
      slots: [
        CanonicalBookingSlotSegmentV3(
          slotId: 'slot-1',
          dateKey: '2026-07-29',
          startAt: startAt,
          endAt: endAt,
          durationMinutes: 90,
          unitPricePaise: 89900,
          serviceId: 'service-1',
          providerId: 'provider-1',
          timezone: 'Asia/Kolkata',
        ),
      ],
      slotCount: 1,
      scheduledStartAt: startAt,
      scheduledEndAt: endAt,
      totalDurationMinutes: 90,
    ),
    lifecycle: CanonicalBookingLifecycleV3(
      requestedAt: requestedAt,
      timerStartsAt: requestedAt,
      wasQueuedOutsideWorkingHours: false,
      notifiedAt: requestedAt,
      acceptDeadlineAt: requestedAt.add(const Duration(hours: 1)),
      viewedByProviderAt: requestedAt.add(const Duration(minutes: 5)),
      respondedAt: respondedAt,
      providerResponseType: respondedAt == null
          ? null
          : ProviderResponseTypeV3.accept,
      responseSeconds: respondedAt?.difference(requestedAt).inSeconds,
      payDeadlineAt: deadline,
      paymentStartedAt: paidAt?.subtract(const Duration(minutes: 5)),
      paidAt: paidAt,
      paymentSeconds: paidAt == null ? null : 300,
      otpGeneratedAt: null,
      otpEnteredAt: null,
      noShowAt: null,
      serviceEndedAt: null,
      disputeDeadlineAt: null,
      completedAt: null,
      reviewWindowEndsAt: null,
      finalizedAt: cancelledAt ?? paidAt ?? deadline,
      cancelledAt: cancelledAt,
    ),
    payment: CanonicalBookingPaymentV3(
      status: paidAt == null ? 'pending' : 'captured',
      razorpayOrderId: '',
      razorpayPaymentId: '',
      razorpayRefundId: '',
      paymentAttemptId: paidAt == null ? 'attempt-1' : 'attempt-paid',
      orderCreatedAt: respondedAt,
      paymentStartedAt: paidAt?.subtract(const Duration(minutes: 5)),
      capturedAt: paidAt,
      verifiedAt: paidAt,
      verificationSource: '',
      webhookEventIds: const [],
      failureCode: '',
      failureMessage: '',
    ),
    financials: customerPaidPaise > 0
        ? BookingFinancialSnapshotV3(
            currency: 'INR',
            serviceSubtotalPaise: customerPaidPaise,
            couponDiscountPaise: 0,
            customerPaidPaise: customerPaidPaise,
            platformCommissionRateBasisPoints: 1500,
            platformCommissionPaise: 0,
            providerPayoutPaise: providerCompensationPaise,
            pettxoCouponFundingPaise: 0,
            gatewayFeeSunkPaise: 0,
            providerFaultCostPaise: 0,
            refundAmountPaise: refundAmountPaise,
            pettxoNetBeforeGatewayPaise: 0,
            pricingVersion: 1,
          )
        : null,
    privacy: const CanonicalBookingPrivacyV3(
      isPaidContactUnlocked: false,
      contactUnlockedAt: null,
      chatUnlockedAt: null,
      otpVisibleToParent: false,
      exactAddressUnlocked: false,
      privacyVersion: canonicalBookingPrivacyVersion,
      privateParticipantsRefPath: '',
    ),
    cancellation: CanonicalBookingCancellationV3(
      cancelledAt: cancelledAt,
      cancelledBy: cancelledBy,
      cancelReasonCode: cancelReasonText.isEmpty ? '' : 'reason',
      cancelReasonText: cancelReasonText,
      hoursBeforeServiceAtCancel: null,
      refundBand: '',
      refundBasisPoints: null,
      refundAmountPaise: refundAmountPaise,
      providerCompensationPaise: providerCompensationPaise,
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
    ),
    payout: CanonicalBookingPayoutV3(
      status: payoutStatus,
      holdReason: '',
      eligibleAt: null,
      readyAt: null,
      processingAt: payoutStatus == 'processing'
          ? cancelledAt?.add(const Duration(minutes: 30))
          : null,
      releasedAt: payoutStatus == 'released'
          ? cancelledAt?.add(const Duration(hours: 4))
          : null,
      failedAt: null,
      providerPayoutPaise: providerCompensationPaise,
      priorPaidPaise: 0,
      remainingPayablePaise: 0,
      payoutReference: '',
      externalTransactionId: '',
      failureCode: '',
      retryCount: 0,
    ),
    statistics: const CanonicalBookingStatisticsV3(
      selectedSlotCount: 1,
      totalDurationMinutes: 90,
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
    stateQueryValue: state,
    bookingTypeQueryValue: BookingV3Type.slot,
    serviceAnchorAt: startAt,
    scheduledStartAt: startAt,
    checkInDateTime: null,
    acceptDeadlineAt: requestedAt.add(const Duration(hours: 1)),
    payDeadlineAt: deadline,
    completedAt: null,
    customerId: 'parent-1',
    serviceOwnerId: 'provider-1',
    createdAt: requestedAt,
    updatedAt: cancelledAt ?? paidAt ?? deadline,
  );
}

CanonicalBookingCancellationRecord _buildCancellationRecord({
  required String actorType,
  required DateTime cancelledAt,
  required String reasonText,
  required int customerPaidPaise,
  required int refundAmountPaise,
  required String refundStatus,
  required int providerCompensationPaise,
}) {
  return CanonicalBookingCancellationRecord(
    bookingId: 'booking-1',
    actorType: actorType,
    actorId: actorType == 'PROVIDER' ? 'provider-1' : 'parent-1',
    reasonCode: 'changed_plans',
    reasonText: reasonText,
    requestedAt: cancelledAt,
    effectiveAt: cancelledAt,
    policyVersion: 'v1',
    timingBand: 'after_payment',
    refundPercentageBasisPoints: 10000,
    providerShareBasisPoints: 0,
    pettxoShareBasisPoints: 0,
    refundableCustomerPaidPaise: refundAmountPaise,
    nonRefundableCustomerPaidPaise: customerPaidPaise - refundAmountPaise,
    providerCompensationPaise: providerCompensationPaise,
    pettxoRetainedPaise: 0,
    gatewayFeeSunkPaise: 0,
    providerFaultCostPaise: 0,
    customerPaidPaise: customerPaidPaise,
    capacityReleaseRequired: true,
    financialReversalRequired: true,
    refundInstructionId: 'refund-1',
    status: 'completed',
    createdAt: cancelledAt.add(const Duration(minutes: 5)),
    updatedAt: cancelledAt.add(const Duration(hours: 1)),
    refundAmountPaise: refundAmountPaise,
    refundStatus: refundStatus,
    capacityReleaseState: 'released',
    outcome: 'cancelled',
  );
}

class _FakeBookingRepository extends BookingRepository {
  _FakeBookingRepository({this.booking, this.cancellationRecord});

  final CanonicalBookingDocumentV3? booking;
  final CanonicalBookingCancellationRecord? cancellationRecord;

  @override
  Stream<BookingReadModel?> watchCanonicalBooking(String bookingId) {
    if (booking == null) {
      return Stream.value(null);
    }
    return Stream.value(
      CanonicalBookingReadModel(documentId: bookingId, booking: booking!),
    );
  }

  @override
  Stream<CanonicalBookingCancellationRecord?> watchCanonicalBookingCancellation(
    String bookingId,
  ) {
    return Stream.value(cancellationRecord);
  }

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

Future<void> _scrollUntilTextVisible(WidgetTester tester, String text) async {
  final finder = find.text(text);
  for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -220));
    await tester.pump();
  }
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
    await tester.pump();
  }
}
