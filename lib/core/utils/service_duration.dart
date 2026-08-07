const String serviceSchedulingModeFixedDuration = 'fixedDuration';
const String serviceSchedulingModeDayCare = 'dayCare';
const String serviceSchedulingModeOvernight = 'overnight';
const String serviceSchedulingModeTwentyFourHours = 'twentyFourHours';

const List<int> selectableFixedServiceDurations = <int>[
  30,
  60,
  90,
  120,
  180,
  240,
];

class ServiceSchedulingValidationResult {
  final bool isValid;
  final String reason;

  const ServiceSchedulingValidationResult({
    required this.isValid,
    required this.reason,
  });
}

bool isValidServiceClockMinutes(int? value) {
  return value != null && value >= 0 && value < 24 * 60;
}

int? deriveOvernightDurationMinutes({
  required int? startMinutes,
  required int? endMinutes,
}) {
  if (!isValidServiceClockMinutes(startMinutes) ||
      !isValidServiceClockMinutes(endMinutes)) {
    return null;
  }
  return (24 * 60 - startMinutes!) + endMinutes!;
}

ServiceSchedulingValidationResult validateServiceSchedulingSetup({
  required String? schedulingMode,
  required int? sessionDurationMinutes,
  required int? startMinutes,
  required int? endMinutes,
  required Iterable<String> availableDays,
}) {
  final normalizedMode = normalizeServiceSchedulingMode(
    schedulingMode,
    sessionDurationMinutes: sessionDurationMinutes,
  );
  if (normalizedMode.trim().isEmpty) {
    return const ServiceSchedulingValidationResult(
      isValid: false,
      reason: 'missing_scheduling_mode',
    );
  }
  if (availableDays.isEmpty) {
    return const ServiceSchedulingValidationResult(
      isValid: false,
      reason: 'missing_available_days',
    );
  }
  if (!isValidServiceClockMinutes(startMinutes)) {
    return const ServiceSchedulingValidationResult(
      isValid: false,
      reason: 'invalid_start_minutes',
    );
  }

  switch (normalizedMode) {
    case serviceSchedulingModeTwentyFourHours:
      if (sessionDurationMinutes != 24 * 60) {
        return const ServiceSchedulingValidationResult(
          isValid: false,
          reason: 'invalid_twenty_four_hour_duration',
        );
      }
      return const ServiceSchedulingValidationResult(
        isValid: true,
        reason: 'valid',
      );
    case serviceSchedulingModeOvernight:
      if (!isValidServiceClockMinutes(endMinutes)) {
        return const ServiceSchedulingValidationResult(
          isValid: false,
          reason: 'invalid_end_minutes',
        );
      }
      final derivedDuration = deriveOvernightDurationMinutes(
        startMinutes: startMinutes,
        endMinutes: endMinutes,
      );
      if (derivedDuration == null ||
          derivedDuration <= 0 ||
          derivedDuration >= 24 * 60) {
        return const ServiceSchedulingValidationResult(
          isValid: false,
          reason: 'invalid_overnight_window',
        );
      }
      if (sessionDurationMinutes == null ||
          sessionDurationMinutes <= 0 ||
          sessionDurationMinutes != derivedDuration) {
        return const ServiceSchedulingValidationResult(
          isValid: false,
          reason: 'invalid_overnight_duration',
        );
      }
      return const ServiceSchedulingValidationResult(
        isValid: true,
        reason: 'valid',
      );
    case serviceSchedulingModeDayCare:
    case serviceSchedulingModeFixedDuration:
      if (!isValidServiceClockMinutes(endMinutes)) {
        return const ServiceSchedulingValidationResult(
          isValid: false,
          reason: 'invalid_end_minutes',
        );
      }
      if (sessionDurationMinutes == null || sessionDurationMinutes <= 0) {
        return const ServiceSchedulingValidationResult(
          isValid: false,
          reason: 'invalid_session_duration',
        );
      }
      if (endMinutes! <= startMinutes!) {
        return const ServiceSchedulingValidationResult(
          isValid: false,
          reason: 'same_day_end_not_after_start',
        );
      }
      return const ServiceSchedulingValidationResult(
        isValid: true,
        reason: 'valid',
      );
    default:
      return const ServiceSchedulingValidationResult(
        isValid: false,
        reason: 'unsupported_scheduling_mode',
      );
  }
}

