import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/fullscreen_image_viewer.dart';
import '../../data/repositories/chat_media_repository.dart';

class PrivateChatImage extends StatefulWidget {
  const PrivateChatImage({
    super.key,
    required this.storagePath,
    required this.aspectRatio,
    this.fit = BoxFit.contain,
    this.openFullscreenOnTap = true,
  });

  final String storagePath;
  final double aspectRatio;
  final BoxFit fit;
  final bool openFullscreenOnTap;

  @override
  State<PrivateChatImage> createState() => _PrivateChatImageState();
}

class _PrivateChatImageState extends State<PrivateChatImage> {
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = PrivateChatImageCache.instance.load(widget.storagePath);
  }

  @override
  void didUpdateWidget(covariant PrivateChatImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storagePath != widget.storagePath) {
      _bytes = PrivateChatImageCache.instance.load(widget.storagePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _error(context);
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return const ColoredBox(
            color: Color(0xFFF2EEE9),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: AppColors.primary,
              ),
            ),
          );
        }
        final provider = MemoryImage(bytes);
        final image = Image(
          image: provider,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _error(context),
        );
        if (!widget.openFullscreenOnTap) return image;
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => FullscreenImageViewer(
                imageProvider: provider,
                aspectRatio: widget.aspectRatio,
                heroTag: widget.storagePath,
              ),
            ),
          ),
          child: Hero(tag: widget.storagePath, child: image),
        );
      },
    );
  }

  Widget _error(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFFF2EA),
      child: Center(
        child: TextButton.icon(
          onPressed: () {
            PrivateChatImageCache.instance.evict(widget.storagePath);
            setState(() {
              _bytes = PrivateChatImageCache.instance.load(widget.storagePath);
            });
          },
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      ),
    );
  }
}
