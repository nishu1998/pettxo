import 'package:cloud_firestore/cloud_firestore.dart';

import 'offer_types.dart';

class ClaimedOffer {
  final String id;
  final String offerId;
  final String couponCode;
  final OfferDiscountType discountType;
  final double discountValue;
  final double? maxDiscountAmount;
  final double? minBookingAmount;
  final DateTime? claimedAt;
  final DateTime? validUntil;
  final int usageLimit;
  final int usedCount;
  final ClaimedOfferStatus status;
  final OfferDisplayType sourceDisplayType;
  final Map<String, dynamic> campaignSnapshot;

  const ClaimedOffer({
    required this.id,
    required this.offerId,
    required this.couponCode,
    required this.discountType,
    required this.discountValue,
    required this.maxDiscountAmount,
    required this.minBookingAmount,
    required this.claimedAt,
    required this.validUntil,
    required this.usageLimit,
    required this.usedCount,
    required this.status,
    required this.sourceDisplayType,
    required this.campaignSnapshot,
  });

  factory ClaimedOffer.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return ClaimedOffer.fromMap(doc.id, doc.data() ?? const {});
  }

  factory ClaimedOffer.fromMap(String id, Map<String, dynamic> data) {
    return ClaimedOffer(
      id: id,
      offerId: (data['offerId'] as String? ?? '').trim(),
      couponCode: (data['couponCode'] as String? ?? '').trim(),
      discountType: OfferDiscountTypeX.fromValue(
        data['discountType'] as String? ?? '',
      ),
      discountValue: (data['discountValue'] as num?)?.toDouble() ?? 0,
      maxDiscountAmount: (data['maxDiscountAmount'] as num?)?.toDouble(),
      minBookingAmount: (data['minBookingAmount'] as num?)?.toDouble(),
      claimedAt: _readDate(data['claimedAt']),
      validUntil: _readDate(data['validUntil']),
      usageLimit: (data['usageLimit'] as num?)?.toInt() ?? 1,
      usedCount: (data['usedCount'] as num?)?.toInt() ?? 0,
      status: ClaimedOfferStatusX.fromValue(data['status'] as String? ?? ''),
      sourceDisplayType: OfferDisplayTypeX.fromValue(
        data['sourceDisplayType'] as String? ?? '',
      ),
      campaignSnapshot:
          data['campaignSnapshot'] as Map<String, dynamic>? ?? const {},
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'offerId': offerId,
      'couponCode': couponCode,
      'discountType': discountType.value,
      'discountValue': discountValue,
      'maxDiscountAmount': maxDiscountAmount,
      'minBookingAmount': minBookingAmount,
      'claimedAt': claimedAt,
      'validUntil': validUntil,
      'usageLimit': usageLimit,
      'usedCount': usedCount,
      'status': status.value,
      'sourceDisplayType': sourceDisplayType.value,
      'campaignSnapshot': campaignSnapshot,
    };
  }

  static DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String get title => (campaignSnapshot['title'] as String? ?? '').trim();

  String get description =>
      (campaignSnapshot['description'] as String? ?? '').trim();

  bool get isExpired =>
      status == ClaimedOfferStatus.expired ||
      (validUntil != null && validUntil!.isBefore(DateTime.now()));

  bool get isUsed =>
      status == ClaimedOfferStatus.used || usedCount >= usageLimit;

  bool get isAvailable => !isExpired && !isUsed;

  int get remainingUses {
    final remaining = usageLimit - usedCount;
    return remaining > 0 ? remaining : 0;
  }

  String get effectiveStatusLabel {
    if (isUsed) return 'Used';
    if (isExpired) return 'Expired';
    return 'Available';
  }

  String get discountSummary {
    final value = discountValue % 1 == 0
        ? discountValue.toInt().toString()
        : discountValue.toStringAsFixed(2);
    if (discountType == OfferDiscountType.percent) {
      return '$value% off';
    }
    return '₹$value off';
  }
}
