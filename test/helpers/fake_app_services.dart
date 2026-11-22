// Fakes for repository unit tests that must not touch Firebase platform code.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:pettexo/features/notifications/data/repositories/notification_repository.dart';
import 'package:pettexo/features/profile/data/repositories/profile_repository.dart';
import 'package:pettexo/features/profile/domain/models/user_profile.dart';

class FakeUser implements User {
  FakeUser(this.uid);

  @override
  final String uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuth implements FirebaseAuth {
  FakeAuth(String? uid) : _user = uid == null ? null : FakeUser(uid);

  User? _user;

  void signInAs(String? uid) => _user = uid == null ? null : FakeUser(uid);

  @override
  User? get currentUser => _user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeStorage implements FirebaseStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

UserProfile visibleProfile(String uid) => UserProfile.fromMap(<String, dynamic>{
  'uid': uid,
  'displayName': uid,
  'name': uid,
  'username': uid,
  'isActive': true,
  'accountStatus': 'active',
});

/// ProfileRepository stand-in: every user is publicly visible unless listed
/// in [hiddenUserIds]. Records fetchPublicVisibilityByIds calls.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository(this.currentUid);

  final String currentUid;
  final Set<String> hiddenUserIds = <String>{};
  final List<List<String>> visibilityRequests = <List<String>>[];

  @override
  Future<UserProfile> getCurrentUserProfile() async =>
      visibleProfile(currentUid);

  @override
  Future<Map<String, bool>> fetchPublicVisibilityByIds(
    List<String> userIds,
  ) async {
    visibilityRequests.add(List<String>.of(userIds));
    return <String, bool>{
      for (final id in userIds) id: !hiddenUserIds.contains(id),
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeNotificationRepository implements NotificationRepository {
  final List<String> created = <String>[];

  @override
  Future<void> createLikeNotification({
    required String recipientId,
    required String postId,
  }) async {
    created.add('like:$recipientId:$postId');
  }

  @override
  Future<void> createCommentNotification({
    required String recipientId,
    required String postId,
    required String commentId,
  }) async {
    created.add('comment:$recipientId:$postId');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
