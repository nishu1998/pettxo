import 'package:flutter/gestures.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/app_loader.dart';
import '../../../../core/services/policy_link_service.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../offers/data/services/offer_service.dart';
import '../../../offers/domain/models/claimed_offer.dart';
import '../../../offers/presentation/widgets/claimed_offer_card.dart';
import '../../../restrictions/data/services/user_restriction_service.dart';
import '../../../settings/presentation/screens/legal_policies_screen.dart';
import '../../data/repositories/booking_repository.dart';
import '../../data/services/razorpay_checkout_service.dart';
import '../../domain/models/booking_checkout_draft.dart';
import '../../domain/models/booking_payment_order.dart';
import '../../domain/models/pending_payment_booking.dart';
import 'booking_confirmation_screen.dart';

class PaymentReviewScreen extends StatefulWidget {
  final BookingCheckoutDraft draft;
  final String? pendingBookingId;

  const PaymentReviewScreen({
    super.key,
    required this.draft,
    this.pendingBookingId,
  });

  @override
  State<PaymentReviewScreen> createState() => _PaymentReviewScreenState();
}

class _PaymentReviewScreenState extends State<PaymentReviewScreen> {
  final BookingRepository _bookingRepository = BookingRepository();
  final OfferService _offerService = OfferService();
  final RazorpayCheckoutService _razorpayCheckoutService =
      RazorpayCheckoutService();
  bool _acceptedPolicy = false;
  bool _isSubmitting = false;
  bool _isPreviewingOffer = false;
  ClaimedOffer? _selectedOffer;
  BookingPaymentOrder? _pendingOrder;
  double _discountAmount = 0;
  double get _serviceAmount => widget.draft.totalAmount.toDouble();
  double get _platformFee => _serviceAmount * 0.15;
  double get _finalAmount => (_serviceAmount + _platformFee - _discountAmount)
      .clamp(0, double.infinity)
      .toDouble();

  @override
  void initState() {
    super.initState();
    _loadPendingPaymentBooking();
  }

  Future<void> _loadPendingPaymentBooking() async {
    try {
      final pending = await _bookingRepository.getPendingPaymentBooking(
        bookingId: widget.pendingBookingId,
        serviceId: widget.pendingBookingId == null ? widget.draft.serviceId : null,
        slotId: widget.pendingBookingId == null ? widget.draft.slotId : null,
      );
      if (!mounted || pending == null) return;
      if (pending.paymentExpiresAt != null &&
          !pending.paymentExpiresAt!.isAfter(DateTime.now())) {
        return;
      }
      setState(() {
        _pendingOrder = _bookingPaymentOrderFromPending(pending);
      });
    } catch (_) {
      // Best-effort preload only. Checkout creation still reuses pending orders server-side.
    }
  }

  BookingPaymentOrder _bookingPaymentOrderFromPending(
    PendingPaymentBooking pending,
  ) {
    return BookingPaymentOrder(
      bookingId: pending.bookingId,
      razorpayOrderId: pending.razorpayOrderId,
      keyId: '',
      amountPaise: pending.amountPaise,
      currency: pending.currency,
      serviceAmountPaise: pending.serviceAmountPaise,
      platformFeePaise: pending.platformFeePaise,
      discountPaise: pending.discountPaise,
      totalPayablePaise: pending.totalPayablePaise,
      paymentExpiresAt: pending.paymentExpiresAt,
      alreadyVerified: false,
    );
  }

