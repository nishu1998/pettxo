import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/profile/domain/models/user_profile.dart';
import 'package:pettexo/features/restrictions/domain/models/user_restriction_state.dart';
import 'package:pettexo/features/social/data/social_post_repository.dart';
import 'package:pettexo/features/social/domain/models/social_post_model.dart';

void main() {
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
