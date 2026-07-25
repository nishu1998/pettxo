import 'package:cloud_firestore/cloud_firestore.dart';

class CanonicalBookingCancellationPreview {
  final String bookingId;
  final String actorType;
  final bool allowed;
  final String outcome;
  final String timingBand;
  final int refundPercentageBasisPoints;
  final int providerShareBasisPoints;
  final int pettxoShareBasisPoints;
  final int customerPaidPaise;
  final int refundableCustomerPaidPaise;
  final int nonRefundableCustomerPaidPaise;
  final int grossCustomerRefundPaise;
  final int remainingRefundablePaise;
  final int providerCompensationPaise;
  final int pettxoRetainedPaise;
  final String message;
  final String policyVersion;

  const CanonicalBookingCancellationPreview({
    required this.bookingId,
    required this.actorType,
    required this.allowed,
    required this.outcome,
    required this.timingBand,
    required this.refundPercentageBasisPoints,
    required this.providerShareBasisPoints,
    required this.pettxoShareBasisPoints,
    required this.customerPaidPaise,
    required this.refundableCustomerPaidPaise,
    required this.nonRefundableCustomerPaidPaise,
    required this.grossCustomerRefundPaise,
    required this.remainingRefundablePaise,
    required this.providerCompensationPaise,
    required this.pettxoRetainedPaise,
    required this.message,
    required this.policyVersion,
  });

  factory CanonicalBookingCancellationPreview.fromMap(
    Map<String, dynamic> data,
  ) {
    return CanonicalBookingCancellationPreview(
      bookingId: (data['bookingId'] as String? ?? '').trim(),
      actorType: (data['actorType'] as String? ?? '').trim(),
      allowed: data['allowed'] == true,
      outcome: (data['outcome'] as String? ?? '').trim(),
      timingBand: (data['timingBand'] as String? ?? '').trim(),
      refundPercentageBasisPoints:
          (data['refundPercentageBasisPoints'] as num?)?.round() ?? 0,
      providerShareBasisPoints:
          (data['providerShareBasisPoints'] as num?)?.round() ?? 0,
      pettxoShareBasisPoints:
          (data['pettxoShareBasisPoints'] as num?)?.round() ?? 0,
      customerPaidPaise: (data['customerPaidPaise'] as num?)?.round() ?? 0,
      refundableCustomerPaidPaise:
          (data['refundableCustomerPaidPaise'] as num?)?.round() ?? 0,
      nonRefundableCustomerPaidPaise:
          (data['nonRefundableCustomerPaidPaise'] as num?)?.round() ?? 0,
      grossCustomerRefundPaise:
          (data['grossCustomerRefundPaise'] as num?)?.round() ?? 0,
      remainingRefundablePaise:
          (data['remainingRefundablePaise'] as num?)?.round() ?? 0,
      providerCompensationPaise:
          (data['providerCompensationPaise'] as num?)?.round() ?? 0,
      pettxoRetainedPaise: (data['pettxoRetainedPaise'] as num?)?.round() ?? 0,
      message: (data['message'] as String? ?? '').trim(),
      policyVersion: (data['policyVersion'] as String? ?? '').trim(),
    );
  }
}

class CanonicalBookingCancellationResult {
  final String bookingId;
  final String state;
  final String cancellationStatus;
  final String refundStatus;
  final int refundAmountPaise;
  final String timingBand;
  final String outcome;
  final DateTime? cancelledAt;
  final bool idempotentReplay;

  const CanonicalBookingCancellationResult({
    required this.bookingId,
    required this.state,
    required this.cancellationStatus,
    required this.refundStatus,
    required this.refundAmountPaise,
    required this.timingBand,
    required this.outcome,
    required this.cancelledAt,
    required this.idempotentReplay,
  });

  factory CanonicalBookingCancellationResult.fromMap(
    Map<String, dynamic> data,
  ) {
    return CanonicalBookingCancellationResult(
      bookingId: (data['bookingId'] as String? ?? '').trim(),
      state: (data['state'] as String? ?? '').trim(),
      cancellationStatus: (data['cancellationStatus'] as String? ?? '').trim(),
      refundStatus: (data['refundStatus'] as String? ?? '').trim(),
      refundAmountPaise: (data['refundAmountPaise'] as num?)?.round() ?? 0,
      timingBand: (data['timingBand'] as String? ?? '').trim(),
      outcome: (data['outcome'] as String? ?? '').trim(),
      cancelledAt: _readDate(data['cancelledAt']),
      idempotentReplay: data['idempotentReplay'] == true,
    );
  }
}

