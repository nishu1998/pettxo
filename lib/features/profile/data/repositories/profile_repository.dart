import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../../restrictions/domain/models/user_restriction_state.dart';
import '../../domain/models/user_profile.dart';

class ProfileRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  DocumentReference<Map<String, dynamic>> _publicUserDoc(String userId) {
    return _firestore.collection('users').doc(userId);
  }

  DocumentReference<Map<String, dynamic>> _privateUserDoc(String userId) {
    return _firestore.collection('userPrivate').doc(userId);
  }

  Future<void> _sanitizeCurrentUserPrivateFields(
    Map<String, dynamic> publicData,
    Map<String, dynamic> privateData,
    bool privateExists,
  ) async {
    final email = (publicData['email'] as String? ?? '').trim();
    final phone = (publicData['phone'] as String? ??
            publicData['mobileNumber'] as String? ??
            '')
        .trim();
    final hasSensitivePublicFields =
        publicData.containsKey('email') ||
        publicData.containsKey('phone') ||
        publicData.containsKey('mobileNumber');
    if (!hasSensitivePublicFields) return;

    try {
      final batch = _firestore.batch();
      if (email.isNotEmpty || phone.isNotEmpty) {
        batch.set(_privateUserDoc(_uid), {
          'uid': _uid,
          if (email.isNotEmpty && !privateData.containsKey('email'))
            'email': email,
          if (phone.isNotEmpty && !privateData.containsKey('phone'))
            'phone': phone,
          if (phone.isNotEmpty && !privateData.containsKey('mobileNumber'))
            'mobileNumber': phone,
          if (!privateExists) 'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      batch.set(_publicUserDoc(_uid), {
        'email': FieldValue.delete(),
        'phone': FieldValue.delete(),
        'mobileNumber': FieldValue.delete(),
      }, SetOptions(merge: true));
      await batch.commit();
    } catch (error, stackTrace) {
      debugPrint(
        'ProfileRepository private field sanitize skipped for uid=$_uid: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw Exception('User not authenticated');
    }
    return uid;
  }

  Stream<UserProfile> watchCurrentUserProfile() {
    return _publicUserDoc(_uid).snapshots().asyncMap((snapshot) async {
      final publicData = snapshot.data();
      if (publicData == null) {
        throw Exception('Profile not found');
      }
      final privateSnapshot = await _privateUserDoc(_uid).get();
      final privateData = privateSnapshot.data() ?? const <String, dynamic>{};
      await _sanitizeCurrentUserPrivateFields(
        publicData,
        privateData,
        privateSnapshot.exists,
      );
      return UserProfile.fromMap({...publicData, ...privateData});
    });
  }

  Future<UserProfile> getCurrentUserProfile() async {
    final snapshots = await Future.wait([
      _publicUserDoc(_uid).get(),
      _privateUserDoc(_uid).get(),
    ]);
    final publicData = snapshots[0].data();
    if (publicData == null) {
      throw Exception('Profile not found');
    }
    final privateData = snapshots[1].data() ?? const <String, dynamic>{};
    await _sanitizeCurrentUserPrivateFields(
      publicData,
      privateData,
      snapshots[1].exists,
    );
    return UserProfile.fromMap({...publicData, ...privateData});
  }

  Stream<UserProfile> watchUserProfile(String userId) {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) {
      throw Exception('Profile not found');
    }

    return _publicUserDoc(trimmedUserId).snapshots().map((
      snapshot,
    ) {
      final data = snapshot.data();
      if (data == null) {
        throw Exception('Profile not found');
      }
      return UserProfile.fromMap(data);
    });
  }

  Future<UserProfile> getUserProfileById(String userId) async {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) {
      throw Exception('Profile not found');
    }

    final snapshot = await _publicUserDoc(trimmedUserId).get();
    final data = snapshot.data();
    if (data == null) {
      throw Exception('Profile not found');
    }

    return UserProfile.fromMap(data);
  }

  Future<Map<String, UserProfile>> fetchUserProfilesByIds(
    List<String> userIds,
  ) async {
    final normalizedIds = userIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedIds.isEmpty) {
      return <String, UserProfile>{};
    }

    final profilesById = <String, UserProfile>{};
    const chunkSize = 10;

    for (var start = 0; start < normalizedIds.length; start += chunkSize) {
      final end = (start + chunkSize) > normalizedIds.length
          ? normalizedIds.length
          : (start + chunkSize);
      final chunk = normalizedIds.sublist(start, end);
      final snapshot = await _firestore
          .collection('users')
          .where('uid', whereIn: chunk)
          .get();

      for (final doc in snapshot.docs) {
        final profile = UserProfile.fromMap(doc.data());
        profilesById[profile.uid] = profile;
      }
    }

    return profilesById;
  }

  Future<List<UserProfile>> fetchSuggestedUsers({
    required String currentUserId,
    required Set<String> followingIds,
    String? city,
    String? state,
    int limit = 10,
    int? seed,
  }) async {
    final trimmedCurrentUserId = currentUserId.trim();
    if (trimmedCurrentUserId.isEmpty || limit <= 0) {
      return const <UserProfile>[];
    }

    final queryLimit = limit < 10 ? 20 : (limit * 3).clamp(20, 30);
    final snapshot = await _firestore
        .collection('users')
        .limit(queryLimit)
        .get();

    final excludedIds = Set<String>.from(followingIds)
      ..add(trimmedCurrentUserId);
    final profiles = snapshot.docs
        .map((doc) => UserProfile.fromMap(doc.data()))
        .where((profile) => profile.uid.isNotEmpty)
        .where((profile) => !excludedIds.contains(profile.uid))
        .toList(growable: true);

    if (seed != null) {
      profiles.shuffle(Random(seed));
    } else {
      profiles.shuffle(Random());
    }

    final normalizedCity = (city ?? '').trim().toLowerCase();
    final normalizedState = (state ?? '').trim().toLowerCase();
    final sameCity = <UserProfile>[];
    final sameState = <UserProfile>[];
    final withPhoto = <UserProfile>[];
    final remaining = <UserProfile>[];

    for (final profile in profiles) {
      final profileCity = profile.city.trim().toLowerCase();
      final profileState = profile.state.trim().toLowerCase();
      if (normalizedCity.isNotEmpty && profileCity == normalizedCity) {
        sameCity.add(profile);
      } else if (normalizedState.isNotEmpty &&
          profileState == normalizedState) {
        sameState.add(profile);
      } else if (profile.profileImageUrl.trim().isNotEmpty) {
        withPhoto.add(profile);
      } else {
        remaining.add(profile);
      }
    }

    final ordered = <UserProfile>[];
    final seenIds = <String>{};
    for (final bucket in [sameCity, sameState, withPhoto, remaining]) {
      for (final profile in bucket) {
        if (seenIds.add(profile.uid)) {
          ordered.add(profile);
          if (ordered.length >= limit) {
            return ordered;
          }
        }
      }
    }

    return ordered;
  }

  Future<List<UserProfile>> searchProfiles(
    String query, {
    String? excludeUserId,
    int limit = 10,
  }) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty || limit <= 0) {
      return const <UserProfile>[];
    }

    final capitalized = normalized.isEmpty
        ? normalized
        : '${normalized[0].toUpperCase()}${normalized.substring(1)}';
    final exactExcludedId = excludeUserId?.trim() ?? '';
    final resultsById = <String, UserProfile>{};

    Future<void> collect(
      Future<QuerySnapshot<Map<String, dynamic>>> Function() loader,
    ) async {
      final snapshot = await loader();
      for (final doc in snapshot.docs) {
        final profile = UserProfile.fromMap(doc.data());
        final profileId = profile.uid.trim();
        if (profileId.isEmpty || profileId == exactExcludedId) continue;

        final name = profile.name.trim().toLowerCase();
        final username = profile.usernameLowercase.trim();
        if (name.contains(normalized) || username.contains(normalized)) {
          resultsById[profileId] = profile;
          if (resultsById.length >= limit) return;
        }
      }
    }

    await collect(
      () => _firestore
          .collection('users')
          .orderBy('usernameLowercase')
          .startAt([normalized])
          .endAt(['$normalized\uf8ff'])
          .limit(limit)
          .get(),
    );

    if (resultsById.length < limit) {
      await collect(
        () => _firestore
            .collection('users')
            .orderBy('name')
            .startAt([capitalized])
            .endAt(['$capitalized\uf8ff'])
            .limit(limit)
            .get(),
      );
    }

    if (resultsById.length < limit) {
      await collect(() => _firestore.collection('users').limit(20).get());
    }

    final ranked = resultsById.values.toList(growable: false)
      ..sort((a, b) {
        final aUsername = a.usernameLowercase;
        final bUsername = b.usernameLowercase;
        final aName = a.name.trim().toLowerCase();
        final bName = b.name.trim().toLowerCase();

        final aExact = aUsername == normalized || aName == normalized;
        final bExact = bUsername == normalized || bName == normalized;
        if (aExact != bExact) return aExact ? -1 : 1;

        final aPrefix =
            aUsername.startsWith(normalized) || aName.startsWith(normalized);
        final bPrefix =
            bUsername.startsWith(normalized) || bName.startsWith(normalized);
        if (aPrefix != bPrefix) return aPrefix ? -1 : 1;

        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return ranked.take(limit).toList(growable: false);
  }

  Stream<UserRestrictionState> watchCurrentUserRestrictionState() {
    return _publicUserDoc(_uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) {
        return UserRestrictionState.unrestricted;
      }
      return UserRestrictionState.fromMap(data);
    });
  }

  Future<UserRestrictionState> getCurrentUserRestrictionState() async {
    final snapshot = await _publicUserDoc(_uid).get();
    return UserRestrictionState.fromMap(snapshot.data() ?? const {});
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
    required String location,
    required String phone,
    required String bio,
    String? profileImageUrl,
  }) async {
    final privateSnapshot = await _privateUserDoc(_uid).get();
    final publicPayload = <String, dynamic>{
      'name': name.trim(),
      'location': location.trim(),
      'bio': bio.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final privatePayload = <String, dynamic>{
      'uid': _uid,
      'phone': phone.trim(),
      'mobileNumber': phone.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!privateSnapshot.exists) {
      privatePayload['createdAt'] = FieldValue.serverTimestamp();
    }

    if (profileImageUrl != null && profileImageUrl.trim().isNotEmpty) {
      publicPayload['profileImage'] = profileImageUrl.trim();
    }

    final batch = _firestore.batch();
    batch.set(_publicUserDoc(_uid), publicPayload, SetOptions(merge: true));
    batch.set(_privateUserDoc(_uid), privatePayload, SetOptions(merge: true));
    await batch.commit();
  }

  String normalizeUsername(String username) => _normalizeUsername(username);

  String _normalizeUsername(String username) {
    return username.trim().replaceAll('@', '').toLowerCase();
  }
}
