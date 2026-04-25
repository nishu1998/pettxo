import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
Future<void> pettxoFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  String? _currentUid;
  String? _currentToken;

  Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(
      pettxoFirebaseMessagingBackgroundHandler,
    );

    await _requestPermission();
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _authSubscription ??= _auth.authStateChanges().listen(_syncForUser);
    _tokenRefreshSubscription ??= _messaging.onTokenRefresh.listen((token) {
      _currentToken = token;
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        _storeToken(uid, token);
      }
    });

    await _syncForUser(_auth.currentUser);
  }

  Future<void> _requestPermission() async {
    await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
  }

  Future<void> _syncForUser(User? user) async {
    final previousUid = _currentUid;
    final previousToken = _currentToken;

    if (user == null) {
      if (previousUid != null && previousToken != null) {
        await _removeToken(previousUid, previousToken);
      }
      _currentUid = null;
      _currentToken = null;
      return;
    }

    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) return;

    if (previousUid != null &&
        previousUid != user.uid &&
        previousToken != null) {
      await _removeToken(previousUid, previousToken);
    }

    _currentUid = user.uid;
    _currentToken = token;
    await _storeToken(user.uid, token);
  }

  Future<void> _storeToken(String uid, String token) {
    final tokenRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('notificationTokens')
        .doc(_tokenDocId(token));

    return tokenRef.set({
      'token': token,
      'platform': _platformName,
      'app': 'pettxo',
      'disabled': false,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _removeToken(String uid, String token) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('notificationTokens')
        .doc(_tokenDocId(token))
        .delete()
        .catchError((_) {
          // Token cleanup should never block logout/navigation.
        });
  }

  String _tokenDocId(String token) {
    return base64Url.encode(utf8.encode(token)).replaceAll('=', '');
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }
}
