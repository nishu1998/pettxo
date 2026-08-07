import 'booking_document_v3.dart';
import 'booking_v3_models.dart';
import '../../presentation/utils/canonical_booking_schedule_presentation.dart';
import '../../presentation/utils/canonical_booking_presentation_state.dart';

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
  final String schedulingMode;
  final DateTime? timerStartsAt;
  final DateTime? acceptDeadlineAt;
  final DateTime? payDeadlineAt;
  final String timezone;
  final int? estimatedProviderPayoutPaise;
  final CanonicalBookingSchedulePresentation schedulePresentation;

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
    required this.schedulingMode,
    required this.timerStartsAt,
    required this.acceptDeadlineAt,
    required this.payDeadlineAt,
    required this.timezone,
    required this.estimatedProviderPayoutPaise,
    required this.schedulePresentation,
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
    final schedulePresentation = buildCanonicalBookingSchedulePresentation(
      booking,
    );

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
      schedulingMode: booking.service.schedulingMode,
      timerStartsAt: booking.lifecycle.timerStartsAt,
      acceptDeadlineAt: booking.lifecycle.acceptDeadlineAt,
      payDeadlineAt: booking.lifecycle.payDeadlineAt,
      timezone: booking.schedule.timezone,
      estimatedProviderPayoutPaise: booking.financials?.providerPayoutPaise,
      schedulePresentation: schedulePresentation,
    );
  }

  CanonicalBookingStateV3 get effectiveState =>
      effectiveCanonicalBookingPresentationStateFromRaw(state, payDeadlineAt);

  bool get isQueuedRequest =>
      effectiveState == CanonicalBookingStateV3.requested;
  bool get isPendingProvider =>
      effectiveState == CanonicalBookingStateV3.pendingProvider;
  bool get isAcceptedAwaitingPayment =>
      effectiveState == CanonicalBookingStateV3.acceptedAwaitingPayment;
  bool get isPaymentExpired =>
      effectiveState == CanonicalBookingStateV3.paymentExpired;
  bool get isAwaitingProviderDecision => isQueuedRequest || isPendingProvider;
  bool get isActionable => isAwaitingProviderDecision;
}
