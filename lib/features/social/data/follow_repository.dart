import 'package:cloud_firestore/cloud_firestore.dart';

import '../../notifications/data/repositories/notification_repository.dart';

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

class FollowRepository {
  FollowRepository({
    FirebaseFirestore? firestore,
    NotificationRepository? notificationRepository,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _notificationRepository =
           notificationRepository ?? NotificationRepository();

  final FirebaseFirestore _firestore;
  final NotificationRepository _notificationRepository;

  CollectionReference<Map<String, dynamic>> get _followsCollection =>
      _firestore.collection('follows');

  String _normalizeRequiredUserId(String userId, String label) {
    final trimmed = userId.trim();
    if (trimmed.isEmpty) {
      throw Exception('$label is missing.');
    }
    return trimmed;
  }

  String followIdFor({
    required String followerId,
    required String followeeId,
  }) {
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

    final snapshot = await _followsCollection
        .doc(followIdFor(followerId: followerId, followeeId: followeeId))
        .get();
    return snapshot.exists;
  }

  Future<void> followUser({
    required String followerId,
    required String followeeId,
  }) async {
    final trimmedFollowerId = _normalizeRequiredUserId(
      followerId,
      'Follower',
    );
    final trimmedFolloweeId = _normalizeRequiredUserId(
      followeeId,
      'Followee',
    );
    if (trimmedFollowerId == trimmedFolloweeId) {
      throw Exception('You cannot follow yourself.');
    }

    final followRef = _followsCollection.doc(
      followIdFor(
        followerId: trimmedFollowerId,
        followeeId: trimmedFolloweeId,
      ),
    );

    try {
      await followRef.set({
        'followerId': trimmedFollowerId,
        'followeeId': trimmedFolloweeId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      throw Exception(_mapFollowError(error));
    }

    try {
      await _notificationRepository.createFollowNotification(
        recipientId: trimmedFolloweeId,
      );
    } catch (_) {
      // Notifications are best-effort and should not break follow success.
    }
  }

  Future<void> unfollowUser({
    required String followerId,
    required String followeeId,
  }) async {
    final trimmedFollowerId = _normalizeRequiredUserId(
      followerId,
      'Follower',
    );
    final trimmedFolloweeId = _normalizeRequiredUserId(
      followeeId,
      'Followee',
    );
    if (trimmedFollowerId == trimmedFolloweeId) {
      return;
    }

    final followRef = _followsCollection.doc(
      followIdFor(
        followerId: trimmedFollowerId,
        followeeId: trimmedFolloweeId,
      ),
    );

    try {
      await followRef.delete();
    } on FirebaseException catch (error) {
      if (!_isMissingDocumentError(error)) {
        throw Exception(_mapFollowError(error));
      }
    }
  }

  Future<bool> toggleFollow({
    required String followerId,
    required String followeeId,
    required bool currentlyFollowing,
  }) async {
    if (currentlyFollowing) {
      await unfollowUser(followerId: followerId, followeeId: followeeId);
      return false;
    }

    await followUser(followerId: followerId, followeeId: followeeId);
    return true;
  }

  Future<Set<String>> fetchFollowingIds(String userId) async {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) return <String>{};

    final snapshot = await _followsCollection
        .where('followerId', isEqualTo: trimmedUserId)
        .get();

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

  // TODO(nishant): Public follower/following list support may need broader
  // read rules, user-scoped mirrors, or Cloud Functions before we expose
  // profile relationship lists safely at scale.

  bool _isMissingDocumentError(FirebaseException error) {
    return error.code == 'not-found' ||
        (error.message?.toLowerCase().contains('no document to update') ??
            false);
  }

  String _mapFollowError(FirebaseException error) {
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
