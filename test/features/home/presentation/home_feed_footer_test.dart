import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/home/presentation/screens/home_screen.dart';

void main() {
  testWidgets('caught-up footer renders the production end-of-feed message', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HomeFeedCaughtUpFooter())),
    );

    expect(find.text("You're all caught up"), findsOneWidget);
  });
}
