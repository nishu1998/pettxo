import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/home_tour_preference_service.dart';

enum HomeTourExitReason { skipped, completed, cancelled }

class HomeTourTargetHandle extends ChangeNotifier {
  RenderBox? _renderBox;
  Rect? _lastNotifiedRect;
  bool _notificationScheduled = false;
  bool _disposed = false;

  Rect? get rect {
    final box = _renderBox;
    if (box == null ||
        !box.attached ||
        !box.hasSize ||
        box.debugNeedsLayout ||
        box.size.isEmpty) {
      return null;
    }
    final value = box.localToGlobal(Offset.zero) & box.size;
    return value.isFinite ? value : null;
  }

  void _attach(RenderBox renderBox) {
    if (_disposed || identical(_renderBox, renderBox)) return;
    _renderBox = renderBox;
    _scheduleNotification();
  }

  void _detach(RenderBox renderBox) {
    if (_disposed || !identical(_renderBox, renderBox)) return;
    _renderBox = null;
    _scheduleNotification();
  }

  void _geometryChanged(RenderBox renderBox, {bool geometryCanBeRead = false}) {
    if (_disposed) return;
    if (!identical(_renderBox, renderBox)) _renderBox = renderBox;
    if (geometryCanBeRead && _sameRect(_lastNotifiedRect, rect)) return;
    _scheduleNotification();
  }

  void _scheduleNotification() {
    if (_disposed || _notificationScheduled) return;
    _notificationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationScheduled = false;
      if (_disposed) return;
      final nextRect = rect;
      if (_sameRect(_lastNotifiedRect, nextRect)) return;
      _lastNotifiedRect = nextRect;
      notifyListeners();
    });
  }

  static bool _sameRect(Rect? first, Rect? second) {
    if (first == null || second == null) return first == second;
    return (first.left - second.left).abs() < 0.5 &&
        (first.top - second.top).abs() < 0.5 &&
        (first.right - second.right).abs() < 0.5 &&
        (first.bottom - second.bottom).abs() < 0.5;
  }

  @override
  void dispose() {
    _disposed = true;
    _renderBox = null;
    super.dispose();
  }
}

class HomeTourTarget extends SingleChildRenderObjectWidget {
  const HomeTourTarget({super.key, required this.handle, required super.child});

  final HomeTourTargetHandle handle;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      HomeTourTargetRenderBox(handle);

  @override
  void updateRenderObject(
    BuildContext context,
    HomeTourTargetRenderBox renderObject,
  ) {
    renderObject.handle = handle;
  }
}

class HomeTourTargetRenderBox extends RenderProxyBox {
  HomeTourTargetRenderBox(this._handle);

  HomeTourTargetHandle _handle;

  set handle(HomeTourTargetHandle value) {
    if (identical(value, _handle)) return;
    if (attached) _handle._detach(this);
    _handle = value;
    if (attached) _handle._attach(this);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _handle._attach(this);
  }

  @override
  void detach() {
    _handle._detach(this);
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    _handle._geometryChanged(this);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    _handle._geometryChanged(this, geometryCanBeRead: true);
  }
}

class HomeTourTargets {
  const HomeTourTargets({
    required this.feed,
    required this.createPost,
    required this.notifications,
  });

  final HomeTourTargetHandle feed;
  final GlobalKey createPost;
  final GlobalKey notifications;
}

typedef HomeTourBeforeShow = Future<bool> Function();

Future<bool> waitForStableHomeTourTarget({
  required HomeTourTargetHandle target,
  required bool Function() canContinue,
  Duration stableFor = const Duration(milliseconds: 48),
  Duration timeout = const Duration(seconds: 4),
}) {
  final completer = Completer<bool>();
  Timer? stableTimer;
  Timer? timeoutTimer;
  Rect? candidate;

  void finish(bool value) {
    if (!completer.isCompleted) completer.complete(value);
  }

  void evaluate() {
    if (!canContinue()) {
      finish(false);
      return;
    }
    final next = target.rect;
    if (next == null || next.width <= 0 || next.height <= 0) {
      candidate = null;
      stableTimer?.cancel();
      return;
    }
    if (HomeTourTargetHandle._sameRect(candidate, next) &&
        stableTimer?.isActive == true) {
      return;
    }
    candidate = next;
    stableTimer?.cancel();
    stableTimer = Timer(stableFor, () {
      if (!canContinue()) {
        finish(false);
        return;
      }
      if (HomeTourTargetHandle._sameRect(candidate, target.rect)) {
        finish(true);
      } else {
        evaluate();
      }
    });
  }

  target.addListener(evaluate);
  timeoutTimer = Timer(timeout, () => finish(false));
  evaluate();
  return completer.future.whenComplete(() {
    stableTimer?.cancel();
    timeoutTimer?.cancel();
    target.removeListener(evaluate);
  });
}

