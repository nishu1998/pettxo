import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/services_tour_preference_service.dart';

enum ServicesTourExitReason { skipped, completed, cancelled }

class ServicesTourTargets {
  const ServicesTourTargets({
    required this.filters,
    required this.search,
    required this.firstCard,
    required this.contentFallback,
  });

  final GlobalKey filters;
  final GlobalKey search;
  final GlobalKey firstCard;
  final GlobalKey contentFallback;
}

typedef ServicesTourBeforeShow = Future<void> Function();
typedef ServicesTourPrepareStep = Future<void> Function(int stepIndex);

class ServicesGuidedTourController {
  ServicesGuidedTourController({ServicesTourPreferenceService? preferences})
    : _preferences = preferences ?? ServicesTourPreferenceService();

  final ServicesTourPreferenceService _preferences;
  final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);

  OverlayEntry? _entry;
  Completer<ServicesTourExitReason?>? _sessionCompleter;
  bool _isStarting = false;
  bool _isDisposed = false;
  int _generation = 0;
  String _activeUid = '';

  Future<ServicesTourExitReason?> start({
    required BuildContext context,
    required String uid,
    required ServicesTourTargets targets,
    ServicesTourBeforeShow? beforeShow,
    ServicesTourPrepareStep? prepareStep,
  }) async {
    final normalizedUid = uid.trim();
    if (_isDisposed || _isStarting || _entry != null || normalizedUid.isEmpty) {
      return null;
    }

    _isStarting = true;
    final generation = ++_generation;
    Future<ServicesTourExitReason?>? sessionFuture;
    try {
      try {
        if (await _preferences.isCompleted(normalizedUid)) return null;
      } catch (_) {
        return null;
      }
      if (!context.mounted || !_canContinue(generation)) return null;

      await beforeShow?.call();
      if (!context.mounted || !_canContinue(generation)) return null;

      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return null;
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) return null;

      final completer = Completer<ServicesTourExitReason?>();
      _sessionCompleter = completer;
      _activeUid = normalizedUid;
      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (overlayContext) => ServicesGuidedTourOverlay(
          targets: targets,
          onExit: _finish,
          prepareStep: prepareStep,
        ),
      );
      _entry = entry;
      overlay.insert(entry);
      isActive.value = true;
      sessionFuture = completer.future;
    } finally {
      _isStarting = false;
    }
    return sessionFuture;
  }

  bool _canContinue(int generation) {
    return !_isDisposed && generation == _generation && _entry == null;
  }

  Future<void> _finish(ServicesTourExitReason reason) async {
    final uid = _activeUid;
    final completer = _takeSessionCompleter();
    final shouldPersist =
        reason == ServicesTourExitReason.skipped ||
        reason == ServicesTourExitReason.completed;
    _removeEntry();
    if (shouldPersist) {
      try {
        await _preferences.markCompleted(uid);
      } catch (_) {
        debugPrint('Services guided-tour completion could not be persisted.');
      }
    }
    _completeSession(completer, reason);
  }

  void cancel() {
    _generation += 1;
    final completer = _takeSessionCompleter();
    _removeEntry();
    _completeSession(completer, ServicesTourExitReason.cancelled);
  }

  Completer<ServicesTourExitReason?>? _takeSessionCompleter() {
    final completer = _sessionCompleter;
    _sessionCompleter = null;
    return completer;
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
    _activeUid = '';
    if (isActive.value) isActive.value = false;
  }

  void _completeSession(
    Completer<ServicesTourExitReason?>? completer,
    ServicesTourExitReason? reason,
  ) {
    if (completer != null && !completer.isCompleted) {
      completer.complete(reason);
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    cancel();
    isActive.dispose();
  }
}

class ServicesGuidedTourOverlay extends StatefulWidget {
  const ServicesGuidedTourOverlay({
    super.key,
    required this.targets,
    required this.onExit,
    this.prepareStep,
  });

