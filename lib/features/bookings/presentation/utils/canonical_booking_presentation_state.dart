import '../../domain/models/booking_document_v3.dart';
import '../../domain/models/booking_v3_models.dart';

const Duration _canonicalNoShowDisputeWindow = Duration(hours: 24);

enum CanonicalBookingDisputeDisplayState { none, open, resolved }

CanonicalBookingStateV3 effectiveCanonicalBookingPresentationState(
  CanonicalBookingDocumentV3 booking,
) {
  return effectiveCanonicalBookingPresentationStateFromRaw(
    booking.state,
    booking.lifecycle.payDeadlineAt,
    bookingType: booking.bookingType,
    slotSchedule: booking.schedule is CanonicalSlotBookingScheduleV3
        ? booking.schedule as CanonicalSlotBookingScheduleV3
        : null,
    rangeCheckOutDateTime: booking.schedule is CanonicalRangeBookingScheduleV3
        ? (booking.schedule as CanonicalRangeBookingScheduleV3).checkOutDateTime
        : null,
    otpEnteredAt: booking.lifecycle.otpEnteredAt,
    paymentStatus: booking.payment.status,
    paidAt: booking.lifecycle.paidAt,
    disputeStatus: booking.dispute.status,
  );
}

CanonicalBookingStateV3 effectiveCanonicalBookingPresentationStateFromRaw(
  CanonicalBookingStateV3 state,
  DateTime? payDeadlineAt, {
  BookingV3Type? bookingType,
  CanonicalSlotBookingScheduleV3? slotSchedule,
  DateTime? rangeCheckOutDateTime,
  DateTime? otpEnteredAt,
  String? paymentStatus,
  DateTime? paidAt,
  String? disputeStatus,
  DateTime? now,
}) {
  final currentNow = now ?? DateTime.now();
  if (state == CanonicalBookingStateV3.acceptedAwaitingPayment &&
      payDeadlineAt != null &&
      !payDeadlineAt.isAfter(currentNow)) {
    return CanonicalBookingStateV3.paymentExpired;
  }
  final noShowDeadlineAt = canonicalBookingNoShowDeadlineFromRaw(
    bookingType: bookingType,
    slotSchedule: slotSchedule,
    rangeCheckOutDateTime: rangeCheckOutDateTime,
  );
  final paymentIsConfirmed =
      paidAt != null || _hasConfirmedPaymentStatus(paymentStatus);
  if (state == CanonicalBookingStateV3.confirmed &&
      paymentIsConfirmed &&
      otpEnteredAt == null &&
      noShowDeadlineAt != null &&
      !noShowDeadlineAt.isAfter(currentNow)) {
    return CanonicalBookingStateV3.noShow;
  }
  final completionAvailableAt = canonicalBookingCompletionAvailableAtFromRaw(
    bookingType: bookingType,
    slotSchedule: slotSchedule,
    rangeCheckOutDateTime: rangeCheckOutDateTime,
  );
  if (state == CanonicalBookingStateV3.inProgress &&
      completionAvailableAt != null &&
      !completionAvailableAt.isAfter(currentNow)) {
    if (otpEnteredAt != null) {
      return CanonicalBookingStateV3.completedPendingReview;
    }
    if (paymentIsConfirmed) {
      return CanonicalBookingStateV3.noShow;
    }
  }
  if (_isCompletedCanonicalBookingState(state) &&
      disputeStatus?.trim().toLowerCase() == 'open') {
    return CanonicalBookingStateV3.disputed;
  }
  return state;
}

CanonicalBookingDisputeDisplayState canonicalBookingDisputeDisplayState(
  CanonicalBookingDocumentV3 booking,
) {
  if (!_isCompletedCanonicalBookingState(booking.state)) {
    return CanonicalBookingDisputeDisplayState.none;
  }
  final disputeStatus = booking.dispute.status.trim().toLowerCase();
  if (disputeStatus == 'open') {
    return CanonicalBookingDisputeDisplayState.open;
  }
  if (disputeStatus == 'resolved') {
    return CanonicalBookingDisputeDisplayState.resolved;
  }
  return CanonicalBookingDisputeDisplayState.none;
}

bool _isCompletedCanonicalBookingState(CanonicalBookingStateV3 state) {
  return state == CanonicalBookingStateV3.completedPendingReview ||
      state == CanonicalBookingStateV3.completedFinal;
}

DateTime? canonicalBookingAuthoritativeServiceWindowEnd(
  CanonicalBookingDocumentV3 booking,
) {
  return canonicalBookingCompletionAvailableAtFromRaw(
    bookingType: booking.bookingType,
    slotSchedule: booking.schedule is CanonicalSlotBookingScheduleV3
        ? booking.schedule as CanonicalSlotBookingScheduleV3
        : null,
    rangeCheckOutDateTime: booking.schedule is CanonicalRangeBookingScheduleV3
        ? (booking.schedule as CanonicalRangeBookingScheduleV3).checkOutDateTime
        : null,
  );
}

