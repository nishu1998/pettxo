import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/services/push_notification_service.dart';
import 'package:pettexo/features/bookings/domain/models/booking_flow_models.dart';

void main() {
  group('foreground push intents', () {
    test('promotional payload resolves to no navigation intent', () {
      final intent = PushNotificationService.navigationIntentFromPayload({
        'category': 'promotion',
        'type': 'promotionalBroadcast',
        'broadcastId': 'promo_broadcast_req_1',
      }, mode: PushPayloadDeliveryMode.foreground);

      expect(intent.target, PushNavigationTarget.none);
    });

    test('confirmed booking payload resolves to booking intent', () {
      final intent = PushNotificationService.navigationIntentFromPayload({
        'bookingId': 'booking-1',
        'recipientRole': 'customer',
        'state': 'CONFIRMED',
      }, mode: PushPayloadDeliveryMode.foreground);

      expect(intent.target, PushNavigationTarget.booking);
      expect(intent.bookingRequest?.bookingId, 'booking-1');
      expect(
        intent.bookingRequest?.fallbackContextMode,
        BookingContextMode.receiving,
      );
    });

    test(
      'processing booking payload ignores stale state and resolves by booking id',
      () {
        final intent = PushNotificationService.navigationIntentFromPayload({
          'bookingId': 'booking-2',
          'recipientRole': 'provider',
          'state': 'CAPTURE_REPORTED',
          'paymentStatus': 'processing',
        }, mode: PushPayloadDeliveryMode.foreground);

        expect(intent.target, PushNavigationTarget.booking);
        expect(intent.bookingRequest?.bookingId, 'booking-2');
        expect(
          intent.bookingRequest?.fallbackContextMode,
          BookingContextMode.delivering,
        );
      },
    );

    test(
      'refund-required foreground payload still resolves to booking intent',
      () {
        final intent = PushNotificationService.navigationIntentFromPayload({
          'bookingId': 'booking-2b',
          'recipientRole': 'customer',
          'state': 'REFUND_REQUIRED',
        }, mode: PushPayloadDeliveryMode.foreground);

        expect(intent.target, PushNavigationTarget.booking);
        expect(intent.bookingRequest?.bookingId, 'booking-2b');
      },
    );

    test('missing foreground booking id falls back to notifications', () {
      final intent = PushNotificationService.navigationIntentFromPayload({
        'recipientRole': 'customer',
        'state': 'CONFIRMED',
      }, mode: PushPayloadDeliveryMode.foreground);

      expect(intent.target, PushNavigationTarget.notifications);
    });

    test('malformed foreground payload safely falls back to notifications', () {
      final intent = PushNotificationService.navigationIntentFromPayload({
        'type': 'unknown',
      }, mode: PushPayloadDeliveryMode.foreground);

      expect(intent.target, PushNavigationTarget.notifications);
    });
  });

  group('background push tap intents', () {
    test('promotional background payload remains non-actionable', () {
      final intent = PushNotificationService.navigationIntentFromPayload({
        'data': {
          'category': 'promotion',
          'type': 'promotionalBroadcast',
          'broadcastId': 'promo_broadcast_req_2',
        },
      }, mode: PushPayloadDeliveryMode.backgroundTap);

      expect(intent.target, PushNavigationTarget.none);
    });

    test('canonical request payload resolves to booking intent', () {
      final intent = PushNotificationService.navigationIntentFromPayload({
        'bookingId': 'booking-3',
        'recipientRole': 'provider',
        'state': 'REQUESTED',
      }, mode: PushPayloadDeliveryMode.backgroundTap);

      expect(intent.target, PushNavigationTarget.booking);
      expect(
        intent.bookingRequest?.fallbackContextMode,
        BookingContextMode.delivering,
      );
    });

    test(
      'booking payload without explicit state still resolves by booking id',
      () {
        final intent = PushNotificationService.navigationIntentFromPayload({
          'bookingId': 'booking-legacyless-1',
          'recipientRole': 'customer',
        }, mode: PushPayloadDeliveryMode.backgroundTap);

        expect(intent.target, PushNavigationTarget.booking);
        expect(intent.bookingRequest?.bookingId, 'booking-legacyless-1');
      },
    );

    test(
      'chat payload resolves to chat intent before any booking fallback',
      () {
        final intent = PushNotificationService.navigationIntentFromPayload({
          'type': 'chatMessage',
          'chatId': 'chat-1',
          'bookingId': 'booking-4',
        }, mode: PushPayloadDeliveryMode.backgroundTap);

        expect(intent.target, PushNavigationTarget.chat);
        expect(intent.chatId, 'chat-1');
      },
    );

    test('unsupported background payload falls back to notifications', () {
      final intent = PushNotificationService.navigationIntentFromPayload({
        'type': 'moderation',
      }, mode: PushPayloadDeliveryMode.backgroundTap);

      expect(intent.target, PushNavigationTarget.notifications);
    });
  });

  group('terminated launch intents', () {
    test('terminated confirmed payload resolves to booking intent', () {
      final intent = PushNotificationService.navigationIntentFromPayload({
        'bookingId': 'booking-5',
        'recipientRole': 'customer',
        'state': 'CONFIRMED',
      }, mode: PushPayloadDeliveryMode.initialLaunch);

      expect(intent.target, PushNavigationTarget.booking);
      expect(intent.bookingRequest?.bookingId, 'booking-5');
    });

    test(
      'terminated refund-pending payload still resolves to booking intent',
      () {
        final intent = PushNotificationService.navigationIntentFromPayload({
          'bookingId': 'booking-6',
          'recipientRole': 'customer',
          'state': 'REFUND_PENDING',
        }, mode: PushPayloadDeliveryMode.initialLaunch);

        expect(intent.target, PushNavigationTarget.booking);
      },
    );

    test(
      'terminated reconciliation payload still resolves to booking intent',
      () {
        final intent = PushNotificationService.navigationIntentFromPayload({
          'bookingId': 'booking-6b',
          'recipientRole': 'customer',
          'state': 'CAPTURED_REQUIRES_RECONCILIATION',
        }, mode: PushPayloadDeliveryMode.initialLaunch);

        expect(intent.target, PushNavigationTarget.booking);
        expect(intent.bookingRequest?.bookingId, 'booking-6b');
      },
    );

    test('terminated malformed payload falls back to notifications', () {
      final intent = PushNotificationService.navigationIntentFromPayload({
        'title': 'Pettxo update',
      }, mode: PushPayloadDeliveryMode.initialLaunch);

      expect(intent.target, PushNavigationTarget.notifications);
    });
  });
}
