import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/navigation/social_app_tab.dart';
import '../../../../core/services/app_loader.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../../restrictions/data/services/user_restriction_service.dart';
import '../../data/repositories/booking_repository.dart';
import '../../data/repositories/booking_review_repository.dart';
import '../../domain/models/booking_model.dart';
import '../../domain/models/booking_flow_models.dart';
import '../widgets/section_block.dart';
import '../widgets/status_chip.dart';

class BookingDetailScreen extends StatefulWidget {
  final String bookingId;
  final BookingContextMode contextMode;
  final BookingRecord? fallbackBooking;

  const BookingDetailScreen({
    super.key,
    required this.bookingId,
    required this.contextMode,
    this.fallbackBooking,
  });

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  final BookingRepository _bookingRepository = BookingRepository();
  final BookingReviewRepository _bookingReviewRepository =
      BookingReviewRepository();
  late final Timer _timer;
  static const List<String> _reviewQuickTags = [
    'Friendly provider',
    'On time',
    'Handled with care',
    'Clean setup',
    'Great communication',
    'Would book again',
  ];

  int _starRating = 0;
  String? _activeRequestAction;
  String? _activeLifecycleAction;
  String? _generatedOtp;
  bool _isSubmittingReview = false;
  bool _reviewSubmittedLocally = false;
  final Set<String> _selectedReviewTags = <String>{};
  final Map<String, Future<BookingContactSnapshot>> _contactDetailsCache = {};
  final TextEditingController _reviewController = TextEditingController();
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // Request-expiry copy is based on Firestore timestamps and should tick
      // without recreating or mutating the booking document.
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _reviewController.dispose();
    for (final controller in _otpControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  String _formatCountdown(int initialSeconds) {
    final remaining = initialSeconds.clamp(0, 99999);
    final minutes = remaining ~/ 60;
    final seconds = remaining % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatRemainingUntil(DateTime? expiresAt) {
    if (expiresAt == null) return 'not available';
    final seconds = expiresAt.difference(DateTime.now()).inSeconds;
    if (seconds <= 0) return 'expired';
    return _formatCountdown(seconds);
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

  Future<BookingContactSnapshot> _contactDetailsFor(
    BookingModel booking, {
    required bool includeProviderPhone,
  }) {
    return _contactDetailsCache.putIfAbsent(
      '${booking.id}:$includeProviderPhone',
      () => _bookingRepository.fetchPostConfirmationDetails(
        booking,
        includeProviderPhone: includeProviderPhone,
      ),
    );
  }

  bool _isCustomer(BookingModel booking) {
    return FirebaseAuth.instance.currentUser?.uid == booking.customerId;
  }

  bool _isProvider(BookingModel booking) {
    return FirebaseAuth.instance.currentUser?.uid == booking.providerId;
  }

  String _maskPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return '';
    return '******${digits.substring(digits.length - 4)}';
  }

  Future<void> _launchPhoneDialer(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.length < 8) {
      _showToast(
        'Provider phone number is not available yet.',
        tone: AppSnackbarTone.warning,
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: digits);
    if (!await canLaunchUrl(uri)) {
      _showToast(
        'Could not open the phone dialer.',
        tone: AppSnackbarTone.error,
      );
      return;
    }

    await launchUrl(uri);
  }

  Future<void> _launchMaps({
    required String address,
    required double latitude,
    required double longitude,
  }) async {
    final hasCoordinates = latitude != 0 || longitude != 0;
    final query = hasCoordinates ? '$latitude,$longitude' : address.trim();

    if (query.isEmpty) {
      _showToast(
        'Location is not available for this booking.',
        tone: AppSnackbarTone.warning,
      );
      return;
    }

    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': query,
    });

    if (!await canLaunchUrl(uri)) {
      _showToast('Could not open maps.', tone: AppSnackbarTone.error);
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _runRequestAction({
    required String bookingId,
    required bool accept,
  }) async {
    if (_activeRequestAction != null) return;

    setState(() => _activeRequestAction = accept ? 'accept' : 'reject');
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
        setState(() => _activeRequestAction = null);
      }
    }
  }

