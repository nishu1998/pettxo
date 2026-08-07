import '../../../../core/utils/service_duration.dart';
import '../../domain/models/booking_document_v3.dart';
import '../../domain/models/booking_v3_models.dart';

class CanonicalBookingScheduleDisplayRow {
  final String label;
  final String value;

  const CanonicalBookingScheduleDisplayRow({
    required this.label,
    required this.value,
  });
}

class CanonicalBookingSchedulePresentation {
  final BookingV3Type bookingType;
  final List<CanonicalBookingScheduleSegmentV3> effectiveSegments;
  final bool isMultiDayPackage;
  final bool hasContinuousServiceWindow;
  final int serviceDayCount;
  final int segmentCount;
  final int slotCount;
  final DateTime? firstStartAt;
  final DateTime? firstSegmentEndAt;
  final DateTime? finalEndAt;
  final int totalDurationMinutes;
  final String schedulingMode;
  final String compactDateRangeLabel;
  final String compactScheduleSummary;
  final String dateLabel;
  final String timeLabel;
  final String durationLabel;
  final String packageLabel;
  final List<CanonicalBookingScheduleDisplayRow> perSegmentDisplayRows;
  final String cancellationConfirmationMessage;

  const CanonicalBookingSchedulePresentation({
    required this.bookingType,
    required this.effectiveSegments,
    required this.isMultiDayPackage,
    required this.hasContinuousServiceWindow,
    required this.serviceDayCount,
    required this.segmentCount,
    required this.slotCount,
    required this.firstStartAt,
    required this.firstSegmentEndAt,
    required this.finalEndAt,
    required this.totalDurationMinutes,
    required this.schedulingMode,
    required this.compactDateRangeLabel,
    required this.compactScheduleSummary,
    required this.dateLabel,
    required this.timeLabel,
    required this.durationLabel,
    required this.packageLabel,
    required this.perSegmentDisplayRows,
    required this.cancellationConfirmationMessage,
  });

  bool get isRangeBooking => bookingType == BookingV3Type.range;
  bool get isSlotBooking => bookingType == BookingV3Type.slot;
}

