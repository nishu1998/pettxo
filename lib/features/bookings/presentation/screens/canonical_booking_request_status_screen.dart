import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/app_loader.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_confirmation_dialog.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../data/repositories/booking_repository.dart';
import '../../domain/models/booking_document_v3.dart';
import '../../domain/models/booking_read_model.dart';
import '../../domain/models/booking_v3_models.dart';
import '../../domain/models/canonical_booking_request_models.dart';
import '../../../services/data/repositories/services_repository.dart';
import '../widgets/canonical_booking_status_detail_template.dart';
import '../../../profile/presentation/screens/service_detail_screen.dart';
import 'bookings_screen.dart';
import 'canonical_booking_payment_screen.dart';

class CanonicalBookingRequestStatusScreen extends StatefulWidget {
  final String bookingId;
  final CanonicalBookingRequestResult initialResult;
  final String serviceName;
  final String providerName;
  final String serviceImageUrl;
  final bool exitToBookingsOnClose;
  final BookingRepository? bookingRepository;
  final ServicesRepository? servicesRepository;

  const CanonicalBookingRequestStatusScreen({
    super.key,
    required this.bookingId,
    required this.initialResult,
    required this.serviceName,
    required this.providerName,
    required this.serviceImageUrl,
    this.exitToBookingsOnClose = false,
    this.bookingRepository,
    this.servicesRepository,
  });

  @override
  State<CanonicalBookingRequestStatusScreen> createState() =>
      _CanonicalBookingRequestStatusScreenState();
}

