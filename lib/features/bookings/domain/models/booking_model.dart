import 'package:cloud_firestore/cloud_firestore.dart';

import 'booking_flow_models.dart';

class BookingModel {
  final String id;
  final String customerId;
  final String providerId;
  final String serviceId;
  final String slotId;
  final String serviceName;
  final String animalType;
  final String category;
  final String serviceType;
  final String primaryPhotoUrl;
  final int durationMinutes;
  final String providerName;
  final String providerUsername;
  final String providerPhotoUrl;
  final String providerPhoneMasked;
  final String providerPhone;
  final double providerRatingAverage;
  final int providerRatingCount;
  final String customerName;
  final String customerUsername;
  final String customerPhotoUrl;
  final String customerPhoneMasked;
  final String status;
  final DateTime? scheduledStartAt;
  final DateTime? scheduledEndAt;
  final String requestMessage;
  final DateTime? requestExpiresAt;
  final DateTime? requestRespondedAt;
  final String requestResponseReason;
  final String displayAddress;
  final double latitude;
  final double longitude;
  final int grossAmount;
  final int grossAmountPaise;
  final int platformFee;
  final int platformFeePaise;
  final int providerEarnings;
  final int providerEarningsPaise;
  final String currency;
  final String paymentStatus;
  final String otpStatus;
  final int otpAttempts;
  final int otpMaxAttempts;
  final DateTime? otpGeneratedAt;
  final DateTime? otpExpiresAt;
  final DateTime? otpVerifiedAt;
  final String payoutStatus;
  final DateTime? payoutEligibleAt;
  final String reviewStatus;
  final String reviewId;
  final int graceWindowMinutes;
  final DateTime? graceWindowEndsAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final DateTime? noShowAt;
  final String disputeStatus;
  final bool hasDispute;
  final String disputeId;
  final String cancellationActorType;
  final String cancellationReason;
  final int cancellationRefundAmount;
  final int cancellationRefundAmountPaise;
  final int cancellationPettxoAmount;
  final int cancellationPettxoAmountPaise;
  final int cancellationProviderAmount;
  final int cancellationProviderAmountPaise;
  final String cancellationCase;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BookingModel({
    required this.id,
    required this.customerId,
    required this.providerId,
    required this.serviceId,
    required this.slotId,
    required this.serviceName,
    required this.animalType,
    required this.category,
    required this.serviceType,
    required this.primaryPhotoUrl,
    required this.durationMinutes,
    required this.providerName,
    required this.providerUsername,
    required this.providerPhotoUrl,
    required this.providerPhoneMasked,
    required this.providerPhone,
    required this.providerRatingAverage,
    required this.providerRatingCount,
    required this.customerName,
    required this.customerUsername,
    required this.customerPhotoUrl,
    required this.customerPhoneMasked,
    required this.status,
    this.scheduledStartAt,
    this.scheduledEndAt,
    required this.requestMessage,
    this.requestExpiresAt,
    this.requestRespondedAt,
    required this.requestResponseReason,
    required this.displayAddress,
    required this.latitude,
    required this.longitude,
    required this.grossAmount,
    required this.grossAmountPaise,
    required this.platformFee,
    required this.platformFeePaise,
    required this.providerEarnings,
    required this.providerEarningsPaise,
    required this.currency,
    required this.paymentStatus,
    required this.otpStatus,
    required this.otpAttempts,
    required this.otpMaxAttempts,
    this.otpGeneratedAt,
    this.otpExpiresAt,
    this.otpVerifiedAt,
    required this.payoutStatus,
    this.payoutEligibleAt,
    required this.reviewStatus,
    required this.reviewId,
    required this.graceWindowMinutes,
    this.graceWindowEndsAt,
    this.completedAt,
    this.cancelledAt,
    this.noShowAt,
    required this.disputeStatus,
    required this.hasDispute,
    required this.disputeId,
    required this.cancellationActorType,
    required this.cancellationReason,
    required this.cancellationRefundAmount,
    required this.cancellationRefundAmountPaise,
    required this.cancellationPettxoAmount,
    required this.cancellationPettxoAmountPaise,
    required this.cancellationProviderAmount,
    required this.cancellationProviderAmountPaise,
    required this.cancellationCase,
    this.createdAt,
    this.updatedAt,
  });

