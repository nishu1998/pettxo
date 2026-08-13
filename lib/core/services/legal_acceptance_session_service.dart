import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LegalAcceptanceSessionService {
  LegalAcceptanceSessionService._();

  static final LegalAcceptanceSessionService instance =
      LegalAcceptanceSessionService._();

  static const String _legacySignupConsentKey = 'auth.signup_consent_accepted';

  bool _signupConsentAccepted = false;
  late final Future<void> _loadFuture = _loadFromPrefs();

  bool get hasPendingSignupConsent => _signupConsentAccepted;

  String _signupConsentKeyForUid(String uid) =>
      'auth.signup_consent_accepted.$uid';

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final scopedAccepted = uid.isEmpty
        ? false
        : (prefs.getBool(_signupConsentKeyForUid(uid)) ?? false);
    final legacyAccepted = prefs.getBool(_legacySignupConsentKey) ?? false;
    _signupConsentAccepted = scopedAccepted || legacyAccepted;
  }

  Future<void> _persist({String? uid}) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedUid = (uid ?? FirebaseAuth.instance.currentUser?.uid ?? '')
        .trim();
    if (normalizedUid.isNotEmpty) {
      await prefs.setBool(
        _signupConsentKeyForUid(normalizedUid),
        _signupConsentAccepted,
      );
      if (!_signupConsentAccepted) {
        await prefs.remove(_legacySignupConsentKey);
      }
      return;
    }

    await prefs.setBool(_legacySignupConsentKey, _signupConsentAccepted);
  }

  Future<bool> readPendingSignupConsent({String? uid}) async {
    await _loadFuture;
    final prefs = await SharedPreferences.getInstance();
    final normalizedUid = (uid ?? FirebaseAuth.instance.currentUser?.uid ?? '')
        .trim();
    final scopedAccepted = normalizedUid.isEmpty
        ? false
        : (prefs.getBool(_signupConsentKeyForUid(normalizedUid)) ?? false);
    final legacyAccepted = prefs.getBool(_legacySignupConsentKey) ?? false;
    _signupConsentAccepted = scopedAccepted || legacyAccepted;
    return _signupConsentAccepted;
  }

  void markSignupConsentAccepted({String? uid}) {
    _signupConsentAccepted = true;
    unawaited(_persist(uid: uid));
  }

  void clearSignupConsent({String? uid}) {
    _signupConsentAccepted = false;
    unawaited(() async {
      final prefs = await SharedPreferences.getInstance();
      final normalizedUid =
          (uid ?? FirebaseAuth.instance.currentUser?.uid ?? '').trim();
      if (normalizedUid.isNotEmpty) {
        await prefs.remove(_signupConsentKeyForUid(normalizedUid));
      }
      await prefs.remove(_legacySignupConsentKey);
    }());
  }
}
