import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/navigation/social_app_tab.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../domain/models/booking_flow_models.dart';
import '../widgets/booking_card.dart';
import 'booking_detail_screen.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  BookingContextMode _context = BookingContextMode.receiving;
  BookingTab _receivingTab = BookingTab.upcoming;
  BookingTab _deliveringTab = BookingTab.requests;
  late final Timer _timer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds += 1);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  BookingTab get _activeTab =>
      _context == BookingContextMode.receiving ? _receivingTab : _deliveringTab;

  List<BookingRecord> get _visibleBookings {
    return bookingRecords
        .where((record) => record.context == _context && record.tab == _activeTab)
        .toList();
  }

  String _formatCountdown(int seconds) {
    final remaining = (seconds - _elapsedSeconds).clamp(0, 99999);
    final hours = remaining ~/ 3600;
    final minutes = (remaining % 3600) ~/ 60;
    final secs = remaining % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openBookingDetail(BookingRecord booking) {
    if (booking.detailType == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingDetailScreen(booking: booking),
      ),
    );
  }

  void _handleAction(BookingRecord booking, BookingActionData action) {
    if (action.opensDetail || action.toastMessage == null && booking.detailType != null) {
      _openBookingDetail(booking);
      return;
    }
    if (action.toastMessage != null) {
      _showToast(action.toastMessage!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final topContentPadding = topInset + 96;
    final bottomContentPadding = SocialBottomNav.contentBottomPadding(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: Stack(
        children: [
          Positioned(
            top: -70,
            right: -50,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            top: 140,
            left: -70,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.secondary.withValues(alpha: 0.06),
              ),
            ),
          ),
          // The list is drawn first so the booking content can travel beneath
          // the floating glass header and shared bottom navigation.
          ListView(
            padding: EdgeInsets.fromLTRB(
              18,
              topContentPadding,
              18,
              bottomContentPadding,
            ),
            children: [
              _ContextToggle(
                contextMode: _context,
                onChanged: (contextMode) {
                  setState(() => _context = contextMode);
                },
              ),
              const SizedBox(height: 14),
              _SubtabBar(
                contextMode: _context,
                activeTab: _activeTab,
                onChanged: (tab) {
                  setState(() {
                    if (_context == BookingContextMode.receiving) {
                      _receivingTab = tab;
                    } else {
                      _deliveringTab = tab;
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              if (_visibleBookings.isEmpty)
                const _EmptyState()
              else ...[
                if (_visibleBookings.first.sectionLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _visibleBookings.first.sectionLabel!.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ..._visibleBookings.map((booking) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: BookingCard(
                      booking: booking,
                      countdownText: booking.countdownSeconds != null
                          ? _formatCountdown(booking.countdownSeconds!)
                          : null,
                      onTap: booking.detailType != null
                          ? () => _openBookingDetail(booking)
                          : null,
                      onActionTap: (action) => _handleAction(booking, action),
                    ),
                  );
                }),
              ],
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
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
              child: const Row(
                children: [
                  Expanded(
                    child: Text(
                      'Bookings',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const SocialBottomNav(activeTab: SocialAppTab.profile),
    );
  }
}

class _ContextToggle extends StatelessWidget {
  final BookingContextMode contextMode;
  final ValueChanged<BookingContextMode> onChanged;

  const _ContextToggle({
    required this.contextMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _ContextButton(
            label: 'Receiving',
            isActive: contextMode == BookingContextMode.receiving,
            onTap: () => onChanged(BookingContextMode.receiving),
          ),
          _ContextButton(
            label: 'Delivering',
            isActive: contextMode == BookingContextMode.delivering,
            onTap: () => onChanged(BookingContextMode.delivering),
          ),
        ],
      ),
    );
  }
}

class _ContextButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ContextButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? AppColors.textDark : AppColors.textGrey,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _SubtabBar extends StatelessWidget {
  final BookingContextMode contextMode;
  final BookingTab activeTab;
  final ValueChanged<BookingTab> onChanged;

  const _SubtabBar({
    required this.contextMode,
    required this.activeTab,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = contextMode == BookingContextMode.receiving
        ? const [
            (BookingTab.upcoming, 'Upcoming'),
            (BookingTab.past, 'Past'),
          ]
        : const [
            (BookingTab.requests, 'Requests'),
            (BookingTab.confirmed, 'Confirmed'),
            (BookingTab.pastDeliveries, 'Past'),
          ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: tabs.map((tab) {
          final isActive = tab.$1 == activeTab;
          final hasRequestBadge =
              contextMode == BookingContextMode.delivering &&
              tab.$1 == BookingTab.requests;

          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(tab.$1),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tab.$2,
                          style: TextStyle(
                            color: isActive
                                ? AppColors.primary
                                : AppColors.textGrey,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (hasRequestBadge) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 18,
                            height: 18,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Text(
                              '2',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: 34,
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Color(0xFFFEF0EB),
            child: Icon(Icons.event_busy_outlined, color: AppColors.primary),
          ),
          SizedBox(height: 14),
          Text(
            'No bookings here yet',
            style: TextStyle(
              color: AppColors.textDark,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'New requests and confirmed visits will appear in this tab.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textGrey,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
