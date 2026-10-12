import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/services/play_store_review_service.dart';
import 'package:pettexo/core/widgets/play_store_review_dialog.dart';

void main() {
  testWidgets('rating button returns the Play Store navigation action', (
    tester,
  ) async {
    Future<PlayStoreReviewDialogAction?>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                result = PlayStoreReviewDialog.show(context: context);
              },
              child: const Text('Open rating dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open rating dialog'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rate us on Play Store'));
    await tester.pumpAndSettle();

    expect(await result, PlayStoreReviewDialogAction.rateOnPlayStore);
  });
}
