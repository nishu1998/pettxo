import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/profile_tour_preference_service.dart';

enum ProfileTourExitReason { skipped, completed, cancelled }

enum ProfileTourLifecycleState {
  idle,
  checkingEligibility,
  waitingForScreen,
  preparingTarget,
  presenting,
  transitioning,
  completing,
  completed,
  cancelled,
}

@immutable
class ProfileTourLayoutSnapshot {
  const ProfileTourLayoutSnapshot({
    required this.stepIndex,
    required this.viewportSize,
    required this.safePadding,
    required this.panelRect,
    required this.usableViewport,
  });

  final int stepIndex;
  final Size viewportSize;
  final EdgeInsets safePadding;
  final Rect panelRect;
  final Rect usableViewport;
}

class ProfileTourTargetHandle extends ChangeNotifier {
  RenderBox? _renderBox;
  bool _notificationScheduled = false;
  Rect? _lastNotifiedRect;

  bool get isAttached => _renderBox?.attached ?? false;
  bool get isAvailable {
    final box = _renderBox;
    return box != null && box.attached && box.hasSize && !box.debugNeedsLayout;
  }

  Rect? get rect {
    final box = _renderBox;
    return box == null ? null : _rectFor(box);
  }

  Rect? _rectFor(RenderBox box) {
    if (!box.attached ||
        !box.hasSize ||
        box.debugNeedsLayout ||
        box.size.isEmpty) {
      return null;
    }
    final topLeft = box.localToGlobal(Offset.zero);
    final value = topLeft & box.size;
    return value.isFinite ? value : null;
  }

  double? get height {
    final box = _renderBox;
    if (box == null || !box.attached || !box.hasSize || box.debugNeedsLayout) {
      return null;
    }
    return box.size.height;
  }

  void _attach(RenderBox renderBox) {
    if (identical(_renderBox, renderBox)) return;
    _renderBox = renderBox;
    _scheduleNotification();
  }

  void _detach(RenderBox renderBox) {
    if (!identical(_renderBox, renderBox)) return;
    _renderBox = null;
    _scheduleNotification();
  }

  void _layoutChanged(RenderBox renderBox, {bool geometryCanBeRead = false}) {
    if (!identical(_renderBox, renderBox)) _renderBox = renderBox;
    if (geometryCanBeRead &&
        _sameRect(_lastNotifiedRect, _rectFor(renderBox))) {
      return;
    }
    _scheduleNotification();
  }

  void _scheduleNotification() {
    if (_notificationScheduled) return;
    _notificationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationScheduled = false;
      final nextRect = rect;
      if (_sameRect(_lastNotifiedRect, nextRect)) return;
      _lastNotifiedRect = nextRect;
      notifyListeners();
    });
  }

  bool _sameRect(Rect? first, Rect? second) {
    if (first == null || second == null) return first == second;
    return (first.left - second.left).abs() < 0.1 &&
        (first.top - second.top).abs() < 0.1 &&
        (first.right - second.right).abs() < 0.1 &&
        (first.bottom - second.bottom).abs() < 0.1;
  }
}

class ProfileTourTarget extends SingleChildRenderObjectWidget {
  const ProfileTourTarget({
    super.key,
    required this.handle,
    required super.child,
  });

  final ProfileTourTargetHandle handle;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      ProfileTourTargetRenderBox(handle);

  @override
  void updateRenderObject(
    BuildContext context,
    ProfileTourTargetRenderBox renderObject,
  ) {
    renderObject.handle = handle;
  }
}

class ProfileTourTargetRenderBox extends RenderProxyBox {
  ProfileTourTargetRenderBox(this._handle);

  ProfileTourTargetHandle _handle;

  set handle(ProfileTourTargetHandle value) {
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
    _handle._layoutChanged(this);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    _handle._layoutChanged(this, geometryCanBeRead: true);
  }
}

class ProfileTourTargets {
  const ProfileTourTargets({
    required this.settings,
    required this.bookings,
    required this.addPet,
    required this.postsTab,
    required this.servicesTab,
    required this.addService,
  });

  final ProfileTourTargetHandle settings;
  final ProfileTourTargetHandle bookings;
  final ProfileTourTargetHandle addPet;
  final ProfileTourTargetHandle postsTab;
  final ProfileTourTargetHandle servicesTab;
  final ProfileTourTargetHandle addService;
}

