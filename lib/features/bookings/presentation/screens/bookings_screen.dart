import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/navigation/social_app_tab.dart';
import '../../../../core/services/app_loader.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../data/repositories/booking_repository.dart';
import '../../domain/models/booking_model.dart';
import '../../domain/models/booking_flow_models.dart';
import '../widgets/booking_card.dart';
import 'booking_detail_screen.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  final BookingRepository _bookingRepository = BookingRepository();
  BookingContextMode _context = BookingContextMode.receiving;
  BookingTab _receivingTab = BookingTab.upcoming;
  BookingTab _deliveringTab = BookingTab.requests;
  late final Timer _timer;
  BookingContextMode? _cachedStreamContext;
  String? _cachedStreamUserId;
  Stream<List<BookingModel>>? _cachedBookingStream;
  String? _actionBookingId;
  String? _actionLabel;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // Rebuild once per second so request-expiry countdowns stay live while
      // Firestore streams continue to own the actual booking data.
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  BookingTab get _activeTab =>
      _context == BookingContextMode.receiving ? _receivingTab : _deliveringTab;

  Stream<List<BookingModel>> _bookingStreamFor(String userId) {
    if (_cachedBookingStream != null &&
        _cachedStreamContext == _context &&
        _cachedStreamUserId == userId) {
      return _cachedBookingStream!;
    }

    _cachedStreamContext = _context;
    _cachedStreamUserId = userId;
    _cachedBookingStream = _context == BookingContextMode.receiving
        ? _bookingRepository.watchReceivingBookings(userId)
        : _bookingRepository.watchDeliveringBookings(userId);
    return _cachedBookingStream!;
  }

  List<BookingModel> _bookingsForActiveTab(List<BookingModel> bookings) {
    if (_context == BookingContextMode.receiving) {
      return _activeTab == BookingTab.upcoming
          ? _bookingRepository.receivingUpcoming(bookings)
          : _bookingRepository.receivingPast(bookings);
    }

    return switch (_activeTab) {
      BookingTab.requests => _bookingRepository.deliveringRequests(bookings),
      BookingTab.confirmed => _bookingRepository.deliveringConfirmed(bookings),
      BookingTab.pastDeliveries => _bookingRepository.deliveringPast(bookings),
      _ => const <BookingModel>[],
    };
  }

  String _sectionLabelFor(int count) {
    final suffix = count == 1 ? '' : 's';
    return switch (_activeTab) {
      BookingTab.upcoming => '$count upcoming',
      BookingTab.past => 'Past bookings',
      BookingTab.requests => '$count pending request$suffix',
      BookingTab.confirmed => '$count confirmed',
      BookingTab.pastDeliveries => 'Past deliveries',
    };
  }

  String _formatCountdown(int seconds) {
    final remaining = seconds.clamp(0, 99999);
    final hours = remaining ~/ 3600;
    final minutes = (remaining % 3600) ~/ 60;
    final secs = remaining % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _showToast(
    String message, {
    AppSnackbarTone tone = AppSnackbarTone.info,
  }) {
    switch (tone) {
      case AppSnackbarTone.success:
        AppSnackbar.showSuccess(context, message);
        break;
      case AppSnackbarTone.error:
        AppSnackbar.showError(context, message);
        break;
      case AppSnackbarTone.warning:
        AppSnackbar.showWarning(context, message);
        break;
      case AppSnackbarTone.info:
        AppSnackbar.showInfo(context, message);
        break;
    }
  }

  void _openBookingDetail(BookingRecord booking) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingDetailScreen(
          bookingId: booking.id,
          contextMode: booking.context,
          fallbackBooking: booking,
        ),
      ),
    );
  }

  Future<void> _handleAction(
    BookingRecord booking,
    BookingActionData action,
  ) async {
    if (action.opensDetail ||
        action.toastMessage == null && booking.detailType != null) {
      _openBookingDetail(booking);
      return;
    }

    final normalizedLabel = action.label.toLowerCase().trim();
    if (normalizedLabel == 'accept' || normalizedLabel == 'reject') {
      await _runRequestAction(
        bookingId: booking.id,
        actionLabel: action.label,
        accept: normalizedLabel == 'accept',
      );
      return;
    }

    if (action.toastMessage != null) {
      _showToast(action.toastMessage!);
    }
  }

  Future<void> _runRequestAction({
    required String bookingId,
    required String actionLabel,
    required bool accept,
  }) async {
    if (_actionBookingId != null) return;

    setState(() {
      _actionBookingId = bookingId;
      _actionLabel = actionLabel;
    });
    AppLoader.showWithMessage(
      accept ? 'Accepting booking request...' : 'Rejecting booking request...',
    );

    try {
      if (accept) {
        await _bookingRepository.acceptBookingRequest(bookingId: bookingId);
        _showToast(
          'Booking accepted. Pet parent notified.',
          tone: AppSnackbarTone.success,
        );
      } else {
        await _bookingRepository.rejectBookingRequest(
          bookingId: bookingId,
          reason: 'Rejected by provider',
        );
        _showToast('Booking rejected.', tone: AppSnackbarTone.warning);
      }
    } catch (error) {
      _showToast(_friendlyActionError(error), tone: AppSnackbarTone.error);
    } finally {
      AppLoader.hide();
      if (mounted) {
        setState(() {
          _actionBookingId = null;
          _actionLabel = null;
        });
      }
    }
  }

  String _friendlyActionError(Object error) {
    final text = error.toString();
    if (text.contains('failed-precondition')) {
      return 'This request can no longer be changed.';
    }
    if (text.contains('permission-denied')) {
      return 'Only the service owner can update this request.';
    }
    if (text.contains('not-found')) {
      return 'Booking request not found.';
    }
    return 'Could not update booking. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final topContentPadding = topInset + 96;
    final bottomContentPadding = SocialBottomNav.contentBottomPadding(context);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

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
              if (currentUserId == null)
                _BookingSectionShell(
                  subtabBar: _SubtabBar(
                    contextMode: _context,
                    activeTab: _activeTab,
                    requestCount: 0,
                    onChanged: _handleTabChanged,
                  ),
                  child: const _EmptyState(
                    icon: Icons.lock_outline_rounded,
                    title: 'Sign in to view bookings',
                    subtitle:
                        'Your requested and received bookings will appear here after sign in.',
                  ),
                )
              else
                StreamBuilder<List<BookingModel>>(
                  stream: _bookingStreamFor(currentUserId),
                  builder: (context, snapshot) {
                    final allBookings = snapshot.data ?? const <BookingModel>[];
                    final requestCount = _bookingRepository
                        .deliveringRequests(allBookings)
                        .length;

                    if (snapshot.hasError) {
                      return _BookingSectionShell(
                        subtabBar: _SubtabBar(
                          contextMode: _context,
                          activeTab: _activeTab,
                          requestCount: requestCount,
                          onChanged: _handleTabChanged,
                        ),
                        child: _EmptyState(
                          icon: Icons.cloud_off_rounded,
                          title: 'Could not load bookings',
                          subtitle: snapshot.error.toString(),
                        ),
                      );
                    }

                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return _BookingSectionShell(
                        subtabBar: _SubtabBar(
                          contextMode: _context,
                          activeTab: _activeTab,
                          requestCount: requestCount,
                          onChanged: _handleTabChanged,
                        ),
                        child: const _LoadingState(),
                      );
                    }

                    final visibleBookings = _bookingsForActiveTab(allBookings);
                    final records = visibleBookings
                        .map((booking) => booking.toBookingRecord(_context))
                        .toList();

                    return _BookingSectionShell(
                      subtabBar: _SubtabBar(
                        contextMode: _context,
                        activeTab: _activeTab,
                        requestCount: requestCount,
                        onChanged: _handleTabChanged,
                      ),
                      child: records.isEmpty
                          ? const _EmptyState()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    _sectionLabelFor(
                                      records.length,
                                    ).toUpperCase(),
                                    style: const TextStyle(
                                      color: AppColors.textGrey,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ),
                                ...records.map((booking) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: BookingCard(
                                      booking: booking,
                                      loadingActionLabel:
                                          _actionBookingId == booking.id
                                          ? _actionLabel
                                          : null,
                                      countdownText:
                                          booking.countdownSeconds != null
                                          ? _formatCountdown(
                                              booking.countdownSeconds!,
                                            )
                                          : null,
                                      onTap: () => _openBookingDetail(booking),
                                      onActionTap: (action) =>
                                          _handleAction(booking, action),
                                    ),
                                  );
                                }),
                              ],
                            ),
                    );
                  },
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
      bottomNavigationBar: const SocialBottomNav(
        activeTab: SocialAppTab.profile,
      ),
    );
  }

  void _handleTabChanged(BookingTab tab) {
    setState(() {
      if (_context == BookingContextMode.receiving) {
        _receivingTab = tab;
      } else {
        _deliveringTab = tab;
      }
    });
  }
}

