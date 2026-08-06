const String serviceSchedulingModeFixedDuration = 'fixedDuration';
const String serviceSchedulingModeDayCare = 'dayCare';

const List<int> selectableFixedServiceDurations = <int>[
  30,
  60,
  90,
  120,
  180,
  240,
];

String normalizeServiceSchedulingMode(
  String? rawMode, {
  int? sessionDurationMinutes,
}) {
  final normalizedRaw = rawMode?.trim() ?? '';
  if (normalizedRaw == serviceSchedulingModeDayCare ||
      normalizedRaw.toLowerCase() == 'wholeday') {
    return serviceSchedulingModeDayCare;
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

String serviceDurationHelperText({required String schedulingMode}) {
  return schedulingMode == serviceSchedulingModeDayCare
      ? 'Each available day creates one booking slot from the selected start time to end time.'
      : 'Available hours are divided into bookable sessions of this duration.';
}