CanonicalBookingSchedulePresentation buildCanonicalBookingSchedulePresentation(
  CanonicalBookingDocumentV3 booking,
) {
  if (booking.schedule case final CanonicalRangeBookingScheduleV3 schedule) {
    final start = schedule.checkInDateTime;
    final end = schedule.checkOutDateTime;
    final dateLabel = _formatLongDate(start);
    final timeLabel = '${_formatTime(start)} - ${_formatTime(end)}';
    return CanonicalBookingSchedulePresentation(
      bookingType: BookingV3Type.range,
      effectiveSegments: const <CanonicalBookingScheduleSegmentV3>[],
      isMultiDayPackage: false,
      hasContinuousServiceWindow: end.isAfter(start),
      serviceDayCount: 1,
      segmentCount: 1,
      slotCount: 0,
      firstStartAt: start,
      firstSegmentEndAt: end,
      finalEndAt: end,
      totalDurationMinutes: end.difference(start).inMinutes,
      schedulingMode: booking.service.schedulingMode,
      compactDateRangeLabel: dateLabel,
      compactScheduleSummary: '$dateLabel · $timeLabel',
      dateLabel: dateLabel,
      timeLabel: timeLabel,
      durationLabel: schedule.nights == 1
          ? '1 night'
          : '${schedule.nights} nights',
      packageLabel: 'Stay booking',
      perSegmentDisplayRows: <CanonicalBookingScheduleDisplayRow>[
        CanonicalBookingScheduleDisplayRow(
          label: 'Stay',
          value: '${_formatLongDateTime(start)} - ${_formatLongDateTime(end)}',
        ),
      ],
      cancellationConfirmationMessage: 'This will cancel the complete booking.',
    );
  }

  final schedule = booking.schedule as CanonicalSlotBookingScheduleV3;
  final effectiveSegments = _resolveEffectiveSegments(booking, schedule);
  final firstStartAt = effectiveSegments.isNotEmpty
      ? effectiveSegments.first.startAt
      : schedule.scheduledStartAt;
  final firstSegmentEndAt =
      schedule.firstSegmentEndAt ??
      (effectiveSegments.isNotEmpty ? effectiveSegments.first.endAt : null);
  final finalEndAt =
      schedule.finalEndAt ??
      (effectiveSegments.isNotEmpty ? effectiveSegments.last.endAt : null);
  final serviceDayCount =
      schedule.serviceDayCount ?? _distinctServiceDateCount(effectiveSegments);
  final segmentCount = schedule.segmentCount ?? effectiveSegments.length;
  final slotCount = schedule.slotCount > 0
      ? schedule.slotCount
      : schedule.slots.length;
  final totalDurationMinutes = schedule.totalDurationMinutes > 0
      ? schedule.totalDurationMinutes
      : booking.statistics.totalDurationMinutes ?? 0;
  final schedulingMode = _resolvedSchedulingMode(booking, effectiveSegments);
  final packageLabel = _packageLabel(
    serviceDayCount: serviceDayCount,
    segmentCount: segmentCount,
    schedulingMode: schedulingMode,
  );
  final compactDateRangeLabel = _serviceDateRangeLabel(effectiveSegments);
  final isMultiDayPackage = serviceDayCount > 1;
  final hasContinuousServiceWindow = _hasContinuousServiceWindow(
    effectiveSegments,
  );

  return CanonicalBookingSchedulePresentation(
    bookingType: BookingV3Type.slot,
    effectiveSegments: effectiveSegments,
    isMultiDayPackage: isMultiDayPackage,
    hasContinuousServiceWindow: hasContinuousServiceWindow,
    serviceDayCount: serviceDayCount,
    segmentCount: segmentCount,
    slotCount: slotCount,
    firstStartAt: firstStartAt,
    firstSegmentEndAt: firstSegmentEndAt,
    finalEndAt: finalEndAt,
    totalDurationMinutes: totalDurationMinutes,
    schedulingMode: schedulingMode,
    compactDateRangeLabel: compactDateRangeLabel,
    compactScheduleSummary: _compactScheduleSummary(
      effectiveSegments: effectiveSegments,
      isMultiDayPackage: isMultiDayPackage,
      packageLabel: packageLabel,
      compactDateRangeLabel: compactDateRangeLabel,
    ),
    dateLabel: _slotDateLabel(
      effectiveSegments: effectiveSegments,
      isMultiDayPackage: isMultiDayPackage,
      packageLabel: packageLabel,
      compactDateRangeLabel: compactDateRangeLabel,
    ),
    timeLabel: _slotTimeLabel(
      effectiveSegments: effectiveSegments,
      isMultiDayPackage: isMultiDayPackage,
      hasContinuousServiceWindow: hasContinuousServiceWindow,
    ),
    durationLabel: totalDurationMinutes > 0
        ? formatServiceDurationLabel(
            durationMinutes: totalDurationMinutes,
            schedulingMode: schedulingMode,
          )
        : 'Pending',
    packageLabel: packageLabel,
    perSegmentDisplayRows: _buildPerSegmentRows(effectiveSegments),
    cancellationConfirmationMessage: isMultiDayPackage
        ? 'This will cancel the complete booking, including all selected service dates.'
        : 'This will cancel the complete booking.',
  );
}

List<CanonicalBookingScheduleSegmentV3> _resolveEffectiveSegments(
  CanonicalBookingDocumentV3 booking,
  CanonicalSlotBookingScheduleV3 schedule,
) {
  final provided =
      (schedule.segments ?? const <CanonicalBookingScheduleSegmentV3>[])
          .where((segment) => segment.endAt.isAfter(segment.startAt))
          .toList(growable: false)
        ..sort((a, b) => a.startAt.compareTo(b.startAt));
  if (provided.isNotEmpty) {
    return provided;
  }
  if (!schedule.scheduledEndAt.isAfter(schedule.scheduledStartAt)) {
    return const <CanonicalBookingScheduleSegmentV3>[];
  }
  final fallbackKey = _resolvedServiceDateKey(
    schedule.slots.isNotEmpty ? schedule.slots.first.serviceDateKey : null,
    schedule.slots.isNotEmpty ? schedule.slots.first.dateKey : null,
    schedule.scheduledStartAt,
  );
  return <CanonicalBookingScheduleSegmentV3>[
    CanonicalBookingScheduleSegmentV3(
      serviceDateKey: fallbackKey,
      slotIds: schedule.slots
          .map((slot) => slot.slotId)
          .toList(growable: false),
      startAt: schedule.scheduledStartAt,
      endAt: schedule.scheduledEndAt,
      durationMinutes: schedule.totalDurationMinutes > 0
          ? schedule.totalDurationMinutes
          : schedule.scheduledEndAt
                .difference(schedule.scheduledStartAt)
                .inMinutes,
      schedulingMode: booking.service.schedulingMode,
    ),
  ];
}

