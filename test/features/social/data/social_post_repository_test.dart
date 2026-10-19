import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/profile/domain/models/user_profile.dart';
import 'package:pettexo/features/restrictions/domain/models/user_restriction_state.dart';
import 'package:pettexo/features/social/data/social_post_repository.dart';
import 'package:pettexo/features/social/domain/models/social_post_model.dart';
import 'package:pettexo/features/explore/domain/models/explore_location_snapshot.dart';

void main() {
  group('SocialPostPublishException diagnostics', () {
    test(
      'retains the original Firebase exception and sanitized stage data',
      () {
        final firebaseError = FirebaseException(
          plugin: 'firebase_storage',
          code: 'unauthorized',
          message:
              'Denied socialPosts/privateUid/privatePost/images/0.jpg for '
              '+919876543210 at https://example.test/private-download-token',
        );
        const diagnostics = SocialPostPublishDiagnostics(
          failedStage: 'original-image-upload',
          firebasePlugin: 'firebase_storage',
          firebaseCode: 'unauthorized',
          sanitizedMessage: 'sanitized',
          sanitizedStoragePath: 'socialPosts/{uid}/{postId}/images/{index}.jpg',
          originalUploadsCompleted: 0,
          thumbnailUploadsCompleted: 0,
          expectedImageCount: 1,
          firestoreBatchStatus: SocialPostFirestoreBatchStatus.notStarted,
          locationIntentStatus: SocialPostLocationIntentStatus.pending,
          imageIndex: 1,
          originalFileExists: true,
          originalFileReadable: true,
          originalByteSize: 6 * 1024 * 1024,
          processedByteSize: 1024,
          thumbnailByteSize: 256,
          processedFormat: 'jpeg',
          thumbnailCreated: true,
          storageTaskState: 'running',
          uploadStarted: true,
          bytesTransferred: 128,
          networkClassification: 'wifi',
          failureDurationMs: 50,
          originalErrorType: 'FirebaseException',
        );
        final exception = SocialPostPublishException(
          userMessage: 'Please try again.',
          originalException: firebaseError,
          diagnostics: diagnostics,
        );

        expect(exception.firebaseException, same(firebaseError));
        expect(exception.firebaseException?.code, 'unauthorized');
        expect(exception.diagnostics.failedStage, 'original-image-upload');
        expect(exception.toString(), 'Exception: Please try again.');
      },
    );

    test('sanitizes private values from Firebase diagnostic messages', () {
      final sanitized = sanitizeSocialPublishDiagnosticMessage(
        'Denied socialPosts/privateUid/privatePost/thumbs/0.jpg for '
        'owner@example.test, +919876543210, '
        'https://example.test/download?token=secret',
      );

      expect(sanitized, contains('socialPosts/{uid}/{postId}/{asset}/{file}'));
      expect(sanitized, contains('<redacted-email>'));
      expect(sanitized, contains('<redacted-phone>'));
      expect(sanitized, contains('<redacted-url>'));
      expect(sanitized, isNot(contains('privateUid')));
      expect(sanitized, isNot(contains('9876543210')));
      expect(sanitized, isNot(contains('secret')));
    });

    test('retains a non-Firebase source exception', () {
      final sourceError = Exception('local image failure');
      const diagnostics = SocialPostPublishDiagnostics(
        failedStage: 'image-read',
        firebasePlugin: 'not-firebase',
        firebaseCode: 'local-error',
        sanitizedMessage: 'Exception: local image failure',
        sanitizedStoragePath: 'not-started',
        originalUploadsCompleted: 0,
        thumbnailUploadsCompleted: 0,
        expectedImageCount: 1,
        firestoreBatchStatus: SocialPostFirestoreBatchStatus.notStarted,
        locationIntentStatus: SocialPostLocationIntentStatus.notRequested,
        imageIndex: 1,
        originalFileExists: false,
        originalFileReadable: false,
        originalByteSize: null,
        processedByteSize: null,
        thumbnailByteSize: null,
        processedFormat: 'not-created',
        thumbnailCreated: false,
        storageTaskState: 'not-started',
        uploadStarted: false,
        bytesTransferred: null,
        networkClassification: 'none',
        failureDurationMs: 10,
        originalErrorType: '_Exception',
      );

      final exception = SocialPostPublishException(
        userMessage: 'local image failure',
        originalException: sourceError,
        diagnostics: diagnostics,
      );

      expect(exception.originalException, same(sourceError));
      expect(exception.firebaseException, isNull);
      expect(exception.diagnostics.uploadStarted, isFalse);
    });

    test('redacts Android local paths from diagnostic messages', () {
      final sanitized = sanitizeSocialPublishDiagnosticMessage(
        'Cannot open /data/user/0/com.pettexo/cache/private/photo.jpg or '
        'content://media/external/images/42',
      );

      expect(sanitized, isNot(contains('/data/user')));
      expect(sanitized, isNot(contains('content://')));
      expect(sanitized, contains('<redacted-local-path>'));
    });
  });

  group('SocialPostRepository processed upload size validation', () {
    test('accepts processed upload bytes at exactly 10 MiB', () {
      expect(
        () => SocialPostRepository.validateProcessedUploadSizes(
          feedByteLength: 10 * 1024 * 1024,
          thumbnailByteLength: 128 * 1024,
        ),
        returnsNormally,
      );
    });

    test('rejects a processed upload over 10 MiB', () {
      expect(
        () => SocialPostRepository.validateProcessedUploadSizes(
          feedByteLength: (10 * 1024 * 1024) + 1,
          thumbnailByteLength: 128 * 1024,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('retains the 5 MiB processed thumbnail limit', () {
      expect(
        () => SocialPostRepository.validateProcessedUploadSizes(
          feedByteLength: 7 * 1024 * 1024,
          thumbnailByteLength: (5 * 1024 * 1024) + 1,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('SocialPostRepository.buildCreatePostPayload', () {
    test('contains only permitted client-owned create fields', () {
      final payload = SocialPostRepository.buildCreatePostPayload(
        postId: 'post-1',
        authorId: 'author-1',
        profile: _profile(),
        imageUrls: const ['https://example.com/image.jpg'],
        thumbnailUrls: const ['https://example.com/thumb.jpg'],
        aspectRatio: SocialPostAspectRatio.portrait,
        caption: ' Hello world ',
        hashtags: const ['pets', 'dogs'],
        createdAtEpoch: 1234567890,
      );

      expect(payload.keys.toSet(), {
        'id',
        'authorId',
        'authorType',
        'authorDisplayName',
        'authorUsername',
        'authorPhotoUrl',
        'authorCategoryLabel',
        'authorCity',
        'authorState',
        'imageUrls',
        'thumbnailUrls',
        'imageAspectRatio',
        'caption',
        'hashtags',
        'likeCount',
        'commentCount',
        'shareCount',
        'reportCount',
        'visibilityStatus',
        'moderationStatus',
        'createdAtEpoch',
        'createdAt',
        'updatedAt',
      });
      expect(payload['authorId'], 'author-1');
      expect(payload['caption'], 'Hello world');
      expect(payload['likeCount'], 0);
      expect(payload['commentCount'], 0);
      expect(payload['shareCount'], 0);
      expect(payload['reportCount'], 0);
      expect(payload['visibilityStatus'], 'visible');
      expect(payload['moderationStatus'], 'approved');
      expect(payload['createdAtEpoch'], 1234567890);
      expect(payload['createdAt'], isA<FieldValue>());
      expect(payload['updatedAt'], isA<FieldValue>());
    });

    test('omits backend-owned discover and nearby metadata fields', () {
      final payload = SocialPostRepository.buildCreatePostPayload(
        postId: 'post-2',
        authorId: 'author-2',
        profile: _profile(),
        imageUrls: const ['https://example.com/image.jpg'],
        thumbnailUrls: const ['https://example.com/thumb.jpg'],
        aspectRatio: SocialPostAspectRatio.square,
        caption: '',
        hashtags: const [],
        createdAtEpoch: 987654321,
      );

      expect(payload.containsKey('discoverScore'), isFalse);
      expect(payload.containsKey('homeScore'), isFalse);
      expect(payload.containsKey('homeRankVersion'), isFalse);
      expect(payload.containsKey('homeScoreUpdatedAt'), isFalse);
      expect(payload.containsKey('homeEligible'), isFalse);
      expect(payload.containsKey('discoverRankVersion'), isFalse);
      expect(payload.containsKey('discoverScoreUpdatedAt'), isFalse);
      expect(payload.containsKey('discoverEligible'), isFalse);
      expect(payload.containsKey('nearbyEligible'), isFalse);
      expect(payload.containsKey('feedGeohash3'), isFalse);
      expect(payload.containsKey('feedGeohash4'), isFalse);
      expect(payload.containsKey('feedGeohash5'), isFalse);
      expect(payload.containsKey('feedCityKey'), isFalse);
      expect(payload.containsKey('feedStateKey'), isFalse);
      expect(payload.containsKey('feedLocationVersion'), isFalse);
      expect(payload.containsKey('feedLocationUpdatedAt'), isFalse);
      expect(payload.containsKey('feedLatitudeBucket'), isFalse);
      expect(payload.containsKey('feedLongitudeBucket'), isFalse);
      expect(payload.containsKey('isAdminPost'), isFalse);
      expect(payload.containsKey('adminPriorityBoost'), isFalse);
      expect(payload.containsKey('recentEngagementScore'), isFalse);
      expect(payload.containsKey('saveCount'), isFalse);
      expect(payload.containsKey('moderationReason'), isFalse);
      expect(payload.containsKey('moderatedBy'), isFalse);
      expect(payload.containsKey('moderatedAt'), isFalse);
      expect(payload.containsKey('lastReportedAt'), isFalse);
    });
  });

  group('SocialPostRepository.buildPostLocationIntentPayload', () {
    test('uses the fresh publish location as immutable private intent', () {
      const freshLocationB = ExploreLocationSnapshot(
        latitude: 18.5204,
        longitude: 73.8567,
        city: 'Pune',
        state: 'Maharashtra',
        country: 'India',
        geohash3: 'tek',
        geohash4: 'tek1',
        geohash5: 'tek1x',
        updatedAt: null,
      );

      final payload = SocialPostRepository.buildPostLocationIntentPayload(
        authorId: 'author-1',
        location: freshLocationB,
      );
      final location = payload['location'] as Map<String, dynamic>;

      expect(payload['ownerUid'], 'author-1');
      expect(payload['source'], 'freshDeviceAtPublish');
      expect(location['latitude'], 18.5204);
      expect(location['longitude'], 73.8567);
      expect(location['city'], 'Pune');
      expect(payload['capturedAt'], isA<FieldValue>());
      expect(payload['createdAt'], isA<FieldValue>());
      expect(payload.toString(), isNot(contains('Balaghat')));
    });

    test('does not create an intent from an unavailable fresh reading', () {
      final payload = SocialPostRepository.buildPostLocationIntentPayload(
        authorId: 'author-1',
        location: ExploreLocationSnapshot.empty,
      );

      expect(payload, isEmpty);
    });
  });
}

UserProfile _profile() {
  return const UserProfile(
    uid: 'author-1',
    displayName: 'Nishant Gautam',
    photoUrl: 'https://example.com/avatar.jpg',
    email: 'nishant@example.com',
    emailVerified: true,
    role: 'petParent',
    name: 'Nishant Gautam',
    username: 'nishant',
    usernameLowercase: 'nishant',
    phoneNumber: '+911234567890',
    phoneVerified: true,
    providers: ['phone'],
    phone: '+911234567890',
    country: 'India',
    state: 'Karnataka',
    city: 'Bengaluru',
    address: '',
    legacyLocation: '',
    bio: '',
    profileImageUrl: 'https://example.com/avatar.jpg',
    ratingAverage: 0,
    ratingCount: 0,
    followingCount: 0,
    followerCount: 0,
    hasFollowCounts: true,
    accountStatus: 'active',
    isDeleted: false,
    isActive: true,
    deletionRequested: false,
    profileVisibility: 'public',
    restrictionState: UserRestrictionState.unrestricted,
    createdAt: null,
    updatedAt: null,
    acceptedTermsAt: null,
    acceptedPrivacyAt: null,
    acceptedProviderAgreementAt: null,
  );
}
