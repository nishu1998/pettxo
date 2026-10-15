import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

const String kPettxoLoaderTransparentAsset =
    'assets/lottie/pettxo_loader_transparent.json';
const String kPettxoLoaderWhiteAsset = 'assets/lottie/pettxo_loader_white.json';
const Key kPettxoLoaderArtworkTransformKey = ValueKey<String>(
  'pettxo-loader-artwork-transform',
);

enum PettxoLoaderVariant { transparent, white }

enum PettxoLoaderPresentation { compact, regular, section, fullScreen }

abstract final class PettxoLoaderDimensions {
  static const double compact = 52;
  static const double regular = 124;
  static const double section = 152;
  static const double fullScreenMin = 176;
  static const double fullScreenMax = 200;
  static const double artworkScale = 1.18;
}

class PettxoLoader extends StatelessWidget {
  const PettxoLoader({
    super.key,
    this.variant = PettxoLoaderVariant.transparent,
    this.presentation = PettxoLoaderPresentation.regular,
    this.size,
    this.semanticLabel = 'Loading',
    this.message,
    this.controller,
  });

  const PettxoLoader.compact({
    super.key,
    this.variant = PettxoLoaderVariant.transparent,
    this.size,
    this.semanticLabel = 'Loading',
    this.message,
    this.controller,
  }) : presentation = PettxoLoaderPresentation.compact;

  const PettxoLoader.fullScreen({
    super.key,
    this.variant = PettxoLoaderVariant.transparent,
    this.size,
    this.semanticLabel = 'Loading',
    this.message,
    this.controller,
  }) : presentation = PettxoLoaderPresentation.fullScreen;

  const PettxoLoader.section({
    super.key,
    this.variant = PettxoLoaderVariant.transparent,
    this.size,
    this.semanticLabel = 'Loading',
    this.message,
    this.controller,
  }) : presentation = PettxoLoaderPresentation.section;

  final PettxoLoaderVariant variant;
  final PettxoLoaderPresentation presentation;
  final double? size;
  final String semanticLabel;
  final String? message;
  final AnimationController? controller;

  String get _assetPath => variant == PettxoLoaderVariant.white
      ? kPettxoLoaderWhiteAsset
      : kPettxoLoaderTransparentAsset;

  double _resolvedSize(BuildContext context) {
    if (size case final explicitSize?) return explicitSize;
    return switch (presentation) {
      PettxoLoaderPresentation.compact => PettxoLoaderDimensions.compact,
      PettxoLoaderPresentation.regular => PettxoLoaderDimensions.regular,
      PettxoLoaderPresentation.section => PettxoLoaderDimensions.section,
      PettxoLoaderPresentation.fullScreen =>
        (MediaQuery.sizeOf(context).shortestSide * 0.48).clamp(
          PettxoLoaderDimensions.fullScreenMin,
          PettxoLoaderDimensions.fullScreenMax,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final loaderSize = _resolvedSize(context);
    final normalizedMessage = message?.trim();

    return Semantics(
      label: semanticLabel,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(
              child: SizedBox.square(
                dimension: loaderSize,
                child: ClipRect(
                  child: Transform.scale(
                    key: kPettxoLoaderArtworkTransformKey,
                    scale: PettxoLoaderDimensions.artworkScale,
                    child: Lottie.asset(
                      _assetPath,
                      controller: reduceMotion ? null : controller,
                      animate: !reduceMotion,
                      repeat: !reduceMotion,
                      fit: BoxFit.contain,
                      frameRate: FrameRate.composition,
                    ),
                  ),
                ),
              ),
            ),
            if (normalizedMessage != null && normalizedMessage.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                normalizedMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
