import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../domain/models/booking_payment_order.dart';

class RazorpayCheckoutSuccess {
  final String paymentId;
  final String orderId;
  final String signature;

  const RazorpayCheckoutSuccess({
    required this.paymentId,
    required this.orderId,
    required this.signature,
  });
}

class RazorpayCheckoutFailure implements Exception {
  final String code;
  final String message;

  const RazorpayCheckoutFailure({required this.code, required this.message});
}

class RazorpayCheckoutDismissed implements Exception {
  const RazorpayCheckoutDismissed();
}

class RazorpayCheckoutService {
  RazorpayCheckoutService() : _razorpay = Razorpay();

  final Razorpay _razorpay;
  Completer<RazorpayCheckoutSuccess>? _checkoutCompleter;

  Future<RazorpayCheckoutSuccess> openCheckout({
    required BookingPaymentOrder order,
    required String customerName,
    required String customerEmail,
    required String customerPhone,
    required String description,
  }) {
    _checkoutCompleter?.completeError(const RazorpayCheckoutDismissed());
    final completer = Completer<RazorpayCheckoutSuccess>();
    _checkoutCompleter = completer;

    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (dynamic response) {
      final success = response as PaymentSuccessResponse;
      if (!completer.isCompleted) {
        completer.complete(
          RazorpayCheckoutSuccess(
            paymentId: success.paymentId?.trim() ?? '',
            orderId: success.orderId?.trim() ?? '',
            signature: success.signature?.trim() ?? '',
          ),
        );
      }
    });

    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (dynamic response) {
      final failure = response as PaymentFailureResponse;
      final message = (failure.message ?? '').trim();
      final code = '${failure.code}'.trim();
      if (!completer.isCompleted) {
        if (message.toLowerCase().contains('cancel')) {
          completer.completeError(const RazorpayCheckoutDismissed());
        } else {
          completer.completeError(
            RazorpayCheckoutFailure(
              code: code,
              message: message.isEmpty
                  ? 'Payment could not be completed.'
                  : message,
            ),
          );
        }
      }
    });

    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {
      if (!completer.isCompleted) {
        completer.completeError(const RazorpayCheckoutDismissed());
      }
    });

    _razorpay.open({
      'key': order.keyId,
      'amount': order.amountPaise,
      'name': 'Pettxo',
      'description': description,
      'order_id': order.razorpayOrderId,
      'currency': order.currency,
      'timeout': 900,
      'prefill': {
        'contact': customerPhone,
        'email': customerEmail,
        'name': customerName,
      },
      'notes': {'bookingId': order.bookingId},
    });

    return completer.future.whenComplete(() {
      _razorpay.clear();
      _checkoutCompleter = null;
    });
  }
}
