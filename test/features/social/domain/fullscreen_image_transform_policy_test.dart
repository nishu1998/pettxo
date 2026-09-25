import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/social/domain/fullscreen_image_transform_policy.dart';

void main() {
  const viewport = Size(400, 800);

  group('FullscreenImageTransformPolicy', () {
    test('starts fitted at minimum scale with zero translation', () {
      final transform = FullscreenImageTransformPolicy.initialTransform();

      expect(transform.getMaxScaleOnAxis(), 1);
      expect(transform.getTranslation().x, 0);
      expect(transform.getTranslation().y, 0);
      expect(FullscreenImageTransformPolicy.isZoomed(transform), isFalse);
    });

    test('clamps scale to the configured minimum and maximum', () {
      final belowMinimum = _transform(scale: 0.4, x: 120, y: -80);
      final aboveMaximum = _transform(scale: 7, x: -100, y: -200);

      final minimum = FullscreenImageTransformPolicy.clamp(
        belowMinimum,
        viewportSize: viewport,
        imageAspectRatio: 0.5,
      );
      final maximum = FullscreenImageTransformPolicy.clamp(
        aboveMaximum,
        viewportSize: viewport,
        imageAspectRatio: 0.5,
      );

      expect(minimum.getMaxScaleOnAxis(), 1);
      expect(minimum.getTranslation().x, 0);
      expect(minimum.getTranslation().y, 0);
      expect(maximum.getMaxScaleOnAxis(), 4);
    });

    test('minimum-scale image cannot retain an off-screen translation', () {
      final clamped = FullscreenImageTransformPolicy.clamp(
        _transform(scale: 1, x: -900, y: 600),
        viewportSize: viewport,
        imageAspectRatio: 0.5,
      );

      expect(clamped.getTranslation().x, 0);
      expect(clamped.getTranslation().y, 0);
    });

    test('zoomed image permits valid panning', () {
      final clamped = FullscreenImageTransformPolicy.clamp(
        _transform(scale: 2, x: -120, y: -260),
        viewportSize: viewport,
        imageAspectRatio: 0.5,
      );

      expect(clamped.getMaxScaleOnAxis(), 2);
      expect(clamped.getTranslation().x, -120);
      expect(clamped.getTranslation().y, -260);
    });

    test('zoomed image translation remains bounded on every edge', () {
      final positive = FullscreenImageTransformPolicy.clamp(
        _transform(scale: 2, x: 500, y: 500),
        viewportSize: viewport,
        imageAspectRatio: 0.5,
      );
      final negative = FullscreenImageTransformPolicy.clamp(
        _transform(scale: 2, x: -900, y: -1800),
        viewportSize: viewport,
        imageAspectRatio: 0.5,
      );

      expect(positive.getTranslation().x, 0);
      expect(positive.getTranslation().y, 0);
      expect(negative.getTranslation().x, -400);
      expect(negative.getTranslation().y, -800);
    });

    test('letterboxed axis stays centered until the image fills it', () {
      final clamped = FullscreenImageTransformPolicy.clamp(
        _transform(scale: 1.5, x: -500, y: -100),
        viewportSize: viewport,
        imageAspectRatio: 0.25,
      );

      expect(clamped.getTranslation().x, -100);
      expect(clamped.getTranslation().y, -100);
    });

    test('returning to minimum resets residual pan', () {
      final zoomed = FullscreenImageTransformPolicy.clamp(
        _transform(scale: 2.5, x: -240, y: -300),
        viewportSize: viewport,
        imageAspectRatio: 0.5,
      );
      final reset = FullscreenImageTransformPolicy.clamp(
        _transform(
          scale: 1,
          x: zoomed.getTranslation().x,
          y: zoomed.getTranslation().y,
        ),
        viewportSize: viewport,
        imageAspectRatio: 0.5,
      );

      expect(reset, equals(Matrix4.identity()));
    });

    test('double tap toggles between bounded zoom and fitted state', () {
      final initial = FullscreenImageTransformPolicy.initialTransform();
      final zoomed = FullscreenImageTransformPolicy.toggleDoubleTap(
        currentTransform: initial,
        viewportSize: viewport,
        imageAspectRatio: 0.5,
        focalPoint: const Offset(350, 700),
      );
      final reset = FullscreenImageTransformPolicy.toggleDoubleTap(
        currentTransform: zoomed,
        viewportSize: viewport,
        imageAspectRatio: 0.5,
        focalPoint: const Offset(350, 700),
      );

      expect(
        zoomed.getMaxScaleOnAxis(),
        FullscreenImageTransformPolicy.doubleTapScale,
      );
      expect(FullscreenImageTransformPolicy.isZoomed(zoomed), isTrue);
      expect(reset, equals(Matrix4.identity()));
    });

    test('new viewer lifecycle starts with a fresh fitted transform', () {
      final previousViewer = FullscreenImageTransformPolicy.toggleDoubleTap(
        currentTransform: FullscreenImageTransformPolicy.initialTransform(),
        viewportSize: viewport,
        imageAspectRatio: 0.5,
      );
      final reopenedViewer = FullscreenImageTransformPolicy.initialTransform();

      expect(FullscreenImageTransformPolicy.isZoomed(previousViewer), isTrue);
      expect(reopenedViewer, equals(Matrix4.identity()));
    });

    test('fitted dimensions preserve portrait and landscape aspect ratios', () {
      final portrait = FullscreenImageTransformPolicy.fittedImageSize(
        viewportSize: viewport,
        imageAspectRatio: 0.5,
      );
      final landscape = FullscreenImageTransformPolicy.fittedImageSize(
        viewportSize: viewport,
        imageAspectRatio: 2,
      );

      expect(portrait, const Size(400, 800));
      expect(landscape, const Size(400, 200));
      expect(portrait.aspectRatio, 0.5);
      expect(landscape.aspectRatio, 2);
    });
  });
}

Matrix4 _transform({
  required double scale,
  required double x,
  required double y,
}) {
  return Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(x, y, 0);
}
