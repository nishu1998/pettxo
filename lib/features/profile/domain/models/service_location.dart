class ServiceLocation {
  final double latitude;
  final double longitude;
  final String displayAddress;
  final String city;
  final String state;

  const ServiceLocation({
    required this.latitude,
    required this.longitude,
    required this.displayAddress,
    this.city = '',
    this.state = '',
  });

  bool get hasValidCoordinates => latitude != 0 || longitude != 0;
  bool get hasPublicArea => city.trim().isNotEmpty && state.trim().isNotEmpty;

  ServiceLocation copyWith({
    double? latitude,
    double? longitude,
    String? displayAddress,
    String? city,
    String? state,
  }) {
    return ServiceLocation(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      displayAddress: displayAddress ?? this.displayAddress,
      city: city ?? this.city,
      state: state ?? this.state,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'displayAddress': displayAddress,
      'city': city,
      'state': state,
    };
  }

  factory ServiceLocation.fromMap(Map<String, dynamic> data) {
    return ServiceLocation(
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      displayAddress: (data['displayAddress'] as String? ?? '').trim(),
      city: (data['city'] as String? ?? '').trim(),
      state: (data['state'] as String? ?? '').trim(),
    );
  }
}
