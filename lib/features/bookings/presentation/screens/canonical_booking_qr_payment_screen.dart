import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../data/repositories/booking_repository.dart';
import '../../domain/models/booking_document_v3.dart';
import '../../domain/models/booking_payment_order.dart';
import '../../domain/models/booking_read_model.dart';
import '../../domain/models/booking_v3_models.dart';
import '../widgets/booking_deadline_countdown.dart';
import 'booking_confirmation_screen.dart';

class CanonicalBookingQrPaymentScreen extends StatefulWidget {
  final String bookingId;
  final CanonicalQrPaymentResult qrPayment;
  final BookingRepository? bookingRepository;
  final Widget Function(String bookingId)? confirmationScreenBuilder;

  const CanonicalBookingQrPaymentScreen({
    super.key,
    required this.bookingId,
    required this.qrPayment,
    this.bookingRepository,
    this.confirmationScreenBuilder,
  });

  @override
  State<CanonicalBookingQrPaymentScreen> createState() =>
      _CanonicalBookingQrPaymentScreenState();
}

class _CanonicalBookingQrPaymentScreenState
    extends State<CanonicalBookingQrPaymentScreen> {
  StreamSubscription<BookingReadModel?>? _confirmationSubscription;
  StreamSubscription<CanonicalPaymentAttemptReadModel?>? _attemptSubscription;
  Timer? _ticker;
  CanonicalPaymentAttemptReadModel? _latestAttempt;
  bool _hasNavigatedToConfirmation = false;
  bool _hasImageError = false;

  BookingRepository get _bookingRepository =>
      widget.bookingRepository ?? BookingRepository();

  @override
  void initState() {
    super.initState();
    _bindConfirmationStream();
    _bindAttemptStream(widget.qrPayment.paymentAttemptId);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _attemptSubscription?.cancel();
    _confirmationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(92),
        child: _QrGlassTopBar(title: 'Pay using QR'),
      ),
      body: StreamBuilder<BookingReadModel?>(
        stream: _bookingRepository.watchCanonicalBooking(widget.bookingId),
        builder: (context, snapshot) {
          final booking = _canonicalBookingFromReadModel(snapshot.data);
          final effectiveExpiry = _effectiveExpiry(booking);
          final isExpired =
              effectiveExpiry != null &&
              !effectiveExpiry.isAfter(DateTime.now());
          final hasRefundState =
              _latestAttempt?.state ==
                  CanonicalPaymentAttemptState.refundRequired ||
              _latestAttempt?.state ==
                  CanonicalPaymentAttemptState.refundPending;
          final hasReconciliationState =
              _latestAttempt?.state ==
              CanonicalPaymentAttemptState.capturedRequiresReconciliation;
          final isCancelled =
              booking != null && _isCancelledState(booking.state);
          final canSwitchMethod =
              !hasRefundState && !hasReconciliationState && !isCancelled;

          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: [
                _QrHeaderCard(
                  amountLabel: _formatMoney(widget.qrPayment.amountPaise),
                  instruction:
                      'Scan this QR from another phone using Google Pay, PhonePe, Paytm, BHIM or any supported UPI app.',
                ),
                const SizedBox(height: 16),
                _QrImageCard(
                  imageUrl: widget.qrPayment.imageUrl,
                  hasImageError: _hasImageError,
                  onImageError: () {
                    if (_hasImageError || !mounted) return;
                    setState(() => _hasImageError = true);
                  },
                ),
                const SizedBox(height: 16),
                _QrStatusCard(
                  headline: _statusHeadline(
                    booking: booking,
                    attempt: _latestAttempt,
                    isExpired: isExpired,
                  ),
                  body: _statusBody(
                    booking: booking,
                    attempt: _latestAttempt,
                    isExpired: isExpired,
                  ),
                  deadline: !isExpired ? effectiveExpiry : null,
                ),
                const SizedBox(height: 18),
                SecondaryButton(
                  label: 'Use another payment method',
                  onPressed: canSwitchMethod
                      ? () => Navigator.of(context).maybePop()
                      : null,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  CanonicalBookingDocumentV3? _canonicalBookingFromReadModel(
    BookingReadModel? readModel,
  ) {
    if (readModel is CanonicalBookingReadModel) {
      return readModel.booking;
    }
    return null;
  }

  void _bindConfirmationStream() {
    _confirmationSubscription?.cancel();
    _confirmationSubscription = _bookingRepository
        .watchCanonicalBookingConfirmation(widget.bookingId)
        .listen((booking) {
          if (!mounted || booking == null || _hasNavigatedToConfirmation) {
            return;
          }
          _hasNavigatedToConfirmation = true;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) =>
                  widget.confirmationScreenBuilder?.call(widget.bookingId) ??
                  BookingConfirmationScreen(bookingId: widget.bookingId),
            ),
          );
        });
  }

  void _bindAttemptStream(String paymentAttemptId) {
    final safeAttemptId = paymentAttemptId.trim();
    if (safeAttemptId.isEmpty) return;
    _attemptSubscription?.cancel();
    _attemptSubscription = _bookingRepository
        .watchPaymentAttempt(
          bookingId: widget.bookingId,
          paymentAttemptId: safeAttemptId,
        )
        .listen((attempt) {
          if (!mounted) return;
          setState(() {
            _latestAttempt = attempt;
          });
        });
  }

  DateTime? _effectiveExpiry(CanonicalBookingDocumentV3? booking) {
    final bookingDeadline = booking?.lifecycle.payDeadlineAt;
    final qrExpiry = widget.qrPayment.expiresAt;
    if (bookingDeadline == null) return qrExpiry;
    if (qrExpiry == null) return bookingDeadline;
    return qrExpiry.isBefore(bookingDeadline) ? qrExpiry : bookingDeadline;
  }

  String _statusHeadline({
    required CanonicalBookingDocumentV3? booking,
    required CanonicalPaymentAttemptReadModel? attempt,
    required bool isExpired,
  }) {
    if (booking?.state == CanonicalBookingStateV3.confirmed) {
      return 'Payment confirmed';
    }
    if (attempt != null) {
      return switch (attempt.state) {
        CanonicalPaymentAttemptState.refundRequired ||
        CanonicalPaymentAttemptState.refundPending =>
          'Payment under refund review',
        CanonicalPaymentAttemptState.capturedRequiresReconciliation =>
          'Verifying payment',
        CanonicalPaymentAttemptState.expired => 'QR payment expired',
        CanonicalPaymentAttemptState.failed => 'Payment could not be completed',
        CanonicalPaymentAttemptState.confirmed => 'Payment confirmed',
        _ => 'Waiting for payment…',
      };
    }
    if (booking != null && _isCancelledState(booking.state)) {
      return 'Booking cancelled';
    }
    if (isExpired || booking?.state == CanonicalBookingStateV3.paymentExpired) {
      return 'QR payment expired';
    }
    return 'Waiting for payment…';
  }

  String _statusBody({
    required CanonicalBookingDocumentV3? booking,
    required CanonicalPaymentAttemptReadModel? attempt,
    required bool isExpired,
  }) {
    if (booking?.state == CanonicalBookingStateV3.confirmed) {
      return 'Your payment was received and the booking is now confirmed.';
    }
    if (attempt != null) {
      return switch (attempt.state) {
        CanonicalPaymentAttemptState.capturedRequiresReconciliation =>
          'We\'re verifying your payment. Please don\'t make another payment for this booking.',
        CanonicalPaymentAttemptState.refundRequired =>
          'A duplicate or conflicting payment is being handled safely. Please do not pay again.',
        CanonicalPaymentAttemptState.refundPending =>
          'Your payment is being processed for refund safely. Please do not pay again.',
        CanonicalPaymentAttemptState.expired =>
          'This QR code is no longer active because the payment window ended.',
        CanonicalPaymentAttemptState.failed =>
          attempt.failureMessage.isNotEmpty
              ? attempt.failureMessage
              : 'This payment attempt could not be completed.',
        CanonicalPaymentAttemptState.confirmed =>
          'Your payment is confirmed and the booking is syncing.',
        _ => 'Complete the payment in any UPI app after scanning this QR code.',
      };
    }
    if (booking != null && _isCancelledState(booking.state)) {
      return 'This booking is no longer payable because it was cancelled.';
    }
    if (isExpired || booking?.state == CanonicalBookingStateV3.paymentExpired) {
      return 'This QR code expired when the booking payment window ended.';
    }
    return 'Waiting for the backend to confirm payment after you scan this QR.';
  }

  bool _isCancelledState(CanonicalBookingStateV3 state) {
    switch (state) {
      case CanonicalBookingStateV3.cancelled:
      case CanonicalBookingStateV3.cancelledByParent:
      case CanonicalBookingStateV3.declined:
      case CanonicalBookingStateV3.expired:
      case CanonicalBookingStateV3.paymentExpired:
        return true;
      default:
        return false;
    }
  }

  String _formatMoney(int paise) {
    final rupees = paise / 100;
    return '₹${rupees.toStringAsFixed(2)}';
  }
}

class _QrGlassTopBar extends StatelessWidget {
  const _QrGlassTopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.45),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(18),
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
                        fontSize: 22,
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

class _QrHeaderCard extends StatelessWidget {
  const _QrHeaderCard({required this.amountLabel, required this.instruction});

  final String amountLabel;
  final String instruction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pay $amountLabel',
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Scan this QR using any UPI app',
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            instruction,
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

class _QrImageCard extends StatelessWidget {
  const _QrImageCard({
    required this.imageUrl,
    required this.hasImageError,
    required this.onImageError,
  });

  final String imageUrl;
  final bool hasImageError;
  final VoidCallback onImageError;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F4EF),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: hasImageError || imageUrl.trim().isEmpty
                    ? const _QrImageErrorState()
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            onImageError();
                          });
                          return const _QrImageErrorState();
                        },
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QrImageErrorState extends StatelessWidget {
  const _QrImageErrorState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.qr_code_2_rounded, size: 56, color: AppColors.textGrey),
            SizedBox(height: 14),
            Text(
              'We couldn\'t load the QR image right now.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textDark,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Go back and try creating the QR again while the payment window remains open.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textGrey,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrStatusCard extends StatelessWidget {
  const _QrStatusCard({
    required this.headline,
    required this.body,
    required this.deadline,
  });

  final String headline;
  final String body;
  final DateTime? deadline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: AppColors.textGrey,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (deadline != null) ...[
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 18),
            BookingDeadlineCountdown(
              deadline: deadline,
              label: 'Waiting for payment…',
              valueFontSize: 24,
            ),
          ],
        ],
      ),
    );
  }
}
