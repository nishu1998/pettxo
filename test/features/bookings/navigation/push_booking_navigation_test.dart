import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/services/push_notification_service.dart';
import 'package:pettexo/features/bookings/domain/models/booking_flow_models.dart';

void main() {
  test('push booking helper defaults to receiving context', () {
    final request = PushNotificationService.bookingOpenRequestFromPayload({
      'bookingId': 'booking-1',
    });

    expect(request.bookingId, 'booking-1');
    expect(request.fallbackContextMode, BookingContextMode.receiving);
  });

  test(
    'push booking helper routes provider payloads to delivering context',
    () {
      final request = PushNotificationService.bookingOpenRequestFromPayload({
        'bookingId': 'booking-2',
        'recipientRole': 'provider',
      });

      expect(request.bookingId, 'booking-2');
      expect(request.fallbackContextMode, BookingContextMode.delivering);
    },
  );

  test('push booking helper supports nested data payloads', () {
    final request = PushNotificationService.bookingOpenRequestFromPayload({
      'data': {'bookingId': 'booking-3', 'recipientRole': 'provider'},
    });

    expect(request.bookingId, 'booking-3');
    expect(request.fallbackContextMode, BookingContextMode.delivering);
  });

  test('push booking helper keeps malformed payloads safe', () {
    final request = PushNotificationService.bookingOpenRequestFromPayload({
      'chatId': 'chat-1',
    });

    expect(request.bookingId, isEmpty);
    expect(request.fallbackContextMode, BookingContextMode.receiving);
  });
}
