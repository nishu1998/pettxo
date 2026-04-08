class UserProfile {
  final String uid;
  final String email;
  final String role;
  final String name;
  final String username;
  final String usernameLowercase;
  final String location;
  final String bio;
  final String profileImageUrl;

  const UserProfile({
    required this.uid,
    required this.email,
    required this.role,
    required this.name,
    required this.username,
    required this.usernameLowercase,
    required this.location,
    required this.bio,
    required this.profileImageUrl,
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
      location: (data['location'] as String? ?? '').trim(),
      bio: (data['bio'] as String? ?? '').trim(),
      profileImageUrl: (data['profileImage'] as String? ?? '').trim(),
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
      'location': location,
      'bio': bio,
      'profileImage': profileImageUrl,
    };
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

  String get initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'P';
    return trimmed.substring(0, 1).toUpperCase();
  }
}