  final ServicesTourTargets targets;
  final Future<void> Function(ServicesTourExitReason reason) onExit;
  final ServicesTourPrepareStep? prepareStep;

  @override
  State<ServicesGuidedTourOverlay> createState() =>
      _ServicesGuidedTourOverlayState();
}

class _ServicesGuidedTourOverlayState extends State<ServicesGuidedTourOverlay> {
  static const Duration _transitionDuration = Duration(milliseconds: 300);
  final List<GlobalKey> _tooltipKeys = List<GlobalKey>.generate(
    3,
    (_) => GlobalKey(),
  );
  final GlobalKey _controlPanelKey = GlobalKey();
  final Map<int, double> _tooltipHeights = <int, double>{};
  double? _controlPanelHeight;
  int _stepIndex = 0;
  bool _exitInFlight = false;
  bool _transitionInFlight = false;

  static const List<_ServicesTourStepContent>
  _steps = <_ServicesTourStepContent>[
    _ServicesTourStepContent(
      title: 'Animal & Service Types',
      description:
          'Filter services by animal type and service category to find the most relevant providers for your pet.',
      semanticsLabel: 'Services filters tour step',
    ),
    _ServicesTourStepContent(
      title: 'Search Services',
      description:
          'Search services, providers, or areas to quickly find the right service near you.',
      semanticsLabel: 'Services search tour step',
    ),
    _ServicesTourStepContent(
      title: 'Service Cards',
      description:
          'Browse service cards to view provider details, pet type, location, and pricing before booking.',
      semanticsLabel: 'Services cards tour step',
    ),
  ];

  Future<void> _exit(ServicesTourExitReason reason) async {
    if (_exitInFlight) return;
    _exitInFlight = true;
    await widget.onExit(reason);
  }

  Future<void> _next() async {
    if (_transitionInFlight || _exitInFlight) return;
    if (_stepIndex >= _steps.length - 1) {
      unawaited(_exit(ServicesTourExitReason.completed));
      return;
    }
    _transitionInFlight = true;
    final nextStep = _stepIndex + 1;
    try {
      await widget.prepareStep?.call(nextStep);
      if (!mounted) return;
      setState(() => _stepIndex = nextStep);
      await WidgetsBinding.instance.endOfFrame;
    } finally {
      _transitionInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final safePadding = MediaQuery.paddingOf(context);
          final targetRect = _targetRect(size, safePadding);
          final highlightRect = _expandedTargetRect(targetRect, size);
          final compact = size.height < 650 || size.width < 350;
          final textScale = (MediaQuery.textScalerOf(context).scale(14) / 14)
              .clamp(1.0, 1.6);
          final estimatedPanelHeight =
              (compact ? 174.0 : 184.0) + ((textScale - 1) * 52);
          final panelHeight = _controlPanelHeight ?? estimatedPanelHeight;
          final panelBottom = math.max(
            safePadding.bottom + (compact ? 76 : 84),
            compact ? 80.0 : 88.0,
          );
          final panelTop = size.height - panelBottom - panelHeight;
          final tooltipRect = _tooltipRect(
            size: size,
            safePadding: safePadding,
            target: highlightRect,
            panelTop: panelTop,
            compact: compact,
            measuredHeight: _tooltipHeights[_stepIndex],
          );
          final renderedStep = _stepIndex;
          final step = _steps[_stepIndex];
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _captureMeasurements(renderedStep);
          });

