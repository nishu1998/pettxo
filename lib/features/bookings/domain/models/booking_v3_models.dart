enum BookingV3Type { slot, range }

enum CanonicalBookingStateV3 {
  requested,
  pendingProvider,
  acceptedAwaitingPayment,
  confirmed,
  inProgress,
  completedPendingReview,
  completedFinal,
  declined,
  expired,
  paymentExpired,
  cancelledByParent,
  cancelled,
  disputed,
  serviceNotStarted,
  noShow,
}

enum BookingActorV3 { parent, provider, system, admin, paymentGateway }

enum ProviderResponseTypeV3 { accept, decline, expired }

enum SlotBookingValidationCode {
  invalidSlotSelection,
  emptySelection,
  invalidBookingType,
  duplicateSlotSelection,
  invalidSlotRange,
  nonContiguousDailySlots,
  overlappingBookingSegments,
  mixedServiceSlotSelection,
  mixedProviderSlotSelection,
  mixedTimezone,
  nonConsecutiveServiceDates,
  tooManyServiceDays,
  invalidSlotCount,
  invalidTotalDuration,
  invalidScheduleBounds,
  invalidUnitPrice,
  mixedSchedulingMode,
}

class SlotBookingValidationIssue {
  final SlotBookingValidationCode code;
  final String message;
  final String? slotId;

  const SlotBookingValidationIssue({
    required this.code,
    required this.message,
    this.slotId,
  });
}

class BookingSlotSegmentV3 {
  final String slotId;
  final String serviceId;
  final String providerId;
  final String timezone;
  final String dateKey;
  final String? serviceDateKey;
  final DateTime startAt;
  final DateTime endAt;
  final int durationMinutes;
  final int unitPricePaise;
  final String? schedulingMode;

  const BookingSlotSegmentV3({
    required this.slotId,
    required this.serviceId,
    required this.providerId,
    required this.timezone,
    required this.dateKey,
    this.serviceDateKey,
    required this.startAt,
    required this.endAt,
    required this.durationMinutes,
    required this.unitPricePaise,
    this.schedulingMode,
  });
}

class SlotBookingScheduleSegmentV3 {
  final String serviceDateKey;
  final List<String> slotIds;
  final DateTime startAt;
  final DateTime endAt;
  final int durationMinutes;
  final String schedulingMode;

  const SlotBookingScheduleSegmentV3({
    required this.serviceDateKey,
    required this.slotIds,
    required this.startAt,
    required this.endAt,
    required this.durationMinutes,
    required this.schedulingMode,
  });
}

class SlotBookingSelectionV3 {
  final BookingV3Type bookingType;
  final List<BookingSlotSegmentV3> slots;
  final int slotCount;
  final DateTime scheduledStartAt;
  final DateTime scheduledEndAt;
  final int totalDurationMinutes;
  final List<SlotBookingScheduleSegmentV3>? segments;
  final DateTime? firstSegmentEndAt;
  final DateTime? finalEndAt;
  final int? serviceDayCount;
  final int? segmentCount;

  const SlotBookingSelectionV3({
    required this.bookingType,
    required this.slots,
    required this.slotCount,
    required this.scheduledStartAt,
    required this.scheduledEndAt,
    required this.totalDurationMinutes,
    this.segments,
    this.firstSegmentEndAt,
    this.finalEndAt,
    this.serviceDayCount,
    this.segmentCount,
  });
}

class SlotBookingValidationResult {
  final bool ok;
  final SlotBookingSelectionV3? normalizedSelection;
  final List<SlotBookingValidationIssue> issues;

  const SlotBookingValidationResult({
    required this.ok,
    required this.normalizedSelection,
    required this.issues,
  });
}

String _normalizeSchedulingModeValue(String? value) => value?.trim() ?? '';

String _resolveServiceDateKey(BookingSlotSegmentV3 slot) {
  final explicit = slot.serviceDateKey?.trim() ?? '';
  if (explicit.isNotEmpty) return explicit;
  final compatibility = slot.dateKey.trim();
  if (compatibility.isNotEmpty) return compatibility;
  return slot.startAt.toUtc().toIso8601String().split('T').first;
}