typedef ProfileTourBeforeShow = Future<void> Function();
typedef ProfileTourPrepareInitial = Future<bool> Function();
typedef ProfileTourPrepareStep = Future<bool> Function(int stepIndex);
Future<bool> waitForProfileTourReadiness({
  required Listenable readinessSignal,
  required ScrollController scrollController,
  required ProfileTourTargetHandle target,
  required bool Function() canContinue,
  Duration timeout = const Duration(seconds: 10),
}) {
  final completer = Completer<bool>();
  Timer? timeoutTimer;

  void finish(bool ready) {
    if (completer.isCompleted) return;
    completer.complete(ready);
  }

  void evaluate() {
    if (completer.isCompleted) return;
    if (!canContinue()) {
      finish(false);
      return;
    }

    final hasClients = scrollController.hasClients;
    final hasDimensions =
        hasClients && scrollController.position.hasContentDimensions;
    final targetAvailable = target.isAvailable;
    if (hasClients && hasDimensions && targetAvailable) {
      finish(true);
      return;
    }
  }

  readinessSignal.addListener(evaluate);
  target.addListener(evaluate);
  timeoutTimer = Timer(timeout, () {
    if (completer.isCompleted) return;
    finish(false);
  });
  evaluate();
  return completer.future.whenComplete(() {
    timeoutTimer?.cancel();
    readinessSignal.removeListener(evaluate);
    target.removeListener(evaluate);
  });
}

class ProfileTourBackScope extends StatelessWidget {
  const ProfileTourBackScope({
    super.key,
    required this.isTourActive,
    required this.onDismissTour,
    required this.child,
  });

  final bool isTourActive;
  final VoidCallback onDismissTour;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isTourActive,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isTourActive) onDismissTour();
      },
      child: child,
    );
  }
}

class ProfileGuidedTourController {
  ProfileGuidedTourController({ProfileTourPreferenceService? preferences})
    : _preferences = preferences ?? ProfileTourPreferenceService();

  final ProfileTourPreferenceService _preferences;
  final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);
  final ValueNotifier<ProfileTourLifecycleState> lifecycleState =
      ValueNotifier<ProfileTourLifecycleState>(ProfileTourLifecycleState.idle);
  final ValueNotifier<ProfileTourLayoutSnapshot?> layoutSnapshot =
      ValueNotifier<ProfileTourLayoutSnapshot?>(null);

  OverlayEntry? _entry;
  Completer<ProfileTourExitReason?>? _sessionCompleter;
  bool _isStarting = false;
  bool _isFinishing = false;
  bool _isDisposed = false;
  int _generation = 0;
  String _activeUid = '';

  int get generation => _generation;

  Future<ProfileTourExitReason?> start({
    required BuildContext context,
    required String uid,
    required ProfileTourTargets targets,
    ProfileTourBeforeShow? beforeShow,
    ProfileTourPrepareInitial? prepareInitial,
    ProfileTourPrepareStep? prepareStep,
  }) async {
    final normalizedUid = uid.trim();
    if (_isDisposed ||
        _isStarting ||
        _isFinishing ||
        _entry != null ||
        normalizedUid.isEmpty) {
      return null;
    }

    _isStarting = true;
    layoutSnapshot.value = null;
    final generation = ++_generation;
    _setLifecycleState(ProfileTourLifecycleState.checkingEligibility);
    Future<ProfileTourExitReason?>? sessionFuture;
    try {
      try {
        if (await _preferences.isCompleted(normalizedUid)) {
          return null;
        }
      } catch (_) {
        return null;
      }
      if (!context.mounted || !_canContinueStart(generation)) {
        return null;
      }

      _setLifecycleState(ProfileTourLifecycleState.waitingForScreen);
      await beforeShow?.call();
      if (!context.mounted || !_canContinueStart(generation)) {
        return null;
      }

      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) {
        return null;
      }
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) {
        return null;
      }

      _setLifecycleState(ProfileTourLifecycleState.preparingTarget);
      final initialTargetReady = await prepareInitial?.call() ?? true;
      if (!initialTargetReady ||
          !context.mounted ||
          !_canContinueStart(generation)) {
        _setLifecycleState(ProfileTourLifecycleState.cancelled);
        return null;
      }

      final preparedRoute = ModalRoute.of(context);
      if (preparedRoute != null && !preparedRoute.isCurrent) {
        _setLifecycleState(ProfileTourLifecycleState.cancelled);
        return null;
      }

      final completer = Completer<ProfileTourExitReason?>();
      _sessionCompleter = completer;
      _activeUid = normalizedUid;
      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (overlayContext) => ProfileGuidedTourOverlay(
          targets: targets,
          onExit: (reason) => _finish(reason, generation),
          prepareStep: prepareStep == null
              ? null
              : (stepIndex) =>
                    _prepareTransition(generation, stepIndex, prepareStep),
          onLayoutSnapshot: (snapshot) {
            if (_ownsActiveSession(generation)) layoutSnapshot.value = snapshot;
          },
        ),
      );
      _entry = entry;
      overlay.insert(entry);
      isActive.value = true;
      _setLifecycleState(ProfileTourLifecycleState.presenting);
      sessionFuture = completer.future;
    } finally {
      _isStarting = false;
      if (sessionFuture == null &&
          lifecycleState.value != ProfileTourLifecycleState.cancelled &&
          lifecycleState.value != ProfileTourLifecycleState.completed) {
        _setLifecycleState(ProfileTourLifecycleState.idle);
      }
    }
    return sessionFuture;
  }

  bool _canContinueStart(int generation) {
    return !_isDisposed && generation == _generation && _entry == null;
  }

  Future<bool> _prepareTransition(
    int generation,
    int stepIndex,
    ProfileTourPrepareStep prepareStep,
  ) async {
    if (!_ownsActiveSession(generation)) {
      return false;
    }
    _setLifecycleState(ProfileTourLifecycleState.transitioning);
    final ready = await prepareStep(stepIndex);
    if (!_ownsActiveSession(generation)) {
      return false;
    }
    _setLifecycleState(ProfileTourLifecycleState.presenting);
    return ready;
  }

  bool _ownsActiveSession(int generation) {
    return !_isDisposed &&
        generation == _generation &&
        _entry != null &&
        _sessionCompleter != null;
  }

  Future<void> _finish(ProfileTourExitReason reason, int generation) async {
    if (!_ownsActiveSession(generation)) {
      return;
    }
    _isFinishing = true;
    final uid = _activeUid;
    final completer = _takeSessionCompleter();
    final shouldPersist =
        reason == ProfileTourExitReason.skipped ||
        reason == ProfileTourExitReason.completed;
    _setLifecycleState(
      shouldPersist
          ? ProfileTourLifecycleState.completing
          : ProfileTourLifecycleState.cancelled,
    );
    _removeEntry();
    try {
      if (shouldPersist) {
        await _preferences.markCompleted(uid);
      }
    } catch (_) {
      debugPrint('Profile guided-tour completion could not be persisted.');
    } finally {
      _isFinishing = false;
      if (!_isDisposed && generation == _generation) {
        _setLifecycleState(
          shouldPersist
              ? ProfileTourLifecycleState.completed
              : ProfileTourLifecycleState.cancelled,
        );
      }
    }
    _completeSession(completer, reason);
  }

  void cancel() {
    final hadPendingSession =
        _isStarting || _entry != null || _sessionCompleter != null;
    _generation += 1;
    final completer = _takeSessionCompleter();
    _removeEntry();
    if (hadPendingSession) {
      _setLifecycleState(ProfileTourLifecycleState.cancelled);
    }
    _completeSession(completer, ProfileTourExitReason.cancelled);
  }

  void _setLifecycleState(ProfileTourLifecycleState state) {
    if (!_isDisposed && lifecycleState.value != state) {
      lifecycleState.value = state;
    }
  }

  Completer<ProfileTourExitReason?>? _takeSessionCompleter() {
    final completer = _sessionCompleter;
    _sessionCompleter = null;
    return completer;
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
    _activeUid = '';
    if (isActive.value) isActive.value = false;
    layoutSnapshot.value = null;
  }

  void _completeSession(
    Completer<ProfileTourExitReason?>? completer,
    ProfileTourExitReason? reason,
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
    lifecycleState.dispose();
    layoutSnapshot.dispose();
  }
}

