import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/firebase_resilience_service.dart';
import '../../domain/fullscreen_image_transform_policy.dart';

class PostImageCarousel extends StatefulWidget {
  final List<String> imageUrls;
  final List<String> thumbnailUrls;
  final double aspectRatio;
  final BorderRadius borderRadius;
  final VoidCallback? onImageDoubleTap;

  const PostImageCarousel({
    super.key,
    required this.imageUrls,
    required this.thumbnailUrls,
    required this.aspectRatio,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.onImageDoubleTap,
  });

  @override
  State<PostImageCarousel> createState() => _PostImageCarouselState();
}

class _PostImageCarouselState extends State<PostImageCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;
  bool _showHeartOverlay = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.imageUrls.length,
              allowImplicitScrolling: true,
              onPageChanged: (value) => setState(() => _currentPage = value),
              itemBuilder: (context, index) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openFullscreen(index),
                  onDoubleTap: _handleDoubleTap,
                  child: Hero(
                    tag: _heroTagFor(widget.imageUrls[index], index),
                    child: _ProgressiveNetworkImage(
                      key: ValueKey('${widget.imageUrls[index]}-$index'),
                      imageUrl: widget.imageUrls[index],
                      thumbnailUrl: index < widget.thumbnailUrls.length
                          ? widget.thumbnailUrls[index]
                          : widget.imageUrls[index],
                    ),
                  ),
                );
              },
            ),
            IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: _showHeartOverlay ? 1 : 0,
                child: const Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0x55000000),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Icon(
                        Icons.favorite_rounded,
                        color: Colors.white,
                        size: 54,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.imageUrls.length > 1)
              Positioned(
                bottom: 14,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.26),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(widget.imageUrls.length, (index) {
                        final active = index == _currentPage;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: active ? 18 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: active
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _handleDoubleTap() {
    widget.onImageDoubleTap?.call();
    setState(() => _showHeartOverlay = true);
    Future<void>.delayed(const Duration(milliseconds: 550), () {
      if (mounted) {
        setState(() => _showHeartOverlay = false);
      }
    });
  }

  Future<void> _openFullscreen(int initialIndex) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullscreenImageGallery(
          imageUrls: widget.imageUrls,
          thumbnailUrls: widget.thumbnailUrls,
          initialIndex: initialIndex,
          imageAspectRatio: widget.aspectRatio,
        ),
      ),
    );
  }
}

class _ProgressiveNetworkImage extends StatelessWidget {
  final String imageUrl;
  final String thumbnailUrl;
  final Color backgroundColor;
  final BoxFit fit;

  const _ProgressiveNetworkImage({
    super.key,
    required this.imageUrl,
    required this.thumbnailUrl,
    this.backgroundColor = const Color(0xFFFCF8F5),
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        fit: fit,
        fadeInDuration: const Duration(milliseconds: 220),
        placeholderFadeInDuration: const Duration(milliseconds: 120),
        placeholder: (context, placeholderUrl) => CachedNetworkImage(
          imageUrl: thumbnailUrl,
          fit: fit,
          fadeInDuration: const Duration(milliseconds: 120),
          placeholder: (context, nestedUrl) => const _ImagePlaceholder(),
          errorWidget: (context, nestedUrl, error) {
            FirebaseResilienceService.logImageFailure(
              operationName: '_ProgressiveNetworkImage.thumbnail',
              error: error,
              imageUrl: nestedUrl,
            );
            return const _ImageErrorFallback();
          },
        ),
        errorWidget: (context, imageUrl, error) {
          FirebaseResilienceService.logImageFailure(
            operationName: '_ProgressiveNetworkImage.fullsize',
            error: error,
            imageUrl: imageUrl,
          );
          return const _ImageErrorFallback();
        },
        memCacheWidth: 1080,
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF2EEE9),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      ),
    );
  }
}

class _ImageErrorFallback extends StatelessWidget {
  const _ImageErrorFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFFF2EA),
      child: const Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: AppColors.textGrey,
          size: 42,
        ),
      ),
    );
  }
}

class _FullscreenImageGallery extends StatefulWidget {
  final List<String> imageUrls;
  final List<String> thumbnailUrls;
  final int initialIndex;
  final double imageAspectRatio;

  const _FullscreenImageGallery({
    required this.imageUrls,
    required this.thumbnailUrls,
    required this.initialIndex,
    required this.imageAspectRatio,
  });

  @override
  State<_FullscreenImageGallery> createState() =>
      _FullscreenImageGalleryState();
}

