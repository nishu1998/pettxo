import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_confirmation_dialog.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../data/repositories/booking_repository.dart';
import '../../domain/models/booking_document_v3.dart';
import '../../domain/models/booking_read_model.dart';
import '../../domain/models/canonical_booking_request_models.dart';
import '../../domain/models/canonical_provider_booking_request_view.dart';
import '../../domain/models/booking_v3_models.dart';

class CanonicalProviderBookingRequestDetailScreen extends StatefulWidget {
  final CanonicalProviderBookingRequestView initialRequest;
  final BookingRepository? bookingRepository;

  const CanonicalProviderBookingRequestDetailScreen({
    super.key,
    required this.initialRequest,
    this.bookingRepository,
  });

  @override
  State<CanonicalProviderBookingRequestDetailScreen> createState() =>
      _CanonicalProviderBookingRequestDetailScreenState();
}

class _CanonicalProviderBookingRequestDetailScreenState
    extends State<CanonicalProviderBookingRequestDetailScreen> {
  bool _hasAttemptedViewedWrite = false;
  bool _isAccepting = false;
  bool _isDeclining = false;

  BookingRepository get _bookingRepository =>
      widget.bookingRepository ?? BookingRepository();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markViewedIfNeeded(widget.initialRequest);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Booking request',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: StreamBuilder<BookingReadModel?>(
        stream: _bookingRepository.watchCanonicalBooking(
          widget.initialRequest.bookingId,
        ),
        builder: (context, snapshot) {
          final currentRequest = _requestFromSnapshot(snapshot.data);
          _markViewedIfNeeded(currentRequest);
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
              children: [
                _RequestHeroCard(request: currentRequest),
                const SizedBox(height: 16),
                _RequestInfoCard(
                  title: 'Schedule',
                  body: _scheduleLabel(currentRequest),
                ),
                const SizedBox(height: 12),
                _RequestInfoCard(
                  title: 'Response status',
                  body: _stateDescription(currentRequest),
                ),
                if (currentRequest.timerStartsAt != null &&
                    currentRequest.isQueuedRequest) ...[
                  const SizedBox(height: 12),
                  _RequestInfoCard(
                    title: 'Working-hours opening',
                    body:
                        'The 60-minute response window starts on ${_dateTimeLabel(currentRequest.timerStartsAt!)}.',
                  ),
                ],
                if (currentRequest.acceptDeadlineAt != null &&
                    currentRequest.isPendingProvider) ...[
                  const SizedBox(height: 12),
                  _RequestInfoCard(
                    title: 'Response countdown',
                    body:
                        '${_remainingLabel(currentRequest.acceptDeadlineAt!)} remaining to respond.',
                  ),
                ],
                if (currentRequest.isActionable ||
                    currentRequest.isAcceptedAwaitingPayment) ...[
                  const SizedBox(height: 12),
                  _RequestInfoCard(
                    title: 'Important',
                    body: _importantMessage(currentRequest),
                  ),
                ],
                const SizedBox(height: 22),
                if (currentRequest.isActionable) ...[
                  Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          label: _isDeclining ? 'Declining...' : 'Decline',
                          onPressed: _isBusy ? null : _declineRequest,
                          size: AppButtonSize.compact,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GradientButton(
                          label: _isAccepting ? 'Accepting...' : 'Accept',
                          onPressed: _isBusy ? null : _acceptRequest,
                          size: AppButtonSize.compact,
                          isLoading: _isAccepting,
                        ),
                      ),
                    ],
                  ),
                ] else if (currentRequest.isAcceptedAwaitingPayment) ...[
                  _PassiveNoticeCard(text: _acceptedMessage(currentRequest)),
                ] else ...[
                  const _PassiveNoticeCard(
                    text:
                        'This request is now read-only here. The latest state has already been applied.',
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  bool get _isBusy => _isAccepting || _isDeclining;

  CanonicalProviderBookingRequestView _requestFromSnapshot(
    BookingReadModel? model,
  ) {
    if (model is CanonicalBookingReadModel) {
      return _requestFromBooking(model.bookingId, model.booking);
    }
    return widget.initialRequest;
  }

  CanonicalProviderBookingRequestView _requestFromBooking(
    String bookingId,
    CanonicalBookingDocumentV3 booking,
  ) {
    return CanonicalProviderBookingRequestView.fromBooking(bookingId, booking);
  }

  void _markViewedIfNeeded(CanonicalProviderBookingRequestView request) {
    if (_hasAttemptedViewedWrite || !request.isActionable) return;
    _hasAttemptedViewedWrite = true;
    _dispatchViewedWrite(request.bookingId);
  }

  Future<void> _dispatchViewedWrite(String bookingId) async {
    try {
      await _bookingRepository.markBookingViewedByProviderV3(
        bookingId: bookingId,
      );
    } catch (_) {
      // Firestore remains the source of truth for viewed state, so a failed
      // best-effort mark does not need to interrupt the detail screen.
    }
  }

  Future<void> _acceptRequest() async {
    final confirmed = await AppConfirmationDialog.show(
      context: context,
      title: 'Accept request?',
      message:
          'This gives the customer 60 minutes to pay. Availability is confirmed only after payment succeeds.',
      cancelLabel: 'Keep pending',
      confirmLabel: 'Accept',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isAccepting = true);
    try {
      await _bookingRepository.acceptBookingRequestV3(
        bookingId: widget.initialRequest.bookingId,
      );
      if (!mounted) return;
      AppSnackbar.showSuccess(
        context,
        'Request accepted. The customer can pay now.',
      );
    } on CanonicalBookingRequestException catch (error) {
      if (!mounted) return;
      AppSnackbar.showError(context, _friendlyCommandError(error));
    } finally {
      if (mounted) {
        setState(() => _isAccepting = false);
      }
    }
  }

  Future<void> _declineRequest() async {
    final confirmed = await AppConfirmationDialog.show(
      context: context,
      title: 'Decline request?',
      message:
          'This keeps availability unconfirmed and notifies the customer that the request was declined.',
      cancelLabel: 'Keep pending',
      confirmLabel: 'Decline',
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeclining = true);
    try {
      await _bookingRepository.declineBookingRequestV3(
        bookingId: widget.initialRequest.bookingId,
      );
      if (!mounted) return;
      AppSnackbar.showInfo(context, 'Request declined.');
    } on CanonicalBookingRequestException catch (error) {
      if (!mounted) return;
      AppSnackbar.showError(context, _friendlyCommandError(error));
    } finally {
      if (mounted) {
        setState(() => _isDeclining = false);
      }
    }
  }

  String _friendlyCommandError(CanonicalBookingRequestException error) {
    switch (error.code) {
      case CanonicalBookingRequestFailureCode.canonicalBookingDisabled:
        return 'This canonical request flow is not enabled for this action.';
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
            : 'We could not update this request right now.';
    }
  }

  String _stateDescription(CanonicalProviderBookingRequestView request) {
    if (request.isQueuedRequest) {
      if (request.timerStartsAt != null) {
        return 'This request was received outside your working hours. You can accept or decline it now. Your official 60-minute response window starts on ${_dateTimeLabel(request.timerStartsAt!)}.';
      }
      return 'This request was received outside your working hours. You can accept or decline it now. The official response clock will start when your schedule opens.';
    }
    if (request.isPendingProvider) {
      return 'The official response window is active. Review safely and respond within the countdown.';
    }
    if (request.isAcceptedAwaitingPayment) {
      return _acceptedMessage(request);
    }
    return 'This request already moved forward and is shown here only for safe read compatibility.';
  }

  String _importantMessage(CanonicalProviderBookingRequestView request) {
    if (request.isQueuedRequest) {
      return 'This request was received outside your working hours. You can accept or decline it now. The official payment and response windows will still anchor to your next working-hours opening.';
    }
    return 'Accepting lets the customer pay now. Availability is confirmed only after payment succeeds.';
  }

  String _acceptedMessage(CanonicalProviderBookingRequestView request) {
    final timerStartsAt = request.timerStartsAt;
    if (timerStartsAt != null && timerStartsAt.isAfter(DateTime.now())) {
      return 'This request was accepted before your working hours opened. The customer can pay now. The official payment deadline is still anchored to ${_dateTimeLabel(timerStartsAt)}.';
    }
    return 'This request has been accepted. The customer can pay now and the booking will confirm as soon as payment succeeds.';
  }

  String _scheduleLabel(CanonicalProviderBookingRequestView request) {
    final start = request.scheduledStartAt;
    final end = request.scheduledEndAt;
    if (start == null || end == null) {
      return 'Schedule details are not available yet for this booking type.';
    }
    final slotCount = request.slotCount > 0
        ? ' · ${request.slotCount} slot${request.slotCount == 1 ? '' : 's'}'
        : '';
    final duration = request.totalDurationMinutes > 0
        ? ' · ${request.totalDurationMinutes} min'
        : '';
    return '${_dateTimeLabel(start)} to ${_timeLabel(end)}$slotCount$duration';
  }

  String _remainingLabel(DateTime deadline) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative) return '00:00';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    final seconds = remaining.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _dateTimeLabel(DateTime value) {
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
    final hour = value.hour;
    final minute = value.minute;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '${value.day} ${months[value.month - 1]} ${value.year} · $displayHour:${minute.toString().padLeft(2, '0')} $suffix';
  }

  String _timeLabel(DateTime value) {
    final hour = value.hour;
    final minute = value.minute;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $suffix';
  }
}

