import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pettexo/core/services/foreground_location_manager.dart';

void main() {
  group('ForegroundLocationManager', () {
    test('reuses granted permission without requesting again', () async {
      final platform = _FakeLocationPlatform(
        permission: LocationPermission.whileInUse,
      );
      final manager = ForegroundLocationManager(platform: platform);

      expect(
        await manager.requestForegroundPermission(),
        ForegroundLocationAvailability.granted,
      );
      expect(platform.permissionRequestCount, 0);
    });

    test('reports denied and permanently denied distinctly', () async {
      final deniedPlatform = _FakeLocationPlatform(
        permission: LocationPermission.denied,
        requestedPermission: LocationPermission.denied,
      );
      final deniedManager = ForegroundLocationManager(platform: deniedPlatform);
      expect(
        await deniedManager.requestForegroundPermission(),
        ForegroundLocationAvailability.denied,
      );

      final permanentPlatform = _FakeLocationPlatform(
        permission: LocationPermission.deniedForever,
      );
      final permanentManager = ForegroundLocationManager(
        platform: permanentPlatform,
      );
      expect(
        await permanentManager.refreshPermissionStatus(),
        ForegroundLocationAvailability.permanentlyDenied,
      );
    });

    test('reports disabled location services without requesting', () async {
      final platform = _FakeLocationPlatform(
        serviceEnabled: false,
        permission: LocationPermission.denied,
      );
      final manager = ForegroundLocationManager(platform: platform);

      expect(
        await manager.requestForegroundPermission(),
        ForegroundLocationAvailability.serviceDisabled,
      );
      expect(platform.permissionRequestCount, 0);
    });

    test('rechecks permission after returning from system settings', () async {
      final platform = _FakeLocationPlatform(
        permission: LocationPermission.deniedForever,
      );
      final manager = ForegroundLocationManager(platform: platform);

      expect(
        await manager.refreshPermissionStatus(),
        ForegroundLocationAvailability.permanentlyDenied,
      );
      platform.permission = LocationPermission.whileInUse;
      expect(
        await manager.refreshPermissionStatus(),
        ForegroundLocationAvailability.granted,
      );
    });

    test('deduplicates concurrent permission requests', () async {
      final requestCompleter = Completer<LocationPermission>();
      final platform = _FakeLocationPlatform(
        permission: LocationPermission.denied,
        permissionRequest: requestCompleter.future,
      );
      final manager = ForegroundLocationManager(platform: platform);

      final first = manager.requestForegroundPermission();
      final second = manager.requestForegroundPermission();
      await Future<void>.delayed(Duration.zero);
      expect(platform.permissionRequestCount, 1);

      requestCompleter.complete(LocationPermission.whileInUse);
      expect(await first, ForegroundLocationAvailability.granted);
      expect(await second, ForegroundLocationAvailability.granted);
    });

    test(
      'reuses a fresh cached location and refreshes when required',
      () async {
        final platform = _FakeLocationPlatform(
          permission: LocationPermission.whileInUse,
        );
        final manager = ForegroundLocationManager(platform: platform);

        final first = await manager.getLocation();
        final cached = await manager.getLocation();
        final refreshed = await manager.getLocation(forceRefresh: true);

        expect(first.hasLocation, isTrue);
        expect(cached.hasLocation, isTrue);
        expect(refreshed.hasLocation, isTrue);
        expect(platform.locationRequestCount, 2);
      },
    );
  });
}

class _FakeLocationPlatform implements ForegroundLocationPlatform {
  _FakeLocationPlatform({
    this.serviceEnabled = true,
    required this.permission,
    this.requestedPermission = LocationPermission.whileInUse,
    this.permissionRequest,
  });

  bool serviceEnabled;
  LocationPermission permission;
  LocationPermission requestedPermission;
  Future<LocationPermission>? permissionRequest;
  int permissionRequestCount = 0;
  int locationRequestCount = 0;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<ForegroundDeviceLocation> getCurrentLocation() async {
    locationRequestCount += 1;
    return ForegroundDeviceLocation(
      latitude: 28.61,
      longitude: 77.20,
      capturedAt: DateTime.now(),
    );
  }

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequestCount += 1;
    final result =
        await (permissionRequest ?? Future.value(requestedPermission));
    permission = result;
    return result;
  }
}
