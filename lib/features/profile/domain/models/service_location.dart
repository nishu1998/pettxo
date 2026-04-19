class ServiceLocation {
  final double latitude;
  final double longitude;
  final String displayAddress;

  const ServiceLocation({
    required this.latitude,
    required this.longitude,
    required this.displayAddress,
  });

  bool get hasValidCoordinates => latitude != 0 || longitude != 0;

  ServiceLocation copyWith({
    double? latitude,
    double? longitude,
    String? displayAddress,
  }) {
    return ServiceLocation(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      displayAddress: displayAddress ?? this.displayAddress,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'displayAddress': displayAddress,
    };
  }

  factory ServiceLocation.fromMap(Map<String, dynamic> data) {
    return ServiceLocation(
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      displayAddress: (data['displayAddress'] as String? ?? '').trim(),
    );
  }
}
