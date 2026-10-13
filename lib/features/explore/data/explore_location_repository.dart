import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';

import '../../../core/services/foreground_location_manager.dart';
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
  ExploreLocationRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    ForegroundLocationManager? locationManager,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _locationManager = locationManager ?? ForegroundLocationManager.instance;

  static const String _privateCollection = 'userPrivate';
  static const String _locationField = 'exploreLocation';
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final ForegroundLocationManager _locationManager;

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

    final result = await _locationManager.getLocation(
      requestPermission: requestPermission,
      forceRefresh: refreshDeviceLocation,
    );
    final location = result.location;
    if (location != null) {
      final nextSnapshot = await _buildSnapshotFromLocation(location);
      await _persistSnapshot(nextSnapshot);
      return ExploreLocationState(
        availability: ExploreLocationAvailability.ready,
        snapshot: nextSnapshot,
      );
    }

    if (stored.hasCoordinates) {
      return ExploreLocationState(
        availability: ExploreLocationAvailability.ready,
        snapshot: stored,
      );
    }
    return ExploreLocationState(
      availability: _mapAvailability(
        result.availability,
        requestedPermission: requestPermission,
      ),
      snapshot: stored,
    );
  }

  /// Captures the device's current position for an immutable, post-specific
  /// creation record. Unlike [ensureLocation], this never substitutes a
  /// previously stored snapshot when a fresh reading is unavailable.
  Future<ExploreLocationSnapshot> captureFreshPostLocation({
    bool requestPermission = true,
  }) async {
    final state = await captureFreshPostLocationState(
      requestPermission: requestPermission,
    );
    return state.snapshot;
  }

  Future<ExploreLocationState> captureFreshPostLocationState({
    bool requestPermission = true,
  }) async {
    final result = await _locationManager.getLocation(
      requestPermission: requestPermission,
      forceRefresh: true,
    );
    final location = result.location;
    if (location == null) {
      return ExploreLocationState(
        availability: _mapAvailability(
          result.availability,
          requestedPermission: requestPermission,
        ),
      );
    }

    final snapshot = await _buildSnapshotFromLocation(location);
    if (!snapshot.hasCoordinates) {
      return const ExploreLocationState(
        availability: ExploreLocationAvailability.unavailable,
      );
    }
    try {
      await _persistSnapshot(snapshot);
    } catch (_) {
      // A post-specific intent can still be committed atomically with the
      // post. Failure to refresh the reusable viewer snapshot must not discard
      // a valid fresh reading.
    }
    return ExploreLocationState(
      availability: ExploreLocationAvailability.ready,
      snapshot: snapshot,
    );
  }

  Future<void> openAppSettings() async {
    await _locationManager.openAppSettings();
  }

  Future<void> openLocationSettings() async {
    await _locationManager.openLocationSettings();
  }

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

  Future<ExploreLocationSnapshot> _buildSnapshotFromLocation(
    ForegroundDeviceLocation location,
  ) async {
    final latitude = location.latitude;
    final longitude = location.longitude;
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
      updatedAt: location.capturedAt,
    );
  }

  ExploreLocationAvailability _mapAvailability(
    ForegroundLocationAvailability availability, {
    required bool requestedPermission,
  }) {
    return switch (availability) {
      ForegroundLocationAvailability.granted =>
        ExploreLocationAvailability.unavailable,
      ForegroundLocationAvailability.denied =>
        requestedPermission
            ? ExploreLocationAvailability.permissionDenied
            : ExploreLocationAvailability.permissionNotRequested,
      ForegroundLocationAvailability.permanentlyDenied =>
        ExploreLocationAvailability.permissionPermanentlyDenied,
      ForegroundLocationAvailability.serviceDisabled =>
        ExploreLocationAvailability.serviceDisabled,
      ForegroundLocationAvailability.unavailable =>
        ExploreLocationAvailability.unavailable,
    };
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
