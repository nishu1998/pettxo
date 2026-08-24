import 'dart:ui';

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/app_loader.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/legal_consent_checkbox.dart';
import '../../../offers/data/services/offer_service.dart';
import '../../../offers/domain/models/available_offer.dart';
import '../../../settings/presentation/screens/legal_policies_screen.dart';
import '../../data/repositories/booking_repository.dart';
import '../../data/services/razorpay_checkout_service.dart';
import '../../domain/models/booking_document_v3.dart';
import '../../domain/models/booking_payment_order.dart';
import '../../domain/models/booking_read_model.dart';
import '../../domain/models/booking_v3_models.dart';
import '../utils/canonical_booking_schedule_presentation.dart';
import 'booking_confirmation_screen.dart';
import 'canonical_booking_qr_payment_screen.dart';
import '../widgets/booking_deadline_countdown.dart';

class CanonicalBookingPaymentScreen extends StatefulWidget {
  final String bookingId;
  final String serviceName;
  final String providerName;
  final String serviceImageUrl;
  final BookingRepository? bookingRepository;
  final OfferService? offerService;
  final RazorpayCheckoutService? razorpayCheckoutService;
  final Future<AvailableOffersResult> Function({
    required double bookingAmount,
    String? serviceId,
    String? providerId,
    String? category,
  })?
  loadAvailableOffers;

  const CanonicalBookingPaymentScreen({
    super.key,
    required this.bookingId,
    required this.serviceName,
    required this.providerName,
    required this.serviceImageUrl,
    this.bookingRepository,
    this.offerService,
    this.razorpayCheckoutService,
    this.loadAvailableOffers,
  });

  @override
  State<CanonicalBookingPaymentScreen> createState() =>
      _CanonicalBookingPaymentScreenState();
}

