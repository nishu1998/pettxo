import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/app_loader.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../offers/data/services/offer_service.dart';
import '../../../offers/domain/models/claimed_offer.dart';
import '../../../offers/presentation/widgets/claimed_offer_card.dart';
import '../../../restrictions/data/services/user_restriction_service.dart';
import '../../data/repositories/booking_repository.dart';
import '../../domain/models/booking_checkout_draft.dart';
import 'booking_confirmation_screen.dart';

class PaymentReviewScreen extends StatefulWidget {
  final BookingCheckoutDraft draft;

  const PaymentReviewScreen({super.key, required this.draft});

  @override
  State<PaymentReviewScreen> createState() => _PaymentReviewScreenState();
}

class _PaymentReviewScreenState extends State<PaymentReviewScreen> {
  final BookingRepository _bookingRepository = BookingRepository();
  final OfferService _offerService = OfferService();
  bool _acceptedPolicy = false;
  bool _isSubmitting = false;
  bool _isPreviewingOffer = false;
  ClaimedOffer? _selectedOffer;
  double _discountAmount = 0;
  double? _previewedFinalAmount;

  double get _subtotal => widget.draft.totalAmount.toDouble();

  double get _finalAmount => _previewedFinalAmount ?? _subtotal;

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
        bookingAmount: _subtotal,
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
        _previewedFinalAmount = preview.finalAmount;
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
      _previewedFinalAmount = null;
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
    AppLoader.showWithMessage('Sending booking request...');

    try {
      // Payment gateway is intentionally mocked for now. Booking creation still
      // goes through Cloud Functions so the app does not bypass backend rules.
      await Future<void>.delayed(const Duration(milliseconds: 650));
      final bookingId = await _bookingRepository.requestBooking(
        serviceId: widget.draft.serviceId,
        slotId: widget.draft.slotId,
        userId: uid,
        amount: _finalAmount.round(),
        claimedOfferId: _selectedOffer?.id,
      );

      AppLoader.hide();
      if (!mounted) return;
      if (bookingId.isEmpty) {
        AppFeedback.show(
          context,
          message: 'Your booking was submitted, but we could not open the confirmation screen yet.',
          tone: AppFeedbackTone.warning,
        );
        Navigator.popUntil(context, (route) => route.isFirst);
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => BookingConfirmationScreen(bookingId: bookingId),
        ),
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
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFFCF8F5),
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.fromLTRB(
              18,
              topInset + 108,
              18,
              bottomInset + 24,
            ),
            children: [
              _ReviewCard(
                draft: widget.draft,
                selectedOffer: _selectedOffer,
                subtotal: _subtotal,
                discountAmount: _discountAmount,
                finalAmount: _finalAmount,
                isPreviewingOffer: _isPreviewingOffer,
                onSelectOffer: _selectOffer,
                onRemoveOffer: _removeOffer,
                acceptedPolicy: _acceptedPolicy,
                onPolicyChanged: (value) {
                  setState(() => _acceptedPolicy = value ?? false);
                },
              ),
              const SizedBox(height: 22),
              GradientButton(
                label: _isSubmitting ? 'Processing...' : 'Proceed to Pay',
                onPressed: _acceptedPolicy && !_isSubmitting
                    ? _proceedToPay
                    : null,
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            top: topInset + 10,
            child: GlassSurface(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              borderRadius: BorderRadius.circular(24),
              backgroundColor: Colors.white.withValues(alpha: 0.72),
              blurSigma: 20,
              border: Border.all(color: Colors.white.withValues(alpha: 0.62)),
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
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final BookingCheckoutDraft draft;
  final ClaimedOffer? selectedOffer;
  final double subtotal;
  final double discountAmount;
  final double finalAmount;
  final bool isPreviewingOffer;
  final VoidCallback onSelectOffer;
  final VoidCallback onRemoveOffer;
  final bool acceptedPolicy;
  final ValueChanged<bool?> onPolicyChanged;

  const _ReviewCard({
    required this.draft,
    required this.selectedOffer,
    required this.subtotal,
    required this.discountAmount,
    required this.finalAmount,
    required this.isPreviewingOffer,
    required this.onSelectOffer,
    required this.onRemoveOffer,
    required this.acceptedPolicy,
    required this.onPolicyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final graceWindowMinutes = _graceWindowMinutesForSlot(draft.selectedSlot);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Review your booking',
            style: TextStyle(
              color: AppColors.textDark,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          _PaymentRow(label: 'Service', value: draft.serviceName),
          _PaymentRow(
            label: 'Date & time',
            value:
                '${_formatDateTime(draft.selectedSlot)} - ${_formatTime(draft.selectedSlotEnd)}',
          ),
          const SizedBox(height: 18),
          _OfferSelectorCard(
            selectedOffer: selectedOffer,
            isPreviewingOffer: isPreviewingOffer,
            onSelectOffer: onSelectOffer,
            onRemoveOffer: onRemoveOffer,
          ),
          const Divider(height: 28),
          _PaymentRow(label: 'Subtotal', value: _formatCurrency(subtotal)),
          if (selectedOffer != null)
            _PaymentRow(
              label: 'Discount',
              value: '-${_formatCurrency(discountAmount)}',
            ),
          _PaymentRow(
            label: 'Total amount',
            value: _formatCurrency(finalAmount),
            isStrong: true,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4EC),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You can cancel within $graceWindowMinutes minutes for a full refund.',
                  style: const TextStyle(
                    color: AppColors.textDark,
                    height: 1.45,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'After that, refunds decrease based on timing.',
                  style: TextStyle(
                    color: AppColors.textDark,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'More than 24h: 90% refund\n24h to 12h: 50% refund\n12h to 6h: 35% refund\n6h to 2h: 20% refund\nLess than 2h: no refund',
                  style: TextStyle(
                    color: AppColors.textGrey,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'The provider has up to 24 hours to respond, or until 1 hour before service start, whichever comes first. If they do not respond in time, the request expires automatically.',
                  style: TextStyle(
                    color: AppColors.textDark,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: acceptedPolicy,
            onChanged: onPolicyChanged,
            activeColor: AppColors.primary,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'I understand the cancellation policy',
              style: TextStyle(
                color: AppColors.textDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime date) {
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
    final hour = date.hour;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '${date.day} ${months[date.month - 1]}, $displayHour:${date.minute.toString().padLeft(2, '0')} $suffix';
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

  static int _graceWindowMinutesForSlot(DateTime slotStart) {
    final now = DateTime.now();
    final hoursUntilService = slotStart.difference(now).inHours;
    if (hoursUntilService < 6) return 10;
    if (hoursUntilService < 12) return 15;
    return 30;
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
