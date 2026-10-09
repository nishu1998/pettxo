import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pettexo/features/messages/presentation/widgets/chat_image_preview_dialog.dart';

void main() {
  testWidgets('crop cancellation returns to preview and original can be sent', (
    tester,
  ) async {
    final original = XFile.fromData(Uint8List.fromList([1, 2, 3]));
    XFile? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<XFile>(
                MaterialPageRoute(
                  builder: (_) => ChatImagePreviewDialog(
                    original: original,
                    cropper: (_) async => null,
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crop'));
    await tester.pumpAndSettle();
    expect(find.text('Preview photo'), findsOneWidget);
    await tester.tap(find.text('Use original'));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(result, same(original));
  });

  testWidgets('successful crop can be previewed and sent', (tester) async {
    final original = XFile.fromData(Uint8List.fromList([1, 2, 3]));
    final cropped = XFile('cropped-chat-preview.jpg');
    XFile? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<XFile>(
                MaterialPageRoute(
                  builder: (_) => ChatImagePreviewDialog(
                    original: original,
                    cropper: (_) async => cropped,
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(result?.path, cropped.path);
  });

  testWidgets('use original discards a successful crop selection', (
    tester,
  ) async {
    final original = XFile.fromData(Uint8List.fromList([1, 2, 3]));
    XFile? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<XFile>(
                MaterialPageRoute(
                  builder: (_) => ChatImagePreviewDialog(
                    original: original,
                    cropper: (_) async => XFile('discarded-crop.jpg'),
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use original'));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(result, same(original));
  });
}
