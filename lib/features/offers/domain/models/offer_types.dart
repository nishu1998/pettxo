enum OfferDisplayType { offerWall, popup }

enum OfferCampaignType { firstBooking, festival, general, rebooking }

enum OfferDiscountType { flat, percent }

enum OfferClaimValidityType { lifelong, fixedDate, daysAfterClaim }

enum ClaimedOfferStatus { claimed, used, expired }

extension OfferDisplayTypeX on OfferDisplayType {
  String get value => switch (this) {
    OfferDisplayType.offerWall => 'offerWall',
    OfferDisplayType.popup => 'popup',
  };

  static OfferDisplayType fromValue(String value) {
    return switch (value.trim()) {
      'popup' => OfferDisplayType.popup,
      _ => OfferDisplayType.offerWall,
    };
  }
}

extension OfferCampaignTypeX on OfferCampaignType {
  String get value => switch (this) {
    OfferCampaignType.firstBooking => 'firstBooking',
    OfferCampaignType.festival => 'festival',
    OfferCampaignType.general => 'general',
    OfferCampaignType.rebooking => 'rebooking',
  };

  static OfferCampaignType fromValue(String value) {
    return switch (value.trim()) {
      'festival' => OfferCampaignType.festival,
      'general' => OfferCampaignType.general,
      'rebooking' => OfferCampaignType.rebooking,
      _ => OfferCampaignType.firstBooking,
    };
  }
}

extension OfferDiscountTypeX on OfferDiscountType {
  String get value => switch (this) {
    OfferDiscountType.flat => 'flat',
    OfferDiscountType.percent => 'percent',
  };

  static OfferDiscountType fromValue(String value) {
    return switch (value.trim()) {
      'percent' => OfferDiscountType.percent,
      _ => OfferDiscountType.flat,
    };
  }
}

extension OfferClaimValidityTypeX on OfferClaimValidityType {
  String get value => switch (this) {
    OfferClaimValidityType.lifelong => 'lifelong',
    OfferClaimValidityType.fixedDate => 'fixedDate',
    OfferClaimValidityType.daysAfterClaim => 'daysAfterClaim',
  };

  static OfferClaimValidityType fromValue(String value) {
    return switch (value.trim()) {
      'fixedDate' => OfferClaimValidityType.fixedDate,
      'daysAfterClaim' => OfferClaimValidityType.daysAfterClaim,
      _ => OfferClaimValidityType.lifelong,
    };
  }
}

extension ClaimedOfferStatusX on ClaimedOfferStatus {
  String get value => switch (this) {
    ClaimedOfferStatus.claimed => 'claimed',
    ClaimedOfferStatus.used => 'used',
    ClaimedOfferStatus.expired => 'expired',
  };

  static ClaimedOfferStatus fromValue(String value) {
    return switch (value.trim()) {
      'used' => ClaimedOfferStatus.used,
      'expired' => ClaimedOfferStatus.expired,
      _ => ClaimedOfferStatus.claimed,
    };
  }
}
