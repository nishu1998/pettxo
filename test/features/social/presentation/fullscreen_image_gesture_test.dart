import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/social/domain/fullscreen_image_transform_policy.dart';
import 'package:pettexo/features/social/presentation/widgets/post_image_carousel.dart';

void main() {
  testWidgets('fullscreen viewer clamps pan and accepts two-pointer zoom', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: PostImageCarousel(
                imageUrls: <String>['https://example.invalid/post.jpg'],
                thumbnailUrls: <String>['https://example.invalid/thumb.jpg'],
                aspectRatio: 1,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(PostImageCarousel));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    final viewerFinder = find.byType(InteractiveViewer);
    expect(viewerFinder, findsOneWidget);
    final viewer = tester.widget<InteractiveViewer>(viewerFinder);
    expect(viewer.minScale, FullscreenImageTransformPolicy.minScale);
    expect(viewer.maxScale, FullscreenImageTransformPolicy.maxScale);
    expect(viewer.boundaryMargin, EdgeInsets.zero);
    expect(viewer.clipBehavior, Clip.hardEdge);

    final controller = viewer.transformationController!;
    final center = tester.getCenter(viewerFinder);

    final firstFinger = await tester.createGesture();
    final secondFinger = await tester.createGesture();
    await firstFinger.down(center + const Offset(-40, 0));
    await secondFinger.down(center + const Offset(40, 0));
    await tester.pump();
    await firstFinger.moveBy(const Offset(-40, 0));
    await secondFinger.moveBy(const Offset(40, 0));
    await tester.pump();
    await firstFinger.moveBy(const Offset(-40, 0));
    await secondFinger.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(
      controller.value.getMaxScaleOnAxis(),
      greaterThan(1),
      reason: 'The live two-pointer gesture must reach InteractiveViewer.',
    );
    await firstFinger.up();
    await secondFinger.up();
    await tester.pump();

    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
    expect(
      controller.value.getMaxScaleOnAxis(),
      lessThanOrEqualTo(FullscreenImageTransformPolicy.maxScale),
    );

    controller.value = Matrix4.identity();
    final defaultPan = await tester.startGesture(center);
    await defaultPan.moveBy(const Offset(180, 120));
    await defaultPan.up();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.001));
    expect(controller.value.getTranslation().x, closeTo(0, 0.001));
    expect(controller.value.getTranslation().y, closeTo(0, 0.001));
  });

  testWidgets('double tap resets and reopening starts fitted', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: PostImageCarousel(
                imageUrls: <String>['https://example.invalid/post.jpg'],
                thumbnailUrls: <String>['https://example.invalid/thumb.jpg'],
                aspectRatio: 1,
              ),
            ),
          ),
        ),
      ),
    );

    await _openViewer(tester);
    var viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    var controller = viewer.transformationController!;
    final center = tester.getCenter(find.byType(InteractiveViewer));

    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      controller.value.getMaxScaleOnAxis(),
      closeTo(FullscreenImageTransformPolicy.doubleTapScale, 0.001),
    );

    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 350));
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.001));
    expect(controller.value.getTranslation().x, closeTo(0, 0.001));
    expect(controller.value.getTranslation().y, closeTo(0, 0.001));

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await _openViewer(tester);

    viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    controller = viewer.transformationController!;
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.001));
    expect(controller.value.getTranslation().x, closeTo(0, 0.001));
    expect(controller.value.getTranslation().y, closeTo(0, 0.001));
  });

  testWidgets('one-finger horizontal swipe keeps multi-image navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: PostImageCarousel(
                imageUrls: <String>[
                  'https://example.invalid/first.jpg',
                  'https://example.invalid/second.jpg',
                ],
                thumbnailUrls: <String>[
                  'https://example.invalid/first-thumb.jpg',
                  'https://example.invalid/second-thumb.jpg',
                ],
                aspectRatio: 1,
              ),
            ),
          ),
        ),
      ),
    );

    await _openViewer(tester);
    final pageView = tester.widget<PageView>(find.byType(PageView).last);
    final center = tester.getCenter(find.byType(InteractiveViewer));

    final swipe = await tester.startGesture(center);
    await swipe.moveBy(const Offset(-80, 0));
    await tester.pump();
    await swipe.moveBy(const Offset(-80, 0));
    await tester.pump();
    await swipe.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(pageView.controller!.page, closeTo(1, 0.001));
  });

  testWidgets('one-finger vertical swipe still dismisses at minimum scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: PostImageCarousel(
                imageUrls: <String>['https://example.invalid/post.jpg'],
                thumbnailUrls: <String>['https://example.invalid/thumb.jpg'],
                aspectRatio: 1,
              ),
            ),
          ),
        ),
      ),
    );

    await _openViewer(tester);
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final dismiss = await tester.startGesture(center);
    await dismiss.moveBy(const Offset(0, 80));
    await tester.pump();
    await dismiss.moveBy(const Offset(0, 80));
    await tester.pump();
    await dismiss.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.byType(PostImageCarousel), findsOneWidget);
  });
}

Future<void> _openViewer(WidgetTester tester) async {
  await tester.tap(find.byType(PostImageCarousel));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
  expect(find.byType(InteractiveViewer), findsOneWidget);
}
