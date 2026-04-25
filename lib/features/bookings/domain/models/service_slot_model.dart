import 'package:cloud_firestore/cloud_firestore.dart';

class ServiceSlotModel {
  final String id;
  final String serviceId;
  final String serviceOwnerId;
  final DateTime startAt;
  final DateTime endAt;
  final String dateKey;
  final int capacity;
  final int acceptedCount;
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
    required this.acceptedCount,
    required this.isBookable,
    required this.status,
  });

  factory ServiceSlotModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ServiceSlotModel(
      id: doc.id,
      serviceId: (data['serviceId'] as String? ?? '').trim(),
      serviceOwnerId: (data['serviceOwnerId'] as String? ?? '').trim(),
      startAt:
          _readDate(data['startAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      endAt: _readDate(data['endAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      dateKey: (data['dateKey'] as String? ?? '').trim(),
      capacity: (data['capacity'] as num?)?.toInt() ?? 1,
      acceptedCount: (data['acceptedCount'] as num?)?.toInt() ?? 0,
      isBookable: data['isBookable'] as bool? ?? false,
      status: (data['status'] as String? ?? 'closed').trim(),
    );
  }

  bool get isFull => acceptedCount >= capacity;

  bool get isOpen => isBookable && status == 'open' && !isFull;

  bool get isTooSoon {
    return startAt.difference(DateTime.now()) < const Duration(hours: 1);
  }

  bool get canRequest => isOpen && !isTooSoon;

  int get remainingCapacity => (capacity - acceptedCount).clamp(0, capacity);

  static DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
