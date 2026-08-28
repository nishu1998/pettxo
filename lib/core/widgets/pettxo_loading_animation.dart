import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../constants/app_colors.dart';

const String kPettxoLoadingFinalAssetPath = 'assets/lottie/pettxo_loading.json';
const String kPettxoOfficialLogoAsset = 'assets/brand/pettxo_logo.svg';
const String kPettxoCatHeadAsset = 'assets/brand/pettxo_cat_head.png';
const Key kPettxoLoadingCatKey = Key('pettxo-loading-cat');
const Key kPettxoLoadingSonarKey = Key('pettxo-loading-sonar');

class PettxoLoadingAnimation extends StatefulWidget {
  const PettxoLoadingAnimation({
    super.key,
    this.controller,
    this.size = 184,
    this.message = 'FETCHING PUPS...',
    this.backgroundColor = AppColors.background,
    this.catSize = 50,
    this.catVerticalOffset = 14,
  });

  final AnimationController? controller;
  final double size;
  final String message;
  final Color backgroundColor;
  final double catSize;
  final double catVerticalOffset;

  @override
  State<PettxoLoadingAnimation> createState() => _PettxoLoadingAnimationState();
}

class _PettxoLoadingAnimationState extends State<PettxoLoadingAnimation>
    with SingleTickerProviderStateMixin {
  static const double _sourceWidth = 380;
  static const double _sourceHeight = 170;
  static const Duration _primaryDuration = Duration(milliseconds: 2600);
  static const Duration _sonarDuration = Duration(milliseconds: 2400);

  late final AnimationController _internalController;

  AnimationController get _controller => widget.controller ?? _internalController;

  double get _animationWidth => widget.size * 1.95;
  double get _animationHeight => _animationWidth * (_sourceHeight / _sourceWidth);

  @override
  void initState() {
    super.initState();
    _internalController = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage(kPettxoCatHeadAsset), context);
  }

  @override
  void dispose() {
    _internalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (reduceMotion) {
      if (controller.isAnimating) {
        controller.stop();
      }
      if (controller.value == 0) {
        controller.value = 0.72;
      }
    } else if (!controller.isAnimating) {
      controller
        ..duration = _primaryDuration
        ..repeat();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: widget.backgroundColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints.tightFor(
              width: _animationWidth,
              height: _animationHeight,
            ),
            child: RepaintBoundary(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scene = _buildScene(
                    Size(constraints.maxWidth, constraints.maxHeight),
                  );
                  final metric = scene.wavePath.computeMetrics().first;

                  return AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) {
                      final rawProgress = reduceMotion ? 0.72 : controller.value;
                      final rideProgress = Curves.easeInOut.transform(rawProgress);
                      final drawProgress = _drawProgress(rawProgress);
                      final trailOpacity = _trailOpacity(rawProgress);
                      final catOpacity = _catOpacity(rawProgress);
                      final sonarState = _sonarState(rawProgress, reduceMotion);

                      final tangent = metric.getTangentForOffset(
                        (metric.length * rideProgress).clamp(0.0, metric.length),
                      );
                      final position = tangent?.position ?? scene.wavePath.getBounds().center;
                      final vector = tangent?.vector ?? const Offset(1, 0);
                      final vectorLength = vector.distance == 0 ? 1.0 : vector.distance;
                      final direction = vector / vectorLength;
                      var normal = Offset(-direction.dy, direction.dx);
                      if (normal.dy > 0) {
                        normal = -normal;
                      }

                      final floatOffset = reduceMotion
                          ? 0.0
                          : math.sin(rawProgress * math.pi * 2) * 1.6;
                      final catOffset =
                          normal * widget.catVerticalOffset + Offset(0, floatOffset);
                      final tangentAngle = math.atan2(direction.dy, direction.dx);
                      final catAngle = (tangentAngle * 0.22).clamp(
                        -8 * math.pi / 180,
                        8 * math.pi / 180,
                      );
                      final catScale = reduceMotion
                          ? 1.0
                          : 1 + math.sin(rawProgress * math.pi * 2) * 0.02;

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _TrailPainter(
                                scene: scene,
                                drawProgress: drawProgress,
                                trailOpacity: trailOpacity,
                                stampProgress: rawProgress,
                              ),
                            ),
                          ),
                          Positioned(
                            left: scene.sonarRect.center.dx -
                                (scene.sonarRect.width * sonarState.scaleX) / 2,
                            top: scene.sonarRect.top,
                            child: IgnorePointer(
                              child: Opacity(
                                opacity: sonarState.opacity,
                                child: Transform.scale(
                                  scaleX: sonarState.scaleX,
                                  child: Container(
                                    key: kPettxoLoadingSonarKey,
                                    width: scene.sonarRect.width,
                                    height: scene.sonarRect.height,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        scene.sonarRect.height,
                                      ),
                                      gradient: RadialGradient(
                                        colors: [
                                          AppColors.primary.withValues(alpha: 0.20),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: position.dx + catOffset.dx - widget.catSize / 2,
                            top: position.dy + catOffset.dy - widget.catSize / 2,
                            child: IgnorePointer(
                              child: Opacity(
                                opacity: catOpacity,
                                child: Transform.rotate(
                                  angle: catAngle,
                                  child: Transform.scale(
                                    scale: catScale,
                                    child: Image.asset(
                                      kPettxoCatHeadAsset,
                                      key: kPettxoLoadingCatKey,
                                      width: widget.catSize,
                                      height: widget.catSize,
                                      filterQuality: FilterQuality.high,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: SvgPicture.asset(
              kPettxoOfficialLogoAsset,
              height: 88,
              fit: BoxFit.contain,
              semanticsLabel: 'Pettxo',
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: Text(
              widget.message.toUpperCase(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textGrey,
                fontSize: 12,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  _TrailScene _buildScene(Size size) {
    final scale = math.min(size.width / _sourceWidth, size.height / _sourceHeight);
    final dx = (size.width - (_sourceWidth * scale)) / 2;
    final dy = (size.height - (_sourceHeight * scale)) / 2;

    final wavePath = Path()
      ..moveTo(dx + 10 * scale, dy + 80 * scale)
      ..cubicTo(
        dx + 50 * scale,
        dy + 10 * scale,
        dx + 90 * scale,
        dy + 150 * scale,
        dx + 130 * scale,
        dy + 80 * scale,
      )
      ..cubicTo(
        dx + 170 * scale,
        dy + 10 * scale,
        dx + 210 * scale,
        dy + 10 * scale,
        dx + 250 * scale,
        dy + 80 * scale,
      )
      ..cubicTo(
        dx + 290 * scale,
        dy + 150 * scale,
        dx + 330 * scale,
        dy + 150 * scale,
        dx + 370 * scale,
        dy + 80 * scale,
      );

    return _TrailScene(
      wavePath: wavePath,
      sceneRect: Rect.fromLTWH(
        dx,
        dy,
        _sourceWidth * scale,
        _sourceHeight * scale,
      ),
      sonarRect: Rect.fromCenter(
        center: Offset(dx + 190 * scale, dy + 153 * scale),
        width: 220 * scale,
        height: 22 * scale,
      ),
      scale: scale,
    );
  }

  double _drawProgress(double progress) {
    if (progress <= 0.6) {
      return Curves.easeInOut.transform(progress / 0.6).clamp(0.0, 1.0);
    }
    return 1.0;
  }

  double _trailOpacity(double progress) {
    if (progress <= 0.85) {
      return 1.0;
    }
    return (1 - ((progress - 0.85) / 0.15)).clamp(0.0, 1.0);
  }

  double _catOpacity(double progress) {
    if (progress < 0.05) {
      return 0.0;
    }
    if (progress < 0.10) {
      return ((progress - 0.05) / 0.05).clamp(0.0, 1.0);
    }
    if (progress < 0.92) {
      return 1.0;
    }
    return (1 - ((progress - 0.92) / 0.08)).clamp(0.0, 1.0);
  }

  _SonarState _sonarState(double progress, bool reduceMotion) {
    if (reduceMotion) {
      return const _SonarState(scaleX: 0.85, opacity: 0.55);
    }
    final secondary = ((progress * _primaryDuration.inMilliseconds) /
            _sonarDuration.inMilliseconds) %
        1.0;
    final eased = 0.5 - 0.5 * math.cos(secondary * math.pi * 2);
    return _SonarState(
      scaleX: lerpDouble(0.6, 1.1, eased)!,
      opacity: lerpDouble(0.4, 0.9, eased)!,
    );
  }
}

class _TrailPainter extends CustomPainter {
  const _TrailPainter({
    required this.scene,
    required this.drawProgress,
    required this.trailOpacity,
    required this.stampProgress,
  });

  final _TrailScene scene;
  final double drawProgress;
  final double trailOpacity;
  final double stampProgress;

  static const List<_PawStamp> _stamps = [
    _PawStamp(Offset(40, 95), -18, 0.0),
    _PawStamp(Offset(80, 55), 12, 0.18),
    _PawStamp(Offset(120, 100), -10, 0.36),
    _PawStamp(Offset(165, 60), 18, 0.54),
    _PawStamp(Offset(210, 100), -14, 0.72),
    _PawStamp(Offset(255, 55), 14, 0.90),
    _PawStamp(Offset(300, 100), -16, 1.08),
    _PawStamp(Offset(340, 65), 10, 1.26),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    _paintGhostPath(canvas);
    _paintTrail(canvas);
    _paintPawStamps(canvas);
  }

  void _paintGhostPath(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0x21D83A10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * scene.scale
      ..strokeCap = StrokeCap.round;

    _drawDashedPath(
      canvas,
      scene.wavePath,
      paint,
      dashLength: 2 * scene.scale,
      gapLength: 6 * scene.scale,
    );
  }

  void _paintTrail(Canvas canvas) {
    final metric = scene.wavePath.computeMetrics().first;
    final visiblePath = metric.extractPath(0, metric.length * drawProgress);
    final trailPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFFF07040),
          Color(0xFFF05020),
          Color(0xFFD83A10),
        ],
      ).createShader(scene.sceneRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * scene.scale
      ..strokeCap = StrokeCap.round;

    final layerRect = scene.sceneRect.inflate(24 * scene.scale);
    canvas.saveLayer(layerRect, Paint());
    canvas.drawPath(visiblePath, trailPaint);
    if (trailOpacity < 1.0) {
      canvas.drawColor(
        Colors.white.withValues(alpha: 1 - trailOpacity),
        BlendMode.modulate,
      );
    }
    canvas.restore();
  }

  void _paintPawStamps(Canvas canvas) {
    for (final stamp in _stamps) {
      final state = _stampState(stampProgress, stamp.delaySeconds / 2.6);
      if (state.opacity <= 0) continue;

      final center = Offset(
        scene.sceneRect.left + stamp.center.dx * scene.scale,
        scene.sceneRect.top + stamp.center.dy * scene.scale,
      );

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(stamp.rotationDegrees * math.pi / 180);
      canvas.scale(state.scale * scene.scale);

      final paint = Paint()
        ..color = const Color(0xFFD83A10).withValues(alpha: state.opacity * 0.72);
      canvas.drawOval(Rect.fromCenter(center: const Offset(0, 3), width: 10, height: 8), paint);
      canvas.drawOval(Rect.fromCenter(center: const Offset(-5, -3), width: 3.6, height: 5.2), paint);
      canvas.drawOval(Rect.fromCenter(center: const Offset(-1.5, -5), width: 3.6, height: 5.2), paint);
      canvas.drawOval(Rect.fromCenter(center: const Offset(2, -5), width: 3.6, height: 5.2), paint);
      canvas.drawOval(Rect.fromCenter(center: const Offset(5.5, -3), width: 3.6, height: 5.2), paint);
      canvas.restore();
    }
  }

  _StampState _stampState(double progress, double delay) {
    var local = progress - delay;
    while (local < 0) {
      local += 1;
    }
    local = local % 1.0;

    if (local <= 0.10) {
      return const _StampState(opacity: 0, scale: 0.4);
    }
    if (local <= 0.25) {
      final t = (local - 0.10) / 0.15;
      return _StampState(
        opacity: Curves.easeOut.transform(t),
        scale: lerpDouble(0.4, 1.1, Curves.easeOut.transform(t))!,
      );
    }
    if (local <= 0.70) {
      final t = (local - 0.25) / 0.45;
      return _StampState(
        opacity: 1.0,
        scale: lerpDouble(1.1, 1.0, Curves.easeOut.transform(t))!,
      );
    }
    if (local <= 1.0) {
      final t = (local - 0.70) / 0.30;
      return _StampState(
        opacity: (1 - t).clamp(0.0, 1.0),
        scale: 1.0,
      );
    }
    return const _StampState(opacity: 0, scale: 1.0);
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dashLength,
    required double gapLength,
  }) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashLength, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrailPainter oldDelegate) {
    return oldDelegate.drawProgress != drawProgress ||
        oldDelegate.trailOpacity != trailOpacity ||
        oldDelegate.stampProgress != stampProgress ||
        oldDelegate.scene != scene;
  }
}

class _TrailScene {
  const _TrailScene({
    required this.wavePath,
    required this.sceneRect,
    required this.sonarRect,
    required this.scale,
  });

  final Path wavePath;
  final Rect sceneRect;
  final Rect sonarRect;
  final double scale;
}

class _SonarState {
  const _SonarState({
    required this.scaleX,
    required this.opacity,
  });

  final double scaleX;
  final double opacity;
}

class _PawStamp {
  const _PawStamp(this.center, this.rotationDegrees, this.delaySeconds);

  final Offset center;
  final double rotationDegrees;
  final double delaySeconds;
}

class _StampState {
  const _StampState({
    required this.opacity,
    required this.scale,
  });

  final double opacity;
  final double scale;
}
