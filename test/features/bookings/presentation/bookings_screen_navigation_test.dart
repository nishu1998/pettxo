import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/widgets/app_buttons.dart';
import 'package:pettexo/features/bookings/domain/models/booking_document_v3.dart';
import 'package:pettexo/features/bookings/domain/models/booking_flow_models.dart';
import 'package:pettexo/features/bookings/domain/models/booking_payment_order.dart';
import 'package:pettexo/features/bookings/domain/models/booking_read_model.dart';
import 'package:pettexo/features/bookings/domain/models/booking_v3_models.dart';
import 'package:pettexo/features/bookings/domain/models/canonical_provider_booking_request_view.dart';
import 'package:pettexo/features/bookings/presentation/navigation/booking_navigation_resolver.dart';
import 'package:pettexo/features/bookings/presentation/screens/bookings_screen.dart';

void main() {
  DateTime fixtureBaseUtc() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(hours: 1));
  }

  DateTime fixtureRequestedAtUtc() => fixtureBaseUtc();

  DateTime fixtureSlotStartUtc() =>
      fixtureBaseUtc().add(const Duration(days: 1, hours: 20));

  DateTime fixtureSlotEndUtc() =>
      fixtureSlotStartUtc().add(const Duration(hours: 1));

  DateTime fixturePayDeadlineUtc() =>
      fixtureRequestedAtUtc().add(const Duration(hours: 2, minutes: 30));

  String canonicalStateValue(CanonicalBookingStateV3 state) {
    return switch (state) {
      CanonicalBookingStateV3.requested => 'REQUESTED',
      CanonicalBookingStateV3.pendingProvider => 'PENDING_PROVIDER',
      CanonicalBookingStateV3.acceptedAwaitingPayment =>
        'ACCEPTED_AWAITING_PAYMENT',
      CanonicalBookingStateV3.confirmed => 'CONFIRMED',
      CanonicalBookingStateV3.inProgress => 'IN_PROGRESS',
      CanonicalBookingStateV3.completedPendingReview =>
        'COMPLETED_PENDING_REVIEW',
      CanonicalBookingStateV3.completedFinal => 'COMPLETED_FINAL',
      CanonicalBookingStateV3.declined => 'DECLINED',
      CanonicalBookingStateV3.expired => 'EXPIRED',
      CanonicalBookingStateV3.paymentExpired => 'PAYMENT_EXPIRED',
      CanonicalBookingStateV3.cancelledByParent => 'CANCELLED_BY_PARENT',
      CanonicalBookingStateV3.cancelled => 'CANCELLED',
      CanonicalBookingStateV3.disputed => 'DISPUTED',
      CanonicalBookingStateV3.serviceNotStarted => 'SERVICE_NOT_STARTED',
      CanonicalBookingStateV3.noShow => 'NO_SHOW',
    };
  }

  String attemptStateValue(CanonicalPaymentAttemptState state) {
    return switch (state) {
      CanonicalPaymentAttemptState.notStarted => 'NOT_STARTED',
      CanonicalPaymentAttemptState.orderCreating => 'ORDER_CREATING',
      CanonicalPaymentAttemptState.orderCreated => 'ORDER_CREATED',
      CanonicalPaymentAttemptState.checkoutOpened => 'CHECKOUT_OPENED',
      CanonicalPaymentAttemptState.captureReported => 'CAPTURE_REPORTED',
      CanonicalPaymentAttemptState.confirming => 'CONFIRMING',
      CanonicalPaymentAttemptState.confirmed => 'CONFIRMED',
      CanonicalPaymentAttemptState.capturedRequiresReconciliation =>
        'CAPTURED_REQUIRES_RECONCILIATION',
      CanonicalPaymentAttemptState.failed => 'FAILED',
      CanonicalPaymentAttemptState.expired => 'EXPIRED',
      CanonicalPaymentAttemptState.refundRequired => 'REFUND_REQUIRED',
      CanonicalPaymentAttemptState.refundPending => 'REFUND_PENDING',
      CanonicalPaymentAttemptState.refunded => 'REFUNDED',
      CanonicalPaymentAttemptState.unknown => 'UNKNOWN',
    };
  }

  Map<String, dynamic> buildCanonicalSlotFixture() {
    final requestedAt = fixtureRequestedAtUtc();
    final timerStartsAt = requestedAt.add(const Duration(minutes: 30));
    final acceptDeadlineAt = requestedAt.add(
      const Duration(hours: 1, minutes: 30),
    );
    final slotStart = fixtureSlotStartUtc();
    final slotEnd = fixtureSlotEndUtc();
    final dateKey =
        '${slotStart.year.toString().padLeft(4, '0')}-'
        '${slotStart.month.toString().padLeft(2, '0')}-'
        '${slotStart.day.toString().padLeft(2, '0')}';

    return <String, dynamic>{
      'schemaVersion': canonicalBookingSchemaVersion,
      'bookingModelVersion': canonicalBookingModelVersion,
      'documentFormat': canonicalBookingDocumentFormat,
      'bookingType': 'SLOT',
      'state': 'REQUESTED',
      'participants': {
        'parent': {
          'parentId': 'parent-1',
          'displayFirstName': 'Nisha',
          'lastInitial': 'G',
          'photoUrl': '',
          'completedBookingCount': 4,
          'rating': 4.8,
        },
        'provider': {
          'providerId': 'provider-1',
          'displayName': 'Pettxo Care',
          'username': 'pettxocare',
          'photoUrl': '',
          'completedBookingCount': 22,
          'rating': 4.9,
        },
      },
      'service': {
        'serviceId': 'service-1',
        'providerId': 'provider-1',
        'serviceTitle': 'Dog Walking',
        'animalType': 'Dog',
        'category': 'Walking',
        'bookingType': 'SLOT',
        'timezone': 'Asia/Kolkata',
        'serviceUnitPricePaise': 25000,
        'durationMinutes': 60,
        'selectedSlotCount': 1,
        'totalDurationMinutes': 60,
        'capacitySnapshot': 1,
        'serviceLocationType': 'provider_location',
        'currency': 'INR',
        'snapshotVersion': 1,
      },
      'schedule': {
        'bookingType': 'SLOT',
        'slots': [
          {
            'slotId': 'slot-1',
            'dateKey': dateKey,
            'startAt': slotStart,
            'endAt': slotEnd,
            'durationMinutes': 60,
            'unitPricePaise': 25000,
            'serviceId': 'service-1',
            'providerId': 'provider-1',
            'timezone': 'Asia/Kolkata',
          },
        ],
        'slotCount': 1,
        'scheduledStartAt': slotStart,
        'scheduledEndAt': slotEnd,
        'totalDurationMinutes': 60,
        'timezone': 'Asia/Kolkata',
        'serviceAnchorAt': slotStart,
      },
      'lifecycle': {
        'requestedAt': requestedAt,
        'timerStartsAt': timerStartsAt,
        'wasQueuedOutsideWorkingHours': false,
        'notifiedAt': requestedAt.add(const Duration(minutes: 1)),
        'acceptDeadlineAt': acceptDeadlineAt,
        'viewedByProviderAt': null,
        'respondedAt': null,
        'providerResponseType': null,
        'responseSeconds': null,
        'payDeadlineAt': null,
        'paymentStartedAt': null,
        'paidAt': null,
        'paymentSeconds': null,
        'otpGeneratedAt': null,
        'otpEnteredAt': null,
        'serviceEndedAt': null,
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
        'serviceSubtotalPaise': 25000,
        'couponDiscountPaise': 0,
        'customerPaidPaise': 25000,
        'platformCommissionRateBasisPoints': 1500,
        'platformCommissionPaise': 3750,
        'providerPayoutPaise': 20000,
        'pettxoCouponFundingPaise': 0,
        'gatewayFeeSunkPaise': 0,
        'providerFaultCostPaise': 0,
        'refundAmountPaise': 0,
        'pettxoNetBeforeGatewayPaise': 5000,
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
        'source': 'fixture',
      },
      'parentId': 'parent-1',
      'providerId': 'provider-1',
      'serviceId': 'service-1',
      'stateQueryValue': 'REQUESTED',
      'bookingTypeQueryValue': 'SLOT',
      'serviceAnchorAt': slotStart,
      'scheduledStartAt': slotStart,
      'checkInDateTime': null,
      'acceptDeadlineAt': acceptDeadlineAt,
      'payDeadlineAt': null,
      'completedAt': null,
      'customerId': 'parent-1',
      'serviceOwnerId': 'provider-1',
      'createdAt': requestedAt,
      'updatedAt': requestedAt,
    };
  }

  CanonicalBookingDocumentV3 buildCanonicalBooking({
    required CanonicalBookingStateV3 state,
    String paymentAttemptId = '',
    DateTime? payDeadlineAtOverride,
    DateTime? scheduledStartAtOverride,
    DateTime? scheduledEndAtOverride,
    DateTime? paidAtOverride,
    DateTime? otpEnteredAtOverride,
    bool reviewSubmitted = false,
    String parentDisplayFirstName = 'Nisha',
    String parentLastInitial = 'G',
  }) {
    final map = buildCanonicalSlotFixture();
    final requestedAt = fixtureRequestedAtUtc();
    final payDeadlineAt = payDeadlineAtOverride ?? fixturePayDeadlineUtc();
    final slotStart = scheduledStartAtOverride ?? fixtureSlotStartUtc();
    final slotEnd = scheduledEndAtOverride ?? fixtureSlotEndUtc();
    final rawState = canonicalStateValue(state);
    map['state'] = rawState;
    map['stateQueryValue'] = rawState;
    (((map['participants'] as Map<String, dynamic>)['parent'])
            as Map<String, dynamic>)['displayFirstName'] =
        parentDisplayFirstName;
    (((map['participants'] as Map<String, dynamic>)['parent'])
            as Map<String, dynamic>)['lastInitial'] =
        parentLastInitial;
    map['serviceAnchorAt'] = slotStart;
    map['scheduledStartAt'] = slotStart;
    final slot =
        ((map['schedule'] as Map<String, dynamic>)['slots'] as List).first
            as Map<String, dynamic>;
    slot['startAt'] = slotStart;
    slot['endAt'] = slotEnd;
    slot['dateKey'] =
        '${slotStart.year.toString().padLeft(4, '0')}-'
        '${slotStart.month.toString().padLeft(2, '0')}-'
        '${slotStart.day.toString().padLeft(2, '0')}';
    (map['schedule'] as Map<String, dynamic>)['scheduledStartAt'] = slotStart;
    (map['schedule'] as Map<String, dynamic>)['scheduledEndAt'] = slotEnd;
    (map['schedule'] as Map<String, dynamic>)['serviceAnchorAt'] = slotStart;
    (map['lifecycle'] as Map<String, dynamic>)['respondedAt'] =
        state == CanonicalBookingStateV3.requested ? null : requestedAt;
    (map['lifecycle'] as Map<String, dynamic>)['providerResponseType'] =
        state == CanonicalBookingStateV3.acceptedAwaitingPayment
        ? 'accept'
        : null;
    (map['lifecycle'] as Map<String, dynamic>)['payDeadlineAt'] =
        state == CanonicalBookingStateV3.acceptedAwaitingPayment ||
            state == CanonicalBookingStateV3.paymentExpired
        ? payDeadlineAt
        : null;
    (map['lifecycle'] as Map<String, dynamic>)['paidAt'] =
        state == CanonicalBookingStateV3.confirmed
        ? (paidAtOverride ?? requestedAt.add(const Duration(hours: 2)))
        : null;
    (map['lifecycle'] as Map<String, dynamic>)['otpEnteredAt'] =
        otpEnteredAtOverride;
    (map['payment'] as Map<String, dynamic>)['status'] =
        state == CanonicalBookingStateV3.confirmed
        ? 'confirmed'
        : paymentAttemptId.isEmpty
        ? 'not_started'
        : 'order_created';
    (map['payment'] as Map<String, dynamic>)['razorpayOrderId'] =
        paymentAttemptId.isEmpty ? '' : 'order_1';
    (map['payment'] as Map<String, dynamic>)['paymentAttemptId'] =
        paymentAttemptId;
    (map['payment'] as Map<String, dynamic>)['orderCreatedAt'] =
        paymentAttemptId.isEmpty ? null : requestedAt;
    if (reviewSubmitted) {
      map['reviewStatus'] = 'submitted';
      map['reviewId'] = 'booking-1';
      map['review'] = {
        'status': 'submitted',
        'reviewId': 'booking-1',
        'submittedAt': requestedAt.add(const Duration(days: 3)),
      };
    }
    map['payDeadlineAt'] =
        state == CanonicalBookingStateV3.acceptedAwaitingPayment ||
            state == CanonicalBookingStateV3.paymentExpired
        ? payDeadlineAt
        : null;

    final result = parseCanonicalBookingDocumentV3(map);
    expect(result.isValid, isTrue);
    return result.booking!;
  }

  CanonicalPaymentAttemptReadModel buildAttempt(
    CanonicalPaymentAttemptState state,
  ) {
    return CanonicalPaymentAttemptReadModel.fromMap({
      'bookingId': 'booking-1',
      'paymentAttemptId': 'attempt-1',
      'state': attemptStateValue(state),
      'amountPaise': 25000,
      'currency': 'INR',
      'razorpayOrderId': 'order-1',
      'razorpayPaymentId': '',
      'failureCode': '',
      'failureMessage': '',
      'retryCount': 0,
      'orderExpiresAt': fixturePayDeadlineUtc(),
      'orderCreatedAt': fixtureRequestedAtUtc().add(
        const Duration(hours: 1, minutes: 30),
      ),
      'checkoutOpenedAt': null,
      'captureReportedAt': null,
      'confirmedAt': null,
      'failedAt': null,
      'refundRequiredAt': null,
      'refundedAt': null,
      'lastReconciledAt': null,
      'pricingSnapshot': {
        'serviceSubtotalPaise': 25000,
        'couponDiscountPaise': 0,
        'financials': {'providerPayoutPaise': 20000, 'currency': 'INR'},
      },
    });
  }

  CanonicalBookingReadModel buildCanonicalReadModel({
    CanonicalBookingStateV3 state = CanonicalBookingStateV3.requested,
    String paymentAttemptId = '',
    DateTime? payDeadlineAtOverride,
    DateTime? scheduledStartAtOverride,
    DateTime? scheduledEndAtOverride,
    DateTime? paidAtOverride,
    DateTime? otpEnteredAtOverride,
    String parentDisplayFirstName = 'Nisha',
    String parentLastInitial = 'G',
  }) {
    return CanonicalBookingReadModel(
      documentId: 'booking-1',
      booking: buildCanonicalBooking(
        state: state,
        paymentAttemptId: paymentAttemptId,
        payDeadlineAtOverride: payDeadlineAtOverride,
        scheduledStartAtOverride: scheduledStartAtOverride,
        scheduledEndAtOverride: scheduledEndAtOverride,
        paidAtOverride: paidAtOverride,
        otpEnteredAtOverride: otpEnteredAtOverride,
        parentDisplayFirstName: parentDisplayFirstName,
        parentLastInitial: parentLastInitial,
      ),
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required RecordingBookingOpener opener,
    required BookingStreamBuilder bookingStreamBuilder,
    ProviderRequestStreamBuilder? providerRequestStreamBuilder,
    String currentUserIdOverride = 'parent-1',
    double textScaleFactor = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScaleFactor)),
          child: BookingsScreen(
            currentUserIdOverride: currentUserIdOverride,
            bookingStreamBuilder: bookingStreamBuilder,
            providerRequestStreamBuilder: providerRequestStreamBuilder,
            bookingRequestOpener: opener.call,
            useLiveIdentity: false,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder canonicalBookingCard(String bookingId) {
    return find.byKey(ValueKey('canonical-booking-card-$bookingId'));
  }

  testWidgets(
    'provider subtabs keep Requests label and badge visible on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final opener = RecordingBookingOpener(
        latestBookings: {
          'booking-1': buildCanonicalReadModel(
            state: CanonicalBookingStateV3.pendingProvider,
          ),
        },
      );
      final canonical = buildCanonicalBooking(
        state: CanonicalBookingStateV3.pendingProvider,
      );

      await pumpScreen(
        tester,
        opener: opener,
        currentUserIdOverride: 'provider-1',
        textScaleFactor: 1.3,
        bookingStreamBuilder: (userId, contextMode) => Stream.value(const []),
        providerRequestStreamBuilder: (_) => Stream.value([
          CanonicalProviderBookingRequestView.fromBooking(
            'booking-1',
            canonical,
          ),
        ]),
      );

      await tester.tap(find.text('I Provide'));
      await tester.pumpAndSettle();

      expect(find.text('Requests'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('Past'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Confirmed'));
      await tester.pumpAndSettle();
      expect(find.text('Dog Walking'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();
      expect(find.text('Dog Walking'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'customer requested booking card opens canonical request status',
    (tester) async {
      final opener = RecordingBookingOpener(
        latestBookings: {'booking-1': buildCanonicalReadModel()},
      );

      await pumpScreen(
        tester,
        opener: opener,
        bookingStreamBuilder: (userId, contextMode) =>
            Stream.value([buildCanonicalReadModel()]),
      );

      await tester.tap(canonicalBookingCard('booking-1'));
      await tester.pump();

      expect(opener.lastRequest?.bookingId, 'booking-1');
      expect(
        opener.lastPlan?.target,
        BookingNavigationTarget.canonicalRequestStatus,
      );
    },
  );

  testWidgets(
    'customer pending-provider booking card opens canonical request status',
    (tester) async {
      final opener = RecordingBookingOpener(
        latestBookings: {
          'booking-1': buildCanonicalReadModel(
            state: CanonicalBookingStateV3.pendingProvider,
          ),
        },
      );

      await pumpScreen(
        tester,
        opener: opener,
        bookingStreamBuilder: (userId, contextMode) => Stream.value([
          buildCanonicalReadModel(
            state: CanonicalBookingStateV3.pendingProvider,
          ),
        ]),
      );

      await tester.tap(canonicalBookingCard('booking-1'));
      await tester.pump();

      expect(
        opener.lastPlan?.target,
        BookingNavigationTarget.canonicalRequestStatus,
      );
    },
  );

  testWidgets(
    'customer payment-processing booking tap resolves to canonical payment',
    (tester) async {
      final opener = RecordingBookingOpener(
        latestBookings: {
          'booking-1': buildCanonicalReadModel(
            state: CanonicalBookingStateV3.acceptedAwaitingPayment,
            paymentAttemptId: 'attempt-1',
          ),
        },
        paymentAttempts: {
          'booking-1:attempt-1': buildAttempt(
            CanonicalPaymentAttemptState.captureReported,
          ),
        },
      );

      await pumpScreen(
        tester,
        opener: opener,
        bookingStreamBuilder: (userId, contextMode) => Stream.value([
          buildCanonicalReadModel(
            state: CanonicalBookingStateV3.acceptedAwaitingPayment,
            paymentAttemptId: 'attempt-1',
          ),
        ]),
      );

      await tester.tap(canonicalBookingCard('booking-1'));
      await tester.pump();

      expect(opener.lastPlan?.target, BookingNavigationTarget.canonicalPayment);
    },
  );

  testWidgets(
    'customer accepted-awaiting-payment tap resolves to canonical payment',
    (tester) async {
      final opener = RecordingBookingOpener(
        latestBookings: {
          'booking-1': buildCanonicalReadModel(
            state: CanonicalBookingStateV3.acceptedAwaitingPayment,
            paymentAttemptId: 'attempt-1',
          ),
        },
        paymentAttempts: {
          'booking-1:attempt-1': buildAttempt(
            CanonicalPaymentAttemptState.orderCreated,
          ),
        },
      );

      await pumpScreen(
        tester,
        opener: opener,
        bookingStreamBuilder: (userId, contextMode) => Stream.value([
          buildCanonicalReadModel(
            state: CanonicalBookingStateV3.acceptedAwaitingPayment,
            paymentAttemptId: 'attempt-1',
          ),
        ]),
      );

      expect(find.text('Time remaining'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is GradientButton && widget.label == 'Pay now',
        ),
        findsOneWidget,
      );

      await tester.tap(canonicalBookingCard('booking-1'));
      await tester.pump();

      expect(opener.lastPlan?.target, BookingNavigationTarget.canonicalPayment);
    },
  );

  testWidgets(
    'customer expired payment card moves to Past and hides payment actions',
    (tester) async {
      final expiredDeadline = DateTime.now().toUtc().subtract(
        const Duration(minutes: 5),
      );
      final expiredAwaitingPayment = buildCanonicalReadModel(
        state: CanonicalBookingStateV3.acceptedAwaitingPayment,
        payDeadlineAtOverride: expiredDeadline,
      );
      final opener = RecordingBookingOpener(
        latestBookings: {'booking-1': expiredAwaitingPayment},
      );

      await pumpScreen(
        tester,
        opener: opener,
        bookingStreamBuilder: (userId, contextMode) =>
            Stream.value([expiredAwaitingPayment]),
      );

      expect(canonicalBookingCard('booking-1'), findsNothing);
      expect(find.text('Awaiting payment'), findsNothing);
      expect(find.text('Time remaining'), findsNothing);

      await tester.tap(find.text('Past'));
      await tester.pumpAndSettle();

      expect(find.text('Dog Walking'), findsOneWidget);
      expect(find.text('Expired'), findsOneWidget);
      expect(find.text('Time remaining'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is GradientButton && widget.label == 'Pay now',
        ),
        findsNothing,
      );
    },
  );

  testWidgets('customer refunded tap stays on terminal booking details', (
    tester,
  ) async {
    final opener = RecordingBookingOpener(
      latestBookings: {
        'booking-1': buildCanonicalReadModel(
          state: CanonicalBookingStateV3.cancelled,
          paymentAttemptId: 'attempt-1',
        ),
      },
      paymentAttempts: {
        'booking-1:attempt-1': buildAttempt(
          CanonicalPaymentAttemptState.refunded,
        ),
      },
    );

    await pumpScreen(
      tester,
      opener: opener,
      bookingStreamBuilder: (userId, contextMode) => Stream.value([
        buildCanonicalReadModel(
          state: CanonicalBookingStateV3.cancelled,
          paymentAttemptId: 'attempt-1',
        ),
      ]),
    );

    await tester.tap(find.text('Past'));
    await tester.pumpAndSettle();
    await tester.tap(canonicalBookingCard('booking-1'));
    await tester.pump();

    expect(
      opener.lastPlan?.target,
      BookingNavigationTarget.canonicalRequestStatus,
    );
  });

  testWidgets('customer confirmed tap uses latest repository result', (
    tester,
  ) async {
    final opener = RecordingBookingOpener(
      latestBookings: {
        'booking-1': buildCanonicalReadModel(
          state: CanonicalBookingStateV3.confirmed,
        ),
      },
    );

    await pumpScreen(
      tester,
      opener: opener,
      bookingStreamBuilder: (userId, contextMode) => Stream.value([
        buildCanonicalReadModel(state: CanonicalBookingStateV3.confirmed),
      ]),
    );

    expect(
      find.text(
        'Payment confirmed. Tap to view booking details and service OTP.',
      ),
      findsOneWidget,
    );

    await tester.tap(canonicalBookingCard('booking-1'));
    await tester.pump();

    expect(
      opener.lastPlan?.target,
      BookingNavigationTarget.canonicalBookingDetail,
    );
  });

  testWidgets(
    'overdue confirmed booking without OTP moves to customer Past as No show and stays tappable',
    (tester) async {
      final now = DateTime.now().toUtc();
      final scheduledStartAt = now.subtract(const Duration(days: 2, hours: 2));
      final scheduledEndAt = scheduledStartAt.add(const Duration(hours: 1));
      final overdueConfirmed = buildCanonicalReadModel(
        state: CanonicalBookingStateV3.confirmed,
        scheduledStartAtOverride: scheduledStartAt,
        scheduledEndAtOverride: scheduledEndAt,
        paidAtOverride: scheduledStartAt.subtract(const Duration(hours: 2)),
      );
      final opener = RecordingBookingOpener(
        latestBookings: {'booking-1': overdueConfirmed},
      );

      await pumpScreen(
        tester,
        opener: opener,
        bookingStreamBuilder: (_, contextMode) => Stream.value(
          contextMode == BookingContextMode.receiving
              ? [overdueConfirmed]
              : const [],
        ),
      );

      expect(find.text('Dog Walking'), findsNothing);

      await tester.tap(find.text('Past'));
      await tester.pumpAndSettle();

      expect(find.text('Dog Walking'), findsOneWidget);
      expect(find.text('No show'), findsOneWidget);

      await tester.tap(canonicalBookingCard('booking-1'));
      await tester.pump();

      expect(
        opener.lastPlan?.target,
        BookingNavigationTarget.canonicalBookingDetail,
      );
    },
  );

  testWidgets(
    'customer completed pending review booking appears in Past immediately',
    (tester) async {
      final completedBooking = buildCanonicalReadModel(
        state: CanonicalBookingStateV3.completedPendingReview,
      );
      final opener = RecordingBookingOpener(
        latestBookings: {'booking-1': completedBooking},
      );

      await pumpScreen(
        tester,
        opener: opener,
        bookingStreamBuilder: (userId, contextMode) =>
            Stream.value([completedBooking]),
      );

      expect(find.text('Dog Walking'), findsNothing);

      await tester.tap(find.text('Past'));
      await tester.pumpAndSettle();

      expect(find.text('Dog Walking'), findsOneWidget);
      expect(find.text('Review pending'), findsOneWidget);
    },
  );

  testWidgets('customer reviewed completed booking shows Reviewed in Past', (
    tester,
  ) async {
    final completedBooking = CanonicalBookingReadModel(
      documentId: 'booking-1',
      booking: buildCanonicalBooking(
        state: CanonicalBookingStateV3.completedPendingReview,
        reviewSubmitted: true,
      ),
    );
    final opener = RecordingBookingOpener(
      latestBookings: {'booking-1': completedBooking},
    );

    await pumpScreen(
      tester,
      opener: opener,
      bookingStreamBuilder: (userId, contextMode) =>
          Stream.value([completedBooking]),
    );

    await tester.tap(find.text('Past'));
    await tester.pumpAndSettle();

    expect(find.text('Dog Walking'), findsOneWidget);
    expect(find.text('Reviewed'), findsOneWidget);
    expect(
      find.text('Service completed. Your review has been submitted.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'customer refund-required tap stays on terminal booking details',
    (tester) async {
      final opener = RecordingBookingOpener(
        latestBookings: {
          'booking-1': buildCanonicalReadModel(
            state: CanonicalBookingStateV3.cancelled,
            paymentAttemptId: 'attempt-1',
          ),
        },
        paymentAttempts: {
          'booking-1:attempt-1': buildAttempt(
            CanonicalPaymentAttemptState.refundRequired,
          ),
        },
      );

      await pumpScreen(
        tester,
        opener: opener,
        bookingStreamBuilder: (userId, contextMode) => Stream.value([
          buildCanonicalReadModel(
            state: CanonicalBookingStateV3.cancelled,
            paymentAttemptId: 'attempt-1',
          ),
        ]),
      );

      await tester.tap(find.text('Past'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dog Walking').first);
      await tester.pump();

      expect(
        opener.lastPlan?.target,
        BookingNavigationTarget.canonicalRequestStatus,
      );
      expect(
        opener.lastPlan?.target ==
            BookingNavigationTarget.canonicalBookingDetail,
        isFalse,
      );
    },
  );

  for (final state in <CanonicalBookingStateV3>[
    CanonicalBookingStateV3.declined,
    CanonicalBookingStateV3.expired,
    CanonicalBookingStateV3.paymentExpired,
    CanonicalBookingStateV3.cancelledByParent,
  ]) {
    testWidgets(
      'customer terminal $state booking appears in Past and stays tappable',
      (tester) async {
        final opener = RecordingBookingOpener(
          latestBookings: {'booking-1': buildCanonicalReadModel(state: state)},
        );

        await pumpScreen(
          tester,
          opener: opener,
          bookingStreamBuilder: (userId, contextMode) =>
              Stream.value([buildCanonicalReadModel(state: state)]),
        );

        expect(find.text('Dog Walking'), findsNothing);

        await tester.tap(find.text('Past'));
        await tester.pumpAndSettle();

        expect(find.text('Dog Walking'), findsOneWidget);

        await tester.tap(canonicalBookingCard('booking-1'));
        await tester.pump();

        expect(
          opener.lastPlan?.target,
          BookingNavigationTarget.canonicalRequestStatus,
        );
      },
    );
  }

  testWidgets('provider request card opens provider request detail', (
    tester,
  ) async {
    final opener = RecordingBookingOpener(
      latestBookings: {
        'booking-1': buildCanonicalReadModel(
          state: CanonicalBookingStateV3.pendingProvider,
        ),
      },
    );
    final canonical = buildCanonicalBooking(
      state: CanonicalBookingStateV3.pendingProvider,
    );

    await pumpScreen(
      tester,
      opener: opener,
      currentUserIdOverride: 'provider-1',
      bookingStreamBuilder: (userId, contextMode) => Stream.value(const []),
      providerRequestStreamBuilder: (userId) => Stream.value([
        CanonicalProviderBookingRequestView.fromBooking('booking-1', canonical),
      ]),
    );

    await tester.tap(find.text('I Provide'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dog Walking').first);
    await tester.pumpAndSettle();

    expect(
      opener.lastRequest?.fallbackContextMode,
      BookingContextMode.delivering,
    );
    expect(
      opener.lastPlan?.target,
      BookingNavigationTarget.canonicalProviderRequestDetail,
    );
  });

  testWidgets(
    'provider confirmed booking tap opens canonical confirmed detail',
    (tester) async {
      final opener = RecordingBookingOpener(
        latestBookings: {
          'booking-1': buildCanonicalReadModel(
            state: CanonicalBookingStateV3.confirmed,
          ),
        },
      );

      await pumpScreen(
        tester,
        opener: opener,
        currentUserIdOverride: 'provider-1',
        bookingStreamBuilder: (_, contextMode) => Stream.value(
          contextMode == BookingContextMode.delivering
              ? [
                  buildCanonicalReadModel(
                    state: CanonicalBookingStateV3.confirmed,
                  ),
                ]
              : const [],
        ),
        providerRequestStreamBuilder: (_) => Stream.value(const []),
      );

      await tester.tap(find.text('I Provide'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmed'));
      await tester.pumpAndSettle();
      await tester.tap(canonicalBookingCard('booking-1'));
      await tester.pumpAndSettle();

      expect(
        opener.lastPlan?.target,
        BookingNavigationTarget.canonicalBookingDetail,
      );
    },
  );

  testWidgets(
    'overdue confirmed booking without OTP moves to provider Past as No show',
    (tester) async {
      final now = DateTime.now().toUtc();
      final scheduledStartAt = now.subtract(const Duration(days: 2, hours: 2));
      final scheduledEndAt = scheduledStartAt.add(const Duration(hours: 1));
      final overdueConfirmed = buildCanonicalReadModel(
        state: CanonicalBookingStateV3.confirmed,
        scheduledStartAtOverride: scheduledStartAt,
        scheduledEndAtOverride: scheduledEndAt,
        paidAtOverride: scheduledStartAt.subtract(const Duration(hours: 2)),
      );

      await pumpScreen(
        tester,
        opener: RecordingBookingOpener(
          latestBookings: {'booking-1': overdueConfirmed},
        ),
        currentUserIdOverride: 'provider-1',
        bookingStreamBuilder: (_, contextMode) => Stream.value(
          contextMode == BookingContextMode.delivering
              ? [overdueConfirmed]
              : const [],
        ),
        providerRequestStreamBuilder: (_) => const Stream.empty(),
      );

      await tester.tap(find.text('I Provide'));
      await tester.pumpAndSettle();

      expect(find.text('Dog Walking'), findsNothing);

      await tester.tap(find.text('Past'));
      await tester.pumpAndSettle();

      expect(find.text('Dog Walking'), findsOneWidget);
      expect(find.text('No show'), findsOneWidget);
    },
  );

  testWidgets(
    'customer confirmed booking tap still opens detail when payment attempt lookup would fail',
    (tester) async {
      final opener = RecordingBookingOpener(
        latestBookings: {
          'booking-1': buildCanonicalReadModel(
            state: CanonicalBookingStateV3.confirmed,
            paymentAttemptId: 'attempt-1',
          ),
        },
        paymentAttemptLoaderOverride:
            ({
              required String bookingId,
              required String paymentAttemptId,
            }) async {
              throw StateError('payment attempt lookup should be skipped');
            },
      );

      await pumpScreen(
        tester,
        opener: opener,
        bookingStreamBuilder: (userId, contextMode) => Stream.value([
          buildCanonicalReadModel(
            state: CanonicalBookingStateV3.confirmed,
            paymentAttemptId: 'attempt-1',
          ),
        ]),
      );

      await tester.tap(canonicalBookingCard('booking-1'));
      await tester.pump();

      expect(opener.lastRequest?.bookingId, 'booking-1');
      expect(
        opener.lastPlan?.target,
        BookingNavigationTarget.canonicalBookingDetail,
      );
      expect(opener.lastError, isNull);
    },
  );

  testWidgets(
    'provider confirmed booking tap still opens detail when payment attempt lookup would fail',
    (tester) async {
      final opener = RecordingBookingOpener(
        latestBookings: {
          'booking-1': buildCanonicalReadModel(
            state: CanonicalBookingStateV3.confirmed,
            paymentAttemptId: 'attempt-1',
          ),
        },
        paymentAttemptLoaderOverride:
            ({
              required String bookingId,
              required String paymentAttemptId,
            }) async {
              throw StateError('payment attempt lookup should be skipped');
            },
      );

      await pumpScreen(
        tester,
        opener: opener,
        currentUserIdOverride: 'provider-1',
        bookingStreamBuilder: (_, contextMode) => Stream.value(
          contextMode == BookingContextMode.delivering
              ? [
                  buildCanonicalReadModel(
                    state: CanonicalBookingStateV3.confirmed,
                    paymentAttemptId: 'attempt-1',
                  ),
                ]
              : const [],
        ),
        providerRequestStreamBuilder: (_) => Stream.value(const []),
      );

      await tester.tap(find.text('I Provide'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmed'));
      await tester.pumpAndSettle();
      await tester.tap(canonicalBookingCard('booking-1'));
      await tester.pump();

      expect(opener.lastRequest?.bookingId, 'booking-1');
      expect(
        opener.lastPlan?.target,
        BookingNavigationTarget.canonicalBookingDetail,
      );
      expect(opener.lastError, isNull);
    },
  );

  testWidgets(
    'provider accepted-awaiting-payment booking stays out of Confirmed tab',
    (tester) async {
      final acceptedAwaitingPayment = buildCanonicalReadModel(
        state: CanonicalBookingStateV3.acceptedAwaitingPayment,
        paymentAttemptId: 'attempt-1',
      );

      await pumpScreen(
        tester,
        opener: RecordingBookingOpener(
          latestBookings: {'booking-1': acceptedAwaitingPayment},
        ),
        currentUserIdOverride: 'provider-1',
        bookingStreamBuilder: (_, contextMode) => Stream.value(
          contextMode == BookingContextMode.delivering
              ? [acceptedAwaitingPayment]
              : const [],
        ),
        providerRequestStreamBuilder: (_) => Stream.value([
          CanonicalProviderBookingRequestView.fromBooking(
            'booking-1',
            acceptedAwaitingPayment.booking,
          ),
        ]),
      );

      await tester.tap(find.text('I Provide'));
      await tester.pumpAndSettle();

      expect(find.text('Dog Walking'), findsOneWidget);

      await tester.tap(find.text('Confirmed'));
      await tester.pumpAndSettle();

      expect(canonicalBookingCard('booking-1'), findsNothing);
      expect(find.text('Dog Walking'), findsNothing);
    },
  );

  testWidgets(
    'provider accepted-awaiting-payment booking stays in Requests while deadline is active',
    (tester) async {
      final acceptedAwaitingPayment = buildCanonicalReadModel(
        state: CanonicalBookingStateV3.acceptedAwaitingPayment,
        paymentAttemptId: 'attempt-1',
        payDeadlineAtOverride: DateTime.now().toUtc().add(
          const Duration(minutes: 30),
        ),
      );

      await pumpScreen(
        tester,
        opener: RecordingBookingOpener(
          latestBookings: {'booking-1': acceptedAwaitingPayment},
        ),
        currentUserIdOverride: 'provider-1',
        bookingStreamBuilder: (_, contextMode) => Stream.value(
          contextMode == BookingContextMode.delivering
              ? [acceptedAwaitingPayment]
              : const [],
        ),
        providerRequestStreamBuilder: (_) => Stream.value([
          CanonicalProviderBookingRequestView.fromBooking(
            'booking-1',
            acceptedAwaitingPayment.booking,
          ),
        ]),
      );

      await tester.tap(find.text('I Provide'));
      await tester.pumpAndSettle();

      expect(find.text('Dog Walking'), findsOneWidget);
      expect(find.text('Time remaining'), findsOneWidget);
      expect(find.text('Expired'), findsNothing);
    },
  );

  testWidgets(
    'provider accepted-awaiting-payment list card hides legacy customer identity',
    (tester) async {
      final acceptedAwaitingPayment = buildCanonicalReadModel(
        state: CanonicalBookingStateV3.acceptedAwaitingPayment,
        paymentAttemptId: 'attempt-1',
        payDeadlineAtOverride: DateTime.now().toUtc().add(
          const Duration(minutes: 30),
        ),
        parentDisplayFirstName: 'Anita',
        parentLastInitial: 'G',
      );

      await pumpScreen(
        tester,
        opener: RecordingBookingOpener(
          latestBookings: {'booking-1': acceptedAwaitingPayment},
        ),
        currentUserIdOverride: 'provider-1',
        bookingStreamBuilder: (_, contextMode) => Stream.value(
          contextMode == BookingContextMode.delivering
              ? [acceptedAwaitingPayment]
              : const [],
        ),
        providerRequestStreamBuilder: (_) => Stream.value([
          CanonicalProviderBookingRequestView.fromBooking(
            'booking-1',
            acceptedAwaitingPayment.booking,
          ),
        ]),
      );

      await tester.tap(find.text('I Provide'));
      await tester.pumpAndSettle();

      expect(find.text('Anita G'), findsNothing);
      expect(find.textContaining('Customer ·'), findsWidgets);
    },
  );

  testWidgets('provider expired unpaid booking moves from Requests to Past', (
    tester,
  ) async {
    final expiredAwaitingPayment = buildCanonicalReadModel(
      state: CanonicalBookingStateV3.acceptedAwaitingPayment,
      paymentAttemptId: 'attempt-1',
      payDeadlineAtOverride: DateTime.now().toUtc().subtract(
        const Duration(minutes: 5),
      ),
    );

    await pumpScreen(
      tester,
      opener: RecordingBookingOpener(
        latestBookings: {'booking-1': expiredAwaitingPayment},
      ),
      currentUserIdOverride: 'provider-1',
      bookingStreamBuilder: (_, contextMode) => Stream.value(
        contextMode == BookingContextMode.delivering
            ? [expiredAwaitingPayment]
            : const [],
      ),
      providerRequestStreamBuilder: (_) => Stream.value([
        CanonicalProviderBookingRequestView.fromBooking(
          'booking-1',
          expiredAwaitingPayment.booking,
        ),
      ]),
    );

    await tester.tap(find.text('I Provide'));
    await tester.pumpAndSettle();

    expect(find.text('Dog Walking'), findsNothing);
    expect(find.text('Time remaining'), findsNothing);

    await tester.tap(find.text('Past'));
    await tester.pumpAndSettle();

    expect(find.text('Dog Walking'), findsOneWidget);
    expect(find.text('Expired'), findsOneWidget);
    expect(find.text('Time remaining'), findsNothing);
  });

  testWidgets(
    'provider completed pending review booking appears in Past immediately',
    (tester) async {
      final completedBooking = buildCanonicalReadModel(
        state: CanonicalBookingStateV3.completedPendingReview,
      );

      await pumpScreen(
        tester,
        opener: RecordingBookingOpener(
          latestBookings: {'booking-1': completedBooking},
        ),
        currentUserIdOverride: 'provider-1',
        bookingStreamBuilder: (_, contextMode) => Stream.value(
          contextMode == BookingContextMode.delivering
              ? [completedBooking]
              : const [],
        ),
        providerRequestStreamBuilder: (_) => const Stream.empty(),
      );

      await tester.tap(find.text('I Provide'));
      await tester.pumpAndSettle();

      expect(find.text('Dog Walking'), findsNothing);

      await tester.tap(find.text('Past'));
      await tester.pumpAndSettle();

      expect(find.text('Dog Walking'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Review pending'), findsNothing);
    },
  );
}

class RecordingBookingOpener {
  RecordingBookingOpener({
    required this.latestBookings,
    this.paymentAttempts = const {},
    this.paymentAttemptLoaderOverride,
  });

  final Map<String, BookingReadModel> latestBookings;
  final Map<String, CanonicalPaymentAttemptReadModel> paymentAttempts;
  final Future<CanonicalPaymentAttemptReadModel?> Function({
    required String bookingId,
    required String paymentAttemptId,
  })?
  paymentAttemptLoaderOverride;

  BookingOpenRequest? lastRequest;
  BookingNavigationPlan? lastPlan;
  Object? lastError;

  Future<void> call(BuildContext context, BookingOpenRequest request) async {
    lastRequest = request;
    final latest = latestBookings[request.bookingId];
    if (latest == null) return;
    final resolver = BookingNavigationResolver(
      paymentAttemptLoader:
          ({
            required String bookingId,
            required String paymentAttemptId,
          }) async {
            if (paymentAttemptLoaderOverride != null) {
              return paymentAttemptLoaderOverride!(
                bookingId: bookingId,
                paymentAttemptId: paymentAttemptId,
              );
            }
            return paymentAttempts['$bookingId:$paymentAttemptId'];
          },
    );
    try {
      lastPlan = await resolver.resolvePlan(
        booking: latest,
        fallbackContextMode: request.fallbackContextMode,
      );
      lastError = null;
    } catch (error) {
      lastPlan = null;
      lastError = error;
    }
  }
}