class ProfileGuidedTourOverlay extends StatefulWidget {
  const ProfileGuidedTourOverlay({
    super.key,
    required this.targets,
    required this.onExit,
    this.prepareStep,
    this.onLayoutSnapshot,
  });

  final ProfileTourTargets targets;
  final Future<void> Function(ProfileTourExitReason reason) onExit;
  final ProfileTourPrepareStep? prepareStep;
  final ValueChanged<ProfileTourLayoutSnapshot>? onLayoutSnapshot;

  @override
  State<ProfileGuidedTourOverlay> createState() =>
      _ProfileGuidedTourOverlayState();
}

class _ProfileGuidedTourOverlayState extends State<ProfileGuidedTourOverlay> {
  static const Duration _transitionDuration = Duration(milliseconds: 300);
  final List<ProfileTourTargetHandle> _tooltipTargets =
      List<ProfileTourTargetHandle>.generate(
        6,
        (_) => ProfileTourTargetHandle(),
      );
  final ProfileTourTargetHandle _controlPanelTarget = ProfileTourTargetHandle();
  final ProfileTourTargetHandle _preparationPanelTarget =
      ProfileTourTargetHandle();
  final Map<int, double> _tooltipHeights = <int, double>{};
  final Map<int, Rect> _stableTargetRects = <int, Rect>{};
  double? _controlPanelHeight;
  int _stepIndex = 0;
  bool _exitInFlight = false;
  bool _transitionInFlight = false;
  int? _preparingStepIndex;
  Size? _lastViewportSize;
  EdgeInsets? _lastSafePadding;
  double? _lastPanelBottom;
  ProfileTourLayoutSnapshot? _lastLayoutSnapshot;

  Iterable<ProfileTourTargetHandle> get _stepTargets =>
      <ProfileTourTargetHandle>[
        widget.targets.settings,
        widget.targets.bookings,
        widget.targets.addPet,
        widget.targets.postsTab,
        widget.targets.servicesTab,
        widget.targets.addService,
      ];