class CanonicalBookingCancellationRecord {
  final String bookingId;
  final String actorType;
  final String actorId;
  final String reasonCode;
  final String reasonText;
  final DateTime? requestedAt;
  final DateTime? effectiveAt;
  final String policyVersion;
  final String timingBand;
  final int refundPercentageBasisPoints;
  final int providerShareBasisPoints;
  final int pettxoShareBasisPoints;
  final int refundableCustomerPaidPaise;
  final int nonRefundableCustomerPaidPaise;
  final int providerCompensationPaise;
  final int pettxoRetainedPaise;
  final int gatewayFeeSunkPaise;
  final int providerFaultCostPaise;
  final int customerPaidPaise;
  final bool capacityReleaseRequired;
  final bool financialReversalRequired;
  final String refundInstructionId;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int refundAmountPaise;
  final String refundStatus;
  final String capacityReleaseState;
  final String outcome;

  const CanonicalBookingCancellationRecord({
    required this.bookingId,
    required this.actorType,
    required this.actorId,
    required this.reasonCode,
    required this.reasonText,
    required this.requestedAt,
    required this.effectiveAt,
    required this.policyVersion,
    required this.timingBand,
    required this.refundPercentageBasisPoints,
    required this.providerShareBasisPoints,
    required this.pettxoShareBasisPoints,
    required this.refundableCustomerPaidPaise,
    required this.nonRefundableCustomerPaidPaise,
    required this.providerCompensationPaise,
    required this.pettxoRetainedPaise,
    required this.gatewayFeeSunkPaise,
    required this.providerFaultCostPaise,
    required this.customerPaidPaise,
    required this.capacityReleaseRequired,
    required this.financialReversalRequired,
    required this.refundInstructionId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.refundAmountPaise,
    required this.refundStatus,
    required this.capacityReleaseState,
    required this.outcome,
  });

  factory CanonicalBookingCancellationRecord.fromMap(
    Map<String, dynamic> data,
  ) {
    return CanonicalBookingCancellationRecord(
      bookingId: (data['bookingId'] as String? ?? '').trim(),
      actorType: (data['actorType'] as String? ?? '').trim(),
      actorId: (data['actorId'] as String? ?? '').trim(),
      reasonCode: (data['reasonCode'] as String? ?? '').trim(),
      reasonText: (data['reasonText'] as String? ?? '').trim(),
      requestedAt: _readDate(data['requestedAt']),
      effectiveAt: _readDate(data['effectiveAt']),
      policyVersion: (data['policyVersion'] as String? ?? '').trim(),
      timingBand: (data['timingBand'] as String? ?? '').trim(),
      refundPercentageBasisPoints:
          (data['refundPercentageBasisPoints'] as num?)?.round() ?? 0,
      providerShareBasisPoints:
          (data['providerShareBasisPoints'] as num?)?.round() ?? 0,
      pettxoShareBasisPoints:
          (data['pettxoShareBasisPoints'] as num?)?.round() ?? 0,
      refundableCustomerPaidPaise:
          (data['refundableCustomerPaidPaise'] as num?)?.round() ?? 0,
      nonRefundableCustomerPaidPaise:
          (data['nonRefundableCustomerPaidPaise'] as num?)?.round() ?? 0,
      providerCompensationPaise:
          (data['providerCompensationPaise'] as num?)?.round() ?? 0,
      pettxoRetainedPaise: (data['pettxoRetainedPaise'] as num?)?.round() ?? 0,
      gatewayFeeSunkPaise: (data['gatewayFeeSunkPaise'] as num?)?.round() ?? 0,
      providerFaultCostPaise:
          (data['providerFaultCostPaise'] as num?)?.round() ?? 0,
      customerPaidPaise: (data['customerPaidPaise'] as num?)?.round() ?? 0,
      capacityReleaseRequired: data['capacityReleaseRequired'] == true,
      financialReversalRequired: data['financialReversalRequired'] == true,
      refundInstructionId: (data['refundInstructionId'] as String? ?? '')
          .trim(),
      status: (data['status'] as String? ?? '').trim(),
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
      refundAmountPaise: (data['refundAmountPaise'] as num?)?.round() ?? 0,
      refundStatus: (data['refundStatus'] as String? ?? '').trim(),
      capacityReleaseState: (data['capacityReleaseState'] as String? ?? '')
          .trim(),
      outcome: (data['outcome'] as String? ?? '').trim(),
    );
  }
}

DateTime? _readDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value.trim());
  return null;
}
