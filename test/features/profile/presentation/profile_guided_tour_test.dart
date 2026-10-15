import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/profile/data/profile_tour_preference_service.dart';
import 'package:pettexo/features/profile/domain/models/profile_service_listing.dart';
import 'package:pettexo/features/profile/presentation/widgets/profile_content_sections.dart';
import 'package:pettexo/features/profile/presentation/widgets/profile_guided_tour.dart';

const _profileServiceFixture = ProfileServiceListing(
  id: 'service-1',
  title: 'Dog walking',
  serviceType: 'Walking',
  description: 'A reliable neighborhood walk.',
  rate: '₹250',
  location: 'Pune',
  availability: 'Weekdays',
  duration: '30 min',
  petSize: 'All sizes',
  rating: 'No reviews yet',
  distance: '',
  imageUrl: '',
);

void main() {
  late _MemoryProfileTourStore store;
  late ProfileGuidedTourController controller;
  late List<GlobalKey> targetKeys;
  late List<ProfileTourTargetHandle> targetHandles;
  late int backgroundTaps;

  setUp(() {
    ProfileTourPreferenceService.clearSessionCompletionsForTesting();
    store = _MemoryProfileTourStore();
    controller = ProfileGuidedTourController(
      preferences: ProfileTourPreferenceService(store: store),
    );
    targetKeys = List<GlobalKey>.generate(6, (_) => GlobalKey());
    targetHandles = List<ProfileTourTargetHandle>.generate(
      6,
      (_) => ProfileTourTargetHandle(),
    );
    backgroundTaps = 0;
  });

  tearDown(() => controller.dispose());

  ProfileTourTargets targets() => ProfileTourTargets(
    settings: targetHandles[0],
    bookings: targetHandles[1],
    addPet: targetHandles[2],
    postsTab: targetHandles[3],
    servicesTab: targetHandles[4],
    addService: targetHandles[5],
  );

  Future<BuildContext> pumpHarness(
    WidgetTester tester, {
    bool includeAddService = true,
    ValueNotifier<bool>? settingsTargetVisibility,
    ValueNotifier<double>? postsTargetTop,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => backgroundTaps += 1,
                child: const SizedBox.expand(),
              ),
              Positioned(
                right: 18,
                top: 30,
                width: 48,
                height: 48,
                child: settingsTargetVisibility == null
                    ? ProfileTourTarget(
                        handle: targetHandles[0],
                        child: SizedBox(key: targetKeys[0]),
                      )
                    : ValueListenableBuilder<bool>(
                        valueListenable: settingsTargetVisibility,
                        builder: (context, visible, child) => visible
                            ? ProfileTourTarget(
                                handle: targetHandles[0],
                                child: SizedBox(key: targetKeys[0]),
                              )
                            : const SizedBox(),
                      ),
              ),
              Positioned(
                key: targetKeys[1],
                right: 18,
                top: 156,
                width: 158,
                height: 46,
                child: ProfileTourTarget(
                  handle: targetHandles[1],
                  child: const Center(child: Text('Bookings')),
                ),
              ),
              Positioned(
                key: targetKeys[2],
                left: 104,
                top: 238,
                width: 74,
                height: 92,
                child: ProfileTourTarget(
                  handle: targetHandles[2],
                  child: const SizedBox(),
                ),
              ),
              const Positioned(
                left: 18,
                top: 210,
                width: 174,
                height: 108,
                child: SizedBox(
                  key: ValueKey<String>('profile-pet-tiles-fixture'),
                ),
              ),
              const Positioned(
                left: 18,
                right: 18,
                top: 92,
                height: 72,
                child: SizedBox(
                  key: ValueKey<String>('profile-spotlight-fixture'),
                ),
              ),
              if (postsTargetTop == null)
                Positioned(
                  key: targetKeys[3],
                  left: 18,
                  top: 346,
                  width: 174,
                  height: 42,
                  child: ProfileTourTarget(
                    handle: targetHandles[3],
                    child: const SizedBox(),
                  ),
                )
              else
                ValueListenableBuilder<double>(
                  valueListenable: postsTargetTop,
                  builder: (context, top, child) => Positioned(
                    key: targetKeys[3],
                    left: 18,
                    top: top,
                    width: 174,
                    height: 42,
                    child: ProfileTourTarget(
                      handle: targetHandles[3],
                      child: const SizedBox(),
                    ),
                  ),
                ),
              Positioned(
                key: targetKeys[4],
                right: 18,
                top: 346,
                width: 174,
                height: 42,
                child: ProfileTourTarget(
                  handle: targetHandles[4],
                  child: const SizedBox(),
                ),
              ),
              if (includeAddService)
                Positioned(
                  key: targetKeys[5],
                  left: 18,
                  right: 18,
                  top: 346,
                  height: 42,
                  child: ProfileTourTarget(
                    handle: targetHandles[5],
                    child: const SizedBox(),
                  ),
                ),
              const Center(
                child: SizedBox(key: ValueKey<String>('profile-tour-host')),
              ),
            ],
          ),
        ),
      ),
    );
    return tester.element(find.byKey(const ValueKey('profile-tour-host')));
  }

  Future<Future<ProfileTourExitReason?>> startTour(
    WidgetTester tester, {
    String uid = 'user-a',
    bool includeAddService = true,
    ProfileTourPrepareStep? prepareStep,
  }) async {
    final context = await pumpHarness(
      tester,
      includeAddService: includeAddService,
    );
    final session = controller.start(
      context: context,
      uid: uid,
      targets: targets(),
      prepareStep: prepareStep,
    );
    await tester.pump();
    return session;
  }

  testWidgets('tour follows the exact six-step order', (tester) async {
    await startTour(tester);
    const expectedTitles = <String>[
      'Settings',
      'Bookings',
      'Add Pet',
      'Posts',
      'Services',
      'Add Service',
    ];

    for (var step = 0; step < expectedTitles.length; step += 1) {
      expect(find.text(expectedTitles[step]), findsWidgets);
      expect(
        find.byKey(ValueKey<String>('profile-tour-progress-$step')),
        findsOne,
      );
      if (step < expectedTitles.length - 1) {
        await tester.tap(find.byKey(const ValueKey('profile-tour-next')));
        await tester.pumpAndSettle();
      }
    }
    expect(find.text('Got it'), findsOne);
  });

  testWidgets('repeated rebuilt six-step walkthroughs complete once each', (
    tester,
  ) async {
    final postsTargetTop = ValueNotifier<double>(346);
    addTearDown(postsTargetTop.dispose);
    final context = await pumpHarness(tester, postsTargetTop: postsTargetTop);

    for (var run = 0; run < 3; run += 1) {
      final session = controller.start(
        context: context,
        uid: 'repeat-user-$run',
        targets: targets(),
      );
      await tester.pumpAndSettle();
      for (var step = 0; step < 5; step += 1) {
        if (step == 2) {
          postsTargetTop.value = 346 + run.toDouble();
          await tester.pump();
        }
        await tester.tap(find.byKey(const ValueKey('profile-tour-next')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('profile-tour-next')));
      await tester.pumpAndSettle();

      expect(await session, ProfileTourExitReason.completed);
      expect(store.values['profile_tour_v1_repeat-user-$run'], isTrue);
      expect(controller.isActive.value, isFalse);
      expect(find.byType(ProfileGuidedTourOverlay), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('prepareStep runs before each Profile transition', (
    tester,
  ) async {
    final preparedSteps = <int>[];
    await startTour(
      tester,
      prepareStep: (step) async {
        preparedSteps.add(step);
        return true;
      },
    );

    for (var step = 1; step < 6; step += 1) {
      await tester.tap(find.byKey(const ValueKey('profile-tour-next')));
      await tester.pumpAndSettle();
    }

    expect(preparedSteps, <int>[1, 2, 3, 4, 5]);
  });

  testWidgets('fast Next taps start only one step transition', (tester) async {
    final preparation = Completer<bool>();
    var preparationCalls = 0;
    final session = await startTour(
      tester,
      prepareStep: (step) {
        preparationCalls += 1;
        return preparation.future;
      },
    );

    final nextButton = find.byKey(const ValueKey('profile-tour-next'));
    await tester.tap(nextButton);
    await tester.pump();
    await tester.tap(nextButton);
    await tester.pump();

    expect(preparationCalls, 1);
    expect(
      find.byKey(const ValueKey<String>('profile-tour-progress-0')),
      findsOneWidget,
    );

    preparation.complete(true);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('profile-tour-progress-1')),
      findsOneWidget,
    );

    controller.cancel();
    await tester.pumpAndSettle();
    expect(await session, ProfileTourExitReason.cancelled);
  });

  testWidgets('pause and resume do not duplicate or dismiss the session', (
    tester,
  ) async {
    final session = await startTour(tester);
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(controller.isActive.value, isTrue);
    expect(find.byType(ProfileGuidedTourOverlay), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('profile-tour-progress-0')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    controller.cancel();
    await tester.pumpAndSettle();
    expect(await session, ProfileTourExitReason.cancelled);
    expect(store.values, isEmpty);
  });

  testWidgets('Step 1 is prepared before the overlay is inserted', (
    tester,
  ) async {
    final context = await pumpHarness(tester);
    final initialTarget = Completer<bool>();

    final session = controller.start(
      context: context,
      uid: 'user-a',
      targets: targets(),
      prepareInitial: () => initialTarget.future,
    );
    await tester.pump();

    expect(
      controller.lifecycleState.value,
      ProfileTourLifecycleState.preparingTarget,
    );
    expect(controller.isActive.value, isFalse);
    expect(
      find.byKey(const ValueKey('profile-tour-control-panel')),
      findsNothing,
    );

    initialTarget.complete(true);
    await tester.pumpAndSettle();

    expect(
      controller.lifecycleState.value,
      ProfileTourLifecycleState.presenting,
    );
    expect(controller.isActive.value, isTrue);
    expect(
      find.byKey(const ValueKey('profile-tour-control-panel')),
      findsOneWidget,
    );

    controller.cancel();
    await tester.pumpAndSettle();
    expect(await session, ProfileTourExitReason.cancelled);
  });

  testWidgets('unready Step 1 never flashes an overlay', (tester) async {
    final context = await pumpHarness(tester);

    final session = controller.start(
      context: context,
      uid: 'user-a',
      targets: targets(),
      prepareInitial: () async => false,
    );
    await tester.pumpAndSettle();

    expect(await session, isNull);
    expect(controller.isActive.value, isFalse);
    expect(
      controller.lifecycleState.value,
      ProfileTourLifecycleState.cancelled,
    );
    expect(
      find.byKey(const ValueKey('profile-tour-control-panel')),
      findsNothing,
    );
    expect(store.values, isEmpty);
  });

  testWidgets('startup rebuilds settle before one overlay is inserted', (
    tester,
  ) async {
    final visibility = ValueNotifier<bool>(true);
    addTearDown(visibility.dispose);
    final context = await pumpHarness(
      tester,
      settingsTargetVisibility: visibility,
    );
    final stableLayout = Completer<bool>();
    final session = controller.start(
      context: context,
      uid: 'user-a',
      targets: targets(),
      prepareInitial: () => stableLayout.future,
    );
    await tester.pump();

    visibility.value = false;
    await tester.pump();
    visibility.value = true;
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('profile-tour-control-panel')),
      findsNothing,
    );
    expect(controller.isActive.value, isFalse);

    stableLayout.complete(targetHandles[0].isAvailable);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('profile-tour-control-panel')),
      findsOneWidget,
    );
    expect(find.byType(ProfileGuidedTourOverlay), findsOneWidget);
    expect(tester.takeException(), isNull);

    controller.cancel();
    await tester.pumpAndSettle();
    expect(await session, ProfileTourExitReason.cancelled);
  });

  testWidgets('a transient target rebuild does not cancel the session', (
    tester,
  ) async {
    final settingsTargetVisibility = ValueNotifier<bool>(true);
    addTearDown(settingsTargetVisibility.dispose);
    final context = await pumpHarness(
      tester,
      settingsTargetVisibility: settingsTargetVisibility,
    );
    final session = controller.start(
      context: context,
      uid: 'user-a',
      targets: targets(),
    );
    await tester.pumpAndSettle();

    settingsTargetVisibility.value = false;
    await tester.pump();
    expect(() => measureProfileTourTarget(targetHandles[0]), returnsNormally);
    expect(measureProfileTourTarget(targetHandles[0]), isNull);
    expect(tester.takeException(), isNull);
    expect(controller.isActive.value, isTrue);

    settingsTargetVisibility.value = true;
    await tester.pumpAndSettle();
    expect(measureProfileTourTarget(targetHandles[0]), isNotNull);
    expect(controller.isActive.value, isTrue);
    expect(
      controller.lifecycleState.value,
      ProfileTourLifecycleState.presenting,
    );
    expect(
      find.byKey(const ValueKey('profile-tour-control-panel')),
      findsOneWidget,
    );

    controller.cancel();
    await tester.pumpAndSettle();
    expect(await session, ProfileTourExitReason.cancelled);
    expect(store.values, isEmpty);
  });

  testWidgets('an obsolete overlay callback cannot remove a newer session', (
    tester,
  ) async {
    final firstSession = await startTour(tester);
    await tester.pumpAndSettle();
    final obsoleteOverlay = tester.widget<ProfileGuidedTourOverlay>(
      find.byType(ProfileGuidedTourOverlay),
    );

    controller.cancel();
    await tester.pumpAndSettle();
    expect(await firstSession, ProfileTourExitReason.cancelled);

    final context = tester.element(
      find.byKey(const ValueKey('profile-tour-host')),
    );
    final secondSession = controller.start(
      context: context,
      uid: 'user-a',
      targets: targets(),
    );
    await tester.pumpAndSettle();
    expect(controller.isActive.value, isTrue);

    await obsoleteOverlay.onExit(ProfileTourExitReason.completed);
    await tester.pump();

    expect(controller.isActive.value, isTrue);
    expect(
      controller.lifecycleState.value,
      ProfileTourLifecycleState.presenting,
    );
    expect(
      find.byKey(const ValueKey('profile-tour-control-panel')),
      findsOneWidget,
    );
    expect(store.values, isEmpty);

    controller.cancel();
    await tester.pumpAndSettle();
    expect(await secondSession, ProfileTourExitReason.cancelled);
  });

  testWidgets('Skip persists completion', (tester) async {
    final session = await startTour(tester);
    await tester.tap(find.byKey(const ValueKey('profile-tour-skip')));
    await tester.pumpAndSettle();
    expect(await session, ProfileTourExitReason.skipped);
    expect(store.values['profile_tour_v1_user-a'], isTrue);
  });

  testWidgets('Got it persists completion', (tester) async {
    final session = await startTour(tester);
    for (var step = 0; step < 6; step += 1) {
      await tester.tap(find.byKey(const ValueKey('profile-tour-next')));
      await tester.pumpAndSettle();
    }
    expect(await session, ProfileTourExitReason.completed);
    expect(store.values['profile_tour_v1_user-a'], isTrue);
  });

  testWidgets('other-tour completion does not suppress Profile', (
    tester,
  ) async {
    store.values.addAll(<String, bool>{
      'home_tour_v1_user-a': true,
      'explore_tour_v1_user-a': true,
      'services_tour_v1_user-a': true,
    });

    await startTour(tester);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('completed UID stays closed', (tester) async {
    store.values['profile_tour_v1_user-a'] = true;

    final completed = await startTour(tester);

    expect(await completed, isNull);
    expect(
      find.byKey(const ValueKey('profile-tour-control-panel')),
      findsNothing,
    );
  });

  testWidgets('cancel removes the modal overlay without persistence', (
    tester,
  ) async {
    final session = await startTour(tester);
    controller.cancel();
    await tester.pumpAndSettle();

    expect(await session, ProfileTourExitReason.cancelled);
    expect(store.values, isEmpty);
    expect(
      find.byKey(const ValueKey('profile-tour-control-panel')),
      findsNothing,
    );
  });

  testWidgets('Android Back dismisses an active tour without completion', (
    tester,
  ) async {
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileTourBackScope(
          isTourActive: true,
          onDismissTour: () => dismissed = true,
          child: const Scaffold(body: Text('Profile route')),
        ),
      ),
    );

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(dismissed, isTrue);
    expect(find.text('Profile route'), findsOneWidget);
    expect(store.values, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overlay blocks the Profile underneath it', (tester) async {
    await startTour(tester);
    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    expect(backgroundTaps, 0);

    await tester.tap(find.byKey(const ValueKey('profile-tour-skip')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    expect(backgroundTaps, 1);
  });

  testWidgets('each spotlight tracks only its real target', (tester) async {
    await startTour(tester);
    await tester.pumpAndSettle();

    for (var step = 0; step < 6; step += 1) {
      final target = tester.getRect(find.byKey(targetKeys[step]));
      final highlight = tester.getRect(
        find.byKey(const ValueKey('profile-tour-highlight-bounds')),
      );
      expect(highlight.contains(target.topLeft), isTrue);
      expect(highlight.contains(target.bottomRight), isTrue);
      expect(highlight.width, lessThanOrEqualTo(target.width + 12.1));
      if (step < 5) {
        await tester.tap(find.byKey(const ValueKey('profile-tour-next')));
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('Bookings spotlight exposes the real button label', (
    tester,
  ) async {
    await startTour(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-tour-next')));
    await tester.pumpAndSettle();

    final bookingsTarget = find.byKey(targetKeys[1]);
    final realLabel = find.descendant(
      of: bookingsTarget,
      matching: find.text('Bookings'),
    );
    expect(realLabel, findsOneWidget);
    final highlight = tester.getRect(
      find.byKey(const ValueKey('profile-tour-highlight-bounds')),
    );
    expect(highlight.contains(tester.getCenter(realLabel)), isTrue);
  });

  testWidgets('Step 4 remeasures the Posts tab and excludes pet tiles', (
    tester,
  ) async {
    final postsTargetTop = ValueNotifier<double>(346);
    addTearDown(postsTargetTop.dispose);
    final context = await pumpHarness(tester, postsTargetTop: postsTargetTop);
    final session = controller.start(
      context: context,
      uid: 'user-a',
      targets: targets(),
    );
    await tester.pumpAndSettle();

    for (var step = 0; step < 3; step += 1) {
      await tester.tap(find.byKey(const ValueKey('profile-tour-next')));
      await tester.pumpAndSettle();
    }
    postsTargetTop.value = 358;
    await tester.pumpAndSettle();

    final postsRect = tester.getRect(find.byKey(targetKeys[3]));
    final petTilesRect = tester.getRect(
      find.byKey(const ValueKey('profile-pet-tiles-fixture')),
    );
    final highlight = tester.getRect(
      find.byKey(const ValueKey('profile-tour-highlight-bounds')),
    );
    expect(highlight.contains(postsRect.topLeft), isTrue);
    expect(highlight.contains(postsRect.bottomRight), isTrue);
    expect(highlight.overlaps(petTilesRect), isFalse);
    expect(tester.takeException(), isNull);

    controller.cancel();
    await tester.pumpAndSettle();
    expect(await session, ProfileTourExitReason.cancelled);
  });

  testWidgets('missing Add Service target preserves the current valid step', (
    tester,
  ) async {
    var failedPreparationCalls = 0;
    final session = await startTour(
      tester,
      includeAddService: false,
      prepareStep: (step) async {
        if (step == 5) failedPreparationCalls += 1;
        return step != 5;
      },
    );
    for (var step = 0; step < 5; step += 1) {
      await tester.tap(find.byKey(const ValueKey('profile-tour-next')));
      await tester.pumpAndSettle();
    }

    expect(controller.isActive.value, isTrue);
    expect(
      controller.lifecycleState.value,
      ProfileTourLifecycleState.presenting,
    );
    expect(store.values, isEmpty);
    expect(
      find.byKey(const ValueKey('profile-tour-highlight-bounds')),
      findsOneWidget,
    );
    expect(find.text('Services'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('profile-tour-next')));
    await tester.pumpAndSettle();
    expect(failedPreparationCalls, 2);
    expect(
      controller.lifecycleState.value,
      ProfileTourLifecycleState.presenting,
    );

    controller.cancel();
    await tester.pumpAndSettle();
    expect(await session, ProfileTourExitReason.cancelled);
  });

  for (final size in const <Size>[
    Size(360, 640),
    Size(393, 852),
    Size(412, 915),
  ]) {
    testWidgets('six steps remain in bounds at ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await startTour(tester);
      await tester.pumpAndSettle();
      for (var step = 0; step < 6; step += 1) {
        final tooltip = tester.getRect(
          find.byKey(const ValueKey('profile-tour-tooltip-card')),
        );
        final panel = tester.getRect(
          find.byKey(const ValueKey('profile-tour-control-panel')),
        );
        final target = tester.getRect(
          find.byKey(const ValueKey('profile-tour-highlight-bounds')),
        );
        final arrow = calculateProfileTourArrowGeometry(
          stepIndex: step,
          tooltipRect: tooltip,
          targetRect: target,
        );
        final head = calculateProfileTourArrowHead(arrow);
        expect(tooltip.left, greaterThanOrEqualTo(0));
        expect(tooltip.right, lessThanOrEqualTo(size.width));
        expect(tooltip.top, greaterThanOrEqualTo(0));
        expect(tooltip.bottom, lessThan(panel.top));
        expect(panel.bottom, lessThanOrEqualTo(size.height));
        expect(arrow.start.dx, closeTo(tooltip.left - 1, 0.01));
        expect(arrow.start.dy, closeTo(tooltip.center.dy, 0.01));
        expect(arrow.control1 - arrow.start, isNot(Offset.zero));
        expect(arrow.end - arrow.control2, isNot(Offset.zero));
        final approach = arrow.end - arrow.control2;
        final targetDirection = target.center - arrow.end;
        expect(
          approach.dx * targetDirection.dx + approach.dy * targetDirection.dy,
          greaterThan(0),
        );
        expect(panel.top - target.bottom, greaterThanOrEqualTo(16));
        _expectArrowOutside(arrow, head, <Rect>[tooltip, target], step: step);
        if (step < 5) {
          await tester.tap(find.byKey(const ValueKey('profile-tour-next')));
          await tester.pumpAndSettle();
        }
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('1.3 text scale keeps tooltip and panel separated', (
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
    for (var step = 0; step < 6; step += 1) {
      final tooltip = tester.getRect(
        find.byKey(const ValueKey('profile-tour-tooltip-card')),
      );
      final panel = tester.getRect(
        find.byKey(const ValueKey('profile-tour-control-panel')),
      );
      final target = tester.getRect(
        find.byKey(const ValueKey('profile-tour-highlight-bounds')),
      );
      expect(tooltip.bottom, lessThan(panel.top));
      expect(panel.top - target.bottom, greaterThanOrEqualTo(16));
      if (step < 5) {
        await tester.tap(find.byKey(const ValueKey('profile-tour-next')));
        await tester.pumpAndSettle();
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom panel uses the lowered safe anchor', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await startTour(tester);
    await tester.pumpAndSettle();

    final panel = tester.getRect(
      find.byKey(const ValueKey('profile-tour-control-panel')),
    );
    expect(panel.bottom, closeTo(788, 0.01));
  });

  test('panel anchor lowers by 16 pixels while preserving safe inset', () {
    expect(calculateProfileTourPanelBottom(safeBottom: 0, compact: true), 56);
    expect(calculateProfileTourPanelBottom(safeBottom: 0, compact: false), 64);
    expect(calculateProfileTourPanelBottom(safeBottom: 24, compact: true), 80);
    expect(calculateProfileTourPanelBottom(safeBottom: 24, compact: false), 88);
  });

  testWidgets('Services target key is bound to the visible animated tab pill', (
    tester,
  ) async {
    final servicesTarget = ProfileTourTargetHandle();
    var selectedIndex = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ProfileSectionTabs(
              selectedIndex: selectedIndex,
              showServices: true,
              serviceCount: 3,
              servicesTargetKey: servicesTarget,
              onChanged: (index) => setState(() => selectedIndex = index),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Services (3)'));
    await tester.pumpAndSettle();

    expect(servicesTarget.isAvailable, isTrue);
    final servicesRect = servicesTarget.rect!;
    final labelRect = tester.getRect(find.text('Services (3)'));
    expect(servicesRect.contains(labelRect.center), isTrue);
    final label = tester.widget<Text>(find.text('Services (3)'));
    expect(label.style?.color, const Color(0xFFF75927));
  });

  testWidgets(
    'Services loading, empty, and populated states retain scrollable',
    (tester) async {
      final harnessKey = GlobalKey<_ProfileServicesStructureHarnessState>();
      await tester.pumpWidget(
        MaterialApp(home: _ProfileServicesStructureHarness(key: harnessKey)),
      );
      await tester.pumpAndSettle();
      final state = harnessKey.currentState!;
      final originalPosition = state.scrollController.position;

      expect(find.byKey(const ValueKey('profile-services-loading')), findsOne);
      expect(state.servicesTarget.isAvailable, isTrue);
      expect(state.addServiceTarget.isAvailable, isTrue);

      state.setServices(const <ProfileServiceListing>[]);
      await tester.pumpAndSettle();
      expect(find.text('No services listed'), findsOneWidget);
      expect(
        identical(state.scrollController.position, originalPosition),
        isTrue,
      );
      expect(state.servicesTarget.isAvailable, isTrue);
      expect(state.addServiceTarget.isAvailable, isTrue);

      state.setServices(const <ProfileServiceListing>[_profileServiceFixture]);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile_service_service-1')), findsOne);
      expect(
        identical(state.scrollController.position, originalPosition),
        isTrue,
      );
      expect(state.servicesTarget.isAvailable, isTrue);
      expect(state.addServiceTarget.isAvailable, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final spotlightVisible in <bool>[true, false]) {
    testWidgets(
      'real lower Profile targets are revealed when spotlight is $spotlightVisible',
      (tester) async {
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final harnessKey = GlobalKey<_ProfileTourRevealHarnessState>();
        await tester.pumpWidget(
          MaterialApp(
            home: _ProfileTourRevealHarness(
              key: harnessKey,
              spotlightVisible: spotlightVisible,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final state = harnessKey.currentState!;
        expect(find.byKey(state.addPetKey), findsOneWidget);
        expect(find.byKey(state.postsKey), findsOneWidget);
        expect(find.byKey(state.servicesKey), findsOneWidget);
        expect(find.byKey(state.addServiceKey), findsOneWidget);
        expect(measureProfileTourTarget(state.addPetTarget), isNotNull);
        expect(measureProfileTourTarget(state.postsTarget), isNotNull);
        expect(measureProfileTourTarget(state.servicesTarget), isNotNull);
        expect(measureProfileTourTarget(state.addServiceTarget), isNotNull);

        for (final entry in <String, ProfileTourTargetHandle>{
          'Add Pet': state.addPetTarget,
          'Posts': state.postsTarget,
          'Services': state.servicesTarget,
          'Add Service': state.addServiceTarget,
        }.entries) {
          final targetKey = entry.value;
          final reveal = revealProfileTourTarget(
            context: state.context,
            scrollController: state.scrollController,
            targetKey: targetKey,
            headerBottom: 84,
            bottomObstruction: 280,
          );
          final revealed = await _pumpProfileTourReveal(tester, reveal);

          expect(
            revealed,
            isTrue,
            reason:
                '${entry.key} was not revealed; rect=${measureProfileTourTarget(targetKey)} offset=${state.scrollController.offset}',
          );
          final targetRect = measureProfileTourTarget(targetKey)!;
          expect(
            isProfileTourTargetVisible(
              targetRect: targetRect,
              viewportWidth: 393,
              safeTop: 98,
              safeBottom: 572,
            ),
            isTrue,
          );
        }
      },
    );
  }

  testWidgets('spotlight insertion during initialization is remeasured', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final harnessKey = GlobalKey<_ProfileTourRevealHarnessState>();
    await tester.pumpWidget(
      MaterialApp(
        home: _ProfileTourRevealHarness(
          key: harnessKey,
          spotlightVisible: false,
        ),
      ),
    );
    final state = harnessKey.currentState!;
    state.setSpotlightVisible(true);

    final reveal = revealProfileTourTarget(
      context: state.context,
      scrollController: state.scrollController,
      targetKey: state.servicesTarget,
      headerBottom: 84,
      bottomObstruction: 280,
    );
    final revealed = await _pumpProfileTourReveal(tester, reveal);

    expect(revealed, isTrue);
    final servicesRect = measureProfileTourTarget(state.servicesTarget)!;
    expect(servicesRect.top, greaterThanOrEqualTo(98));
    expect(servicesRect.bottom, lessThanOrEqualTo(572));
  });

  test('scrolling is minimal, header-safe, and clamped', () {
    expect(
      calculateProfileTourScrollOffset(
        currentOffset: 40,
        minScrollExtent: 0,
        maxScrollExtent: 700,
        targetRect: const Rect.fromLTWH(18, 180, 170, 46),
        headerBottom: 98,
        viewportHeight: 852,
        bottomObstruction: 280,
      ),
      40,
    );
    expect(
      calculateProfileTourScrollOffset(
        currentOffset: 40,
        minScrollExtent: 0,
        maxScrollExtent: 700,
        targetRect: const Rect.fromLTWH(18, 620, 170, 46),
        headerBottom: 98,
        viewportHeight: 852,
        bottomObstruction: 280,
      ),
      134,
    );
    expect(
      calculateProfileTourScrollOffset(
        currentOffset: 20,
        minScrollExtent: 0,
        maxScrollExtent: 700,
        targetRect: const Rect.fromLTWH(18, 20, 170, 46),
        headerBottom: 98,
        viewportHeight: 852,
        bottomObstruction: 280,
      ),
      0,
    );
  });

  test(
    'visibility tolerates fractional edges but reserves spotlight space',
    () {
      const target = Rect.fromLTRB(20, 405.8, 86.2, 500.3);
      expect(
        isProfileTourTargetVisible(
          targetRect: target,
          viewportWidth: 360,
          safeTop: 118.3,
          safeBottom: 500,
        ),
        isTrue,
      );
      expect(
        isProfileTourTargetVisible(
          targetRect: target,
          viewportWidth: 360,
          safeTop: 118.3,
          safeBottom: 500,
          spotlightPadding: 5,
        ),
        isFalse,
      );
    },
  );

  test('tour-only scroll spacer is derived from the panel obstruction', () {
    expect(
      calculateProfileTourScrollSpacer(
        viewportHeight: 640,
        normalBottomPadding: 124,
      ),
      150,
    );
    expect(
      calculateProfileTourScrollSpacer(
        viewportHeight: 852,
        normalBottomPadding: 132,
      ),
      164,
    );
    expect(
      calculateProfileTourScrollSpacer(
        viewportHeight: 852,
        normalBottomPadding: 320,
      ),
      0,
    );
  });

  testWidgets('tour spacer resolves the physical-device scroll clamp', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final harnessKey = GlobalKey<_ScrollClampHarnessState>();
    await tester.pumpWidget(
      MaterialApp(home: _ScrollClampHarness(key: harnessKey)),
    );
    await tester.pumpAndSettle();
    final state = harnessKey.currentState!;
    final maxExtentWithoutSpacer =
        state.scrollController.position.maxScrollExtent;
    final initialRect = measureProfileTourTarget(state.target)!;
    expect(initialRect.top, closeTo(526.3, 0.1));
    expect(initialRect.bottom, closeTo(620.6, 0.1));

    final failedReveal = revealProfileTourTarget(
      context: state.context,
      scrollController: state.scrollController,
      targetKey: state.target,
      headerBottom: 84,
      bottomObstruction: 280,
    );
    expect(await _pumpProfileTourReveal(tester, failedReveal), isFalse);
    final clampedRect = measureProfileTourTarget(state.target)!;
    expect(state.scrollController.offset, closeTo(120.5, 0.1));
    expect(clampedRect.top, closeTo(405.8, 0.1));
    expect(clampedRect.bottom, closeTo(500.1, 0.1));
    expect(clampedRect.bottom, greaterThan(460));

    state.setTourSpacerEnabled(true);
    await tester.pumpAndSettle();
    final maxExtentWithSpacer = state.scrollController.position.maxScrollExtent;
    expect(
      maxExtentWithSpacer - maxExtentWithoutSpacer,
      closeTo(
        calculateProfileTourScrollSpacer(
          viewportHeight: 740,
          normalBottomPadding: 132,
        ),
        0.1,
      ),
    );
    final recoveredReveal = revealProfileTourTarget(
      context: state.context,
      scrollController: state.scrollController,
      targetKey: state.target,
      headerBottom: 84,
      bottomObstruction: 280,
      spotlightPadding: 5,
    );
    expect(await _pumpProfileTourReveal(tester, recoveredReveal), isTrue);
    final recoveredRect = measureProfileTourTarget(state.target)!;
    expect(recoveredRect.bottom + 5, lessThanOrEqualTo(460.5));
  });

  testWidgets(
    'event-driven readiness survives attachment beyond twelve frames',
    (tester) async {
      final harnessKey = GlobalKey<_ScrollClampHarnessState>();
      final readiness = _CountingReadinessSignal();
      addTearDown(readiness.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: _ScrollClampHarness(
            key: harnessKey,
            initiallyAttached: false,
            targetTop: 300,
            targetHeight: 44,
          ),
        ),
      );
      final state = harnessKey.currentState!;
      var completed = false;
      final waiting =
          waitForProfileTourReadiness(
            readinessSignal: readiness,
            scrollController: state.scrollController,
            target: state.target,
            canContinue: () => true,
            timeout: const Duration(seconds: 3),
          ).then((value) {
            completed = true;
            return value;
          });

      for (var frame = 0; frame < 20; frame += 1) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(completed, isFalse);

      state.setScrollAttached(true);
      await tester.pumpAndSettle();
      readiness.signal();
      await tester.pump();

      expect(await waiting, isTrue);
      expect(readiness.listenerCount, 0);
      expect(state.target.isAvailable, isTrue);
    },
  );

  testWidgets('interrupted readiness removes listeners without completion', (
    tester,
  ) async {
    final harnessKey = GlobalKey<_ScrollClampHarnessState>();
    final readiness = _CountingReadinessSignal();
    addTearDown(readiness.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: _ScrollClampHarness(key: harnessKey, initiallyAttached: false),
      ),
    );
    final state = harnessKey.currentState!;
    var canContinue = true;
    final waiting = waitForProfileTourReadiness(
      readinessSignal: readiness,
      scrollController: state.scrollController,
      target: state.target,
      canContinue: () => canContinue,
      timeout: const Duration(seconds: 3),
    );

    canContinue = false;
    readiness.signal();
    await tester.pump();

    expect(await waiting, isFalse);
    expect(readiness.listenerCount, 0);
    expect(store.values, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Step 2 to Step 3 succeeds at the 360-wide Android boundary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final harnessKey = GlobalKey<_ScrollClampHarnessState>();
    await tester.pumpWidget(
      MaterialApp(
        home: _ScrollClampHarness(
          key: harnessKey,
          viewportHeight: 780,
          trailingHeight: 279.9,
          normalBottomPadding: 124,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = harnessKey.currentState!;
    final context = state.context;
    final target = state.target;
    final tourTargets = ProfileTourTargets(
      settings: target,
      bookings: target,
      addPet: target,
      postsTab: target,
      servicesTab: target,
      addService: target,
    );
    final session = controller.start(
      context: context,
      uid: 'user-a',
      targets: tourTargets,
      prepareStep: (step) async {
        if (step != 2) return true;
        state.setTourSpacerEnabled(true);
        await WidgetsBinding.instance.endOfFrame;
        return revealProfileTourTarget(
          context: context,
          scrollController: state.scrollController,
          targetKey: target,
          headerBottom: 104.3,
          bottomObstruction: 280,
          spotlightPadding: 5,
        );
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-tour-next')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('profile-tour-progress-1')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('profile-tour-next')));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Profile add pet tour step'), findsOneWidget);
    final rect = measureProfileTourTarget(target)!;
    expect(rect.bottom + 5, lessThanOrEqualTo(500.5));
    expect(
      controller.lifecycleState.value,
      ProfileTourLifecycleState.presenting,
    );

    controller.cancel();
    await tester.pumpAndSettle();
    expect(await session, ProfileTourExitReason.cancelled);
  });

  testWidgets('Step 6 corrects the 500 versus 492.6 viewport mismatch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 777);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final harnessKey = GlobalKey<_ScrollClampHarnessState>();
    await tester.pumpWidget(
      MaterialApp(
        home: _ScrollClampHarness(
          key: harnessKey,
          viewportHeight: 777,
          targetTop: 450,
          targetHeight: 44,
          trailingHeight: 400,
          normalBottomPadding: 124,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = harnessKey.currentState!;
    final target = state.target;
    final initialRect = measureProfileTourTarget(target)!;
    expect(initialRect, const Rect.fromLTRB(20, 450, 86.2, 494));
    expect(
      isProfileTourTargetVisible(
        targetRect: initialRect,
        viewportWidth: 360,
        safeTop: 118.3,
        safeBottom: 500,
        spotlightPadding: 6,
      ),
      isTrue,
    );

    ProfileTourLayoutSnapshot? stepSixSnapshot;
    final tourTargets = ProfileTourTargets(
      settings: target,
      bookings: target,
      addPet: target,
      postsTab: target,
      servicesTab: target,
      addService: target,
    );
    final session = controller.start(
      context: state.context,
      uid: 'user-a',
      targets: tourTargets,
      prepareStep: (step) async {
        if (step != 5) return true;
        stepSixSnapshot = controller.layoutSnapshot.value;
        final snapshot = stepSixSnapshot;
        if (snapshot == null || snapshot.stepIndex != 5) return false;
        state.setTourSpacerEnabled(true);
        await WidgetsBinding.instance.endOfFrame;
        return revealProfileTourTarget(
          context: state.context,
          scrollController: state.scrollController,
          targetKey: target,
          headerBottom: 104.3,
          bottomObstruction: 280,
          spotlightPadding: 6,
          usableViewport: snapshot.usableViewport,
        );
      },
    );
    await tester.pumpAndSettle();

    for (var step = 0; step < 5; step += 1) {
      await tester.tap(find.byKey(const ValueKey('profile-tour-next')));
      await tester.pumpAndSettle();
    }

    final snapshot = stepSixSnapshot!;
    expect(snapshot.stepIndex, 5);
    expect(snapshot.usableViewport.bottom, closeTo(492.6, 1.0));
    expect(
      isProfileTourTargetVisible(
        targetRect: initialRect,
        viewportWidth: 360,
        safeTop: snapshot.usableViewport.top,
        safeBottom: snapshot.usableViewport.bottom,
        spotlightPadding: 6,
      ),
      isFalse,
    );
    final correctedRect = measureProfileTourTarget(target)!;
    expect(
      correctedRect.bottom + 6,
      lessThanOrEqualTo(snapshot.usableViewport.bottom + 0.5),
    );
    expect(
      find.byKey(const ValueKey<String>('profile-tour-progress-5')),
      findsOneWidget,
    );
    expect(find.text('Got it'), findsOneWidget);
    expect(tester.takeException(), isNull);

    controller.cancel();
    await tester.pumpAndSettle();
    expect(await session, ProfileTourExitReason.cancelled);
  });

  testWidgets(
    'Posts to Services waits through scroll-controller detachment once',
    (tester) async {
      final harnessKey = GlobalKey<_ScrollClampHarnessState>();
      await tester.pumpWidget(
        MaterialApp(
          home: _ScrollClampHarness(
            key: harnessKey,
            targetTop: 300,
            targetHeight: 44,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = harnessKey.currentState!;
      final tourTargets = ProfileTourTargets(
        settings: state.target,
        bookings: state.target,
        addPet: state.target,
        postsTab: state.target,
        servicesTab: state.target,
        addService: state.target,
      );
      var servicesPreparationCalls = 0;
      final session = controller.start(
        context: state.context,
        uid: 'user-a',
        targets: tourTargets,
        prepareStep: (step) async {
          if (step != 4) return true;
          servicesPreparationCalls += 1;
          state.setScrollAttached(false);
          await WidgetsBinding.instance.endOfFrame;
          state.setScrollAttached(true);
          for (var frame = 0; frame < 4; frame += 1) {
            await WidgetsBinding.instance.endOfFrame;
            if (state.scrollController.hasClients && state.target.isAvailable) {
              return true;
            }
          }
          return false;
        },
      );
      await tester.pumpAndSettle();

      for (var step = 0; step < 4; step += 1) {
        await tester.tap(find.byKey(const ValueKey('profile-tour-next')));
        await tester.pumpAndSettle();
      }

      expect(servicesPreparationCalls, 1);
      expect(
        find.byKey(const ValueKey<String>('profile-tour-progress-4')),
        findsOneWidget,
      );
      expect(
        controller.lifecycleState.value,
        ProfileTourLifecycleState.presenting,
      );
      expect(tester.takeException(), isNull);

      controller.cancel();
      await tester.pumpAndSettle();
      expect(await session, ProfileTourExitReason.cancelled);
    },
  );

  testWidgets('storage read failure leaves Profile usable', (tester) async {
    controller.dispose();
    controller = ProfileGuidedTourController(
      preferences: ProfileTourPreferenceService(
        store: const _FailingProfileTourStore(),
      ),
    );

    final session = await startTour(tester);
    expect(await session, isNull);
    expect(find.byKey(targetKeys[0]), findsOne);
    expect(
      find.byKey(const ValueKey('profile-tour-control-panel')),
      findsNothing,
    );
  });
}

Offset _sampleCubic(ProfileTourArrowGeometry geometry, double t) {
  final inverse = 1 - t;
  return geometry.start * (inverse * inverse * inverse) +
      geometry.control1 * (3 * inverse * inverse * t) +
      geometry.control2 * (3 * inverse * t * t) +
      geometry.end * (t * t * t);
}

Future<bool> _pumpProfileTourReveal(
  WidgetTester tester,
  Future<bool> reveal,
) async {
  bool? result;
  reveal.then((value) => result = value);
  for (var frame = 0; frame < 30 && result == null; frame += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return result ?? await reveal;
}

void _expectArrowOutside(
  ProfileTourArrowGeometry geometry,
  ProfileTourArrowHead head,
  List<Rect> excludedRects, {
  required int step,
}) {
  for (var sample = 0; sample <= 40; sample += 1) {
    final point = _sampleCubic(geometry, sample / 40);
    for (final rect in excludedRects) {
      expect(
        rect.contains(point),
        isFalse,
        reason: 'step $step shaft sample $sample at $point entered $rect',
      );
    }
  }
  for (final wing in <Offset>[head.firstWing, head.secondWing]) {
    for (var sample = 0; sample <= 20; sample += 1) {
      final point = Offset.lerp(geometry.end, wing, sample / 20)!;
      for (final rect in excludedRects) {
        expect(
          rect.contains(point),
          isFalse,
          reason: 'step $step arrowhead sample $sample entered $rect',
        );
      }
    }
  }
}

class _MemoryProfileTourStore implements ProfileTourCompletionStore {
  final Map<String, bool> values = <String, bool>{};

  @override
  Future<bool> read(String key) async => values[key] ?? false;

  @override
  Future<void> write(String key, bool value) async {
    values[key] = value;
  }
}

class _FailingProfileTourStore implements ProfileTourCompletionStore {
  const _FailingProfileTourStore();

  @override
  Future<bool> read(String key) async => throw StateError('read failed');

  @override
  Future<void> write(String key, bool value) async =>
      throw StateError('write failed');
}

class _CountingReadinessSignal extends ChangeNotifier {
  int listenerCount = 0;

  @override
  void addListener(VoidCallback listener) {
    listenerCount += 1;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerCount -= 1;
    super.removeListener(listener);
  }

  void signal() => notifyListeners();
}

class _ProfileServicesStructureHarness extends StatefulWidget {
  const _ProfileServicesStructureHarness({super.key});

  @override
  State<_ProfileServicesStructureHarness> createState() =>
      _ProfileServicesStructureHarnessState();
}

class _ProfileServicesStructureHarnessState
    extends State<_ProfileServicesStructureHarness> {
  final ScrollController scrollController = ScrollController();
  final ProfileTourTargetHandle servicesTarget = ProfileTourTargetHandle();
  final ProfileTourTargetHandle addServiceTarget = ProfileTourTargetHandle();
  List<ProfileServiceListing>? _services;

  void setServices(List<ProfileServiceListing> services) {
    setState(() => _services = services);
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = _services ?? const <ProfileServiceListing>[];
    return Scaffold(
      body: SingleChildScrollView(
        key: const ValueKey<String>('profile-services-outer-scrollable'),
        controller: scrollController,
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            ProfileSectionTabs(
              selectedIndex: 1,
              showServices: true,
              serviceCount: services.length,
              servicesTargetKey: servicesTarget,
              onChanged: (_) {},
            ),
            if (_services == null)
              const SizedBox(
                key: ValueKey<String>('profile-services-loading'),
                height: 24,
              ),
            ProfileServicesSection(
              services: services,
              canManage: true,
              addServiceTargetKey: addServiceTarget,
              onAdd: () {},
              isGlobalActionRunning: false,
              runningServiceActionId: '',
              onToggleAll: (_) {},
              onPauseService: (_) {},
              onResumeService: (_) {},
              onDeleteService: (_) {},
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTourRevealHarness extends StatefulWidget {
  const _ProfileTourRevealHarness({super.key, required this.spotlightVisible});

  final bool spotlightVisible;

  @override
  State<_ProfileTourRevealHarness> createState() =>
      _ProfileTourRevealHarnessState();
}

class _ProfileTourRevealHarnessState extends State<_ProfileTourRevealHarness> {
  final ScrollController scrollController = ScrollController();
  final GlobalKey addPetKey = GlobalKey();
  final GlobalKey postsKey = GlobalKey();
  final GlobalKey servicesKey = GlobalKey();
  final GlobalKey addServiceKey = GlobalKey();
  final ProfileTourTargetHandle addPetTarget = ProfileTourTargetHandle();
  final ProfileTourTargetHandle postsTarget = ProfileTourTargetHandle();
  final ProfileTourTargetHandle servicesTarget = ProfileTourTargetHandle();
  final ProfileTourTargetHandle addServiceTarget = ProfileTourTargetHandle();
  late bool _spotlightVisible;

  @override
  void initState() {
    super.initState();
    _spotlightVisible = widget.spotlightVisible;
  }

  void setSpotlightVisible(bool value) {
    setState(() => _spotlightVisible = value);
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(18, 110, 18, 320),
        child: Column(
          children: [
            const SizedBox(height: 220),
            if (_spotlightVisible)
              const SizedBox(
                key: ValueKey<String>('profile-spotlight-fixture'),
                height: 130,
              ),
            ProfileTourTarget(
              handle: addPetTarget,
              child: SizedBox(
                key: addPetKey,
                width: double.infinity,
                height: 92,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 46,
              child: Row(
                children: [
                  ProfileTourTarget(
                    handle: postsTarget,
                    child: Container(
                      key: postsKey,
                      width: 170,
                      height: 46,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  ProfileTourTarget(
                    handle: servicesTarget,
                    child: Container(
                      key: servicesKey,
                      width: 170,
                      height: 46,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ProfileTourTarget(
              handle: addServiceTarget,
              child: SizedBox(
                key: addServiceKey,
                width: double.infinity,
                height: 46,
              ),
            ),
            const SizedBox(height: 500),
          ],
        ),
      ),
    );
  }
}

class _ScrollClampHarness extends StatefulWidget {
  const _ScrollClampHarness({
    super.key,
    this.viewportHeight = 740,
    this.trailingHeight = 239.9,
    this.normalBottomPadding = 132,
    this.targetTop = 526.3,
    this.targetHeight = 94.3,
    this.initiallyAttached = true,
  });

  final double viewportHeight;
  final double trailingHeight;
  final double normalBottomPadding;
  final double targetTop;
  final double targetHeight;
  final bool initiallyAttached;

  @override
  State<_ScrollClampHarness> createState() => _ScrollClampHarnessState();
}

class _ScrollClampHarnessState extends State<_ScrollClampHarness> {
  final ScrollController scrollController = ScrollController();
  final ProfileTourTargetHandle target = ProfileTourTargetHandle();
  bool _tourSpacerEnabled = false;
  late bool _scrollAttached;

  @override
  void initState() {
    super.initState();
    _scrollAttached = widget.initiallyAttached;
  }

  void setTourSpacerEnabled(bool enabled) {
    setState(() => _tourSpacerEnabled = enabled);
  }

  void setScrollAttached(bool attached) {
    setState(() => _scrollAttached = attached);
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _scrollAttached
          ? SingleChildScrollView(
              controller: scrollController,
              child: Column(
                children: [
                  SizedBox(height: widget.targetTop),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 20),
                      child: ProfileTourTarget(
                        handle: target,
                        child: SizedBox(
                          width: 66.2,
                          height: widget.targetHeight,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: widget.trailingHeight),
                  if (_tourSpacerEnabled)
                    SizedBox(
                      height: calculateProfileTourScrollSpacer(
                        viewportHeight: widget.viewportHeight,
                        normalBottomPadding: widget.normalBottomPadding,
                      ),
                    ),
                ],
              ),
            )
          : const SizedBox.expand(),
    );
  }
}