          return Semantics(
            scopesRoute: true,
            explicitChildNodes: true,
            label: step.semanticsLabel,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ServicesTourScrimPainter(
                      highlightRect: highlightRect,
                      cornerRadius: _stepIndex == 2 ? 24 : 22,
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: highlightRect,
                  child: const IgnorePointer(
                    child: SizedBox(
                      key: ValueKey<String>('services-tour-highlight-bounds'),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ServicesTourArrowPainter(
                        tooltipRect: tooltipRect,
                        targetRect: highlightRect,
                        stepIndex: _stepIndex,
                      ),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  key: const ValueKey<String>('services-tour-tooltip-position'),
                  duration: _transitionDuration,
                  curve: Curves.easeInOutCubic,
                  left: tooltipRect.left,
                  top: tooltipRect.top,
                  width: tooltipRect.width,
                  onEnd: () => _captureMeasurements(renderedStep),
                  child: Align(
                    alignment: Alignment.topLeft,
                    widthFactor: 1,
                    heightFactor: 1,
                    child: AnimatedSwitcher(
                      duration: _transitionDuration,
                      child: _ServicesTourTooltip(
                        key: _tooltipKeys[_stepIndex],
                        step: step,
                        compact: compact,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: compact ? 10 : 16,
                  right: compact ? 10 : 16,
                  bottom: panelBottom,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: _ServicesTourControlPanel(
                        key: _controlPanelKey,
                        stepIndex: _stepIndex,
                        step: step,
                        compact: compact,
                        onSkip: () =>
                            unawaited(_exit(ServicesTourExitReason.skipped)),
                        onNext: () => unawaited(_next()),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _captureMeasurements(int stepIndex) {
    if (!mounted || stepIndex != _stepIndex) return;
    final tooltipObject = _tooltipKeys[stepIndex].currentContext
        ?.findRenderObject();
    final panelObject = _controlPanelKey.currentContext?.findRenderObject();
    final tooltipHeight = tooltipObject is RenderBox && tooltipObject.hasSize
        ? tooltipObject.size.height
        : null;
    final panelHeight = panelObject is RenderBox && panelObject.hasSize
        ? panelObject.size.height
        : null;
    final tooltipChanged =
        tooltipHeight != null &&
        ((_tooltipHeights[stepIndex] ?? -1) - tooltipHeight).abs() >= 0.5;
    final panelChanged =
        panelHeight != null &&
        ((_controlPanelHeight ?? -1) - panelHeight).abs() >= 0.5;
    if (!tooltipChanged && !panelChanged) return;
    setState(() {
      if (tooltipChanged) _tooltipHeights[stepIndex] = tooltipHeight;
      if (panelChanged) _controlPanelHeight = panelHeight;
    });
  }

  Rect _targetRect(Size size, EdgeInsets safePadding) {
    final key = switch (_stepIndex) {
      0 => widget.targets.filters,
      1 => widget.targets.search,
      _ => widget.targets.firstCard,
    };
    final measured = _rectForKey(key);
    if (measured != null) return measured;
    if (_stepIndex == 2) {
      final fallback = _rectForKey(widget.targets.contentFallback);
      if (fallback != null) {
        return Rect.fromLTWH(
          fallback.left,
          fallback.top,
          fallback.width,
          math.min(210, math.max(110, size.height * 0.25)),
        );
      }
    }
    return switch (_stepIndex) {
      0 => Rect.fromLTWH(18, safePadding.top + 126, size.width - 36, 116),
      1 => Rect.fromLTWH(18, safePadding.top + 73, size.width - 36, 44),
      _ => Rect.fromLTWH(18, safePadding.top + 260, size.width - 36, 180),
    };
  }

  Rect? _rectForKey(GlobalKey key) {
    final object = key.currentContext?.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return null;
    }
    final rect = object.localToGlobal(Offset.zero) & object.size;
    return rect.width > 0 && rect.height > 0 ? rect : null;
  }

  Rect _expandedTargetRect(Rect target, Size size) {
    final padding = _stepIndex == 2 ? 5.0 : 7.0;
    return Rect.fromLTRB(
      math.max(2, target.left - padding),
      math.max(2, target.top - padding),
      math.min(size.width - 2, target.right + padding),
      math.min(size.height - 2, target.bottom + padding),
    );
  }

  Rect _tooltipRect({
    required Size size,
    required EdgeInsets safePadding,
    required Rect target,
    required double panelTop,
    required bool compact,
    required double? measuredHeight,
  }) {
    final margin = compact ? 12.0 : 18.0;
    final usableWidth = size.width - margin * 2;
    final textScale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
      1.0,
      1.6,
    );
    final width = switch (_stepIndex) {
      0 => (usableWidth * 0.94).clamp(
        math.min(230.0, usableWidth),
        math.min(330.0, usableWidth),
      ),
      1 => (usableWidth * 0.72).clamp(
        math.min(220.0, usableWidth),
        math.min(286.0, usableWidth),
      ),
      _ => (usableWidth * 0.60).clamp(
        math.min(205.0, usableWidth),
        math.min(250.0, usableWidth),
      ),
    }.toDouble();
    final estimatedHeight = (compact ? 100.0 : 108.0) + ((textScale - 1) * 54);
    final height = measuredHeight ?? estimatedHeight;
    double left;
    double top;
    if (_stepIndex == 2) {
      left = size.width - width - margin;
      top = target.top - height - 20;
    } else {
      left = _stepIndex == 1 ? margin + 18 : target.left + 1;
      top = target.bottom + (_stepIndex == 0 ? 14 : 22);
    }
    final minimumTop = safePadding.top + 8;
    final maximumTop = math.max(minimumTop, panelTop - height - 16);
    return Rect.fromLTWH(
      left.clamp(margin, size.width - width - margin).toDouble(),
      top.clamp(minimumTop, maximumTop).toDouble(),
      width,
      height,
    );
  }
}

class _ServicesTourStepContent {
  const _ServicesTourStepContent({
    required this.title,
    required this.description,
    required this.semanticsLabel,
  });

  final String title;
  final String description;
  final String semanticsLabel;
}

class _ServicesTourTooltip extends StatelessWidget {
  const _ServicesTourTooltip({
    super.key,
    required this.step,
    required this.compact,
  });

  final _ServicesTourStepContent step;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _ServicesTourGlassCard(
      key: const ValueKey<String>('services-tour-tooltip-card'),
      borderRadius: compact ? 20 : 22,
      backgroundOpacity: 0.72,
      blurSigma: 18,
      glowOpacity: 0.34,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 9 : 13,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step.title,
            style: TextStyle(
              color: AppColors.primary,
              fontSize: compact ? 15 : 18.5,
              fontWeight: FontWeight.w800,
              height: 1.08,
            ),
          ),
          SizedBox(height: compact ? 4 : 6),
          Text(
            step.description,
            style: TextStyle(
              color: const Color(0xFF4F535E),
              fontSize: compact ? 10 : 13,
              fontWeight: FontWeight.w500,
              height: 1.24,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServicesTourControlPanel extends StatelessWidget {
  const _ServicesTourControlPanel({
    super.key,
    required this.stepIndex,
    required this.step,
    required this.compact,
    required this.onSkip,
    required this.onNext,
  });

  final int stepIndex;
  final _ServicesTourStepContent step;
  final bool compact;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _ServicesTourGlassCard(
      key: const ValueKey<String>('services-tour-control-panel'),
      borderRadius: compact ? 24 : 28,
      backgroundOpacity: 0.76,
      blurSigma: 22,
      glowOpacity: 0.32,
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 18,
        compact ? 8 : 12,
        compact ? 12 : 18,
        compact ? 10 : 14,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(3, (index) {
              final selected = index == stepIndex;
              return AnimatedContainer(
                key: ValueKey<String>('services-tour-progress-$index'),
                duration: const Duration(milliseconds: 300),
                width: selected ? 34 : 22,
                height: compact ? 4 : 5,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary
                      : Colors.white.withValues(alpha: 0.66),
                  borderRadius: BorderRadius.circular(99),
                ),
              );
            }),
          ),
          SizedBox(height: compact ? 6 : 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Row(
              key: ValueKey<int>(stepIndex),
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: compact ? 38 : 48,
                  height: compact ? 38 : 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6A35), Color(0xFFFF3D16)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.30),
                        blurRadius: 13,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Text(
                    '${stepIndex + 1}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 18 : 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox(width: compact ? 9 : 13),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: TextStyle(
                          color: AppColors.textDark,
                          fontSize: compact ? 14.5 : 18,
                          fontWeight: FontWeight.w800,
                          height: 1.08,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        step.description,
                        style: TextStyle(
                          color: const Color(0xFF5D626D),
                          fontSize: compact ? 10 : 12.5,
                          fontWeight: FontWeight.w500,
                          height: compact ? 1.08 : 1.18,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 6 : 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey<String>('services-tour-skip'),
                  onPressed: onSkip,
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size(0, compact ? 42 : 48),
                    foregroundColor: const Color(0xFF686B72),
                    backgroundColor: Colors.white.withValues(alpha: 0.24),
                    side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.16),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 13 : 15,
                    ),
                  ),
                ),
              ),
              SizedBox(width: compact ? 9 : 11),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6A35), Color(0xFFFF3D16)],
                    ),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.22),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: TextButton(
                    key: const ValueKey<String>('services-tour-next'),
                    onPressed: onNext,
                    style: TextButton.styleFrom(
                      minimumSize: Size(0, compact ? 42 : 48),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          stepIndex == 2 ? 'Got it' : 'Next',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: compact ? 13.5 : 15,
                          ),
                        ),
                        if (stepIndex != 2) ...[
                          const SizedBox(width: 5),
                          const Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ServicesTourGlassCard extends StatelessWidget {
  const _ServicesTourGlassCard({
    super.key,
    required this.borderRadius,
    required this.backgroundOpacity,
    required this.blurSigma,
    required this.glowOpacity,
    required this.padding,
    required this.child,
  });

  final double borderRadius;
  final double backgroundOpacity;
  final double blurSigma;
  final double glowOpacity;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: glowOpacity),
            blurRadius: 30,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: AppColors.primary.withValues(alpha: glowOpacity * 0.45),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: backgroundOpacity),
                  const Color(
                    0xFFFFF3ED,
                  ).withValues(alpha: math.max(0, backgroundOpacity - 0.07)),
                ],
              ),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.76),
                width: 1.2,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ServicesTourScrimPainter extends CustomPainter {
  const _ServicesTourScrimPainter({
    required this.highlightRect,
    required this.cornerRadius,
  });

  final Rect highlightRect;
  final double cornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final fullPath = Path()..addRect(Offset.zero & size);
    final highlight = RRect.fromRectAndRadius(
      highlightRect,
      Radius.circular(cornerRadius),
    );
    final scrimPath = Path.combine(
      PathOperation.difference,
      fullPath,
      Path()..addRRect(highlight),
    );
    canvas.drawPath(
      scrimPath,
      Paint()..color = Colors.black.withValues(alpha: 0.70),
    );
    canvas.drawRRect(
      highlight,
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.62)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
    );
    canvas.drawRRect(
      highlight,
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      highlight,
      Paint()
        ..color = const Color(0xFFFFA06F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
  }

  @override
  bool shouldRepaint(_ServicesTourScrimPainter oldDelegate) {
    return oldDelegate.highlightRect != highlightRect ||
        oldDelegate.cornerRadius != cornerRadius;
  }
}