class _CanonicalBookingPaymentScreenState
    extends State<CanonicalBookingPaymentScreen> {
  StreamSubscription<BookingReadModel?>? _confirmationSubscription;
  StreamSubscription<CanonicalPaymentAttemptReadModel?>? _attemptSubscription;
  Timer? _ticker;

  String _paymentAttemptId = '';
  CanonicalPaymentAttemptReadModel? _latestAttempt;
  CanonicalPaymentPricingPreviewResult? _pricingPreview;
  bool _isPreparingOrder = false;
  bool _isPreparingQr = false;
  bool _isCheckoutOpen = false;
  bool _isObservingConfirmation = false;
  bool _hasNavigatedToConfirmation = false;
  bool _isRefreshingOfferPreview = false;
  bool _isLoadingAvailableOffers = false;
  bool _isLoadingPricingPreview = false;
  bool _hasAcceptedCancellationPolicy = false;
  String _selectedOfferCampaignId = '';
  String _selectedOfferMessage = '';
  String _pricingPreviewError = '';
  String _lastPreviewKey = '';
  String _lastAvailableOffersKey = '';
  String _availableOffersError = '';
  List<AvailableOffer> _availableOffers = const <AvailableOffer>[];

  BookingRepository get _bookingRepository =>
      widget.bookingRepository ?? BookingRepository();

  RazorpayCheckoutService get _razorpayCheckoutService =>
      widget.razorpayCheckoutService ?? RazorpayCheckoutService();

  OfferService get _offerService => widget.offerService ?? OfferService();

  bool _canResumeExistingCheckoutAttempt(
    CanonicalPaymentAttemptReadModel? attempt,
  ) {
    if (attempt == null) return false;
    return attempt.state == CanonicalPaymentAttemptState.orderCreated ||
        attempt.state == CanonicalPaymentAttemptState.checkoutOpened;
  }

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
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(92),
        child: _GlassTopBar(title: 'Review & pay'),
      ),
      body: StreamBuilder<BookingReadModel?>(
        stream: _bookingRepository.watchCanonicalBooking(widget.bookingId),
        builder: (context, snapshot) {
          final booking = _canonicalBookingFromReadModel(snapshot.data);
          AvailableOffer? selectedOffer;
          for (final offer in _availableOffers) {
            if (offer.id == _selectedOfferCampaignId) {
              selectedOffer = offer;
              break;
            }
          }
          if (_selectedOfferCampaignId.isNotEmpty && selectedOffer == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _clearSelectedOffer(showFeedback: false);
            });
          }
          if (booking != null &&
              booking.payment.paymentAttemptId.trim().isNotEmpty &&
              booking.payment.paymentAttemptId.trim() != _paymentAttemptId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _bindAttemptStream(booking.payment.paymentAttemptId.trim());
            });
          }

          if (booking != null) {
            final availableOffersKey = _availableOffersKey(booking);
            if (_lastAvailableOffersKey != availableOffersKey &&
                !_isLoadingAvailableOffers) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _refreshAvailableOffers(booking);
              });
            }

            final previewKey =
                '${widget.bookingId}:${_selectedOfferCampaignId.trim()}';
            if (_lastPreviewKey != previewKey &&
                !_isLoadingPricingPreview &&
                !_isRefreshingOfferPreview) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _refreshPricingPreview(
                  booking,
                  offerCampaignId: _selectedOfferCampaignId,
                );
              });
            }
          }

          final pricingSummary = _resolvePricingSummary();
          final payDeadline =
              _pricingPreview?.payDeadlineAt ??
              booking?.lifecycle.payDeadlineAt ??
              _latestAttempt?.orderExpiresAt;
          final isExpired =
              payDeadline != null && !payDeadline.isAfter(DateTime.now());
          final hasValidPricing =
              pricingSummary != null &&
              _pricingPreviewError.isEmpty &&
              !_isLoadingPricingPreview;
          final canPay =
              booking != null &&
              booking.state ==
                  CanonicalBookingStateV3.acceptedAwaitingPayment &&
              !isExpired &&
              hasValidPricing &&
              !_isPreparingOrder &&
              !_isPreparingQr &&
              !_isCheckoutOpen &&
              !_isObservingConfirmation &&
              (_latestAttempt == null ||
                  _canResumeExistingCheckoutAttempt(_latestAttempt) ||
                  _latestAttempt!.state ==
                      CanonicalPaymentAttemptState.notStarted);
          final payableBooking = canPay ? booking : null;
          final canSubmitPayment =
              payableBooking != null && _hasAcceptedCancellationPolicy;
          return SafeArea(
            child: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 196),
                  children: [
                    const _SectionLabel('Booking summary'),
                    const SizedBox(height: 10),
                    _PaymentHeroCard(
                      serviceName: widget.serviceName,
                      providerName: widget.providerName,
                      dateLabel: booking == null
                          ? 'Loading...'
                          : _bookingDateLabel(booking),
                      timeLabel: booking == null
                          ? 'Loading...'
                          : _bookingTimeLabel(booking),
                      durationLabel: booking == null
                          ? 'Loading...'
                          : _bookingDurationLabel(booking),
                    ),
                    const SizedBox(height: 16),
                    const _SectionLabel('Payment status'),
                    const SizedBox(height: 10),
                    _PaymentStatusCard(
                      statusLabel: _paymentStatusHeadline(
                        booking,
                        _latestAttempt,
                        isExpired,
                      ),
                      statusBody: _paymentStatusText(
                        booking,
                        _latestAttempt,
                        isExpired,
                      ),
                      paymentDeadline:
                          !isExpired &&
                              booking?.state ==
                                  CanonicalBookingStateV3
                                      .acceptedAwaitingPayment
                          ? payDeadline
                          : null,
                    ),
                    const _SectionLabel('Price details'),
                    const SizedBox(height: 10),
                    _PricingCard(
                      pricingSummary: pricingSummary,
                      isLoading: _isLoadingPricingPreview,
                      errorMessage: _pricingPreviewError,
                      selectedOffer: selectedOffer,
                      selectionMessage: _selectedOfferMessage,
                      isRefreshingOffer: _isRefreshingOfferPreview,
                      offersAvailable: _availableOffers.isNotEmpty,
                      isLoadingOffers: _isLoadingAvailableOffers,
                      offersErrorMessage: _availableOffersError,
                      onChooseOffer: booking == null
                          ? null
                          : () => _showCouponSheet(booking, _availableOffers),
                      onRemoveOffer: _selectedOfferCampaignId.isEmpty
                          ? null
                          : booking == null
                          ? null
                          : () => _removeSelectedOffer(booking),
                      onChangeOffer: booking == null || selectedOffer == null
                          ? null
                          : () => _showCouponSheet(booking, _availableOffers),
                      onRetry: booking == null
                          ? null
                          : () => _refreshPricingPreview(
                              booking,
                              offerCampaignId: _selectedOfferCampaignId,
                              force: true,
                            ),
                    ),
                    const SizedBox(height: 16),
                    const _SectionLabel('Choose payment method'),
                    const SizedBox(height: 10),
                    _PaymentMethodCard(
                      title: 'Pay with Razorpay',
                      subtitle: 'UPI Apps • Cards • Netbanking • Wallets',
                      action: _isPreparingOrder
                          ? const SizedBox(
                              width: double.infinity,
                              child: GradientButton(
                                label: 'Preparing secure payment...',
                                onPressed: null,
                                isLoading: true,
                              ),
                            )
                          : canSubmitPayment
                          ? GradientButton(
                              label: _checkoutButtonLabel(pricingSummary),
                              onPressed: () =>
                                  _startCheckoutPaymentFlow(payableBooking),
                            )
                          : SecondaryButton(
                              label: _secondaryButtonLabel(booking, isExpired),
                              onPressed: null,
                            ),
                    ),
                    const SizedBox(height: 12),
                    _PaymentMethodCard(
                      title: 'Pay using QR',
                      subtitle: 'Scan using another phone or any UPI app',
                      action: _isPreparingQr
                          ? const SizedBox(
                              width: double.infinity,
                              child: GradientButton(
                                label: 'Creating QR...',
                                onPressed: null,
                                isLoading: true,
                              ),
                            )
                          : canSubmitPayment
                          ? SecondaryButton(
                              label: _qrButtonLabel(pricingSummary),
                              onPressed: () =>
                                  _startQrPaymentFlow(payableBooking),
                            )
                          : SecondaryButton(
                              label: _secondaryButtonLabel(booking, isExpired),
                              onPressed: null,
                            ),
                    ),
                    const SizedBox(height: 16),
                    const _SectionLabel('Cancellation'),
                    const SizedBox(height: 10),
                    _CancellationPolicyCard(
                      onOpenCancellationPolicy: () => _openPolicyDocument(
                        LegalPoliciesCatalog.cancellationPolicy,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: LegalConsentCheckbox(
                        value: _hasAcceptedCancellationPolicy,
                        onChanged: (value) {
                          setState(() {
                            _hasAcceptedCancellationPolicy = value ?? false;
                          });
                        },
                        segments: [
                          const LegalConsentSegment(text: 'I understand the '),
                          LegalConsentSegment(
                            text: 'Cancellation Policy',
                            onTap: () => _openPolicyDocument(
                              LegalPoliciesCatalog.cancellationPolicy,
                            ),
                          ),
                          const LegalConsentSegment(text: ' and agree to the '),
                          LegalConsentSegment(
                            text: 'Refund Policy',
                            onTap: () => _openPolicyDocument(
                              LegalPoliciesCatalog.refundPolicy,
                            ),
                          ),
                          const LegalConsentSegment(text: '.'),
                        ],
                      ),
                    ),
                    if (_latestAttempt != null) ...[
                      const SizedBox(height: 16),
                      const _SectionLabel('Latest attempt'),
                      const SizedBox(height: 10),
                      _DetailCard(
                        title: 'Latest payment attempt',
                        body: _attemptStatusDescription(_latestAttempt!),
                      ),
                    ],
                  ],
                ),
              ],
            ),
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

  CanonicalPaymentPricingSummary? _resolvePricingSummary() {
    if (_pricingPreview != null) {
      return _pricingPreview!.pricingSummary;
    }
    if (_latestAttempt != null) return _latestAttempt!.pricingSummary;
    return null;
  }

  Future<void> _startCheckoutPaymentFlow(
    CanonicalBookingDocumentV3 booking,
  ) async {
    if (_isPreparingOrder ||
        _isPreparingQr ||
        _isCheckoutOpen ||
        _isObservingConfirmation) {
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
        offerCampaignId: _selectedOfferCampaignId.isEmpty
            ? null
            : _selectedOfferCampaignId,
      );
      _pricingPreview = CanonicalPaymentPricingPreviewResult(
        bookingId: orderResult.bookingId,
        pricingSummary: orderResult.pricingSummary,
        payDeadlineAt: orderResult.expiresAt,
        offerCampaignId: _selectedOfferCampaignId,
        idempotentReplay: orderResult.idempotentReplay,
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
      if (error.code == CanonicalPaymentFailureCode.couponInvalid ||
          error.code == CanonicalPaymentFailureCode.pricingChanged) {
        _handlePricingInvalidation(booking, error);
        return;
      }
      if (error.activeAttemptId.isNotEmpty) {
        _bindAttemptStream(error.activeAttemptId);
      }
      if (checkoutSucceeded && _shouldObserveAfterVerificationError(error)) {
        _beginAuthoritativeObservation(
          message: _observationMessageForVerificationError(error),
        );
        return;
      }
      AppFeedback.show(
        context,
        message: _friendlyPaymentActionError(error),
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

  Future<void> _startQrPaymentFlow(CanonicalBookingDocumentV3 booking) async {
    if (_isPreparingOrder ||
        _isPreparingQr ||
        _isCheckoutOpen ||
        _isObservingConfirmation) {
      return;
    }
    final authUser = Firebase.apps.isNotEmpty
        ? FirebaseAuth.instance.currentUser
        : null;
    if (kDebugMode) {
      debugPrint(
        '[BookingQrPayment] tap bookingId=${widget.bookingId} firebaseInitialized=${Firebase.apps.isNotEmpty} currentUserPresent=${authUser != null} currentUserId=${authUser?.uid ?? ''} paymentState=${booking.state.name} payablePaise=${_pricingPreview?.pricingSummary.customerPaidPaise ?? 0}',
      );
      debugPrint(
        '[BookingQrPayment] auth_check bookingId=${widget.bookingId} firebaseAuthCurrentUserPresent=${authUser != null} uidMatchBookingCustomer=${authUser?.uid.trim() == booking.customerId.trim()}',
      );
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

    setState(() => _isPreparingQr = true);
    AppLoader.showWithMessage('Creating secure QR...');

    try {
      if (kDebugMode) {
        debugPrint(
          '[BookingQrPayment] callable_start callable=createBookingQrPaymentV3 bookingId=${widget.bookingId}',
        );
      }
      final qrResult = await _bookingRepository.createQrPaymentV3(
        bookingId: widget.bookingId,
        offerCampaignId: _selectedOfferCampaignId.isEmpty
            ? null
            : _selectedOfferCampaignId,
      );
      _pricingPreview = CanonicalPaymentPricingPreviewResult(
        bookingId: qrResult.bookingId,
        pricingSummary: qrResult.pricingSummary,
        payDeadlineAt: qrResult.expiresAt ?? booking.lifecycle.payDeadlineAt,
        offerCampaignId: _selectedOfferCampaignId,
        idempotentReplay: qrResult.idempotentReplay,
      );
      _bindAttemptStream(qrResult.paymentAttemptId);
      AppLoader.hide();
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint(
          '[BookingQrPayment] callable_success bookingId=${widget.bookingId} qrIdPresent=${qrResult.qrCodeId.trim().isNotEmpty} status=${qrResult.state}',
        );
      }

      if (qrResult.isZeroPayable) {
        setState(() => _isObservingConfirmation = true);
        AppFeedback.show(
          context,
          message: 'No payment is required. Confirming your booking now...',
          tone: AppFeedbackTone.info,
        );
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CanonicalBookingQrPaymentScreen(
            bookingId: widget.bookingId,
            qrPayment: qrResult,
            bookingRepository: _bookingRepository,
          ),
        ),
      );
    } on CanonicalPaymentException catch (error) {
      AppLoader.hide();
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint(
          '[BookingQrPayment] callable_failed bookingId=${widget.bookingId} failureCode=${error.code.name} safeMessage=${error.message}',
        );
      }
      if (error.code == CanonicalPaymentFailureCode.couponInvalid ||
          error.code == CanonicalPaymentFailureCode.pricingChanged) {
        _handlePricingInvalidation(booking, error);
        return;
      }
      if (error.activeAttemptId.isNotEmpty) {
        _bindAttemptStream(error.activeAttemptId);
      }
      final message = switch (error.code) {
        CanonicalPaymentFailureCode.paymentReconciliationRequired =>
          'We\'re verifying your payment. Please don\'t make another payment for this booking.',
        CanonicalPaymentFailureCode.paymentQrSwitchLocked =>
          _qrSwitchLockedMessage(error),
        _ => error.message,
      };
      AppFeedback.show(
        context,
        message: message,
        tone: error.code == CanonicalPaymentFailureCode.paymentWindowExpired
            ? AppFeedbackTone.warning
            : AppFeedbackTone.error,
      );
    } catch (_) {
      AppLoader.hide();
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint(
          '[BookingQrPayment] unknown_failure bookingId=${widget.bookingId}',
        );
      }
      AppFeedback.show(
        context,
        message: 'We could not create a QR payment right now.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      AppLoader.hide();
      if (mounted) {
        setState(() => _isPreparingQr = false);
      }
    }
  }

  String _availableOffersKey(CanonicalBookingDocumentV3 booking) {
    return [
      widget.bookingId,
      booking.serviceId,
      booking.providerId,
      booking.service.category,
      _serviceSubtotalPaise(booking).toString(),
    ].join(':');
  }

  Future<void> _refreshAvailableOffers(
    CanonicalBookingDocumentV3 booking, {
    bool force = false,
  }) async {
    final requestKey = _availableOffersKey(booking);
    if (!force &&
        (_isLoadingAvailableOffers || _lastAvailableOffersKey == requestKey)) {
      return;
    }

    setState(() {
      _isLoadingAvailableOffers = true;
      _availableOffersError = '';
      _lastAvailableOffersKey = requestKey;
    });

    try {
      final loader =
          widget.loadAvailableOffers ??
          ({
            required double bookingAmount,
            String? serviceId,
            String? providerId,
            String? category,
          }) => _offerService.getAvailableOffers(
            screen: 'checkout',
            bookingAmount: bookingAmount,
            serviceId: serviceId,
            providerId: providerId,
            serviceCategory: category,
          );
      final result = await loader(
        bookingAmount: _serviceSubtotalPaise(booking) / 100,
        serviceId: booking.serviceId,
        providerId: booking.providerId,
        category: booking.service.category,
      );
      if (!mounted) return;
      setState(() {
        _availableOffers = result.offers;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _availableOffers = const <AvailableOffer>[];
        _availableOffersError =
            'We could not refresh available offers right now.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingAvailableOffers = false);
      }
    }
  }

  Future<void> _refreshPricingPreview(
    CanonicalBookingDocumentV3 booking, {
    String? offerCampaignId,
    bool force = false,
  }) async {
    final safeOfferCampaignId = offerCampaignId?.trim() ?? '';
    final previewKey = '${widget.bookingId}:$safeOfferCampaignId';
    if (!force && (_isLoadingPricingPreview || _lastPreviewKey == previewKey)) {
      return;
    }
    _logPricingPreview(
      'request',
      booking: booking,
      offerCampaignId: safeOfferCampaignId,
      extra: 'force=$force',
    );
    setState(() {
      _isLoadingPricingPreview = true;
      _pricingPreview = null;
      _pricingPreviewError = '';
      _lastPreviewKey = previewKey;
    });
    try {
      final preview = await _bookingRepository.previewPaymentPricingV3(
        bookingId: widget.bookingId,
        offerCampaignId: safeOfferCampaignId.isEmpty
            ? null
            : safeOfferCampaignId,
      );
      if (!mounted) return;
      setState(() {
        _pricingPreview = preview;
        _paymentAttemptId = '';
        _latestAttempt = null;
      });
      _logPricingPreview(
        'success',
        booking: booking,
        offerCampaignId: safeOfferCampaignId,
        extra:
            'payablePaise=${preview.pricingSummary.customerPaidPaise} discountPaise=${preview.pricingSummary.couponDiscountPaise}',
      );
    } on CanonicalPaymentException catch (error) {
      if (!mounted) return;
      setState(() {
        _pricingPreview = null;
        _pricingPreviewError = _friendlyPricingPreviewError(error);
      });
      _logPricingPreview(
        'business_error',
        booking: booking,
        offerCampaignId: safeOfferCampaignId,
        extra: 'code=${error.code.name} message=${error.message}',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pricingPreview = null;
        _pricingPreviewError = 'We couldn\'t load the payment total.';
      });
      _logPricingPreview(
        'unknown_error',
        booking: booking,
        offerCampaignId: safeOfferCampaignId,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingPricingPreview = false);
      }
    }
  }

  void _handlePricingInvalidation(
    CanonicalBookingDocumentV3 booking,
    CanonicalPaymentException error,
  ) {
    final message = error.code == CanonicalPaymentFailureCode.couponInvalid
        ? 'That coupon is no longer valid. We refreshed your total.'
        : 'The latest payment total changed. We refreshed it for you.';
    if (_selectedOfferCampaignId.isNotEmpty) {
      _clearSelectedOffer(showFeedback: false);
    }
    _refreshAvailableOffers(booking, force: true);
    _refreshPricingPreview(booking, force: true);
    AppFeedback.show(context, message: message, tone: AppFeedbackTone.warning);
  }

  String _friendlyPricingPreviewError(CanonicalPaymentException error) {
    switch (error.code) {
      case CanonicalPaymentFailureCode.paymentWindowExpired:
        return 'The payment window has expired.';
      case CanonicalPaymentFailureCode.bookingNotFound:
        return 'This booking could not be found.';
      case CanonicalPaymentFailureCode.bookingNotPayable:
        return 'This booking is not payable right now.';
      case CanonicalPaymentFailureCode.couponInvalid:
        return 'This coupon can no longer be applied.';
      case CanonicalPaymentFailureCode.actorNotAuthorized:
        return 'Please sign in again before continuing.';
      case CanonicalPaymentFailureCode.paymentDisabled:
        return 'Pricing is temporarily unavailable.';
      default:
        return 'We couldn\'t load the payment total.';
    }
  }

  String _friendlyPaymentActionError(CanonicalPaymentException error) {
    switch (error.code) {
      case CanonicalPaymentFailureCode.paymentQrSwitchLocked:
        return _qrSwitchLockedMessage(error);
      case CanonicalPaymentFailureCode.paymentReconciliationRequired:
        return 'Checking your previous payment. Please don\'t pay again.';
      default:
        return error.message;
    }
  }

  String _qrSwitchLockedMessage(CanonicalPaymentException error) {
    final lockUntil = error.lockUntil;
    if (lockUntil == null) {
      return 'QR payment is still active for your safety. Please wait before switching payment methods.';
    }
    final remaining = BookingDeadlineCountdown.formatClock(lockUntil);
    return 'QR payment is still active. You can switch payment methods in $remaining.';
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
    return 'Awaiting payment.';
  }

  String _paymentStatusHeadline(
    CanonicalBookingDocumentV3? booking,
    CanonicalPaymentAttemptReadModel? attempt,
    bool isExpired,
  ) {
    if (attempt != null) {
      return switch (attempt.state) {
        CanonicalPaymentAttemptState.confirmed => 'Payment confirmed',
        CanonicalPaymentAttemptState.failed => 'Payment failed',
        CanonicalPaymentAttemptState.expired => 'Payment window expired',
        CanonicalPaymentAttemptState.refundPending ||
        CanonicalPaymentAttemptState.refundRequired => 'Refund in progress',
        _ => 'Action required',
      };
    }
    if (booking == null) return 'Loading status';
    if (booking.lifecycle.paidAt != null ||
        booking.state == CanonicalBookingStateV3.confirmed) {
      return 'Payment received';
    }
    if (isExpired || booking.state == CanonicalBookingStateV3.paymentExpired) {
      return 'Payment window expired';
    }
    return 'Awaiting payment';
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

  String _checkoutButtonLabel(CanonicalPaymentPricingSummary? pricingSummary) {
    if (_isCheckoutOpen) return 'Opening checkout...';
    if (_isObservingConfirmation) return 'Awaiting confirmation...';
    if (_canResumeExistingCheckoutAttempt(_latestAttempt)) {
      return 'Resume Razorpay checkout';
    }
    return 'Pay with Razorpay';
  }

  String _qrButtonLabel(CanonicalPaymentPricingSummary? pricingSummary) {
    if (_isObservingConfirmation) return 'Awaiting confirmation...';
    return 'Pay using QR';
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
    List<AvailableOffer> offers,
  ) async {
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
                  'Choose a coupon to refresh your total before checkout starts.',
                  style: TextStyle(
                    color: AppColors.textGrey,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                if (_isLoadingAvailableOffers)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (offers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No coupons are currently available for this booking.',
                      style: TextStyle(
                        color: AppColors.textGrey,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: offers.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final offer = offers[index];
                        final isSelected = offer.id == _selectedOfferCampaignId;
                        return _CouponOptionTile(
                          offer: offer,
                          isSelected: isSelected,
                          onTap: () async {
                            Navigator.pop(context);
                            await _previewAvailableOffer(
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

  Future<void> _previewAvailableOffer(
    CanonicalBookingDocumentV3 booking,
    AvailableOffer offer, {
    required bool selectOffer,
  }) async {
    setState(() => _isRefreshingOfferPreview = true);
    try {
      setState(() {
        if (selectOffer) {
          _selectedOfferCampaignId = offer.id;
          _selectedOfferMessage = offer.couponCode.isEmpty
              ? 'Offer applied.'
              : '${offer.couponCode} applied.';
          _paymentAttemptId = '';
          _latestAttempt = null;
        }
      });
      await _refreshPricingPreview(
        booking,
        offerCampaignId: offer.id,
        force: true,
      );
    } on CanonicalPaymentException catch (error) {
      if (!mounted) return;
      if (error.code == CanonicalPaymentFailureCode.couponInvalid ||
          error.code == CanonicalPaymentFailureCode.pricingChanged) {
        _handlePricingInvalidation(booking, error);
        return;
      }
      AppFeedback.show(
        context,
        message: error.message,
        tone: AppFeedbackTone.error,
      );
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
      _selectedOfferCampaignId = '';
      _selectedOfferMessage = '';
      _paymentAttemptId = '';
      _latestAttempt = null;
      _lastPreviewKey = '';
    });
    if (showFeedback) {
      AppFeedback.show(
        context,
        message: 'Coupon removed. Refreshing your total...',
      );
    }
  }

  Future<void> _removeSelectedOffer(CanonicalBookingDocumentV3 booking) async {
    _clearSelectedOffer();
    await _refreshPricingPreview(booking, force: true);
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

  String _bookingDateLabel(CanonicalBookingDocumentV3 booking) {
    return buildCanonicalBookingSchedulePresentation(booking).dateLabel;
  }

  String _bookingTimeLabel(CanonicalBookingDocumentV3 booking) {
    return buildCanonicalBookingSchedulePresentation(booking).timeLabel;
  }

  String _bookingDurationLabel(CanonicalBookingDocumentV3 booking) {
    return buildCanonicalBookingSchedulePresentation(booking).durationLabel;
  }

  Future<void> _openPolicyDocument(LegalPolicyDocument document) {
    return Navigator.of(context).pushNamed(document.routeName);
  }

  void _logPricingPreview(
    String event, {
    required CanonicalBookingDocumentV3 booking,
    required String offerCampaignId,
    String extra = '',
  }) {
    if (kDebugMode) {
      debugPrint(
        '[CanonicalPaymentScreen] preview_$event bookingId=${widget.bookingId} state=${booking.state.name} hasCoupon=${offerCampaignId.isNotEmpty} $extra',
      );
    }
  }
}

class _CouponOptionTile extends StatelessWidget {
  const _CouponOptionTile({
    required this.offer,
    required this.isSelected,
    required this.onTap,
  });

  final AvailableOffer offer;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF4EC) : Colors.white,
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
            if (offer.description.isNotEmpty) ...[
              Text(
                offer.description,
                style: const TextStyle(
                  color: AppColors.textGrey,
                  height: 1.4,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if ((offer.minBookingAmount ?? 0) > 0)
                  _CouponMetaChip(
                    label:
                        'Min ${_formatMoney((offer.minBookingAmount! * 100).round())}',
                  ),
                if ((offer.maxDiscountAmount ?? 0) > 0)
                  _CouponMetaChip(
                    label:
                        'Up to ${_formatMoney((offer.maxDiscountAmount! * 100).round())}',
                  ),
                if (offer.endAt != null)
                  _CouponMetaChip(
                    label:
                        'Valid until ${offer.endAt!.day}/${offer.endAt!.month}/${offer.endAt!.year}',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isSelected
                  ? 'Applied to this checkout.'
                  : 'Tap to apply and refresh the backend total.',
              style: const TextStyle(
                color: AppColors.textGrey,
                height: 1.4,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: SecondaryButton(
                label: isSelected ? 'Applied' : 'Apply',
                onPressed: isSelected ? null : onTap,
                size: AppButtonSize.compact,
                expand: false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatMoney(int paise) {
    final rupees = paise / 100;
    return '₹${rupees.toStringAsFixed(2)}';
  }
}

class _CouponMetaChip extends StatelessWidget {
  const _CouponMetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textDark,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _GlassTopBar extends StatelessWidget {
  const _GlassTopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.45),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textGrey,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentHeroCard extends StatelessWidget {
  final String serviceName;
  final String providerName;
  final String dateLabel;
  final String timeLabel;
  final String durationLabel;

  const _PaymentHeroCard({
    required this.serviceName,
    required this.providerName,
    required this.dateLabel,
    required this.timeLabel,
    required this.durationLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryRow(label: 'Service', value: serviceName),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          _SummaryRow(label: 'Provider', value: providerName),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          _SummaryRow(label: 'Date', value: dateLabel),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          _SummaryRow(label: 'Time', value: timeLabel),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          _SummaryRow(label: 'Duration', value: durationLabel),
        ],
      ),
    );
  }
}

class _PaymentStatusCard extends StatelessWidget {
  const _PaymentStatusCard({
    required this.statusLabel,
    required this.statusBody,
    required this.paymentDeadline,
  });

  final String statusLabel;
  final String statusBody;
  final DateTime? paymentDeadline;

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
          Text(
            statusLabel,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            statusBody,
            style: const TextStyle(
              color: AppColors.textGrey,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (paymentDeadline != null) ...[
            const SizedBox(height: 18),
            BookingDeadlineCountdown(
              deadline: paymentDeadline,
              valueFontSize: 18,
              labelFontSize: 12,
              crossAxisAlignment: CrossAxisAlignment.center,
              textAlign: TextAlign.center,
              centerLabelRow: true,
              showSideDividers: true,
            ),
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.center,
              child: Text(
                'Pay before the timer ends to confirm availability.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 12,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
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
  final bool isLoading;
  final String errorMessage;
  final AvailableOffer? selectedOffer;
  final String selectionMessage;
  final bool isRefreshingOffer;
  final bool offersAvailable;
  final bool isLoadingOffers;
  final String offersErrorMessage;
  final VoidCallback? onChooseOffer;
  final VoidCallback? onRemoveOffer;
  final VoidCallback? onChangeOffer;
  final VoidCallback? onRetry;

  const _PricingCard({
    required this.pricingSummary,
    required this.isLoading,
    required this.errorMessage,
    required this.selectedOffer,
    required this.selectionMessage,
    required this.isRefreshingOffer,
    required this.offersAvailable,
    required this.isLoadingOffers,
    required this.offersErrorMessage,
    required this.onChooseOffer,
    required this.onRemoveOffer,
    required this.onChangeOffer,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: isLoading
          ? const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Price details',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Calculating your total...',
                  style: TextStyle(
                    color: AppColors.textGrey,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          : errorMessage.trim().isNotEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Price details',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'We couldn’t load the payment total.',
                  style: TextStyle(
                    color: AppColors.textGrey,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                SecondaryButton(
                  label: 'Retry',
                  onPressed: onRetry,
                  size: AppButtonSize.compact,
                  expand: false,
                ),
              ],
            )
          : pricingSummary == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Price details',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                _OfferSummaryPanel(
                  selectedOffer: selectedOffer,
                  selectionMessage: selectionMessage,
                  isRefreshing: isRefreshingOffer,
                  offersAvailable: offersAvailable,
                  isLoadingOffers: isLoadingOffers,
                  offersErrorMessage: offersErrorMessage,
                  onChoose: onChooseOffer,
                  onRemove: onRemoveOffer,
                  onChange: onChangeOffer,
                ),
                const SizedBox(height: 14),
                _PriceRow(
                  label: 'Service amount',
                  value: _formatMoney(pricingSummary!.serviceSubtotalPaise),
                ),
                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  color: AppColors.textGrey.withValues(alpha: 0.14),
                ),
                const SizedBox(height: 12),
                _PriceRow(
                  label: 'Offer discount',
                  value: pricingSummary!.couponDiscountPaise > 0
                      ? '-${_formatMoney(pricingSummary!.couponDiscountPaise)}'
                      : '- ${_formatMoney(0)}',
                ),
                const SizedBox(height: 6),
                Divider(
                  height: 1,
                  color: AppColors.textGrey.withValues(alpha: 0.14),
                ),
                const SizedBox(height: 6),
                _PriceRow(
                  label: 'Total payable',
                  value: _formatMoney(pricingSummary!.customerPaidPaise),
                  isStrong: true,
                ),
              ],
            ),
    );
  }

  String _formatMoney(int paise) {
    final rupees = paise / 100;
    return '₹${rupees.toStringAsFixed(2)}';
  }
}

class _OfferSummaryPanel extends StatelessWidget {
  const _OfferSummaryPanel({
    required this.selectedOffer,
    required this.selectionMessage,
    required this.isRefreshing,
    required this.offersAvailable,
    required this.isLoadingOffers,
    required this.offersErrorMessage,
    required this.onChoose,
    required this.onRemove,
    required this.onChange,
  });

  final AvailableOffer? selectedOffer;
  final String selectionMessage;
  final bool isRefreshing;
  final bool offersAvailable;
  final bool isLoadingOffers;
  final String offersErrorMessage;
  final VoidCallback? onChoose;
  final VoidCallback? onRemove;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final action = selectedOffer == null ? onChoose : onChange;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  selectedOffer == null ? 'Apply an offer' : 'Offer applied',
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SecondaryButton(
                label: isRefreshing ? 'Refreshing...' : 'Available offers',
                onPressed: isRefreshing ? null : action,
                size: AppButtonSize.compact,
                expand: false,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            selectedOffer == null
                ? isLoadingOffers
                      ? 'Loading available offers for this booking...'
                      : offersErrorMessage.trim().isNotEmpty
                      ? offersErrorMessage
                      : offersAvailable
                      ? 'Choose an offer to refresh your payable amount.'
                      : 'No offers are currently available for this booking.'
                : '${selectedOffer!.title.isNotEmpty ? selectedOffer!.title : selectedOffer!.couponCode} · ${selectedOffer!.discountSummary}',
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 12,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (selectionMessage.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              selectionMessage,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (selectedOffer != null) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: isRefreshing ? null : onRemove,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  'Remove offer',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: AppColors.textGrey,
        fontSize: 12,
        letterSpacing: 1.8,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final String title;
  final String subtitle;
  final Widget action;

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
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textGrey,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          action,
        ],
      ),
    );
  }
}

class _CancellationPolicyCard extends StatelessWidget {
  const _CancellationPolicyCard({required this.onOpenCancellationPolicy});

  final VoidCallback onOpenCancellationPolicy;

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
            'Review the policy before paying',
            style: TextStyle(
              color: AppColors.textDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Cancellation refunds depend on when the booking is cancelled and follow Pettxo’s published policy.',
            style: TextStyle(
              color: AppColors.textGrey,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 8),
          Wrap(
            children: [
              const Text(
                'Please review the ',
                style: TextStyle(
                  color: AppColors.textGrey,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              InkWell(
                onTap: onOpenCancellationPolicy,
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    'Cancellation Policy',
                    style: TextStyle(
                      color: Color(0xFF2563EB),
                      height: 1.45,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const Text(
                ' before you continue.',
                style: TextStyle(
                  color: AppColors.textGrey,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