  @override
  void initState() {
    super.initState();
    for (final target in _stepTargets) {
      target.addListener(_handleTargetGeometryChanged);
    }
  }

  @override
  void didUpdateWidget(ProfileGuidedTourOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldTargets = <ProfileTourTargetHandle>[
      oldWidget.targets.settings,
      oldWidget.targets.bookings,
      oldWidget.targets.addPet,
      oldWidget.targets.postsTab,
      oldWidget.targets.servicesTab,
      oldWidget.targets.addService,
    ];
    for (final target in oldTargets) {
      target.removeListener(_handleTargetGeometryChanged);
    }
    for (final target in _stepTargets) {
      target.addListener(_handleTargetGeometryChanged);
    }
  }

  @override
  void dispose() {
    for (final target in _stepTargets) {
      target.removeListener(_handleTargetGeometryChanged);
    }
    super.dispose();
  }

  void _handleTargetGeometryChanged() {
    if (!mounted || _exitInFlight || _transitionInFlight) return;
    setState(() {});
  }

  static const List<_ProfileTourStepContent> _steps = <_ProfileTourStepContent>[
    _ProfileTourStepContent(
      tooltipTitle: 'Settings',
      tooltipDescription:
          'Manage your account, privacy, notifications, and other preferences from here.',
      panelTitle: 'Settings',
      panelDescription:
          'Manage your account, privacy, notifications, and other preferences from here.',
      semanticsLabel: 'Profile settings tour step',
    ),
    _ProfileTourStepContent(
      tooltipTitle: 'Bookings',
      tooltipDescription:
          'View your upcoming bookings and booking history. Service providers can also manage booking requests and service appointments here.',
      panelTitle: 'Bookings',
      panelDescription:
          'Track bookings, view history, and manage service requests.',
      semanticsLabel: 'Profile bookings tour step',
    ),
    _ProfileTourStepContent(
      tooltipTitle: 'Add Your Pet',
      tooltipDescription:
          'Add your pet and save their details to personalize your Pettxo experience.',
      panelTitle: 'Add Pet',
      panelDescription:
          'Create a pet profile with important details about your pet.',
      semanticsLabel: 'Profile add pet tour step',
    ),
    _ProfileTourStepContent(
      tooltipTitle: 'Posts',
      tooltipDescription: 'View all your posts, photos, and updates here.',
      panelTitle: 'Posts',
      panelDescription:
          'View your posts, photos, and updates from your profile.',
      semanticsLabel: 'Profile posts tour step',
    ),
    _ProfileTourStepContent(
      tooltipTitle: 'Services',
      tooltipDescription:
          'View all your listed services here. Other users can discover and book your services from your profile.',
      panelTitle: 'Services',
      panelDescription:
          'Manage your listed services and make them discoverable to pet owners.',
      semanticsLabel: 'Profile services tour step',
    ),
    _ProfileTourStepContent(
      tooltipTitle: 'Add Service',
      tooltipDescription:
          'Create a new service and share what you offer with pet lovers. Add service details, pricing, and availability to start receiving bookings.',
      panelTitle: 'Add Service',
      panelDescription:
          'Create a service, set your pricing and availability, and start receiving bookings.',
      semanticsLabel: 'Profile add service tour step',
    ),
  ];

  Future<void> _exit(ProfileTourExitReason reason) async {
    if (_exitInFlight) return;
    _exitInFlight = true;
    await widget.onExit(reason);
  }

