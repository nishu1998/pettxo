import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/app_loader.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../data/repositories/booking_repository.dart';
import '../../domain/models/booking_checkout_draft.dart';

class PaymentReviewScreen extends StatefulWidget {
  final BookingCheckoutDraft draft;

  const PaymentReviewScreen({super.key, required this.draft});

  @override
  State<PaymentReviewScreen> createState() => _PaymentReviewScreenState();
}

class _PaymentReviewScreenState extends State<PaymentReviewScreen> {
  final BookingRepository _bookingRepository = BookingRepository();
  bool _acceptedPolicy = false;
  bool _isSubmitting = false;

  Future<void> _proceedToPay() async {
    if (!_acceptedPolicy || _isSubmitting) return;

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
        amount: widget.draft.totalAmount,
      );

      AppLoader.hide();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Booking requested'),
            content: Text(
              bookingId.isEmpty
                  ? 'Your request was submitted. The provider will accept or reject it soon.'
                  : 'Your request was submitted. Booking ID: $bookingId',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      if (!mounted) return;
      Navigator.popUntil(context, (route) => route.isFirst);
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
  final bool acceptedPolicy;
  final ValueChanged<bool?> onPolicyChanged;

  const _ReviewCard({
    required this.draft,
    required this.acceptedPolicy,
    required this.onPolicyChanged,
  });

  @override
  Widget build(BuildContext context) {
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
          _PaymentRow(label: 'Price', value: '₹${draft.price}'),
          const Divider(height: 28),
          _PaymentRow(
            label: 'Total amount',
            value: '₹${draft.totalAmount}',
            isStrong: true,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4EC),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Text(
              'The provider has up to 24 hours to respond, or until 1 hour before service start, whichever comes first. If they do not respond in time, the request expires automatically.',
              style: TextStyle(
                color: AppColors.textDark,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
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
