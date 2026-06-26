class ProfileServiceListing {
  final String id;
  final String ownerUserId;
  final String ownerName;
  final String ownerUsername;
  final String title;
  final String serviceType;
  final String animalType;
  final String category;
  // Deprecated: still read from older stored payloads so they deserialize
  // safely, but no active UI or write path depends on this field anymore.
  final double serviceRadiusKm;
  final String bookingServiceType;
  final double latitude;
  final double longitude;
  final String description;
  final String rate;
  final int pricePerSession;
  final int durationMinutes;
  final String location;
  final String availability;
  final String duration;
  final String petSize;
  final String rating;
  final double ratingAverage;
  final int ratingCount;
  final int completedBookingCount;
  final int reviewedBookingCount;
  final double trustScore;
  final double rankingScore;
  final double organicRankingScore;
  final double distanceKm;
  final bool isSponsored;
  final double sponsorBoost;
  final DateTime? sponsorStartAt;
  final DateTime? sponsorEndAt;
  final double adminRankBoost;
  final DateTime? adminPinnedUntil;
  final String promotionLabel;
  // Deprecated: preserved only for backward-compatible reads of older local
  // payloads/doc snapshots.
  final String distance;
  final String imageUrl;
  final String notes;
  final List<String> photoPaths;
  final bool isPaused;
  final bool isPausedByVerification;
  final String pauseReason;

  const ProfileServiceListing({
    required this.id,
    this.ownerUserId = '',
    this.ownerName = '',
    this.ownerUsername = '',
    required this.title,
    required this.serviceType,
    this.animalType = '',
    this.category = '',
    this.serviceRadiusKm = 0,
    this.bookingServiceType = '',
    this.latitude = 0,
    this.longitude = 0,
    required this.description,
    required this.rate,
    this.pricePerSession = 0,
    this.durationMinutes = 0,
    required this.location,
    required this.availability,
    required this.duration,
    required this.petSize,
    required this.rating,
    this.ratingAverage = 0,
    this.ratingCount = 0,
    this.completedBookingCount = 0,
    this.reviewedBookingCount = 0,
    this.trustScore = 0,
    this.rankingScore = 0,
    this.organicRankingScore = 0,
    this.distanceKm = 0,
    this.isSponsored = false,
    this.sponsorBoost = 0,
    this.sponsorStartAt,
    this.sponsorEndAt,
    this.adminRankBoost = 0,
    this.adminPinnedUntil,
    this.promotionLabel = '',
    required this.distance,
    required this.imageUrl,
    this.notes = '',
    this.photoPaths = const [],
    this.isPaused = false,
    this.isPausedByVerification = false,
    this.pauseReason = '',
  });

  ProfileServiceListing copyWith({
    bool? isPaused,
    bool? isPausedByVerification,
    String? pauseReason,
  }) {
    return ProfileServiceListing(
      id: id,
      ownerUserId: ownerUserId,
      ownerName: ownerName,
      ownerUsername: ownerUsername,
      title: title,
      serviceType: serviceType,
      animalType: animalType,
      category: category,
      serviceRadiusKm: serviceRadiusKm,
      bookingServiceType: bookingServiceType,
      latitude: latitude,
      longitude: longitude,
      description: description,
      rate: rate,
      pricePerSession: pricePerSession,
      durationMinutes: durationMinutes,
      location: location,
      availability: availability,
      duration: duration,
      petSize: petSize,
      rating: rating,
      ratingAverage: ratingAverage,
      ratingCount: ratingCount,
      completedBookingCount: completedBookingCount,
      reviewedBookingCount: reviewedBookingCount,
      trustScore: trustScore,
      rankingScore: rankingScore,
      organicRankingScore: organicRankingScore,
      distanceKm: distanceKm,
      isSponsored: isSponsored,
      sponsorBoost: sponsorBoost,
      sponsorStartAt: sponsorStartAt,
      sponsorEndAt: sponsorEndAt,
      adminRankBoost: adminRankBoost,
      adminPinnedUntil: adminPinnedUntil,
      promotionLabel: promotionLabel,
      distance: distance,
      imageUrl: imageUrl,
      notes: notes,
      photoPaths: photoPaths,
      isPaused: isPaused ?? this.isPaused,
      isPausedByVerification:
          isPausedByVerification ?? this.isPausedByVerification,
      pauseReason: pauseReason ?? this.pauseReason,
    );
  }

  List<String> get galleryImages {
    final values = <String>[imageUrl, ...photoPaths];
    final images = <String>[];
    for (final rawPath in values) {
      final path = rawPath.trim();
      if (path.isEmpty || images.contains(path)) continue;
      images.add(path);
    }
    return images;
  }

  bool get hasReviews => ratingCount > 0;

  String get providerDisplayName {
    final resolvedName = ownerName.trim();
    if (resolvedName.isNotEmpty) return resolvedName;
    final resolvedUsername = ownerUsername.trim().replaceFirst('@', '');
    if (resolvedUsername.isNotEmpty) return resolvedUsername;
    return 'Service provider';
  }

  String get reviewSummary {
    if (!hasReviews) return 'No reviews yet';
    return '⭐ ${ratingAverage.toStringAsFixed(1)} · $ratingCount ${ratingCount == 1 ? 'review' : 'reviews'}';
  }

  String get ratingLabel => reviewSummary;

  bool get isSponsorActive {
    if (!isSponsored) return false;
    final now = DateTime.now();
    if (sponsorStartAt != null && sponsorStartAt!.isAfter(now)) return false;
    if (sponsorEndAt != null && sponsorEndAt!.isBefore(now)) return false;
    return true;
  }

  bool get isAdminPinnedActive {
    final until = adminPinnedUntil;
    if (until == null) return adminRankBoost > 0;
    return until.isAfter(DateTime.now());
  }

  double get activeSponsorBoost => isSponsorActive ? sponsorBoost : 0;

  double get activeAdminRankBoost => isAdminPinnedActive ? adminRankBoost : 0;

  String get sponsoredLabel => isSponsorActive ? 'Sponsored' : '';

  factory ProfileServiceListing.fromMap(Map<String, dynamic> data) {
    return ProfileServiceListing(
      id: (data['id'] as String? ?? '').trim(),
      ownerUserId: (data['ownerUserId'] as String? ?? '').trim(),
      ownerName:
          (data['ownerName'] as String? ??
                  data['providerName'] as String? ??
                  '')
              .trim(),
      ownerUsername:
          (data['ownerUsername'] as String? ??
                  data['providerUsername'] as String? ??
                  '')
              .trim()
              .replaceFirst('@', ''),
      title: (data['title'] as String? ?? '').trim(),
      serviceType: (data['serviceType'] as String? ?? 'Pet Care').trim(),
      animalType: (data['animalType'] as String? ?? '').trim(),
      category: (data['category'] as String? ?? '').trim(),
      serviceRadiusKm: (data['serviceRadiusKm'] as num?)?.toDouble() ?? 0,
      bookingServiceType: (data['bookingServiceType'] as String? ?? '').trim(),
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      description: (data['description'] as String? ?? '').trim(),
      rate: (data['rate'] as String? ?? '').trim(),
      pricePerSession: (data['pricePerSession'] as num?)?.toInt() ?? 0,
      durationMinutes: (data['durationMinutes'] as num?)?.toInt() ?? 0,
      location: (data['location'] as String? ?? '').trim(),
      availability: (data['availability'] as String? ?? '').trim(),
      duration: (data['duration'] as String? ?? '').trim(),
      petSize: (data['petSize'] as String? ?? '').trim(),
      rating: (data['rating'] as String? ?? 'New').trim(),
      ratingAverage: (data['ratingAverage'] as num?)?.toDouble() ?? 0,
      ratingCount: (data['ratingCount'] as num?)?.toInt() ?? 0,
      completedBookingCount:
          (data['completedBookingCount'] as num?)?.toInt() ??
          (data['completedBookingsCount'] as num?)?.toInt() ??
          0,
      reviewedBookingCount:
          (data['reviewedBookingCount'] as num?)?.toInt() ?? 0,
      trustScore: (data['trustScore'] as num?)?.toDouble() ?? 0,
      rankingScore: (data['rankingScore'] as num?)?.toDouble() ?? 0,
      organicRankingScore:
          (data['organicRankingScore'] as num?)?.toDouble() ?? 0,
      distanceKm: (data['distanceKm'] as num?)?.toDouble() ?? 0,
      isSponsored: data['isSponsored'] as bool? ?? false,
      sponsorBoost: (data['sponsorBoost'] as num?)?.toDouble() ?? 0,
      sponsorStartAt: _readDate(data['sponsorStartAt']),
      sponsorEndAt: _readDate(data['sponsorEndAt']),
      adminRankBoost: (data['adminRankBoost'] as num?)?.toDouble() ?? 0,
      adminPinnedUntil: _readDate(data['adminPinnedUntil']),
      promotionLabel: (data['promotionLabel'] as String? ?? '').trim(),
      distance: (data['distance'] as String? ?? '').trim(),
      imageUrl: (data['imageUrl'] as String? ?? '').trim(),
      notes: (data['notes'] as String? ?? '').trim(),
      photoPaths: (data['photoPaths'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      isPaused: data['isPaused'] as bool? ?? false,
      isPausedByVerification: data['isPausedByVerification'] as bool? ?? false,
      pauseReason: (data['pauseReason'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ownerUserId': ownerUserId,
      'ownerName': ownerName,
      'ownerUsername': ownerUsername,
      'title': title,
      'serviceType': serviceType,
      'animalType': animalType,
      'category': category,
      'bookingServiceType': bookingServiceType,
      'latitude': latitude,
      'longitude': longitude,
      'description': description,
      'rate': rate,
      'pricePerSession': pricePerSession,
      'durationMinutes': durationMinutes,
      'location': location,
      'availability': availability,
      'duration': duration,
      'petSize': petSize,
      'rating': rating,
      'ratingAverage': ratingAverage,
      'ratingCount': ratingCount,
      'completedBookingCount': completedBookingCount,
      'reviewedBookingCount': reviewedBookingCount,
      'trustScore': trustScore,
      'rankingScore': rankingScore,
      'organicRankingScore': organicRankingScore,
      'distanceKm': distanceKm,
      'isSponsored': isSponsored,
      'sponsorBoost': sponsorBoost,
      'sponsorStartAt': sponsorStartAt,
      'sponsorEndAt': sponsorEndAt,
      'adminRankBoost': adminRankBoost,
      'adminPinnedUntil': adminPinnedUntil,
      'promotionLabel': promotionLabel,
      'imageUrl': imageUrl,
      'notes': notes,
      'photoPaths': photoPaths,
      'isPaused': isPaused,
      'isPausedByVerification': isPausedByVerification,
      'pauseReason': pauseReason,
    };
  }

  static DateTime? _readDate(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    try {
      return (value as dynamic)?.toDate() as DateTime?;
    } catch (_) {
      return null;
    }
  }
}