  Future<void> _next() async {
    if (_transitionInFlight || _exitInFlight) return;
    if (_stepIndex >= _steps.length - 1) {
      unawaited(_exit(ProfileTourExitReason.completed));
      return;
    }
    final nextStep = _stepIndex + 1;
    _transitionInFlight = true;
    try {
      setState(() => _preparingStepIndex = nextStep);
      double? preparationPanelHeight;
      for (
        var frame = 0;
        frame < 3 && preparationPanelHeight == null;
        frame++
      ) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        preparationPanelHeight = _preparationPanelTarget.height;
      }
      if (preparationPanelHeight == null ||
          !_publishLayoutSnapshot(
            stepIndex: nextStep,
            panelHeight: preparationPanelHeight,
          )) {
        return;
      }
      var targetReady = await widget.prepareStep?.call(nextStep) ?? true;
      if (!mounted) return;
      if (targetReady) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        targetReady = _isTargetValidForSharedLayout(nextStep);
        if (!targetReady && widget.prepareStep != null) {
          targetReady = await widget.prepareStep!.call(nextStep);
          if (!mounted) return;
          if (targetReady) {
            await WidgetsBinding.instance.endOfFrame;
            if (!mounted) return;
            targetReady = _isTargetValidForSharedLayout(nextStep);
          }
        }
      }
      if (!targetReady) return;
      setState(() => _stepIndex = nextStep);
      await WidgetsBinding.instance.endOfFrame;
    } finally {
      if (mounted && _preparingStepIndex != null) {
        setState(() => _preparingStepIndex = null);
      }
      _transitionInFlight = false;
    }
  }

  bool _isTargetValidForSharedLayout(int stepIndex) {
    if (stepIndex < 2) return true;
    final snapshot = _lastLayoutSnapshot;
    final targetRect = measureProfileTourTarget(_targetKeyForStep(stepIndex));
    return snapshot != null &&
        snapshot.stepIndex == stepIndex &&
        targetRect != null &&
        isProfileTourTargetVisible(
          targetRect: targetRect,
          viewportWidth: snapshot.viewportSize.width,
          safeTop: snapshot.usableViewport.top,
          safeBottom: snapshot.usableViewport.bottom,
          spotlightPadding: stepIndex == 2 ? 5 : 6,
        );
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
          final estimatedPanelHeight =
              (compact ? 158.0 : 184.0) + ((textScale - 1) * 52);
          final panelHeight = _controlPanelHeight ?? estimatedPanelHeight;
          final panelBottom = calculateProfileTourPanelBottom(
            safeBottom: safePadding.bottom,
            compact: compact,
          );
          _lastViewportSize = size;
          _lastSafePadding = safePadding;
          _lastPanelBottom = panelBottom;
          final panelTop = size.height - panelBottom - panelHeight;
          final measuredTargetRect = _targetRect();
          final measuredTargetValid =
              measuredTargetRect != null &&
              (_stepIndex < 2 ||
                  isProfileTourTargetVisible(
                    targetRect: measuredTargetRect,
                    viewportWidth: size.width,
                    safeTop: safePadding.top + 88,
                    safeBottom: panelTop - 16,
                    spotlightPadding: _stepIndex == 2 ? 5 : 6,
                  ));
          if (measuredTargetValid) {
            _stableTargetRects[_stepIndex] = measuredTargetRect;
          }
          final stableTargetRect = _stableTargetRects[_stepIndex];
          final canUseStableTarget =
              stableTargetRect != null &&
              (measuredTargetRect == null || _transitionInFlight);
          final targetRect = measuredTargetValid
              ? measuredTargetRect
              : canUseStableTarget
              ? stableTargetRect
              : null;
          if (targetRect == null) {
            return const AbsorbPointer(child: SizedBox.expand());
          }
          final highlightRect = _expandedTargetRect(targetRect, size);
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
          final preparingStep = _preparingStepIndex;
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
                    painter: _ProfileTourScrimPainter(
                      highlightRect: highlightRect,
                      cornerRadius: _stepIndex == 2 ? 22 : 20,
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: highlightRect,
                  child: const IgnorePointer(
                    child: SizedBox(
                      key: ValueKey<String>('profile-tour-highlight-bounds'),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ProfileTourArrowPainter(
                        tooltipRect: tooltipRect,
                        targetRect: highlightRect,
                        stepIndex: _stepIndex,
                      ),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  key: const ValueKey<String>('profile-tour-tooltip-position'),
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
                      child: ProfileTourTarget(
                        key: ValueKey<int>(_stepIndex),
                        handle: _tooltipTargets[_stepIndex],
                        child: _ProfileTourTooltip(
                          step: step,
                          compact: compact,
                        ),
                      ),
                    ),
                  ),
                ),
                if (preparingStep != null)
                  Positioned(
                    left: compact ? 10 : 16,
                    right: compact ? 10 : 16,
                    bottom: panelBottom,
                    child: Offstage(
                      offstage: true,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: ProfileTourTarget(
                            handle: _preparationPanelTarget,
                            child: _ProfileTourControlPanel(
                              stepIndex: preparingStep,
                              step: _steps[preparingStep],
                              compact: compact,
                              onSkip: () {},
                              onNext: () {},
                            ),
                          ),
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
                      child: ProfileTourTarget(
                        handle: _controlPanelTarget,
                        child: _ProfileTourControlPanel(
                          stepIndex: _stepIndex,
                          step: step,
                          compact: compact,
                          onSkip: () {
                            unawaited(_exit(ProfileTourExitReason.skipped));
                          },
                          onNext: () => unawaited(_next()),
                        ),
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
    final tooltipHeight = _tooltipTargets[stepIndex].height;
    final panelHeight = _controlPanelTarget.height;
    final tooltipChanged =
        tooltipHeight != null &&
        ((_tooltipHeights[stepIndex] ?? -1) - tooltipHeight).abs() >= 0.5;
    final panelChanged =
        panelHeight != null &&
        ((_controlPanelHeight ?? -1) - panelHeight).abs() >= 0.5;
    if (tooltipChanged || panelChanged) {
      setState(() {
        if (tooltipChanged) _tooltipHeights[stepIndex] = tooltipHeight;
        if (panelChanged) _controlPanelHeight = panelHeight;
      });
    }
    if (panelHeight != null) {
      _publishLayoutSnapshot(stepIndex: stepIndex, panelHeight: panelHeight);
    }
  }

  bool _publishLayoutSnapshot({
    required int stepIndex,
    required double panelHeight,
  }) {
    final preparingStep = _preparingStepIndex;
    if (preparingStep != null && stepIndex != preparingStep) return false;
    final size = _lastViewportSize;
    final safePadding = _lastSafePadding;
    final panelBottom = _lastPanelBottom;
    if (size == null || safePadding == null || panelBottom == null) {
      return false;
    }
    final panelTop = size.height - panelBottom - panelHeight;
    final panelRect = Rect.fromLTWH(0, panelTop, size.width, panelHeight);
    final snapshot = ProfileTourLayoutSnapshot(
      stepIndex: stepIndex,
      viewportSize: size,
      safePadding: safePadding,
      panelRect: panelRect,
      usableViewport: Rect.fromLTRB(
        0,
        safePadding.top + 88,
        size.width,
        panelTop - 16,
      ),
    );
    _lastLayoutSnapshot = snapshot;
    widget.onLayoutSnapshot?.call(snapshot);
    return true;
  }

  Rect? _targetRect() {
    return measureProfileTourTarget(_targetKeyForStep(_stepIndex));
  }

  ProfileTourTargetHandle _targetKeyForStep(int stepIndex) {
    return switch (stepIndex) {
      0 => widget.targets.settings,
      1 => widget.targets.bookings,
      2 => widget.targets.addPet,
      3 => widget.targets.postsTab,
      4 => widget.targets.servicesTab,
      _ => widget.targets.addService,
    };
  }

  Rect _expandedTargetRect(Rect target, Size size) {
    final padding = _stepIndex == 2 ? 5.0 : 6.0;
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
    final width = (usableWidth * (_stepIndex == 0 ? 0.74 : 0.68))
        .clamp(
          math.min(220.0, usableWidth),
          math.min(_stepIndex == 0 ? 286.0 : 270.0, usableWidth),
        )
        .toDouble();
    final estimatedHeight = (compact ? 92.0 : 104.0) + ((textScale - 1) * 52);
    final height = measuredHeight ?? estimatedHeight;
    double left;
    double top;
    if (_stepIndex == 0) {
      left = size.width - width - margin;
      top = target.bottom + 18;
    } else {
      left = size.width - width - margin;
      final aboveTarget = target.top - height - 18;
      final belowTarget = target.bottom + 18;
      top =
          aboveTarget >= safePadding.top + 8 ||
              belowTarget + height > panelTop - 16
          ? aboveTarget
          : belowTarget;
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

class _ProfileTourStepContent {
  const _ProfileTourStepContent({
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

class _ProfileTourTooltip extends StatelessWidget {
  const _ProfileTourTooltip({required this.step, required this.compact});

  final _ProfileTourStepContent step;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _ProfileTourGlassCard(
      key: const ValueKey<String>('profile-tour-tooltip-card'),
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
            step.tooltipTitle,
            style: TextStyle(
              color: AppColors.primary,
              fontSize: compact ? 15 : 18.5,
              fontWeight: FontWeight.w800,
              height: 1.08,
            ),
          ),
          SizedBox(height: compact ? 4 : 6),
          Text(
            step.tooltipDescription,
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

class _ProfileTourControlPanel extends StatelessWidget {
  const _ProfileTourControlPanel({
    required this.stepIndex,
    required this.step,
    required this.compact,
    required this.onSkip,
    required this.onNext,
  });

  final int stepIndex;
  final _ProfileTourStepContent step;
  final bool compact;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _ProfileTourGlassCard(
      key: const ValueKey<String>('profile-tour-control-panel'),
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
            children: List<Widget>.generate(6, (index) {
              final selected = index == stepIndex;
              return AnimatedContainer(
                key: ValueKey<String>('profile-tour-progress-$index'),
                duration: const Duration(milliseconds: 300),
                width: selected ? 28 : 18,
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
                        step.panelTitle,
                        style: TextStyle(
                          color: AppColors.textDark,
                          fontSize: compact ? 14.5 : 18,
                          fontWeight: FontWeight.w800,
                          height: 1.08,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        step.panelDescription,
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
                  key: const ValueKey<String>('profile-tour-skip'),
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
                    key: const ValueKey<String>('profile-tour-next'),
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
                          stepIndex == 5 ? 'Got it' : 'Next',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: compact ? 13.5 : 15,
                          ),
                        ),
                        if (stepIndex != 5) ...[
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

class _ProfileTourGlassCard extends StatelessWidget {
  const _ProfileTourGlassCard({
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

class _ProfileTourScrimPainter extends CustomPainter {
  const _ProfileTourScrimPainter({
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
    // Keep blurred glow pixels outside the cutout. On narrow capsule targets,
    // an inward blur can otherwise wash over the real child painting (notably
    // the Bookings label) even though the scrim itself has a transparent hole.
    canvas.save();
    canvas.clipPath(scrimPath);
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
    canvas.restore();
    canvas.drawRRect(
      highlight,
      Paint()
        ..color = const Color(0xFFFFA06F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
  }

  @override
  bool shouldRepaint(_ProfileTourScrimPainter oldDelegate) {
    return oldDelegate.highlightRect != highlightRect ||
        oldDelegate.cornerRadius != cornerRadius;
  }
}

class _ProfileTourArrowPainter extends CustomPainter {
  const _ProfileTourArrowPainter({
    required this.tooltipRect,
    required this.targetRect,
    required this.stepIndex,
  });

  final Rect tooltipRect;
  final Rect targetRect;
  final int stepIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = calculateProfileTourArrowGeometry(
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
    final head = calculateProfileTourArrowHead(geometry, arrowLength: 8);
    for (final paint in <Paint>[outline, orange]) {
      canvas.drawLine(geometry.end, head.firstWing, paint);
      canvas.drawLine(geometry.end, head.secondWing, paint);
    }
  }

  @override
  bool shouldRepaint(_ProfileTourArrowPainter oldDelegate) {
    return oldDelegate.tooltipRect != tooltipRect ||
        oldDelegate.targetRect != targetRect ||
        oldDelegate.stepIndex != stepIndex;
  }
}

ProfileTourArrowGeometry calculateProfileTourArrowGeometry({
  required int stepIndex,
  required Rect tooltipRect,
  required Rect targetRect,
}) {
  assert(stepIndex >= 0 && stepIndex < 6);
  const targetGap = 8.0;
  final targetIsAboveTooltip = targetRect.center.dy < tooltipRect.center.dy;
  final start = Offset(tooltipRect.left - 1, tooltipRect.center.dy);
  final canPointToLeftEdge = targetRect.left - targetGap >= 8;
  final end = canPointToLeftEdge
      ? Offset(targetRect.left - targetGap, targetRect.center.dy)
      : Offset(
          targetRect.left + 24,
          targetIsAboveTooltip
              ? targetRect.bottom + targetGap
              : targetRect.top - targetGap,
        );
  final horizontalTravel = (end.dx - start.dx).abs();
  final verticalTravel = (end.dy - start.dy).abs();
  final outwardReach = (36 + horizontalTravel * 0.18 + verticalTravel * 0.06)
      .clamp(38.0, 70.0);
  final outwardX = start.dx - outwardReach;
  final targetIsRightOfTooltip = end.dx > tooltipRect.left;
  final outsideTooltipY = targetIsAboveTooltip
      ? math.min(end.dy, tooltipRect.top - 40)
      : math.max(end.dy, tooltipRect.bottom + 40);
  return ProfileTourArrowGeometry(
    start: start,
    control1: Offset(outwardX, start.dy),
    control2: targetIsRightOfTooltip
        ? Offset(outwardX, outsideTooltipY)
        : canPointToLeftEdge
        ? Offset(end.dx - 20, end.dy)
        : Offset(end.dx, end.dy + (targetIsAboveTooltip ? 20 : -20)),
    end: end,
  );
}

double calculateProfileTourPanelBottom({
  required double safeBottom,
  required bool compact,
}) {
  final navigationShellClearance = compact ? 56.0 : 64.0;
  return math.max(0, safeBottom) + navigationShellClearance;
}

double calculateProfileTourScrollSpacer({
  required double viewportHeight,
  required double normalBottomPadding,
}) {
  final bottomObstruction = viewportHeight < 650 ? 258.0 : 280.0;
  const spotlightAndPanelClearance = 16.0;
  return math.max(
    0,
    bottomObstruction + spotlightAndPanelClearance - normalBottomPadding,
  );
}

ProfileTourArrowHead calculateProfileTourArrowHead(
  ProfileTourArrowGeometry geometry, {
  double arrowLength = 8,
}) {
  final angle = math.atan2(
    geometry.end.dy - geometry.control2.dy,
    geometry.end.dx - geometry.control2.dx,
  );
  return ProfileTourArrowHead(
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

double calculateProfileTourScrollOffset({
  required double currentOffset,
  required double minScrollExtent,
  required double maxScrollExtent,
  required Rect targetRect,
  required double headerBottom,
  required double viewportHeight,
  required double bottomObstruction,
  double spotlightPadding = 0,
  Rect? usableViewport,
}) {
  const gap = 14.0;
  final safeTop = usableViewport?.top ?? headerBottom + gap;
  final safeBottom =
      usableViewport?.bottom ??
      math.max(safeTop, viewportHeight - bottomObstruction);
  final paddedTarget = targetRect.inflate(spotlightPadding);
  var delta = 0.0;
  if (paddedTarget.top < safeTop) {
    delta = paddedTarget.top - safeTop;
  } else if (paddedTarget.bottom > safeBottom) {
    delta = math.min(
      paddedTarget.bottom - safeBottom,
      paddedTarget.top - safeTop,
    );
  }
  return (currentOffset + delta)
      .clamp(minScrollExtent, maxScrollExtent)
      .toDouble();
}

Rect? measureProfileTourTarget(ProfileTourTargetHandle target) => target.rect;

bool isProfileTourInitialTargetReady({
  required Rect targetRect,
  required Size viewportSize,
  required EdgeInsets safePadding,
}) {
  return targetRect.isFinite &&
      targetRect.width > 0 &&
      targetRect.height > 0 &&
      targetRect.left >= 0 &&
      targetRect.right <= viewportSize.width &&
      targetRect.top >= safePadding.top &&
      targetRect.bottom <= viewportSize.height - safePadding.bottom;
}

bool isProfileTourTargetVisible({
  required Rect targetRect,
  required double viewportWidth,
  required double safeTop,
  required double safeBottom,
  double spotlightPadding = 0,
  double tolerance = 0.5,
}) {
  final paddedTarget = targetRect.inflate(spotlightPadding);
  return targetRect.isFinite &&
      targetRect.width > 0 &&
      targetRect.height > 0 &&
      paddedTarget.left >= -tolerance &&
      paddedTarget.right <= viewportWidth + tolerance &&
      paddedTarget.top >= safeTop - tolerance &&
      paddedTarget.bottom <= safeBottom + tolerance;
}

Future<bool> revealProfileTourTarget({
  required BuildContext context,
  required ScrollController scrollController,
  required ProfileTourTargetHandle targetKey,
  required double headerBottom,
  required double bottomObstruction,
  double spotlightPadding = 0,
  Rect? usableViewport,
  bool Function()? canContinue,
  int maxAttempts = 5,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted ||
        !scrollController.hasClients ||
        (canContinue != null && !canContinue())) {
      return false;
    }

    final targetRect = measureProfileTourTarget(targetKey);
    if (targetRect == null) {
      final position = scrollController.position;
      final discoveryOffset =
          (scrollController.offset +
                  math.max(72, position.viewportDimension * 0.25))
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble();
      if ((discoveryOffset - scrollController.offset).abs() < 0.5) {
        break;
      }
      try {
        await scrollController.animateTo(
          discoveryOffset,
          duration: Duration(milliseconds: attempt == 0 ? 220 : 120),
          curve: Curves.easeInOutCubic,
        );
      } catch (_) {
        if (!context.mounted) {
          return false;
        }
      }
      continue;
    }
    final viewportSize = MediaQuery.sizeOf(context);
    const gap = 14.0;
    final safeTop = usableViewport?.top ?? headerBottom + gap;
    final safeBottom =
        usableViewport?.bottom ??
        math.max(safeTop, viewportSize.height - bottomObstruction);
    if (isProfileTourTargetVisible(
      targetRect: targetRect,
      viewportWidth: viewportSize.width,
      safeTop: safeTop,
      safeBottom: safeBottom,
      spotlightPadding: spotlightPadding,
    )) {
      return true;
    }

    final desiredOffset = calculateProfileTourScrollOffset(
      currentOffset: scrollController.offset,
      minScrollExtent: scrollController.position.minScrollExtent,
      maxScrollExtent: scrollController.position.maxScrollExtent,
      targetRect: targetRect,
      headerBottom: headerBottom,
      viewportHeight: viewportSize.height,
      bottomObstruction: bottomObstruction,
      spotlightPadding: spotlightPadding,
      usableViewport: usableViewport,
    );
    if ((desiredOffset - scrollController.offset).abs() < 0.5) {
      break;
    }

    try {
      await scrollController.animateTo(
        desiredOffset,
        duration: Duration(milliseconds: attempt == 0 ? 220 : 120),
        curve: Curves.easeInOutCubic,
      );
    } catch (_) {
      if (!context.mounted) {
        return false;
      }
    }
  }

  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted ||
      !scrollController.hasClients ||
      (canContinue != null && !canContinue())) {
    return false;
  }
  final targetRect = measureProfileTourTarget(targetKey);
  if (targetRect == null) return false;
  final viewportSize = MediaQuery.sizeOf(context);
  const gap = 14.0;
  return isProfileTourTargetVisible(
    targetRect: targetRect,
    viewportWidth: viewportSize.width,
    safeTop: usableViewport?.top ?? headerBottom + gap,
    safeBottom:
        usableViewport?.bottom ??
        math.max(headerBottom + gap, viewportSize.height - bottomObstruction),
    spotlightPadding: spotlightPadding,
  );
}

class ProfileTourArrowGeometry {
  const ProfileTourArrowGeometry({
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

class ProfileTourArrowHead {
  const ProfileTourArrowHead({
    required this.firstWing,
    required this.secondWing,
  });

  final Offset firstWing;
  final Offset secondWing;
}
