import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

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
        ),
      ),
    );
  }
}

class _ProgressiveNetworkImage extends StatelessWidget {
  final String imageUrl;
  final String thumbnailUrl;
  final Color backgroundColor;

  const _ProgressiveNetworkImage({
    super.key,
    required this.imageUrl,
    required this.thumbnailUrl,
    this.backgroundColor = const Color(0xFFFCF8F5),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.contain,
        fadeInDuration: const Duration(milliseconds: 220),
        placeholderFadeInDuration: const Duration(milliseconds: 120),
        placeholder: (context, placeholderUrl) => CachedNetworkImage(
          imageUrl: thumbnailUrl,
          fit: BoxFit.contain,
          fadeInDuration: const Duration(milliseconds: 120),
          placeholder: (context, nestedUrl) => const _ImagePlaceholder(),
          errorWidget: (context, nestedUrl, error) =>
              const _ImageErrorFallback(),
        ),
        errorWidget: (context, imageUrl, error) => const _ImageErrorFallback(),
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

  const _FullscreenImageGallery({
    required this.imageUrls,
    required this.thumbnailUrls,
    required this.initialIndex,
  });

  @override
  State<_FullscreenImageGallery> createState() =>
      _FullscreenImageGalleryState();
}

class _FullscreenImageGalleryState extends State<_FullscreenImageGallery> {
  late final PageController _pageController;
  late int _currentPage;
  final Map<int, double> _pageScales = <int, double>{};
  double _verticalDragOffset = 0;

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
    final isZoomed = (_pageScales[_currentPage] ?? 1) > 1.01;
    final dragProgress = (_verticalDragOffset.abs() / 240).clamp(0.0, 1.0);
    final backgroundOpacity = 1.0 - (dragProgress * 0.45);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: backgroundOpacity),
      body: SafeArea(
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(0, _verticalDragOffset, 0),
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.imageUrls.length,
                physics: isZoomed
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
                onPageChanged: (value) {
                  setState(() {
                    _currentPage = value;
                    _verticalDragOffset = 0;
                  });
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
                            imageUrl: widget.imageUrls[index],
                            thumbnailUrl: index < widget.thumbnailUrls.length
                                ? widget.thumbnailUrls[index]
                                : widget.imageUrls[index],
                            viewportSize: viewportSize,
                            enableDismissDrag:
                                index == _currentPage && !isZoomed,
                            onScaleChanged: (scale) {
                              _handleScaleChanged(index, scale);
                            },
                            onTapClose: () => Navigator.of(context).maybePop(),
                            onVerticalDragUpdate: _handleVerticalDragUpdate,
                            onVerticalDragEnd: _handleVerticalDragEnd,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
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

  void _handleScaleChanged(int index, double scale) {
    if (!mounted) return;
    final normalizedScale = scale < 1.01 ? 1.0 : scale;
    if ((_pageScales[index] ?? 1.0) == normalizedScale) return;
    setState(() {
      _pageScales[index] = normalizedScale;
      if (index == _currentPage && normalizedScale > 1.01) {
        _verticalDragOffset = 0;
      }
    });
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _verticalDragOffset += details.delta.dy;
    });
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    final shouldDismiss =
        _verticalDragOffset.abs() > 120 || details.primaryVelocity!.abs() > 900;
    if (shouldDismiss) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _verticalDragOffset = 0);
  }
}

class _ZoomableFullscreenImage extends StatefulWidget {
  final String imageUrl;
  final String thumbnailUrl;
  final Size viewportSize;
  final bool enableDismissDrag;
  final ValueChanged<double> onScaleChanged;
  final VoidCallback onTapClose;
  final ValueChanged<DragUpdateDetails> onVerticalDragUpdate;
  final ValueChanged<DragEndDetails> onVerticalDragEnd;

  const _ZoomableFullscreenImage({
    required this.imageUrl,
    required this.thumbnailUrl,
    required this.viewportSize,
    required this.enableDismissDrag,
    required this.onScaleChanged,
    required this.onTapClose,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
  });

  @override
  State<_ZoomableFullscreenImage> createState() =>
      _ZoomableFullscreenImageState();
}

class _ZoomableFullscreenImageState extends State<_ZoomableFullscreenImage> {
  final TransformationController _transformationController =
      TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_handleTransformChanged);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_handleTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTapClose,
      onDoubleTapDown: (details) => _doubleTapDetails = details,
      onDoubleTap: _handleDoubleTap,
      onVerticalDragUpdate: widget.enableDismissDrag
          ? widget.onVerticalDragUpdate
          : null,
      onVerticalDragEnd: widget.enableDismissDrag
          ? widget.onVerticalDragEnd
          : null,
      child: SizedBox.expand(
        child: ClipRect(
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 1,
            maxScale: 4,
            panEnabled: true,
            boundaryMargin: EdgeInsets.all(widget.viewportSize.longestSide),
            constrained: true,
            clipBehavior: Clip.none,
            child: SizedBox(
              width: widget.viewportSize.width,
              height: widget.viewportSize.height,
              child: _ProgressiveNetworkImage(
                imageUrl: widget.imageUrl,
                thumbnailUrl: widget.thumbnailUrl,
                backgroundColor: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleTransformChanged() {
    widget.onScaleChanged(_transformationController.value.getMaxScaleOnAxis());
  }

  void _handleDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.01) {
      _transformationController.value = Matrix4.identity();
      widget.onScaleChanged(1);
      return;
    }

    final tapPosition = _doubleTapDetails?.localPosition;
    if (tapPosition == null) {
      _transformationController.value = Matrix4.diagonal3Values(2.5, 2.5, 1);
      widget.onScaleChanged(2.5);
      return;
    }

    const targetScale = 2.5;
    final translateX =
        (widget.viewportSize.width / 2) - tapPosition.dx * targetScale;
    final translateY =
        (widget.viewportSize.height / 2) - tapPosition.dy * targetScale;
    final zoomed = Matrix4.diagonal3Values(targetScale, targetScale, 1)
      ..setTranslationRaw(translateX, translateY, 0);
    _transformationController.value = zoomed;
    widget.onScaleChanged(targetScale);
  }
}

String _heroTagFor(String imageUrl, int index) => 'post-image-$index-$imageUrl';
