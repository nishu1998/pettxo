import 'dart:ui';

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Presentation for the app-level location explanation prompt.
///
/// This dialog deliberately returns a decision only. The caller remains
/// responsible for invoking the platform permission request.
class LocationPermissionDialog {
  LocationPermissionDialog._();

  static Future<bool> show({required BuildContext context}) async {
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.38),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, _, _) => LocationPermissionDialogContent(
        onNotNow: () => Navigator.of(dialogContext).pop(false),
        onContinue: () => Navigator.of(dialogContext).pop(true),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final reduceMotion =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(
              begin: reduceMotion ? 1 : 0.96,
              end: 1,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
    return result ?? false;
  }
}

@visibleForTesting
class LocationPermissionDialogContent extends StatefulWidget {
  const LocationPermissionDialogContent({
    required this.onNotNow,
    required this.onContinue,
    super.key,
  });

  final VoidCallback onNotNow;
  final VoidCallback onContinue;

  @override
  State<LocationPermissionDialogContent> createState() =>
      _LocationPermissionDialogContentState();
}

class _LocationPermissionDialogContentState
    extends State<LocationPermissionDialogContent> {
  bool _hasActed = false;

  void _act(VoidCallback callback) {
    if (_hasActed) return;
    setState(() => _hasActed = true);
    callback();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.04),
          child: SafeArea(
            minimum: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, viewportConstraints) {
                final maxHeightFactor = viewportConstraints.maxHeight >= 650
                    ? 0.82
                    : 0.94;
                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 430,
                      maxHeight:
                          viewportConstraints.maxHeight * maxHeightFactor,
                    ),
                    child: DecoratedBox(
                      key: const Key('location-permission-dialog-surface'),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF59220F,
                            ).withValues(alpha: 0.22),
                            blurRadius: 40,
                            offset: const Offset(0, 20),
                          ),
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.34),
                            blurRadius: 18,
                            offset: const Offset(0, -5),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withValues(alpha: 0.88),
                                  const Color(
                                    0xFFFFF2E9,
                                  ).withValues(alpha: 0.82),
                                  const Color(
                                    0xFFFFE2D2,
                                  ).withValues(alpha: 0.76),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.75),
                                width: 1.4,
                              ),
                            ),
                            child: Stack(
                              children: [
                                Positioned(
                                  right: -14,
                                  top: 142,
                                  child: Icon(
                                    Icons.pets_rounded,
                                    size: 66,
                                    color: AppColors.primary.withValues(
                                      alpha: 0.1,
                                    ),
                                  ),
                                ),
                                SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                    18,
                                    12,
                                    18,
                                    18,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Semantics(
                                        image: true,
                                        label:
                                            'Location pin on a map with paw prints',
                                        child: const SizedBox(
                                          width: 180,
                                          height: 125,
                                          child: CustomPaint(
                                            painter:
                                                _NearbyIllustrationPainter(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Discover what is\nnearby',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium
                                            ?.copyWith(
                                              color: const Color(0xFF19131B),
                                              fontSize: 24,
                                              height: 1.12,
                                              letterSpacing: -0.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'Allow location access to discover nearby posts, '
                                        'find pet services around you, and add an '
                                        'approximate location to your posts.',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.copyWith(
                                              color: const Color(0xFF625A64),
                                              fontSize: 14,
                                              height: 1.4,
                                              fontWeight: FontWeight.w500,
                                            ),
                                      ),
                                      const SizedBox(height: 14),
                                      const _PrivacyPanel(),
                                      const SizedBox(height: 16),
                                      _ActionButtons(
                                        enabled: !_hasActed,
                                        onNotNow: () => _act(widget.onNotNow),
                                        onContinue: () =>
                                            _act(widget.onContinue),
                                      ),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  top: 12,
                                  right: 12,
                                  child: _GlassIconButton(
                                    semanticLabel: 'Close location prompt',
                                    onPressed: _hasActed
                                        ? null
                                        : () => _act(widget.onNotNow),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.semanticLabel, this.onPressed});

  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: InkWell(
        key: const Key('location-permission-close'),
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Ink(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.5),
            border: Border.all(color: Colors.white.withValues(alpha: 0.88)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(
            Icons.close_rounded,
            size: 26,
            color: Color(0xFF27222A),
          ),
        ),
      ),
    );
  }
}

class _PrivacyPanel extends StatelessWidget {
  const _PrivacyPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.82)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD9BF).withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: AppColors.primary,
              size: 25,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your privacy matters',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF221A22),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'We use your approximate location for nearby discovery. '
                  'You can change this anytime in your device settings.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6D636A),
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.enabled,
    required this.onNotNow,
    required this.onContinue,
  });

  final bool enabled;
  final VoidCallback onNotNow;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final scaledHorizontalMinimum = 286 * textScale.clamp(1.0, 1.45);
        final stacked =
            constraints.maxWidth < scaledHorizontalMinimum || textScale > 1.45;
        final notNow = _LocationActionButton(
          key: const Key('location-permission-not-now'),
          label: 'Not now',
          onPressed: enabled ? onNotNow : null,
        );
        final continueButton = _LocationActionButton(
          key: const Key('location-permission-continue'),
          label: 'Continue',
          icon: Icons.navigation_rounded,
          trailingIcon: Icons.chevron_right_rounded,
          filled: true,
          onPressed: enabled ? onContinue : null,
        );

        if (stacked) {
          return Column(
            children: [
              SizedBox(width: double.infinity, child: continueButton),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: notNow),
            ],
          );
        }
        return SizedBox(
          height: 58,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 2, child: notNow),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: continueButton),
            ],
          ),
        );
      },
    );
  }
}