class _FullscreenImageGalleryState extends State<_FullscreenImageGallery> {
  late final PageController _pageController;
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.imageUrls.length,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (value) {
                setState(() => _currentPage = value);
              },
              itemBuilder: (context, index) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final viewportSize = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    return Hero(
                      tag: _heroTagFor(widget.imageUrls[index], index),
                      child: ColoredBox(
                        color: Colors.black,
                        child: _ZoomableFullscreenImage(
                          key: ValueKey(
                            'fullscreen-${widget.imageUrls[index]}-$index',
                          ),
                          imageUrl: widget.imageUrls[index],
                          thumbnailUrl: index < widget.thumbnailUrls.length
                              ? widget.thumbnailUrls[index]
                              : widget.imageUrls[index],
                          viewportSize: viewportSize,
                          imageAspectRatio: widget.imageAspectRatio,
                          onTapClose: () => Navigator.of(context).maybePop(),
                          onSwipeDismiss: () =>
                              Navigator.of(context).maybePop(),
                          onPageSwipe: (direction) {
                            _showAdjacentPage(index, direction);
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            Positioned(
              top: 8,
              left: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.36),
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
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
            if (widget.imageUrls.length > 1)
              Positioned(
                bottom: 22,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(widget.imageUrls.length, (index) {
                        final active = index == _currentPage;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: active ? 18 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: active
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showAdjacentPage(int sourceIndex, int direction) {
    if (sourceIndex != _currentPage || direction == 0) return;
    final target = (_currentPage + direction).clamp(
      0,
      widget.imageUrls.length - 1,
    );
    if (target == _currentPage) return;
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }
}

class _ZoomableFullscreenImage extends StatefulWidget {
  final String imageUrl;
  final String thumbnailUrl;
  final Size viewportSize;
  final double imageAspectRatio;
  final VoidCallback onTapClose;
  final VoidCallback onSwipeDismiss;
  final ValueChanged<int> onPageSwipe;

  const _ZoomableFullscreenImage({
    super.key,
    required this.imageUrl,
    required this.thumbnailUrl,
    required this.viewportSize,
    required this.imageAspectRatio,
    required this.onTapClose,
    required this.onSwipeDismiss,
    required this.onPageSwipe,
  });

  @override
  State<_ZoomableFullscreenImage> createState() =>
      _ZoomableFullscreenImageState();
}

class _ZoomableFullscreenImageState extends State<_ZoomableFullscreenImage> {
  final TransformationController _transformationController =
      TransformationController();
  TapDownDetails? _doubleTapDetails;
  int? _swipePointer;
  bool _pageSwipeEligible = false;
  Offset _swipeDelta = Offset.zero;
  VelocityTracker? _swipeVelocityTracker;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: SizedBox.expand(
        child: InteractiveViewer(
          transformationController: _transformationController,
          minScale: FullscreenImageTransformPolicy.minScale,
          maxScale: FullscreenImageTransformPolicy.maxScale,
          panEnabled: true,
          scaleEnabled: true,
          boundaryMargin: EdgeInsets.zero,
          constrained: true,
          clipBehavior: Clip.hardEdge,
          onInteractionEnd: _handleInteractionEnd,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTapClose,
            onDoubleTapDown: (details) => _doubleTapDetails = details,
            onDoubleTap: _handleDoubleTap,
            child: SizedBox(
              width: widget.viewportSize.width,
              height: widget.viewportSize.height,
              child: _ProgressiveNetworkImage(
                imageUrl: widget.imageUrl,
                thumbnailUrl: widget.thumbnailUrl,
                backgroundColor: Colors.black,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleDoubleTap() {
    _transformationController.value =
        FullscreenImageTransformPolicy.toggleDoubleTap(
          currentTransform: _transformationController.value,
          viewportSize: widget.viewportSize,
          imageAspectRatio: widget.imageAspectRatio,
          focalPoint: _doubleTapDetails?.localPosition,
        );
  }

  void _handleInteractionEnd(ScaleEndDetails details) {
    _transformationController.value = FullscreenImageTransformPolicy.clamp(
      _transformationController.value,
      viewportSize: widget.viewportSize,
      imageAspectRatio: widget.imageAspectRatio,
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_swipePointer == null) {
      _swipePointer = event.pointer;
      _swipeDelta = Offset.zero;
      _swipeVelocityTracker = VelocityTracker.withKind(event.kind)
        ..addPosition(event.timeStamp, event.position);
      _pageSwipeEligible = !FullscreenImageTransformPolicy.isZoomed(
        _transformationController.value,
      );
      return;
    }
    _pageSwipeEligible = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_pageSwipeEligible && event.pointer == _swipePointer) {
      _swipeDelta += event.delta;
      _swipeVelocityTracker?.addPosition(event.timeStamp, event.position);
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _swipePointer) return;
    _swipeVelocityTracker?.addPosition(event.timeStamp, event.position);
    final velocity = _swipeVelocityTracker?.getVelocity().pixelsPerSecond;
    if (_pageSwipeEligible &&
        !FullscreenImageTransformPolicy.isZoomed(
          _transformationController.value,
        )) {
      if (_swipeDelta.dx.abs() >= 72 &&
          _swipeDelta.dx.abs() > _swipeDelta.dy.abs() * 1.2) {
        widget.onPageSwipe(_swipeDelta.dx < 0 ? 1 : -1);
      } else if (_swipeDelta.dy.abs() > _swipeDelta.dx.abs() * 1.2 &&
          (_swipeDelta.dy.abs() > 120 || (velocity?.dy.abs() ?? 0) > 900)) {
        widget.onSwipeDismiss();
      }
    }
    _resetPageSwipe();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer == _swipePointer) _resetPageSwipe();
  }

  void _resetPageSwipe() {
    _swipePointer = null;
    _pageSwipeEligible = false;
    _swipeDelta = Offset.zero;
    _swipeVelocityTracker = null;
  }
}

String _heroTagFor(String imageUrl, int index) => 'post-image-$index-$imageUrl';
