import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pettexo/main.dart';

void main() {
  testWidgets('Pettexo app builds a MaterialApp shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const PettexoApp());

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
