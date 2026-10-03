class ServiceSlotModel {
  final String id;
  final String serviceId;
  final String serviceOwnerId;
  final DateTime startAt;
  final DateTime endAt;
  final String dateKey;
  final int capacity;
  final int confirmedUnits;
  final bool isBookable;
  final String status;

  const ServiceSlotModel({
    required this.id,
    required this.serviceId,
    required this.serviceOwnerId,
    required this.startAt,
    required this.endAt,
    required this.dateKey,
    required this.capacity,
    required this.confirmedUnits,
    required this.isBookable,
    required this.status,
  });

  factory ServiceSlotModel.fromCallableMap(Map<String, dynamic> data) {
    final id = (data['id'] as String? ?? '').trim();
    final startAt = _readDate(data['startAt']);
    final endAt = _readDate(data['endAt']);
    final capacity = (data['capacity'] as num?)?.toInt();
    final confirmedUnits = (data['confirmedUnits'] as num?)?.toInt();
    if (id.isEmpty ||
        startAt == null ||
        endAt == null ||
        capacity == null ||
        capacity <= 0 ||
        confirmedUnits == null ||
        confirmedUnits < 0) {
      throw const FormatException('Malformed service slot availability.');
    }
    return ServiceSlotModel(
      id: id,
      serviceId: (data['serviceId'] as String? ?? '').trim(),
      serviceOwnerId: (data['serviceOwnerId'] as String? ?? '').trim(),
      startAt: startAt,
      endAt: endAt,
      dateKey: (data['dateKey'] as String? ?? '').trim(),
      capacity: capacity,
      confirmedUnits: confirmedUnits,
      isBookable: data['isBookable'] as bool? ?? false,
      status: (data['status'] as String? ?? 'closed').trim(),
    );
  }

  bool get isFull => confirmedUnits >= capacity;

  bool get isOpen => isBookable && status == 'open' && !isFull;

  bool get canRequest => isOpen;

  int get remainingCapacity => (capacity - confirmedUnits).clamp(0, capacity);

  static DateTime? _readDate(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