int? _dateKeyOrdinal(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) return null;
  return DateTime.utc(year, month, day).millisecondsSinceEpoch ~/
      const Duration(days: 1).inMilliseconds;
}

SlotBookingValidationResult validateSlotBookingSelectionV3(
  SlotBookingSelectionV3 selection,
) {
  final issues = <SlotBookingValidationIssue>[];
  if (selection.bookingType != BookingV3Type.slot) {
    issues.add(
      const SlotBookingValidationIssue(
        code: SlotBookingValidationCode.invalidBookingType,
        message: 'Slot booking selection must use BookingV3Type.slot.',
      ),
    );
  }
  if (selection.slots.isEmpty) {
    issues.add(
      const SlotBookingValidationIssue(
        code: SlotBookingValidationCode.emptySelection,
        message: 'At least one slot is required.',
      ),
    );
  }

  final sorted = [...selection.slots]
    ..sort((a, b) => a.startAt.compareTo(b.startAt));
  final normalizedSlots = <BookingSlotSegmentV3>[];
  final seenSlotIds = <String>{};
  final groupedByServiceDate = <String, List<BookingSlotSegmentV3>>{};
  var totalDuration = 0;
  String? firstServiceId;
  String? firstProviderId;
  String? firstTimezone;
  String? firstSchedulingMode;

  for (final slot in sorted) {
    if (slot.slotId.trim().isEmpty) {
      issues.add(
        SlotBookingValidationIssue(
          code: SlotBookingValidationCode.invalidSlotSelection,
          message: 'Slot ID is required.',
          slotId: slot.slotId,
        ),
      );
    }
    if (seenSlotIds.contains(slot.slotId)) {
      issues.add(
        SlotBookingValidationIssue(
          code: SlotBookingValidationCode.duplicateSlotSelection,
          message: 'Duplicate slot IDs are invalid.',
          slotId: slot.slotId,
        ),
      );
    }
    seenSlotIds.add(slot.slotId);

    if (!slot.startAt.isBefore(slot.endAt)) {
      issues.add(
        SlotBookingValidationIssue(
          code: SlotBookingValidationCode.invalidSlotRange,
          message: 'Each slot must have startAt < endAt.',
          slotId: slot.slotId,
        ),
      );
      continue;
    }

    if (slot.unitPricePaise < 0) {
      issues.add(
        SlotBookingValidationIssue(
          code: SlotBookingValidationCode.invalidUnitPrice,
          message: 'unitPricePaise must be non-negative.',
          slotId: slot.slotId,
        ),
      );
    }

    final derivedDuration = slot.endAt.difference(slot.startAt).inMinutes;
    totalDuration += derivedDuration;
    if (slot.durationMinutes != derivedDuration) {
      issues.add(
        SlotBookingValidationIssue(
          code: SlotBookingValidationCode.invalidTotalDuration,
          message: 'durationMinutes must match the slot timestamps.',
          slotId: slot.slotId,
        ),
      );
    }

    firstServiceId ??= slot.serviceId;
    firstProviderId ??= slot.providerId;
    firstTimezone ??= slot.timezone;
    final normalizedSchedulingMode = _normalizeSchedulingModeValue(
      slot.schedulingMode,
    );
    if (firstSchedulingMode == null && normalizedSchedulingMode.isNotEmpty) {
      firstSchedulingMode = normalizedSchedulingMode;
    }

    if (slot.serviceId != firstServiceId) {
      issues.add(
        SlotBookingValidationIssue(
          code: SlotBookingValidationCode.mixedServiceSlotSelection,
          message: 'All slots must belong to the same service.',
          slotId: slot.slotId,
        ),
      );
    }
    if (slot.providerId != firstProviderId) {
      issues.add(
        SlotBookingValidationIssue(
          code: SlotBookingValidationCode.mixedProviderSlotSelection,
          message: 'All slots must belong to the same provider.',
          slotId: slot.slotId,
        ),
      );
    }
    if (slot.timezone != firstTimezone) {
      issues.add(
        SlotBookingValidationIssue(
          code: SlotBookingValidationCode.mixedTimezone,
          message: 'All slots must use the same timezone.',
          slotId: slot.slotId,
        ),
      );
    }
    if (firstSchedulingMode != null &&
        firstSchedulingMode.isNotEmpty &&
        normalizedSchedulingMode.isNotEmpty &&
        normalizedSchedulingMode != firstSchedulingMode) {
      issues.add(
        SlotBookingValidationIssue(
          code: SlotBookingValidationCode.mixedSchedulingMode,
          message: 'All slots must use the same scheduling mode.',
          slotId: slot.slotId,
        ),
      );
    }

    final serviceDateKey = _resolveServiceDateKey(slot);
    final normalizedSlot = BookingSlotSegmentV3(
      slotId: slot.slotId,
      serviceId: slot.serviceId,
      providerId: slot.providerId,
      timezone: slot.timezone,
      dateKey: serviceDateKey,
      serviceDateKey: serviceDateKey,
      startAt: slot.startAt,
      endAt: slot.endAt,
      durationMinutes: derivedDuration,
      unitPricePaise: slot.unitPricePaise,
      schedulingMode: normalizedSchedulingMode,
    );
    normalizedSlots.add(normalizedSlot);
    groupedByServiceDate.putIfAbsent(
      serviceDateKey,
      () => <BookingSlotSegmentV3>[],
    );
    groupedByServiceDate[serviceDateKey]!.add(normalizedSlot);
  }

  if (selection.slotCount != selection.slots.length) {
    issues.add(
      const SlotBookingValidationIssue(
        code: SlotBookingValidationCode.invalidSlotCount,
        message: 'slotCount must equal slots.length.',
      ),
    );
  }

  final sortedServiceDateKeys = groupedByServiceDate.keys.toList()..sort();
  if (sortedServiceDateKeys.length > 10) {
    issues.add(
      const SlotBookingValidationIssue(
        code: SlotBookingValidationCode.tooManyServiceDays,
        message:
            'A booking can include at most 10 consecutive service start dates.',
      ),
    );
  }
  for (var index = 1; index < sortedServiceDateKeys.length; index += 1) {
    final previousOrdinal = _dateKeyOrdinal(sortedServiceDateKeys[index - 1]);
    final currentOrdinal = _dateKeyOrdinal(sortedServiceDateKeys[index]);
    if (previousOrdinal == null ||
        currentOrdinal == null ||
        currentOrdinal - previousOrdinal != 1) {
      issues.add(
        const SlotBookingValidationIssue(
          code: SlotBookingValidationCode.nonConsecutiveServiceDates,
          message: 'Selected service dates must be consecutive calendar dates.',
        ),
      );
      break;
    }
  }

  final derivedSegments = <SlotBookingScheduleSegmentV3>[];
  for (final serviceDateKey in sortedServiceDateKeys) {
    final daySlots = [...groupedByServiceDate[serviceDateKey]!]
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    BookingSlotSegmentV3? previousDaySlot;
    var dayDuration = 0;
    for (final slot in daySlots) {
      dayDuration += slot.durationMinutes;
      if (previousDaySlot != null) {
        if (slot.startAt.isBefore(previousDaySlot.endAt)) {
          issues.add(
            SlotBookingValidationIssue(
              code: SlotBookingValidationCode.overlappingBookingSegments,
              message: 'Selected slots within a service day cannot overlap.',
              slotId: slot.slotId,
            ),
          );
        } else if (slot.startAt != previousDaySlot.endAt) {
          issues.add(
            SlotBookingValidationIssue(
              code: SlotBookingValidationCode.nonContiguousDailySlots,
              message:
                  'Selected slots within one service day must remain contiguous.',
              slotId: slot.slotId,
            ),
          );
        }
      }
      previousDaySlot = slot;
    }
    derivedSegments.add(
      SlotBookingScheduleSegmentV3(
        serviceDateKey: serviceDateKey,
        slotIds: daySlots.map((slot) => slot.slotId).toList(growable: false),
        startAt: daySlots.first.startAt,
        endAt: daySlots.last.endAt,
        durationMinutes: dayDuration,
        schedulingMode: _normalizeSchedulingModeValue(
          daySlots.first.schedulingMode,
        ),
      ),
    );
  }

  for (var index = 1; index < derivedSegments.length; index += 1) {
    if (derivedSegments[index].startAt.isBefore(
      derivedSegments[index - 1].endAt,
    )) {
      issues.add(
        const SlotBookingValidationIssue(
          code: SlotBookingValidationCode.overlappingBookingSegments,
          message:
              'Daily booking segments cannot overlap across service dates.',
        ),
      );
    }
  }

  if (normalizedSlots.isNotEmpty) {
    if (selection.scheduledStartAt != normalizedSlots.first.startAt ||
        selection.scheduledEndAt != normalizedSlots.last.endAt) {
      issues.add(
        const SlotBookingValidationIssue(
          code: SlotBookingValidationCode.invalidScheduleBounds,
          message:
              'scheduledStartAt and scheduledEndAt must match the slot boundaries.',
        ),
      );
    }
  }
  if (selection.totalDurationMinutes != totalDuration) {
    issues.add(
      const SlotBookingValidationIssue(
        code: SlotBookingValidationCode.invalidTotalDuration,
        message: 'totalDurationMinutes must equal the sum of slot durations.',
      ),
    );
  }
  if (selection.serviceDayCount != null &&
      selection.serviceDayCount != derivedSegments.length) {
    issues.add(
      const SlotBookingValidationIssue(
        code: SlotBookingValidationCode.invalidScheduleBounds,
        message:
            'serviceDayCount must equal the number of distinct service dates.',
      ),
    );
  }
  if (selection.segmentCount != null &&
      selection.segmentCount != derivedSegments.length) {
    issues.add(
      const SlotBookingValidationIssue(
        code: SlotBookingValidationCode.invalidScheduleBounds,
        message:
            'segmentCount must equal the number of normalized schedule segments.',
      ),
    );
  }
  if (derivedSegments.isNotEmpty) {
    if (selection.firstSegmentEndAt != null &&
        selection.firstSegmentEndAt != derivedSegments.first.endAt) {
      issues.add(
        const SlotBookingValidationIssue(
          code: SlotBookingValidationCode.invalidScheduleBounds,
          message:
              'firstSegmentEndAt must equal the first normalized segment endAt.',
        ),
      );
    }
    if (selection.finalEndAt != null &&
        selection.finalEndAt != derivedSegments.last.endAt) {
      issues.add(
        const SlotBookingValidationIssue(
          code: SlotBookingValidationCode.invalidScheduleBounds,
          message: 'finalEndAt must equal the final normalized segment endAt.',
        ),
      );
    }
  }
  if (selection.segments != null) {
    if (selection.segments!.length != derivedSegments.length) {
      issues.add(
        const SlotBookingValidationIssue(
          code: SlotBookingValidationCode.invalidScheduleBounds,
          message:
              'schedule.segments must match the normalized daily selection.',
        ),
      );
    } else {
      for (var index = 0; index < selection.segments!.length; index += 1) {
        final provided = selection.segments![index];
        final derived = derivedSegments[index];
        final sameSlotIds =
            provided.slotIds.length == derived.slotIds.length &&
            List.generate(
              provided.slotIds.length,
              (slotIndex) =>
                  provided.slotIds[slotIndex] == derived.slotIds[slotIndex],
            ).every((matches) => matches);
        if (provided.serviceDateKey != derived.serviceDateKey ||
            !sameSlotIds ||
            provided.startAt != derived.startAt ||
            provided.endAt != derived.endAt ||
            provided.durationMinutes != derived.durationMinutes ||
            _normalizeSchedulingModeValue(provided.schedulingMode) !=
                _normalizeSchedulingModeValue(derived.schedulingMode)) {
          issues.add(
            const SlotBookingValidationIssue(
              code: SlotBookingValidationCode.invalidScheduleBounds,
              message:
                  'schedule.segments must match the authoritative normalized daily segments.',
            ),
          );
          break;
        }
      }
    }
  }

  if (issues.isNotEmpty) {
    return SlotBookingValidationResult(
      ok: false,
      normalizedSelection: null,
      issues: issues,
    );
  }

  return SlotBookingValidationResult(
    ok: true,
    normalizedSelection: SlotBookingSelectionV3(
      bookingType: BookingV3Type.slot,
      slots: normalizedSlots,
      slotCount: normalizedSlots.length,
      scheduledStartAt: normalizedSlots.first.startAt,
      scheduledEndAt: normalizedSlots.last.endAt,
      totalDurationMinutes: totalDuration,
      segments: derivedSegments,
      firstSegmentEndAt: derivedSegments.first.endAt,
      finalEndAt: derivedSegments.last.endAt,
      serviceDayCount: derivedSegments.length,
      segmentCount: derivedSegments.length,
    ),
    issues: const [],
  );
}

