import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/messages/domain/models/message_model.dart';

void main() {
  test('historical messages without type remain text messages', () {
    final message = MessageModel.fromMap('old', {'text': 'Hello'});
    expect(message.isText, isTrue);
    expect(message.isImage, isFalse);
  });

  test('valid image metadata parses without affecting delivery fields', () {
    final message = MessageModel.fromMap('image-1', {
      'senderId': 'uid-a',
      'receiverId': 'uid-b',
      'text': '',
      'type': 'image',
      'storagePath': 'chatMedia/chat_uid-a_uid-b/image-1/image.jpg',
      'imageWidth': 1200,
      'imageHeight': 800,
      'imageSizeBytes': 123456,
      'mimeType': 'image/jpeg',
      'mediaSchemaVersion': 1,
      'deliveredTo': ['uid-b'],
      'readBy': ['uid-b'],
    });
    expect(message.isImage, isTrue);
    expect(message.imageWidth, 1200);
    expect(message.deliveredTo, ['uid-b']);
    expect(message.readBy, ['uid-b']);
  });

  test('unknown and malformed image types are not treated as images', () {
    expect(MessageModel.fromMap('future', {'type': 'video'}).isImage, isFalse);
    expect(MessageModel.fromMap('broken', {'type': 'image'}).isImage, isFalse);
  });
}
