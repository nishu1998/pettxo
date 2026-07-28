class BookingPaymentOrder {
  final String bookingId;
  final String paymentAttemptId;
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
    required this.paymentAttemptId,
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
      paymentAttemptId: asString(data['paymentAttemptId']),
      razorpayOrderId: asString(data['orderId']).isEmpty
          ? asString(data['razorpayOrderId'])
          : asString(data['orderId']),
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

enum CanonicalPaymentOrderMode { razorpay, zeroPayable }

enum CanonicalPaymentProcessingStatus {
  confirmed,
  processing,
  reconciliationRequired,
  refundRequired,
  paymentExpired,
  failed,
}

enum CanonicalPaymentAttemptState {
  notStarted,
  orderCreating,
  orderCreated,
  checkoutOpened,
  captureReported,
  confirming,
  confirmed,
  capturedRequiresReconciliation,
  failed,
  expired,
  refundRequired,
  refundPending,
  refunded,
  unknown,
}

class CanonicalPaymentPricingSummary {
  final int serviceSubtotalPaise;
  final int couponDiscountPaise;
  final int customerPaidPaise;
  final int providerPayoutPaise;
  final String currency;

  const CanonicalPaymentPricingSummary({
    required this.serviceSubtotalPaise,
    required this.couponDiscountPaise,
    required this.customerPaidPaise,
    required this.providerPayoutPaise,
    required this.currency,
  });

  factory CanonicalPaymentPricingSummary.fromMap(Map<String, dynamic> data) {
    return CanonicalPaymentPricingSummary(
      serviceSubtotalPaise: _CanonicalPaymentParsing.asInt(
        data['serviceSubtotalPaise'],
      ),
      couponDiscountPaise: _CanonicalPaymentParsing.asInt(
        data['couponDiscountPaise'],
      ),
      customerPaidPaise: _CanonicalPaymentParsing.asInt(
        data['customerPaidPaise'],
      ),
      providerPayoutPaise: _CanonicalPaymentParsing.asInt(
        data['providerPayoutPaise'],
      ),
      currency: _CanonicalPaymentParsing.asString(data['currency']).isEmpty
          ? 'INR'
          : _CanonicalPaymentParsing.asString(data['currency']),
    );
  }
}

class CanonicalPaymentOrderResult {
  final String bookingId;
  final String paymentAttemptId;
  final CanonicalPaymentOrderMode mode;
  final String keyId;
  final String razorpayOrderId;
  final int amountPaise;
  final String currency;
  final CanonicalPaymentPricingSummary pricingSummary;
  final DateTime? expiresAt;
  final String state;
  final DateTime? confirmedAt;
  final bool idempotentReplay;

  const CanonicalPaymentOrderResult({
    required this.bookingId,
    required this.paymentAttemptId,
    required this.mode,
    required this.keyId,
    required this.razorpayOrderId,
    required this.amountPaise,
    required this.currency,
    required this.pricingSummary,
    required this.expiresAt,
    required this.state,
    required this.confirmedAt,
    required this.idempotentReplay,
  });

  bool get requiresRazorpayCheckout =>
      mode == CanonicalPaymentOrderMode.razorpay && amountPaise > 0;

  bool get isZeroPayable => mode == CanonicalPaymentOrderMode.zeroPayable;

  BookingPaymentOrder toCheckoutOrder() {
    if (!requiresRazorpayCheckout) {
      throw StateError(
        'Canonical payment order does not require Razorpay checkout.',
      );
    }
    return BookingPaymentOrder(
      bookingId: bookingId,
      paymentAttemptId: paymentAttemptId,
      razorpayOrderId: razorpayOrderId,
      keyId: keyId,
      amountPaise: amountPaise,
      currency: currency,
      serviceAmountPaise: pricingSummary.serviceSubtotalPaise,
      platformFeePaise: 0,
      discountPaise: pricingSummary.couponDiscountPaise,
      totalPayablePaise: pricingSummary.customerPaidPaise,
      paymentExpiresAt: expiresAt,
      alreadyVerified: false,
    );
  }

  factory CanonicalPaymentOrderResult.fromMap(Map<String, dynamic> data) {
    final modeValue = _CanonicalPaymentParsing.asString(data['mode']);
    final mode = modeValue == 'zero_payable'
        ? CanonicalPaymentOrderMode.zeroPayable
        : CanonicalPaymentOrderMode.razorpay;
    final pricingMap = _CanonicalPaymentParsing.asMap(data['pricingSummary']);
    return CanonicalPaymentOrderResult(
      bookingId: _CanonicalPaymentParsing.asString(data['bookingId']),
      paymentAttemptId: _CanonicalPaymentParsing.asString(
        data['paymentAttemptId'],
      ),
      mode: mode,
      keyId: _CanonicalPaymentParsing.asString(data['keyId']),
      razorpayOrderId: _CanonicalPaymentParsing.asString(
        data['razorpayOrderId'],
      ),
      amountPaise: _CanonicalPaymentParsing.asInt(data['amountPaise']),
      currency: _CanonicalPaymentParsing.asString(data['currency']).isEmpty
          ? 'INR'
          : _CanonicalPaymentParsing.asString(data['currency']),
      pricingSummary: CanonicalPaymentPricingSummary.fromMap(pricingMap),
      expiresAt: _CanonicalPaymentParsing.readDate(data['expiresAt']),
      state: _CanonicalPaymentParsing.asString(data['state']),
      confirmedAt: _CanonicalPaymentParsing.readDate(data['confirmedAt']),
      idempotentReplay: data['idempotentReplay'] == true,
    );
  }
}

class CanonicalPaymentPricingPreviewResult {
  final String bookingId;
  final CanonicalPaymentPricingSummary pricingSummary;
  final DateTime? payDeadlineAt;
  final String claimedOfferId;
  final bool idempotentReplay;

  const CanonicalPaymentPricingPreviewResult({
    required this.bookingId,
    required this.pricingSummary,
    required this.payDeadlineAt,
    required this.claimedOfferId,
    required this.idempotentReplay,
  });

  factory CanonicalPaymentPricingPreviewResult.fromMap(
    Map<String, dynamic> data,
  ) {
    return CanonicalPaymentPricingPreviewResult(
      bookingId: _CanonicalPaymentParsing.asString(data['bookingId']),
      pricingSummary: CanonicalPaymentPricingSummary.fromMap(
        _CanonicalPaymentParsing.asMap(data['pricingSummary']),
      ),
      payDeadlineAt: _CanonicalPaymentParsing.readDate(data['payDeadlineAt']),
      claimedOfferId: _CanonicalPaymentParsing.asString(data['claimedOfferId']),
      idempotentReplay: data['idempotentReplay'] == true,
    );
  }
}

class CanonicalPaymentVerificationResult {
  final String bookingId;
  final String paymentAttemptId;
  final CanonicalPaymentProcessingStatus status;
  final String state;
  final DateTime? confirmedAt;
  final DateTime? payDeadlineAt;
  final bool idempotentReplay;

  const CanonicalPaymentVerificationResult({
    required this.bookingId,
    required this.paymentAttemptId,
    required this.status,
    required this.state,
    required this.confirmedAt,
    required this.payDeadlineAt,
    required this.idempotentReplay,
  });

  bool get needsAuthoritativeObservation =>
      status == CanonicalPaymentProcessingStatus.confirmed ||
      status == CanonicalPaymentProcessingStatus.processing ||
      status == CanonicalPaymentProcessingStatus.reconciliationRequired;

  factory CanonicalPaymentVerificationResult.fromMap(
    Map<String, dynamic> data,
  ) {
    final statusValue = _CanonicalPaymentParsing.asString(data['status']);
    return CanonicalPaymentVerificationResult(
      bookingId: _CanonicalPaymentParsing.asString(data['bookingId']),
      paymentAttemptId: _CanonicalPaymentParsing.asString(
        data['paymentAttemptId'],
      ),
      status: _CanonicalPaymentParsing.processingStatusFromString(statusValue),
      state: _CanonicalPaymentParsing.asString(data['state']),
      confirmedAt: _CanonicalPaymentParsing.readDate(data['confirmedAt']),
      payDeadlineAt: _CanonicalPaymentParsing.readDate(data['payDeadlineAt']),
      idempotentReplay: data['idempotentReplay'] == true,
    );
  }
}

class CanonicalPaymentAttemptReadModel {
  final String bookingId;
  final String paymentAttemptId;
  final CanonicalPaymentAttemptState state;
  final int amountPaise;
  final String currency;
  final String razorpayOrderId;
  final String razorpayPaymentId;
  final String failureCode;
  final String failureMessage;
  final int retryCount;
  final DateTime? orderExpiresAt;
  final DateTime? orderCreatedAt;
  final DateTime? checkoutOpenedAt;
  final DateTime? captureReportedAt;
  final DateTime? confirmedAt;
  final DateTime? failedAt;
  final DateTime? refundRequiredAt;
  final DateTime? refundedAt;
  final DateTime? lastReconciledAt;
  final CanonicalPaymentPricingSummary pricingSummary;

  const CanonicalPaymentAttemptReadModel({
    required this.bookingId,
    required this.paymentAttemptId,
    required this.state,
    required this.amountPaise,
    required this.currency,
    required this.razorpayOrderId,
    required this.razorpayPaymentId,
    required this.failureCode,
    required this.failureMessage,
    required this.retryCount,
    required this.orderExpiresAt,
    required this.orderCreatedAt,
    required this.checkoutOpenedAt,
    required this.captureReportedAt,
    required this.confirmedAt,
    required this.failedAt,
    required this.refundRequiredAt,
    required this.refundedAt,
    required this.lastReconciledAt,
    required this.pricingSummary,
  });

  bool get isTerminal =>
      state == CanonicalPaymentAttemptState.confirmed ||
      state == CanonicalPaymentAttemptState.expired ||
      state == CanonicalPaymentAttemptState.failed ||
      state == CanonicalPaymentAttemptState.refunded;

  bool get canRetryWithSameAttempt =>
      state == CanonicalPaymentAttemptState.orderCreated ||
      state == CanonicalPaymentAttemptState.checkoutOpened ||
      state == CanonicalPaymentAttemptState.captureReported ||
      state == CanonicalPaymentAttemptState.confirming ||
      state == CanonicalPaymentAttemptState.capturedRequiresReconciliation ||
      state == CanonicalPaymentAttemptState.refundRequired ||
      state == CanonicalPaymentAttemptState.refundPending;

  factory CanonicalPaymentAttemptReadModel.fromMap(Map<String, dynamic> data) {
    final pricingSnapshot = _CanonicalPaymentParsing.asMap(
      data['pricingSnapshot'],
    );
    final financials = _CanonicalPaymentParsing.asMap(
      pricingSnapshot['financials'],
    );
    return CanonicalPaymentAttemptReadModel(
      bookingId: _CanonicalPaymentParsing.asString(data['bookingId']),
      paymentAttemptId: _CanonicalPaymentParsing.asString(
        data['paymentAttemptId'],
      ),
      state: _CanonicalPaymentParsing.attemptStateFromString(
        _CanonicalPaymentParsing.asString(data['state']),
      ),
      amountPaise: _CanonicalPaymentParsing.asInt(data['amountPaise']),
      currency: _CanonicalPaymentParsing.asString(data['currency']).isEmpty
          ? 'INR'
          : _CanonicalPaymentParsing.asString(data['currency']),
      razorpayOrderId: _CanonicalPaymentParsing.asString(
        data['razorpayOrderId'],
      ),
      razorpayPaymentId: _CanonicalPaymentParsing.asString(
        data['razorpayPaymentId'],
      ),
      failureCode: _CanonicalPaymentParsing.asString(data['failureCode']),
      failureMessage: _CanonicalPaymentParsing.asString(data['failureMessage']),
      retryCount: _CanonicalPaymentParsing.asInt(data['retryCount']),
      orderExpiresAt: _CanonicalPaymentParsing.readDate(data['orderExpiresAt']),
      orderCreatedAt: _CanonicalPaymentParsing.readDate(data['orderCreatedAt']),
      checkoutOpenedAt: _CanonicalPaymentParsing.readDate(
        data['checkoutOpenedAt'],
      ),
      captureReportedAt: _CanonicalPaymentParsing.readDate(
        data['captureReportedAt'],
      ),
      confirmedAt: _CanonicalPaymentParsing.readDate(data['confirmedAt']),
      failedAt: _CanonicalPaymentParsing.readDate(data['failedAt']),
      refundRequiredAt: _CanonicalPaymentParsing.readDate(
        data['refundRequiredAt'],
      ),
      refundedAt: _CanonicalPaymentParsing.readDate(data['refundedAt']),
      lastReconciledAt: _CanonicalPaymentParsing.readDate(
        data['lastReconciledAt'],
      ),
      pricingSummary: CanonicalPaymentPricingSummary(
        serviceSubtotalPaise: _CanonicalPaymentParsing.asInt(
          pricingSnapshot['serviceSubtotalPaise'],
        ),
        couponDiscountPaise: _CanonicalPaymentParsing.asInt(
          pricingSnapshot['couponDiscountPaise'],
        ),
        customerPaidPaise: _CanonicalPaymentParsing.asInt(data['amountPaise']),
        providerPayoutPaise: _CanonicalPaymentParsing.asInt(
          financials['providerPayoutPaise'],
        ),
        currency:
            _CanonicalPaymentParsing.asString(financials['currency']).isEmpty
            ? 'INR'
            : _CanonicalPaymentParsing.asString(financials['currency']),
      ),
    );
  }
}

enum CanonicalPaymentFailureCode {
  unauthenticated,
  bookingNotFound,
  invalidCanonicalBooking,
  actorNotAuthorized,
  paymentDisabled,
  bookingNotPayable,
  paymentWindowExpired,
  paymentAttemptConflict,
  serviceUnavailable,
  capacityUnavailable,
  couponInvalid,
  pricingChanged,
  paymentAlreadyConfirmed,
  paymentReconciliationRequired,
  unknown,
}

class CanonicalPaymentException implements Exception {
  final CanonicalPaymentFailureCode code;
  final String message;

  const CanonicalPaymentException({required this.code, required this.message});

  @override
  String toString() => 'CanonicalPaymentException($code, $message)';
}

class _CanonicalPaymentParsing {
  static int asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String asString(Object? value) => value?.toString().trim() ?? '';

  static DateTime? readDate(Object? value) {
    if (value is DateTime) return value.toLocal();
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }

  static Map<String, dynamic> asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  static CanonicalPaymentProcessingStatus processingStatusFromString(
    String raw,
  ) {
    switch (raw.trim().toUpperCase()) {
      case 'CONFIRMED':
        return CanonicalPaymentProcessingStatus.confirmed;
      case 'PROCESSING':
        return CanonicalPaymentProcessingStatus.processing;
      case 'RECONCILIATION_REQUIRED':
        return CanonicalPaymentProcessingStatus.reconciliationRequired;
      case 'REFUND_REQUIRED':
        return CanonicalPaymentProcessingStatus.refundRequired;
      case 'PAYMENT_EXPIRED':
        return CanonicalPaymentProcessingStatus.paymentExpired;
      default:
        return CanonicalPaymentProcessingStatus.failed;
    }
  }

  static CanonicalPaymentAttemptState attemptStateFromString(String raw) {
    switch (raw.trim().toUpperCase()) {
      case 'NOT_STARTED':
        return CanonicalPaymentAttemptState.notStarted;
      case 'ORDER_CREATING':
        return CanonicalPaymentAttemptState.orderCreating;
      case 'ORDER_CREATED':
        return CanonicalPaymentAttemptState.orderCreated;
      case 'CHECKOUT_OPENED':
        return CanonicalPaymentAttemptState.checkoutOpened;
      case 'CAPTURE_REPORTED':
        return CanonicalPaymentAttemptState.captureReported;
      case 'CONFIRMING':
        return CanonicalPaymentAttemptState.confirming;
      case 'CONFIRMED':
        return CanonicalPaymentAttemptState.confirmed;
      case 'CAPTURED_REQUIRES_RECONCILIATION':
        return CanonicalPaymentAttemptState.capturedRequiresReconciliation;
      case 'FAILED':
        return CanonicalPaymentAttemptState.failed;
      case 'EXPIRED':
        return CanonicalPaymentAttemptState.expired;
      case 'REFUND_REQUIRED':
        return CanonicalPaymentAttemptState.refundRequired;
      case 'REFUND_PENDING':
        return CanonicalPaymentAttemptState.refundPending;
      case 'REFUNDED':
        return CanonicalPaymentAttemptState.refunded;
      default:
        return CanonicalPaymentAttemptState.unknown;
    }
  }
}