int _distinctServiceDateCount(
  List<CanonicalBookingScheduleSegmentV3> segments,
) {
  return segments
      .map((segment) => segment.serviceDateKey.trim())
      .where((key) => key.isNotEmpty)
      .toSet()
      .length;
}

String _resolvedSchedulingMode(
  CanonicalBookingDocumentV3 booking,
  List<CanonicalBookingScheduleSegmentV3> segments,
) {
  for (final segment in segments) {
    final value = segment.schedulingMode.trim();
    if (value.isNotEmpty) return value;
  }
  return booking.service.schedulingMode;
}

String _packageLabel({
  required int serviceDayCount,
  required int segmentCount,
  required String schedulingMode,
}) {
  final normalized = schedulingMode.trim().toLowerCase();
  if (serviceDayCount <= 1) {
    return switch (normalized) {
      'daycare' => 'Day care',
      'overnight' => 'Overnight session',
      'twentyfourhours' => '24-hour session',
      _ => segmentCount == 1 ? 'Service day' : '$segmentCount sessions',
    };
  }
  return switch (normalized) {
    'daycare' => '$serviceDayCount Day care sessions',
    'overnight' => '$serviceDayCount Overnight sessions',
    'twentyfourhours' => '$serviceDayCount service days',
    _ => '$serviceDayCount service days',
  };
}

String _compactScheduleSummary({
  required List<CanonicalBookingScheduleSegmentV3> effectiveSegments,
  required bool isMultiDayPackage,
  required String packageLabel,
  required String compactDateRangeLabel,
}) {
  if (effectiveSegments.isEmpty) return 'Schedule unavailable';
  if (isMultiDayPackage) {
    return '$packageLabel · $compactDateRangeLabel';
  }
  return _segmentDisplayValue(effectiveSegments.first, includeYear: true);
}

String _slotDateLabel({
  required List<CanonicalBookingScheduleSegmentV3> effectiveSegments,
  required bool isMultiDayPackage,
  required String packageLabel,
  required String compactDateRangeLabel,
}) {
  if (effectiveSegments.isEmpty) return 'Pending';
  if (isMultiDayPackage) {
    return '$packageLabel · $compactDateRangeLabel';
  }
  final segment = effectiveSegments.first;
  if (_crossesMidnight(segment)) {
    return '${_formatLongDate(segment.startAt)} - ${_formatLongDate(segment.endAt)}';
  }
  return _formatLongDate(segment.startAt);
}

String _slotTimeLabel({
  required List<CanonicalBookingScheduleSegmentV3> effectiveSegments,
  required bool isMultiDayPackage,
  required bool hasContinuousServiceWindow,
}) {
  if (effectiveSegments.isEmpty) return 'Pending';
  final first = effectiveSegments.first;
  final last = effectiveSegments.last;
  if (!isMultiDayPackage) {
    if (_crossesMidnight(first)) {
      return '${_formatTime(first.startAt)} - ${_formatTime(first.endAt)}';
    }
    return '${_formatTime(first.startAt)} - ${_formatTime(first.endAt)}';
  }
  if (hasContinuousServiceWindow) {
    return '${_formatLongDateTime(first.startAt)} - ${_formatLongDateTime(last.endAt)}';
  }
  return '${_formatTime(first.startAt)} first session';
}

