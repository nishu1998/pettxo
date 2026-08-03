class ExploreLocationSnapshot {
  final double latitude;
  final double longitude;
  final String city;
  final String state;
  final String country;
  final String geohash3;
  final String geohash4;
  final String geohash5;
  final DateTime? updatedAt;

  const ExploreLocationSnapshot({
    required this.latitude,
    required this.longitude,
    required this.city,
    required this.state,
    required this.country,
    required this.geohash3,
    required this.geohash4,
    required this.geohash5,
    required this.updatedAt,
  });

  static const empty = ExploreLocationSnapshot(
    latitude: 0,
    longitude: 0,
    city: '',
    state: '',
    country: '',
    geohash3: '',
    geohash4: '',
    geohash5: '',
    updatedAt: null,
  );

  bool get hasCoordinates =>
      latitude.isFinite &&
      longitude.isFinite &&
      (latitude != 0 || longitude != 0) &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  bool get hasCityStateFallback =>
      city.trim().isNotEmpty || state.trim().isNotEmpty;

  String get normalizedCity => city.trim().toLowerCase();
  String get normalizedState => state.trim().toLowerCase();

  factory ExploreLocationSnapshot.fromMap(Map<String, dynamic>? data) {
    if (data == null) return ExploreLocationSnapshot.empty;
    final updatedAtRaw = data['updatedAt'];
    return ExploreLocationSnapshot(
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      city: (data['city'] as String? ?? '').trim(),
      state: (data['state'] as String? ?? '').trim(),
      country: (data['country'] as String? ?? '').trim(),
      geohash3: (data['geohash3'] as String? ?? '').trim(),
      geohash4: (data['geohash4'] as String? ?? '').trim(),
      geohash5: (data['geohash5'] as String? ?? '').trim(),
      updatedAt: updatedAtRaw is DateTime ? updatedAtRaw : null,
    );
  }

  Map<String, dynamic> toPrivateMap() {
    return <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'city': city,
      'state': state,
      'country': country,
      'geohash3': geohash3,
      'geohash4': geohash4,
      'geohash5': geohash5,
      if (updatedAt != null) 'updatedAt': updatedAt,
    };
  }

  ExploreLocationSnapshot copyWith({
    double? latitude,
    double? longitude,
    String? city,
    String? state,
    String? country,
    String? geohash3,
    String? geohash4,
    String? geohash5,
    DateTime? updatedAt,
  }) {
    return ExploreLocationSnapshot(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      geohash3: geohash3 ?? this.geohash3,
      geohash4: geohash4 ?? this.geohash4,
      geohash5: geohash5 ?? this.geohash5,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
