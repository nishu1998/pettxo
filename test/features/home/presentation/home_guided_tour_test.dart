import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/home/data/home_tour_preference_service.dart';
import 'package:pettexo/features/home/presentation/widgets/home_guided_tour.dart';

void main() {
  late _MemoryHomeTourStore store;
  late HomeGuidedTourController controller;
  late HomeTourTargetHandle feedTarget;
  late GlobalKey feedKey;
  late GlobalKey createPostKey;
  late GlobalKey notificationsKey;
  late int createPostTaps;
  late int notificationTaps;

  setUp(() {
    HomeTourPreferenceService.clearSessionCompletionsForTesting();
    store = _MemoryHomeTourStore();
    controller = HomeGuidedTourController(
      preferences: HomeTourPreferenceService(store: store),
    );
    feedTarget = HomeTourTargetHandle();
    feedKey = GlobalKey();
    createPostKey = GlobalKey();
    notificationsKey = GlobalKey();
    createPostTaps = 0;
    notificationTaps = 0;
  });

  tearDown(() {
    controller.dispose();
    feedTarget.dispose();
  });

  Future<BuildContext> pumpHarness(
    WidgetTester tester, {
    ValueNotifier<Rect>? feedLayout,
  }) async {
    Widget feedTargetWidget({Key? key}) {
      return HomeTourTarget(
        key: key,
        handle: feedTarget,
        child: Container(
          key: feedKey,
          color: Colors.white,
          child: const Text('Real feed'),
        ),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              if (feedLayout == null)
                Positioned(
                  left: 16,
                  right: 16,
                  top: 210,
                  height: 170,
                  child: feedTargetWidget(),
                )
              else
                ValueListenableBuilder<Rect>(
                  valueListenable: feedLayout,
                  builder: (_, rect, _) => Positioned.fromRect(
                    rect: rect,
                    child: feedTargetWidget(key: ValueKey<Rect>(rect)),
                  ),
                ),
              Positioned(
                left: 16,
                top: 28,
                child: IconButton(
                  key: createPostKey,
                  onPressed: () => createPostTaps += 1,
                  icon: const Icon(Icons.add),
                ),
              ),
              Positioned(
                right: 16,
                top: 28,
                child: IconButton(
                  key: notificationsKey,
                  onPressed: () => notificationTaps += 1,
                  icon: const Icon(Icons.notifications),
                ),
              ),
              const Center(child: SizedBox(key: ValueKey<String>('tour-host'))),
            ],
          ),
        ),
      ),
    );
    return tester.element(find.byKey(const ValueKey<String>('tour-host')));
  }

  HomeTourTargets targets() => HomeTourTargets(
    feed: feedTarget,
    createPost: createPostKey,
    notifications: notificationsKey,
  );

  Rect spotlightRect(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey<String>('home-tour-spotlight')),
    );
    return (paint.painter! as HomeTourScrimPainter).highlightRect;
  }

  Future<Future<HomeTourExitReason?>> startTour(
    WidgetTester tester, {
    String uid = 'user-a',
    HomeTourTargets? customTargets,
  }) async {
    final context = await pumpHarness(tester);
    final session = controller.start(
      context: context,
      uid: uid,
      targets: customTargets ?? targets(),
    );
    await tester.pump();
    return session;
  }

  testWidgets('first eligible authenticated user sees step one', (
    tester,
  ) async {
    await startTour(tester);

    expect(find.text('Welcome to Home'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(controller.isActive.value, isTrue);
  });

  testWidgets('overlay waits for final target readiness before insertion', (
    tester,
  ) async {
    final context = await pumpHarness(tester);
    final readiness = Completer<bool>();
    final session = controller.start(
      context: context,
      uid: 'user-a',
      targets: targets(),
      beforeShow: () => readiness.future,
    );
    await tester.pump();
    expect(find.text('Welcome to Home'), findsNothing);

    readiness.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Home'), findsOneWidget);

    controller.cancel();
    await tester.pump();
    expect(await session, HomeTourExitReason.cancelled);
  });

  testWidgets('glass cards stay compact on a small standard phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await startTour(tester);
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsNWidgets(2));
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('home-tour-tooltip-card')))
          .height,
      lessThan(175),
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('home-tour-control-panel')),
          )
          .height,
      lessThan(190),
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in const <Size>[
    Size(360, 640),
    Size(393, 852),
    Size(412, 915),
  ]) {
    testWidgets(
      'step layouts remain in bounds at ${size.width}x${size.height}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await startTour(tester);
        await tester.pumpAndSettle();

        final feedRect = tester.getRect(find.byKey(feedKey));
        final homeTooltip = tester.getRect(
          find.byKey(const ValueKey<String>('home-tour-tooltip-card')),
        );
        final controlPanel = tester.getRect(
          find.byKey(const ValueKey<String>('home-tour-control-panel')),
        );
        expect(homeTooltip.left, greaterThanOrEqualTo(0));
        expect(homeTooltip.right, lessThanOrEqualTo(size.width));
        expect(homeTooltip.top, greaterThanOrEqualTo(0));
        expect(homeTooltip.bottom, lessThan(controlPanel.top));
        expect(homeTooltip.bottom, lessThan(feedRect.top));
        expect(homeTooltip.overlaps(feedRect), isFalse);
        expect(controlPanel.bottom, lessThanOrEqualTo(size.height - 80));

        await tester.tap(find.byKey(const ValueKey<String>('home-tour-next')));
        await tester.pumpAndSettle();
        final createTarget = tester.getRect(find.byKey(createPostKey));
        final createTooltip = tester.getRect(
          find.byKey(const ValueKey<String>('home-tour-tooltip-card')),
        );
        expect(createTooltip.top, greaterThan(createTarget.bottom));
        expect(createTooltip.overlaps(createTarget), isFalse);
        expect(createTooltip.right, lessThanOrEqualTo(size.width));

        await tester.tap(find.byKey(const ValueKey<String>('home-tour-next')));
        await tester.pumpAndSettle();
        final notificationTarget = tester.getRect(find.byKey(notificationsKey));
        final notificationTooltip = tester.getRect(
          find.byKey(const ValueKey<String>('home-tour-tooltip-card')),
        );
        expect(notificationTooltip.top, greaterThan(notificationTarget.bottom));
        expect(notificationTooltip.overlaps(notificationTarget), isFalse);
        expect(notificationTooltip.left, greaterThanOrEqualTo(0));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('larger text stays readable without colliding with controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await startTour(tester);
    await tester.pumpAndSettle();

    final tooltip = tester.getRect(
      find.byKey(const ValueKey<String>('home-tour-tooltip-card')),
    );
    final controls = tester.getRect(
      find.byKey(const ValueKey<String>('home-tour-control-panel')),
    );
    expect(tooltip.bottom, lessThan(controls.top));
    expect(find.textContaining('Pettxo community'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('home-tour-next')));
    await tester.pumpAndSettle();
    expect(find.text('Create a Post'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('home-tour-next')));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  test('header arrowheads stop eight pixels outside spotlight bounds', () {
    const createTarget = Rect.fromLTWH(20, 20, 64, 64);
    const createTooltip = Rect.fromLTWH(70, 132, 286, 120);
    final createGeometry = calculateHomeTourArrowGeometry(
      stepIndex: 1,
      tooltipRect: createTooltip,
      targetRect: createTarget,
    );
    expect(createGeometry.end.dy - createTarget.bottom, 8);
    expect(createTarget.contains(createGeometry.end), isFalse);
    expect(createGeometry.end.dx, createTarget.center.dx);

    const notificationTarget = Rect.fromLTWH(309, 20, 64, 64);
    const notificationTooltip = Rect.fromLTWH(18, 132, 286, 120);
    final notificationGeometry = calculateHomeTourArrowGeometry(
      stepIndex: 2,
      tooltipRect: notificationTooltip,
      targetRect: notificationTarget,
    );
    expect(notificationGeometry.end.dy - notificationTarget.bottom, 8);
    expect(notificationTarget.contains(notificationGeometry.end), isFalse);
    expect(notificationGeometry.end.dx, notificationTarget.center.dx);
  });

  test('Home arrow leaves the tooltip left side and stops before the feed', () {
    const feedTarget = Rect.fromLTWH(12, 206, 369, 220);
    const tooltip = Rect.fromLTWH(82, 42, 293, 120);
    final geometry = calculateHomeTourArrowGeometry(
      stepIndex: 0,
      tooltipRect: tooltip,
      targetRect: feedTarget,
    );

    expect(geometry.start.dx, tooltip.left - 1);
    expect(geometry.start.dy, tooltip.center.dy);
    expect(feedTarget.contains(geometry.end), isFalse);
    expect(feedTarget.top - geometry.end.dy, 8);
    expect(geometry.end.dx, greaterThan(feedTarget.left));
    expect(geometry.end.dx, lessThan(feedTarget.right));
    expect(geometry.control2.dy, lessThan(geometry.end.dy));
    expect(tooltip.contains(geometry.end), isFalse);
  });

  test('Home spotlight tightly follows the measured feed content', () {
    const target = Rect.fromLTWH(16, 210, 361, 170);
    final highlight = calculateHomeTourHighlightRect(
      stepIndex: 0,
      targetRect: target,
      viewportSize: const Size(393, 852),
    );

    expect(highlight, const Rect.fromLTRB(12, 206, 381, 384));
    expect(highlight.top, greaterThan(200));
  });

  test('partially visible media is clipped to the intentional usable area', () {
    final visible = calculateHomeTourVisibleFeedRect(
      targetRect: const Rect.fromLTWH(16, 72, 361, 640),
      viewportSize: const Size(393, 852),
      safePadding: const EdgeInsets.only(top: 24, bottom: 24),
      panelTop: 602,
    );

    expect(visible, const Rect.fromLTRB(16, 100, 377, 586));
    expect(visible.height, greaterThan(96));
  });

  test('restored scroll positions request only the required reveal delta', () {
    expect(
      calculateHomeTourRevealScrollDelta(
        targetRect: const Rect.fromLTWH(16, 54, 361, 220),
        usableTop: 100,
        usableBottom: 586,
      ),
      -46,
    );
    expect(
      calculateHomeTourRevealScrollDelta(
        targetRect: const Rect.fromLTWH(16, 550, 361, 220),
        usableTop: 100,
        usableBottom: 586,
      ),
      60,
    );
  });

  testWidgets(
    'Step 1 follows replacement media and changed aspect ratio after insertion',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final layout = ValueNotifier<Rect>(
        const Rect.fromLTWH(16, 210, 361, 150),
      );
      addTearDown(layout.dispose);
      final context = await pumpHarness(tester, feedLayout: layout);
      controller.start(context: context, uid: 'user-a', targets: targets());
      await tester.pumpAndSettle();

      expect(spotlightRect(tester), const Rect.fromLTRB(12, 206, 381, 364));

      layout.value = const Rect.fromLTWH(16, 190, 361, 260);
      await tester.pumpAndSettle();

      expect(spotlightRect(tester), const Rect.fromLTRB(12, 186, 381, 454));
      final tooltip = tester.getRect(
        find.byKey(const ValueKey<String>('home-tour-tooltip-card')),
      );
      expect(tooltip.bottom, lessThan(spotlightRect(tester).top));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('interrupted tour reopens with only the new route target', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final firstLayout = ValueNotifier<Rect>(
      const Rect.fromLTWH(16, 210, 361, 150),
    );
    addTearDown(firstLayout.dispose);
    var context = await pumpHarness(tester, feedLayout: firstLayout);
    final firstSession = controller.start(
      context: context,
      uid: 'user-a',
      targets: targets(),
    );
    await tester.pumpAndSettle();
    expect(spotlightRect(tester).top, 206);

    controller.cancel();
    await tester.pump();
    expect(await firstSession, HomeTourExitReason.cancelled);
    expect(store.values['home_tour_v1_user-a'], isNull);

    final oldController = controller;
    final oldTarget = feedTarget;
    await tester.pumpWidget(const SizedBox());
    oldController.dispose();
    oldTarget.dispose();

    controller = HomeGuidedTourController(
      preferences: HomeTourPreferenceService(store: store),
    );
    feedTarget = HomeTourTargetHandle();
    feedKey = GlobalKey();
    createPostKey = GlobalKey();
    notificationsKey = GlobalKey();
    final reopenedLayout = ValueNotifier<Rect>(
      const Rect.fromLTWH(16, 245, 361, 230),
    );
    addTearDown(reopenedLayout.dispose);
    context = await pumpHarness(tester, feedLayout: reopenedLayout);
    controller.start(context: context, uid: 'user-a', targets: targets());
    await tester.pumpAndSettle();

    expect(spotlightRect(tester), const Rect.fromLTRB(12, 241, 381, 479));
    expect(find.text('Welcome to Home'), findsOneWidget);
    expect(store.values['home_tour_v1_user-a'], isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unchanged render bounds do not schedule repeated updates', (
    tester,
  ) async {
    var notifications = 0;
    feedTarget.addListener(() => notifications += 1);
    await pumpHarness(tester);
    await tester.pump();
    final settledNotifications = notifications;

    for (var index = 0; index < 8; index += 1) {
      await tester.pump();
    }

    expect(settledNotifications, greaterThan(0));
    expect(notifications, settledNotifications);
  });

  testWidgets('Next advances exactly from step 1 to 2 to 3', (tester) async {
    await startTour(tester);

    await tester.tap(find.byKey(const ValueKey<String>('home-tour-next')));
    await tester.pumpAndSettle();
    expect(find.text('Create a Post'), findsOneWidget);
    expect(find.text('Create Post'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('home-tour-next')));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsNWidgets(2));
    expect(find.text('Got it'), findsOneWidget);
  });

  testWidgets('Skip closes and persists completion', (tester) async {
    final session = await startTour(tester);

    await tester.tap(find.byKey(const ValueKey<String>('home-tour-skip')));
    await tester.pumpAndSettle();

    expect(await session, HomeTourExitReason.skipped);
    expect(store.values['home_tour_v1_user-a'], isTrue);
    expect(find.text('Welcome to Home'), findsNothing);
  });

  testWidgets('Got it closes and persists completion', (tester) async {
    final session = await startTour(tester);
    await tester.tap(find.byKey(const ValueKey<String>('home-tour-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('home-tour-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('home-tour-next')));
    await tester.pumpAndSettle();

    expect(await session, HomeTourExitReason.completed);
    expect(store.values['home_tour_v1_user-a'], isTrue);
  });

  testWidgets('completed users do not see the automatic tour', (tester) async {
    store.values['home_tour_v1_user-a'] = true;
    final session = await startTour(tester);

    expect(await session, isNull);
    expect(find.text('Welcome to Home'), findsNothing);
    expect(controller.isActive.value, isFalse);
  });

  testWidgets('completion remains independent for another UID', (tester) async {
    store.values['home_tour_v1_user-a'] = true;
    await startTour(tester, uid: 'user-b');

    expect(find.text('Welcome to Home'), findsOneWidget);
    expect(store.values['home_tour_v1_user-b'], isNull);
  });

  testWidgets('duplicate starts never create duplicate overlays', (
    tester,
  ) async {
    await startTour(tester);
    final context = tester.element(
      find.byKey(const ValueKey<String>('tour-host')),
    );
    final duplicate = controller.start(
      context: context,
      uid: 'user-a',
      targets: targets(),
    );
    await tester.pump();

    expect(await duplicate, isNull);
    expect(find.text('Welcome to Home'), findsOneWidget);
  });

  testWidgets('an inactive Home route cannot start its tour', (tester) async {
    final context = await pumpHarness(tester);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Active route')),
      ),
    );
    await tester.pumpAndSettle();

    final session = await controller.start(
      context: context,
      uid: 'user-a',
      targets: targets(),
    );

    expect(session, isNull);
    expect(find.text('Welcome to Home'), findsNothing);
    expect(find.text('Active route'), findsOneWidget);
  });

  testWidgets('missing targets use fallbacks and disposal cancels safely', (
    tester,
  ) async {
    final missingFeed = HomeTourTargetHandle();
    addTearDown(missingFeed.dispose);
    final session = await startTour(
      tester,
      customTargets: HomeTourTargets(
        feed: missingFeed,
        createPost: GlobalKey(),
        notifications: GlobalKey(),
      ),
    );
    expect(find.text('Welcome to Home'), findsOneWidget);

    controller.dispose();
    await tester.pump();

    expect(await session, HomeTourExitReason.cancelled);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overlay blocks background and actions work after it closes', (
    tester,
  ) async {
    await startTour(tester);

    await tester.tap(find.byKey(createPostKey), warnIfMissed: false);
    await tester.tap(find.byKey(notificationsKey), warnIfMissed: false);
    expect(createPostTaps, 0);
    expect(notificationTaps, 0);

    await tester.tap(find.byKey(const ValueKey<String>('home-tour-skip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(createPostKey));
    await tester.tap(find.byKey(notificationsKey));

    expect(createPostTaps, 1);
    expect(notificationTaps, 1);
  });
}

class _MemoryHomeTourStore implements HomeTourCompletionStore {
  final Map<String, bool> values = <String, bool>{};

  @override
  Future<bool> read(String key) async => values[key] ?? false;

  @override
  Future<void> write(String key, bool value) async {
    values[key] = value;
  }
}
