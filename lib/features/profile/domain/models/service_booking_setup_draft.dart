import 'service_location.dart';

class ServiceBookingSetupDraft {
  final int sessionDurationMinutes;
  final bool hasConfirmedBookings;
  final int capacity;
  final List<String> availableDays;
  final int startMinutes;
  final int endMinutes;
  final bool sameForAllDays;
  final String serviceType;
  final ServiceLocation location;

  const ServiceBookingSetupDraft({
    required this.sessionDurationMinutes,
    required this.hasConfirmedBookings,
    required this.capacity,
    required this.availableDays,
    required this.startMinutes,
    required this.endMinutes,
    required this.sameForAllDays,
    required this.serviceType,
    required this.location,
  });
}
