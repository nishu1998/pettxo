class BookingCancellationPreview {
  final bool ok;
  final int refundAmount;
  final int refundAmountPaise;
  final int providerAmount;
  final int providerAmountPaise;
  final int pettxoAmount;
  final int pettxoAmountPaise;
  final int totalAmountPaise;
  final int refundPercent;
  final int providerPercent;
  final int pettxoPercent;
  final String cancellationCase;
  final int graceWindowMinutes;
  final DateTime? graceWindowEndsAt;
  final bool isWithinGraceWindow;
  final String message;

  const BookingCancellationPreview({
    required this.ok,
    required this.refundAmount,
    required this.refundAmountPaise,
    required this.providerAmount,
    required this.providerAmountPaise,
    required this.pettxoAmount,
    required this.pettxoAmountPaise,
    required this.totalAmountPaise,
    required this.refundPercent,
    required this.providerPercent,
    required this.pettxoPercent,
    required this.cancellationCase,
    required this.graceWindowMinutes,
    required this.graceWindowEndsAt,
    required this.isWithinGraceWindow,
    required this.message,
  });

  factory BookingCancellationPreview.fromMap(Map<String, dynamic> data) {
    return BookingCancellationPreview(
      ok: data['ok'] == true,
      refundAmount: (data['refundAmount'] as num?)?.round() ?? 0,
      refundAmountPaise:
          (data['refundAmountPaise'] as num?)?.round() ??
          ((data['refundAmount'] as num?)?.round() ?? 0) * 100,
      providerAmount: (data['providerAmount'] as num?)?.round() ?? 0,
      providerAmountPaise:
          (data['providerAmountPaise'] as num?)?.round() ??
          ((data['providerAmount'] as num?)?.round() ?? 0) * 100,
      pettxoAmount: (data['pettxoAmount'] as num?)?.round() ?? 0,
      pettxoAmountPaise:
          (data['pettxoAmountPaise'] as num?)?.round() ??
          ((data['pettxoAmount'] as num?)?.round() ?? 0) * 100,
      totalAmountPaise:
          (data['totalAmountPaise'] as num?)?.round() ?? 0,
      refundPercent: (data['refundPercent'] as num?)?.round() ?? 0,
      providerPercent: (data['providerPercent'] as num?)?.round() ?? 0,
      pettxoPercent: (data['pettxoPercent'] as num?)?.round() ?? 0,
      cancellationCase: (data['cancellationCase'] as String? ?? '').trim(),
      graceWindowMinutes: (data['graceWindowMinutes'] as num?)?.round() ?? 0,
      graceWindowEndsAt: DateTime.tryParse(
        (data['graceWindowEndsAt'] as String? ?? '').trim(),
      ),
      isWithinGraceWindow: data['isWithinGraceWindow'] == true,
      message: (data['message'] as String? ?? '').trim(),
    );
  }
}
