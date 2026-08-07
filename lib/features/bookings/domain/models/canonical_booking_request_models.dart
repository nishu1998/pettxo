import 'booking_v3_models.dart';

enum CanonicalBookingRequestFailureCode {
  canonicalBookingDisabled,
  unauthenticated,
  serviceNotFound,
  serviceInactive,
  servicePaused,
  providerUnavailable,
  invalidBookingType,
  invalidSchedule,
  runwayNotSatisfied,
  invalidTimezone,
  idempotencyConflict,
  permissionDenied,
  unknown,
}

class CanonicalBookingRequestInput {
  final String requestAttemptId;
  final String serviceId;
  final BookingV3Type bookingType;
  final CanonicalSlotRequestInput? slotRequest;
  final CanonicalRangeRequestInput? rangeRequest;

  const CanonicalBookingRequestInput({
    required this.requestAttemptId,
    required this.serviceId,
    required this.bookingType,
    this.slotRequest,
    this.rangeRequest,
  });

  Map<String, dynamic> toCallableMap() {
    return {
      'requestAttemptId': requestAttemptId,
      'serviceId': serviceId,
      'bookingType': bookingType == BookingV3Type.slot ? 'SLOT' : 'RANGE',
      if (slotRequest != null) ...slotRequest!.toCallableMap(),
      if (rangeRequest != null) ...rangeRequest!.toCallableMap(),
    };
  }
}

class CanonicalSlotRequestInput {
  final SlotBookingSelectionV3 selection;
  final int estimatedSubtotalPaise;
  final List<CanonicalSelectedDaySlotInput>? selectedDays;

  const CanonicalSlotRequestInput({
    required this.selection,
    required this.estimatedSubtotalPaise,
    this.selectedDays,
  });

  List<String> get slotIds => selectedDays != null && selectedDays!.isNotEmpty
      ? selectedDays!.expand((day) => day.slotIds).toList(growable: false)
      : selection.slots.map((slot) => slot.slotId).toList(growable: false);

  Map<String, dynamic> toCallableMap() {
    return {
      if (selectedDays != null && selectedDays!.isNotEmpty)
        'selectedDays': selectedDays!
            .map((day) => day.toCallableMap())
            .toList(growable: false)
      else
        'slotIds': slotIds,
    };
  }
}

class CanonicalSelectedDaySlotInput {
  final String serviceDateKey;
  final List<String> slotIds;

  const CanonicalSelectedDaySlotInput({
    required this.serviceDateKey,
    required this.slotIds,
  });

  Map<String, dynamic> toCallableMap() {
    return {'serviceDateKey': serviceDateKey, 'slotIds': slotIds};
  }
}

class CanonicalRangeRequestInput {
  final DateTime checkInDateTime;
  final DateTime checkOutDateTime;
  final int nights;
  final String timezone;
  final int? petQuantity;
  final int estimatedSubtotalPaise;

  const CanonicalRangeRequestInput({
    required this.checkInDateTime,
    required this.checkOutDateTime,
    required this.nights,
    required this.timezone,
    required this.petQuantity,
    required this.estimatedSubtotalPaise,
  });

  Map<String, dynamic> toCallableMap() {
    return {
      'checkInDateTime': checkInDateTime.toIso8601String(),
      'checkOutDateTime': checkOutDateTime.toIso8601String(),
      if (petQuantity != null) 'petQuantity': petQuantity,
    };
  }
}

class CanonicalBookingRequestResult {
  final String bookingId;
  final String source;
  final int schemaVersion;
  final String bookingModelVersion;
  final CanonicalBookingStateV3 state;
  final BookingV3Type bookingType;
  final DateTime? requestedAt;
  final DateTime? timerStartsAt;
  final DateTime? acceptDeadlineAt;
  final bool wasQueuedOutsideWorkingHours;
  final bool idempotentReplay;

  const CanonicalBookingRequestResult({
    required this.bookingId,
    required this.source,
    required this.schemaVersion,
    required this.bookingModelVersion,
    required this.state,
    required this.bookingType,
    required this.requestedAt,
    required this.timerStartsAt,
    required this.acceptDeadlineAt,
    required this.wasQueuedOutsideWorkingHours,
    required this.idempotentReplay,
  });

  factory CanonicalBookingRequestResult.fromMap(Map<String, dynamic> data) {
    final stateValue = (data['state'] as String? ?? '').trim();
    final typeValue = (data['bookingType'] as String? ?? 'SLOT').trim();
    final state = CanonicalBookingStateV3.values.firstWhere(
      (entry) =>
          _normalizeEnumValue(entry.name) == _normalizeEnumValue(stateValue),
      orElse: () => CanonicalBookingStateV3.requested,
    );
    return CanonicalBookingRequestResult(
      bookingId: (data['bookingId'] as String? ?? '').trim(),
      source: (data['source'] as String? ?? '').trim(),
      schemaVersion: (data['schemaVersion'] as num?)?.toInt() ?? 0,
      bookingModelVersion: (data['bookingModelVersion'] as String? ?? '')
          .trim(),
      state: state,
      bookingType: typeValue == 'RANGE'
          ? BookingV3Type.range
          : BookingV3Type.slot,
      requestedAt: _readDate(data['requestedAt']),
      timerStartsAt: _readDate(data['timerStartsAt']),
      acceptDeadlineAt: _readDate(data['acceptDeadlineAt']),
      wasQueuedOutsideWorkingHours:
          data['wasQueuedOutsideWorkingHours'] == true,
      idempotentReplay: data['idempotentReplay'] == true,
    );
  }

  static DateTime? _readDate(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }

  static String _normalizeEnumValue(String value) {
    return value.replaceAll('_', '').toUpperCase();
  }
}

class CanonicalBookingCommandResult {
  final String bookingId;
  final CanonicalBookingStateV3 state;
  final DateTime? respondedAt;
  final DateTime? payDeadlineAt;
  final DateTime? cancelledAt;
  final DateTime? viewedByProviderAt;
  final bool idempotentReplay;

  const CanonicalBookingCommandResult({
    required this.bookingId,
    required this.state,
    required this.respondedAt,
    required this.payDeadlineAt,
    required this.cancelledAt,
    required this.viewedByProviderAt,
    required this.idempotentReplay,
  });

  factory CanonicalBookingCommandResult.fromMap(Map<String, dynamic> data) {
    final stateValue = (data['state'] as String? ?? '').trim();
    final state = CanonicalBookingStateV3.values.firstWhere(
      (entry) =>
          CanonicalBookingRequestResult._normalizeEnumValue(entry.name) ==
          CanonicalBookingRequestResult._normalizeEnumValue(stateValue),
      orElse: () => CanonicalBookingStateV3.requested,
    );
    return CanonicalBookingCommandResult(
      bookingId: (data['bookingId'] as String? ?? '').trim(),
      state: state,
      respondedAt: CanonicalBookingRequestResult._readDate(data['respondedAt']),
      payDeadlineAt: CanonicalBookingRequestResult._readDate(
        data['payDeadlineAt'],
      ),
      cancelledAt: CanonicalBookingRequestResult._readDate(data['cancelledAt']),
      viewedByProviderAt: CanonicalBookingRequestResult._readDate(
        data['viewedByProviderAt'],
      ),
      idempotentReplay: data['idempotentReplay'] == true,
    );
  }
}

class CanonicalBookingRequestException implements Exception {
  final CanonicalBookingRequestFailureCode code;
  final String message;
  final List<String> issues;

  const CanonicalBookingRequestException({
    required this.code,
    required this.message,
    this.issues = const [],
  });

  @override
  String toString() => 'CanonicalBookingRequestException($code, $message)';
}
