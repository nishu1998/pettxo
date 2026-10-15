import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/home/presentation/screens/home_screen.dart';

void main() {
  test('initial loader area is centered between header and bottom nav', () {
    final area = calculateHomeInitialLoaderArea(
      viewportSize: const Size(393, 852),
      topContentPadding: 100,
      bottomContentPadding: 120,
    );

    expect(area, const Rect.fromLTRB(0, 100, 393, 732));
    expect(area.center, const Offset(196.5, 416));
  });

  test('initial loader area remains valid on a compact screen', () {
    final area = calculateHomeInitialLoaderArea(
      viewportSize: const Size(360, 640),
      topContentPadding: 92,
      bottomContentPadding: 104,
    );

    expect(area.top, 92);
    expect(area.bottom, 536);
    expect(area.height, 444);
  });

  testWidgets('caught-up footer renders the production end-of-feed message', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HomeFeedCaughtUpFooter())),
    );

    expect(find.text("You're all caught up"), findsOneWidget);
  });
}
