import 'package:cloud_firestore/cloud_firestore.dart';

class CanonicalBookingPrivateData {
  final String bookingId;
  final String parentId;
  final String providerId;
  final String parentOtpCode;
  final String otpState;
  final int failedAttemptCount;
  final DateTime? lockedUntil;
  final DateTime? verifiedAt;
  final DateTime? contactUnlockedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CanonicalBookingPrivateData({
    required this.bookingId,
    required this.parentId,
    required this.providerId,
    required this.parentOtpCode,
    required this.otpState,
    required this.failedAttemptCount,
    required this.lockedUntil,
    required this.verifiedAt,
    required this.contactUnlockedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CanonicalBookingPrivateData.fromMap(Map<String, dynamic> map) {
    return CanonicalBookingPrivateData(
      bookingId: (map['bookingId'] as String? ?? '').trim(),
      parentId: (map['parentId'] as String? ?? '').trim(),
      providerId: (map['providerId'] as String? ?? '').trim(),
      parentOtpCode:
          (map['parentOtpCode'] as String? ??
                  map['otpCode'] as String? ??
                  map['serviceOtp'] as String? ??
                  '')
              .trim(),
      otpState: (map['otpState'] as String? ?? '').trim(),
      failedAttemptCount: (map['failedAttemptCount'] as num?)?.toInt() ?? 0,
      lockedUntil: _readDate(map['lockedUntil']),
      verifiedAt: _readDate(map['verifiedAt']),
      contactUnlockedAt: _readDate(map['contactUnlockedAt']),
      createdAt: _readDate(map['createdAt']),
      updatedAt: _readDate(map['updatedAt']),
    );
  }

  bool get hasOtp => parentOtpCode.isNotEmpty;
  bool get isOtpActive => otpState.toUpperCase() == 'ACTIVE' && hasOtp;

  static DateTime? _readDate(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}

class CanonicalBookingPrivateParticipantsData {
  final String bookingId;
  final String parentId;
  final String providerId;
  final bool unlockedAfterPaidOnly;
  final String fullName;
  final String phoneNumber;
  final String email;
  final String exactAddress;
  final double? latitude;
  final double? longitude;
  final String providerPhoneNumber;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CanonicalBookingPrivateParticipantsData({
    required this.bookingId,
    required this.parentId,
    required this.providerId,
    required this.unlockedAfterPaidOnly,
    required this.fullName,
    required this.phoneNumber,
    required this.email,
    required this.exactAddress,
    required this.latitude,
    required this.longitude,
    required this.providerPhoneNumber,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CanonicalBookingPrivateParticipantsData.fromMap(
    Map<String, dynamic> map,
  ) {
    final parentPrivate = Map<String, dynamic>.from(
      map['parentPrivate'] as Map? ?? const {},
    );
    final providerPrivate = Map<String, dynamic>.from(
      map['providerPrivate'] as Map? ?? const {},
    );
    final legacyAddress =
        (map['serviceAddress'] as String? ??
                map['exactAddress'] as String? ??
                map['address'] as String? ??
                '')
            .trim();
    final legacyPhoneNumber =
        (map['phoneNumber'] as String? ??
                map['customerPhoneNumber'] as String? ??
                '')
            .trim();
    final legacyProviderPhoneNumber =
        (map['providerPhoneNumber'] as String? ??
                map['providerContactNumber'] as String? ??
                '')
            .trim();
    return CanonicalBookingPrivateParticipantsData(
      bookingId: (map['bookingId'] as String? ?? '').trim(),
      parentId: (map['parentId'] as String? ?? '').trim(),
      providerId: (map['providerId'] as String? ?? '').trim(),
      unlockedAfterPaidOnly: map['unlockedAfterPaidOnly'] as bool? ?? false,
      fullName:
          (parentPrivate['fullName'] as String? ??
                  map['fullName'] as String? ??
                  '')
              .trim(),
      phoneNumber:
          (parentPrivate['phoneNumber'] as String? ?? legacyPhoneNumber).trim(),
      email:
          (parentPrivate['email'] as String? ?? map['email'] as String? ?? '')
              .trim(),
      exactAddress: (parentPrivate['exactAddress'] as String? ?? legacyAddress)
          .trim(),
      latitude:
          _readDouble(parentPrivate['latitude']) ??
          _readDouble(map['latitude']),
      longitude:
          _readDouble(parentPrivate['longitude']) ??
          _readDouble(map['longitude']),
      providerPhoneNumber:
          (providerPrivate['phoneNumber'] as String? ??
                  legacyProviderPhoneNumber)
              .trim(),
      createdAt: CanonicalBookingPrivateData._readDate(map['createdAt']),
      updatedAt: CanonicalBookingPrivateData._readDate(map['updatedAt']),
    );
  }

  bool get hasPhoneNumber => phoneNumber.isNotEmpty;
  bool get hasAddress => exactAddress.isNotEmpty;
  bool get hasProviderPhoneNumber => providerPhoneNumber.isNotEmpty;
  bool get hasCoordinates => latitude != null && longitude != null;

  static double? _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    return null;
  }
}
