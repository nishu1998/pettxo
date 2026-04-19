class ProfileServiceListing {
  final String id;
  final String title;
  final String serviceType;
  final String animalType;
  final String category;
  final double serviceRadiusKm;
  final String bookingServiceType;
  final double latitude;
  final double longitude;
  final String description;
  final String rate;
  final String location;
  final String availability;
  final String duration;
  final String petSize;
  final String rating;
  final String distance;
  final String imageUrl;
  final String notes;
  final List<String> photoPaths;
  final bool isPaused;

  const ProfileServiceListing({
    required this.id,
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

  factory ProfileServiceListing.fromMap(Map<String, dynamic> data) {
    return ProfileServiceListing(
      id: (data['id'] as String? ?? '').trim(),
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
      'title': title,
      'serviceType': serviceType,
      'animalType': animalType,
      'category': category,
      'serviceRadiusKm': serviceRadiusKm,
      'bookingServiceType': bookingServiceType,
      'latitude': latitude,
      'longitude': longitude,
      'description': description,
      'rate': rate,
      'location': location,
      'availability': availability,
      'duration': duration,
      'petSize': petSize,
      'rating': rating,
      'distance': distance,
      'imageUrl': imageUrl,
      'notes': notes,
      'photoPaths': photoPaths,
      'isPaused': isPaused,
    };
  }
}
