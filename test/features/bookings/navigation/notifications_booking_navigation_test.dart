import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/domain/models/booking_flow_models.dart';
import 'package:pettexo/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:pettexo/features/provider/presentation/screens/provider_verification_hub_screen.dart';

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

  test('in-app visibility includes explicit in-app channel', () {
    expect(
      NotificationsScreen.isVisibleInAppNotification({
        'channels': ['push', 'in_app'],
      }),
      isTrue,
    );
  });

  test('in-app visibility hides push-only notifications', () {
    expect(
      NotificationsScreen.isVisibleInAppNotification({
        'channels': ['push'],
      }),
      isFalse,
    );
  });

  test('in-app visibility keeps legacy notifications visible', () {
    expect(
      NotificationsScreen.isVisibleInAppNotification({
        'type': 'payment_required',
      }),
      isTrue,
    );
  });

  test('promotional notifications are identified as non-actionable', () {
    expect(
      NotificationsScreen.isPromotionalNotification({
        'category': 'promotion',
        'type': 'promotionalBroadcast',
      }),
      isTrue,
    );
    expect(
      NotificationsScreen.isActionableNotification({
        'category': 'promotion',
        'type': 'promotionalBroadcast',
      }),
      isFalse,
    );
  });

  test('existing booking notifications remain actionable', () {
    expect(
      NotificationsScreen.isActionableNotification({
        'bookingId': 'booking-1',
        'type': 'payment_required',
      }),
      isTrue,
    );
  });

  test('approval notification renders canonical content and routes to hub', () {
    final data = <String, dynamic>{
      'type': 'providerVerificationApproved',
      'title': 'Verification approved',
      'body': 'You can now offer services as a verified provider.',
      'channels': ['in_app', 'push'],
    };

    final content = NotificationsScreen.displayContentFromNotificationData(
      data,
    );

    expect(content.title, 'Verification approved');
    expect(content.body, 'You can now offer services as a verified provider.');
    expect(NotificationsScreen.isVisibleInAppNotification(data), isTrue);
    expect(
      NotificationsScreen.destinationForNotificationData(data),
      isA<ProviderVerificationHubScreen>(),
    );
  });

  test(
    'rejection notification renders canonical content and routes to hub',
    () {
      final data = <String, dynamic>{
        'type': 'providerVerificationRejected',
        'title': 'Verification needs attention',
        'body': 'Review the details and resubmit your verification.',
        'channels': ['in_app', 'push'],
      };

      final content = NotificationsScreen.displayContentFromNotificationData(
        data,
      );

      expect(content.title, 'Verification needs attention');
      expect(content.body, contains('resubmit'));
      expect(NotificationsScreen.isVisibleInAppNotification(data), isTrue);
      expect(
        NotificationsScreen.destinationForNotificationData(data),
        isA<ProviderVerificationHubScreen>(),
      );
    },
  );

  test('nested verification type routes to hub', () {
    expect(
      NotificationsScreen.destinationForNotificationData({
        'data': {'type': 'providerVerificationRejected'},
      }),
      isA<ProviderVerificationHubScreen>(),
    );
  });

  test('generic notification destination behavior remains unchanged', () {
    expect(
      NotificationsScreen.destinationForNotificationData({
        'type': 'accountUpdate',
      }),
      isNull,
    );
  });
}
