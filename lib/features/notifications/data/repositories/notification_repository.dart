import 'package:cloud_functions/cloud_functions.dart';

class NotificationRepository {
  NotificationRepository({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');

  final FirebaseFunctions _functions;

  Future<void> createFollowNotification({
    required String recipientId,
  }) async {
    await _createSocialNotification(
      type: 'socialFollow',
      recipientId: recipientId,
    );
  }

  Future<void> createLikeNotification({
    required String recipientId,
    required String postId,
  }) async {
    await _createSocialNotification(
      type: 'socialLike',
      recipientId: recipientId,
      postId: postId,
    );
  }

  Future<void> createCommentNotification({
    required String recipientId,
    required String postId,
    required String commentId,
  }) async {
    await _createSocialNotification(
      type: 'socialComment',
      recipientId: recipientId,
      postId: postId,
      commentId: commentId,
    );
  }

  Future<void> _createSocialNotification({
    required String type,
    required String recipientId,
    String? postId,
    String? commentId,
  }) async {
    final callable = _functions.httpsCallable('createSocialNotification');
    await callable.call(<String, dynamic>{
      'type': type,
      'recipientId': recipientId.trim(),
      if (postId != null) 'postId': postId.trim(),
      if (commentId != null) 'commentId': commentId.trim(),
    });
  }
}