  Future<void> _cancelBooking(BookingModel booking) async {
    if (_activeLifecycleAction != null) return;

    try {
      final preview = await _bookingRepository.previewCancellation(
        bookingId: booking.id,
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Cancel booking?'),
            content: Text(
              'Refund will be ${_moneyFromPaise(preview.refundAmountPaise)} based on current timing.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Go Back'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirm Cancel'),
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;

      setState(() => _activeLifecycleAction = 'cancelBooking');
      AppLoader.showWithMessage('Cancelling booking...');
      final result = await _bookingRepository.cancelBookingWithBreakdown(
        bookingId: booking.id,
        reason: 'Cancelled from booking details',
      );
      _showToast(
        'Booking cancelled. Refund: ${_moneyFromPaise(result.refundAmountPaise)}.',
        tone: AppSnackbarTone.success,
      );
    } catch (error) {
      _showToast(
        _friendlyCancellationError(error),
        tone: AppSnackbarTone.error,
      );
    } finally {
      AppLoader.hide();
      if (mounted) setState(() => _activeLifecycleAction = null);
    }
  }

  Future<void> _raiseDispute(BookingModel booking) async {
    if (_activeLifecycleAction != null) return;
    final reasonController = TextEditingController();
    final descriptionController = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
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
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    hintText: 'Service issue, payment concern, no-show...',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Tell us what happened.',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext, false),
                        child: const Text('Close'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        child: const Text('Submit'),
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

    if (confirmed != true) return;

    setState(() => _activeLifecycleAction = 'raiseDispute');
    AppLoader.showWithMessage('Submitting dispute...');
    try {
      await _bookingRepository.raiseDispute(
        bookingId: booking.id,
        reason: reasonController.text,
        description: descriptionController.text,
      );
      _showToast(
        'Dispute submitted. Your payout or refund outcome is now on hold for review.',
        tone: AppSnackbarTone.success,
      );
    } catch (error) {
      _showToast(_friendlyDisputeError(error), tone: AppSnackbarTone.error);
    } finally {
      reasonController.dispose();
      descriptionController.dispose();
      AppLoader.hide();
      if (mounted) setState(() => _activeLifecycleAction = null);
    }
  }

  Future<void> _generateOtp(BookingModel booking) async {
    if (_activeLifecycleAction != null) return;

    setState(() {
      _activeLifecycleAction = 'generateOtp';
      _generatedOtp = null;
    });
    AppLoader.showWithMessage('Generating secure code...');

    try {
      final otp = await _bookingRepository.generateBookingOtp(
        bookingId: booking.id,
      );
      setState(() => _generatedOtp = otp);
      _showToast(
        'OTP generated. Share it with the provider.',
        tone: AppSnackbarTone.success,
      );
    } catch (error) {
      _showToast(_friendlyLifecycleError(error), tone: AppSnackbarTone.error);
    } finally {
      AppLoader.hide();
      if (mounted) setState(() => _activeLifecycleAction = null);
    }
  }

  Future<void> _verifyOtpAndStart(BookingModel booking) async {
    if (_activeLifecycleAction != null) return;

    final otp = _otpControllers.map((controller) => controller.text).join();
    if (otp.length != 6) {
      _showToast(
        'Enter the 6-digit OTP shared by the pet parent.',
        tone: AppSnackbarTone.warning,
      );
      return;
    }

    setState(() => _activeLifecycleAction = 'verifyOtp');
    AppLoader.showWithMessage('Verifying secure code...');

    try {
      await _bookingRepository.verifyBookingOtpAndStart(
        bookingId: booking.id,
        otp: otp,
      );
      for (final controller in _otpControllers) {
        controller.clear();
      }
      _showToast(
        'OTP verified. Service started.',
        tone: AppSnackbarTone.success,
      );
    } catch (error) {
      _showToast(_friendlyLifecycleError(error), tone: AppSnackbarTone.error);
    } finally {
      AppLoader.hide();
      if (mounted) setState(() => _activeLifecycleAction = null);
    }
  }

  Future<void> _completeBooking(BookingModel booking) async {
    if (_activeLifecycleAction != null) return;

    setState(() => _activeLifecycleAction = 'completeBooking');
    AppLoader.showWithMessage('Completing service...');

    try {
      await _bookingRepository.completeBooking(bookingId: booking.id);
      _showToast(
        'Service completed. Payout is now eligible.',
        tone: AppSnackbarTone.success,
      );
    } catch (error) {
      _showToast(_friendlyLifecycleError(error), tone: AppSnackbarTone.error);
    } finally {
      AppLoader.hide();
      if (mounted) setState(() => _activeLifecycleAction = null);
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

  String _friendlyCancellationError(Object error) {
    final text = error.toString();
    if (text.contains('failed-precondition')) {
      return 'This booking can no longer be cancelled.';
    }
    if (text.contains('permission-denied')) {
      return 'Only booking participants can cancel this booking.';
    }
    if (text.contains('not-found')) return 'Booking or slot not found.';
    return 'Could not cancel booking. Please try again.';
  }

  String _friendlyLifecycleError(Object error) {
    final text = error.toString();
    if (text.contains('deadline-exceeded')) {
      return 'OTP expired. Ask the pet parent to generate a new one.';
    }
    if (text.contains('failed-precondition')) {
      return 'This booking is not in the right state for that action.';
    }
    if (text.contains('permission-denied')) {
      return 'You do not have permission for this booking action.';
    }
    if (text.contains('not-found')) return 'Booking not found.';
    if (text.contains('invalid-argument')) {
      return 'Please check the booking details and try again.';
    }
    return 'Could not update booking. Please try again.';
  }

  String _friendlyReviewError(Object error) {
    final text = error.toString();
    if (text.contains('failed-precondition')) {
      return 'This booking has already been reviewed or is not ready for review.';
    }
    if (text.contains('permission-denied')) {
      return 'Only the pet parent can submit a review for this booking.';
    }
    if (text.contains('invalid-argument')) {
      return 'Please select a rating before submitting your review.';
    }
    if (text.contains('not-found')) {
      return 'Booking details could not be found.';
    }
    return 'Could not submit review. Please try again.';
  }

  String _friendlyDisputeError(Object error) {
    final text = error.toString();
    if (text.contains('failed-precondition')) {
      return 'This booking is no longer inside the dispute window.';
    }
    if (text.contains('permission-denied')) {
      return 'Only booking participants can raise a dispute.';
    }
    if (text.contains('invalid-argument')) {
      return 'Please add both a reason and a description.';
    }
    if (text.contains('not-found')) {
      return 'Booking details could not be found.';
    }
    return 'Could not submit dispute right now.';
  }

  Future<void> _submitReview(BookingModel booking) async {
    if (_isSubmittingReview || booking.hasReview || _reviewSubmittedLocally) {
      return;
    }
    if (!UserRestrictionService.instance.ensureCanUseBookingFeatures(context)) {
      return;
    }
    if (_starRating < 1) {
      _showToast(
        'Select a star rating before submitting your review.',
        tone: AppSnackbarTone.warning,
      );
      return;
    }

    setState(() => _isSubmittingReview = true);
    AppLoader.showWithMessage('Submitting your review...');

    try {
      await _bookingReviewRepository.submitBookingReview(
        bookingId: booking.id,
        rating: _starRating,
        comment: _reviewController.text,
        tags: _selectedReviewTags.toList(growable: false),
      );
      if (kDebugMode) {
        debugPrint(
          'Review submit debug -> success | bookingId=${booking.id} | rating=$_starRating | tags=${_selectedReviewTags.toList(growable: false)}',
        );
      }
      if (!mounted) return;
      setState(() => _reviewSubmittedLocally = true);
      _showToast(
        'Review submitted successfully.',
        tone: AppSnackbarTone.success,
      );
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        Navigator.of(context).maybePop(true);
      });
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'Review submit debug -> failure | bookingId=${booking.id} | error=$error',
        );
      }
      _showToast(_friendlyReviewError(error), tone: AppSnackbarTone.error);
    } finally {
      AppLoader.hide();
      if (mounted) {
        setState(() => _isSubmittingReview = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final topContentPadding = topInset + 100;
    final bottomContentPadding = SocialBottomNav.contentBottomPadding(context);
    final title = switch (widget.fallbackBooking?.detailType) {
      BookingDetailType.deliveringRequest => 'Booking Request',
      _ => 'Booking Details',
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: Stack(
        children: [
          StreamBuilder<BookingModel?>(
            stream: _bookingRepository.watchBookingById(widget.bookingId),
            builder: (context, snapshot) {
              final booking = snapshot.data;
              if (kDebugMode && booking != null) {
                debugPrint(
                  'Booking review state debug -> bookingId=${booking.id} | hasReview=${booking.hasReview} | reviewStatus=${booking.reviewStatus} | reviewId=${booking.reviewId}',
                );
              }
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  18,
                  topContentPadding,
                  18,
                  bottomContentPadding,
                ),
                children: [
                  if (snapshot.hasError)
                    _DetailStateCard(
                      icon: Icons.cloud_off_rounded,
                      title: 'Could not load booking',
                      subtitle: snapshot.error.toString(),
                    )
                  else if (snapshot.connectionState ==
                          ConnectionState.waiting &&
                      booking == null)
                    const _DetailLoadingCard()
                  else if (booking == null)
                    const _DetailStateCard(
                      icon: Icons.event_busy_outlined,
                      title: 'Booking not found',
                      subtitle:
                          'This booking may have been removed or is no longer available.',
                    )
                  else
                    ..._buildDetailContent(booking),
                ],
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            top: topInset + 10,
            child: Align(
              child: FractionallySizedBox(
                widthFactor: 0.85,
                child: GlassSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  backgroundColor: Colors.white.withValues(alpha: 0.72),
                  blurSigma: 20,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
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
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.56),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
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
            ),
          ),
        ],
      ),
      bottomNavigationBar: const SocialBottomNav(
        activeTab: SocialAppTab.profile,
      ),
    );
  }

  List<Widget> _buildDetailContent(BookingModel booking) {
    final record = booking.toBookingRecord(widget.contextMode);
    switch (record.detailType) {
      case BookingDetailType.receivingConfirmed:
        return _buildReceivingConfirmed(booking, record);
      case BookingDetailType.receivingRequested:
        return _buildReceivingRequested(booking, record);
      case BookingDetailType.receivingCompleted:
        return _buildReceivingCompleted(booking, record);
      case BookingDetailType.deliveringRequest:
        return _buildDeliveringRequest(booking, record);
      case BookingDetailType.deliveringConfirmed:
        return _buildDeliveringConfirmed(booking, record);
      case null:
        return [_buildGenericDetails(booking, record)];
    }
  }

  List<Widget> _bookingPolicySections(BookingModel booking) {
    final sections = <Widget>[];
    final remainingGrace = booking.remainingGraceDuration;

    if (booking.isNoShow) {
      sections.add(
        const _BannerCard(
          backgroundColor: Color(0xFFFFF1EF),
          text: 'This booking was marked as no-show. No refund applicable.',
        ),
      );
    } else if (booking.isCancelled) {
      sections.add(
        _BannerCard(
          backgroundColor: const Color(0xFFEFF6FF),
          text:
              'Cancellation recorded. Refund: ${_moneyFromPaise(booking.cancellationRefundAmountPaise)} · Provider share: ${_moneyFromPaise(booking.cancellationProviderAmountPaise)}.',
        ),
      );
    } else if (remainingGrace != null && remainingGrace > Duration.zero) {
      sections.add(
        _BannerCard(
          backgroundColor: const Color(0xFFDCFCE7),
          text:
              'Cancel within ${_formatCountdown(remainingGrace.inSeconds)} for a full refund.',
        ),
      );
    } else if ((booking.isRequested || booking.isAccepted) &&
        !booking.isCancelled &&
        !booking.isCompleted &&
        !booking.isInProgress) {
      sections.add(
        const _BannerCard(
          backgroundColor: Color(0xFFFEF3C7),
          text: 'Cancellation charges apply now.',
        ),
      );
    }

    if (booking.hasDispute) {
      sections.add(
        _BannerCard(
          backgroundColor: const Color(0xFFEFF6FF),
          text:
              'Dispute status: ${_titleCase(_emptyFallback(booking.disputeStatus, fallback: 'open'))}',
        ),
      );
    } else if (booking.canRaiseDispute) {
      sections.add(
        SectionBlock(
          title: 'DISPUTE SUPPORT',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'If something went wrong, you can raise a dispute until 24 hours after the service is completed.',
                style: TextStyle(color: AppColors.textGrey, height: 1.5),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _activeLifecycleAction == null
                      ? () => _raiseDispute(booking)
                      : null,
                  icon: const Icon(Icons.report_gmailerrorred_rounded),
                  label: Text(
                    _activeLifecycleAction == 'raiseDispute'
                        ? 'Submitting...'
                        : 'Raise dispute',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (sections.isEmpty) return const [];
    return [
      ...sections.expand((widget) => [widget, const SizedBox(height: 12)]),
    ];
  }

  List<Widget> _buildReceivingConfirmed(
    BookingModel booking,
    BookingRecord record,
  ) {
    return [
      _BannerCard(
        backgroundColor: const Color(0xFFFEF3C7),
        text:
            'Booking confirmed for ${_dateLabel(booking.scheduledStartAt)} at ${_timeLabel(booking.scheduledStartAt)}.',
      ),
      ..._bookingPolicySections(booking),
      SectionBlock(
        title: 'SERVICE',
        rows: [
          DetailRowData(label: 'Service', value: booking.serviceName),
          DetailRowData(
            label: 'Animal',
            value: _emptyFallback(booking.animalType),
          ),
          DetailRowData(
            label: 'Provider',
            value: '${booking.providerName} ↗',
            valueColor: AppColors.primary,
          ),
        ],
      ),
      const SizedBox(height: 12),
      SectionBlock(
        title: 'SCHEDULE',
        rows: [
          DetailRowData(
            label: 'Date',
            value: _dateLabel(booking.scheduledStartAt),
          ),
          DetailRowData(
            label: 'Time',
            value: _timeLabel(booking.scheduledStartAt),
          ),
          DetailRowData(
            label: 'Duration',
            value: '${booking.durationMinutes} min',
          ),
        ],
      ),
      const SizedBox(height: 12),
      SectionBlock(
        title: 'STATUS',
        rows: [
          DetailRowData(
            label: 'Status',
            value: '',
            trailing: StatusChip(
              label: record.statusLabel,
              tone: record.statusTone,
            ),
          ),
          DetailRowData(
            label: 'Paid',
            value: _moneyFromPaise(booking.grossAmountPaise),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SectionBlock(
        title: 'YOUR SERVICE OTP',
        child: _CustomerOtpPanel(
          booking: booking,
          generatedOtp: _generatedOtp,
          isLoading: _activeLifecycleAction == 'generateOtp',
          timeText: _formatRemainingUntil(booking.otpExpiresAt),
          onGenerate: booking.canCustomerGenerateOtp
              ? () => _generateOtp(booking)
              : null,
        ),
      ),
      const SizedBox(height: 12),
      ..._postConfirmationActionSections(booking),
      const SizedBox(height: 12),
      _DualActionRow(
        primaryLabel: _activeLifecycleAction == 'cancelBooking'
            ? 'Cancelling...'
            : 'Cancel booking',
        primaryStyle: BookingActionStyle.danger,
        secondaryLabel: 'Message',
        secondaryStyle: BookingActionStyle.secondary,
        onPrimaryTap:
            booking.canCancelBeforeStart && _activeLifecycleAction == null
            ? () => _cancelBooking(booking)
            : null,
        onSecondaryTap: () => _showToast('Messaging flow opened'),
      ),
    ];
  }

  List<Widget> _buildReceivingRequested(
    BookingModel booking,
    BookingRecord record,
  ) {
    return [
      _BannerCard(
        backgroundColor: const Color(0xFFEFF6FF),
        text:
            'Waiting for provider to confirm · Response window ends in ${_formatRemainingUntil(booking.requestExpiresAt)}',
      ),
      _BannerCard(
        backgroundColor: const Color(0xFFFEF3C7),
        text:
            'Payment status: ${_titleCase(_emptyFallback(booking.paymentStatus, fallback: 'pending'))}',
      ),
      ..._bookingPolicySections(booking),
      SectionBlock(
        title: 'SERVICE',
        rows: [
          DetailRowData(label: 'Service', value: booking.serviceName),
          DetailRowData(
            label: 'Animal',
            value: _emptyFallback(booking.animalType),
          ),
          DetailRowData(
            label: 'Provider',
            value: '${booking.providerName} ↗',
            valueColor: AppColors.primary,
          ),
        ],
      ),
      const SizedBox(height: 12),
      SectionBlock(
        title: 'SCHEDULE',
        rows: [
          DetailRowData(
            label: 'Date',
            value: _dateLabel(booking.scheduledStartAt),
          ),
          DetailRowData(
            label: 'Time',
            value: _timeLabel(booking.scheduledStartAt),
          ),
          DetailRowData(
            label: 'Duration',
            value: '${booking.durationMinutes} min',
          ),
        ],
      ),
      const SizedBox(height: 12),
      SectionBlock(
        title: 'STATUS',
        rows: [
          DetailRowData(
            label: 'Status',
            value: '',
            trailing: StatusChip(
              label: record.statusLabel,
              tone: record.statusTone,
            ),
          ),
          DetailRowData(
            label: 'Paid',
            value: _moneyFromPaise(booking.grossAmountPaise),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const SectionBlock(
        title: 'CONTACT',
        backgroundColor: Color(0xFFF3F4F6),
        child: Text(
          'Phone number unlocks after the provider confirms the booking.',
          style: TextStyle(color: AppColors.textGrey, fontSize: 12.5),
        ),
      ),
      const SizedBox(height: 12),
      _DualActionRow(
        primaryLabel: _activeLifecycleAction == 'cancelBooking'
            ? 'Cancelling...'
            : 'Cancel request',
        primaryStyle: BookingActionStyle.danger,
        secondaryLabel: 'Message',
        secondaryStyle: BookingActionStyle.secondary,
        onPrimaryTap: _activeLifecycleAction == null
            ? () => _cancelBooking(booking)
            : null,
        onSecondaryTap: () => _showToast('Messaging flow opened'),
      ),
      const SizedBox(height: 12),
      ..._postConfirmationActionSections(booking),
    ];
  }

  List<Widget> _buildReceivingCompleted(
    BookingModel booking,
    BookingRecord record,
  ) {
    final hasSubmittedReview =
        booking.hasReview ||
        booking.reviewStatus.trim().toLowerCase() == 'submitted' ||
        _reviewSubmittedLocally;

    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x3315803D)),
        ),
        child: const Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: Color(0xFF15803D),
              child: Icon(Icons.check_rounded, color: Colors.white, size: 18),
            ),
            SizedBox(width: 10),
            Text(
              'Service Completed',
              style: TextStyle(
                color: Color(0xFF15803D),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      ..._bookingPolicySections(booking),
      SectionBlock(
        title: 'REVIEW ${booking.providerName.toUpperCase()}',
        child: hasSubmittedReview
            ? const _ReviewSubmittedState()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'How was your experience?',
                    style: TextStyle(color: AppColors.textGrey, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final isLit = index < _starRating;
                      return IconButton(
                        onPressed: _isSubmittingReview
                            ? null
                            : () => setState(() => _starRating = index + 1),
                        icon: Icon(
                          Icons.star_rounded,
                          color: isLit
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFFD1D5DB),
                          size: 30,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _reviewQuickTags.map((tag) {
                      final selected = _selectedReviewTags.contains(tag);
                      return FilterChip(
                        label: Text(tag),
                        selected: selected,
                        onSelected: _isSubmittingReview
                            ? null
                            : (value) {
                                setState(() {
                                  if (value) {
                                    _selectedReviewTags.add(tag);
                                  } else {
                                    _selectedReviewTags.remove(tag);
                                  }
                                });
                              },
                        backgroundColor: Colors.white,
                        selectedColor: const Color(0xFFFEF0EB),
                        checkmarkColor: AppColors.primary,
                        side: BorderSide(
                          color: selected
                              ? const Color(0xFFF7A07A)
                              : const Color(0x1A000000),
                        ),
                        labelStyle: TextStyle(
                          color: selected
                              ? AppColors.primary
                              : AppColors.textDark,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _reviewController,
                    enabled: !_isSubmittingReview,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Tell others about your experience...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0x1A000000)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0x1A000000)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _DualActionRow(
                    primaryLabel: _isSubmittingReview
                        ? 'Submitting...'
                        : 'Submit review',
                    primaryStyle: BookingActionStyle.primary,
                    secondaryLabel: 'Skip',
                    secondaryStyle: BookingActionStyle.secondary,
                    onPrimaryTap: _starRating > 0 && !_isSubmittingReview
                        ? () => _submitReview(booking)
                        : null,
                    onSecondaryTap: _isSubmittingReview
                        ? null
                        : () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
      ),
      const SizedBox(height: 12),
      SectionBlock(
        title: 'SERVICE',
        rows: [
          DetailRowData(label: 'Service', value: booking.serviceName),
          DetailRowData(
            label: 'Animal',
            value: _emptyFallback(booking.animalType),
          ),
          DetailRowData(
            label: 'Paid',
            value: _moneyFromPaise(booking.grossAmountPaise),
          ),
          DetailRowData(
            label: 'Status',
            value: '',
            trailing: StatusChip(
              label: record.statusLabel,
              tone: record.statusTone,
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildDeliveringRequest(
    BookingModel booking,
    BookingRecord record,
  ) {
    return [
      _BannerCard(
        backgroundColor: const Color(0xFFFEF3C7),
        text:
            'Respond within ${_formatRemainingUntil(booking.requestExpiresAt)} · Auto-cancels when the timer ends',
      ),
      ..._bookingPolicySections(booking),
      SectionBlock(
        title: 'PET PARENT',
        child: _IdentityRow(
          initials: _initials(booking.customerName),
          name: booking.customerName,
          handle: _handleFor(booking.customerUsername),
          avatarUrl: booking.customerPhotoUrl,
          initialsBackground: const Color(0xFFEFF6FF),
          initialsForeground: const Color(0xFF1D4ED8),
        ),
      ),
      const SizedBox(height: 12),
      SectionBlock(
        title: 'SERVICE REQUESTED',
        rows: [
          DetailRowData(label: 'Service', value: booking.serviceName),
          DetailRowData(
            label: 'Animal',
            value: _emptyFallback(booking.animalType),
          ),
          DetailRowData(
            label: 'Date',
            value: _dateLabel(booking.scheduledStartAt),
          ),
          DetailRowData(
            label: 'Time',
            value: _timeLabel(booking.scheduledStartAt),
          ),
          DetailRowData(
            label: 'Duration',
            value: '${booking.durationMinutes} min',
          ),
          DetailRowData(
            label: 'Status',
            value: '',
            trailing: StatusChip(
              label: record.statusLabel,
              tone: record.statusTone,
            ),
          ),
          DetailRowData(
            label: 'You earn',
            value: _moneyFromPaise(booking.providerEarningsPaise),
            valueColor: const Color(0xFF15803D),
            valueWeight: FontWeight.w700,
          ),
        ],
      ),
      const SizedBox(height: 12),
      _DualActionRow(
        primaryLabel: _activeRequestAction == 'accept'
            ? 'Accepting...'
            : 'Accept booking',
        primaryStyle: BookingActionStyle.primary,
        secondaryLabel: _activeRequestAction == 'reject'
            ? 'Rejecting...'
            : 'Reject',
        secondaryStyle: BookingActionStyle.danger,
        onPrimaryTap: _activeRequestAction == null
            ? () => _runRequestAction(bookingId: booking.id, accept: true)
            : null,
        onSecondaryTap: _activeRequestAction == null
            ? () => _runRequestAction(bookingId: booking.id, accept: false)
            : null,
      ),
      const SizedBox(height: 8),
      const Text(
        'If you do not respond before the timer ends, the booking request automatically expires.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.textGrey,
          fontSize: 11.5,
          height: 1.5,
        ),
      ),
    ];
  }

  List<Widget> _buildDeliveringConfirmed(
    BookingModel booking,
    BookingRecord record,
  ) {
    return [
      ..._bookingPolicySections(booking),
      SectionBlock(
        title: 'PET PARENT',
        child: _IdentityRow(
          initials: _initials(booking.customerName),
          name: booking.customerName,
          handle: _handleFor(booking.customerUsername),
          avatarUrl: booking.customerPhotoUrl,
          initialsBackground: const Color(0xFFFEF0EB),
          initialsForeground: const Color(0xFF9A3412),
        ),
      ),
      const SizedBox(height: 12),
      SectionBlock(
        title: 'SERVICE',
        rows: [
          DetailRowData(label: 'Service', value: booking.serviceName),
          DetailRowData(
            label: 'Animal',
            value: _emptyFallback(booking.animalType),
          ),
          DetailRowData(
            label: 'Date',
            value: _dateLabel(booking.scheduledStartAt),
          ),
          DetailRowData(
            label: 'Time',
            value: _timeLabel(booking.scheduledStartAt),
          ),
          DetailRowData(
            label: 'Duration',
            value: '${booking.durationMinutes} min',
          ),
          DetailRowData(
            label: 'Status',
            value: '',
            trailing: StatusChip(
              label: record.statusLabel,
              tone: record.statusTone,
            ),
          ),
          DetailRowData(
            label: 'You earn',
            value: _moneyFromPaise(booking.providerEarningsPaise),
            valueColor: const Color(0xFF15803D),
            valueWeight: FontWeight.w700,
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (booking.isInProgress)
        SectionBlock(
          title: 'SERVICE IN PROGRESS',
          child: _CompletionPanel(
            isLoading: _activeLifecycleAction == 'completeBooking',
            onComplete: () => _completeBooking(booking),
          ),
        )
      else
        SectionBlock(
          title: 'ENTER OTP TO START SERVICE',
          child: _ProviderOtpPanel(
            controllers: _otpControllers,
            booking: booking,
            isLoading: _activeLifecycleAction == 'verifyOtp',
            onVerify: () => _verifyOtpAndStart(booking),
          ),
        ),
      const SizedBox(height: 12),
      ..._postConfirmationActionSections(booking),
      if (!booking.isInProgress && !booking.isCompleted) ...[
        const SizedBox(height: 12),
        _DualActionRow(
          primaryLabel: _activeLifecycleAction == 'cancelBooking'
              ? 'Cancelling...'
              : 'Cancel booking',
          primaryStyle: BookingActionStyle.danger,
          secondaryLabel: 'Message',
          secondaryStyle: BookingActionStyle.secondary,
          onPrimaryTap:
              booking.canCancelBeforeStart && _activeLifecycleAction == null
              ? () => _cancelBooking(booking)
              : null,
          onSecondaryTap: () => _showToast('Messaging flow opened'),
        ),
      ],
    ];
  }

  Widget _buildGenericDetails(BookingModel booking, BookingRecord record) {
    final isDelivering = widget.contextMode == BookingContextMode.delivering;
    return Column(
      children: [
        ..._bookingPolicySections(booking),
        SectionBlock(
          title: 'BOOKING',
          rows: [
            DetailRowData(label: 'Service', value: booking.serviceName),
            DetailRowData(
              label: 'Animal',
              value: _emptyFallback(booking.animalType),
            ),
            DetailRowData(
              label: isDelivering ? 'Pet parent' : 'Provider',
              value: isDelivering ? booking.customerName : booking.providerName,
            ),
            DetailRowData(
              label: 'Date',
              value: _dateLabel(booking.scheduledStartAt),
            ),
            DetailRowData(
              label: 'Time',
              value: _timeLabel(booking.scheduledStartAt),
            ),
            DetailRowData(
              label: 'Duration',
              value: '${booking.durationMinutes} min',
            ),
            DetailRowData(
              label: 'Status',
              value: '',
              trailing: StatusChip(
                label: record.statusLabel,
                tone: record.statusTone,
              ),
            ),
            DetailRowData(
              label: 'Paid',
              value: _moneyFromPaise(booking.grossAmountPaise),
            ),
          ],
        ),
        if (booking.isPostConfirmation) ...[
          const SizedBox(height: 12),
          ..._postConfirmationActionSections(booking),
        ],
      ],
    );
  }

  List<Widget> _postConfirmationActionSections(BookingModel booking) {
    if (!booking.isPostConfirmation) return const [];

    final isCustomer = _isCustomer(booking);
    final isProvider = _isProvider(booking);

    return [
      FutureBuilder<BookingContactSnapshot>(
        future: _contactDetailsFor(booking, includeProviderPhone: isCustomer),
        builder: (context, snapshot) {
          final details = snapshot.data;
          final providerPhone = details?.providerPhone ?? booking.providerPhone;
          final maskedPhone = _maskPhone(providerPhone);
          final address = _emptyFallback(
            details?.displayAddress ?? booking.displayAddress,
            fallback: 'Location not available',
          );
          final latitude = details?.latitude ?? booking.latitude;
          final longitude = details?.longitude ?? booking.longitude;

          return Column(
            children: [
              SectionBlock(
                title: 'LOCATION',
                child: _BookingLocationAction(
                  address: address,
                  isLoading:
                      snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData,
                  onTap: () => _launchMaps(
                    address: address == 'Location not available' ? '' : address,
                    latitude: latitude,
                    longitude: longitude,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (isCustomer)
                SectionBlock(
                  title: 'PROVIDER CONTACT',
                  child: _CustomerProviderContact(
                    providerName: booking.providerName,
                    maskedPhone: maskedPhone.isEmpty
                        ? _emptyFallback(
                            booking.providerPhoneMasked,
                            fallback: 'Provider phone not available yet',
                          )
                        : maskedPhone,
                    canCall: providerPhone.trim().isNotEmpty,
                    isLoading:
                        snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData,
                    onCall: () => _launchPhoneDialer(providerPhone),
                    onMessage: () => _showToast('Messaging flow opened'),
                  ),
                )
              else if (isProvider)
                SectionBlock(
                  title: 'CONTACT',
                  child: _ProviderMessagingOnly(
                    customerName: booking.customerName,
                    onMessage: () => _showToast('Messaging flow opened'),
                  ),
                ),
            ],
          );
        },
      ),
    ];
  }

  String _dateLabel(DateTime? value) {
    if (value == null) return 'Not scheduled';
    final local = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(local.year, local.month, local.day);
    final difference = target.difference(today).inDays;
    if (difference == 0) return 'Today, ${local.day} ${_month(local.month)}';
    if (difference == 1) return 'Tomorrow, ${local.day} ${_month(local.month)}';
    return '${local.day} ${_month(local.month)} ${local.year}';
  }

  String _timeLabel(DateTime? value) {
    if (value == null) return 'Not selected';
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  String _moneyFromPaise(int paise) {
    final rupees = paise / 100;
    final text = paise % 100 == 0
        ? rupees.toStringAsFixed(0)
        : rupees.toStringAsFixed(2);
    return '₹$text';
  }

  String _emptyFallback(String value, {String fallback = 'Not available'}) {
    final text = value.trim();
    return text.isEmpty ? fallback : text;
  }

  String _handleFor(String username) {
    final text = username.trim();
    if (text.isEmpty) return '@pettxo_user';
    return text.startsWith('@') ? text : '@$text';
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'P';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }

  String _month(int month) {
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
    return months[(month - 1).clamp(0, 11)];
  }

  String _titleCase(String value) {
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}

class _BannerCard extends StatelessWidget {
  final Color backgroundColor;
  final String text;

  const _BannerCard({required this.backgroundColor, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 12.5,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DetailLoadingCard extends StatelessWidget {
  const _DetailLoadingCard();

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
            'Loading booking details...',
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

class _DetailStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _DetailStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
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
            textAlign: TextAlign.center,
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

class _OtpNotice extends StatelessWidget {
  final String text;

  const _OtpNotice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF0EB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDD5C4)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF9A3412),
          fontSize: 12.5,
          height: 1.45,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ReviewSubmittedState extends StatelessWidget {
  const _ReviewSubmittedState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x3315803D)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Color(0xFF15803D),
                child: Icon(Icons.check_rounded, color: Colors.white, size: 18),
              ),
              SizedBox(width: 10),
              Text(
                'Review Submitted',
                style: TextStyle(
                  color: Color(0xFF15803D),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            'Thanks for sharing your experience. Your review is now part of the provider profile.',
            style: TextStyle(
              color: Color(0xFF166534),
              fontSize: 12.5,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerOtpPanel extends StatelessWidget {
  final BookingModel booking;
  final String? generatedOtp;
  final bool isLoading;
  final String timeText;
  final VoidCallback? onGenerate;

  const _CustomerOtpPanel({
    required this.booking,
    required this.generatedOtp,
    required this.isLoading,
    required this.timeText,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    final otp = generatedOtp?.trim() ?? '';
    final canGenerate =
        onGenerate != null &&
        booking.isAccepted &&
        booking.isWithinServiceStartWindow;

    if (booking.isInProgress) {
      return const _OtpNotice(
        text: 'OTP verified. Your service has started with the provider.',
      );
    }

    if (booking.hasActiveOtp && otp.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OtpNotice(
            text:
                'An OTP is already active for this booking. Generate a new OTP only when you are with the provider.',
          ),
          const SizedBox(height: 12),
          GradientButton(
            label: isLoading ? 'Generating...' : 'Generate New OTP',
            onPressed: isLoading || !canGenerate ? null : onGenerate,
            size: AppButtonSize.compact,
          ),
        ],
      );
    }

    if (otp.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Share this OTP with the provider to start the service.',
            style: TextStyle(
              color: AppColors.textGrey,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: otp.characters.map((digit) {
              return Expanded(
                child: Container(
                  height: 48,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDD5C4)),
                  ),
                  child: Text(
                    digit,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Text(
            'Expires in $timeText',
            style: const TextStyle(
              color: Color(0xFF9A3412),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    final note = booking.isWithinServiceStartWindow
        ? 'Generate OTP when you are ready to start the service with the provider.'
        : 'OTP unlocks 1 hour before the scheduled start time.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OtpNotice(text: note),
        const SizedBox(height: 12),
        GradientButton(
          label: isLoading ? 'Generating...' : 'Generate OTP',
          onPressed: isLoading || !canGenerate ? null : onGenerate,
          size: AppButtonSize.compact,
        ),
      ],
    );
  }
}

class _ProviderOtpPanel extends StatelessWidget {
  final List<TextEditingController> controllers;
  final BookingModel booking;
  final bool isLoading;
  final VoidCallback onVerify;

  const _ProviderOtpPanel({
    required this.controllers,
    required this.booking,
    required this.isLoading,
    required this.onVerify,
  });

  @override
  Widget build(BuildContext context) {
    final otpReady = booking.hasActiveOtp;
    final helper = otpReady
        ? 'Ask the pet parent to share their 6-digit OTP.'
        : 'Waiting for the pet parent to generate an OTP from their booking screen.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          helper,
          style: const TextStyle(color: AppColors.textGrey, fontSize: 12.5),
        ),
        if (booking.normalizedOtpStatus == 'failed') ...[
          const SizedBox(height: 8),
          Text(
            'Last OTP attempt failed. Attempts: ${booking.otpAttempts}/${booking.otpMaxAttempts}',
            style: const TextStyle(
              color: Color(0xFFB91C1C),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: controllers.map((controller) {
            return Expanded(
              child: Container(
                height: 52,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x1A000000)),
                ),
                alignment: Alignment.center,
                child: TextField(
                  controller: controller,
                  enabled: otpReady && !isLoading,
                  maxLength: 1,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (value) {
                    if (value.isNotEmpty) {
                      FocusScope.of(context).nextFocus();
                    }
                  },
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    hintText: '-',
                  ),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        GradientButton(
          label: isLoading ? 'Verifying...' : 'Verify OTP & Start',
          onPressed: otpReady && !isLoading ? onVerify : null,
        ),
      ],
    );
  }
}

class _CompletionPanel extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onComplete;

  const _CompletionPanel({required this.isLoading, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _OtpNotice(
          text:
              'OTP is verified and the service is in progress. Complete it only after the service is finished.',
        ),
        const SizedBox(height: 12),
        GradientButton(
          label: isLoading ? 'Completing...' : 'Mark Service Complete',
          onPressed: isLoading ? null : onComplete,
        ),
      ],
    );
  }
}

class _BookingLocationAction extends StatelessWidget {
  final String address;
  final bool isLoading;
  final VoidCallback onTap;

  const _BookingLocationAction({
    required this.address,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFFD8C2)),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 17,
                backgroundColor: Color(0xFFFFE7DB),
                child: Icon(
                  Icons.location_on_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLoading ? 'Loading location...' : address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Tap to open in maps',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerProviderContact extends StatelessWidget {
  final String providerName;
  final String maskedPhone;
  final bool canCall;
  final bool isLoading;
  final VoidCallback onCall;
  final VoidCallback onMessage;

  const _CustomerProviderContact({
    required this.providerName,
    required this.maskedPhone,
    required this.canCall,
    required this.isLoading,
    required this.onCall,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const CircleAvatar(
              radius: 17,
              backgroundColor: Color(0xFFDCFCE7),
              child: Icon(
                Icons.call_rounded,
                size: 18,
                color: Color(0xFF15803D),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLoading ? 'Loading provider contact...' : maskedPhone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    canCall
                        ? 'Provider: $providerName'
                        : 'Use Pettxo chat for now',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textGrey,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DualActionRow(
          primaryLabel: 'Call',
          primaryStyle: BookingActionStyle.primary,
          secondaryLabel: 'Message',
          secondaryStyle: BookingActionStyle.secondary,
          onPrimaryTap: canCall && !isLoading ? onCall : null,
          onSecondaryTap: onMessage,
        ),
      ],
    );
  }
}

class _ProviderMessagingOnly extends StatelessWidget {
  final String customerName;
  final VoidCallback onMessage;

  const _ProviderMessagingOnly({
    required this.customerName,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Phone number is hidden for providers. Message $customerName from Pettxo for booking coordination.',
          style: const TextStyle(
            color: AppColors.textGrey,
            fontSize: 12.5,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        GradientButton(
          label: 'Message',
          onPressed: onMessage,
          size: AppButtonSize.compact,
        ),
      ],
    );
  }
}

class _IdentityRow extends StatelessWidget {
  final String initials;
  final String name;
  final String handle;
  final String avatarUrl;
  final Color initialsBackground;
  final Color initialsForeground;

  const _IdentityRow({
    required this.initials,
    required this.name,
    required this.handle,
    this.avatarUrl = '',
    required this.initialsBackground,
    required this.initialsForeground,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: initialsBackground,
          backgroundImage: avatarUrl.trim().isEmpty
              ? null
              : NetworkImage(avatarUrl.trim()),
          child: avatarUrl.trim().isNotEmpty
              ? null
              : Text(
                  initials,
                  style: TextStyle(
                    color: initialsForeground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              Text(
                handle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DualActionRow extends StatelessWidget {
  final String primaryLabel;
  final BookingActionStyle primaryStyle;
  final VoidCallback? onPrimaryTap;
  final String secondaryLabel;
  final BookingActionStyle secondaryStyle;
  final VoidCallback? onSecondaryTap;

  const _DualActionRow({
    required this.primaryLabel,
    required this.primaryStyle,
    required this.onPrimaryTap,
    required this.secondaryLabel,
    required this.secondaryStyle,
    this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _DetailActionButton(
            label: primaryLabel,
            styleKind: primaryStyle,
            onTap: onPrimaryTap,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _DetailActionButton(
            label: secondaryLabel,
            styleKind: secondaryStyle,
            onTap: onSecondaryTap,
          ),
        ),
      ],
    );
  }
}

class _DetailActionButton extends StatelessWidget {
  final String label;
  final BookingActionStyle styleKind;
  final VoidCallback? onTap;

  const _DetailActionButton({
    required this.label,
    required this.styleKind,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (styleKind == BookingActionStyle.primary) {
      return GradientButton(label: label, onPressed: onTap);
    }

    return SecondaryButton(label: label, onPressed: onTap);
  }
}
