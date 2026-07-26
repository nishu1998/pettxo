import 'booking_document_v3.dart';
import 'booking_v3_models.dart';

class CanonicalProviderBookingRequestView {
  final String bookingId;
  final BookingV3Type bookingType;
  final CanonicalBookingStateV3 state;
  final String serviceTitle;
  final String animalType;
  final String serviceCategory;
  final String maskedParentDisplayName;
  final double parentRating;
  final int completedBookingCount;
  final DateTime? scheduledStartAt;
  final DateTime? scheduledEndAt;
  final int slotCount;
  final int totalDurationMinutes;
  final DateTime? timerStartsAt;
  final DateTime? acceptDeadlineAt;
  final String timezone;
  final int? estimatedProviderPayoutPaise;

  const CanonicalProviderBookingRequestView({
    required this.bookingId,
    required this.bookingType,
    required this.state,
    required this.serviceTitle,
    required this.animalType,
    required this.serviceCategory,
    required this.maskedParentDisplayName,
    required this.parentRating,
    required this.completedBookingCount,
    required this.scheduledStartAt,
    required this.scheduledEndAt,
    required this.slotCount,
    required this.totalDurationMinutes,
    required this.timerStartsAt,
    required this.acceptDeadlineAt,
    required this.timezone,
    required this.estimatedProviderPayoutPaise,
  });

  factory CanonicalProviderBookingRequestView.fromBooking(
    String bookingId,
    CanonicalBookingDocumentV3 booking,
  ) {
    final schedule = booking.schedule;
    final slotSchedule = schedule is CanonicalSlotBookingScheduleV3
        ? schedule
        : null;
    final maskedName = [
      booking.participants.parent.displayFirstName.trim(),
      if (booking.participants.parent.lastInitial.trim().isNotEmpty)
        '${booking.participants.parent.lastInitial.trim()}.',
    ].join(' ');

    return CanonicalProviderBookingRequestView(
      bookingId: bookingId,
      bookingType: booking.bookingType,
      state: booking.state,
      serviceTitle: booking.service.serviceTitle,
      animalType: booking.service.animalType,
      serviceCategory: booking.service.category,
      maskedParentDisplayName: maskedName.trim().isEmpty
          ? 'Pet parent'
          : maskedName.trim(),
      parentRating: booking.participants.parent.rating,
      completedBookingCount: booking.participants.parent.completedBookingCount,
      scheduledStartAt: slotSchedule?.scheduledStartAt,
      scheduledEndAt: slotSchedule?.scheduledEndAt,
      slotCount: slotSchedule?.slotCount ?? 0,
      totalDurationMinutes: slotSchedule?.totalDurationMinutes ?? 0,
      timerStartsAt: booking.lifecycle.timerStartsAt,
      acceptDeadlineAt: booking.lifecycle.acceptDeadlineAt,
      timezone: booking.schedule.timezone,
      estimatedProviderPayoutPaise: booking.financials?.providerPayoutPaise,
    );
  }

  bool get isQueuedRequest => state == CanonicalBookingStateV3.requested;
  bool get isPendingProvider =>
      state == CanonicalBookingStateV3.pendingProvider;
  bool get isAcceptedAwaitingPayment =>
      state == CanonicalBookingStateV3.acceptedAwaitingPayment;
  bool get isAwaitingProviderDecision => isQueuedRequest || isPendingProvider;
  bool get isActionable => isAwaitingProviderDecision;
}
