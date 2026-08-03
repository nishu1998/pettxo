import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? parseFirebaseDateTime(dynamic value) {
  if (value == null) return null;

  if (value is DateTime) {
    return value;
  }

  if (value is Timestamp) {
    return value.toDate();
  }

  if (value is num) {
    return _dateTimeFromEpochNumber(value);
  }

  if (value is String) {
    return DateTime.tryParse(value);
  }

  if (value is Map) {
    final secondsValue = value['_seconds'] ?? value['seconds'];
    final nanosecondsValue = value['_nanoseconds'] ?? value['nanoseconds'] ?? 0;
    if (secondsValue is num && nanosecondsValue is num) {
      final milliseconds =
          (secondsValue.toInt() * 1000) + (nanosecondsValue.toInt() ~/ 1000000);
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }
  }

  return null;
}

Timestamp? parseFirebaseTimestamp(dynamic value) {
  final dateTime = parseFirebaseDateTime(value);
  if (dateTime == null) return null;
  return Timestamp.fromDate(dateTime);
}

int? parseFirebaseEpochMilliseconds(dynamic value) {
  if (value == null) return null;
  if (value is num) {
    return _normalizeEpochMilliseconds(value);
  }

  final dateTime = parseFirebaseDateTime(value);
  return dateTime?.millisecondsSinceEpoch;
}

DateTime _dateTimeFromEpochNumber(num value) {
  final milliseconds = _normalizeEpochMilliseconds(value);
  return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
}

int _normalizeEpochMilliseconds(num value) {
  final normalized = value.toInt();
  final absolute = normalized.abs();
  if (absolute > 0 && absolute < 100000000000) {
    return normalized * 1000;
  }
  return normalized;
}
