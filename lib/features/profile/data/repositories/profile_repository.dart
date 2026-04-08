import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../domain/models/user_profile.dart';

class ProfileRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw Exception('User not authenticated');
    }
    return uid;
  }

  Stream<UserProfile> watchCurrentUserProfile() {
    return _firestore.collection('users').doc(_uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) {
        throw Exception('Profile not found');
      }
      return UserProfile.fromMap(data);
    });
  }

  Future<UserProfile> getCurrentUserProfile() async {
    final snapshot = await _firestore.collection('users').doc(_uid).get();
    final data = snapshot.data();

    if (data == null) {
      throw Exception('Profile not found');
    }

    return UserProfile.fromMap(data);
  }

  Future<bool> isUsernameAvailable(
    String username, {
    String? excludeUid,
  }) async {
    final normalized = _normalizeUsername(username);
    if (normalized.isEmpty) return false;

    final normalizedQuery = await _firestore
        .collection('users')
        .where('usernameLowercase', isEqualTo: normalized)
        .limit(1)
        .get();

    if (normalizedQuery.docs.isNotEmpty) {
      final matchedUid = normalizedQuery.docs.first.id;
      return excludeUid != null && matchedUid == excludeUid;
    }

    final legacyQuery = await _firestore
        .collection('users')
        .where('username', isEqualTo: normalized)
        .limit(1)
        .get();

    if (legacyQuery.docs.isEmpty) {
      return true;
    }

    final matchedUid = legacyQuery.docs.first.id;
    return excludeUid != null && matchedUid == excludeUid;
  }

  Future<String> uploadProfileImage(File file) async {
    final ref = _storage.ref().child(
      'users/$_uid/profile/profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );

    await ref.putFile(file);
    return ref.getDownloadURL();
  }

  Future<void> updateCurrentUserProfile({
    required String name,
    required String username,
    required String location,
    required String bio,
    String? profileImageUrl,
  }) async {
    final normalizedUsername = _normalizeUsername(username);

    await _firestore.collection('users').doc(_uid).set({
      'name': name.trim(),
      'username': normalizedUsername,
      'usernameLowercase': normalizedUsername.toLowerCase(),
      'location': location.trim(),
      'bio': bio.trim(),
      'profileImage': profileImageUrl?.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String normalizeUsername(String username) => _normalizeUsername(username);

  String _normalizeUsername(String username) {
    return username.trim().replaceAll('@', '').toLowerCase();
  }
}
