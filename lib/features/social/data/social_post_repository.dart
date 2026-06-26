import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

import '../../notifications/data/repositories/notification_repository.dart';
import '../../profile/data/repositories/profile_repository.dart';
import '../../profile/domain/models/user_profile.dart';
import '../domain/models/comment_model.dart';
import '../domain/models/social_post_model.dart';

class SocialFeedPage {
  final List<SocialPostModel> posts;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;

  const SocialFeedPage({
    required this.posts,
    required this.lastDocument,
    required this.hasMore,
  });
}

class CommentPage {
  final List<CommentModel> comments;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;

  const CommentPage({
    required this.comments,
    required this.lastDocument,
    required this.hasMore,
  });
}

class ExploreHashtagSummary {
  final String tag;
  final int postCount;
  final List<String> recentPostIds;
  final Timestamp? lastUsedAt;

  const ExploreHashtagSummary({
    required this.tag,
    required this.postCount,
    required this.recentPostIds,
    required this.lastUsedAt,
  });

  factory ExploreHashtagSummary.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ExploreHashtagSummary(
      tag: (data['tag'] as String? ?? doc.id).trim().toLowerCase(),
      postCount: (data['postCount'] as num?)?.toInt() ?? 0,
      recentPostIds: (data['recentPostIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toList(growable: false),
      lastUsedAt: data['lastUsedAt'] as Timestamp?,
    );
  }
}

class SocialPostRepository {
  SocialPostRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
    ProfileRepository? profileRepository,
    NotificationRepository? notificationRepository,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _profileRepository = profileRepository ?? ProfileRepository(),
       _notificationRepository =
           notificationRepository ?? NotificationRepository();

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
  final ProfileRepository _profileRepository;
  final NotificationRepository _notificationRepository;

  CollectionReference<Map<String, dynamic>> get _postsCollection =>
      _firestore.collection('socialPosts');
  CollectionReference<Map<String, dynamic>> get _hashtagsCollection =>
      _firestore.collection('hashtags');

  // TODO(nishant): Move this counter mutation to Cloud Function before
  // production abuse scale.
  Future<void> _updatePostLikeCounter({
    required Transaction transaction,
    required DocumentReference<Map<String, dynamic>> postRef,
    required int nextLikeCount,
  }) async {
    transaction.update(postRef, {'likeCount': nextLikeCount});
  }

  // TODO(nishant): Move this counter mutation to Cloud Function before
  // production abuse scale.
  Future<void> _updatePostCommentCounter({
    required Transaction transaction,
    required DocumentReference<Map<String, dynamic>> postRef,
    required int nextCommentCount,
  }) async {
    transaction.update(postRef, {'commentCount': nextCommentCount});
  }

  // TODO(nishant): Move this counter mutation to Cloud Function before
  // production abuse scale.
  Future<void> _updatePostShareCounter({
    required Transaction transaction,
    required DocumentReference<Map<String, dynamic>> postRef,
    required int nextShareCount,
  }) async {
    transaction.update(postRef, {'shareCount': nextShareCount});
  }

  // TODO(nishant): Move this counter mutation and moderation threshold
  // transition to Cloud Function before production abuse scale.
  Future<void> _updatePostReportCounter({
    required Transaction transaction,
    required DocumentReference<Map<String, dynamic>> postRef,
    required int nextReportCount,
  }) async {
    transaction.update(postRef, {
      'reportCount': nextReportCount,
      'lastReportedAt': FieldValue.serverTimestamp(),
      if (nextReportCount >= 5) 'moderationStatus': 'pending',
    });
  }

