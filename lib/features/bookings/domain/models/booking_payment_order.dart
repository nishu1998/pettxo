class BookingPaymentOrder {
  final String bookingId;
  final String razorpayOrderId;
  final String keyId;
  final int amountPaise;
  final String currency;
  final int serviceAmountPaise;
  final int platformFeePaise;
  final int discountPaise;
  final int totalPayablePaise;
  final DateTime? paymentExpiresAt;
  final bool alreadyVerified;

  const BookingPaymentOrder({
    required this.bookingId,
    required this.razorpayOrderId,
    required this.keyId,
    required this.amountPaise,
    required this.currency,
    required this.serviceAmountPaise,
    required this.platformFeePaise,
    required this.discountPaise,
    required this.totalPayablePaise,
    required this.paymentExpiresAt,
    this.alreadyVerified = false,
  });

  factory BookingPaymentOrder.fromMap(Map<String, dynamic> data) {
    DateTime? expiresAt;
    final rawExpiresAt = data['paymentExpiresAt'];
    if (rawExpiresAt is String && rawExpiresAt.trim().isNotEmpty) {
      expiresAt = DateTime.tryParse(rawExpiresAt)?.toLocal();
    }

    int asInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.round();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    String asString(Object? value) => value?.toString().trim() ?? '';

    return BookingPaymentOrder(
      bookingId: asString(data['bookingId']),
      razorpayOrderId: asString(data['orderId']),
      keyId: asString(data['keyId']),
      amountPaise: asInt(data['amount']),
      currency: asString(data['currency']).isEmpty
          ? 'INR'
          : asString(data['currency']),
      serviceAmountPaise: asInt(data['serviceAmountPaise']),
      platformFeePaise: asInt(data['platformFeePaise']),
      discountPaise: asInt(data['discountPaise']),
      totalPayablePaise: asInt(data['totalPayablePaise']),
      paymentExpiresAt: expiresAt,
      alreadyVerified: data['alreadyVerified'] == true,
    );
  }
}
