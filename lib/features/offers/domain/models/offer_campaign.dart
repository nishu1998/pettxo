import 'package:cloud_firestore/cloud_firestore.dart';

import 'offer_types.dart';

class OfferCampaignTargeting {
  final bool firstBookingOnly;
  final bool rebookingOnly;

  const OfferCampaignTargeting({
    required this.firstBookingOnly,
    required this.rebookingOnly,
  });

  factory OfferCampaignTargeting.fromMap(Map<String, dynamic>? data) {
    final source = data ?? const <String, dynamic>{};
    return OfferCampaignTargeting(
      firstBookingOnly: source['firstBookingOnly'] as bool? ?? false,
      rebookingOnly: source['rebookingOnly'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'firstBookingOnly': firstBookingOnly,
      'rebookingOnly': rebookingOnly,
    };
  }
}

class OfferCampaign {
  final String id;
  final String title;
  final String description;
  final String imageUrl;
  final String couponCode;
  final OfferDisplayType displayType;
  final OfferCampaignType campaignType;
  final OfferDiscountType discountType;
  final double discountValue;
  final double? maxDiscountAmount;
  final double? minBookingAmount;
  final bool isActive;
  final DateTime? startAt;
  final DateTime? endAt;
  final OfferClaimValidityType claimValidityType;
  final DateTime? claimValidUntil;
  final int? validDaysAfterClaim;
  final int usageLimitPerUser;
  final OfferCampaignTargeting targeting;
  final int priority;
  final DateTime? createdAt;
  final String createdBy;
  final DateTime? updatedAt;
  final String updatedBy;

  const OfferCampaign({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.couponCode,
    required this.displayType,
    required this.campaignType,
    required this.discountType,
    required this.discountValue,
    required this.maxDiscountAmount,
    required this.minBookingAmount,
    required this.isActive,
    required this.startAt,
    required this.endAt,
    required this.claimValidityType,
    required this.claimValidUntil,
    required this.validDaysAfterClaim,
    required this.usageLimitPerUser,
    required this.targeting,
    required this.priority,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
  });

  factory OfferCampaign.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return OfferCampaign.fromMap(doc.id, doc.data() ?? const {});
  }

  factory OfferCampaign.fromMap(String id, Map<String, dynamic> data) {
    return OfferCampaign(
      id: id,
      title: (data['title'] as String? ?? '').trim(),
      description: (data['description'] as String? ?? '').trim(),
      imageUrl: (data['imageUrl'] as String? ?? '').trim(),
      couponCode: (data['couponCode'] as String? ?? '').trim(),
      displayType: OfferDisplayTypeX.fromValue(
        data['displayType'] as String? ?? '',
      ),
      campaignType: OfferCampaignTypeX.fromValue(
        data['campaignType'] as String? ?? '',
      ),
      discountType: OfferDiscountTypeX.fromValue(
        data['discountType'] as String? ?? '',
      ),
      discountValue: (data['discountValue'] as num?)?.toDouble() ?? 0,
      maxDiscountAmount: (data['maxDiscountAmount'] as num?)?.toDouble(),
      minBookingAmount: (data['minBookingAmount'] as num?)?.toDouble(),
      isActive: data['isActive'] as bool? ?? false,
      startAt: _readDate(data['startAt']),
      endAt: _readDate(data['endAt']),
      claimValidityType: OfferClaimValidityTypeX.fromValue(
        data['claimValidityType'] as String? ?? '',
      ),
      claimValidUntil: _readDate(data['claimValidUntil']),
      validDaysAfterClaim: (data['validDaysAfterClaim'] as num?)?.toInt(),
      usageLimitPerUser: (data['usageLimitPerUser'] as num?)?.toInt() ?? 1,
      targeting: OfferCampaignTargeting.fromMap(
        data['targeting'] as Map<String, dynamic>?,
      ),
      priority: (data['priority'] as num?)?.toInt() ?? 0,
      createdAt: _readDate(data['createdAt']),
      createdBy: (data['createdBy'] as String? ?? '').trim(),
      updatedAt: _readDate(data['updatedAt']),
      updatedBy: (data['updatedBy'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'couponCode': couponCode,
      'displayType': displayType.value,
      'campaignType': campaignType.value,
      'discountType': discountType.value,
      'discountValue': discountValue,
      'maxDiscountAmount': maxDiscountAmount,
      'minBookingAmount': minBookingAmount,
      'isActive': isActive,
      'startAt': startAt,
      'endAt': endAt,
      'claimValidityType': claimValidityType.value,
      'claimValidUntil': claimValidUntil,
      'validDaysAfterClaim': validDaysAfterClaim,
      'usageLimitPerUser': usageLimitPerUser,
      'targeting': targeting.toMap(),
      'priority': priority,
      'createdAt': createdAt,
      'createdBy': createdBy,
      'updatedAt': updatedAt,
      'updatedBy': updatedBy,
    };
  }

  static DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
