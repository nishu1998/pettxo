import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/utils/service_duration.dart';
import 'booking_v3_models.dart';

const int canonicalBookingSchemaVersion = 3;
const String canonicalBookingModelVersion = '3.2';
const String canonicalBookingDocumentFormat = 'canonical_v3';
const String canonicalBookingPrivateDocumentFormat = 'canonical_v3_private';
const int canonicalBookingPrivacyVersion = 1;

enum CanonicalBookingValidationSeverity { error }

class CanonicalBookingValidationIssue {
  final String code;
  final String message;
  final String path;
  final CanonicalBookingValidationSeverity severity;

  const CanonicalBookingValidationIssue({
    required this.code,
    required this.message,
    required this.path,
    this.severity = CanonicalBookingValidationSeverity.error,
  });
}

class CanonicalPublicParentParticipantV3 {
  final String parentId;
  final String displayFirstName;
  final String lastInitial;
  final String photoUrl;
  final int completedBookingCount;
  final double rating;

  const CanonicalPublicParentParticipantV3({
    required this.parentId,
    required this.displayFirstName,
    required this.lastInitial,
    required this.photoUrl,
    required this.completedBookingCount,
    required this.rating,
  });
}

class CanonicalPublicProviderParticipantV3 {
  final String providerId;
  final String displayName;
  final String username;
  final String photoUrl;
  final int completedBookingCount;
  final double rating;

  const CanonicalPublicProviderParticipantV3({
    required this.providerId,
    required this.displayName,
    required this.username,
    required this.photoUrl,
    required this.completedBookingCount,
    required this.rating,
  });
}

class CanonicalBookingParticipantsV3 {
  final CanonicalPublicParentParticipantV3 parent;
  final CanonicalPublicProviderParticipantV3 provider;

  const CanonicalBookingParticipantsV3({
    required this.parent,
    required this.provider,
  });
}

class CanonicalBookingSlotSegmentV3 {
  final String slotId;
  final String dateKey;
  final DateTime startAt;
  final DateTime endAt;
  final int durationMinutes;
  final int unitPricePaise;
  final String serviceId;
  final String providerId;
  final String timezone;

  const CanonicalBookingSlotSegmentV3({
    required this.slotId,
    required this.dateKey,
    required this.startAt,
    required this.endAt,
    required this.durationMinutes,
    required this.unitPricePaise,
    required this.serviceId,
    required this.providerId,
    required this.timezone,
  });

  BookingSlotSegmentV3 toDomainSegment() {
    return BookingSlotSegmentV3(
      slotId: slotId,
      serviceId: serviceId,
      providerId: providerId,
      timezone: timezone,
      dateKey: dateKey,
      startAt: startAt,
      endAt: endAt,
      durationMinutes: durationMinutes,
      unitPricePaise: unitPricePaise,
    );
  }
}

abstract class CanonicalBookingScheduleV3 {
  final BookingV3Type bookingType;
  final DateTime serviceAnchorAt;
  final String timezone;

  const CanonicalBookingScheduleV3({
    required this.bookingType,
    required this.serviceAnchorAt,
    required this.timezone,
  });
}

class CanonicalSlotBookingScheduleV3 extends CanonicalBookingScheduleV3 {
  final List<CanonicalBookingSlotSegmentV3> slots;
  final int slotCount;
  final DateTime scheduledStartAt;
  final DateTime scheduledEndAt;
  final int totalDurationMinutes;

  const CanonicalSlotBookingScheduleV3({
    required super.serviceAnchorAt,
    required super.timezone,
    required this.slots,
    required this.slotCount,
    required this.scheduledStartAt,
    required this.scheduledEndAt,
    required this.totalDurationMinutes,
  }) : super(bookingType: BookingV3Type.slot);
}

class CanonicalRangeBookingScheduleV3 extends CanonicalBookingScheduleV3 {
  final DateTime checkInDateTime;
  final DateTime checkOutDateTime;
  final int nights;
  final int? minNightsSnapshot;
  final int? maxNightsSnapshot;
  final int? maxConcurrentPetsSnapshot;
  final int? petQuantity;

  const CanonicalRangeBookingScheduleV3({
    required super.serviceAnchorAt,
    required super.timezone,
    required this.checkInDateTime,
    required this.checkOutDateTime,
    required this.nights,
    required this.minNightsSnapshot,
    required this.maxNightsSnapshot,
    required this.maxConcurrentPetsSnapshot,
    required this.petQuantity,
  }) : super(bookingType: BookingV3Type.range);
}

class CanonicalBookingLifecycleV3 {
  final DateTime? requestedAt;
  final DateTime? timerStartsAt;
  final bool wasQueuedOutsideWorkingHours;
  final DateTime? notifiedAt;
  final DateTime? acceptDeadlineAt;
  final DateTime? viewedByProviderAt;
  final DateTime? respondedAt;
  final ProviderResponseTypeV3? providerResponseType;
  final int? responseSeconds;
  final DateTime? payDeadlineAt;
  final DateTime? paymentStartedAt;
  final DateTime? paidAt;
  final int? paymentSeconds;
  final DateTime? otpGeneratedAt;
  final DateTime? otpEnteredAt;
  final DateTime? noShowAt;
  final DateTime? serviceEndedAt;
  final DateTime? disputeDeadlineAt;
  final DateTime? completedAt;
  final DateTime? reviewWindowEndsAt;
  final DateTime? finalizedAt;
  final DateTime? cancelledAt;

  const CanonicalBookingLifecycleV3({
    required this.requestedAt,
    required this.timerStartsAt,
    required this.wasQueuedOutsideWorkingHours,
    required this.notifiedAt,
    required this.acceptDeadlineAt,
    required this.viewedByProviderAt,
    required this.respondedAt,
    required this.providerResponseType,
    required this.responseSeconds,
    required this.payDeadlineAt,
    required this.paymentStartedAt,
    required this.paidAt,
    required this.paymentSeconds,
    required this.otpGeneratedAt,
    required this.otpEnteredAt,
    required this.noShowAt,
    required this.serviceEndedAt,
    required this.disputeDeadlineAt,
    required this.completedAt,
    required this.reviewWindowEndsAt,
    required this.finalizedAt,
    required this.cancelledAt,
  });
}

class CanonicalBookingPaymentV3 {
  final String status;
  final String razorpayOrderId;
  final String razorpayPaymentId;
  final String razorpayRefundId;
  final String paymentAttemptId;
  final DateTime? orderCreatedAt;
  final DateTime? paymentStartedAt;
  final DateTime? capturedAt;
  final DateTime? verifiedAt;
  final String verificationSource;
  final List<String> webhookEventIds;
  final String failureCode;
  final String failureMessage;

  const CanonicalBookingPaymentV3({
    required this.status,
    required this.razorpayOrderId,
    required this.razorpayPaymentId,
    required this.razorpayRefundId,
    required this.paymentAttemptId,
    required this.orderCreatedAt,
    required this.paymentStartedAt,
    required this.capturedAt,
    required this.verifiedAt,
    required this.verificationSource,
    required this.webhookEventIds,
    required this.failureCode,
    required this.failureMessage,
  });
}

class CanonicalBookingPrivacyV3 {
  final bool isPaidContactUnlocked;
  final DateTime? contactUnlockedAt;
  final DateTime? chatUnlockedAt;
  final bool otpVisibleToParent;
  final bool exactAddressUnlocked;
  final int privacyVersion;
  final String privateParticipantsRefPath;

