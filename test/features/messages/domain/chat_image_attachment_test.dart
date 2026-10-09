import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/messages/domain/models/chat_image_attachment.dart';

void main() {
  test('retry keeps the same message identity and marks only upload state', () {
    final pending = PendingChatImageSend(
      messageId: 'AbCdEfGhIjKlMnOpQrSt',
      storagePath: 'chatMedia/chat_uid-a_uid-b/AbCdEfGhIjKlMnOpQrSt/image.jpg',
      image: ProcessedChatImage(
        bytes: Uint8List.fromList([1, 2, 3]),
        width: 3,
        height: 2,
      ),
    );
    final uploaded = pending.copyWith(uploaded: true);
    expect(uploaded.messageId, pending.messageId);
    expect(uploaded.storagePath, pending.storagePath);
    expect(uploaded.image, same(pending.image));
    expect(uploaded.uploaded, isTrue);
  });
}
