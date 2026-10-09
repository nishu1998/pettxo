import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pettexo/features/messages/data/services/chat_image_processing_service.dart';

void main() {
  test('preserves aspect ratio while limiting the longest edge', () async {
    final source = img.Image(width: 2000, height: 1000);
    img.fill(source, color: img.ColorRgb8(240, 120, 40));
    final file = XFile.fromData(
      Uint8List.fromList(img.encodePng(source)),
      mimeType: 'image/png',
    );
    const service = ChatImageProcessingService();
    final result = await service.process(file);
    expect(result.width, 1600);
    expect(result.height, 800);
    expect(result.sizeBytes, lessThanOrEqualTo(maxProcessedChatImageBytes));
    expect(result.bytes.take(2), [0xff, 0xd8]);
  });

  test('rejects corrupted or unsupported input cleanly', () async {
    final service = ChatImageProcessingService(fallback: (_) async => null);
    await expectLater(
      service.process(XFile.fromData(Uint8List.fromList([1, 2, 3]))),
      throwsA(isA<ChatImageProcessingException>()),
    );
  });
}