class RangeBookingSelectionV3 {
  final BookingV3Type bookingType;
  final DateTime checkInDateTime;
  final DateTime checkOutDateTime;
  final int nights;
  final int pricePerNightPaise;
  final String timezone;
  final int? petQuantity;
  final int? maxConcurrentPetsSnapshot;

  const RangeBookingSelectionV3({
    required this.bookingType,
    required this.checkInDateTime,
    required this.checkOutDateTime,
    required this.nights,
    required this.pricePerNightPaise,
    required this.timezone,
    this.petQuantity,
    this.maxConcurrentPetsSnapshot,
  });
}

enum RangeBookingValidationCode {
  invalidBookingType,
  missingDates,
  invalidDateOrder,
  invalidNightCount,
  invalidPricePerNight,
  invalidPetQuantity,
  invalidCapacity,
}

class RangeBookingValidationIssue {
  final RangeBookingValidationCode code;
  final String message;

  const RangeBookingValidationIssue({
    required this.code,
    required this.message,
  });
}

class RangeBookingValidationResult {
  final bool ok;
  final List<RangeBookingValidationIssue> issues;

  const RangeBookingValidationResult({required this.ok, required this.issues});
}

RangeBookingValidationResult validateRangeBookingSelectionV3(
  RangeBookingSelectionV3 selection,
) {
  final issues = <RangeBookingValidationIssue>[];
  if (selection.bookingType != BookingV3Type.range) {
    issues.add(
      const RangeBookingValidationIssue(
        code: RangeBookingValidationCode.invalidBookingType,
        message: 'Range booking selection must use BookingV3Type.range.',
      ),
    );
  }
  if (!selection.checkOutDateTime.isAfter(selection.checkInDateTime)) {
    issues.add(
      const RangeBookingValidationIssue(
        code: RangeBookingValidationCode.invalidDateOrder,
        message: 'checkOutDateTime must be after checkInDateTime.',
      ),
    );
  }
  if (selection.nights <= 0) {
    issues.add(
      const RangeBookingValidationIssue(
        code: RangeBookingValidationCode.invalidNightCount,
        message: 'nights must be greater than zero.',
      ),
    );
  }
  if (selection.pricePerNightPaise <= 0) {
    issues.add(
      const RangeBookingValidationIssue(
        code: RangeBookingValidationCode.invalidPricePerNight,
        message: 'pricePerNightPaise must be greater than zero.',
      ),
    );
  }
  if (selection.petQuantity != null && selection.petQuantity! <= 0) {
    issues.add(
      const RangeBookingValidationIssue(
        code: RangeBookingValidationCode.invalidPetQuantity,
        message: 'petQuantity must be greater than zero when provided.',
      ),
    );
  }
  if (selection.maxConcurrentPetsSnapshot != null &&
      selection.maxConcurrentPetsSnapshot! <= 0) {
    issues.add(
      const RangeBookingValidationIssue(
        code: RangeBookingValidationCode.invalidCapacity,
        message:
            'maxConcurrentPetsSnapshot must be greater than zero when provided.',
      ),
    );
  }
  return RangeBookingValidationResult(ok: issues.isEmpty, issues: issues);
}

