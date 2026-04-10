class ProfileServiceListing {
  final String id;
  final String title;
  final String serviceType;
  final String description;
  final String rate;
  final String location;
  final String availability;
  final String duration;
  final String petSize;
  final String rating;
  final String distance;
  final String imageUrl;
  final bool isPaused;

  const ProfileServiceListing({
    required this.id,
    required this.title,
    required this.serviceType,
    required this.description,
    required this.rate,
    required this.location,
    required this.availability,
    required this.duration,
    required this.petSize,
    required this.rating,
    required this.distance,
    required this.imageUrl,
    this.isPaused = false,
  });

  ProfileServiceListing copyWith({bool? isPaused}) {
    return ProfileServiceListing(
      id: id,
      title: title,
      serviceType: serviceType,
      description: description,
      rate: rate,
      location: location,
      availability: availability,
      duration: duration,
      petSize: petSize,
      rating: rating,
      distance: distance,
      imageUrl: imageUrl,
      isPaused: isPaused ?? this.isPaused,
    );
  }

  factory ProfileServiceListing.fromMap(Map<String, dynamic> data) {
    return ProfileServiceListing(
      id: (data['id'] as String? ?? '').trim(),
      title: (data['title'] as String? ?? '').trim(),
      serviceType: (data['serviceType'] as String? ?? 'Pet Care').trim(),
      description: (data['description'] as String? ?? '').trim(),
      rate: (data['rate'] as String? ?? '').trim(),
      location: (data['location'] as String? ?? '').trim(),
      availability: (data['availability'] as String? ?? '').trim(),
      duration: (data['duration'] as String? ?? '').trim(),
      petSize: (data['petSize'] as String? ?? '').trim(),
      rating: (data['rating'] as String? ?? 'New').trim(),
      distance: (data['distance'] as String? ?? '').trim(),
      imageUrl: (data['imageUrl'] as String? ?? '').trim(),
      isPaused: data['isPaused'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'serviceType': serviceType,
      'description': description,
      'rate': rate,
      'location': location,
      'availability': availability,
      'duration': duration,
      'petSize': petSize,
      'rating': rating,
      'distance': distance,
      'imageUrl': imageUrl,
      'isPaused': isPaused,
    };
  }
}