  const CanonicalBookingPrivacyV3({
    required this.isPaidContactUnlocked,
    required this.contactUnlockedAt,
    required this.chatUnlockedAt,
    required this.otpVisibleToParent,
    required this.exactAddressUnlocked,
    required this.privacyVersion,
    required this.privateParticipantsRefPath,
  });
}

class CanonicalBookingCancellationV3 {
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String cancelReasonCode;
  final String cancelReasonText;
  final int? hoursBeforeServiceAtCancel;
  final String refundBand;
  final int? refundBasisPoints;
  final int refundAmountPaise;
  final int providerCompensationPaise;
  final int pettxoRetainedPaise;
  final String? cancellationType;

  const CanonicalBookingCancellationV3({
    required this.cancelledAt,
    required this.cancelledBy,
    required this.cancelReasonCode,
    required this.cancelReasonText,
    required this.hoursBeforeServiceAtCancel,
    required this.refundBand,
    required this.refundBasisPoints,
    required this.refundAmountPaise,
    required this.providerCompensationPaise,
    required this.pettxoRetainedPaise,
    required this.cancellationType,
  });
}

class CanonicalBookingDisputeV3 {
  final String disputeId;
  final String status;
  final DateTime? raisedAt;
  final String? raisedBy;
  final String reasonCode;
  final String description;
  final List<String> evidenceRefs;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String resolution;
  final int resolutionVersion;
  final String financialAdjustmentId;
  final String refundInstructionId;
  final int customerRefundPaise;
  final int providerReleasePaise;

  const CanonicalBookingDisputeV3({
    required this.disputeId,
    required this.status,
    required this.raisedAt,
    required this.raisedBy,
    required this.reasonCode,
    required this.description,
    required this.evidenceRefs,
    required this.resolvedAt,
    required this.resolvedBy,
    required this.resolution,
    required this.resolutionVersion,
    required this.financialAdjustmentId,
    required this.refundInstructionId,
    required this.customerRefundPaise,
    required this.providerReleasePaise,
  });
}

class CanonicalBookingReviewV3 {
  final String status;
  final String reviewId;
  final DateTime? submittedAt;

  const CanonicalBookingReviewV3({
    required this.status,
    required this.reviewId,
    required this.submittedAt,
  });

  bool get isSubmitted =>
      reviewId.trim().isNotEmpty || status.trim().toLowerCase() == 'submitted';
}

class CanonicalBookingPayoutV3 {
  final String status;
  final String holdReason;
  final DateTime? eligibleAt;
  final DateTime? readyAt;
  final DateTime? processingAt;
  final DateTime? releasedAt;
  final DateTime? failedAt;
  final int providerPayoutPaise;
  final int priorPaidPaise;
  final int remainingPayablePaise;
  final String payoutReference;
  final String externalTransactionId;
  final String failureCode;
  final int retryCount;

  const CanonicalBookingPayoutV3({
    required this.status,
    required this.holdReason,
    required this.eligibleAt,
    required this.readyAt,
    required this.processingAt,
    required this.releasedAt,
    required this.failedAt,
    required this.providerPayoutPaise,
    required this.priorPaidPaise,
    required this.remainingPayablePaise,
    required this.payoutReference,
    required this.externalTransactionId,
    required this.failureCode,
    required this.retryCount,
  });
}

class CanonicalBookingStatisticsV3 {
  final int? selectedSlotCount;
  final int? totalDurationMinutes;
  final int? nights;

  const CanonicalBookingStatisticsV3({
    required this.selectedSlotCount,
    required this.totalDurationMinutes,
    required this.nights,
  });
}

class CanonicalBookingAuditV3 {
  final BookingActorV3 createdBy;
  final BookingActorV3 lastUpdatedBy;
  final String source;

  const CanonicalBookingAuditV3({
    required this.createdBy,
    required this.lastUpdatedBy,
    required this.source,
  });
}

class CanonicalBookingPrivateParticipantsDocumentV3 {
  final int schemaVersion;
  final String bookingModelVersion;
  final String documentFormat;
  final String bookingId;
  final String parentId;
  final String providerId;
  final bool unlockedAfterPaidOnly;
  final String fullName;
  final String phoneNumber;
  final String email;
  final String exactAddress;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CanonicalBookingPrivateParticipantsDocumentV3({
    required this.schemaVersion,
    required this.bookingModelVersion,
    required this.documentFormat,
    required this.bookingId,
    required this.parentId,
    required this.providerId,
    required this.unlockedAfterPaidOnly,
    required this.fullName,
    required this.phoneNumber,
    required this.email,
    required this.exactAddress,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    required this.updatedAt,
  });
}

