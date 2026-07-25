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
  emptySelection,
  duplicateSlot,
  invalidSlotRange,
  nonContiguous,
  overlapping,
  mixedService,
  mixedProvider,
  mixedTimezone,
  mixedDateKey,
  invalidSlotCount,
  invalidTotalDuration,
  invalidScheduleBounds,
  invalidUnitPrice,
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
  final DateTime startAt;
  final DateTime endAt;
  final int durationMinutes;
  final int unitPricePaise;

  const BookingSlotSegmentV3({
    required this.slotId,
    required this.serviceId,
    required this.providerId,
    required this.timezone,
    required this.dateKey,
    required this.startAt,
    required this.endAt,
    required this.durationMinutes,
    required this.unitPricePaise,
  });
}

class SlotBookingSelectionV3 {
  final BookingV3Type bookingType;
  final List<BookingSlotSegmentV3> slots;
  final int slotCount;
  final DateTime scheduledStartAt;
  final DateTime scheduledEndAt;
  final int totalDurationMinutes;

  const SlotBookingSelectionV3({
    required this.bookingType,
    required this.slots,
    required this.slotCount,
    required this.scheduledStartAt,
    required this.scheduledEndAt,
    required this.totalDurationMinutes,
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

SlotBookingValidationResult validateSlotBookingSelectionV3(
  SlotBookingSelectionV3 selection,
) {
  final issues = <SlotBookingValidationIssue>[];
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
  final seenSlotIds = <String>{};
  var totalDuration = 0;
  BookingSlotSegmentV3? previous;
  String? firstServiceId;
  String? firstProviderId;
  String? firstTimezone;
  String? firstDateKey;

  for (final slot in sorted) {
    if (seenSlotIds.contains(slot.slotId)) {
      issues.add(
        SlotBookingValidationIssue(
          code: SlotBookingValidationCode.duplicateSlot,
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
    firstDateKey ??= slot.dateKey;

    if (slot.serviceId != firstServiceId) {
      issues.add(
        SlotBookingValidationIssue(
          code: SlotBookingValidationCode.mixedService,
          message: 'All slots must belong to the same service.',
          slotId: slot.slotId,
        ),
      );
    }
    if (slot.providerId != firstProviderId) {
      issues.add(
        SlotBookingValidationIssue(
          code: SlotBookingValidationCode.mixedProvider,
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
    if (slot.dateKey != firstDateKey) {
      issues.add(
        SlotBookingValidationIssue(
          code: SlotBookingValidationCode.mixedDateKey,
          message: 'Slots cannot span multiple service date keys.',
          slotId: slot.slotId,
        ),
      );
    }

    if (previous != null) {
      if (slot.startAt.isBefore(previous.endAt)) {
        issues.add(
          SlotBookingValidationIssue(
            code: SlotBookingValidationCode.overlapping,
            message: 'Slots cannot overlap.',
            slotId: slot.slotId,
          ),
        );
      } else if (slot.startAt != previous.endAt) {
        issues.add(
          SlotBookingValidationIssue(
            code: SlotBookingValidationCode.nonContiguous,
            message: 'Slots must be exactly continuous.',
            slotId: slot.slotId,
          ),
        );
      }
    }
    previous = slot;
  }

  if (selection.slotCount != selection.slots.length) {
    issues.add(
      const SlotBookingValidationIssue(
        code: SlotBookingValidationCode.invalidSlotCount,
        message: 'slotCount must equal slots.length.',
      ),
    );
  }
  if (sorted.isNotEmpty) {
    if (selection.scheduledStartAt != sorted.first.startAt ||
        selection.scheduledEndAt != sorted.last.endAt) {
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
      slots: sorted,
      slotCount: sorted.length,
      scheduledStartAt: sorted.first.startAt,
      scheduledEndAt: sorted.last.endAt,
      totalDurationMinutes: totalDuration,
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
  final int? serviceUnitPricePaise;
  final int? durationMinutes;
  final int? pricePerNightPaise;
  final int? selectedSlotCount;
  final int? totalDurationMinutes;
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
    required this.serviceUnitPricePaise,
    required this.durationMinutes,
    required this.pricePerNightPaise,
    required this.selectedSlotCount,
    required this.totalDurationMinutes,
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
