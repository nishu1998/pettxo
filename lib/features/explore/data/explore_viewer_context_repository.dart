import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../profile/data/repositories/profile_repository.dart';
import '../../profile/domain/models/user_profile.dart';
import '../../social/data/follow_repository.dart';
import '../domain/models/explore_feed_viewer_context.dart';
import 'explore_location_repository.dart';

class ExploreViewerContextRepository {
  ExploreViewerContextRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    ProfileRepository? profileRepository,
    FollowRepository? followRepository,
    ExploreLocationRepository? locationRepository,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _profileRepository = profileRepository ?? ProfileRepository(),
       _followRepository = followRepository ?? FollowRepository(),
       _locationRepository = locationRepository ?? ExploreLocationRepository();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final ProfileRepository _profileRepository;
  final FollowRepository _followRepository;
  final ExploreLocationRepository _locationRepository;

  String get _currentUserId => _auth.currentUser?.uid.trim() ?? '';

  Future<ExploreFeedViewerContext> load() async {
    final currentUserId = _currentUserId;
    if (currentUserId.isEmpty) {
      return ExploreFeedViewerContext.empty;
    }

    final results = await Future.wait<dynamic>([
      _profileRepository.getCurrentUserProfile(),
      _followRepository.fetchFollowingIds(currentUserId),
      _loadRelationIds(
        collection: 'userBlocks',
        ownerField: 'ownerUserId',
        targetField: 'blockedUserId',
        ownerUserId: currentUserId,
      ),
      _loadRelationIds(
        collection: 'userMutes',
        ownerField: 'ownerUserId',
        targetField: 'mutedUserId',
        ownerUserId: currentUserId,
      ),
      _locationRepository.loadStoredSnapshot(),
    ]);

    final profile = results[0] as UserProfile;
    final followingIds = results[1] as Set<String>;
    final blockedUserIds = results[2] as Set<String>;
    final mutedUserIds = results[3] as Set<String>;
    final locationSnapshot = results[4];

    return ExploreFeedViewerContext(
      currentUserId: currentUserId,
      city: profile.city,
      state: profile.state,
      locationSnapshot: locationSnapshot,
      followingIds: followingIds,
      blockedUserIds: blockedUserIds,
      mutedUserIds: mutedUserIds,
    );
  }

  Future<Set<String>> _loadRelationIds({
    required String collection,
    required String ownerField,
    required String targetField,
    required String ownerUserId,
  }) async {
    try {
      final snapshot = await _firestore
          .collection(collection)
          .where(ownerField, isEqualTo: ownerUserId)
          .get();

      return snapshot.docs
          .map((doc) => (doc.data()[targetField] as String? ?? '').trim())
          .where((id) => id.isNotEmpty)
          .toSet();
    } on FirebaseException catch (error, stackTrace) {
      developer.log(
        'Explore relation lookup failed for $collection.',
        name: 'ExploreViewerContextRepository',
        error: error,
        stackTrace: stackTrace,
      );
      throw Exception(
        'We could not verify your blocked or muted accounts right now. Please try again.',
      );
    }
  }
}
