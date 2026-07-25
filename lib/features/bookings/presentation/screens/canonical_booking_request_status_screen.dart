import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_confirmation_dialog.dart';
import '../../data/repositories/booking_repository.dart';
import '../../domain/models/booking_document_v3.dart';
import '../../domain/models/booking_read_model.dart';
import '../../domain/models/booking_v3_models.dart';
import '../../domain/models/canonical_booking_request_models.dart';
import 'canonical_booking_payment_screen.dart';

class CanonicalBookingRequestStatusScreen extends StatefulWidget {
  final String bookingId;
  final CanonicalBookingRequestResult initialResult;
  final String serviceName;
  final String providerName;
  final String serviceImageUrl;

  const CanonicalBookingRequestStatusScreen({
    super.key,
    required this.bookingId,
    required this.initialResult,
    required this.serviceName,
    required this.providerName,
    required this.serviceImageUrl,
  });

  @override
  State<CanonicalBookingRequestStatusScreen> createState() =>
      _CanonicalBookingRequestStatusScreenState();
}

class _CanonicalBookingRequestStatusScreenState
    extends State<CanonicalBookingRequestStatusScreen> {
  final BookingRepository _bookingRepository = BookingRepository();
  Timer? _ticker;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
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
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Request status',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: StreamBuilder<BookingReadModel?>(
        stream: _bookingRepository.watchCanonicalBooking(widget.bookingId),
        builder: (context, snapshot) {
          final readModel = snapshot.data;
          final status = _deriveStatus(readModel);
          final canonicalBooking = readModel is CanonicalBookingReadModel
              ? readModel.booking
              : null;
          final canOpenPayment = _canOpenCanonicalPayment(canonicalBooking);
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
              children: [
                _StatusHeroCard(
                  serviceName: widget.serviceName,
                  providerName: widget.providerName,
                  serviceImageUrl: widget.serviceImageUrl,
                  title: status.title,
                  subtitle: status.subtitle,
                  color: status.color,
                ),
                const SizedBox(height: 16),
                if (status.countdownLabel != null)
                  _DetailCard(
                    title: 'Response window',
                    body: status.countdownLabel!,
                  ),
                if (status.timerStartsAtLabel != null) ...[
                  const SizedBox(height: 12),
                  _DetailCard(
                    title: 'Timer starts',
                    body: status.timerStartsAtLabel!,
                  ),
                ],
                const SizedBox(height: 12),
                const _DetailCard(
                  title: 'Charges',
                  body: 'Nothing has been charged.',
                ),
                const SizedBox(height: 12),
                _DetailCard(title: 'Current state', body: status.stateLabel),
                if (status.developmentNote != null) ...[
                  const SizedBox(height: 12),
                  _DetailCard(title: 'Payment', body: status.developmentNote!),
                ],
                const SizedBox(height: 20),
                if (status.canCancel) ...[
                  SecondaryButton(
                    label: _isCancelling ? 'Cancelling...' : 'Cancel request',
                    onPressed: _isCancelling ? null : _cancelRequest,
                  ),
                  const SizedBox(height: 10),
                ],
                if (canOpenPayment) ...[
                  GradientButton(
                    label:
                        canonicalBooking!.payment.paymentAttemptId
                            .trim()
                            .isNotEmpty
                        ? 'Resume payment'
                        : 'Pay now',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CanonicalBookingPaymentScreen(
                          bookingId: widget.bookingId,
                          serviceName: widget.serviceName,
                          providerName: widget.providerName,
                          serviceImageUrl: widget.serviceImageUrl,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SecondaryButton(
                  label: 'Close',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  _RequestStatusViewData _deriveStatus(BookingReadModel? booking) {
    if (booking is CanonicalBookingReadModel) {
      return _fromCanonicalBooking(booking.booking);
    }
    return _fromInitialResult(widget.initialResult);
  }

  _RequestStatusViewData _fromCanonicalBooking(
    CanonicalBookingDocumentV3 booking,
  ) {
    final state = booking.state;
    switch (state) {
      case CanonicalBookingStateV3.requested:
        return _RequestStatusViewData(
          stateLabel: 'Requested',
          title: 'Your request has been created.',
          subtitle:
              'Nothing has been charged. We are waiting for the provider response window to begin.',
          color: const Color(0xFFFFB36B),
          canCancel: true,
          timerStartsAtLabel: booking.lifecycle.timerStartsAt == null
              ? null
              : _dateTimeLabel(booking.lifecycle.timerStartsAt!),
        );
      case CanonicalBookingStateV3.pendingProvider:
        return _RequestStatusViewData(
          stateLabel: 'Pending provider',
          title: 'Waiting for provider response.',
          subtitle:
              'Nothing has been charged while the provider reviews your request.',
          color: AppColors.primary,
          canCancel: true,
          countdownLabel: _remainingLabel(booking.lifecycle.acceptDeadlineAt),
        );
      case CanonicalBookingStateV3.acceptedAwaitingPayment:
        final hasResumableAttempt = booking.payment.paymentAttemptId
            .trim()
            .isNotEmpty;
        return _RequestStatusViewData(
          stateLabel: 'Accepted, awaiting payment',
          title: 'The provider accepted your request.',
          subtitle:
              'Pay within the active window to confirm availability and unlock the booking.',
          color: Color(0xFF2F9E44),
          countdownLabel: _remainingLabel(booking.lifecycle.payDeadlineAt),
          developmentNote: hasResumableAttempt
              ? 'Your payment state will be confirmed from Firestore after checkout completes.'
              : 'Your payment window is active. Complete payment to confirm availability.',
        );
      case CanonicalBookingStateV3.declined:
        return const _RequestStatusViewData(
          stateLabel: 'Declined',
          title: 'The provider declined this request.',
          subtitle: 'Nothing has been charged.',
          color: Color(0xFFE24A4A),
        );
      case CanonicalBookingStateV3.expired:
        return const _RequestStatusViewData(
          stateLabel: 'Expired',
          title: 'The provider did not respond in time.',
          subtitle: 'Nothing has been charged.',
          color: Color(0xFF6B7280),
        );
      case CanonicalBookingStateV3.cancelledByParent:
        return const _RequestStatusViewData(
          stateLabel: 'Cancelled',
          title: 'This request was cancelled.',
          subtitle: 'Nothing has been charged.',
          color: Color(0xFF6B7280),
        );
      case CanonicalBookingStateV3.paymentExpired:
        return const _RequestStatusViewData(
          stateLabel: 'Payment expired',
          title: 'The payment window expired.',
          subtitle: 'No payment was completed.',
          color: Color(0xFF6B7280),
        );
      default:
        return _fromInitialResult(widget.initialResult);
    }
  }

  bool _canOpenCanonicalPayment(CanonicalBookingDocumentV3? booking) {
    if (booking == null ||
        booking.state != CanonicalBookingStateV3.acceptedAwaitingPayment) {
      return false;
    }
    final deadline = booking.lifecycle.payDeadlineAt;
    if (deadline != null && !deadline.isAfter(DateTime.now())) {
      return false;
    }
    return true;
  }

  _RequestStatusViewData _fromInitialResult(
    CanonicalBookingRequestResult result,
  ) {
    switch (result.state) {
      case CanonicalBookingStateV3.requested:
        return _RequestStatusViewData(
          stateLabel: 'Requested',
          title: result.wasQueuedOutsideWorkingHours
              ? 'Your request is queued for working hours.'
              : 'Your request has been sent.',
          subtitle: 'Nothing has been charged.',
          color: AppColors.primary,
          canCancel: true,
          timerStartsAtLabel: result.timerStartsAt == null
              ? null
              : _dateTimeLabel(result.timerStartsAt!),
        );
      case CanonicalBookingStateV3.pendingProvider:
        return _RequestStatusViewData(
          stateLabel: 'Pending provider',
          title: 'Waiting for provider response.',
          subtitle: 'Nothing has been charged.',
          color: AppColors.primary,
          canCancel: true,
          countdownLabel: _remainingLabel(result.acceptDeadlineAt),
        );
      default:
        return const _RequestStatusViewData(
          stateLabel: 'Request sent',
          title: 'Your request has been sent.',
          subtitle: 'Nothing has been charged.',
          color: AppColors.primary,
        );
    }
  }

  String? _remainingLabel(DateTime? deadline) {
    if (deadline == null) return null;
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative) return 'Response window ended';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    final seconds = remaining.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')} remaining';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')} remaining';
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

  Future<void> _cancelRequest() async {
    final confirmed = await AppConfirmationDialog.show(
      context: context,
      title: 'Cancel request?',
      message:
          'This request will be cancelled before payment and the provider will be notified if needed.',
      cancelLabel: 'Keep request',
      confirmLabel: 'Cancel request',
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isCancelling = true);
    try {
      await _bookingRepository.cancelBookingRequestByParentV3(
        bookingId: widget.bookingId,
      );
    } on CanonicalBookingRequestException catch (_) {
      // Firestore observation remains authoritative; the UI will refresh if the
      // server applied the transition while the callable response was racing.
    } finally {
      if (mounted) {
        setState(() => _isCancelling = false);
      }
    }
  }
}

class _StatusHeroCard extends StatelessWidget {
  final String serviceName;
  final String providerName;
  final String serviceImageUrl;
  final String title;
  final String subtitle;
  final Color color;

  const _StatusHeroCard({
    required this.serviceName,
    required this.providerName,
    required this.serviceImageUrl,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: serviceImageUrl.trim().isEmpty
                      ? Container(
                          color: const Color(0xFFFFEFE7),
                          child: const Icon(
                            Icons.pets_rounded,
                            color: AppColors.primary,
                          ),
                        )
                      : Image.network(
                          serviceImageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: const Color(0xFFFFEFE7),
                            child: const Icon(
                              Icons.pets_rounded,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      serviceName,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      providerName.trim().isEmpty
                          ? 'Service provider'
                          : providerName,
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.14),
                child: Icon(Icons.hourglass_top_rounded, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final String title;
  final String body;

  const _DetailCard({required this.title, required this.body});

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
              color: AppColors.textGrey,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(
              color: AppColors.textDark,
              fontWeight: FontWeight.w800,
              fontSize: 14.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestStatusViewData {
  final String stateLabel;
  final String title;
  final String subtitle;
  final Color color;
  final String? countdownLabel;
  final String? timerStartsAtLabel;
  final String? developmentNote;
  final bool canCancel;

  const _RequestStatusViewData({
    required this.stateLabel,
    required this.title,
    required this.subtitle,
    required this.color,
    this.countdownLabel,
    this.timerStartsAtLabel,
    this.developmentNote,
    this.canCancel = false,
  });
}
