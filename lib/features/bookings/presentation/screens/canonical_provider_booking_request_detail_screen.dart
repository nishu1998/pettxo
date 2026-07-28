import 'dart:ui';
import 'dart:async';

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
import '../widgets/booking_deadline_countdown.dart';

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
  Timer? _ticker;

  BookingRepository get _bookingRepository =>
      widget.bookingRepository ?? BookingRepository();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markViewedIfNeeded(widget.initialRequest);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(92),
        child: _ProviderGlassTopBar(title: 'Booking request'),
      ),
      body: StreamBuilder<BookingReadModel?>(
        stream: _bookingRepository.watchCanonicalBooking(
          widget.initialRequest.bookingId,
        ),
        builder: (context, snapshot) {
          final currentRequest = _requestFromSnapshot(snapshot.data);
          _markViewedIfNeeded(currentRequest);
          final effectiveState = currentRequest.effectiveState;
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
              children: [
                _RequestHeroCard(
                  request: currentRequest,
                  effectiveState: effectiveState,
                ),
                const SizedBox(height: 16),
                _RequestSummaryCard(
                  request: currentRequest,
                  scheduleLabel: _scheduleLabel(currentRequest),
                ),
                const SizedBox(height: 12),
                _RequestStatusCard(
                  request: currentRequest,
                  effectiveState: effectiveState,
                  statusBody: _stateDescription(currentRequest, effectiveState),
                  noteBody: _importantMessage(currentRequest, effectiveState),
                  countdownDeadline: currentRequest.isAcceptedAwaitingPayment
                      ? currentRequest.payDeadlineAt
                      : currentRequest.isPendingProvider
                      ? currentRequest.acceptDeadlineAt
                      : null,
                  countdownTitle: currentRequest.isAcceptedAwaitingPayment
                      ? 'Customer payment window'
                      : currentRequest.isPendingProvider
                      ? 'Response window'
                      : null,
                ),
                if (currentRequest.timerStartsAt != null &&
                    currentRequest.isQueuedRequest) ...[
                  const SizedBox(height: 12),
                  _RequestInfoCard(
                    title: 'Working-hours opening',
                    body:
                        'The official 60-minute response window starts on ${_dateTimeLabel(currentRequest.timerStartsAt!)}.',
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
                ] else if (currentRequest.isPaymentExpired) ...[
                  _PassiveNoticeCard(
                    text: _acceptedMessage(currentRequest, effectiveState),
                  ),
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

  String _stateDescription(
    CanonicalProviderBookingRequestView request,
    CanonicalBookingStateV3 effectiveState,
  ) {
    if (request.isQueuedRequest) {
      if (request.timerStartsAt != null) {
        return 'Received outside working hours. You can still accept or decline it now, and the official 60-minute response window starts on ${_dateTimeLabel(request.timerStartsAt!)}.';
      }
      return 'Received outside working hours. You can still accept or decline it now, and the official response clock starts when your schedule opens.';
    }
    if (request.isPendingProvider) {
      return 'The official response window is active. Review the request and respond within the countdown.';
    }
    if (effectiveState == CanonicalBookingStateV3.acceptedAwaitingPayment) {
      return 'The customer is in the payment window. The booking confirms only after payment succeeds.';
    }
    if (effectiveState == CanonicalBookingStateV3.paymentExpired) {
      return 'The customer did not complete payment within the allowed time. This booking request has expired.';
    }
    return 'This request already moved forward and is shown here only for safe read compatibility.';
  }

  String _importantMessage(
    CanonicalProviderBookingRequestView request,
    CanonicalBookingStateV3 effectiveState,
  ) {
    if (request.isQueuedRequest) {
      return 'Payment and response windows still anchor to your next working-hours opening.';
    }
    if (effectiveState == CanonicalBookingStateV3.paymentExpired) {
      return 'The customer did not complete payment within the allowed time. No further action is available.';
    }
    if (effectiveState == CanonicalBookingStateV3.acceptedAwaitingPayment) {
      return '';
    }
    return 'Accepting lets the customer pay now. Availability is confirmed only after payment succeeds.';
  }

  String _acceptedMessage(
    CanonicalProviderBookingRequestView request,
    CanonicalBookingStateV3 effectiveState,
  ) {
    if (effectiveState == CanonicalBookingStateV3.paymentExpired) {
      return 'This request expired before the customer completed payment. No further action is available.';
    }
    final timerStartsAt = request.timerStartsAt;
    if (timerStartsAt != null && timerStartsAt.isAfter(DateTime.now())) {
      return 'This request was accepted before your working hours opened. The customer can pay now. The official payment deadline is still anchored to ${_dateTimeLabel(timerStartsAt)}.';
    }
    return 'Accepted. The customer can still pay within the active window, and the booking will confirm only after payment succeeds.';
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
  final CanonicalBookingStateV3 effectiveState;

  const _RequestHeroCard({required this.request, required this.effectiveState});

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
              color: _stateTint(effectiveState),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _stateLabel(effectiveState),
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
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
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
                  maxWidth: constraints.maxWidth * 0.62,
                  allowWrap: true,
                ),
                _MetricChip(
                  icon: Icons.account_balance_wallet_outlined,
                  label: payout,
                  maxWidth: constraints.maxWidth * 0.78,
                  allowWrap: true,
                ),
              ],
            ),
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
      CanonicalBookingStateV3.paymentExpired => 'Expired',
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
      CanonicalBookingStateV3.paymentExpired => const Color(0xFFF3F4F6),
      _ => const Color(0xFFF3F4F6),
    };
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final double? maxWidth;
  final bool allowWrap;

  const _MetricChip({
    required this.icon,
    required this.label,
    this.maxWidth,
    this.allowWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = const TextStyle(
      color: AppColors.textDark,
      fontWeight: FontWeight.w700,
      fontSize: 12,
      height: 1.3,
    );
    if (allowWrap && maxWidth != null) {
      return SizedBox(
        width: maxWidth,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7F1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(label, softWrap: true, style: labelStyle)),
            ],
          ),
        ),
      );
    }

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
          Text(label, style: labelStyle),
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