class _CanonicalBookingRequestStatusScreenState
    extends State<CanonicalBookingRequestStatusScreen> {
  late final BookingRepository _bookingRepository =
      widget.bookingRepository ?? BookingRepository();
  late final ServicesRepository _servicesRepository =
      widget.servicesRepository ?? ServicesRepository();
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
    return PopScope(
      canPop: !widget.exitToBookingsOnClose,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !widget.exitToBookingsOnClose) return;
        _closeToBookings();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: const CanonicalBookingStatusDetailTopBar(),
        body: StreamBuilder<BookingReadModel?>(
          stream: _bookingRepository.watchCanonicalBooking(widget.bookingId),
          builder: (context, snapshot) {
            final readModel = snapshot.data;
            final status = _deriveStatus(readModel);
            final canonicalBooking = readModel is CanonicalBookingReadModel
                ? readModel.booking
                : null;
            final terminalPresentation = canonicalBooking == null
                ? null
                : _buildTerminalPresentation(canonicalBooking);
            final canOpenPayment = _canOpenCanonicalPayment(canonicalBooking);
            if (terminalPresentation != null) {
              return SafeArea(
                child: CanonicalBookingStatusDetailTemplate(
                  model: terminalPresentation,
                ),
              );
            }
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
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 10),
                  _DetailCard(title: 'Current state', body: status.stateLabel),
                  if (status.developmentNote != null) ...[
                    const SizedBox(height: 12),
                    _DetailCard(
                      title: 'Payment',
                      body: status.developmentNote!,
                    ),
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
                    onPressed: _handleClosePressed,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _handleClosePressed() {
    if (!widget.exitToBookingsOnClose) {
      Navigator.pop(context);
      return;
    }
    _closeToBookings();
  }

  void _closeToBookings() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const BookingsScreen()),
      (route) => false,
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
    final state = _effectiveDisplayState(booking);
    switch (state) {
      case CanonicalBookingStateV3.requested:
        return _RequestStatusViewData(
          stateLabel: 'Requested',
          title: 'Your request has been created.',
          subtitle: 'We are waiting for the provider response window to begin.',
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
          subtitle: 'The provider is reviewing your request.',
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
          countdownLabel: 'Response window ended.',
          developmentNote: hasResumableAttempt
              ? 'Your payment state will be confirmed from Firestore after checkout completes.'
              : 'Your payment window is active. Complete payment to confirm availability.',
        );
      case CanonicalBookingStateV3.declined:
        return _RequestStatusViewData(
          stateLabel: 'Declined',
          title: _terminalTitleForBooking(booking),
          subtitle: _terminalSubtitleForBooking(booking),
          color: Color(0xFFE24A4A),
        );
      case CanonicalBookingStateV3.expired:
        return _RequestStatusViewData(
          stateLabel: 'Expired',
          title: _terminalTitleForBooking(booking),
          subtitle: _terminalSubtitleForBooking(booking),
          color: Color(0xFF6B7280),
        );
      case CanonicalBookingStateV3.cancelledByParent:
        return _RequestStatusViewData(
          stateLabel: 'Cancelled',
          title: _terminalTitleForBooking(booking),
          subtitle: _terminalSubtitleForBooking(booking),
          color: Color(0xFF6B7280),
        );
      case CanonicalBookingStateV3.paymentExpired:
        if (booking.state == CanonicalBookingStateV3.acceptedAwaitingPayment ||
            (!_isAvailabilityLostAfterCapture(booking) &&
                !_isPaymentFailureAfterCapture(booking))) {
          return const _RequestStatusViewData(
            stateLabel: 'Payment window expired',
            title: 'Payment window expired',
            subtitle:
                'You did not complete payment within the active payment window. This booking request has expired.',
            color: Color(0xFF6B7280),
            countdownLabel: 'Response window ended.',
            developmentNote:
                'Payment was not completed within the active payment window. This booking request has expired.',
          );
        }
        return _RequestStatusViewData(
          stateLabel: 'Payment expired',
          title: _terminalTitleForBooking(booking),
          subtitle: _terminalSubtitleForBooking(booking),
          color: Color(0xFF6B7280),
          countdownLabel: 'Response window ended.',
        );
      default:
        return _fromInitialResult(widget.initialResult);
    }
  }

  bool _canOpenCanonicalPayment(CanonicalBookingDocumentV3? booking) {
    if (booking == null ||
        _effectiveDisplayState(booking) !=
            CanonicalBookingStateV3.acceptedAwaitingPayment) {
      return false;
    }
    final deadline = booking.lifecycle.payDeadlineAt;
    if (deadline != null && !deadline.isAfter(DateTime.now())) {
      return false;
    }
    return true;
  }

  StatusPresentationModel? _buildTerminalPresentation(
    CanonicalBookingDocumentV3 booking,
  ) {
    final displayState = _effectiveDisplayState(booking);
    switch (displayState) {
      case CanonicalBookingStateV3.declined:
      case CanonicalBookingStateV3.expired:
      case CanonicalBookingStateV3.cancelledByParent:
      case CanonicalBookingStateV3.paymentExpired:
      case CanonicalBookingStateV3.cancelled:
        return StatusPresentationModel(
          summaryRows: _buildSummaryRows(booking),
          status: _buildStatusCardPresentation(booking, displayState),
          timeline: _buildTimeline(booking, displayState),
          financialRows: _buildFinancialRows(booking, displayState),
          importantInformation: _buildImportantInformation(
            booking,
            displayState,
          ),
          actions: _buildActionsPresentation(booking, displayState),
        );
      default:
        return null;
    }
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
          subtitle: result.wasQueuedOutsideWorkingHours
              ? 'We are waiting for the provider response window to begin.'
              : 'The provider can review your request now.',
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
          subtitle: 'The provider is reviewing your request.',
          color: AppColors.primary,
          canCancel: true,
          countdownLabel: _remainingLabel(result.acceptDeadlineAt),
        );
      default:
        return const _RequestStatusViewData(
          stateLabel: 'Request sent',
          title: 'Your request has been sent.',
          subtitle: 'The provider will review your request shortly.',
          color: AppColors.primary,
        );
    }
  }

  String? _remainingLabel(DateTime? deadline) {
    if (deadline == null) return null;
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative) return 'Response window ended.';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    final seconds = remaining.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')} remaining';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')} remaining';
  }

  CanonicalBookingStateV3 _effectiveDisplayState(
    CanonicalBookingDocumentV3 booking,
  ) {
    final deadline = booking.lifecycle.payDeadlineAt;
    if (booking.state == CanonicalBookingStateV3.acceptedAwaitingPayment &&
        deadline != null &&
        !deadline.isAfter(DateTime.now())) {
      return CanonicalBookingStateV3.paymentExpired;
    }
    return booking.state;
  }

  String _terminalTitleForBooking(CanonicalBookingDocumentV3 booking) {
    switch (booking.state) {
      case CanonicalBookingStateV3.declined:
        return 'The provider declined this request.';
      case CanonicalBookingStateV3.expired:
        return 'The provider did not respond in time.';
      case CanonicalBookingStateV3.cancelledByParent:
        return 'The request was cancelled by the customer.';
      case CanonicalBookingStateV3.paymentExpired:
        if (_isAvailabilityLostAfterCapture(booking)) {
          return 'Availability was no longer available.';
        }
        if (_isPaymentFailureAfterCapture(booking)) {
          return 'Payment could not be completed.';
        }
        return 'The payment window expired.';
      default:
        return 'This request has ended.';
    }
  }

  String _terminalSubtitleForBooking(CanonicalBookingDocumentV3 booking) {
    final paymentFailureMessage = booking.payment.failureMessage.trim();
    final cancelReasonText = booking.cancellation.cancelReasonText.trim();
    if (paymentFailureMessage.isNotEmpty) {
      return paymentFailureMessage;
    }
    if (cancelReasonText.isNotEmpty) {
      return cancelReasonText;
    }

    switch (booking.state) {
      case CanonicalBookingStateV3.declined:
      case CanonicalBookingStateV3.expired:
      case CanonicalBookingStateV3.cancelledByParent:
        return '';
      case CanonicalBookingStateV3.paymentExpired:
        if (_isAvailabilityLostAfterCapture(booking)) {
          return 'Any captured payment will follow the canonical refund and reconciliation flow.';
        }
        if (_isPaymentFailureAfterCapture(booking)) {
          return 'The payment did not reach a confirmed booking state.';
        }
        return 'No payment was completed in time.';
      default:
        return '';
    }
  }

  bool _isAvailabilityLostAfterCapture(CanonicalBookingDocumentV3 booking) {
    final failureCode = booking.payment.failureCode.trim().toUpperCase();
    return failureCode == 'CAPACITY_EXHAUSTED' ||
        failureCode == 'CAPACITY_UNAVAILABLE_AFTER_CAPTURE';
  }

  bool _isPaymentFailureAfterCapture(CanonicalBookingDocumentV3 booking) {
    final failureCode = booking.payment.failureCode.trim().toUpperCase();
    return failureCode.isNotEmpty && !_isAvailabilityLostAfterCapture(booking);
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

  List<StatusSummaryRowModel> _buildSummaryRows(
    CanonicalBookingDocumentV3 booking,
  ) {
    final rows = <StatusSummaryRowModel>[
      StatusSummaryRowModel(
        label: 'Service',
        value: booking.service.serviceTitle,
        icon: Icons.pets_outlined,
      ),
      StatusSummaryRowModel(
        label: 'Provider',
        value: booking.participants.provider.displayName.trim().isEmpty
            ? widget.providerName
            : booking.participants.provider.displayName,
        icon: Icons.person_outline_rounded,
      ),
      StatusSummaryRowModel(
        label: 'Booking Date',
        value: _bookingDateLabel(booking),
        icon: Icons.calendar_today_outlined,
      ),
      StatusSummaryRowModel(
        label: 'Time',
        value: _bookingTimeLabel(booking),
        icon: Icons.access_time_rounded,
      ),
      StatusSummaryRowModel(
        label: 'Duration',
        value: _bookingDurationLabel(booking),
        icon: Icons.timelapse_outlined,
      ),
    ];
    final category = booking.service.category.trim();
    if (category.isNotEmpty) {
      rows.add(
        StatusSummaryRowModel(
          label: 'Category',
          value: category,
          icon: Icons.category_outlined,
        ),
      );
    }
    rows.add(
      StatusSummaryRowModel(
        label: 'Booking ID',
        value: widget.bookingId.toUpperCase(),
        icon: Icons.confirmation_number_outlined,
      ),
    );
    return rows;
  }

  StatusCardPresentationModel _buildStatusCardPresentation(
    CanonicalBookingDocumentV3 booking,
    CanonicalBookingStateV3 displayState,
  ) {
    switch (displayState) {
      case CanonicalBookingStateV3.declined:
        return const StatusCardPresentationModel(
          icon: Icons.cancel_outlined,
          title: 'Declined by Provider',
          explanation:
              'This booking request ended before confirmation. No payment was taken and the selected slot is no longer held.',
          accentColor: Color(0xFFE24A4A),
          badgeLabel: 'Declined',
        );
      case CanonicalBookingStateV3.expired:
        return const StatusCardPresentationModel(
          icon: Icons.hourglass_disabled_rounded,
          title: 'Response window expired',
          explanation:
              'The provider did not respond within the allowed time, so this request closed automatically.',
          accentColor: Color(0xFF6B7280),
          badgeLabel: 'Expired',
        );
      case CanonicalBookingStateV3.cancelledByParent:
        return const StatusCardPresentationModel(
          icon: Icons.event_busy_rounded,
          title: 'Cancelled by You',
          explanation:
              'This booking request was cancelled before it reached a confirmed booking state.',
          accentColor: Color(0xFF5B7BB2),
          badgeLabel: 'Cancelled',
        );
      case CanonicalBookingStateV3.cancelled:
        return StatusCardPresentationModel(
          icon: Icons.assignment_late_outlined,
          title: _isProviderCancelledAfterPayment(booking)
              ? 'Cancelled by Provider'
              : 'Booking Cancelled',
          explanation: _isProviderCancelledAfterPayment(booking)
              ? 'The provider cancelled this booking after payment.'
              : booking.cancellation.cancelReasonText.trim().isNotEmpty
              ? booking.cancellation.cancelReasonText.trim()
              : 'This booking ended after payment activity. Any applicable refund follows the canonical refund flow.',
          accentColor: const Color(0xFFE1604D),
          badgeLabel: _refundBadgeLabel(booking),
        );
      case CanonicalBookingStateV3.paymentExpired:
        if (_isAvailabilityLostAfterCapture(booking)) {
          return const StatusCardPresentationModel(
            icon: Icons.sync_problem_rounded,
            title: 'Availability changed after payment',
            explanation:
                'Payment activity was recorded, but the booking could not be confirmed because availability changed. Pettxo will reconcile this safely.',
            accentColor: Color(0xFFE07A2D),
            badgeLabel: 'Refund processing',
          );
        }
        if (_isPaymentFailureAfterCapture(booking)) {
          return const StatusCardPresentationModel(
            icon: Icons.receipt_long_outlined,
            title: 'Payment could not be finalized',
            explanation:
                'The booking did not reach a confirmed state after payment activity. Pettxo will finish the final reconciliation safely.',
            accentColor: Color(0xFFE07A2D),
            badgeLabel: 'Payment issue',
          );
        }
        return const StatusCardPresentationModel(
          icon: Icons.timer_off_outlined,
          title: 'Payment Window Expired',
          explanation:
              'Payment was not completed before the deadline, so the request expired.',
          accentColor: Color(0xFFF08A24),
          badgeLabel: 'Expired',
        );
      default:
        return const StatusCardPresentationModel(
          icon: Icons.info_outline_rounded,
          title: 'Booking update',
          explanation: 'This booking reached a terminal state.',
          accentColor: AppColors.primary,
        );
    }
  }

  List<BookingTimelineStepModel> _buildTimeline(
    CanonicalBookingDocumentV3 booking,
    CanonicalBookingStateV3 displayState,
  ) {
    final steps = <BookingTimelineStepModel>[];
    if (booking.lifecycle.requestedAt != null) {
      steps.add(
        BookingTimelineStepModel(
          label: 'Request submitted',
          timestamp: _dateTimeLabel(booking.lifecycle.requestedAt!),
          tone: BookingTimelineStepTone.success,
        ),
      );
    }
    if (booking.lifecycle.respondedAt != null &&
        booking.lifecycle.providerResponseType != null) {
      steps.add(
        BookingTimelineStepModel(
          label: switch (booking.lifecycle.providerResponseType!) {
            ProviderResponseTypeV3.accept => 'Provider accepted',
            ProviderResponseTypeV3.decline => 'Provider declined',
            ProviderResponseTypeV3.expired => 'Provider response expired',
          },
          timestamp: _dateTimeLabel(booking.lifecycle.respondedAt!),
          isHighlighted: displayState == CanonicalBookingStateV3.declined,
          tone:
              booking.lifecycle.providerResponseType ==
                  ProviderResponseTypeV3.decline
              ? BookingTimelineStepTone.failure
              : booking.lifecycle.providerResponseType ==
                    ProviderResponseTypeV3.expired
              ? BookingTimelineStepTone.warning
              : BookingTimelineStepTone.success,
        ),
      );
    }
    if (booking.lifecycle.paidAt != null) {
      steps.add(
        BookingTimelineStepModel(
          label: 'Payment completed',
          timestamp: _dateTimeLabel(booking.lifecycle.paidAt!),
          tone: BookingTimelineStepTone.success,
        ),
      );
    }
    final cancelledAt =
        booking.cancellation.cancelledAt ?? booking.lifecycle.cancelledAt;
    if (cancelledAt != null) {
      steps.add(
        BookingTimelineStepModel(
          label: _timelineCancellationLabel(booking),
          timestamp: _dateTimeLabel(cancelledAt),
          isHighlighted:
              displayState == CanonicalBookingStateV3.cancelledByParent ||
              displayState == CanonicalBookingStateV3.cancelled,
          tone: BookingTimelineStepTone.failure,
        ),
      );
      if (displayState == CanonicalBookingStateV3.cancelled &&
          _isProviderCancelledAfterPayment(booking) &&
          (_hasRefundInFlight(booking) || _isRefundCompleted(booking))) {
        steps.add(
          BookingTimelineStepModel(
            label: _isRefundCompleted(booking)
                ? 'Refund completed'
                : 'Refund processing',
            isHighlighted: true,
            tone: _isRefundCompleted(booking)
                ? BookingTimelineStepTone.success
                : BookingTimelineStepTone.warning,
          ),
        );
      }
    } else if (displayState == CanonicalBookingStateV3.expired) {
      steps.add(
        BookingTimelineStepModel(
          label: 'Request expired',
          timestamp: booking.lifecycle.acceptDeadlineAt == null
              ? null
              : _dateTimeLabel(booking.lifecycle.acceptDeadlineAt!),
          isHighlighted: true,
          tone: BookingTimelineStepTone.warning,
        ),
      );
    } else if (displayState == CanonicalBookingStateV3.paymentExpired) {
      steps.add(
        BookingTimelineStepModel(
          label: _isAvailabilityLostAfterCapture(booking)
              ? 'Refund processing'
              : 'Payment window expired',
          timestamp: booking.lifecycle.payDeadlineAt == null
              ? null
              : _dateTimeLabel(booking.lifecycle.payDeadlineAt!),
          isHighlighted: true,
          tone: BookingTimelineStepTone.warning,
        ),
      );
    }
    return steps;
  }

  List<StatusFinancialRowModel> _buildFinancialRows(
    CanonicalBookingDocumentV3 booking,
    CanonicalBookingStateV3 displayState,
  ) {
    final financials = booking.financials;
    final servicePrice = _moneyFromPaise(
      financials?.serviceSubtotalPaise ??
          _fallbackServiceSubtotalPaise(booking),
    );
    final rows = <StatusFinancialRowModel>[];
    if (displayState == CanonicalBookingStateV3.cancelled &&
        _isProviderCancelledAfterPayment(booking)) {
      rows.add(
        StatusFinancialRowModel(label: 'Service Price', value: servicePrice),
      );
    }
    if ((financials?.couponDiscountPaise ?? 0) > 0) {
      rows.add(
        StatusFinancialRowModel(
          label: 'Coupon Discount',
          value: '-${_moneyFromPaise(financials!.couponDiscountPaise)}',
        ),
      );
    }
    final customerPaidPaise = financials?.customerPaidPaise ?? 0;
    if (displayState == CanonicalBookingStateV3.cancelled &&
        _isProviderCancelledAfterPayment(booking) &&
        customerPaidPaise > 0) {
      rows.add(
        StatusFinancialRowModel(
          label: 'Customer Paid',
          value: _moneyFromPaise(customerPaidPaise),
        ),
      );
    }
    if (displayState == CanonicalBookingStateV3.declined ||
        displayState == CanonicalBookingStateV3.expired ||
        displayState == CanonicalBookingStateV3.cancelledByParent) {
      rows.add(
        const StatusFinancialRowModel(
          label: 'Customer Paid',
          value: '₹0',
          valueTone: StatusFinancialValueTone.neutral,
        ),
      );
      rows.add(
        const StatusFinancialRowModel(
          label: 'Refund',
          value: 'Not required',
          isEmphasized: true,
          valueTone: StatusFinancialValueTone.neutral,
        ),
      );
      return rows;
    }
    final refundAmountPaise = booking.cancellation.refundAmountPaise > 0
        ? booking.cancellation.refundAmountPaise
        : (financials?.refundAmountPaise ?? 0);
    if (refundAmountPaise > 0) {
      rows.add(
        StatusFinancialRowModel(
          label: 'Refund Amount',
          value: _moneyFromPaise(refundAmountPaise),
        ),
      );
    }
    final refundStatus = _refundStatusLabel(booking, displayState);
    if (refundStatus != null) {
      rows.add(
        StatusFinancialRowModel(
          label: 'Refund Status',
          value: refundStatus,
          valueTone: refundStatus == 'Completed'
              ? StatusFinancialValueTone.positive
              : refundStatus == 'Processing'
              ? StatusFinancialValueTone.warning
              : StatusFinancialValueTone.neutral,
        ),
      );
    }
    if (displayState == CanonicalBookingStateV3.paymentExpired &&
        customerPaidPaise == 0) {
      rows.add(
        const StatusFinancialRowModel(
          label: 'Customer Paid',
          value: '₹0',
          valueTone: StatusFinancialValueTone.neutral,
        ),
      );
      rows.add(
        const StatusFinancialRowModel(
          label: 'Payment Window',
          value: 'Expired',
          isEmphasized: true,
          valueTone: StatusFinancialValueTone.warning,
        ),
      );
    } else if (displayState == CanonicalBookingStateV3.paymentExpired &&
        booking.lifecycle.payDeadlineAt != null) {
      rows.add(
        StatusFinancialRowModel(
          label: 'Payment Window',
          value: _dateTimeLabel(booking.lifecycle.payDeadlineAt!),
          isEmphasized: customerPaidPaise == 0,
        ),
      );
    } else if (rows.isNotEmpty) {
      rows[rows.length - 1] = StatusFinancialRowModel(
        label: rows.last.label,
        value: rows.last.value,
        isEmphasized: true,
      );
    }
    return rows;
  }

  StatusImportantInformationModel _buildImportantInformation(
    CanonicalBookingDocumentV3 booking,
    CanonicalBookingStateV3 displayState,
  ) {
    switch (displayState) {
      case CanonicalBookingStateV3.declined:
        return const StatusImportantInformationModel(
          title: 'No payment was taken',
          body:
              'The provider declined before confirmation, so no charge was created and the slot has been released.',
        );
      case CanonicalBookingStateV3.expired:
        return const StatusImportantInformationModel(
          title: 'Slot released',
          body:
              'The request expired without a provider response. No further action is required for this booking.',
        );
      case CanonicalBookingStateV3.cancelledByParent:
        return const StatusImportantInformationModel(
          title: 'No action required',
          body:
              'This request was cancelled before confirmation. If you still need the service, you can start a new booking request from the service page.',
        );
      case CanonicalBookingStateV3.cancelled:
        return StatusImportantInformationModel(
          title: _isProviderCancelledAfterPayment(booking)
              ? 'Refund handling'
              : 'Refund handling follows the booking record',
          body: _isProviderCancelledAfterPayment(booking)
              ? (_refundCompletionMessage(booking) ??
                    'Any applicable refund continues automatically through Pettxo’s refund flow.')
              : booking.cancellation.cancelReasonText.trim().isNotEmpty
              ? booking.cancellation.cancelReasonText.trim()
              : 'This booking was cancelled after payment activity. Any applicable refund continues through Pettxo’s canonical refund flow.',
        );
      case CanonicalBookingStateV3.paymentExpired:
        if (_isAvailabilityLostAfterCapture(booking)) {
          return const StatusImportantInformationModel(
            title: 'Refund processing',
            body:
                'Availability changed after payment capture. Pettxo will reconcile the captured amount safely and process the applicable refund.',
          );
        }
        if (_isPaymentFailureAfterCapture(booking)) {
          return const StatusImportantInformationModel(
            title: 'Payment reconciliation',
            body:
                'The payment did not finalize into a confirmed booking. If money was captured, Pettxo will complete reconciliation and handle the outcome safely.',
          );
        }
        return const StatusImportantInformationModel(
          title: 'Booking expired',
          body:
              'The payment window ended before checkout completed. No active payment action remains on this booking.',
        );
      default:
        return const StatusImportantInformationModel(
          title: 'Booking update',
          body: 'No further action is required.',
        );
    }
  }

  String? _actionsFootnoteForState(CanonicalBookingStateV3 displayState) {
    switch (displayState) {
      case CanonicalBookingStateV3.declined:
      case CanonicalBookingStateV3.expired:
      case CanonicalBookingStateV3.cancelledByParent:
        return 'You can create a new booking request from the service page whenever you are ready.';
      case CanonicalBookingStateV3.cancelled:
      case CanonicalBookingStateV3.paymentExpired:
        return 'You can close this screen safely. Any applicable refund or reconciliation continues automatically.';
      default:
        return null;
    }
  }

  StatusActionsPresentationModel _buildActionsPresentation(
    CanonicalBookingDocumentV3 booking,
    CanonicalBookingStateV3 displayState,
  ) {
    switch (displayState) {
      case CanonicalBookingStateV3.cancelled:
        if (_isProviderCancelledAfterPayment(booking)) {
          return StatusActionsPresentationModel(
            primaryLabel: 'View Refund Status',
            onPrimaryPressed: () => _viewRefundStatus(booking),
            primaryIcon: Icons.receipt_long_outlined,
            secondaryLabel: 'Contact Support',
            onSecondaryPressed: _openSupportEntryPoint,
            secondaryIcon: Icons.support_agent_outlined,
            footnote:
                'Payment actions are disabled because this booking is already closed.',
          );
        }
        return StatusActionsPresentationModel(
          secondaryLabel: 'Contact Support',
          onSecondaryPressed: _openSupportEntryPoint,
          footnote: _actionsFootnoteForState(displayState),
        );
      case CanonicalBookingStateV3.cancelledByParent:
      case CanonicalBookingStateV3.declined:
      case CanonicalBookingStateV3.expired:
      case CanonicalBookingStateV3.paymentExpired:
        return StatusActionsPresentationModel(
          primaryLabel: 'Book Again',
          onPrimaryPressed: () => _bookAgain(booking),
          primaryIcon: Icons.event_repeat_outlined,
          footnote: _actionsFootnoteForState(displayState),
        );
      default:
        return StatusActionsPresentationModel(
          footnote: _actionsFootnoteForState(displayState),
        );
    }
  }

  String _bookingDateLabel(CanonicalBookingDocumentV3 booking) {
    if (booking.schedule is CanonicalSlotBookingScheduleV3) {
      final schedule = booking.schedule as CanonicalSlotBookingScheduleV3;
      return _calendarDateLabel(schedule.scheduledStartAt);
    }
    final schedule = booking.schedule as CanonicalRangeBookingScheduleV3;
    return _calendarDateLabel(schedule.checkInDateTime);
  }

  String _bookingTimeLabel(CanonicalBookingDocumentV3 booking) {
    if (booking.schedule is CanonicalSlotBookingScheduleV3) {
      final schedule = booking.schedule as CanonicalSlotBookingScheduleV3;
      return '${_timeLabel(schedule.scheduledStartAt)} to ${_timeLabel(schedule.scheduledEndAt)}';
    }
    final schedule = booking.schedule as CanonicalRangeBookingScheduleV3;
    return '${_timeLabel(schedule.checkInDateTime)} to ${_timeLabel(schedule.checkOutDateTime)}';
  }

  String _bookingDurationLabel(CanonicalBookingDocumentV3 booking) {
    if (booking.schedule is CanonicalSlotBookingScheduleV3) {
      final schedule = booking.schedule as CanonicalSlotBookingScheduleV3;
      return '${schedule.totalDurationMinutes} min';
    }
    final schedule = booking.schedule as CanonicalRangeBookingScheduleV3;
    return schedule.nights == 1 ? '1 night' : '${schedule.nights} nights';
  }

  String _calendarDateLabel(DateTime value) {
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
    return '${value.day} ${months[value.month - 1]} ${value.year}';
  }

  String _timeLabel(DateTime value) {
    final hour = value.hour;
    final minute = value.minute;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $suffix';
  }

  int _fallbackServiceSubtotalPaise(CanonicalBookingDocumentV3 booking) {
    if (booking.schedule is CanonicalSlotBookingScheduleV3) {
      final schedule = booking.schedule as CanonicalSlotBookingScheduleV3;
      return schedule.slots.fold<int>(
        0,
        (sum, slot) => sum + slot.unitPricePaise,
      );
    }
    final schedule = booking.schedule as CanonicalRangeBookingScheduleV3;
    return (booking.service.pricePerNightPaise ?? 0) * schedule.nights;
  }

  String _moneyFromPaise(int amountPaise) {
    final rupees = amountPaise / 100;
    return '₹${rupees.toStringAsFixed(amountPaise % 100 == 0 ? 0 : 2)}';
  }

  String? _refundStatusLabel(
    CanonicalBookingDocumentV3 booking,
    CanonicalBookingStateV3 displayState,
  ) {
    if (displayState == CanonicalBookingStateV3.cancelled &&
        _isProviderCancelledAfterPayment(booking)) {
      if (_isRefundCompleted(booking)) return 'Completed';
      if (_hasRefundInFlight(booking)) return 'Processing';
    }
    if (displayState == CanonicalBookingStateV3.paymentExpired &&
        _isAvailabilityLostAfterCapture(booking)) {
      return 'Processing';
    }
    if (booking.cancellation.refundAmountPaise > 0) {
      return 'Applicable';
    }
    if (displayState == CanonicalBookingStateV3.paymentExpired &&
        booking.lifecycle.paidAt != null) {
      return 'Under review';
    }
    return null;
  }

  String _timelineCancellationLabel(CanonicalBookingDocumentV3 booking) {
    final cancelledBy = booking.cancellation.cancelledBy?.trim().toLowerCase();
    switch (cancelledBy) {
      case 'parent':
        return 'Cancelled by customer';
      case 'provider':
        return 'Cancelled by provider';
      case 'system':
        return 'Cancelled automatically';
      default:
        return 'Booking cancelled';
    }
  }

  bool _isProviderCancelledAfterPayment(CanonicalBookingDocumentV3 booking) {
    return booking.state == CanonicalBookingStateV3.cancelled &&
        booking.lifecycle.paidAt != null &&
        booking.cancellation.cancelledBy?.trim().toLowerCase() == 'provider';
  }

  bool _isRefundCompleted(CanonicalBookingDocumentV3 booking) {
    return booking.payment.razorpayRefundId.trim().isNotEmpty;
  }

  bool _hasRefundInFlight(CanonicalBookingDocumentV3 booking) {
    return booking.cancellation.refundAmountPaise > 0 ||
        (booking.financials?.refundAmountPaise ?? 0) > 0;
  }

  String _refundBadgeLabel(CanonicalBookingDocumentV3 booking) {
    if (_isProviderCancelledAfterPayment(booking)) {
      if (_isRefundCompleted(booking)) return 'Refund completed';
      if (_hasRefundInFlight(booking)) return 'Refund processing';
    }
    return 'Cancelled';
  }

  String? _refundCompletionMessage(CanonicalBookingDocumentV3 booking) {
    if (_isRefundCompleted(booking)) {
      return 'The refund has been completed and will settle to the original payment method according to your bank or wallet timeline.';
    }
    if (_hasRefundInFlight(booking)) {
      return 'Refund processing has started for this cancelled booking and will return to the original payment method after settlement.';
    }
    return null;
  }

  Future<void> _bookAgain(CanonicalBookingDocumentV3 booking) async {
    final serviceId = booking.serviceId.trim();
    if (serviceId.isEmpty) {
      AppSnackbar.showWarning(
        context,
        'This service is not available to book again right now.',
      );
      return;
    }

    AppLoader.showWithMessage('Loading service details...');
    try {
      final service = await _servicesRepository.fetchServiceById(serviceId);
      AppLoader.hide();
      if (!mounted) return;

      if (service == null || service.isDeleted || !service.isActive) {
        AppSnackbar.showWarning(
          context,
          'This service is no longer available.',
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
      AppSnackbar.showError(context, 'Could not open this service right now.');
    }
  }

  void _viewRefundStatus(CanonicalBookingDocumentV3 booking) {
    final status = _refundStatusLabel(booking, booking.state);
    if (status == 'Completed') {
      AppSnackbar.showInfo(
        context,
        'Refund completed. Final settlement depends on your bank or wallet timeline.',
      );
      return;
    }
    if (status == 'Processing') {
      AppSnackbar.showInfo(
        context,
        'Refund processing is active for this booking.',
      );
      return;
    }
    AppSnackbar.showInfo(
      context,
      'Any applicable refund details are shown in the financial summary above.',
    );
  }

  void _openSupportEntryPoint() {
    Navigator.of(context).pushNamed('/settings');
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
