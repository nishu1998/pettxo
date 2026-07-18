import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pettexo/main.dart';

void main() {
  testWidgets('Pettexo app widget can be constructed', (
    WidgetTester tester,
  ) async {
    const app = PettexoApp();

    expect(app, isA<StatelessWidget>());
  });
}
