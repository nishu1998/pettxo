import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'glass_surface.dart';

class AppGlassDialogFrame extends StatelessWidget {
  const AppGlassDialogFrame({
    super.key,
    required this.child,
    this.maxWidth = 420,
    this.padding = const EdgeInsets.all(22),
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: GlassSurface(
                borderRadius: borderRadius,
                blurSigma: 24,
                padding: padding,
                backgroundColor: isDark
                    ? const Color(0xCC1D1B1A)
                    : Colors.white.withValues(alpha: 0.82),
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? 0.16 : 0.58),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppGlassBottomSheetFrame extends StatelessWidget {
  const AppGlassBottomSheetFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 14, 18, 18),
    this.margin = const EdgeInsets.fromLTRB(12, 0, 12, 12),
    this.maxHeightFactor,
    this.includeTopSafeArea = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double? maxHeightFactor;
  final bool includeTopSafeArea;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxHeight = maxHeightFactor == null
        ? null
        : MediaQuery.sizeOf(context).height * maxHeightFactor!;

    return SafeArea(
      top: includeTopSafeArea,
      child: Padding(
        padding: margin,
        child: ConstrainedBox(
          constraints: maxHeight == null
              ? const BoxConstraints()
              : BoxConstraints(maxHeight: maxHeight),
          child: GlassSurface(
            padding: padding,
            borderRadius: borderRadius,
            blurSigma: 24,
            backgroundColor: isDark
                ? const Color(0xCC1D1B1A)
                : Colors.white.withValues(alpha: 0.82),
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.16 : 0.58),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
            child: child,
          ),
        ),
      ),
    );
  }
}
