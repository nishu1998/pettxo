import 'package:shared_preferences/shared_preferences.dart';

import 'foreground_location_manager.dart';

abstract class LocationStartupPromptStore {
  Future<bool> wasShownFor(String uid);

  Future<void> markShownFor(String uid);
}

class SharedPreferencesLocationStartupPromptStore
    implements LocationStartupPromptStore {
  static const String _keyPrefix = 'foreground_location_intro_v1_';

  @override
  Future<void> markShownFor(String uid) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('$_keyPrefix$uid', true);
  }

  @override
  Future<bool> wasShownFor(String uid) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool('$_keyPrefix$uid') ?? false;
  }
}

enum AuthenticatedLocationPromptDecision {
  showExplanation,
  alreadyGranted,
  previouslyHandled,
  unavailable,
}

class AuthenticatedLocationPermissionService {
  AuthenticatedLocationPermissionService({
    ForegroundLocationManager? locationManager,
    LocationStartupPromptStore? promptStore,
  }) : _locationManager = locationManager ?? ForegroundLocationManager.instance,
       _promptStore =
           promptStore ?? SharedPreferencesLocationStartupPromptStore();

  final ForegroundLocationManager _locationManager;
  final LocationStartupPromptStore _promptStore;
  final Map<String, Future<AuthenticatedLocationPromptDecision>> _preparations =
      <String, Future<AuthenticatedLocationPromptDecision>>{};
  final Set<String> _reservedPrompts = <String>{};

  Future<AuthenticatedLocationPromptDecision> prepareForUser(String uid) {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      return Future<AuthenticatedLocationPromptDecision>.value(
        AuthenticatedLocationPromptDecision.unavailable,
      );
    }
    final active = _preparations[normalizedUid];
    if (active != null) return active;
    final preparation = _prepareForUser(normalizedUid);
    _preparations[normalizedUid] = preparation;
    return preparation.whenComplete(() {
      if (identical(_preparations[normalizedUid], preparation)) {
        _preparations.remove(normalizedUid);
      }
    });
  }

  Future<void> recordPromptShown(String uid) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) return;
    await _promptStore.markShownFor(normalizedUid);
  }

  Future<AuthenticatedLocationPromptDecision> _prepareForUser(
    String uid,
  ) async {
    final status = await _locationManager.refreshPermissionStatus();
    if (status == ForegroundLocationAvailability.granted) {
      return AuthenticatedLocationPromptDecision.alreadyGranted;
    }
    if (status == ForegroundLocationAvailability.permanentlyDenied) {
      return AuthenticatedLocationPromptDecision.previouslyHandled;
    }
    if (_reservedPrompts.contains(uid) || await _promptStore.wasShownFor(uid)) {
      return AuthenticatedLocationPromptDecision.previouslyHandled;
    }
    if (status != ForegroundLocationAvailability.denied &&
        status != ForegroundLocationAvailability.serviceDisabled) {
      return AuthenticatedLocationPromptDecision.unavailable;
    }

    // Reserve in memory immediately. The UI persists only once it is still
    // mounted and actually about to display the explanation.
    _reservedPrompts.add(uid);
    return AuthenticatedLocationPromptDecision.showExplanation;
  }
}
