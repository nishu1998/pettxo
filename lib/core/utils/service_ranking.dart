class ServiceRankingInput {
  final double ratingAverage;
  final int ratingCount;
  final int completedBookingCount;
  final double distanceKm;
  final DateTime? updatedAt;
  final DateTime? publishedAt;
  final bool isActive;
  final double activeSponsorBoost;
  final double activeAdminRankBoost;
  final double trustBadgeSignal;

  const ServiceRankingInput({
    required this.ratingAverage,
    required this.ratingCount,
    required this.completedBookingCount,
    required this.distanceKm,
    required this.updatedAt,
    required this.publishedAt,
    required this.isActive,
    required this.activeSponsorBoost,
    required this.activeAdminRankBoost,
    this.trustBadgeSignal = 50,
  });
}

class ServiceRankingBreakdown {
  final double ratingScore;
  final double distanceScore;
  final double completedBookingScore;
  final double freshnessScore;
  final double trustBadgeScore;
  final double organicScore;
  final double finalRankingScore;

  const ServiceRankingBreakdown({
    required this.ratingScore,
    required this.distanceScore,
    required this.completedBookingScore,
    required this.freshnessScore,
    required this.trustBadgeScore,
    required this.organicScore,
    required this.finalRankingScore,
  });
}

class ServiceRanking {
  static const double _neutralRatingScore = 60;
  static const double _neutralTrustBadgeScore = 50;
  static const int _completedBookingCap = 50;

  const ServiceRanking._();

  static ServiceRankingBreakdown calculate(ServiceRankingInput input) {
    final ratingScore = calculateRatingScore(
      ratingAverage: input.ratingAverage,
      ratingCount: input.ratingCount,
    );
    final distanceScore = calculateDistanceScore(input.distanceKm);
    final completedBookingScore = calculateCompletedBookingScore(
      input.completedBookingCount,
    );
    final freshnessScore = calculateFreshnessScore(
      updatedAt: input.updatedAt,
      publishedAt: input.publishedAt,
      isActive: input.isActive,
    );
    final trustBadgeScore = calculateTrustBadgeScore(input.trustBadgeSignal);
    final organicScore = _round2(
      (ratingScore * 0.40) +
          (distanceScore * 0.30) +
          (completedBookingScore * 0.15) +
          (freshnessScore * 0.10) +
          (trustBadgeScore * 0.05),
    );
    final finalRankingScore = _round2(
      organicScore + input.activeSponsorBoost + input.activeAdminRankBoost,
    );

    return ServiceRankingBreakdown(
      ratingScore: ratingScore,
      distanceScore: distanceScore,
      completedBookingScore: completedBookingScore,
      freshnessScore: freshnessScore,
      trustBadgeScore: trustBadgeScore,
      organicScore: organicScore,
      finalRankingScore: finalRankingScore,
    );
  }

  static double calculateRatingScore({
    required double ratingAverage,
    required int ratingCount,
  }) {
    if (ratingCount <= 0) return _neutralRatingScore;
    final normalized = (ratingAverage.clamp(0, 5) / 5) * 100;
    return _round2(normalized);
  }

  static double calculateDistanceScore(double distanceKm) {
    if (distanceKm <= 0) return 100;
    if (distanceKm <= 2) return 100;
    if (distanceKm >= 50) return 0;

    final score = 100 - (((distanceKm - 2) / 48) * 100);
    return _round2(score.clamp(0, 100));
  }

  static double calculateCompletedBookingScore(int completedBookingCount) {
    final normalized = (completedBookingCount.clamp(0, _completedBookingCap) /
            _completedBookingCap) *
        100;
    return _round2(normalized);
  }

  static double calculateFreshnessScore({
    required DateTime? updatedAt,
    required DateTime? publishedAt,
    required bool isActive,
    DateTime? now,
  }) {
    if (!isActive) return 0;
    final baseline = updatedAt ?? publishedAt;
    if (baseline == null) return 50;

    final reference = now ?? DateTime.now();
    final ageDays = reference.difference(baseline).inDays;

    if (ageDays <= 3) return 100;
    if (ageDays <= 14) return 85;
    if (ageDays <= 30) return 70;
    if (ageDays <= 60) return 55;
    if (ageDays <= 90) return 40;
    return 25;
  }

  static double calculateTrustBadgeScore(double? trustBadgeSignal) {
    final signal = trustBadgeSignal ?? _neutralTrustBadgeScore;
    return _round2(signal.clamp(0, 100));
  }

  static double _round2(double value) {
    return (value * 100).roundToDouble() / 100;
  }
}
