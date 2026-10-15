import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/explore_tour_preference_service.dart';

enum ExploreTourExitReason { skipped, completed, cancelled }

class ExploreTourTargets {
  const ExploreTourTargets({
    required this.search,
    required this.trending,
    required this.feedSwitcher,
    required this.firstPost,
    required this.contentFallback,
  });

  final GlobalKey search;
  final GlobalKey trending;
  final GlobalKey feedSwitcher;
  final GlobalKey firstPost;
  final GlobalKey contentFallback;
}

typedef ExploreTourBeforeShow = Future<void> Function();
typedef ExploreTourPrepareStep = Future<void> Function(int stepIndex);

class ExploreGuidedTourController {
  ExploreGuidedTourController({ExploreTourPreferenceService? preferences})
    : _preferences = preferences ?? ExploreTourPreferenceService();

  final ExploreTourPreferenceService _preferences;
  final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);

  OverlayEntry? _entry;
  Completer<ExploreTourExitReason?>? _sessionCompleter;
  bool _isStarting = false;
  bool _isDisposed = false;
  int _generation = 0;
  String _activeUid = '';

  Future<ExploreTourExitReason?> start({
    required BuildContext context,
    required String uid,
    required ExploreTourTargets targets,
    ExploreTourBeforeShow? beforeShow,
    ExploreTourPrepareStep? prepareStep,
  }) async {
    final normalizedUid = uid.trim();
    if (_isDisposed || _isStarting || _entry != null || normalizedUid.isEmpty) {
      return null;
    }

    _isStarting = true;
    final generation = ++_generation;
    Future<ExploreTourExitReason?>? sessionFuture;
    try {
      try {
        if (await _preferences.isCompleted(normalizedUid)) return null;
      } catch (_) {
        // Local storage must never block or cover Explore.
        return null;
      }
      if (!context.mounted || !_canContinue(generation)) return null;

      await beforeShow?.call();
      if (!context.mounted || !_canContinue(generation)) return null;

      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return null;
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) return null;

      final completer = Completer<ExploreTourExitReason?>();
      _sessionCompleter = completer;
      _activeUid = normalizedUid;
      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (overlayContext) => ExploreGuidedTourOverlay(
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

  Future<void> _finish(ExploreTourExitReason reason) async {
    final uid = _activeUid;
    final sessionCompleter = _takeSessionCompleter();
    final shouldPersist =
        reason == ExploreTourExitReason.skipped ||
        reason == ExploreTourExitReason.completed;
    _removeEntry();
    if (shouldPersist) {
      try {
        await _preferences.markCompleted(uid);
      } catch (_) {
        debugPrint('Explore guided-tour completion could not be persisted.');
      }
    }
    _completeSession(sessionCompleter, reason);
  }

  void cancel() {
    _generation += 1;
    final sessionCompleter = _takeSessionCompleter();
    _removeEntry();
    _completeSession(sessionCompleter, ExploreTourExitReason.cancelled);
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
    _activeUid = '';
    if (isActive.value) isActive.value = false;
  }

  Completer<ExploreTourExitReason?>? _takeSessionCompleter() {
    final completer = _sessionCompleter;
    _sessionCompleter = null;
    return completer;
  }

  void _completeSession(
    Completer<ExploreTourExitReason?>? completer,
    ExploreTourExitReason? reason,
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

class ExploreGuidedTourOverlay extends StatefulWidget {
  const ExploreGuidedTourOverlay({
    super.key,
    required this.targets,
    required this.onExit,
    this.prepareStep,
  });

  final ExploreTourTargets targets;
  final Future<void> Function(ExploreTourExitReason reason) onExit;
  final ExploreTourPrepareStep? prepareStep;

  @override
  State<ExploreGuidedTourOverlay> createState() =>
      _ExploreGuidedTourOverlayState();
}

class _ExploreGuidedTourOverlayState extends State<ExploreGuidedTourOverlay> {
  static const Duration _transitionDuration = Duration(milliseconds: 300);
  final List<GlobalKey> _tooltipKeys = List<GlobalKey>.generate(
    4,
    (_) => GlobalKey(),
  );
  final GlobalKey _controlPanelKey = GlobalKey();
  final Map<int, double> _tooltipHeights = <int, double>{};
  double? _controlPanelHeight;
  int _stepIndex = 0;
  bool _exitInFlight = false;
  bool _transitionInFlight = false;

  static const List<_ExploreTourStepContent> _steps = <_ExploreTourStepContent>[
    _ExploreTourStepContent(
      tooltipTitle: 'Search Profiles & Hashtags',
      tooltipDescription:
          'Find pet lovers, explore profiles, and search posts using hashtags.',
      panelTitle: 'Search Profiles & Hashtags',
      panelDescription:
          'Find pet lovers, explore profiles, and search posts using hashtags.',
      semanticsLabel: 'Explore search tour step',
    ),
    _ExploreTourStepContent(
      tooltipTitle: 'Trending Hashtags',
      tooltipDescription:
          'Explore popular hashtags to discover trending pet content, stories, and community posts.',
      panelTitle: 'Trending Hashtags',
      panelDescription:
          'Explore popular hashtags to discover trending pet content and community posts.',
      semanticsLabel: 'Explore trending hashtags tour step',
    ),
    _ExploreTourStepContent(
      tooltipTitle: 'Discover & Nearby You',
      tooltipDescription:
          'Switch between global posts and content near your location to explore relevant pet content.',
      panelTitle: 'Discover & Nearby You',
      panelDescription:
          'Switch between global posts and content near your location to explore relevant pet content.',
      semanticsLabel: 'Explore feed switcher tour step',
    ),
    _ExploreTourStepContent(
      tooltipTitle: 'Explore Posts',
      tooltipDescription:
          'Browse community posts, pet stories, and updates from other pet lovers. Tap any post to view details, like, or comment.',
      panelTitle: 'Explore Posts',
      panelDescription:
          'Browse community posts, pet stories, and updates. Tap any post to view details, like, or comment.',
      semanticsLabel: 'Explore posts tour step',
    ),
  ];

  Future<void> _exit(ExploreTourExitReason reason) async {
    if (_exitInFlight) return;
    _exitInFlight = true;
    await widget.onExit(reason);
  }

  Future<void> _next() async {
    if (_transitionInFlight || _exitInFlight) return;
    if (_stepIndex >= _steps.length - 1) {
      unawaited(_exit(ExploreTourExitReason.completed));
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
            safePadding.bottom + (compact ? 84 : 92),
            compact ? 88.0 : 96.0,
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
          final step = _steps[_stepIndex];
          final renderedStep = _stepIndex;
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
                    painter: _ExploreTourScrimPainter(
                      highlightRect: highlightRect,
                      cornerRadius: _stepIndex == 3 ? 22 : 24,
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: highlightRect,
                  child: const IgnorePointer(
                    child: SizedBox(
                      key: ValueKey<String>('explore-tour-highlight-bounds'),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ExploreTourArrowPainter(
                        tooltipRect: tooltipRect,
                        targetRect: highlightRect,
                        stepIndex: _stepIndex,
                      ),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  key: const ValueKey<String>('explore-tour-tooltip-position'),
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
                      child: _ExploreTourTooltip(
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
                      child: _ExploreTourControlPanel(
                        key: _controlPanelKey,
                        stepIndex: _stepIndex,
                        step: step,
                        compact: compact,
                        onSkip: () =>
                            unawaited(_exit(ExploreTourExitReason.skipped)),
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
    final tooltipRenderObject = _tooltipKeys[stepIndex].currentContext
        ?.findRenderObject();
    final panelRenderObject = _controlPanelKey.currentContext
        ?.findRenderObject();
    double? tooltipHeight;
    double? panelHeight;
    if (tooltipRenderObject is RenderBox &&
        tooltipRenderObject.attached &&
        tooltipRenderObject.hasSize) {
      tooltipHeight = tooltipRenderObject.size.height;
    }
    if (panelRenderObject is RenderBox &&
        panelRenderObject.attached &&
        panelRenderObject.hasSize) {
      panelHeight = panelRenderObject.size.height;
    }
    final tooltipChanged =
        tooltipHeight != null &&
        ((_tooltipHeights[stepIndex] ?? -1) - tooltipHeight).abs() >= 0.5;
    final panelChanged =
        panelHeight != null &&
        ((_controlPanelHeight ?? -1) - panelHeight).abs() >= 0.5;
    if (!tooltipChanged && !panelChanged) return;
    setState(() {
      if (tooltipChanged) _tooltipHeights[stepIndex] = tooltipHeight!;
      if (panelChanged) _controlPanelHeight = panelHeight;
    });
  }

  Rect _targetRect(Size size, EdgeInsets safePadding) {
    final key = switch (_stepIndex) {
      0 => widget.targets.search,
      1 => widget.targets.trending,
      2 => widget.targets.feedSwitcher,
      _ => widget.targets.firstPost,
    };
    final measured = _rectForKey(key);
    if (measured != null) return measured;
    if (_stepIndex == 3) {
      final contentFallback = _rectForKey(widget.targets.contentFallback);
      if (contentFallback != null) {
        final height = math.min(contentFallback.height, size.height * 0.38);
        return Rect.fromLTWH(
          contentFallback.left,
          contentFallback.top,
          contentFallback.width,
          math.max(96, height),
        );
      }
    }

    return switch (_stepIndex) {
      0 => Rect.fromLTWH(16, safePadding.top + 4, size.width - 32, 58),
      1 => Rect.fromLTWH(16, safePadding.top + 82, size.width - 32, 86),
      2 => Rect.fromLTWH(16, safePadding.top + 182, size.width - 32, 64),
      _ => Rect.fromLTWH(
        16,
        safePadding.top + 260,
        math.max(140, (size.width - 44) / 2),
        math.min(300, size.height * 0.38),
      ),
    };
  }

  Rect? _rectForKey(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    final origin = renderObject.localToGlobal(Offset.zero);
    final rect = origin & renderObject.size;
    return rect.width > 0 && rect.height > 0 ? rect : null;
  }

  Rect _expandedTargetRect(Rect target, Size size) {
    final padding = _stepIndex == 3 ? 5.0 : 7.0;
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
    final isPostStep = _stepIndex == 3;
    late final double width;
    if (isPostStep) {
      const sideGap = 26.0;
      final roomOnRight = size.width - margin - target.right - sideGap;
      final roomOnLeft = target.left - margin - sideGap;
      final sideRoom = math.max(roomOnRight, roomOnLeft);
      width = sideRoom >= 160
          ? sideRoom.clamp(160.0, 210.0).toDouble()
          : (usableWidth * 0.72)
                .clamp(
                  math.min(220.0, usableWidth),
                  math.min(286.0, usableWidth),
                )
                .toDouble();
    } else {
      final widthFactor = switch (_stepIndex) {
        0 => 0.72,
        1 => 0.76,
        _ => 0.72,
      };
      final maximumWidth = switch (_stepIndex) {
        0 => 286.0,
        1 => 300.0,
        _ => 286.0,
      };
      width = (usableWidth * widthFactor)
          .clamp(
            math.min(220.0, usableWidth),
            math.min(maximumWidth, usableWidth),
          )
          .toDouble();
    }
    final estimatedHeight =
        (isPostStep ? (compact ? 140.0 : 150.0) : (compact ? 100.0 : 108.0)) +
        ((textScale - 1) * (isPostStep ? 66 : 48));
    final height = measuredHeight ?? estimatedHeight;
    double left;
    double top;
    if (isPostStep) {
      const sideGap = 26.0;
      final roomOnRight = size.width - margin - target.right;
      final roomOnLeft = target.left - margin;
      if (roomOnRight >= width + sideGap) {
        left = target.right + sideGap;
        top = target.top + math.min(28, target.height * 0.10);
      } else if (roomOnLeft >= width + sideGap) {
        left = target.left - width - sideGap;
        top = target.top + math.min(28, target.height * 0.10);
      } else {
        left = size.width - width - margin;
        final belowTop = target.bottom + 14;
        top = belowTop + height <= panelTop - 16
            ? belowTop
            : target.top - height - 14;
      }
    } else {
      left = switch (_stepIndex) {
        1 => target.center.dx - width / 2,
        _ => size.width - width - margin,
      };
      top = target.bottom + 26;
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

class _ExploreTourStepContent {
  const _ExploreTourStepContent({
    required this.tooltipTitle,
    required this.tooltipDescription,
    required this.panelTitle,
    required this.panelDescription,
    required this.semanticsLabel,
  });

  final String tooltipTitle;
  final String tooltipDescription;
  final String panelTitle;
  final String panelDescription;
  final String semanticsLabel;
}

class _ExploreTourTooltip extends StatelessWidget {
  const _ExploreTourTooltip({
    super.key,
    required this.step,
    required this.compact,
  });

  final _ExploreTourStepContent step;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _ExploreTourGlassCard(
      key: const ValueKey<String>('explore-tour-tooltip-card'),
      borderRadius: compact ? 20 : 22,
      backgroundOpacity: 0.72,
      blurSigma: 18,
      glowOpacity: 0.34,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
        vertical: compact ? 12 : 13,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step.tooltipTitle,
            style: TextStyle(
              color: AppColors.primary,
              fontSize: compact ? 16.5 : 18.5,
              fontWeight: FontWeight.w800,
              height: 1.08,
            ),
          ),
          SizedBox(height: compact ? 5 : 6),
          Text(
            step.tooltipDescription,
            style: TextStyle(
              color: const Color(0xFF4F535E),
              fontSize: compact ? 11.5 : 13,
              fontWeight: FontWeight.w500,
              height: 1.24,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExploreTourControlPanel extends StatelessWidget {
  const _ExploreTourControlPanel({
    super.key,
    required this.stepIndex,
    required this.step,
    required this.compact,
    required this.onSkip,
    required this.onNext,
  });

  final int stepIndex;
  final _ExploreTourStepContent step;
  final bool compact;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _ExploreTourGlassCard(
      key: const ValueKey<String>('explore-tour-control-panel'),
      borderRadius: compact ? 24 : 28,
      backgroundOpacity: 0.76,
      blurSigma: 22,
      glowOpacity: 0.32,
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 18,
        compact ? 10 : 12,
        compact ? 14 : 18,
        compact ? 12 : 14,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(4, (index) {
              final selected = index == stepIndex;
              return AnimatedContainer(
                key: ValueKey<String>('explore-tour-progress-$index'),
                duration: const Duration(milliseconds: 300),
                width: selected ? 34 : 22,
                height: 5,
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
          SizedBox(height: compact ? 8 : 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Row(
              key: ValueKey<int>(stepIndex),
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: compact ? 44 : 48,
                  height: compact ? 44 : 48,
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
                      fontSize: compact ? 20 : 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox(width: compact ? 11 : 13),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.panelTitle,
                        style: TextStyle(
                          color: AppColors.textDark,
                          fontSize: compact ? 16.5 : 18,
                          fontWeight: FontWeight.w800,
                          height: 1.08,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        step.panelDescription,
                        style: TextStyle(
                          color: const Color(0xFF5D626D),
                          fontSize: compact ? 11.5 : 12.5,
                          fontWeight: FontWeight.w500,
                          height: 1.18,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 8 : 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey<String>('explore-tour-skip'),
                  onPressed: onSkip,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
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
                      fontSize: compact ? 14 : 15,
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
                    key: const ValueKey<String>('explore-tour-next'),
                    onPressed: onNext,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 48),
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
                          stepIndex == 3 ? 'Got it' : 'Next',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        if (stepIndex != 3) ...[
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

class _ExploreTourGlassCard extends StatelessWidget {
  const _ExploreTourGlassCard({
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

class _ExploreTourScrimPainter extends CustomPainter {
  const _ExploreTourScrimPainter({
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
    final holePath = Path()..addRRect(highlight);
    final scrimPath = Path.combine(
      PathOperation.difference,
      fullPath,
      holePath,
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
  bool shouldRepaint(_ExploreTourScrimPainter oldDelegate) {
    return oldDelegate.highlightRect != highlightRect ||
        oldDelegate.cornerRadius != cornerRadius;
  }
}

class _ExploreTourArrowPainter extends CustomPainter {
  const _ExploreTourArrowPainter({
    required this.tooltipRect,
    required this.targetRect,
    required this.stepIndex,
  });

  final Rect tooltipRect;
  final Rect targetRect;
  final int stepIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = calculateExploreTourArrowGeometry(
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
    final whitePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.94)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final orangePaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, whitePaint);
    canvas.drawPath(path, orangePaint);

    final arrowHead = calculateExploreTourArrowHead(
      geometry,
      arrowLength: switch (stepIndex) {
        0 => 8,
        3 => 6,
        _ => 13,
      },
    );
    for (final paint in <Paint>[whitePaint, orangePaint]) {
      canvas.drawLine(geometry.end, arrowHead.firstWing, paint);
      canvas.drawLine(geometry.end, arrowHead.secondWing, paint);
    }
  }

  @override
  bool shouldRepaint(_ExploreTourArrowPainter oldDelegate) {
    return oldDelegate.tooltipRect != tooltipRect ||
        oldDelegate.targetRect != targetRect ||
        oldDelegate.stepIndex != stepIndex;
  }
}

ExploreTourArrowGeometry calculateExploreTourArrowGeometry({
  required int stepIndex,
  required Rect tooltipRect,
  required Rect targetRect,
}) {
  const targetGap = 8.0;
  if (stepIndex == 0) {
    final end = Offset(
      targetRect.left + targetRect.width * 0.22,
      targetRect.bottom + targetGap,
    );
    final start = Offset(
      tooltipRect.left - 1,
      tooltipRect.top + tooltipRect.height * 0.32,
    );
    return ExploreTourArrowGeometry(
      start: start,
      control1: Offset(start.dx - 18, start.dy - 2),
      control2: Offset(end.dx - 10, end.dy + 14),
      end: end,
    );
  }

  if (stepIndex == 3) {
    final tooltipIsAbove = tooltipRect.bottom <= targetRect.top;
    final start = Offset(
      tooltipRect.left - 1,
      tooltipRect.top + tooltipRect.height * (tooltipIsAbove ? 0.42 : 0.36),
    );
    if (tooltipIsAbove) {
      final end = Offset(
        targetRect.left + targetRect.width * 0.52,
        targetRect.top - targetGap,
      );
      return ExploreTourArrowGeometry(
        start: start,
        control1: Offset(start.dx - 18, start.dy + 16),
        control2: Offset(end.dx + 14, end.dy - 20),
        end: end,
      );
    }

    final tooltipIsRight = tooltipRect.left >= targetRect.right;
    if (tooltipIsRight) {
      final end = Offset(
        targetRect.right + targetGap,
        (start.dy + 44).clamp(targetRect.top + 32, targetRect.bottom - 32),
      );
      return ExploreTourArrowGeometry(
        start: start,
        control1: Offset(start.dx - 10, start.dy + 14),
        control2: Offset(end.dx + 14, end.dy - 16),
        end: end,
      );
    }

    final end = Offset(
      targetRect.left + targetRect.width * 0.52,
      targetRect.top - targetGap,
    );
    return ExploreTourArrowGeometry(
      start: start,
      control1: Offset(start.dx - 18, start.dy + 16),
      control2: Offset(end.dx + 14, end.dy - 20),
      end: end,
    );
  }

  final tooltipIsAbove = tooltipRect.bottom <= targetRect.top;
  final targetAnchorFactor = stepIndex == 1 ? 0.28 : 0.62;
  final end = Offset(
    targetRect.left + targetRect.width * targetAnchorFactor,
    tooltipIsAbove ? targetRect.top - targetGap : targetRect.bottom + targetGap,
  );
  final preferredOffset = stepIndex == 1 ? 18.0 : 20.0;
  final start = Offset(
    (end.dx + preferredOffset).clamp(
      tooltipRect.left + 24,
      tooltipRect.right - 24,
    ),
    tooltipIsAbove ? tooltipRect.bottom + 1 : tooltipRect.top - 1,
  );
  final verticalDirection = tooltipIsAbove ? 1.0 : -1.0;
  return ExploreTourArrowGeometry(
    start: start,
    control1: Offset(start.dx, start.dy + (6 * verticalDirection)),
    control2: Offset(end.dx + 10, end.dy - (8 * verticalDirection)),
    end: end,
  );
}

ExploreTourArrowHead calculateExploreTourArrowHead(
  ExploreTourArrowGeometry geometry, {
  double arrowLength = 13,
}) {
  final angle = math.atan2(
    geometry.end.dy - geometry.control2.dy,
    geometry.end.dx - geometry.control2.dx,
  );
  return ExploreTourArrowHead(
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

double calculateExploreTourPostScrollOffset({
  required double currentOffset,
  required double minScrollExtent,
  required double maxScrollExtent,
  required Rect targetRect,
  required double headerBottom,
  required double viewportHeight,
  required double bottomObstruction,
}) {
  const targetGap = 14.0;
  final safeTop = headerBottom + targetGap;
  final safeBottom = math.max(safeTop, viewportHeight - bottomObstruction);
  var scrollDelta = 0.0;
  if (targetRect.top < safeTop) {
    scrollDelta = targetRect.top - safeTop;
  } else if (targetRect.bottom > safeBottom) {
    final requestedDelta = targetRect.bottom - safeBottom;
    final maximumDeltaBeforeHeader = targetRect.top - safeTop;
    scrollDelta = math.min(requestedDelta, maximumDeltaBeforeHeader);
  }
  return (currentOffset + scrollDelta)
      .clamp(minScrollExtent, maxScrollExtent)
      .toDouble();
}

class ExploreTourArrowGeometry {
  const ExploreTourArrowGeometry({
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

class ExploreTourArrowHead {
  const ExploreTourArrowHead({
    required this.firstWing,
    required this.secondWing,
  });

  final Offset firstWing;
  final Offset secondWing;
}
