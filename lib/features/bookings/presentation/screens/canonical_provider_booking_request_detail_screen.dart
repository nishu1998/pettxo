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
import '../../domain/models/canonical_booking_cancellation_models.dart';
import '../../domain/models/canonical_booking_request_models.dart';
import '../../domain/models/canonical_provider_booking_request_view.dart';
import '../../domain/models/booking_v3_models.dart';
import '../utils/canonical_booking_presentation_state.dart';
import '../widgets/booking_deadline_countdown.dart';
import '../widgets/canonical_booking_status_detail_template.dart';

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
    final shouldUseTerminalTopBar = !widget.initialRequest.isActionable;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: shouldUseTerminalTopBar
          ? const CanonicalBookingStatusDetailTopBar(title: 'Booking Details')
          : const PreferredSize(
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
          final canonicalBooking = snapshot.data is CanonicalBookingReadModel
              ? (snapshot.data as CanonicalBookingReadModel).booking
              : null;
          if (canonicalBooking != null &&
              _isProviderTerminalPastState(effectiveState)) {
            return _ProviderTerminalBookingDetailsView(
              bookingId: widget.initialRequest.bookingId,
              booking: canonicalBooking,
              repository: _bookingRepository,
            );
          }
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
                ] else if (!currentRequest.isPaymentExpired) ...[
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

  bool _isProviderTerminalPastState(CanonicalBookingStateV3 state) {
    switch (state) {
      case CanonicalBookingStateV3.paymentExpired:
      case CanonicalBookingStateV3.cancelledByParent:
      case CanonicalBookingStateV3.cancelled:
      case CanonicalBookingStateV3.declined:
      case CanonicalBookingStateV3.expired:
        return true;
      default:
        return false;
    }
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
      return '';
    }
    if (effectiveState == CanonicalBookingStateV3.acceptedAwaitingPayment) {
      return '';
    }
    return 'Accepting lets the customer pay now. Availability is confirmed only after payment succeeds.';
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

enum _ProviderTerminalKind {
  paymentWindowExpired,
  customerCancelledBeforePayment,
  customerCancelledAfterPayment,
  providerCancelledAfterPayment,
  providerDeclined,
  requestExpired,
  genericClosed,
}

class _ProviderTerminalBookingDetailsView extends StatelessWidget {
  const _ProviderTerminalBookingDetailsView({
    required this.bookingId,
    required this.booking,
    required this.repository,
  });

  final String bookingId;
  final CanonicalBookingDocumentV3 booking;
  final BookingRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CanonicalBookingCancellationRecord?>(
      stream: repository.watchCanonicalBookingCancellation(bookingId),
      builder: (context, snapshot) {
        final cancellationRecord = snapshot.data;
        final kind = _kindForBooking(booking, cancellationRecord);
        final summaryRows = _buildSummaryRows(bookingId, booking);
        final statusModel = _buildStatusModel(kind, cancellationRecord);
        final timeline = _buildTimeline(kind, booking, cancellationRecord);
        final outcomeRows = _buildOutcomeRows(
          kind,
          booking,
          cancellationRecord,
        );
        final financialRows = _buildFinancialRows(
          kind,
          booking,
          cancellationRecord,
        );
        final importantInformation = _buildImportantInformation(
          kind,
          booking,
          cancellationRecord,
        );

        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            children: [
              const BookingDetailsSectionLabel('Booking summary'),
              const SizedBox(height: 10),
              BookingSummaryCard(rows: summaryRows),
              const SizedBox(height: 16),
              const BookingDetailsSectionLabel('Booking status'),
              const SizedBox(height: 10),
              BookingStatusCard(model: statusModel),
              const SizedBox(height: 16),
              const BookingDetailsSectionLabel('Booking timeline'),
              const SizedBox(height: 10),
              BookingTimelineCard(steps: timeline),
              if (outcomeRows.isNotEmpty) ...[
                const SizedBox(height: 16),
                const BookingDetailsSectionLabel('Outcome details'),
                const SizedBox(height: 10),
                BookingSummaryCard(rows: outcomeRows),
              ],
              if (financialRows.isNotEmpty) ...[
                const SizedBox(height: 16),
                const BookingDetailsSectionLabel('Financial summary'),
                const SizedBox(height: 10),
                FinancialSummaryCard(rows: financialRows),
              ],
              const SizedBox(height: 16),
              const BookingDetailsSectionLabel('Important information'),
              const SizedBox(height: 10),
              ImportantInformationCard(model: importantInformation),
            ],
          ),
        );
      },
    );
  }

  static _ProviderTerminalKind _kindForBooking(
    CanonicalBookingDocumentV3 booking,
    CanonicalBookingCancellationRecord? cancellationRecord,
  ) {
    final effectiveState = effectiveCanonicalBookingPresentationState(booking);
    final paid = _hasConfirmedPayment(booking);
    switch (effectiveState) {
      case CanonicalBookingStateV3.paymentExpired:
        return _ProviderTerminalKind.paymentWindowExpired;
      case CanonicalBookingStateV3.cancelledByParent:
        return paid
            ? _ProviderTerminalKind.customerCancelledAfterPayment
            : _ProviderTerminalKind.customerCancelledBeforePayment;
      case CanonicalBookingStateV3.cancelled:
        if (_isCustomerCancellation(booking, cancellationRecord)) {
          return paid
              ? _ProviderTerminalKind.customerCancelledAfterPayment
              : _ProviderTerminalKind.customerCancelledBeforePayment;
        }
        return _ProviderTerminalKind.providerCancelledAfterPayment;
      case CanonicalBookingStateV3.declined:
        return _ProviderTerminalKind.providerDeclined;
      case CanonicalBookingStateV3.expired:
        return _ProviderTerminalKind.requestExpired;
      default:
        return _ProviderTerminalKind.genericClosed;
    }
  }

  static List<StatusSummaryRowModel> _buildSummaryRows(
    String bookingId,
    CanonicalBookingDocumentV3 booking,
  ) {
    final rows = <StatusSummaryRowModel>[
      StatusSummaryRowModel(
        label: 'Service',
        value: booking.service.serviceTitle,
        icon: Icons.pets_outlined,
      ),
      StatusSummaryRowModel(
        label: 'Customer',
        value: _customerLabel(booking),
        icon: Icons.person_outline_rounded,
      ),
    ];

    final pet = booking.service.animalType.trim();
    if (pet.isNotEmpty) {
      rows.add(
        StatusSummaryRowModel(
          label: 'Pet',
          value: pet,
          icon: Icons.pets_rounded,
        ),
      );
    }

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

    rows.addAll([
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
    ]);

    final slotLabel = _slotCountLabel(booking);
    if (slotLabel != null) {
      rows.add(
        StatusSummaryRowModel(
          label: 'Slot count',
          value: slotLabel,
          icon: Icons.view_week_outlined,
        ),
      );
    }

    rows.add(
      StatusSummaryRowModel(
        label: 'Booking ID',
        value: bookingId.toUpperCase(),
        icon: Icons.confirmation_number_outlined,
      ),
    );
    return rows;
  }

  static StatusCardPresentationModel _buildStatusModel(
    _ProviderTerminalKind kind,
    CanonicalBookingCancellationRecord? cancellationRecord,
  ) {
    switch (kind) {
      case _ProviderTerminalKind.paymentWindowExpired:
        return const StatusCardPresentationModel(
          icon: Icons.schedule_rounded,
          title: 'Payment Window Expired',
          explanation:
              'The customer did not complete payment within the allowed time, so this booking request expired.',
          accentColor: Color(0xFF6B7280),
          badgeLabel: 'Expired',
        );
      case _ProviderTerminalKind.customerCancelledBeforePayment:
        return const StatusCardPresentationModel(
          icon: Icons.person_remove_alt_1_outlined,
          title: 'Cancelled by Customer',
          explanation:
              'The customer cancelled this request before completing payment. No payment was collected.',
          accentColor: Color(0xFFF59E0B),
          badgeLabel: 'Cancelled',
        );
      case _ProviderTerminalKind.customerCancelledAfterPayment:
        return StatusCardPresentationModel(
          icon: Icons.person_off_outlined,
          title: 'Cancelled by Customer',
          explanation: _hasActiveFinancialProcessing(cancellationRecord)
              ? 'The customer cancelled this confirmed booking. Refund and provider settlement updates will appear here as processing completes.'
              : 'The customer cancelled this confirmed booking. Any refund and provider settlement are handled according to the cancellation policy.',
          accentColor: const Color(0xFFEF4444),
          badgeLabel: 'Cancelled',
        );
      case _ProviderTerminalKind.providerCancelledAfterPayment:
        return StatusCardPresentationModel(
          icon: Icons.gpp_bad_outlined,
          title: 'Cancelled by You',
          explanation: _hasActiveFinancialProcessing(cancellationRecord)
              ? 'You cancelled this confirmed booking. Refund and provider settlement updates will appear here as processing completes.'
              : 'You cancelled this confirmed booking. The customer refund and provider settlement are handled according to the cancellation policy.',
          accentColor: const Color(0xFFDC2626),
          badgeLabel: 'Cancelled',
        );
      case _ProviderTerminalKind.providerDeclined:
        return const StatusCardPresentationModel(
          icon: Icons.close_rounded,
          title: 'Declined by You',
          explanation:
              'You declined this request, so the booking was not confirmed and no payment was collected.',
          accentColor: Color(0xFFEF4444),
          badgeLabel: 'Declined',
        );
      case _ProviderTerminalKind.requestExpired:
        return const StatusCardPresentationModel(
          icon: Icons.event_busy_outlined,
          title: 'Request Expired',
          explanation:
              'The request was not confirmed within the response window and is now closed.',
          accentColor: Color(0xFF6B7280),
          badgeLabel: 'Expired',
        );
      case _ProviderTerminalKind.genericClosed:
        return const StatusCardPresentationModel(
          icon: Icons.info_outline_rounded,
          title: 'Booking Closed',
          explanation:
              'This booking reached a terminal state and is now read-only.',
          accentColor: Color(0xFF6B7280),
          badgeLabel: 'Closed',
        );
    }
  }

  static List<BookingTimelineStepModel> _buildTimeline(
    _ProviderTerminalKind kind,
    CanonicalBookingDocumentV3 booking,
    CanonicalBookingCancellationRecord? cancellationRecord,
  ) {
    final steps = <BookingTimelineStepModel>[];
    if (booking.lifecycle.requestedAt != null) {
      steps.add(
        BookingTimelineStepModel(
          label: 'Request submitted',
          timestamp: _dateTimeLabel(booking.lifecycle.requestedAt!),
        ),
      );
    }
    if (booking.lifecycle.respondedAt != null &&
        booking.lifecycle.providerResponseType ==
            ProviderResponseTypeV3.accept) {
      steps.add(
        BookingTimelineStepModel(
          label: 'Provider accepted',
          timestamp: _dateTimeLabel(booking.lifecycle.respondedAt!),
        ),
      );
    }
    if (booking.lifecycle.paidAt != null) {
      steps.add(
        BookingTimelineStepModel(
          label: 'Payment completed',
          timestamp: _dateTimeLabel(booking.lifecycle.paidAt!),
        ),
      );
    }
    switch (kind) {
      case _ProviderTerminalKind.paymentWindowExpired:
        if (booking.lifecycle.payDeadlineAt != null) {
          steps.add(
            BookingTimelineStepModel(
              label: 'Payment window expired',
              timestamp: _dateTimeLabel(booking.lifecycle.payDeadlineAt!),
              tone: BookingTimelineStepTone.warning,
              isHighlighted: true,
            ),
          );
        }
      case _ProviderTerminalKind.customerCancelledBeforePayment:
      case _ProviderTerminalKind.customerCancelledAfterPayment:
        final cancelledAt = _cancelledAt(booking, cancellationRecord);
        if (cancelledAt != null) {
          steps.add(
            BookingTimelineStepModel(
              label: 'Customer cancelled',
              timestamp: _dateTimeLabel(cancelledAt),
              tone: BookingTimelineStepTone.failure,
              isHighlighted: true,
            ),
          );
        }
      case _ProviderTerminalKind.providerCancelledAfterPayment:
        final cancelledAt = _cancelledAt(booking, cancellationRecord);
        if (cancelledAt != null) {
          steps.add(
            BookingTimelineStepModel(
              label: 'Provider cancelled',
              timestamp: _dateTimeLabel(cancelledAt),
              tone: BookingTimelineStepTone.failure,
              isHighlighted: true,
            ),
          );
        }
      case _ProviderTerminalKind.providerDeclined:
        if (booking.lifecycle.respondedAt != null) {
          steps.add(
            BookingTimelineStepModel(
              label: 'Provider declined',
              timestamp: _dateTimeLabel(booking.lifecycle.respondedAt!),
              tone: BookingTimelineStepTone.failure,
              isHighlighted: true,
            ),
          );
        }
      case _ProviderTerminalKind.requestExpired:
        if (booking.lifecycle.acceptDeadlineAt != null) {
          steps.add(
            BookingTimelineStepModel(
              label: 'Request expired',
              timestamp: _dateTimeLabel(booking.lifecycle.acceptDeadlineAt!),
              tone: BookingTimelineStepTone.warning,
              isHighlighted: true,
            ),
          );
        }
      case _ProviderTerminalKind.genericClosed:
        if (booking.lifecycle.finalizedAt != null) {
          steps.add(
            BookingTimelineStepModel(
              label: 'Booking closed',
              timestamp: _dateTimeLabel(booking.lifecycle.finalizedAt!),
              tone: BookingTimelineStepTone.neutral,
              isHighlighted: true,
            ),
          );
        }
    }

    if (_shouldShowRefundInitiated(cancellationRecord)) {
      steps.add(
        BookingTimelineStepModel(
          label: 'Refund initiated',
          timestamp: _dateTimeLabel(cancellationRecord!.createdAt!),
          tone: BookingTimelineStepTone.warning,
        ),
      );
    }
    if (_shouldShowRefundCompleted(cancellationRecord)) {
      steps.add(
        BookingTimelineStepModel(
          label: 'Refund completed',
          timestamp: _dateTimeLabel(cancellationRecord!.updatedAt!),
          tone: BookingTimelineStepTone.success,
        ),
      );
    }
    if (booking.payout.releasedAt != null) {
      steps.add(
        BookingTimelineStepModel(
          label: 'Settlement processed',
          timestamp: _dateTimeLabel(booking.payout.releasedAt!),
          tone: BookingTimelineStepTone.success,
        ),
      );
    }
    return steps;
  }

  static List<StatusSummaryRowModel> _buildOutcomeRows(
    _ProviderTerminalKind kind,
    CanonicalBookingDocumentV3 booking,
    CanonicalBookingCancellationRecord? cancellationRecord,
  ) {
    switch (kind) {
      case _ProviderTerminalKind.paymentWindowExpired:
        return const [
          StatusSummaryRowModel(
            label: 'Outcome',
            value: 'Payment window expired',
          ),
          StatusSummaryRowModel(label: 'Payment', value: 'Not completed'),
          StatusSummaryRowModel(
            label: 'Booking result',
            value: 'Request expired',
          ),
        ];
      case _ProviderTerminalKind.customerCancelledBeforePayment:
        return const [
          StatusSummaryRowModel(label: 'Cancelled by', value: 'Customer'),
          StatusSummaryRowModel(label: 'Payment', value: 'Not completed'),
          StatusSummaryRowModel(
            label: 'Booking result',
            value: 'Request cancelled',
          ),
        ];
      case _ProviderTerminalKind.customerCancelledAfterPayment:
      case _ProviderTerminalKind.providerCancelledAfterPayment:
        final rows = <StatusSummaryRowModel>[
          StatusSummaryRowModel(
            label: 'Cancelled by',
            value: kind == _ProviderTerminalKind.providerCancelledAfterPayment
                ? 'You'
                : 'Customer',
          ),
        ];
        final cancelledAt = _cancelledAt(booking, cancellationRecord);
        if (cancelledAt != null) {
          rows.add(
            StatusSummaryRowModel(
              label: 'Cancelled on',
              value: _dateTimeLabel(cancelledAt),
            ),
          );
        }
        final reason = _cancellationReason(booking, cancellationRecord);
        if (reason.isNotEmpty) {
          rows.add(StatusSummaryRowModel(label: 'Reason', value: reason));
        }
        rows.add(
          const StatusSummaryRowModel(
            label: 'Booking result',
            value: 'Cancelled',
          ),
        );
        return rows;
      case _ProviderTerminalKind.providerDeclined:
        return const [
          StatusSummaryRowModel(
            label: 'Outcome',
            value: 'Declined by provider',
          ),
          StatusSummaryRowModel(label: 'Payment', value: 'Not completed'),
          StatusSummaryRowModel(
            label: 'Booking result',
            value: 'Request declined',
          ),
        ];
      case _ProviderTerminalKind.requestExpired:
        return const [
          StatusSummaryRowModel(label: 'Outcome', value: 'Request expired'),
          StatusSummaryRowModel(label: 'Payment', value: 'Not completed'),
          StatusSummaryRowModel(
            label: 'Booking result',
            value: 'Request closed',
          ),
        ];
      case _ProviderTerminalKind.genericClosed:
        return const [
          StatusSummaryRowModel(label: 'Booking result', value: 'Closed'),
        ];
    }
  }

  static List<StatusFinancialRowModel> _buildFinancialRows(
    _ProviderTerminalKind kind,
    CanonicalBookingDocumentV3 booking,
    CanonicalBookingCancellationRecord? cancellationRecord,
  ) {
    final financials = booking.financials;
    switch (kind) {
      case _ProviderTerminalKind.paymentWindowExpired:
        return const [
          StatusFinancialRowModel(
            label: 'Customer payment',
            value: 'Not completed',
            valueTone: StatusFinancialValueTone.neutral,
          ),
          StatusFinancialRowModel(
            label: 'Provider payout',
            value: 'Not applicable',
            valueTone: StatusFinancialValueTone.neutral,
          ),
        ];
      case _ProviderTerminalKind.customerCancelledBeforePayment:
      case _ProviderTerminalKind.providerDeclined:
      case _ProviderTerminalKind.requestExpired:
        return const [
          StatusFinancialRowModel(
            label: 'Customer payment',
            value: 'Not collected',
            valueTone: StatusFinancialValueTone.neutral,
          ),
          StatusFinancialRowModel(
            label: 'Provider payout',
            value: 'Not applicable',
            valueTone: StatusFinancialValueTone.neutral,
          ),
        ];
      case _ProviderTerminalKind.customerCancelledAfterPayment:
      case _ProviderTerminalKind.providerCancelledAfterPayment:
        final rows = <StatusFinancialRowModel>[];
        final customerPaidPaise =
            financials?.customerPaidPaise ??
            cancellationRecord?.customerPaidPaise ??
            0;
        if (customerPaidPaise > 0) {
          rows.add(
            StatusFinancialRowModel(
              label: 'Customer paid',
              value: _money(customerPaidPaise),
            ),
          );
        }
        final refundStatus = cancellationRecord?.refundStatus.trim() ?? '';
        if (refundStatus.isNotEmpty) {
          rows.add(
            StatusFinancialRowModel(
              label: 'Refund status',
              value: _humanizeStatus(refundStatus),
              valueTone: _statusTone(refundStatus),
            ),
          );
        }
        final refundAmountPaise =
            cancellationRecord?.refundAmountPaise ??
            booking.cancellation.refundAmountPaise;
        if (refundAmountPaise > 0) {
          rows.add(
            StatusFinancialRowModel(
              label: 'Refund amount',
              value: _money(refundAmountPaise),
              valueTone: StatusFinancialValueTone.warning,
            ),
          );
        }
        final payoutStatus = booking.payout.status.trim();
        if (payoutStatus.isNotEmpty) {
          rows.add(
            StatusFinancialRowModel(
              label: 'Provider settlement status',
              value: _humanizeStatus(payoutStatus),
              valueTone: _statusTone(payoutStatus),
            ),
          );
        }
        final providerSettlementPaise = booking.payout.providerPayoutPaise > 0
            ? booking.payout.providerPayoutPaise
            : cancellationRecord?.providerCompensationPaise ??
                  booking.cancellation.providerCompensationPaise;
        if (providerSettlementPaise > 0) {
          rows.add(
            StatusFinancialRowModel(
              label: 'Provider settlement amount',
              value: _money(providerSettlementPaise),
            ),
          );
        }
        return rows;
      case _ProviderTerminalKind.genericClosed:
        return const [];
    }
  }

  static StatusImportantInformationModel _buildImportantInformation(
    _ProviderTerminalKind kind,
    CanonicalBookingDocumentV3 booking,
    CanonicalBookingCancellationRecord? cancellationRecord,
  ) {
    final hasProcessing =
        _hasActiveFinancialProcessing(cancellationRecord) ||
        _hasActivePayoutProcessing(booking);
    return StatusImportantInformationModel(
      title: hasProcessing ? 'Processing updates' : 'Read-only record',
      body: hasProcessing
          ? 'This booking is closed. Refund and settlement updates will appear here when processing is complete.'
          : 'This booking is closed and is shown here for your records. No further action is required.',
    );
  }

  static bool _hasConfirmedPayment(CanonicalBookingDocumentV3 booking) {
    return booking.lifecycle.paidAt != null ||
        booking.financials?.customerPaidPaise != null &&
            booking.financials!.customerPaidPaise > 0;
  }

  static bool _isCustomerCancellation(
    CanonicalBookingDocumentV3 booking,
    CanonicalBookingCancellationRecord? cancellationRecord,
  ) {
    if (cancellationRecord != null) {
      return cancellationRecord.actorType.trim().toUpperCase() == 'CUSTOMER' ||
          cancellationRecord.actorType.trim().toUpperCase() == 'PARENT';
    }
    return (booking.cancellation.cancelledBy ?? '').trim().toUpperCase() ==
            'CUSTOMER' ||
        (booking.cancellation.cancelledBy ?? '').trim().toUpperCase() ==
            'PARENT';
  }

  static String _customerLabel(CanonicalBookingDocumentV3 booking) {
    final first = booking.participants.parent.displayFirstName.trim();
    final lastInitial = booking.participants.parent.lastInitial.trim();
    final parts = <String>[
      if (first.isNotEmpty) first,
      if (lastInitial.isNotEmpty) '$lastInitial.',
    ];
    return parts.isEmpty ? 'Customer' : parts.join(' ');
  }

  static DateTime? _scheduleStart(CanonicalBookingDocumentV3 booking) {
    final schedule = booking.schedule;
    if (schedule is CanonicalSlotBookingScheduleV3) {
      return schedule.scheduledStartAt;
    }
    if (schedule is CanonicalRangeBookingScheduleV3) {
      return schedule.checkInDateTime;
    }
    return null;
  }

  static DateTime? _scheduleEnd(CanonicalBookingDocumentV3 booking) {
    final schedule = booking.schedule;
    if (schedule is CanonicalSlotBookingScheduleV3) {
      return schedule.scheduledEndAt;
    }
    if (schedule is CanonicalRangeBookingScheduleV3) {
      return schedule.checkOutDateTime;
    }
    return null;
  }

  static String _bookingDateLabel(CanonicalBookingDocumentV3 booking) {
    final start = _scheduleStart(booking);
    return start == null ? 'Pending' : _calendarDate(start);
  }

  static String _bookingTimeLabel(CanonicalBookingDocumentV3 booking) {
    final start = _scheduleStart(booking);
    final end = _scheduleEnd(booking);
    if (start == null || end == null) return 'Pending';
    return '${_timeLabel(start)} - ${_timeLabel(end)}';
  }

  static String _bookingDurationLabel(CanonicalBookingDocumentV3 booking) {
    final schedule = booking.schedule;
    if (schedule is CanonicalSlotBookingScheduleV3) {
      final minutes = schedule.totalDurationMinutes > 0
          ? schedule.totalDurationMinutes
          : (booking.statistics.totalDurationMinutes ?? 0);
      return minutes > 0 ? '$minutes min' : 'Pending';
    }
    if (schedule is CanonicalRangeBookingScheduleV3) {
      return schedule.nights > 0
          ? '${schedule.nights} night${schedule.nights == 1 ? '' : 's'}'
          : 'Pending';
    }
    return 'Pending';
  }

  static String? _slotCountLabel(CanonicalBookingDocumentV3 booking) {
    final schedule = booking.schedule;
    if (schedule is CanonicalSlotBookingScheduleV3) {
      final slotCount = schedule.slotCount > 0
          ? schedule.slotCount
          : (booking.statistics.selectedSlotCount ?? 0);
      if (slotCount > 0) {
        return '$slotCount slot${slotCount == 1 ? '' : 's'}';
      }
    }
    return null;
  }

  static DateTime? _cancelledAt(
    CanonicalBookingDocumentV3 booking,
    CanonicalBookingCancellationRecord? cancellationRecord,
  ) {
    return cancellationRecord?.effectiveAt ??
        cancellationRecord?.requestedAt ??
        booking.cancellation.cancelledAt ??
        booking.lifecycle.cancelledAt;
  }

  static String _cancellationReason(
    CanonicalBookingDocumentV3 booking,
    CanonicalBookingCancellationRecord? cancellationRecord,
  ) {
    final reason =
        cancellationRecord?.reasonText.trim() ??
        booking.cancellation.cancelReasonText.trim();
    return reason;
  }

  static bool _shouldShowRefundInitiated(
    CanonicalBookingCancellationRecord? cancellationRecord,
  ) {
    if (cancellationRecord == null || cancellationRecord.createdAt == null) {
      return false;
    }
    return cancellationRecord.refundStatus.trim().isNotEmpty &&
        cancellationRecord.refundStatus.trim().toLowerCase() !=
            'not_applicable';
  }

  static bool _shouldShowRefundCompleted(
    CanonicalBookingCancellationRecord? cancellationRecord,
  ) {
    if (cancellationRecord == null || cancellationRecord.updatedAt == null) {
      return false;
    }
    final status = cancellationRecord.refundStatus.trim().toLowerCase();
    return status == 'completed' || status == 'refunded' || status == 'success';
  }

  static bool _hasActiveFinancialProcessing(
    CanonicalBookingCancellationRecord? cancellationRecord,
  ) {
    if (cancellationRecord == null) return false;
    final status = cancellationRecord.refundStatus.trim().toLowerCase();
    return status == 'pending' ||
        status == 'processing' ||
        status == 'initiated' ||
        status == 'queued';
  }

  static bool _hasActivePayoutProcessing(CanonicalBookingDocumentV3 booking) {
    final payoutStatus = booking.payout.status.trim().toLowerCase();
    return payoutStatus == 'processing' ||
        payoutStatus == 'ready' ||
        payoutStatus == 'pending';
  }

  static String _calendarDate(DateTime value) {
    final local = value.toLocal();
    return '${local.day} ${_monthLabel(local.month)} ${local.year}';
  }

  static String _dateTimeLabel(DateTime value) {
    return '${_calendarDate(value)} · ${_timeLabel(value)}';
  }

  static String _timeLabel(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour > 12
        ? local.hour - 12
        : (local.hour == 0 ? 12 : local.hour);
    final minutes = local.minute.toString().padLeft(2, '0');
    final meridiem = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minutes $meridiem';
  }

  static String _monthLabel(int month) {
    const months = <String>[
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
    if (month < 1 || month > 12) return month.toString();
    return months[month - 1];
  }

  static String _money(int paise) {
    final amount = paise / 100;
    final decimals = paise % 100 == 0 ? 0 : 2;
    return '₹${amount.toStringAsFixed(decimals)}';
  }

  static String _humanizeStatus(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return cleaned;
    return cleaned
        .split(RegExp(r'[_\s]+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part.substring(0, 1).toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  static StatusFinancialValueTone _statusTone(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'completed' ||
        normalized == 'paid' ||
        normalized == 'released' ||
        normalized == 'refunded' ||
        normalized == 'success') {
      return StatusFinancialValueTone.positive;
    }
    if (normalized == 'pending' ||
        normalized == 'processing' ||
        normalized == 'initiated' ||
        normalized == 'queued' ||
        normalized == 'ready') {
      return StatusFinancialValueTone.warning;
    }
    if (normalized == 'failed' || normalized == 'cancelled') {
      return StatusFinancialValueTone.danger;
    }
    return StatusFinancialValueTone.neutral;
Bye  }
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
