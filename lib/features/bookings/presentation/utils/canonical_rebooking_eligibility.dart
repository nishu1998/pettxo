import '../../domain/models/booking_document_v3.dart';
import '../../domain/models/booking_v3_models.dart';
import '../../../services/domain/models/service_model.dart';

bool canonicalBookingStateAllowsRebooking(CanonicalBookingStateV3 state) {
  return switch (state) {
    CanonicalBookingStateV3.completedPendingReview ||
    CanonicalBookingStateV3.completedFinal ||
    CanonicalBookingStateV3.noShow ||
    CanonicalBookingStateV3.cancelled ||
    CanonicalBookingStateV3.cancelledByParent ||
    CanonicalBookingStateV3.declined ||
    CanonicalBookingStateV3.expired ||
    CanonicalBookingStateV3.paymentExpired => true,
    _ => false,
  };
}

bool canonicalBookingAllowsRebooking(
  CanonicalBookingDocumentV3 booking, {
  CanonicalBookingStateV3? effectiveState,
}) {
  final state = effectiveState ?? booking.state;
  if (!canonicalBookingStateAllowsRebooking(state)) return false;

  switch (state) {
    case CanonicalBookingStateV3.completedPendingReview:
    case CanonicalBookingStateV3.completedFinal:
      return booking.state == CanonicalBookingStateV3.completedPendingReview ||
          booking.state == CanonicalBookingStateV3.completedFinal;
    case CanonicalBookingStateV3.noShow:
      return booking.state == CanonicalBookingStateV3.noShow;
    case CanonicalBookingStateV3.cancelled:
      if (booking.state != CanonicalBookingStateV3.cancelled) return false;
      return const {
        'parent',
        'customer',
        'provider',
      }.contains(booking.cancellation.cancelledBy?.trim().toLowerCase());
    default:
      return true;
  }
}

bool canonicalServiceAllowsRebooking(ServiceModel? service) {
  return service != null &&
      !service.isDeleted &&
      service.isActive &&
      !service.isPaused &&
      service.isVisibleToMarketplace &&
      !service.isEffectivelyPausedByVerification;
}
