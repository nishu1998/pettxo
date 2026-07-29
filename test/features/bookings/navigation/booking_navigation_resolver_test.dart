import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/domain/models/booking_document_v3.dart';
import 'package:pettexo/features/bookings/domain/models/booking_flow_models.dart';
import 'package:pettexo/features/bookings/domain/models/booking_payment_order.dart';
import 'package:pettexo/features/bookings/domain/models/booking_read_model.dart';
import 'package:pettexo/features/bookings/domain/models/booking_v3_models.dart';
import 'package:pettexo/features/bookings/presentation/navigation/booking_navigation_resolver.dart';

void main() {
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
    final now = DateTime.now().toUtc();
    final requestedAt = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(hours: 1));
    final timerStartsAt = requestedAt.add(const Duration(minutes: 30));
    final acceptDeadlineAt = requestedAt.add(
      const Duration(hours: 1, minutes: 30),
    );
    final slotStart = requestedAt.add(const Duration(days: 1, hours: 20));
    final slotEnd = slotStart.add(const Duration(hours: 1));

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
            'dateKey': '2026-07-23',
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
  }) {
    final map = buildCanonicalSlotFixture();
    final requestedAt = map['createdAt'] as DateTime;
    final payDeadlineAt =
        payDeadlineAtOverride ??
        requestedAt.add(const Duration(hours: 2, minutes: 30));
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
    expect(
      result.isValid,
      isTrue,
      reason: 'canonical booking fixture must stay valid',
    );
    return result.booking!;
  }

  CanonicalPaymentAttemptReadModel buildAttempt(
    CanonicalPaymentAttemptState state,
  ) {
    final now = DateTime.now().toUtc();
    final orderCreatedAt = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(minutes: 5));
    final orderExpiresAt = orderCreatedAt.add(const Duration(hours: 1));
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
      'orderExpiresAt': orderExpiresAt,
      'orderCreatedAt': orderCreatedAt,
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

  BookingRecord buildCanonicalRecord({
    BookingContextMode context = BookingContextMode.receiving,
  }) {
    final booking = buildCanonicalBooking(
      state: CanonicalBookingStateV3.pendingProvider,
    );
    final counterpartyName = context == BookingContextMode.receiving
        ? booking.participants.provider.displayName
        : booking.participants.parent.displayFirstName;
    final counterpartyUsername = context == BookingContextMode.receiving
        ? booking.participants.provider.username
        : '';
    final counterpartyUserId = context == BookingContextMode.receiving
        ? booking.providerId
        : booking.parentId;
    final slotSchedule = booking.schedule as CanonicalSlotBookingScheduleV3;
    return BookingRecord(
      id: 'booking-1',
      serviceId: booking.serviceId,
      slotId: slotSchedule.slots.first.slotId,
      context: context,
      tab: context == BookingContextMode.receiving
          ? BookingTab.upcoming
          : BookingTab.requests,
      title: booking.service.serviceTitle,
      subtitle: counterpartyName,
      serviceTitle: booking.service.serviceTitle,
      animalType: booking.service.animalType,
      counterpartyName: counterpartyName,
      counterpartyUsername: counterpartyUsername,
      counterpartyPhotoUrl: '',
      counterpartyUserId: counterpartyUserId,
      meta: '1 hr',
      providerUserId: booking.providerId,
      scheduledStartAt: slotSchedule.scheduledStartAt,
      scheduledEndAt: slotSchedule.scheduledEndAt,
      pricePaise: booking.financials?.customerPaidPaise ?? 25000,
      durationMinutes: slotSchedule.totalDurationMinutes,
      statusLabel: 'Awaiting provider response',
      statusTone: BookingStatusTone.awaiting,
    );
  }

  BookingNavigationTarget customerTargetFor(
    CanonicalBookingStateV3 state, {
    CanonicalPaymentAttemptReadModel? paymentAttempt,
    String paymentAttemptId = '',
    DateTime? payDeadlineAtOverride,
  }) {
    return BookingNavigationResolver.resolveCanonicalPlan(
      booking: buildCanonicalBooking(
        state: state,
        paymentAttemptId: paymentAttemptId,
        payDeadlineAtOverride: payDeadlineAtOverride,
      ),
      contextMode: BookingContextMode.receiving,
      paymentAttempt: paymentAttempt,
    ).target;
  }

  BookingNavigationTarget providerTargetFor(CanonicalBookingStateV3 state) {
    return BookingNavigationResolver.resolveCanonicalPlan(
      booking: buildCanonicalBooking(state: state),
      contextMode: BookingContextMode.delivering,
    ).target;
  }

  group('customer canonical routing', () {
    for (final state in const <CanonicalBookingStateV3>[
      CanonicalBookingStateV3.requested,
      CanonicalBookingStateV3.pendingProvider,
      CanonicalBookingStateV3.declined,
      CanonicalBookingStateV3.expired,
      CanonicalBookingStateV3.cancelledByParent,
      CanonicalBookingStateV3.paymentExpired,
    ]) {
      test('$state opens request status', () {
        expect(
          customerTargetFor(state),
          BookingNavigationTarget.canonicalRequestStatus,
        );
      });
    }

    for (final state in const <CanonicalBookingStateV3>[
      CanonicalBookingStateV3.acceptedAwaitingPayment,
    ]) {
      test('$state opens payment', () {
        expect(
          customerTargetFor(state),
          BookingNavigationTarget.canonicalPayment,
        );
      });
    }

    for (final attemptState in const <CanonicalPaymentAttemptState>[
      CanonicalPaymentAttemptState.orderCreated,
      CanonicalPaymentAttemptState.checkoutOpened,
      CanonicalPaymentAttemptState.captureReported,
      CanonicalPaymentAttemptState.confirming,
      CanonicalPaymentAttemptState.capturedRequiresReconciliation,
      CanonicalPaymentAttemptState.failed,
      CanonicalPaymentAttemptState.refundRequired,
      CanonicalPaymentAttemptState.refundPending,
      CanonicalPaymentAttemptState.refunded,
    ]) {
      test(
        'attempt $attemptState does not bypass request-state routing before provider acceptance',
        () {
          expect(
            customerTargetFor(
              CanonicalBookingStateV3.pendingProvider,
              paymentAttemptId: 'attempt-1',
              paymentAttempt: buildAttempt(attemptState),
            ),
            BookingNavigationTarget.canonicalRequestStatus,
          );
        },
      );
    }

    test(
      'provider-cancelled-after-payment stays on terminal booking details instead of payment',
      () {
        expect(
          customerTargetFor(
            CanonicalBookingStateV3.cancelled,
            paymentAttemptId: 'attempt-1',
            paymentAttempt: buildAttempt(
              CanonicalPaymentAttemptState.refundPending,
            ),
          ),
          BookingNavigationTarget.canonicalRequestStatus,
        );
      },
    );

    test(
      'expired payment window stays on terminal booking details instead of payment',
      () {
        expect(
          customerTargetFor(
            CanonicalBookingStateV3.acceptedAwaitingPayment,
            paymentAttemptId: 'attempt-1',
            paymentAttempt: buildAttempt(
              CanonicalPaymentAttemptState.orderCreated,
            ),
            payDeadlineAtOverride: DateTime.now().toUtc().subtract(
              const Duration(minutes: 5),
            ),
          ),
          BookingNavigationTarget.canonicalRequestStatus,
        );
      },
    );

    for (final state in const <CanonicalBookingStateV3>[
      CanonicalBookingStateV3.confirmed,
      CanonicalBookingStateV3.inProgress,
      CanonicalBookingStateV3.completedPendingReview,
      CanonicalBookingStateV3.completedFinal,
      CanonicalBookingStateV3.disputed,
      CanonicalBookingStateV3.noShow,
    ]) {
      test('$state opens canonical detail', () {
        expect(
          customerTargetFor(state),
          BookingNavigationTarget.canonicalBookingDetail,
        );
      });
    }
  });

  group('provider canonical routing', () {
    for (final state in const <CanonicalBookingStateV3>[
      CanonicalBookingStateV3.requested,
      CanonicalBookingStateV3.pendingProvider,
      CanonicalBookingStateV3.acceptedAwaitingPayment,
      CanonicalBookingStateV3.declined,
      CanonicalBookingStateV3.expired,
      CanonicalBookingStateV3.cancelledByParent,
    ]) {
      test('$state opens provider request detail', () {
        expect(
          providerTargetFor(state),
          BookingNavigationTarget.canonicalProviderRequestDetail,
        );
      });
    }

    test('confirmed provider bookings open canonical detail', () {
      expect(
        providerTargetFor(CanonicalBookingStateV3.confirmed),
        BookingNavigationTarget.canonicalBookingDetail,
      );
    });
  });

  test('record-based open requests preserve the fallback context', () {
    final record = buildCanonicalRecord(context: BookingContextMode.delivering);
    final request = BookingNavigationResolver.openRequestForRecord(record);

    expect(request.bookingId, 'booking-1');
    expect(request.fallbackContextMode, BookingContextMode.delivering);
  });

  test('external open requests preserve booking id and fallback context', () {
    final request = BookingNavigationResolver.openRequestForExternalBooking(
      bookingId: 'booking-1',
      contextMode: BookingContextMode.receiving,
    );

    expect(request.bookingId, 'booking-1');
    expect(request.fallbackContextMode, BookingContextMode.receiving);
  });

  test(
    'resolvePlan fetches the latest payment attempt before routing',
    () async {
      String? loadedBookingId;
      String? loadedAttemptId;
      final resolver = BookingNavigationResolver(
        paymentAttemptLoader:
            ({
              required String bookingId,
              required String paymentAttemptId,
            }) async {
              loadedBookingId = bookingId;
              loadedAttemptId = paymentAttemptId;
              return buildAttempt(CanonicalPaymentAttemptState.confirming);
            },
      );

      final plan = await resolver.resolvePlan(
        booking: CanonicalBookingReadModel(
          documentId: 'booking-1',
          booking: buildCanonicalBooking(
            state: CanonicalBookingStateV3.pendingProvider,
            paymentAttemptId: 'attempt-1',
          ),
        ),
        fallbackContextMode: BookingContextMode.receiving,
      );

      expect(plan.target, BookingNavigationTarget.canonicalRequestStatus);
      expect(loadedBookingId, 'booking-1');
      expect(loadedAttemptId, 'attempt-1');
    },
  );

  test('customer pending-provider bookings open request status', () {
    final plan = BookingNavigationResolver.resolveCanonicalPlan(
      booking: buildCanonicalBooking(
        state: CanonicalBookingStateV3.pendingProvider,
      ),
      contextMode: BookingContextMode.receiving,
    );

    expect(plan.target, BookingNavigationTarget.canonicalRequestStatus);
  });

  test('customer accepted-awaiting-payment bookings open payment', () {
    final plan = BookingNavigationResolver.resolveCanonicalPlan(
      booking: buildCanonicalBooking(
        state: CanonicalBookingStateV3.acceptedAwaitingPayment,
      ),
      contextMode: BookingContextMode.receiving,
    );

    expect(plan.target, BookingNavigationTarget.canonicalPayment);
  });

  test('customer payment-expired bookings open request status', () {
    final plan = BookingNavigationResolver.resolveCanonicalPlan(
      booking: buildCanonicalBooking(
        state: CanonicalBookingStateV3.paymentExpired,
      ),
      contextMode: BookingContextMode.receiving,
    );

    expect(plan.target, BookingNavigationTarget.canonicalRequestStatus);
  });

  test(
    'customer accepted-awaiting-payment processing attempts keep routing to payment',
    () {
      final plan = BookingNavigationResolver.resolveCanonicalPlan(
        booking: buildCanonicalBooking(
          state: CanonicalBookingStateV3.acceptedAwaitingPayment,
          paymentAttemptId: 'attempt-1',
        ),
        contextMode: BookingContextMode.receiving,
        paymentAttempt: buildAttempt(
          CanonicalPaymentAttemptState.captureReported,
        ),
      );

      expect(plan.target, BookingNavigationTarget.canonicalPayment);
    },
  );

  test('expired attempts on customer requests route to request status', () {
    final plan = BookingNavigationResolver.resolveCanonicalPlan(
      booking: buildCanonicalBooking(
        state: CanonicalBookingStateV3.pendingProvider,
        paymentAttemptId: 'attempt-1',
      ),
      contextMode: BookingContextMode.receiving,
      paymentAttempt: buildAttempt(CanonicalPaymentAttemptState.expired),
    );

    expect(plan.target, BookingNavigationTarget.canonicalRequestStatus);
  });

  test('customer refund states stay on terminal booking details', () {
    final plan = BookingNavigationResolver.resolveCanonicalPlan(
      booking: buildCanonicalBooking(
        state: CanonicalBookingStateV3.cancelled,
        paymentAttemptId: 'attempt-1',
      ),
      contextMode: BookingContextMode.receiving,
      paymentAttempt: buildAttempt(CanonicalPaymentAttemptState.refundPending),
    );

    expect(plan.target, BookingNavigationTarget.canonicalRequestStatus);
  });

  test('customer confirmed bookings open canonical detail', () {
    final plan = BookingNavigationResolver.resolveCanonicalPlan(
      booking: buildCanonicalBooking(state: CanonicalBookingStateV3.confirmed),
      contextMode: BookingContextMode.receiving,
    );

    expect(plan.target, BookingNavigationTarget.canonicalBookingDetail);
  });

  test('provider canonical request bookings open provider detail', () {
    final plan = BookingNavigationResolver.resolveCanonicalPlan(
      booking: buildCanonicalBooking(
        state: CanonicalBookingStateV3.acceptedAwaitingPayment,
      ),
      contextMode: BookingContextMode.delivering,
      paymentAttempt: buildAttempt(CanonicalPaymentAttemptState.orderCreated),
    );

    expect(plan.target, BookingNavigationTarget.canonicalProviderRequestDetail);
  });
}
