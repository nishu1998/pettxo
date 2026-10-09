import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pettexo/core/widgets/fullscreen_image_transform_policy.dart';
import 'package:pettexo/core/widgets/fullscreen_image_viewer.dart';

void main() {
  late MemoryImage provider;

  setUp(() {
    final image = img.Image(width: 4, height: 2);
    provider = MemoryImage(Uint8List.fromList(img.encodePng(image)));
  });

  testWidgets('shared viewer supports double-tap zoom and back navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FullscreenImageViewer(imageProvider: provider, aspectRatio: 2),
      ),
    );
    await tester.pump();
    final viewer = find.byType(InteractiveViewer);
    expect(viewer, findsOneWidget);
    final controller = tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!;
    final center = tester.getCenter(viewer);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      controller.value.getMaxScaleOnAxis(),
      closeTo(FullscreenImageTransformPolicy.doubleTapScale, 0.001),
    );
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
  });
}
