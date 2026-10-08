import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/messages/data/repositories/chat_repository.dart';
import 'package:pettexo/features/messages/domain/models/chat_model.dart';

ChatModel chat(
  String id, {
  required String chatType,
  String linkedBookingId = '',
}) {
  return ChatModel.fromMap(id, <String, dynamic>{
    'customerId': 'uid-a',
    'providerId': 'uid-b',
    'participantIds': <String>['uid-a', 'uid-b'],
    'chatType': chatType,
    'linkedBookingId': linkedBookingId,
    'status': chatType == 'booking' ? 'unlocked' : 'active',
  });
}

void main() {
  test('shows only the exact canonical direct chat for a UID pair', () {
    final result = dedupeChatsForInbox(<ChatModel>[
      chat('uid-a_uid-b', chatType: 'directUser'),
      chat('chat_uid-a_uid-b', chatType: 'directUser'),
      chat('booking-1', chatType: 'booking', linkedBookingId: 'booking-1'),
      chat('booking-2', chatType: 'booking', linkedBookingId: 'booking-2'),
    ]);

    expect(result.map((item) => item.id), <String>['chat_uid-a_uid-b']);
  });

  test('historical booking chats do not create additional inbox rows', () {
    final result = dedupeChatsForInbox(<ChatModel>[
      chat('chat_uid-a_uid-b', chatType: 'directUser'),
      chat('booking-1', chatType: 'booking', linkedBookingId: 'booking-1'),
    ]);

    expect(result.map((item) => item.id), <String>['chat_uid-a_uid-b']);
  });

  test('does not manufacture a pair identity for malformed direct chats', () {
    final malformed = ChatModel.fromMap('legacy-malformed', <String, dynamic>{
      'participantIds': <String>['uid-a'],
      'chatType': 'directUser',
    });
    final canonical = chat('chat_uid-a_uid-b', chatType: 'directUser');

    expect(dedupeChatsForInbox(<ChatModel>[malformed, canonical]), <ChatModel>[
      canonical,
    ]);
  });

  test('a chat-prefixed malformed row cannot replace the canonical chat', () {
    final malformed = chat('chat_legacy_uid-a_uid-b', chatType: 'directUser');
    final canonical = chat('chat_uid-a_uid-b', chatType: 'directUser');

    expect(
      dedupeChatsForInbox(<ChatModel>[malformed, canonical]).single.id,
      canonical.id,
    );
  });
}
