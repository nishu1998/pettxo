import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

import '../../../core/services/firestore_cache_service.dart';
import '../../notifications/data/repositories/notification_repository.dart';
import '../../explore/domain/models/explore_location_snapshot.dart';
import '../../profile/data/repositories/profile_repository.dart';
import '../../profile/domain/models/user_profile.dart';
import '../../blocking/data/blocked_relationship_repository.dart';
import '../domain/models/comment_model.dart';
import '../domain/models/social_post_model.dart';
import '../domain/hashtag_normalizer.dart' as hashtag_normalizer;

class SocialPostLikeState {
  final bool isLiked;
  final int likeCount;

  const SocialPostLikeState({required this.isLiked, required this.likeCount});
}

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

enum SocialPostUploadStage { preparing, uploading, finalizing }

@immutable
class SocialPostUploadProgress {
  const SocialPostUploadProgress({
    required this.stage,
    required this.fraction,
    required this.message,
  });

  final SocialPostUploadStage stage;
  final double fraction;
  final String message;
}

typedef SocialPostUploadProgressCallback =
    void Function(SocialPostUploadProgress progress);

enum SocialPostFirestoreBatchStatus {
  notStarted,
  committing,
  committed,
  failed,
}

enum SocialPostLocationIntentStatus {
  notRequested,
  pending,
  queuedInBatch,
  committed,
  failedWithBatch,
}

@immutable
class SocialPostPublishDiagnostics {
  const SocialPostPublishDiagnostics({
    required this.failedStage,
    required this.firebasePlugin,
    required this.firebaseCode,
    required this.sanitizedMessage,
    required this.sanitizedStoragePath,
    required this.originalUploadsCompleted,
    required this.thumbnailUploadsCompleted,
    required this.expectedImageCount,
    required this.firestoreBatchStatus,
    required this.locationIntentStatus,
    required this.imageIndex,
    required this.originalFileExists,
    required this.originalFileReadable,
    required this.originalByteSize,
    required this.processedByteSize,
    required this.thumbnailByteSize,
    required this.processedFormat,
    required this.thumbnailCreated,
    required this.storageTaskState,
    required this.uploadStarted,
    required this.bytesTransferred,
    required this.networkClassification,
    required this.failureDurationMs,
    required this.originalErrorType,
  });

  final String failedStage;
  final String firebasePlugin;
  final String firebaseCode;
  final String sanitizedMessage;
  final String sanitizedStoragePath;
  final int originalUploadsCompleted;
  final int thumbnailUploadsCompleted;
  final int expectedImageCount;
  final SocialPostFirestoreBatchStatus firestoreBatchStatus;
  final SocialPostLocationIntentStatus locationIntentStatus;
  final int? imageIndex;
  final bool? originalFileExists;
  final bool? originalFileReadable;
  final int? originalByteSize;
  final int? processedByteSize;
  final int? thumbnailByteSize;
  final String processedFormat;
  final bool thumbnailCreated;
  final String storageTaskState;
  final bool uploadStarted;
  final int? bytesTransferred;
  final String networkClassification;
  final int failureDurationMs;
  final String originalErrorType;

  String toDebugLog() =>
      'stage=$failedStage, plugin=$firebasePlugin, code=$firebaseCode, '
      'message=$sanitizedMessage, storagePath=$sanitizedStoragePath, '
      'originalUploads=$originalUploadsCompleted/$expectedImageCount, '
      'thumbnailUploads=$thumbnailUploadsCompleted/$expectedImageCount, '
      'firestoreBatch=${firestoreBatchStatus.name}, '
      'locationIntent=${locationIntentStatus.name}, image=$imageIndex/'
      '$expectedImageCount, fileExists=$originalFileExists, '
      'fileReadable=$originalFileReadable, originalBytes=$originalByteSize, '
      'processedBytes=$processedByteSize, thumbnailBytes=$thumbnailByteSize, '
      'format=$processedFormat, thumbnailCreated=$thumbnailCreated, '
      'storageTask=$storageTaskState, uploadStarted=$uploadStarted, '
      'bytesTransferred=$bytesTransferred, network=$networkClassification, '
      'durationMs=$failureDurationMs, errorType=$originalErrorType';
}

class SocialPostPublishException implements Exception {
  const SocialPostPublishException({
    required this.userMessage,
    required this.originalException,
    required this.diagnostics,
  });

  final String userMessage;
  final Object originalException;
  final SocialPostPublishDiagnostics diagnostics;

  FirebaseException? get firebaseException =>
      originalException is FirebaseException
      ? originalException as FirebaseException
      : null;

  @override
  String toString() => 'Exception: $userMessage';
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
  late final BlockedRelationshipRepository _blockedRelationships =
      BlockedRelationshipRepository(firestore: _firestore, auth: _auth);
  final Map<String, bool> _authorVisibilityCache = <String, bool>{};

