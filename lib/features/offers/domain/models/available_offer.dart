import 'offer_types.dart';

class AvailableOffer {
  final String id;
  final String title;
  final String description;
  final String couponCode;
  final OfferDisplayType displayType;
  final OfferCampaignType campaignType;
  final OfferDiscountType discountType;
  final double discountValue;
  final double? maxDiscountAmount;
  final double? minBookingAmount;
  final int usageLimitPerUser;
  final int priority;
  final DateTime? startAt;
  final DateTime? endAt;

  const AvailableOffer({
    required this.id,
    required this.title,
    required this.description,
    required this.couponCode,
    required this.displayType,
    required this.campaignType,
    required this.discountType,
    required this.discountValue,
    required this.maxDiscountAmount,
    required this.minBookingAmount,
    required this.usageLimitPerUser,
    required this.priority,
    required this.startAt,
    required this.endAt,
  });

  factory AvailableOffer.fromMap(Map<String, dynamic> data) {
    return AvailableOffer(
      id: (data['id'] as String? ?? '').trim(),
      title: (data['title'] as String? ?? '').trim(),
      description: (data['description'] as String? ?? '').trim(),
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

  String get displayTitle => title.isEmpty ? 'Offer' : title;

  String get discountSummary {
    final value = discountValue % 1 == 0
        ? discountValue.toInt().toString()
        : discountValue.toStringAsFixed(2);
    if (discountType == OfferDiscountType.percent) {
      return '$value% off';
    }
    return '₹$value off';
  }

  String get usageSummary {
    return usageLimitPerUser == 1
        ? '1 use per account'
        : '$usageLimitPerUser uses per account';
  }

  String get availabilitySummary {
    if (endAt != null) {
      return 'Available until ${_formatDate(endAt!)}';
    }
    return 'Available now';
  }

  static String _formatDate(DateTime date) {
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
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

class AvailableOffersResult {
  final AvailableOffer? offerWall;
  final AvailableOffer? popup;
  final List<AvailableOffer> offers;

  const AvailableOffersResult({
    required this.offerWall,
    required this.popup,
    required this.offers,
  });

  static const empty = AvailableOffersResult(
    offerWall: null,
    popup: null,
    offers: [],
  );

  factory AvailableOffersResult.fromMap(Map<String, dynamic> data) {
    final offers = (data['offers'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((raw) => AvailableOffer.fromMap(Map<String, dynamic>.from(raw)))
        .where((offer) => offer.id.isNotEmpty)
        .toList();

    AvailableOffer? readOffer(String key) {
      final value = data[key];
      if (value is! Map) return null;
      final offer = AvailableOffer.fromMap(Map<String, dynamic>.from(value));
      return offer.id.isEmpty ? null : offer;
    }

    return AvailableOffersResult(
      offerWall: readOffer('offerWall'),
      popup: readOffer('popup'),
      offers: offers,
    );
  }
}