class _ServicesTourArrowPainter extends CustomPainter {
  const _ServicesTourArrowPainter({
    required this.tooltipRect,
    required this.targetRect,
    required this.stepIndex,
  });

  final Rect tooltipRect;
  final Rect targetRect;
  final int stepIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = calculateServicesTourArrowGeometry(
      stepIndex: stepIndex,
      tooltipRect: tooltipRect,
      targetRect: targetRect,
    );
    final path = Path()
      ..moveTo(geometry.start.dx, geometry.start.dy)
      ..cubicTo(
        geometry.control1.dx,
        geometry.control1.dy,
        geometry.control2.dx,
        geometry.control2.dy,
        geometry.end.dx,
        geometry.end.dy,
      );
    final outline = Paint()
      ..color = Colors.white.withValues(alpha: 0.94)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final orange = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, outline);
    canvas.drawPath(path, orange);
    final head = calculateServicesTourArrowHead(geometry, arrowLength: 8);
    for (final paint in <Paint>[outline, orange]) {
      canvas.drawLine(geometry.end, head.firstWing, paint);
      canvas.drawLine(geometry.end, head.secondWing, paint);
    }
  }

  @override
  bool shouldRepaint(_ServicesTourArrowPainter oldDelegate) {
    return oldDelegate.tooltipRect != tooltipRect ||
        oldDelegate.targetRect != targetRect ||
        oldDelegate.stepIndex != stepIndex;
  }
}

