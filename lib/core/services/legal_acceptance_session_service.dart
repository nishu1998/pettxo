import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/signup_terms_communications.dart';

class LegalAcceptanceSessionService {
  LegalAcceptanceSessionService._();

  static final LegalAcceptanceSessionService instance =
      LegalAcceptanceSessionService._();

  static const String _legacySignupConsentKey = 'auth.signup_consent_accepted';
  static const String _legacySignupConsentVersionKey =
      'auth.signup_consent_version';

  bool _signupConsentAccepted = false;
  late final Future<void> _loadFuture = _loadFromPrefs();

  bool get hasPendingSignupConsent => _signupConsentAccepted;

  String _signupConsentKeyForUid(String uid) =>
      'auth.signup_consent_accepted.$uid';

  String _signupConsentVersionKeyForUid(String uid) =>
      'auth.signup_consent_version.$uid';

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final scopedVersion = uid.isEmpty
        ? ''
        : (prefs.getString(_signupConsentVersionKeyForUid(uid)) ?? '');
    final legacyVersion = prefs.getString(_legacySignupConsentVersionKey) ?? '';
    _signupConsentAccepted =
        scopedVersion == signupTermsCommunicationsPolicyVersion ||
        legacyVersion == signupTermsCommunicationsPolicyVersion;
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
      await prefs.setString(
        _signupConsentVersionKeyForUid(normalizedUid),
        signupTermsCommunicationsPolicyVersion,
      );
      if (!_signupConsentAccepted) {
        await prefs.remove(_legacySignupConsentKey);
        await prefs.remove(_legacySignupConsentVersionKey);
      }
      return;
    }

    await prefs.setBool(_legacySignupConsentKey, _signupConsentAccepted);
    await prefs.setString(
      _legacySignupConsentVersionKey,
      signupTermsCommunicationsPolicyVersion,
    );
  }

  Future<bool> readPendingSignupConsent({String? uid}) async {
    await _loadFuture;
    final prefs = await SharedPreferences.getInstance();
    final normalizedUid = (uid ?? FirebaseAuth.instance.currentUser?.uid ?? '')
        .trim();
    final scopedVersion = normalizedUid.isEmpty
        ? ''
        : (prefs.getString(_signupConsentVersionKeyForUid(normalizedUid)) ??
              '');
    final legacyVersion = prefs.getString(_legacySignupConsentVersionKey) ?? '';
    _signupConsentAccepted =
        scopedVersion == signupTermsCommunicationsPolicyVersion ||
        legacyVersion == signupTermsCommunicationsPolicyVersion;
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
        await prefs.remove(_signupConsentVersionKeyForUid(normalizedUid));
      }
      await prefs.remove(_legacySignupConsentKey);
      await prefs.remove(_legacySignupConsentVersionKey);
    }());
  }
}
