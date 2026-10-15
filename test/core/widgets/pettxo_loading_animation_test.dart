import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:pettexo/core/widgets/pettxo_full_screen_loader.dart';
import 'package:pettexo/core/widgets/pettxo_loading_animation.dart';

void main() {
  Widget host(Widget child, {bool disableAnimations = false}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          disableAnimations: disableAnimations,
        ),
        child: Scaffold(body: Center(child: child)),
      ),
    );
  }

  String displayedAsset(WidgetTester tester) {
    final builder = tester.widget<LottieBuilder>(find.byType(LottieBuilder));
    return (builder.lottie as AssetLottie).assetName;
  }

  testWidgets('regular loader uses the transparent animation', (tester) async {
    await tester.pumpWidget(
      host(const PettxoLoader(semanticLabel: 'Loading pets')),
    );
    await tester.pump();

    expect(displayedAsset(tester), kPettxoLoaderTransparentAsset);
    expect(find.bySemanticsLabel('Loading pets'), findsOneWidget);
    expect(tester.getSize(find.byType(LottieBuilder)), const Size(124, 124));
    expect(
      find.descendant(
        of: find.byType(PettxoLoader),
        matching: find.byType(ColoredBox),
      ),
      findsNothing,
    );
  });

  testWidgets('section loader uses the centralized section size', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const PettxoLoader.section(semanticLabel: 'Loading services')),
    );
    await tester.pump();

    expect(displayedAsset(tester), kPettxoLoaderTransparentAsset);
    expect(tester.getSize(find.byType(LottieBuilder)), const Size(152, 152));
  });

  testWidgets('full-screen loader stays transparent and sizes responsively', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const PettxoLoader.fullScreen(semanticLabel: 'Loading account')),
    );
    await tester.pump();

    expect(displayedAsset(tester), kPettxoLoaderTransparentAsset);
    expect(tester.getSize(find.byType(LottieBuilder)), const Size(192, 192));
  });

  testWidgets('compact loader honors size and reduced motion', (tester) async {
    await tester.pumpWidget(
      host(const PettxoLoader.compact(), disableAnimations: true),
    );
    await tester.pump();

    final builder = tester.widget<LottieBuilder>(find.byType(LottieBuilder));
    expect(tester.getSize(find.byType(LottieBuilder)), const Size(52, 52));
    expect(builder.animate, isFalse);
    expect(builder.repeat, isFalse);
  });

  testWidgets('artwork is enlarged within a clipped composition viewport', (
    tester,
  ) async {
    await tester.pumpWidget(host(const PettxoLoader()));
    await tester.pump();

    final transform = tester.widget<Transform>(
      find.byKey(kPettxoLoaderArtworkTransformKey),
    );
    expect(transform.transform.storage[0], PettxoLoaderDimensions.artworkScale);
    expect(find.byType(ClipRect), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full-screen loader remains in bounds on a compact viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(320, 568)),
          child: const Scaffold(body: Center(child: PettxoLoader.fullScreen())),
        ),
      ),
    );
    await tester.pump();

    expect(tester.getSize(find.byType(LottieBuilder)), const Size(176, 176));
    expect(tester.takeException(), isNull);
  });

  testWidgets('overlay blocks interaction and dismisses for success or error', (
    tester,
  ) async {
    final state = ValueNotifier<String>('loading');
    addTearDown(state.dispose);
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<String>(
          valueListenable: state,
          builder: (context, value, _) {
            return Scaffold(
              body: Stack(
                children: [
                  Center(
                    child: FilledButton(
                      onPressed: () => taps += 1,
                      child: Text(value),
                    ),
                  ),
                  if (value == 'loading')
                    const PettxoFullScreenLoader(message: 'Saving'),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(PettxoLoader), findsOneWidget);
    expect(displayedAsset(tester), kPettxoLoaderTransparentAsset);
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    expect(taps, 0);

    state.value = 'success';
    await tester.pump();
    expect(find.byType(PettxoLoader), findsNothing);
    expect(find.text('success'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    expect(taps, 1);

    state.value = 'error';
    await tester.pump();
    expect(find.byType(PettxoLoader), findsNothing);
    expect(find.text('error'), findsOneWidget);
  });
}
