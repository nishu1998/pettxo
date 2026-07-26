import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/app_loader.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../offers/data/services/offer_service.dart';
import '../../../offers/domain/models/claimed_offer.dart';
import '../../data/repositories/booking_repository.dart';
import '../../data/services/razorpay_checkout_service.dart';
import '../../domain/models/booking_document_v3.dart';
import '../../domain/models/booking_payment_order.dart';
import '../../domain/models/booking_read_model.dart';
import '../../domain/models/booking_v3_models.dart';
import 'booking_confirmation_screen.dart';

class CanonicalBookingPaymentScreen extends StatefulWidget {
  final String bookingId;
  final String serviceName;
  final String providerName;
  final String serviceImageUrl;

  const CanonicalBookingPaymentScreen({
    super.key,
    required this.bookingId,
    required this.serviceName,
    required this.providerName,
    required this.serviceImageUrl,
  });

  @override
  State<CanonicalBookingPaymentScreen> createState() =>
      _CanonicalBookingPaymentScreenState();
}

class _CanonicalBookingPaymentScreenState
    extends State<CanonicalBookingPaymentScreen> {
  final BookingRepository _bookingRepository = BookingRepository();
  final RazorpayCheckoutService _razorpayCheckoutService =
      RazorpayCheckoutService();
  final OfferService _offerService = OfferService();

  StreamSubscription<BookingReadModel?>? _confirmationSubscription;
  StreamSubscription<CanonicalPaymentAttemptReadModel?>? _attemptSubscription;
  Timer? _ticker;

  String _paymentAttemptId = '';
  CanonicalPaymentAttemptReadModel? _latestAttempt;
  bool _isPreparingOrder = false;
  bool _isCheckoutOpen = false;
  bool _isObservingConfirmation = false;
  bool _hasNavigatedToConfirmation = false;
  bool _isRefreshingOfferPreview = false;
  String _selectedClaimedOfferId = '';
  OfferPreviewResult? _selectedOfferPreview;
  String _selectedOfferMessage = '';

  @override
  void initState() {
    super.initState();
    _bindConfirmationStream();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _attemptSubscription?.cancel();
    _confirmationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Complete payment',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: StreamBuilder<BookingReadModel?>(
        stream: _bookingRepository.watchCanonicalBooking(widget.bookingId),
        builder: (context, snapshot) {
          final booking = _canonicalBookingFromReadModel(snapshot.data);
          return StreamBuilder<List<ClaimedOffer>>(
            stream: _offerService.watchClaimedOffers(),
            builder: (context, offerSnapshot) {
              final claimedOffers =
                  offerSnapshot.data ?? const <ClaimedOffer>[];
              ClaimedOffer? selectedOffer;
              for (final offer in claimedOffers) {
                if (offer.id == _selectedClaimedOfferId) {
                  selectedOffer = offer;
                  break;
                }
              }
              if (_selectedClaimedOfferId.isNotEmpty && selectedOffer == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _clearSelectedOffer(showFeedback: false);
                });
              }
              if (booking != null &&
                  booking.payment.paymentAttemptId.trim().isNotEmpty &&
                  booking.payment.paymentAttemptId.trim() !=
                      _paymentAttemptId) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _bindAttemptStream(booking.payment.paymentAttemptId.trim());
                });
              }

              final pricingSummary = _resolvePricingSummary(booking);
              final payDeadline =
                  booking?.lifecycle.payDeadlineAt ??
                  _latestAttempt?.orderExpiresAt;
              final isExpired =
                  payDeadline != null && !payDeadline.isAfter(DateTime.now());
              final canPay =
                  booking != null &&
                  booking.state ==
                      CanonicalBookingStateV3.acceptedAwaitingPayment &&
                  !isExpired &&
                  !_isPreparingOrder &&
                  !_isCheckoutOpen &&
                  !_isObservingConfirmation &&
                  (_latestAttempt == null ||
                      _latestAttempt!.canRetryWithSameAttempt ||
                      _latestAttempt!.state ==
                          CanonicalPaymentAttemptState.notStarted ||
                      _latestAttempt!.state ==
                          CanonicalPaymentAttemptState.unknown);
              final payableBooking = canPay ? booking : null;

              return SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                  children: [
                    _PaymentHeroCard(
                      serviceName: widget.serviceName,
                      providerName: widget.providerName,
                      serviceImageUrl: widget.serviceImageUrl,
                      headline: _headlineForState(booking, isExpired),
                      subheadline: _subheadlineForState(booking, isExpired),
                    ),
                    const SizedBox(height: 16),
                    _DetailCard(
                      title: 'Payment window',
                      body: payDeadline == null
                          ? 'Waiting for the server to sync the payment window.'
                          : _remainingLabel(payDeadline),
                    ),
                    const SizedBox(height: 12),
                    _DetailCard(
                      title: 'Availability',
                      body:
                          'Availability is confirmed only after payment succeeds.',
                    ),
                    const SizedBox(height: 12),
                    _DetailCard(
                      title: 'Status',
                      body: _paymentStatusText(
                        booking,
                        _latestAttempt,
                        isExpired,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _PricingCard(pricingSummary: pricingSummary),
                    const SizedBox(height: 12),
                    _CouponCard(
                      selectedOffer: selectedOffer,
                      selectionMessage: _selectedOfferMessage,
                      isRefreshing: _isRefreshingOfferPreview,
                      offersAvailable: claimedOffers.isNotEmpty,
                      onChoose: booking == null
                          ? null
                          : () => _showCouponSheet(booking, claimedOffers),
                      onRemove: _selectedClaimedOfferId.isEmpty
                          ? null
                          : () => _clearSelectedOffer(),
                      onRefresh: booking == null || selectedOffer == null
                          ? null
                          : () => _previewClaimedOffer(
                              booking,
                              selectedOffer!,
                              selectOffer: true,
                            ),
                    ),
                    if (_latestAttempt != null) ...[
                      const SizedBox(height: 12),
                      _DetailCard(
                        title: 'Latest payment attempt',
                        body: _attemptStatusDescription(_latestAttempt!),
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (payableBooking != null)
                      GradientButton(
                        label: _primaryButtonLabel(_latestAttempt),
                        onPressed: () => _startPaymentFlow(payableBooking),
                      )
                    else
                      SecondaryButton(
                        label: _secondaryButtonLabel(booking, isExpired),
                        onPressed: null,
                      ),
                    const SizedBox(height: 10),
                    SecondaryButton(
                      label: 'Close',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  CanonicalBookingDocumentV3? _canonicalBookingFromReadModel(
    BookingReadModel? readModel,
  ) {
    if (readModel is CanonicalBookingReadModel) {
      return readModel.booking;
    }
    return null;
  }

  CanonicalPaymentPricingSummary? _resolvePricingSummary(
    CanonicalBookingDocumentV3? booking,
  ) {
    if (_selectedOfferPreview != null && booking != null) {
      final serviceSubtotalPaise = _serviceSubtotalPaise(booking);
      final customerPaidPaise = (_selectedOfferPreview!.finalAmount * 100)
          .round();
      final couponDiscountPaise = (_selectedOfferPreview!.discountAmount * 100)
          .round();
      return CanonicalPaymentPricingSummary(
        serviceSubtotalPaise: serviceSubtotalPaise,
        couponDiscountPaise: couponDiscountPaise,
        customerPaidPaise: customerPaidPaise.clamp(0, serviceSubtotalPaise),
        providerPayoutPaise:
            booking.financials?.providerPayoutPaise ??
            _latestAttempt?.pricingSummary.providerPayoutPaise ??
            0,
        currency:
            booking.financials?.currency ??
            _latestAttempt?.pricingSummary.currency ??
            'INR',
      );
    }
    final financials = booking?.financials;
    if (_latestAttempt != null) return _latestAttempt!.pricingSummary;
    if (financials == null) {
      return null;
    }
    return CanonicalPaymentPricingSummary(
      serviceSubtotalPaise: financials.serviceSubtotalPaise,
      couponDiscountPaise: financials.couponDiscountPaise,
      customerPaidPaise: financials.customerPaidPaise,
      providerPayoutPaise: financials.providerPayoutPaise,
      currency: financials.currency,
    );
  }

  Future<void> _startPaymentFlow(CanonicalBookingDocumentV3 booking) async {
    if (_isPreparingOrder || _isCheckoutOpen || _isObservingConfirmation) {
      return;
    }
    if (booking.lifecycle.payDeadlineAt != null &&
        !booking.lifecycle.payDeadlineAt!.isAfter(DateTime.now())) {
      AppFeedback.show(
        context,
        message: 'The payment window has expired.',
        tone: AppFeedbackTone.warning,
      );
      return;
    }

    var checkoutSucceeded = false;
    setState(() => _isPreparingOrder = true);
    AppLoader.showWithMessage('Preparing secure payment...');

    try {
      final orderResult = await _bookingRepository.createPaymentOrderV3(
        bookingId: widget.bookingId,
        paymentAttemptId: _paymentAttemptId.isEmpty ? null : _paymentAttemptId,
        claimedOfferId: _selectedClaimedOfferId.isEmpty
            ? null
            : _selectedClaimedOfferId,
      );
      _bindAttemptStream(orderResult.paymentAttemptId);

      if (orderResult.isZeroPayable) {
        AppLoader.hide();
        if (!mounted) return;
        setState(() => _isObservingConfirmation = true);
        AppFeedback.show(
          context,
          message: 'No payment is required. Confirming your booking now...',
          tone: AppFeedbackTone.info,
        );
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      AppLoader.hide();
      if (!mounted) return;

      setState(() => _isCheckoutOpen = true);
      final checkoutResult = await _razorpayCheckoutService.openCheckout(
        order: orderResult.toCheckoutOrder(),
        customerName: user?.displayName?.trim().isNotEmpty == true
            ? user!.displayName!.trim()
            : 'Pettxo Customer',
        customerEmail: user?.email?.trim() ?? '',
        customerPhone: user?.phoneNumber?.trim() ?? '',
        description: widget.serviceName,
      );
      checkoutSucceeded = true;

      if (!mounted) return;

      AppLoader.showWithMessage('Verifying payment...');
      final verification = await _bookingRepository.verifyPaymentV3(
        bookingId: orderResult.bookingId,
        paymentAttemptId: orderResult.paymentAttemptId,
        razorpayOrderId: checkoutResult.orderId,
        razorpayPaymentId: checkoutResult.paymentId,
        razorpaySignature: checkoutResult.signature,
      );

      AppLoader.hide();
      if (!mounted) return;

      if (verification.needsAuthoritativeObservation) {
        setState(() => _isObservingConfirmation = true);
        final message = switch (verification.status) {
          CanonicalPaymentProcessingStatus.confirmed =>
            'Payment received. Final confirmation is syncing now.',
          CanonicalPaymentProcessingStatus.reconciliationRequired =>
            'Payment was captured and is being reconciled securely.',
          CanonicalPaymentProcessingStatus.processing =>
            'Payment is processing. We will confirm the booking shortly.',
          _ => 'Payment is being processed.',
        };
        AppFeedback.show(context, message: message, tone: AppFeedbackTone.info);
        return;
      }

      _showVerificationOutcome(verification);
    } on RazorpayCheckoutDismissed {
      AppLoader.hide();
      if (!mounted) return;
      AppFeedback.show(
        context,
        message:
            'Checkout was closed. You can retry while the payment window remains open.',
        tone: AppFeedbackTone.info,
      );
    } on RazorpayCheckoutFailure catch (error) {
      AppLoader.hide();
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: error.message.isEmpty
            ? 'Payment could not be completed right now.'
            : error.message,
        tone: AppFeedbackTone.error,
      );
    } on CanonicalPaymentException catch (error) {
      AppLoader.hide();
      if (!mounted) return;
      if (checkoutSucceeded && _shouldObserveAfterVerificationError(error)) {
        _beginAuthoritativeObservation(
          message: _observationMessageForVerificationError(error),
        );
        return;
      }
      AppFeedback.show(
        context,
        message: error.message,
        tone: AppFeedbackTone.error,
      );
    } catch (_) {
      AppLoader.hide();
      if (!mounted) return;
      if (checkoutSucceeded) {
        _beginAuthoritativeObservation(
          message:
              'Payment callback succeeded. We are syncing the final booking state securely.',
        );
        return;
      }
      AppFeedback.show(
        context,
        message: 'We could not continue this payment right now.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      AppLoader.hide();
      if (mounted) {
        setState(() {
          _isPreparingOrder = false;
          _isCheckoutOpen = false;
        });
      }
    }
  }

  void _showVerificationOutcome(CanonicalPaymentVerificationResult result) {
    final message = switch (result.status) {
      CanonicalPaymentProcessingStatus.refundRequired =>
        'Payment was captured but the booking could not be confirmed. A refund will be processed safely.',
      CanonicalPaymentProcessingStatus.paymentExpired =>
        'The payment window expired before confirmation completed.',
      CanonicalPaymentProcessingStatus.failed =>
        'Payment could not be confirmed. Please try again.',
      _ => 'Payment is being processed.',
    };
    AppFeedback.show(
      context,
      message: message,
      tone: result.status == CanonicalPaymentProcessingStatus.paymentExpired
          ? AppFeedbackTone.warning
          : AppFeedbackTone.error,
    );
  }

  void _beginAuthoritativeObservation({
    required String message,
    AppFeedbackTone tone = AppFeedbackTone.info,
  }) {
    setState(() => _isObservingConfirmation = true);
    AppFeedback.show(context, message: message, tone: tone);
  }

  void _bindConfirmationStream() {
    _confirmationSubscription?.cancel();
    _confirmationSubscription = _bookingRepository
        .watchCanonicalBookingConfirmation(widget.bookingId)
        .listen((booking) {
          if (!mounted || booking == null || _hasNavigatedToConfirmation) {
            return;
          }
          _hasNavigatedToConfirmation = true;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) =>
                  BookingConfirmationScreen(bookingId: widget.bookingId),
            ),
          );
        });
  }

  void _bindAttemptStream(String paymentAttemptId) {
    final safeAttemptId = paymentAttemptId.trim();
    if (safeAttemptId.isEmpty || safeAttemptId == _paymentAttemptId) return;
    _paymentAttemptId = safeAttemptId;
    _attemptSubscription?.cancel();
    _attemptSubscription = _bookingRepository
        .watchPaymentAttempt(
          bookingId: widget.bookingId,
          paymentAttemptId: safeAttemptId,
        )
        .listen((attempt) {
          if (!mounted) return;
          setState(() {
            _latestAttempt = attempt;
            if (attempt?.state == CanonicalPaymentAttemptState.refundRequired ||
                attempt?.state == CanonicalPaymentAttemptState.refundPending ||
                attempt?.state == CanonicalPaymentAttemptState.expired ||
                attempt?.state == CanonicalPaymentAttemptState.failed) {
              _isObservingConfirmation = false;
            }
          });
        });
  }

  String _headlineForState(
    CanonicalBookingDocumentV3? booking,
    bool isExpired,
  ) {
    if (booking == null) return 'Loading booking payment details...';
    if (booking.lifecycle.paidAt != null ||
        booking.state == CanonicalBookingStateV3.confirmed) {
      return 'Payment received';
    }
    if (isExpired || booking.state == CanonicalBookingStateV3.paymentExpired) {
      return 'Payment window expired';
    }
    return 'Provider accepted your request';
  }

  String _subheadlineForState(
    CanonicalBookingDocumentV3? booking,
    bool isExpired,
  ) {
    if (booking == null) {
      return 'We are syncing the latest canonical booking state.';
    }
    if (booking.lifecycle.paidAt != null ||
        booking.state == CanonicalBookingStateV3.confirmed) {
      return 'We are validating the final Firestore confirmation before moving you forward.';
    }
    if (isExpired || booking.state == CanonicalBookingStateV3.paymentExpired) {
      return 'No availability was confirmed because payment did not complete in time.';
    }
    return 'Pay within the active window to confirm availability and unlock the booking.';
  }

  String _paymentStatusText(
    CanonicalBookingDocumentV3? booking,
    CanonicalPaymentAttemptReadModel? attempt,
    bool isExpired,
  ) {
    if (attempt != null) return _attemptStatusDescription(attempt);
    if (booking == null) return 'Waiting for booking details.';
    if (booking.lifecycle.paidAt != null) {
      return 'Payment captured and waiting for authoritative confirmation.';
    }
    if (isExpired) return 'Payment window expired.';
    return 'Ready for payment.';
  }

  String _attemptStatusDescription(CanonicalPaymentAttemptReadModel attempt) {
    switch (attempt.state) {
      case CanonicalPaymentAttemptState.orderCreated:
      case CanonicalPaymentAttemptState.checkoutOpened:
        return 'Checkout is ready. You can safely resume this payment attempt.';
      case CanonicalPaymentAttemptState.captureReported:
      case CanonicalPaymentAttemptState.confirming:
        return 'Payment capture has been reported. Confirmation is still running.';
      case CanonicalPaymentAttemptState.capturedRequiresReconciliation:
        return 'Payment was captured and is awaiting backend reconciliation.';
      case CanonicalPaymentAttemptState.refundRequired:
        return 'Payment was captured but the booking could not be confirmed. Refund processing is required.';
      case CanonicalPaymentAttemptState.refundPending:
        return 'Refund processing has started for this payment.';
      case CanonicalPaymentAttemptState.expired:
        return 'This payment attempt expired before confirmation.';
      case CanonicalPaymentAttemptState.failed:
        return attempt.failureMessage.isNotEmpty
            ? attempt.failureMessage
            : 'This payment attempt failed.';
      case CanonicalPaymentAttemptState.confirmed:
        return 'Payment is confirmed.';
      default:
        return 'Payment attempt status: ${attempt.state.name}.';
    }
  }

  String _primaryButtonLabel(CanonicalPaymentAttemptReadModel? attempt) {
    if (_isPreparingOrder) return 'Preparing secure payment...';
    if (_isCheckoutOpen) return 'Opening checkout...';
    if (_isObservingConfirmation) return 'Awaiting confirmation...';
    if (attempt != null && attempt.canRetryWithSameAttempt) {
      return 'Resume payment';
    }
    return 'Pay now';
  }

  String _secondaryButtonLabel(
    CanonicalBookingDocumentV3? booking,
    bool isExpired,
  ) {
    if (_isObservingConfirmation) return 'Awaiting confirmation...';
    if (isExpired || booking?.state == CanonicalBookingStateV3.paymentExpired) {
      return 'Payment window expired';
    }
    if (booking == null) return 'Loading payment details...';
    return 'Payment unavailable';
  }

  String _remainingLabel(DateTime deadline) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative) return 'Payment window ended';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    final seconds = remaining.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')} remaining';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')} remaining';
  }

  int _serviceSubtotalPaise(CanonicalBookingDocumentV3 booking) {
    final financials = booking.financials;
    if (financials != null && financials.serviceSubtotalPaise > 0) {
      return financials.serviceSubtotalPaise;
    }
    if (booking.schedule is CanonicalSlotBookingScheduleV3) {
      final schedule = booking.schedule as CanonicalSlotBookingScheduleV3;
      return schedule.slots.fold<int>(
        0,
        (sum, slot) => sum + slot.unitPricePaise,
      );
    }
    final schedule = booking.schedule as CanonicalRangeBookingScheduleV3;
    return (booking.service.pricePerNightPaise ?? 0) * schedule.nights;
  }

  Future<void> _showCouponSheet(
    CanonicalBookingDocumentV3 booking,
    List<ClaimedOffer> offers,
  ) async {
    if (offers.isEmpty) {
      AppFeedback.show(
        context,
        message: 'No claimed coupons are available for this booking yet.',
      );
      return;
    }
    final serviceSubtotalPaise = _serviceSubtotalPaise(booking);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose coupon',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pettxo-funded discounts update your payable amount from the backend before checkout starts.',
                  style: TextStyle(
                    color: AppColors.textGrey,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: offers.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final offer = offers[index];
                      final issue = _localOfferIssue(
                        offer,
                        booking,
                        serviceSubtotalPaise,
                      );
                      final isSelected = offer.id == _selectedClaimedOfferId;
                      return _CouponOptionTile(
                        offer: offer,
                        issue: issue,
                        isSelected: isSelected,
                        onTap: () async {
                          if (issue != null) {
                            AppFeedback.show(
                              context,
                              message: issue,
                              tone: AppFeedbackTone.warning,
                            );
                            return;
                          }
                          Navigator.pop(context);
                          await _previewClaimedOffer(
                            booking,
                            offer,
                            selectOffer: true,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _previewClaimedOffer(
    CanonicalBookingDocumentV3 booking,
    ClaimedOffer offer, {
    required bool selectOffer,
  }) async {
    final issue = _localOfferIssue(
      offer,
      booking,
      _serviceSubtotalPaise(booking),
    );
    if (issue != null) {
      AppFeedback.show(context, message: issue, tone: AppFeedbackTone.warning);
      return;
    }
    setState(() => _isRefreshingOfferPreview = true);
    try {
      final preview = await _offerService.previewOfferForBooking(
        claimedOfferId: offer.id,
        bookingAmount: _serviceSubtotalPaise(booking) / 100,
        serviceId: booking.serviceId,
        category: booking.service.category,
      );
      if (!mounted) return;
      if (!preview.ok || !preview.isValid) {
        AppFeedback.show(
          context,
          message: preview.message.isEmpty
              ? 'This coupon can no longer be applied.'
              : preview.message,
          tone: AppFeedbackTone.warning,
        );
        return;
      }
      setState(() {
        if (selectOffer) {
          _selectedClaimedOfferId = offer.id;
          _selectedOfferPreview = preview;
          _selectedOfferMessage = preview.message.isEmpty
              ? '${offer.couponCode} applied.'
              : preview.message;
          _paymentAttemptId = '';
          _latestAttempt = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'We could not refresh this coupon right now.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isRefreshingOfferPreview = false);
      }
    }
  }

  void _clearSelectedOffer({bool showFeedback = true}) {
    setState(() {
      _selectedClaimedOfferId = '';
      _selectedOfferPreview = null;
      _selectedOfferMessage = '';
      _paymentAttemptId = '';
      _latestAttempt = null;
    });
    if (showFeedback) {
      AppFeedback.show(
        context,
        message:
            'Coupon removed. Authoritative pricing will refresh on the next payment start.',
      );
    }
  }

  String? _localOfferIssue(
    ClaimedOffer offer,
    CanonicalBookingDocumentV3 booking,
    int serviceSubtotalPaise,
  ) {
    if (offer.isExpired) {
      return 'This coupon has expired.';
    }
    if (offer.isUsed) {
      return 'This coupon has already been used.';
    }
    final minBookingAmountPaise = ((offer.minBookingAmount ?? 0) * 100).round();
    if (minBookingAmountPaise > 0 &&
        serviceSubtotalPaise < minBookingAmountPaise) {
      return 'This coupon requires a higher booking amount.';
    }
    final campaign = offer.campaignSnapshot;
    final serviceIds = (campaign['serviceIds'] as List<dynamic>? ?? const [])
        .map((entry) => '$entry'.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet();
    if (serviceIds.isNotEmpty && !serviceIds.contains(booking.serviceId)) {
      return 'This coupon does not apply to this service.';
    }
    final providerIds = (campaign['providerIds'] as List<dynamic>? ?? const [])
        .map((entry) => '$entry'.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet();
    if (providerIds.isNotEmpty && !providerIds.contains(booking.providerId)) {
      return 'This coupon does not apply to this provider.';
    }
    final categoryRestrictions =
        (campaign['categoryRestrictions'] as List<dynamic>? ?? const [])
            .map((entry) => '$entry'.trim())
            .where((entry) => entry.isNotEmpty)
            .toSet();
    if (categoryRestrictions.isNotEmpty &&
        !categoryRestrictions.contains(booking.service.category)) {
      return 'This coupon does not apply to this category.';
    }
    return null;
  }

  bool _shouldObserveAfterVerificationError(CanonicalPaymentException error) {
    return error.code == CanonicalPaymentFailureCode.unknown ||
        error.code == CanonicalPaymentFailureCode.paymentAlreadyConfirmed ||
        error.code == CanonicalPaymentFailureCode.paymentReconciliationRequired;
  }

  String _observationMessageForVerificationError(
    CanonicalPaymentException error,
  ) {
    switch (error.code) {
      case CanonicalPaymentFailureCode.paymentAlreadyConfirmed:
        return 'This payment was already verified. We are syncing the booking now.';
      case CanonicalPaymentFailureCode.paymentReconciliationRequired:
        return 'Payment was captured and is being reconciled securely.';
      default:
        return 'Payment succeeded at checkout. We are waiting for authoritative booking confirmation.';
    }
  }
}

class _CouponCard extends StatelessWidget {
  const _CouponCard({
    required this.selectedOffer,
    required this.selectionMessage,
    required this.isRefreshing,
    required this.offersAvailable,
    required this.onChoose,
    required this.onRemove,
    required this.onRefresh,
  });

  final ClaimedOffer? selectedOffer;
  final String selectionMessage;
  final bool isRefreshing;
  final bool offersAvailable;
  final VoidCallback? onChoose;
  final VoidCallback? onRemove;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Coupons',
            style: TextStyle(
              color: AppColors.textDark,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            selectedOffer == null
                ? offersAvailable
                      ? 'Apply a claimed coupon to refresh the authoritative total before checkout.'
                      : 'Claimed coupons will appear here when available for this account.'
                : '${selectedOffer!.couponCode} · ${selectedOffer!.discountSummary}',
            style: const TextStyle(
              color: AppColors.textGrey,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (selectionMessage.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              selectionMessage,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: isRefreshing ? 'Refreshing...' : 'Choose coupon',
                  onPressed: isRefreshing ? null : onChoose,
                  size: AppButtonSize.compact,
                ),
              ),
              if (selectedOffer != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: SecondaryButton(
                    label: 'Remove',
                    onPressed: isRefreshing ? null : onRemove,
                    size: AppButtonSize.compact,
                  ),
                ),
              ],
            ],
          ),
          if (selectedOffer != null) ...[
            const SizedBox(height: 10),
            SecondaryButton(
              label: isRefreshing ? 'Refreshing...' : 'Refresh total',
              onPressed: isRefreshing ? null : onRefresh,
              size: AppButtonSize.compact,
            ),
          ],
        ],
      ),
    );
  }
}

class _CouponOptionTile extends StatelessWidget {
  const _CouponOptionTile({
    required this.offer,
    required this.issue,
    required this.isSelected,
    required this.onTap,
  });

  final ClaimedOffer offer;
  final String? issue;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isUnavailable = issue != null;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFF4EC)
              : isUnavailable
              ? const Color(0xFFF7F7F7)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppColors.primary : const Color(0xFFE8E3DC),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    offer.couponCode,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  offer.discountSummary,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (offer.title.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                offer.title,
                style: const TextStyle(
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              issue ??
                  (isSelected
                      ? 'Applied to this checkout.'
                      : 'Tap to apply and refresh the backend total.'),
              style: TextStyle(
                color: isUnavailable
                    ? const Color(0xFFB45309)
                    : AppColors.textGrey,
                height: 1.4,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentHeroCard extends StatelessWidget {
  final String serviceName;
  final String providerName;
  final String serviceImageUrl;
  final String headline;
  final String subheadline;

  const _PaymentHeroCard({
    required this.serviceName,
    required this.providerName,
    required this.serviceImageUrl,
    required this.headline,
    required this.subheadline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: serviceImageUrl.trim().isEmpty
                      ? Container(
                          color: const Color(0xFFFFF0E5),
                          child: const Icon(
                            Icons.pets_rounded,
                            color: AppColors.primary,
                          ),
                        )
                      : Image.network(
                          serviceImageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: const Color(0xFFFFF0E5),
                            child: const Icon(
                              Icons.pets_rounded,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      serviceName,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      providerName,
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            headline,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subheadline,
            style: const TextStyle(
              color: AppColors.textGrey,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final String title;
  final String body;

  const _DetailCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textDark,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              color: AppColors.textGrey,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PricingCard extends StatelessWidget {
  final CanonicalPaymentPricingSummary? pricingSummary;

  const _PricingCard({required this.pricingSummary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: pricingSummary == null
          ? const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pricing summary',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Authoritative pricing will appear once secure payment initialization starts.',
                  style: TextStyle(
                    color: AppColors.textGrey,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          : Column(
              children: [
                _PriceRow(
                  label: 'Service subtotal',
                  value: _formatMoney(pricingSummary!.serviceSubtotalPaise),
                ),
                const SizedBox(height: 10),
                _PriceRow(
                  label: 'Coupon discount',
                  value: pricingSummary!.couponDiscountPaise > 0
                      ? '-${_formatMoney(pricingSummary!.couponDiscountPaise)}'
                      : _formatMoney(0),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(height: 1),
                ),
                _PriceRow(
                  label: 'Amount payable',
                  value: _formatMoney(pricingSummary!.customerPaidPaise),
                  isStrong: true,
                ),
              ],
            ),
    );
  }

  String _formatMoney(int paise) {
    final rupees = paise / 100;
    final formatted = rupees == rupees.roundToDouble()
        ? rupees.toInt().toString()
        : rupees.toStringAsFixed(2);
    return '₹$formatted';
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isStrong;

  const _PriceRow({
    required this.label,
    required this.value,
    this.isStrong = false,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle = TextStyle(
      color: AppColors.textDark,
      fontWeight: isStrong ? FontWeight.w900 : FontWeight.w700,
      fontSize: isStrong ? 18 : 15,
    );
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(value, style: valueStyle),
      ],
    );
  }
}