class _RequestHeroCard extends StatelessWidget {
  final CanonicalProviderBookingRequestView request;

  const _RequestHeroCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final payout = request.estimatedProviderPayoutPaise != null
        ? '₹${(request.estimatedProviderPayoutPaise! / 100).toStringAsFixed(0)} payout'
        : 'Payout shown after payment flow activation';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _stateTint(request.state),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _stateLabel(request.state),
              style: const TextStyle(
                color: AppColors.textDark,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            request.serviceTitle,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${request.maskedParentDisplayName} · ${request.animalType} · ${request.serviceCategory}',
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: AppColors.textGrey,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricChip(
                icon: Icons.star_rounded,
                label: request.parentRating > 0
                    ? request.parentRating.toStringAsFixed(1)
                    : 'New',
              ),
              _MetricChip(
                icon: Icons.verified_rounded,
                label:
                    '${request.completedBookingCount} completed booking${request.completedBookingCount == 1 ? '' : 's'}',
              ),
              _MetricChip(
                icon: Icons.account_balance_wallet_outlined,
                label: payout,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _stateLabel(CanonicalBookingStateV3 state) {
    return switch (state) {
      CanonicalBookingStateV3.requested => 'Queued request',
      CanonicalBookingStateV3.pendingProvider => 'Action required',
      CanonicalBookingStateV3.acceptedAwaitingPayment =>
        'Accepted, awaiting payment',
      CanonicalBookingStateV3.declined => 'Declined',
      CanonicalBookingStateV3.expired => 'Expired',
      CanonicalBookingStateV3.cancelledByParent => 'Cancelled',
      CanonicalBookingStateV3.paymentExpired => 'Payment expired',
      CanonicalBookingStateV3.confirmed => 'Confirmed',
      _ => 'Booking request',
    };
  }

  static Color _stateTint(CanonicalBookingStateV3 state) {
    return switch (state) {
      CanonicalBookingStateV3.requested => const Color(0xFFFFE8D4),
      CanonicalBookingStateV3.pendingProvider => const Color(0xFFFFE1D2),
      CanonicalBookingStateV3.acceptedAwaitingPayment => const Color(
        0xFFDDF7E3,
      ),
      _ => const Color(0xFFF3F4F6),
    };
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetricChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textDark,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestInfoCard extends StatelessWidget {
  final String title;
  final String body;

  const _RequestInfoCard({required this.title, required this.body});

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
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
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

class _PassiveNoticeCard extends StatelessWidget {
  final String text;

  const _PassiveNoticeCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textGrey,
          height: 1.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