DateTime? canonicalBookingNoShowDeadline(CanonicalBookingDocumentV3 booking) {
  return canonicalBookingNoShowDeadlineFromRaw(
    bookingType: booking.bookingType,
    slotSchedule: booking.schedule is CanonicalSlotBookingScheduleV3
        ? booking.schedule as CanonicalSlotBookingScheduleV3
        : null,
    rangeCheckOutDateTime: booking.schedule is CanonicalRangeBookingScheduleV3
        ? (booking.schedule as CanonicalRangeBookingScheduleV3).checkOutDateTime
        : null,
  );
}

DateTime? canonicalBookingNoShowDeadlineFromRaw({
  BookingV3Type? bookingType,
  CanonicalSlotBookingScheduleV3? slotSchedule,
  DateTime? rangeCheckOutDateTime,
}) {
  if (bookingType == BookingV3Type.range) {
    return rangeCheckOutDateTime;
  }
  final schedule = slotSchedule;
  if (schedule == null) return null;
  if (schedule.firstSegmentEndAt != null) return schedule.firstSegmentEndAt;
  final firstSegment =
      (schedule.segments ?? const <CanonicalBookingScheduleSegmentV3>[])
          .where((segment) => segment.endAt.isAfter(segment.startAt))
          .toList(growable: false);
  if (firstSegment.isNotEmpty) {
    return firstSegment.first.endAt;
  }
  return schedule.scheduledEndAt;
}

DateTime? canonicalBookingCompletionAvailableAt(
  CanonicalBookingDocumentV3 booking,
) {
  return canonicalBookingCompletionAvailableAtFromRaw(
    bookingType: booking.bookingType,
    slotSchedule: booking.schedule is CanonicalSlotBookingScheduleV3
        ? booking.schedule as CanonicalSlotBookingScheduleV3
        : null,
    rangeCheckOutDateTime: booking.schedule is CanonicalRangeBookingScheduleV3
        ? (booking.schedule as CanonicalRangeBookingScheduleV3).checkOutDateTime
        : null,
  );
}

DateTime? canonicalBookingCompletionAvailableAtFromRaw({
  BookingV3Type? bookingType,
  CanonicalSlotBookingScheduleV3? slotSchedule,
  DateTime? rangeCheckOutDateTime,
}) {
  if (bookingType == BookingV3Type.range) {
    return rangeCheckOutDateTime;
  }
  final schedule = slotSchedule;
  if (schedule == null) return null;
  if (schedule.finalEndAt != null) return schedule.finalEndAt;
  final segments =
      (schedule.segments ?? const <CanonicalBookingScheduleSegmentV3>[])
          .where((segment) => segment.endAt.isAfter(segment.startAt))
          .toList(growable: false);
  if (segments.isNotEmpty) {
    return segments.last.endAt;
  }
  return schedule.scheduledEndAt;
}

DateTime? effectiveCanonicalNoShowDisputeDeadline(
  CanonicalBookingDocumentV3 booking,
) {
  final persistedDeadline = booking.lifecycle.disputeDeadlineAt;
  if (persistedDeadline != null) return persistedDeadline;
  final effectiveState = effectiveCanonicalBookingPresentationState(booking);
  if (effectiveState != CanonicalBookingStateV3.noShow) {
    return null;
  }
  final anchor = effectiveCanonicalNoShowTimestamp(booking);
  return anchor?.add(_canonicalNoShowDisputeWindow);
}

DateTime? effectiveCanonicalNoShowTimestamp(
  CanonicalBookingDocumentV3 booking,
) {
  final persistedNoShowAt = booking.lifecycle.noShowAt;
  if (persistedNoShowAt != null) return persistedNoShowAt;
  final effectiveState = effectiveCanonicalBookingPresentationState(booking);
  if (effectiveState != CanonicalBookingStateV3.noShow) {
    return null;
  }
  return canonicalBookingNoShowDeadline(booking);
}

bool hasActiveCanonicalPaymentWindow(DateTime? payDeadlineAt) {
  return payDeadlineAt == null || payDeadlineAt.isAfter(DateTime.now());
}

bool hasCanonicalConfirmedPaymentLifecycle(CanonicalBookingDocumentV3 booking) {
  return booking.lifecycle.paidAt != null &&
      booking.privacy.contactUnlockedAt != null;
}

bool canProviderViewCustomerIdentity(CanonicalBookingDocumentV3 booking) {
  return hasCanonicalConfirmedPaymentLifecycle(booking);
}

bool _hasConfirmedPaymentStatus(String? paymentStatus) {
  final normalized = paymentStatus?.trim().toLowerCase() ?? '';
  return normalized == 'paid' || normalized == 'confirmed';
}