String normalizeServiceSchedulingMode(
  String? rawMode, {
  int? sessionDurationMinutes,
}) {
  final normalizedRaw = rawMode?.trim() ?? '';
  if (normalizedRaw == serviceSchedulingModeDayCare ||
      normalizedRaw.toLowerCase() == 'wholeday') {
    return serviceSchedulingModeDayCare;
  }
  if (normalizedRaw == serviceSchedulingModeOvernight) {
    return serviceSchedulingModeOvernight;
  }
  if (normalizedRaw == serviceSchedulingModeTwentyFourHours) {
    return serviceSchedulingModeTwentyFourHours;
  }
  if (normalizedRaw == serviceSchedulingModeFixedDuration) {
    return serviceSchedulingModeFixedDuration;
  }
  final durationMinutes = sessionDurationMinutes ?? 0;
  if (durationMinutes <= 0 || durationMinutes >= 24 * 60) {
    return serviceSchedulingModeDayCare;
  }
  return serviceSchedulingModeFixedDuration;
}

bool isDayCareSchedulingMode(String? rawMode, {int? sessionDurationMinutes}) {
  return normalizeServiceSchedulingMode(
        rawMode,
        sessionDurationMinutes: sessionDurationMinutes,
      ) ==
      serviceSchedulingModeDayCare;
}

bool isOvernightSchedulingMode(String? rawMode, {int? sessionDurationMinutes}) {
  return normalizeServiceSchedulingMode(
        rawMode,
        sessionDurationMinutes: sessionDurationMinutes,
      ) ==
      serviceSchedulingModeOvernight;
}

bool isTwentyFourHourSchedulingMode(
  String? rawMode, {
  int? sessionDurationMinutes,
}) {
  return normalizeServiceSchedulingMode(
        rawMode,
        sessionDurationMinutes: sessionDurationMinutes,
      ) ==
      serviceSchedulingModeTwentyFourHours;
}

bool isLegacyWholeDayDuration(int? sessionDurationMinutes) {
  final durationMinutes = sessionDurationMinutes ?? 0;
  return durationMinutes <= 0 || durationMinutes >= 24 * 60;
}

String formatServiceDurationLabel({
  required int durationMinutes,
  String? schedulingMode,
}) {
  if (isDayCareSchedulingMode(
    schedulingMode,
    sessionDurationMinutes: durationMinutes,
  )) {
    return 'Day care';
  }
  if (isOvernightSchedulingMode(
    schedulingMode,
    sessionDurationMinutes: durationMinutes,
  )) {
    return 'Overnight';
  }
  if (isTwentyFourHourSchedulingMode(
    schedulingMode,
    sessionDurationMinutes: durationMinutes,
  )) {
    return '24 hours';
  }

  if (durationMinutes <= 0) return 'Pending';
  if (durationMinutes < 60) {
    return '$durationMinutes minute${durationMinutes == 1 ? '' : 's'}';
  }

  final hours = durationMinutes ~/ 60;
  final remainingMinutes = durationMinutes % 60;
  final hourLabel = '$hours hour${hours == 1 ? '' : 's'}';
  if (remainingMinutes == 0) {
    return hourLabel;
  }
  return '$hourLabel $remainingMinutes minute${remainingMinutes == 1 ? '' : 's'}';
}

String formatServiceAvailabilityLabel({
  required Iterable<String> availableDays,
  required int startMinutes,
  required int endMinutes,
  String? schedulingMode,
  int? sessionDurationMinutes,
}) {
  final normalizedMode = normalizeServiceSchedulingMode(
    schedulingMode,
    sessionDurationMinutes: sessionDurationMinutes,
  );
  final endSuffix =
      normalizedMode == serviceSchedulingModeOvernight ||
          normalizedMode == serviceSchedulingModeTwentyFourHours
      ? ' (next day)'
      : '';

  return '${availableDays.join(', ')} - '
      '${_formatServiceClockMinutes(startMinutes)} to '
      '${_formatServiceClockMinutes(endMinutes)}$endSuffix';
}

String serviceDurationHelperText({required String schedulingMode}) {
  switch (schedulingMode) {
    case serviceSchedulingModeDayCare:
      return 'Each available day creates one booking slot from the selected start time to end time.';
    case serviceSchedulingModeOvernight:
      return 'Each available day creates one overnight booking slot from the selected start time until the selected next-day end time.';
    case serviceSchedulingModeTwentyFourHours:
      return 'Each available day creates one booking slot that starts at the selected time and ends exactly 24 hours later.';
    default:
      return 'Available hours are divided into bookable sessions of this duration.';
  }
}

String _formatServiceClockMinutes(int totalMinutes) {
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  final normalizedHour = hours % 24;
  final displayHour = normalizedHour == 0
      ? 12
      : (normalizedHour > 12 ? normalizedHour - 12 : normalizedHour);
  final period = normalizedHour >= 12 ? 'PM' : 'AM';
  final paddedMinutes = minutes.toString().padLeft(2, '0');
  return '$displayHour:$paddedMinutes $period';
}
