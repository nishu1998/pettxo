import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/messages/domain/models/chat_model.dart';

void main() {
  group('ChatModel safety notice normalization', () {
    test('replaces only the exact legacy booking safety notice', () {
      final chat = ChatModel.fromMap('booking-1', {
        'customerId': 'parent-1',
        'providerId': 'provider-1',
        'participantIds': ['parent-1', 'provider-1'],
        'customerName': 'Nisha Gautam',
        'providerName': 'Prakash Gautam',
        'status': 'unlocked',
        'chatType': 'booking',
        'linkedBookingId': 'booking-1',
        'safetyNotice': ChatModel.legacyBookingSafetyNotice,
      });

      expect(chat.safetyNotice, ChatModel.bookingSafetyNotice);
      expect(chat.isBookingChat, isTrue);
    });

    test('preserves unknown safety notices without rewriting them', () {
      const customNotice = 'Bring the pet carrier to the pickup point.';
      final chat = ChatModel.fromMap('booking-2', {
        'customerId': 'parent-1',
        'providerId': 'provider-1',
        'participantIds': ['parent-1', 'provider-1'],
        'customerName': 'Nisha Gautam',
        'providerName': 'Prakash Gautam',
        'status': 'unlocked',
        'chatType': 'booking',
        'linkedBookingId': 'booking-2',
        'safetyNotice': customNotice,
      });

      expect(chat.safetyNotice, customNotice);
    });
  });
}
