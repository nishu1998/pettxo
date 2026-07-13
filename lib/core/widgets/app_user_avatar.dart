import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class AppUserAvatar extends StatelessWidget {
  static const double defaultRadius = 12;

  const AppUserAvatar({
    super.key,
    required this.size,
    required this.fallback,
    this.imageUrl = '',
    this.imageFile,
    this.useCachedImage = true,
    this.fadeInDuration,
    this.borderRadius = const BorderRadius.all(Radius.circular(defaultRadius)),
  });

  final double size;
  final Widget fallback;
  final String imageUrl;
  final File? imageFile;
  final bool useCachedImage;
  final Duration? fadeInDuration;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final normalizedImageUrl = imageUrl.trim();

    if (imageFile != null) {
      return _frame(
        Image.file(imageFile!, width: size, height: size, fit: BoxFit.cover),
      );
    }

    if (normalizedImageUrl.isNotEmpty) {
      if (useCachedImage) {
        return _frame(
          CachedNetworkImage(
            imageUrl: normalizedImageUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            fadeInDuration: fadeInDuration ?? Duration.zero,
            placeholder: (context, imageUrl) => fallback,
            errorWidget: (context, imageUrl, error) => fallback,
          ),
        );
      }

      return _frame(
        Image.network(
          normalizedImageUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        ),
      );
    }

    return _frame(fallback);
  }

  Widget _frame(Widget child) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}

class AppUserAvatarFallback extends StatelessWidget {
  const AppUserAvatarFallback({
    super.key,
    required this.initials,
    this.backgroundColor,
    this.gradient,
    this.textStyle,
    this.child,
  });

  final String initials;
  final Color? backgroundColor;
  final Gradient? gradient;
  final TextStyle? textStyle;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: backgroundColor, gradient: gradient),
      child: Center(child: child ?? Text(initials, style: textStyle)),
    );
  }
}
