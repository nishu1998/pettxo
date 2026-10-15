import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ProfileTourCompletionStore {
  Future<bool> read(String key);

  Future<void> write(String key, bool value);
}

class SharedPreferencesProfileTourCompletionStore
    implements ProfileTourCompletionStore {
  const SharedPreferencesProfileTourCompletionStore();

  @override
  Future<bool> read(String key) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(key) ?? false;
  }

  @override
  Future<void> write(String key, bool value) async {
    final preferences = await SharedPreferences.getInstance();
    final didPersist = await preferences.setBool(key, value);
    if (!didPersist) throw StateError('Could not persist tour completion.');
  }
}

class ProfileTourPreferenceService {
  ProfileTourPreferenceService({
    ProfileTourCompletionStore store =
        const SharedPreferencesProfileTourCompletionStore(),
  }) : _store = store;

  static const String keyPrefix = 'profile_tour_v1_';
  static final Set<String> _sessionCompletedUids = <String>{};

  final ProfileTourCompletionStore _store;

  String keyForUid(String uid) => '$keyPrefix${uid.trim()}';

  Future<bool> isCompleted(String uid) {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) return Future<bool>.value(true);
    if (_sessionCompletedUids.contains(normalizedUid)) {
      return Future<bool>.value(true);
    }
    return _store.read(keyForUid(normalizedUid));
  }

  Future<void> markCompleted(String uid) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) return;
    _sessionCompletedUids.add(normalizedUid);
    await _store.write(keyForUid(normalizedUid), true);
  }

  static void clearSessionCompletionsForTesting() =>
      _sessionCompletedUids.clear();
}
