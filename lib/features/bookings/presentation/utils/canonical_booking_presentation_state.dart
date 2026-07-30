import '../../domain/models/booking_document_v3.dart';
import '../../domain/models/booking_v3_models.dart';

const Duration _canonicalNoShowDisputeWindow = Duration(hours: 24);

CanonicalBookingStateV3 effectiveCanonicalBookingPresentationState(
  CanonicalBookingDocumentV3 booking,
) {
  return effectiveCanonicalBookingPresentationStateFromRaw(
    booking.state,
    booking.lifecycle.payDeadlineAt,
    bookingType: booking.bookingType,
    slotScheduledEndAt: booking.schedule is CanonicalSlotBookingScheduleV3
        ? (booking.schedule as CanonicalSlotBookingScheduleV3).scheduledEndAt
        : null,
    rangeCheckOutDateTime: booking.schedule is CanonicalRangeBookingScheduleV3
        ? (booking.schedule as CanonicalRangeBookingScheduleV3).checkOutDateTime
        : null,
    otpEnteredAt: booking.lifecycle.otpEnteredAt,
    paymentStatus: booking.payment.status,
    paidAt: booking.lifecycle.paidAt,
  );
}

CanonicalBookingStateV3 effectiveCanonicalBookingPresentationStateFromRaw(
  CanonicalBookingStateV3 state,
  DateTime? payDeadlineAt, {
  BookingV3Type? bookingType,
  DateTime? slotScheduledEndAt,
  DateTime? rangeCheckOutDateTime,
  DateTime? otpEnteredAt,
  String? paymentStatus,
  DateTime? paidAt,
  DateTime? now,
}) {
  final currentNow = now ?? DateTime.now();
  if (state == CanonicalBookingStateV3.acceptedAwaitingPayment &&
      payDeadlineAt != null &&
      !payDeadlineAt.isAfter(currentNow)) {
    return CanonicalBookingStateV3.paymentExpired;
  }
  final serviceWindowEnd = canonicalBookingAuthoritativeServiceWindowEndFromRaw(
    bookingType: bookingType,
    slotScheduledEndAt: slotScheduledEndAt,
    rangeCheckOutDateTime: rangeCheckOutDateTime,
  );
  final paymentIsConfirmed =
      paidAt != null || _hasConfirmedPaymentStatus(paymentStatus);
  if (state == CanonicalBookingStateV3.confirmed &&
      paymentIsConfirmed &&
      otpEnteredAt == null &&
      serviceWindowEnd != null &&
      !serviceWindowEnd.isAfter(currentNow)) {
    return CanonicalBookingStateV3.noShow;
  }
  return state;
}

DateTime? canonicalBookingAuthoritativeServiceWindowEnd(
  CanonicalBookingDocumentV3 booking,
) {
  return canonicalBookingAuthoritativeServiceWindowEndFromRaw(
    bookingType: booking.bookingType,
    slotScheduledEndAt: booking.schedule is CanonicalSlotBookingScheduleV3
        ? (booking.schedule as CanonicalSlotBookingScheduleV3).scheduledEndAt
        : null,
    rangeCheckOutDateTime: booking.schedule is CanonicalRangeBookingScheduleV3
        ? (booking.schedule as CanonicalRangeBookingScheduleV3).checkOutDateTime
        : null,
  );
}

DateTime? canonicalBookingAuthoritativeServiceWindowEndFromRaw({
  BookingV3Type? bookingType,
  DateTime? slotScheduledEndAt,
  DateTime? rangeCheckOutDateTime,
}) {
  if (bookingType == BookingV3Type.range) {
    return rangeCheckOutDateTime;
  }
  return slotScheduledEndAt;
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
  return canonicalBookingAuthoritativeServiceWindowEnd(booking);
}

bool hasActiveCanonicalPaymentWindow(DateTime? payDeadlineAt) {
  return payDeadlineAt == null || payDeadlineAt.isAfter(DateTime.now());
}

bool _hasConfirmedPaymentStatus(String? paymentStatus) {
  final normalized = paymentStatus?.trim().toLowerCase() ?? '';
  return normalized == 'paid' || normalized == 'confirmed';
}
