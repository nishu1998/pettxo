import 'package:flutter/material.dart';
import '../../data/repositories/booking_repository.dart';
import '../../domain/models/provider_earning_record.dart';
import '../utils/provider_earnings_presentation.dart';
import 'canonical_booking_status_detail_template.dart';

/// Customer projection deliberately has no provider allocation or payout data.
class CustomerCancellationFinancialPresentation {
  const CustomerCancellationFinancialPresentation({
    required this.paidPaise,
    required this.refundPaise,
    required this.refundStatus,
  });
  final int paidPaise;
  final int refundPaise;
  final String refundStatus;

  String get statusLabel => switch (refundStatus.trim().toUpperCase()) {
    'REFUND_REQUIRED' || 'REQUIRED' => 'Refund required',
    'REFUND_PENDING' ||
    'PENDING' ||
    'PROCESSING' ||
    'SUBMITTED' => 'Processing',
    'REFUNDED' || 'COMPLETED' || 'PROCESSED' || 'SUCCESS' => 'Refunded',
    'REFUND_FAILED' || 'FAILED' || 'NEEDS_ATTENTION' => 'Needs attention',
    'NOT_REQUIRED' || 'NO_REFUND' => 'No refund',
    _ => 'Awaiting update',
  };
  List<StatusFinancialRowModel> get rows => [
    StatusFinancialRowModel(
      label: 'You paid',
      value: formatEarningsPaise(paidPaise),
    ),
    StatusFinancialRowModel(
      label: 'Refund',
      value: formatEarningsPaise(refundPaise),
    ),
    StatusFinancialRowModel(label: 'Refund status', value: statusLabel),
  ];
}

/// Receives only the provider earnings read model; no customer refund inputs.
class ProviderCancellationEarnings extends StatelessWidget {
  const ProviderCancellationEarnings({
    super.key,
    required this.repository,
    required this.bookingId,
  });
  final BookingRepository repository;
  final String bookingId;
  @override
  Widget build(BuildContext context) => StreamBuilder<ProviderEarningRecord?>(
    stream: repository.watchCanonicalProviderEarning(bookingId),
    builder: (context, snapshot) {
      final earning = snapshot.data;
      final amount = earning?.finalEntitlementPaise;
      return FinancialSummaryCard(
        rows: [
          StatusFinancialRowModel(
            label: 'Your earnings',
            value: snapshot.hasError
                ? 'Unavailable'
                : amount == null
                ? 'Awaiting finalization'
                : formatEarningsPaise(amount),
          ),
          if (earning != null)
            StatusFinancialRowModel(
              label: 'Earning status',
              value: earningsStatusLabel(earning),
            ),
          if (earning != null && earningsPayoutLabel(earning) != null)
            StatusFinancialRowModel(
              label: 'Payout status',
              value: earningsPayoutLabel(earning)!.replaceFirst('Payout: ', ''),
            ),
        ],
      );
    },
  );
}
