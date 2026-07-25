import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/domain/models/booking_flow_models.dart';
import 'package:pettexo/features/notifications/presentation/screens/notifications_screen.dart';

void main() {
  test(
    'notification booking helper defaults customers to receiving context',
    () {
      final request =
          NotificationsScreen.bookingOpenRequestFromNotificationData({
            'bookingId': 'booking-1',
          });

      expect(request.bookingId, 'booking-1');
      expect(request.fallbackContextMode, BookingContextMode.receiving);
    },
  );

  test(
    'notification booking helper routes provider notifications to delivering context',
    () {
      final request =
          NotificationsScreen.bookingOpenRequestFromNotificationData({
            'bookingId': 'booking-2',
            'recipientRole': 'provider',
          });

      expect(request.bookingId, 'booking-2');
      expect(request.fallbackContextMode, BookingContextMode.delivering);
    },
  );

  test('notification booking helper supports nested data payloads', () {
    final request = NotificationsScreen.bookingOpenRequestFromNotificationData({
      'data': {'bookingId': 'booking-3', 'recipientRole': 'provider'},
    });

    expect(request.bookingId, 'booking-3');
    expect(request.fallbackContextMode, BookingContextMode.delivering);
  });

  test('notification booking helper keeps empty booking ids safe', () {
    final request = NotificationsScreen.bookingOpenRequestFromNotificationData({
      'type': 'socialFollow',
    });

    expect(request.bookingId, isEmpty);
    expect(request.fallbackContextMode, BookingContextMode.receiving);
  });
}
