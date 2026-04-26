import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/utils/geohash.dart';
import '../../../../core/utils/service_ranking.dart';
import '../../../profile/domain/models/profile_service_listing.dart';

class ServiceModel {
  final String id;
  final String ownerUserId;
  final String ownerName;
  final String ownerUsername;
  final String ownerPhotoUrl;
  final String ownerCity;
  final String ownerState;
  final String title;
  final String animalType;
  final String category;
  final String description;
  final String privateNotes;
  final int pricePerSession;
  final String currency;
  final int sessionDurationMinutes;
  final int capacity;
  final List<String> availableDays;
  final int startMinutes;
  final int endMinutes;
  final bool sameForAllDays;
  // Deprecated: kept read-only for older Firestore documents that may still
  // carry radius coverage data. Active UI and writes no longer use it.
  final double serviceRadiusKm;
  final String serviceType;
  final String displayAddress;
  final double latitude;
  final double longitude;
  final String city;
  final String state;
  final List<String> photoUrls;
  final String primaryPhotoUrl;
  final String status;
  final bool isActive;
  final bool isDeleted;
  final bool isPaused;
  final String moderationStatus;
  final bool isVisibleToMarketplace;
  final double ratingAverage;
  final int ratingCount;
  final int completedBookingCount;
  final int reviewedBookingCount;
  final double trustScore;
  final double rankingScore;
  final double organicRankingScore;
  final double distanceKm;
  final bool isSponsored;
  final double sponsorBoost;
  final DateTime? sponsorStartAt;
  final DateTime? sponsorEndAt;
  final double adminRankBoost;
  final DateTime? adminPinnedUntil;
  final String promotionLabel;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? publishedAt;

  const ServiceModel({
    required this.id,
    required this.ownerUserId,
    required this.ownerName,
    required this.ownerUsername,
    required this.ownerPhotoUrl,
    required this.ownerCity,
    required this.ownerState,
    required this.title,
    required this.animalType,
    required this.category,
    required this.description,
    required this.privateNotes,
    required this.pricePerSession,
    required this.currency,
    required this.sessionDurationMinutes,
    required this.capacity,
    required this.availableDays,
    required this.startMinutes,
    required this.endMinutes,
    required this.sameForAllDays,
    this.serviceRadiusKm = 0,
    required this.serviceType,
    required this.displayAddress,
    required this.latitude,
    required this.longitude,
    required this.city,
    required this.state,
    required this.photoUrls,
    required this.primaryPhotoUrl,
    required this.status,
    required this.isActive,
    required this.isDeleted,
    required this.isPaused,
    required this.moderationStatus,
    required this.isVisibleToMarketplace,
    required this.ratingAverage,
    required this.ratingCount,
    this.completedBookingCount = 0,
    this.reviewedBookingCount = 0,
    this.trustScore = 0,
    this.rankingScore = 0,
    this.organicRankingScore = 0,
    this.distanceKm = 0,
    this.isSponsored = false,
    this.sponsorBoost = 0,
    this.sponsorStartAt,
    this.sponsorEndAt,
    this.adminRankBoost = 0,
    this.adminPinnedUntil,
    this.promotionLabel = '',
    required this.createdAt,
    required this.updatedAt,
    required this.publishedAt,
  });

