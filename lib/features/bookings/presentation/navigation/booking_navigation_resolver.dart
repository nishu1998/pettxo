import 'package:flutter/material.dart';

import '../../../../core/widgets/app_snackbar.dart';
import '../../data/repositories/booking_repository.dart';
import '../../domain/models/booking_document_v3.dart';
import '../../domain/models/booking_flow_models.dart';
import '../../domain/models/booking_payment_order.dart';
import '../../domain/models/booking_read_model.dart';
import '../../domain/models/booking_v3_models.dart';
import '../../domain/models/canonical_booking_request_models.dart';
import '../../domain/models/canonical_provider_booking_request_view.dart';
import '../screens/canonical_booking_detail_screen.dart';
import '../screens/canonical_booking_payment_screen.dart';
import '../screens/canonical_booking_request_status_screen.dart';
import '../screens/canonical_provider_booking_request_detail_screen.dart';
import '../utils/canonical_booking_presentation_state.dart';

enum BookingNavigationTarget {
  canonicalRequestStatus,
  canonicalPayment,
  canonicalBookingDetail,
  canonicalProviderRequestDetail,
}

class BookingOpenRequest {
  const BookingOpenRequest({required this.bookingId, this.fallbackContextMode});

  final String bookingId;
  final BookingContextMode? fallbackContextMode;
}

class BookingNavigationPlan {
  const BookingNavigationPlan({
    required this.target,
    required this.contextMode,
    this.paymentAttempt,
  });

  final BookingNavigationTarget target;
  final BookingContextMode contextMode;
  final CanonicalPaymentAttemptReadModel? paymentAttempt;
}

class BookingNavigationResolver {
  BookingNavigationResolver({
    BookingRepository? repository,
    Future<BookingReadModel?> Function(String bookingId)? bookingLoader,
    Future<CanonicalPaymentAttemptReadModel?> Function({
      required String bookingId,
      required String paymentAttemptId,
    })?
    paymentAttemptLoader,
  }) : _repository = repository,
       _bookingLoader = bookingLoader,
       _paymentAttemptLoader = paymentAttemptLoader;

  final BookingRepository? _repository;
  final Future<BookingReadModel?> Function(String bookingId)? _bookingLoader;
  final Future<CanonicalPaymentAttemptReadModel?> Function({
    required String bookingId,
    required String paymentAttemptId,
  })?
  _paymentAttemptLoader;

  BookingRepository get _readRepository => _repository ?? BookingRepository();

  static BookingOpenRequest openRequestForRecord(BookingRecord booking) {
    return BookingOpenRequest(
      bookingId: booking.id,
      fallbackContextMode: booking.context,
    );
  }

  static BookingOpenRequest openRequestForExternalBooking({
    required String bookingId,
    required BookingContextMode contextMode,
  }) {
    return BookingOpenRequest(
      bookingId: bookingId,
      fallbackContextMode: contextMode,
    );
  }

  Future<void> openBookingRequest(
    BuildContext context,
    BookingOpenRequest request,
  ) {
    return openBookingDetails(
      context,
      bookingId: request.bookingId,
      fallbackContextMode: request.fallbackContextMode,
    );
  }

  Future<void> openBookingDetails(
    BuildContext context, {
    required String bookingId,
    BookingContextMode? fallbackContextMode,
  }) async {
    final booking =
        await _bookingLoader?.call(bookingId) ??
        await _readRepository.fetchBookingReadModel(bookingId);
    if (!context.mounted) return;
    if (booking == null) {
      AppSnackbar.showWarning(context, 'This booking is no longer available.');
      return;
    }

    await openBookingReadModel(
      context,
      booking: booking,
      fallbackContextMode: fallbackContextMode,
    );
  }

  Future<void> openBookingReadModel(
    BuildContext context, {
    required BookingReadModel booking,
    BookingContextMode? fallbackContextMode,
  }) async {
    BookingNavigationPlan plan;
    try {
      plan = await resolvePlan(
        booking: booking,
        fallbackContextMode: fallbackContextMode,
      );
    } on StateError {
      if (context.mounted) {
        AppSnackbar.showWarning(
          context,
          'This booking uses a retired flow and can no longer be opened.',
        );
      }
      return;
    }
    if (!context.mounted) return;

    if (booking is CanonicalBookingReadModel) {
      final route = MaterialPageRoute(
        builder: (_) =>
            _buildCanonicalDestination(plan: plan, booking: booking),
      );
      await Navigator.push(context, route);
      return;
    }

    AppSnackbar.showError(context, 'We could not open this booking right now.');
  }

