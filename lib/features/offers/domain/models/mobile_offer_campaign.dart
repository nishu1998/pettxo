import 'offer_types.dart';

class MobileOfferCampaign {
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
  final OfferClaimValidityType claimValidityType;
  final int usageLimitPerUser;
  final int priority;
  final DateTime? startAt;
  final DateTime? endAt;

  const MobileOfferCampaign({
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
    required this.claimValidityType,
    required this.usageLimitPerUser,
    required this.priority,
    required this.startAt,
    required this.endAt,
  });

  factory MobileOfferCampaign.fromMap(Map<String, dynamic> data) {
    return MobileOfferCampaign(
      id: (data['id'] as String? ?? '').trim(),
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
      claimValidityType: OfferClaimValidityTypeX.fromValue(
        data['claimValidityType'] as String? ?? '',
      ),
      usageLimitPerUser: (data['usageLimitPerUser'] as num?)?.toInt() ?? 1,
      priority: (data['priority'] as num?)?.toInt() ?? 0,
      startAt: _readDate(data['startAt']),
      endAt: _readDate(data['endAt']),
    );
  }

  static DateTime? _readDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim())?.toLocal();
    }
    return null;
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

  String get validitySummary {
    return switch (claimValidityType) {
      OfferClaimValidityType.lifelong => 'Claim once, keep it until used',
      OfferClaimValidityType.fixedDate => 'Limited-time claim window',
      OfferClaimValidityType.daysAfterClaim => 'Valid for a limited time after claim',
    };
  }
}

class EligibleOffersResult {
  final MobileOfferCampaign? offerWall;
  final MobileOfferCampaign? popup;
  final List<MobileOfferCampaign> offers;

  const EligibleOffersResult({
    required this.offerWall,
    required this.popup,
    required this.offers,
  });

  static const empty = EligibleOffersResult(
    offerWall: null,
    popup: null,
    offers: [],
  );

  factory EligibleOffersResult.fromMap(Map<String, dynamic> data) {
    final offers = (data['offers'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((raw) => MobileOfferCampaign.fromMap(Map<String, dynamic>.from(raw)))
        .toList();

    MobileOfferCampaign? readOffer(String key) {
      final value = data[key];
      if (value is! Map) return null;
      return MobileOfferCampaign.fromMap(Map<String, dynamic>.from(value));
    }

    return EligibleOffersResult(
      offerWall: readOffer('offerWall'),
      popup: readOffer('popup'),
      offers: offers,
    );
  }
}