  // TODO(nishant): Move this counter mutation and moderation threshold
  // transition to Cloud Function before production abuse scale.
  Future<void> _updateCommentReportCounter({
    required Transaction transaction,
    required DocumentReference<Map<String, dynamic>> commentRef,
    required int nextReportCount,
  }) async {
    transaction.update(commentRef, {
      'reportCount': nextReportCount,
      'lastReportedAt': FieldValue.serverTimestamp(),
      if (nextReportCount >= 5) 'moderationStatus': 'pending',
    });
  }

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw Exception('User not authenticated');
    }
    return uid;
  }

  Query<Map<String, dynamic>> get _visiblePostsQuery => _firestore
      .collection('socialPosts')
      .where('visibilityStatus', isEqualTo: 'visible')
      .where('moderationStatus', isEqualTo: 'approved')
      .orderBy('createdAt', descending: true);

  Future<SocialFeedPage> fetchVisiblePosts({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 10,
  }) async {
    Query<Map<String, dynamic>> query = _visiblePostsQuery.limit(limit);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await query.get();
    final posts = snapshot.docs.map(SocialPostModel.fromDocument).toList();
    return SocialFeedPage(
      posts: posts,
      lastDocument: snapshot.docs.isEmpty ? startAfter : snapshot.docs.last,
      hasMore: snapshot.docs.length == limit,
    );
  }

  Future<List<SocialPostModel>> fetchRecentVisiblePosts({
    int limit = 30,
  }) async {
    final page = await fetchVisiblePosts(limit: limit);
    return page.posts;
  }

  Future<List<ExploreHashtagSummary>> fetchTrendingHashtags({
    int limit = 10,
  }) async {
    final snapshot = await _hashtagsCollection
        .orderBy('lastUsedAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs.map(ExploreHashtagSummary.fromDocument).toList();
  }

  Future<List<ExploreHashtagSummary>> searchHashtags(
    String query, {
    int limit = 10,
  }) async {
    final normalized = normalizeHashtag(query);
    if (normalized.isEmpty) return const <ExploreHashtagSummary>[];

    final snapshot = await _hashtagsCollection
        .orderBy('tag')
        .startAt([normalized])
        .endAt(['$normalized\uf8ff'])
        .limit(limit)
        .get();
    return snapshot.docs.map(ExploreHashtagSummary.fromDocument).toList();
  }

  Future<List<SocialPostModel>> fetchPostsByIds(
    List<String> postIds, {
    int limit = 12,
  }) async {
    final normalizedIds = postIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .take(limit)
        .toList(growable: false);
    if (normalizedIds.isEmpty) return const <SocialPostModel>[];

    final postsById = <String, SocialPostModel>{};
    const chunkSize = 10;

    for (var start = 0; start < normalizedIds.length; start += chunkSize) {
      final end = math.min(start + chunkSize, normalizedIds.length);
      final chunk = normalizedIds.sublist(start, end);
      final snapshot = await _postsCollection
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        final post = SocialPostModel.fromDocument(doc);
        if (post.visibilityStatus == 'visible' &&
            post.moderationStatus == 'approved') {
          postsById[post.id] = post;
        }
      }
    }

    return normalizedIds
        .map((id) => postsById[id])
        .whereType<SocialPostModel>()
        .toList(growable: false);
  }

  Future<List<SocialPostModel>> fetchPopularPosts({
    int limit = 10,
    bool allowLocalFallback = true,
  }) async {
    try {
      final snapshot = await _postsCollection
          .where('visibilityStatus', isEqualTo: 'visible')
          .where('moderationStatus', isEqualTo: 'approved')
          .orderBy('likeCount', descending: true)
          .limit(limit)
          .get();
      return snapshot.docs.map(SocialPostModel.fromDocument).toList();
    } on FirebaseException catch (error) {
      if (error.code != 'failed-precondition' || !allowLocalFallback) {
        rethrow;
      }

      final recentPosts = await fetchRecentVisiblePosts(limit: 30);
      final sorted = recentPosts.toList(growable: false)
        ..sort((a, b) {
          final scoreA = a.likeCount + (a.commentCount * 2);
          final scoreB = b.likeCount + (b.commentCount * 2);
          return scoreB.compareTo(scoreA);
        });
      return sorted.take(limit).toList(growable: false);
    }
  }

  Future<List<SocialPostModel>> searchPostsByHashtag(
    String hashtag, {
    int limit = 12,
  }) async {
    final normalized = normalizeHashtag(hashtag);
    if (normalized.isEmpty) {
      return const <SocialPostModel>[];
    }
    final matches = await searchHashtags(normalized, limit: 10);
    if (matches.isEmpty) return const <SocialPostModel>[];

    ExploreHashtagSummary selected = matches.first;
    for (final match in matches) {
      if (match.tag == normalized) {
        selected = match;
        break;
      }
    }

    return fetchPostsByIds(selected.recentPostIds, limit: limit);
  }

  Future<SocialPostModel> createPost({
    required List<XFile> images,
    required SocialPostAspectRatio aspectRatio,
    required String caption,
    required List<String> hashtags,
  }) async {
    if (images.isEmpty) {
      throw Exception('Select at least one image.');
    }
    if (images.length > 5) {
      throw Exception('You can upload up to 5 images.');
    }

    final authorId = await _ensureAuthenticatedForStorageWrite();
    final profile = await _profileRepository.getCurrentUserProfile();
    final postRef = _postsCollection.doc();
    final uploads = await _uploadImages(
      authorId: authorId,
      postId: postRef.id,
      images: images,
      aspectRatio: aspectRatio,
    );

    final payload = <String, dynamic>{
      'id': postRef.id,
      'authorId': authorId,
      'authorType': 'user',
      'authorDisplayName': profile.name,
      'authorUsername': profile.displayUsername,
      'authorPhotoUrl': profile.profileImageUrl,
      'authorCategoryLabel': _buildCategoryLabel(profile),
      'authorCity': profile.city,
      'authorState': profile.state,
      'isAdminPost': false,
      'adminPriorityBoost': 0,
      'recentEngagementScore': 0,
      'imageUrls': uploads.fullSizeUrls,
      'thumbnailUrls': uploads.thumbnailUrls,
      'imageAspectRatio': aspectRatio.value,
      'caption': caption.trim(),
      'hashtags': hashtags,
      'likeCount': 0,
      'commentCount': 0,
      'shareCount': 0,
      'saveCount': 0,
      'reportCount': 0,
      'visibilityStatus': 'visible',
      'moderationStatus': 'approved',
      'moderationReason': '',
      'moderatedBy': '',
      'moderatedAt': null,
      'lastReportedAt': null,
      'createdAtEpoch': DateTime.now().millisecondsSinceEpoch,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await postRef.set(payload);
    await _updateHashtagDocuments(hashtags: hashtags, postId: postRef.id);
    final createdSnapshot = await postRef.get();
    return SocialPostModel.fromDocument(createdSnapshot);
  }

  Future<String> _ensureAuthenticatedForStorageWrite() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('Please sign in again before publishing a post.');
    }

    await currentUser.reload();
    final refreshedUser = _auth.currentUser;
    if (refreshedUser == null) {
      throw Exception('Please sign in again before publishing a post.');
    }

    await refreshedUser.getIdToken(true);
    return refreshedUser.uid;
  }

  String normalizeHashtag(String input) {
    final collapsed = input.trim().replaceAll('#', '').toLowerCase();
    if (collapsed.isEmpty || collapsed.contains(' ')) {
      return '';
    }
    return collapsed;
  }

  Future<bool> hasCurrentUserLikedPost(String postId) async {
    final likeSnapshot = await _postsCollection
        .doc(postId)
        .collection('likes')
        .doc(_uid)
        .get();
    return likeSnapshot.exists;
  }

  Future<Set<String>> fetchCurrentUserLikedPostIds(List<String> postIds) async {
    if (postIds.isEmpty) return <String>{};

    final entries = await Future.wait(
      postIds.map((postId) async {
        final liked = await hasCurrentUserLikedPost(postId);
        return MapEntry(postId, liked);
      }),
    );

    return entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toSet();
  }

  Future<void> toggleLike({
    required String postId,
    required String currentUserId,
  }) async {
    final postRef = _postsCollection.doc(postId);
    final likeRef = postRef.collection('likes').doc(currentUserId);
    var createdLike = false;
    var recipientId = '';

    await _firestore.runTransaction((transaction) async {
      final postSnapshot = await transaction.get(postRef);
      if (!postSnapshot.exists) {
        throw Exception('Post not found.');
      }
      final postData = postSnapshot.data();
      if (postData == null) {
        throw Exception('Post not found.');
      }
      final visibilityStatus = (postData['visibilityStatus'] as String? ?? '')
          .trim();
      final moderationStatus = (postData['moderationStatus'] as String? ?? '')
          .trim();
      if (visibilityStatus != 'visible' || moderationStatus != 'approved') {
        throw Exception('This post is no longer available for likes.');
      }
      recipientId = (postData['authorId'] as String? ?? '').trim();

      final likeSnapshot = await transaction.get(likeRef);
      final currentLikeCount = (postData['likeCount'] as num?)?.toInt() ?? 0;

      if (likeSnapshot.exists) {
        transaction.delete(likeRef);
        await _updatePostLikeCounter(
          transaction: transaction,
          postRef: postRef,
          nextLikeCount: math.max(0, currentLikeCount - 1),
        );
        return;
      }

      transaction.set(likeRef, {
        'userId': currentUserId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      createdLike = true;
      await _updatePostLikeCounter(
        transaction: transaction,
        postRef: postRef,
        nextLikeCount: currentLikeCount + 1,
      );
    });

    if (createdLike && recipientId.isNotEmpty && recipientId != currentUserId) {
      try {
        await _notificationRepository.createLikeNotification(
          recipientId: recipientId,
          postId: postId,
        );
      } catch (_) {
        // Notifications are best-effort and should not break like success.
      }
    }
  }

  Future<int> incrementShareCount({required String postId}) async {
    final postRef = _postsCollection.doc(postId);
    var nextShareCount = 0;

    await _firestore.runTransaction((transaction) async {
      final postSnapshot = await transaction.get(postRef);
      if (!postSnapshot.exists) {
        throw Exception('Post not found.');
      }
      final postData = postSnapshot.data();
      if (postData == null) {
        throw Exception('Post not found.');
      }

      final visibilityStatus = (postData['visibilityStatus'] as String? ?? '')
          .trim();
      final moderationStatus = (postData['moderationStatus'] as String? ?? '')
          .trim();
      if (visibilityStatus != 'visible' || moderationStatus != 'approved') {
        throw Exception('This post is no longer available for sharing.');
      }

      final currentShareCount = (postData['shareCount'] as num?)?.toInt() ?? 0;
      nextShareCount = currentShareCount + 1;
      await _updatePostShareCounter(
        transaction: transaction,
        postRef: postRef,
        nextShareCount: nextShareCount,
      );
    });

    return nextShareCount;
  }

  Future<bool> reportPost({
    required String postId,
    required String currentUserId,
    required String reason,
  }) async {
    final postRef = _postsCollection.doc(postId);
    final reportRef = postRef.collection('reports').doc(currentUserId);
    var movedToPending = false;

    await _firestore.runTransaction((transaction) async {
      final postSnapshot = await transaction.get(postRef);
      if (!postSnapshot.exists) {
        throw Exception('Post not found.');
      }
      final postData = postSnapshot.data();
      if (postData == null) {
        throw Exception('Post not found.');
      }
      final visibilityStatus = (postData['visibilityStatus'] as String? ?? '')
          .trim();
      final moderationStatus = (postData['moderationStatus'] as String? ?? '')
          .trim();
      if (visibilityStatus != 'visible' || moderationStatus != 'approved') {
        throw Exception('This post is no longer available for reports.');
      }

      final reportSnapshot = await transaction.get(reportRef);
      if (reportSnapshot.exists) {
        throw Exception('You already reported this post.');
      }

      final currentReportCount =
          (postData['reportCount'] as num?)?.toInt() ?? 0;

      transaction.set(reportRef, {
        'reporterId': currentUserId,
        'reason': reason.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      final nextReportCount = currentReportCount + 1;
      movedToPending = nextReportCount >= 5;
      await _updatePostReportCounter(
        transaction: transaction,
        postRef: postRef,
        nextReportCount: nextReportCount,
      );
    });

    return movedToPending;
  }

  Future<CommentPage> fetchComments({
    required String postId,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 10,
  }) async {
    try {
      final comments = <CommentModel>[];
      DocumentSnapshot<Map<String, dynamic>>? cursor = startAfter;
      var hasMore = true;
      final pageSize = math.max(limit * 2, 20);

      while (comments.length < limit && hasMore) {
        Query<Map<String, dynamic>> query = _postsCollection
            .doc(postId)
            .collection('comments')
            .orderBy('createdAt', descending: true)
            .limit(pageSize);

        if (cursor != null) {
          query = query.startAfterDocument(cursor);
        }

        final snapshot = await query.get();
        if (snapshot.docs.isEmpty) {
          hasMore = false;
          break;
        }

        cursor = snapshot.docs.last;
        hasMore = snapshot.docs.length == pageSize;

        for (final doc in snapshot.docs) {
          final comment = CommentModel.fromDocument(doc);
          if (comment.visibilityStatus == 'visible' &&
              comment.moderationStatus == 'approved') {
            comments.add(comment);
            if (comments.length == limit) {
              break;
            }
          }
        }
      }

      return CommentPage(
        comments: comments,
        lastDocument: cursor ?? startAfter,
        hasMore: hasMore,
      );
    } on FirebaseException catch (error) {
      throw Exception(_mapCommentQueryError(error));
    }
  }

  Future<CommentModel> addComment({
    required String postId,
    required String currentUserId,
    required String text,
  }) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      throw Exception('Comment cannot be empty.');
    }
    if (trimmedText.length > 500) {
      throw Exception('Comments can be up to 500 characters.');
    }

    final profile = await _profileRepository.getCurrentUserProfile();
    final postRef = _postsCollection.doc(postId);
    final commentRef = postRef.collection('comments').doc();
    var postAuthorId = '';

    await _firestore.runTransaction((transaction) async {
      final postSnapshot = await transaction.get(postRef);
      if (!postSnapshot.exists) {
        throw Exception('Post not found.');
      }
      final postData = postSnapshot.data();
      if (postData == null) {
        throw Exception('Post not found.');
      }
      final visibilityStatus = (postData['visibilityStatus'] as String? ?? '')
          .trim();
      final moderationStatus = (postData['moderationStatus'] as String? ?? '')
          .trim();
      if (visibilityStatus != 'visible' || moderationStatus != 'approved') {
        throw Exception('This post is no longer available for comments.');
      }
      postAuthorId = (postData['authorId'] as String? ?? '').trim();

      final currentCommentCount =
          (postData['commentCount'] as num?)?.toInt() ?? 0;

      transaction.set(commentRef, {
        'id': commentRef.id,
        'postId': postId,
        'authorId': currentUserId,
        'authorDisplayName': profile.name,
        'authorUsername': profile.displayUsername,
        'authorPhotoUrl': profile.profileImageUrl,
        'parentPostAuthorId': (postData['authorId'] as String? ?? '').trim(),
        'parentPostPreview': _buildParentPostPreview(
          postData['caption'] as String?,
        ),
        'text': trimmedText,
        'likeCount': 0,
        'reportCount': 0,
        'visibilityStatus': 'visible',
        'moderationStatus': 'approved',
        'moderationReason': '',
        'moderatedBy': '',
        'moderatedAt': null,
        'lastReportedAt': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _updatePostCommentCounter(
        transaction: transaction,
        postRef: postRef,
        nextCommentCount: currentCommentCount + 1,
      );
    });

    final createdSnapshot = await commentRef.get();
    final createdComment = CommentModel.fromDocument(createdSnapshot);
    if (postAuthorId.isNotEmpty && postAuthorId != currentUserId) {
      try {
        await _notificationRepository.createCommentNotification(
          recipientId: postAuthorId,
          postId: postId,
          commentId: createdComment.id,
        );
      } catch (_) {
        // Notifications are best-effort and should not break comment success.
      }
    }
    return createdComment;
  }

  Future<void> softDeleteComment({
    required String postId,
    required String commentId,
    required String currentUserId,
  }) async {
    final postRef = _postsCollection.doc(postId);
    final commentRef = postRef.collection('comments').doc(commentId);

    await _firestore.runTransaction((transaction) async {
      final postSnapshot = await transaction.get(postRef);
      if (!postSnapshot.exists) {
        throw Exception('Post not found.');
      }
      final postData = postSnapshot.data();
      if (postData == null) {
        throw Exception('Post not found.');
      }

      final commentSnapshot = await transaction.get(commentRef);
      if (!commentSnapshot.exists) {
        throw Exception('Comment not found.');
      }
      final commentData = commentSnapshot.data();
      if (commentData == null) {
        throw Exception('Comment not found.');
      }
      if ((commentData['authorId'] as String? ?? '').trim() != currentUserId) {
        throw Exception('You can only delete your own comment.');
      }
      if ((commentData['visibilityStatus'] as String? ?? '').trim() !=
          'visible') {
        throw Exception('This comment is already removed.');
      }

      final currentCommentCount =
          (postData['commentCount'] as num?)?.toInt() ?? 0;
      transaction.update(commentRef, {
        'visibilityStatus': 'deleted',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _updatePostCommentCounter(
        transaction: transaction,
        postRef: postRef,
        nextCommentCount: math.max(0, currentCommentCount - 1),
      );
    });
  }

  Future<bool> reportComment({
    required String postId,
    required String commentId,
    required String currentUserId,
    required String reason,
  }) async {
    final postRef = _postsCollection.doc(postId);
    final commentRef = postRef.collection('comments').doc(commentId);
    final reportRef = commentRef.collection('reports').doc(currentUserId);
    var movedToPending = false;

    await _firestore.runTransaction((transaction) async {
      final postSnapshot = await transaction.get(postRef);
      if (!postSnapshot.exists) {
        throw Exception('Post not found.');
      }

      final commentSnapshot = await transaction.get(commentRef);
      if (!commentSnapshot.exists) {
        throw Exception('Comment not found.');
      }
      final commentData = commentSnapshot.data();
      if (commentData == null) {
        throw Exception('Comment not found.');
      }
      final visibilityStatus =
          (commentData['visibilityStatus'] as String? ?? '').trim();
      final moderationStatus =
          (commentData['moderationStatus'] as String? ?? '').trim();
      if (visibilityStatus != 'visible' || moderationStatus != 'approved') {
        throw Exception('This comment is no longer available for reports.');
      }

      final reportSnapshot = await transaction.get(reportRef);
      if (reportSnapshot.exists) {
        throw Exception('You already reported this comment.');
      }

      final currentReportCount =
          (commentData['reportCount'] as num?)?.toInt() ?? 0;
      final nextReportCount = currentReportCount + 1;

      transaction.set(reportRef, {
        'reporterId': currentUserId,
        'reason': reason.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      movedToPending = nextReportCount >= 5;
      await _updateCommentReportCounter(
        transaction: transaction,
        commentRef: commentRef,
        nextReportCount: nextReportCount,
      );
    });

    return movedToPending;
  }

  Future<void> softDeletePost({
    required String postId,
    required String currentUserId,
  }) async {
    final postRef = _postsCollection.doc(postId);
    final snapshot = await postRef.get();
    final data = snapshot.data();

    if (!snapshot.exists || data == null) {
      throw Exception('Post not found.');
    }
    if ((data['authorId'] as String? ?? '').trim() != currentUserId) {
      throw Exception('You can only delete your own posts.');
    }
    if ((data['visibilityStatus'] as String? ?? '').trim() != 'visible') {
      throw Exception('This post is already removed from the feed.');
    }

    await postRef.update({
      'visibilityStatus': 'deleted',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  String _buildCategoryLabel(UserProfile profile) {
    if (profile.role == 'serviceProvider') {
      return 'Provider';
    }
    if (profile.role == 'petLover') {
      return 'Pet Lover';
    }
    return 'Pet Parent';
  }

  String _buildParentPostPreview(String? caption) {
    final trimmed = (caption ?? '').trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length <= 80) return trimmed;
    return '${trimmed.substring(0, 80).trim()}...';
  }

  Future<void> _updateHashtagDocuments({
    required List<String> hashtags,
    required String postId,
  }) async {
    final normalizedTags = hashtags
        .map(normalizeHashtag)
        .where(_isValidHashtagTag)
        .toSet()
        .toList(growable: false);
    if (normalizedTags.isEmpty) return;

    await _firestore.runTransaction((transaction) async {
      for (final tag in normalizedTags) {
        final ref = _hashtagsCollection.doc(tag);
        final snapshot = await transaction.get(ref);
        final data = snapshot.data() ?? const <String, dynamic>{};
        final currentPostCount = (data['postCount'] as num?)?.toInt() ?? 0;
        final recentPostIds =
            (data['recentPostIds'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .map((id) => id.trim())
                .where((id) => id.isNotEmpty)
                .toList(growable: true);

        if (!recentPostIds.contains(postId)) {
          recentPostIds.insert(0, postId);
        } else {
          recentPostIds
            ..remove(postId)
            ..insert(0, postId);
        }
        if (recentPostIds.length > 30) {
          recentPostIds.removeRange(30, recentPostIds.length);
        }

        transaction.set(ref, {
          'tag': tag,
          'postCount': currentPostCount + 1,
          'recentPostIds': recentPostIds,
          'lastUsedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }

  bool _isValidHashtagTag(String tag) {
    if (tag.isEmpty || tag.length > 30) {
      return false;
    }
    if (tag.contains(RegExp(r'\s'))) {
      return false;
    }
    return RegExp(r'^[a-z0-9_]+$').hasMatch(tag);
  }

  Future<_SocialUploadResult> _uploadImages({
    required String authorId,
    required String postId,
    required List<XFile> images,
    required SocialPostAspectRatio aspectRatio,
  }) async {
    final fullSizeUrls = <String>[];
    final thumbnailUrls = <String>[];

    try {
      for (var index = 0; index < images.length; index++) {
        final originalSize = await images[index].length();
        if (originalSize > 5 * 1024 * 1024) {
          throw Exception('Each image must be 5 MB or smaller before upload.');
        }

        final bytes = await images[index].readAsBytes();
        final processed = await _processImage(bytes, aspectRatio: aspectRatio);

        final imageRef = _storage.ref().child(
          'socialPosts/$authorId/$postId/images/$index.jpg',
        );
        final thumbRef = _storage.ref().child(
          'socialPosts/$authorId/$postId/thumbs/$index.jpg',
        );

        await imageRef.putData(
          processed.feedBytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        await thumbRef.putData(
          processed.thumbnailBytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );

        fullSizeUrls.add(await imageRef.getDownloadURL());
        thumbnailUrls.add(await thumbRef.getDownloadURL());
      }
    } on FirebaseException catch (error) {
      throw Exception(_mapStorageUploadError(error));
    }

    return _SocialUploadResult(
      fullSizeUrls: fullSizeUrls,
      thumbnailUrls: thumbnailUrls,
    );
  }

  String _mapStorageUploadError(FirebaseException error) {
    switch (error.code) {
      case 'unauthorized':
        return 'Image upload is blocked by Firebase Storage permissions. Sign in again, then deploy the latest storage rules so social post uploads under socialPosts/{uid}/{postId} are allowed.';
      case 'unauthenticated':
        return 'Please sign in again before publishing a post.';
      case 'object-not-found':
        return 'The upload destination could not be created. Please try again.';
      case 'retry-limit-exceeded':
        return 'Upload timed out. Please check your connection and try again.';
      default:
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'Unable to upload post images right now. Please try again.';
    }
  }

  String _mapCommentQueryError(FirebaseException error) {
    switch (error.code) {
      case 'failed-precondition':
        return 'Comments are temporarily unavailable because the required Firestore index is not deployed yet. Deploy the latest Firestore indexes and try again.';
      case 'permission-denied':
        return 'You do not have permission to load comments right now.';
      default:
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'Unable to load comments right now. Please try again.';
    }
  }

  Future<_ProcessedImageBytes> _processImage(
    Uint8List originalBytes, {
    required SocialPostAspectRatio aspectRatio,
  }) async {
    final decoded = img.decodeImage(originalBytes);
    if (decoded == null) {
      throw Exception('One of the selected images could not be processed.');
    }

    final fitted = _fitImageToAspectRatio(decoded, aspectRatio);
    final resizedFeed = img.copyResize(
      fitted,
      width: math.min(fitted.width, 1080),
    );
    final resizedThumb = img.copyResize(
      fitted,
      width: math.min(fitted.width, 300),
    );

    final feedBytes = await FlutterImageCompress.compressWithList(
      Uint8List.fromList(img.encodeJpg(resizedFeed, quality: 88)),
      quality: 78,
      format: CompressFormat.jpeg,
    );
    final thumbBytes = await FlutterImageCompress.compressWithList(
      Uint8List.fromList(img.encodeJpg(resizedThumb, quality: 80)),
      quality: 70,
      format: CompressFormat.jpeg,
    );

    return _ProcessedImageBytes(
      feedBytes: Uint8List.fromList(feedBytes),
      thumbnailBytes: Uint8List.fromList(thumbBytes),
    );
  }

  img.Image _fitImageToAspectRatio(
    img.Image source,
    SocialPostAspectRatio aspectRatio,
  ) {
    final targetRatio = switch (aspectRatio) {
      SocialPostAspectRatio.square => 1.0,
      SocialPostAspectRatio.portrait => 4 / 5,
      SocialPostAspectRatio.landscape => 1.91 / 1,
    };

    final sourceRatio = source.width / source.height;
    if ((sourceRatio - targetRatio).abs() < 0.01) {
      return source;
    }

    var targetWidth = source.width;
    var targetHeight = source.height;

    if (sourceRatio > targetRatio) {
      targetHeight = math.max(1, (source.width / targetRatio).round());
    } else {
      targetWidth = math.max(1, (source.height * targetRatio).round());
    }

    final canvas = img.Image(width: targetWidth, height: targetHeight);
    img.fill(canvas, color: img.ColorRgb8(252, 248, 245));
    final offsetX = ((targetWidth - source.width) / 2).round();
    final offsetY = ((targetHeight - source.height) / 2).round();
    img.compositeImage(canvas, source, dstX: offsetX, dstY: offsetY);
    return canvas;
  }
}

class _ProcessedImageBytes {
  final Uint8List feedBytes;
  final Uint8List thumbnailBytes;

  const _ProcessedImageBytes({
    required this.feedBytes,
    required this.thumbnailBytes,
  });
}

class _SocialUploadResult {
  final List<String> fullSizeUrls;
  final List<String> thumbnailUrls;

  const _SocialUploadResult({
    required this.fullSizeUrls,
    required this.thumbnailUrls,
  });
}