  Future<BookingNavigationPlan> resolvePlan({
    required BookingReadModel booking,
    BookingContextMode? fallbackContextMode,
  }) async {
    if (booking is! CanonicalBookingReadModel) {
      throw StateError('Legacy bookings are no longer supported.');
    }

    final canonical = booking.booking;
    final contextMode =
        fallbackContextMode ??
        _inferContextMode(canonical.providerId, canonical.parentId);
    if (_isCanonicalConfirmedOrLaterState(canonical.state)) {
      return BookingNavigationPlan(
        target: BookingNavigationTarget.canonicalBookingDetail,
        contextMode: contextMode,
      );
    }

    CanonicalPaymentAttemptReadModel? paymentAttempt;
    final paymentAttemptId = canonical.payment.paymentAttemptId.trim();
    if (paymentAttemptId.isNotEmpty) {
      paymentAttempt =
          await _paymentAttemptLoader?.call(
            bookingId: booking.bookingId,
            paymentAttemptId: paymentAttemptId,
          ) ??
          await _readRepository.fetchCanonicalPaymentAttempt(
            bookingId: booking.bookingId,
            paymentAttemptId: paymentAttemptId,
          );
    }

    return resolveCanonicalPlan(
      booking: canonical,
      contextMode: contextMode,
      paymentAttempt: paymentAttempt,
    );
  }

  static BookingNavigationPlan resolveCanonicalPlan({
    required CanonicalBookingDocumentV3 booking,
    required BookingContextMode contextMode,
    CanonicalPaymentAttemptReadModel? paymentAttempt,
  }) {
    final effectiveState = effectiveCanonicalBookingPresentationState(booking);
    if (_isCanonicalConfirmedOrLaterState(effectiveState)) {
      return BookingNavigationPlan(
        target: BookingNavigationTarget.canonicalBookingDetail,
        contextMode: contextMode,
        paymentAttempt: paymentAttempt,
      );
    }

    if (_isCanonicalTerminalRequestState(effectiveState)) {
      return BookingNavigationPlan(
        target: contextMode == BookingContextMode.delivering
            ? BookingNavigationTarget.canonicalProviderRequestDetail
            : BookingNavigationTarget.canonicalRequestStatus,
        contextMode: contextMode,
        paymentAttempt: paymentAttempt,
      );
    }

    if (contextMode == BookingContextMode.delivering) {
      return BookingNavigationPlan(
        target: BookingNavigationTarget.canonicalProviderRequestDetail,
        contextMode: contextMode,
        paymentAttempt: paymentAttempt,
      );
    }

    if (_shouldOpenCanonicalPayment(booking, paymentAttempt)) {
      return BookingNavigationPlan(
        target: BookingNavigationTarget.canonicalPayment,
        contextMode: contextMode,
        paymentAttempt: paymentAttempt,
      );
    }

    return BookingNavigationPlan(
      target: BookingNavigationTarget.canonicalRequestStatus,
      contextMode: contextMode,
      paymentAttempt: paymentAttempt,
    );
  }

  Widget _buildCanonicalDestination({
    required BookingNavigationPlan plan,
    required CanonicalBookingReadModel booking,
  }) {
    final canonical = booking.booking;
    switch (plan.target) {
      case BookingNavigationTarget.canonicalBookingDetail:
        return CanonicalBookingDetailScreen(bookingId: booking.bookingId);
      case BookingNavigationTarget.canonicalProviderRequestDetail:
        return CanonicalProviderBookingRequestDetailScreen(
          initialRequest: CanonicalProviderBookingRequestView.fromBooking(
            booking.bookingId,
            canonical,
          ),
        );
      case BookingNavigationTarget.canonicalPayment:
        return CanonicalBookingPaymentScreen(
          bookingId: booking.bookingId,
          serviceName: canonical.service.serviceTitle,
          providerName: canonical.participants.provider.displayName,
          serviceImageUrl: '',
        );
      case BookingNavigationTarget.canonicalRequestStatus:
        return CanonicalBookingRequestStatusScreen(
          bookingId: booking.bookingId,
          initialResult: _requestResultFromBooking(
            booking.bookingId,
            canonical,
          ),
          serviceName: canonical.service.serviceTitle,
          providerName: canonical.participants.provider.displayName,
          serviceImageUrl: '',
        );
    }
  }

