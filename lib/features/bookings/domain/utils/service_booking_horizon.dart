// Keep in sync with SERVICE_BOOKING_HORIZON_DAYS in serviceSlotCandidates.ts.
// The backend contract test checks parity. Both endpoints are inclusive.
const int serviceBookingHorizonDays = 30;

/// A calendar label in the service's Asia/Kolkata timezone, independent of the
/// device timezone. Local DateTime keeps the existing calendar widget contract.
DateTime serviceBookingDate(DateTime instant) {
  final ist = instant.toUtc().add(const Duration(minutes: 330));
  return DateTime(ist.year, ist.month, ist.day);
}

DateTime lastServiceBookingDate(DateTime instant) {
  final today = serviceBookingDate(instant);
  return DateTime(
    today.year,
    today.month,
    today.day + serviceBookingHorizonDays,
  );
}
