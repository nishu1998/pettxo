class ProfileServiceListing {
  final String id;
  final String ownerUserId;
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
  // Deprecated: preserved only for backward-compatible reads of older local
  // payloads/doc snapshots.
  final String distance;
  final String imageUrl;
  final String notes;
  final List<String> photoPaths;
  final bool isPaused;

  const ProfileServiceListing({
    required this.id,
    this.ownerUserId = '',
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
    required this.distance,
    required this.imageUrl,
    this.notes = '',
    this.photoPaths = const [],
    this.isPaused = false,
  });

  ProfileServiceListing copyWith({bool? isPaused}) {
    return ProfileServiceListing(
      id: id,
      ownerUserId: ownerUserId,
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
      distance: distance,
      imageUrl: imageUrl,
      notes: notes,
      photoPaths: photoPaths,
      isPaused: isPaused ?? this.isPaused,
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

  factory ProfileServiceListing.fromMap(Map<String, dynamic> data) {
    return ProfileServiceListing(
      id: (data['id'] as String? ?? '').trim(),
      ownerUserId: (data['ownerUserId'] as String? ?? '').trim(),
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
      distance: (data['distance'] as String? ?? '').trim(),
      imageUrl: (data['imageUrl'] as String? ?? '').trim(),
      notes: (data['notes'] as String? ?? '').trim(),
      photoPaths: (data['photoPaths'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      isPaused: data['isPaused'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ownerUserId': ownerUserId,
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
      'imageUrl': imageUrl,
      'notes': notes,
      'photoPaths': photoPaths,
      'isPaused': isPaused,
    };
  }
}
