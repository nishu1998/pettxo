class BookingCheckoutDraft {
  final String serviceId;
  final String serviceName;
  final int price;
  final int durationMinutes;
  final String providerId;
  final String slotId;
  final DateTime selectedSlot;
  final DateTime selectedSlotEnd;

  const BookingCheckoutDraft({
    required this.serviceId,
    required this.serviceName,
    required this.price,
    required this.durationMinutes,
    required this.providerId,
    required this.slotId,
    required this.selectedSlot,
    required this.selectedSlotEnd,
  });

  int get totalAmount => price;
}