class BookingServiceSnapshotV3 {
  final String serviceId;
  final String providerId;
  final String serviceTitle;
  final String animalType;
  final String category;
  final BookingV3Type bookingType;
  final String timezone;
  final String schedulingMode;
  final int? serviceUnitPricePaise;
  final int? durationMinutes;
  final int? pricePerNightPaise;
  final int? selectedSlotCount;
  final int? totalDurationMinutes;
  final int? selectedServiceDayCount;
  final int? scheduleSegmentCount;
  final DateTime? checkInDateTime;
  final DateTime? checkOutDateTime;
  final int capacitySnapshot;
  final String serviceLocationType;
  final String currency;
  final int snapshotVersion;

  const BookingServiceSnapshotV3({
    required this.serviceId,
    required this.providerId,
    required this.serviceTitle,
    required this.animalType,
    required this.category,
    required this.bookingType,
    required this.timezone,
    required this.schedulingMode,
    required this.serviceUnitPricePaise,
    required this.durationMinutes,
    required this.pricePerNightPaise,
    required this.selectedSlotCount,
    required this.totalDurationMinutes,
    this.selectedServiceDayCount,
    this.scheduleSegmentCount,
    required this.checkInDateTime,
    required this.checkOutDateTime,
    required this.capacitySnapshot,
    required this.serviceLocationType,
    required this.currency,
    required this.snapshotVersion,
  });
}

