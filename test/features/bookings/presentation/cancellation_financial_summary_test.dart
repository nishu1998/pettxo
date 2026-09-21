import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/presentation/widgets/cancellation_financial_summary.dart';
import 'package:pettexo/features/bookings/presentation/widgets/canonical_booking_status_detail_template.dart';

void main() {
  for (final entry in {
    'REFUND_REQUIRED': 'Refund required',
    'PROCESSING': 'Processing',
    'REFUNDED': 'Refunded',
    'NEEDS_ATTENTION': 'Needs attention',
  }.entries) {
    testWidgets('customer cancellation uses own allocation: ${entry.key}', (
      tester,
    ) async {
      final model = CustomerCancellationFinancialPresentation(
        paidPaise: 100,
        refundPaise: 25,
        refundStatus: entry.key,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FinancialSummaryCard(rows: model.rows)),
        ),
      );
      expect(find.text('₹1.00'), findsOneWidget);
      expect(find.text('₹0.25'), findsOneWidget);
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('₹0.60'), findsNothing);
      expect(find.text('Payout status'), findsNothing);
      expect(find.text('Your earnings'), findsNothing);
    });
  }
}
