import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/messages/data/repositories/chat_media_repository.dart';

void main() {
  test(
    'upload operation reports bounded progress and forwards cancellation',
    () async {
      var cancelled = false;
      final operation = ChatImageUploadOperation.testing(
        progress: Stream.fromIterable(const [
          ChatImageUploadProgress(bytesTransferred: 25, totalBytes: 100),
          ChatImageUploadProgress(bytesTransferred: 150, totalBytes: 100),
        ]),
        completed: Future<void>.value(),
        cancel: () async {
          cancelled = true;
          return true;
        },
      );

      expect(await operation.progress.map((event) => event.fraction).toList(), [
        0.25,
        1,
      ]);
      await operation.completed;
      expect(await operation.cancel(), isTrue);
      expect(cancelled, isTrue);
    },
  );

  test(
    'upload operation surfaces upload failure without reporting completion',
    () async {
      final operation = ChatImageUploadOperation.testing(
        progress: const Stream.empty(),
        completed: Future<void>.error(StateError('upload failed')),
        cancel: () async => false,
      );

      await expectLater(operation.completed, throwsStateError);
    },
  );
}
