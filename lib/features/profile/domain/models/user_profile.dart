import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/identity/username_utils.dart';
import '../../../restrictions/domain/models/user_restriction_state.dart';

class UserProfile {
  final String uid;
  final String displayName;
  final String photoUrl;
  final String email;
  final bool emailVerified;
  final String role;
  final String name;
  final String username;
  final String usernameLowercase;
  final String phoneNumber;
  final bool phoneVerified;
  final List<String> providers;
  final String phone;
  final String country;
  final String state;
  final String city;
  final String address;
  final String legacyLocation;
  final String bio;
  final String profileImageUrl;
  final double ratingAverage;
  final int ratingCount;
  final int followingCount;
  final int followerCount;
  final bool hasFollowCounts;
  final String accountStatus;
  final bool isDeleted;
  final bool isActive;
  final bool deletionRequested;
  final String profileVisibility;
  final UserRestrictionState restrictionState;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? acceptedTermsAt;
  final DateTime? acceptedPrivacyAt;
  final DateTime? acceptedProviderAgreementAt;

  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.photoUrl,
    required this.email,
    required this.emailVerified,
    required this.role,
    required this.name,
    required this.username,
    required this.usernameLowercase,
    required this.phoneNumber,
    required this.phoneVerified,
    required this.providers,
    required this.phone,
    required this.country,
    required this.state,
    required this.city,
    required this.address,
    required this.legacyLocation,
    required this.bio,
    required this.profileImageUrl,
    required this.ratingAverage,
    required this.ratingCount,
    required this.followingCount,
    required this.followerCount,
    required this.hasFollowCounts,
    required this.accountStatus,
    required this.isDeleted,
    required this.isActive,
    required this.deletionRequested,
    required this.profileVisibility,
    required this.restrictionState,
    required this.createdAt,
    required this.updatedAt,
    required this.acceptedTermsAt,
    required this.acceptedPrivacyAt,
    required this.acceptedProviderAgreementAt,
  });

  factory UserProfile.fromMap(Map<String, dynamic> data) {
    final username = normalizeUsername(
      (data['username'] as String? ?? '').trim(),
    );
    final hasFollowCounts = _hasAnyKey(data, const [
      'followingCount',
      'followingsCount',
      'following',
      'followerCount',
      'followersCount',
      'followers',
    ]);
    final displayName =
        (data['displayName'] as String? ?? data['name'] as String? ?? '')
            .trim();
    final photoUrl =
        (data['photoUrl'] as String? ?? data['profileImage'] as String? ?? '')
            .trim();
    final phoneNumber =
        (data['phoneNumber'] as String? ??
                data['phone'] as String? ??
                data['mobileNumber'] as String? ??
                '')
            .trim();
    final providers = ((data['providers'] as List?) ?? const <dynamic>[])
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);

    return UserProfile(
      uid: (data['uid'] as String? ?? '').trim(),
      displayName: displayName,
      photoUrl: photoUrl,
      email: (data['email'] as String? ?? '').trim(),
      emailVerified: data['emailVerified'] == true,
      role: (data['role'] as String? ?? 'petParent').trim(),
      name: displayName,
      username: username,
      usernameLowercase: normalizeUsername(
        (data['usernameLowercase'] as String? ?? username).trim(),
      ),
      phoneNumber: phoneNumber,
      phoneVerified:
          data['phoneVerified'] == true ||
          (phoneNumber.isNotEmpty && providers.contains('phone')),
      providers: providers,
      phone: phoneNumber,
      country: (data['country'] as String? ?? '').trim(),
      state: (data['state'] as String? ?? '').trim(),
      city: (data['city'] as String? ?? '').trim(),
      address: (data['address'] as String? ?? '').trim(),
      legacyLocation: (data['location'] as String? ?? '').trim(),
      bio: (data['bio'] as String? ?? '').trim(),
      profileImageUrl: photoUrl,
      ratingAverage: (data['ratingAverage'] as num?)?.toDouble() ?? 0,
      ratingCount: (data['ratingCount'] as num?)?.toInt() ?? 0,
      followingCount: _readCount(data, const [
        'followingCount',
        'followingsCount',
        'following',
      ]),
      followerCount: _readCount(data, const [
        'followerCount',
        'followersCount',
        'followers',
      ]),
      hasFollowCounts: hasFollowCounts,
      accountStatus: (data['accountStatus'] as String? ?? 'active').trim(),
      isDeleted: data['isDeleted'] == true,
      isActive: data.containsKey('isActive') ? data['isActive'] != false : true,
      deletionRequested: data['deletionRequested'] == true,
      profileVisibility: (data['profileVisibility'] as String? ?? 'public')
          .trim(),
      restrictionState: UserRestrictionState.fromMap(data),
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
      acceptedTermsAt: _readDate(data['acceptedTermsAt']),
      acceptedPrivacyAt: _readDate(data['acceptedPrivacyAt']),
      acceptedProviderAgreementAt: _readDate(
        data['acceptedProviderAgreementAt'],
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'role': role,
      'name': displayName,
      'username': username,
      'usernameLowercase': usernameLowercase,
      'email': email,
      'emailVerified': emailVerified,
      'phoneNumber': phoneNumber,
      'phone': phoneNumber,
      'phoneVerified': phoneVerified,
      'providers': providers,
      'country': country,
      'state': state,
      'city': city,
      'address': address,
      'location': location,
      'bio': bio,
      'profileImage': photoUrl,
      'ratingAverage': ratingAverage,
      'ratingCount': ratingCount,
      'followingCount': followingCount,
      'followerCount': followerCount,
      'accountStatus': accountStatus,
      'isDeleted': isDeleted,
      'isActive': isActive,
      'deletionRequested': deletionRequested,
      'profileVisibility': profileVisibility,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  static DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static int _readCount(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return 0;
  }

  static bool _hasAnyKey(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      if (data.containsKey(key)) return true;
    }
    return false;
  }

  String get mobileNumber => phone;

  String get location {
    if (address.isNotEmpty) return address;
    if (legacyLocation.isNotEmpty) return legacyLocation;

    final parts = <String>[
      city,
      state,
      country,
    ].where((part) => part.trim().isNotEmpty).toList(growable: false);
    if (parts.isNotEmpty) {
      return parts.join(', ');
    }

    return '';
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

  bool get isLegacyDeletedProfile {
    final normalizedName = name.trim().toLowerCase();
    final normalizedUsername = usernameLowercase.trim();
    return normalizedName == 'deleted user' ||
        normalizedUsername.startsWith('deleted_');
  }

  bool get isUnavailableAccountStatus {
    final normalizedStatus = accountStatus.trim().toLowerCase();
    return normalizedStatus == 'deleted' ||
        normalizedStatus == 'deactivated' ||
        normalizedStatus == 'disabled' ||
        normalizedStatus == 'pendingdeletion' ||
        normalizedStatus == 'deletioninprogress';
  }

  bool get isPendingDeletion {
    return accountStatus.trim().toLowerCase() == 'pendingdeletion' ||
        deletionRequested;
  }

  bool get isPubliclyVisible {
    if (isDeleted ||
        isPendingDeletion ||
        profileVisibility.toLowerCase() == 'hidden' ||
        isUnavailableAccountStatus ||
        isLegacyDeletedProfile) {
      return false;
    }
    return isActive;
  }

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