ServicesTourArrowGeometry calculateServicesTourArrowGeometry({
  required int stepIndex,
  required Rect tooltipRect,
  required Rect targetRect,
}) {
  const targetGap = 8.0;
  if (stepIndex == 2) {
    final start = Offset(
      tooltipRect.left - 1,
      tooltipRect.bottom - tooltipRect.height * 0.30,
    );
    final end = Offset(
      math.min(targetRect.left + targetRect.width * 0.38, start.dx - 10),
      targetRect.top - targetGap,
    );
    return ServicesTourArrowGeometry(
      start: start,
      control1: Offset(start.dx - 18, start.dy + 5),
      control2: Offset(end.dx + 10, end.dy - 16),
      end: end,
    );
  }

  final start = Offset(
    tooltipRect.left - 2,
    tooltipRect.top + tooltipRect.height * (stepIndex == 0 ? 0.34 : 0.24),
  );
  final end = Offset(
    targetRect.left + (stepIndex == 0 ? -4 : 12),
    targetRect.bottom + targetGap,
  );
  return ServicesTourArrowGeometry(
    start: start,
    control1: Offset(start.dx - 18, start.dy - 2),
    control2: Offset(end.dx - 10, end.dy + 14),
    end: end,
  );
}

ServicesTourArrowHead calculateServicesTourArrowHead(
  ServicesTourArrowGeometry geometry, {
  double arrowLength = 8,
}) {
  final angle = math.atan2(
    geometry.end.dy - geometry.control2.dy,
    geometry.end.dx - geometry.control2.dx,
  );
  return ServicesTourArrowHead(
    firstWing:
        geometry.end -
        Offset(
          math.cos(angle - 0.65) * arrowLength,
          math.sin(angle - 0.65) * arrowLength,
        ),
    secondWing:
        geometry.end -
        Offset(
          math.cos(angle + 0.65) * arrowLength,
          math.sin(angle + 0.65) * arrowLength,
        ),
  );
}

double calculateServicesTourCardScrollOffset({
  required double currentOffset,
  required double minScrollExtent,
  required double maxScrollExtent,
  required Rect targetRect,
  required double headerBottom,
  required double viewportHeight,
  required double bottomObstruction,
}) {
  const gap = 14.0;
  final safeTop = headerBottom + gap;
  final safeBottom = math.max(safeTop, viewportHeight - bottomObstruction);
  var delta = 0.0;
  if (targetRect.top < safeTop) {
    delta = targetRect.top - safeTop;
  } else if (targetRect.bottom > safeBottom) {
    delta = math.min(targetRect.bottom - safeBottom, targetRect.top - safeTop);
  }
  return (currentOffset + delta)
      .clamp(minScrollExtent, maxScrollExtent)
      .toDouble();
}

class ServicesTourArrowGeometry {
  const ServicesTourArrowGeometry({
    required this.start,
    required this.control1,
    required this.control2,
    required this.end,
  });

  final Offset start;
  final Offset control1;
  final Offset control2;
  final Offset end;
}

class ServicesTourArrowHead {
  const ServicesTourArrowHead({
    required this.firstWing,
    required this.secondWing,
  });

  final Offset firstWing;
  final Offset secondWing;
}
