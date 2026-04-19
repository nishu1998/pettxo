import 'dart:ui';

import 'package:flutter/material.dart';

/// Shared frosted-glass surface for floating bars and overlays.
///
/// The blur is clipped to the rounded outline so content can render behind the
/// surface while still keeping icons and labels readable.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final Border? border;
  final List<BoxShadow>? boxShadow;
  final double blurSigma;

  const GlassSurface({
    super.key,
    required this.child,
    required this.borderRadius,
    this.padding = EdgeInsets.zero,
    this.backgroundColor = const Color.fromRGBO(255, 255, 255, 1.95),
    this.border,
    this.boxShadow,
    this.blurSigma = 20,
  });

  @override
  Widget build(BuildContext context) {
    final Border effectiveBorder =
        border ??
        Border.all(
          color: Colors.white.withValues(alpha: 0.30),
          width: 1,
        );

    final List<BoxShadow> effectiveBoxShadow =
        boxShadow ??
        [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ];

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: effectiveBoxShadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: borderRadius,
              border: effectiveBorder,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
