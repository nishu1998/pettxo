import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../settings/presentation/screens/legal_policies_screen.dart';
import '../../../messages/presentation/screens/chat_detail_screen.dart';
import '../controllers/canonical_booking_private_controller.dart';
import '../../data/repositories/booking_repository.dart';
import '../../domain/models/booking_document_v3.dart';
import '../../domain/models/booking_read_model.dart';
import '../../domain/models/canonical_booking_cancellation_models.dart';
import '../../domain/models/canonical_booking_private.dart';
import '../../domain/models/booking_v3_models.dart';
import '../../domain/utils/booking_request_attempt_id.dart';
import '../utils/canonical_booking_presentation_state.dart';
import '../widgets/canonical_booking_status_detail_template.dart';

class CanonicalBookingDetailScreen extends StatefulWidget {
  const CanonicalBookingDetailScreen({
    super.key,
    required this.bookingId,
    this.repository,
    this.privateController,
    this.currentUserIdOverride,
    this.onOpenChatOverride,
    this.canLaunchUrlOverride,
    this.launchUrlOverride,
  });

  final String bookingId;
  final BookingRepository? repository;
  final CanonicalBookingPrivateController? privateController;
  final String? currentUserIdOverride;
  final Future<void> Function(String bookingId)? onOpenChatOverride;
  final Future<bool> Function(Uri uri)? canLaunchUrlOverride;
  final Future<bool> Function(Uri uri, {LaunchMode mode})? launchUrlOverride;

  @override
  State<CanonicalBookingDetailScreen> createState() =>
      _CanonicalBookingDetailScreenState();
}

