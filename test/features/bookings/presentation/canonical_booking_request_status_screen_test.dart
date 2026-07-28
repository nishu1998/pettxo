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
    'expired payment request status shows expired messaging and hides pay action',
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
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Payment window expired'), findsWidgets);
      expect(
        find.text(
          'You did not complete payment within the active payment window. This booking request has expired.',
        ),
        findsOneWidget,
      );
      expect(find.text('Response window ended.'), findsOneWidget);
      expect(
        find.text(
          'Payment was not completed within the active payment window. This booking request has expired.',
        ),
        findsOneWidget,
      );
      expect(find.text('Nothing has been charged.'), findsOneWidget);
      expect(find.text('Pay now'), findsNothing);
      expect(find.text('Resume payment'), findsNothing);
    },
  );
}

class _FakeBookingRepository extends BookingRepository {
  _FakeBookingRepository(this.booking);

  final CanonicalBookingDocumentV3 booking;

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
      'customerPaidPaise': 10000,
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
