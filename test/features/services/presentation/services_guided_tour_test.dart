import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/services/data/services_tour_preference_service.dart';
import 'package:pettexo/features/services/presentation/widgets/services_guided_tour.dart';

void main() {
  late _MemoryServicesTourStore store;
  late ServicesGuidedTourController controller;
  late GlobalKey filtersKey;
  late GlobalKey animalKey;
  late GlobalKey serviceKey;
  late GlobalKey searchKey;
  late GlobalKey firstCardKey;
  late GlobalKey fallbackKey;
  late int backgroundTaps;

  setUp(() {
    ServicesTourPreferenceService.clearSessionCompletionsForTesting();
    store = _MemoryServicesTourStore();
    controller = ServicesGuidedTourController(
      preferences: ServicesTourPreferenceService(store: store),
    );
    filtersKey = GlobalKey();
    animalKey = GlobalKey();
    serviceKey = GlobalKey();
    searchKey = GlobalKey();
    firstCardKey = GlobalKey();
    fallbackKey = GlobalKey();
    backgroundTaps = 0;
  });

  tearDown(() => controller.dispose());

  Future<BuildContext> pumpHarness(
    WidgetTester tester, {
    bool includeCard = true,
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
                left: 18,
                right: 18,
                top: 46,
                height: 44,
                child: SizedBox(key: searchKey),
              ),
              Positioned(
                left: 18,
                right: 18,
                top: 126,
                height: 116,
                child: SizedBox(
                  key: filtersKey,
                  child: Column(
                    children: [
                      SizedBox(key: animalKey, height: 52),
                      const SizedBox(height: 12),
                      SizedBox(key: serviceKey, height: 52),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                top: 260,
                height: 18,
                child: SizedBox(key: fallbackKey),
              ),
              if (includeCard)
                Positioned(
                  left: 18,
                  right: 18,
                  top: 286,
                  height: 176,
                  child: SizedBox(key: firstCardKey),
                ),
              const Center(
                child: SizedBox(key: ValueKey<String>('services-tour-host')),
              ),
            ],
          ),
        ),
      ),
    );
    return tester.element(
      find.byKey(const ValueKey<String>('services-tour-host')),
    );
  }

  ServicesTourTargets targets() => ServicesTourTargets(
    filters: filtersKey,
    search: searchKey,
    firstCard: firstCardKey,
    contentFallback: fallbackKey,
  );

  Future<Future<ServicesTourExitReason?>> startTour(
    WidgetTester tester, {
    String uid = 'user-a',
    bool includeCard = true,
  }) async {
    final context = await pumpHarness(tester, includeCard: includeCard);
    final session = controller.start(
      context: context,
      uid: uid,
      targets: targets(),
    );
    await tester.pump();
    return session;
  }

  testWidgets('first eligible visit starts at Animal & Service Types', (
    tester,
  ) async {
    await startTour(tester);

    expect(find.text('Animal & Service Types'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('services-tour-progress-0')), findsOne);
    expect(controller.isActive.value, isTrue);
  });

  testWidgets('Next advances exactly from step 1 to 2 to 3', (tester) async {
    await startTour(tester);

    await tester.tap(find.byKey(const ValueKey('services-tour-next')));
    await tester.pumpAndSettle();
    expect(find.text('Search Services'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('services-tour-next')));
    await tester.pumpAndSettle();
    expect(find.text('Service Cards'), findsNWidgets(2));
    expect(find.text('Got it'), findsOne);
  });

  testWidgets('Skip closes and persists completion', (tester) async {
    final session = await startTour(tester);
    await tester.tap(find.byKey(const ValueKey('services-tour-skip')));
    await tester.pumpAndSettle();

    expect(await session, ServicesTourExitReason.skipped);
    expect(store.values['services_tour_v1_user-a'], isTrue);
    expect(controller.isActive.value, isFalse);
  });

  testWidgets('Got it closes and persists completion', (tester) async {
    final session = await startTour(tester);
    for (var step = 0; step < 3; step += 1) {
      await tester.tap(find.byKey(const ValueKey('services-tour-next')));
      await tester.pumpAndSettle();
    }

    expect(await session, ServicesTourExitReason.completed);
    expect(store.values['services_tour_v1_user-a'], isTrue);
  });

  testWidgets('completed user stays closed and another UID remains eligible', (
    tester,
  ) async {
    store.values['services_tour_v1_user-a'] = true;
    final completed = await startTour(tester);
    expect(await completed, isNull);

    await startTour(tester, uid: 'user-b');
    await tester.pumpAndSettle();
    expect(find.text('Animal & Service Types'), findsNWidgets(2));
  });

  testWidgets('Home and Explore completion keys do not complete Services', (
    tester,
  ) async {
    store.values['home_tour_v1_user-a'] = true;
    store.values['explore_tour_v1_user-a'] = true;

    await startTour(tester);

    expect(find.text('Animal & Service Types'), findsNWidgets(2));
    expect(store.values['services_tour_v1_user-a'], isNull);
  });

  testWidgets('cancel removes overlay without persisting completion', (
    tester,
  ) async {
    final session = await startTour(tester);
    controller.cancel();
    await tester.pumpAndSettle();

    expect(await session, ServicesTourExitReason.cancelled);
    expect(store.values, isEmpty);
    expect(find.text('Animal & Service Types'), findsNothing);
  });

  testWidgets('overlay blocks background interactions until dismissed', (
    tester,
  ) async {
    await startTour(tester);
    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    expect(backgroundTaps, 0);

    await tester.tap(find.byKey(const ValueKey('services-tour-skip')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    expect(backgroundTaps, 1);
  });

  testWidgets('spotlights follow filters, search, and first visible card', (
    tester,
  ) async {
    await startTour(tester);
    await tester.pumpAndSettle();

    Rect highlight() => tester.getRect(
      find.byKey(const ValueKey('services-tour-highlight-bounds')),
    );

    final filters = tester.getRect(find.byKey(filtersKey));
    expect(
      highlight().contains(tester.getRect(find.byKey(animalKey)).topLeft),
      isTrue,
    );
    expect(
      highlight().contains(tester.getRect(find.byKey(serviceKey)).bottomRight),
      isTrue,
    );
    expect(highlight().contains(filters.center), isTrue);

    await tester.tap(find.byKey(const ValueKey('services-tour-next')));
    await tester.pumpAndSettle();
    final search = tester.getRect(find.byKey(searchKey));
    expect(highlight().contains(search.topLeft), isTrue);
    expect(highlight().contains(search.bottomRight), isTrue);

    await tester.tap(find.byKey(const ValueKey('services-tour-next')));
    await tester.pumpAndSettle();
    final card = tester.getRect(find.byKey(firstCardKey));
    expect(highlight().contains(card.topLeft), isTrue);
    expect(highlight().contains(card.bottomRight), isTrue);
  });

  testWidgets('missing service card uses stable content fallback', (
    tester,
  ) async {
    await startTour(tester, includeCard: false);
    for (var step = 0; step < 2; step += 1) {
      await tester.tap(find.byKey(const ValueKey('services-tour-next')));
      await tester.pumpAndSettle();
    }

    final fallback = tester.getRect(find.byKey(fallbackKey));
    final highlight = tester.getRect(
      find.byKey(const ValueKey('services-tour-highlight-bounds')),
    );
    expect(highlight.top, lessThanOrEqualTo(fallback.top));
    expect(highlight.height, greaterThan(100));
    expect(tester.takeException(), isNull);
  });

  for (final size in const <Size>[
    Size(360, 640),
    Size(393, 852),
    Size(412, 915),
  ]) {
    testWidgets('layout and arrows stay safe at ${size.width}x${size.height}', (
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
      for (var step = 0; step < 3; step += 1) {
        final tooltip = tester.getRect(
          find.byKey(const ValueKey('services-tour-tooltip-card')),
        );
        final controls = tester.getRect(
          find.byKey(const ValueKey('services-tour-control-panel')),
        );
        final target = tester.getRect(
          find.byKey(const ValueKey('services-tour-highlight-bounds')),
        );
        final arrow = calculateServicesTourArrowGeometry(
          stepIndex: step,
          tooltipRect: tooltip,
          targetRect: target,
        );
        final head = calculateServicesTourArrowHead(arrow);
        expect(tooltip.left, greaterThanOrEqualTo(0));
        expect(tooltip.right, lessThanOrEqualTo(size.width));
        expect(tooltip.top, greaterThanOrEqualTo(0));
        expect(tooltip.bottom, lessThan(controls.top));
        expect(controls.bottom, lessThanOrEqualTo(size.height));
        _expectArrowOutside(arrow, head, <Rect>[tooltip, target]);

        if (step < 2) {
          await tester.tap(find.byKey(const ValueKey('services-tour-next')));
          await tester.pumpAndSettle();
        }
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('1.3 text scaling remains readable without overlap', (
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
      find.byKey(const ValueKey('services-tour-tooltip-card')),
    );
    final controls = tester.getRect(
      find.byKey(const ValueKey('services-tour-control-panel')),
    );
    expect(tooltip.bottom, lessThan(controls.top));
    expect(find.textContaining('most relevant providers'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  test('card scrolling is minimal and respects header clearance', () {
    expect(
      calculateServicesTourCardScrollOffset(
        currentOffset: 40,
        minScrollExtent: 0,
        maxScrollExtent: 900,
        targetRect: const Rect.fromLTWH(18, 180, 357, 176),
        headerBottom: 100,
        viewportHeight: 852,
        bottomObstruction: 292,
      ),
      40,
    );

    final adjusted = calculateServicesTourCardScrollOffset(
      currentOffset: 40,
      minScrollExtent: 0,
      maxScrollExtent: 900,
      targetRect: const Rect.fromLTWH(18, 500, 357, 176),
      headerBottom: 100,
      viewportHeight: 852,
      bottomObstruction: 292,
    );
    expect(adjusted, 156);
    expect(500 - (adjusted - 40), greaterThanOrEqualTo(114));
  });

  testWidgets('storage failures never block normal Services usage', (
    tester,
  ) async {
    controller.dispose();
    controller = ServicesGuidedTourController(
      preferences: ServicesTourPreferenceService(
        store: const _FailingServicesTourStore(),
      ),
    );

    final session = await startTour(tester);
    expect(await session, isNull);
    expect(find.byKey(filtersKey), findsOne);
    expect(find.text('Animal & Service Types'), findsNothing);
  });
}

Offset _sampleCubic(ServicesTourArrowGeometry geometry, double t) {
  final inverse = 1 - t;
  return geometry.start * (inverse * inverse * inverse) +
      geometry.control1 * (3 * inverse * inverse * t) +
      geometry.control2 * (3 * inverse * t * t) +
      geometry.end * (t * t * t);
}

void _expectArrowOutside(
  ServicesTourArrowGeometry geometry,
  ServicesTourArrowHead head,
  List<Rect> excludedRects,
) {
  for (var sample = 0; sample <= 40; sample += 1) {
    final point = _sampleCubic(geometry, sample / 40);
    for (final rect in excludedRects) {
      expect(
        rect.contains(point),
        isFalse,
        reason: 'shaft sample $sample at $point entered $rect',
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
          reason: 'arrowhead sample $sample at $point entered $rect',
        );
      }
    }
  }
}

class _MemoryServicesTourStore implements ServicesTourCompletionStore {
  final Map<String, bool> values = <String, bool>{};

  @override
  Future<bool> read(String key) async => values[key] ?? false;

  @override
  Future<void> write(String key, bool value) async {
    values[key] = value;
  }
}

class _FailingServicesTourStore implements ServicesTourCompletionStore {
  const _FailingServicesTourStore();

  @override
  Future<bool> read(String key) async => throw StateError('read failed');

  @override
  Future<void> write(String key, bool value) async =>
      throw StateError('write failed');
}
