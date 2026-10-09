import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

import '../../domain/models/chat_image_attachment.dart';

const int maxChatImageDecodedPixels = 40 * 1000 * 1000;
const int maxChatImageEdge = 1600;
const int maxProcessedChatImageBytes = 3 * 1024 * 1024;

class ChatImageProcessingException implements Exception {
  const ChatImageProcessingException(this.message);
  final String message;

  @override
  String toString() => message;
}

typedef ChatImageFallbackConverter = Future<Uint8List?> Function(XFile source);

class ChatImageProcessingService {
  const ChatImageProcessingService({ChatImageFallbackConverter? fallback})
    : _fallback = fallback;

  final ChatImageFallbackConverter? _fallback;

  Future<ProcessedChatImage> process(XFile source) async {
    final sourceBytes = await source.readAsBytes();
    if (sourceBytes.isEmpty) {
      throw const ChatImageProcessingException('The selected image is empty.');
    }

    var result = await compute(_processDecodableImage, sourceBytes);
    if (result == null) {
      Uint8List? converted;
      try {
        converted = _fallback == null
            ? await FlutterImageCompress.compressWithFile(
                source.path,
                minWidth: maxChatImageEdge,
                minHeight: maxChatImageEdge,
                quality: 82,
                format: CompressFormat.jpeg,
                keepExif: false,
                autoCorrectionAngle: true,
              )
            : await _fallback(source);
      } catch (_) {
        converted = null;
      }
      if (converted == null || converted.isEmpty) {
        throw const ChatImageProcessingException(
          'This image format is not supported on this device.',
        );
      }
      result = await compute(
        _processDecodableImage,
        Uint8List.fromList(converted),
      );
    }
    if (result == null) {
      throw const ChatImageProcessingException(
        'The selected image is corrupted or unsupported.',
      );
    }
    if (result.bytes.length > maxProcessedChatImageBytes) {
      throw const ChatImageProcessingException(
        'The processed image is still too large. Please choose another photo.',
      );
    }
    return result;
  }
}

ProcessedChatImage? _processDecodableImage(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  if (decoded.width <= 0 || decoded.height <= 0) return null;
  if (decoded.width * decoded.height > maxChatImageDecodedPixels) {
    throw const ChatImageProcessingException(
      'This image has extremely large dimensions. Please choose another photo.',
    );
  }

  final oriented = img.bakeOrientation(decoded);
  final longest = oriented.width > oriented.height
      ? oriented.width
      : oriented.height;
  final resized = longest <= maxChatImageEdge
      ? oriented
      : oriented.width >= oriented.height
      ? img.copyResize(oriented, width: maxChatImageEdge)
      : img.copyResize(oriented, height: maxChatImageEdge);

  Uint8List? encoded;
  for (final quality in const [82, 74, 66, 58]) {
    final candidate = Uint8List.fromList(
      img.encodeJpg(resized, quality: quality),
    );
    if (candidate.length <= maxProcessedChatImageBytes) {
      encoded = candidate;
      break;
    }
  }
  if (encoded == null) {
    throw const ChatImageProcessingException(
      'The processed image is still too large. Please choose another photo.',
    );
  }
  return ProcessedChatImage(
    bytes: encoded,
    width: resized.width,
    height: resized.height,
  );
}