  BookingContextMode _inferContextMode(String providerId, String parentId) {
    // The caller should usually provide a role-aware fallback; this default
    // keeps customer entry points safe when role metadata is unavailable.
    if (providerId.trim().isNotEmpty && parentId.trim().isEmpty) {
      return BookingContextMode.delivering;
    }
    return BookingContextMode.receiving;
  }

  static bool _isCanonicalConfirmedOrLaterState(CanonicalBookingStateV3 state) {
    switch (state) {
      case CanonicalBookingStateV3.confirmed:
      case CanonicalBookingStateV3.inProgress:
      case CanonicalBookingStateV3.completedPendingReview:
      case CanonicalBookingStateV3.completedFinal:
      case CanonicalBookingStateV3.disputed:
      case CanonicalBookingStateV3.noShow:
        return true;
      default:
        return false;
    }
  }

  static bool _shouldOpenCanonicalPayment(
    CanonicalBookingDocumentV3 booking,
    CanonicalPaymentAttemptReadModel? paymentAttempt,
  ) {
    final effectiveState = effectiveCanonicalBookingPresentationState(booking);
    if (effectiveState != CanonicalBookingStateV3.acceptedAwaitingPayment) {
      return false;
    }

    if (booking.state == CanonicalBookingStateV3.acceptedAwaitingPayment &&
        _hasActivePaymentWindow(booking)) {
      return true;
    }

    if (paymentAttempt == null) {
      return false;
    }

    switch (paymentAttempt.state) {
      case CanonicalPaymentAttemptState.orderCreated:
      case CanonicalPaymentAttemptState.checkoutOpened:
      case CanonicalPaymentAttemptState.captureReported:
      case CanonicalPaymentAttemptState.confirming:
      case CanonicalPaymentAttemptState.capturedRequiresReconciliation:
      case CanonicalPaymentAttemptState.failed:
      case CanonicalPaymentAttemptState.refundRequired:
      case CanonicalPaymentAttemptState.refundPending:
      case CanonicalPaymentAttemptState.refunded:
        return true;
      case CanonicalPaymentAttemptState.expired:
        return booking.state ==
                CanonicalBookingStateV3.acceptedAwaitingPayment &&
            _hasActivePaymentWindow(booking);
      case CanonicalPaymentAttemptState.notStarted:
      case CanonicalPaymentAttemptState.orderCreating:
      case CanonicalPaymentAttemptState.confirmed:
      case CanonicalPaymentAttemptState.unknown:
        return false;
    }
  }

  static bool _isCanonicalTerminalRequestState(CanonicalBookingStateV3 state) {
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

  static bool _hasActivePaymentWindow(CanonicalBookingDocumentV3 booking) {
    final deadline = booking.lifecycle.payDeadlineAt;
    return deadline == null || deadline.isAfter(DateTime.now());
  }

  CanonicalBookingRequestResult _requestResultFromBooking(
    String bookingId,
    CanonicalBookingDocumentV3 booking,
  ) {
    return CanonicalBookingRequestResult(
      bookingId: bookingId,
      source: 'canonical_v3',
      schemaVersion: booking.schemaVersion,
      bookingModelVersion: booking.bookingModelVersion,
      state: effectiveCanonicalBookingPresentationState(booking),
      bookingType: booking.bookingType == BookingV3Type.slot
          ? BookingV3Type.slot
          : BookingV3Type.range,
      requestedAt: booking.lifecycle.requestedAt,
      timerStartsAt: booking.lifecycle.timerStartsAt,
      acceptDeadlineAt: booking.lifecycle.acceptDeadlineAt,
      wasQueuedOutsideWorkingHours:
          booking.lifecycle.wasQueuedOutsideWorkingHours,
      idempotentReplay: false,
    );
  }
}
