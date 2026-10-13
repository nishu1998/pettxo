import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/widgets/location_permission_dialog.dart';

void main() {
  Widget buildContent({
    required VoidCallback onNotNow,
    required VoidCallback onContinue,
    double textScale = 1,
    bool disableAnimations = false,
  }) {
    return MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: Scaffold(
            body: LocationPermissionDialogContent(
              onNotNow: onNotNow,
              onContinue: onContinue,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
  }

  void useViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('renders the approved explanation and privacy copy', (
    tester,
  ) async {
    await tester.pumpWidget(buildContent(onNotNow: () {}, onContinue: () {}));

    expect(find.text('Discover what is\nnearby'), findsOneWidget);
    expect(
      find.textContaining('Allow location access to discover nearby posts'),
      findsOneWidget,
    );
    expect(find.text('Your privacy matters'), findsOneWidget);
    expect(
      find.textContaining(
        'We use your approximate location for nearby discovery',
      ),
      findsOneWidget,
    );
    expect(find.text('Not now'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('continue invokes its callback exactly once', (tester) async {
    var continueCount = 0;
    await tester.pumpWidget(
      buildContent(onNotNow: () {}, onContinue: () => continueCount += 1),
    );

    final continueButton = find.byKey(
      const Key('location-permission-continue'),
    );
    await tapVisible(tester, continueButton);
    await tester.tap(continueButton);
    await tester.pump();

    expect(continueCount, 1);
  });

  testWidgets('not now invokes only the dismiss callback', (tester) async {
    var dismissCount = 0;
    var continueCount = 0;
    await tester.pumpWidget(
      buildContent(
        onNotNow: () => dismissCount += 1,
        onContinue: () => continueCount += 1,
      ),
    );

    await tapVisible(
      tester,
      find.byKey(const Key('location-permission-not-now')),
    );
    await tester.pump();

    expect(dismissCount, 1);
    expect(continueCount, 0);
  });

  testWidgets('close has the same behavior as not now', (tester) async {
    var dismissCount = 0;
    await tester.pumpWidget(
      buildContent(onNotNow: () => dismissCount += 1, onContinue: () {}),
    );

    await tester.tap(find.byKey(const Key('location-permission-close')));
    await tester.pump();

    expect(dismissCount, 1);
  });

  testWidgets(
    'rapid taps across actions cannot produce conflicting decisions',
    (tester) async {
      var dismissCount = 0;
      var continueCount = 0;
      await tester.pumpWidget(
        buildContent(
          onNotNow: () => dismissCount += 1,
          onContinue: () => continueCount += 1,
        ),
      );

      await tapVisible(
        tester,
        find.byKey(const Key('location-permission-continue')),
      );
      await tester.tap(find.byKey(const Key('location-permission-not-now')));
      await tester.pump();

      expect(continueCount, 1);
      expect(dismissCount, 0);
    },
  );

  testWidgets('small screens remain scrollable without overflow', (
    tester,
  ) async {
    useViewport(tester, const Size(320, 480));

    await tester.pumpWidget(buildContent(onNotNow: () {}, onContinue: () {}));

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text keeps all actions available without overflow', (
    tester,
  ) async {
    useViewport(tester, const Size(360, 640));

    await tester.pumpWidget(
      buildContent(textScale: 2, onNotNow: () {}, onContinue: () {}),
    );

    expect(
      find.byKey(const Key('location-permission-continue')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('location-permission-not-now')),
      findsOneWidget,
    );
    final continueRect = tester.getRect(
      find.byKey(const Key('location-permission-continue')),
    );
    final notNowRect = tester.getRect(
      find.byKey(const Key('location-permission-not-now')),
    );
    expect(continueRect.bottom, lessThan(notNowRect.top));
    expect(continueRect.width, closeTo(notNowRect.width, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('normal phone width uses a stable 40/60 horizontal action row', (
    tester,
  ) async {
    useViewport(tester, const Size(393, 852));
    await tester.pumpWidget(buildContent(onNotNow: () {}, onContinue: () {}));

    final notNowRect = tester.getRect(
      find.byKey(const Key('location-permission-not-now')),
    );
    final continueRect = tester.getRect(
      find.byKey(const Key('location-permission-continue')),
    );

    expect(notNowRect.top, closeTo(continueRect.top, 0.01));
    expect(notNowRect.height, closeTo(continueRect.height, 0.01));
    expect(notNowRect.height, greaterThanOrEqualTo(48));
    expect(notNowRect.width, greaterThan(100));
    expect(continueRect.width / notNowRect.width, closeTo(1.5, 0.05));
    expect(tester.takeException(), isNull);
  });

  testWidgets('360dp phone keeps both actions horizontal and fully visible', (
    tester,
  ) async {
    useViewport(tester, const Size(360, 800));
    await tester.pumpWidget(buildContent(onNotNow: () {}, onContinue: () {}));

    final notNowRect = tester.getRect(
      find.byKey(const Key('location-permission-not-now')),
    );
    final continueRect = tester.getRect(
      find.byKey(const Key('location-permission-continue')),
    );

    expect(notNowRect.top, closeTo(continueRect.top, 0.01));
    expect(notNowRect.width, greaterThan(100));
    expect(continueRect.right, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow available width stacks full-width actions', (
    tester,
  ) async {
    useViewport(tester, const Size(300, 700));
    await tester.pumpWidget(buildContent(onNotNow: () {}, onContinue: () {}));

    final notNowRect = tester.getRect(
      find.byKey(const Key('location-permission-not-now')),
    );
    final continueRect = tester.getRect(
      find.byKey(const Key('location-permission-continue')),
    );

    expect(continueRect.bottom, lessThan(notNowRect.top));
    expect(notNowRect.width, closeTo(continueRect.width, 0.01));
    expect(notNowRect.height, closeTo(continueRect.height, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog stays centered within a compact viewport budget', (
    tester,
  ) async {
    const viewport = Size(393, 852);
    useViewport(tester, viewport);
    await tester.pumpWidget(buildContent(onNotNow: () {}, onContinue: () {}));

    final dialogRect = tester.getRect(
      find.byKey(const Key('location-permission-dialog-surface')),
    );

    expect(dialogRect.top, greaterThanOrEqualTo(16));
    expect(dialogRect.bottom, lessThanOrEqualTo(viewport.height - 16));
    expect(
      dialogRect.height,
      lessThanOrEqualTo(((viewport.height - 32) * 0.82) + 0.01),
    );
    expect(dialogRect.center.dy, closeTo(viewport.height / 2, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape layout scrolls without clipping or overflow', (
    tester,
  ) async {
    const viewport = Size(760, 360);
    useViewport(tester, viewport);
    await tester.pumpWidget(buildContent(onNotNow: () {}, onContinue: () {}));

    final dialogRect = tester.getRect(
      find.byKey(const Key('location-permission-dialog-surface')),
    );
    expect(dialogRect.top, greaterThanOrEqualTo(16));
    expect(dialogRect.bottom, lessThanOrEqualTo(viewport.height - 16));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog route returns true only from Continue', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await LocationPermissionDialog.show(context: context);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(result, isNull);

    await tapVisible(
      tester,
      find.byKey(const Key('location-permission-continue')),
    );
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('dialog route returns false from close', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await LocationPermissionDialog.show(context: context);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('location-permission-close')));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('reduced-motion mode still presents and dismisses safely', (
    tester,
  ) async {
    var dismissed = false;
    await tester.pumpWidget(
      buildContent(
        disableAnimations: true,
        onNotNow: () => dismissed = true,
        onContinue: () {},
      ),
    );

    await tapVisible(
      tester,
      find.byKey(const Key('location-permission-not-now')),
    );
    await tester.pump();

    expect(dismissed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
