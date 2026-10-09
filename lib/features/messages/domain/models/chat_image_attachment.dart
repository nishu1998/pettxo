import 'dart:typed_data';

class ProcessedChatImage {
  const ProcessedChatImage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;

  int get sizeBytes => bytes.length;
  double get aspectRatio => width / height;
}

enum ChatImageSendStage {
  idle,
  selecting,
  previewing,
  processing,
  uploading,
  committing,
  failed,
  cancelled,
  complete,
}

class PendingChatImageSend {
  const PendingChatImageSend({
    required this.messageId,
    required this.storagePath,
    required this.image,
    this.uploaded = false,
  });

  final String messageId;
  final String storagePath;
  final ProcessedChatImage image;
  final bool uploaded;

  PendingChatImageSend copyWith({bool? uploaded}) => PendingChatImageSend(
    messageId: messageId,
    storagePath: storagePath,
    image: image,
    uploaded: uploaded ?? this.uploaded,
  );
}
