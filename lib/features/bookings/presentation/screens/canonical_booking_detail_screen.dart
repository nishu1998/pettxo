import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../messages/presentation/screens/chat_detail_screen.dart';
import '../controllers/canonical_booking_private_controller.dart';
import '../../data/repositories/booking_repository.dart';
import '../../domain/models/booking_document_v3.dart';
import '../../domain/models/booking_read_model.dart';
import '../../domain/models/canonical_booking_cancellation_models.dart';
import '../../domain/models/canonical_booking_private.dart';
import '../../domain/models/booking_v3_models.dart';
import '../../domain/utils/booking_request_attempt_id.dart';

class CanonicalBookingDetailScreen extends StatefulWidget {
  const CanonicalBookingDetailScreen({
    super.key,
    required this.bookingId,
    this.repository,
    this.privateController,
  });

  final String bookingId;
  final BookingRepository? repository;
  final CanonicalBookingPrivateController? privateController;

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
  bool _reviewSubmittedLocally = false;
  final TextEditingController _reviewCommentController =
      TextEditingController();
  final TextEditingController _disputeReasonController =
      TextEditingController();
  final TextEditingController _disputeDescriptionController =
      TextEditingController();
  int _reviewRating = 0;

  @override
  void dispose() {
    _reviewCommentController.dispose();
    _disputeReasonController.dispose();
    _disputeDescriptionController.dispose();
    if (_ownsPrivateController) {
      _privateController.dispose();
    }
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
          'Booking details',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.w900,
          ),
        ),
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

          final currentUid =
              FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
          final isParent = booking.parentId == currentUid;
          final userIsProvider = booking.providerId == currentUid;
          final canReadPrivate =
              booking.state == CanonicalBookingStateV3.confirmed &&
              booking.lifecycle.paidAt != null &&
              isParent;
          final canReadParticipantPrivate =
              booking.lifecycle.paidAt != null &&
              (booking.state == CanonicalBookingStateV3.confirmed ||
                  booking.state == CanonicalBookingStateV3.inProgress);
          _privateController.bind(
            bookingId: widget.bookingId,
            shouldLoadPrivate: canReadPrivate,
          );

          return StreamBuilder<CanonicalBookingPrivateParticipantsData?>(
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
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                    children: [
                      _HeroCard(booking: booking),
                      const SizedBox(height: 14),
                      _CancellationStatusSection(
                        bookingId: widget.bookingId,
                        repository: _repository,
                        booking: booking,
                      ),
                      if (booking.state == CanonicalBookingStateV3.noShow) ...[
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
                      const SizedBox(height: 14),
                      _InfoCard(
                        title: 'Schedule',
                        rows: [
                          _InfoRow(
                            'Type',
                            booking.bookingType.name.toUpperCase(),
                          ),
                          _InfoRow('When', _scheduleLabel(booking)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _PrivateSection(
                        booking: booking,
                        otpPrivateData: privateState.privateData,
                        participantPrivateData: participantSnapshot.data,
                        isLoading: privateState.isLoading,
                        errorMessage: privateState.errorMessage,
                        currentUid: currentUid,
                      ),
                      const SizedBox(height: 14),
                      _ChatSection(
                        bookingId: widget.bookingId,
                        isUnlocked: booking.privacy.chatUnlockedAt != null,
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

  static String _scheduleLabel(CanonicalBookingDocumentV3 booking) {
    final schedule = booking.schedule;
    if (schedule is CanonicalSlotBookingScheduleV3) {
      return _dateTime(schedule.scheduledStartAt);
    }
    if (schedule is CanonicalRangeBookingScheduleV3) {
      return '${_dateTime(schedule.checkInDateTime)} to ${_dateTime(schedule.checkOutDateTime)}';
    }
    return 'Schedule unavailable';
  }

  Widget _buildActions(CanonicalBookingDocumentV3 booking) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final isParent = booking.parentId == currentUid;
    final isProvider = booking.providerId == currentUid;
    final canCancel =
        booking.state == CanonicalBookingStateV3.confirmed &&
        (isParent || isProvider);
    final canStart =
        booking.state == CanonicalBookingStateV3.confirmed && isProvider;
    final canComplete =
        booking.state == CanonicalBookingStateV3.inProgress && isProvider;
    if (!canCancel && !canStart && !canComplete) {
      return const SizedBox.shrink();
    }
    final label = isProvider ? 'Cancel as provider' : 'Cancel booking';
    return Column(
      children: [
        if (canStart)
          GradientButton(
            label: _isStartingService ? 'Starting...' : 'Start service',
            onPressed: _isStartingService
                ? null
                : () => _startServiceFlow(bookingId: widget.bookingId),
            size: AppButtonSize.compact,
          ),
        if (canStart && (canCancel || canComplete)) const SizedBox(height: 10),
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
      final controller = TextEditingController();
      final confirmed = await showModalBottomSheet<String>(
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
                  'Enter service OTP',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ask the pet parent for the six-digit OTP shown in their confirmed booking details.',
                  style: TextStyle(
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: 'Enter OTP',
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        label: 'Cancel',
                        onPressed: () => Navigator.of(context).pop(),
                        size: AppButtonSize.compact,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GradientButton(
                        label: 'Verify OTP',
                        onPressed: () =>
                            Navigator.of(context).pop(controller.text.trim()),
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
      controller.dispose();
      if (!mounted || confirmed == null) return;
      final otp = confirmed.trim();
      if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
        AppSnackbar.showError(context, 'Enter a valid 6-digit OTP.');
        return;
      }
      setState(() => _isStartingService = true);
      await _repository.verifyBookingStartOtpV3(
        bookingId: bookingId,
        otp: otp,
        requestAttemptId: BookingRequestAttemptIdController.generate(),
      );
      if (!mounted) return;
      AppSnackbar.showSuccess(context, 'Service started successfully.');
    } catch (error) {
      if (!mounted) return;
      final message = '$error';
      if (message.contains('resource-exhausted')) {
        AppSnackbar.showError(
          context,
          'Too many incorrect OTP attempts. Please wait before trying again.',
        );
      } else if (message.contains('permission-denied')) {
        AppSnackbar.showError(context, 'The OTP is invalid.');
      } else if (message.contains('AFTER_SERVICE_END') ||
          message.contains('service-start window has already passed')) {
        AppSnackbar.showError(
          context,
          'This service can no longer be started because the service window has ended.',
        );
      } else {
        AppSnackbar.showError(
          context,
          message.trim().isEmpty
              ? 'Could not start this service right now.'
              : message,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isStartingService = false);
      }
    }
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
      await _repository.completeBookingServiceV3(bookingId: bookingId);
      if (!mounted) return;
      AppSnackbar.showSuccess(
        context,
        'Service completed. The customer now has 24 hours to review or dispute.',
      );
    } catch (error) {
      if (!mounted) return;
      AppSnackbar.showError(
        context,
        '$error'.contains('failed-precondition')
            ? 'This booking cannot be completed right now.'
            : 'Could not complete this service right now.',
      );
    } finally {
      if (mounted) {
        setState(() => _isCompletingService = false);
      }
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
      if (!mounted) return;
      AppSnackbar.showError(
        context,
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
      if (!mounted) return;
      AppSnackbar.showError(
        context,
        '$error'.contains('failed-precondition')
            ? 'This booking is no longer eligible for dispute submission.'
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
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.booking});

  final CanonicalBookingDocumentV3 booking;

  @override
  Widget build(BuildContext context) {
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              booking.state == CanonicalBookingStateV3.inProgress
                  ? 'Service in progress'
                  : booking.state == CanonicalBookingStateV3.noShow
                  ? 'No-show'
                  : 'Confirmed',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            booking.service.serviceTitle,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            booking.state == CanonicalBookingStateV3.inProgress
                ? 'The provider has started this service. OTP reuse is disabled and cancellation is no longer available.'
                : booking.state == CanonicalBookingStateV3.noShow
                ? 'This booking was marked as no-show because the service OTP was not entered before the service window ended.'
                : 'OTP, contact access, and booking chat are available only after Pettxo confirms payment in Firestore.',
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
    required this.isLoading,
    required this.errorMessage,
    required this.currentUid,
  });

  final CanonicalBookingDocumentV3 booking;
  final CanonicalBookingPrivateData? otpPrivateData;
  final CanonicalBookingPrivateParticipantsData? participantPrivateData;
  final bool isLoading;
  final String? errorMessage;
  final String currentUid;

  @override
  Widget build(BuildContext context) {
    final isParent = booking.parentId == currentUid;
    if (isLoading) {
      return const _InfoCard(
        title: 'Private access',
        rows: [_InfoRow('Status', 'Loading paid-only details...')],
      );
    }
    if (errorMessage != null && errorMessage!.trim().isNotEmpty) {
      return _InfoCard(
        title: 'Private access',
        rows: [_InfoRow('Status', errorMessage!)],
      );
    }
    if (otpPrivateData == null && participantPrivateData == null) {
      return _InfoCard(
        title: 'Private access',
        rows: [
          _InfoRow(
            'Status',
            booking.state == CanonicalBookingStateV3.noShow
                ? 'The service OTP is no longer available because this booking was marked as no-show.'
                : 'Private contact and OTP stay hidden until payment confirmation finishes.',
          ),
        ],
      );
    }
    final otpDetails = otpPrivateData;
    final participantDetails = participantPrivateData;
    return _InfoCard(
      title: 'Paid-only details',
      rows: [
        if (isParent &&
            booking.state == CanonicalBookingStateV3.confirmed &&
            otpDetails?.isOtpActive == true)
          _InfoRow('Service OTP', otpDetails!.parentOtpCode),
        if (participantDetails?.hasPhoneNumber == true)
          _ActionInfoRow(
            label: 'Phone',
            value: participantDetails!.phoneNumber,
            actionLabel: 'Call',
            onTap: () => _launchPhone(context, participantDetails.phoneNumber),
          ),
        if (participantDetails?.hasAddress == true)
          _InfoRow('Address', participantDetails!.exactAddress),
        _InfoRow(
          'Chat',
          booking.privacy.chatUnlockedAt != null
              ? 'Booking chat is unlocked inside Pettxo.'
              : 'Chat is still locked.',
        ),
      ],
    );
  }

  Future<void> _launchPhone(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.trim());
    if (!await canLaunchUrl(uri)) {
      if (!context.mounted) return;
      AppSnackbar.showError(context, 'Could not open the phone dialer.');
      return;
    }
    await launchUrl(uri);
  }
}

class _NoShowStatusSection extends StatelessWidget {
  const _NoShowStatusSection({required this.booking});

  final CanonicalBookingDocumentV3 booking;

  @override
  Widget build(BuildContext context) {
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
          booking.lifecycle.disputeDeadlineAt != null
              ? 'If the provider was unavailable, Pettxo support can review a dispute until ${_CanonicalBookingDetailScreenState._dateTime(booking.lifecycle.disputeDeadlineAt)}.'
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
  const _ChatSection({required this.bookingId, required this.isUnlocked});

  final String bookingId;
  final bool isUnlocked;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: 'Booking chat',
      rows: [
        _InfoRow(
          'Notice',
          'Bookings made outside Pettxo are not covered by OTP verification, dispute protection, or refunds.',
        ),
      ],
      footer: isUnlocked
          ? GradientButton(
              label: 'Open booking chat',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatDetailScreen(chatId: bookingId),
                  ),
                );
              },
              size: AppButtonSize.compact,
            )
          : const SecondaryButton(
              label: 'Chat unlocks after confirmation',
              onPressed: null,
              size: AppButtonSize.compact,
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
