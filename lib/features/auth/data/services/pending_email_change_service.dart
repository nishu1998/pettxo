import 'package:shared_preferences/shared_preferences.dart';

class PendingEmailChangeService {
  static const _pendingEmailKeyPrefix = 'pending_email_change:';

  const PendingEmailChangeService();

  String _keyForUid(String uid) => '$_pendingEmailKeyPrefix${uid.trim()}';

  Future<void> savePendingEmail({
    required String uid,
    required String email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyForUid(uid), email.trim());
  }

  Future<String?> getPendingEmail(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyForUid(uid));
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  Future<void> clearPendingEmail(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyForUid(uid));
  }
}
