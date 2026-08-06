import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/utils/service_duration.dart';

void main() {
  test('selectable durations exclude legacy 15 and include 180 and 240', () {
    expect(selectableFixedServiceDurations, isNot(contains(15)));
    expect(selectableFixedServiceDurations, containsAll(<int>[180, 240]));
  });

  test('formats fixed-duration labels in user-friendly hour text', () {
    expect(formatServiceDurationLabel(durationMinutes: 30), '30 minutes');
    expect(formatServiceDurationLabel(durationMinutes: 60), '1 hour');
    expect(
      formatServiceDurationLabel(durationMinutes: 90),
      '1 hour 30 minutes',
    );
    expect(formatServiceDurationLabel(durationMinutes: 240), '4 hours');
  });

  test('normalizes legacy whole-day records to day care safely', () {
    expect(
      normalizeServiceSchedulingMode(null, sessionDurationMinutes: 24 * 60),
      serviceSchedulingModeDayCare,
    );
    expect(
      normalizeServiceSchedulingMode('wholeDay', sessionDurationMinutes: 0),
      serviceSchedulingModeDayCare,
    );
    expect(
      formatServiceDurationLabel(
        durationMinutes: 540,
        schedulingMode: serviceSchedulingModeDayCare,
      ),
      'Day care',
    );
  });

  test('keeps legacy 15-minute data readable', () {
    expect(
      normalizeServiceSchedulingMode(null, sessionDurationMinutes: 15),
      serviceSchedulingModeFixedDuration,
    );
    expect(formatServiceDurationLabel(durationMinutes: 15), '15 minutes');
  });
}
