import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../notifications/data/repositories/notification_repository.dart';

typedef FollowCallableInvoker =
    Future<Map<String, dynamic>> Function(
      String functionName,
      Map<String, dynamic> payload,
    );

class FollowChange {
  final String followerId;
  final String followeeId;
  final bool isFollowing;

  const FollowChange({
    required this.followerId,
    required this.followeeId,
    required this.isFollowing,
  });
}

class FollowIdsPage {
  final List<String> userIds;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;

  const FollowIdsPage({
    required this.userIds,
    required this.lastDocument,
    required this.hasMore,
  });
}

class ProfileFollowCounts {
  final int followerCount;
  final int followingCount;

  const ProfileFollowCounts({
    required this.followerCount,
    required this.followingCount,
  });
}

class FollowRepository {
  static final StreamController<FollowChange> _changesController =
      StreamController<FollowChange>.broadcast();

  FollowRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    NotificationRepository? notificationRepository,
    FollowCallableInvoker? callableInvoker,
  }) : _firestoreOverride = firestore,
       _functionsOverride = functions,
       _notificationRepositoryOverride = notificationRepository,
       _callableInvoker = callableInvoker;

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseFunctions? _functionsOverride;
  final NotificationRepository? _notificationRepositoryOverride;
  final FollowCallableInvoker? _callableInvoker;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  NotificationRepository get _notificationRepository =>
      _notificationRepositoryOverride ?? NotificationRepository();

  Stream<FollowChange> get changes => _changesController.stream;

  CollectionReference<Map<String, dynamic>> get _followsCollection =>
      _firestore.collection('follows');

  Future<Map<String, dynamic>> _invoke(
    String functionName,
    Map<String, dynamic> payload,
  ) async {
    final override = _callableInvoker;
    if (override != null) return override(functionName, payload);
    final result = await _functions
        .httpsCallable(functionName)
        .call<Map<String, dynamic>>(payload);
    return result.data;
  }

  String _normalizeRequiredUserId(String userId, String label) {
    final trimmed = userId.trim();
    if (trimmed.isEmpty) {
      throw Exception('$label is missing.');
    }
    return trimmed;
  }

  String followIdFor({required String followerId, required String followeeId}) {
    return '${followerId.trim()}_${followeeId.trim()}';
  }

  Future<bool> isFollowing({
    required String followerId,
    required String followeeId,
  }) async {
    final trimmedFollowerId = followerId.trim();
    final trimmedFolloweeId = followeeId.trim();

    if (trimmedFollowerId.isEmpty || trimmedFolloweeId.isEmpty) return false;
    if (trimmedFollowerId == trimmedFolloweeId) return false;

    try {
      final data = await _invoke('getFollowState', {
        'followeeId': trimmedFolloweeId,
      });
      return data['isFollowing'] == true;
    } on FirebaseFunctionsException catch (error) {
      throw Exception(_mapFollowFunctionError(error));
    }
  }

  Future<void> followUser({
    required String followerId,
    required String followeeId,
  }) async {
    final trimmedFollowerId = _normalizeRequiredUserId(followerId, 'Follower');
    final trimmedFolloweeId = _normalizeRequiredUserId(followeeId, 'Followee');
    if (trimmedFollowerId == trimmedFolloweeId) {
      throw Exception('You cannot follow yourself.');
    }
    await _setFollowState(
      followerId: trimmedFollowerId,
      followeeId: trimmedFolloweeId,
      desiredFollowing: true,
    );
  }

  Future<void> unfollowUser({
    required String followerId,
    required String followeeId,
  }) async {
    final trimmedFollowerId = _normalizeRequiredUserId(followerId, 'Follower');
    final trimmedFolloweeId = _normalizeRequiredUserId(followeeId, 'Followee');
    if (trimmedFollowerId == trimmedFolloweeId) {
      return;
    }

    await _setFollowState(
      followerId: trimmedFollowerId,
      followeeId: trimmedFolloweeId,
      desiredFollowing: false,
    );
  }

  Future<bool> toggleFollow({
    required String followerId,
    required String followeeId,
    required bool currentlyFollowing,
  }) async {
    final trimmedFollowerId = _normalizeRequiredUserId(followerId, 'Follower');
    final trimmedFolloweeId = _normalizeRequiredUserId(followeeId, 'Followee');
    if (trimmedFollowerId == trimmedFolloweeId) {
      throw Exception('You cannot follow yourself.');
    }
    return _setFollowState(
      followerId: trimmedFollowerId,
      followeeId: trimmedFolloweeId,
      desiredFollowing: !currentlyFollowing,
    );
  }

  Future<bool> _setFollowState({
    required String followerId,
    required String followeeId,
    required bool desiredFollowing,
  }) async {
    try {
      final data = await _invoke('setFollowState', {
        'followeeId': followeeId,
        'desiredFollowing': desiredFollowing,
      });
      final isFollowing = data['isFollowing'] == true;
      final changed = data['changed'] == true;
      if (changed) {
        _changesController.add(
          FollowChange(
            followerId: followerId,
            followeeId: followeeId,
            isFollowing: isFollowing,
          ),
        );
      }
      if (changed && isFollowing) {
        try {
          await _notificationRepository.createFollowNotification(
            recipientId: followeeId,
          );
        } catch (_) {
          // Notifications are best-effort and should not break follow success.
        }
      }
      return isFollowing;
    } on FirebaseFunctionsException catch (error) {
      throw Exception(_mapFollowFunctionError(error));
    }
  }

  Future<Set<String>> fetchFollowingIds(String userId) async {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) return <String>{};

    final query = _followsCollection.where(
      'followerId',
      isEqualTo: trimmedUserId,
    );
    // Callable mutations happen on the server and do not update this client's
    // local query cache. A normal get checks the server when online while still
    // retaining Firestore's offline fallback behavior.
    final snapshot = await query.get();

    return snapshot.docs
        .map((doc) => (doc.data()['followeeId'] as String? ?? '').trim())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<FollowIdsPage> fetchFollowingIdsPage({
    required String userId,
    DocumentSnapshot<Map<String, dynamic>>? lastDoc,
    int limit = 15,
  }) async {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) {
      return const FollowIdsPage(
        userIds: <String>[],
        lastDocument: null,
        hasMore: false,
      );
    }

    Query<Map<String, dynamic>> query = _followsCollection
        .where('followerId', isEqualTo: trimmedUserId)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (lastDoc != null) {
      query = query.startAfterDocument(lastDoc);
    }

    final snapshot = await query.get();
    return FollowIdsPage(
      userIds: snapshot.docs
          .map((doc) => (doc.data()['followeeId'] as String? ?? '').trim())
          .where((id) => id.isNotEmpty)
          .toList(growable: false),
      lastDocument: snapshot.docs.isEmpty ? lastDoc : snapshot.docs.last,
      hasMore: snapshot.docs.length == limit,
    );
  }

  Future<FollowIdsPage> fetchFollowerIdsPage({
    required String userId,
    DocumentSnapshot<Map<String, dynamic>>? lastDoc,
    int limit = 15,
  }) async {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) {
      return const FollowIdsPage(
        userIds: <String>[],
        lastDocument: null,
        hasMore: false,
      );
    }

    Query<Map<String, dynamic>> query = _followsCollection
        .where('followeeId', isEqualTo: trimmedUserId)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (lastDoc != null) {
      query = query.startAfterDocument(lastDoc);
    }

    final snapshot = await query.get();
    return FollowIdsPage(
      userIds: snapshot.docs
          .map((doc) => (doc.data()['followerId'] as String? ?? '').trim())
          .where((id) => id.isNotEmpty)
          .toList(growable: false),
      lastDocument: snapshot.docs.isEmpty ? lastDoc : snapshot.docs.last,
      hasMore: snapshot.docs.length == limit,
    );
  }

  Future<ProfileFollowCounts> fetchProfileFollowCounts(String userId) async {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) {
      return const ProfileFollowCounts(followerCount: 0, followingCount: 0);
    }

    try {
      final callable = _functions.httpsCallable('getProfileFollowCounts');
      final result = await callable.call<Map<String, dynamic>>({
        'userId': trimmedUserId,
      });
      final data = result.data;
      return ProfileFollowCounts(
        followerCount: (data['followerCount'] as num?)?.toInt() ?? 0,
        followingCount: (data['followingCount'] as num?)?.toInt() ?? 0,
      );
    } on FirebaseFunctionsException catch (error) {
      throw Exception(
        error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'We could not load profile counts right now.',
      );
    }
  }

  String _mapFollowFunctionError(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'You do not have permission to update this follow right now.';
      case 'unauthenticated':
        return 'Please sign in again and try once more.';
      default:
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'We could not update the follow right now. Please try again.';
    }
  }
}