class _CanonicalBookingDetailScreenState
    extends State<CanonicalBookingDetailScreen> {
  late final BookingRepository _repository =
      widget.repository ?? BookingRepository();
  late final CanonicalBookingPrivateController _privateController =
      widget.privateController ??
      CanonicalBookingPrivateController(
        privateLoader: _repository.watchCanonicalBookingPrivate,
        authStateStreamFactory: FirebaseAuth.instance.authStateChanges,
      );
  late final bool _ownsPrivateController = widget.privateController == null;
  bool _isCancelling = false;
  bool _isLoadingPreview = false;
  bool _isStartingService = false;
  bool _isCompletingService = false;
  bool _isSubmittingReview = false;
  bool _isSubmittingDispute = false;
  bool _isOpeningChat = false;
  bool _reviewSubmittedLocally = false;
  int _privateRetryTick = 0;
  StreamSubscription<BookingReadModel?>? _serviceStartStateSubscription;
  final TextEditingController _reviewCommentController =
      TextEditingController();
  final TextEditingController _disputeReasonController =
      TextEditingController();
  final TextEditingController _disputeDescriptionController =
      TextEditingController();
  int _reviewRating = 0;

  String get _currentUserId =>
      widget.currentUserIdOverride?.trim().isNotEmpty == true
      ? widget.currentUserIdOverride!.trim()
      : FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  @override
  void dispose() {
    _reviewCommentController.dispose();
    _disputeReasonController.dispose();
    _disputeDescriptionController.dispose();
    _serviceStartStateSubscription?.cancel();
    if (_ownsPrivateController) {
      _privateController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CanonicalBookingStatusDetailTopBar(
        title: 'Booking Details',
      ),
      body: StreamBuilder<BookingReadModel?>(
        stream: _repository.watchCanonicalBooking(widget.bookingId),
        builder: (context, snapshot) {
          final readModel = snapshot.data;
          final booking = readModel is CanonicalBookingReadModel
              ? readModel.booking
              : null;
          if (booking == null) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final currentUid = _currentUserId;
          final isParent = booking.parentId == currentUid;
          final userIsProvider = booking.providerId == currentUid;
          final effectiveState = effectiveCanonicalBookingPresentationState(
            booking,
          );
          final isPaidConfirmedOrLater =
              booking.lifecycle.paidAt != null &&
              (booking.state == CanonicalBookingStateV3.confirmed ||
                  booking.state == CanonicalBookingStateV3.inProgress ||
                  booking.state ==
                      CanonicalBookingStateV3.completedPendingReview ||
                  booking.state == CanonicalBookingStateV3.completedFinal);
          final canReadPrivate = isPaidConfirmedOrLater && isParent;
          final canReadParticipantPrivate = isPaidConfirmedOrLater;
          _privateController.bind(
            bookingId: widget.bookingId,
            shouldLoadPrivate: canReadPrivate,
          );

          return StreamBuilder<CanonicalBookingPrivateParticipantsData?>(
            key: ValueKey(
              'canonical-private-participants-${widget.bookingId}-$_privateRetryTick',
            ),
            stream: canReadParticipantPrivate
                ? _repository.watchCanonicalBookingPrivateParticipants(
                    widget.bookingId,
                  )
                : Stream.value(null),
            builder: (context, participantSnapshot) {
              return AnimatedBuilder(
                animation: _privateController,
                builder: (context, _) {
                  final privateState = _privateController.state;
                  if (_shouldUseRedesignedCustomerBookingDetails(
                    booking,
                    isParent,
                  )) {
                    return _buildCustomerBookingDetailsExperience(
                      booking: booking,
                      participantPrivateData: participantSnapshot.data,
                      participantErrorMessage: participantSnapshot.hasError
                          ? 'Paid-only booking details could not be loaded right now.'
                          : null,
                      otpPrivateData: privateState.privateData,
                      isOtpLoading: privateState.isLoading,
                      otpErrorMessage: privateState.errorMessage,
                    );
                  }
                  if (_shouldUseRedesignedProviderBookingDetails(
                    booking,
                    userIsProvider,
                  )) {
                    return _buildProviderBookingDetailsExperience(
                      booking: booking,
                      participantPrivateData: participantSnapshot.data,
                      participantErrorMessage: participantSnapshot.hasError
                          ? 'Paid-only booking details could not be loaded right now.'
                          : null,
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                    children: [
                      _HeroCard(booking: booking, currentUid: currentUid),
                      const SizedBox(height: 14),
                      _CancellationStatusSection(
                        bookingId: widget.bookingId,
                        repository: _repository,
                        booking: booking,
                      ),
                      if (effectiveState == CanonicalBookingStateV3.noShow) ...[
                        const SizedBox(height: 14),
                        _NoShowStatusSection(booking: booking),
                      ],
                      if (booking.state ==
                              CanonicalBookingStateV3.completedPendingReview ||
                          booking.state ==
                              CanonicalBookingStateV3.completedFinal) ...[
                        const SizedBox(height: 14),
                        _CompletionStatusSection(
                          booking: booking,
                          isParent: isParent,
                          isProvider: userIsProvider,
                          reviewSubmittedLocally: _reviewSubmittedLocally,
                          isSubmittingReview: _isSubmittingReview,
                          isSubmittingDispute: _isSubmittingDispute,
                          onSubmitReview:
                              booking.state ==
                                      CanonicalBookingStateV3
                                          .completedPendingReview &&
                                  isParent
                              ? () => _showReviewSheet(booking)
                              : null,
                          onRaiseDispute:
                              booking.state ==
                                      CanonicalBookingStateV3
                                          .completedPendingReview &&
                                  isParent &&
                                  booking.dispute.status.trim().toLowerCase() !=
                                      'open'
                              ? () => _showDisputeSheet(booking)
                              : null,
                        ),
                      ],
                      const SizedBox(height: 14),
                      _InfoCard(
                        title: 'Service',
                        rows: [
                          _InfoRow('Title', booking.service.serviceTitle),
                          _InfoRow(
                            'Provider',
                            booking.participants.provider.displayName,
                          ),
                          if (isParent &&
                              participantSnapshot
                                      .data
                                      ?.hasProviderPhoneNumber ==
                                  true)
                            _ActionInfoRow(
                              label: 'Provider contact',
                              value:
                                  participantSnapshot.data!.providerPhoneNumber,
                              actionLabel: 'Call provider',
                              onTap: () => _openPhone(
                                participantSnapshot.data!.providerPhoneNumber,
                              ),
                            ),
                          _InfoRow('Status', _statusLabel(booking)),
                          _InfoRow('Payment', _paymentStatusLabel(booking)),
                          _InfoRow('Amount paid', _money(booking)),
                          _InfoRow(
                            'Confirmed at',
                            _dateTime(booking.lifecycle.paidAt),
                          ),
                          if (booking.lifecycle.otpEnteredAt != null)
                            _InfoRow(
                              'Started at',
                              _dateTime(booking.lifecycle.otpEnteredAt),
                            ),
                        ],
                      ),
                      if (isParent &&
                          participantSnapshot.data?.hasAddress == true) ...[
                        const SizedBox(height: 14),
                        _AddressCard(
                          address: participantSnapshot.data!.exactAddress,
                          onTapDirections: () =>
                              _openMap(participantSnapshot.data!),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _InfoCard(
                        title: 'Schedule',
                        rows: _scheduleRows(booking),
                      ),
                      const SizedBox(height: 14),
                      _PrivateSection(
                        booking: booking,
                        otpPrivateData: privateState.privateData,
                        participantPrivateData: participantSnapshot.data,
                        isOtpLoading: privateState.isLoading,
                        otpErrorMessage: privateState.errorMessage,
                        participantErrorMessage: participantSnapshot.hasError
                            ? 'Paid-only booking details could not be loaded right now.'
                            : null,
                        currentUid: currentUid,
                        onRetry: _retryPrivateReads,
                        onCallPhone: (phone) => _openPhone(phone),
                        onOpenMap: (details) => _openMap(details),
                      ),
                      if (userIsProvider &&
                          effectiveCanonicalBookingPresentationState(booking) ==
                              CanonicalBookingStateV3.confirmed &&
                          booking.lifecycle.paidAt != null) ...[
                        const SizedBox(height: 14),
                        _ProviderServiceStartSection(
                          isVerifying: _isStartingService,
                          onEnterOtp: _isStartingService
                              ? null
                              : () => _startServiceFlow(
                                  bookingId: widget.bookingId,
                                ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _ChatSection(
                        isParent: isParent,
                        isUnlocked: booking.privacy.chatUnlockedAt != null,
                        isOpening: _isOpeningChat,
                        onOpenChat: booking.privacy.chatUnlockedAt != null
                            ? () => _openBookingChat(widget.bookingId)
                            : null,
                      ),
                      const SizedBox(height: 16),
                      _buildActions(booking),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  static String _money(CanonicalBookingDocumentV3 booking) {
    final amountPaise = booking.financials?.customerPaidPaise ?? 0;
    return '₹${(amountPaise / 100).toStringAsFixed(amountPaise % 100 == 0 ? 0 : 2)}';
  }

  static String _dateTime(DateTime? value) {
    if (value == null) return 'Pending';
    final local = value.toLocal();
    return '${local.day}/${local.month}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  static List<Widget> _scheduleRows(CanonicalBookingDocumentV3 booking) {
    final rows = <Widget>[_InfoRow('Type', _bookingTypeLabel(booking))];
    final schedule = booking.schedule;
    if (schedule is CanonicalSlotBookingScheduleV3) {
      if (!_hasValidSlotWindow(schedule)) {
        rows.add(const _InfoRow('Window', 'Schedule unavailable'));
        return rows;
      }
      rows.add(_InfoRow('Date', _calendarDate(schedule.scheduledStartAt)));
      rows.add(
        _InfoRow(
          'Time',
          '${_timeOnly(schedule.scheduledStartAt)} to ${_timeOnly(schedule.scheduledEndAt)}',
        ),
      );
      rows.add(
        _InfoRow(
          'Duration',
          _minutesLabel(
            schedule.totalDurationMinutes > 0
                ? schedule.totalDurationMinutes
                : booking.statistics.totalDurationMinutes,
          ),
        ),
      );
      if (schedule.slotCount > 1) {
        rows.add(_InfoRow('Slots', '${schedule.slotCount} continuous slots'));
      }
      return rows;
    }
    if (schedule is CanonicalRangeBookingScheduleV3) {
      if (!_hasValidRangeWindow(schedule)) {
        rows.add(const _InfoRow('Window', 'Schedule unavailable'));
        return rows;
      }
      rows.add(
        _InfoRow('Check-in', _dateTimeWithMeridiem(schedule.checkInDateTime)),
      );
      rows.add(
        _InfoRow('Check-out', _dateTimeWithMeridiem(schedule.checkOutDateTime)),
      );
      rows.add(_InfoRow('Duration', _nightsLabel(schedule.nights)));
      return rows;
    }
    rows.add(const _InfoRow('Window', 'Schedule unavailable'));
    return rows;
  }

  static String _bookingTypeLabel(CanonicalBookingDocumentV3 booking) {
    return switch (booking.bookingType) {
      BookingV3Type.slot => 'Single visit',
      BookingV3Type.range => 'Stay booking',
    };
  }

  static bool _hasValidSlotWindow(CanonicalSlotBookingScheduleV3 schedule) {
    return schedule.scheduledEndAt.isAfter(schedule.scheduledStartAt);
  }

  static bool _hasValidRangeWindow(CanonicalRangeBookingScheduleV3 schedule) {
    return schedule.checkOutDateTime.isAfter(schedule.checkInDateTime);
  }

  static String _calendarDate(DateTime value) {
    final local = value.toLocal();
    return '${local.day} ${_monthLabel(local.month)} ${local.year}';
  }

  static String _dateTimeWithMeridiem(DateTime value) {
    return '${_calendarDate(value)} ${_timeOnly(value)}';
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

  static String _minutesLabel(int? minutes) {
    if (minutes == null || minutes <= 0) return 'Pending';
    return '$minutes min';
  }

  static String _nightsLabel(int nights) {
    if (nights <= 0) return 'Pending';
    return nights == 1 ? '1 night' : '$nights nights';
  }

  static String _timeOnly(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour > 12
        ? local.hour - 12
        : (local.hour == 0 ? 12 : local.hour);
    final minutes = local.minute.toString().padLeft(2, '0');
    final meridiem = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minutes $meridiem';
  }

  static String _statusLabel(CanonicalBookingDocumentV3 booking) {
    return switch (effectiveCanonicalBookingPresentationState(booking)) {
      CanonicalBookingStateV3.confirmed => 'Confirmed',
      CanonicalBookingStateV3.inProgress => 'In progress',
      CanonicalBookingStateV3.completedPendingReview => 'Completed',
      CanonicalBookingStateV3.completedFinal => 'Completed',
      CanonicalBookingStateV3.noShow => 'No show',
      _ => booking.state.name,
    };
  }

  static String _paymentStatusLabel(CanonicalBookingDocumentV3 booking) {
    return booking.lifecycle.paidAt != null
        ? 'Payment confirmed'
        : 'Payment pending';
  }

  void _retryPrivateReads() {
    if (!mounted) return;
    setState(() => _privateRetryTick += 1);
    _privateController.retry();
  }

  bool _shouldUseRedesignedCustomerBookingDetails(
    CanonicalBookingDocumentV3 booking,
    bool isParent,
  ) {
    if (!isParent) return false;
    final effectiveState = effectiveCanonicalBookingPresentationState(booking);
    return effectiveState == CanonicalBookingStateV3.confirmed ||
        effectiveState == CanonicalBookingStateV3.inProgress ||
        effectiveState == CanonicalBookingStateV3.noShow ||
        effectiveState == CanonicalBookingStateV3.completedPendingReview ||
        effectiveState == CanonicalBookingStateV3.completedFinal;
  }

  bool _shouldUseRedesignedProviderBookingDetails(
    CanonicalBookingDocumentV3 booking,
    bool isProvider,
  ) {
    if (!isProvider) return false;
    final effectiveState = effectiveCanonicalBookingPresentationState(booking);
    return effectiveState == CanonicalBookingStateV3.confirmed ||
        effectiveState == CanonicalBookingStateV3.inProgress ||
        effectiveState == CanonicalBookingStateV3.noShow ||
        effectiveState == CanonicalBookingStateV3.completedPendingReview ||
        effectiveState == CanonicalBookingStateV3.completedFinal;
  }

  bool _shouldShowCompletedCustomerAddressSection(
    CanonicalBookingPrivateParticipantsData? participantPrivateData,
    String? participantErrorMessage,
  ) {
    return participantPrivateData?.hasAddress == true ||
        participantPrivateData?.hasProviderPhoneNumber == true ||
        (participantErrorMessage?.trim().isNotEmpty ?? false);
  }

  Widget _buildCustomerBookingDetailsExperience({
    required CanonicalBookingDocumentV3 booking,
    required CanonicalBookingPrivateParticipantsData? participantPrivateData,
    required String? participantErrorMessage,
    required CanonicalBookingPrivateData? otpPrivateData,
    required bool isOtpLoading,
    required String? otpErrorMessage,
  }) {
    final isCompletedState =
        booking.state == CanonicalBookingStateV3.completedPendingReview ||
        booking.state == CanonicalBookingStateV3.completedFinal;
    final effectiveState = effectiveCanonicalBookingPresentationState(booking);
    if (isCompletedState) {
      return _buildCustomerCompletedBookingDetailsExperience(
        booking: booking,
        participantPrivateData: participantPrivateData,
        participantErrorMessage: participantErrorMessage,
      );
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          const BookingDetailsSectionLabel('Booking summary'),
          const SizedBox(height: 10),
          BookingSummaryCard(rows: _buildCustomerSummaryRows(booking)),
          const SizedBox(height: 16),
          const BookingDetailsSectionLabel('Booking status'),
          const SizedBox(height: 10),
          BookingStatusCard(model: _buildCustomerStatusCard(booking)),
          const SizedBox(height: 16),
          const BookingDetailsSectionLabel('Booking timeline'),
          const SizedBox(height: 10),
          BookingTimelineCard(steps: _buildCustomerTimeline(booking)),
          if (effectiveState == CanonicalBookingStateV3.noShow) ...[
            const SizedBox(height: 16),
            _NoShowStatusSection(booking: booking),
          ],
          if (effectiveState != CanonicalBookingStateV3.noShow) ...[
            const SizedBox(height: 16),
            const BookingDetailsSectionLabel('Service-start OTP'),
            const SizedBox(height: 10),
            _CustomerOtpSectionCard(
              booking: booking,
              otpPrivateData: otpPrivateData,
              isLoading: isOtpLoading,
              errorMessage: otpErrorMessage,
              providerName: booking.participants.provider.displayName,
              onRetry: _retryPrivateReads,
            ),
          ],
          if (_shouldShowLocationSection(
            participantPrivateData,
            participantErrorMessage,
          )) ...[
            const SizedBox(height: 16),
            const BookingDetailsSectionLabel('Service location'),
            const SizedBox(height: 10),
            _CustomerLocationCard(
              participantPrivateData: participantPrivateData,
              errorMessage: participantErrorMessage,
              onOpenMap: _hasDirectionsData(participantPrivateData)
                  ? () => _openMap(participantPrivateData!)
                  : null,
              onCallProvider:
                  participantPrivateData?.hasProviderPhoneNumber == true
                  ? () =>
                        _openPhone(participantPrivateData!.providerPhoneNumber)
                  : null,
              onRetry: participantErrorMessage == null
                  ? null
                  : _retryPrivateReads,
            ),
          ],
          const SizedBox(height: 16),
          const BookingDetailsSectionLabel('Payment summary'),
          const SizedBox(height: 10),
          FinancialSummaryCard(rows: _buildCustomerPaymentRows(booking)),
          const SizedBox(height: 16),
          const BookingDetailsSectionLabel('Booking chat'),
          const SizedBox(height: 10),
          _CustomerChatCard(
            isOpening: _isOpeningChat,
            isUnlocked: booking.privacy.chatUnlockedAt != null,
            onOpenChat: booking.privacy.chatUnlockedAt != null
                ? () => _openBookingChat(widget.bookingId)
                : null,
          ),
          const SizedBox(height: 16),
          const BookingDetailsSectionLabel('Cancellation'),
          const SizedBox(height: 10),
          _CustomerCancellationCard(
            canCancel: effectiveState == CanonicalBookingStateV3.confirmed,
            isBusy: _isCancelling || _isLoadingPreview || _isStartingService,
            onReadPolicy: () => Navigator.of(
              context,
            ).pushNamed(LegalPoliciesCatalog.cancellationPolicy.routeName),
            onCancel: effectiveState == CanonicalBookingStateV3.confirmed
                ? () => _startCancellationFlow(
                    bookingId: widget.bookingId,
                    actorType: 'CUSTOMER',
                    isProvider: false,
                  )
                : null,
          ),
          const SizedBox(height: 16),
          const BookingDetailsSectionLabel('Important information'),
          const SizedBox(height: 10),
          ImportantInformationCard(
            model: StatusImportantInformationModel(
              title: effectiveState == CanonicalBookingStateV3.inProgress
                  ? 'Service in progress'
                  : effectiveState == CanonicalBookingStateV3.noShow
                  ? 'OTP no longer available'
                  : 'OTP verification required',
              body: effectiveState == CanonicalBookingStateV3.inProgress
                  ? 'The service clock started after successful OTP verification.'
                  : effectiveState == CanonicalBookingStateV3.noShow
                  ? 'The service window ended before OTP verification, so the booking was marked as no-show.'
                  : 'OTP verification is required to start the service. The service clock starts only after successful OTP verification.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCompletedBookingDetailsExperience({
    required CanonicalBookingDocumentV3 booking,
    required CanonicalBookingPrivateParticipantsData? participantPrivateData,
    required String? participantErrorMessage,
  }) {
    final disputeDeadlineAt =
        booking.lifecycle.disputeDeadlineAt ??
        booking.lifecycle.reviewWindowEndsAt;
    final reviewSubmitted =
        _reviewSubmittedLocally || booking.hasSubmittedReview;
    final hasOpenDispute =
        booking.dispute.status.trim().toLowerCase() == 'open';
    final disputeWindowActive =
        disputeDeadlineAt != null && !DateTime.now().isAfter(disputeDeadlineAt);
    final canLeaveReview =
        (booking.state == CanonicalBookingStateV3.completedPendingReview ||
            booking.state == CanonicalBookingStateV3.completedFinal) &&
        !reviewSubmitted &&
        !_isSubmittingReview;
    final canRaiseDispute =
        booking.state == CanonicalBookingStateV3.completedPendingReview &&
        disputeWindowActive &&
        !hasOpenDispute &&
        !_isSubmittingDispute;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          _CustomerCompletedSummaryCard(
            serviceTitle: booking.service.serviceTitle,
            providerName: booking.participants.provider.displayName,
          ),
          const SizedBox(height: 24),
          const BookingDetailsSectionLabel('Completion status'),
          const SizedBox(height: 10),
          _CustomerCompletedStatusCard(
            disputeDeadlineText: disputeDeadlineAt != null
                ? _dateTimeWithMeridiem(disputeDeadlineAt)
                : 'Not available',
            canLeaveReview: canLeaveReview,
            canRaiseDispute: canRaiseDispute,
            reviewSubmitted: reviewSubmitted,
            disputeOpen: hasOpenDispute,
            disputeWindowActive: disputeWindowActive,
            isSubmittingReview: _isSubmittingReview,
            isSubmittingDispute: _isSubmittingDispute,
            onLeaveReview: canLeaveReview
                ? () => _showReviewSheet(booking)
                : null,
            onRaiseDispute: canRaiseDispute
                ? () => _showDisputeSheet(booking)
                : null,
          ),
          const SizedBox(height: 24),
          const BookingDetailsSectionLabel('Service'),
          const SizedBox(height: 10),
          _CustomerCompletedServiceCard(
            serviceTitle: booking.service.serviceTitle,
            providerName: booking.participants.provider.displayName,
            paymentLabel: _paymentStatusLabel(booking),
            amountPaid: _money(booking),
            confirmedAt: _dateTimeWithMeridiem(
              booking.lifecycle.paidAt ?? booking.createdAt,
            ),
          ),
          const SizedBox(height: 24),
          const BookingDetailsSectionLabel('Schedule'),
          const SizedBox(height: 10),
          BookingSummaryCard(
            rows: _buildCustomerCompletedScheduleRows(booking),
          ),
          const SizedBox(height: 24),
          if (_shouldShowCompletedCustomerAddressSection(
            participantPrivateData,
            participantErrorMessage,
          )) ...[
            const BookingDetailsSectionLabel('Service address'),
            const SizedBox(height: 10),
            _CustomerCompletedAddressCard(
              participantPrivateData: participantPrivateData,
              errorMessage: participantErrorMessage,
              onOpenMap: _hasDirectionsData(participantPrivateData)
                  ? () => _openMap(participantPrivateData!)
                  : null,
              onCallProvider:
                  participantPrivateData?.hasProviderPhoneNumber == true
                  ? () =>
                        _openPhone(participantPrivateData!.providerPhoneNumber)
                  : null,
              onRetry: participantErrorMessage == null
                  ? null
                  : _retryPrivateReads,
            ),
            const SizedBox(height: 24),
          ],
          const BookingDetailsSectionLabel('Booking chat'),
          const SizedBox(height: 10),
          _CustomerCompletedChatCard(
            isOpening: _isOpeningChat,
            isUnlocked: booking.privacy.chatUnlockedAt != null,
            onOpenChat: booking.privacy.chatUnlockedAt != null
                ? () => _openBookingChat(widget.bookingId)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildProviderBookingDetailsExperience({
    required CanonicalBookingDocumentV3 booking,
    required CanonicalBookingPrivateParticipantsData? participantPrivateData,
    required String? participantErrorMessage,
  }) {
    final effectiveState = effectiveCanonicalBookingPresentationState(booking);
    final isCompletedState =
        booking.state == CanonicalBookingStateV3.completedPendingReview ||
        booking.state == CanonicalBookingStateV3.completedFinal;
    if (isCompletedState) {
      return _buildProviderCompletedBookingDetailsExperience(
        booking: booking,
        participantPrivateData: participantPrivateData,
        participantErrorMessage: participantErrorMessage,
      );
    }

    final canCancel = effectiveState == CanonicalBookingStateV3.confirmed;
    final canComplete = effectiveState == CanonicalBookingStateV3.inProgress;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          const BookingDetailsSectionLabel('Booking status'),
          const SizedBox(height: 10),
          BookingStatusCard(model: _buildProviderStatusCard(booking)),
          const SizedBox(height: 16),
          const BookingDetailsSectionLabel('Booking summary'),
          const SizedBox(height: 10),
          BookingSummaryCard(rows: _buildProviderSummaryRows(booking)),
          const SizedBox(height: 16),
          const BookingDetailsSectionLabel('Booking timeline'),
          const SizedBox(height: 10),
          BookingTimelineCard(steps: _buildProviderTimeline(booking)),
          const SizedBox(height: 16),
          const BookingDetailsSectionLabel('Service details'),
          const SizedBox(height: 10),
          _ProviderServiceDetailsCard(
            participantPrivateData: participantPrivateData,
            errorMessage: participantErrorMessage,
            onOpenMap: _hasDirectionsData(participantPrivateData)
                ? () => _openMap(participantPrivateData!)
                : null,
            onCallCustomer: participantPrivateData?.hasPhoneNumber == true
                ? () => _openPhone(participantPrivateData!.phoneNumber)
                : null,
            onRetry: participantErrorMessage == null
                ? null
                : _retryPrivateReads,
          ),
          if (effectiveState != CanonicalBookingStateV3.noShow) ...[
            const SizedBox(height: 16),
            const BookingDetailsSectionLabel('Service start'),
            const SizedBox(height: 10),
            _ProviderUnifiedServiceActionCard(
              booking: booking,
              isBusy: _isStartingService || _isCompletingService,
              onEnterOtp: effectiveState == CanonicalBookingStateV3.confirmed
                  ? () => _startServiceFlow(bookingId: widget.bookingId)
                  : null,
              onCompleteService: canComplete
                  ? () => _completeServiceFlow(bookingId: widget.bookingId)
                  : null,
            ),
          ],
          const SizedBox(height: 16),
          const BookingDetailsSectionLabel('Booking chat'),
          const SizedBox(height: 10),
          _ProviderBookingChatCard(
            isOpening: _isOpeningChat,
            isUnlocked: booking.privacy.chatUnlockedAt != null,
            onOpenChat: booking.privacy.chatUnlockedAt != null
                ? () => _openBookingChat(widget.bookingId)
                : null,
          ),
          const SizedBox(height: 16),
          const BookingDetailsSectionLabel('Cancellation'),
          const SizedBox(height: 10),
          _ProviderCancellationCard(
            canCancel: canCancel,
            isBusy: _isCancelling || _isLoadingPreview || _isStartingService,
            onCancel: canCancel
                ? () => _startCancellationFlow(
                    bookingId: widget.bookingId,
                    actorType: 'PROVIDER',
                    isProvider: true,
                  )
                : null,
          ),
          const SizedBox(height: 16),
          const BookingDetailsSectionLabel('Important information'),
          const SizedBox(height: 10),
          ImportantInformationCard(
            model: StatusImportantInformationModel(
              title: booking.state == CanonicalBookingStateV3.inProgress
                  ? 'Service already started'
                  : 'OTP verification required',
              body: booking.state == CanonicalBookingStateV3.inProgress
                  ? 'This booking officially started after successful OTP verification. Complete the service only after the scheduled work is finished.'
                  : 'The booking officially begins only after successful OTP verification. Verify the customer\'s OTP only when the service is ready to start.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderCompletedBookingDetailsExperience({
    required CanonicalBookingDocumentV3 booking,
    required CanonicalBookingPrivateParticipantsData? participantPrivateData,
    required String? participantErrorMessage,
  }) {
    final reviewWindowText = booking.lifecycle.reviewWindowEndsAt != null
        ? '${_calendarDate(booking.lifecycle.reviewWindowEndsAt!)} • ${_timeOnly(booking.lifecycle.reviewWindowEndsAt!)}'
        : 'Awaiting final sync';
    final currentStateText =
        booking.state == CanonicalBookingStateV3.completedPendingReview
        ? 'Waiting for customer review or automatic finalization.'
        : 'Customer review window is closed and the booking is finalized.';
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          _ProviderCompletedSummaryCard(
            serviceTitle: booking.service.serviceTitle,
            providerName: booking.participants.provider.displayName,
          ),
          const SizedBox(height: 24),
          const BookingDetailsSectionLabel('Completion status'),
          const SizedBox(height: 10),
          _ProviderCompletedStatusCard(
            statusText: 'Service completed successfully.',
            reviewWindowText: reviewWindowText,
            currentStateText: currentStateText,
            isPendingReview:
                booking.state == CanonicalBookingStateV3.completedPendingReview,
          ),
          const SizedBox(height: 24),
          const BookingDetailsSectionLabel('Service'),
          const SizedBox(height: 10),
          _ProviderCompletedServiceCard(
            providerName: booking.participants.provider.displayName,
            bookingType: _bookingTypeLabel(booking),
            paymentLabel: _paymentStatusLabel(booking),
            amountPaid: _money(booking),
            completedAt: booking.completedAt != null
                ? _timelineDateTimeLabel(booking.completedAt!)
                : 'Pending sync',
            serviceTitle: booking.service.serviceTitle,
          ),
          const SizedBox(height: 24),
          const BookingDetailsSectionLabel('Schedule'),
          const SizedBox(height: 10),
          _ProviderCompletedScheduleCard(
            rows: _buildProviderCompletedScheduleRows(booking),
          ),
          const SizedBox(height: 24),
          const BookingDetailsSectionLabel('Paid booking details'),
          const SizedBox(height: 10),
          _ProviderCompletedPaidDetailsCard(
            participantPrivateData: participantPrivateData,
            errorMessage: participantErrorMessage,
            onOpenMap: _hasDirectionsData(participantPrivateData)
                ? () => _openMap(participantPrivateData!)
                : null,
            onCallCustomer: participantPrivateData?.hasPhoneNumber == true
                ? () => _openPhone(participantPrivateData!.phoneNumber)
                : null,
            onRetry: participantErrorMessage == null
                ? null
                : _retryPrivateReads,
          ),
          const SizedBox(height: 24),
          const BookingDetailsSectionLabel('Booking chat'),
          const SizedBox(height: 10),
          _ProviderCompletedChatCard(
            isOpening: _isOpeningChat,
            isUnlocked: booking.privacy.chatUnlockedAt != null,
            onOpenChat: booking.privacy.chatUnlockedAt != null
                ? () => _openBookingChat(widget.bookingId)
                : null,
          ),
        ],
      ),
    );
  }

  List<StatusSummaryRowModel> _buildCustomerSummaryRows(
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
        value: booking.participants.provider.displayName,
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

  List<StatusSummaryRowModel> _buildCustomerCompletedScheduleRows(
    CanonicalBookingDocumentV3 booking,
  ) {
    return [
      StatusSummaryRowModel(
        label: 'Type',
        value: _bookingTypeLabel(booking),
        icon: Icons.event_note_outlined,
      ),
      StatusSummaryRowModel(
        label: 'Date',
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
        icon: Icons.hourglass_bottom_rounded,
      ),
    ];
  }

  List<StatusSummaryRowModel> _buildProviderSummaryRows(
    CanonicalBookingDocumentV3 booking,
  ) {
    final customerName =
        '${booking.participants.parent.displayFirstName} ${booking.participants.parent.lastInitial}.';
    final rows = <StatusSummaryRowModel>[
      StatusSummaryRowModel(
        label: 'Service',
        value: booking.service.serviceTitle,
        icon: Icons.pets_outlined,
      ),
      StatusSummaryRowModel(
        label: 'Customer',
        value: customerName,
        icon: Icons.person_outline_rounded,
      ),
      StatusSummaryRowModel(
        label: 'Pet',
        value: booking.service.animalType.trim().isEmpty
            ? 'Pet'
            : booking.service.animalType.trim(),
        icon: Icons.pets_rounded,
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
      StatusSummaryRowModel(
        label: 'Booking Type',
        value: _bookingTypeLabel(booking),
        icon: Icons.event_note_outlined,
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

  List<StatusSummaryRowModel> _buildProviderCompletedScheduleRows(
    CanonicalBookingDocumentV3 booking,
  ) {
    return [
      StatusSummaryRowModel(
        label: 'Date',
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
        icon: Icons.hourglass_bottom_rounded,
      ),
      StatusSummaryRowModel(
        label: 'Visit type',
        value: _bookingTypeLabel(booking),
        icon: Icons.sell_outlined,
      ),
    ];
  }

  StatusCardPresentationModel _buildCustomerStatusCard(
    CanonicalBookingDocumentV3 booking,
  ) {
    final effectiveState = effectiveCanonicalBookingPresentationState(booking);
    if (booking.state == CanonicalBookingStateV3.inProgress) {
      return const StatusCardPresentationModel(
        icon: Icons.play_circle_outline_rounded,
        title: 'Service Started',
        explanation:
            'The provider verified your OTP and the service is now in progress.',
        accentColor: Color(0xFF2FA56A),
        badgeLabel: 'Confirmed',
      );
    }
    if (effectiveState == CanonicalBookingStateV3.noShow) {
      return const StatusCardPresentationModel(
        icon: Icons.event_busy_outlined,
        title: 'No Show',
        explanation:
            'The service window ended before OTP verification, so this booking was marked as no-show.',
        accentColor: Color(0xFFE07A2D),
        badgeLabel: 'Closed',
      );
    }
    return const StatusCardPresentationModel(
      icon: Icons.verified_outlined,
      title: 'Confirmed',
      explanation:
          'Your booking is confirmed. Share the service-start OTP with the provider only when the service actually begins.',
      accentColor: Color(0xFF2FA56A),
      badgeLabel: 'Confirmed',
    );
  }

  StatusCardPresentationModel _buildProviderStatusCard(
    CanonicalBookingDocumentV3 booking,
  ) {
    final effectiveState = effectiveCanonicalBookingPresentationState(booking);
    if (booking.state == CanonicalBookingStateV3.inProgress) {
      return const StatusCardPresentationModel(
        icon: Icons.play_circle_outline_rounded,
        title: 'Service In Progress',
        explanation:
            'The customer\'s OTP has been verified successfully. Finish the service and complete the booking when the visit ends.',
        accentColor: Color(0xFF2FA56A),
        badgeLabel: 'Confirmed',
      );
    }
    if (effectiveState == CanonicalBookingStateV3.noShow) {
      return const StatusCardPresentationModel(
        icon: Icons.event_busy_outlined,
        title: 'No Show',
        explanation:
            'The service window ended before OTP verification, so this booking was marked as no-show.',
        accentColor: Color(0xFFE07A2D),
        badgeLabel: 'Closed',
      );
    }
    return const StatusCardPresentationModel(
      icon: Icons.check_circle_outline_rounded,
      title: 'Booking Confirmed',
      explanation:
          'The customer has successfully completed payment.\n\nYou can begin the service at the scheduled time.',
      accentColor: Color(0xFF2FA56A),
      badgeLabel: 'Confirmed',
    );
  }

  List<BookingTimelineStepModel> _buildCustomerTimeline(
    CanonicalBookingDocumentV3 booking,
  ) {
    final steps = <BookingTimelineStepModel>[];
    final effectiveState = effectiveCanonicalBookingPresentationState(booking);
    if (booking.lifecycle.requestedAt != null) {
      steps.add(
        BookingTimelineStepModel(
          label: 'Request submitted',
          timestamp: _timelineDateTimeLabel(booking.lifecycle.requestedAt!),
        ),
      );
    }
    if (booking.lifecycle.respondedAt != null) {
      steps.add(
        BookingTimelineStepModel(
          label: 'Provider accepted',
          timestamp: _timelineDateTimeLabel(booking.lifecycle.respondedAt!),
        ),
      );
    }
    if (booking.lifecycle.paidAt != null) {
      steps.add(
        BookingTimelineStepModel(
          label: 'Payment completed',
          timestamp: _timelineDateTimeLabel(booking.lifecycle.paidAt!),
        ),
      );
    }
    final scheduledAt = _scheduledStartAt(booking);
    if (scheduledAt != null) {
      steps.add(
        BookingTimelineStepModel(
          label: 'Service scheduled',
          timestamp: _timelineDateTimeLabel(scheduledAt),
          tone: BookingTimelineStepTone.neutral,
        ),
      );
    }
    if (effectiveState == CanonicalBookingStateV3.noShow) {
      final noShowAt = effectiveCanonicalNoShowTimestamp(booking);
      steps.add(
        BookingTimelineStepModel(
          label: 'Marked as no-show',
          subtitle: 'OTP was not verified before the service window ended',
          timestamp: noShowAt != null ? _timelineDateTimeLabel(noShowAt) : null,
          tone: BookingTimelineStepTone.warning,
          isHighlighted: true,
        ),
      );
    } else if (booking.lifecycle.otpEnteredAt != null) {
      steps.add(
        BookingTimelineStepModel(
          label: 'Service started',
          timestamp: _timelineDateTimeLabel(booking.lifecycle.otpEnteredAt!),
          isHighlighted: true,
        ),
      );
    }
    return steps;
  }

  List<BookingTimelineStepModel> _buildProviderTimeline(
    CanonicalBookingDocumentV3 booking,
  ) {
    final steps = <BookingTimelineStepModel>[];
    final effectiveState = effectiveCanonicalBookingPresentationState(booking);
    final hasStarted =
        effectiveState == CanonicalBookingStateV3.inProgress ||
        booking.lifecycle.otpEnteredAt != null;
    if (booking.lifecycle.requestedAt != null) {
      steps.add(
        BookingTimelineStepModel(
          label: 'Request submitted',
          timestamp: _timelineDateTimeLabel(booking.lifecycle.requestedAt!),
        ),
      );
    }
    if (booking.lifecycle.respondedAt != null) {
      steps.add(
        BookingTimelineStepModel(
          label: 'Provider accepted',
          timestamp: _timelineDateTimeLabel(booking.lifecycle.respondedAt!),
        ),
      );
    }
    if (booking.lifecycle.paidAt != null) {
      steps.add(
        BookingTimelineStepModel(
          label: 'Payment completed',
          timestamp: _timelineDateTimeLabel(booking.lifecycle.paidAt!),
        ),
      );
    }
    final scheduledAt = _scheduledStartAt(booking);
    if (scheduledAt != null) {
      steps.add(
        BookingTimelineStepModel(
          label: 'Service scheduled',
          timestamp: _timelineDateTimeLabel(scheduledAt),
          tone: BookingTimelineStepTone.neutral,
        ),
      );
    }
    if (hasStarted) {
      steps.add(
        BookingTimelineStepModel(
          label: 'Service started',
          timestamp: booking.lifecycle.otpEnteredAt != null
              ? _timelineDateTimeLabel(booking.lifecycle.otpEnteredAt!)
              : null,
          isHighlighted: true,
        ),
      );
    } else if (effectiveState == CanonicalBookingStateV3.noShow) {
      final noShowAt = effectiveCanonicalNoShowTimestamp(booking);
      steps.add(
        BookingTimelineStepModel(
          label: 'Marked as no-show',
          subtitle: 'OTP was not verified before the service window ended',
          timestamp: noShowAt != null ? _timelineDateTimeLabel(noShowAt) : null,
          tone: BookingTimelineStepTone.warning,
          isHighlighted: true,
        ),
      );
    } else {
      steps.add(
        const BookingTimelineStepModel(
          label: 'Start service',
          tone: BookingTimelineStepTone.neutral,
        ),
      );
    }
    if (effectiveState != CanonicalBookingStateV3.noShow) {
      steps.add(
        const BookingTimelineStepModel(
          label: 'Complete service',
          tone: BookingTimelineStepTone.neutral,
        ),
      );
    }
    return steps;
  }

  List<StatusFinancialRowModel> _buildCustomerPaymentRows(
    CanonicalBookingDocumentV3 booking,
  ) {
    final financials = booking.financials;
    final rows = <StatusFinancialRowModel>[
      StatusFinancialRowModel(
        label: 'Service Price',
        value: _moneyFromPaise(financials?.serviceSubtotalPaise ?? 0),
      ),
    ];
    if ((financials?.couponDiscountPaise ?? 0) > 0) {
      rows.add(
        StatusFinancialRowModel(
          label: 'Coupon Discount',
          value: '-${_moneyFromPaise(financials!.couponDiscountPaise)}',
        ),
      );
    }
    rows.add(
      StatusFinancialRowModel(
        label: 'Customer Paid',
        value: _moneyFromPaise(financials?.customerPaidPaise ?? 0),
      ),
    );
    rows.add(
      const StatusFinancialRowModel(
        label: 'Payment Status',
        value: 'Confirmed',
        valueTone: StatusFinancialValueTone.positive,
      ),
    );
    rows.add(
      StatusFinancialRowModel(
        label: 'Confirmed On',
        value: _dateTime(booking.lifecycle.paidAt),
        isEmphasized: true,
      ),
    );
    return rows;
  }

  bool _shouldShowLocationSection(
    CanonicalBookingPrivateParticipantsData? participantPrivateData,
    String? errorMessage,
  ) {
    return _hasDirectionsData(participantPrivateData) ||
        participantPrivateData?.hasProviderPhoneNumber == true ||
        (errorMessage != null && errorMessage.trim().isNotEmpty);
  }

  bool _hasDirectionsData(
    CanonicalBookingPrivateParticipantsData? participantPrivateData,
  ) {
    if (participantPrivateData == null) return false;
    return (participantPrivateData.latitude != null &&
            participantPrivateData.longitude != null) ||
        participantPrivateData.hasAddress;
  }

  String _bookingDateLabel(CanonicalBookingDocumentV3 booking) {
    final startAt = _scheduledStartAt(booking);
    return startAt == null ? 'Pending' : _calendarDate(startAt);
  }

  String _bookingTimeLabel(CanonicalBookingDocumentV3 booking) {
    if (booking.schedule case final CanonicalSlotBookingScheduleV3 schedule) {
      if (!_hasValidSlotWindow(schedule)) return 'Pending';
      return '${_timeOnly(schedule.scheduledStartAt)} to ${_timeOnly(schedule.scheduledEndAt)}';
    }
    if (booking.schedule case final CanonicalRangeBookingScheduleV3 schedule) {
      if (!_hasValidRangeWindow(schedule)) return 'Pending';
      return '${_timeOnly(schedule.checkInDateTime)} to ${_timeOnly(schedule.checkOutDateTime)}';
    }
    return 'Pending';
  }

  String _bookingDurationLabel(CanonicalBookingDocumentV3 booking) {
    if (booking.schedule case final CanonicalSlotBookingScheduleV3 schedule) {
      return _minutesLabel(
        schedule.totalDurationMinutes > 0
            ? schedule.totalDurationMinutes
            : booking.statistics.totalDurationMinutes,
      );
    }
    if (booking.schedule case final CanonicalRangeBookingScheduleV3 schedule) {
      return _nightsLabel(schedule.nights);
    }
    return 'Pending';
  }

  DateTime? _scheduledStartAt(CanonicalBookingDocumentV3 booking) {
    if (booking.schedule case final CanonicalSlotBookingScheduleV3 schedule) {
      return _hasValidSlotWindow(schedule) ? schedule.scheduledStartAt : null;
    }
    if (booking.schedule case final CanonicalRangeBookingScheduleV3 schedule) {
      return _hasValidRangeWindow(schedule) ? schedule.checkInDateTime : null;
    }
    return null;
  }

  String _timelineDateTimeLabel(DateTime value) {
    return '${_calendarDate(value)} · ${_timeOnly(value)}';
  }

  Widget _buildActions(CanonicalBookingDocumentV3 booking) {
    final currentUid = _currentUserId;
    final isParent = booking.parentId == currentUid;
    final isProvider = booking.providerId == currentUid;
    final effectiveState = effectiveCanonicalBookingPresentationState(booking);
    final canCancel =
        effectiveState == CanonicalBookingStateV3.confirmed &&
        (isParent || isProvider);
    final canComplete =
        effectiveState == CanonicalBookingStateV3.inProgress && isProvider;
    if (!canCancel && !canComplete) {
      return const SizedBox.shrink();
    }
    final label = isProvider ? 'Cancel as provider' : 'Cancel booking';
    return Column(
      children: [
        if (canComplete)
          GradientButton(
            label: _isCompletingService ? 'Completing...' : 'Complete service',
            onPressed: _isCompletingService
                ? null
                : () => _completeServiceFlow(bookingId: widget.bookingId),
            size: AppButtonSize.compact,
          ),
        if (canComplete && canCancel) const SizedBox(height: 10),
        if (canCancel)
          SecondaryButton(
            label: _isCancelling || _isLoadingPreview ? 'Processing...' : label,
            onPressed: _isCancelling || _isLoadingPreview || _isStartingService
                ? null
                : () => _startCancellationFlow(
                    bookingId: widget.bookingId,
                    actorType: isProvider ? 'PROVIDER' : 'CUSTOMER',
                    isProvider: isProvider,
                  ),
            size: AppButtonSize.compact,
          ),
      ],
    );
  }

  Future<void> _startServiceFlow({required String bookingId}) async {
    if (_isStartingService) return;
    final screenContext = context;
    try {
      final latest = await _repository.fetchCanonicalBooking(bookingId);
      if (latest is! CanonicalBookingReadModel ||
          latest.booking.state != CanonicalBookingStateV3.confirmed) {
        if (!mounted) return;
        AppSnackbar.showError(
          context,
          'This booking is no longer ready to start.',
        );
        return;
      }

      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        builder: (sheetContext) {
          var otpValue = '';
          var otpInputResetVersion = 0;
          return StatefulBuilder(
            builder: (context, setSheetState) {
              final canSubmit =
                  RegExp(r'^\d{6}$').hasMatch(otpValue) && !_isStartingService;
              Future<void> submitOtp() async {
                if (!canSubmit || _isStartingService) return;
                FocusScope.of(context).unfocus();
                final otp = otpValue.trim();
                setState(() => _isStartingService = true);
                setSheetState(() {});
                try {
                  await _repository.verifyBookingStartOtpV3(
                    bookingId: bookingId,
                    otp: otp,
                    requestAttemptId:
                        BookingRequestAttemptIdController.generate(),
                  );
                  await _waitForBookingState(
                    bookingId: bookingId,
                    expectedState: CanonicalBookingStateV3.inProgress,
                  );
                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                  }
                  if (!mounted || !screenContext.mounted) return;
                  AppSnackbar.showSuccess(
                    screenContext,
                    'Service is now in progress.',
                  );
                } catch (error) {
                  if (!mounted || !screenContext.mounted) return;
                  final message = _serviceStartErrorMessage(error);
                  final shouldClearOtp = _shouldResetProviderOtpInput(error);
                  if (shouldClearOtp) {
                    otpValue = '';
                    otpInputResetVersion += 1;
                    if (sheetContext.mounted) {
                      setSheetState(() {});
                    }
                  }
                  AppSnackbar.showError(screenContext, message);
                } finally {
                  if (mounted) {
                    setState(() => _isStartingService = false);
                  }
                  if (sheetContext.mounted) {
                    setSheetState(() {});
                  }
                }
              }

              return Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Enter customer OTP',
                        style: TextStyle(
                          color: AppColors.textDark,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Ask the customer for the 6-digit OTP shown in their confirmed booking details. Entering the correct OTP starts the service.',
                        style: TextStyle(
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: ValueKey(
                          'provider-otp-input-$otpInputResetVersion',
                        ),
                        initialValue: otpValue,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        onChanged: (value) {
                          otpValue = value.trim();
                          setSheetState(() {});
                        },
                        onTapOutside: (_) => FocusScope.of(context).unfocus(),
                        decoration: const InputDecoration(
                          counterText: '',
                          hintText: 'Enter 6-digit OTP',
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: SecondaryButton(
                              label: 'Cancel',
                              onPressed: _isStartingService
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              size: AppButtonSize.compact,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GradientButton(
                              label: _isStartingService
                                  ? 'Verifying...'
                                  : 'Verify OTP',
                              onPressed: canSubmit ? submitOtp : null,
                              size: AppButtonSize.compact,
                              isLoading: _isStartingService,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } catch (error) {
      if (!mounted) return;
      AppSnackbar.showError(context, _serviceStartErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _isStartingService = false);
      }
    }
  }

  Future<void> _waitForBookingState({
    required String bookingId,
    required CanonicalBookingStateV3 expectedState,
  }) async {
    final current = await _repository.fetchCanonicalBooking(bookingId);
    if (current is CanonicalBookingReadModel &&
        current.booking.state == expectedState) {
      return;
    }
    _serviceStartStateSubscription?.cancel();
    final completer = Completer<void>();
    _serviceStartStateSubscription = _repository
        .watchCanonicalBooking(bookingId)
        .listen((readModel) {
          if (readModel is CanonicalBookingReadModel &&
              readModel.booking.state == expectedState &&
              !completer.isCompleted) {
            completer.complete();
          }
        });
    try {
      await completer.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      final latest = await _repository.fetchCanonicalBooking(bookingId);
      if (latest is! CanonicalBookingReadModel ||
          latest.booking.state != expectedState) {
        rethrow;
      }
    } finally {
      await _serviceStartStateSubscription?.cancel();
      _serviceStartStateSubscription = null;
    }
  }

  String _serviceStartErrorMessage(Object error) {
    if (error is TimeoutException) {
      return 'We verified the OTP, but the booking status is still refreshing. Please wait a moment.';
    }
    if (error is FirebaseFunctionsException) {
      final code = error.code.trim().toLowerCase();
      final message = error.message?.trim() ?? '';
      final details = '${error.details}';
      if (code == 'unauthenticated') {
        return 'Please sign in again.';
      }
      if (code == 'resource-exhausted' ||
          details.contains('TEMPORARILY_LOCKED') ||
          details.contains('ATTEMPTS_EXCEEDED')) {
        return 'Too many incorrect attempts. Please wait before trying again.';
      }
      if (details.contains('ACTOR_NOT_AUTHORIZED') ||
          message.contains('Only the assigned provider can verify this OTP')) {
        return 'Only the assigned provider can verify this OTP.';
      }
      if (message.contains('already been cancelled')) {
        return 'This booking is no longer available for service start.';
      }
      if (message.contains('service-start window has already passed') ||
          details.contains('AFTER_SERVICE_END')) {
        return 'The service window has ended.';
      }
      if (message.contains('not eligible for service start') ||
          details.contains('INVALID_BOOKING_STATE') ||
          details.contains('INVALID_STATE') ||
          details.contains('PAYMENT_NOT_CONFIRMED')) {
        return 'Booking is not ready for OTP verification.';
      }
      if (message.contains('OTP verification is not available')) {
        return 'Booking is not ready for OTP verification.';
      }
      if (message.contains('OTP is invalid') ||
          details.contains('INVALID_OTP')) {
        return 'The OTP is incorrect.';
      }
      if (code == 'permission-denied') {
        return 'Only the assigned provider can verify this OTP.';
      }
      if (code == 'unavailable' ||
          code == 'deadline-exceeded' ||
          code == 'aborted' ||
          message.contains('network')) {
        return 'Check your internet connection.';
      }
      if (code == 'internal' || code == 'unknown' || code == 'data-loss') {
        return 'We could not start the service right now. Please try again.';
      }
    }
    final text = '$error';
    if (text.contains('unauthenticated')) {
      return 'Please sign in again.';
    }
    if (text.contains('ACTOR_NOT_AUTHORIZED')) {
      return 'Only the assigned provider can verify this OTP.';
    }
    if (text.contains('AFTER_SERVICE_END') ||
        text.contains('service-start window has already passed')) {
      return 'The service window has ended.';
    }
    if (text.contains('resource-exhausted')) {
      return 'Too many incorrect attempts. Please wait before trying again.';
    }
    if (text.contains('INVALID_OTP')) {
      return 'The OTP is incorrect. Ask the customer to confirm the code and try again.';
    }
    if (text.contains('INVALID_BOOKING_STATE')) {
      return 'Booking is not ready for OTP verification.';
    }
    if (text.contains('network-request-failed') ||
        text.contains('deadline-exceeded') ||
        text.contains('aborted') ||
        text.contains('unavailable')) {
      return 'Check your internet connection.';
    }
    if (text.contains('internal') ||
        text.contains('unknown') ||
        text.contains('data-loss')) {
      return 'We could not start the service right now. Please try again.';
    }
    return 'We could not verify the OTP right now. Please try again.';
  }

  bool _shouldResetProviderOtpInput(Object error) {
    if (error is FirebaseFunctionsException) {
      final code = error.code.trim().toLowerCase();
      final message = error.message?.trim() ?? '';
      final details = '${error.details}';
      return code == 'permission-denied' ||
          message.contains('OTP is invalid') ||
          details.contains('INVALID_OTP');
    }
    final text = '$error';
    return text.contains('permission-denied') || text.contains('INVALID_OTP');
  }

  Future<void> _startCancellationFlow({
    required String bookingId,
    required String actorType,
    required bool isProvider,
  }) async {
    setState(() => _isLoadingPreview = true);
    try {
      final latest = await _repository.fetchCanonicalBooking(bookingId);
      if (latest is! CanonicalBookingReadModel ||
          latest.booking.state != CanonicalBookingStateV3.confirmed) {
        if (!mounted) return;
        AppSnackbar.showError(
          context,
          'This booking is no longer eligible for cancellation.',
        );
        return;
      }
      final preview = await _repository.previewBookingCancellationV3(
        bookingId: bookingId,
        actorType: actorType,
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(isProvider ? 'Cancel booking?' : 'Cancel this booking?'),
          content: Text(
            preview.allowed
                ? isProvider
                      ? 'Customer refund: ${_moneyFromPaise(preview.grossCustomerRefundPaise)} (100%).\n\nRefunds go back to the original payment instrument in normal speed, typically within 5–7 working days.'
                      : 'Time band: ${_labelForTimingBand(preview.timingBand)}\n'
                            'Amount paid: ${_moneyFromPaise(preview.customerPaidPaise)}\n'
                            'Estimated refund: ${_moneyFromPaise(preview.grossCustomerRefundPaise)} '
                            '(${_percentLabel(preview.refundPercentageBasisPoints)})\n\n'
                            '${preview.grossCustomerRefundPaise == 0 ? 'This band does not return a customer refund.' : 'Refunds are based only on the amount actually paid and return to the original payment instrument in normal speed, typically within 5–7 working days.'}'
                : preview.message,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep booking'),
            ),
            TextButton(
              onPressed: preview.allowed
                  ? () => Navigator.of(context).pop(true)
                  : null,
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _isCancelling = true);
      final result = isProvider
          ? await _repository.cancelConfirmedBookingByProviderV3(
              bookingId: bookingId,
              reasonCode: 'provider_requested',
            )
          : await _repository.cancelConfirmedBookingByCustomerV3(
              bookingId: bookingId,
              reasonCode: 'customer_requested',
            );
      if (!mounted) return;
      AppSnackbar.showSuccess(
        context,
        'Cancellation recorded. Refund status: ${result.refundStatus}.',
      );
    } catch (error) {
      if (!mounted) return;
      AppSnackbar.showError(
        context,
        '$error'.trim().isEmpty
            ? 'Could not cancel this booking right now.'
            : '$error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPreview = false;
          _isCancelling = false;
        });
      }
    }
  }

  Future<void> _completeServiceFlow({required String bookingId}) async {
    setState(() => _isCompletingService = true);
    try {
      debugPrint(
        '[CanonicalServiceCompletion] request callable=completeBookingServiceV3 bookingId=$bookingId',
      );
      await _repository.completeBookingServiceV3(bookingId: bookingId);
      debugPrint(
        '[CanonicalServiceCompletion] success callable=completeBookingServiceV3 bookingId=$bookingId',
      );
      debugPrint(
        '[CanonicalServiceCompletion] refresh_started bookingId=$bookingId targetStates=COMPLETED_PENDING_REVIEW,COMPLETED_FINAL',
      );
      await _waitForBookingStates(
        bookingId: bookingId,
        expectedStates: const {
          CanonicalBookingStateV3.completedPendingReview,
          CanonicalBookingStateV3.completedFinal,
        },
      );
      debugPrint(
        '[CanonicalServiceCompletion] refresh_completed bookingId=$bookingId',
      );
      if (!mounted) return;
      AppSnackbar.showSuccess(
        context,
        'Service completed. The customer now has 24 hours to review or dispute.',
      );
      debugPrint(
        '[CanonicalServiceCompletion] navigation_completed bookingId=$bookingId',
      );
    } catch (error) {
      if (error is FirebaseFunctionsException) {
        debugPrint(
          '[CanonicalServiceCompletion] firebase_error callable=completeBookingServiceV3 bookingId=$bookingId code=${error.code} message=${(error.message ?? '').trim()} details=${error.details}',
        );
      } else {
        debugPrint(
          '[CanonicalServiceCompletion] unexpected_error callable=completeBookingServiceV3 bookingId=$bookingId error=$error',
        );
      }
      if (!mounted) return;
      final text = '$error';
      AppSnackbar.showError(
        context,
        error is TimeoutException
            ? 'Service completion is still refreshing. Please wait a moment.'
            : text.contains('failed-precondition')
            ? 'This booking cannot be completed right now.'
            : 'Could not complete this service right now.',
      );
    } finally {
      if (mounted) {
        setState(() => _isCompletingService = false);
      }
    }
  }

  Future<void> _waitForBookingStates({
    required String bookingId,
    required Set<CanonicalBookingStateV3> expectedStates,
  }) async {
    final current = await _repository.fetchCanonicalBooking(bookingId);
    if (current is CanonicalBookingReadModel &&
        expectedStates.contains(current.booking.state)) {
      return;
    }
    _serviceStartStateSubscription?.cancel();
    final completer = Completer<void>();
    _serviceStartStateSubscription = _repository
        .watchCanonicalBooking(bookingId)
        .listen((readModel) {
          if (readModel is CanonicalBookingReadModel &&
              expectedStates.contains(readModel.booking.state) &&
              !completer.isCompleted) {
            completer.complete();
          }
        });
    try {
      await completer.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      final latest = await _repository.fetchCanonicalBooking(bookingId);
      if (latest is! CanonicalBookingReadModel ||
          !expectedStates.contains(latest.booking.state)) {
        rethrow;
      }
    } finally {
      await _serviceStartStateSubscription?.cancel();
      _serviceStartStateSubscription = null;
    }
  }

  Future<void> _showReviewSheet(CanonicalBookingDocumentV3 booking) async {
    _reviewCommentController.clear();
    _reviewRating = 0;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Review your experience',
                    style: TextStyle(
                      color: AppColors.textDark,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: List.generate(5, (index) {
                      final selected = _reviewRating >= index + 1;
                      return IconButton(
                        onPressed: _isSubmittingReview
                            ? null
                            : () => setModalState(
                                () => _reviewRating = index + 1,
                              ),
                        icon: Icon(
                          selected
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textGrey,
                        ),
                      );
                    }),
                  ),
                  TextField(
                    controller: _reviewCommentController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Share anything helpful about the service',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          label: 'Cancel',
                          onPressed: _isSubmittingReview
                              ? null
                              : () => Navigator.of(context).pop(),
                          size: AppButtonSize.compact,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GradientButton(
                          label: _isSubmittingReview
                              ? 'Submitting...'
                              : 'Submit review',
                          onPressed: _isSubmittingReview
                              ? null
                              : () => _submitReview(booking, closeSheet: true),
                          size: AppButtonSize.compact,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showDisputeSheet(CanonicalBookingDocumentV3 booking) async {
    _disputeReasonController.clear();
    _disputeDescriptionController.clear();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Raise dispute',
                style: TextStyle(
                  color: AppColors.textDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _disputeReasonController,
                decoration: const InputDecoration(hintText: 'Reason'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _disputeDescriptionController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Describe what went wrong',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: 'Cancel',
                      onPressed: _isSubmittingDispute
                          ? null
                          : () => Navigator.of(context).pop(),
                      size: AppButtonSize.compact,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GradientButton(
                      label: _isSubmittingDispute
                          ? 'Submitting...'
                          : 'Raise dispute',
                      onPressed: _isSubmittingDispute
                          ? null
                          : () => _submitDispute(booking, closeSheet: true),
                      size: AppButtonSize.compact,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submitReview(
    CanonicalBookingDocumentV3 booking, {
    required bool closeSheet,
  }) async {
    if (_reviewRating < 1) {
      AppSnackbar.showError(context, 'Select a rating before submitting.');
      return;
    }
    setState(() => _isSubmittingReview = true);
    try {
      await _repository.submitBookingReviewV3(
        bookingId: widget.bookingId,
        rating: _reviewRating,
        comment: _reviewCommentController.text,
      );
      if (!mounted) return;
      setState(() => _reviewSubmittedLocally = true);
      if (closeSheet) Navigator.of(context).pop();
      AppSnackbar.showSuccess(context, 'Review submitted successfully.');
    } catch (error) {
      String? functionCode;
      String? detailCode;
      debugPrint(
        '[CanonicalReviewSubmission] submit_failed bookingId=${widget.bookingId} state=${booking.state.name} completedAtPresent=${(booking.lifecycle.completedAt ?? booking.completedAt) != null} reviewStatus=${booking.review.status} reviewIdPresent=${booking.review.reviewId.isNotEmpty} reviewAlreadyExistsKnown=${_reviewSubmittedLocally || booking.hasSubmittedReview} error=$error',
      );
      if (error is FirebaseFunctionsException) {
        functionCode = error.code;
        final details = error.details is Map<Object?, Object?>
            ? Map<Object?, Object?>.from(error.details as Map<Object?, Object?>)
            : null;
        final backendCode = details?['code'];
        if (backendCode is String && backendCode.trim().isNotEmpty) {
          detailCode = backendCode.trim();
        }
        debugPrint(
          '[CanonicalReviewSubmission] functions_exception bookingId=${widget.bookingId} code=${error.code} message=${(error.message ?? '').trim()} details=${error.details}',
        );
      } else if (error is FirebaseException) {
        debugPrint(
          '[CanonicalReviewSubmission] firebase_exception bookingId=${widget.bookingId} code=${error.code} message=${(error.message ?? '').trim()}',
        );
      }
      if (!mounted) return;
      final normalizedCode = (detailCode ?? functionCode ?? '')
          .trim()
          .toUpperCase();
      if (normalizedCode == 'REVIEW_ALREADY_SUBMITTED' ||
          normalizedCode == 'ALREADY_REVIEWED' ||
          functionCode == 'already-exists') {
        setState(() => _reviewSubmittedLocally = true);
      }
      AppSnackbar.showError(
        context,
        normalizedCode == 'REVIEW_ALREADY_SUBMITTED' ||
                normalizedCode == 'ALREADY_REVIEWED' ||
                functionCode == 'already-exists' ||
                '$error'.contains('ALREADY_REVIEWED')
            ? 'Your review has already been submitted for this booking.'
            : functionCode == 'failed-precondition' ||
                  '$error'.contains('failed-precondition')
            ? 'This booking is no longer ready for review.'
            : 'Could not submit your review right now.',
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmittingReview = false);
      }
    }
  }

  Future<void> _submitDispute(
    CanonicalBookingDocumentV3 booking, {
    required bool closeSheet,
  }) async {
    final reason = _disputeReasonController.text.trim();
    final description = _disputeDescriptionController.text.trim();
    final nestedDisputeDeadlineAt = booking.lifecycle.disputeDeadlineAt;
    final reviewWindowFallback = booking.lifecycle.reviewWindowEndsAt;
    if (reason.isEmpty || description.isEmpty) {
      AppSnackbar.showError(
        context,
        'Add both a reason and a description before submitting.',
      );
      return;
    }
    setState(() => _isSubmittingDispute = true);
    try {
      await _repository.createBookingDisputeV3(
        bookingId: widget.bookingId,
        reason: reason,
        description: description,
      );
      if (!mounted) return;
      if (closeSheet) Navigator.of(context).pop();
      AppSnackbar.showSuccess(
        context,
        'Dispute submitted. Payout stays on hold until Pettxo reviews it.',
      );
    } catch (error) {
      debugPrint(
        '[CanonicalDisputeSubmission] submit_failed bookingId=${widget.bookingId} callable=createBookingDisputeV3 state=${booking.state.name} nestedDisputeDeadlinePresent=${nestedDisputeDeadlineAt != null} historicalDottedDisputeDeadlineExposed=false reviewWindowFallbackPresent=${reviewWindowFallback != null} reasonPresent=${reason.isNotEmpty} descriptionLength=${description.length} error=$error',
      );
      String? functionCode;
      String? detailCode;
      if (error is FirebaseFunctionsException) {
        functionCode = error.code;
        final details = error.details is Map<Object?, Object?>
            ? Map<Object?, Object?>.from(error.details as Map<Object?, Object?>)
            : null;
        final backendCode = details?['code'];
        if (backendCode is String && backendCode.trim().isNotEmpty) {
          detailCode = backendCode.trim();
        }
        debugPrint(
          '[CanonicalDisputeSubmission] functions_exception bookingId=${widget.bookingId} code=${error.code} message=${(error.message ?? '').trim()} details=${error.details}',
        );
      } else if (error is FirebaseException) {
        debugPrint(
          '[CanonicalDisputeSubmission] firebase_exception bookingId=${widget.bookingId} code=${error.code} message=${(error.message ?? '').trim()}',
        );
      }
      if (!mounted) return;
      final normalizedCode = (detailCode ?? functionCode ?? '')
          .trim()
          .toUpperCase();
      final text = '$error';
      AppSnackbar.showError(
        context,
        normalizedCode == 'WINDOW_EXPIRED' || text.contains('WINDOW_EXPIRED')
            ? 'The dispute window for this booking has expired.'
            : normalizedCode == 'ALREADY_DISPUTED' ||
                  functionCode == 'already-exists' ||
                  text.contains('ALREADY_DISPUTED')
            ? 'A dispute has already been raised for this booking.'
            : functionCode == 'permission-denied' ||
                  text.contains('permission-denied')
            ? 'You are not allowed to raise a dispute for this booking.'
            : functionCode == 'invalid-argument' ||
                  text.contains('invalid-argument')
            ? 'Please check your dispute details and try again.'
            : functionCode == 'failed-precondition' ||
                  text.contains('failed-precondition')
            ? 'This booking is not eligible for dispute submission.'
            : functionCode == 'unavailable' || text.contains('unavailable')
            ? 'Network is unavailable right now. Please try again.'
            : 'Could not submit your dispute right now.',
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmittingDispute = false);
      }
    }
  }

  static String _moneyFromPaise(int amountPaise) {
    final whole = amountPaise / 100;
    return '₹${whole.toStringAsFixed(amountPaise % 100 == 0 ? 0 : 2)}';
  }

  static String _percentLabel(int basisPoints) {
    final wholePercent = basisPoints / 100;
    return wholePercent % 1 == 0
        ? '${wholePercent.toStringAsFixed(0)}%'
        : '${wholePercent.toStringAsFixed(2)}%';
  }

  static String _labelForTimingBand(String timingBand) {
    switch (timingBand) {
      case 'MORE_THAN_24_HOURS':
        return 'More than 24 hours remaining';
      case 'BETWEEN_24_AND_12_HOURS':
        return '24 hours to 12 hours remaining';
      case 'BETWEEN_12_AND_6_HOURS':
        return 'Under 12 hours to 6 hours remaining';
      case 'BETWEEN_6_AND_2_HOURS':
        return 'Under 6 hours to 2 hours remaining';
      case 'UNDER_2_HOURS':
        return 'Under 2 hours remaining';
      case 'AFTER_OTP_ENTRY':
        return 'After OTP entry';
      case 'PROVIDER_CANCELLATION':
        return 'Provider cancellation';
      case 'AFTER_START':
        return 'After service start';
      default:
        return timingBand.replaceAll('_', ' ');
    }
  }

  Future<void> _openBookingChat(String bookingId) async {
    if (_isOpeningChat) return;
    setState(() => _isOpeningChat = true);
    try {
      if (widget.onOpenChatOverride != null) {
        await widget.onOpenChatOverride!(bookingId);
        return;
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatDetailScreen(chatId: bookingId)),
      );
    } finally {
      if (mounted) {
        setState(() => _isOpeningChat = false);
      }
    }
  }

  Future<void> _openPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.trim());
    final canLaunch = widget.canLaunchUrlOverride == null
        ? await canLaunchUrl(uri)
        : await widget.canLaunchUrlOverride!(uri);
    if (!canLaunch) {
      if (!mounted) return;
      AppSnackbar.showError(context, 'Could not open the phone dialer.');
      return;
    }
    final opened = widget.launchUrlOverride == null
        ? await launchUrl(uri)
        : await widget.launchUrlOverride!(uri);
    if (!opened && mounted) {
      AppSnackbar.showError(context, 'Could not open the phone dialer.');
    }
  }

  Future<void> _openMap(CanonicalBookingPrivateParticipantsData details) async {
    final latitude = details.latitude;
    final longitude = details.longitude;
    final address = details.exactAddress.trim();
    final query = latitude != null && longitude != null
        ? '$latitude,$longitude'
        : address;
    if (query.isEmpty) {
      if (!mounted) return;
      AppSnackbar.showError(
        context,
        'Location is not available for this booking.',
      );
      return;
    }
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
    );
    final canLaunch = widget.canLaunchUrlOverride == null
        ? await canLaunchUrl(uri)
        : await widget.canLaunchUrlOverride!(uri);
    if (!canLaunch) {
      if (!mounted) return;
      AppSnackbar.showError(context, 'Could not open maps for this booking.');
      return;
    }
    final opened = widget.launchUrlOverride == null
        ? await launchUrl(uri, mode: LaunchMode.externalApplication)
        : await widget.launchUrlOverride!(
            uri,
            mode: LaunchMode.externalApplication,
          );
    if (!opened && mounted) {
      AppSnackbar.showError(context, 'Could not open maps for this booking.');
    }
  }
}

class _CustomerOtpSectionCard extends StatelessWidget {
  const _CustomerOtpSectionCard({
    required this.booking,
    required this.otpPrivateData,
    required this.isLoading,
    required this.errorMessage,
    required this.providerName,
    required this.onRetry,
  });

  final CanonicalBookingDocumentV3 booking;
  final CanonicalBookingPrivateData? otpPrivateData;
  final bool isLoading;
  final String? errorMessage;
  final String providerName;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final hasError = errorMessage != null && errorMessage!.trim().isNotEmpty;
    final isStarted =
        booking.state == CanonicalBookingStateV3.inProgress ||
        booking.lifecycle.otpEnteredAt != null ||
        otpPrivateData?.otpState.toUpperCase() == 'USED';
    return BookingDetailsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BookingDetailsIconTile(
                icon: Icons.password_rounded,
                iconColor: AppColors.primary,
                backgroundColor: const Color(0xFFFFF1E7),
                size: 34,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Use this OTP to start the service',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isStarted)
            const Text(
              'Service started. Your booking OTP has already been used for this booking.',
              style: TextStyle(
                color: AppColors.textGrey,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            )
          else if (otpPrivateData?.isOtpActive == true) ...[
            _OtpInfoBlock(
              otpCode: otpPrivateData!.parentOtpCode,
              providerName: providerName,
            ),
          ] else if (isLoading)
            const Text(
              'Loading your service OTP...',
              style: TextStyle(
                color: AppColors.textGrey,
                fontWeight: FontWeight.w600,
              ),
            )
          else ...[
            Text(
              hasError
                  ? 'Your service OTP could not be loaded right now.'
                  : effectiveCanonicalBookingPresentationState(booking) ==
                        CanonicalBookingStateV3.noShow
                  ? 'The service OTP is no longer available because this booking was marked as no-show.'
                  : 'Private OTP details are not available right now.',
              style: const TextStyle(
                color: AppColors.textGrey,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
            if (hasError) ...[
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Retry details',
                onPressed: onRetry,
                size: AppButtonSize.compact,
              ),
            ],
          ],
          const SizedBox(height: 14),
          BookingDetailsSurfaceCard(
            backgroundColor: const Color(0xFFFFF8F1),
            borderColor: AppColors.primary.withValues(alpha: 0.10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BookingDetailsIconTile(
                  icon: Icons.warning_amber_rounded,
                  iconColor: AppColors.primary,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.10),
                  size: 28,
                  iconSize: 16,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Do not share this OTP before meeting the provider and confirming that the service is ready to begin.',
                    style: TextStyle(
                      color: AppColors.textGrey,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerLocationCard extends StatelessWidget {
  const _CustomerLocationCard({
    required this.participantPrivateData,
    required this.errorMessage,
    required this.onOpenMap,
    required this.onCallProvider,
    required this.onRetry,
  });

  final CanonicalBookingPrivateParticipantsData? participantPrivateData;
  final String? errorMessage;
  final VoidCallback? onOpenMap;
  final VoidCallback? onCallProvider;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return BookingDetailsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BookingDetailsIconTile(
                icon: Icons.location_on_outlined,
                iconColor: AppColors.primary,
                backgroundColor: Color(0xFFFFF1E7),
                size: 34,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  participantPrivateData?.hasAddress == true
                      ? participantPrivateData!.exactAddress
                      : 'Directions could not be loaded right now.',
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (onOpenMap != null)
            SecondaryButton(
              label: 'Get directions',
              onPressed: onOpenMap,
              icon: Icons.map_outlined,
              size: AppButtonSize.compact,
            ),
          if (onCallProvider != null) ...[
            const SizedBox(height: 10),
            SecondaryButton(
              label: 'Call provider',
              onPressed: onCallProvider,
              icon: Icons.call_outlined,
              size: AppButtonSize.compact,
            ),
          ],
          if (onRetry != null && onOpenMap == null) ...[
            const SizedBox(height: 10),
            SecondaryButton(
              label: 'Retry details',
              onPressed: onRetry,
              size: AppButtonSize.compact,
            ),
          ],
        ],
      ),
    );
  }
}

class _CustomerChatCard extends StatelessWidget {
  const _CustomerChatCard({
    required this.isOpening,
    required this.isUnlocked,
    required this.onOpenChat,
  });

  final bool isOpening;
  final bool isUnlocked;
  final VoidCallback? onOpenChat;

  @override
  Widget build(BuildContext context) {
    return BookingDetailsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BookingDetailsIconTile(
                icon: Icons.chat_bubble_outline_rounded,
                iconColor: AppColors.primary,
                backgroundColor: Color(0xFFFFF1E7),
                size: 34,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Coordinate service details directly with the provider.',
                  style: TextStyle(
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GradientButton(
            label: isOpening ? 'Opening...' : 'Message provider',
            onPressed: isUnlocked && !isOpening ? onOpenChat : null,
            size: AppButtonSize.compact,
            isLoading: isOpening,
          ),
        ],
      ),
    );
  }
}

class _CustomerCancellationCard extends StatelessWidget {
  const _CustomerCancellationCard({
    required this.canCancel,
    required this.isBusy,
    required this.onReadPolicy,
    required this.onCancel,
  });

  final bool canCancel;
  final bool isBusy;
  final VoidCallback onReadPolicy;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return BookingDetailsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BookingDetailsIconTile(
                icon: Icons.policy_outlined,
                iconColor: AppColors.primary,
                backgroundColor: Color(0xFFFFF1E7),
                size: 34,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  canCancel
                      ? 'Cancellation eligibility and refund depend on the time remaining before the scheduled service.'
                      : 'Cancellation is no longer available for this booking.',
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SecondaryButton(
            label: 'Read Cancellation Policy',
            onPressed: onReadPolicy,
            icon: Icons.open_in_new_rounded,
            size: AppButtonSize.compact,
          ),
          if (canCancel && onCancel != null) ...[
            const SizedBox(height: 10),
            SecondaryButton(
              label: isBusy ? 'Processing...' : 'Cancel Booking',
              onPressed: isBusy ? null : onCancel,
              size: AppButtonSize.compact,
            ),
          ],
        ],
      ),
    );
  }
}

class _CustomerCompletedSummaryCard extends StatelessWidget {
  const _CustomerCompletedSummaryCard({
    required this.serviceTitle,
    required this.providerName,
  });

  final String serviceTitle;
  final String providerName;

  @override
  Widget build(BuildContext context) {
    return BookingDetailsSurfaceCard(
      backgroundColor: const Color(0xFFFFFBF8),
      borderColor: AppColors.primary.withValues(alpha: 0.10),
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
                      serviceTitle,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      providerName,
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE4F6E9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Completed',
                  style: TextStyle(
                    color: Color(0xFF248A52),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Your payment is confirmed. You can now leave a review, raise a dispute during the review window, contact the provider, view directions, or continue chatting.',
            style: TextStyle(
              color: AppColors.textGrey,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerCompletedStatusCard extends StatelessWidget {
  const _CustomerCompletedStatusCard({
    required this.disputeDeadlineText,
    required this.canLeaveReview,
    required this.canRaiseDispute,
    required this.reviewSubmitted,
    required this.disputeOpen,
    required this.disputeWindowActive,
    required this.isSubmittingReview,
    required this.isSubmittingDispute,
    required this.onLeaveReview,
    required this.onRaiseDispute,
  });

  final String disputeDeadlineText;
  final bool canLeaveReview;
  final bool canRaiseDispute;
  final bool reviewSubmitted;
  final bool disputeOpen;
  final bool disputeWindowActive;
  final bool isSubmittingReview;
  final bool isSubmittingDispute;
  final VoidCallback? onLeaveReview;
  final VoidCallback? onRaiseDispute;

  @override
  Widget build(BuildContext context) {
    return BookingDetailsSurfaceCard(
      child: Column(
        children: [
          const _ProviderCompletedInfoRow(
            icon: Icons.verified_rounded,
            iconColor: Color(0xFF248A52),
            iconBackgroundColor: Color(0xFFE8F7EC),
            label: 'Status',
            value: 'Service completed successfully.',
          ),
          const _ProviderDetailDivider(),
          _ProviderCompletedInfoRow(
            icon: Icons.schedule_rounded,
            iconColor: Color(0xFF2D6CDF),
            iconBackgroundColor: Color(0xFFE8F1FF),
            label: 'Dispute window',
            value: disputeWindowActive
                ? 'Raise a dispute before\n$disputeDeadlineText'
                : 'The dispute window closed on\n$disputeDeadlineText',
          ),
          const _ProviderDetailDivider(),
          _ProviderCompletedInfoRow(
            icon: Icons.hourglass_bottom_rounded,
            iconColor: Color(0xFF8B57D9),
            iconBackgroundColor: Color(0xFFF1E9FF),
            label: 'Review',
            value: reviewSubmitted
                ? 'Your review has already been submitted.'
                : 'You can leave a review at any time.',
          ),
          if (onLeaveReview != null || onRaiseDispute != null) ...[
            const SizedBox(height: 18),
            if (onLeaveReview != null)
              GradientButton(
                label: reviewSubmitted
                    ? 'Review submitted'
                    : isSubmittingReview
                    ? 'Submitting...'
                    : 'Leave Review',
                onPressed: reviewSubmitted || isSubmittingReview
                    ? null
                    : onLeaveReview,
                size: AppButtonSize.compact,
                isLoading: isSubmittingReview,
              ),
            if (onRaiseDispute != null) ...[
              const SizedBox(height: 12),
              SecondaryButton(
                label: disputeOpen
                    ? 'Dispute submitted'
                    : isSubmittingDispute
                    ? 'Submitting...'
                    : 'Raise Dispute',
                onPressed: disputeOpen || isSubmittingDispute
                    ? null
                    : onRaiseDispute,
                size: AppButtonSize.compact,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _CustomerCompletedServiceCard extends StatelessWidget {
  const _CustomerCompletedServiceCard({
    required this.serviceTitle,
    required this.providerName,
    required this.paymentLabel,
    required this.amountPaid,
    required this.confirmedAt,
  });

  final String serviceTitle;
  final String providerName;
  final String paymentLabel;
  final String amountPaid;
  final String confirmedAt;

  @override
  Widget build(BuildContext context) {
    return BookingDetailsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProviderCompletedMetricRow(label: 'Title', value: serviceTitle),
          const _ProviderDetailDivider(),
          _ProviderCompletedMetricRow(label: 'Provider', value: providerName),
          const _ProviderDetailDivider(),
          _CustomerCompletedServiceStatusRow(),
          const _ProviderDetailDivider(),
          _ProviderCompletedMetricRow(
            label: 'Payment',
            value: paymentLabel == 'Payment confirmed'
                ? paymentLabel
                : 'Payment confirmed',
          ),
          const _ProviderDetailDivider(),
          _ProviderCompletedMetricRow(label: 'Amount Paid', value: amountPaid),
          const _ProviderDetailDivider(),
          _ProviderCompletedMetricRow(
            label: 'Confirmed At',
            value: confirmedAt,
          ),
        ],
      ),
    );
  }
}

class _CustomerCompletedServiceStatusRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          flex: 5,
          child: Text(
            'Status',
            style: TextStyle(
              color: AppColors.textGrey,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 7,
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFE4F6E9),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Completed',
                style: TextStyle(
                  color: Color(0xFF248A52),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CustomerCompletedAddressCard extends StatelessWidget {
  const _CustomerCompletedAddressCard({
    required this.participantPrivateData,
    required this.errorMessage,
    required this.onOpenMap,
    required this.onCallProvider,
    required this.onRetry,
  });

  final CanonicalBookingPrivateParticipantsData? participantPrivateData;
  final String? errorMessage;
  final VoidCallback? onOpenMap;
  final VoidCallback? onCallProvider;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final hasError = errorMessage != null && errorMessage!.trim().isNotEmpty;
    final addressText = participantPrivateData?.hasAddress == true
        ? participantPrivateData!.exactAddress
        : hasError
        ? 'Service address could not be loaded right now.'
        : 'Service address is not available right now.';
    return BookingDetailsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BookingDetailsIconTile(
                icon: Icons.location_on_outlined,
                iconColor: AppColors.primary,
                backgroundColor: Color(0xFFFFF1E7),
                size: 34,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  addressText,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (onOpenMap != null)
            SecondaryButton(
              label: 'Get Directions',
              onPressed: onOpenMap,
              icon: Icons.place_outlined,
              size: AppButtonSize.compact,
            ),
          if (onCallProvider != null) ...[
            const SizedBox(height: 10),
            SecondaryButton(
              label: 'Call provider',
              onPressed: onCallProvider,
              icon: Icons.call_outlined,
              size: AppButtonSize.compact,
            ),
          ],
          if (onRetry != null &&
              onOpenMap == null &&
              onCallProvider == null) ...[
            const SizedBox(height: 10),
            SecondaryButton(
              label: 'Retry details',
              onPressed: onRetry,
              size: AppButtonSize.compact,
            ),
          ],
        ],
      ),
    );
  }
}

class _CustomerCompletedChatCard extends StatelessWidget {
  const _CustomerCompletedChatCard({
    required this.isOpening,
    required this.isUnlocked,
    required this.onOpenChat,
  });

  final bool isOpening;
  final bool isUnlocked;
  final VoidCallback? onOpenChat;

  @override
  Widget build(BuildContext context) {
    return BookingDetailsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Booking Chat',
            style: TextStyle(
              color: AppColors.textDark,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Use this chat to coordinate with your provider regarding this completed booking.',
            style: TextStyle(
              color: AppColors.textGrey,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          GradientButton(
            label: isOpening ? 'Opening...' : 'Message Provider',
            onPressed: isUnlocked && !isOpening ? onOpenChat : null,
            size: AppButtonSize.compact,
            isLoading: isOpening,
          ),
        ],
      ),
    );
  }
}

class _ProviderCompletedSummaryCard extends StatelessWidget {
  const _ProviderCompletedSummaryCard({
    required this.serviceTitle,
    required this.providerName,
  });

  final String serviceTitle;
  final String providerName;

  @override
  Widget build(BuildContext context) {
    return BookingDetailsSurfaceCard(
      backgroundColor: const Color(0xFFF7FDF8),
      borderColor: const Color(0xFFD7F0DE),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(child: SizedBox.shrink()),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE4F6E9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Completed',
                  style: TextStyle(
                    color: Color(0xFF248A52),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          Text(
            serviceTitle,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            providerName,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFD7F0DE)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BookingDetailsIconTile(
                  icon: Icons.verified_rounded,
                  iconColor: Color(0xFF248A52),
                  backgroundColor: Color(0xFFE8F7EC),
                  size: 32,
                  iconSize: 18,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'The service has been completed successfully.',
                    style: TextStyle(
                      color: AppColors.textDark,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderCompletedStatusCard extends StatelessWidget {
  const _ProviderCompletedStatusCard({
    required this.statusText,
    required this.reviewWindowText,
    required this.currentStateText,
    required this.isPendingReview,
  });

  final String statusText;
  final String reviewWindowText;
  final String currentStateText;
  final bool isPendingReview;

  @override
  Widget build(BuildContext context) {
    return BookingDetailsSurfaceCard(
      child: Column(
        children: [
          _ProviderCompletedInfoRow(
            icon: Icons.verified_rounded,
            iconColor: const Color(0xFF248A52),
            iconBackgroundColor: const Color(0xFFE8F7EC),
            label: 'Status',
            value: statusText,
          ),
          const _ProviderDetailDivider(),
          _ProviderCompletedInfoRow(
            icon: Icons.schedule_rounded,
            iconColor: const Color(0xFFE07A2D),
            iconBackgroundColor: const Color(0xFFFFF1E7),
            label: 'Review window',
            value: isPendingReview
                ? 'Ends $reviewWindowText'
                : 'Closed after $reviewWindowText',
          ),
          const _ProviderDetailDivider(),
          _ProviderCompletedInfoRow(
            icon: Icons.hourglass_bottom_rounded,
            iconColor: const Color(0xFFB67A00),
            iconBackgroundColor: const Color(0xFFFFF5D9),
            label: 'Current state',
            value: currentStateText,
          ),
        ],
      ),
    );
  }
}

class _ProviderCompletedServiceCard extends StatelessWidget {
  const _ProviderCompletedServiceCard({
    required this.serviceTitle,
    required this.providerName,
    required this.bookingType,
    required this.paymentLabel,
    required this.amountPaid,
    required this.completedAt,
  });

  final String serviceTitle;
  final String providerName;
  final String bookingType;
  final String paymentLabel;
  final String amountPaid;
  final String completedAt;

  @override
  Widget build(BuildContext context) {
    return BookingDetailsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Service details',
                style: TextStyle(
                  color: AppColors.textDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE4F6E9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Completed',
                  style: TextStyle(
                    color: Color(0xFF248A52),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ProviderCompletedMetricRow(label: 'Title', value: serviceTitle),
          const _ProviderDetailDivider(),
          _ProviderCompletedMetricRow(label: 'Provider', value: providerName),
          const _ProviderDetailDivider(),
          _ProviderCompletedMetricRow(
            label: 'Booking type',
            value: bookingType,
          ),
          const _ProviderDetailDivider(),
          _ProviderCompletedMetricRow(label: 'Payment', value: paymentLabel),
          const _ProviderDetailDivider(),
          _ProviderCompletedMetricRow(label: 'Amount paid', value: amountPaid),
          const _ProviderDetailDivider(),
          _ProviderCompletedMetricRow(
            label: 'Completed at',
            value: completedAt,
          ),
        ],
      ),
    );
  }
}

class _ProviderCompletedScheduleCard extends StatelessWidget {
  const _ProviderCompletedScheduleCard({required this.rows});

  final List<StatusSummaryRowModel> rows;

  @override
  Widget build(BuildContext context) {
    return BookingSummaryCard(rows: rows);
  }
}

class _ProviderCompletedPaidDetailsCard extends StatelessWidget {
  const _ProviderCompletedPaidDetailsCard({
    required this.participantPrivateData,
    required this.errorMessage,
    required this.onOpenMap,
    required this.onCallCustomer,
    required this.onRetry,
  });

  final CanonicalBookingPrivateParticipantsData? participantPrivateData;
  final String? errorMessage;
  final VoidCallback? onOpenMap;
  final VoidCallback? onCallCustomer;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final hasError = errorMessage != null && errorMessage!.trim().isNotEmpty;
    final addressValue = participantPrivateData?.hasAddress == true
        ? participantPrivateData!.exactAddress
        : hasError
        ? 'Service address could not be loaded right now.'
        : 'Service address is not available right now.';
    final phoneValue = participantPrivateData?.hasPhoneNumber == true
        ? participantPrivateData!.phoneNumber
        : hasError
        ? 'Customer phone could not be loaded right now.'
        : 'Customer phone is not available right now.';

    return BookingDetailsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProviderCompletedInfoRow(
            icon: Icons.call_outlined,
            iconColor: AppColors.primary,
            iconBackgroundColor: const Color(0xFFFFF1E7),
            label: 'Customer phone',
            value: phoneValue,
            actionLabel: onCallCustomer != null ? 'Call customer' : null,
            onActionTap: onCallCustomer,
          ),
          const _ProviderDetailDivider(),
          _ProviderCompletedInfoRow(
            icon: Icons.location_on_outlined,
            iconColor: AppColors.primary,
            iconBackgroundColor: const Color(0xFFFFF1E7),
            label: 'Service address',
            value: addressValue,
          ),
          if (onOpenMap != null) ...[
            const SizedBox(height: 16),
            SecondaryButton(
              label: 'Get directions',
              onPressed: onOpenMap,
              icon: Icons.map_outlined,
              size: AppButtonSize.compact,
            ),
          ],
          if (onRetry != null &&
              onOpenMap == null &&
              onCallCustomer == null) ...[
            const SizedBox(height: 16),
            SecondaryButton(
              label: 'Retry details',
              onPressed: onRetry,
              size: AppButtonSize.compact,
            ),
          ],
        ],
      ),
    );
  }
}

class _ProviderCompletedChatCard extends StatelessWidget {
  const _ProviderCompletedChatCard({
    required this.isOpening,
    required this.isUnlocked,
    required this.onOpenChat,
  });

  final bool isOpening;
  final bool isUnlocked;
  final VoidCallback? onOpenChat;

  @override
  Widget build(BuildContext context) {
    return BookingDetailsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              BookingDetailsIconTile(
                icon: Icons.chat_bubble_outline_rounded,
                iconColor: AppColors.primary,
                backgroundColor: Color(0xFFFFF1E7),
                size: 34,
                iconSize: 18,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Use chat to coordinate any follow-up details with the customer.',
                  style: TextStyle(
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GradientButton(
            label: isOpening ? 'Opening...' : 'Message Customer',
            onPressed: isUnlocked && !isOpening ? onOpenChat : null,
            size: AppButtonSize.compact,
            isLoading: isOpening,
          ),
        ],
      ),
    );
  }
}

class _ProviderServiceDetailsCard extends StatelessWidget {
  const _ProviderServiceDetailsCard({
    required this.participantPrivateData,
    required this.errorMessage,
    required this.onOpenMap,
    required this.onCallCustomer,
    required this.onRetry,
  });

  final CanonicalBookingPrivateParticipantsData? participantPrivateData;
  final String? errorMessage;
  final VoidCallback? onOpenMap;
  final VoidCallback? onCallCustomer;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final hasError = errorMessage != null && errorMessage!.trim().isNotEmpty;
    final rows = <Widget>[
      _ProviderDetailRow(
        label: 'Service address',
        value: participantPrivateData?.hasAddress == true
            ? participantPrivateData!.exactAddress
            : hasError
            ? 'Directions could not be loaded right now.'
            : 'Service address is not available right now.',
        actionLabel: onOpenMap != null ? 'Get directions' : null,
        onActionTap: onOpenMap,
      ),
      const _ProviderDetailDivider(),
      _ProviderDetailRow(
        label: 'Customer phone',
        value: participantPrivateData?.hasPhoneNumber == true
            ? participantPrivateData!.phoneNumber
            : hasError
            ? 'Customer phone could not be loaded right now.'
            : 'Customer phone is not available right now.',
        actionLabel: onCallCustomer != null ? 'Call customer' : null,
        onActionTap: onCallCustomer,
      ),
    ];
    if (participantPrivateData?.hasProviderPhoneNumber == true || hasError) {
      rows.addAll([
        const _ProviderDetailDivider(),
        _ProviderDetailRow(
          label: 'Provider phone',
          value: participantPrivateData?.hasProviderPhoneNumber == true
              ? participantPrivateData!.providerPhoneNumber
              : 'Provider phone could not be loaded right now.',
        ),
      ]);
    }

    return BookingDetailsSurfaceCard(
      child: Column(
        children: [
          ...rows,
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            SecondaryButton(
              label: 'Retry details',
              onPressed: onRetry,
              size: AppButtonSize.compact,
            ),
          ],
        ],
      ),
    );
  }
}

class _ProviderUnifiedServiceActionCard extends StatelessWidget {
  const _ProviderUnifiedServiceActionCard({
    required this.booking,
    required this.isBusy,
    required this.onEnterOtp,
    required this.onCompleteService,
  });

  final CanonicalBookingDocumentV3 booking;
  final bool isBusy;
  final VoidCallback? onEnterOtp;
  final VoidCallback? onCompleteService;

  @override
  Widget build(BuildContext context) {
    final effectiveState = effectiveCanonicalBookingPresentationState(booking);
    final hasStarted =
        effectiveState == CanonicalBookingStateV3.inProgress ||
        booking.lifecycle.otpEnteredAt != null;
    final isNoShow = effectiveState == CanonicalBookingStateV3.noShow;

    return BookingDetailsSurfaceCard(
      backgroundColor: const Color(0xFFF5F9FF),
      borderColor: const Color(0xFFDCEAFF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BookingDetailsIconTile(
                icon: Icons.shield_outlined,
                iconColor: Color(0xFF2D6CDF),
                backgroundColor: Color(0xFFE8F1FF),
                size: 38,
                iconSize: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasStarted
                          ? 'Service started'
                          : isNoShow
                          ? 'No-show'
                          : 'OTP required',
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (isNoShow)
                      const Text(
                        'The service window ended before OTP verification, so the start OTP is no longer available for this booking.',
                        style: TextStyle(
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      )
                    else if (!hasStarted)
                      const Text(
                        'Ask the customer for their 6-digit service OTP when the service begins.\n\nEntering the correct OTP validates the service start for this booking.',
                        style: TextStyle(
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                    if (hasStarted) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'The customer OTP was verified successfully. You can now complete the service when the work is finished.',
                        style: TextStyle(
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                    ] else
                      const Text('', style: TextStyle(fontSize: 0)),
                  ],
                ),
              ),
            ],
          ),
          if (!isNoShow && (!hasStarted || onCompleteService != null)) ...[
            const SizedBox(height: 16),
            GradientButton(
              label: hasStarted
                  ? (isBusy ? 'Completing...' : 'Complete service')
                  : (isBusy ? 'Verifying...' : 'Enter customer OTP'),
              onPressed: hasStarted ? onCompleteService : onEnterOtp,
              size: AppButtonSize.compact,
              isLoading: isBusy,
            ),
          ],
        ],
      ),
    );
  }
}

class _ProviderBookingChatCard extends StatelessWidget {
  const _ProviderBookingChatCard({
    required this.isOpening,
    required this.isUnlocked,
    required this.onOpenChat,
  });

  final bool isOpening;
  final bool isUnlocked;
  final VoidCallback? onOpenChat;

  @override
  Widget build(BuildContext context) {
    return BookingDetailsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BookingDetailsIconTile(
                icon: Icons.chat_bubble_outline_rounded,
                iconColor: Color(0xFF6D4BDE),
                backgroundColor: Color(0xFFF0EBFF),
                size: 38,
                iconSize: 20,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Coordinate any remaining service details directly with the customer.',
                  style: TextStyle(
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SecondaryButton(
            label: isOpening ? 'Opening...' : 'Message customer',
            onPressed: isUnlocked && !isOpening ? onOpenChat : null,
            icon: Icons.chat_bubble_outline_rounded,
            size: AppButtonSize.compact,
          ),
        ],
      ),
    );
  }
}

class _ProviderCancellationCard extends StatelessWidget {
  const _ProviderCancellationCard({
    required this.canCancel,
    required this.isBusy,
    required this.onCancel,
  });

  final bool canCancel;
  final bool isBusy;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return BookingDetailsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BookingDetailsIconTile(
                icon: Icons.cancel_outlined,
                iconColor: Color(0xFFDC2626),
                backgroundColor: Color(0xFFFEECEC),
                size: 38,
                iconSize: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  canCancel
                      ? 'Provider cancellation is still available before the service starts. Refunds and payout handling will follow the active cancellation policy.'
                      : 'Provider cancellation is no longer available because the service has already started.',
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          if (canCancel && onCancel != null) ...[
            const SizedBox(height: 16),
            SecondaryButton(
              label: isBusy ? 'Processing...' : 'Cancel as provider',
              onPressed: isBusy ? null : onCancel,
              icon: Icons.cancel_outlined,
              size: AppButtonSize.compact,
            ),
          ],
        ],
      ),
    );
  }
}

class _ProviderCompletedInfoRow extends StatelessWidget {
  const _ProviderCompletedInfoRow({
    required this.icon,
    required this.iconColor,
    required this.iconBackgroundColor,
    required this.label,
    required this.value,
    this.actionLabel,
    this.onActionTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackgroundColor;
  final String label;
  final String value;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BookingDetailsIconTile(
          icon: icon,
          iconColor: iconColor,
          backgroundColor: iconBackgroundColor,
          size: 34,
          iconSize: 18,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              if (actionLabel != null && onActionTap != null) ...[
                const SizedBox(height: 10),
                InkWell(
                  onTap: onActionTap,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        actionLabel!,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.open_in_new_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ProviderCompletedMetricRow extends StatelessWidget {
  const _ProviderCompletedMetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 7,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProviderDetailRow extends StatelessWidget {
  const _ProviderDetailRow({
    required this.label,
    required this.value,
    this.actionLabel,
    this.onActionTap,
  });

  final String label;
  final String value;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          if (actionLabel != null && onActionTap != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: onActionTap,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      actionLabel!,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.open_in_new_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProviderDetailDivider extends StatelessWidget {
  const _ProviderDetailDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 12),
      color: AppColors.textGrey.withValues(alpha: 0.12),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.booking, required this.currentUid});

  final CanonicalBookingDocumentV3 booking;
  final String currentUid;

  @override
  Widget build(BuildContext context) {
    final isParent = booking.parentId == currentUid;
    final effectiveState = effectiveCanonicalBookingPresentationState(booking);
    final statusLabel = effectiveState == CanonicalBookingStateV3.inProgress
        ? 'Service in progress'
        : effectiveState == CanonicalBookingStateV3.noShow
        ? 'No-show'
        : 'Confirmed';
    final statusColor = effectiveState == CanonicalBookingStateV3.noShow
        ? const Color(0xFFDC2626)
        : const Color(0xFF2FA56A);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF1E7), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  booking.service.serviceTitle,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            booking.participants.provider.displayName,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            effectiveState == CanonicalBookingStateV3.inProgress
                ? 'The provider has started this service. OTP reuse is disabled and cancellation is no longer available.'
                : effectiveState == CanonicalBookingStateV3.noShow
                ? 'This booking was marked as no-show because the service OTP was not entered before the service window ended.'
                : isParent
                ? 'Your payment is confirmed. Use this screen for your service OTP, provider contact, directions, and booking chat.'
                : 'Paid booking details, customer contact access, and booking chat are available here after payment confirmation.',
            style: TextStyle(
              color: AppColors.textGrey.withValues(alpha: 0.92),
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivateSection extends StatelessWidget {
  const _PrivateSection({
    required this.booking,
    required this.otpPrivateData,
    required this.participantPrivateData,
    required this.isOtpLoading,
    required this.otpErrorMessage,
    required this.participantErrorMessage,
    required this.currentUid,
    required this.onRetry,
    required this.onCallPhone,
    required this.onOpenMap,
  });

  final CanonicalBookingDocumentV3 booking;
  final CanonicalBookingPrivateData? otpPrivateData;
  final CanonicalBookingPrivateParticipantsData? participantPrivateData;
  final bool isOtpLoading;
  final String? otpErrorMessage;
  final String? participantErrorMessage;
  final String currentUid;
  final VoidCallback onRetry;
  final Future<void> Function(String phone) onCallPhone;
  final Future<void> Function(CanonicalBookingPrivateParticipantsData details)
  onOpenMap;

  @override
  Widget build(BuildContext context) {
    final isParent = booking.parentId == currentUid;
    final effectiveState = effectiveCanonicalBookingPresentationState(booking);
    if (isParent && effectiveState == CanonicalBookingStateV3.noShow) {
      return const SizedBox.shrink();
    }
    final otpDetails = otpPrivateData;
    final participantDetails = participantPrivateData;
    final hasOtpError =
        otpErrorMessage != null && otpErrorMessage!.trim().isNotEmpty;
    final hasParticipantError =
        participantErrorMessage != null &&
        participantErrorMessage!.trim().isNotEmpty;
    if (otpDetails == null &&
        participantDetails == null &&
        !isOtpLoading &&
        !hasOtpError &&
        !hasParticipantError) {
      return _InfoCard(
        title: isParent ? 'OTP' : 'Paid booking details',
        rows: [
          _InfoRow(
            'Status',
            'Private contact and OTP stay hidden until payment confirmation finishes.',
          ),
        ],
      );
    }
    final rows = <Widget>[
      if (isParent) ...[
        if (effectiveState == CanonicalBookingStateV3.inProgress ||
            booking.lifecycle.otpEnteredAt != null ||
            otpDetails?.otpState.toUpperCase() == 'USED')
          const _InfoRow(
            'Service status',
            'Service started. Your booking OTP has already been used for this booking.',
          )
        else if (otpDetails?.isOtpActive == true)
          _OtpInfoBlock(
            otpCode: otpDetails!.parentOtpCode,
            providerName: booking.participants.provider.displayName,
          )
        else if (isOtpLoading)
          const _InfoRow('Start OTP', 'Loading your service OTP...')
        else if (hasOtpError)
          _InfoRow(
            'Start OTP',
            'Your service OTP could not be loaded right now.',
          ),
      ],
      if (!isParent && participantDetails?.hasPhoneNumber == true)
        _InfoRow('Phone', participantDetails!.phoneNumber),
      if (!isParent && participantDetails?.hasAddress == true)
        _ActionInfoRow(
          label: 'Service address',
          value: participantDetails!.exactAddress,
          actionLabel: 'Get directions',
          onTap: () => onOpenMap(participantDetails),
        )
      else if (!isParent && hasParticipantError)
        _InfoRow(
          'Service address',
          'Directions could not be loaded right now.',
        ),
      if (!isParent && participantDetails?.hasProviderPhoneNumber == true)
        _ActionInfoRow(
          label: 'Provider contact',
          value: participantDetails!.providerPhoneNumber,
          actionLabel: 'Call provider',
          onTap: () => onCallPhone(participantDetails.providerPhoneNumber),
        )
      else if (!isParent && hasParticipantError)
        _InfoRow(
          'Provider contact',
          'Provider phone could not be loaded right now.',
        ),
    ];
    final needsRetry = hasOtpError || hasParticipantError;
    return _InfoCard(
      title: isParent ? 'OTP' : 'Paid booking details',
      rows: rows,
      footer: needsRetry
          ? SecondaryButton(
              label: 'Retry details',
              onPressed: onRetry,
              size: AppButtonSize.compact,
            )
          : null,
    );
  }
}

class _ProviderServiceStartSection extends StatelessWidget {
  const _ProviderServiceStartSection({
    required this.isVerifying,
    required this.onEnterOtp,
  });

  final bool isVerifying;
  final VoidCallback? onEnterOtp;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: 'Service start',
      rows: const [
        _InfoRow(
          'OTP required',
          'Ask the customer for their 6-digit service OTP when you begin the booking.',
        ),
        _InfoRow(
          'What happens next',
          'Entering the correct OTP starts the service and moves this booking to Service in progress.',
        ),
      ],
      footer: GradientButton(
        label: isVerifying ? 'Verifying...' : 'Enter customer OTP',
        onPressed: onEnterOtp,
        size: AppButtonSize.compact,
        isLoading: isVerifying,
      ),
    );
  }
}

class _NoShowStatusSection extends StatelessWidget {
  const _NoShowStatusSection({required this.booking});

  final CanonicalBookingDocumentV3 booking;

  @override
  Widget build(BuildContext context) {
    final disputeDeadlineAt = effectiveCanonicalNoShowDisputeDeadline(booking);
    return _InfoCard(
      title: 'No-show status',
      rows: [
        const _InfoRow(
          'Status',
          'The service OTP was not entered before the service window ended.',
        ),
        const _InfoRow(
          'Refund',
          'No automatic refund was issued under the default no-show policy.',
        ),
        _InfoRow(
          'Dispute',
          disputeDeadlineAt != null
              ? 'If the provider was unavailable, Pettxo support can review a dispute until ${_CanonicalBookingDetailScreenState._dateTime(disputeDeadlineAt)}.'
              : 'Dispute review remains available if the provider was unavailable.',
        ),
      ],
    );
  }
}

class _CompletionStatusSection extends StatelessWidget {
  const _CompletionStatusSection({
    required this.booking,
    required this.isParent,
    required this.isProvider,
    required this.reviewSubmittedLocally,
    required this.isSubmittingReview,
    required this.isSubmittingDispute,
    required this.onSubmitReview,
    required this.onRaiseDispute,
  });

  final CanonicalBookingDocumentV3 booking;
  final bool isParent;
  final bool isProvider;
  final bool reviewSubmittedLocally;
  final bool isSubmittingReview;
  final bool isSubmittingDispute;
  final VoidCallback? onSubmitReview;
  final VoidCallback? onRaiseDispute;

  @override
  Widget build(BuildContext context) {
    final reviewWindowEndsAt = booking.lifecycle.reviewWindowEndsAt;
    final hasOpenDispute =
        booking.dispute.status.trim().toLowerCase() == 'open';
    final disputeResolved =
        booking.dispute.status.trim().toLowerCase() == 'resolved';
    final reviewSubmitted = reviewSubmittedLocally;
    final isPendingReview =
        booking.state == CanonicalBookingStateV3.completedPendingReview;
    final payoutStatus = booking.payout.status.trim().toLowerCase();
    final countdownText = reviewWindowEndsAt == null
        ? 'Review window details are not available.'
        : DateTime.now().isBefore(reviewWindowEndsAt)
        ? 'Review window ends on ${_CanonicalBookingDetailScreenState._dateTime(reviewWindowEndsAt)}.'
        : 'Review window has ended and finalization is pending sync.';

    final rows = <_InfoRow>[
      _InfoRow(
        'Status',
        isPendingReview
            ? 'Service marked complete. The 24-hour customer review and dispute window is active.'
            : 'Service is finalized. No open customer review window remains.',
      ),
      _InfoRow('Window', countdownText),
      if (hasOpenDispute)
        const _InfoRow(
          'Dispute',
          'A dispute is open, so payout stays on hold until Pettxo reviews the case.',
        )
      else if (disputeResolved)
        _InfoRow(
          'Dispute',
          booking.dispute.customerRefundPaise > 0
              ? 'Dispute resolved. Approved refund: ${_CanonicalBookingDetailScreenState._moneyFromPaise(booking.dispute.customerRefundPaise)}.'
              : 'Dispute resolved with no additional customer refund.',
        )
      else if (isPendingReview && isProvider)
        const _InfoRow(
          'Provider',
          'Waiting for the customer to review the service or let the 24-hour window expire.',
        )
      else if (!isPendingReview && isProvider)
        const _InfoRow(
          'Provider',
          'This booking is finalized and is now payout-ready inside Pettxo.',
        ),
      if (!isPendingReview && isProvider)
        _InfoRow('Payout', _providerPayoutStatusLabel(payoutStatus, booking)),
      if (!isPendingReview && isParent && disputeResolved)
        _InfoRow(
          'Refund',
          booking.dispute.customerRefundPaise > 0
              ? 'If Pettxo approves money back, it returns only to the original payment source.'
              : 'No refund was awarded for this resolved dispute.',
        ),
      if (reviewSubmitted)
        const _InfoRow(
          'Review',
          'Your review has been submitted successfully.',
        ),
    ];

    Widget? footer;
    if (isPendingReview && isParent) {
      footer = Column(
        children: [
          GradientButton(
            label: reviewSubmitted
                ? 'Review submitted'
                : isSubmittingReview
                ? 'Submitting...'
                : 'Leave review',
            onPressed: reviewSubmitted || isSubmittingReview
                ? null
                : onSubmitReview,
            size: AppButtonSize.compact,
          ),
          const SizedBox(height: 10),
          SecondaryButton(
            label: hasOpenDispute
                ? 'Dispute submitted'
                : isSubmittingDispute
                ? 'Submitting...'
                : 'Raise dispute',
            onPressed: hasOpenDispute || isSubmittingDispute
                ? null
                : onRaiseDispute,
            size: AppButtonSize.compact,
          ),
        ],
      );
    } else if (!isPendingReview && isProvider) {
      footer = SecondaryButton(
        label: _providerPayoutButtonLabel(payoutStatus),
        onPressed: null,
        size: AppButtonSize.compact,
      );
    }

    return _InfoCard(title: 'Completion status', rows: rows, footer: footer);
  }

  static String _providerPayoutStatusLabel(
    String payoutStatus,
    CanonicalBookingDocumentV3 booking,
  ) {
    switch (payoutStatus) {
      case 'held':
        return booking.payout.holdReason.isNotEmpty
            ? booking.payout.holdReason
            : 'Payout is held until all financial checks are clear.';
      case 'ready':
        return 'Payout is ready inside Pettxo and waiting for secure processing.';
      case 'processing':
        return 'Payout processing has started.';
      case 'paid':
        return booking.payout.releasedAt != null
            ? 'Payout completed on ${_CanonicalBookingDetailScreenState._dateTime(booking.payout.releasedAt)}.'
            : 'Payout completed successfully.';
      case 'failed':
        return 'Payout needs Pettxo support review before it can proceed.';
      case 'cancelled':
        return 'No provider payout is due for this booking.';
      default:
        return 'Payout status will appear here once Pettxo finishes the final financial review.';
    }
  }

  static String _providerPayoutButtonLabel(String payoutStatus) {
    switch (payoutStatus) {
      case 'ready':
        return 'Payout ready';
      case 'processing':
        return 'Payout processing';
      case 'paid':
        return 'Payout completed';
      case 'failed':
        return 'Payout review needed';
      case 'cancelled':
        return 'No payout due';
      default:
        return 'Payout on hold';
    }
  }
}

class _CancellationStatusSection extends StatelessWidget {
  const _CancellationStatusSection({
    required this.bookingId,
    required this.repository,
    required this.booking,
  });

  final String bookingId;
  final BookingRepository repository;
  final CanonicalBookingDocumentV3 booking;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CanonicalBookingCancellationRecord?>(
      stream: repository.watchCanonicalBookingCancellation(bookingId),
      builder: (context, snapshot) {
        final cancellation = snapshot.data;
        if (booking.state != CanonicalBookingStateV3.cancelled &&
            cancellation == null) {
          return const SizedBox.shrink();
        }
        return _InfoCard(
          title: 'Cancellation',
          rows: [
            _InfoRow(
              'Status',
              cancellation?.status.isNotEmpty == true
                  ? cancellation!.status
                  : 'Cancelled',
            ),
            _InfoRow(
              'Refund status',
              cancellation?.refundStatus.isNotEmpty == true
                  ? cancellation!.refundStatus
                  : 'Pending',
            ),
            _InfoRow(
              'Refund amount',
              '₹${(((cancellation?.refundAmountPaise ?? booking.cancellation.refundAmountPaise) / 100)).toStringAsFixed(0)}',
            ),
            _InfoRow(
              'Policy band',
              cancellation?.timingBand.isNotEmpty == true
                  ? _CanonicalBookingDetailScreenState._labelForTimingBand(
                      cancellation!.timingBand,
                    )
                  : booking.cancellation.refundBand,
            ),
            _InfoRow(
              'Refund percentage',
              _CanonicalBookingDetailScreenState._percentLabel(
                cancellation?.refundPercentageBasisPoints ??
                    booking.cancellation.refundBasisPoints ??
                    0,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ChatSection extends StatelessWidget {
  const _ChatSection({
    required this.isParent,
    required this.isUnlocked,
    required this.isOpening,
    required this.onOpenChat,
  });

  final bool isParent;
  final bool isUnlocked;
  final bool isOpening;
  final VoidCallback? onOpenChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Booking chat',
            style: TextStyle(
              color: AppColors.textDark,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Use this chat to coordinate details for this booking.',
            style: const TextStyle(
              color: AppColors.textGrey,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          isUnlocked
              ? GradientButton(
                  label: isOpening
                      ? 'Opening...'
                      : (isParent ? 'Message provider' : 'Message customer'),
                  onPressed: isOpening ? null : onOpenChat,
                  size: AppButtonSize.compact,
                )
              : SecondaryButton(
                  label: isParent
                      ? 'Message provider after confirmation'
                      : 'Message customer after confirmation',
                  onPressed: null,
                  size: AppButtonSize.compact,
                ),
        ],
      ),
    );
  }
}

class _OtpInfoBlock extends StatelessWidget {
  const _OtpInfoBlock({required this.otpCode, required this.providerName});

  final String otpCode;
  final String providerName;

  @override
  Widget build(BuildContext context) {
    final digits = otpCode.split('');
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalGap = 6.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'START OTP',
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var index = 0; index < digits.length; index++) ...[
                  Expanded(
                    child: Container(
                      height: 58,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1E7),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          digits[index],
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (index != digits.length - 1)
                    SizedBox(width: horizontalGap),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                'Share this with $providerName only when the service actually begins. The OTP is what starts the clock.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textGrey,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.address, required this.onTapDirections});

  final String address;
  final VoidCallback onTapDirections;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Service address',
            style: TextStyle(
              color: AppColors.textDark,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            address,
            style: const TextStyle(
              color: AppColors.textDark,
              fontWeight: FontWeight.w700,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: onTapDirections,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.35),
                ),
                foregroundColor: AppColors.primary,
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
              child: const Text('Get directions'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.rows, this.footer});

  final String title;
  final List<Widget> rows;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          ...rows,
          if (footer != null) ...[const SizedBox(height: 14), footer!],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textGrey),
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
      ),
    );
  }
}

class _ActionInfoRow extends StatelessWidget {
  const _ActionInfoRow({
    required this.label,
    required this.value,
    required this.actionLabel,
    required this.onTap,
  });

  final String label;
  final String value;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textGrey),
            ),
          ),
          TextButton(onPressed: onTap, child: Text(actionLabel)),
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
}
