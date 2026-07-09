import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../social/domain/models/social_post_model.dart';
import '../../domain/models/user_profile.dart';
import 'profile_repository.dart';

class ProfileContentRepository {
  ProfileContentRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final ProfileRepository _profileRepository = ProfileRepository();

  Stream<List<SocialPostModel>> watchPostsForProfile(UserProfile profile) {
    return watchPostsForAuthorId(profile.uid);
  }

  Stream<List<SocialPostModel>> watchPostsForAuthorId(String authorId) {
    final trimmedAuthorId = authorId.trim();
    if (trimmedAuthorId.isEmpty) {
      return Stream<List<SocialPostModel>>.value(const <SocialPostModel>[]);
    }

    return _firestore
        .collection('socialPosts')
        .where('authorId', isEqualTo: trimmedAuthorId)
        .where('visibilityStatus', isEqualTo: 'visible')
        .where('moderationStatus', isEqualTo: 'approved')
        .snapshots()
        .asyncMap((snapshot) async {
          final isAuthorVisible = await _profileRepository
              .isUserPubliclyVisible(trimmedAuthorId);
          if (!isAuthorVisible) {
            return const <SocialPostModel>[];
          }

          final orderedDocs = snapshot.docs.toList(growable: false)
            ..sort((a, b) {
              final aEpoch = (a.data()['createdAtEpoch'] as num?)?.toInt() ?? 0;
              final bEpoch = (b.data()['createdAtEpoch'] as num?)?.toInt() ?? 0;
              return bEpoch.compareTo(aEpoch);
            });

          return orderedDocs
              .map((doc) => SocialPostModel.fromDocument(doc))
              .toList(growable: false);
        });
  }
}
