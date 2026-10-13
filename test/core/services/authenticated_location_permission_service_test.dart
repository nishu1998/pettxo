import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pettexo/core/services/authenticated_location_permission_service.dart';
import 'package:pettexo/core/services/foreground_location_manager.dart';

void main() {
  test(
    'first authenticated entry shows once and records the decision',
    () async {
      final store = _MemoryPromptStore();
      final service = AuthenticatedLocationPermissionService(
        locationManager: ForegroundLocationManager(
          platform: _PermissionPlatform(LocationPermission.denied),
        ),
        promptStore: store,
      );

      expect(
        await service.prepareForUser('user-1'),
        AuthenticatedLocationPromptDecision.showExplanation,
      );
      expect(store.markCount, 0);
      await service.recordPromptShown('user-1');
      expect(
        await service.prepareForUser('user-1'),
        AuthenticatedLocationPromptDecision.previouslyHandled,
      );
      expect(store.markCount, 1);
    },
  );

  test('granted permission does not show or persist an intro', () async {
    final store = _MemoryPromptStore();
    final service = AuthenticatedLocationPermissionService(
      locationManager: ForegroundLocationManager(
        platform: _PermissionPlatform(LocationPermission.whileInUse),
      ),
      promptStore: store,
    );

    expect(
      await service.prepareForUser('user-1'),
      AuthenticatedLocationPromptDecision.alreadyGranted,
    );
    expect(store.markCount, 0);
  });

  test('permanently denied permission is not repeatedly requested', () async {
    final store = _MemoryPromptStore();
    final service = AuthenticatedLocationPermissionService(
      locationManager: ForegroundLocationManager(
        platform: _PermissionPlatform(LocationPermission.deniedForever),
      ),
      promptStore: store,
    );

    expect(
      await service.prepareForUser('user-1'),
      AuthenticatedLocationPromptDecision.previouslyHandled,
    );
    expect(store.markCount, 0);
  });
}

class _MemoryPromptStore implements LocationStartupPromptStore {
  final Set<String> _shown = <String>{};
  int markCount = 0;

  @override
  Future<void> markShownFor(String uid) async {
    markCount += 1;
    _shown.add(uid);
  }

  @override
  Future<bool> wasShownFor(String uid) async => _shown.contains(uid);
}

class _PermissionPlatform implements ForegroundLocationPlatform {
  _PermissionPlatform(this.permission);

  LocationPermission permission;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<ForegroundDeviceLocation> getCurrentLocation() async {
    return ForegroundDeviceLocation(
      latitude: 28.61,
      longitude: 77.20,
      capturedAt: DateTime.now(),
    );
  }

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  Future<LocationPermission> requestPermission() async => permission;
}
