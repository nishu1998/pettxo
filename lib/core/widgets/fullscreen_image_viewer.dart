import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'fullscreen_image_transform_policy.dart';

class FullscreenImageViewer extends StatefulWidget {
  const FullscreenImageViewer({
    super.key,
    required this.imageProvider,
    required this.aspectRatio,
    this.heroTag,
  });

  final ImageProvider imageProvider;
  final double aspectRatio;
  final Object? heroTag;

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  final TransformationController _controller = TransformationController();
  TapDownDetails? _doubleTapDetails;
  Offset _drag = Offset.zero;
  bool _dragEligible = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) {
            _drag = Offset.zero;
            _dragEligible = !FullscreenImageTransformPolicy.isZoomed(
              _controller.value,
            );
          },
          onVerticalDragUpdate: (details) {
            if (_dragEligible) _drag += details.delta;
          },
          onVerticalDragEnd: (details) {
            if (_dragEligible &&
                (_drag.dy.abs() > 120 ||
                    details.primaryVelocity?.abs() != null &&
                        details.primaryVelocity!.abs() > 900)) {
              Navigator.of(context).maybePop();
            }
          },
          child: InteractiveViewer(
            transformationController: _controller,
            minScale: FullscreenImageTransformPolicy.minScale,
            maxScale: FullscreenImageTransformPolicy.maxScale,
            boundaryMargin: EdgeInsets.zero,
            clipBehavior: Clip.hardEdge,
            onInteractionEnd: (_) {
              _controller.value = FullscreenImageTransformPolicy.clamp(
                _controller.value,
                viewportSize: viewport,
                imageAspectRatio: widget.aspectRatio,
              );
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTapDown: (details) => _doubleTapDetails = details,
              onDoubleTap: () {
                _controller.value =
                    FullscreenImageTransformPolicy.toggleDoubleTap(
                      currentTransform: _controller.value,
                      viewportSize: viewport,
                      imageAspectRatio: widget.aspectRatio,
                      focalPoint: _doubleTapDetails?.localPosition,
                    );
              },
              child: SizedBox(
                width: viewport.width,
                height: viewport.height,
                child: Image(
                  image: widget.imageProvider,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: Colors.white70,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: widget.heroTag == null
                  ? body
                  : Hero(tag: widget.heroTag!, child: body),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.36),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