  Future<void> _selectOffer() async {
    final picked = await showModalBottomSheet<ClaimedOffer>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _OfferPickerSheet(offerService: _offerService);
      },
    );

    if (!mounted || picked == null) return;

    setState(() => _isPreviewingOffer = true);
    try {
      final preview = await _offerService.previewOfferForBooking(
        claimedOfferId: picked.id,
        bookingAmount: _serviceAmount,
        serviceId: widget.draft.serviceId,
        category: null,
      );

      if (!mounted) return;
      if (!preview.ok || !preview.isValid) {
        AppFeedback.show(
          context,
          message: preview.message.isEmpty
              ? 'This offer cannot be applied right now.'
              : preview.message,
          tone: AppFeedbackTone.warning,
        );
        return;
      }

      setState(() {
        _selectedOffer = picked;
        _discountAmount = preview.discountAmount;
        _pendingOrder = null;
      });
      AppFeedback.show(
        context,
        message: preview.message.isEmpty
            ? 'Offer applied successfully.'
            : preview.message,
        tone: AppFeedbackTone.success,
      );
    } catch (_) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'We could not preview this offer right now.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isPreviewingOffer = false);
      }
    }
  }

  void _removeOffer() {
    setState(() {
      _selectedOffer = null;
      _discountAmount = 0;
      _pendingOrder = null;
    });
    AppFeedback.show(
      context,
      message: 'Offer removed.',
      tone: AppFeedbackTone.info,
    );
  }

  Future<void> _proceedToPay() async {
    if (!_acceptedPolicy || _isSubmitting) return;
    if (!UserRestrictionService.instance.ensureCanUseBookingFeatures(context)) {
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      AppFeedback.show(
        context,
        message: 'Please sign in again before booking.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    AppLoader.showWithMessage('Preparing secure payment...');

    try {
      final now = DateTime.now();
      final pendingOrder = _pendingOrder;
      final order =
          pendingOrder != null &&
              pendingOrder.paymentExpiresAt != null &&
              pendingOrder.paymentExpiresAt!.isAfter(now)
          ? pendingOrder
          : await _bookingRepository.createRazorpayBookingOrder(
              serviceId: widget.draft.serviceId,
              slotId: widget.draft.slotId,
              userId: uid,
              claimedOfferId: _selectedOffer?.id,
            );
      var resolvedOrder = order;
      _pendingOrder = resolvedOrder;

      if (!resolvedOrder.alreadyVerified && resolvedOrder.keyId.isEmpty) {
        resolvedOrder = await _bookingRepository.createRazorpayBookingOrder(
          serviceId: widget.draft.serviceId,
          slotId: widget.draft.slotId,
          userId: uid,
          claimedOfferId: _selectedOffer?.id,
        );
        _pendingOrder = resolvedOrder;
      }

      if (resolvedOrder.alreadyVerified) {
        AppLoader.hide();
        if (!mounted) return;
        _pendingOrder = null;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                BookingConfirmationScreen(bookingId: resolvedOrder.bookingId),
          ),
        );
        return;
      }

      if (resolvedOrder.keyId.isEmpty) {
        throw StateError(
          'Razorpay checkout could not be prepared for this booking.',
        );
      }

      AppLoader.hide();
      if (!mounted) return;

      final checkoutOrder = resolvedOrder;
      final checkoutResult = await _razorpayCheckoutService.openCheckout(
        order: checkoutOrder,
        customerName:
            FirebaseAuth.instance.currentUser?.displayName?.trim() ??
            'Pettxo Customer',
        customerEmail: FirebaseAuth.instance.currentUser?.email?.trim() ?? '',
        customerPhone:
            FirebaseAuth.instance.currentUser?.phoneNumber?.trim() ?? '',
        description: widget.draft.serviceName,
      );

      if (!mounted) return;
      AppLoader.showWithMessage('Verifying payment...');
      final bookingId = await _bookingRepository.verifyRazorpayPayment(
        bookingId: checkoutOrder.bookingId,
        razorpayOrderId: checkoutResult.orderId,
        razorpayPaymentId: checkoutResult.paymentId,
        razorpaySignature: checkoutResult.signature,
      );

      AppLoader.hide();
      if (!mounted) return;
      _pendingOrder = null;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => BookingConfirmationScreen(bookingId: bookingId),
        ),
      );
    } on RazorpayCheckoutDismissed {
      AppLoader.hide();
      if (!mounted) return;
      AppFeedback.show(
        context,
        message:
            'Payment was closed. You can retry while the booking is pending.',
        tone: AppFeedbackTone.info,
      );
    } on RazorpayCheckoutFailure catch (error) {
      AppLoader.hide();
      final failedBookingId = _pendingOrder?.bookingId ?? '';
      if (mounted && failedBookingId.isNotEmpty) {
        await _bookingRepository
            .markRazorpayPaymentFailed(
              bookingId: failedBookingId,
              code: error.code,
              message: error.message,
            )
            .catchError((_) {});
      }
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: error.message.isEmpty
            ? 'Unable to complete payment right now.'
            : error.message,
        tone: AppFeedbackTone.error,
      );
    } on FirebaseFunctionsException catch (error) {
      final message = (error.message ?? '').trim();
      final friendlyMessage = message.isNotEmpty
          ? message
          : 'We could not request this booking. Please try again.';
      AppLoader.hide();
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: friendlyMessage,
        tone: AppFeedbackTone.error,
      );
    } catch (error) {
      AppLoader.hide();
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'We could not request this booking. Please try again.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      AppLoader.hide();
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final buttonLabel = _isSubmitting
        ? 'Processing...'
        : 'Proceed to Pay ${_formatCurrency(_finalAmount)}';

    return Scaffold(
      backgroundColor: const Color(0xFFFCF8F5),
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.fromLTRB(
              18,
              topInset + 108,
              18,
              bottomInset + 120,
            ),
            children: [
              _ReviewContent(
                draft: widget.draft,
                serviceAmount: _serviceAmount,
                platformFee: _platformFee,
                selectedOffer: _selectedOffer,
                discountAmount: _discountAmount,
                finalAmount: _finalAmount,
                isPreviewingOffer: _isPreviewingOffer,
                onSelectOffer: _selectOffer,
                onRemoveOffer: _removeOffer,
                acceptedPolicy: _acceptedPolicy,
                onPolicyChanged: (value) {
                  setState(() => _acceptedPolicy = value ?? false);
                },
                onOpenCancellationPolicy: () => PolicyLinkService.openPolicy(
                  context,
                  webUrl: PolicyLinkService.urlForKey(
                    LegalPoliciesCatalog.cancellationPolicy.remoteConfigKey,
                  ),
                  fallbackRoute:
                      LegalPoliciesCatalog.cancellationPolicy.routeName,
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            top: topInset + 10,
            child: Align(
              child: FractionallySizedBox(
                widthFactor: 0.85,
                child: GlassSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  backgroundColor: Colors.white.withValues(alpha: 0.72),
                  blurSigma: 20,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.56),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Payment Review',
                          style: TextStyle(
                            color: AppColors.textDark,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
          child: SizedBox(
            height: AppButtonTokens.height(AppButtonSize.regular),
            child: GradientButton(
              label: buttonLabel,
              onPressed: _acceptedPolicy && !_isSubmitting
                  ? _proceedToPay
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  String _formatCurrency(double amount) {
    final normalized = amount % 1 == 0
        ? amount.toInt().toString()
        : amount.toStringAsFixed(2);
    return '₹$normalized';
  }
}

class _ReviewContent extends StatelessWidget {
  final BookingCheckoutDraft draft;
  final double serviceAmount;
  final double platformFee;
  final ClaimedOffer? selectedOffer;
  final double discountAmount;
  final double finalAmount;
  final bool isPreviewingOffer;
  final VoidCallback onSelectOffer;
  final VoidCallback onRemoveOffer;
  final bool acceptedPolicy;
  final ValueChanged<bool?> onPolicyChanged;
  final VoidCallback onOpenCancellationPolicy;

  const _ReviewContent({
    required this.draft,
    required this.serviceAmount,
    required this.platformFee,
    required this.selectedOffer,
    required this.discountAmount,
    required this.finalAmount,
    required this.isPreviewingOffer,
    required this.onSelectOffer,
    required this.onRemoveOffer,
    required this.acceptedPolicy,
    required this.onPolicyChanged,
    required this.onOpenCancellationPolicy,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CheckoutCard(
          title: 'Booking Summary',
          subtitle: 'Review your service and slot before payment.',
          child: Column(
            children: [
              _InfoRow(
                label: 'Service',
                value: draft.serviceName,
                isPrimaryValue: true,
              ),
              _InfoRow(label: 'Date', value: _formatDate(draft.selectedSlot)),
              _InfoRow(
                label: 'Time',
                value:
                    '${_formatTime(draft.selectedSlot)} - ${_formatTime(draft.selectedSlotEnd)}',
              ),
              _InfoRow(
                label: 'Duration',
                value: '${draft.durationMinutes} mins',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _CheckoutCard(
          title: 'Price Details',
          child: Column(
            children: [
              _OfferSelectorCard(
                selectedOffer: selectedOffer,
                isPreviewingOffer: isPreviewingOffer,
                onSelectOffer: onSelectOffer,
                onRemoveOffer: onRemoveOffer,
              ),
              const SizedBox(height: 18),
              _PaymentRow(
                label: 'Service Amount',
                value: _formatCurrency(serviceAmount),
              ),
              _PaymentRow(
                label: 'Platform & Service Fee (15%)',
                value: _formatCurrency(platformFee),
              ),
              _PaymentRow(
                label: 'Offer Discount',
                value: discountAmount > 0
                    ? '-${_formatCurrency(discountAmount)}'
                    : _formatCurrency(0),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 14),
                child: Divider(height: 1),
              ),
              _PaymentRow(
                label: 'Total Payable',
                value: _formatCurrency(finalAmount),
                isStrong: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _CheckoutCard(
          title: 'Cancellation Policy Summary',
          compact: true,
          child: const Column(
            children: [
              _PolicySummaryLine(text: 'Free cancellation within 30 minutes.'),
              SizedBox(height: 10),
              _PolicySummaryLine(
                text: 'Refund amount depends on cancellation timing.',
              ),
              SizedBox(height: 10),
              _PolicySummaryLine(
                text:
                    'Provider must respond within 24 hours or before 1 hour of service start, whichever comes first.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _CheckoutCard(
          title: 'Terms Confirmation',
          compact: true,
          child: _TermsConfirmationSection(
            acceptedPolicy: acceptedPolicy,
            onPolicyChanged: onPolicyChanged,
            onOpenCancellationPolicy: onOpenCancellationPolicy,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatTime(DateTime date) {
    final hour = date.hour;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${date.minute.toString().padLeft(2, '0')} $suffix';
  }

  String _formatCurrency(double amount) {
    final normalized = amount % 1 == 0
        ? amount.toInt().toString()
        : amount.toStringAsFixed(2);
    return '₹$normalized';
  }
}

class _OfferSelectorCard extends StatelessWidget {
  final ClaimedOffer? selectedOffer;
  final bool isPreviewingOffer;
  final VoidCallback onSelectOffer;
  final VoidCallback onRemoveOffer;

  const _OfferSelectorCard({
    required this.selectedOffer,
    required this.isPreviewingOffer,
    required this.onSelectOffer,
    required this.onRemoveOffer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F3),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Apply Offer',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SecondaryButton(
                label: isPreviewingOffer ? 'Checking...' : 'My Offers',
                size: AppButtonSize.compact,
                expand: false,
                onPressed: isPreviewingOffer ? null : onSelectOffer,
              ),
            ],
          ),
          if (selectedOffer != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedOffer!.couponCode,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          selectedOffer!.discountSummary,
                          style: const TextStyle(
                            color: AppColors.textDark,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onRemoveOffer,
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OfferPickerSheet extends StatelessWidget {
  final OfferService offerService;

  const _OfferPickerSheet({required this.offerService});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFCF8F5),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: StreamBuilder<List<ClaimedOffer>>(
          stream: offerService.watchClaimedOffers(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final offers = (snapshot.data ?? const <ClaimedOffer>[])
                .where((offer) => offer.isAvailable)
                .toList();

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Choose an offer',
                        style: TextStyle(
                          color: AppColors.textDark,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Available claimed offers that can still be used will appear here.',
                  style: TextStyle(
                    color: AppColors.textGrey,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                if (offers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 16, 4, 20),
                    child: Center(
                      child: Text(
                        'No available offers right now.',
                        style: TextStyle(
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w600,
                        ),
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
                        return InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => Navigator.pop(context, offer),
                          child: ClaimedOfferCard(offer: offer),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isStrong;

  const _PaymentRow({
    required this.label,
    required this.value,
    this.isStrong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textGrey,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppColors.textDark,
                fontSize: isStrong ? 18 : 15,
                fontWeight: isStrong ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final bool compact;

  const _CheckoutCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 18 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: const TextStyle(
                color: AppColors.textGrey,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isPrimaryValue;

  const _InfoRow({
    required this.label,
    required this.value,
    this.isPrimaryValue = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textGrey,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppColors.textDark,
                fontWeight: isPrimaryValue ? FontWeight.w800 : FontWeight.w700,
                fontSize: isPrimaryValue ? 16 : 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicySummaryLine extends StatelessWidget {
  final String text;

  const _PolicySummaryLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 6),
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textDark,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _TermsConfirmationSection extends StatelessWidget {
  final bool acceptedPolicy;
  final ValueChanged<bool?> onPolicyChanged;
  final VoidCallback onOpenCancellationPolicy;

  const _TermsConfirmationSection({
    required this.acceptedPolicy,
    required this.onPolicyChanged,
    required this.onOpenCancellationPolicy,
  });

  @override
  Widget build(BuildContext context) {
    const linkColor = Color(0xFF2563EB);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: acceptedPolicy,
          onChanged: onPolicyChanged,
          activeColor: AppColors.primary,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 15,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
                children: [
                  const TextSpan(text: 'I understand and agree to the '),
                  TextSpan(
                    text: 'Cancellation Policy',
                    style: const TextStyle(
                      color: linkColor,
                      fontWeight: FontWeight.w800,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = onOpenCancellationPolicy,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
