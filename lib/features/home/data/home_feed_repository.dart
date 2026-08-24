import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/firebase_resilience_service.dart';
import '../../../core/services/network_status_service.dart';
import '../../profile/data/repositories/profile_repository.dart';
import '../../social/data/follow_repository.dart';
import '../../social/domain/models/social_post_model.dart';
import '../../social/domain/social_feed_pagination.dart';

class HomeFeedPage {
  final List<SocialPostModel> posts;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;

  const HomeFeedPage({
    required this.posts,
    required this.lastDocument,
    required this.hasMore,
  });
}

class HomeFeedViewerContext {
  final String currentUserId;
  final String city;
  final String state;
  final Set<String> followingIds;
  final Set<String> blockedUserIds;
  final Set<String> mutedUserIds;
  final Set<String> creatorsWhoBlockedViewerIds;

  const HomeFeedViewerContext({
    required this.currentUserId,
    required this.city,
    required this.state,
    required this.followingIds,
    required this.blockedUserIds,
    required this.mutedUserIds,
    required this.creatorsWhoBlockedViewerIds,
  });

  static const empty = HomeFeedViewerContext(
    currentUserId: '',
    city: '',
    state: '',
    followingIds: <String>{},
    blockedUserIds: <String>{},
    mutedUserIds: <String>{},
    creatorsWhoBlockedViewerIds: <String>{},
  );
}

class HomeFeedRepository {
  HomeFeedRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    ProfileRepository? profileRepository,
    FollowRepository? followRepository,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _profileRepository = profileRepository ?? ProfileRepository(),
       _followRepository = followRepository ?? FollowRepository();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final ProfileRepository _profileRepository;
  final FollowRepository _followRepository;
  final Map<String, bool> _authorVisibilityCache = <String, bool>{};

  Future<HomeFeedViewerContext> loadViewerContext() async {
    final currentUserId = _auth.currentUser?.uid.trim() ?? '';
    if (currentUserId.isEmpty) {
      return HomeFeedViewerContext.empty;
    }

    final results = await Future.wait<dynamic>([
      _profileRepository.getCurrentUserProfile(),
      _followRepository.fetchFollowingIds(currentUserId),
      _loadBlockedUserIds(),
      _loadRelationIds(
        collection: 'userMutes',
        ownerField: 'ownerUserId',
        targetField: 'mutedUserId',
        ownerUserId: currentUserId,
      ),
      _loadCreatorsWhoBlockedViewerIds(),
    ]);

    final profile = results[0];
    return HomeFeedViewerContext(
      currentUserId: currentUserId,
      city: profile.city,
      state: profile.state,
      followingIds: results[1] as Set<String>,
      blockedUserIds: results[2] as Set<String>,
      mutedUserIds: results[3] as Set<String>,
      creatorsWhoBlockedViewerIds: results[4] as Set<String>,
    );
  }