List<CanonicalBookingScheduleDisplayRow> _buildPerSegmentRows(
  List<CanonicalBookingScheduleSegmentV3> segments,
) {
  if (segments.isEmpty) {
    return const <CanonicalBookingScheduleDisplayRow>[
      CanonicalBookingScheduleDisplayRow(
        label: 'Schedule',
        value: 'Schedule unavailable',
      ),
    ];
  }
  return [
    for (var index = 0; index < segments.length; index += 1)
      CanonicalBookingScheduleDisplayRow(
        label: segments.length == 1 ? 'Schedule' : 'Session ${index + 1}',
        value: _segmentDisplayValue(segments[index], includeYear: true),
      ),
  ];
}

bool _hasContinuousServiceWindow(
  List<CanonicalBookingScheduleSegmentV3> segments,
) {
  if (segments.length <= 1) return true;
  for (var index = 1; index < segments.length; index += 1) {
    if (segments[index - 1].endAt != segments[index].startAt) {
      return false;
    }
  }
  return true;
}

String _serviceDateRangeLabel(
  List<CanonicalBookingScheduleSegmentV3> segments,
) {
  if (segments.isEmpty) return 'Pending';
  final keys = segments
      .map((segment) => segment.serviceDateKey.trim())
      .where((key) => key.isNotEmpty)
      .toList(growable: false);
  if (keys.isEmpty) return _formatLongDate(segments.first.startAt);
  final first = DateTime.parse(keys.first);
  final last = DateTime.parse(keys.last);
  return _formatDateRange(first, last);
}

String _segmentDisplayValue(
  CanonicalBookingScheduleSegmentV3 segment, {
  required bool includeYear,
}) {
  if (_crossesMidnight(segment)) {
    return '${_formatLongDateTime(segment.startAt, includeYear: includeYear)} - ${_formatLongDateTime(segment.endAt, includeYear: includeYear)}';
  }
  final date = includeYear
      ? _formatLongDate(segment.startAt)
      : _formatShortDate(segment.startAt);
  return '$date · ${_formatTime(segment.startAt)} - ${_formatTime(segment.endAt)}';
}

bool _crossesMidnight(CanonicalBookingScheduleSegmentV3 segment) {
  final start = segment.startAt.toLocal();
  final end = segment.endAt.toLocal();
  return start.year != end.year ||
      start.month != end.month ||
      start.day != end.day;
}

String _resolvedServiceDateKey(
  String? serviceDateKey,
  String? dateKey,
  DateTime startAt,
) {
  final explicit = serviceDateKey?.trim() ?? '';
  if (explicit.isNotEmpty) return explicit;
  final compatibility = dateKey?.trim() ?? '';
  if (compatibility.isNotEmpty) return compatibility;
  final local = startAt.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

String _formatDateRange(DateTime start, DateTime end) {
  final sameYear = start.year == end.year;
  final sameMonth = sameYear && start.month == end.month;
  if (sameMonth && start.day == end.day) {
    return _formatLongDate(start);
  }
  if (sameMonth) {
    return '${_monthLabel(start.month)} ${start.day}-${end.day}, ${start.year}';
  }
  if (sameYear) {
    return '${_monthLabel(start.month)} ${start.day} - ${_monthLabel(end.month)} ${end.day}, ${start.year}';
  }
  return '${_monthLabel(start.month)} ${start.day}, ${start.year} - ${_monthLabel(end.month)} ${end.day}, ${end.year}';
}

String _formatLongDate(DateTime value) {
  final local = value.toLocal();
  return '${_monthLabel(local.month)} ${local.day}, ${local.year}';
}

String _formatShortDate(DateTime value) {
  final local = value.toLocal();
  return '${_monthLabel(local.month)} ${local.day}';
}

String _formatLongDateTime(DateTime value, {bool includeYear = true}) {
  final date = includeYear ? _formatLongDate(value) : _formatShortDate(value);
  return '$date, ${_formatTime(value)}';
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour;
  final minute = local.minute;
  final suffix = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$displayHour:${minute.toString().padLeft(2, '0')} $suffix';
}

String _monthLabel(int month) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return months[(month - 1).clamp(0, 11)];
}
