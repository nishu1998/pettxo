import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/navigation/social_app_tab.dart';
import '../../../../core/services/app_loader.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../../profile/presentation/screens/service_detail_screen.dart';
import '../../data/repositories/booking_repository.dart';
import '../../domain/models/booking_document_v3.dart';
import '../../domain/models/booking_flow_models.dart';
import '../../domain/models/booking_read_model.dart';
import '../../domain/models/booking_v3_models.dart';
import '../../domain/models/canonical_booking_request_models.dart';
import '../../domain/models/canonical_provider_booking_request_view.dart';
import '../navigation/booking_navigation_resolver.dart';
import '../../../services/data/repositories/services_repository.dart';
import '../widgets/canonical_provider_request_card.dart';

typedef BookingStreamBuilder =
    Stream<List<BookingReadModel>> Function(
      String userId,
      BookingContextMode contextMode,
    );

typedef ProviderRequestStreamBuilder =
    Stream<List<CanonicalProviderBookingRequestView>> Function(String userId);

typedef BookingRequestOpener =
    Future<void> Function(BuildContext context, BookingOpenRequest request);

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({
    super.key,
    this.bookingRepository,
    this.servicesRepository,
    this.bookingNavigationResolver,
    this.currentUserIdOverride,
    this.bookingStreamBuilder,
    this.providerRequestStreamBuilder,
    this.bookingRequestOpener,
    this.useLiveIdentity = true,
  });

  final BookingRepository? bookingRepository;
  final ServicesRepository? servicesRepository;
  final BookingNavigationResolver? bookingNavigationResolver;
  final String? currentUserIdOverride;
  final BookingStreamBuilder? bookingStreamBuilder;
  final ProviderRequestStreamBuilder? providerRequestStreamBuilder;
  final BookingRequestOpener? bookingRequestOpener;
  final bool useLiveIdentity;

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  late final BookingRepository _bookingRepository =
      widget.bookingRepository ?? BookingRepository();
  late final ServicesRepository _servicesRepository =
      widget.servicesRepository ?? ServicesRepository();
  late final BookingNavigationResolver _bookingNavigationResolver =
      widget.bookingNavigationResolver ?? BookingNavigationResolver();
  BookingContextMode _context = BookingContextMode.receiving;
  BookingTab _receivingTab = BookingTab.upcoming;
  BookingTab _deliveringTab = BookingTab.requests;
  late final Timer _timer;
  BookingContextMode? _cachedReadModelContext;
  String? _cachedReadModelUserId;
  Stream<List<BookingReadModel>>? _cachedReadModelStream;
  String? _canonicalActionBookingId;
  String? _canonicalActionType;

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

  Stream<List<BookingReadModel>> _bookingReadModelStreamFor(String userId) {
    if (widget.bookingStreamBuilder != null) {
      return widget.bookingStreamBuilder!(userId, _context);
    }
    if (_cachedReadModelStream != null &&
        _cachedReadModelContext == _context &&
        _cachedReadModelUserId == userId) {
      return _cachedReadModelStream!;
    }

    _cachedReadModelContext = _context;
    _cachedReadModelUserId = userId;
    _cachedReadModelStream = _context == BookingContextMode.receiving
        ? _bookingRepository.watchReceivingBookingReadModels(userId)
        : _bookingRepository.watchDeliveringBookingReadModels(userId);
    return _cachedReadModelStream!;
  }

  List<CanonicalBookingReadModel> _canonicalBookingsForActiveTab(
    List<BookingReadModel> bookings,
  ) {
    final canonical = bookings.whereType<CanonicalBookingReadModel>();
    final filtered = canonical
        .where((entry) {
          final state = entry.booking.state;
          if (_context == BookingContextMode.receiving) {
            return _activeTab == BookingTab.upcoming
                ? !_isPastCustomerState(state)
                : _isPastCustomerState(state);
          }

          return switch (_activeTab) {
            BookingTab.requests =>
              state == CanonicalBookingStateV3.requested ||
                  state == CanonicalBookingStateV3.pendingProvider,
            BookingTab.confirmed => _isProviderActiveState(state),
            BookingTab.pastDeliveries => _isPastProviderState(state),
            _ => false,
          };
        })
        .toList(growable: false);

    return filtered..sort((left, right) {
      final leftTime =
          left.booking.scheduledStartAt ?? left.booking.serviceAnchorAt;
      final rightTime =
          right.booking.scheduledStartAt ?? right.booking.serviceAnchorAt;
      return rightTime.compareTo(leftTime);
    });
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

  Future<void> _openCanonicalProviderRequest(
    CanonicalProviderBookingRequestView request,
  ) async {
    final openRequest = BookingNavigationResolver.openRequestForExternalBooking(
      bookingId: request.bookingId,
      contextMode: BookingContextMode.delivering,
    );
    final opener = widget.bookingRequestOpener;
    if (opener != null) {
      await opener(context, openRequest);
      return;
    }
    await _bookingNavigationResolver.openBookingRequest(context, openRequest);
  }

  Future<void> _openCanonicalBooking(String bookingId) async {
    final openRequest = BookingNavigationResolver.openRequestForExternalBooking(
      bookingId: bookingId,
      contextMode: _context,
    );
    final opener = widget.bookingRequestOpener;
    if (opener != null) {
      await opener(context, openRequest);
      return;
    }
    await _bookingNavigationResolver.openBookingRequest(context, openRequest);
  }

  Future<void> _openCanonicalRebookService(
    CanonicalBookingDocumentV3 booking,
  ) async {
    final serviceId = booking.serviceId.trim();
    if (serviceId.isEmpty) {
      _showToast(
        'This service is not available to book again right now.',
        tone: AppSnackbarTone.warning,
      );
      return;
    }

    AppLoader.showWithMessage('Loading service details...');
    try {
      final service = await _servicesRepository.fetchServiceById(serviceId);
      AppLoader.hide();
      if (!mounted) return;

      if (service == null || service.isDeleted || !service.isActive) {
        _showToast(
          'This service is no longer available.',
          tone: AppSnackbarTone.warning,
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ServiceDetailScreen(
            service: service.toProfileListing(),
            showRebookHint: true,
            suggestedSlotStartAt: booking.scheduledStartAt,
          ),
        ),
      );
    } catch (_) {
      AppLoader.hide();
      if (!mounted) return;
      _showToast(
        'Could not open this service right now.',
        tone: AppSnackbarTone.error,
      );
    }
  }

  String? _canonicalCountdownText(CanonicalProviderBookingRequestView request) {
    if (!request.isPendingProvider || request.acceptDeadlineAt == null) {
      return null;
    }
    final remaining = request.acceptDeadlineAt!
        .difference(DateTime.now())
        .inSeconds;
    if (remaining <= 0) return '00:00';
    return _formatCountdown(remaining);
  }

  bool _isCanonicalAccepting(CanonicalProviderBookingRequestView request) {
    return _canonicalActionBookingId == request.bookingId &&
        _canonicalActionType == 'accept';
  }

  bool _isCanonicalDeclining(CanonicalProviderBookingRequestView request) {
    return _canonicalActionBookingId == request.bookingId &&
        _canonicalActionType == 'decline';
  }

  Future<void> _runCanonicalProviderAction({
    required CanonicalProviderBookingRequestView request,
    required bool accept,
  }) async {
    if (_canonicalActionBookingId != null) return;

    setState(() {
      _canonicalActionBookingId = request.bookingId;
      _canonicalActionType = accept ? 'accept' : 'decline';
    });

    try {
      if (accept) {
        await _bookingRepository.acceptBookingRequestV3(
          bookingId: request.bookingId,
        );
        _showToast(
          'Request accepted. The customer now has 60 minutes to pay.',
          tone: AppSnackbarTone.success,
        );
      } else {
        await _bookingRepository.declineBookingRequestV3(
          bookingId: request.bookingId,
        );
        _showToast('Request declined.', tone: AppSnackbarTone.info);
      }
    } on CanonicalBookingRequestException catch (error) {
      _showToast(
        _friendlyCanonicalActionError(error),
        tone: AppSnackbarTone.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _canonicalActionBookingId = null;
          _canonicalActionType = null;
        });
      }
    }
  }

  String _friendlyCanonicalActionError(CanonicalBookingRequestException error) {
    switch (error.code) {
      case CanonicalBookingRequestFailureCode.canonicalBookingDisabled:
        return 'This canonical request action is not enabled right now.';
      case CanonicalBookingRequestFailureCode.permissionDenied:
        return 'Only the assigned provider can update this request.';
      case CanonicalBookingRequestFailureCode.runwayNotSatisfied:
        return 'The response window already ended for this request.';
      case CanonicalBookingRequestFailureCode.invalidSchedule:
        return 'This request already moved to a different state.';
      case CanonicalBookingRequestFailureCode.unauthenticated:
        return 'Please sign in again and try once more.';
      default:
        return error.message.trim().isNotEmpty
            ? error.message.trim()
            : 'Could not update this canonical request right now.';
    }
  }

  Widget _buildCanonicalRuntimeBody(String currentUserId) {
    return StreamBuilder<List<BookingReadModel>>(
      stream: _bookingReadModelStreamFor(currentUserId),
      builder: (context, snapshot) {
        final allBookings = snapshot.data ?? const <BookingReadModel>[];
        final canonicalBookings = _canonicalBookingsForActiveTab(allBookings);
        final canonicalRequestCount = allBookings
            .whereType<CanonicalBookingReadModel>()
            .where((entry) {
              final state = entry.booking.state;
              return state == CanonicalBookingStateV3.requested ||
                  state == CanonicalBookingStateV3.pendingProvider;
            })
            .length;

        if (snapshot.hasError) {
          return _wrapSwipeNavigation(
            _BookingSectionShell(
              subtabBar: _SubtabBar(
                contextMode: _context,
                activeTab: _activeTab,
                requestCount: canonicalRequestCount,
                onChanged: _handleTabChanged,
              ),
              child: _EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Could not load bookings',
                subtitle: snapshot.error.toString(),
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _wrapSwipeNavigation(
            _BookingSectionShell(
              subtabBar: _SubtabBar(
                contextMode: _context,
                activeTab: _activeTab,
                requestCount: canonicalRequestCount,
                onChanged: _handleTabChanged,
              ),
              child: const _LoadingState(),
            ),
          );
        }

        return StreamBuilder<List<CanonicalProviderBookingRequestView>>(
          stream: _context == BookingContextMode.delivering
              ? (widget.providerRequestStreamBuilder?.call(currentUserId) ??
                    _bookingRepository.watchProviderCanonicalRequests(
                      currentUserId,
                    ))
              : Stream.value(const []),
          builder: (context, canonicalSnapshot) {
            final canonicalRequests = _activeTab == BookingTab.requests
                ? canonicalSnapshot.data ??
                      const <CanonicalProviderBookingRequestView>[]
                : const <CanonicalProviderBookingRequestView>[];

            final bodyChildren = _activeTab == BookingTab.requests
                ? _buildCanonicalRequestOnlySections(canonicalRequests)
                : _buildCanonicalBookingSections(canonicalBookings);

            return _wrapSwipeNavigation(
              _BookingSectionShell(
                subtabBar: _SubtabBar(
                  contextMode: _context,
                  activeTab: _activeTab,
                  requestCount: canonicalRequests.length,
                  onChanged: _handleTabChanged,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: bodyChildren,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _wrapSwipeNavigation(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 180) return;
        _handleTabSwipe(velocity < 0);
      },
      child: child,
    );
  }

  List<Widget> _buildCanonicalRequestOnlySections(
    List<CanonicalProviderBookingRequestView> canonicalRequests,
  ) {
    if (canonicalRequests.isEmpty) {
      return const [_EmptyState()];
    }

    return [
      const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text(
          'REQUESTS',
          style: TextStyle(
            color: Color(0xFF908476),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
          ),
        ),
      ),
      ...canonicalRequests.map(
        (request) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: CanonicalProviderRequestCard(
            request: request,
            countdownText: _canonicalCountdownText(request),
            isAccepting: _isCanonicalAccepting(request),
            isDeclining: _isCanonicalDeclining(request),
            onTap: () => _openCanonicalProviderRequest(request),
            onAccept: request.isPendingProvider
                ? () => _runCanonicalProviderAction(
                    request: request,
                    accept: true,
                  )
                : null,
            onDecline: request.isPendingProvider
                ? () => _runCanonicalProviderAction(
                    request: request,
                    accept: false,
                  )
                : null,
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildCanonicalBookingSections(
    List<CanonicalBookingReadModel> canonicalBookings,
  ) {
    if (canonicalBookings.isEmpty) {
      return const [_EmptyState()];
    }

    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          _sectionLabelFor(canonicalBookings.length).toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF908476),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
          ),
        ),
      ),
      ...canonicalBookings.map(
        (booking) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _CanonicalBookingListCard(
            booking: booking.booking,
            contextMode: _context,
            onTap: () => _openCanonicalBooking(booking.bookingId),
            onBookAgain:
                _context == BookingContextMode.receiving &&
                    _activeTab == BookingTab.past
                ? () => _openCanonicalRebookService(booking.booking)
                : null,
          ),
        ),
      ),
    ];
  }

  List<BookingTab> _tabsForContext(BookingContextMode contextMode) {
    return contextMode == BookingContextMode.receiving
        ? const [BookingTab.upcoming, BookingTab.past]
        : const [
            BookingTab.requests,
            BookingTab.confirmed,
            BookingTab.pastDeliveries,
          ];
  }

  void _handleTabSwipe(bool forward) {
    final tabs = _tabsForContext(_context);
    final currentIndex = tabs.indexOf(_activeTab);
    if (currentIndex == -1) return;

    final nextIndex = forward ? currentIndex + 1 : currentIndex - 1;
    if (nextIndex < 0 || nextIndex >= tabs.length) return;
    _handleTabChanged(tabs[nextIndex]);
  }

  bool _isPastCustomerState(CanonicalBookingStateV3 state) {
    return state == CanonicalBookingStateV3.completedPendingReview ||
        state == CanonicalBookingStateV3.completedFinal ||
        state == CanonicalBookingStateV3.cancelledByParent ||
        state == CanonicalBookingStateV3.cancelled ||
        state == CanonicalBookingStateV3.declined ||
        state == CanonicalBookingStateV3.expired ||
        state == CanonicalBookingStateV3.paymentExpired ||
        state == CanonicalBookingStateV3.noShow ||
        state == CanonicalBookingStateV3.disputed;
  }

  bool _isProviderActiveState(CanonicalBookingStateV3 state) {
    return state == CanonicalBookingStateV3.acceptedAwaitingPayment ||
        state == CanonicalBookingStateV3.confirmed ||
        state == CanonicalBookingStateV3.inProgress ||
        state == CanonicalBookingStateV3.completedPendingReview;
  }

  bool _isPastProviderState(CanonicalBookingStateV3 state) {
    return !_isProviderActiveState(state) &&
        state != CanonicalBookingStateV3.requested &&
        state != CanonicalBookingStateV3.pendingProvider;
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final topContentPadding = topInset + 118;
    final bottomContentPadding = SocialBottomNav.contentBottomPadding(context);
    final currentUserId =
        widget.currentUserIdOverride ?? FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFFBF6EF),
      extendBody: true,
      body: Stack(
        children: [
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
              const SizedBox(height: 8),
              if (currentUserId == null)
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity.abs() < 180) return;
                    _handleTabSwipe(velocity < 0);
                  },
                  child: _BookingSectionShell(
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
                  ),
                )
              else
                _buildCanonicalRuntimeBody(currentUserId),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: GlassSurface(
              padding: EdgeInsets.fromLTRB(18, topInset + 10, 18, 12),
              borderRadius: BorderRadius.zero,
              backgroundColor: Colors.white.withValues(alpha: 0.72),
              blurSigma: 22,
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.58)),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.84),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Bookings',
                      style: TextStyle(
                        fontSize: 24,
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
    return GlassSurface(
      padding: const EdgeInsets.all(8),
      borderRadius: BorderRadius.circular(24),
      backgroundColor: Colors.white.withValues(alpha: 0.92),
      blurSigma: 16,
      border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
      boxShadow: const [],
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F7F4),
          borderRadius: BorderRadius.circular(20),
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
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            gradient: isActive
                ? const LinearGradient(
                    colors: [Color(0xFFFF5A1F), Color(0xFFE94D17)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  )
                : null,
            color: isActive ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? Colors.white : const Color(0xFF8E8479),
              fontWeight: FontWeight.w800,
              fontSize: 16,
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: tabs.map((tab) {
          final isActive = tab.$1 == activeTab;
          final hasRequestBadge =
              contextMode == BookingContextMode.delivering &&
              tab.$1 == BookingTab.requests &&
              requestCount > 0;

          return Flexible(
            child: GestureDetector(
              onTap: () => onChanged(tab.$1),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            tab.$2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isActive
                                  ? AppColors.primary
                                  : const Color(0xFF8E8479),
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (hasRequestBadge) ...[
                          const SizedBox(width: 6),
                          Container(
                            constraints: const BoxConstraints(minWidth: 18),
                            height: 18,
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              requestCount > 9 ? '9+' : '$requestCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      width: isActive ? 40 : 0,
                      height: 4,
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

class _CanonicalBookingListCard extends StatelessWidget {
  const _CanonicalBookingListCard({
    required this.booking,
    required this.contextMode,
    required this.onTap,
    this.onBookAgain,
  });

  final CanonicalBookingDocumentV3 booking;
  final BookingContextMode contextMode;
  final VoidCallback onTap;
  final VoidCallback? onBookAgain;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking.service.serviceTitle,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        contextMode == BookingContextMode.receiving
                            ? booking.participants.provider.displayName
                            : '${booking.participants.parent.displayFirstName} ${booking.participants.parent.lastInitial}'
                                  .trim(),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF8E8479),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _pillColor(booking.state),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _stateLabel(booking.state),
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _scheduleLabel(booking),
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF5F5650),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7F1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _supportingLine(booking),
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 12,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (onBookAgain != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: 'Book again',
                      onPressed: onBookAgain,
                      size: AppButtonSize.compact,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Color _pillColor(CanonicalBookingStateV3 state) {
    switch (state) {
      case CanonicalBookingStateV3.confirmed:
      case CanonicalBookingStateV3.inProgress:
      case CanonicalBookingStateV3.completedPendingReview:
      case CanonicalBookingStateV3.completedFinal:
        return const Color(0xFFDDF7E3);
      case CanonicalBookingStateV3.acceptedAwaitingPayment:
        return const Color(0xFFFFE1D2);
      case CanonicalBookingStateV3.requested:
      case CanonicalBookingStateV3.pendingProvider:
        return const Color(0xFFFFE8D4);
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  static String _stateLabel(CanonicalBookingStateV3 state) {
    return switch (state) {
      CanonicalBookingStateV3.requested => 'Queued',
      CanonicalBookingStateV3.pendingProvider => 'Pending',
      CanonicalBookingStateV3.acceptedAwaitingPayment => 'Pay now',
      CanonicalBookingStateV3.confirmed => 'Confirmed',
      CanonicalBookingStateV3.inProgress => 'In progress',
      CanonicalBookingStateV3.completedPendingReview => 'Review pending',
      CanonicalBookingStateV3.completedFinal => 'Completed',
      CanonicalBookingStateV3.paymentExpired => 'Payment expired',
      CanonicalBookingStateV3.cancelledByParent ||
      CanonicalBookingStateV3.cancelled => 'Cancelled',
      CanonicalBookingStateV3.declined => 'Declined',
      CanonicalBookingStateV3.expired => 'Expired',
      CanonicalBookingStateV3.noShow => 'No show',
      CanonicalBookingStateV3.disputed => 'Disputed',
      CanonicalBookingStateV3.serviceNotStarted => 'Not started',
    };
  }

  static String _scheduleLabel(CanonicalBookingDocumentV3 booking) {
    final start = booking.scheduledStartAt ?? booking.serviceAnchorAt;
    final end = booking.schedule is CanonicalSlotBookingScheduleV3
        ? (booking.schedule as CanonicalSlotBookingScheduleV3).scheduledEndAt
        : null;
    final day = _dateLabel(start);
    final startTime = _timeLabel(start);
    if (end == null) return '$day · $startTime';
    return '$day · $startTime to ${_timeLabel(end)}';
  }

  static String _supportingLine(CanonicalBookingDocumentV3 booking) {
    switch (booking.state) {
      case CanonicalBookingStateV3.requested:
      case CanonicalBookingStateV3.pendingProvider:
        return 'Waiting for provider response. Nothing has been charged.';
      case CanonicalBookingStateV3.acceptedAwaitingPayment:
        return 'Provider accepted. Complete payment to confirm availability.';
      case CanonicalBookingStateV3.confirmed:
        return 'Payment confirmed. OTP and private booking details unlock in the booking screen.';
      case CanonicalBookingStateV3.inProgress:
        return 'Service is currently in progress.';
      case CanonicalBookingStateV3.completedPendingReview:
        return 'Service completed. You can now leave a review.';
      case CanonicalBookingStateV3.completedFinal:
        return 'Booking finished successfully.';
      case CanonicalBookingStateV3.paymentExpired:
        if (_isAvailabilityLostAfterCapture(booking)) {
          return 'Availability was no longer available after payment capture.';
        }
        if (_isPaymentFailureAfterCapture(booking)) {
          return booking.payment.failureMessage.trim().isNotEmpty
              ? booking.payment.failureMessage.trim()
              : 'Payment could not be completed.';
        }
        return 'Payment was not completed within the allowed time.';
      case CanonicalBookingStateV3.cancelledByParent:
        return 'Request cancelled by customer.';
      case CanonicalBookingStateV3.cancelled:
        return booking.cancellation.cancelReasonText.trim().isNotEmpty
            ? booking.cancellation.cancelReasonText.trim()
            : 'This booking was cancelled.';
      case CanonicalBookingStateV3.declined:
        return 'The provider declined this request.';
      case CanonicalBookingStateV3.expired:
        return 'The provider did not respond in time.';
      case CanonicalBookingStateV3.noShow:
        return 'This booking was marked as a no-show.';
      case CanonicalBookingStateV3.disputed:
        return 'This booking is under dispute review.';
      case CanonicalBookingStateV3.serviceNotStarted:
        return 'The service did not start as scheduled.';
    }
  }

  static bool _isAvailabilityLostAfterCapture(
    CanonicalBookingDocumentV3 booking,
  ) {
    final failureCode = booking.payment.failureCode.trim().toUpperCase();
    return failureCode == 'CAPACITY_EXHAUSTED' ||
        failureCode == 'CAPACITY_UNAVAILABLE_AFTER_CAPTURE';
  }

  static bool _isPaymentFailureAfterCapture(
    CanonicalBookingDocumentV3 booking,
  ) {
    final failureCode = booking.payment.failureCode.trim().toUpperCase();
    return failureCode.isNotEmpty && !_isAvailabilityLostAfterCapture(booking);
  }

  static String _dateLabel(DateTime value) {
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
    return '${value.day} ${months[value.month - 1]}';
  }

  static String _timeLabel(DateTime value) {
    final hour = value.hour;
    final minute = value.minute;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $suffix';
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