  static const Set<String> _backendOwnedCreateFields = <String>{
    'homeScore',
    'homeRankVersion',
    'homeScoreUpdatedAt',
    'homeEligible',
    'discoverScore',
    'discoverRankVersion',
    'discoverScoreUpdatedAt',
    'discoverEligible',
    'nearbyEligible',
    'feedGeohash3',
    'feedGeohash4',
    'feedGeohash5',
    'feedCityKey',
    'feedStateKey',
    'feedLocationVersion',
    'feedLocationUpdatedAt',
    'feedLatitudeBucket',
    'feedLongitudeBucket',
    'isAdminPost',
    'adminPriorityBoost',
    'recentEngagementScore',
  };

  CollectionReference<Map<String, dynamic>> get _postsCollection =>
      _firestore.collection('socialPosts');
  CollectionReference<Map<String, dynamic>> get _hashtagsCollection =>
      _firestore.collection('hashtags');
  CollectionReference<Map<String, dynamic>>
  get _postLocationIntentsCollection =>
      _firestore.collection('socialPostLocationIntents');

  // Counter updates stay colocated with the write transaction for now.
  Future<void> _updatePostLikeCounter({
    required Transaction transaction,
    required DocumentReference<Map<String, dynamic>> postRef,
    required int nextLikeCount,
  }) async {
    transaction.update(postRef, {'likeCount': nextLikeCount});
  }

  // Counter updates stay colocated with the write transaction for now.
  Future<void> _updatePostCommentCounter({
    required Transaction transaction,
    required DocumentReference<Map<String, dynamic>> postRef,
    required int nextCommentCount,
  }) async {
    transaction.update(postRef, {'commentCount': nextCommentCount});
  }

  // Counter updates stay colocated with the write transaction for now.
  Future<void> _updatePostShareCounter({
    required Transaction transaction,
    required DocumentReference<Map<String, dynamic>> postRef,
    required int nextShareCount,
  }) async {
    transaction.update(postRef, {'shareCount': nextShareCount});
  }

  // Report updates keep moderation thresholds in the same transaction.
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

  // Report updates keep moderation thresholds in the same transaction.
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
    final posts = <SocialPostModel>[];
    DocumentSnapshot<Map<String, dynamic>>? cursor = startAfter;
    var hasMore = true;
    final pageSize = math.max(limit * 2, 20);

    while (posts.length < limit && hasMore) {
      Query<Map<String, dynamic>> query = _visiblePostsQuery.limit(pageSize);
      if (cursor != null) {
        query = query.startAfterDocument(cursor);
      }

      final snapshot = await FirestoreCacheService.getCollectionCacheFirst(
        query,
      );
      if (snapshot.docs.isEmpty) {
        hasMore = false;
        break;
      }

      cursor = snapshot.docs.last;
      hasMore = snapshot.docs.length == pageSize;
      final visiblePosts = await _filterPostsByVisibleAuthors(
        snapshot.docs.map(SocialPostModel.fromDocument).toList(growable: false),
      );
      posts.addAll(visiblePosts);
    }

    return SocialFeedPage(
      posts: posts.take(limit).toList(growable: false),
      lastDocument: cursor ?? startAfter,
      hasMore: hasMore,
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
    final snapshot = await FirestoreCacheService.getCollectionCacheFirst(
      _hashtagsCollection.orderBy('lastUsedAt', descending: true).limit(limit),
    );
    return snapshot.docs.map(ExploreHashtagSummary.fromDocument).toList();
  }

