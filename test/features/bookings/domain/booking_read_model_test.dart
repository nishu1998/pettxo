import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/domain/models/booking_document_v3.dart';
import 'package:pettexo/features/bookings/domain/models/booking_v3_models.dart';

void main() {
  Map<String, dynamic> buildCanonicalSlot({
    int schemaVersion = canonicalBookingSchemaVersion,
  }) {
    final requestedAt = DateTime.utc(2026, 7, 22, 10);
    final timerStartsAt = DateTime.utc(2026, 7, 22, 10, 30);
    final acceptDeadlineAt = DateTime.utc(2026, 7, 22, 11, 30);
    final slotStart = DateTime.utc(2026, 7, 23, 6);
    final slotEnd = DateTime.utc(2026, 7, 23, 7);
    return <String, dynamic>{
      'schemaVersion': schemaVersion,
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
      'financials': null,
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

  Map<String, dynamic> buildCanonicalRange() {
    final requestedAt = DateTime.utc(2026, 7, 22, 10);
    final checkIn = DateTime.utc(2026, 7, 25, 6);
    final checkOut = DateTime.utc(2026, 7, 27, 6);
    final paidAt = DateTime.utc(2026, 7, 22, 12, 30);
    return <String, dynamic>{
      ...buildCanonicalSlot(),
      'bookingType': 'RANGE',
      'state': 'CONFIRMED',
      'service': {
        'serviceId': 'service-1',
        'providerId': 'provider-1',
        'serviceTitle': 'Pet Boarding',
        'animalType': 'Dog',
        'category': 'Boarding',
        'bookingType': 'RANGE',
        'timezone': 'Asia/Kolkata',
        'pricePerNightPaise': 180000,
        'capacitySnapshot': 2,
        'serviceLocationType': 'provider_location',
        'currency': 'INR',
        'snapshotVersion': 1,
      },
      'schedule': {
        'bookingType': 'RANGE',
        'checkInDateTime': checkIn,
        'checkOutDateTime': checkOut,
        'nights': 2,
        'timezone': 'Asia/Kolkata',
        'minNightsSnapshot': 1,
        'maxNightsSnapshot': 14,
        'maxConcurrentPetsSnapshot': 2,
        'petQuantity': 1,
        'pricePerNightPaise': 180000,
        'serviceAnchorAt': checkIn,
      },
      'lifecycle': {
        'requestedAt': requestedAt,
        'timerStartsAt': requestedAt,
        'wasQueuedOutsideWorkingHours': false,
        'notifiedAt': requestedAt,
        'acceptDeadlineAt': requestedAt.add(const Duration(hours: 1)),
        'viewedByProviderAt': requestedAt.add(const Duration(minutes: 3)),
        'respondedAt': requestedAt.add(const Duration(minutes: 10)),
        'providerResponseType': 'accept',
        'responseSeconds': 600,
        'payDeadlineAt': requestedAt.add(const Duration(hours: 1, minutes: 10)),
        'paymentStartedAt': requestedAt.add(const Duration(minutes: 15)),
        'paidAt': paidAt,
        'paymentSeconds': 3300,
        'otpGeneratedAt': paidAt.add(const Duration(hours: 48)),
        'otpEnteredAt': null,
        'serviceEndedAt': null,
        'disputeDeadlineAt': null,
        'completedAt': null,
        'cancelledAt': null,
      },
      'payment': {
        'status': 'paid',
        'razorpayOrderId': 'order_123',
        'razorpayPaymentId': 'pay_123',
        'razorpayRefundId': '',
        'paymentAttemptId': 'attempt-1',
        'orderCreatedAt': requestedAt,
        'paymentStartedAt': requestedAt.add(const Duration(minutes: 15)),
        'capturedAt': paidAt,
        'verifiedAt': paidAt,
        'verificationSource': 'callable',
        'webhookEventIds': <String>['evt_1'],
        'failureCode': '',
        'failureMessage': '',
      },
      'financials': {
        'currency': 'INR',
        'serviceSubtotalPaise': 360000,
        'couponDiscountPaise': 20000,
        'customerPaidPaise': 340000,
        'platformCommissionRateBasisPoints': 1500,
        'platformCommissionPaise': 54000,
        'providerPayoutPaise': 306000,
        'pettxoCouponFundingPaise': 20000,
        'gatewayFeeSunkPaise': 0,
        'providerFaultCostPaise': 0,
        'refundAmountPaise': 0,
        'pettxoNetBeforeGatewayPaise': 34000,
        'pricingVersion': 1,
      },
      'statistics': {
        'selectedSlotCount': null,
        'totalDurationMinutes': null,
        'nights': 2,
      },
      'stateQueryValue': 'CONFIRMED',
      'bookingTypeQueryValue': 'RANGE',
      'serviceAnchorAt': checkIn,
      'scheduledStartAt': null,
      'checkInDateTime': checkIn,
      'acceptDeadlineAt': requestedAt.add(const Duration(hours: 1)),
      'payDeadlineAt': requestedAt.add(const Duration(hours: 1, minutes: 10)),
      'completedAt': null,
    };
  }

  group('parseCanonicalBookingDocumentV3', () {
    test('parses canonical SLOT booking', () {
      final result = parseCanonicalBookingDocumentV3(buildCanonicalSlot());
      expect(result.isValid, isTrue);
      expect(result.booking?.bookingType, BookingV3Type.slot);
      expect(result.booking?.schedule, isA<CanonicalSlotBookingScheduleV3>());
    });

    test('parses canonical multi-slot booking', () {
      final map = buildCanonicalSlot();
      final start = DateTime.utc(2026, 7, 23, 6);
      final second = DateTime.utc(2026, 7, 23, 7);
      final third = DateTime.utc(2026, 7, 23, 8);
      map['service']['selectedSlotCount'] = 3;
      map['service']['totalDurationMinutes'] = 180;
      map['schedule'] = {
        'bookingType': 'SLOT',
        'slots': [
          {
            'slotId': 'slot-1',
            'dateKey': '2026-07-23',
            'startAt': start,
            'endAt': second,
            'durationMinutes': 60,
            'unitPricePaise': 25000,
            'serviceId': 'service-1',
            'providerId': 'provider-1',
            'timezone': 'Asia/Kolkata',
          },
          {
            'slotId': 'slot-2',
            'dateKey': '2026-07-23',
            'startAt': second,
            'endAt': third,
            'durationMinutes': 60,
            'unitPricePaise': 25000,
            'serviceId': 'service-1',
            'providerId': 'provider-1',
            'timezone': 'Asia/Kolkata',
          },
          {
            'slotId': 'slot-3',
            'dateKey': '2026-07-23',
            'startAt': third,
            'endAt': DateTime.utc(2026, 7, 23, 9),
            'durationMinutes': 60,
            'unitPricePaise': 25000,
            'serviceId': 'service-1',
            'providerId': 'provider-1',
            'timezone': 'Asia/Kolkata',
          },
        ],
        'slotCount': 3,
        'scheduledStartAt': start,
        'scheduledEndAt': DateTime.utc(2026, 7, 23, 9),
        'totalDurationMinutes': 180,
        'timezone': 'Asia/Kolkata',
        'serviceAnchorAt': start,
      };
      map['statistics']['selectedSlotCount'] = 3;
      map['statistics']['totalDurationMinutes'] = 180;
      map['serviceAnchorAt'] = start;
      map['scheduledStartAt'] = start;

      final result = parseCanonicalBookingDocumentV3(map);
      expect(result.isValid, isTrue);
      expect(
        (result.booking?.schedule as CanonicalSlotBookingScheduleV3).slotCount,
        3,
      );
    });

    test('parses canonical RANGE booking', () {
      final result = parseCanonicalBookingDocumentV3(buildCanonicalRange());
      expect(result.isValid, isTrue);
      expect(result.booking?.bookingType, BookingV3Type.range);
      expect(result.booking?.financials?.customerPaidPaise, 340000);
    });

    test('rejects invalid schema version', () {
      final result = parseCanonicalBookingDocumentV3(
        buildCanonicalSlot(schemaVersion: 2),
      );
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((issue) => issue.code == 'INVALID_SCHEMA_VERSION'),
        isTrue,
      );
    });

    test('rejects missing required fields safely', () {
      final map = buildCanonicalSlot();
      (map['participants']['parent'] as Map<String, dynamic>).remove(
        'parentId',
      );
      final result = parseCanonicalBookingDocumentV3(map);
      expect(result.isValid, isFalse);
      expect(result.booking, isNull);
    });

    test('preserves paise precision and accepts null lifecycle timestamps', () {
      final map = buildCanonicalRange();
      (map['lifecycle'] as Map<String, dynamic>)['otpEnteredAt'] = null;
      (map['lifecycle'] as Map<String, dynamic>)['serviceEndedAt'] = null;
      final result = parseCanonicalBookingDocumentV3(map);
      expect(result.isValid, isTrue);
      expect(result.booking?.financials?.serviceSubtotalPaise, 360000);
      expect(result.booking?.lifecycle.otpEnteredAt, isNull);
    });

    test('rejects pre-payment private fields on public booking doc', () {
      final map = buildCanonicalSlot();
      (map['participants']['parent'] as Map<String, dynamic>)['phoneNumber'] =
          '+919999999999';
      final result = parseCanonicalBookingDocumentV3(map);
      expect(result.isValid, isFalse);
      expect(
        result.issues.any((issue) => issue.code == 'PREPAYMENT_PRIVATE_FIELD'),
        isTrue,
      );
    });
  });
}