  factory BookingModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final serviceSnapshot = _map(data['serviceSnapshot']);
    final providerSnapshot = _map(data['providerSnapshot']);
    final customerSnapshot = _map(data['customerSnapshot']);
    final locationSnapshot = _map(data['locationSnapshot']);
    final request = _map(data['request']);
    final pricing = _map(data['pricing']);
    final otp = _map(data['otp']);
    final payoutReadiness = _map(data['payoutReadiness']);
    final review = _map(data['review']);
    final dispute = _map(data['dispute']);
    final cancellation = _map(data['cancellation']);

    return BookingModel(
      id: snapshot.id,
      customerId: _string(data['customerId']),
      // Current Cloud Function writes serviceOwnerId. Keep providerId fallback so
      // future schema naming can be adopted without changing the UI layer.
      providerId: _firstString([data['providerId'], data['serviceOwnerId']]),
      serviceId: _string(data['serviceId']),
      slotId: _string(data['slotId']),
      serviceName: _string(
        serviceSnapshot['title'],
        fallback: 'Service booking',
      ),
      animalType: _string(serviceSnapshot['animalType']),
      category: _string(serviceSnapshot['category']),
      serviceType: _string(serviceSnapshot['serviceType']),
      primaryPhotoUrl: _string(serviceSnapshot['primaryPhotoUrl']),
      durationMinutes: _int(serviceSnapshot['durationMinutes'], fallback: 60),
      providerName: _string(providerSnapshot['name'], fallback: 'Provider'),
      providerUsername: _string(providerSnapshot['username']),
      providerPhotoUrl: _string(providerSnapshot['photoUrl']),
      providerPhoneMasked: _string(providerSnapshot['phoneMasked']),
      providerPhone: _firstString([
        providerSnapshot['phone'],
        providerSnapshot['phoneNumber'],
        providerSnapshot['mobileNumber'],
      ]),
      providerRatingAverage:
          (providerSnapshot['ratingAverage'] as num?)?.toDouble() ?? 0,
      providerRatingCount:
          (providerSnapshot['ratingCount'] as num?)?.toInt() ?? 0,
      customerName: _string(customerSnapshot['name'], fallback: 'Pet parent'),
      customerUsername: _string(customerSnapshot['username']),
      customerPhotoUrl: _string(customerSnapshot['photoUrl']),
      customerPhoneMasked: _string(customerSnapshot['phoneMasked']),
      status: _string(data['status'], fallback: 'requested'),
      scheduledStartAt: _dateTime(data['scheduledStartAt']),
      scheduledEndAt: _dateTime(data['scheduledEndAt']),
      requestMessage: _string(request['message']),
      requestExpiresAt: _dateTime(request['expiresAt']),
      requestRespondedAt: _dateTime(request['respondedAt']),
      requestResponseReason: _string(request['responseReason']),
      displayAddress: _string(locationSnapshot['displayAddress']),
      latitude: _double(locationSnapshot['latitude']),
      longitude: _double(locationSnapshot['longitude']),
      grossAmount: _int(pricing['grossAmount']),
      grossAmountPaise: _int(
        pricing['grossAmountPaise'],
        fallback: _int(pricing['grossAmount']) * 100,
      ),
      platformFee: _int(pricing['platformFee']),
      platformFeePaise: _int(
        pricing['platformFeePaise'],
        fallback: _int(pricing['platformFee']) * 100,
      ),
      providerEarnings: _int(pricing['providerEarnings']),
      providerEarningsPaise: _int(
        pricing['providerEarningsPaise'],
        fallback: _int(pricing['providerEarnings']) * 100,
      ),
      currency: _string(
        pricing['currency'],
        fallback: _string(serviceSnapshot['currency'], fallback: 'INR'),
      ),
      paymentStatus: _string(pricing['paymentStatus']),
      otpStatus: _string(otp['status']),
      otpAttempts: _int(otp['attempts']),
      otpMaxAttempts: _int(otp['maxAttempts']),
      otpGeneratedAt: _dateTime(otp['generatedAt']),
      otpExpiresAt: _dateTime(otp['expiresAt']),
      otpVerifiedAt: _dateTime(otp['verifiedAt']),
      payoutStatus: _string(payoutReadiness['status']),
      payoutEligibleAt: _dateTime(payoutReadiness['eligibleAt']),
      reviewStatus: _string(
        review['status'],
        fallback: _string(data['reviewStatus']),
      ),
      reviewId: _string(
        review['reviewId'],
        fallback: _string(data['reviewId']),
      ),
      graceWindowMinutes: _int(data['graceWindowMinutes']),
      graceWindowEndsAt: _dateTime(data['graceWindowEndsAt']),
      completedAt: _dateTime(data['completedAt']),
      cancelledAt: _dateTime(data['cancelledAt']),
      noShowAt: _dateTime(data['noShowAt']),
      disputeStatus: _string(
        dispute['status'],
        fallback: _string(data['disputeStatus']),
      ),
      hasDispute: dispute['hasDispute'] == true,
      disputeId: _string(dispute['disputeId']),
      cancellationActorType: _string(
        cancellation['actorType'],
        fallback: _string(data['cancellationType']),
      ),
      cancellationReason: _string(cancellation['reason']),
      cancellationRefundAmount: _int(cancellation['refundAmount']),
      cancellationRefundAmountPaise: _int(
        cancellation['refundAmountPaise'],
        fallback: _int(cancellation['refundAmount']) * 100,
      ),
      cancellationPettxoAmount: _int(cancellation['pettxoAmount']),
      cancellationPettxoAmountPaise: _int(
        cancellation['pettxoAmountPaise'],
        fallback: _int(cancellation['pettxoAmount']) * 100,
      ),
      cancellationProviderAmount: _int(cancellation['providerAmount']),
      cancellationProviderAmountPaise: _int(
        cancellation['providerAmountPaise'],
        fallback: _int(cancellation['providerAmount']) * 100,
      ),
      cancellationCase: _string(
        cancellation['cancellationCase'],
        fallback: _string(data['cancellationCase']),
      ),
      createdAt: _dateTime(data['createdAt']),
      updatedAt: _dateTime(data['updatedAt']),
    );
  }

  String get normalizedStatus {
    final value = status
        .trim()
        .replaceAllMapped(
          RegExp(r'(?<=[a-z])([A-Z])'),
          (match) => '_${match.group(1)}',
        )
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    return switch (value) {
      'inprogress' => 'in_progress',
      'paymentpending' => 'payment_pending',
      'paymentexpired' => 'payment_expired',
      'cancelledbyuser' => 'cancelled_by_user',
      'cancelledbycustomer' => 'cancelled_by_customer',
      'cancelledbyprovider' => 'cancelled_by_provider',
      _ => value,
    };
  }

  String get normalizedOtpStatus {
    final value = otpStatus.trim().toLowerCase().replaceAll('-', '_');
    return switch (value) {
      'notgenerated' => 'not_generated',
      _ => value,
    };
  }

  bool get isRequested => normalizedStatus == 'requested';

  bool get isAccepted =>
      const {'accepted', 'confirmed'}.contains(normalizedStatus);

  bool get isInProgress => normalizedStatus == 'in_progress';

  bool get isCompleted => normalizedStatus == 'completed';

  bool get isNoShow => normalizedStatus == 'no_show';

  bool get isCancelled => const {
    'cancelled_by_customer',
    'cancelled_by_provider',
    'cancelled_by_user',
    'cancelled_by_system',
    'cancelled',
  }.contains(normalizedStatus);

  bool get isPostConfirmation => isAccepted || isInProgress || isCompleted;

  bool get hasUsableCoordinates => latitude != 0 || longitude != 0;

  bool get isConfirmedLike {
    return const {
      'accepted',
      'confirmed',
      'otp_pending',
      'in_progress',
    }.contains(normalizedStatus);
  }

  bool get hasActiveOtp {
    if (normalizedOtpStatus != 'generated') return false;
    final expiresAt = otpExpiresAt;
    return expiresAt == null || expiresAt.isAfter(DateTime.now());
  }

  bool get canCustomerGenerateOtp => isAccepted;

  bool get canCancelBeforeStart {
    if (isRequested) return true;
    if (!isAccepted) return false;
    final start = scheduledStartAt;
    return start == null || start.isAfter(DateTime.now());
  }

  bool get canRaiseDispute {
    if (disputeWindowEndsAt == null) return false;
    return DateTime.now().isBefore(disputeWindowEndsAt!);
  }

  DateTime? get disputeWindowEndsAt {
    if (completedAt != null) {
      return completedAt!.add(const Duration(hours: 24));
    }
    if (scheduledStartAt != null) {
      return scheduledStartAt!.add(const Duration(hours: 24));
    }
    if (createdAt != null) {
      return createdAt!.add(const Duration(hours: 24));
    }
    return null;
  }

  Duration? get remainingGraceDuration {
    final endsAt = graceWindowEndsAt;
    if (endsAt == null) return null;
    final remaining = endsAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get isWithinGraceWindow {
    final remaining = remainingGraceDuration;
    return remaining != null && remaining > Duration.zero;
  }

  bool get isWithinServiceStartWindow {
    final start = scheduledStartAt;
    if (start == null) return true;
    final now = DateTime.now();
    return now.isAfter(start.subtract(const Duration(hours: 1)));
  }

  bool get isFinished {
    return const {
      'completed',
      'rejected',
      'cancelled',
      'canceled',
      'cancelled_by_customer',
      'cancelled_by_provider',
      'expired',
      'payment_expired',
      'refunded',
      'no_show',
      'disputed',
    }.contains(normalizedStatus);
  }

  bool get hasReview => reviewId.trim().isNotEmpty;

  String get providerReviewSummary {
    if (providerRatingCount <= 0) return 'New provider';
    return '⭐ ${providerRatingAverage.toStringAsFixed(1)} · '
        '$providerRatingCount ${providerRatingCount == 1 ? 'review' : 'reviews'}';
  }

  bool get belongsInReceivingUpcoming {
    if (normalizedStatus == 'payment_pending') {
      return true;
    }
    if (normalizedStatus == 'payment_expired') {
      return false;
    }
    if (isRequested || isConfirmedLike) return true;
    final start = scheduledStartAt;
    return start != null && start.isAfter(DateTime.now()) && !isFinished;
  }

  bool get belongsInReceivingPast => !belongsInReceivingUpcoming;

  bool get belongsInDeliveringPast => isFinished;

  BookingRecord toBookingRecord(BookingContextMode contextMode) {
    final isDelivering = contextMode == BookingContextMode.delivering;
    final tab = _tabFor(contextMode);
    final title = isDelivering ? customerName : serviceName;
    final counterparty = isDelivering ? serviceName : providerName;
    final subtitleParts = [
      if (animalType.trim().isNotEmpty) animalType.trim(),
      counterparty,
    ];
    final countdownSeconds = _requestCountdownSeconds;

    return BookingRecord(
      id: id,
      serviceId: serviceId,
      slotId: slotId,
      context: contextMode,
      tab: tab,
      title: title,
      subtitle: subtitleParts.join(' · '),
      meta: _scheduleMeta,
      reviewSummary: normalizedStatus == 'completed'
          ? providerReviewSummary
          : '',
      providerUserId: providerId,
      scheduledStartAt: scheduledStartAt,
      scheduledEndAt: scheduledEndAt,
      pricePaise: grossAmountPaise,
      durationMinutes: durationMinutes,
      statusLabel: _statusLabel(contextMode),
      statusTone: _statusTone(contextMode),
      countdownSeconds: countdownSeconds,
      isRequestHighlighted: isDelivering && isRequested,
      actions: _actionsFor(contextMode),
      detailType: _detailTypeFor(contextMode),
    );
  }

  BookingTab _tabFor(BookingContextMode contextMode) {
    if (contextMode == BookingContextMode.receiving) {
      return belongsInReceivingUpcoming ? BookingTab.upcoming : BookingTab.past;
    }
    if (isRequested) return BookingTab.requests;
    if (isConfirmedLike) return BookingTab.confirmed;
    return BookingTab.pastDeliveries;
  }

  BookingDetailType? _detailTypeFor(BookingContextMode contextMode) {
    if (contextMode == BookingContextMode.receiving) {
      if (isRequested) return BookingDetailType.receivingRequested;
      if (isConfirmedLike) return BookingDetailType.receivingConfirmed;
      if (normalizedStatus == 'completed') {
        return BookingDetailType.receivingCompleted;
      }
      return null;
    }
    if (isRequested) return BookingDetailType.deliveringRequest;
    if (isConfirmedLike) return BookingDetailType.deliveringConfirmed;
    return null;
  }

  List<BookingActionData> _actionsFor(BookingContextMode contextMode) {
    if (contextMode == BookingContextMode.receiving) {
      if (normalizedStatus == 'payment_pending') {
        return const [
          BookingActionData(
            label: 'Resume Payment',
            style: BookingActionStyle.primary,
          ),
        ];
      }
      if (normalizedStatus == 'completed') {
        return const [
          BookingActionData(
            label: 'Book Again',
            style: BookingActionStyle.primary,
          ),
        ];
      }
      if (isFinished) return const [];
      return const [
        BookingActionData(
          label: 'View booking',
          style: BookingActionStyle.primary,
          opensDetail: true,
        ),
      ];
    }

    if (isRequested) {
      return const [
        BookingActionData(
          label: 'Accept',
          style: BookingActionStyle.primary,
          toastMessage: 'Accept flow will be connected in the next phase.',
        ),
        BookingActionData(
          label: 'Reject',
          style: BookingActionStyle.danger,
          toastMessage: 'Reject flow will be connected in the next phase.',
        ),
      ];
    }

    if (isConfirmedLike) {
      return const [
        BookingActionData(
          label: 'Start service',
          style: BookingActionStyle.primary,
          opensDetail: true,
        ),
        BookingActionData(
          label: 'Message',
          style: BookingActionStyle.secondary,
          toastMessage: 'Messaging flow will be connected in the next phase.',
        ),
      ];
    }

    return const [];
  }

  String _statusLabel(BookingContextMode contextMode) {
    switch (normalizedStatus) {
      case 'requested':
        return contextMode == BookingContextMode.delivering
            ? 'Request'
            : 'Awaiting confirm';
      case 'accepted':
      case 'confirmed':
        return 'Confirmed';
      case 'otp_pending':
        return 'OTP pending';
      case 'in_progress':
        return 'In progress';
      case 'completed':
        return 'Completed';
      case 'rejected':
        return 'Rejected';
      case 'expired':
        return 'Expired';
      case 'payment_pending':
        return 'Payment pending';
      case 'payment_expired':
        return 'Payment expired';
      case 'refunded':
        return 'Refunded';
      case 'no_show':
        return 'No-show';
      case 'cancelled_by_provider':
        return 'Cancelled by provider';
      case 'cancelled_by_customer':
        return 'Cancelled by customer';
      case 'cancelled':
      case 'canceled':
        return 'Cancelled';
      default:
        return status.trim().isEmpty ? 'Pending' : _titleCase(status);
    }
  }

  BookingStatusTone _statusTone(BookingContextMode contextMode) {
    if (isRequested) {
      return contextMode == BookingContextMode.delivering
          ? BookingStatusTone.highlighted
          : BookingStatusTone.awaiting;
    }
    if (isConfirmedLike) return BookingStatusTone.confirmed;
    switch (normalizedStatus) {
      case 'completed':
        return BookingStatusTone.completed;
      case 'no_show':
        return BookingStatusTone.noShow;
      case 'rejected':
      case 'expired':
      case 'payment_expired':
      case 'refunded':
      case 'cancelled':
      case 'canceled':
      case 'cancelled_by_provider':
      case 'cancelled_by_customer':
        return BookingStatusTone.cancelled;
      default:
        return BookingStatusTone.request;
    }
  }

  String get _scheduleMeta {
    final start = scheduledStartAt;
    if (start == null) return durationMinutes > 0 ? '$durationMinutes min' : '';
    final dateText = _formatDate(start);
    final timeText = _formatTime(start);
    final durationText = durationMinutes > 0 ? ' · $durationMinutes min' : '';
    return '$dateText, $timeText$durationText';
  }

  int? get _requestCountdownSeconds {
    if (!isRequested || requestExpiresAt == null) return null;
    final seconds = requestExpiresAt!.difference(DateTime.now()).inSeconds;
    if (seconds <= 0) return null;
    return seconds;
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  static String _firstString(List<Object?> values, {String fallback = ''}) {
    for (final value in values) {
      final text = _string(value);
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }

  static String _string(Object? value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static int _int(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _double(Object? value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static DateTime? _dateTime(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String _formatDate(DateTime value) {
    final now = DateTime.now();
    final local = value.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(local.year, local.month, local.day);
    final difference = target.difference(today).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Tomorrow';
    if (difference == -1) return 'Yesterday';
    const months = [
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
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  static String _formatTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  static String _titleCase(String value) {
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}