  Future<HomeFeedPage> fetchPage({
    required HomeFeedViewerContext viewerContext,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    Set<String> excludePostIds = const <String>{},
    int limit = socialFeedPageSize,
    bool forceRefresh = false,
  }) async {
    final posts = <SocialPostModel>[];
    final seenPostIds = Set<String>.from(excludePostIds);
    DocumentSnapshot<Map<String, dynamic>>? cursor = startAfter;
    var hasMore = true;
    final targetCandidates = math.max(limit * 3, 24);
    final pageSize = math.max(targetCandidates * 2, 30);

    while (posts.length < targetCandidates && hasMore) {
      Query<Map<String, dynamic>> query = _firestore
          .collection('socialPosts')
          .where('visibilityStatus', isEqualTo: 'visible')
          .where('moderationStatus', isEqualTo: 'approved')
          .where('homeEligible', isEqualTo: true)
          .orderBy('homeScore', descending: true)
          .orderBy('createdAtEpoch', descending: true)
          .orderBy(FieldPath.documentId)
          .limit(pageSize);
      if (cursor != null) {
        query = query.startAfterDocument(cursor);
      }

      final snapshot = await _executeQuery(
        query,
        useCache: !forceRefresh && cursor == null,
      );
      if (snapshot.docs.isEmpty) {
        hasMore = false;
        break;
      }

      cursor = snapshot.docs.last;
      hasMore = snapshot.docs.length == pageSize;
      final visiblePosts = await _filterPosts(
        snapshot.docs.map(SocialPostModel.fromDocument).toList(growable: false),
        viewerContext: viewerContext,
        seenPostIds: seenPostIds,
      );
      posts.addAll(visiblePosts);
    }

    return HomeFeedPage(
      posts: posts,
      lastDocument: cursor ?? startAfter,
      hasMore: hasMore,
    );
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _executeQuery(
    Query<Map<String, dynamic>> query, {
    required bool useCache,
  }) async {
    if (useCache || NetworkStatusService.instance.isOffline) {
      try {
        final cacheSnapshot = await query.get(
          const GetOptions(source: Source.cache),
        );
        if (cacheSnapshot.docs.isNotEmpty ||
            NetworkStatusService.instance.isOffline) {
          return cacheSnapshot;
        }
      } on FirebaseException {
        if (NetworkStatusService.instance.isOffline) rethrow;
      }
    }

    try {
      return await FirebaseResilienceService.retryTransient<
        QuerySnapshot<Map<String, dynamic>>
      >(
        operationName: 'HomeFeedRepository.fetchPage:serverQuery',
        operation: query.get,
      );
    } on FirebaseException catch (error) {
      if (error.code == 'failed-precondition') {
        throw Exception(
          'Home feed ranking indexes are not deployed yet. Deploy the latest Firestore indexes for homeScore ordering.',
        );
      }
      rethrow;
    }
  }

  Future<List<SocialPostModel>> _filterPosts(
    List<SocialPostModel> posts, {
    required HomeFeedViewerContext viewerContext,
    required Set<String> seenPostIds,
  }) async {
    if (posts.isEmpty) return const <SocialPostModel>[];

    final missingAuthorIds = posts
        .map((post) => post.authorId.trim())
        .where((authorId) => authorId.isNotEmpty)
        .where((authorId) => !_authorVisibilityCache.containsKey(authorId))
        .toSet()
        .toList(growable: false);
    if (missingAuthorIds.isNotEmpty) {
      _authorVisibilityCache.addAll(
        await _profileRepository.fetchPublicVisibilityByIds(missingAuthorIds),
      );
    }

    return posts
        .where((post) {
          final postId = post.id.trim();
          final authorId = post.authorId.trim();
          if (postId.isEmpty || authorId.isEmpty) return false;
          if (seenPostIds.contains(postId)) return false;
          if (post.visibilityStatus != 'visible') return false;
          if (post.moderationStatus != 'approved') return false;
          if ((post.homeEligible) == false) return false;
          if ((_authorVisibilityCache[authorId] ?? false) == false) {
            return false;
          }
          if (viewerContext.blockedUserIds.contains(authorId)) return false;
          if (viewerContext.mutedUserIds.contains(authorId)) return false;
          if (viewerContext.creatorsWhoBlockedViewerIds.contains(authorId)) {
            return false;
          }
          seenPostIds.add(postId);
          return true;
        })
        .toList(growable: false);
  }

  Future<Set<String>> _loadRelationIds({
    required String collection,
    required String ownerField,
    required String targetField,
    required String ownerUserId,
  }) async {
    final snapshot =
        await FirebaseResilienceService.retryTransient<
          QuerySnapshot<Map<String, dynamic>>
        >(
          operationName: 'HomeFeedRepository.loadRelationIds:$collection',
          operation: () => _firestore
              .collection(collection)
              .where(ownerField, isEqualTo: ownerUserId)
              .get(),
        );

    return snapshot.docs
        .map((doc) => (doc.data()[targetField] as String? ?? '').trim())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<Set<String>> _loadBlockedUserIds() async {
    // User-to-user blocking is not currently a Pettxo product feature.
    // Keep the viewer-context shape intact so block-based filtering can be
    // re-enabled here later without changing the feed consumers.
    return const <String>{};
  }

  Future<Set<String>> _loadCreatorsWhoBlockedViewerIds() async {
    // User-to-user blocking is not currently a Pettxo product feature.
    // Keep the viewer-context shape intact so reciprocal block filtering can
    // be re-enabled here later without changing the feed consumers.
    return const <String>{};
  }
}
