class UserProfile {
  final String uid;
  final String email;
  final String role;
  final String name;
  final String username;
  final String usernameLowercase;
  final String phone;
  final String state;
  final String city;
  final String legacyLocation;
  final String bio;
  final String profileImageUrl;
  final double ratingAverage;
  final int ratingCount;

  const UserProfile({
    required this.uid,
    required this.email,
    required this.role,
    required this.name,
    required this.username,
    required this.usernameLowercase,
    required this.phone,
    required this.state,
    required this.city,
    required this.legacyLocation,
    required this.bio,
    required this.profileImageUrl,
    required this.ratingAverage,
    required this.ratingCount,
  });

  factory UserProfile.fromMap(Map<String, dynamic> data) {
    final username = (data['username'] as String? ?? '').trim();
    final normalizedUsername = username.replaceFirst('@', '').trim();

    return UserProfile(
      uid: (data['uid'] as String? ?? '').trim(),
      email: (data['email'] as String? ?? '').trim(),
      role: (data['role'] as String? ?? 'petParent').trim(),
      name: (data['name'] as String? ?? '').trim(),
      username: normalizedUsername,
      usernameLowercase:
          (data['usernameLowercase'] as String? ?? normalizedUsername)
              .trim()
              .toLowerCase(),
      phone: (data['phone'] as String? ?? data['mobileNumber'] as String? ?? '')
          .trim(),
      state: (data['state'] as String? ?? '').trim(),
      city: (data['city'] as String? ?? '').trim(),
      legacyLocation: (data['location'] as String? ?? '').trim(),
      bio: (data['bio'] as String? ?? '').trim(),
      profileImageUrl: (data['profileImage'] as String? ?? '').trim(),
      ratingAverage: (data['ratingAverage'] as num?)?.toDouble() ?? 0,
      ratingCount: (data['ratingCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'role': role,
      'name': name,
      'username': username,
      'usernameLowercase': usernameLowercase,
      'phone': phone,
      'state': state,
      'city': city,
      'location': location,
      'bio': bio,
      'profileImage': profileImageUrl,
      'ratingAverage': ratingAverage,
      'ratingCount': ratingCount,
    };
  }

  String get mobileNumber => phone;

  String get location {
    if (city.isNotEmpty && state.isNotEmpty) {
      return '$city, $state';
    }
    if (city.isNotEmpty) return city;
    if (state.isNotEmpty) return state;
    return legacyLocation;
  }

  bool get isServiceProvider => role == 'serviceProvider';

  String get roleLabel {
    return switch (role) {
      'serviceProvider' => 'Service Provider',
      'petLover' => 'Pet Lover',
      _ => 'Pet Parent',
    };
  }

  String get displayUsername => username.isEmpty ? '' : '@$username';

  bool get hasReviews => ratingCount > 0;

  String get providerReviewSummary {
    if (!hasReviews) return 'New provider';
    return '⭐ ${ratingAverage.toStringAsFixed(1)} · $ratingCount ${ratingCount == 1 ? 'review' : 'reviews'}';
  }

  String get initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'P';
    return trimmed.substring(0, 1).toUpperCase();
  }
}