class CanonicalBookingDocumentV3 {
  final int schemaVersion;
  final String bookingModelVersion;
  final String documentFormat;
  final BookingV3Type bookingType;
  final CanonicalBookingStateV3 state;
  final CanonicalBookingParticipantsV3 participants;
  final BookingServiceSnapshotV3 service;
  final CanonicalBookingScheduleV3 schedule;
  final CanonicalBookingLifecycleV3 lifecycle;
  final CanonicalBookingPaymentV3 payment;
  final BookingFinancialSnapshotV3? financials;
  final CanonicalBookingPrivacyV3 privacy;
  final CanonicalBookingCancellationV3 cancellation;
  final CanonicalBookingDisputeV3 dispute;
  final CanonicalBookingReviewV3 review;
  final CanonicalBookingPayoutV3 payout;
  final CanonicalBookingStatisticsV3 statistics;
  final CanonicalBookingAuditV3 audit;
  final String parentId;
  final String providerId;
  final String serviceId;
  final CanonicalBookingStateV3 stateQueryValue;
  final BookingV3Type bookingTypeQueryValue;
  final DateTime serviceAnchorAt;
  final DateTime? scheduledStartAt;
  final DateTime? checkInDateTime;
  final DateTime? acceptDeadlineAt;
  final DateTime? payDeadlineAt;
  final DateTime? completedAt;
  final String customerId;
  final String serviceOwnerId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CanonicalBookingDocumentV3({
    required this.schemaVersion,
    required this.bookingModelVersion,
    required this.documentFormat,
    required this.bookingType,
    required this.state,
    required this.participants,
    required this.service,
    required this.schedule,
    required this.lifecycle,
    required this.payment,
    required this.financials,
    required this.privacy,
    required this.cancellation,
    required this.dispute,
    this.review = const CanonicalBookingReviewV3(
      status: '',
      reviewId: '',
      submittedAt: null,
    ),
    required this.payout,
    required this.statistics,
    required this.audit,
    required this.parentId,
    required this.providerId,
    required this.serviceId,
    required this.stateQueryValue,
    required this.bookingTypeQueryValue,
    required this.serviceAnchorAt,
    required this.scheduledStartAt,
    required this.checkInDateTime,
    required this.acceptDeadlineAt,
    required this.payDeadlineAt,
    required this.completedAt,
    required this.customerId,
    required this.serviceOwnerId,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isSlotBooking => bookingType == BookingV3Type.slot;
  bool get isRangeBooking => bookingType == BookingV3Type.range;
  bool get hasSubmittedReview => review.isSubmitted;
}

class CanonicalBookingDocumentParseResult {
  final CanonicalBookingDocumentV3? booking;
  final List<CanonicalBookingValidationIssue> issues;

  const CanonicalBookingDocumentParseResult._({
    required this.booking,
    required this.issues,
  });

  factory CanonicalBookingDocumentParseResult.success(
    CanonicalBookingDocumentV3 booking,
  ) {
    return CanonicalBookingDocumentParseResult._(
      booking: booking,
      issues: const [],
    );
  }

  factory CanonicalBookingDocumentParseResult.failure(
    List<CanonicalBookingValidationIssue> issues,
  ) {
    return CanonicalBookingDocumentParseResult._(booking: null, issues: issues);
  }

  bool get isValid => booking != null && issues.isEmpty;
}

class _CanonicalBookingDocumentParser {
  final Map<String, dynamic> raw;
  final List<CanonicalBookingValidationIssue> issues = [];

  _CanonicalBookingDocumentParser(this.raw);

  CanonicalBookingDocumentParseResult parse() {
    final schemaVersion = _readInt(raw['schemaVersion']);
    final bookingModelVersion = _readString(raw['bookingModelVersion']);
    final documentFormat = _readString(raw['documentFormat']);

    if (schemaVersion != canonicalBookingSchemaVersion) {
      _addIssue(
        'INVALID_SCHEMA_VERSION',
        'Expected schemaVersion == $canonicalBookingSchemaVersion.',
        'schemaVersion',
      );
    }
    if (bookingModelVersion != canonicalBookingModelVersion) {
      _addIssue(
        'INVALID_BOOKING_MODEL_VERSION',
        'Expected bookingModelVersion == "$canonicalBookingModelVersion".',
        'bookingModelVersion',
      );
    }
    if (documentFormat != canonicalBookingDocumentFormat) {
      _addIssue(
        'INVALID_DOCUMENT_FORMAT',
        'Expected documentFormat == "$canonicalBookingDocumentFormat".',
        'documentFormat',
      );
    }

    final bookingType = _parseBookingType(raw['bookingType'], 'bookingType');
    final state = _parseState(raw['state'], 'state');
    final participants = _parseParticipants(_readMap(raw['participants']));
    final service = _parseService(_readMap(raw['service']));
    final schedule = _parseSchedule(
      bookingType,
      _readMap(raw['schedule']),
      service?.serviceId ?? '',
      service?.providerId ?? '',
    );
    var lifecycle = _parseLifecycle(_readMap(raw['lifecycle']));
    final payment = _parsePayment(_readMap(raw['payment']));
    final financials = _parseFinancials(raw['financials']);
    final privacy = _parsePrivacy(_readMap(raw['privacy']));
    final cancellation = _parseCancellation(_readMap(raw['cancellation']));
    final dispute = _parseDispute(_readMap(raw['dispute']));
    final payout = _parsePayout(_readMap(raw['payout']));
    final statistics = _parseStatistics(_readMap(raw['statistics']));
    final audit = _parseAudit(_readMap(raw['audit']));
    final parentId = _readString(raw['parentId']);
    final providerId = _readString(raw['providerId']);
    final serviceId = _readString(raw['serviceId']);
    final stateQueryValue = _parseState(
      raw['stateQueryValue'],
      'stateQueryValue',
    );
    final bookingTypeQueryValue = _parseBookingType(
      raw['bookingTypeQueryValue'],
      'bookingTypeQueryValue',
    );
    final serviceAnchorAt = _readDate(
      raw['serviceAnchorAt'],
      'serviceAnchorAt',
      required: true,
    );
    final scheduledStartAt = _readDate(
      raw['scheduledStartAt'],
      'scheduledStartAt',
    );
    final checkInDateTime = _readDate(
      raw['checkInDateTime'],
      'checkInDateTime',
    );
    final acceptDeadlineAt = _readDate(
      raw['acceptDeadlineAt'],
      'acceptDeadlineAt',
    );
    final payDeadlineAt = _readDate(raw['payDeadlineAt'], 'payDeadlineAt');
    final completedAt = _readDate(raw['completedAt'], 'completedAt');
    final customerId = _readString(raw['customerId']);
    final serviceOwnerId = _readString(raw['serviceOwnerId']);
    final createdAt = _readDate(raw['createdAt'], 'createdAt', required: true);
    final updatedAt = _readDate(raw['updatedAt'], 'updatedAt', required: true);

    if (bookingType == null ||
        state == null ||
        participants == null ||
        service == null ||
        schedule == null ||
        lifecycle == null ||
        payment == null ||
        privacy == null ||
        cancellation == null ||
        dispute == null ||
        payout == null ||
        statistics == null ||
        audit == null ||
        stateQueryValue == null ||
        bookingTypeQueryValue == null ||
        serviceAnchorAt == null ||
        createdAt == null ||
        updatedAt == null) {
      return CanonicalBookingDocumentParseResult.failure(
        List<CanonicalBookingValidationIssue>.unmodifiable(issues),
      );
    }

    lifecycle = _applyLegacyCompletedLifecycleFallback(
      raw: raw,
      state: state,
      lifecycle: lifecycle,
    );

    if (parentId.isEmpty ||
        providerId.isEmpty ||
        serviceId.isEmpty ||
        customerId.isEmpty ||
        serviceOwnerId.isEmpty) {
      if (parentId.isEmpty) {
        _addIssue(
          'MISSING_REQUIRED_FIELD',
          'parentId is required.',
          'parentId',
        );
      }
      if (providerId.isEmpty) {
        _addIssue(
          'MISSING_REQUIRED_FIELD',
          'providerId is required.',
          'providerId',
        );
      }
      if (serviceId.isEmpty) {
        _addIssue(
          'MISSING_REQUIRED_FIELD',
          'serviceId is required.',
          'serviceId',
        );
      }
      if (customerId.isEmpty) {
        _addIssue(
          'MISSING_REQUIRED_FIELD',
          'customerId compatibility field is required.',
          'customerId',
        );
      }
      if (serviceOwnerId.isEmpty) {
        _addIssue(
          'MISSING_REQUIRED_FIELD',
          'serviceOwnerId compatibility field is required.',
          'serviceOwnerId',
        );
      }
    }

    _validateLifecycle(lifecycle, payment, financials);
    _validateTopLevelConsistency(
      bookingType: bookingType,
      state: state,
      participants: participants,
      service: service,
      schedule: schedule,
      lifecycle: lifecycle,
      parentId: parentId,
      providerId: providerId,
      serviceId: serviceId,
      stateQueryValue: stateQueryValue,
      bookingTypeQueryValue: bookingTypeQueryValue,
      serviceAnchorAt: serviceAnchorAt,
      scheduledStartAt: scheduledStartAt,
      checkInDateTime: checkInDateTime,
      acceptDeadlineAt: acceptDeadlineAt,
      payDeadlineAt: payDeadlineAt,
      completedAt: completedAt,
      customerId: customerId,
      serviceOwnerId: serviceOwnerId,
    );

    if (issues.isNotEmpty) {
      return CanonicalBookingDocumentParseResult.failure(
        List<CanonicalBookingValidationIssue>.unmodifiable(issues),
      );
    }

    return CanonicalBookingDocumentParseResult.success(
      CanonicalBookingDocumentV3(
        schemaVersion: schemaVersion ?? canonicalBookingSchemaVersion,
        bookingModelVersion: bookingModelVersion,
        documentFormat: documentFormat,
        bookingType: bookingType,
        state: state,
        participants: participants,
        service: service,
        schedule: schedule,
        lifecycle: lifecycle,
        payment: payment,
        financials: financials,
        privacy: privacy,
        cancellation: cancellation,
        dispute: dispute,
        review: _parseReview(raw),
        payout: payout,
        statistics: statistics,
        audit: audit,
        parentId: parentId,
        providerId: providerId,
        serviceId: serviceId,
        stateQueryValue: stateQueryValue,
        bookingTypeQueryValue: bookingTypeQueryValue,
        serviceAnchorAt: serviceAnchorAt,
        scheduledStartAt: scheduledStartAt,
        checkInDateTime: checkInDateTime,
        acceptDeadlineAt: acceptDeadlineAt,
        payDeadlineAt: payDeadlineAt,
        completedAt: completedAt,
        customerId: customerId,
        serviceOwnerId: serviceOwnerId,
        createdAt: createdAt,
        updatedAt: updatedAt,
      ),
    );
  }

  CanonicalBookingParticipantsV3? _parseParticipants(Map<String, dynamic> map) {
    final parentMap = _readMap(map['parent']);
    final providerMap = _readMap(map['provider']);
    final parent = _parseParent(parentMap);
    final provider = _parseProvider(providerMap);
    if (parent == null || provider == null) return null;
    return CanonicalBookingParticipantsV3(parent: parent, provider: provider);
  }

  CanonicalPublicParentParticipantV3? _parseParent(Map<String, dynamic> map) {
    const restrictedKeys = <String>{
      'fullName',
      'phoneNumber',
      'email',
      'exactAddress',
      'latitude',
      'longitude',
      'username',
      'profileRoute',
    };
    for (final key in restrictedKeys) {
      final value = map[key];
      if (value != null &&
          (value is! String || value.trim().isNotEmpty) &&
          value != false) {
        _addIssue(
          'PREPAYMENT_PRIVATE_FIELD',
          'Public parent snapshot must not include $key.',
          'participants.parent.$key',
        );
      }
    }

    final parentId = _readString(map['parentId']);
    final displayFirstName = _readString(map['displayFirstName']);
    final lastInitial = _readString(map['lastInitial']);
    if (parentId.isEmpty || displayFirstName.isEmpty || lastInitial.isEmpty) {
      _addIssue(
        'MISSING_REQUIRED_FIELD',
        'participants.parent requires parentId, displayFirstName, and lastInitial.',
        'participants.parent',
      );
      return null;
    }

    return CanonicalPublicParentParticipantV3(
      parentId: parentId,
      displayFirstName: displayFirstName,
      lastInitial: lastInitial,
      photoUrl: _readString(map['photoUrl']),
      completedBookingCount: _readInt(map['completedBookingCount']) ?? 0,
      rating: _readDouble(map['rating']) ?? 0,
    );
  }

  CanonicalPublicProviderParticipantV3? _parseProvider(
    Map<String, dynamic> map,
  ) {
    final providerId = _readString(map['providerId']);
    final displayName = _readString(map['displayName']);
    final username = _readString(map['username']);
    if (providerId.isEmpty || displayName.isEmpty) {
      _addIssue(
        'MISSING_REQUIRED_FIELD',
        'participants.provider requires providerId and displayName.',
        'participants.provider',
      );
      return null;
    }

    return CanonicalPublicProviderParticipantV3(
      providerId: providerId,
      displayName: displayName,
      username: username,
      photoUrl: _readString(map['photoUrl']),
      completedBookingCount: _readInt(map['completedBookingCount']) ?? 0,
      rating: _readDouble(map['rating']) ?? 0,
    );
  }

  BookingServiceSnapshotV3? _parseService(Map<String, dynamic> map) {
    try {
      return BookingServiceSnapshotV3(
        serviceId: _requiredString(map['serviceId'], 'service.serviceId'),
        providerId: _requiredString(map['providerId'], 'service.providerId'),
        serviceTitle: _requiredString(
          map['serviceTitle'],
          'service.serviceTitle',
        ),
        animalType: _requiredString(map['animalType'], 'service.animalType'),
        category: _requiredString(map['category'], 'service.category'),
        bookingType:
            _parseBookingType(map['bookingType'], 'service.bookingType') ??
            BookingV3Type.slot,
        timezone: _requiredString(map['timezone'], 'service.timezone'),
        schedulingMode: normalizeServiceSchedulingMode(
          _readString(map['schedulingMode']),
          sessionDurationMinutes: _readInt(map['durationMinutes']),
        ),
        serviceUnitPricePaise: _readInt(map['serviceUnitPricePaise']),
        durationMinutes: _readInt(map['durationMinutes']),
        pricePerNightPaise: _readInt(map['pricePerNightPaise']),
        selectedSlotCount: _readInt(map['selectedSlotCount']),
        totalDurationMinutes: _readInt(map['totalDurationMinutes']),
        checkInDateTime: _readDate(
          map['checkInDateTime'],
          'service.checkInDateTime',
        ),
        checkOutDateTime: _readDate(
          map['checkOutDateTime'],
          'service.checkOutDateTime',
        ),
        capacitySnapshot: _readInt(map['capacitySnapshot']) ?? 0,
        serviceLocationType: _requiredString(
          map['serviceLocationType'],
          'service.serviceLocationType',
        ),
        currency: _requiredString(map['currency'], 'service.currency'),
        snapshotVersion: _readInt(map['snapshotVersion']) ?? 1,
      );
    } on FormatException {
      return null;
    }
  }

  CanonicalBookingScheduleV3? _parseSchedule(
    BookingV3Type? bookingType,
    Map<String, dynamic> map,
    String serviceId,
    String providerId,
  ) {
    final scheduleType = _parseBookingType(
      map['bookingType'],
      'schedule.bookingType',
    );
    if (bookingType == null ||
        scheduleType == null ||
        bookingType != scheduleType) {
      _addIssue(
        'BOOKING_TYPE_MISMATCH',
        'schedule.bookingType must match bookingType.',
        'schedule.bookingType',
      );
      return null;
    }

    final serviceAnchorAt = _readDate(
      map['serviceAnchorAt'],
      'schedule.serviceAnchorAt',
      required: true,
    );
    final timezone = _requiredString(map['timezone'], 'schedule.timezone');
    if (serviceAnchorAt == null) return null;

    if (scheduleType == BookingV3Type.slot) {
      final slotMaps = _readListOfMaps(map['slots']);
      final slots = slotMaps
          .map(
            (slot) => CanonicalBookingSlotSegmentV3(
              slotId: _requiredString(slot['slotId'], 'schedule.slots.slotId'),
              dateKey: _requiredString(
                slot['dateKey'],
                'schedule.slots.dateKey',
              ),
              startAt:
                  _readDate(
                    slot['startAt'],
                    'schedule.slots.startAt',
                    required: true,
                  ) ??
                  DateTime.fromMillisecondsSinceEpoch(0),
              endAt:
                  _readDate(
                    slot['endAt'],
                    'schedule.slots.endAt',
                    required: true,
                  ) ??
                  DateTime.fromMillisecondsSinceEpoch(0),
              durationMinutes: _readInt(slot['durationMinutes']) ?? 0,
              unitPricePaise: _readInt(slot['unitPricePaise']) ?? 0,
              serviceId: _requiredString(
                slot['serviceId'],
                'schedule.slots.serviceId',
              ),
              providerId: _requiredString(
                slot['providerId'],
                'schedule.slots.providerId',
              ),
              timezone: _requiredString(
                slot['timezone'],
                'schedule.slots.timezone',
              ),
            ),
          )
          .toList(growable: false);

      final scheduledStartAt = _readDate(
        map['scheduledStartAt'],
        'schedule.scheduledStartAt',
        required: true,
      );
      final scheduledEndAt = _readDate(
        map['scheduledEndAt'],
        'schedule.scheduledEndAt',
        required: true,
      );
      final slotCount = _readInt(map['slotCount']);
      final totalDurationMinutes = _readInt(map['totalDurationMinutes']);
      if (scheduledStartAt == null ||
          scheduledEndAt == null ||
          slotCount == null ||
          totalDurationMinutes == null) {
        return null;
      }

      final validation = validateSlotBookingSelectionV3(
        SlotBookingSelectionV3(
          bookingType: BookingV3Type.slot,
          slots: slots.map((slot) => slot.toDomainSegment()).toList(),
          slotCount: slotCount,
          scheduledStartAt: scheduledStartAt,
          scheduledEndAt: scheduledEndAt,
          totalDurationMinutes: totalDurationMinutes,
        ),
      );
      if (!validation.ok) {
        for (final entry in validation.issues) {
          _addIssue(entry.code.name.toUpperCase(), entry.message, 'schedule');
        }
      }
      if (!serviceAnchorAt.isAtSameMomentAs(scheduledStartAt)) {
        _addIssue(
          'QUERY_FIELD_MISMATCH',
          'schedule.serviceAnchorAt must equal schedule.scheduledStartAt for SLOT.',
          'schedule.serviceAnchorAt',
        );
      }
      if (slots.any((slot) => slot.serviceId != serviceId)) {
        _addIssue(
          'SERVICE_SNAPSHOT_MISMATCH',
          'All slot serviceIds must match service.serviceId.',
          'schedule.slots',
        );
      }
      if (slots.any((slot) => slot.providerId != providerId)) {
        _addIssue(
          'PROVIDER_SNAPSHOT_MISMATCH',
          'All slot providerIds must match service.providerId.',
          'schedule.slots',
        );
      }
      return CanonicalSlotBookingScheduleV3(
        serviceAnchorAt: serviceAnchorAt,
        timezone: timezone,
        slots: slots,
        slotCount: slotCount,
        scheduledStartAt: scheduledStartAt,
        scheduledEndAt: scheduledEndAt,
        totalDurationMinutes: totalDurationMinutes,
      );
    }

    final checkInDateTime = _readDate(
      map['checkInDateTime'],
      'schedule.checkInDateTime',
      required: true,
    );
    final checkOutDateTime = _readDate(
      map['checkOutDateTime'],
      'schedule.checkOutDateTime',
      required: true,
    );
    final nights = _readInt(map['nights']);
    if (checkInDateTime == null || checkOutDateTime == null || nights == null) {
      return null;
    }

    final validation = validateRangeBookingSelectionV3(
      RangeBookingSelectionV3(
        bookingType: BookingV3Type.range,
        checkInDateTime: checkInDateTime,
        checkOutDateTime: checkOutDateTime,
        nights: nights,
        pricePerNightPaise: _readInt(map['pricePerNightPaise']) ?? 0,
        timezone: timezone,
        petQuantity: _readInt(map['petQuantity']),
        maxConcurrentPetsSnapshot: _readInt(map['maxConcurrentPetsSnapshot']),
      ),
    );
    if (!validation.ok) {
      for (final entry in validation.issues) {
        _addIssue(entry.code.name.toUpperCase(), entry.message, 'schedule');
      }
    }
    if (!serviceAnchorAt.isAtSameMomentAs(checkInDateTime)) {
      _addIssue(
        'QUERY_FIELD_MISMATCH',
        'schedule.serviceAnchorAt must equal schedule.checkInDateTime for RANGE.',
        'schedule.serviceAnchorAt',
      );
    }

    return CanonicalRangeBookingScheduleV3(
      serviceAnchorAt: serviceAnchorAt,
      timezone: timezone,
      checkInDateTime: checkInDateTime,
      checkOutDateTime: checkOutDateTime,
      nights: nights,
      minNightsSnapshot: _readInt(map['minNightsSnapshot']),
      maxNightsSnapshot: _readInt(map['maxNightsSnapshot']),
      maxConcurrentPetsSnapshot: _readInt(map['maxConcurrentPetsSnapshot']),
      petQuantity: _readInt(map['petQuantity']),
    );
  }

  CanonicalBookingLifecycleV3? _parseLifecycle(Map<String, dynamic> map) {
    return CanonicalBookingLifecycleV3(
      requestedAt: _readDate(map['requestedAt'], 'lifecycle.requestedAt'),
      timerStartsAt: _readDate(map['timerStartsAt'], 'lifecycle.timerStartsAt'),
      wasQueuedOutsideWorkingHours:
          map['wasQueuedOutsideWorkingHours'] as bool? ?? false,
      notifiedAt: _readDate(map['notifiedAt'], 'lifecycle.notifiedAt'),
      acceptDeadlineAt: _readDate(
        map['acceptDeadlineAt'],
        'lifecycle.acceptDeadlineAt',
      ),
      viewedByProviderAt: _readDate(
        map['viewedByProviderAt'],
        'lifecycle.viewedByProviderAt',
      ),
      respondedAt: _readDate(map['respondedAt'], 'lifecycle.respondedAt'),
      providerResponseType: _parseProviderResponseType(
        map['providerResponseType'],
        'lifecycle.providerResponseType',
      ),
      responseSeconds: _readInt(map['responseSeconds']),
      payDeadlineAt: _readDate(map['payDeadlineAt'], 'lifecycle.payDeadlineAt'),
      paymentStartedAt: _readDate(
        map['paymentStartedAt'],
        'lifecycle.paymentStartedAt',
      ),
      paidAt: _readDate(map['paidAt'], 'lifecycle.paidAt'),
      paymentSeconds: _readInt(map['paymentSeconds']),
      otpGeneratedAt: _readDate(
        map['otpGeneratedAt'],
        'lifecycle.otpGeneratedAt',
      ),
      otpEnteredAt: _readDate(map['otpEnteredAt'], 'lifecycle.otpEnteredAt'),
      noShowAt: _readDate(map['noShowAt'], 'lifecycle.noShowAt'),
      serviceEndedAt: _readDate(
        map['serviceEndedAt'],
        'lifecycle.serviceEndedAt',
      ),
      disputeDeadlineAt: _readDate(
        map['disputeDeadlineAt'],
        'lifecycle.disputeDeadlineAt',
      ),
      completedAt: _readDate(map['completedAt'], 'lifecycle.completedAt'),
      reviewWindowEndsAt: _readDate(
        map['reviewWindowEndsAt'],
        'lifecycle.reviewWindowEndsAt',
      ),
      finalizedAt: _readDate(map['finalizedAt'], 'lifecycle.finalizedAt'),
      cancelledAt: _readDate(map['cancelledAt'], 'lifecycle.cancelledAt'),
    );
  }

  CanonicalBookingPaymentV3? _parsePayment(Map<String, dynamic> map) {
    return CanonicalBookingPaymentV3(
      status: _readString(map['status']),
      razorpayOrderId: _readString(map['razorpayOrderId']),
      razorpayPaymentId: _readString(map['razorpayPaymentId']),
      razorpayRefundId: _readString(map['razorpayRefundId']),
      paymentAttemptId: _readString(map['paymentAttemptId']),
      orderCreatedAt: _readDate(
        map['orderCreatedAt'],
        'payment.orderCreatedAt',
      ),
      paymentStartedAt: _readDate(
        map['paymentStartedAt'],
        'payment.paymentStartedAt',
      ),
      capturedAt: _readDate(map['capturedAt'], 'payment.capturedAt'),
      verifiedAt: _readDate(map['verifiedAt'], 'payment.verifiedAt'),
      verificationSource: _readString(map['verificationSource']),
      webhookEventIds: _readStringList(map['webhookEventIds']),
      failureCode: _readString(map['failureCode']),
      failureMessage: _readString(map['failureMessage']),
    );
  }

  BookingFinancialSnapshotV3? _parseFinancials(Object? value) {
    final map = _readMap(value);
    if (map.isEmpty) return null;
    final parsed = BookingFinancialSnapshotV3.tryParse(map);
    if (parsed == null) {
      _addIssue(
        'INVALID_FINANCIAL_SNAPSHOT',
        'financials must match the canonical immutable paise contract.',
        'financials',
      );
    }
    return parsed;
  }

  CanonicalBookingPrivacyV3? _parsePrivacy(Map<String, dynamic> map) {
    return CanonicalBookingPrivacyV3(
      isPaidContactUnlocked: map['isPaidContactUnlocked'] as bool? ?? false,
      contactUnlockedAt: _readDate(
        map['contactUnlockedAt'],
        'privacy.contactUnlockedAt',
      ),
      chatUnlockedAt: _readDate(
        map['chatUnlockedAt'],
        'privacy.chatUnlockedAt',
      ),
      otpVisibleToParent: map['otpVisibleToParent'] as bool? ?? false,
      exactAddressUnlocked: map['exactAddressUnlocked'] as bool? ?? false,
      privacyVersion:
          _readInt(map['privacyVersion']) ?? canonicalBookingPrivacyVersion,
      privateParticipantsRefPath: _readString(
        map['privateParticipantsRefPath'],
      ),
    );
  }

  CanonicalBookingCancellationV3? _parseCancellation(Map<String, dynamic> map) {
    return CanonicalBookingCancellationV3(
      cancelledAt: _readDate(map['cancelledAt'], 'cancellation.cancelledAt'),
      cancelledBy: _readString(map['cancelledBy']).isEmpty
          ? null
          : _readString(map['cancelledBy']),
      cancelReasonCode: _readString(map['cancelReasonCode']),
      cancelReasonText: _readString(map['cancelReasonText']),
      hoursBeforeServiceAtCancel: _readInt(map['hoursBeforeServiceAtCancel']),
      refundBand: _readString(map['refundBand']),
      refundBasisPoints: _readInt(map['refundBasisPoints']),
      refundAmountPaise: _readInt(map['refundAmountPaise']) ?? 0,
      providerCompensationPaise:
          _readInt(map['providerCompensationPaise']) ?? 0,
      pettxoRetainedPaise: _readInt(map['pettxoRetainedPaise']) ?? 0,
      cancellationType: _readString(map['cancellationType']).isEmpty
          ? null
          : _readString(map['cancellationType']),
    );
  }

  CanonicalBookingDisputeV3? _parseDispute(Map<String, dynamic> map) {
    return CanonicalBookingDisputeV3(
      disputeId: _readString(map['disputeId']),
      status: _readString(map['status']),
      raisedAt: _readDate(map['raisedAt'], 'dispute.raisedAt'),
      raisedBy: _readString(map['raisedBy']).isEmpty
          ? null
          : _readString(map['raisedBy']),
      reasonCode: _readString(map['reasonCode']),
      description: _readString(map['description']),
      evidenceRefs: _readStringList(map['evidenceRefs']),
      resolvedAt: _readDate(map['resolvedAt'], 'dispute.resolvedAt'),
      resolvedBy: _readString(map['resolvedBy']).isEmpty
          ? null
          : _readString(map['resolvedBy']),
      resolution: _readString(map['resolution']),
      resolutionVersion: _readInt(map['resolutionVersion']) ?? 0,
      financialAdjustmentId: _readString(map['financialAdjustmentId']),
      refundInstructionId: _readString(map['refundInstructionId']),
      customerRefundPaise: _readInt(map['customerRefundPaise']) ?? 0,
      providerReleasePaise: _readInt(map['providerReleasePaise']) ?? 0,
    );
  }

  CanonicalBookingReviewV3 _parseReview(Map<String, dynamic> raw) {
    final reviewMap = _readMap(raw['review']);
    final reviewStatus = _readString(raw['reviewStatus']).isNotEmpty
        ? _readString(raw['reviewStatus'])
        : _readString(reviewMap['status']);
    final reviewId = _readString(raw['reviewId']).isNotEmpty
        ? _readString(raw['reviewId'])
        : _readString(reviewMap['reviewId']);
    final submittedAt =
        _readDate(raw['reviewSubmittedAt'], 'reviewSubmittedAt') ??
        _readDate(reviewMap['submittedAt'], 'review.submittedAt');
    return CanonicalBookingReviewV3(
      status: reviewStatus,
      reviewId: reviewId,
      submittedAt: submittedAt,
    );
  }

  CanonicalBookingPayoutV3? _parsePayout(Map<String, dynamic> map) {
    return CanonicalBookingPayoutV3(
      status: _readString(map['status']),
      holdReason: _readString(map['holdReason']),
      eligibleAt: _readDate(map['eligibleAt'], 'payout.eligibleAt'),
      readyAt: _readDate(map['readyAt'], 'payout.readyAt'),
      processingAt: _readDate(map['processingAt'], 'payout.processingAt'),
      releasedAt: _readDate(map['releasedAt'], 'payout.releasedAt'),
      failedAt: _readDate(map['failedAt'], 'payout.failedAt'),
      providerPayoutPaise: _readInt(map['providerPayoutPaise']) ?? 0,
      priorPaidPaise: _readInt(map['priorPaidPaise']) ?? 0,
      remainingPayablePaise: _readInt(map['remainingPayablePaise']) ?? 0,
      payoutReference: _readString(map['payoutReference']),
      externalTransactionId: _readString(map['externalTransactionId']),
      failureCode: _readString(map['failureCode']),
      retryCount: _readInt(map['retryCount']) ?? 0,
    );
  }

  CanonicalBookingStatisticsV3? _parseStatistics(Map<String, dynamic> map) {
    return CanonicalBookingStatisticsV3(
      selectedSlotCount: _readInt(map['selectedSlotCount']),
      totalDurationMinutes: _readInt(map['totalDurationMinutes']),
      nights: _readInt(map['nights']),
    );
  }

  CanonicalBookingAuditV3? _parseAudit(Map<String, dynamic> map) {
    final createdBy = _parseBookingActor(map['createdBy'], 'audit.createdBy');
    final lastUpdatedBy = _parseBookingActor(
      map['lastUpdatedBy'],
      'audit.lastUpdatedBy',
    );
    final source = _readString(map['source']);
    if (createdBy == null || lastUpdatedBy == null || source.isEmpty) {
      if (source.isEmpty) {
        _addIssue(
          'MISSING_REQUIRED_FIELD',
          'audit.source is required.',
          'audit.source',
        );
      }
      return null;
    }
    return CanonicalBookingAuditV3(
      createdBy: createdBy,
      lastUpdatedBy: lastUpdatedBy,
      source: source,
    );
  }

  void _validateLifecycle(
    CanonicalBookingLifecycleV3 lifecycle,
    CanonicalBookingPaymentV3 payment,
    BookingFinancialSnapshotV3? financials,
  ) {
    if (lifecycle.paidAt != null && lifecycle.respondedAt == null) {
      _addIssue(
        'PAID_WITHOUT_RESPONSE',
        'paidAt requires respondedAt.',
        'lifecycle.paidAt',
      );
    }
    if (lifecycle.otpGeneratedAt != null && lifecycle.paidAt == null) {
      _addIssue(
        'OTP_BEFORE_PAYMENT',
        'otpGeneratedAt requires paidAt.',
        'lifecycle.otpGeneratedAt',
      );
    }
    if (lifecycle.completedAt != null && lifecycle.serviceEndedAt == null) {
      _addIssue(
        'COMPLETED_WITHOUT_SERVICE_END',
        'completedAt requires serviceEndedAt.',
        'lifecycle.completedAt',
      );
    }
    if (lifecycle.payDeadlineAt != null && lifecycle.respondedAt == null) {
      _addIssue(
        'PAY_DEADLINE_WITHOUT_RESPONSE',
        'payDeadlineAt requires respondedAt.',
        'lifecycle.payDeadlineAt',
      );
    }
    final paymentLooksConfirmed =
        lifecycle.paidAt != null ||
        payment.capturedAt != null ||
        payment.verifiedAt != null ||
        payment.status.toLowerCase() == 'paid' ||
        payment.status.toLowerCase() == 'captured' ||
        payment.status.toLowerCase() == 'verified';
    if (paymentLooksConfirmed && financials == null) {
      _addIssue(
        'PAID_WITHOUT_FINANCIAL_SNAPSHOT',
        'Confirmed payment requires immutable financials.',
        'financials',
      );
    }
  }

  void _validateTopLevelConsistency({
    required BookingV3Type bookingType,
    required CanonicalBookingStateV3 state,
    required CanonicalBookingParticipantsV3 participants,
    required BookingServiceSnapshotV3 service,
    required CanonicalBookingScheduleV3 schedule,
    required CanonicalBookingLifecycleV3 lifecycle,
    required String parentId,
    required String providerId,
    required String serviceId,
    required CanonicalBookingStateV3 stateQueryValue,
    required BookingV3Type bookingTypeQueryValue,
    required DateTime serviceAnchorAt,
    required DateTime? scheduledStartAt,
    required DateTime? checkInDateTime,
    required DateTime? acceptDeadlineAt,
    required DateTime? payDeadlineAt,
    required DateTime? completedAt,
    required String customerId,
    required String serviceOwnerId,
  }) {
    _requireEqual(
      parentId,
      participants.parent.parentId,
      code: 'QUERY_FIELD_MISMATCH',
      path: 'parentId',
      message: 'parentId must mirror participants.parent.parentId.',
    );
    _requireEqual(
      providerId,
      participants.provider.providerId,
      code: 'QUERY_FIELD_MISMATCH',
      path: 'providerId',
      message: 'providerId must mirror participants.provider.providerId.',
    );
    _requireEqual(
      providerId,
      service.providerId,
      code: 'QUERY_FIELD_MISMATCH',
      path: 'providerId',
      message: 'providerId must mirror service.providerId.',
    );
    _requireEqual(
      serviceId,
      service.serviceId,
      code: 'QUERY_FIELD_MISMATCH',
      path: 'serviceId',
      message: 'serviceId must mirror service.serviceId.',
    );
    _requireEqual(
      customerId,
      parentId,
      code: 'QUERY_FIELD_MISMATCH',
      path: 'customerId',
      message: 'customerId compatibility field must equal parentId.',
    );
    _requireEqual(
      serviceOwnerId,
      providerId,
      code: 'QUERY_FIELD_MISMATCH',
      path: 'serviceOwnerId',
      message: 'serviceOwnerId compatibility field must equal providerId.',
    );
    if (state != stateQueryValue) {
      _addIssue(
        'QUERY_FIELD_MISMATCH',
        'stateQueryValue must mirror state.',
        'stateQueryValue',
      );
    }
    if (bookingType != bookingTypeQueryValue) {
      _addIssue(
        'QUERY_FIELD_MISMATCH',
        'bookingTypeQueryValue must mirror bookingType.',
        'bookingTypeQueryValue',
      );
    }
    if (!serviceAnchorAt.isAtSameMomentAs(schedule.serviceAnchorAt)) {
      _addIssue(
        'QUERY_FIELD_MISMATCH',
        'serviceAnchorAt must mirror schedule.serviceAnchorAt.',
        'serviceAnchorAt',
      );
    }
    if (schedule is CanonicalSlotBookingScheduleV3) {
      if (scheduledStartAt == null ||
          !scheduledStartAt.isAtSameMomentAs(schedule.scheduledStartAt)) {
        _addIssue(
          'QUERY_FIELD_MISMATCH',
          'scheduledStartAt must mirror schedule.scheduledStartAt.',
          'scheduledStartAt',
        );
      }
      if (checkInDateTime != null) {
        _addIssue(
          'QUERY_FIELD_MISMATCH',
          'checkInDateTime must be null for SLOT bookings.',
          'checkInDateTime',
        );
      }
    } else if (schedule is CanonicalRangeBookingScheduleV3) {
      if (checkInDateTime == null ||
          !checkInDateTime.isAtSameMomentAs(schedule.checkInDateTime)) {
        _addIssue(
          'QUERY_FIELD_MISMATCH',
          'checkInDateTime must mirror schedule.checkInDateTime.',
          'checkInDateTime',
        );
      }
    }
    _requireMatchingDate(
      acceptDeadlineAt,
      lifecycle.acceptDeadlineAt,
      path: 'acceptDeadlineAt',
    );
    _requireMatchingDate(
      payDeadlineAt,
      lifecycle.payDeadlineAt,
      path: 'payDeadlineAt',
    );
    _requireMatchingDate(
      completedAt,
      lifecycle.completedAt,
      path: 'completedAt',
    );
  }

  void _requireEqual(
    String a,
    String b, {
    required String code,
    required String path,
    required String message,
  }) {
    if (a != b) {
      _addIssue(code, message, path);
    }
  }

  void _requireMatchingDate(
    DateTime? queryValue,
    DateTime? lifecycleValue, {
    required String path,
  }) {
    final matches =
        queryValue == null && lifecycleValue == null ||
        queryValue != null &&
            lifecycleValue != null &&
            queryValue.isAtSameMomentAs(lifecycleValue);
    if (!matches) {
      _addIssue(
        'QUERY_FIELD_MISMATCH',
        '$path must mirror lifecycle.$path.',
        path,
      );
    }
  }

  void _addIssue(String code, String message, String path) {
    issues.add(
      CanonicalBookingValidationIssue(code: code, message: message, path: path),
    );
  }

  CanonicalBookingLifecycleV3 _applyLegacyCompletedLifecycleFallback({
    required Map<String, dynamic> raw,
    required CanonicalBookingStateV3 state,
    required CanonicalBookingLifecycleV3 lifecycle,
  }) {
    final isCompletedState =
        state == CanonicalBookingStateV3.completedPendingReview ||
        state == CanonicalBookingStateV3.completedFinal;
    if (!isCompletedState) {
      return lifecycle;
    }

    final fallbackServiceEndedAt =
        lifecycle.serviceEndedAt ??
        _readDate(raw['lifecycle.serviceEndedAt'], 'lifecycle.serviceEndedAt');
    final fallbackCompletedAt =
        lifecycle.completedAt ??
        _readDate(raw['lifecycle.completedAt'], 'lifecycle.completedAt') ??
        _readDate(raw['completedAt'], 'completedAt');
    final normalizedServiceEndedAt =
        fallbackServiceEndedAt ?? fallbackCompletedAt;
    final fallbackReviewWindowEndsAt =
        lifecycle.reviewWindowEndsAt ??
        _readDate(
          raw['lifecycle.reviewWindowEndsAt'],
          'lifecycle.reviewWindowEndsAt',
        );
    final fallbackDisputeDeadlineAt =
        lifecycle.disputeDeadlineAt ??
        _readDate(
          raw['lifecycle.disputeDeadlineAt'],
          'lifecycle.disputeDeadlineAt',
        );
    final fallbackOtpEnteredAt =
        lifecycle.otpEnteredAt ??
        _readDate(raw['lifecycle.otpEnteredAt'], 'lifecycle.otpEnteredAt');

    if (normalizedServiceEndedAt == lifecycle.serviceEndedAt &&
        fallbackCompletedAt == lifecycle.completedAt &&
        fallbackReviewWindowEndsAt == lifecycle.reviewWindowEndsAt &&
        fallbackDisputeDeadlineAt == lifecycle.disputeDeadlineAt &&
        fallbackOtpEnteredAt == lifecycle.otpEnteredAt) {
      return lifecycle;
    }

    return CanonicalBookingLifecycleV3(
      requestedAt: lifecycle.requestedAt,
      timerStartsAt: lifecycle.timerStartsAt,
      wasQueuedOutsideWorkingHours: lifecycle.wasQueuedOutsideWorkingHours,
      notifiedAt: lifecycle.notifiedAt,
      acceptDeadlineAt: lifecycle.acceptDeadlineAt,
      viewedByProviderAt: lifecycle.viewedByProviderAt,
      respondedAt: lifecycle.respondedAt,
      providerResponseType: lifecycle.providerResponseType,
      responseSeconds: lifecycle.responseSeconds,
      payDeadlineAt: lifecycle.payDeadlineAt,
      paymentStartedAt: lifecycle.paymentStartedAt,
      paidAt: lifecycle.paidAt,
      paymentSeconds: lifecycle.paymentSeconds,
      otpGeneratedAt: lifecycle.otpGeneratedAt,
      otpEnteredAt: fallbackOtpEnteredAt,
      noShowAt: lifecycle.noShowAt,
      serviceEndedAt: normalizedServiceEndedAt,
      disputeDeadlineAt: fallbackDisputeDeadlineAt,
      completedAt: fallbackCompletedAt,
      reviewWindowEndsAt: fallbackReviewWindowEndsAt,
      finalizedAt: lifecycle.finalizedAt,
      cancelledAt: lifecycle.cancelledAt,
    );
  }

  BookingV3Type? _parseBookingType(Object? value, String path) {
    final normalized = _readString(value).toUpperCase();
    return switch (normalized) {
      'SLOT' => BookingV3Type.slot,
      'RANGE' => BookingV3Type.range,
      '' => null,
      _ => _invalidEnum('INVALID_BOOKING_TYPE', path, normalized),
    };
  }

  CanonicalBookingStateV3? _parseState(Object? value, String path) {
    final normalized = _readString(value).toUpperCase();
    return switch (normalized) {
      'REQUESTED' => CanonicalBookingStateV3.requested,
      'PENDING_PROVIDER' => CanonicalBookingStateV3.pendingProvider,
      'ACCEPTED_AWAITING_PAYMENT' =>
        CanonicalBookingStateV3.acceptedAwaitingPayment,
      'CONFIRMED' => CanonicalBookingStateV3.confirmed,
      'IN_PROGRESS' => CanonicalBookingStateV3.inProgress,
      'COMPLETED_PENDING_REVIEW' =>
        CanonicalBookingStateV3.completedPendingReview,
      'COMPLETED_FINAL' => CanonicalBookingStateV3.completedFinal,
      'DECLINED' => CanonicalBookingStateV3.declined,
      'EXPIRED' => CanonicalBookingStateV3.expired,
      'PAYMENT_EXPIRED' => CanonicalBookingStateV3.paymentExpired,
      'CANCELLED_BY_PARENT' => CanonicalBookingStateV3.cancelledByParent,
      'CANCELLED' => CanonicalBookingStateV3.cancelled,
      'DISPUTED' => CanonicalBookingStateV3.disputed,
      'SERVICE_NOT_STARTED' => CanonicalBookingStateV3.serviceNotStarted,
      'NO_SHOW' => CanonicalBookingStateV3.noShow,
      '' => null,
      _ => _invalidEnum('INVALID_STATE', path, normalized),
    };
  }

  ProviderResponseTypeV3? _parseProviderResponseType(
    Object? value,
    String path,
  ) {
    final normalized = _readString(value).toLowerCase();
    return switch (normalized) {
      '' => null,
      'accept' => ProviderResponseTypeV3.accept,
      'decline' => ProviderResponseTypeV3.decline,
      'expired' => ProviderResponseTypeV3.expired,
      _ => _invalidEnum('INVALID_PROVIDER_RESPONSE_TYPE', path, normalized),
    };
  }

  BookingActorV3? _parseBookingActor(Object? value, String path) {
    final normalized = _readString(value).toLowerCase();
    return switch (normalized) {
      'parent' => BookingActorV3.parent,
      'provider' => BookingActorV3.provider,
      'system' => BookingActorV3.system,
      'admin' => BookingActorV3.admin,
      'payment_gateway' => BookingActorV3.paymentGateway,
      'paymentgateway' => BookingActorV3.paymentGateway,
      '' => null,
      _ => _invalidEnum('INVALID_BOOKING_ACTOR', path, normalized),
    };
  }

  T? _invalidEnum<T>(String code, String path, String value) {
    _addIssue(code, 'Unsupported enum value "$value".', path);
    return null;
  }

  String _requiredString(Object? value, String path) {
    final text = _readString(value);
    if (text.isEmpty) {
      throw FormatException('Missing required string at $path');
    }
    return text;
  }

  Map<String, dynamic> _readMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _readListOfMaps(Object? value) {
    if (value is! Iterable) return const [];
    return value
        .map((entry) => _readMap(entry))
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _readStringList(Object? value) {
    if (value is! Iterable) return const [];
    return value
        .map(_readString)
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  String _readString(Object? value) => value?.toString().trim() ?? '';

  int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    return int.tryParse(_readString(value));
  }

  double? _readDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(_readString(value));
  }

  DateTime? _readDate(Object? value, String path, {bool required = false}) {
    DateTime? parsed;
    if (value is Timestamp) {
      parsed = value.toDate();
    } else if (value is DateTime) {
      parsed = value;
    } else if (value is String) {
      parsed = DateTime.tryParse(value.trim());
    }

    if (required && parsed == null) {
      _addIssue('MISSING_REQUIRED_FIELD', '$path is required.', path);
    }
    return parsed;
  }
}

bool isCanonicalBookingDocumentCandidate(Map<String, dynamic> raw) {
  return (raw['schemaVersion'] == canonicalBookingSchemaVersion) &&
      (raw['bookingModelVersion']?.toString().trim() ==
          canonicalBookingModelVersion) &&
      (raw['documentFormat']?.toString().trim() ==
          canonicalBookingDocumentFormat);
}

CanonicalBookingDocumentParseResult parseCanonicalBookingDocumentV3(
  Map<String, dynamic> raw,
) {
  return _CanonicalBookingDocumentParser(raw).parse();
}
