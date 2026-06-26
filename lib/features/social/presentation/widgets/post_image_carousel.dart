import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

class PostImageCarousel extends StatefulWidget {
  final List<String> imageUrls;
  final List<String> thumbnailUrls;
  final double aspectRatio;
  final BorderRadius borderRadius;

  const PostImageCarousel({
    super.key,
    required this.imageUrls,
    required this.thumbnailUrls,
    required this.aspectRatio,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
  });

  @override
  State<PostImageCarousel> createState() => _PostImageCarouselState();
}

class _PostImageCarouselState extends State<PostImageCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;

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
                return _ProgressiveNetworkImage(
                  key: ValueKey('${widget.imageUrls[index]}-$index'),
                  imageUrl: widget.imageUrls[index],
                  thumbnailUrl: index < widget.thumbnailUrls.length
                      ? widget.thumbnailUrls[index]
                      : widget.imageUrls[index],
                );
              },
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
}

class _ProgressiveNetworkImage extends StatelessWidget {
  final String imageUrl;
  final String thumbnailUrl;

  const _ProgressiveNetworkImage({
    super.key,
    required this.imageUrl,
    required this.thumbnailUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFCF8F5),
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
          errorWidget: (context, nestedUrl, error) => const _ImageErrorFallback(),
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