  factory ServiceModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return ServiceModel.fromMap(doc.id, doc.data() ?? const {});
  }

  factory ServiceModel.fromMap(String id, Map<String, dynamic> data) {
    final location = data['location'] as Map<String, dynamic>? ?? const {};
    final ownerSnapshot =
        data['ownerSnapshot'] as Map<String, dynamic>? ?? const {};
    final stats = data['stats'] as Map<String, dynamic>? ?? const {};

    return ServiceModel(
      id: id,
      ownerUserId: (data['ownerUserId'] as String? ?? '').trim(),
      ownerName:
          (ownerSnapshot['name'] as String? ??
                  data['ownerName'] as String? ??
                  data['providerName'] as String? ??
                  '')
              .trim(),
      ownerUsername:
          (ownerSnapshot['username'] as String? ??
                  data['ownerUsername'] as String? ??
                  data['providerUsername'] as String? ??
                  '')
              .trim()
              .replaceFirst('@', ''),
      ownerPhotoUrl:
          (ownerSnapshot['photoUrl'] as String? ??
                  data['ownerPhotoUrl'] as String? ??
                  '')
              .trim(),
      ownerCity: (ownerSnapshot['city'] as String? ?? '').trim(),
      ownerState: (ownerSnapshot['state'] as String? ?? '').trim(),
      title: (data['title'] as String? ?? '').trim(),
      animalType: (data['animalType'] as String? ?? '').trim(),
      category: (data['category'] as String? ?? '').trim(),
      description: (data['description'] as String? ?? '').trim(),
      privateNotes: (data['privateNotes'] as String? ?? '').trim(),
      pricePerSession: (data['pricePerSession'] as num?)?.toInt() ?? 0,
      currency: (data['currency'] as String? ?? 'INR').trim(),
      sessionDurationMinutes:
          (data['sessionDurationMinutes'] as num?)?.toInt() ?? 0,
      capacity: (data['capacity'] as num?)?.toInt() ?? 1,
      availableDays: (data['availableDays'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      startMinutes: (data['startMinutes'] as num?)?.toInt() ?? 0,
      endMinutes: (data['endMinutes'] as num?)?.toInt() ?? 0,
      sameForAllDays: data['sameForAllDays'] as bool? ?? true,
      serviceRadiusKm: (data['serviceRadiusKm'] as num?)?.toDouble() ?? 0,
      serviceType: (data['serviceType'] as String? ?? '').trim(),
      displayAddress: (location['displayAddress'] as String? ?? '').trim(),
      latitude: (location['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (location['longitude'] as num?)?.toDouble() ?? 0,
      city: (location['city'] as String? ?? '').trim(),
      state: (location['state'] as String? ?? '').trim(),
      photoUrls: (data['photoUrls'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      primaryPhotoUrl: (data['primaryPhotoUrl'] as String? ?? '').trim(),
      status: (data['status'] as String? ?? 'active').trim(),
      isActive: data['isActive'] as bool? ?? false,
      isDeleted: data['isDeleted'] as bool? ?? false,
      isPaused: data['isPaused'] as bool? ?? false,
      moderationStatus: (data['moderationStatus'] as String? ?? 'pending')
          .trim(),
      isVisibleToMarketplace: data['isVisibleToMarketplace'] as bool? ?? false,
      ratingAverage:
          (stats['ratingAverage'] as num?)?.toDouble() ??
          (data['ratingAverage'] as num?)?.toDouble() ??
          0,
      ratingCount:
          (stats['ratingCount'] as num?)?.toInt() ??
          (data['ratingCount'] as num?)?.toInt() ??
          0,
      completedBookingCount:
          (stats['completedBookingsCount'] as num?)?.toInt() ??
          (data['completedBookingCount'] as num?)?.toInt() ??
          (data['completedBookingsCount'] as num?)?.toInt() ??
          0,
      reviewedBookingCount:
          (stats['reviewedBookingCount'] as num?)?.toInt() ??
          (data['reviewedBookingCount'] as num?)?.toInt() ??
          0,
      trustScore:
          (stats['trustScore'] as num?)?.toDouble() ??
          (data['trustScore'] as num?)?.toDouble() ??
          0,
      rankingScore: (data['rankingScore'] as num?)?.toDouble() ?? 0,
      organicRankingScore:
          (data['organicRankingScore'] as num?)?.toDouble() ?? 0,
      distanceKm: (data['distanceKm'] as num?)?.toDouble() ?? 0,
      isSponsored: data['isSponsored'] as bool? ?? false,
      sponsorBoost: (data['sponsorBoost'] as num?)?.toDouble() ?? 0,
      sponsorStartAt: _readDate(data['sponsorStartAt']),
      sponsorEndAt: _readDate(data['sponsorEndAt']),
      adminRankBoost: (data['adminRankBoost'] as num?)?.toDouble() ?? 0,
      adminPinnedUntil: _readDate(data['adminPinnedUntil']),
      promotionLabel: (data['promotionLabel'] as String? ?? '').trim(),
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
      publishedAt: _readDate(data['publishedAt']),
    );
  }

  Map<String, dynamic> toCreateMap() {
    return {
      'ownerUserId': ownerUserId,
      'ownerName': ownerName,
      'ownerUsername': ownerUsername,
      'ownerPhotoUrl': ownerPhotoUrl,
      'ownerSnapshot': {
        'name': ownerName,
        'username': ownerUsername,
        'photoUrl': ownerPhotoUrl,
        'city': ownerCity,
        'state': ownerState,
      },
      'title': title.trim(),
      'titleLowercase': title.trim().toLowerCase(),
      'animalType': animalType.trim(),
      'animalTypeLowercase': animalType.trim().toLowerCase(),
      'category': category.trim(),
      'categoryLowercase': category.trim().toLowerCase(),
      'description': description.trim(),
      'privateNotes': privateNotes.trim(),
      'pricePerSession': pricePerSession,
      'currency': currency,
      'sessionDurationMinutes': sessionDurationMinutes,
      'capacity': capacity,
      'availableDays': availableDays,
      'startMinutes': startMinutes,
      'endMinutes': endMinutes,
      'sameForAllDays': sameForAllDays,
      'serviceType': serviceType,
      'location': {
        'displayAddress': displayAddress.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'geohash': Geohash.encode(latitude, longitude),
        'city': city.trim(),
        'state': state.trim(),
        'country': 'IN',
      },
      'photoUrls': photoUrls,
      'primaryPhotoUrl': primaryPhotoUrl,
      'status': status,
      'isActive': isActive,
      'isDeleted': isDeleted,
      'isPaused': isPaused,
      // Moderation can hide listings later by flipping this visibility flag.
      // New services remain visible until admin tooling introduces review gates.
      'moderationStatus': moderationStatus,
      'isVisibleToMarketplace': isVisibleToMarketplace,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'publishedAt': FieldValue.serverTimestamp(),
    };
  }

  ProfileServiceListing toProfileListing() {
    return ProfileServiceListing(
      id: id,
      ownerUserId: ownerUserId,
      ownerName: ownerName,
      ownerUsername: ownerUsername,
      title: title,
      serviceType: category,
      animalType: animalType,
      category: category,
      serviceRadiusKm: 0,
      bookingServiceType: serviceType,
      latitude: latitude,
      longitude: longitude,
      description: description,
      rate: '₹$pricePerSession/session',
      pricePerSession: pricePerSession,
      durationMinutes: sessionDurationMinutes,
      location: displayAddress,
      availability:
          '${availableDays.join(', ')} - ${_formatTime(startMinutes)} to ${_formatTime(endMinutes)}',
      duration: sessionDurationMinutes >= 24 * 60
          ? 'Whole day'
          : '$sessionDurationMinutes min',
      petSize: animalType,
      rating: ratingCount > 0
          ? ratingLabel
          : 'No reviews yet',
      distance: '',
      imageUrl: primaryPhotoUrl,
      notes: privateNotes,
      photoPaths: photoUrls,
      isPaused: isPaused || status == 'paused',
      ratingAverage: ratingAverage,
      ratingCount: ratingCount,
      completedBookingCount: completedBookingCount,
      reviewedBookingCount: reviewedBookingCount,
      trustScore: trustScore,
      rankingScore: rankingScore,
      organicRankingScore: organicRankingScore,
      distanceKm: distanceKm,
      isSponsored: isSponsored,
      sponsorBoost: sponsorBoost,
      sponsorStartAt: sponsorStartAt,
      sponsorEndAt: sponsorEndAt,
      adminRankBoost: adminRankBoost,
      adminPinnedUntil: adminPinnedUntil,
      promotionLabel: promotionLabel,
    );
  }

  bool get hasReviews => ratingCount > 0;

  String get ratingLabel {
    if (!hasReviews) return 'No reviews yet';
    return '⭐ ${ratingAverage.toStringAsFixed(1)} · '
        '$ratingCount ${ratingCount == 1 ? 'review' : 'reviews'}';
  }

  bool get isSponsorActive {
    if (!isSponsored) return false;
    final now = DateTime.now();
    if (sponsorStartAt != null && sponsorStartAt!.isAfter(now)) return false;
    if (sponsorEndAt != null && sponsorEndAt!.isBefore(now)) return false;
    return true;
  }

  bool get isAdminPinnedActive {
    final until = adminPinnedUntil;
    if (until == null) return adminRankBoost > 0;
    return until.isAfter(DateTime.now());
  }

  double get activeSponsorBoost => isSponsorActive ? sponsorBoost : 0;

  double get activeAdminRankBoost => isAdminPinnedActive ? adminRankBoost : 0;

  String get sponsoredLabel => isSponsorActive ? 'Sponsored' : '';

  ServiceRankingInput get rankingInput {
    return ServiceRankingInput(
      ratingAverage: ratingAverage,
      ratingCount: ratingCount,
      completedBookingCount: completedBookingCount,
      distanceKm: distanceKm,
      updatedAt: updatedAt,
      publishedAt: publishedAt,
      isActive: isActive && !isDeleted && !isPaused,
      activeSponsorBoost: activeSponsorBoost,
      activeAdminRankBoost: activeAdminRankBoost,
    );
  }

  ServiceRankingBreakdown get rankingBreakdown {
    return ServiceRanking.calculate(rankingInput);
  }

  double get calculatedOrganicRankingScore => rankingBreakdown.organicScore;

  double get calculatedFinalRankingScore => rankingBreakdown.finalRankingScore;

  static DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static String _formatTime(int totalMinutes) {
    final hour = (totalMinutes ~/ 60) % 24;
    final minute = totalMinutes % 60;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $suffix';
  }
}

class ServicesPage {
  final List<ServiceModel> services;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;

  const ServicesPage({
    required this.services,
    required this.lastDocument,
    required this.hasMore,
  });
}
