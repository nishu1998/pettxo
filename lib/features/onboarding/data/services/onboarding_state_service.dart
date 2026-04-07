import 'package:shared_preferences/shared_preferences.dart';

class OnboardingStateService {
  static const String _seenVersionKey = 'onboarding_seen_version';

  Future<bool> shouldShowOnboarding({
    required int currentVersion,
    required bool forceShow,
  }) async {
    if (forceShow) return true;

    final prefs = await SharedPreferences.getInstance();
    final seenVersion = prefs.getInt(_seenVersionKey) ?? 0;

    return seenVersion < currentVersion;
  }

  Future<void> markOnboardingSeen(int version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seenVersionKey, version);
  }
}
