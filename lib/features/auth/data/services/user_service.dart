import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/identity/username_utils.dart';
import '../../../../core/services/firestore_cache_service.dart';
import 'auth_service.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AuthService _authService = AuthService();

  DocumentReference<Map<String, dynamic>> _publicUserDoc(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  DocumentReference<Map<String, dynamic>> _privateUserDoc(String uid) {
    return _firestore.collection('userPrivate').doc(uid);
  }

  Future<OnboardingProfileCompletionResult> createUserProfile({
    required String role,
    required String name,
    required String username,
    required String state,
    required String city,
    bool acceptedTerms = false,
    bool acceptedPrivacy = false,
    bool acceptedProviderAgreement = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final usernameResult = normalizeAndValidateUsername(username);
    if (!usernameResult.isValid) {
      throw Exception(usernameResult.error);
    }

    final result = await _authService.completeOnboardingProfile(
      role: role,
      displayName: name.trim(),
      username: usernameResult.normalized,
      state: state.trim(),
      city: city.trim(),
      acceptedTerms: acceptedTerms,
      acceptedPrivacy: acceptedPrivacy,
      acceptedProviderAgreement: acceptedProviderAgreement,
    );
    await _authService.syncTrustedAuthIdentity();
    return result;
  }

  Future<bool> hasAcceptedProviderAgreement() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final snapshot = await _privateUserDoc(user.uid).get();
    return snapshot.data()?['acceptedProviderAgreementAt'] != null;
  }

  Future<void> acceptProviderAgreementIfNeeded() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final snapshot = await _privateUserDoc(user.uid).get();
    if (snapshot.data()?['acceptedProviderAgreementAt'] != null) return;

    await _privateUserDoc(user.uid).set({
      'uid': user.uid,
      if (!snapshot.exists) 'createdAt': FieldValue.serverTimestamp(),
      'acceptedProviderAgreementAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<DocumentSnapshot?> getUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }

    return FirestoreCacheService.getDocCacheFirst(_publicUserDoc(user.uid));
  }

  Future<bool> hasUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      return false;
    }

    await syncCurrentUserPrivateFields();
    final snapshot = await FirestoreCacheService.getDocCacheFirst(
      _publicUserDoc(user.uid),
    );
    return snapshot.exists && snapshot.data() != null;
  }

  Future<bool?> hasUserProfileCacheFirst() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final snapshot = await FirestoreCacheService.getDocCacheFirst(
        _publicUserDoc(user.uid),
      );
      if (!snapshot.exists) return false;
      return snapshot.data() != null;
    } catch (error) {
      debugPrint(
        'UserService startup debug -> profile availability fallback for uid=${user.uid}: $error',
      );
      return null;
    }
  }

  Future<String> getPostAuthRoute() async {
    await syncCurrentUserPrivateFields();
    return '/auth-gate';
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }
    final uid = user.uid;

    final updatedData = {...data};
    if (updatedData.containsKey('username') ||
        updatedData.containsKey('usernameLowercase')) {
      throw Exception(
        'Username changes are only available through Account & Security.',
      );
    }

    final displayName =
        (updatedData['displayName'] as String? ??
                updatedData['name'] as String? ??
                '')
            .trim();
    final photoUrl =
        (updatedData['photoUrl'] as String? ??
                updatedData['profileImage'] as String? ??
                '')
            .trim();

    if (displayName.isNotEmpty) {
      updatedData['displayName'] = displayName;
      updatedData['name'] = displayName;
    }
    if (photoUrl.isNotEmpty) {
      updatedData['photoUrl'] = photoUrl;
      updatedData['profileImage'] = photoUrl;
    }

    final publicData = Map<String, dynamic>.from(updatedData)
      ..remove('email')
      ..remove('emailVerified')
      ..remove('phoneVerified')
      ..remove('providers')
      ..remove('phoneNumber')
      ..remove('phone')
      ..remove('mobileNumber');

    final batch = _firestore.batch();
    batch.set(_publicUserDoc(uid), {
      ...publicData,
      'uid': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
    await _authService.syncTrustedAuthIdentity();
  }

  Future<void> syncCurrentUserPrivateFields() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _authService.syncTrustedAuthIdentity();
    } catch (error, stackTrace) {
      debugPrint(
        'UserService private field sync skipped for uid=${user.uid}: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