class _LocationActionButton extends StatelessWidget {
  const _LocationActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.filled = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? Colors.white : AppColors.primary;
    return Semantics(
      button: true,
      child: Opacity(
        opacity: onPressed == null ? 0.65 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(24),
            child: Ink(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                gradient: filled ? AppColors.brandGradient : null,
                color: filled ? null : Colors.white.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: filled
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.88),
                ),
                boxShadow: [
                  BoxShadow(
                    color: filled
                        ? AppColors.primary.withValues(alpha: 0.24)
                        : Colors.black.withValues(alpha: 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: foreground, size: 23),
                    const SizedBox(width: 9),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (trailingIcon != null) ...[
                    const SizedBox(width: 5),
                    Icon(trailingIcon, color: foreground, size: 26),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NearbyIllustrationPainter extends CustomPainter {
  const _NearbyIllustrationPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 190, size.height / 132);
    const designSize = Size(190, 132);
    final center = Offset(designSize.width / 2, 48);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (var radius = 36.0; radius <= 66; radius += 15) {
      ringPaint.color = Colors.white.withValues(alpha: 0.72 - radius / 220);
      canvas.drawCircle(center, radius, ringPaint);
    }

    final mapShadow = Paint()
      ..color = const Color(0xFF7E3215).withValues(alpha: 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    final map = Path()
      ..moveTo(27, 89)
      ..lineTo(74, 74)
      ..lineTo(113, 87)
      ..lineTo(163, 72)
      ..lineTo(164, 109)
      ..lineTo(114, 125)
      ..lineTo(74, 112)
      ..lineTo(27, 125)
      ..close();
    canvas.drawPath(map.shift(const Offset(0, 5)), mapShadow);
    canvas.drawPath(
      map,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE5CF), Color(0xFFFFC9A7)],
        ).createShader(Rect.fromLTWH(27, 72, 137, 53)),
    );
    final foldPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.52)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(const Offset(74, 74), const Offset(74, 112), foldPaint);
    canvas.drawLine(const Offset(113, 87), const Offset(114, 125), foldPaint);

    final patchPaint = Paint()..color = const Color(0xFF77B94B);
    canvas.drawOval(const Rect.fromLTWH(42, 94, 25, 11), patchPaint);
    canvas.drawOval(const Rect.fromLTWH(119, 96, 30, 13), patchPaint);
    canvas.drawOval(const Rect.fromLTWH(87, 113, 23, 9), patchPaint);

    final pin = Path()
      ..moveTo(center.dx, 105)
      ..cubicTo(center.dx - 8, 91, center.dx - 31, 68, center.dx - 31, 43)
      ..cubicTo(center.dx - 31, 20, center.dx - 17, 7, center.dx, 7)
      ..cubicTo(center.dx + 17, 7, center.dx + 31, 20, center.dx + 31, 43)
      ..cubicTo(center.dx + 31, 68, center.dx + 8, 91, center.dx, 105)
      ..close();
    canvas.drawPath(
      pin.shift(const Offset(0, 4)),
      Paint()
        ..color = const Color(0xFF8A2B0A).withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawPath(
      pin,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8D46), Color(0xFFF34B1C)],
        ).createShader(Rect.fromCircle(center: center, radius: 45)),
    );
    canvas.drawCircle(
      Offset(center.dx, 42),
      11,
      Paint()..color = const Color(0xFFFFE8DC),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(center.dx - 8, 30), width: 9, height: 25),
      Paint()..color = Colors.white.withValues(alpha: 0.26),
    );

    _paintPaw(canvas, const Offset(28, 61), 0.72);
    _paintPaw(canvas, const Offset(165, 47), 0.62);
    canvas.restore();
  }

  void _paintPaw(Canvas canvas, Offset center, double scale) {
    final paint = Paint()..color = AppColors.primary.withValues(alpha: 0.88);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.drawOval(const Rect.fromLTWH(-9, 2, 18, 15), paint);
    canvas.drawOval(const Rect.fromLTWH(-13, -8, 7, 9), paint);
    canvas.drawOval(const Rect.fromLTWH(-4, -13, 7, 9), paint);
    canvas.drawOval(const Rect.fromLTWH(6, -8, 7, 9), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NearbyIllustrationPainter oldDelegate) => false;
}
