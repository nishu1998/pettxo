import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/utils/geohash.dart';
import '../../../core/utils/service_distance_utils.dart';
import '../domain/models/explore_location_snapshot.dart';

enum ExploreLocationAvailability {
  ready,
  permissionNotRequested,
  permissionDenied,
  permissionPermanentlyDenied,
  serviceDisabled,
  unavailable,
}

class ExploreLocationState {
  final ExploreLocationAvailability availability;
  final ExploreLocationSnapshot snapshot;

  const ExploreLocationState({
    required this.availability,
    this.snapshot = ExploreLocationSnapshot.empty,
  });

  bool get hasCoordinates => snapshot.hasCoordinates;
  bool get canRetryPermission =>
      availability == ExploreLocationAvailability.permissionDenied ||
      availability == ExploreLocationAvailability.permissionNotRequested;
}

class ExploreLocationRepository {
  ExploreLocationRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  static const String _privateCollection = 'userPrivate';
  static const String _locationField = 'exploreLocation';
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _uid => _auth.currentUser?.uid.trim() ?? '';

  Future<ExploreLocationSnapshot> loadStoredSnapshot() async {
    final uid = _uid;
    if (uid.isEmpty) return ExploreLocationSnapshot.empty;

    final snapshot = await _firestore
        .collection(_privateCollection)
        .doc(uid)
        .get();
    final data = snapshot.data();
    if (data == null) return ExploreLocationSnapshot.empty;
    return _fromPrivateMap(data[_locationField] as Map<String, dynamic>?);
  }

  Future<ExploreLocationState> ensureLocation({
    bool requestPermission = false,
    bool refreshDeviceLocation = false,
  }) async {
    final stored = await loadStoredSnapshot();
    if (stored.hasCoordinates && !refreshDeviceLocation) {
      return ExploreLocationState(
        availability: ExploreLocationAvailability.ready,
        snapshot: stored,
      );
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return ExploreLocationState(
        availability: ExploreLocationAvailability.serviceDisabled,
        snapshot: stored,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (requestPermission && permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return ExploreLocationState(
        availability: requestPermission
            ? ExploreLocationAvailability.permissionDenied
            : ExploreLocationAvailability.permissionNotRequested,
        snapshot: stored,
      );
    }
    if (permission == LocationPermission.deniedForever) {
      return ExploreLocationState(
        availability: ExploreLocationAvailability.permissionPermanentlyDenied,
        snapshot: stored,
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      final nextSnapshot = await _buildSnapshotFromPosition(position);
      await _persistSnapshot(nextSnapshot);
      return ExploreLocationState(
        availability: ExploreLocationAvailability.ready,
        snapshot: nextSnapshot,
      );
    } catch (_) {
      if (stored.hasCoordinates) {
        return ExploreLocationState(
          availability: ExploreLocationAvailability.ready,
          snapshot: stored,
        );
      }
      return ExploreLocationState(
        availability: ExploreLocationAvailability.unavailable,
        snapshot: stored,
      );
    }
  }

  Future<void> openAppSettings() => Geolocator.openAppSettings();

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  Future<void> clearStoredSnapshot() async {
    final uid = _uid;
    if (uid.isEmpty) return;
    await _firestore
        .collection(_privateCollection)
        .doc(uid)
        .set(<String, dynamic>{
          _locationField: FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  ExploreLocationSnapshot _fromPrivateMap(Map<String, dynamic>? data) {
    if (data == null) return ExploreLocationSnapshot.empty;
    final rawUpdatedAt = data['updatedAt'];
    return ExploreLocationSnapshot(
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      city: (data['city'] as String? ?? '').trim(),
      state: (data['state'] as String? ?? '').trim(),
      country: (data['country'] as String? ?? '').trim(),
      geohash3: (data['geohash3'] as String? ?? '').trim(),
      geohash4: (data['geohash4'] as String? ?? '').trim(),
      geohash5: (data['geohash5'] as String? ?? '').trim(),
      updatedAt: rawUpdatedAt is Timestamp
          ? rawUpdatedAt.toDate()
          : (rawUpdatedAt is DateTime ? rawUpdatedAt : null),
    );
  }

  Future<ExploreLocationSnapshot> _buildSnapshotFromPosition(
    Position position,
  ) async {
    final latitude = position.latitude;
    final longitude = position.longitude;
    if (!ServiceDistanceUtils.hasUsableCoordinates(latitude, longitude)) {
      return ExploreLocationSnapshot.empty;
    }

    String city = '';
    String state = '';
    String country = '';
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        city = (place.locality ?? place.subAdministrativeArea ?? '').trim();
        state = (place.administrativeArea ?? '').trim();
        country = (place.country ?? '').trim();
      }
    } catch (_) {
      // Nearby feed can still work without reverse-geocoded labels.
    }

    final fullGeohash = Geohash.encode(latitude, longitude, precision: 5);
    return ExploreLocationSnapshot(
      latitude: latitude,
      longitude: longitude,
      city: city,
      state: state,
      country: country,
      geohash3: fullGeohash.length >= 3 ? fullGeohash.substring(0, 3) : '',
      geohash4: fullGeohash.length >= 4 ? fullGeohash.substring(0, 4) : '',
      geohash5: fullGeohash,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _persistSnapshot(ExploreLocationSnapshot snapshot) async {
    final uid = _uid;
    if (uid.isEmpty || !snapshot.hasCoordinates) return;

    await _firestore.collection(_privateCollection).doc(uid).set(
      <String, dynamic>{
        _locationField: <String, dynamic>{
          'latitude': snapshot.latitude,
          'longitude': snapshot.longitude,
          'city': snapshot.city,
          'state': snapshot.state,
          'country': snapshot.country,
          'geohash3': snapshot.geohash3,
          'geohash4': snapshot.geohash4,
          'geohash5': snapshot.geohash5,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