  Future<List<ExploreHashtagSummary>> searchHashtags(
    String query, {
    int limit = 10,
  }) async {
    final normalized = normalizeHashtag(query);
    if (normalized.isEmpty) return const <ExploreHashtagSummary>[];

    final firestoreQuery = _hashtagsCollection
        .orderBy('tag')
        .startAt([normalized])
        .endAt(['$normalized\uf8ff'])
        .limit(limit);
    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await firestoreQuery.get(
        const GetOptions(source: Source.server),
      );
    } catch (_) {
      snapshot = await firestoreQuery.get(
        const GetOptions(source: Source.cache),
      );
    }
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
      final snapshot = await FirestoreCacheService.getCollectionCacheFirst(
        _postsCollection.where(FieldPath.documentId, whereIn: chunk),
      );
      for (final doc in snapshot.docs) {
        final post = SocialPostModel.fromDocument(doc);
        if (post.visibilityStatus == 'visible' &&
            post.moderationStatus == 'approved') {
          postsById[post.id] = post;
        }
      }
    }

    final visiblePosts = await _filterPostsByVisibleAuthors(
      normalizedIds
          .map((id) => postsById[id])
          .whereType<SocialPostModel>()
          .toList(growable: false),
    );
    return visiblePosts;
  }

  Future<SocialPostModel?> fetchVisiblePostById(String postId) async {
    final normalizedPostId = postId.trim();
    if (normalizedPostId.isEmpty) return null;
    final posts = await fetchPostsByIds(<String>[normalizedPostId], limit: 1);
    return posts.isEmpty ? null : posts.first;
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
      return _filterPostsByVisibleAuthors(
        snapshot.docs.map(SocialPostModel.fromDocument).toList(growable: false),
      );
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
    final query = _postsCollection
        .where('hashtags', arrayContains: normalized)
        .where('visibilityStatus', isEqualTo: 'visible')
        .where('moderationStatus', isEqualTo: 'approved')
        .orderBy('createdAt', descending: true)
        .limit(math.min(math.max(limit * 3, limit), 60));
    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await query.get(const GetOptions(source: Source.server));
    } catch (_) {
      snapshot = await query.get(const GetOptions(source: Source.cache));
    }
    final visiblePosts = await _filterPostsByVisibleAuthors(
      snapshot.docs.map(SocialPostModel.fromDocument).toList(growable: false),
    );
    return visiblePosts.take(limit).toList(growable: false);
  }

  Future<SocialPostModel> createPost({
    required List<XFile> images,
    required SocialPostAspectRatio aspectRatio,
    required String caption,
    required List<String> hashtags,
    ExploreLocationSnapshot? creationLocation,
    SocialPostUploadProgressCallback? onProgress,
  }) async {
    if (images.isEmpty) {
      throw Exception('Select at least one image.');
    }
    if (images.length > 5) {
      throw Exception('You can upload up to 5 images.');
    }

    final diagnostics = _SocialPostPublishDiagnosticsTracker(
      expectedImageCount: images.length,
      locationIntentRequested: creationLocation?.hasCoordinates == true,
    );
    try {
      onProgress?.call(
        const SocialPostUploadProgress(
          stage: SocialPostUploadStage.preparing,
          fraction: 0.04,
          message: 'Preparing your post...',
        ),
      );
      diagnostics.failedStage = 'authentication';
      final authorId = await _ensureAuthenticatedForStorageWrite();
      diagnostics.failedStage = 'profile-load';
      final profile = await _profileRepository.getCurrentUserProfile();
      final postRef = _postsCollection.doc();
      final normalizedHashtags = hashtag_normalizer.validatePostHashtags(
        hashtags,
      );
      final uploads = await _uploadImages(
        authorId: authorId,
        postId: postRef.id,
        images: images,
        aspectRatio: aspectRatio,
        diagnostics: diagnostics,
        onProgress: onProgress,
      );

      final payload = buildCreatePostPayload(
        postId: postRef.id,
        authorId: authorId,
        profile: profile,
        imageUrls: uploads.fullSizeUrls,
        thumbnailUrls: uploads.thumbnailUrls,
        aspectRatio: aspectRatio,
        caption: caption,
        hashtags: normalizedHashtags,
        createdAtEpoch: DateTime.now().millisecondsSinceEpoch,
      );
      _debugLogCreatePayload(payload);

      onProgress?.call(
        const SocialPostUploadProgress(
          stage: SocialPostUploadStage.finalizing,
          fraction: 0.95,
          message: 'Publishing your post...',
        ),
      );
      diagnostics.failedStage = 'firestore-batch';
      diagnostics.firestoreBatchStatus =
          SocialPostFirestoreBatchStatus.committing;
      final batch = _firestore.batch()..set(postRef, payload);
      if (creationLocation?.hasCoordinates == true) {
        diagnostics.locationIntentStatus =
            SocialPostLocationIntentStatus.queuedInBatch;
        batch.set(
          _postLocationIntentsCollection.doc(postRef.id),
          buildPostLocationIntentPayload(
            authorId: authorId,
            location: creationLocation!,
          ),
        );
      }
      try {
        await batch.commit();
        diagnostics.firestoreBatchStatus =
            SocialPostFirestoreBatchStatus.committed;
        if (diagnostics.locationIntentStatus ==
            SocialPostLocationIntentStatus.queuedInBatch) {
          diagnostics.locationIntentStatus =
              SocialPostLocationIntentStatus.committed;
        }
      } on FirebaseException catch (error, stackTrace) {
        diagnostics.firestoreBatchStatus =
            SocialPostFirestoreBatchStatus.failed;
        if (diagnostics.locationIntentStatus ==
            SocialPostLocationIntentStatus.queuedInBatch) {
          diagnostics.locationIntentStatus =
              SocialPostLocationIntentStatus.failedWithBatch;
        }
        await _cleanupUploadedImages(uploads);
        Error.throwWithStackTrace(
          diagnostics.toException(error, _mapCreatePostError(error)),
          stackTrace,
        );
      }

      try {
        await _updateHashtagDocuments(
          hashtags: normalizedHashtags,
          postId: postRef.id,
        );
      } on FirebaseException catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint(
            'SocialPostRepository hashtag update skipped: '
            'plugin=${error.plugin}, code=${error.code}, '
            'message=${sanitizeSocialPublishDiagnosticMessage(error.message)}',
          );
          debugPrintStack(stackTrace: stackTrace);
        }
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('SocialPostRepository hashtag update skipped.');
          debugPrintStack(stackTrace: stackTrace);
        }
      }

      try {
        final createdSnapshot = await postRef.get();
        return SocialPostModel.fromDocument(createdSnapshot);
      } on FirebaseException catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint(
            'SocialPostRepository readback skipped: plugin=${error.plugin}, '
            'code=${error.code}, '
            'message=${sanitizeSocialPublishDiagnosticMessage(error.message)}',
          );
          debugPrintStack(stackTrace: stackTrace);
        }
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('SocialPostRepository readback skipped.');
          debugPrintStack(stackTrace: stackTrace);
        }
      }

      return SocialPostModel.fromMap({
        ...payload,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      }, fallbackId: postRef.id);
    } on SocialPostPublishException {
      rethrow;
    } on FirebaseException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        diagnostics.toException(error, _mapCreatePostError(error)),
        stackTrace,
      );
    }
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
    return hashtag_normalizer.normalizeHashtag(input);
  }

  Future<bool> hasCurrentUserLikedPost(
    String postId, {
    bool preferServer = false,
  }) async {
    final likeRef = _postsCollection.doc(postId).collection('likes').doc(_uid);
    if (preferServer) {
      try {
        final serverSnapshot = await likeRef.get(
          const GetOptions(source: Source.server),
        );
        return serverSnapshot.exists;
      } catch (_) {
        // Offline detail views can still use the locally cached viewer state.
      }
    }
    final likeSnapshot = await FirestoreCacheService.getDocCacheFirst(likeRef);
    return likeSnapshot.exists;
  }

  Future<Set<String>> fetchCurrentUserLikedPostIds(
    List<String> postIds, {
    bool preferServer = false,
  }) async {
    if (postIds.isEmpty) return <String>{};

    final entries = await Future.wait(
      postIds.map((postId) async {
        final liked = await hasCurrentUserLikedPost(
          postId,
          preferServer: preferServer,
        );
        return MapEntry(postId, liked);
      }),
    );

    return entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toSet();
  }

  Future<SocialPostLikeState> toggleLike({
    required String postId,
    required String currentUserId,
  }) async {
    final postRef = _postsCollection.doc(postId);
    final likeRef = postRef.collection('likes').doc(currentUserId);
    var createdLike = false;
    var recipientId = '';

    final persistedState = await _firestore.runTransaction<SocialPostLikeState>(
      (transaction) async {
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
        if (!await _isUserVisible(recipientId)) {
          throw Exception('This post is no longer available for likes.');
        }

        final likeSnapshot = await transaction.get(likeRef);
        final currentLikeCount = (postData['likeCount'] as num?)?.toInt() ?? 0;

        if (likeSnapshot.exists) {
          transaction.delete(likeRef);
          final nextLikeCount = math.max(0, currentLikeCount - 1);
          await _updatePostLikeCounter(
            transaction: transaction,
            postRef: postRef,
            nextLikeCount: nextLikeCount,
          );
          return SocialPostLikeState(isLiked: false, likeCount: nextLikeCount);
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
        return SocialPostLikeState(
          isLiked: true,
          likeCount: currentLikeCount + 1,
        );
      },
    );

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
    return persistedState;
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
      final authorId = (postData['authorId'] as String? ?? '').trim();
      if (!await _isUserVisible(authorId)) {
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
      final authorId = (postData['authorId'] as String? ?? '').trim();
      if (!await _isUserPubliclyVisibleIgnoringBlock(authorId)) {
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
      final blockedAuthorIds = await _blockedRelationships
          .loadEffectiveBlockedUserIds();
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

        final pageComments = snapshot.docs
            .map(CommentModel.fromDocument)
            .toList(growable: false);
        final missingAuthorIds = pageComments
            .map((comment) => comment.authorId.trim())
            .where((authorId) => authorId.isNotEmpty)
            .where((authorId) => !blockedAuthorIds.contains(authorId))
            .where((authorId) => !_authorVisibilityCache.containsKey(authorId))
            .toSet()
            .toList(growable: false);
        if (missingAuthorIds.isNotEmpty) {
          final fetchedVisibility = await _profileRepository
              .fetchPublicVisibilityByIds(missingAuthorIds);
          _authorVisibilityCache.addAll(fetchedVisibility);
        }

        for (final comment in pageComments) {
          final authorId = comment.authorId.trim();
          if (comment.visibilityStatus == 'visible' &&
              comment.moderationStatus == 'approved' &&
              !blockedAuthorIds.contains(authorId) &&
              (_authorVisibilityCache[authorId] ?? false)) {
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
    if (!profile.isPubliclyVisible) {
      throw Exception('Your account is not available for commenting.');
    }
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
      if (!await _isUserVisible(postAuthorId)) {
        throw Exception('This post is no longer available for comments.');
      }

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

  static String _buildCategoryLabel(UserProfile profile) {
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
      final refs = normalizedTags
          .map(_hashtagsCollection.doc)
          .toList(growable: false);
      final snapshots = await Future.wait(refs.map(transaction.get));
      for (var index = 0; index < normalizedTags.length; index += 1) {
        final tag = normalizedTags[index];
        final ref = refs[index];
        final snapshot = snapshots[index];
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
    return hashtag_normalizer.isValidCanonicalHashtag(tag);
  }

  @visibleForTesting
  static Map<String, dynamic> buildCreatePostPayload({
    required String postId,
    required String authorId,
    required UserProfile profile,
    required List<String> imageUrls,
    required List<String> thumbnailUrls,
    required SocialPostAspectRatio aspectRatio,
    required String caption,
    required List<String> hashtags,
    required int createdAtEpoch,
  }) {
    return <String, dynamic>{
      'id': postId,
      'authorId': authorId,
      'authorType': 'user',
      'authorDisplayName': profile.name,
      'authorUsername': profile.displayUsername,
      'authorPhotoUrl': profile.profileImageUrl,
      'authorCategoryLabel': _buildCategoryLabel(profile),
      'authorCity': profile.city,
      'authorState': profile.state,
      'imageUrls': imageUrls,
      'thumbnailUrls': thumbnailUrls,
      'imageAspectRatio': aspectRatio.value,
      'caption': caption.trim(),
      'hashtags': hashtags,
      'likeCount': 0,
      'commentCount': 0,
      'shareCount': 0,
      'reportCount': 0,
      'visibilityStatus': 'visible',
      'moderationStatus': 'approved',
      'createdAtEpoch': createdAtEpoch,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  @visibleForTesting
  static Map<String, dynamic> buildPostLocationIntentPayload({
    required String authorId,
    required ExploreLocationSnapshot location,
  }) {
    if (!location.hasCoordinates) return const <String, dynamic>{};
    return <String, dynamic>{
      'ownerUid': authorId,
      'source': 'freshDeviceAtPublish',
      'location': <String, dynamic>{
        'latitude': location.latitude,
        'longitude': location.longitude,
        'city': location.city,
        'state': location.state,
        'country': location.country,
      },
      'capturedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Future<_SocialUploadResult> _uploadImages({
    required String authorId,
    required String postId,
    required List<XFile> images,
    required SocialPostAspectRatio aspectRatio,
    required _SocialPostPublishDiagnosticsTracker diagnostics,
    SocialPostUploadProgressCallback? onProgress,
  }) async {
    final fullSizeUrls = <String>[];
    final thumbnailUrls = <String>[];
    final fullSizeRefs = <Reference>[];
    final thumbnailRefs = <Reference>[];
    final totalUploads = images.length * 2;
    var completedUploads = 0;
    UploadTask? activeUploadTask;

    try {
      for (var index = 0; index < images.length; index++) {
        onProgress?.call(
          SocialPostUploadProgress(
            stage: SocialPostUploadStage.uploading,
            fraction: totalUploads == 0
                ? 0.10
                : 0.10 + ((completedUploads / totalUploads) * 0.76),
            message: 'Uploading image ${index + 1} of ${images.length}...',
          ),
        );
        diagnostics
          ..failedStage = 'image-file-inspection'
          ..imageIndex = index + 1
          ..resetImageAttempt();
        if (kDebugMode) {
          try {
            diagnostics.originalFileExists = await File(
              images[index].path,
            ).exists();
          } catch (_) {
            diagnostics.originalFileExists = false;
          }
        }
        final originalSize = await images[index].length();
        diagnostics.originalByteSize = originalSize;

        diagnostics.failedStage = 'image-read';
        final bytes = await images[index].readAsBytes();
        diagnostics.originalFileReadable = true;
        diagnostics.failedStage = 'image-processing';
        final processed = await _processImage(bytes, aspectRatio: aspectRatio);
        diagnostics
          ..processedByteSize = processed.feedBytes.length
          ..thumbnailByteSize = processed.thumbnailBytes.length
          ..processedFormat = 'jpeg'
          ..thumbnailCreated = processed.thumbnailBytes.isNotEmpty;
        validateProcessedUploadSizes(
          feedByteLength: processed.feedBytes.length,
          thumbnailByteLength: processed.thumbnailBytes.length,
        );

        final imageRef = _storage.ref().child(
          'socialPosts/$authorId/$postId/images/$index.jpg',
        );
        final thumbRef = _storage.ref().child(
          'socialPosts/$authorId/$postId/thumbs/$index.jpg',
        );

        diagnostics
          ..failedStage = 'original-image-upload'
          ..sanitizedStoragePath =
              'socialPosts/{uid}/{postId}/images/{index}.jpg'
          ..uploadStarted = true
          ..storageTaskState = 'running';
        activeUploadTask = imageRef.putData(
          processed.feedBytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        final imageSnapshot = await activeUploadTask;
        diagnostics.captureTaskSnapshot(imageSnapshot);
        activeUploadTask = null;
        fullSizeRefs.add(imageRef);
        diagnostics.originalUploadsCompleted += 1;
        completedUploads += 1;
        onProgress?.call(
          SocialPostUploadProgress(
            stage: SocialPostUploadStage.uploading,
            fraction: 0.10 + ((completedUploads / totalUploads) * 0.76),
            message: 'Uploading image ${index + 1} of ${images.length}...',
          ),
        );
        diagnostics
          ..failedStage = 'thumbnail-upload'
          ..sanitizedStoragePath =
              'socialPosts/{uid}/{postId}/thumbs/{index}.jpg'
          ..storageTaskState = 'running';
        activeUploadTask = thumbRef.putData(
          processed.thumbnailBytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        final thumbnailSnapshot = await activeUploadTask;
        diagnostics.captureTaskSnapshot(thumbnailSnapshot);
        activeUploadTask = null;
        thumbnailRefs.add(thumbRef);
        diagnostics.thumbnailUploadsCompleted += 1;
        completedUploads += 1;
        onProgress?.call(
          SocialPostUploadProgress(
            stage: SocialPostUploadStage.uploading,
            fraction: 0.10 + ((completedUploads / totalUploads) * 0.76),
            message: 'Uploading image ${index + 1} of ${images.length}...',
          ),
        );

        diagnostics
          ..failedStage = 'download-url-resolution'
          ..sanitizedStoragePath =
              'socialPosts/{uid}/{postId}/{images|thumbs}/{index}.jpg';
        fullSizeUrls.add(await imageRef.getDownloadURL());
        thumbnailUrls.add(await thumbRef.getDownloadURL());
      }
    } catch (error, stackTrace) {
      if (activeUploadTask != null) {
        diagnostics.captureTaskSnapshot(activeUploadTask.snapshot);
      }
      await diagnostics.captureFailureEnvironment();
      final userMessage = error is FirebaseException
          ? _mapStorageUploadError(error)
          : _localPublishErrorMessage(error);
      Error.throwWithStackTrace(
        diagnostics.toException(error, userMessage),
        stackTrace,
      );
    }

    return _SocialUploadResult(
      fullSizeUrls: fullSizeUrls,
      thumbnailUrls: thumbnailUrls,
      fullSizeRefs: fullSizeRefs,
      thumbnailRefs: thumbnailRefs,
    );
  }

  @visibleForTesting
  static void validateProcessedUploadSizes({
    required int feedByteLength,
    required int thumbnailByteLength,
  }) {
    const maxImageUploadBytes = 10 * 1024 * 1024;
    const maxThumbnailUploadBytes = 5 * 1024 * 1024;
    if (feedByteLength > maxImageUploadBytes ||
        thumbnailByteLength > maxThumbnailUploadBytes) {
      throw Exception('The processed post image is too large to upload.');
    }
  }

  String _localPublishErrorMessage(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    return message.isEmpty
        ? 'Unable to upload post images right now. Please try again.'
        : message;
  }

  Future<void> _cleanupUploadedImages(_SocialUploadResult uploads) async {
    final refs = <Reference>[...uploads.fullSizeRefs, ...uploads.thumbnailRefs];
    for (final ref in refs) {
      try {
        await ref.delete();
      } on FirebaseException catch (error) {
        if (kDebugMode) {
          debugPrint(
            'SocialPostRepository cleanup failed: plugin=${error.plugin}, '
            'code=${error.code}, path=${_sanitizeStoragePath(ref.fullPath)}, '
            'message=${sanitizeSocialPublishDiagnosticMessage(error.message)}',
          );
        }
      } catch (error) {
        if (kDebugMode) {
          debugPrint(
            'SocialPostRepository cleanup failed: '
            'path=${_sanitizeStoragePath(ref.fullPath)}',
          );
        }
      }
    }
  }

  void _debugLogCreatePayload(Map<String, dynamic> payload) {
    if (!kDebugMode) return;
    final keys = payload.keys.toList(growable: false)..sort();
    final backendFieldsPresent = keys
        .where(_backendOwnedCreateFields.contains)
        .toList(growable: false);
    debugPrint(
      'SocialPostRepository create debug -> fields=$keys, backendOwnedFieldsPresent=$backendFieldsPresent',
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

  String _mapCreatePostError(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'You do not have permission to publish a post right now. Please sign in again and try once more.';
      case 'unauthenticated':
        return 'Please sign in again before publishing a post.';
      case 'unavailable':
        return 'Post publishing is temporarily unavailable. Please try again in a moment.';
      case 'aborted':
      case 'deadline-exceeded':
        return 'Post publishing took too long. Please check your connection and try again.';
      default:
        final message = error.message?.trim() ?? '';
        if (message.isNotEmpty) {
          return message;
        }
        return 'Unable to publish your post right now. Please try again.';
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
    final targetRatio = switch (aspectRatio) {
      SocialPostAspectRatio.square => 1.0,
      SocialPostAspectRatio.portrait => 4 / 5,
      SocialPostAspectRatio.landscape => 1.91 / 1,
    };
    final encoded = await compute(_prepareSocialPostImageJpegs, (
      bytes: originalBytes,
      targetRatio: targetRatio,
    ));
    if (encoded == null) {
      throw Exception('One of the selected images could not be processed.');
    }

    final feedBytes = await FlutterImageCompress.compressWithList(
      encoded.feed,
      quality: 78,
      format: CompressFormat.jpeg,
    );
    final thumbBytes = await FlutterImageCompress.compressWithList(
      encoded.thumbnail,
      quality: 70,
      format: CompressFormat.jpeg,
    );

    return _ProcessedImageBytes(
      feedBytes: Uint8List.fromList(feedBytes),
      thumbnailBytes: Uint8List.fromList(thumbBytes),
    );
  }

  Future<List<SocialPostModel>> _filterPostsByVisibleAuthors(
    List<SocialPostModel> posts,
  ) async {
    if (posts.isEmpty) return const <SocialPostModel>[];
    final blockedAuthorIds = await _blockedRelationships
        .loadEffectiveBlockedUserIds();

    final missingAuthorIds = posts
        .map((post) => post.authorId.trim())
        .where((authorId) => authorId.isNotEmpty)
        .where((authorId) => !_authorVisibilityCache.containsKey(authorId))
        .toSet()
        .toList(growable: false);

    if (missingAuthorIds.isNotEmpty) {
      final fetchedVisibility = await _profileRepository
          .fetchPublicVisibilityByIds(missingAuthorIds);
      _authorVisibilityCache.addAll(fetchedVisibility);
    }

    return posts
        .where((post) {
          final authorId = post.authorId.trim();
          if (authorId.isEmpty) return false;
          if (blockedAuthorIds.contains(authorId)) return false;
          return _authorVisibilityCache[authorId] ?? false;
        })
        .toList(growable: false);
  }

  Future<bool> _isUserVisible(String userId) async {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) return false;
    if (await _blockedRelationships.isEffectivelyBlocked(trimmedUserId)) {
      return false;
    }

    return _isUserPubliclyVisibleIgnoringBlock(trimmedUserId);
  }

  Future<bool> _isUserPubliclyVisibleIgnoringBlock(String userId) async {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) return false;

    final cached = _authorVisibilityCache[trimmedUserId];
    if (cached != null) {
      return cached;
    }

    final fetchedVisibility = await _profileRepository
        .fetchPublicVisibilityByIds([trimmedUserId]);
    final resolved = fetchedVisibility[trimmedUserId] ?? false;
    _authorVisibilityCache[trimmedUserId] = resolved;
    return resolved;
  }
}

@visibleForTesting
String sanitizeSocialPublishDiagnosticMessage(String? message) {
  var sanitized = (message ?? '').replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  sanitized = sanitized
      .replaceAll(
        RegExp(r'https?://\S+', caseSensitive: false),
        '<redacted-url>',
      )
      .replaceAll(
        RegExp(r'gs://\S+', caseSensitive: false),
        '<redacted-storage-url>',
      )
      .replaceAll(
        RegExp(r'(?:file|content)://\S+', caseSensitive: false),
        '<redacted-local-path>',
      )
      .replaceAll(
        RegExp(
          r'/(?:data|storage|sdcard|mnt|private|Users)(?:/[^\s,:]+)+',
          caseSensitive: false,
        ),
        '<redacted-local-path>',
      )
      .replaceAll(
        RegExp(
          r'socialPosts/[^/\s]+/[^/\s]+/(images|thumbs)/[^\s]+',
          caseSensitive: false,
        ),
        'socialPosts/{uid}/{postId}/{asset}/{file}',
      )
      .replaceAll(RegExp(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}'), '<redacted-email>')
      .replaceAll(RegExp(r'\+?\d[\d\s().-]{7,}\d'), '<redacted-phone>')
      .replaceAll(RegExp(r'\b[A-Za-z0-9_-]{24,}\b'), '<redacted-identifier>');
  if (sanitized.isEmpty) return '<no-message>';
  return sanitized.length <= 240
      ? sanitized
      : '${sanitized.substring(0, 240)}…';
}

String _sanitizeStoragePath(String path) {
  if (path.startsWith('socialPosts/')) {
    final segments = path.split('/');
    if (segments.length >= 5) {
      return 'socialPosts/{uid}/{postId}/${segments[3]}/{file}';
    }
  }
  return '<redacted-storage-path>';
}

({Uint8List feed, Uint8List thumbnail})? _prepareSocialPostImageJpegs(
  ({Uint8List bytes, double targetRatio}) request,
) {
  final decoded = img.decodeImage(request.bytes);
  if (decoded == null) return null;
  final sourceRatio = decoded.width / decoded.height;
  img.Image cropped;
  if ((sourceRatio - request.targetRatio).abs() < 0.01) {
    cropped = decoded;
  } else if (sourceRatio > request.targetRatio) {
    final targetWidth = math.max(
      1,
      (decoded.height * request.targetRatio).round(),
    );
    final offsetX = ((decoded.width - targetWidth) / 2).round();
    cropped = img.copyCrop(
      decoded,
      x: offsetX.clamp(0, math.max(0, decoded.width - targetWidth)),
      y: 0,
      width: targetWidth,
      height: decoded.height,
    );
  } else {
    final targetHeight = math.max(
      1,
      (decoded.width / request.targetRatio).round(),
    );
    final offsetY = ((decoded.height - targetHeight) / 2).round();
    cropped = img.copyCrop(
      decoded,
      x: 0,
      y: offsetY.clamp(0, math.max(0, decoded.height - targetHeight)),
      width: decoded.width,
      height: targetHeight,
    );
  }

  final feed = img.copyResize(cropped, width: math.min(cropped.width, 1080));
  final thumbnail = img.copyResize(
    cropped,
    width: math.min(cropped.width, 300),
  );
  return (
    feed: Uint8List.fromList(img.encodeJpg(feed, quality: 88)),
    thumbnail: Uint8List.fromList(img.encodeJpg(thumbnail, quality: 80)),
  );
}

class _SocialPostPublishDiagnosticsTracker {
  _SocialPostPublishDiagnosticsTracker({
    required this.expectedImageCount,
    required bool locationIntentRequested,
  }) : locationIntentStatus = locationIntentRequested
           ? SocialPostLocationIntentStatus.pending
           : SocialPostLocationIntentStatus.notRequested,
       _stopwatch = Stopwatch()..start();

  String failedStage = 'preparing';
  String sanitizedStoragePath = 'not-started';
  int originalUploadsCompleted = 0;
  int thumbnailUploadsCompleted = 0;
  int? imageIndex;
  bool? originalFileExists;
  bool? originalFileReadable;
  int? originalByteSize;
  int? processedByteSize;
  int? thumbnailByteSize;
  String processedFormat = 'not-created';
  bool thumbnailCreated = false;
  String storageTaskState = 'not-started';
  bool uploadStarted = false;
  int? bytesTransferred;
  String networkClassification = 'not-checked';
  final int expectedImageCount;
  final Stopwatch _stopwatch;
  SocialPostFirestoreBatchStatus firestoreBatchStatus =
      SocialPostFirestoreBatchStatus.notStarted;
  SocialPostLocationIntentStatus locationIntentStatus;

  void resetImageAttempt() {
    originalFileExists = null;
    originalFileReadable = null;
    originalByteSize = null;
    processedByteSize = null;
    thumbnailByteSize = null;
    processedFormat = 'not-created';
    thumbnailCreated = false;
    storageTaskState = 'not-started';
    uploadStarted = false;
    bytesTransferred = null;
  }

  void captureTaskSnapshot(TaskSnapshot snapshot) {
    storageTaskState = snapshot.state.name;
    bytesTransferred = snapshot.bytesTransferred;
  }

  Future<void> captureFailureEnvironment() async {
    if (!kDebugMode) return;
    try {
      final results = await Connectivity().checkConnectivity();
      final names = results.map((result) => result.name).toSet().toList()
        ..sort();
      networkClassification = names.isEmpty ? 'unknown' : names.join('+');
    } catch (_) {
      networkClassification = 'unavailable';
    }
  }

  SocialPostPublishException toException(Object error, String userMessage) {
    final firebaseError = error is FirebaseException ? error : null;
    return SocialPostPublishException(
      userMessage: userMessage,
      originalException: error,
      diagnostics: SocialPostPublishDiagnostics(
        failedStage: failedStage,
        firebasePlugin: firebaseError?.plugin ?? 'not-firebase',
        firebaseCode: firebaseError?.code ?? 'local-error',
        sanitizedMessage: sanitizeSocialPublishDiagnosticMessage(
          firebaseError?.message ?? error.toString(),
        ),
        sanitizedStoragePath: sanitizedStoragePath,
        originalUploadsCompleted: originalUploadsCompleted,
        thumbnailUploadsCompleted: thumbnailUploadsCompleted,
        expectedImageCount: expectedImageCount,
        firestoreBatchStatus: firestoreBatchStatus,
        locationIntentStatus: locationIntentStatus,
        imageIndex: imageIndex,
        originalFileExists: originalFileExists,
        originalFileReadable: originalFileReadable,
        originalByteSize: originalByteSize,
        processedByteSize: processedByteSize,
        thumbnailByteSize: thumbnailByteSize,
        processedFormat: processedFormat,
        thumbnailCreated: thumbnailCreated,
        storageTaskState: storageTaskState,
        uploadStarted: uploadStarted,
        bytesTransferred: bytesTransferred,
        networkClassification: networkClassification,
        failureDurationMs: _stopwatch.elapsedMilliseconds,
        originalErrorType: error.runtimeType.toString(),
      ),
    );
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
  final List<Reference> fullSizeRefs;
  final List<Reference> thumbnailRefs;

  const _SocialUploadResult({
    required this.fullSizeUrls,
    required this.thumbnailUrls,
    required this.fullSizeRefs,
    required this.thumbnailRefs,
  });
}
