import 'package:flutter/material.dart';

enum ProfileType { petParent, serviceProvider, petLover }

extension ProfileTypeX on ProfileType {
  String get storedValue => name;

  String get label {
    return switch (this) {
      ProfileType.petParent => 'Pet Parent',
      ProfileType.serviceProvider => 'Service Provider',
      ProfileType.petLover => 'Pet Lover',
    };
  }

  String get badge {
    return switch (this) {
      ProfileType.petParent => 'For pet owners',
      ProfileType.serviceProvider => 'For professionals',
      ProfileType.petLover => 'For community',
    };
  }

  String get description {
    return switch (this) {
      ProfileType.petParent =>
        'Manage care, book services and track your pet’s journey.',
      ProfileType.serviceProvider =>
        'List services, get bookings and grow your business.',
      ProfileType.petLover =>
        'Explore pet stories and connect with the community.',
    };
  }

  IconData get icon {
    return switch (this) {
      ProfileType.petParent => Icons.pets_rounded,
      ProfileType.serviceProvider => Icons.work_outline_rounded,
      ProfileType.petLover => Icons.favorite_border_rounded,
    };
  }
}

ProfileType profileTypeFromStoredValue(String value) {
  final normalized = value.trim();
  return ProfileType.values.firstWhere(
    (type) => type.storedValue == normalized,
    orElse: () => ProfileType.petParent,
  );
}
