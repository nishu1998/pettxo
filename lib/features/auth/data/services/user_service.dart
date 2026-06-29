import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  DocumentReference<Map<String, dynamic>> _publicUserDoc(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  DocumentReference<Map<String, dynamic>> _privateUserDoc(String uid) {
    return _firestore.collection('userPrivate').doc(uid);
  }

  Future<void> createUserProfile({
    required String role,
    required String name,
    required String username,
    required String phone,
    required String state,
    required String city,
    bool acceptedTerms = false,
    bool acceptedPrivacy = false,
    bool acceptedProviderAgreement = false,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception("User not authenticated");
    }

    final batch = _firestore.batch();
    batch.set(_publicUserDoc(user.uid), {
      "uid": user.uid,
      "role": role,
      "name": name,
      "username": _normalizeUsername(username),
      "usernameLowercase": _normalizeUsername(username),
      "state": state.trim(),
      "city": city.trim(),
      "profileImage": "",
      "bio": "",
      "createdAt": FieldValue.serverTimestamp(),
    });
    batch.set(_privateUserDoc(user.uid), {
      "uid": user.uid,
      "email": user.email ?? '',
      "phone": phone.trim(),
      "mobileNumber": phone.trim(),
      if (acceptedTerms) "acceptedTermsAt": FieldValue.serverTimestamp(),
      if (acceptedPrivacy) "acceptedPrivacyAt": FieldValue.serverTimestamp(),
      if (acceptedProviderAgreement)
        "acceptedProviderAgreementAt": FieldValue.serverTimestamp(),
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
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

    return _publicUserDoc(user.uid).get();
  }

  Future<bool> hasUserProfile() async {
    final user = _auth.currentUser;

    if (user == null) {
      return false;
    }

    await syncCurrentUserPrivateFields();
    final snapshot = await _publicUserDoc(user.uid).get();
    return snapshot.exists && snapshot.data() != null;
  }

  Future<String> getPostAuthRoute() async {
    await syncCurrentUserPrivateFields();
    return await hasUserProfile() ? '/home' : '/profile-type';
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    final uid = _auth.currentUser!.uid;
    final privateSnapshot = await _privateUserDoc(uid).get();

    final updatedData = {...data};
    final username = updatedData['username'] as String?;
    if (username != null) {
      updatedData['username'] = _normalizeUsername(username);
      updatedData['usernameLowercase'] = _normalizeUsername(username);
    }

    final publicData = Map<String, dynamic>.from(updatedData)
      ..remove('email')
      ..remove('phone')
      ..remove('mobileNumber');
    final privateData = <String, dynamic>{
      if (updatedData['email'] != null) 'email': updatedData['email'],
      if (updatedData['phone'] != null) 'phone': updatedData['phone'],
      if (updatedData['mobileNumber'] != null)
        'mobileNumber': updatedData['mobileNumber'],
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!privateSnapshot.exists && privateData.length > 1) {
      privateData['uid'] = uid;
      privateData['createdAt'] = FieldValue.serverTimestamp();
    }

    final batch = _firestore.batch();
    batch.set(_publicUserDoc(uid), publicData, SetOptions(merge: true));
    if (privateData.length > 1) {
      batch.set(_privateUserDoc(uid), privateData, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> syncCurrentUserPrivateFields() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final snapshots = await Future.wait([
        _publicUserDoc(user.uid).get(),
        _privateUserDoc(user.uid).get(),
      ]);
      final publicSnapshot = snapshots[0];
      final privateSnapshot = snapshots[1];
      if (!publicSnapshot.exists) return;

      final publicData = publicSnapshot.data() ?? const <String, dynamic>{};
      final email = (publicData['email'] as String? ?? user.email ?? '').trim();
      final phone = (publicData['phone'] as String? ??
              publicData['mobileNumber'] as String? ??
              '')
          .trim();
      final hasSensitivePublicFields =
          publicData.containsKey('email') ||
          publicData.containsKey('phone') ||
          publicData.containsKey('mobileNumber');
      final shouldWritePrivate = email.isNotEmpty || phone.isNotEmpty;

      if (!hasSensitivePublicFields && !shouldWritePrivate) return;

      final batch = _firestore.batch();
      if (shouldWritePrivate) {
        batch.set(_privateUserDoc(user.uid), {
          'uid': user.uid,
          if (email.isNotEmpty) 'email': email,
          if (phone.isNotEmpty) 'phone': phone,
          if (phone.isNotEmpty) 'mobileNumber': phone,
          if (!privateSnapshot.exists)
            'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      if (hasSensitivePublicFields) {
        batch.set(_publicUserDoc(user.uid), {
          'email': FieldValue.delete(),
          'phone': FieldValue.delete(),
          'mobileNumber': FieldValue.delete(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    } catch (error, stackTrace) {
      debugPrint(
        'UserService private field sync skipped for uid=${user.uid}: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  String _normalizeUsername(String username) {
    return username.trim().replaceAll('@', '').toLowerCase();
  }
}
