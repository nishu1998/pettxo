import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/navigation/social_app_tab.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../data/repositories/booking_repository.dart';
import '../../domain/models/booking_read_model.dart';
import 'canonical_booking_detail_screen.dart';

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
          StreamBuilder<BookingReadModel?>(
            stream: _bookingRepository.watchBookingReadModel(widget.bookingId),
            builder: (context, snapshot) {
              final readModel = snapshot.data;
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  18,
                  topInset + 108,
                  18,
                  bottomInset + 24,
                ),
                children: [
                  _StatusHero(readModel: readModel),
                  const SizedBox(height: 16),
                  _SummaryCard(readModel: readModel),
                  const SizedBox(height: 20),
                  GradientButton(
                    label: 'View Booking',
                    onPressed: () {
                      if (readModel is CanonicalBookingReadModel) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CanonicalBookingDetailScreen(
                              bookingId: widget.bookingId,
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/bookings',
                        (route) => route.isFirst,
                      );
                    },
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
  final BookingReadModel? readModel;

  const _StatusHero({required this.readModel});

  @override
  Widget build(BuildContext context) {
    final booking = readModel is CanonicalBookingReadModel
        ? (readModel as CanonicalBookingReadModel).booking
        : null;
    final graceText = booking == null
        ? 'We are syncing your confirmed booking details.'
        : 'Payment is confirmed. Private contact, OTP, and booking chat now unlock from your Firestore booking state.';

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
}

class _SummaryCard extends StatelessWidget {
  final BookingReadModel? readModel;

  const _SummaryCard({required this.readModel});

  @override
  Widget build(BuildContext context) {
    final canonicalReadModel = readModel is CanonicalBookingReadModel
        ? readModel as CanonicalBookingReadModel
        : null;
    final booking = canonicalReadModel?.booking;
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
                _row('Service', booking.service.serviceTitle),
                _row('Provider', booking.participants.provider.displayName),
                _row('Status', 'Confirmed'),
                _row(
                  'Amount paid',
                  _moneyFromPaise(booking.financials?.customerPaidPaise ?? 0),
                ),
                if (booking.lifecycle.paidAt != null)
                  _row('Paid at', _dateTimeLabel(booking.lifecycle.paidAt!)),
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