class _BookingSectionShell extends StatelessWidget {
  final Widget subtabBar;
  final Widget child;

  const _BookingSectionShell({required this.subtabBar, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [subtabBar, const SizedBox(height: 16), child],
    );
  }
}

class _ContextToggle extends StatelessWidget {
  final BookingContextMode contextMode;
  final ValueChanged<BookingContextMode> onChanged;

  const _ContextToggle({required this.contextMode, required this.onChanged});

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
  final int requestCount;
  final ValueChanged<BookingTab> onChanged;

  const _SubtabBar({
    required this.contextMode,
    required this.activeTab,
    required this.requestCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = contextMode == BookingContextMode.receiving
        ? const [(BookingTab.upcoming, 'Upcoming'), (BookingTab.past, 'Past')]
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
              tab.$1 == BookingTab.requests &&
              requestCount > 0;

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
                            child: Text(
                              requestCount > 9 ? '9+' : '$requestCount',
                              style: const TextStyle(
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
                        color: isActive
                            ? AppColors.primary
                            : Colors.transparent,
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
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    this.icon = Icons.event_busy_outlined,
    this.title = 'No bookings here yet',
    this.subtitle =
        'New requests and confirmed visits will appear in this tab.',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: const Color(0xFFFEF0EB),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
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

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(height: 14),
          Text(
            'Loading bookings...',
            style: TextStyle(
              color: AppColors.textGrey,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