class HomeGuidedTourController {
  HomeGuidedTourController({HomeTourPreferenceService? preferences})
    : _preferences = preferences ?? HomeTourPreferenceService();

  final HomeTourPreferenceService _preferences;
  final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);

  OverlayEntry? _entry;
  Completer<HomeTourExitReason?>? _sessionCompleter;
  bool _isStarting = false;
  bool _isDisposed = false;
  int _generation = 0;
  String _activeUid = '';

  Future<HomeTourExitReason?> start({
    required BuildContext context,
    required String uid,
    required HomeTourTargets targets,
    HomeTourBeforeShow? beforeShow,
  }) async {
    final normalizedUid = uid.trim();
    if (_isDisposed || _isStarting || _entry != null || normalizedUid.isEmpty) {
      return null;
    }

    _isStarting = true;
    final generation = ++_generation;
    Future<HomeTourExitReason?>? sessionFuture;
    try {
      try {
        if (await _preferences.isCompleted(normalizedUid)) return null;
      } catch (_) {
        // Local storage must never block or cover the Home screen.
        return null;
      }
      if (!context.mounted || !_canContinue(generation)) return null;

      if (beforeShow != null && !await beforeShow()) return null;
      if (!context.mounted || !_canContinue(generation)) return null;

      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return null;
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) return null;

      final completer = Completer<HomeTourExitReason?>();
      _sessionCompleter = completer;
      _activeUid = normalizedUid;
      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (overlayContext) =>
            HomeGuidedTourOverlay(targets: targets, onExit: _finish),
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

  Future<void> _finish(HomeTourExitReason reason) async {
    final uid = _activeUid;
    final sessionCompleter = _takeSessionCompleter();
    final shouldPersist =
        reason == HomeTourExitReason.skipped ||
        reason == HomeTourExitReason.completed;
    _removeEntry();
    if (shouldPersist) {
      try {
        await _preferences.markCompleted(uid);
      } catch (_) {
        debugPrint('Home guided-tour completion could not be persisted.');
      }
    }
    _completeSession(sessionCompleter, reason);
  }

  void cancel() {
    _generation += 1;
    final sessionCompleter = _takeSessionCompleter();
    _removeEntry();
    _completeSession(sessionCompleter, HomeTourExitReason.cancelled);
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
    _activeUid = '';
    if (isActive.value) isActive.value = false;
  }

  Completer<HomeTourExitReason?>? _takeSessionCompleter() {
    final completer = _sessionCompleter;
    _sessionCompleter = null;
    return completer;
  }

  void _completeSession(
    Completer<HomeTourExitReason?>? completer,
    HomeTourExitReason? reason,
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

class HomeGuidedTourOverlay extends StatefulWidget {
  const HomeGuidedTourOverlay({
    super.key,
    required this.targets,
    required this.onExit,
  });

  final HomeTourTargets targets;
  final Future<void> Function(HomeTourExitReason reason) onExit;

  @override
  State<HomeGuidedTourOverlay> createState() => _HomeGuidedTourOverlayState();
}

class _HomeGuidedTourOverlayState extends State<HomeGuidedTourOverlay> {
  static const Duration _transitionDuration = Duration(milliseconds: 300);
  final List<GlobalKey> _tooltipKeys = List<GlobalKey>.generate(
    3,
    (_) => GlobalKey(),
  );
  final Map<int, double> _tooltipHeights = <int, double>{};
  Rect? _stableFeedRect;
  int _stepIndex = 0;
  bool _exitInFlight = false;

  static const List<_HomeTourStepContent> _steps = <_HomeTourStepContent>[
    _HomeTourStepContent(
      tooltipTitle: 'Welcome to Home',
      tooltipDescription:
          'See posts, pet stories, updates, and helpful content from the Pettxo community.',
      panelTitle: 'Home',
      panelDescription:
          'Discover pet stories, updates, and community posts near you.',
      semanticsLabel: 'Home feed tour step',
    ),
    _HomeTourStepContent(
      tooltipTitle: 'Create a Post',
      tooltipDescription:
          'Tap here to share pet updates, stories, photos, or helpful posts with the community.',
      panelTitle: 'Create Post',
      panelDescription:
          'Share updates, pet moments, and useful posts with other pet lovers.',
      semanticsLabel: 'Create a post tour step',
    ),
    _HomeTourStepContent(
      tooltipTitle: 'Notifications',
      tooltipDescription:
          'Check alerts for likes, comments, booking updates, and important activity in the app.',
      panelTitle: 'Notifications',
      panelDescription:
          'Stay updated with alerts, activity, and important app updates.',
      semanticsLabel: 'Notifications tour step',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _stableFeedRect = widget.targets.feed.rect;
    widget.targets.feed.addListener(_handleFeedGeometryChanged);
  }

  @override
  void didUpdateWidget(covariant HomeGuidedTourOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.targets.feed, widget.targets.feed)) return;
    oldWidget.targets.feed.removeListener(_handleFeedGeometryChanged);
    _stableFeedRect = widget.targets.feed.rect;
    widget.targets.feed.addListener(_handleFeedGeometryChanged);
  }

  @override
  void dispose() {
    widget.targets.feed.removeListener(_handleFeedGeometryChanged);
    super.dispose();
  }

  void _handleFeedGeometryChanged() {
    final nextRect = widget.targets.feed.rect;
    if (nextRect != null) _stableFeedRect = nextRect;
    if (mounted && _stepIndex == 0) setState(() {});
  }

  Future<void> _exit(HomeTourExitReason reason) async {
    if (_exitInFlight) return;
    _exitInFlight = true;
    await widget.onExit(reason);
  }

  void _next() {
    if (_stepIndex >= _steps.length - 1) {
      unawaited(_exit(HomeTourExitReason.completed));
      return;
    }
    setState(() => _stepIndex += 1);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final safePadding = MediaQuery.paddingOf(context);
          final compact = size.height < 650 || size.width < 350;
          final textScale = (MediaQuery.textScalerOf(context).scale(14) / 14)
              .clamp(1.0, 1.6);
          final panelHeight =
              (compact ? 144.0 : 154.0) + ((textScale - 1) * 44);
          final panelBottom = math.max(
            safePadding.bottom + (compact ? 84 : 92),
            compact ? 88.0 : 96.0,
          );
          final panelTop = size.height - panelBottom - panelHeight;
          final measuredTargetRect = _targetRect(size, safePadding);
          final targetRect = _stepIndex == 0
              ? calculateHomeTourVisibleFeedRect(
                  targetRect: measuredTargetRect,
                  viewportSize: size,
                  safePadding: safePadding,
                  panelTop: panelTop,
                )
              : measuredTargetRect;
          final highlightRect = calculateHomeTourHighlightRect(
            stepIndex: _stepIndex,
            targetRect: targetRect,
            viewportSize: size,
          );
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
            _captureTooltipHeight(renderedStep);
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
                    key: const ValueKey<String>('home-tour-spotlight'),
                    painter: HomeTourScrimPainter(
                      highlightRect: highlightRect,
                      cornerRadius: _stepIndex == 0 ? 28 : 20,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _HomeTourArrowPainter(
                        tooltipRect: tooltipRect,
                        targetRect: highlightRect,
                        stepIndex: _stepIndex,
                      ),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  key: const ValueKey<String>('home-tour-tooltip-position'),
                  duration: _transitionDuration,
                  curve: Curves.easeInOutCubic,
                  left: tooltipRect.left,
                  top: tooltipRect.top,
                  width: tooltipRect.width,
                  onEnd: () => _captureTooltipHeight(renderedStep),
                  child: Align(
                    alignment: Alignment.topLeft,
                    widthFactor: 1,
                    heightFactor: 1,
                    child: AnimatedSwitcher(
                      duration: _transitionDuration,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: _HomeTourTooltip(
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
                      child: _HomeTourControlPanel(
                        stepIndex: _stepIndex,
                        step: step,
                        compact: compact,
                        onSkip: () =>
                            unawaited(_exit(HomeTourExitReason.skipped)),
                        onNext: _next,
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

  void _captureTooltipHeight(int stepIndex) {
    if (!mounted || stepIndex != _stepIndex) return;
    final renderObject = _tooltipKeys[stepIndex].currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return;
    }
    final measuredHeight = renderObject.size.height;
    final previousHeight = _tooltipHeights[stepIndex];
    if (previousHeight != null &&
        (previousHeight - measuredHeight).abs() < 0.5) {
      return;
    }
    setState(() => _tooltipHeights[stepIndex] = measuredHeight);
  }

  Rect _targetRect(Size size, EdgeInsets safePadding) {
    if (_stepIndex == 0) {
      final rect = widget.targets.feed.rect ?? _stableFeedRect;
      if (rect != null && rect.width > 0 && rect.height > 0) return rect;
      return Rect.fromLTWH(
        18,
        safePadding.top + 82,
        math.max(120, size.width - 36),
        math.max(140, size.height * 0.42),
      );
    }

    final key = _stepIndex == 1
        ? widget.targets.createPost
        : widget.targets.notifications;
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize) {
      final origin = renderObject.localToGlobal(Offset.zero);
      final rect = origin & renderObject.size;
      if (rect.width > 0 && rect.height > 0) return rect;
    }

    return _stepIndex == 1
        ? Rect.fromLTWH(24, safePadding.top + 10, 52, 52)
        : Rect.fromLTWH(
            math.max(0, size.width - 76),
            safePadding.top + 10,
            52,
            52,
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
    final preferredWidth = usableWidth * (compact ? 0.85 : 0.82);
    final width = preferredWidth
        .clamp(math.min(250.0, usableWidth), math.min(324.0, usableWidth))
        .toDouble();
    final textScale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
      1.0,
      1.6,
    );
    final estimatedHeight = (compact ? 108.0 : 116.0) + ((textScale - 1) * 48);
    final height = measuredHeight ?? estimatedHeight;
    double left;
    double top;
    if (_stepIndex == 0) {
      left = size.width - width - margin;
      top = target.top - height - 44;
    } else if (_stepIndex == 1) {
      left = size.width - width - margin;
      top = target.bottom + 48;
    } else {
      left = margin;
      top = target.bottom + 48;
    }
    final minimumTop = safePadding.top + 8;
    final maximumTop = math.max(minimumTop, panelTop - height - 16);
    return Rect.fromLTWH(
      left,
      top.clamp(minimumTop, maximumTop).toDouble(),
      width,
      height,
    );
  }
}

class _HomeTourStepContent {
  const _HomeTourStepContent({
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

class _HomeTourTooltip extends StatelessWidget {
  const _HomeTourTooltip({
    super.key,
    required this.step,
    required this.compact,
  });

  final _HomeTourStepContent step;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _HomeTourGlassCard(
      key: const ValueKey<String>('home-tour-tooltip-card'),
      borderRadius: compact ? 20 : 22,
      backgroundOpacity: 0.72,
      blurSigma: 18,
      glowOpacity: 0.34,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 18,
        vertical: compact ? 14 : 15,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step.tooltipTitle,
            style: TextStyle(
              color: AppColors.primary,
              fontSize: compact ? 17.5 : 20,
              fontWeight: FontWeight.w800,
              height: 1.08,
            ),
          ),
          SizedBox(height: compact ? 5 : 6),
          Text(
            step.tooltipDescription,
            style: TextStyle(
              color: const Color(0xFF4F535E),
              fontSize: compact ? 11.5 : 13.5,
              fontWeight: FontWeight.w500,
              height: 1.24,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeTourControlPanel extends StatelessWidget {
  const _HomeTourControlPanel({
    required this.stepIndex,
    required this.step,
    required this.compact,
    required this.onSkip,
    required this.onNext,
  });

  final int stepIndex;
  final _HomeTourStepContent step;
  final bool compact;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _HomeTourGlassCard(
      key: const ValueKey<String>('home-tour-control-panel'),
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
            children: List<Widget>.generate(3, (index) {
              final selected = index == stepIndex;
              return AnimatedContainer(
                key: ValueKey<String>('home-tour-progress-$index'),
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
                  key: const ValueKey<String>('home-tour-skip'),
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
                    key: const ValueKey<String>('home-tour-next'),
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
                          stepIndex == 2 ? 'Got it' : 'Next',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
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

class _HomeTourGlassCard extends StatelessWidget {
  const _HomeTourGlassCard({
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

class HomeTourScrimPainter extends CustomPainter {
  const HomeTourScrimPainter({
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
  bool shouldRepaint(HomeTourScrimPainter oldDelegate) {
    return oldDelegate.highlightRect != highlightRect ||
        oldDelegate.cornerRadius != cornerRadius;
  }
}

class _HomeTourArrowPainter extends CustomPainter {
  const _HomeTourArrowPainter({
    required this.tooltipRect,
    required this.targetRect,
    required this.stepIndex,
  });

  final Rect tooltipRect;
  final Rect targetRect;
  final int stepIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = calculateHomeTourArrowGeometry(
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

    final angle = math.atan2(
      geometry.end.dy - geometry.control2.dy,
      geometry.end.dx - geometry.control2.dx,
    );
    const arrowLength = 13.0;
    for (final paint in <Paint>[whitePaint, orangePaint]) {
      canvas.drawLine(
        geometry.end,
        geometry.end -
            Offset(
              math.cos(angle - 0.65) * arrowLength,
              math.sin(angle - 0.65) * arrowLength,
            ),
        paint,
      );
      canvas.drawLine(
        geometry.end,
        geometry.end -
            Offset(
              math.cos(angle + 0.65) * arrowLength,
              math.sin(angle + 0.65) * arrowLength,
            ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HomeTourArrowPainter oldDelegate) {
    return oldDelegate.tooltipRect != tooltipRect ||
        oldDelegate.targetRect != targetRect ||
        oldDelegate.stepIndex != stepIndex;
  }
}

HomeTourArrowGeometry calculateHomeTourArrowGeometry({
  required int stepIndex,
  required Rect tooltipRect,
  required Rect targetRect,
}) {
  if (stepIndex == 0) {
    final start = Offset(tooltipRect.left - 1, tooltipRect.center.dy);
    const targetGap = 8.0;
    final end = Offset(
      targetRect.left + math.min(48, targetRect.width * 0.18),
      targetRect.top - targetGap,
    );
    return HomeTourArrowGeometry(
      start: start,
      control1: Offset(start.dx - 24, start.dy + 10),
      control2: Offset(end.dx - 22, end.dy - 26),
      end: end,
    );
  }

  final isCreatePost = stepIndex == 1;
  final start = Offset(
    isCreatePost ? tooltipRect.left + 42 : tooltipRect.right - 42,
    tooltipRect.top - 1,
  );
  const targetGap = 8.0;
  final end = Offset(targetRect.center.dx, targetRect.bottom + targetGap);
  final horizontalDirection = isCreatePost ? 1.0 : -1.0;
  return HomeTourArrowGeometry(
    start: start,
    control1: Offset(start.dx - (18 * horizontalDirection), start.dy - 24),
    control2: Offset(end.dx + (30 * horizontalDirection), end.dy + 28),
    end: end,
  );
}

Rect calculateHomeTourHighlightRect({
  required int stepIndex,
  required Rect targetRect,
  required Size viewportSize,
}) {
  final padding = stepIndex == 0 ? 4.0 : 8.0;
  return Rect.fromLTRB(
    math.max(2, targetRect.left - padding),
    math.max(2, targetRect.top - padding),
    math.min(viewportSize.width - 2, targetRect.right + padding),
    math.min(viewportSize.height - 2, targetRect.bottom + padding),
  );
}

Rect calculateHomeTourVisibleFeedRect({
  required Rect targetRect,
  required Size viewportSize,
  required EdgeInsets safePadding,
  required double panelTop,
}) {
  final usableViewport = Rect.fromLTRB(
    2,
    safePadding.top + 76,
    viewportSize.width - 2,
    math.max(safePadding.top + 77, panelTop - 16),
  );
  final visibleRect = targetRect.intersect(usableViewport);
  if (visibleRect.width > 0 && visibleRect.height > 0) return visibleRect;
  return targetRect;
}

double calculateHomeTourRevealScrollDelta({
  required Rect targetRect,
  required double usableTop,
  required double usableBottom,
  double minimumVisibleHeight = 96,
}) {
  if (targetRect.top < usableTop) return targetRect.top - usableTop;
  if (targetRect.top > usableBottom - minimumVisibleHeight) {
    return targetRect.top - (usableBottom - minimumVisibleHeight);
  }
  return 0;
}

class HomeTourArrowGeometry {
  const HomeTourArrowGeometry({
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
