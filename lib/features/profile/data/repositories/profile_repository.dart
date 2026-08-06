import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/identity/username_utils.dart' as username_utils;
import '../../../../core/services/firestore_cache_service.dart';
import '../../../auth/domain/models/profile_type.dart';
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

  DocumentReference<Map<String, dynamic>> _usernameDoc(String normalized) {
    return _firestore.collection('usernames').doc(normalized);
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
      return UserProfile.fromMap({...publicData, ...privateData});
    });
  }

  Future<UserProfile> getCurrentUserProfile() async {
    final snapshots = await Future.wait([
      FirestoreCacheService.getDocCacheFirst(_publicUserDoc(_uid)),
      FirestoreCacheService.getDocCacheFirst(_privateUserDoc(_uid)),
    ]);
    final publicData = snapshots[0].data();
    if (publicData == null) {
      throw Exception('Profile not found');
    }
    final privateData = snapshots[1].data() ?? const <String, dynamic>{};
    return UserProfile.fromMap({...publicData, ...privateData});
  }

  Stream<UserProfile> watchUserProfile(String userId) {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) {
      throw Exception('Profile not found');
    }

    return _publicUserDoc(trimmedUserId).snapshots().map((snapshot) {
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

    final snapshot = await FirestoreCacheService.getDocCacheFirst(
      _publicUserDoc(trimmedUserId),
    );
    final data = snapshot.data();
    if (data == null) {
      throw Exception('Profile not found');
    }

    return UserProfile.fromMap(data);
  }

  Future<bool> isUserPubliclyVisible(String userId) async {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) return false;

    try {
      final profile = await getUserProfileById(trimmedUserId);
      return profile.isPubliclyVisible;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, bool>> fetchPublicVisibilityByIds(
    List<String> userIds,
  ) async {
    final normalizedIds = userIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedIds.isEmpty) {
      return <String, bool>{};
    }

    final visibilityById = <String, bool>{};
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

      final foundIds = <String>{};
      for (final doc in snapshot.docs) {
        final profile = UserProfile.fromMap(doc.data());
        final profileId = profile.uid.trim();
        if (profileId.isEmpty) continue;
        foundIds.add(profileId);
        visibilityById[profileId] = profile.isPubliclyVisible;
      }

      for (final userId in chunk) {
        visibilityById.putIfAbsent(userId, () => false);
      }
    }

    return visibilityById;
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
        if (!profile.isPubliclyVisible) continue;
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
    final snapshot = await FirestoreCacheService.getCollectionCacheFirst(
      _firestore.collection('users').limit(queryLimit),
    );

    final excludedIds = Set<String>.from(followingIds)
      ..add(trimmedCurrentUserId);
    final profiles = snapshot.docs
        .map((doc) => UserProfile.fromMap(doc.data()))
        .where((profile) => profile.uid.isNotEmpty)
        .where((profile) => profile.isPubliclyVisible)
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
        if (!profile.isPubliclyVisible) continue;

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
    final normalized = username_utils.normalizeUsername(username);
    if (normalized.isEmpty) return false;

    final validationError = username_utils.validateNormalizedUsername(
      normalized,
    );
    if (validationError != null) return false;

    final reservationSnapshot = await _usernameDoc(normalized).get();
    if (!reservationSnapshot.exists) {
      return true;
    }

    final matchedUid = (reservationSnapshot.data()?['uid'] as String? ?? '')
        .trim();
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
    required String bio,
    String? role,
    String? profileImageUrl,
  }) async {
    final normalizedLocationPayload = _buildNormalizedLocationPayload(location);
    final normalizedRole = role?.trim() ?? '';
    final publicPayload = <String, dynamic>{
      'displayName': name.trim(),
      'name': name.trim(),
      'bio': bio.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      ...normalizedLocationPayload,
    };

    if (normalizedRole.isNotEmpty) {
      publicPayload['role'] = normalizedRole;
    }

    if (profileImageUrl != null && profileImageUrl.trim().isNotEmpty) {
      publicPayload['photoUrl'] = profileImageUrl.trim();
      publicPayload['profileImage'] = profileImageUrl.trim();
    }

    await _publicUserDoc(_uid).set(publicPayload, SetOptions(merge: true));
    if (normalizedRole.isNotEmpty) {
      try {
        await _syncCurrentUserRoleAcrossPosts(
          role: normalizedRole,
          profileImageUrl: profileImageUrl?.trim(),
          displayName: name.trim(),
          city: (normalizedLocationPayload['city'] as String? ?? '').trim(),
          state: (normalizedLocationPayload['state'] as String? ?? '').trim(),
        );
      } on FirebaseException catch (error, stackTrace) {
        if (error.code != 'permission-denied') {
          rethrow;
        }
        debugPrint(
          'ProfileRepository debug -> skipped social post author snapshot sync for uid=$_uid because Firestore rules denied the write: ${error.message}',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  Future<void> _syncCurrentUserRoleAcrossPosts({
    required String role,
    required String displayName,
    required String city,
    required String state,
    String? profileImageUrl,
  }) async {
    final roleLabel = profileTypeFromStoredValue(role).label;
    final trimmedPhotoUrl = profileImageUrl?.trim() ?? '';
    final snapshot = await _firestore
        .collection('socialPosts')
        .where('authorId', isEqualTo: _uid)
        .get();

    if (snapshot.docs.isEmpty) {
      return;
    }

    for (var start = 0; start < snapshot.docs.length; start += 50) {
      final end = min(start + 50, snapshot.docs.length);
      final chunk = snapshot.docs.sublist(start, end);
      final batch = _firestore.batch();

      for (final doc in chunk) {
        final update = <String, dynamic>{
          'authorCategoryLabel': roleLabel,
          'authorDisplayName': displayName,
          'authorCity': city,
          'authorState': state,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (trimmedPhotoUrl.isNotEmpty) {
          update['authorPhotoUrl'] = trimmedPhotoUrl;
        }
        batch.set(doc.reference, update, SetOptions(merge: true));
      }

      await batch.commit();
    }
  }

  Map<String, dynamic> _buildNormalizedLocationPayload(String location) {
    final trimmedLocation = location.trim();
    final parts = trimmedLocation
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    final payload = <String, dynamic>{
      'location': trimmedLocation,
      'address': FieldValue.delete(),
      'city': FieldValue.delete(),
      'state': FieldValue.delete(),
      'country': FieldValue.delete(),
    };

    if (parts.isEmpty) {
      return payload;
    }

    if (parts.length == 1) {
      payload['city'] = parts[0];
      return payload;
    }

    if (parts.length == 2) {
      payload['city'] = parts[0];
      payload['state'] = parts[1];
      return payload;
    }

    if (parts.length == 3) {
      payload['city'] = parts[0];
      payload['state'] = parts[1];
      payload['country'] = parts[2];
      return payload;
    }

    payload['address'] = parts.sublist(0, parts.length - 3).join(', ');
    payload['city'] = parts[parts.length - 3];
    payload['state'] = parts[parts.length - 2];
    payload['country'] = parts.last;
    return payload;
  }

  String normalizeUsername(String username) =>
      username_utils.normalizeUsername(username);
}
