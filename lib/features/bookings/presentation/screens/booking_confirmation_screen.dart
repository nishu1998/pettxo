import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/navigation/social_app_tab.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../data/repositories/booking_repository.dart';
import '../../domain/models/booking_model.dart';

class BookingConfirmationScreen extends StatefulWidget {
  final String bookingId;

  const BookingConfirmationScreen({super.key, required this.bookingId});

  @override
  State<BookingConfirmationScreen> createState() =>
      _BookingConfirmationScreenState();
}

class _BookingConfirmationScreenState extends State<BookingConfirmationScreen> {
  final BookingRepository _bookingRepository = BookingRepository();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          StreamBuilder<BookingModel?>(
            stream: _bookingRepository.watchBookingById(widget.bookingId),
            builder: (context, snapshot) {
              final booking = snapshot.data;
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  18,
                  topInset + 108,
                  18,
                  bottomInset + 24,
                ),
                children: [
                  _StatusHero(booking: booking),
                  const SizedBox(height: 16),
                  _SummaryCard(booking: booking),
                  const SizedBox(height: 20),
                  GradientButton(
                    label: 'View Booking',
                    onPressed: () => Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/bookings',
                      (route) => route.isFirst,
                    ),
                  ),
                ],
              );
            },
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
                          onPressed: () => Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/bookings',
                            (route) => route.isFirst,
                          ),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Booking Confirmed',
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
      bottomNavigationBar: const SocialBottomNav(
        activeTab: SocialAppTab.profile,
      ),
    );
  }
}

class _StatusHero extends StatelessWidget {
  final BookingModel? booking;

  const _StatusHero({required this.booking});

  @override
  Widget build(BuildContext context) {
    final remaining = booking?.remainingGraceDuration;
    final graceText = remaining == null
        ? 'Full refund window will appear as soon as the booking syncs.'
        : remaining == Duration.zero
        ? 'The full-refund grace window has ended. Cancellation charges now apply.'
        : 'Full refund available for ${_formatDuration(remaining)}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF4EC), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your booking request is in.',
            style: TextStyle(
              color: AppColors.textDark,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            graceText,
            style: const TextStyle(
              color: AppColors.textDark,
              height: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _SummaryCard extends StatelessWidget {
  final BookingModel? booking;

  const _SummaryCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: booking == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('Service', booking!.serviceName),
                _row('Provider', booking!.providerName),
                _row('Status', booking!._statusLabelForUi),
                _row('Amount paid', _moneyFromPaise(booking!.grossAmountPaise)),
                if (booking!.graceWindowEndsAt != null)
                  _row(
                    'Full-refund until',
                    _dateTimeLabel(booking!.graceWindowEndsAt!),
                  ),
              ],
            ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textGrey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _dateTimeLabel(DateTime value) {
    final local = value.toLocal();
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    return '${local.day}/${local.month}/${local.year} $hour:${local.minute.toString().padLeft(2, '0')} $suffix';
  }

  static String _moneyFromPaise(int paise) {
    final rupees = paise / 100;
    return paise % 100 == 0
        ? '₹${rupees.toStringAsFixed(0)}'
        : '₹${rupees.toStringAsFixed(2)}';
  }
}

extension on BookingModel {
  String get _statusLabelForUi {
    if (isRequested) return 'Awaiting provider response';
    if (isAccepted) return 'Confirmed';
    if (isCompleted) return 'Completed';
    if (isNoShow) return 'No-show';
    if (isCancelled) return 'Cancelled';
    return status;
  }
}