class BookingFinancialSnapshotV3 {
  final String currency;
  final int serviceSubtotalPaise;
  final int couponDiscountPaise;
  final int customerPaidPaise;
  final int platformCommissionRateBasisPoints;
  final int platformCommissionPaise;
  final int providerPayoutPaise;
  final int pettxoCouponFundingPaise;
  final int gatewayFeeSunkPaise;
  final int providerFaultCostPaise;
  final int refundAmountPaise;
  final int pettxoNetBeforeGatewayPaise;
  final int pricingVersion;

  const BookingFinancialSnapshotV3({
    required this.currency,
    required this.serviceSubtotalPaise,
    required this.couponDiscountPaise,
    required this.customerPaidPaise,
    required this.platformCommissionRateBasisPoints,
    required this.platformCommissionPaise,
    required this.providerPayoutPaise,
    required this.pettxoCouponFundingPaise,
    required this.gatewayFeeSunkPaise,
    required this.providerFaultCostPaise,
    required this.refundAmountPaise,
    required this.pettxoNetBeforeGatewayPaise,
    required this.pricingVersion,
  });

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  factory BookingFinancialSnapshotV3.fromMap(Map<String, dynamic> map) {
    int requireInt(String key) {
      final value = _readInt(map[key]);
      if (value == null) {
        throw FormatException('Expected integer for $key');
      }
      return value;
    }

    final currency = (map['currency'] as String? ?? '').trim();
    if (currency.isEmpty) {
      throw const FormatException('Expected non-empty currency');
    }

    return BookingFinancialSnapshotV3(
      currency: currency,
      serviceSubtotalPaise: requireInt('serviceSubtotalPaise'),
      couponDiscountPaise: requireInt('couponDiscountPaise'),
      customerPaidPaise: requireInt('customerPaidPaise'),
      platformCommissionRateBasisPoints: requireInt(
        'platformCommissionRateBasisPoints',
      ),
      platformCommissionPaise: requireInt('platformCommissionPaise'),
      providerPayoutPaise: requireInt('providerPayoutPaise'),
      pettxoCouponFundingPaise: requireInt('pettxoCouponFundingPaise'),
      gatewayFeeSunkPaise: requireInt('gatewayFeeSunkPaise'),
      providerFaultCostPaise: requireInt('providerFaultCostPaise'),
      refundAmountPaise: requireInt('refundAmountPaise'),
      pettxoNetBeforeGatewayPaise: requireInt('pettxoNetBeforeGatewayPaise'),
      pricingVersion: requireInt('pricingVersion'),
    );
  }

  static BookingFinancialSnapshotV3? tryParse(Map<String, dynamic> map) {
    try {
      return BookingFinancialSnapshotV3.fromMap(map);
    } on FormatException {
      return null;
    }
  }
}
