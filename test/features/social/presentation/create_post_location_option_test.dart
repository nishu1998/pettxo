import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/social/presentation/screens/create_post_screen.dart';

void main() {
  testWidgets('post location option defaults to checked and is wired', (
    tester,
  ) async {
    bool? changedValue;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostLocationOption(
            enabled: true,
            onChanged: (value) => changedValue = value,
          ),
        ),
      ),
    );

    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const Key('create-post-location-toggle')),
    );
    expect(toggle.value, isTrue);

    await tester.tap(find.text('Add location to this post'));
    await tester.pump();
    expect(changedValue, isFalse);
  });
}
