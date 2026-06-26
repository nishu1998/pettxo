class PendingPaymentBooking {
  final String bookingId;
  final String paymentStatus;
  final String razorpayOrderId;
  final DateTime? paymentExpiresAt;
  final String serviceId;
  final String slotId;
  final String providerId;
  final int amountPaise;
  final String currency;
  final int serviceAmountPaise;
  final int platformFeePaise;
  final int discountPaise;
  final int totalPayablePaise;
  final DateTime? scheduledStartAt;
  final DateTime? scheduledEndAt;

  const PendingPaymentBooking({
    required this.bookingId,
    required this.paymentStatus,
    required this.razorpayOrderId,
    required this.paymentExpiresAt,
    required this.serviceId,
    required this.slotId,
    required this.providerId,
    required this.amountPaise,
    required this.currency,
    required this.serviceAmountPaise,
    required this.platformFeePaise,
    required this.discountPaise,
    required this.totalPayablePaise,
    required this.scheduledStartAt,
    required this.scheduledEndAt,
  });

  static DateTime? _parseDate(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _string(Object? value) => value?.toString().trim() ?? '';

  factory PendingPaymentBooking.fromMap(Map<String, dynamic> data) {
    return PendingPaymentBooking(
      bookingId: _string(data['bookingId']),
      paymentStatus: _string(data['paymentStatus']),
      razorpayOrderId: _string(data['razorpayOrderId']),
      paymentExpiresAt: _parseDate(data['paymentExpiresAt']),
      serviceId: _string(data['serviceId']),
      slotId: _string(data['slotId']),
      providerId: _string(data['providerId']),
      amountPaise: _int(data['amountPaise']),
      currency: _string(data['currency']),
      serviceAmountPaise: _int(data['serviceAmountPaise']),
      platformFeePaise: _int(data['platformFeePaise']),
      discountPaise: _int(data['discountPaise']),
      totalPayablePaise: _int(data['totalPayablePaise']),
      scheduledStartAt: _parseDate(data['scheduledStartAt']),
      scheduledEndAt: _parseDate(data['scheduledEndAt']),
    );
  }
}
