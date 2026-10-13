import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum ForegroundLocationAvailability {
  granted,
  denied,
  permanentlyDenied,
  serviceDisabled,
  unavailable,
}

@immutable
class ForegroundDeviceLocation {
  const ForegroundDeviceLocation({
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    this.accuracy,
  });

  final double latitude;
  final double longitude;
  final DateTime capturedAt;
  final double? accuracy;
}

@immutable
class ForegroundLocationResult {
  const ForegroundLocationResult({required this.availability, this.location});

  final ForegroundLocationAvailability availability;
  final ForegroundDeviceLocation? location;

  bool get hasLocation => location != null;
}

abstract class ForegroundLocationPlatform {
  Future<bool> isLocationServiceEnabled();

  Future<LocationPermission> checkPermission();

  Future<LocationPermission> requestPermission();

  Future<ForegroundDeviceLocation> getCurrentLocation();

  Future<bool> openAppSettings();

  Future<bool> openLocationSettings();
}

class GeolocatorForegroundLocationPlatform
    implements ForegroundLocationPlatform {
  const GeolocatorForegroundLocationPlatform();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<ForegroundDeviceLocation> getCurrentLocation() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
      ),
    );
    return ForegroundDeviceLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      capturedAt: position.timestamp,
    );
  }

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();
}

/// The single foreground-only location gateway used throughout Pettxo.
///
/// It owns permission request de-duplication and a short-lived in-memory
/// location cache. Feature repositories remain responsible for deciding when
/// a fresh reading is required and whether it should be persisted.
class ForegroundLocationManager {
  ForegroundLocationManager({
    ForegroundLocationPlatform? platform,
    this.cacheMaxAge = const Duration(minutes: 5),
  }) : _platform = platform ?? const GeolocatorForegroundLocationPlatform();

  static final ForegroundLocationManager instance = ForegroundLocationManager();

  final ForegroundLocationPlatform _platform;
  final Duration cacheMaxAge;
  final ValueNotifier<ForegroundLocationAvailability> availability =
      ValueNotifier<ForegroundLocationAvailability>(
        ForegroundLocationAvailability.unavailable,
      );

  ForegroundDeviceLocation? _cachedLocation;
  Future<ForegroundLocationAvailability>? _permissionRequest;
  Future<ForegroundLocationResult>? _locationRequest;

  ForegroundDeviceLocation? get cachedLocation {
    final cached = _cachedLocation;
    if (cached == null || !_isCacheFresh(cached)) return null;
    return cached;
  }

  Future<ForegroundLocationAvailability> refreshPermissionStatus() async {
    try {
      if (!await _platform.isLocationServiceEnabled()) {
        return _setAvailability(ForegroundLocationAvailability.serviceDisabled);
      }
      final permission = await _platform.checkPermission();
      return _setAvailability(_mapPermission(permission));
    } catch (_) {
      return _setAvailability(ForegroundLocationAvailability.unavailable);
    }
  }

  Future<ForegroundLocationAvailability> requestForegroundPermission() {
    final active = _permissionRequest;
    if (active != null) return active;

    final request = _requestForegroundPermission();
    _permissionRequest = request;
    return request.whenComplete(() {
      if (identical(_permissionRequest, request)) {
        _permissionRequest = null;
      }
    });
  }

  Future<ForegroundLocationAvailability> _requestForegroundPermission() async {
    try {
      if (!await _platform.isLocationServiceEnabled()) {
        return _setAvailability(ForegroundLocationAvailability.serviceDisabled);
      }
      var permission = await _platform.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _platform.requestPermission();
      }
      return _setAvailability(_mapPermission(permission));
    } catch (_) {
      return _setAvailability(ForegroundLocationAvailability.unavailable);
    }
  }

  Future<ForegroundLocationResult> getLocation({
    bool requestPermission = false,
    bool forceRefresh = false,
  }) {
    if (!forceRefresh) {
      final cached = cachedLocation;
      if (cached != null) {
        return Future<ForegroundLocationResult>.value(
          ForegroundLocationResult(
            availability: ForegroundLocationAvailability.granted,
            location: cached,
          ),
        );
      }
    }

    final active = _locationRequest;
    if (active != null) return active;
    final request = _getLocation(requestPermission: requestPermission);
    _locationRequest = request;
    return request.whenComplete(() {
      if (identical(_locationRequest, request)) {
        _locationRequest = null;
      }
    });
  }

  Future<ForegroundLocationResult> _getLocation({
    required bool requestPermission,
  }) async {
    final permission = requestPermission
        ? await requestForegroundPermission()
        : await refreshPermissionStatus();
    if (permission != ForegroundLocationAvailability.granted) {
      return ForegroundLocationResult(availability: permission);
    }

    try {
      final location = await _platform.getCurrentLocation();
      _cachedLocation = location;
      _setAvailability(ForegroundLocationAvailability.granted);
      return ForegroundLocationResult(
        availability: ForegroundLocationAvailability.granted,
        location: location,
      );
    } catch (_) {
      return ForegroundLocationResult(
        availability: _setAvailability(
          ForegroundLocationAvailability.unavailable,
        ),
      );
    }
  }

  Future<bool> openAppSettings() => _platform.openAppSettings();

  Future<bool> openLocationSettings() => _platform.openLocationSettings();

  void clearMemoryCache() => _cachedLocation = null;

  bool _isCacheFresh(ForegroundDeviceLocation location) =>
      DateTime.now().difference(location.capturedAt) <= cacheMaxAge;

  ForegroundLocationAvailability _setAvailability(
    ForegroundLocationAvailability value,
  ) {
    if (availability.value != value) availability.value = value;
    return value;
  }

  ForegroundLocationAvailability _mapPermission(LocationPermission permission) {
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => ForegroundLocationAvailability.granted,
      LocationPermission.deniedForever =>
        ForegroundLocationAvailability.permanentlyDenied,
      LocationPermission.denied || LocationPermission.unableToDetermine =>
        ForegroundLocationAvailability.denied,
    };
  }
}
