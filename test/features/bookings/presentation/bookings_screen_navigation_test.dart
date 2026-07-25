import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    return DateTime.utc(now.year, now.month, now.day, 10);
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
  }) {
    final map = buildCanonicalSlotFixture();
    final requestedAt = fixtureRequestedAtUtc();
    final payDeadlineAt = fixturePayDeadlineUtc();
    final rawState = canonicalStateValue(state);
    map['state'] = rawState;
    map['stateQueryValue'] = rawState;
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
        ? requestedAt.add(const Duration(hours: 2))
        : null;
    (map['payment'] as Map<String, dynamic>)['status'] =
        paymentAttemptId.isEmpty ? 'not_started' : 'order_created';
    (map['payment'] as Map<String, dynamic>)['razorpayOrderId'] =
        paymentAttemptId.isEmpty ? '' : 'order_1';
    (map['payment'] as Map<String, dynamic>)['paymentAttemptId'] =
        paymentAttemptId;
    (map['payment'] as Map<String, dynamic>)['orderCreatedAt'] =
        paymentAttemptId.isEmpty ? null : requestedAt;
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
  }) {
    return CanonicalBookingReadModel(
      documentId: 'booking-1',
      booking: buildCanonicalBooking(
        state: state,
        paymentAttemptId: paymentAttemptId,
      ),
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required RecordingBookingOpener opener,
    required BookingStreamBuilder bookingStreamBuilder,
    ProviderRequestStreamBuilder? providerRequestStreamBuilder,
    String currentUserIdOverride = 'parent-1',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BookingsScreen(
          currentUserIdOverride: currentUserIdOverride,
          bookingStreamBuilder: bookingStreamBuilder,
          providerRequestStreamBuilder: providerRequestStreamBuilder,
          bookingRequestOpener: opener.call,
          useLiveIdentity: false,
        ),
      ),
    );
    await tester.pump();
  }

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

      await tester.tap(find.text('Dog Walking').first);
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

      await tester.tap(find.text('Dog Walking').first);
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
            state: CanonicalBookingStateV3.pendingProvider,
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
            state: CanonicalBookingStateV3.pendingProvider,
            paymentAttemptId: 'attempt-1',
          ),
        ]),
      );

      await tester.tap(find.text('Dog Walking').first);
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

      await tester.tap(find.text('Dog Walking').first);
      await tester.pump();

      expect(opener.lastPlan?.target, BookingNavigationTarget.canonicalPayment);
    },
  );

  testWidgets('customer refunded tap remains on canonical payment flow', (
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
    await tester.tap(find.text('Dog Walking').first);
    await tester.pump();

    expect(opener.lastPlan?.target, BookingNavigationTarget.canonicalPayment);
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

    await tester.tap(find.text('Dog Walking').first);
    await tester.pump();

    expect(
      opener.lastPlan?.target,
      BookingNavigationTarget.canonicalBookingDetail,
    );
  });

  testWidgets('customer refund-required tap never opens confirmed detail', (
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

    expect(opener.lastPlan?.target, BookingNavigationTarget.canonicalPayment);
    expect(
      opener.lastPlan?.target == BookingNavigationTarget.canonicalBookingDetail,
      isFalse,
    );
  });

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

    await tester.tap(find.text('Delivering'));
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

      await tester.tap(find.text('Delivering'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dog Walking').first);
      await tester.pumpAndSettle();

      expect(
        opener.lastPlan?.target,
        BookingNavigationTarget.canonicalBookingDetail,
      );
    },
  );
}

class RecordingBookingOpener {
  RecordingBookingOpener({
    required this.latestBookings,
    this.paymentAttempts = const {},
  });

  final Map<String, BookingReadModel> latestBookings;
  final Map<String, CanonicalPaymentAttemptReadModel> paymentAttempts;

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