class _RequestSummaryCard extends StatelessWidget {
  const _RequestSummaryCard({
    required this.request,
    required this.scheduleLabel,
  });

  final CanonicalProviderBookingRequestView request;
  final String scheduleLabel;

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
          _SummaryLine(label: 'Schedule', value: scheduleLabel),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _SummaryLine(
            label: 'Status',
            value: _RequestHeroCard._stateLabel(request.effectiveState),
          ),
        ],
      ),
    );
  }
}

class _RequestStatusCard extends StatelessWidget {
  const _RequestStatusCard({
    required this.request,
    required this.effectiveState,
    required this.statusBody,
    required this.noteBody,
    required this.countdownDeadline,
    required this.countdownTitle,
  });

  final CanonicalProviderBookingRequestView request;
  final CanonicalBookingStateV3 effectiveState;
  final String statusBody;
  final String noteBody;
  final DateTime? countdownDeadline;
  final String? countdownTitle;

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
            _cardTitle,
            style: const TextStyle(
              color: AppColors.textDark,
              fontWeight: FontWeight.w800,
              fontSize: 14,
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
          if (countdownDeadline != null && countdownTitle != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7F1),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    countdownTitle!,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  BookingDeadlineCountdown(
                    deadline: countdownDeadline,
                    valueFontSize: 18,
                    labelFontSize: 11,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    textAlign: TextAlign.center,
                    centerLabelRow: true,
                  ),
                ],
              ),
            ),
          ],
          if (noteBody.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              noteBody,
              style: const TextStyle(
                color: AppColors.textGrey,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String get _cardTitle {
    if (effectiveState == CanonicalBookingStateV3.acceptedAwaitingPayment) {
      return 'Accepted, awaiting payment';
    }
    if (effectiveState == CanonicalBookingStateV3.paymentExpired) {
      return 'Payment window expired';
    }
    if (request.isPendingProvider) {
      return 'Response status';
    }
    if (request.isQueuedRequest) {
      return 'Queued request';
    }
    return 'Request status';
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
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
    );
  }
}

class _ProviderGlassTopBar extends StatelessWidget {
  const _ProviderGlassTopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.58),
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(16),
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
                  const SizedBox(width: 12),
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
