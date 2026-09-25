import 'package:flutter/widgets.dart';

class FullscreenImageTransformPolicy {
  const FullscreenImageTransformPolicy._();

  static const double minScale = 1;
  static const double maxScale = 4;
  static const double doubleTapScale = 2.5;
  static const double zoomEpsilon = 0.01;

  static Matrix4 initialTransform() => Matrix4.identity();

  static bool isZoomed(Matrix4 transform) {
    return transform.getMaxScaleOnAxis() > minScale + zoomEpsilon;
  }

  static Matrix4 toggleDoubleTap({
    required Matrix4 currentTransform,
    required Size viewportSize,
    required double imageAspectRatio,
    Offset? focalPoint,
  }) {
    if (isZoomed(currentTransform)) return initialTransform();

    final focal = focalPoint ?? viewportSize.center(Offset.zero);
    final transform = Matrix4.diagonal3Values(doubleTapScale, doubleTapScale, 1)
      ..setTranslationRaw(
        (viewportSize.width / 2) - (focal.dx * doubleTapScale),
        (viewportSize.height / 2) - (focal.dy * doubleTapScale),
        0,
      );
    return clamp(
      transform,
      viewportSize: viewportSize,
      imageAspectRatio: imageAspectRatio,
    );
  }

  static Matrix4 clamp(
    Matrix4 transform, {
    required Size viewportSize,
    required double imageAspectRatio,
  }) {
    if (viewportSize.isEmpty) return initialTransform();

    final rawScale = transform.getMaxScaleOnAxis();
    final scale = rawScale.clamp(minScale, maxScale).toDouble();
    if (scale <= minScale + zoomEpsilon) return initialTransform();

    final imageSize = fittedImageSize(
      viewportSize: viewportSize,
      imageAspectRatio: imageAspectRatio,
    );
    final translation = transform.getTranslation();
    final x = _clampAxisTranslation(
      translation: translation.x,
      viewportExtent: viewportSize.width,
      imageExtent: imageSize.width,
      scale: scale,
    );
    final y = _clampAxisTranslation(
      translation: translation.y,
      viewportExtent: viewportSize.height,
      imageExtent: imageSize.height,
      scale: scale,
    );

    return Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(x, y, 0);
  }

  static Size fittedImageSize({
    required Size viewportSize,
    required double imageAspectRatio,
  }) {
    final safeAspectRatio = imageAspectRatio.isFinite && imageAspectRatio > 0
        ? imageAspectRatio
        : viewportSize.aspectRatio;
    if (viewportSize.aspectRatio > safeAspectRatio) {
      return Size(viewportSize.height * safeAspectRatio, viewportSize.height);
    }
    return Size(viewportSize.width, viewportSize.width / safeAspectRatio);
  }

  static double _clampAxisTranslation({
    required double translation,
    required double viewportExtent,
    required double imageExtent,
    required double scale,
  }) {
    final scaledImageExtent = imageExtent * scale;
    if (scaledImageExtent <= viewportExtent) {
      return viewportExtent * (1 - scale) / 2;
    }

    final fittedLeadingSpace = (viewportExtent - imageExtent) / 2;
    final minimum =
        viewportExtent - ((fittedLeadingSpace + imageExtent) * scale);
    final maximum = -(fittedLeadingSpace * scale);
    return translation.clamp(minimum, maximum).toDouble();
  }
}
