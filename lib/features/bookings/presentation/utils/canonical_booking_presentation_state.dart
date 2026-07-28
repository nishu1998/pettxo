import '../../domain/models/booking_document_v3.dart';
import '../../domain/models/booking_v3_models.dart';

CanonicalBookingStateV3 effectiveCanonicalBookingPresentationState(
  CanonicalBookingDocumentV3 booking,
) {
  return effectiveCanonicalBookingPresentationStateFromRaw(
    booking.state,
    booking.lifecycle.payDeadlineAt,
  );
}

CanonicalBookingStateV3 effectiveCanonicalBookingPresentationStateFromRaw(
  CanonicalBookingStateV3 state,
  DateTime? payDeadlineAt,
) {
  if (state == CanonicalBookingStateV3.acceptedAwaitingPayment &&
      payDeadlineAt != null &&
      !payDeadlineAt.isAfter(DateTime.now())) {
    return CanonicalBookingStateV3.paymentExpired;
  }
  return state;
}

bool hasActiveCanonicalPaymentWindow(DateTime? payDeadlineAt) {
  return payDeadlineAt == null || payDeadlineAt.isAfter(DateTime.now());
}
