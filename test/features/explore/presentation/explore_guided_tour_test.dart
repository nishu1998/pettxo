import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/explore/data/explore_tour_preference_service.dart';
import 'package:pettexo/features/explore/presentation/widgets/explore_guided_tour.dart';

void main() {
  late _MemoryExploreTourStore store;
  late ExploreGuidedTourController controller;
  late GlobalKey searchKey;
  late GlobalKey trendingKey;
  late GlobalKey trendingHeadingKey;
  late GlobalKey switcherKey;
  late GlobalKey firstPostKey;
  late GlobalKey contentFallbackKey;
  late ValueNotifier<double> postTop;
  late int backgroundTaps;

  setUp(() {
    ExploreTourPreferenceService.clearSessionCompletionsForTesting();
    store = _MemoryExploreTourStore();
    controller = ExploreGuidedTourController(
      preferences: ExploreTourPreferenceService(store: store),
    );
    searchKey = GlobalKey();
    trendingKey = GlobalKey();
    trendingHeadingKey = GlobalKey();
    switcherKey = GlobalKey();
    firstPostKey = GlobalKey();
    contentFallbackKey = GlobalKey();
    postTop = ValueNotifier<double>(294);
    backgroundTaps = 0;
  });

  tearDown(() {
    controller.dispose();
    postTop.dispose();
  });

  Future<BuildContext> pumpHarness(
    WidgetTester tester, {
    bool includeTrending = true,
    bool includePost = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 16,
                right: 16,
                top: 36,
                height: 56,
                child: GestureDetector(
                  key: searchKey,
                  onTap: () => backgroundTaps += 1,
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
              if (includeTrending)
                Positioned(
                  left: 16,
                  right: 16,
                  top: 116,
                  height: 82,
                  child: SizedBox(
                    key: trendingKey,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        key: trendingHeadingKey,
                        width: 210,
                        height: 24,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 16,
                right: 16,
                top: 214,
                height: 64,
                child: SizedBox(key: switcherKey),
              ),
              ValueListenableBuilder<double>(
                valueListenable: postTop,
                builder: (context, top, child) => Positioned(
                  left: 16,
                  right: 16,
                  top: top,
                  height: 300,
                  child: SizedBox(
                    key: contentFallbackKey,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: includePost
                          ? SizedBox(key: firstPostKey, width: 156, height: 250)
                          : const Text('No posts available right now.'),
                    ),
                  ),
                ),
              ),
              const Center(
                child: SizedBox(key: ValueKey<String>('explore-tour-host')),
              ),
            ],
          ),
        ),
      ),
    );
    return tester.element(
      find.byKey(const ValueKey<String>('explore-tour-host')),
    );
  }

  ExploreTourTargets targets() => ExploreTourTargets(
    search: searchKey,
    trending: trendingKey,
    feedSwitcher: switcherKey,
    firstPost: firstPostKey,
    contentFallback: contentFallbackKey,
  );

  Future<Future<ExploreTourExitReason?>> startTour(
    WidgetTester tester, {
    String uid = 'user-a',
    bool includeTrending = true,
    bool includePost = true,
    ExploreTourPrepareStep? prepareStep,
  }) async {
    final context = await pumpHarness(
      tester,
      includeTrending: includeTrending,
      includePost: includePost,
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

  testWidgets('first eligible visit starts at Search Profiles & Hashtags', (
    tester,
  ) async {
    await startTour(tester);

    expect(find.text('Search Profiles & Hashtags'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('explore-tour-progress-0')),
      findsOneWidget,
    );
    expect(controller.isActive.value, isTrue);
  });

  testWidgets('Next advances through all four steps exactly', (tester) async {
    await startTour(tester);

    await tester.tap(find.byKey(const ValueKey('explore-tour-next')));
    await tester.pumpAndSettle();
    expect(find.text('Trending Hashtags'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('explore-tour-next')));
    await tester.pumpAndSettle();
    expect(find.text('Discover & Nearby You'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('explore-tour-next')));
    await tester.pumpAndSettle();
    expect(find.text('Explore Posts'), findsNWidgets(2));
    expect(find.text('Got it'), findsOneWidget);
  });

  testWidgets('Skip dismisses and persists completion', (tester) async {
    final session = await startTour(tester);

    await tester.tap(find.byKey(const ValueKey('explore-tour-skip')));
    await tester.pumpAndSettle();

    expect(await session, ExploreTourExitReason.skipped);
    expect(store.values['explore_tour_v1_user-a'], isTrue);
    expect(controller.isActive.value, isFalse);
  });

  testWidgets('Got it dismisses and persists completion', (tester) async {
    final session = await startTour(tester);
    for (var index = 0; index < 4; index += 1) {
      await tester.tap(find.byKey(const ValueKey('explore-tour-next')));
      await tester.pumpAndSettle();
    }

    expect(await session, ExploreTourExitReason.completed);
    expect(store.values['explore_tour_v1_user-a'], isTrue);
  });

  testWidgets('completed tour stays closed and another UID remains eligible', (
    tester,
  ) async {
    store.values['explore_tour_v1_user-a'] = true;
    final completedSession = await startTour(tester);
    expect(await completedSession, isNull);
    expect(find.text('Search Profiles & Hashtags'), findsNothing);

    await startTour(tester, uid: 'user-b');
    await tester.pumpAndSettle();
    expect(find.text('Search Profiles & Hashtags'), findsNWidgets(2));
    expect(store.values['explore_tour_v1_user-b'], isNull);
  });

  testWidgets('Home and Explore completion keys remain independent', (
    tester,
  ) async {
    store.values['home_tour_v1_user-a'] = true;
    await startTour(tester);

    expect(find.text('Search Profiles & Hashtags'), findsNWidgets(2));
    expect(store.values['explore_tour_v1_user-a'], isNull);
  });

  testWidgets('cancel removes overlay without persisting completion', (
    tester,
  ) async {
    final session = await startTour(tester);
    controller.cancel();
    await tester.pumpAndSettle();

    expect(await session, ExploreTourExitReason.cancelled);
    expect(find.text('Search Profiles & Hashtags'), findsNothing);
    expect(store.values, isEmpty);
  });

  testWidgets('preference read failure never blocks normal Explore usage', (
    tester,
  ) async {
    controller.dispose();
    controller = ExploreGuidedTourController(
      preferences: ExploreTourPreferenceService(
        store: _FailingExploreTourStore(failRead: true),
      ),
    );

    final session = await startTour(tester);

    expect(await session, isNull);
    expect(find.text('Search Profiles & Hashtags'), findsNothing);
    expect(find.byKey(searchKey), findsOneWidget);
  });

  testWidgets('preference write failure still dismisses the overlay', (
    tester,
  ) async {
    controller.dispose();
    controller = ExploreGuidedTourController(
      preferences: ExploreTourPreferenceService(
        store: _FailingExploreTourStore(failWrite: true),
      ),
    );
    final session = await startTour(tester);

    await tester.tap(find.byKey(const ValueKey('explore-tour-skip')));
    await tester.pumpAndSettle();

    expect(await session, ExploreTourExitReason.skipped);
    expect(find.text('Search Profiles & Hashtags'), findsNothing);
    expect(find.byKey(searchKey), findsOneWidget);
  });

  testWidgets('duplicate starts never stack overlays', (tester) async {
    await startTour(tester);
    final context = tester.element(
      find.byKey(const ValueKey<String>('explore-tour-host')),
    );
    final duplicate = await controller.start(
      context: context,
      uid: 'user-a',
      targets: targets(),
    );

    expect(duplicate, isNull);
    expect(find.text('Search Profiles & Hashtags'), findsNWidgets(2));
  });

  testWidgets('overlay blocks background taps until dismissed', (tester) async {
    await startTour(tester);
    await tester.tapAt(const Offset(40, 60));
    await tester.pump();
    expect(backgroundTaps, 0);

    await tester.tap(find.byKey(const ValueKey('explore-tour-skip')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(40, 60));
    await tester.pump();
    expect(backgroundTaps, 1);
  });

  for (final size in const <Size>[
    Size(360, 640),
    Size(393, 852),
    Size(412, 915),
  ]) {
    testWidgets(
      'targets and cards stay bounded at ${size.width}x${size.height}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await startTour(tester);
        await tester.pumpAndSettle();
        for (var step = 0; step < 4; step += 1) {
          final tooltip = tester.getRect(
            find.byKey(const ValueKey('explore-tour-tooltip-card')),
          );
          final panel = tester.getRect(
            find.byKey(const ValueKey('explore-tour-control-panel')),
          );
          final highlight = tester.getRect(
            find.byKey(const ValueKey('explore-tour-highlight-bounds')),
          );
          expect(tooltip.left, greaterThanOrEqualTo(0));
          expect(tooltip.right, lessThanOrEqualTo(size.width));
          expect(tooltip.top, greaterThanOrEqualTo(0));
          expect(tooltip.bottom, lessThan(panel.top));
          expect(panel.bottom, lessThanOrEqualTo(size.height - 80));
          expect(highlight.left, greaterThanOrEqualTo(0));
          expect(highlight.right, lessThanOrEqualTo(size.width));
          if (step < 3) {
            await tester.tap(find.byKey(const ValueKey('explore-tour-next')));
            await tester.pumpAndSettle();
          }
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('highlights follow each measured target', (tester) async {
    await startTour(tester);
    await tester.pumpAndSettle();

    void expectHighlightContains(GlobalKey targetKey) {
      final target = tester.getRect(find.byKey(targetKey));
      final highlight = tester.getRect(
        find.byKey(const ValueKey('explore-tour-highlight-bounds')),
      );
      expect(highlight.contains(target.topLeft), isTrue);
      expect(highlight.contains(target.bottomRight), isTrue);
    }

    expectHighlightContains(searchKey);
    await tester.tap(find.byKey(const ValueKey('explore-tour-next')));
    await tester.pumpAndSettle();
    expectHighlightContains(trendingKey);
    await tester.tap(find.byKey(const ValueKey('explore-tour-next')));
    await tester.pumpAndSettle();
    expectHighlightContains(switcherKey);
    await tester.tap(find.byKey(const ValueKey('explore-tour-next')));
    await tester.pumpAndSettle();
    expectHighlightContains(firstPostKey);
  });

  testWidgets('1.3 text scaling stays readable without truncation', (
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
      find.byKey(const ValueKey('explore-tour-tooltip-card')),
    );
    final panel = tester.getRect(
      find.byKey(const ValueKey('explore-tour-control-panel')),
    );
    expect(tooltip.bottom, lessThan(panel.top));
    expect(
      find.textContaining('search posts using hashtags'),
      findsNWidgets(2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty dynamic sections use fallbacks without stalling', (
    tester,
  ) async {
    await startTour(tester, includeTrending: false, includePost: false);
    for (var step = 0; step < 3; step += 1) {
      await tester.tap(find.byKey(const ValueKey('explore-tour-next')));
      await tester.pumpAndSettle();
    }

    expect(find.text('Explore Posts'), findsNWidgets(2));
    expect(find.text('No posts available right now.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('steps one to three keep compact tooltips close to targets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await startTour(tester);
    await tester.pumpAndSettle();
    for (var step = 0; step < 3; step += 1) {
      final tooltip = tester.getRect(
        find.byKey(const ValueKey('explore-tour-tooltip-card')),
      );
      final highlight = tester.getRect(
        find.byKey(const ValueKey('explore-tour-highlight-bounds')),
      );
      expect(tooltip.top - highlight.bottom, closeTo(26, 1));
      expect(tooltip.width, lessThanOrEqualTo(step == 1 ? 300 : 286));
      if (step == 1) {
        expect(tooltip.center.dx, closeTo(highlight.center.dx, 1));
      }
      if (step < 2) {
        await tester.tap(find.byKey(const ValueKey('explore-tour-next')));
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('post target is remeasured after tutorial-only repositioning', (
    tester,
  ) async {
    await startTour(
      tester,
      prepareStep: (stepIndex) async {
        if (stepIndex != 3) return;
        postTop.value = 170;
      },
    );
    for (var step = 0; step < 3; step += 1) {
      await tester.tap(find.byKey(const ValueKey('explore-tour-next')));
      await tester.pumpAndSettle();
    }

    final post = tester.getRect(find.byKey(firstPostKey));
    final highlight = tester.getRect(
      find.byKey(const ValueKey('explore-tour-highlight-bounds')),
    );
    expect(post.top, 170);
    expect(highlight.contains(post.topLeft), isTrue);
    expect(highlight.contains(post.bottomRight), isTrue);
  });

  test(
    'post scrolling is minimal and never moves the card under the header',
    () {
      expect(
        calculateExploreTourPostScrollOffset(
          currentOffset: 40,
          minScrollExtent: 0,
          maxScrollExtent: 900,
          targetRect: const Rect.fromLTWH(16, 160, 170, 250),
          headerBottom: 90,
          viewportHeight: 852,
          bottomObstruction: 292,
        ),
        40,
      );

      final raisedOffset = calculateExploreTourPostScrollOffset(
        currentOffset: 40,
        minScrollExtent: 0,
        maxScrollExtent: 900,
        targetRect: const Rect.fromLTWH(16, 500, 170, 250),
        headerBottom: 90,
        viewportHeight: 852,
        bottomObstruction: 292,
      );
      expect(raisedOffset, 230);
      expect(500 - (raisedOffset - 40), greaterThanOrEqualTo(104));

      final loweredOffset = calculateExploreTourPostScrollOffset(
        currentOffset: 200,
        minScrollExtent: 0,
        maxScrollExtent: 900,
        targetRect: const Rect.fromLTWH(16, 80, 170, 250),
        headerBottom: 90,
        viewportHeight: 852,
        bottomObstruction: 292,
      );
      expect(loweredOffset, 176);
      expect(80 - (loweredOffset - 200), 104);
    },
  );

  for (final size in const <Size>[
    Size(360, 640),
    Size(393, 852),
    Size(412, 915),
  ]) {
    testWidgets(
      'step 1 and 4 arrows adapt safely at ${size.width}x${size.height}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await startTour(tester);
        await tester.pumpAndSettle();

        final searchSpotlight = tester.getRect(
          find.byKey(const ValueKey('explore-tour-highlight-bounds')),
        );
        final searchTooltip = tester.getRect(
          find.byKey(const ValueKey('explore-tour-tooltip-card')),
        );
        final trendingHeading = tester.getRect(find.byKey(trendingHeadingKey));
        final searchArrow = calculateExploreTourArrowGeometry(
          stepIndex: 0,
          tooltipRect: searchTooltip,
          targetRect: searchSpotlight,
        );
        final searchHead = calculateExploreTourArrowHead(
          searchArrow,
          arrowLength: 8,
        );

        expect(searchArrow.start.dx, closeTo(searchTooltip.left - 1, 0.01));
        expect(searchArrow.start.dy, greaterThan(searchTooltip.top));
        expect(searchArrow.start.dy, lessThan(searchTooltip.center.dy));
        expect(searchArrow.end.dy - searchSpotlight.bottom, 8);
        expect(searchArrow.end.dy - searchArrow.control2.dy, lessThan(0));
        _expectArrowOutside(
          searchArrow,
          searchHead,
          <Rect>[searchSpotlight, searchTooltip],
          headExcludedRects: <Rect>[trendingHeading],
        );

        for (var step = 0; step < 3; step += 1) {
          await tester.tap(find.byKey(const ValueKey('explore-tour-next')));
          await tester.pumpAndSettle();
        }

        final postSpotlight = tester.getRect(
          find.byKey(const ValueKey('explore-tour-highlight-bounds')),
        );
        final postTooltip = tester.getRect(
          find.byKey(const ValueKey('explore-tour-tooltip-card')),
        );
        final postArrow = calculateExploreTourArrowGeometry(
          stepIndex: 3,
          tooltipRect: postTooltip,
          targetRect: postSpotlight,
        );
        final postHead = calculateExploreTourArrowHead(
          postArrow,
          arrowLength: 6,
        );

        expect(postArrow.start.dx, closeTo(postTooltip.left - 1, 0.01));
        expect(postArrow.start.dy, greaterThan(postTooltip.top));
        expect(postArrow.start.dy, lessThan(postTooltip.center.dy));
        if (postTooltip.bottom <= postSpotlight.top) {
          expect(postSpotlight.top - postArrow.end.dy, 8);
        } else {
          expect(postArrow.end.dx - postSpotlight.right, 8);
        }
        expect(postArrow.end.dx, lessThan(postArrow.start.dx));
        expect(postArrow.end.dy - postArrow.control2.dy, greaterThan(0));
        _expectArrowOutside(postArrow, postHead, <Rect>[
          postSpotlight,
          postTooltip,
        ]);
      },
    );
  }

  test('steps 2 and 3 retain their previous arrow geometry', () {
    const target = Rect.fromLTWH(20, 30, 320, 82);
    const tooltip = Rect.fromLTWH(92, 138, 230, 104);

    final trendingArrow = calculateExploreTourArrowGeometry(
      stepIndex: 1,
      tooltipRect: tooltip,
      targetRect: target,
    );
    _expectOffsetClose(trendingArrow.start, const Offset(127.6, 137));
    _expectOffsetClose(trendingArrow.control1, const Offset(127.6, 131));
    _expectOffsetClose(trendingArrow.control2, const Offset(119.6, 128));
    _expectOffsetClose(trendingArrow.end, const Offset(109.6, 120));

    final switcherArrow = calculateExploreTourArrowGeometry(
      stepIndex: 2,
      tooltipRect: tooltip,
      targetRect: target,
    );
    _expectOffsetClose(switcherArrow.start, const Offset(238.4, 137));
    _expectOffsetClose(switcherArrow.control1, const Offset(238.4, 131));
    _expectOffsetClose(switcherArrow.control2, const Offset(228.4, 128));
    _expectOffsetClose(switcherArrow.end, const Offset(218.4, 120));
  });
}

Offset _sampleCubic(ExploreTourArrowGeometry geometry, double t) {
  final oneMinusT = 1 - t;
  return geometry.start * (oneMinusT * oneMinusT * oneMinusT) +
      geometry.control1 * (3 * oneMinusT * oneMinusT * t) +
      geometry.control2 * (3 * oneMinusT * t * t) +
      geometry.end * (t * t * t);
}

void _expectArrowOutside(
  ExploreTourArrowGeometry geometry,
  ExploreTourArrowHead head,
  List<Rect> excludedRects, {
  List<Rect> headExcludedRects = const <Rect>[],
}) {
  for (var sample = 0; sample <= 40; sample += 1) {
    final point = _sampleCubic(geometry, sample / 40);
    for (final rect in excludedRects) {
      expect(
        rect.contains(point),
        isFalse,
        reason: 'shaft sample $sample at $point entered $rect for $geometry',
      );
    }
  }
  final arrowheadExcludedRects = <Rect>[...excludedRects, ...headExcludedRects];
  for (final wing in <Offset>[head.firstWing, head.secondWing]) {
    for (var sample = 0; sample <= 20; sample += 1) {
      final point = Offset.lerp(geometry.end, wing, sample / 20)!;
      for (final rect in arrowheadExcludedRects) {
        expect(
          rect.contains(point),
          isFalse,
          reason: 'arrowhead sample $sample at $point entered $rect',
        );
      }
    }
  }
}

void _expectOffsetClose(Offset actual, Offset expected) {
  expect(actual.dx, closeTo(expected.dx, 0.0001));
  expect(actual.dy, closeTo(expected.dy, 0.0001));
}

class _MemoryExploreTourStore implements ExploreTourCompletionStore {
  final Map<String, bool> values = <String, bool>{};

  @override
  Future<bool> read(String key) async => values[key] ?? false;

  @override
  Future<void> write(String key, bool value) async {
    values[key] = value;
  }
}

class _FailingExploreTourStore implements ExploreTourCompletionStore {
  const _FailingExploreTourStore({
    this.failRead = false,
    this.failWrite = false,
  });

  final bool failRead;
  final bool failWrite;

  @override
  Future<bool> read(String key) async {
    if (failRead) throw StateError('read failed');
    return false;
  }

  @override
  Future<void> write(String key, bool value) async {
    if (failWrite) throw StateError('write failed');
  }
}
