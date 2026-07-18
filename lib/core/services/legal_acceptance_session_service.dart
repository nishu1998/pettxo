import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class LegalAcceptanceSessionService {
  LegalAcceptanceSessionService._();

  static final LegalAcceptanceSessionService instance =
      LegalAcceptanceSessionService._();

  static const String _signupConsentKey = 'auth.signup_consent_accepted';

  bool _signupConsentAccepted = false;
  late final Future<void> _loadFuture = _loadFromPrefs();

  bool get hasPendingSignupConsent => _signupConsentAccepted;

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _signupConsentAccepted = prefs.getBool(_signupConsentKey) ?? false;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_signupConsentKey, _signupConsentAccepted);
  }

  Future<bool> readPendingSignupConsent() async {
    await _loadFuture;
    return _signupConsentAccepted;
  }

  void markSignupConsentAccepted() {
    _signupConsentAccepted = true;
    unawaited(_persist());
  }

  void clearSignupConsent() {
    _signupConsentAccepted = false;
    unawaited(_persist());
  }
}
